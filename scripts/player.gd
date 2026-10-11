extends CharacterBody2D
class_name Player

const SPEED = 200.0
const DASH_SPEED = 900.0
const DASH_DURATION = 0.099
const CAST_DURATION = 0.84
const MELEE_DAMAGE := 18.0
const MAX_HP := 100.0
const INVULN_DURATION := 0.6

var is_dashing = false
var dash_timer = 0.0
var dash_direction = Vector2.RIGHT
var last_direction = Vector2.RIGHT

enum AimMode { DIRECTIONAL, MOUSE, LOCK_ON }
var aim_mode: int = AimMode.DIRECTIONAL

enum EminateMode { ATTRACT, SCATTER }
var eminate_mode: int = EminateMode.ATTRACT

enum BombMode { ATTRACT, SCATTER }
var bomb_mode: int = BombMode.ATTRACT

enum HuntPattern { DIRECT, LOOP, MULTI, BOUNCE }
var hunt_pattern: int = HuntPattern.DIRECT
var nest_pheromone_enabled: bool = true

## Mechanic progression stages. CONTROL and CARNAGE are direct-command modes
## (built later). LOCKOUT freezes the player and zeros all pheromone fields so
## ants wander on their base physics. SPRAY -> EMINATE -> BEACON -> HUNT -> BOMB
## is the scalar-field unlock ladder; each stage gates only its own abilities.
enum Stage { CONTROL, CARNAGE, LOCKOUT, SPRAY, EMINATE, BEACON, HUNT, BOMB }
var stage: int = Stage.SPRAY

var hunt_unlocked := false       # cast (hunt pheromone) works
var all_hunt_unlocked := false   # loop/multi/bounce patterns available
var eminate_unlocked := false
var beacon_unlocked := false
var bomb_unlocked := true
var input_locked := false        # CARNAGE / LOCKOUT: player frozen
var is_control_mode := false     # CONTROL: casts are direct commands
var _was_eminating := false      # edge-trigger for the control eminate release

var is_casting = false
var cast_timer = 0
var is_eminating = false
var is_attacking = false
var attack_timer = 0.0

var hp: float = MAX_HP
var invuln_timer: float = 0.0
var hit_timer: float = 0.0

var bomb_aiming: bool = false
var bomb_reticle_pos: Vector2 = Vector2.ZERO
const BOMB_RETICLE_SPEED: float = 200.0

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
	set_stage(stage)


## Single source of truth for the mechanic ladder. Every player ability gates on
## these boolean flags; only this method mutates them.
func set_stage(s: int) -> void:
	stage = s
	input_locked = (s == Stage.CARNAGE or s == Stage.LOCKOUT)
	is_control_mode = (s == Stage.CONTROL)
	hunt_unlocked = (is_control_mode or s >= Stage.SPRAY) and not input_locked
	# CONTROL hands every ability the keys one-by-one, but each one is routed
	# through the direct-command layer instead of the scalar fields.
	all_hunt_unlocked = is_control_mode or s >= Stage.HUNT
	eminate_unlocked = is_control_mode or s >= Stage.EMINATE
	beacon_unlocked = is_control_mode or s >= Stage.BEACON
	bomb_unlocked = is_control_mode or s >= Stage.BOMB
	if not all_hunt_unlocked:
		hunt_pattern = HuntPattern.DIRECT
	if input_locked:
		bomb_aiming = false
		is_eminating = false
		velocity = Vector2.ZERO
	if is_control_mode or not beacon_unlocked:
		nest_pheromone_enabled = false
		if swarm_world != null and swarm_world.has_method("set_nest_emit_enabled"):
			swarm_world.set_nest_emit_enabled(false)
	elif not nest_pheromone_enabled:
		nest_pheromone_enabled = true
		if swarm_world != null and swarm_world.has_method("set_nest_emit_enabled"):
			swarm_world.set_nest_emit_enabled(true)
	if swarm_world != null and swarm_world.has_method("set_mode"):
		swarm_world.set_mode(s)
	print("Stage: ", stage_name())


func stage_name() -> String:
	return Stage.keys()[stage]


## P key: advance the gameplay ladder SPRAY -> EMINATE -> BEACON -> HUNT -> BOMB.
func advance_progress() -> void:
	var ladder: Array[int] = [Stage.SPRAY, Stage.EMINATE, Stage.BEACON, Stage.HUNT, Stage.BOMB]
	var i: int = ladder.find(stage)
	if i < 0:
		i = 0
	set_stage(ladder[(i + 1) % ladder.size()])


