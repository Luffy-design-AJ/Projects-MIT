"""Interactive CLI: play a Palate session like a human answering Akinator.

Usage:
  python3 cli.py                      # enthusiastic (2-4 questions)
  python3 cli.py --conservative       # careful, asks 6-10 questions
"""

from __future__ import annotations

import sys

from palate.engine.bayes import default_engine
from palate.types import AnswerRecord


def _render(question, engine):
    print(f"\nQ. {question.text}")
    if question.kind == "choice":
        print("   (I've narrowed it down -- tell me which one hits the spot)")
    else:
        print(f"   (best of {engine.candidate_question_count()} remaining questions)")
    for i, a in enumerate(question.answers, 1):
        print(f"     {i:>2}) {a.label}")
    print(f"   {'':>2}) skip to results")


def _state(engine):
    top = engine.top(3)
    names = ", ".join(r.name for r, _ in top)
    print(f"   [entropy {engine.entropy():.2f} | "
          f"~{engine.effective_candidates():.1f} candidates | "
          f"best guess {engine.top1_prob():.0%} | top: {names}]")


def _ask_question(engine):
    sel = engine.select_question()
    if sel is None or sel["information_gain"] < 0.02:
        return False
    _render(sel["question"], engine)
    while True:
        raw = input("   -> ").strip()
        if raw == "":
            if input("      Skip to results? (y/n) ").strip().lower() == "y":
                return False
            continue
        try:
            idx = int(raw) - 1
            aid = sel["question"].answers[idx].id
        except (ValueError, IndexError):
            print("      (enter a number)")
            continue
        engine.answer(aid)
        _state(engine)
        return True


def _ask_seed(engine, trait_key, prompt):
    q = engine.question_by_key(trait_key)
    print(f"\n{prompt}")
    _render(q, engine)
    while True:
        raw = input("   -> ").strip()
        try:
            idx = int(raw) - 1
            if 0 <= idx < len(q.answers):
                return AnswerRecord(q.id, q.answers[idx].id, q.answers[idx].label)
        except ValueError:
            pass
        print("      (enter a number)")


def main(style: str = "enthusiastic", max_questions: int = 10,
         min_questions: int = 2):
    title = "PALATE (careful mode)" if style == "conservative" else "PALATE"
    blurb = ("Answers are treated with caution, so expect 6-10 questions "
             "before it is sure of a real dish."
             if style == "conservative"
             else "Answer a few questions; Palate picks each one to learn the most.")

    print("=" * 70)
    print(title + "  --  an adaptive search over what you feel like eating")
    print("=" * 70)
    print(blurb)
    print("(type 'q' at any question prompt to quit)\n")

    engine = default_engine(style=style)
    print(f"Search space: {len(engine.recipes)} recipes | "
          f"question bank: {len(engine.questions)} | mode: {style}")

    while True:
        seeds = []
        seeds.append(_ask_seed(engine, "seed.mood", "How are you feeling right now?"))
        seeds.append(_ask_seed(engine, "seed.time", "How much time do you have?"))

        engine.reset(seeds)
        _state(engine)

        while len(engine.history) < max_questions:
            if engine.should_stop(max_questions, min_questions=min_questions):
                break
            if not _ask_question(engine):
                break

        print("\n" + "=" * 70)
        print(f"RECOMMENDED after {len(engine.history)} answers "
              f"({engine.top1_prob():.0%} confident)")
        print("=" * 70)
        for i, (r, p) in enumerate(engine.top(5), 1):
            cuis = ", ".join(c.title() for c in r.cuisines)
            print(f"  {i}. {r.name:32s} {cuis:24s} {r.cook_minutes:3d} min  p={p:.2f}")

        print("\nWHY THESE?")
        for line in engine.explain(engine.top(1)[0][0].id):
            print(line)

        again = input("\nAnother craving? (y/n) ").strip().lower()
        if again != "y":
            break
        engine.reset()


if __name__ == "__main__":
    try:
        if "--conservative" in sys.argv:
            main(style="conservative", max_questions=14, min_questions=6)
        else:
            main()
    except (KeyboardInterrupt, EOFError):
        print("\nBye.")
        sys.exit(0)
