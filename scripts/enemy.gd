extends SwarmTarget
class_name Enemy

## Generic enemy. Behaviour is driven entirely by `type`; every future enemy
## type lands a new case in `_physics_process` rather than a new class. Like
## the swarm, an enemy never commands an ant directly — it expresses through
## the shared pheromone fields and the swarm reacts via its own scoring.

enum Type { PLACEHOLDER, ASSASSIN, PREDATOR, FIREWALL, BROODMOTHER, SIREN }

## Hades-style duel loop for the ASSASSIN: readable rhythm, dodgeable strikes,
## vulnerable recovery. It ignores the swarm and hunts only the player.
enum DuelState { STALK, WINDUP, STRIKE, BACKOFF, RECOVER }
enum PredState { SEARCH, CHARGE, RECOVER }
enum FirewallState { IDLE, MOVE }
enum SirenState { LURE, WINDUP, SNAP, RECOVER }

@export var type: Type = Type.PLACEHOLDER:
	set(value):
		type = value
		if is_node_ready():
			_apply_type()

@export_group("Shared")
@export var max_hp: float = 150.0
@export var counter_damage: float = 4.0
@export var counter_damage_interval: float = 1.0

@export_group("Assassin")
@export var move_speed: float = 90.0
## Distance at which the assassin stops stalking and begins a wind-up.
@export var strike_range: float = 45.0
@export var windup_time: float = 0.6
@export var lunge_speed: float = 420.0
@export var lunge_time: float = 0.22
@export var strike_damage: float = 12.0
@export var backoff_time: float = 0.4
@export var backoff_speed: float = 160.0
@export var recover_time: float = 0.8

@export_group("Predator")
@export var pred_search_radius: float = 151.0
@export var pred_cluster_threshold: int = 5
@export var pred_search_speed: float = 60.0
@export var pred_charge_speed: float = 320.0
@export var pred_charge_damage: float = 15.0
@export var pred_charge_duration: float = 0.6
@export var pred_recover_time: float = 0.4
## Fear flare (WINDUP + STRIKE only): radius in cells and the absolute hunt
## value stamped at the centre each frame while flaring. Negative scatters
## ants; positive would draw them in. Set to 0 to disable the flare entirely
## (currently off).
@export var aura_radius_cells: int = 5
@export var aura_strength: float = 0.0

var hp: float
var dead: bool = false

var duel_state: int = DuelState.STALK
var state_timer: float = 0.0
var aim_dir: Vector2 = Vector2.RIGHT
var struck_this_strike: bool = false

var pred_state: int = PredState.SEARCH
var pred_state_timer: float = 0.0
var pred_charge_dir: Vector2 = Vector2.RIGHT
var pred_hit_set: Dictionary = {}
var pred_grace_elapsed: float = 0.0
var pred_kill_chance: float = 0.125

@export_group("Firewall")
@export var firewall_max_hp: float = 350.0
@export var firewall_speed: float = 20.0
@export var firewall_accel: float = 200.0
@export var firewall_field_radius: float = 95.0
@export var firewall_distort_factor: float = 0.25
@export var firewall_noise: float = 0.12
@export var firewall_falloff_pow: float = 1.5
var firewall_state: int = FirewallState.MOVE
var firewall_vel: Vector2 = Vector2.ZERO

@export_group("Broodmother")
## Heavy hijacker: paints home pheromone so returning foragers treat it as a
## nest, then skims the food they bring. It does not kill ants — it starves
## your economy. Very slow, very tanky.
@export var broodmother_max_hp: float = 500.0
@export var broodmother_speed: float = 12.0
@export var broodmother_field_radius_cells: int = 6
@export var broodmother_emit_per_sec: float = 3.0
@export var broodmother_steal_radius_cells: float = 4.0
@export var broodmother_steal_heal: float = 10.0
var brood_stolen: int = 0

