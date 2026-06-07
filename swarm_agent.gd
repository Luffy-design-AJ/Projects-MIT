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

var orbit_anchor: Vector2 = Vector2.ZERO
var orbit_angle: float = 0.0
var orbit_radius: float = 40.0
var orbit_speed: float = 1.0

var cast_field: Node = null
var directed_speed: float = DIRECTED_BASE_SPEED

var swarm_controller: Node = null
var neighbors: Array = []

var _noise_offset: float = 0.0

func _ready() -> void:
	_noise_offset = randf() * TAU
	orbit_angle = randf() * TAU

func _physics_process(delta: float) -> void:
	var steering: Vector2
	match state:
		State.IDLE:
			steering = _idle_steering(delta)
		State.DIRECTED:
			steering = _directed_steering(delta)
		_:
			steering = Vector2.ZERO

	steering += _separation_steering()

	var target_speed: float = directed_speed if state == State.DIRECTED else orbit_speed * orbit_radius
	velocity = velocity.lerp(steering, STEER_LERP)
	global_position += velocity * delta

	_resolve_combat(delta)

func _idle_steering(delta: float) -> Vector2:
	orbit_angle += orbit_speed * delta
	var target_point: Vector2 = orbit_anchor + Vector2(cos(orbit_angle), sin(orbit_angle)) * orbit_radius

	_noise_offset += delta
	var noise_vec := Vector2(
		cos(_noise_offset * 1.7),
		sin(_noise_offset * 2.3)
	) * NOISE_STRENGTH

	var to_target: Vector2 = (target_point - global_position)
	return to_target + noise_vec

func _directed_steering(_delta: float) -> Vector2:
	return Vector2.ZERO  # filled in by Task 5

func _separation_steering() -> Vector2:
	var push := Vector2.ZERO
	for neighbor in neighbors:
		if neighbor == self or not is_instance_valid(neighbor):
			continue
		var offset: Vector2 = global_position - neighbor.global_position
		var dist: float = offset.length()
		if dist > 0.0 and dist < SEPARATION_RADIUS:
			push += offset.normalized() * (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS * SEPARATION_FORCE
	return push

func _resolve_combat(_delta: float) -> void:
	pass  # filled in by Task 6

func return_to_idle() -> void:
	state = State.IDLE
	cast_field = null
