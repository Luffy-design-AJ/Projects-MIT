"""Verification harness.

Checks the hard MVP requirements:
  * the question bank contains >= 500 questions
  * each of a session's ~10 questions is chosen from that full pool
  * the Bayesian + entropy pipeline converges on a hidden craving
"""

from __future__ import annotations

import random
import time

from palate.data.questions import load_questions
from palate.data.recipes import load_recipes
from palate.engine.bayes import default_engine
from palate.types import AnswerRecord

N_TARGETS = 30
MAX_Q = 12


def time_answer_id(cook_minutes: int) -> str:
    if cook_minutes <= 15:
        return "lt15"
    if cook_minutes <= 30:
        return "15-30"
    if cook_minutes <= 45:
        return "30-45"
    if cook_minutes <= 60:
        return "45-60"
    if cook_minutes <= 90:
        return "60-90"
    return "90+"


def run(style: str = "enthusiastic"):
    recipes = load_recipes()
    questions = load_questions()

    print(f"Recipes               : {len(recipes)}")
    print(f"Question bank         : {len(questions)}  "
          f"(requirement: >= 500)  {'PASS' if len(questions) >= 500 else 'FAIL'}")

    rng = random.Random(7)
    targets = rng.sample(recipes, min(N_TARGETS, len(recipes)))

    successes = 0
    questions_used = []
    candidates_min = len(questions)
    t0 = time.time()

    engine = default_engine(style=style)
    min_questions = 6 if style == "conservative" else 3

    for target in targets:
        mood = target.emotions[0]
        time_id = time_answer_id(target.cook_minutes)
        engine.reset([
            AnswerRecord(engine.question_by_key("seed.mood").id, mood),
            AnswerRecord(engine.question_by_key("seed.time").id, time_id),
        ])

        steps = 0
        while steps < MAX_Q and not engine.should_stop(MAX_Q,
                                                       min_questions=min_questions):
            sel = engine.select_question()
            if sel is None or sel["information_gain"] < 0.02:
                break
            candidates_min = min(candidates_min, sel["candidates_considered"])
            aid = engine.best_answer_for_recipe(sel["question"].id, target.id)
            engine.answer(aid)
            steps += 1

        rank = next((i for i, (r, _) in enumerate(engine.top(len(engine.recipes)))
                     if r.id == target.id), None)
        ok = rank is not None and rank < 5
        successes += ok
        questions_used.append(steps)
        print(f"  {target.id:26s} -> rank #{rank + 1 if rank is not None else 'n/a':>4}"
              f"  questions={steps:2d}  {'OK' if ok else 'MISS'}")

    dt = time.time() - t0
    avg = sum(questions_used) / len(questions_used)
    print(f"\nStyle                     : {style}")
    print(f"Hit rate (target in top-5) : {successes}/{len(targets)} "
          f"({100 * successes / len(targets):.0f}%)")
    print(f"Avg adaptive questions     : {avg:.1f}")
    print(f"Min candidate pool seen    : {candidates_min} (requirement: each of the "
          f"~10 questions is selected from the full 500+)  "
          f"{'PASS' if candidates_min >= 500 else 'FAIL'}")
    print(f"Total wall time            : {dt:.1f}s")


if __name__ == "__main__":
    import sys

    style = "conservative" if "--conservative" in sys.argv else "enthusiastic"
    run(style=style)