@export_group("Siren")
## Heavy bait: mimics the player's ATTRACT to gather the swarm, then snaps shut
## and devours everything caught in the lure. Lure → windup → snap → recover.
@export var siren_max_hp: float = 300.0
@export var siren_speed: float = 14.0
@export var siren_lure_radius_cells: int = 8
@export var siren_lure_emit_per_sec: float = 4.0
@export var siren_threshold: int = 6
@export var siren_windup_time: float = 0.9
@export var siren_snap_radius_cells: float = 5.0
@export var siren_snap_damage: float = 1000.0
@export var siren_recover_time: float = 1.6
var siren_state: int = SirenState.LURE
var siren_timer: float = 0.0
var siren_snaps: int = 0

@onready var counter_damage_timer: Timer = $CounterDamageTimer
@onready var hp_label: Label = $HPLabel


func _ready() -> void:
	super._ready()
	hp = max_hp
	_update_label()
	if type == Type.PLACEHOLDER:
		counter_damage_timer.wait_time = counter_damage_interval
		counter_damage_timer.timeout.connect(_on_counter_damage_timeout)
		counter_damage_timer.start()
	_apply_type()


## Applies configuration that depends on `type`. Called from `_ready()` and
## whenever `type` changes after the node is in the tree (e.g. `game.gd`
## selects the enemy once the scene, and therefore this node, is already ready).
func _apply_type() -> void:
	if type == Type.FIREWALL:
		max_hp = firewall_max_hp
		hp = max_hp
		firewall_vel = Vector2.ZERO
		if not is_in_group("firewalls"):
			add_to_group("firewalls")
		_update_label()
	elif type == Type.BROODMOTHER:
		max_hp = broodmother_max_hp
		hp = max_hp
		brood_stolen = 0
		_update_label()
	elif type == Type.SIREN:
		max_hp = siren_max_hp
		hp = max_hp
		siren_state = SirenState.LURE
		siren_timer = 0.0
		siren_snaps = 0
		_update_label()


func _physics_process(delta: float) -> void:
	match type:
		Type.ASSASSIN:
			_behave_assassin(delta)
		Type.PREDATOR:
			_behave_predator(delta)
		Type.FIREWALL:
			_behave_firewall(delta)
		Type.BROODMOTHER:
			_behave_broodmother(delta)
		Type.SIREN:
			_behave_siren(delta)


func take_damage(amount: float) -> void:
	hp = maxf(hp - amount, 0.0)
	_update_label()
	if hp <= 0.0 and not dead:
		dead = true
		queue_free()


## Ignores the swarm entirely and duels the player in a readable rhythm:
## stalk, telegraphed wind-up (the aim locks here, so the lunge is dodgeable),
## a single-hit lunge, a back-off hop away from the player, then a stationary
## vulnerable recovery. The fear field flares only while attacking and decays
## naturally through normal diffusion afterwards. No continuous contact
## damage; the swarm hurting this node on overlap is the counterplay.
func _behave_assassin(delta: float) -> void:
	var world := _get_world()
	var player := _nearest_player()
	if world == null or player == null:
		return

	state_timer -= delta
	match duel_state:
		DuelState.STALK:
			var to_player: Vector2 = player.global_position - global_position
			if to_player.length() <= strike_range:
				aim_dir = to_player.normalized()
				struck_this_strike = false
				_enter_state(DuelState.WINDUP, windup_time)
			else:
				_move_clamped(to_player.normalized() * move_speed * delta, world)
		DuelState.WINDUP:
			if aura_strength != 0.0:
				world.stamp_enemy_field(global_position, aura_radius_cells, aura_strength)
			if state_timer <= 0.0:
				_enter_state(DuelState.STRIKE, lunge_time)
		DuelState.STRIKE:
			if aura_strength != 0.0:
				world.stamp_enemy_field(global_position, aura_radius_cells, aura_strength)
			_move_clamped(aim_dir * lunge_speed * delta, world)
			if not struck_this_strike:
				for body in get_overlapping_bodies():
					if body is Player and body.has_method("take_damage"):
						body.take_damage(strike_damage, global_position)
						struck_this_strike = true
						break
			if state_timer <= 0.0:
				_enter_state(DuelState.BACKOFF, backoff_time)
		DuelState.BACKOFF:
			var away: Vector2 = (global_position - player.global_position).normalized()
			if away == Vector2.ZERO:
				away = -aim_dir
			_move_clamped(away * backoff_speed * delta, world)
			if state_timer <= 0.0:
				_enter_state(DuelState.RECOVER, recover_time)
		DuelState.RECOVER:
			if state_timer <= 0.0:
				duel_state = DuelState.STALK

	queue_redraw()


