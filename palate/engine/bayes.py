"""The Palate Bayesian recommendation engine.

Maintains a posterior distribution P(recipe | user responses) over the whole
recipe database and chooses the next question to ask as the one that maximizes
expected information gain (i.e. minimizes expected posterior entropy) over the
entire remaining question bank.

  P(recipe)          -- uniform prior
  P(a | recipe)      -- likelihood of answering `a` given the recipe's traits
  P(recipe | a)      -- Bayes update after each answer
  Question selection -- argmax_q  H(P) - E_a[ H(P | a) ]
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Optional

from ..data.questions import load_questions
from ..data.recipes import load_recipes
from ..engine.traits import clamp01, score_trait
from ..types import Answer, AnswerRecord, Question, Recipe


@dataclass
class EngineConfig:
    """Knobs that control how "enthusiastic" the engine is.

    Enthusiastic  -- each answer is treated as highly informative (P(yes | a
                     strong match) ~ 0.93), the stop rule fires early, and the
                     prior is uniform. Converges in 2-3 questions but that few
                     answers can leave a near-tie among near-duplicate recipes.

    Conservative  -- each answer moves the posterior only partway, "not sure"
                     is a real option, the stop rule demands higher confidence,
                     a minimum number of questions is enforced, and
                     hand-curated dishes get a prior boost so convergence lands
                     on an actual dish rather than whichever generated
                     near-duplicate wins the tie.

    Objective vs mood.  Objective opinions (protein, cuisine, base, dietary,
    time, star ingredient, structure...) are treated as near-constraints: a
    single "fish" answer sharply favors fish dishes, so "give me only fish"
    actually gives only fish. Mood questions (emotion, context, sensory
    craving) shift the posterior gently, so the quiz feels exploratory rather
    than letting one feeling dominate.
    """

    binary_slope: float = 0.92     # mood-answer slope (also the default)
    unsure: float = 0.06           # residual probability of "not sure"
    tau: float = 3.5               # mood softmax temperature (also default)
    none_weight: Optional[float] = None  # fallback weight for "none" answers
    stop_top1: float = 0.40        # stop when best candidate >= this
    stop_top5: float = 0.85        # ... and top-5 mass >= this
    stop_entropy: float = 1.2      # ... or entropy drops to this
    curated_bonus: float = 1.0     # prior multiplier for hand-curated recipes
    choice_min_questions: int = 5  # offer a direct dish pick after N answers
    choice_top3: float = 0.40      # ... once the top-3 hold this much mass

    objective_slope: Optional[float] = None  # hard-constraint binary slope
    objective_unsure: Optional[float] = None
    objective_tau: Optional[float] = None
    mood_slope: Optional[float] = None       # gentle mood binary slope
    mood_unsure: Optional[float] = None
    mood_tau: Optional[float] = None
    mood_bonus: float = 0.15       # extra IG nudged toward mood questions
    min_floor: float = 0.02        # no answer may zero out a recipe family

    @property
    def binary_floor(self) -> float:
        """(1 - slope - unsure)/2 keeps P(yes)+P(no)+P(unsure) == 1."""
        return (1.0 - self.binary_slope - self.unsure) / 2.0

    def effective_none_weight(self, tau: float) -> float:
        if self.none_weight is not None:
            return self.none_weight
        return math.exp(tau * 0.06)


OBJECTIVE_CATEGORIES = frozenset({
    "protein", "cuisine", "base", "method", "meal", "diet",
    "ingredient", "struct",
})
# Dish-defining objective traits: stating these pins down WHAT the dish is.
# "time" / "effort" / "serving" are scheduling, not a dish opinion.
DISH_OBJECTIVE_CATEGORIES = frozenset({
    "protein", "cuisine", "base", "method", "meal", "diet",
    "ingredient", "struct",
})
_OBJECTIVE_SEED_KEYS = frozenset({
    "seed.protein", "seed.cuisine", "seed.base", "seed.meal", "seed.diet",
})
_DISH_SEED_KEYS = frozenset({
    "seed.protein", "seed.cuisine", "seed.base", "seed.meal", "seed.diet",
})


def _is_objective(q: Question) -> bool:
    """Objective = a stated fact that pins down WHAT the dish is (protein,
    cuisine, base, method, meal, diet, star ingredient, structure).

    Everything else (emotion, context, sensory craving, combo, and the
    scheduling traits time/effort/serving/occasion) is mood: a feeling, meant
    to shift the posterior gently. Scheduling answers nudge but never lock
    out -- otherwise a single "under 15 min" could silently kill every fish
    dish before the user ever gets to say "fish".
    """
    if q.category in OBJECTIVE_CATEGORIES:
        return True
    return q.category == "seed" and q.trait_key in _OBJECTIVE_SEED_KEYS


def _is_dish_objective(q: Question) -> bool:
    if q.category in DISH_OBJECTIVE_CATEGORIES:
        return True
    return q.category == "seed" and q.trait_key in _DISH_SEED_KEYS


def _q_params(q: Question, config: EngineConfig) -> tuple:
    """(slope, floor, unsure, tau) for this question's likelihood row.

    The "wrong" side of an answer must never be allowed to hit zero: a zero
    floor permanently locks out every non-matching recipe (p * 0 stays 0),
    so an early answer could silently delete whole protein/cuisine families
    before the user ever gets to state a preference. Floor is clamped to
    config.min_floor and slope is renormalized so rows still sum to 1.
    """
    if _is_objective(q):
        slope = config.objective_slope or config.binary_slope
        unsure = config.objective_unsure if config.objective_unsure is not None \
            else config.unsure
        tau = config.objective_tau or config.tau
    else:
        slope = config.mood_slope or config.binary_slope
        unsure = config.mood_unsure if config.mood_unsure is not None \
            else config.unsure
        tau = config.mood_tau or config.tau
    floor = max(config.min_floor, (1.0 - slope - unsure) / 2.0)
    slope = 1.0 - unsure - 2.0 * floor  # renormalize so slope+2*floor+unsure=1
    return slope, floor, unsure, tau


ENTHUSIASTIC = EngineConfig()
CONSERVATIVE = EngineConfig(
    binary_slope=0.55,
    unsure=0.22,
    tau=1.3,
    stop_top1=0.55,
    stop_top5=0.92,
    stop_entropy=0.6,
    curated_bonus=2.0,
    choice_top3=0.35,
    choice_min_questions=7,
)
ENTHUSIASTIC.objective_slope = 0.98
ENTHUSIASTIC.objective_unsure = 0.02
ENTHUSIASTIC.objective_tau = 8.0
ENTHUSIASTIC.mood_slope = 0.55
ENTHUSIASTIC.mood_unsure = 0.10
ENTHUSIASTIC.mood_tau = 2.2
ENTHUSIASTIC.mood_bonus = 0.15
CONSERVATIVE.objective_slope = 0.90
CONSERVATIVE.objective_unsure = 0.04
CONSERVATIVE.objective_tau = 4.0
CONSERVATIVE.mood_slope = 0.45
CONSERVATIVE.mood_unsure = 0.20
CONSERVATIVE.mood_tau = 1.5
CONSERVATIVE.mood_bonus = 0.15
STYLES = {"enthusiastic": ENTHUSIASTIC, "conservative": CONSERVATIVE}


def _entropy(p: list) -> float:
    h = 0.0
    for v in p:
        if v > 0.0:
            h -= v * math.log(v)
    return h


def p_answer(question: Question, answer_idx: int, recipe: Recipe,
             config: EngineConfig = ENTHUSIASTIC) -> float:
    """P(user answers `answers[answer_idx]` | recipe)."""
    slope, floor, unsure, tau = _q_params(question, config)
    if question.kind == "binary":
        if answer_idx == 0:   # yes
            s = clamp01(score_trait(question.answers[0].trait, recipe))
        elif answer_idx == 1:  # no
            s = 1.0 - clamp01(score_trait(question.answers[0].trait, recipe))
        else:                 # unsure
            return unsure
        return slope * s + floor
    # multi-answer: softmax over answer scores; the trailing "none" fallback
    # answer gets its own weight so probabilities sum to exactly 1. Each
    # answer keeps at least min_floor mass so no recipe is ever locked out.
    ws = [math.exp(tau * clamp01(score_trait(a.trait, recipe)))
          for a in question.answers]
    ws[-1] = config.effective_none_weight(tau)
    total = sum(ws)
    probs = [max(config.min_floor, w / total) for w in ws]
    norm = sum(probs)
    return probs[answer_idx] / norm


class PalateEngine:
    def __init__(self, recipes: list, questions: list,
                 config: EngineConfig = ENTHUSIASTIC):
        self.config = config
        self.recipes = recipes
        self.questions = questions
        self._q_index = {q.id: i for i, q in enumerate(questions)}
        self._key_index = {q.trait_key: q for q in questions}
        # likelihood[qi][ai][r] = P(answer ai | recipe r)
        self.likelihood = [
            [[p_answer(q, ai, r, config) for r in recipes]
             for ai in range(len(q.answers))]
            for q in questions
        ]
        # Prior: uniform, optionally biased toward hand-curated dishes so that
        # a conservative session converges on a real dish rather than a
        # procedurally-generated near-duplicate that happens to win the tie.
        prior = [
            (config.curated_bonus if r.source == "curated" else 1.0)
            for r in recipes
        ]
        total = sum(prior)
        self._prior = [v / total for v in prior]
        self.p = list(self._prior)
        self.asked = set()
        self.history = []
        self._last = None
        self._choice_decided = False
        self._choice_gap = 0
        self._objective_opinion = False
        self._objective_declined = False

    # -- lifecycle -----------------------------------------------------------

    def reset(self, seeds: list = None) -> None:
        self.p = list(self._prior)
        self.asked = set()
        self.history = []
        self._last = None
        self._choice_decided = False
        self._choice_gap = 0
        self._objective_opinion = False
        self._objective_declined = False
        for s in (seeds or []):
            self.answer_direct(s.question_id, s.answer_id)

    # -- posterior statistics ------------------------------------------------

    def entropy(self) -> float:
        return _entropy(self.p)

    def effective_candidates(self) -> float:
        return math.exp(self.entropy())

    def top(self, k: int) -> list:
        ranked = sorted(
            ((self.recipes[i], self.p[i]) for i in range(len(self.recipes))),
            key=lambda x: x[1], reverse=True,
        )
        return ranked[:k]

    def top1_prob(self) -> float:
        return max(self.p)

    def top5_prob(self) -> float:
        return sum(p for _, p in self.top(5))

    def top_k_prob(self, k: int) -> float:
        return sum(p for _, p in self.top(k))

    # -- question selection --------------------------------------------------

    def _expected_entropy(self, qi: int) -> tuple:
        p = self.p
        R = len(p)
        H = _entropy(p)
        expected = 0.0
        for la in self.likelihood[qi]:
            pa = 0.0
            for i in range(R):
                pa += p[i] * la[i]
            if pa <= 1e-12:
                continue
            h_a = 0.0
            for i in range(R):
                q = (p[i] * la[i]) / pa
                if q > 1e-15:
                    h_a -= q * math.log(q)
            expected += pa * h_a
        return expected, max(0.0, H - expected)

    def select_question(self) -> dict:
        """Return the unasked question with maximum expected information gain.

        Scores every candidate question in the bank that has not been asked,
        so a 10-question session is choosing each of its questions from the
        full 500+ pool.

        Once the top few dishes carry enough posterior mass, the best
        "question" to ask is a direct one: list those dishes and let the user
        pick (or reject them all). This is what actually converges on a dish
        someone wants to eat instead of firing weak trait questions forever.
        """
        best = None
        for qi, q in enumerate(self.questions):
            if q.id in self.asked:
                continue
            if (self._objective_declined and not self._objective_opinion
                    and _is_dish_objective(q)):
                # The user said "no preference" to one dish-defining question
                # (cuisine/protein/base/...) and never stated an opinion --
                # don't drag them through that survey; let the mood quiz run.
                continue
            expected, ig = self._expected_entropy(qi)
            score = ig + (self.config.mood_bonus if not _is_objective(q) else 0.0)
            if best is None or score > best["_score"]:
                best = {
                    "question": q,
                    "information_gain": ig,
                    "expected_entropy": expected,
                    "candidates_considered": sum(
                        1 for x in self.questions if x.id not in self.asked),
                    "_score": score,
                }

        offer = self._offer_choice()
        if not offer and not self._choice_decided \
                and best is not None and best["information_gain"] < 0.02 \
                and self.top_k_prob(3) >= self.config.choice_top3:
            # Nothing left to ask that would help, but the field has narrowed:
            # offer the shortlist so the user can confirm rather than drift.
            offer = True
        if offer:
            best = {
                "question": self._disambiguation_question(),
                "information_gain": self.entropy(),  # picking the dish is the
                "expected_entropy": 0.0,             # maximum-IG move possible
                "candidates_considered": len(self.questions),
                "dynamic": True,
            }
        self._last = best
        return best

    def _offer_choice(self) -> bool:
        if self._choice_decided:
            return False
        if len(self.history) < self.config.choice_min_questions:
            return False
        if self._choice_gap < 3:
            # After a "none of these" rejection, give the engine a few real
            # questions (re-opened dish-defining ones) before re-offering the
            # shortlist -- otherwise it bounces straight back into the list.
            return False
        return self.top_k_prob(3) >= self.config.choice_top3

    def _disambiguation_question(self) -> Question:
        """A dynamic 'which of these dishes' question over the current top-4."""
        answers = [Answer(id=f"dish:{r.id}",
                          label=f"{r.name} ({r.cuisines[0].title()})")
                   for r, _ in self.top(4)]
        answers.append(Answer(id="none", label="None of these sound good"))
        return Question(
            id="choice.top", category="choice", trait_key="choice.top",
            text="Between these, which sounds best right now?",
            kind="choice", answers=answers,
        )

    def candidate_question_count(self) -> int:
        return len(self.questions) - len(self.asked)

    # -- answering -----------------------------------------------------------

    def _apply(self, qid: str, aid: str) -> None:
        if qid == "choice.top":
            self._apply_choice(aid)
            return
        qi = self._q_index[qid]
        q = self.questions[qi]
        ai = next(i for i, a in enumerate(q.answers) if a.id == aid)
        la = self.likelihood[qi][ai]
        total = 0.0
        nxt = [0.0] * len(self.recipes)
        for i in range(len(self.recipes)):
            v = self.p[i] * la[i]
            nxt[i] = v
            total += v
        if total <= 1e-14:  # safety net: collapse should never happen
            nxt = list(self._prior)
            total = 1.0
        for i in range(len(self.recipes)):
            nxt[i] /= total
        self.p = nxt
        self.asked.add(qid)
        self._choice_gap += 1
        if _is_dish_objective(q):
            if aid in ("none", "unsure"):
                self._objective_declined = True
            else:
                self._objective_opinion = True
        self.history.append(AnswerRecord(
            question_id=qid, answer_id=aid, label=q.answers[ai].label))

    def answer(self, answer_id: str) -> None:
        if self._last is None:
            raise RuntimeError("No question selected yet")
        self._apply(self._last["question"].id, answer_id)

    def _apply_choice(self, aid: str) -> None:
        q = self._disambiguation_question()
        label = next(a.label for a in q.answers if a.id == aid)
        if aid == "none":
            # Reject the shown candidates outright: crush their mass so a new
            # set of top dishes emerges and the session can recover.
            shown = {a.id.split(":", 1)[1] for a in q.answers
                     if a.id.startswith("dish:")}
            nxt = [p * 0.03 if r.id in shown else p
                   for r, p in zip(self.recipes, self.p)]
            total = sum(nxt)
            self.p = [v / total for v in nxt] if total > 1e-14 else list(self._prior)
            # The mood-driven shortlist missed. Re-open the dish-defining
            # questions so the user can state a real opinion ("actually, fish")
            # instead of being bounced back into the mood quiz forever.
            self._objective_declined = False
            self._choice_gap = 0
        else:
            rid = aid.split(":", 1)[1]
            rest = 0.15 / (len(self.recipes) - 1)
            self.p = [0.85 if r.id == rid else rest for r in self.recipes]
            self._choice_decided = True
        self.asked.add(q.id)
        self.history.append(AnswerRecord(question_id=q.id, answer_id=aid,
                                         label=label))

    def answer_direct(self, qid: str, aid: str) -> None:
        if qid in self.asked:
            return
        self._apply(qid, aid)

    def answer_by_key(self, trait_key: str, aid: str) -> None:
        q = self._key_index[trait_key]
        self.answer_direct(q.id, aid)

    def question_by_key(self, trait_key: str) -> Question:
        return self._key_index[trait_key]

    def best_answer_for_recipe(self, qid: str, recipe_id: str) -> str:
        """Scripted-agent helper: answer the way a user craving `recipe_id`
        most likely would, so the engine can be demonstrated end-to-end."""
        if qid == "choice.top":
            q = self._disambiguation_question()
            for a in q.answers:
                if a.id.startswith("dish:") and a.id.split(":", 1)[1] == recipe_id:
                    return a.id
            return "none"
        qi = self._q_index[qid]
        ri = next(i for i, r in enumerate(self.recipes) if r.id == recipe_id)
        best_i, best_p = 0, -1.0
        for ai, la in enumerate(self.likelihood[qi]):
            if la[ri] > best_p:
                best_p, best_i = la[ri], ai
        return self.questions[qi].answers[best_i].id

    # -- stopping ------------------------------------------------------------

    def should_stop(self, max_questions: int = 10, min_questions: int = 0,
                    min_ig: float = 0.02) -> bool:
        if len(self.history) < min_questions:
            return False
        if len(self.history) >= max_questions:
            return True
        if self._choice_decided:
            return True  # user actively picked their dish -- done
        # Never declare a winner purely from posterior mass before the user has
        # had the chance to confirm (or reject) the front-runners in the direct
        # dish-choice. Otherwise a strong objective answer could hand the user
        # a dish they don't actually want. So: if the shortlist is offerable,
        # or we're mid-recovery after a rejection (gap < 3), keep asking.
        if len(self.history) > self.config.choice_min_questions:
            if self._offer_choice() or self._choice_gap < 3:
                return False
            if self.top1_prob() >= self.config.stop_top1 \
                    and self.top5_prob() >= self.config.stop_top5:
                return True
            if self.entropy() <= self.config.stop_entropy:
                return True
        return False

    # -- explainability ------------------------------------------------------

    def explain(self, recipe_id: str, limit: int = 6) -> list:
        """Explain why this recipe rose to the top."""
        ri = next(i for i, r in enumerate(self.recipes) if r.id == recipe_id)
        lines = []
        for record in self.history:
            if record.question_id not in self._q_index:
                continue
            qi = self._q_index[record.question_id]
            q = self.questions[qi]
            ai = next(i for i, a in enumerate(q.answers)
                      if a.id == record.answer_id)
            la = self.likelihood[qi][ai]
            marginal = sum(la) / len(la)          # P(a) under uniform prior
            ratio = math.log(max(la[ri], 1e-9)) - math.log(max(marginal, 1e-9))
            if ratio > 0.05:
                lines.append(
                    (ratio, f"  +{ratio:4.2f}  \"{record.label}\"  <-  {q.text}"))
        lines.sort(reverse=True)
        return [t for _, t in lines[:limit]]

    def full_state(self) -> dict:
        return {
            "entropy": self.entropy(),
            "effective_candidates": self.effective_candidates(),
            "questions_asked": len(self.history),
            "candidates_considered": self.candidate_question_count(),
            "top": self.top(5),
        }


def default_engine(seed=42, style: str = "enthusiastic") -> PalateEngine:
    config = STYLES[style]
    return PalateEngine(load_recipes(seed=seed), load_questions(), config=config)
