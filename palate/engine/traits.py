"""Trait evaluation: turn a Recipe into a score in [0, 1]."""

from __future__ import annotations

from ..types import Recipe, Trait


def clamp01(x: float) -> float:
    return max(0.0, min(1.0, x))


def _numeric_value(recipe: Recipe, field: str) -> float:
    if field in recipe.sensory:
        return recipe.sensory[field]
    return float(getattr(recipe, field))


def _score_numeric(v: float, lo: Optional[float], hi: Optional[float], soft: float) -> float:
    if lo is not None and hi is not None:
        if v < lo - soft or v > hi + soft:
            return 0.0
        if v < lo:
            return 1.0 - (lo - v) / soft
        if v > hi:
            return 1.0 - (v - hi) / soft
        return 1.0
    if lo is not None:
        if v >= lo:
            return 1.0
        if v < lo - soft:
            return 0.0
        return 1.0 - (lo - v) / soft
    if hi is not None:
        if v <= hi:
            return 1.0
        if v > hi + soft:
            return 0.0
        return 1.0 - (v - hi) / soft
    return 1.0


def score_trait(trait: Optional[Trait], recipe: Recipe) -> float:
    if trait is None:
        return 0.0
    k = trait.kind
    if k == "has_any":
        tags = getattr(recipe, trait.field, [])
        return 1.0 if any(v in trait.values for v in tags) else 0.0
    if k == "bool":
        return 1.0 if getattr(recipe, trait.field) == trait.value else 0.0
    if k == "numeric":
        return _score_numeric(_numeric_value(recipe, trait.field), trait.min_, trait.max_, trait.soft)
    if k == "and":
        return min((score_trait(t, recipe) for t in trait.traits), default=1.0)
    if k == "or":
        return max((score_trait(t, recipe) for t in trait.traits), default=0.0)
    if k == "not":
        return 1.0 - score_trait(trait.trait, recipe)
    raise ValueError(f"Unknown trait kind: {k}")


# --- Convenience constructors ------------------------------------------------

def has_any(field: str, values: list) -> Trait:
    return Trait(kind="has_any", field=field, values=values)


def numeric(field: str, min_: Optional[float] = None, max_: Optional[float] = None,
            soft: float = 0.1) -> Trait:
    return Trait(kind="numeric", field=field, min_=min_, max_=max_, soft=soft)


def boolean(field: str, value: bool = True) -> Trait:
    return Trait(kind="bool", field=field, value=value)


def and_traits(*traits: Trait) -> Trait:
    return Trait(kind="and", traits=list(traits))


def or_traits(*traits: Trait) -> Trait:
    return Trait(kind="or", traits=list(traits))


def not_trait(trait: Trait) -> Trait:
    return Trait(kind="not", trait=trait)
