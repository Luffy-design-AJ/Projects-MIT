extends Area2D
class_name SwarmTarget

## Minimal contract for anything the swarm can engage. Extend this and
## override take_damage() — registration in the "swarm_targets" group is
## handled here so SwarmAgents can detect any subclass. World position is
## just the inherited Node2D `global_position` — no need to wrap it; later
## tasks read `target.global_position` directly.

func _ready() -> void:
	add_to_group("swarm_targets")

func take_damage(_amount: float) -> void:
	pass
