extends CharacterBody2D

const SPEED = 200.0
const DASH_SPEED = 900.0
const DASH_DURATION = 0.099
const CAST_DURATION = 0.84

var is_dashing = false
var dash_timer = 0.0
var dash_direction = Vector2.RIGHT
var last_direction = Vector2.RIGHT

var is_casting = false
var cast_timer = 0
var is_eminating = false
var is_attacking = false
var eminate_timer = 0.0
var attack_timer = 0.0


var current_animation = ""





@onready var animated_sprite = $AnimatedSprite2D
var projectile_scene = preload("res://scenes/rift_projectile.tscn")
var cast_projectile_pending = false




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
# CAST INPUT
	# CAST INPUT
	if Input.is_action_just_pressed("cast"):

		is_casting = true
		cast_timer = CAST_DURATION

		cast_projectile_pending = true

		
	if Input.is_action_just_pressed("eminate"):

		is_eminating = true
		eminate_timer = 1
	if Input.is_action_just_pressed("Attack"):
		is_attacking = true
		attack_timer = 0.5

	# CAST TIMER
	if is_casting:

		cast_timer -= delta

		if cast_timer <= 0:
			is_casting = false
	# SPAWN PROJECTILE MID-CAST
	if is_casting and cast_projectile_pending and cast_timer <= 0.1:

		cast_projectile_pending = false

		var projectile = projectile_scene.instantiate()

		projectile.global_position = global_position

		projectile.direction = last_direction

		get_parent().add_child(projectile)
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
