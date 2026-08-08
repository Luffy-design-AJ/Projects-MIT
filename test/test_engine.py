"""Tests for the Palate Bayesian recommendation engine."""

from __future__ import annotations

import unittest

from palate.data.questions import load_questions
from palate.data.recipes import load_recipes
from palate.engine.bayes import default_engine, PalateEngine
from palate.engine.traits import score_trait, has_any
from palate.types import AnswerRecord


class TestData(unittest.TestCase):
    def test_question_bank_at_least_500(self):
        qs = load_questions()
        self.assertGreaterEqual(len(qs), 500)

    def test_unique_question_ids(self):
        qs = load_questions()
        ids = [q.id for q in qs]
        self.assertEqual(len(ids), len(set(ids)))

    def test_recipe_database_size(self):
        rs = load_recipes()
        self.assertGreaterEqual(len(rs), 100)

    def test_question_ids_match_category(self):
        for q in load_questions():
            self.assertTrue(q.id.startswith(q.category + "."))

    def test_seed_questions_exist(self):
        for key in ("seed.mood", "seed.time", "seed.occasion", "seed.diet",
                    "seed.cuisine", "seed.meal", "seed.protein", "seed.base"):
            self.assertTrue(any(q.trait_key == key for q in load_questions()),
                            f"missing {key}")

    def test_nuanced_mood_questions_exist(self):
        mood = [q for q in load_questions() if q.trait_key.startswith("mood.")]
        self.assertGreaterEqual(len(mood), 15)
        multis = [q for q in mood if q.kind == "multi"]
        self.assertGreaterEqual(len(multis), 3)


