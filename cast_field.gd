extends Node2D
class_name CastField

@export var lifetime: float = 1.2
@export var radius: float = 260.0

const WAYPOINT_HOLD_TIME := 0.35
const WAYPOINT_SIDE_OFFSET := 70.0

var direction: Vector2 = Vector2.RIGHT
var anchor: Vector2 = Vector2.ZERO
var pattern: CastPattern = null

var waypoints: Array = []
var _waypoint_index: int = 0
var _waypoint_timer: float = 0.0

var _age: float = 0.0

func _ready() -> void:
	if pattern.shape == CastPattern.Shape.WAYPOINT:
		_build_waypoints()

func _physics_process(delta: float) -> void:
	_age += delta
	if pattern.shape == CastPattern.Shape.WAYPOINT and _waypoint_index < waypoints.size() - 1:
		_waypoint_timer += delta
		if _waypoint_timer >= WAYPOINT_HOLD_TIME:
			_waypoint_timer = 0.0
			_waypoint_index += 1
	if _age >= lifetime:
		queue_free()

func _build_waypoints() -> void:
	var start := global_position
	var perpendicular := (anchor - start).orthogonal().normalized()
	waypoints.clear()
	for i in range(1, pattern.waypoint_count + 1):
		var t := float(i) / float(pattern.waypoint_count)
		var point := start.lerp(anchor, t)
		var side := -1.0 if i % 2 == 0 else 1.0
		point += perpendicular * side * WAYPOINT_SIDE_OFFSET * (1.0 - t)
		waypoints.append(point)

## Returns [direction: Vector2, strength: float] for the given world position.
## strength is 0 once the field has nothing left to offer (out of range or expired).
func sample(world_pos: Vector2) -> Array:
	match pattern.shape:
		CastPattern.Shape.PULSE:
			return [direction, _falloff(global_position, world_pos) * pattern.field_strength]
		CastPattern.Shape.CONE:
			return _sample_cone(world_pos)
		CastPattern.Shape.TANGENTIAL:
			return _sample_tangential(world_pos)
		CastPattern.Shape.WAYPOINT:
			return _sample_waypoint(world_pos)
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

func _sample_tangential(world_pos: Vector2) -> Array:
	var to_anchor := anchor - world_pos
	if to_anchor.length() < 0.001:
		return [direction, pattern.field_strength]
	var radial := to_anchor.normalized()
	var tangent := radial.orthogonal()
	var blended := (radial + tangent * pattern.curve_bias).normalized()
	return [blended, _falloff(anchor, world_pos) * pattern.field_strength]

func _sample_waypoint(world_pos: Vector2) -> Array:
	if waypoints.is_empty():
		return [direction, 0.0]
	var target: Vector2 = waypoints[_waypoint_index]
	var to_target := target - world_pos
	if to_target.length() < 0.001:
		return [direction, pattern.field_strength]
	return [to_target.normalized(), _falloff(target, world_pos) * pattern.field_strength]

func _falloff(reference_point: Vector2, world_pos: Vector2) -> float:
	var dist := world_pos.distance_to(reference_point)
	var distance_factor := clamp(1.0 - dist / radius, 0.0, 1.0)
	var age_factor := clamp(1.0 - _age / lifetime, 0.0, 1.0)
	return distance_factor * age_factor
