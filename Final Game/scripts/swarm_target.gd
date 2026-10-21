extends Area2D
class_name SwarmTarget

## Minimal contract for anything the swarm can engage. Extend this and
## override take_damage() — registration in the "swarm_targets" group is
## handled here so SwarmAgents can detect any subclass. World position is
## just the inherited Node2D `global_position` — no need to wrap it; later
## tasks read `target.global_position` directly.

## When true the swarm cannot engage this target at all: both its contact damage
## and the swarm's own targeting skip it. It stays in the "swarm_targets" group
## on purpose, because the player's melee reads that group directly — so a
## swarm-immune enemy remains killable, just only by the player. Used by the
## Predator (ants cannot bite it) and the lure enemies (Broodmother, Siren),
## which would otherwise be destroyed by the very ants they attract.
var swarm_immune: bool = false

func _ready() -> void:
	add_to_group("swarm_targets")

func take_damage(_amount: float) -> void:
	pass