## F key: cycle every stage live in enum order (CONTROL and CARNAGE included).
func cycle_stage() -> void:
	var all: Array[int] = [
		Stage.CONTROL, Stage.CARNAGE, Stage.LOCKOUT, Stage.SPRAY, Stage.EMINATE,
		Stage.BEACON, Stage.HUNT, Stage.BOMB,
	]
	var i: int = all.find(stage)
	if i < 0:
		i = 0
	set_stage(all[(i + 1) % all.size()])


func _physics_process(delta: float) -> void:

	var direction = Vector2.ZERO

	if not input_locked:
		# INPUT
		direction.x = Input.get_axis("move_left", "move_right")
		direction.y = Input.get_axis("move_up", "move_down")

	direction = direction.normalized()

	# SAVE LAST DIRECTION
	if direction != Vector2.ZERO:
		last_direction = direction

	# BOMB INPUT
	if Input.is_action_just_pressed("drop_bomb") and bomb_unlocked:
		if not bomb_aiming:
			bomb_aiming = true
			bomb_reticle_pos = global_position + last_direction * 40.0
			velocity = Vector2.ZERO
			queue_redraw()
		elif is_instance_valid(swarm_world) and swarm_world.has_method("drop_bomb"):
			_drop_bomb()

	# CAST INPUT
	if Input.is_action_just_pressed("cast") and hunt_unlocked:

		is_casting = true
		cast_timer = CAST_DURATION

		# Cast stamps the active hunt pattern (hunt pheromone the ants follow).
		_resolve_and_cast()


	if Input.is_action_just_pressed("cycle_cast_pattern") and all_hunt_unlocked:
		hunt_pattern = (hunt_pattern + 1) % 4
		print("Cast pattern: ", hunt_pattern_name())

	if Input.is_action_just_pressed("cycle_eminate_mode") and eminate_unlocked:
		eminate_mode = (eminate_mode + 1) % 2
		print("Eminate mode: ", EminateMode.keys()[eminate_mode])

	if Input.is_action_just_pressed("cycle_bomb_mode") and bomb_unlocked:
		bomb_mode = (bomb_mode + 1) % 2
		print("Bomb mode: ", BombMode.keys()[bomb_mode])

	# Eminate: controller pulls the swarm in (attract) or pushes it away
	# (scatter). In CONTROL it is a direct order, otherwise hunt pheromone.
	var now_emitting: bool = Input.is_action_pressed("eminate") and eminate_unlocked
	is_eminating = now_emitting
	if swarm_world != null:
		if is_control_mode:
			if now_emitting:
				swarm_world.command_eminate(global_position, eminate_mode, true)
			elif _was_eminating:
				# Edge-triggered release - otherwise this would clear a standing
				# rally order (the nest toggle) every single frame.
				swarm_world.command_eminate(global_position, eminate_mode, false)
		elif now_emitting and swarm_world.has_method("eminate_at"):
			swarm_world.eminate_at(global_position, eminate_mode)
	_was_eminating = now_emitting

	if Input.is_action_just_pressed("toggle_aim_mode"):
		aim_mode = (aim_mode + 1) % 3
		print("Aim mode: ", AimMode.keys()[aim_mode])

	if Input.is_action_just_pressed("toggle_nest_pheromone") and beacon_unlocked:
		if is_control_mode:
			# CONTROL: the nest beacon is a rally order - gather the swarm here.
			nest_pheromone_enabled = not nest_pheromone_enabled
			swarm_world.command_rally(global_position, nest_pheromone_enabled)
			print("Rally order: ", "ON" if nest_pheromone_enabled else "OFF")
		else:
			nest_pheromone_enabled = not nest_pheromone_enabled
			if swarm_world != null and swarm_world.has_method("set_nest_emit_enabled"):
				swarm_world.set_nest_emit_enabled(nest_pheromone_enabled)
			print("Nest pheromone: ", "ON" if nest_pheromone_enabled else "OFF")

	if Input.is_action_just_pressed("Attack") and not input_locked:
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

	# HIT TIMER
	if hit_timer > 0.0:
		hit_timer -= delta

	# INVULN TIMER
	if invuln_timer > 0.0:
		invuln_timer -= delta

	# BOMB AIMING: WASD drives reticle, arrows still move player
	if bomb_aiming:
		var reticle_input := Vector2.ZERO
		reticle_input.x = Input.get_axis("aim_left", "aim_right")
		reticle_input.y = Input.get_axis("aim_up", "aim_down")
		if reticle_input.length() > 0.01:
			bomb_reticle_pos += reticle_input.normalized() * BOMB_RETICLE_SPEED * delta
		if is_instance_valid(swarm_world):
			bomb_reticle_pos.x = clampf(bomb_reticle_pos.x, swarm_world.origin.x, swarm_world.origin.x + swarm_world.arena_size.x)
			bomb_reticle_pos.y = clampf(bomb_reticle_pos.y, swarm_world.origin.y, swarm_world.origin.y + swarm_world.arena_size.y)
		queue_redraw()

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
		if Input.is_action_just_pressed("dash") and not input_locked:

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
	elif hit_timer > 0.0:
		new_animation = "Hit"
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

