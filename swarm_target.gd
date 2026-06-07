extends Area2D
class_name SwarmTarget

## Minimal contract for anything the swarm can engage. Extend this and
## override take_damage() — registration in the "swarm_targets" group and
## position lookup are handled here so SwarmAgents can detect any subclass.

func _ready() -> void:
	add_to_group("swarm_targets")

func take_damage(_amount: float) -> void:
	pass

func get_position() -> Vector2:
	return global_position