func _enter_state(next: int, duration: float) -> void:
	duel_state = next
	state_timer = duration


## Kinematic step kept inside the arena rectangle (small margin).
func _move_clamped(step: Vector2, world: SwarmWorld) -> void:
	global_position += step
	var margin := 16.0
	global_position.x = clampf(global_position.x, world.origin.x + margin, world.origin.x + world.arena_size.x - margin)
	global_position.y = clampf(global_position.y, world.origin.y + margin, world.origin.y + world.arena_size.y - margin)


func _nearest_player() -> Node2D:
	var parent := get_parent()
	if parent == null:
		return null
	var p := parent.get_node_or_null("Player")
	if p != null and is_instance_valid(p):
		return p
	return null


func _get_world() -> SwarmWorld:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("SwarmWorld") as SwarmWorld


func _on_counter_damage_timeout() -> void:
	for area in get_overlapping_areas():
		if area.is_in_group("swarm_agents") and area.has_method("take_damage"):
			area.take_damage(counter_damage)


func _update_label() -> void:
	if hp_label == null:
		return
	var text := "HP: %d / %d" % [int(hp), int(max_hp)]
	if type == Type.BROODMOTHER:
		text += "  Stolen: %d" % brood_stolen
	elif type == Type.SIREN:
		text += "  %s" % SirenState.keys()[siren_state]
	hp_label.text = text


func _draw() -> void:
	match type:
		Type.ASSASSIN:
			_draw_assassin()
		Type.PREDATOR:
			draw_circle(Vector2.ZERO, 16.0, Color(0.8, 0.3, 0.1, 0.95))
		Type.FIREWALL:
			_draw_firewall()
		Type.BROODMOTHER:
			_draw_broodmother()
		Type.SIREN:
			_draw_siren()
		_:
			draw_circle(Vector2.ZERO, 14.0, Color(0.55, 0.4, 0.75, 0.9))


## State read at a glance: dim red stalking, brightening pulse + growing aim
## line and danger ring while winding up, hot flash on the lunge, muted hop
## backing off, dark and desaturated while recovering.

func _behave_firewall(delta: float) -> void:
	var world := _get_world()
	var player := _nearest_player()
	if world == null:
		return
	var target: Vector2 = global_position
	if player != null:
		target = player.global_position
	var to_target: Vector2 = target - global_position
	var dir := Vector2.ZERO
	if to_target.length_squared() > 0.01:
		dir = to_target.normalized()
	var desired_vel := dir * firewall_speed
	firewall_vel = firewall_vel.move_toward(desired_vel, firewall_accel * delta)
	_move_clamped(firewall_vel * delta, world)


## Heavy hijacker. Crawls toward the player while continuously painting home
## pheromone around itself, so carrying foragers climb to it as if it were a
## nest and deposit their food — which the Broodmother skims, healing itself
## and starving the player's delivery economy. It never kills ants directly.
func _behave_broodmother(delta: float) -> void:
	var world := _get_world()
	if world == null:
		return
	var player := _nearest_player()
	if player != null:
		var to_player: Vector2 = player.global_position - global_position
		if to_player.length_squared() > 0.01:
			_move_clamped(to_player.normalized() * broodmother_speed * delta, world)
	# Hijack beacon — the swarm's own loyalty does the pulling.
	world.stamp_home_field(global_position, broodmother_field_radius_cells, broodmother_emit_per_sec * delta)
	# Skim deliveries from carrying ants that reach the beacon.
	var steal_px: float = broodmother_steal_radius_cells * world.cell_size
	var stole := false
	for agent in get_tree().get_nodes_in_group("swarm_agents"):
		if not is_instance_valid(agent) or not agent.carry:
			continue
		if global_position.distance_to(agent.global_position) <= steal_px:
			agent.carry = false
			brood_stolen += 1
			hp = minf(hp + broodmother_steal_heal, max_hp)
			stole = true
	if stole:
		_update_label()
	queue_redraw()


