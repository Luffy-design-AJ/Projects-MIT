# Palate — MVP prototype

> *An adaptive search engine over the space of human food preferences.*

Palate is the "Akinator of food". It doesn't ask you to search for a recipe. It
asks you a small number of carefully chosen questions and infers what you
actually feel like eating.

This MVP implements the core algorithm described in the Palate Technical
Vision: a **Bayesian candidate-updating engine** that, at every step, selects
the question with the **maximum expected information gain (minimum expected
entropy)** from a bank of **500+ questions**.

```
P(recipe)            uniform prior over every recipe in the database
P(a | recipe)        likelihood of answering a given the recipe's traits
P(recipe | a) ∝ P(a | recipe) · P(recipe)     Bayes update after each answer
next question = argmax_q  H(P) − E_a[H(P | a)]   expected information gain
```

The engine never hard-filters recipes. Every answer re-weights the posterior
distribution over *all* recipes, so uncertainty is represented naturally and
no early binary decisions are made.

### Direct dish-choice (recovery)

Once the top few dishes hold enough posterior mass, "best next question" is no
longer a trait question — it's the dishes themselves. The engine then asks:

> *"Between these, which sounds best right now?" — Avocado Toast, Omelette,
> Caprese, Hue Rice Steam Basket, or None of these sound good.*

Picking a dish locks it in at high confidence and ends the session. Choosing
**"None of these sound good"** crushes the shown candidates' mass so a fresh
set of dishes surfaces — that is how a session recovers when the front-runners
aren't what the user actually wants, instead of firing weak trait questions at
an unresolved distribution forever. The engine refuses to declare a winner on
posterior mass alone before the user has had this chance to confirm.

### Objective opinions vs. mood

Questions split into two likelihood regimes (`palate/engine/bayes.py`):

- **Objective** (protein, cuisine, base, method, meal, dietary, time, star
  ingredient, structure): treated as near-constraints. Say "fish" and the
  shortlist is fish — `P(yes | match) ≈ 0.98`, a single answer dominates.
- **Mood** (emotion, context, sensory craving, combined cues): shifted gently
  (`P(yes | match) ≈ 0.55–0.67`), so the quiz reads exploratory and one
  feeling doesn't overwhelm everything.

