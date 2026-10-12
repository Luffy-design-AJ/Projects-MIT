extends SwarmTarget
class_name Enemy

## Generic enemy. Behaviour is driven entirely by `type`; every future enemy
## type lands a new case in `_physics_process` rather than a new class. Like
## the swarm, an enemy never commands an ant directly — it expresses through
## the shared pheromone fields and the swarm reacts via its own scoring.

enum Type { PLACEHOLDER, ASSASSIN, PREDATOR }

## Hades-style duel loop for the ASSASSIN: readable rhythm, dodgeable strikes,
## vulnerable recovery. It ignores the swarm and hunts only the player.
enum DuelState { STALK, WINDUP, STRIKE, BACKOFF, RECOVER }
enum PredState { SEARCH, CHARGE, RECOVER }

@export var type: Type = Type.PLACEHOLDER

@export_group("Shared")
@export var max_hp: float = 100.0
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
@export var pred_search_radius: float = 150.0
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


func _physics_process(delta: float) -> void:
	match type:
		Type.ASSASSIN:
			_behave_assassin(delta)
		Type.PREDATOR:
			_behave_predator(delta)


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
	if hp_label != null:
		hp_label.text = "HP: %d / %d" % [int(hp), int(max_hp)]


func _draw() -> void:
	match type:
		Type.ASSASSIN:
			_draw_assassin()
		Type.PREDATOR:
			draw_circle(Vector2.ZERO, 16.0, Color(0.8, 0.3, 0.1, 0.95))
		_:
			draw_circle(Vector2.ZERO, 14.0, Color(0.55, 0.4, 0.75, 0.9))


## State read at a glance: dim red stalking, brightening pulse + growing aim
## line and danger ring while winding up, hot flash on the lunge, muted hop
## backing off, dark and desaturated while recovering.

func _behave_predator(delta: float) -> void:
	var world := _get_world()
	if world == null:
		return
	pred_state_timer -= delta
	match pred_state:
		PredState.SEARCH:
			var sum := Vector2.ZERO
			var count: int = 0
			for area in get_overlapping_areas():
				if area.is_in_group("swarm_agents"):
					var dist := global_position.distance_to(area.global_position)
					if dist <= pred_search_radius:
						sum += area.global_position
						count += 1
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
						area.take_damage(pred_charge_damage)
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