## Heavy bait. Mimics the player's ATTRACT to gather the swarm, telegraphs a
## windup, then snaps shut and devours everything in the lure. Then it recovers,
## giving the player a window to scatter the swarm or strike it.
func _behave_siren(delta: float) -> void:
	var world := _get_world()
	if world == null:
		return
	siren_timer -= delta
	var player := _nearest_player()
	if player != null:
		var to_player: Vector2 = player.global_position - global_position
		if to_player.length_squared() > 0.01 and siren_state != SirenState.SNAP:
			_move_clamped(to_player.normalized() * siren_speed * delta, world)
	match siren_state:
		SirenState.LURE:
			world.stamp_lure_field(global_position, siren_lure_radius_cells, siren_lure_emit_per_sec * delta)
			if _agents_within(world, siren_lure_radius_cells) >= siren_threshold:
				siren_state = SirenState.WINDUP
				siren_timer = siren_windup_time
		SirenState.WINDUP:
			# Keep baiting so the swarm does not wander off before the bite.
			world.stamp_lure_field(global_position, siren_lure_radius_cells, siren_lure_emit_per_sec * delta)
			if siren_timer <= 0.0:
				_siren_snap(world)
				siren_state = SirenState.RECOVER
				siren_timer = siren_recover_time
		SirenState.RECOVER:
			if siren_timer <= 0.0:
				siren_state = SirenState.LURE
	queue_redraw()


func _agents_within(world: SwarmWorld, radius_cells: float) -> int:
	var r: float = radius_cells * world.cell_size
	var n := 0
	for agent in get_tree().get_nodes_in_group("swarm_agents"):
		if is_instance_valid(agent) and global_position.distance_to(agent.global_position) <= r:
			n += 1
	return n


func _siren_snap(world: SwarmWorld) -> void:
	var r: float = siren_snap_radius_cells * world.cell_size
	for agent in get_tree().get_nodes_in_group("swarm_agents"):
		if is_instance_valid(agent) and global_position.distance_to(agent.global_position) <= r:
			agent.take_damage(siren_snap_damage)
	siren_snaps += 1
	_update_label()


func _behave_predator(delta: float) -> void:
	var world := _get_world()
	if world == null:
		return
	pred_state_timer -= delta
	pred_grace_elapsed += delta
	if pred_grace_elapsed < 15.0:
		return
	match pred_state:
		PredState.SEARCH:
			var sum := Vector2.ZERO
			var count: int = 0
			var agents = get_tree().get_nodes_in_group("swarm_agents")
			for agent in agents:
				var dist := global_position.distance_to(agent.global_position)
				if dist <= pred_search_radius:
					sum += agent.global_position
					count += 1
			# Also check swarm density near player if player is in range
			var player := _nearest_player()
			if count < pred_cluster_threshold and player != null and global_position.distance_to(player.global_position) <= pred_search_radius * 1.2:
				var pcount: int = 0
				var psum := Vector2.ZERO
				for agent in agents:
					var dist := player.global_position.distance_to(agent.global_position)
					if dist <= 90.0:
						psum += agent.global_position
						pcount += 1
				if pcount >= pred_cluster_threshold:
					sum = psum
					count = pcount
			if count >= pred_cluster_threshold:
				var centroid = sum / float(count)
				pred_charge_dir = (centroid - global_position)
				if pred_charge_dir.length() < 0.001:
					pred_charge_dir = Vector2.RIGHT
				else:
					pred_charge_dir = pred_charge_dir.normalized()
				pred_hit_set.clear()
				pred_state = PredState.CHARGE
				pred_state_timer = pred_charge_duration
			else:
				_move_clamped(pred_charge_dir * pred_search_speed * 0.1 * delta, world)
		PredState.CHARGE:
			_move_clamped(pred_charge_dir * pred_charge_speed * delta, world)
			for area in get_overlapping_areas():
				if area.is_in_group("swarm_agents") and area.has_method("take_damage"):
					var id: int = area.get_instance_id()
					if not pred_hit_set.has(id):
						pred_hit_set[id] = true
						if randf() < pred_kill_chance:
							if area.has_method("take_damage"):
								area.take_damage(250.0)
			if pred_state_timer <= 0.0:
				pred_state = PredState.RECOVER
				pred_state_timer = pred_recover_time
		PredState.RECOVER:
			if pred_state_timer <= 0.0:
				pred_state = PredState.SEARCH
	queue_redraw()
