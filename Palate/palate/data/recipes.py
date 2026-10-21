"""Recipe database.

Two layers:
  1. ~100 hand-curated classics with full, meaningful metadata.
  2. ~340 procedurally generated dishes sampled from coherent cuisine priors.

The generated layer exists so the Bayesian engine has a large search space to
navigate; the curated layer gives the demo and CLI recognizable dishes.
"""

from __future__ import annotations

import random

from .cuisines import CUISINES, METHOD_COOK, METHOD_DIFF, SUFFIX
from ..types import SENSORY_FIELDS, Recipe, derive

MEAT = {"chicken", "beef", "pork", "lamb", "fish", "shrimp"}


def _build(id, name, cuisines, o, source="curated") -> Recipe:
    base = CUISINES[cuisines[0]]

    def pick(key, default):
        return list(o.get(key, default))

    meal_types = pick("meal_types", base["meal_types"])
    methods = pick("methods", base["methods"])
    proteins = pick("proteins", base["proteins"])
    bases = pick("bases", base["bases"])
    ingredients = pick("ingredients", base["ingredients"])
    dietary = pick("dietary", base["dietary"])
    emotions = pick("emotions", base["emotions"])
    contexts = pick("contexts", base["contexts"])

    sensory = {}
    for f in SENSORY_FIELDS:
        if o.get("sensory") and f in o["sensory"]:
            sensory[f] = o["sensory"][f]
        else:
            sensory[f] = base["flavor"].get(f, 0.5)

    recipe = Recipe(
        id=id, name=name, cuisines=cuisines,
        meal_types=meal_types, methods=methods, proteins=proteins,
        bases=bases, ingredients=ingredients, dietary=dietary,
        emotions=emotions, contexts=contexts, sensory=sensory,
        cook_minutes=int(o.get("cook_minutes", 40)),
        difficulty=int(o.get("difficulty", 2)),
        servings=int(o.get("servings", 2)),
        source=source,
    )
    return derive(recipe)


def _clamp(x, lo=0.05, hi=0.95):
    return max(lo, min(hi, x))


# ---------------------------------------------------------------------------
# Hand-curated classics
# ---------------------------------------------------------------------------

