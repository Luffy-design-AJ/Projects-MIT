"""Scripted end-to-end demo.

Shows the engine asking a minimal number of questions, each chosen from the
entire 500+ question bank to maximize expected information gain, and converging
on a recommendation the user never had to name.
"""

from __future__ import annotations

from palate.data.recipes import load_recipes
from palate.engine.bayes import default_engine
from palate.types import AnswerRecord


def _fmt_recipe(r):
    return f"{r.name:32s} {r.cuisines[0].title():16s} {r.cook_minutes:3d} min"


def _time_answer_id(cook_minutes: int) -> str:
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


def run_demo(target_id: str = "pho", max_questions: int = 10, seed: int = 42,
             style: str = "enthusiastic"):
    recipes = load_recipes(seed=seed)
    target = next(r for r in recipes if r.id == target_id)
    engine = default_engine(seed=seed, style=style)
    min_questions = 6 if style == "conservative" else 3

    print("=" * 78)
    print(f"PALATE ({style}) - emotion-aware, entropy-minimizing "
          "food recommendation")
    print("=" * 78)
    print(f"\nRecipes in search space : {len(recipes)}")
    print(f"Questions in bank       : {len(engine.questions)}")
    print(f"Hidden user craving     : {target.name} ({target.cuisines[0]})\n")

    mood = target.emotions[0]
    time_id = _time_answer_id(target.cook_minutes)
    engine.reset([
        AnswerRecord(engine.question_by_key("seed.mood").id, mood,
                     mood.title() + " (seeded mood)"),
        AnswerRecord(engine.question_by_key("seed.time").id, time_id,
                     time_id + " (seeded time)"),
    ])

    print(f"Seed signals: mood={mood!r}, available time={time_id}\n")

    def state_line():
        return (f"  entropy={engine.entropy():5.2f}  "
                f"effective-candidates={engine.effective_candidates():6.1f}")

    print(f"Start                  {state_line()}")
    print("  top-3:", ", ".join(r.name for r, _ in engine.top(3)), "\n")

    steps = 0
    while steps < max_questions and not engine.should_stop(max_questions,
                                                           min_questions=min_questions):
        sel = engine.select_question()
        if sel is None or sel["information_gain"] < 0.02:
            break
        q = sel["question"]
        steps += 1
        aid = engine.best_answer_for_recipe(q.id, target.id)
        label = next(a.label for a in q.answers if a.id == aid)
        engine.answer(aid)

        print(f"Q{steps}. {q.text}")
        if sel.get("dynamic"):
            print("      [direct dish choice -- narrowed the field]")
        else:
            print(f"      [chosen from {sel['candidates_considered']} candidate questions, "
                  f"IG={sel['information_gain']:+.2f}]")
        print(f"   -> user: {label}")
        print(f"      {state_line()}")
        print("      top-3:", ", ".join(r.name for r, _ in engine.top(3)), "\n")

    print("=" * 78)
    print("RECOMMENDATION")
    print("=" * 78)
    rank = next((i for i, (r, _) in enumerate(engine.top(len(engine.recipes)))
                 if r.id == target_id), None)
    for i, (r, p) in enumerate(engine.top(5), 1):
        marker = " <-- hidden craving" if r.id == target_id else ""
        print(f"  {i}. {_fmt_recipe(r)}  p={p:.3f}{marker}")
    print(f"\nTarget ranked #{rank + 1} after {steps} adaptive questions "
          f"(+2 seeded).")

    print("\nWHY THESE? (top contributor answers for the recommended dish)\n")
    for line in engine.explain(engine.top(1)[0][0].id):
        print(line)
    print()


if __name__ == "__main__":
    import sys

    style = "conservative" if "--conservative" in sys.argv else "enthusiastic"
    target = sys.argv[1] if len(sys.argv) > 1 else "pho"
    run_demo(target_id=target,
             max_questions=14 if style == "conservative" else 10,
             style=style)