func _draw_assassin() -> void:
	match duel_state:
		DuelState.STALK:
			draw_circle(Vector2.ZERO, 14.0, Color(0.62, 0.2, 0.2, 0.85))
		DuelState.WINDUP:
			var t := clampf(1.0 - state_timer / maxf(windup_time, 0.001), 0.0, 1.0)
			draw_circle(Vector2.ZERO, 14.0, Color(0.95, 0.25, 0.2, 0.7 + 0.3 * t))
			draw_line(Vector2.ZERO, aim_dir * (22.0 + 52.0 * t), Color(1.0, 0.9, 0.6, 0.4 + 0.6 * t), 3.0)
			draw_arc(Vector2.ZERO, strike_range * t, 0.0, TAU, 24, Color(1.0, 0.55, 0.4, 0.25 + 0.45 * t), 2.0)
		DuelState.STRIKE:
			draw_circle(Vector2.ZERO, 15.0, Color(1.0, 0.55, 0.25, 0.95))
			draw_line(Vector2.ZERO, aim_dir * 28.0, Color(1.0, 0.85, 0.5, 0.9), 4.0)
		DuelState.BACKOFF:
			draw_circle(Vector2.ZERO, 13.0, Color(0.5, 0.22, 0.38, 0.85))
		DuelState.RECOVER:
			draw_circle(Vector2.ZERO, 12.0, Color(0.34, 0.17, 0.17, 0.65))
	draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 24, Color(0.95, 0.4, 0.4, 0.8), 2.0)

func _draw_firewall() -> void:
	# Faint ring telegraphs the distortion field's true extent.
	draw_arc(Vector2.ZERO, firewall_field_radius, 0.0, TAU, 48, Color(0.4, 0.65, 1.0, 0.18), 2.0)
	draw_circle(Vector2.ZERO, 22.0, Color(0.25, 0.35, 0.6, 0.6))
	draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 24, Color(0.45, 0.7, 1.0, 0.9), 3.0)
	draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 16, Color(0.3, 0.5, 0.9, 0.7), 2.0)


func _draw_broodmother() -> void:
	var world := _get_world()
	if world != null:
		draw_arc(Vector2.ZERO, float(broodmother_field_radius_cells) * world.cell_size, 0.0, TAU, 48, Color(0.7, 0.9, 0.4, 0.16), 2.0)
	draw_circle(Vector2.ZERO, 26.0, Color(0.34, 0.16, 0.38, 0.75))
	draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 24, Color(0.85, 0.5, 1.0, 0.9), 3.0)
	draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 16, Color(0.95, 0.75, 1.0, 0.7), 2.0)


func _draw_siren() -> void:
	var world := _get_world()
	match siren_state:
		SirenState.LURE:
			draw_circle(Vector2.ZERO, 18.0, Color(0.18, 0.55, 0.5, 0.8))
			if world != null:
				draw_arc(Vector2.ZERO, float(siren_lure_radius_cells) * world.cell_size, 0.0, TAU, 48, Color(0.4, 0.95, 0.85, 0.16), 2.0)
		SirenState.WINDUP:
			var t := clampf(1.0 - siren_timer / maxf(siren_windup_time, 0.001), 0.0, 1.0)
			draw_circle(Vector2.ZERO, 18.0, Color(0.95, 0.7, 0.2, 0.7 + 0.3 * t))
			draw_arc(Vector2.ZERO, 18.0 + 22.0 * t, 0.0, TAU, 24, Color(1.0, 0.85, 0.4, 0.5 + 0.5 * t), 3.0)
		SirenState.SNAP:
			draw_circle(Vector2.ZERO, 24.0, Color(1.0, 0.32, 0.2, 0.95))
		SirenState.RECOVER:
			draw_circle(Vector2.ZERO, 16.0, Color(0.28, 0.34, 0.3, 0.6))
	draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 24, Color(0.5, 0.9, 0.8, 0.8), 2.0)