class TestLikelihood(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.recipes = load_recipes()
        cls.questions = load_questions()

    def _check_binary(self, q):
        eng = PalateEngine(self.recipes, [q])
        self.assertEqual(len(eng.likelihood), 1)
        for la in eng.likelihood[0]:
            self.assertEqual(len(la), len(self.recipes))
        for i in range(len(self.recipes)):
            total = sum(eng.likelihood[0][a][i] for a in range(len(q.answers)))
            self.assertAlmostEqual(total, 1.0, places=6,
                                   msg=f"{q.id} row {i} sums to {total}")

    def test_binary_likelihood_normalised(self):
        for q in self.questions:
            if q.kind == "binary":
                self._check_binary(q)

    def test_multi_likelihood_normalised(self):
        for q in self.questions:
            if q.kind == "multi":
                self._check_binary(q)

    def test_positive_likelihoods(self):
        eng = PalateEngine(self.recipes, [q for q in self.questions if q.kind == "binary"][:5])
        for table in eng.likelihood:
            for la in table:
                for v in la:
                    self.assertGreater(v, 0.0)


class TestEngine(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.recipes = load_recipes()
        cls.questions = load_questions()
        cls.engine = PalateEngine(cls.recipes, cls.questions)

    def test_initial_posterior_uniform(self):
        self.engine.reset()
        for p in self.engine.p:
            self.assertAlmostEqual(p, 1.0 / len(self.recipes), places=9)
        self.assertAlmostEqual(sum(self.engine.p), 1.0, places=9)

    def test_posterior_sums_to_one_after_answers(self):
        self.engine.reset()
        q = self.engine.question_by_key("seed.mood")
        self.engine.answer_direct(q.id, "comfort")
        self.assertAlmostEqual(sum(self.engine.p), 1.0, places=9)
        sel = self.engine.select_question()
        self.engine.answer(sel["question"].answers[0].id)
        self.assertAlmostEqual(sum(self.engine.p), 1.0, places=9)

    def test_broth_answer_boosts_broth_recipes(self):
        self.engine.reset()
        q = self.engine.question_by_key("broth")
        self.engine.answer_direct(q.id, "yes")
        broth = [p for (r, p) in zip(self.recipes, self.engine.p) if r.has_broth]
        other = [p for (r, p) in zip(self.recipes, self.engine.p) if not r.has_broth]
        self.assertGreater(sum(broth), sum(other))

    def test_selection_uses_full_pool(self):
        self.engine.reset([
            AnswerRecord(self.engine.question_by_key("seed.mood").id, "comfort"),
        ])
        for _ in range(6):
            sel = self.engine.select_question()
            self.assertIsNotNone(sel)
            self.assertGreaterEqual(sel["candidates_considered"], 500)
            self.assertGreater(sel["information_gain"], 0.0)
            self.assertNotIn(sel["question"].id, self.engine.asked)
            self.engine.answer(sel["question"].answers[0].id)

    def test_entropy_decreases_with_informative_answers(self):
        self.engine.reset()
        h0 = self.engine.entropy()
        target = next(r for r in self.recipes if r.id == "pho")
        for _ in range(4):
            sel = self.engine.select_question()
            aid = self.engine.best_answer_for_recipe(sel["question"].id, target.id)
            self.engine.answer(aid)
        self.assertLess(self.engine.entropy(), h0)

    def test_objective_answer_constrains_to_matching_recipes(self):
        engine = default_engine()
        engine.reset()
        q = engine.question_by_key("want.fish")
        engine.answer_direct(q.id, "yes")
        top = engine.top(10)
        self.assertTrue(all("fish" in r.proteins for r, _ in top),
                        "stating 'fish' should surface only fish dishes")

    def test_mood_answer_shifts_less_than_objective_answer(self):
        def shift(question_key, aid):
            engine = default_engine()
            engine.reset()
            q = engine.question_by_key(question_key)
            p0 = list(engine.p)
            engine.answer_direct(q.id, aid)
            return sum(abs(a - b) for a, b in zip(p0, engine.p)) / 2.0

        objective = shift("want.fish", "yes")
        mood = shift("want.energizing", "yes")
        self.assertGreater(objective, mood * 2.0,
                           "an objective opinion should bite harder than a mood")

    def test_declining_one_dish_question_skips_the_rest_of_survey(self):
        engine = default_engine()
        engine.reset()
        engine.answer_direct(engine.question_by_key("seed.cuisine").id, "none")
        for _ in range(5):
            sel = engine.select_question()
            q = sel["question"]
            self.assertNotIn(q.trait_key, {
                "seed.protein", "seed.cuisine", "seed.base", "seed.meal",
                "seed.diet",
            })
            self.assertNotIn(q.category, {
                "protein", "cuisine", "base", "method", "meal", "diet",
                "ingredient", "struct",
            })
            if sel.get("dynamic"):
                engine.answer("none")
            else:
                engine.answer(q.answers[0].id)

    def test_fish_answer_dominates_even_after_scheduling_answers(self):
        engine = default_engine()
        target = next(r for r in engine.recipes if r.id == "pho")
        engine.reset()
        # scheduling/mood answers first (as in a real quiz), then "fish"
        for key, aid in [("serving.size", "two"), ("seed.occasion", "dinner-party")]:
            engine.answer_direct(engine.question_by_key(key).id, aid)
        engine.answer_direct(engine.question_by_key("seed.protein").id, "fish")
        fish_mass = sum(p for r, p in zip(engine.recipes, engine.p)
                        if "fish" in r.proteins)
        self.assertGreater(fish_mass, 0.5,
                           "stating fish must dominate earlier scheduling nudges")

    def test_pho_converges_to_top_five(self):
        engine = default_engine()
        target = next(r for r in engine.recipes if r.id == "pho")
        engine.reset([
            AnswerRecord(engine.question_by_key("seed.mood").id, "comfort"),
            AnswerRecord(engine.question_by_key("seed.time").id, "90+"),
        ])
        for _ in range(10):
            if engine.should_stop(10, min_questions=3):
                break
            sel = engine.select_question()
            aid = engine.best_answer_for_recipe(sel["question"].id, target.id)
            engine.answer(aid)
        top_ids = [r.id for r, _ in engine.top(5)]
        self.assertIn("pho", top_ids)

    def test_conservative_needs_more_questions_than_enthusiastic(self):
        def questions_to_stop(style):
            engine = default_engine(style=style)
            target = next(r for r in engine.recipes if r.id == "pho")
            engine.reset([
                AnswerRecord(engine.question_by_key("seed.mood").id, "comfort"),
                AnswerRecord(engine.question_by_key("seed.time").id, "90+"),
            ])
            n = 0
            while n < 14 and not engine.should_stop(14, min_questions=0):
                sel = engine.select_question()
                if sel is None or sel["information_gain"] < 0.02:
                    break
                aid = engine.best_answer_for_recipe(sel["question"].id, target.id)
                engine.answer(aid)
                n += 1
            return n, [r.id for r, _ in engine.top(5)]

        n_e, top_e = questions_to_stop("enthusiastic")
        n_c, top_c = questions_to_stop("conservative")
        self.assertLess(n_e, n_c)
        self.assertIn("pho", top_e)
        self.assertIn("pho", top_c)

    def test_no_repeated_questions_in_session(self):
        engine = default_engine()
        engine.reset()
        for _ in range(8):
            sel = engine.select_question()
            self.assertIsNotNone(sel)
            self.engine_ask_answer = sel["question"].answers[0].id
            engine.answer(sel["question"].answers[0].id)
        self.assertEqual(len(engine.history), len({h.question_id for h in engine.history}))

    def test_dish_choice_offered_once_field_narrows(self):
        engine = default_engine(style="conservative")
        target = next(r for r in engine.recipes if r.id == "pho")
        engine.reset([
            AnswerRecord(engine.question_by_key("seed.mood").id, "comfort"),
            AnswerRecord(engine.question_by_key("seed.time").id, "90+"),
        ])
        choice_seen = False
        for _ in range(10):
            if engine.should_stop(10, min_questions=3):
                break
            sel = engine.select_question()
            if sel.get("dynamic"):
                choice_seen = True
                self.assertEqual(sel["question"].kind, "choice")
                self.assertGreaterEqual(len(sel["question"].answers), 4)
                break
            engine.answer(engine.best_answer_for_recipe(sel["question"].id, target.id))
        self.assertTrue(choice_seen, "expected a direct dish-choice question")

    def test_dish_choice_pick_locks_in_top_dish(self):
        engine = default_engine()
        engine.reset()
        for _ in range(6):
            sel = engine.select_question()
            if sel.get("dynamic"):
                break
            engine.answer(sel["question"].answers[0].id)
        sel = engine.select_question()
        self.assertTrue(sel.get("dynamic"))
        pick = sel["question"].answers[0].id
        engine.answer(pick)
        self.assertGreaterEqual(engine.top1_prob(), 0.8)
        self.assertTrue(engine.should_stop(10, min_questions=0))

    def test_dish_choice_reject_demotes_shown_dishes(self):
        engine = default_engine()
        engine.reset()
        for _ in range(6):
            sel = engine.select_question()
            if sel.get("dynamic"):
                break
            engine.answer(sel["question"].answers[0].id)
        shown_before = {r.id for r, _ in engine.top(4)}
        mass_before = sum(p for r, p in engine.top(4)
                          if r.id in shown_before)
        sel = engine.select_question()
        engine.answer("none")
        mass_after = sum(self._prob(engine, rid) for rid in shown_before)
        self.assertLess(mass_after, mass_before / 3.0)
        shown_after = {r.id for r, _ in engine.top(4)}
        self.assertTrue(any(r not in shown_after for r in shown_before),
                        "rejecting the top-4 should surface new dishes")

    def _prob(self, engine, rid):
        return next(p for r, p in zip(engine.recipes, engine.p) if r.id == rid)


    def test_determinism(self):
        e1, e2 = default_engine(), default_engine()
        seeds = [AnswerRecord(e1.question_by_key("seed.mood").id, "adventurous")]
        e1.reset(seeds)
        e2.reset(seeds)
        self.assertEqual(e1.entropy(), e2.entropy())
        self.assertEqual(e1.select_question()["question"].id,
                         e2.select_question()["question"].id)

    def test_explain_returns_lines(self):
        engine = default_engine()
        engine.reset([
            AnswerRecord(engine.question_by_key("seed.mood").id, "comfort"),
            AnswerRecord(engine.question_by_key("seed.time").id, "90+"),
        ])
        target = next(r for r in engine.recipes if r.id == "pho")
        for _ in range(3):
            sel = engine.select_question()
            aid = engine.best_answer_for_recipe(sel["question"].id, target.id)
            engine.answer(aid)
        lines = engine.explain("pho")
        self.assertGreater(len(lines), 0)

    def test_score_trait(self):
        pho = next(r for r in self.recipes if r.id == "pho")
        self.assertEqual(score_trait(has_any("emotions", ["comfort"]), pho), 1.0)
        self.assertEqual(score_trait(has_any("emotions", ["celebratory"]), pho), 0.0)
        self.assertGreaterEqual(score_trait(None, pho), 0.0)


if __name__ == "__main__":
    unittest.main()