The engine also nudges selection toward mood questions (a small IG bonus), and
the bank now carries **18 nuanced mood questions** ("Do you want food that
feels like a hug?", "How do you want to FEEL after this meal?") alongside the
basic ones, so sessions are mood-first unless the user states a hard
preference.

## MVP numbers

| Metric | Value |
| --- | --- |
| Recipes in the search space | 432 (96 hand-curated + 336 procedural) |
| Question bank | **541** questions (requirement: ≥ 500) |
| Question selection pool per step | full remaining bank (starts at 539) |
| Typical questions to converge | 3–5, ending in a direct dish pick |
| Verification hit rate | 30/30 targets in top-5 (100%) |
| Runtime | ~0.2 s per question selection, pure stdlib Python |

Each of the ~10 questions in a session is picked from the entire 500+ pool by
exhaustively scoring every candidate question's expected entropy reduction —
so the minimum "candidates considered" in a session is guaranteed ≥ 500.

## Run it

No dependencies. Python ≥ 3.10.

```bash
# scripted demo — the engine discovers a hidden craving ("pho" by default)
python3 demo.py                 # or: python3 demo.py laksa / tiramisu / tacos
python3 demo.py pho --conservative   # careful mode: ~8 questions instead of 2-3

# interactive Akinator-style session
python3 cli.py                  # enthusiastic (2-4 questions)
python3 cli_conservative.py     # conservative: 6-10 questions, higher confidence

# verification harness (bank size + 30-target convergence + timing)
python3 verify.py
python3 verify.py --conservative

# tests
python3 -m unittest test.test_engine -v
```

### Two personalities

The engine is configurable via `EngineConfig` (`palate/engine/bayes.py`). The
default **enthusiastic** style answers sharply and stops as soon as it can; the
**conservative** style treats every answer with caution, so it needs
**more questions before converging on an actual dish** — its likelihood slopes
are weaker (0.55 vs 0.92), it carries more "unsure" mass, it demands higher
confidence before stopping (top-1 ≥ 0.55 & top-5 ≥ 0.92, entropy ≤ 0.6), and a
prior bonus (2×) nudges ties toward hand-curated dishes over procedural
near-duplicates.

| Style | Objective slope | Mood slope | Stop (top-1 / top-5 / entropy) | Curated prior bonus | Typical questions |
| --- | --- | --- | --- | --- | --- | --- |
| `enthusiastic` | 0.98 | 0.55 | 0.40 / 0.85 / 1.2 | 1.0× | ~3 |
| `conservative` | 0.90 | 0.45 | 0.55 / 0.92 / 0.6 | 2.0× | ~5 |

Both styles keep 100% hit rate on the 30-target verification suite while the
conservative mode converges to the *same* top dish with higher final
confidence. Either way, the engine stops probing and asks the user to pick
directly between the front-runners — that choice is what lands on a dish the
person actually wants to eat.

### Demo excerpt

```
Recipes in search space : 432
Questions in bank       : 541
Hidden user craving     : Pho (vietnamese)

Start   entropy= 3.76  effective-candidates=  42.9
Q1. Are you leaning toward any cuisine?   [chosen from 539 candidate questions, IG=+2.30]
   -> user: Vietnamese
Q2. Between these, which sounds best right now?   [direct dish choice]
   1) Pho (Vietnamese)   2) Tonkotsu Ramen   3) Laksa   4) Paya
   -> user: Pho

  1. Pho   p=0.850  <-- hidden craving
```

## How it works

### Recipes are rich, not ingredient lists

`palate/types.py` — every recipe carries structural metadata (cuisine, meal
type, method, protein, base, dietary), sensory vectors (warmth, richness,
freshness, creaminess, crunchiness, sweetness, saltiness, sourness, bitterness,
umami, spiciness), emotional tags and contextual tags. The engine reasons at
this level, not over ingredient statistics.

### A composable trait layer

`palate/engine/traits.py` — `Trait` is a small predicate language
(`has_any`, `numeric`, `bool`, `and`, `or`, `not`) scored against a recipe in
`[0, 1]`. Both the recipe database (cuisine flavour priors) and every question
in the bank are expressed through it.

### The question bank

`palate/data/questions.py` — 541 questions generated from ~15 templates:
sensory cravings/aversions, mood (basic **and** 18 nuanced multi-feel questions
like "How do you want to FEEL after this meal?"), context/occasion, cuisine,
protein, base, cooking method, meal type, dietary, time, effort, structural
traits (broth, noodles, cold, sweet, fried…), star ingredients,
multi-attribute combinations, serving size, and cuisine×protein cues. The
`none` sentinel ("no preference" / "no protein") never leaks into question text —
every question reads like a human asked it.

### The Bayesian engine

`palate/engine/bayes.py` — precomputes `P(answer | recipe)` for every
question × answer × recipe, then:

- **posterior update** — `P(recipe | response) ∝ P(recipe) · P(response | recipe)`
- **question selection** — expected posterior entropy after each candidate
  question, pick the minimum (maximum information gain)
- **stopping rule** — configurable per style (top-1 ≥ 0.40 with top-5 ≥ 0.85,
  entropy ≤ 1.2, or a question cap for `enthusiastic`; stricter thresholds for
  `conservative`)
- **explainability** — every answer logs a log-likelihood ratio contribution,
  so recommendations can say *why* ("We recommended Laksa because…")

### Mood-first signals

The interactive flow starts by seeding the engine with emotional and
situational state (mood, available time, occasion, dietary need) before any
adaptive question — matching the vision's claim that mood sets the direction of
the search rather than acting as one more feature.

## Structure

```
palate/
  types.py            data model (Recipe, Question, Answer, Trait)
  data/
    cuisines.py       cuisine flavour priors, method priors, star ingredients
    recipes.py        curated + procedural recipe database
    questions.py      the 500+ question bank
  engine/
    traits.py         trait scoring
    bayes.py          posterior updates + entropy-minimising question selector
demo.py               scripted end-to-end demo (supports --conservative)
cli.py                interactive session (supports --conservative)
cli_conservative.py   alternate conservative interactive session
verify.py             requirement verification harness
test/test_engine.py   25 tests
```

## Headroom (vision-doc alignment)

The architecture keeps every component modular and replaceable on purpose, so
the future evolution path in the vision doc stays open:

- the handcrafted trait layer is a single pluggable scorer → replaceable by
  learned embeddings / GNNs / LLM-generated representations
- the likelihood model (`p_answer`) is a pure function → replaceable by
  learned P(a|r) from real interaction data
- the selector maximizes IG today → can become a contextual-bandit / RL
  policy without touching the posterior machinery
- the static recipe DB → swap in a larger corpus; nothing changes in the engine

The algorithm — not the recipe collection — is the product.