func bomb_mode_name() -> String:
	return BombMode.keys()[bomb_mode].to_lower()

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
	if swarm_world == null:
		return
	var aim: Array = _resolve_cast_aim()
	if is_control_mode:
		# CONTROL: no pheromone - the cast is a direct order shaped by the active
		# hunt pattern (direct / loop / bounce; multi splits across all targets).
		var cmd_target: Node2D = aim[1]
		var cmd_pos: Vector2 = (cmd_target.global_position if (cmd_target != null and is_instance_valid(cmd_target)) else (global_position + aim[0] * 200.0))
		swarm_world.command_swarm_pattern(cmd_pos, aim[0], hunt_pattern, cmd_target)
		_spawn_cast_flash(aim[0])
		return
	if not swarm_world.has_method("cast_hunt"):
		return
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


func _drop_bomb() -> void:
	bomb_aiming = false
	if is_control_mode:
		# CONTROL bomb reticle is a direct point-order: attract bunches the
		# swarm on the cell, scatter runs them off it. No pheromone.
		swarm_world.command_point_bomb(bomb_reticle_pos, bomb_mode)
	else:
		swarm_world.drop_bomb(bomb_reticle_pos, bomb_mode)
	_spawn_bomb_flash(bomb_reticle_pos)
	queue_redraw()
	print("Bomb dropped at cell ", swarm_world.world_to_cell(bomb_reticle_pos),
		" mode=", BombMode.keys()[bomb_mode], " direct=", "yes" if is_control_mode else "no")


func _spawn_bomb_flash(at: Vector2) -> void:
	var flash := Polygon2D.new()
	flash.name = "BombFlash"
	var n_seg := 24
	var radius := 50.0
	var pts := PackedVector2Array()
	for i in range(n_seg + 1):
		var angle := TAU * float(i) / float(n_seg)
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	flash.polygon = pts
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash.material = mat
	if bomb_mode == BombMode.SCATTER:
		flash.color = Color(1.0, 0.3, 0.15, 0.6)
	else:
		flash.color = Color(1.0, 0.8, 0.2, 0.6)
	flash.position = at - global_position
	add_child(flash)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector2(1.5, 1.5), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(flash.queue_free)


func _draw() -> void:
	if not bomb_aiming:
		return
	var local := bomb_reticle_pos - global_position
	var ring_r := 40.0
	if is_instance_valid(swarm_world):
		ring_r = swarm_world.cell_size * float(swarm_world.bomb_radius_cells) * 0.3
	var ring_color := Color(1.0, 0.9, 0.3, 0.7) if bomb_mode == BombMode.ATTRACT else Color(1.0, 0.35, 0.2, 0.7)
	var n_seg := 32
	var pts := PackedVector2Array()
	for i in range(n_seg + 1):
		var angle := TAU * float(i) / float(n_seg)
		pts.append(local + Vector2(cos(angle), sin(angle)) * ring_r)
	draw_polyline(pts, ring_color, 2.0)
	draw_circle(local, 4.0, ring_color)


## Enemy → player damage with a short invulnerability window so overlapping
## contact drains HP in steps instead of instantly. `from` (optional) knocks
## the player away from the source.
func take_damage(amount: float, from: Vector2 = Vector2.ZERO) -> void:
	if invuln_timer > 0.0:
		return
	invuln_timer = INVULN_DURATION
	hit_timer = 0.4
	hp = maxf(hp - amount, 0.0)
	if from != Vector2.ZERO:
		velocity = (global_position - from).normalized() * 140.0