# fields per dish: meal_types, methods, proteins, bases, emotions, contexts,
# optional ingredients/dietary/sensory/cook_minutes/difficulty
CURATED = [
    ("pho", "Pho", ["vietnamese"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["beef"], bases=["noodles"],
        ingredients=["cilantro", "mint", "lime", "fish-sauce"],
        emotions=["comfort", "soothing", "refreshing"], contexts=["winter", "sick-day", "rainy"],
        sensory=dict(warmth=0.80, umami=0.85, spiciness=0.50, sourness=0.55, freshness=0.70, richness=0.35),
        cook_minutes=120, difficulty=2)),
    ("ramen", "Tonkotsu Ramen", ["japanese"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["pork"], bases=["noodles"],
        ingredients=["miso", "egg", "scallion"],
        emotions=["comfort", "indulgent", "soothing"], contexts=["late-night", "winter"],
        sensory=dict(warmth=0.80, umami=0.90, richness=0.75, creaminess=0.45, spiciness=0.15, saltiness=0.75),
        cook_minutes=90, difficulty=2)),
    ("laksa", "Laksa", ["malaysian"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["shrimp"], bases=["noodles"],
        ingredients=["coconut", "chili", "lemongrass"],
        emotions=["adventurous", "indulgent"], contexts=["rainy", "dinner-party"],
        sensory=dict(warmth=0.80, spiciness=0.80, creaminess=0.70, richness=0.70, umami=0.70, freshness=0.50),
        cook_minutes=60, difficulty=2)),
    ("paya", "Paya", ["indian"], dict(
        meal_types=["dinner"], methods=["slow-cooked"], proteins=["lamb"], bases=["none"],
        ingredients=["ginger", "garlic", "cumin"],
        emotions=["hearty", "comfort", "adventurous"], contexts=["winter", "family-meal"],
        sensory=dict(warmth=0.85, richness=0.80, umami=0.70, spiciness=0.60),
        cook_minutes=300, difficulty=3)),
    ("chicken-noodle-soup", "Chicken Noodle Soup", ["american"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["chicken"], bases=["noodles"],
        ingredients=["onion", "garlic"],
        emotions=["comfort", "soothing", "nostalgic"], contexts=["sick-day", "winter", "late-night"],
        sensory=dict(warmth=0.80, richness=0.45, umami=0.55, saltiness=0.60),
        cook_minutes=60, difficulty=1)),
    ("tom-yum", "Tom Yum", ["thai"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["shrimp"], bases=["none"],
        ingredients=["lemongrass", "chili", "lime", "mushroom"],
        emotions=["adventurous", "energizing"], contexts=["rainy", "summer"],
        sensory=dict(spiciness=0.90, sourness=0.80, freshness=0.70, warmth=0.75, umami=0.55),
        cook_minutes=30, difficulty=1)),
    ("bibimbap", "Bibimbap", ["korean"], dict(
        meal_types=["dinner"], methods=["stir-fried"], proteins=["beef"], bases=["rice"],
        ingredients=["egg", "sesame", "gochujang", "scallion"],
        emotions=["hearty", "energizing", "adventurous"], contexts=["quick-lunch", "family-meal"],
        sensory=dict(crunchiness=0.50, umami=0.60, spiciness=0.50, freshness=0.60),
        cook_minutes=40, difficulty=2)),
    ("kimchi-jjigae", "Kimchi Jjigae", ["korean"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["tofu"], bases=["rice"],
        ingredients=["kimchi", "tofu", "gochujang"],
        emotions=["comfort", "soothing", "hearty"], contexts=["winter", "late-night", "hangover"],
        sensory=dict(spiciness=0.70, sourness=0.70, umami=0.70, warmth=0.80, richness=0.50),
        cook_minutes=35, difficulty=1)),
    ("pad-thai", "Pad Thai", ["thai"], dict(
        meal_types=["dinner"], methods=["stir-fried"], proteins=["shrimp"], bases=["noodles"],
        ingredients=["peanut", "lime", "bean-sprout", "egg"],
        emotions=["indulgent", "fun"], contexts=["late-night", "date-night"],
        sensory=dict(sweetness=0.55, sourness=0.55, spiciness=0.45, umami=0.60, crunchiness=0.40),
        cook_minutes=25, difficulty=2)),
    ("green-curry", "Thai Green Curry", ["thai"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["chicken"], bases=["rice"],
        ingredients=["coconut", "chili", "basil"],
        emotions=["indulgent", "adventurous"], contexts=["rainy", "dinner-party"],
        sensory=dict(spiciness=0.80, creaminess=0.70, richness=0.60, freshness=0.50),
        cook_minutes=40, difficulty=2)),
    ("tikka-masala", "Chicken Tikka Masala", ["indian"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["chicken"], bases=["rice"],
        ingredients=["garam-masala", "yogurt", "ginger"],
        emotions=["comfort", "indulgent"], contexts=["dinner-party", "family-meal"],
        sensory=dict(creaminess=0.70, richness=0.65, spiciness=0.55, umami=0.60),
        cook_minutes=45, difficulty=2)),
    ("butter-chicken", "Butter Chicken", ["indian"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["chicken"], bases=["bread"],
        ingredients=["butter", "yogurt", "garam-masala"],
        emotions=["indulgent", "comfort", "nostalgic"], contexts=["dinner-party", "winter"],
        sensory=dict(creaminess=0.80, richness=0.80, sweetness=0.50, spiciness=0.40),
        cook_minutes=60, difficulty=2)),
    ("chana-masala", "Chana Masala", ["indian"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["beans"], bases=["bread"],
        ingredients=["cumin", "tomato", "garlic"],
        emotions=["comfort", "soothing"], contexts=["family-meal", "winter"],
        sensory=dict(spiciness=0.60, richness=0.50, umami=0.55, sourness=0.50),
        cook_minutes=45, difficulty=2, dietary=["vegetarian", "gluten-free"])),
    ("palak-paneer", "Palak Paneer", ["indian"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["paneer"], bases=["bread"],
        ingredients=["spinach", "garam-masala", "yogurt"],
        emotions=["comfort", "nostalgic"], contexts=["family-meal"],
        sensory=dict(creaminess=0.60, richness=0.50, bitterness=0.30, spiciness=0.45),
        cook_minutes=40, difficulty=2, dietary=["vegetarian", "gluten-free"])),
    ("sushi", "Sushi", ["japanese"], dict(
        meal_types=["dinner"], methods=["raw"], proteins=["fish"], bases=["rice"],
        ingredients=["nori", "sesame", "soy"],
        emotions=["refreshing", "light", "celebratory"], contexts=["summer", "date-night", "quick-lunch"],
        sensory=dict(freshness=0.90, warmth=0.20, umami=0.70, saltiness=0.55),
        cook_minutes=45, difficulty=3, dietary=["high-protein"])),
    ("tempura", "Tempura", ["japanese"], dict(
        meal_types=["dinner"], methods=["fried"], proteins=["shrimp"], bases=["none"],
        ingredients=["sesame"],
        emotions=["fun", "indulgent", "refreshing"], contexts=["dinner-party", "weekend"],
        sensory=dict(crunchiness=0.85, freshness=0.50, saltiness=0.50),
        cook_minutes=35, difficulty=2)),
    ("teriyaki-chicken", "Teriyaki Chicken", ["japanese"], dict(
        meal_types=["dinner"], methods=["grilled"], proteins=["chicken"], bases=["rice"],
        ingredients=["soy", "sesame", "ginger"],
        emotions=["comfort"], contexts=["quick-lunch", "family-meal"],
        sensory=dict(sweetness=0.55, saltiness=0.65, umami=0.60),
        cook_minutes=25, difficulty=1)),
    ("katsu-curry", "Katsu Curry", ["japanese"], dict(
        meal_types=["dinner"], methods=["fried"], proteins=["pork"], bases=["rice"],
        ingredients=["curry", "onion"],
        emotions=["comfort", "hearty", "nostalgic"], contexts=["late-night", "winter", "family-meal"],
        sensory=dict(crunchiness=0.70, richness=0.60, umami=0.65, sweetness=0.45),
        cook_minutes=50, difficulty=2)),
    ("caesar-salad", "Caesar Salad", ["american"], dict(
        meal_types=["lunch"], methods=["raw"], proteins=["chicken"], bases=["greens"],
        ingredients=["parmesan", "olive-oil"],
        emotions=["light", "refreshing", "comfort"], contexts=["quick-lunch"],
        sensory=dict(umami=0.60, saltiness=0.65, creaminess=0.40, crunchiness=0.45),
        cook_minutes=20, difficulty=1)),
    ("greek-salad", "Greek Salad", ["greek"], dict(
        meal_types=["lunch"], methods=["raw"], proteins=["none"], bases=["greens"],
        ingredients=["feta", "olive-oil", "lemon", "cucumber"],
        emotions=["refreshing", "light"], contexts=["summer", "quick-lunch"],
        sensory=dict(sourness=0.60, freshness=0.85, warmth=0.30, creaminess=0.40, saltiness=0.60),
        cook_minutes=10, difficulty=1, dietary=["vegetarian", "gluten-free"])),
    ("caprese", "Caprese", ["italian"], dict(
        meal_types=["snack"], methods=["raw"], proteins=["none"], bases=["none"],
        ingredients=["tomato", "basil", "mozzarella"],
        emotions=["refreshing", "light", "nostalgic"], contexts=["summer", "date-night"],
        sensory=dict(freshness=0.80, creaminess=0.40, sweetness=0.40, sourness=0.35),
        cook_minutes=10, difficulty=1, dietary=["vegetarian"])),
    ("pizza-margherita", "Pizza Margherita", ["italian"], dict(
        meal_types=["dinner"], methods=["baked"], proteins=["none"], bases=["bread"],
        ingredients=["tomato", "mozzarella", "basil"],
        emotions=["comfort", "fun"], contexts=["family-meal", "weekend", "date-night"],
        sensory=dict(creaminess=0.50, umami=0.55, richness=0.50),
        cook_minutes=40, difficulty=2, dietary=["vegetarian"])),
    ("carbonara", "Carbonara", ["italian"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["egg"], bases=["pasta"],
        ingredients=["parmesan", "pork"],
        emotions=["indulgent", "comfort", "nostalgic"], contexts=["late-night", "date-night"],
        sensory=dict(creaminess=0.70, richness=0.70, saltiness=0.75, umami=0.60),
        cook_minutes=25, difficulty=2)),
    ("lasagna", "Lasagna", ["italian"], dict(
        meal_types=["dinner"], methods=["baked"], proteins=["beef"], bases=["pasta"],
        ingredients=["tomato", "mozzarella", "parmesan"],
        emotions=["comfort", "celebratory"], contexts=["family-meal", "dinner-party", "winter"],
        sensory=dict(richness=0.75, creaminess=0.60, umami=0.70, saltiness=0.70),
        cook_minutes=90, difficulty=3)),
    ("french-toast", "French Toast", ["french"], dict(
        meal_types=["breakfast"], methods=["fried"], proteins=["egg"], bases=["bread"],
        ingredients=["butter"],
        emotions=["nostalgic", "comfort"], contexts=["brunch", "weekend"],
        sensory=dict(sweetness=0.70, richness=0.55, warmth=0.60),
        cook_minutes=20, difficulty=1)),
    ("omelette", "Omelette", ["french"], dict(
        meal_types=["breakfast"], methods=["fried"], proteins=["egg"], bases=["none"],
        ingredients=["butter", "cheese"],
        emotions=["light", "energizing", "comfort"], contexts=["brunch", "quick-lunch"],
        sensory=dict(freshness=0.40, creaminess=0.40),
        cook_minutes=10, difficulty=1, dietary=["vegetarian", "low-carb"])),
    ("pancakes", "Pancakes", ["american"], dict(
        meal_types=["breakfast"], methods=["fried"], proteins=["egg"], bases=["bread"],
        ingredients=["butter"],
        emotions=["comfort", "nostalgic", "indulgent"], contexts=["brunch", "weekend", "family-meal"],
        sensory=dict(sweetness=0.75, richness=0.50, warmth=0.60),
        cook_minutes=20, difficulty=1, dietary=["vegetarian"])),
    ("mac-and-cheese", "Mac & Cheese", ["american"], dict(
        meal_types=["dinner"], methods=["baked"], proteins=["none"], bases=["pasta"],
        ingredients=["cheese", "butter"],
        emotions=["comfort", "nostalgic", "indulgent"], contexts=["family-meal", "late-night", "winter"],
        sensory=dict(creaminess=0.85, richness=0.80, saltiness=0.70),
        cook_minutes=35, difficulty=1, dietary=["vegetarian"])),
    ("grilled-cheese", "Grilled Cheese", ["american"], dict(
        meal_types=["lunch"], methods=["fried"], proteins=["none"], bases=["bread"],
        ingredients=["cheese", "butter"],
        emotions=["comfort", "nostalgic"], contexts=["quick-lunch", "late-night", "rainy"],
        sensory=dict(creaminess=0.70, richness=0.60, saltiness=0.60),
        cook_minutes=15, difficulty=1, dietary=["vegetarian"])),
    ("roast-chicken", "Roast Chicken", ["american"], dict(
        meal_types=["dinner"], methods=["roasted"], proteins=["chicken"], bases=["potato"],
        ingredients=["butter", "garlic"],
        emotions=["comfort", "hearty"], contexts=["family-meal", "weekend"],
        sensory=dict(richness=0.60, umami=0.60, saltiness=0.55),
        cook_minutes=90, difficulty=2)),
    ("beef-bourguignon", "Beef Bourguignon", ["french"], dict(
        meal_types=["dinner"], methods=["braised"], proteins=["beef"], bases=["potato"],
        ingredients=["mushroom", "butter", "wine"],
        emotions=["indulgent", "celebratory", "comfort"], contexts=["dinner-party", "winter", "date-night"],
        sensory=dict(richness=0.80, umami=0.75, warmth=0.75),
        cook_minutes=240, difficulty=3)),
    ("ratatouille", "Ratatouille", ["french"], dict(
        meal_types=["dinner"], methods=["baked"], proteins=["none"], bases=["none"],
        ingredients=["tomato", "garlic"],
        emotions=["light", "refreshing", "nostalgic"], contexts=["summer", "date-night"],
        sensory=dict(freshness=0.70, richness=0.40),
        cook_minutes=75, difficulty=2, dietary=["vegetarian", "vegan", "gluten-free"])),
    ("shakshuka", "Shakshuka", ["middle-eastern"], dict(
        meal_types=["breakfast"], methods=["simmered"], proteins=["egg"], bases=["bread"],
        ingredients=["tomato", "chili", "cumin"],
        emotions=["energizing", "comfort"], contexts=["brunch", "weekend", "sick-day"],
        sensory=dict(spiciness=0.50, sourness=0.40, warmth=0.70, umami=0.50),
        cook_minutes=30, difficulty=1, dietary=["vegetarian"])),
    ("hummus-platter", "Hummus Platter", ["middle-eastern"], dict(
        meal_types=["lunch"], methods=["raw"], proteins=["beans"], bases=["bread"],
        ingredients=["tahini", "lemon", "olive-oil"],
        emotions=["light", "soothing", "refreshing"], contexts=["quick-lunch"],
        sensory=dict(creaminess=0.50),
        cook_minutes=20, difficulty=1, dietary=["vegetarian", "vegan"])),
    ("falafel-wrap", "Falafel Wrap", ["middle-eastern"], dict(
        meal_types=["lunch"], methods=["fried"], proteins=["beans"], bases=["bread"],
        ingredients=["chickpea", "tahini", "parsley"],
        emotions=["fun", "hearty"], contexts=["quick-lunch", "late-night"],
        sensory=dict(crunchiness=0.60, spiciness=0.40),
        cook_minutes=35, difficulty=2, dietary=["vegetarian", "vegan"])),
    ("shawarma", "Shawarma", ["middle-eastern"], dict(
        meal_types=["dinner"], methods=["grilled"], proteins=["chicken"], bases=["bread"],
        ingredients=["garlic", "tahini", "cumin"],
        emotions=["hearty", "adventurous"], contexts=["late-night", "quick-lunch"],
        sensory=dict(spiciness=0.55, umami=0.50, richness=0.45),
        cook_minutes=40, difficulty=2)),
    ("mapo-tofu", "Mapo Tofu", ["chinese"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["tofu"], bases=["rice"],
        ingredients=["tofu", "chili", "scallion"],
        emotions=["comfort", "hearty"], contexts=["winter", "family-meal"],
        sensory=dict(spiciness=0.75, umami=0.70, saltiness=0.65),
        cook_minutes=25, difficulty=2, dietary=["vegetarian"])),
    ("kung-pao-chicken", "Kung Pao Chicken", ["chinese"], dict(
        meal_types=["dinner"], methods=["stir-fried"], proteins=["chicken"], bases=["rice"],
        ingredients=["peanut", "chili", "garlic"],
        emotions=["fun", "energizing"], contexts=["quick-lunch", "family-meal"],
        sensory=dict(spiciness=0.55, sweetness=0.40, umami=0.65, crunchiness=0.45),
        cook_minutes=25, difficulty=2)),
    ("dumplings", "Steamed Dumplings", ["chinese"], dict(
        meal_types=["dinner"], methods=["steamed"], proteins=["pork"], bases=["dumpling"],
        ingredients=["ginger", "scallion", "soy"],
        emotions=["comfort", "fun", "nostalgic"], contexts=["family-meal", "weekend", "late-night"],
        sensory=dict(umami=0.70, saltiness=0.65),
        cook_minutes=40, difficulty=2)),
    ("fried-rice", "Fried Rice", ["chinese"], dict(
        meal_types=["lunch"], methods=["stir-fried"], proteins=["egg"], bases=["rice"],
        ingredients=["soy", "scallion", "garlic"],
        emotions=["comfort", "fun"], contexts=["quick-lunch", "late-night", "family-meal"],
        sensory=dict(umami=0.60, saltiness=0.65),
        cook_minutes=20, difficulty=1)),
    ("congee", "Congee", ["chinese"], dict(
        meal_types=["breakfast"], methods=["simmered"], proteins=["chicken"], bases=["rice"],
        ingredients=["ginger", "scallion"],
        emotions=["soothing", "comfort", "nostalgic"], contexts=["sick-day", "hangover", "winter"],
        sensory=dict(warmth=0.80, richness=0.35, umami=0.50),
        cook_minutes=75, difficulty=1)),
    ("dal", "Dal", ["indian"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["lentils"], bases=["rice"],
        ingredients=["turmeric", "cumin", "ginger"],
        emotions=["comfort", "soothing", "hearty"], contexts=["family-meal", "winter", "sick-day"],
        sensory=dict(spiciness=0.45, richness=0.40, umami=0.50),
        cook_minutes=50, difficulty=1, dietary=["vegetarian", "vegan", "gluten-free"])),
    ("biryani", "Chicken Biryani", ["indian"], dict(
        meal_types=["dinner"], methods=["slow-cooked"], proteins=["chicken"], bases=["rice"],
        ingredients=["garam-masala", "yogurt", "garlic"],
        emotions=["celebratory", "hearty", "indulgent"], contexts=["dinner-party", "family-meal"],
        sensory=dict(spiciness=0.60, richness=0.70, umami=0.60),
        cook_minutes=90, difficulty=3)),
    ("nasi-goreng", "Nasi Goreng", ["malaysian"], dict(
        meal_types=["lunch"], methods=["stir-fried"], proteins=["egg"], bases=["rice"],
        ingredients=["chili", "soy"],
        emotions=["comfort", "fun"], contexts=["quick-lunch", "late-night"],
        sensory=dict(spiciness=0.60, umami=0.65, saltiness=0.70),
        cook_minutes=20, difficulty=1)),
    ("soto-ayam", "Soto Ayam", ["malaysian"], dict(
        meal_types=["lunch"], methods=["simmered"], proteins=["chicken"], bases=["noodles"],
        ingredients=["turmeric", "lemongrass", "lime"],
        emotions=["comfort", "soothing", "light"], contexts=["sick-day", "winter", "rainy"],
        sensory=dict(warmth=0.75, umami=0.55, freshness=0.50),
        cook_minutes=60, difficulty=2)),
    ("gado-gado", "Gado Gado", ["malaysian"], dict(
        meal_types=["lunch"], methods=["raw"], proteins=["tofu"], bases=["greens"],
        ingredients=["peanut", "lime"],
        emotions=["light", "refreshing", "energizing"], contexts=["summer", "quick-lunch"],
        sensory=dict(creaminess=0.50, freshness=0.60),
        cook_minutes=25, difficulty=1, dietary=["vegetarian"])),
    ("satay", "Chicken Satay", ["malaysian"], dict(
        meal_types=["dinner"], methods=["grilled"], proteins=["chicken"], bases=["none"],
        ingredients=["peanut", "cumin"],
        emotions=["fun", "adventurous", "hearty"], contexts=["dinner-party", "weekend", "late-night"],
        sensory=dict(spiciness=0.45, sweetness=0.40, richness=0.50),
        cook_minutes=30, difficulty=2)),
    ("burrito", "Burrito", ["mexican"], dict(
        meal_types=["dinner"], methods=["grilled"], proteins=["beef"], bases=["tortilla"],
        ingredients=["beans", "rice", "avocado"],
        emotions=["hearty", "fun"], contexts=["quick-lunch", "late-night", "workout-recovery"],
        sensory=dict(richness=0.55, freshness=0.50, spiciness=0.45),
        cook_minutes=30, difficulty=2)),
    ("tacos", "Street Tacos", ["mexican"], dict(
        meal_types=["dinner"], methods=["grilled"], proteins=["pork"], bases=["tortilla"],
        ingredients=["cilantro", "onion", "lime"],
        emotions=["fun", "celebratory"], contexts=["weekend", "dinner-party", "late-night"],
        sensory=dict(freshness=0.60, spiciness=0.55, saltiness=0.60),
        cook_minutes=30, difficulty=2)),
    ("nachos", "Nachos", ["mexican"], dict(
        meal_types=["snack"], methods=["baked"], proteins=["beans"], bases=["tortilla"],
        ingredients=["cheese", "chili", "avocado"],
        emotions=["fun", "comfort"], contexts=["weekend", "late-night", "study"],
        sensory=dict(creaminess=0.60, crunchiness=0.60, spiciness=0.45),
        cook_minutes=15, difficulty=1, dietary=["vegetarian"])),
    ("chilaquiles", "Chilaquiles", ["mexican"], dict(
        meal_types=["breakfast"], methods=["fried"], proteins=["egg"], bases=["tortilla"],
        ingredients=["tomato", "chili", "cilantro"],
        emotions=["comfort", "energizing"], contexts=["brunch", "weekend"],
        sensory=dict(spiciness=0.50, sourness=0.40, warmth=0.65),
        cook_minutes=25, difficulty=2, dietary=["vegetarian"])),
    ("paella", "Paella", ["spanish"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["shrimp"], bases=["rice"],
        ingredients=["paprika", "lemon", "saffron"],
        emotions=["celebratory", "hearty"], contexts=["dinner-party", "family-meal", "weekend"],
        sensory=dict(umami=0.65, richness=0.50, saltiness=0.65),
        cook_minutes=60, difficulty=3)),
    ("risotto", "Mushroom Risotto", ["italian"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["none"], bases=["rice"],
        ingredients=["mushroom", "parmesan", "butter"],
        emotions=["indulgent", "comfort"], contexts=["dinner-party", "date-night", "winter"],
        sensory=dict(creaminess=0.75, richness=0.65, umami=0.60),
        cook_minutes=40, difficulty=3, dietary=["vegetarian"])),
    ("minestrone", "Minestrone", ["italian"], dict(
        meal_types=["lunch"], methods=["simmered"], proteins=["beans"], bases=["pasta"],
        ingredients=["tomato", "basil"],
        emotions=["light", "soothing"], contexts=["winter", "sick-day", "family-meal"],
        sensory=dict(freshness=0.60, warmth=0.70, richness=0.35),
        cook_minutes=45, difficulty=1, dietary=["vegetarian", "vegan"])),
    ("clam-chowder", "Clam Chowder", ["american"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["fish"], bases=["none"],
        ingredients=["potato", "onion"],
        emotions=["comfort", "hearty", "nostalgic"], contexts=["winter", "rainy", "family-meal"],
        sensory=dict(creaminess=0.70, richness=0.65, saltiness=0.60),
        cook_minutes=45, difficulty=2)),
    ("french-onion-soup", "French Onion Soup", ["french"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["none"], bases=["bread"],
        ingredients=["onion", "cheese"],
        emotions=["comfort", "soothing", "nostalgic"], contexts=["winter", "rainy", "late-night"],
        sensory=dict(umami=0.70, sweetness=0.50, warmth=0.80, richness=0.50),
        cook_minutes=60, difficulty=2, dietary=["vegetarian"])),
    ("banh-mi", "Banh Mi", ["vietnamese"], dict(
        meal_types=["lunch"], methods=["grilled"], proteins=["pork"], bases=["bread"],
        ingredients=["cilantro", "lime", "chili"],
        emotions=["adventurous", "refreshing", "light"], contexts=["quick-lunch", "late-night"],
        sensory=dict(freshness=0.70, crunchiness=0.60, spiciness=0.45, saltiness=0.65),
        cook_minutes=30, difficulty=2)),
    ("onigiri", "Onigiri", ["japanese"], dict(
        meal_types=["snack"], methods=["steamed"], proteins=["none"], bases=["rice"],
        ingredients=["nori", "sesame"],
        emotions=["light", "refreshing", "soothing"], contexts=["quick-lunch", "study"],
        sensory=dict(freshness=0.50, umami=0.50),
        cook_minutes=20, difficulty=1, dietary=["vegetarian", "vegan"])),
    ("ceviche", "Ceviche", ["mexican"], dict(
        meal_types=["lunch"], methods=["raw"], proteins=["fish"], bases=["none"],
        ingredients=["lime", "chili", "cilantro"],
        emotions=["refreshing", "light", "energizing"], contexts=["summer", "date-night"],
        sensory=dict(freshness=0.95, sourness=0.80, spiciness=0.50, warmth=0.15),
        cook_minutes=20, difficulty=1, dietary=["gluten-free", "dairy-free"])),
    ("gazpacho", "Gazpacho", ["spanish"], dict(
        meal_types=["lunch"], methods=["raw"], proteins=["none"], bases=["none"],
        ingredients=["tomato", "garlic", "olive-oil"],
        emotions=["refreshing", "light"], contexts=["summer", "workout-recovery"],
        sensory=dict(sourness=0.50, freshness=0.90, warmth=0.20),
        cook_minutes=15, difficulty=1, dietary=["vegetarian", "vegan", "gluten-free"])),
    ("udon-soup", "Udon Soup", ["japanese"], dict(
        meal_types=["lunch"], methods=["simmered"], proteins=["tofu"], bases=["noodles"],
        ingredients=["soy", "scallion"],
        emotions=["soothing", "comfort", "light"], contexts=["winter", "sick-day", "late-night"],
        sensory=dict(warmth=0.80, umami=0.70, richness=0.40),
        cook_minutes=30, difficulty=1, dietary=["vegetarian"])),
    ("miso-soup", "Miso Soup", ["japanese"], dict(
        meal_types=["breakfast"], methods=["simmered"], proteins=["tofu"], bases=["none"],
        ingredients=["miso", "scallion", "nori"],
        emotions=["soothing", "light", "comfort"], contexts=["quick-lunch", "sick-day"],
        sensory=dict(umami=0.80, warmth=0.75, saltiness=0.70),
        cook_minutes=10, difficulty=1, dietary=["vegetarian", "vegan"])),
    ("tom-kha", "Tom Kha", ["thai"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["chicken"], bases=["rice"],
        ingredients=["coconut", "lemongrass", "lime"],
        emotions=["comfort", "indulgent", "adventurous"], contexts=["rainy", "dinner-party"],
        sensory=dict(creaminess=0.75, spiciness=0.60, sourness=0.55, richness=0.60, warmth=0.75),
        cook_minutes=40, difficulty=2)),
    ("massaman", "Massaman Curry", ["thai"], dict(
        meal_types=["dinner"], methods=["slow-cooked"], proteins=["beef"], bases=["rice"],
        ingredients=["peanut", "coconut", "cumin"],
        emotions=["comfort", "nostalgic"], contexts=["winter", "family-meal"],
        sensory=dict(sweetness=0.55, richness=0.65, spiciness=0.45, creaminess=0.50),
        cook_minutes=90, difficulty=2)),
    ("vindaloo", "Vindaloo", ["indian"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["pork"], bases=["rice"],
        ingredients=["chili", "garlic", "cumin"],
        emotions=["adventurous", "energizing"], contexts=["dinner-party", "weekend"],
        sensory=dict(spiciness=0.90, sourness=0.60, richness=0.60),
        cook_minutes=75, difficulty=3)),
    ("enchiladas", "Enchiladas", ["mexican"], dict(
        meal_types=["dinner"], methods=["baked"], proteins=["chicken"], bases=["tortilla"],
        ingredients=["cheese", "tomato", "chili"],
        emotions=["comfort"], contexts=["family-meal", "weekend"],
        sensory=dict(creaminess=0.50, spiciness=0.45, richness=0.50),
        cook_minutes=45, difficulty=2)),
    ("fish-and-chips", "Fish & Chips", ["american"], dict(
        meal_types=["dinner"], methods=["fried"], proteins=["fish"], bases=["potato"],
        ingredients=["lemon"],
        emotions=["fun", "comfort", "nostalgic"], contexts=["family-meal", "weekend", "late-night"],
        sensory=dict(crunchiness=0.80, saltiness=0.70, warmth=0.60),
        cook_minutes=30, difficulty=2)),
    ("shepherd-pie", "Shepherd's Pie", ["american"], dict(
        meal_types=["dinner"], methods=["baked"], proteins=["lamb"], bases=["potato"],
        ingredients=["onion", "butter"],
        emotions=["comfort", "hearty", "nostalgic"], contexts=["winter", "family-meal"],
        sensory=dict(richness=0.65, warmth=0.70),
        cook_minutes=75, difficulty=2)),
    ("tiramisu", "Tiramisu", ["italian"], dict(
        meal_types=["dessert"], methods=["raw"], proteins=["none"], bases=["none"],
        ingredients=["chocolate", "cream"],
        emotions=["indulgent", "celebratory", "nostalgic"], contexts=["dinner-party", "date-night"],
        sensory=dict(sweetness=0.75, creaminess=0.80, bitterness=0.50),
        cook_minutes=30, difficulty=2, dietary=["vegetarian"])),
    ("cheesecake", "Cheesecake", ["american"], dict(
        meal_types=["dessert"], methods=["baked"], proteins=["none"], bases=["none"],
        ingredients=["cheese"],
        emotions=["indulgent", "nostalgic"], contexts=["dinner-party"],
        sensory=dict(sweetness=0.75, creaminess=0.85, richness=0.70),
        cook_minutes=90, difficulty=2, dietary=["vegetarian"])),
    ("brownies", "Brownies", ["american"], dict(
        meal_types=["dessert"], methods=["baked"], proteins=["none"], bases=["none"],
        ingredients=["chocolate", "butter"],
        emotions=["indulgent", "nostalgic", "comfort"], contexts=["late-night", "study", "weekend"],
        sensory=dict(sweetness=0.85, richness=0.70),
        cook_minutes=30, difficulty=1, dietary=["vegetarian"])),
    ("creme-brulee", "Creme Brulee", ["french"], dict(
        meal_types=["dessert"], methods=["baked"], proteins=["none"], bases=["none"],
        ingredients=["butter"],
        emotions=["celebratory", "indulgent"], contexts=["date-night", "dinner-party"],
        sensory=dict(sweetness=0.75, creaminess=0.80),
        cook_minutes=60, difficulty=2, dietary=["vegetarian"])),
    ("mango-sticky-rice", "Mango Sticky Rice", ["thai"], dict(
        meal_types=["dessert"], methods=["steamed"], proteins=["none"], bases=["rice"],
        ingredients=["coconut"],
        emotions=["refreshing", "indulgent"], contexts=["summer", "date-night"],
        sensory=dict(sweetness=0.85, creaminess=0.50),
        cook_minutes=40, difficulty=1, dietary=["vegetarian", "vegan"])),
    ("mochi", "Mochi", ["japanese"], dict(
        meal_types=["dessert"], methods=["steamed"], proteins=["none"], bases=["rice"],
        ingredients=["sesame"],
        emotions=["refreshing", "nostalgic"], contexts=["study"],
        sensory=dict(sweetness=0.70),
        cook_minutes=20, difficulty=1, dietary=["vegetarian"])),
    ("churros", "Churros", ["spanish"], dict(
        meal_types=["dessert"], methods=["fried"], proteins=["none"], bases=["none"],
        ingredients=["chocolate"],
        emotions=["fun", "celebratory", "nostalgic"], contexts=["weekend", "date-night"],
        sensory=dict(sweetness=0.80, crunchiness=0.70),
        cook_minutes=25, difficulty=2, dietary=["vegetarian"])),
    ("smoothie-bowl", "Smoothie Bowl", ["american"], dict(
        meal_types=["breakfast"], methods=["raw"], proteins=["none"], bases=["none"],
        ingredients=["yogurt"],
        emotions=["energizing", "refreshing"], contexts=["brunch", "workout-recovery", "summer"],
        sensory=dict(sweetness=0.60, freshness=0.85, warmth=0.15, creaminess=0.50),
        cook_minutes=10, difficulty=1, dietary=["vegetarian", "gluten-free"])),
    ("oatmeal", "Oatmeal", ["american"], dict(
        meal_types=["breakfast"], methods=["simmered"], proteins=["none"], bases=["none"],
        ingredients=["butter"],
        emotions=["comfort", "soothing", "energizing"], contexts=["winter", "brunch", "sick-day"],
        sensory=dict(warmth=0.70, sweetness=0.50, creaminess=0.40),
        cook_minutes=15, difficulty=1, dietary=["vegetarian", "vegan"])),
    ("avocado-toast", "Avocado Toast", ["american"], dict(
        meal_types=["breakfast"], methods=["raw"], proteins=["none"], bases=["bread"],
        ingredients=["avocado", "lemon"],
        emotions=["energizing", "refreshing", "light"], contexts=["brunch", "quick-lunch"],
        sensory=dict(creaminess=0.55, freshness=0.60),
        cook_minutes=10, difficulty=1, dietary=["vegetarian", "vegan"])),
    ("eggs-benedict", "Eggs Benedict", ["french"], dict(
        meal_types=["breakfast"], methods=["simmered"], proteins=["egg"], bases=["bread"],
        ingredients=["butter"],
        emotions=["indulgent", "nostalgic"], contexts=["brunch", "weekend", "date-night"],
        sensory=dict(richness=0.70, creaminess=0.60, saltiness=0.60),
        cook_minutes=25, difficulty=2, dietary=["vegetarian"])),
    ("poke-bowl", "Poke Bowl", ["japanese"], dict(
        meal_types=["lunch"], methods=["raw"], proteins=["fish"], bases=["rice"],
        ingredients=["sesame", "avocado", "soy"],
        emotions=["light", "energizing", "refreshing"], contexts=["summer", "quick-lunch", "workout-recovery"],
        sensory=dict(freshness=0.90, umami=0.60, creaminess=0.40),
        cook_minutes=20, difficulty=1, dietary=["dairy-free", "high-protein"])),
    ("jambalaya", "Jambalaya", ["american"], dict(
        meal_types=["dinner"], methods=["slow-cooked"], proteins=["shrimp"], bases=["rice"],
        ingredients=["chili", "garlic", "onion"],
        emotions=["hearty", "celebratory", "fun"], contexts=["family-meal", "weekend"],
        sensory=dict(spiciness=0.60, richness=0.55, umami=0.60),
        cook_minutes=75, difficulty=2)),
    ("gumbo", "Gumbo", ["american"], dict(
        meal_types=["dinner"], methods=["slow-cooked"], proteins=["shrimp"], bases=["rice"],
        ingredients=["chili", "onion", "garlic"],
        emotions=["hearty", "comfort"], contexts=["family-meal", "winter"],
        sensory=dict(umami=0.65, spiciness=0.55, richness=0.60),
        cook_minutes=120, difficulty=2)),
    ("tortilla-soup", "Tortilla Soup", ["mexican"], dict(
        meal_types=["lunch"], methods=["simmered"], proteins=["chicken"], bases=["none"],
        ingredients=["tomato", "chili", "avocado"],
        emotions=["comfort", "soothing", "energizing"], contexts=["sick-day", "rainy", "winter"],
        sensory=dict(spiciness=0.45, warmth=0.80, freshness=0.50),
        cook_minutes=45, difficulty=1)),
    ("wonton-soup", "Wonton Soup", ["chinese"], dict(
        meal_types=["dinner"], methods=["simmered"], proteins=["pork"], bases=["dumpling"],
        ingredients=["ginger", "scallion", "soy"],
        emotions=["soothing", "comfort"], contexts=["sick-day", "winter", "late-night"],
        sensory=dict(umami=0.65, warmth=0.80),
        cook_minutes=40, difficulty=2)),
    ("hot-and-sour-soup", "Hot & Sour Soup", ["chinese"], dict(
        meal_types=["lunch"], methods=["simmered"], proteins=["tofu"], bases=["none"],
        ingredients=["mushroom", "chili"],
        emotions=["energizing"], contexts=["sick-day", "rainy"],
        sensory=dict(spiciness=0.70, sourness=0.70, warmth=0.80),
        cook_minutes=25, difficulty=1, dietary=["vegetarian"])),
    ("baba-ganoush", "Baba Ganoush", ["middle-eastern"], dict(
        meal_types=["snack"], methods=["grilled"], proteins=["none"], bases=["bread"],
        ingredients=["tahini", "lemon", "garlic"],
        emotions=["light", "soothing"], contexts=["dinner-party", "quick-lunch"],
        sensory=dict(creaminess=0.50, bitterness=0.40),
        cook_minutes=25, difficulty=1, dietary=["vegetarian", "vegan"])),
    ("tabbouleh", "Tabbouleh", ["middle-eastern"], dict(
        meal_types=["lunch"], methods=["raw"], proteins=["none"], bases=["greens"],
        ingredients=["mint", "lemon", "parsley"],
        emotions=["refreshing", "light"], contexts=["summer", "quick-lunch"],
        sensory=dict(freshness=0.85, sourness=0.50, crunchiness=0.40),
        cook_minutes=20, difficulty=1, dietary=["vegetarian", "vegan", "gluten-free"])),
    ("fattoush", "Fattoush", ["middle-eastern"], dict(
        meal_types=["lunch"], methods=["raw"], proteins=["none"], bases=["bread"],
        ingredients=["lemon", "mint"],
        emotions=["refreshing", "light"], contexts=["summer", "quick-lunch"],
        sensory=dict(freshness=0.80, sourness=0.50),
        cook_minutes=20, difficulty=1, dietary=["vegetarian", "vegan"])),
    ("spanakopita", "Spanakopita", ["greek"], dict(
        meal_types=["dinner"], methods=["baked"], proteins=["none"], bases=["none"],
        ingredients=["cheese", "feta"],
        emotions=["indulgent", "comfort"], contexts=["dinner-party", "family-meal"],
        sensory=dict(richness=0.55, creaminess=0.45),
        cook_minutes=60, difficulty=2, dietary=["vegetarian"])),
    ("moussaka", "Moussaka", ["greek"], dict(
        meal_types=["dinner"], methods=["baked"], proteins=["lamb"], bases=["potato"],
        ingredients=["cheese", "garlic"],
        emotions=["hearty"], contexts=["family-meal", "dinner-party"],
        sensory=dict(richness=0.65, warmth=0.70),
        cook_minutes=90, difficulty=3)),
    ("gyro", "Gyro", ["greek"], dict(
        meal_types=["lunch"], methods=["grilled"], proteins=["lamb"], bases=["bread"],
        ingredients=["garlic", "yogurt"],
        emotions=["hearty", "fun"], contexts=["late-night", "quick-lunch"],
        sensory=dict(spiciness=0.35, richness=0.50),
        cook_minutes=30, difficulty=2)),
    ("paneer-tikka", "Paneer Tikka", ["indian"], dict(
        meal_types=["dinner"], methods=["grilled"], proteins=["paneer"], bases=["none"],
        ingredients=["cumin", "garam-masala", "yogurt"],
        emotions=["fun", "energizing", "adventurous"], contexts=["dinner-party", "weekend"],
        sensory=dict(spiciness=0.50, richness=0.45),
        cook_minutes=35, difficulty=2, dietary=["vegetarian", "gluten-free"])),
    ("hainanese-chicken", "Hainanese Chicken Rice", ["malaysian"], dict(
        meal_types=["lunch"], methods=["steamed"], proteins=["chicken"], bases=["rice"],
        ingredients=["ginger", "scallion"],
        emotions=["comfort", "soothing", "nostalgic"], contexts=["family-meal", "quick-lunch"],
        sensory=dict(umami=0.60, richness=0.45),
        cook_minutes=60, difficulty=2)),
    ("char-kway-teow", "Char Kway Teow", ["malaysian"], dict(
        meal_types=["dinner"], methods=["stir-fried"], proteins=["shrimp"], bases=["noodles"],
        ingredients=["soy", "chili", "egg"],
        emotions=["indulgent", "fun", "adventurous"], contexts=["late-night", "quick-lunch"],
        sensory=dict(umami=0.70, spiciness=0.50, sweetness=0.40, saltiness=0.70),
        cook_minutes=15, difficulty=2)),
    ("greek-yogurt-bowl", "Greek Yogurt Bowl", ["greek"], dict(
        meal_types=["breakfast"], methods=["raw"], proteins=["none"], bases=["none"],
        ingredients=["yogurt", "berry"],
        emotions=["energizing", "refreshing"], contexts=["brunch", "workout-recovery"],
        sensory=dict(creaminess=0.70, sweetness=0.50, sourness=0.45),
        cook_minutes=5, difficulty=1, dietary=["vegetarian", "gluten-free"])),
    ("pad-kra-pao", "Pad Kra Pao", ["thai"], dict(
        meal_types=["lunch"], methods=["stir-fried"], proteins=["chicken"], bases=["rice"],
        ingredients=["basil", "chili", "garlic"],
        emotions=["energizing", "comfort"], contexts=["quick-lunch", "late-night"],
        sensory=dict(spiciness=0.70, umami=0.60, saltiness=0.60),
        cook_minutes=15, difficulty=1)),
]


