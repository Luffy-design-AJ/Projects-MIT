extends Node2D
class_name CastField

@export var lifetime: float = 1.2
@export var radius: float = 260.0

var direction: Vector2 = Vector2.RIGHT
var anchor: Vector2 = Vector2.ZERO
var pattern: CastPattern = null

var _age: float = 0.0

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()

## Returns [direction: Vector2, strength: float] for the given world position.
## strength is 0 once the field has nothing left to offer (out of range or expired).
func sample(world_pos: Vector2) -> Array:
	match pattern.shape:
		CastPattern.Shape.PULSE:
			return [direction, _falloff(global_position, world_pos) * pattern.field_strength]
		CastPattern.Shape.CONE:
			return _sample_cone(world_pos)
		_:
			return [direction, 0.0]

func _sample_cone(world_pos: Vector2) -> Array:
	var to_pos := world_pos - global_position
	if to_pos.length() < 0.001:
		return [direction, pattern.field_strength]
	var outward := to_pos.normalized()
	var angle_diff: float = absf(direction.angle_to(outward))
	var cone_factor := clamp(1.0 - angle_diff / pattern.cone_half_angle, 0.0, 1.0)
	return [outward, _falloff(global_position, world_pos) * cone_factor * pattern.field_strength]

func _falloff(reference_point: Vector2, world_pos: Vector2) -> float:
	var dist := world_pos.distance_to(reference_point)
	var distance_factor := clamp(1.0 - dist / radius, 0.0, 1.0)
	var age_factor := clamp(1.0 - _age / lifetime, 0.0, 1.0)
	return distance_factor * age_factor
