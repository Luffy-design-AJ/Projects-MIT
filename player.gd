extends CharacterBody2D

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

var is_casting = false
var cast_timer = 0
var is_eminating = false
var is_attacking = false
var eminate_timer = 0.0
var attack_timer = 0.0


var current_animation = ""





@onready var animated_sprite = $AnimatedSprite2D
@onready var swarm_controller = $SwarmController
@onready var melee_hitbox: Area2D = $MeleeHitbox




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

		var aim := _resolve_cast_aim()
		swarm_controller.cast(aim[0], aim[1])


	if Input.is_action_just_pressed("eminate"):

		is_eminating = true
		eminate_timer = 1
		swarm_controller.recall()

	if Input.is_action_just_pressed("toggle_aim_mode"):
		aim_mode = (aim_mode + 1) % 3
		print("Aim mode: ", AimMode.keys()[aim_mode])
	if Input.is_action_just_pressed("cycle_cast_pattern"):
		swarm_controller.cycle_pattern()
	if Input.is_action_just_pressed("Attack"):
		is_attacking = true
		attack_timer = 0.5
		_perform_melee_strike()

	# CAST TIMER
	if is_casting:

		cast_timer -= delta

		if cast_timer <= 0:
			is_casting = false
	# EMINATE TIMER
	if is_eminating:

		eminate_timer -= delta

		if eminate_timer <= 0:
			is_eminating = false
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
func _resolve_cast_aim() -> Array:
	match aim_mode:
		AimMode.MOUSE:
			var to_cursor := get_global_mouse_position() - global_position
			if to_cursor.length() < 0.001:
				return [last_direction, null]
			var direction := to_cursor.normalized()
			return [direction, swarm_controller.find_nearest_target(global_position, direction, 0.5)]
		AimMode.LOCK_ON:
			var target := swarm_controller.find_nearest_target(global_position)
			if target != null:
				return [(target.global_position - global_position).normalized(), target]
			return [last_direction, null]
		_:
			return [last_direction, swarm_controller.find_nearest_target(global_position, last_direction, 0.5)]

func _perform_melee_strike() -> void:
	for area in melee_hitbox.get_overlapping_areas():
		if area.is_in_group("swarm_targets") and area.has_method("take_damage"):
			area.take_damage(MELEE_DAMAGE)