def curated_recipes() -> list:
    recipes = []
    for rid, name, cuisines, o in CURATED:
        recipes.append(_build(rid, name, cuisines, o, source="curated"))
    return recipes


# ---------------------------------------------------------------------------
# Procedurally generated dishes
# ---------------------------------------------------------------------------

DISH_WORDS = {
    "japanese": ["Tokyo", "Osaka", "Hokkaido", "Kyoto"],
    "korean": ["Seoul", "Busan", "Jeju", "Gyeongju"],
    "chinese": ["Cantonese", "Sichuan", "Hunan", "Shanghai"],
    "thai": ["Bangkok", "Chiang Mai", "Phuket", "Isaan"],
    "vietnamese": ["Hanoi", "Saigon", "Hue", "Danang"],
    "malaysian": ["Penang", "Kuala Lumpur", "Ipoh", "Malacca"],
    "indian": ["Punjabi", "Hyderabadi", "Goan", "Bengali"],
    "mexican": ["Oaxacan", "Yucatan", "Jalisco", "Veracruz"],
    "italian": ["Tuscan", "Sicilian", "Neapolitan", "Ligurian"],
    "french": ["Provencal", "Lyonnais", "Breton", "Alsacian"],
    "greek": ["Athenian", "Cretan", "Thessalian", "Aegean"],
    "middle-eastern": ["Levantine", "Anatolian", "Persian", "Bedouin"],
    "american": ["Southern", "Texan", "New England", "Cajun"],
    "spanish": ["Catalan", "Andalusian", "Basque", "Galician"],
}


