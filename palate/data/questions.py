"""The adaptive question bank.

This is the pool the Bayesian engine selects from.  Every question is scored
against every recipe (see engine/bayes.py), so the engine can compute the
expected information gain of asking any one of them and pick the maximum.

The bank is generated from composable trait templates so that 500+ questions
share a tiny amount of hand-written structure: an answer to any question
updates P(recipe | responses) through the same likelihood machinery.
"""

from __future__ import annotations

from ..engine.traits import (
    and_traits, boolean, has_any, not_trait, numeric, or_traits,
)
from ..types import (
    Answer, BASES, CONTEXTS, DIETARY, EMOTIONS, MEAL_TYPES, METHODS,
    PROTEINS, SENSORY_FIELDS, Question,
)
from .cuisines import CUISINE_LIST, CUISINES, STAR_INGREDIENTS

MEAT = ["chicken", "beef", "pork", "lamb", "fish", "shrimp"]

SENSORY_ADJ = [
    ("warmth", "warm"), ("richness", "rich"), ("freshness", "fresh"),
    ("creaminess", "creamy"), ("crunchiness", "crunchy"), ("sweetness", "sweet"),
    ("saltiness", "salty"), ("sourness", "sour"), ("bitterness", "bitter"),
    ("umami", "savory"), ("spiciness", "spicy"),
]

EMOTION_LABEL = {
    "comfort": "comfort food", "celebratory": "something celebratory",
    "refreshing": "something light & fresh", "indulgent": "something indulgent",
    "light": "something light & simple", "hearty": "something hearty",
    "adventurous": "something adventurous", "nostalgic": "a nostalgic classic",
    "soothing": "something soothing", "energizing": "something energizing",
    "fun": "something fun",
}

CONTEXT_LABEL = {
    "winter": "winter comfort", "summer": "a summer day", "rainy": "a rainy day",
    "late-night": "late night", "quick-lunch": "a quick lunch",
    "family-meal": "a family meal", "dinner-party": "a dinner party",
    "workout-recovery": "post-workout", "hangover": "hangover fuel",
    "sick-day": "feeling under the weather", "brunch": "brunch",
    "date-night": "a date night", "study": "studying",
    "weekend": "a lazy weekend",
}


