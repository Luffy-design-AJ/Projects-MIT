"""Core data model for Palate.

Recipes are never reduced to ingredient lists.  They carry rich structural,
sensory, emotional and contextual metadata that the recommendation engine can
reason over with Bayesian updates.
"""

from __future__ import annotations

from dataclasses import dataclass, field as dc_field
from typing import Optional

# --- Controlled vocabularies -------------------------------------------------

SENSORY_FIELDS = [
    "warmth", "richness", "freshness", "creaminess", "crunchiness",
    "sweetness", "saltiness", "sourness", "bitterness", "umami", "spiciness",
]

MEAL_TYPES = ["breakfast", "lunch", "dinner", "dessert", "snack"]
METHODS = [
    "grilled", "roasted", "baked", "fried", "steamed", "stir-fried",
    "simmered", "slow-cooked", "braised", "raw",
]
PROTEINS = [
    "chicken", "beef", "pork", "lamb", "fish", "shrimp", "tofu", "paneer",
    "beans", "lentils", "egg", "none",
]
BASES = ["rice", "noodles", "pasta", "bread", "potato", "tortilla", "dumpling", "greens", "none"]
DIETARY = [
    "vegetarian", "vegan", "gluten-free", "dairy-free", "nut-free",
    "high-protein", "keto", "low-carb",
]
EMOTIONS = [
    "comfort", "celebratory", "refreshing", "indulgent", "light", "hearty",
    "adventurous", "nostalgic", "soothing", "energizing", "fun",
]
CONTEXTS = [
    "winter", "summer", "rainy", "late-night", "quick-lunch", "family-meal",
    "dinner-party", "workout-recovery", "hangover", "sick-day", "brunch",
    "date-night", "study", "weekend",
]

# Field names that hold lists of category tags (for Trait kind == "has_any").
ARRAY_FIELDS = {
    "cuisines", "meal_types", "methods", "proteins", "bases",
    "ingredients", "dietary", "emotions", "contexts",
}


@dataclass
class Trait:
    """A composable predicate over recipes, scored in [0, 1].

    Kinds:
      has_any  -> 1 if recipe[field] intersects `values`
      bool     -> 1 if recipe[field] == `value`
      numeric  -> trapezoid score on recipe[field] within [min_, max_]
      and      -> min of child traits
      or       -> max of child traits
      not      -> 1 - child trait
    """

    kind: str
    field: Optional[str] = None
    values: Optional[list] = None
    min_: Optional[float] = None
    max_: Optional[float] = None
    value: Optional[object] = None
    soft: float = 0.1
    trait: Optional["Trait"] = None
    traits: Optional[list] = dc_field(default=None)


@dataclass
class Recipe:
    id: str
    name: str
    cuisines: list
    meal_types: list
    methods: list
    proteins: list
    bases: list
    ingredients: list
    dietary: list
    emotions: list
    contexts: list
    sensory: dict
    cook_minutes: int
    difficulty: int
    servings: int
    source: str
    # Derived flags ----------------------------------------------------------
    has_broth: bool = False
    is_noodle: bool = False
    is_cold: bool = False
    is_sweet: bool = False
    is_one_pot: bool = False
    vegetarian: bool = False


@dataclass
class Answer:
    id: str
    label: str
    trait: Optional[Trait] = None


@dataclass
class Question:
    id: str
    category: str
    trait_key: str
    text: str
    kind: str  # "binary" | "multi"
    answers: list  # list[Answer]


@dataclass
class AnswerRecord:
    question_id: str
    answer_id: str
    label: Optional[str] = None


def derive(recipe: Recipe) -> Recipe:
    """Fill derived boolean flags after all attributes are known."""
    soupish = {"simmered", "slow-cooked", "braised"} & set(recipe.methods)
    recipe.has_broth = bool(soupish)
    recipe.is_noodle = "noodles" in recipe.bases
    recipe.is_cold = recipe.sensory.get("warmth", 0.5) <= 0.25
    recipe.is_sweet = ("dessert" in recipe.meal_types) or recipe.sensory.get("sweetness", 0.0) >= 0.65
    recipe.is_one_pot = bool(soupish) or recipe.sensory.get("warmth", 0.5) >= 0.65
    meat = {"chicken", "beef", "pork", "lamb", "fish", "shrimp"}
    recipe.vegetarian = not (meat & set(recipe.proteins))
    return recipe