def generated_recipes(per_cuisine=24, seed=42) -> list:
    rng = random.Random(seed)
    recipes = []

    def v(f):
        return float(f.__round__(3))

    for cid in sorted(CUISINES):
        c = CUISINES[cid]
        for i in range(per_cuisine):
            meal = rng.choice(c["meal_types"])
            method = rng.choice(c["methods"])
            protein = rng.choice(c["proteins"])
            base = rng.choice(c["bases"])
            ings = rng.sample(c["ingredients"], 2)

            sensory = {}
            for f in SENSORY_FIELDS:
                center = c["flavor"].get(f, 0.5)
                sensory[f] = _clamp(center + rng.uniform(-0.12, 0.12))
            if method in ("fried", "grilled"):
                sensory["crunchiness"] = _clamp(sensory["crunchiness"] + 0.15)
            if method == "raw":
                sensory["warmth"] = _clamp(sensory["warmth"] - 0.35)
                sensory["freshness"] = _clamp(sensory["freshness"] + 0.15)
            if method == "steamed":
                sensory["freshness"] = _clamp(sensory["freshness"] + 0.10)
            if method in ("simmered", "slow-cooked", "braised"):
                sensory["warmth"] = _clamp(sensory["warmth"] + 0.15)
                sensory["richness"] = _clamp(sensory["richness"] + 0.10)
            if meal == "dessert":
                sensory["sweetness"] = _clamp(sensory["sweetness"] + 0.35)
                sensory["warmth"] = _clamp(sensory["warmth"] - 0.15)
            if meal == "snack":
                sensory["crunchiness"] = _clamp(sensory["crunchiness"] + 0.10)

            cook = int(METHOD_COOK[method] * rng.uniform(0.7, 1.35))
            diff = METHOD_DIFF[method]

            place = rng.choice(DISH_WORDS[cid])
            suffix = rng.choice(SUFFIX[method])
            modifier = base if base != "none" else ings[0]
            name = f"{place} {modifier.title()} {suffix}"

            emotions = rng.sample(c["emotions"], min(3, len(c["emotions"])))
            contexts = rng.sample(c["contexts"], min(3, len(c["contexts"])))

            dietary = list(c["dietary"])
            if not (MEAT & set(protein)):
                if "vegetarian" not in dietary:
                    dietary = dietary + ["vegetarian"]

            recipe = Recipe(
                id=f"gen-{cid}-{i:03d}", name=name, cuisines=[cid],
                meal_types=[meal], methods=[method], proteins=[protein],
                bases=[base], ingredients=ings, dietary=dietary,
                emotions=emotions, contexts=contexts,
                sensory={f: v(sensory[f]) for f in SENSORY_FIELDS},
                cook_minutes=cook, difficulty=diff,
                servings=rng.randint(1, 6), source="generated",
            )
            recipes.append(derive(recipe))

    return recipes


