extends Area2D
class_name SwarmAgent

enum State { IDLE, DIRECTED }

const SEPARATION_RADIUS := 16.0
const SEPARATION_FORCE := 80.0
const NOISE_STRENGTH := 18.0
const STEER_LERP := 0.12
const DIRECTED_BASE_SPEED := 220.0
const DOT_PER_SECOND := 6.0

var state: int = State.IDLE
var velocity: Vector2 = Vector2.ZERO

# Idle orbit
var orbit_anchor: Node2D = null
var orbit_angle: float = 0.0
var orbit_radius: float = 40.0
var orbit_speed: float = 90.0

# Directed (cast) movement — set by SwarmController.enter_directed()
var cast_field = null
var directed_speed: float = DIRECTED_BASE_SPEED

# Wiring set by SwarmController at spawn time
var swarm_controller: Node = null
var neighbors: Array = []

var _noise_offset: float = 0.0

func _ready() -> void:
	add_to_group("swarm_agents")
	_noise_offset = randf() * TAU
	orbit_angle = randf() * TAU

func _physics_process(delta: float) -> void:
	var steer := Vector2.ZERO
	match state:
		State.IDLE:
			steer = _idle_steering(delta)
		State.DIRECTED:
			steer = _directed_steering()
	steer += _separation_steering()
	velocity = velocity.lerp(steer, STEER_LERP)
	global_position += velocity * delta
	_resolve_combat(delta)

func _idle_steering(delta: float) -> Vector2:
	if orbit_anchor == null:
		return Vector2.ZERO
	orbit_angle += (orbit_speed / orbit_radius) * delta
	var orbit_target: Vector2 = orbit_anchor.global_position + Vector2.RIGHT.rotated(orbit_angle) * orbit_radius
	var to_target := orbit_target - global_position
	var noise := Vector2.RIGHT.rotated(_noise_offset + Time.get_ticks_msec() * 0.001) * NOISE_STRENGTH
	return to_target.normalized() * orbit_speed + noise

func _directed_steering() -> Vector2:
	if cast_field == null or not is_instance_valid(cast_field):
		state = State.IDLE
		return Vector2.ZERO
	var sample: Array = cast_field.sample(global_position)
	var sample_direction: Vector2 = sample[0]
	var sample_strength: float = sample[1]
	if sample_strength <= 0.0:
		state = State.IDLE
		cast_field = null
		return Vector2.ZERO
	return sample_direction * directed_speed * sample_strength

func _separation_steering() -> Vector2:
	var push := Vector2.ZERO
	for neighbor in neighbors:
		if neighbor == self or not is_instance_valid(neighbor):
			continue
		var offset: Vector2 = global_position - neighbor.global_position
		var dist := offset.length()
		if dist > 0.0 and dist < SEPARATION_RADIUS:
			push += offset.normalized() * (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS
	return push * SEPARATION_FORCE

func _resolve_combat(delta: float) -> void:
	for area in get_overlapping_areas():
		if area.is_in_group("swarm_targets") and area.has_method("take_damage"):
			area.take_damage(DOT_PER_SECOND * delta)

func take_counter_damage(amount: float) -> void:
	if swarm_controller != null:
		swarm_controller.deplete_strength(amount)

func return_to_idle() -> void:
	state = State.IDLE
	cast_field = null

func enter_directed(field, speed_multiplier: float) -> void:
	state = State.DIRECTED
	cast_field = field
	directed_speed = DIRECTED_BASE_SPEED * speed_multiplier