def _build_bank() -> list:
    bank = []
    seq = 0

    def add_binary(cat, key, text, trait):
        nonlocal seq
        seq += 1
        bank.append(Question(
            id=f"{cat}.{key}.{seq:04d}", category=cat, trait_key=key, text=text,
            kind="binary",
            answers=[
                Answer(id="yes", label="Yes", trait=trait),
                Answer(id="no", label="No"),
                Answer(id="unsure", label="Not sure"),
            ],
        ))

    def add_multi(cat, key, text, answers):
        nonlocal seq
        seq += 1
        built = [Answer(id=a[0], label=a[1], trait=a[2]) for a in answers]
        built.append(Answer(id="none", label="None of these / no preference"))
        bank.append(Question(
            id=f"{cat}.{key}.{seq:04d}", category=cat, trait_key=key, text=text,
            kind="multi", answers=built,
        ))

    # ------------------------------------------------------------------
    # 1. Sensory craving / avoiding
    # ------------------------------------------------------------------
    for field, adj in SENSORY_ADJ:
        high = numeric(field, min_=0.55)
        for text in (f"Are you craving something {adj}?",
                     f"Does something {adj} sound good?",
                     f"How about something {adj}?"):
            add_binary("sensory", f"want.{field}.high", text, high)
        add_binary("sensory", f"want.{field}.mild",
                   f"Do you want something mildly {adj}?", numeric(field, 0.2, 0.5))
        add_binary("sensory", f"want.{field}.intense",
                   f"Are you in the mood for something intensely {adj}?",
                   numeric(field, min_=0.65))
        add_binary("sensory", f"avoid.{field}",
                   f"Do you want to avoid something {adj}?", not_trait(high))

    add_multi("sensory", "flavor.profile",
              "Which flavor profile are you most craving?", [
        ("savory", "Savory / umami", numeric("umami", min_=0.6)),
        ("spicy", "Spicy", numeric("spiciness", min_=0.55)),
        ("sweet", "Sweet", numeric("sweetness", min_=0.55)),
        ("sour", "Sour / tangy", numeric("sourness", min_=0.5)),
        ("fresh", "Fresh & herbaceous",
         and_traits(numeric("freshness", min_=0.6), numeric("warmth", max_=0.55))),
        ("rich-creamy", "Rich & creamy",
         and_traits(numeric("creaminess", min_=0.55), numeric("richness", min_=0.5))),
        ("salty-crunchy", "Salty & crunchy",
         and_traits(numeric("saltiness", min_=0.55), numeric("crunchiness", min_=0.5))),
        ("bitter", "Bitter", numeric("bitterness", min_=0.5)),
        ("light", "Light & delicate",
         and_traits(numeric("freshness", min_=0.4), numeric("richness", max_=0.45),
                    numeric("spiciness", max_=0.3))),
    ])

    # ------------------------------------------------------------------
    # 2. Mood / emotion
    # ------------------------------------------------------------------
    for e in EMOTIONS:
        t = has_any("emotions", [e])
        lab = EMOTION_LABEL[e]
        for text in (f"Are you in the mood for {lab}?",
                     f"Does {lab} sound good today?",
                     f"How about {lab}?"):
            add_binary("emotion", f"want.{e}", text, t)
        add_binary("emotion", f"avoid.{e}", f"Do you want to avoid {lab}?", not_trait(t))

    add_multi("seed", "seed.mood", "How are you feeling right now?",
              [(e, EMOTION_LABEL[e].capitalize(), has_any("emotions", [e]))
               for e in EMOTIONS])

    # ------------------------------------------------------------------
    # 2b. Nuanced mood -- feelings expressed the way people actually think
    # about a meal, each answer mapping onto multiple traits at once.
    # ------------------------------------------------------------------
    for key, text, trait in [
        ("mood.comfort-hug", "Do you want food that feels like a hug?",
         and_traits(has_any("emotions", ["comfort"]),
                    has_any("emotions", ["soothing"]))),
        ("mood.warm-cozy", "Are you craving something warm and cozy?",
         and_traits(numeric("warmth", min_=0.6),
                    has_any("emotions", ["comfort"]))),
        ("mood.bright-peppy", "Do you want something bright that lifts you up?",
         and_traits(has_any("emotions", ["energizing"]),
                    numeric("freshness", min_=0.5))),
        ("mood.treat", "Do you want to treat yourself?",
         or_traits(has_any("emotions", ["indulgent"]),
                   has_any("emotions", ["celebratory"]))),
        ("mood.nostalgia", "Craving something nostalgic, like from childhood?",
         has_any("emotions", ["nostalgic"])),
        ("mood.reset", "Want something that feels like a clean reset?",
         and_traits(has_any("emotions", ["refreshing"]),
                    numeric("freshness", min_=0.55))),
        ("mood.playful", "Are you feeling playful and adventurous?",
         and_traits(has_any("emotions", ["fun"]),
                    has_any("emotions", ["adventurous"]))),
        ("mood.under-weather", "Feeling under the weather -- need soothing?",
         or_traits(has_any("contexts", ["sick-day"]),
                   has_any("emotions", ["soothing"]))),
        ("mood.reward", "Need a reward after a long day?",
         or_traits(has_any("emotions", ["indulgent"]),
                   has_any("contexts", ["late-night"]))),
        ("mood.simple-calm", "Want something simple and calming?",
         and_traits(has_any("emotions", ["soothing"]),
                    numeric("richness", max_=0.45))),
        ("mood.hearty-fulfill", "Want to feel properly fed and satisfied?",
         and_traits(has_any("emotions", ["hearty"]),
                    numeric("richness", min_=0.55))),
        ("mood.excited", "In the mood for something that feels like an event?",
         or_traits(has_any("emotions", ["celebratory"]),
                   has_any("emotions", ["adventurous"]))),
    ]:
        add_binary("emotion", key, text, trait)

    add_multi("emotion", "mood.feeling", "How do you want to FEEL after this meal?", [
        ("grounded", "Grounded & calm",
         and_traits(has_any("emotions", ["comfort"]), has_any("emotions", ["soothing"]))),
        ("alert", "Wide awake",
         and_traits(has_any("emotions", ["energizing"]), has_any("emotions", ["refreshing"]))),
        ("pampered", "Pampered",
         and_traits(has_any("emotions", ["indulgent"]), numeric("creaminess", min_=0.5))),
        ("cozy", "Cozy & warm",
         and_traits(has_any("emotions", ["comfort"]), numeric("warmth", min_=0.55))),
        ("excited", "Excited & buzzing",
         and_traits(has_any("emotions", ["fun"]), has_any("emotions", ["adventurous"]))),
    ])

    add_multi("emotion", "mood.tone", "What emotional tone are you craving?", [
        ("nostalgia", "Nostalgia", has_any("emotions", ["nostalgic"])),
        ("comfort-blanket", "Comfort blanket",
         and_traits(has_any("emotions", ["comfort"]), has_any("emotions", ["soothing"]))),
        ("celebration", "Celebration", has_any("emotions", ["celebratory"])),
        ("adventure", "Adventure", has_any("emotions", ["adventurous"])),
        ("reset", "Clean reset",
         and_traits(has_any("emotions", ["refreshing"]), numeric("richness", max_=0.4))),
        ("pamper", "Pampering",
         and_traits(has_any("emotions", ["indulgent"]), numeric("creaminess", min_=0.5))),
    ])

    add_multi("emotion", "mood.energy", "What energy level fits right now?", [
        ("low", "Low & slow",
         and_traits(has_any("emotions", ["soothing"]), numeric("warmth", min_=0.5))),
        ("steady", "Steady & solid", has_any("emotions", ["hearty"])),
        ("bright", "Bright & peppy", has_any("emotions", ["energizing"])),
        ("electric", "Electric",
         and_traits(has_any("emotions", ["adventurous"]), numeric("spiciness", min_=0.5))),
    ])

    add_multi("emotion", "mood.vibe", "What's the vibe of the meal tonight?", [
        ("hug", "A comforting hug",
         and_traits(has_any("emotions", ["comfort"]), has_any("emotions", ["soothing"]))),
        ("fresh", "Clean & fresh",
         and_traits(has_any("emotions", ["refreshing"]), numeric("freshness", min_=0.5))),
        ("hearty", "Warm & hearty",
         and_traits(has_any("emotions", ["hearty"]), numeric("warmth", min_=0.55))),
        ("exciting", "Bright & exciting",
         or_traits(has_any("emotions", ["adventurous"]), has_any("emotions", ["fun"]))),
        ("rich", "Rich & indulgent",
         and_traits(has_any("emotions", ["indulgent"]), numeric("richness", min_=0.55))),
    ])

    add_binary("emotion", "mood.umami-linger",
               "Craving something that lingers on the tongue?",
               and_traits(numeric("umami", min_=0.55), numeric("richness", min_=0.5)))
    add_binary("emotion", "mood.savory-comfort",
               "Want savory comfort, not sweet?",
               and_traits(has_any("emotions", ["comfort"]),
                          not_trait(boolean("is_sweet"))))

    # ------------------------------------------------------------------
    # 3. Context / occasion
    # ------------------------------------------------------------------
    for c in CONTEXTS:
        t = has_any("contexts", [c])
        lab = CONTEXT_LABEL[c]
        for text in (f"Is this for {lab}?",
                     f"Does {lab} sound like the occasion?",
                     f"Is {lab} a factor today?"):
            add_binary("context", f"want.{c}", text, t)
        add_binary("context", f"avoid.{c}", f"Should I rule out {lab}?", not_trait(t))

    add_multi("seed", "seed.occasion", "What's the occasion?",
              [(c, CONTEXT_LABEL[c].capitalize(), has_any("contexts", [c]))
               for c in CONTEXTS])

    # ------------------------------------------------------------------
    # 4. Cuisine
    # ------------------------------------------------------------------
    for cid in CUISINE_LIST:
        label = CUISINES[cid]["label"]
        t = has_any("cuisines", [cid])
        for text in (f"Do you feel like {label} food?",
                     f"How about {label} today?",
                     f"Are you craving {label} flavors?"):
            add_binary("cuisine", f"want.{cid}", text, t)
        add_binary("cuisine", f"avoid.{cid}", f"Want to avoid {label} food?", not_trait(t))

    add_multi("seed", "seed.cuisine", "Are you leaning toward any cuisine?",
              [(cid, CUISINES[cid]["label"], has_any("cuisines", [cid]))
               for cid in CUISINE_LIST])

    # ------------------------------------------------------------------
    # 5. Protein
    # ------------------------------------------------------------------
    for p in PROTEINS:
        if p == "none":
            continue
        t = has_any("proteins", [p])
        for text in (f"Does {p} sound good?",
                     f"In the mood for {p}?",
                     f"Any {p}?"):
            add_binary("protein", f"want.{p}", text, t)
        add_binary("protein", f"avoid.{p}", f"Want to skip {p}?", not_trait(t))

    add_multi("seed", "seed.protein", "What protein are you craving?",
              [(p, p.capitalize(), has_any("proteins", [p])) for p in PROTEINS])

    # ------------------------------------------------------------------
    # 6. Base / starch
    # ------------------------------------------------------------------
    for b in BASES:
        if b == "none":
            continue
        t = has_any("bases", [b])
        for text in (f"Does {b} sound good?",
                     f"How about {b}?"):
            add_binary("base", f"want.{b}", text, t)
        add_binary("base", f"avoid.{b}", f"Do you want to avoid {b}?", not_trait(t))

    add_multi("seed", "seed.base", "What base are you leaning toward?",
              [(b, b.capitalize(), has_any("bases", [b])) for b in BASES])

    # ------------------------------------------------------------------
    # 7. Cooking method
    # ------------------------------------------------------------------
    for m in METHODS:
        t = has_any("methods", [m])
        for text in (f"In the mood for {m} food?",
                     f"Would {m} work?"):
            add_binary("method", f"want.{m}", text, t)
        add_binary("method", f"avoid.{m}", f"Want to avoid {m} food?", not_trait(t))

    add_multi("method", "method.choice", "How would you like it cooked?",
              [(m, m.capitalize(), has_any("methods", [m])) for m in METHODS])

    # ------------------------------------------------------------------
    # 8. Meal type
    # ------------------------------------------------------------------
    for mt in MEAL_TYPES:
        t = has_any("meal_types", [mt])
        for text in (f"Do you want a {mt}?",
                     f"Feeling {mt}?"):
            add_binary("meal", f"want.{mt}", text, t)
        add_binary("meal", f"avoid.{mt}", f"Do you want to avoid a {mt}?", not_trait(t))

    add_multi("seed", "seed.meal", "Which meal is this for?",
              [(mt, mt.capitalize(), has_any("meal_types", [mt])) for mt in MEAL_TYPES])

    # ------------------------------------------------------------------
    # 9. Dietary
    # ------------------------------------------------------------------
    for d in DIETARY:
        t = has_any("dietary", [d])
        for text in (f"Are you looking for {d} options?",
                     f"Do you need {d}?"):
            add_binary("diet", f"want.{d}", text, t)

    add_multi("seed", "seed.diet", "Any key dietary need?",
              [(d, d.capitalize(), has_any("dietary", [d])) for d in DIETARY])

    # ------------------------------------------------------------------
    # 10. Time & effort
    # ------------------------------------------------------------------
    for mins in (15, 30, 45, 60, 90):
        add_binary("time", f"under.{mins}",
                   f"Do you want something under {mins} minutes?",
                   numeric("cook_minutes", max_=mins, soft=5))

    add_multi("seed", "seed.time", "How much time do you have?",
              [("lt15", "Under 15 min", numeric("cook_minutes", max_=15, soft=5)),
               ("15-30", "15-30 min", numeric("cook_minutes", 15, 30, soft=5)),
               ("30-45", "30-45 min", numeric("cook_minutes", 30, 45, soft=5)),
               ("45-60", "45-60 min", numeric("cook_minutes", 45, 60, soft=5)),
               ("60-90", "60-90 min", numeric("cook_minutes", 60, 90, soft=5)),
               ("90+", "90+ min", numeric("cook_minutes", min_=90, soft=5))])

    add_multi("time", "time.range", "How much time do you have?",
              [("lt15", "Under 15 min", numeric("cook_minutes", max_=15, soft=5)),
               ("15-30", "15-30 min", numeric("cook_minutes", 15, 30, soft=5)),
               ("30-45", "30-45 min", numeric("cook_minutes", 30, 45, soft=5)),
               ("45-60", "45-60 min", numeric("cook_minutes", 45, 60, soft=5)),
               ("60-90", "60-90 min", numeric("cook_minutes", 60, 90, soft=5)),
               ("90+", "90+ min", numeric("cook_minutes", min_=90, soft=5))])

    add_binary("effort", "easy", "Do you want something easy to make?",
               numeric("difficulty", max_=1, soft=0.5))
    add_binary("effort", "ambitious", "Are you up for something ambitious?",
               numeric("difficulty", min_=2, soft=0.5))
    add_multi("effort", "effort.level", "How much effort tonight?",
              [("easy", "Easy", numeric("difficulty", max_=1, soft=0.5)),
               ("medium", "Medium effort", numeric("difficulty", 2, 2, soft=0.5)),
               ("ambitious", "Ambitious", numeric("difficulty", min_=3, soft=0.5))])

    # ------------------------------------------------------------------
    # 11. Structural
    # ------------------------------------------------------------------
    add_binary("struct", "broth", "Do you want something brothy?", boolean("has_broth"))
    add_binary("struct", "noodle", "Are you in the mood for noodles?", boolean("is_noodle"))
    add_binary("struct", "cold", "Do you want something cold?", boolean("is_cold"))
    add_binary("struct", "sweet", "Are you craving something sweet?", boolean("is_sweet"))
    add_binary("struct", "fried", "Do you want something fried?", has_any("methods", ["fried"]))
    add_binary("struct", "raw", "Are you open to raw / uncooked?", has_any("methods", ["raw"]))
    add_binary("struct", "grill", "Craving grill marks?", has_any("methods", ["grilled"]))
    add_binary("struct", "one-pot", "Do you want a one-pot meal?", boolean("is_one_pot"))
    add_binary("struct", "hands", "Do you want to eat with your hands?",
               or_traits(has_any("bases", ["bread", "tortilla"]),
                         has_any("methods", ["fried"])))
    add_binary("struct", "veg", "Must it be vegetarian?", boolean("vegetarian"))

    add_multi("struct", "struct.shape", "What's the shape of the meal?", [
        ("broth", "Broth / soup",
         or_traits(boolean("has_broth"), has_any("methods", ["simmered"]))),
        ("salad", "Fresh salad",
         and_traits(has_any("methods", ["raw"]), has_any("bases", ["greens"]))),
        ("hearty", "Hearty main", numeric("richness", min_=0.55)),
        ("sandwich", "Sandwich / wrap",
         has_any("bases", ["bread", "tortilla"])),
        ("snack", "Snack / small plates", has_any("meal_types", ["snack"])),
    ])

    add_multi("struct", "struct.temp", "What temperature sounds right?", [
        ("cold", "Cold", numeric("warmth", max_=0.3)),
        ("room", "Room temp", numeric("warmth", 0.25, 0.5)),
        ("hot", "Hot", numeric("warmth", min_=0.55)),
    ])

    add_multi("struct", "struct.spice", "How much heat can you take?", [
        ("mild", "Mild", numeric("spiciness", max_=0.3)),
        ("medium", "Medium", numeric("spiciness", 0.3, 0.55)),
        ("hot", "Hot", numeric("spiciness", min_=0.55)),
    ])

    # ------------------------------------------------------------------
    # 12. Star ingredients
    # ------------------------------------------------------------------
    for ing in STAR_INGREDIENTS:
        t = has_any("ingredients", [ing])
        for text in (f"Does {ing} sound good as the star?",
                     f"How about something with {ing}?"):
            add_binary("ingredient", f"want.{ing}", text, t)

    for ing in ("peanut", "cheese", "chocolate", "mushroom", "garlic", "onion", "fish-sauce"):
        add_binary("ingredient", f"avoid.{ing}",
                   f"Want to avoid {ing}?", not_trait(has_any("ingredients", [ing])))

    # ------------------------------------------------------------------
    # 13. Combined / multi-attribute questions
    # ------------------------------------------------------------------
    combos = [
        ("spicy-comfort", "Are you craving something spicy AND comforting?",
         and_traits(numeric("spiciness", min_=0.55), has_any("emotions", ["comfort"]))),
        ("fresh-light", "Do you want something fresh and light?",
         and_traits(numeric("freshness", min_=0.6), numeric("richness", max_=0.4))),
        ("creamy-sweet", "Something creamy and sweet?",
         and_traits(numeric("creaminess", min_=0.55), numeric("sweetness", min_=0.5))),
        ("warm-brothy", "Warm and brothy?",
         and_traits(numeric("warmth", min_=0.6), boolean("has_broth"))),
        ("hearty-meaty", "Hearty and meaty?",
         and_traits(numeric("richness", min_=0.6), has_any("proteins", MEAT))),
        ("adventurous", "Something adventurous and new?",
         has_any("emotions", ["adventurous"])),
        ("crunchy-fresh", "Crunchy and fresh?",
         and_traits(numeric("crunchiness", min_=0.5), numeric("freshness", min_=0.5))),
        ("rich-indulgent", "Rich and indulgent?",
         and_traits(numeric("richness", min_=0.6), has_any("emotions", ["indulgent"]))),
        ("workout", "For post-workout recovery?",
         has_any("contexts", ["workout-recovery"])),
        ("sick-day", "Something soothing for a rough day?",
         has_any("contexts", ["sick-day"])),
        ("spicy-sour", "Spicy and sour?",
         and_traits(numeric("spiciness", min_=0.55), numeric("sourness", min_=0.5))),
        ("savory-brothy", "Savory and brothy?",
         and_traits(numeric("umami", min_=0.6), boolean("has_broth"))),
        ("cold-refreshing", "Cold and refreshing?",
         and_traits(numeric("warmth", max_=0.3), has_any("emotions", ["refreshing"]))),
        ("crispy-fried", "Crispy and fried?",
         and_traits(numeric("crunchiness", min_=0.6), has_any("methods", ["fried"]))),
        ("sweet-dessert", "Something sweet for dessert?",
         and_traits(numeric("sweetness", min_=0.6), boolean("is_sweet"))),
        ("quick-light", "Quick and light?",
         and_traits(numeric("cook_minutes", max_=30, soft=5), numeric("richness", max_=0.45))),
        ("family", "Family-friendly?",
         has_any("contexts", ["family-meal"])),
        ("impressive", "Do you need to impress someone?",
         or_traits(has_any("contexts", ["dinner-party"]),
                   has_any("emotions", ["celebratory"]))),
        ("healthy-protein", "Healthy and protein-forward?",
         and_traits(has_any("dietary", ["high-protein"]), numeric("richness", max_=0.55))),
        ("date-night", "For a date night?",
         has_any("contexts", ["date-night"])),
        ("breakfast-y", "Something breakfast-y?",
         has_any("meal_types", ["breakfast"])),
        ("late-night", "A late-night craving?",
         has_any("contexts", ["late-night"])),
        ("hangover", "A hangover cure?",
         has_any("contexts", ["hangover"])),
        ("brothy-noodle", "A brothy noodle soup?",
         and_traits(boolean("has_broth"), boolean("is_noodle"))),
        ("cold-creamy", "Cold and creamy?",
         and_traits(numeric("warmth", max_=0.3), numeric("creaminess", min_=0.55))),
        ("spicy-meat", "Spicy and meaty?",
         and_traits(numeric("spiciness", min_=0.55), has_any("proteins", MEAT))),
        ("fresh-veggie", "Fresh and veggie-forward?",
         and_traits(numeric("freshness", min_=0.5), has_any("dietary", ["vegetarian"]))),
        ("warm-hearty", "Warm and hearty?",
         and_traits(numeric("warmth", min_=0.6), numeric("richness", min_=0.5))),
        ("crunchy-salty", "Crunchy and salty?",
         and_traits(numeric("crunchiness", min_=0.5), numeric("saltiness", min_=0.5))),
        ("light-dinner", "A light dinner?",
         and_traits(numeric("richness", max_=0.45), has_any("meal_types", ["dinner"]))),
        ("breakfast-sweet", "Something sweet for breakfast?",
         and_traits(boolean("is_sweet"), has_any("meal_types", ["breakfast"]))),
        ("soupy-winter", "A cozy soup for a winter day?",
         and_traits(boolean("has_broth"), has_any("contexts", ["winter"]))),
        ("noodle-summer", "Cold noodles for summer?",
         and_traits(boolean("is_noodle"), numeric("warmth", max_=0.4))),
        ("rich-sweet-dessert", "Rich and sweet for dessert?",
         and_traits(numeric("richness", min_=0.5), boolean("is_sweet"))),
        ("grilled-meat", "Something grilled and meaty?",
         and_traits(has_any("methods", ["grilled"]), has_any("proteins", MEAT))),
        ("spicy-seafood", "Spicy seafood?",
         and_traits(numeric("spiciness", min_=0.5),
                    has_any("proteins", ["fish", "shrimp"]))),
        ("creamy-soup", "A creamy soup?",
         and_traits(boolean("has_broth"), numeric("creaminess", min_=0.5))),
        ("sticky-sweet", "Sticky and sweet?",
         and_traits(numeric("sweetness", min_=0.55), numeric("richness", min_=0.4))),
        ("umami-heavy", "Umami-forward?",
         numeric("umami", min_=0.65)),
    ]
    for key, text, trait in combos:
        add_binary("combo", key, text, trait)

    # ------------------------------------------------------------------
    # 14. Serving size & other multi questions
    # ------------------------------------------------------------------
    add_multi("serving", "serving.size", "How many people are you feeding?", [
        ("just-me", "Just me", numeric("servings", max_=1, soft=1)),
        ("two", "Two", numeric("servings", 2, 2, soft=1)),
        ("three-four", "3-4", numeric("servings", 3, 4, soft=1)),
        ("five-plus", "5+", numeric("servings", min_=5, soft=1)),
    ])

    add_multi("time", "time.pace", "Quick fix or a project?", [
        ("quick", "Quick (<30 min)", numeric("cook_minutes", max_=30, soft=5)),
        ("casual", "Casual (30-60 min)", numeric("cook_minutes", 30, 60, soft=5)),
        ("ambitious", "Ambitious (60+ min)", numeric("cook_minutes", min_=60, soft=5)),
    ])

    add_multi("struct", "struct.sweet-savory", "Sweet or savory?", [
        ("sweet", "Sweet", boolean("is_sweet")),
        ("savory", "Savory", not_trait(boolean("is_sweet"))),
        ("mix", "A bit of both", None),
    ])

    add_multi("combo", "combo.adventurousness", "How adventurous are you feeling?", [
        ("familiar", "Familiar & cozy",
         or_traits(has_any("emotions", ["comfort"]), has_any("emotions", ["light"]))),
        ("new", "Something new",
         or_traits(has_any("emotions", ["adventurous"]), has_any("emotions", ["fun"]))),
        ("bold", "Bold & exciting",
         and_traits(has_any("emotions", ["adventurous"]), numeric("spiciness", min_=0.5))),
    ])

    # ------------------------------------------------------------------
    # 15. Cuisine x protein combination cues
    # ------------------------------------------------------------------
    for cid in CUISINE_LIST:
        label = CUISINES[cid]["label"]
        for p in CUISINES[cid]["proteins"][:3]:
            if p == "none":
                continue
            add_binary("cuisine", f"combo.{cid}.{p}",
                       f"Do you feel like {p} {label}?",
                       and_traits(has_any("cuisines", [cid]), has_any("proteins", [p])))

    return bank


_questions = None


def load_questions() -> list:
    global _questions
    if _questions is None:
        _questions = _build_bank()
        assert len(_questions) >= 500, \
            f"question bank too small: {len(_questions)} (need >= 500)"
        ids = [q.id for q in _questions]
        assert len(set(ids)) == len(ids), "duplicate question ids"
    return _questions


if __name__ == "__main__":
    qs = load_questions()
    cats = {}
    for q in qs:
        cats[q.category] = cats.get(q.category, 0) + 1
    print(f"question bank: {len(qs)} questions")
    for k, v in sorted(cats.items()):
        print(f"  {k:12s} {v}")
