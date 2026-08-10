extends CharacterBody2D
class_name Player

const SPEED = 200.0
const DASH_SPEED = 900.0
const DASH_DURATION = 0.099
const CAST_DURATION = 0.84
const MELEE_DAMAGE := 18.0

var is_dashing = false
var dash_timer = 0.0
var dash_direction = Vector2.RIGHT
var last_direction = Vector2.RIGHT

enum AimMode { DIRECTIONAL, MOUSE, LOCK_ON }
var aim_mode: int = AimMode.DIRECTIONAL

enum EminateMode { ATTRACT, SCATTER }
var eminate_mode: int = EminateMode.ATTRACT

enum HuntPattern { DIRECT, LOOP, MULTI, BOUNCE }
var hunt_pattern: int = HuntPattern.DIRECT

var is_casting = false
var cast_timer = 0
var is_eminating = false
var is_attacking = false
var attack_timer = 0.0

var swarm_world: Node2D = null


@onready var animated_sprite = $AnimatedSprite2D
@onready var melee_hitbox: Area2D = $MeleeHitbox


var current_animation = ""


func _ready() -> void:
	var parent := get_parent()
	if parent != null and parent.has_node("SwarmWorld"):
		swarm_world = parent.get_node("SwarmWorld")
		if swarm_world != null and swarm_world.has_method("set_nest_carrier"):
			swarm_world.set_nest_carrier(self)


func _physics_process(delta: float) -> void:

	var direction = Vector2.ZERO

	# INPUT
	direction.x = Input.get_axis("move_left", "move_right")
	direction.y = Input.get_axis("move_up", "move_down")

	direction = direction.normalized()

	# SAVE LAST DIRECTION
	if direction != Vector2.ZERO:
		last_direction = direction

	# CAST INPUT
	if Input.is_action_just_pressed("cast"):

		is_casting = true
		cast_timer = CAST_DURATION

		# Cast stamps the active hunt pattern (hunt pheromone the ants follow).
		_resolve_and_cast()


	if Input.is_action_just_pressed("cycle_cast_pattern"):
		hunt_pattern = (hunt_pattern + 1) % 4
		print("Cast pattern: ", hunt_pattern_name())

	if Input.is_action_just_pressed("cycle_eminate_mode"):
		eminate_mode = (eminate_mode + 1) % 2
		print("Eminate mode: ", EminateMode.keys()[eminate_mode])

	# Eminate emits hunt pheromone while held (attract: ants follow, scatter: ants flee).
	is_eminating = Input.is_action_pressed("eminate")
	if is_eminating and swarm_world != null and swarm_world.has_method("eminate_at"):
		swarm_world.eminate_at(global_position, eminate_mode)

	if Input.is_action_just_pressed("toggle_aim_mode"):
		aim_mode = (aim_mode + 1) % 3
		print("Aim mode: ", AimMode.keys()[aim_mode])
	if Input.is_action_just_pressed("Attack"):
		is_attacking = true
		attack_timer = 0.5
		_perform_melee_strike()

	# CAST TIMER
	if is_casting:

		cast_timer -= delta

		if cast_timer <= 0:
			is_casting = false
	# ATTACK TIMER
	if is_attacking:

		attack_timer -= delta

		if attack_timer <= 0:
			is_attacking = false
	

	# DASH LOGIC
	if is_dashing:

		velocity = dash_direction * DASH_SPEED

		dash_timer -= delta

		if dash_timer <= 0:
			is_dashing = false

	# NORMAL MOVEMENT
	else:

		velocity = direction * SPEED

		# START DASH
		if Input.is_action_just_pressed("dash"):

			is_dashing = true
			dash_timer = DASH_DURATION

			# Dash in movement direction
			if direction != Vector2.ZERO:
				dash_direction = direction
			else:
				dash_direction = last_direction

	# DIRECTIONAL FACING
	if velocity.x > 0:
		animated_sprite.flip_h = false
	elif velocity.x < 0:
		animated_sprite.flip_h = true

	# ANIMATIONS
	var new_animation = ""

	# CAST
	if is_casting:

		new_animation = "Cast"
	elif is_eminating:
		new_animation = "Eminate"
	elif is_attacking:
		new_animation = "Attack"
	elif is_dashing:

		# DASH RIGHT
		if dash_direction.x > 0:
			new_animation = "DashRight"

		# DASH LEFT
		elif dash_direction.x < 0:
			new_animation = "DashLeft"

		# DASH UP/DOWN FALLBACK
		else:
			new_animation = "DashRight"

	# WALKING
	elif direction != Vector2.ZERO:

		if velocity.x == 0:
			if direction.y < 0:
				new_animation = "Walk_up"

			# DOWN
			elif direction.y > 0:
				new_animation = "Walk_down"

		# SIDE
		else:
			new_animation = "Run"

	# IDLE
	else:

		new_animation = "Rest"

	# ONLY CHANGE ANIMATION IF DIFFERENT
	if current_animation != new_animation:

		current_animation = new_animation
		animated_sprite.play(current_animation)



	move_and_slide()