def load_recipes(seed=42) -> list:
    from ..types import CONTEXTS, EMOTIONS, MEAL_TYPES, METHODS, PROTEINS, BASES, DIETARY
    recipes = curated_recipes() + generated_recipes(per_cuisine=24, seed=seed)
    ids = [r.id for r in recipes]
    assert len(set(ids)) == len(ids), "duplicate recipe ids"
    vocab = {
        "meal_types": set(MEAL_TYPES), "methods": set(METHODS),
        "proteins": set(PROTEINS), "bases": set(BASES),
        "dietary": set(DIETARY), "emotions": set(EMOTIONS),
        "contexts": set(CONTEXTS),
    }
    for r in recipes:
        for field, allowed in vocab.items():
            bad = set(getattr(r, field)) - allowed
            assert not bad, f"recipe {r.id}: invalid {field} values {bad}"
        for f in SENSORY_FIELDS:
            assert 0.0 <= r.sensory[f] <= 1.0, f"recipe {r.id}: sensory {f} out of range"
    return recipes


if __name__ == "__main__":
    rs = load_recipes()
    print(f"loaded {len(rs)} recipes "
          f"({sum(1 for r in rs if r.source == 'curated')} curated, "
          f"{sum(1 for r in rs if r.source == 'generated')} generated)")