## Returns [direction: Vector2, target: Node2D (or null)] for the active aim mode.
## Kept controller-free until pheromone abilities land in later phases.
func _resolve_cast_aim() -> Array:
	match aim_mode:
		AimMode.MOUSE:
			var to_cursor: Vector2 = get_global_mouse_position() - global_position
			if to_cursor.length() < 0.001:
				return [last_direction, null]
			return [to_cursor.normalized(), null]
		AimMode.LOCK_ON:
			var target: Node2D = _nearest_target(global_position)
			if target != null:
				return [(target.global_position - global_position).normalized(), target]
			return [last_direction, null]
		_:
			return [last_direction, null]

func _nearest_target_in_cone(from_position: Vector2, preferred_direction: Vector2, cos_angle: float) -> Node2D:
	if preferred_direction == Vector2.ZERO:
		return _nearest_target(from_position)
	var best: Node2D = null
	var best_dist: float = INF
	for target in get_tree().get_nodes_in_group("swarm_targets"):
		if not is_instance_valid(target):
			continue
		var to_target: Vector2 = target.global_position - from_position
		var dist: float = to_target.length()
		if dist >= best_dist or dist <= 0.001:
			continue
		if preferred_direction.normalized().dot(to_target.normalized()) < cos_angle:
			continue
		best = target
		best_dist = dist
	return best

func _nearest_target(from_position: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist: float = INF
	for target in get_tree().get_nodes_in_group("swarm_targets"):
		if not is_instance_valid(target):
			continue
		var dist: float = from_position.distance_to(target.global_position)
		if dist < best_dist:
			best_dist = dist
			best = target
	return best

func eminate_mode_name() -> String:
	return EminateMode.keys()[eminate_mode].to_lower()

func hunt_pattern_name() -> String:
	match hunt_pattern:
		HuntPattern.LOOP:
			return "Loop Hunt"
		HuntPattern.MULTI:
			return "Multi-target Hunt"
		HuntPattern.BOUNCE:
			return "Bounce Hunt"
		_:
			return "Direct Hunt"

func _hunt_pattern_id() -> String:
	match hunt_pattern:
		HuntPattern.LOOP:
			return "loop"
		HuntPattern.MULTI:
			return "multi"
		HuntPattern.BOUNCE:
			return "bounce"
		_:
			return "direct"

func _resolve_and_cast() -> void:
	if swarm_world == null or not swarm_world.has_method("cast_hunt"):
		return
	var aim: Array = _resolve_cast_aim()
	swarm_world.cast_hunt(global_position, aim[0], _hunt_pattern_id(), aim[1])
	_spawn_cast_flash(aim[0])

## Brief additive V-shaped flash in the aim direction so a cast is visible even
## though the pheromone layer is hidden. Purely cosmetic; the swarm reacts to
## the hunt pheromone stamped by cast_hunt().
func _spawn_cast_flash(aim_dir: Vector2) -> void:
	if aim_dir == Vector2.ZERO:
		aim_dir = Vector2.RIGHT
	var flash := Polygon2D.new()
	flash.name = "CastFlash"
	var spread := deg_to_rad(35.0)
	var radius := 60.0
	var pts := PackedVector2Array()
	pts.append(Vector2.ZERO)
	pts.append(Vector2(radius, 0.0).rotated(-spread))
	pts.append(Vector2(radius, 0.0).rotated(spread))
	flash.polygon = pts
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash.material = mat
	flash.color = Color(1.0, 0.85, 0.5, 0.55)
	flash.rotation = aim_dir.angle()
	flash.scale = Vector2(0.4, 0.4)
	add_child(flash)
	flash.position = Vector2.ZERO
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(flash.queue_free)

func _perform_melee_strike() -> void:
	for area in melee_hitbox.get_overlapping_areas():
		if area.is_in_group("swarm_targets") and area.has_method("take_damage"):
			area.take_damage(MELEE_DAMAGE)
