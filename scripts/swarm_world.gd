extends Node2D
class_name SwarmWorld

## The shared environmental landscape. Owns every scalar field and the ant
## colony. Player abilities (later phases) stamp these fields; nothing here
## ever commands an ant directly.

signal deliveries_changed(count: int)

@export_group("Grid")
@export var cell_size: float = 10.0
@export var arena_size: Vector2 = Vector2(1280, 800)
@export var arena_center: Vector2 = Vector2.ZERO
@export var step_rate: float = 0.12
@export var ant_count: int = 36

@export_group("Nest")
@export var nest_position: Vector2 = Vector2.ZERO
@export var nest_radius_cells: int = 3
@export var nest_emit_per_sec: float = 2.0
@export var amplified_radius_cells: int = 12
@export var amplified_strength: float = 0.8
@export var carrier_emit_per_sec: float = 3.0
@export var carrier_aura_radius_cells: int = 6
@export var carrier_speed_ref: float = 60.0
@export var stale_decay_boost: float = 0.6
@export var sticky_hold_sec: float = 3.0

@export_group("Eminate")
@export var eminate_radius_cells: int = 16
@export var eminate_emit_per_sec: float = 0.6

@export_group("Cast")
@export var cast_reach_cells: int = 40
@export var cast_strength: float = 1.0
@export var cast_effect_seconds: float = 3.0
@export var nest_suppress_seconds: float = 2.0
@export var loop_radius_cells: int = 9
## Loop Hunt runs in two phases: the swarm marches out along the aim for
## `loop_out_seconds`, then the lane is weakened and a hot arc + return lane
## pull them back around to the player.
@export var loop_out_seconds: float = 1.5
@export var bounce_side_cells: int = 6
@export var bounce_waypoint_count: int = 4

@export_group("Funnel (animation only)")
## The funnel is a PURE ANIMATION on the ant side — it writes NO pheromone at
## all. Its only job is to scoop up ants standing on top of the player and
## flick them out into the already-stamped cast lane, so the cast does not have
## to fight the crowd that is milling around the nest. It must stay brief: the
## moment an ant lands in the lane it is handed back to normal field-driven
## movement and the pheromone takes over.
@export var funnel_capture_radius_cells: int = 4
## Seconds the gather+launch animation lasts. Kept short on purpose — a long
## funnel is just an ant standing still, which is the exact problem it is meant
## to solve.
@export var funnel_seconds: float = 0.3
## How far (in cells) along the aim an ant is placed the instant its funnel
## animation completes, so it is already moving forward when the pheromone
## takes over instead of pausing at the mouth.
@export var funnel_launch_cells: int = 4
## Revolutions of the entry corkscrew. Low, so it reads as a smooth scoop rather
## than a blur.
@export var funnel_turns: float = 0.5
## How far (in cells) along the aim the corkscrew's centre travels, so the
## animation itself carries the ant outward instead of spinning it in place.
@export var funnel_travel_cells: float = 2.0

@export_group("Arrive")
## Radius (in cells) of the dense arrive basin stamped at the fixed stop anchor
## (the enemy cell resolved once at cast time). A packed mass of ants holds here
## and deals DOT on overlap. No lock-on — the anchor never follows the enemy.
@export var arrive_hold_cells: int = 2
@export var arrive_hold_strength: float = 6.0
## Half-width (in cells) of the wall of zero hunt stamped from just past the stop
## anchor out to the cast reach, so the swarm stops continued travel in that
## direction instead of plowing past. Only stamped when an enemy is on the path.
@export var terminus_void_len_cells: int = 3
@export var terminus_void_strength: float = 7.0

## Fixed corridor half-width (in cells) used when resolving the stop anchor, so a
## cast that merely passes an enemy still halts there. Independent of the funnel.
const STOP_CORRIDOR_MARGIN_CELLS := 7
## How far (in cells) the pinned enemy may drift from its pinned stop cell
## before the cast stops holding for it.
const PIN_HOLD_CELLS := 2

@export_group("Bomb")
@export var bomb_radius_cells: int = 20
@export var bomb_strength: float = 2.0
@export var bomb_attract_duration: float = 5.0
@export var bomb_nest_suppress_seconds: float = 5.0

@export_group("Behaviour (JS-faithful defaults)")
@export var params_noise: float = 0.05
@export var params_explore: float = 0.06
@export var params_return_noise: float = 0.12
@export var params_sat_cap: float = 1.0
@export var params_sat_pen: float = 0.8
@export var params_ft_deposit: float = 0.08
@export var params_ft_return_w: float = 1.8
@export var params_home_w: float = 2.8
@export var params_fresh_bonus: float = 3.5
@export var params_forag_hwy_w: float = 1.2

@export_group("Visualization (read-only)")
## Pheromone overlay is hidden by default; toggle it in-game under
## Options > Visualization > "Show pheromones".
@export var show_pheromone_vis: bool = false
@export var vis_intensity: float = 0.8
@export var vis_strength_ref: float = 0.5
@export var vis_gamma: float = 1.0
@export var vis_home_color: Color = Color(0.30, 1.0, 0.55)
@export var vis_foot_color: Color = Color(0.35, 0.65, 1.0)
@export var vis_hunt_color: Color = Color(1.0, 0.35, 0.30)
@export var vis_fresh_color: Color = Color(1.0, 0.85, 0.25)

var cols: int = 0
var rows: int = 0
var origin: Vector2 = Vector2.ZERO
var nest_cell: Vector2i = Vector2i.ZERO
var nest_carrier: Node2D = null
var food_sources: Array = []
var deliveries: int = 0
var show_overlay: bool = false

## --- Procedural level (only populated when GameConfig.mode != SANDBOX) ---
var procedural: bool = false
## 1 = the original BSP/maze generator, 2 = the open arena generator.
var generator_version: int = 2
## LevelGenerator1.Level or LevelGenerator2.Level (both expose the same fields).
var level = null
var level_seed: int = 0
var combo: Array = []
## Pre-baked wall rectangles (world space), rebuilt once per generation so the
## draw pass never walks the grid.
var _wall_rects: Array = []

var field_manager: ScalarFieldManager
var ant_manager: AntManager
var _sticky_timer: float = 0.0
var _vis_timer: float = 0.0
## Tracks whether the pheromone sprites were left visible last frame, so the
## overlay can be hidden exactly once when it is toggled off mid-game.
var _vis_shown: bool = false
var _vis_layers: Array = []
var _active_cast: Dictionary = {}
var _cast_seq: int = 0
var _active_bomb: Dictionary = {}
var _nest_suppress_timer: float = 0.0
var nest_emit_enabled: bool = true
var _pheromone_locked: bool = false

## Direct-command stage modes. In CONTROL the player casts an order and ants
## steer straight toward it (no scalar field). In CARNAGE every ant chases the
## nearest enemy autonomously. Neither stamps pheromone.
const COMMAND_NONE := 0
const COMMAND_CONTROL := 1
const COMMAND_CARNAGE := 2
var command_mode: int = COMMAND_NONE

## Persistent direct-command state for CONTROL only.
var _rally_active: bool = false
var _rally_follow_carrier: bool = false
var _rally_pos: Vector2 = Vector2.ZERO
var _bomb_cell: Vector2i = Vector2i(-1, -1)
var _bomb_mode: int = 0
var _bomb_timer: float = 0.0
## Firewall enemies (group "firewalls"), refreshed each physics tick so the
## distortion query stays cheap. Empty when no firewall is present.
var _firewalls: Array = []

const VIS_REFRESH_INTERVAL: float = 0.1
## Adaptive update rate for very large grids. When the grid is > ~1.5M cells,
## pheromone/ant steps and vis refreshes run at half rate to keep framerate up
## while preserving the same dt scaling inside the simulation.
var _update_accum: float = 0.0
var _large_grid: bool = false
var _step_every: float = 1.0 / 60.0  # base
var _step_dt: float = 1.0 / 60.0


func _ready() -> void:
	var cfg: GameConfig = get_node_or_null("/root/GameConfig") as GameConfig
	procedural = cfg != null and cfg.mode != cfg.Mode.SANDBOX
	if procedural:
		cell_size = cfg.cell_size
		if cfg.arena_size != Vector2.ZERO:
			arena_size = cfg.arena_size

	cols = maxi(1, int(arena_size.x / cell_size))
	rows = maxi(1, int(arena_size.y / cell_size))
	origin = arena_center - arena_size * 0.5

	_setup_vis()

	field_manager = ScalarFieldManager.new()
	field_manager.setup(cols, rows)

	_large_grid = (cols * rows > 1_500_000)
	if _large_grid:
		_step_every = 1.0 / 30.0  # run at 30hz instead of 60hz
	else:
		_step_every = 1.0 / 60.0
	_step_dt = _step_every
	add_child(field_manager)

	nest_cell = world_to_cell(nest_position)

	if procedural:
		_generate_level(cfg)

	for food in get_tree().get_nodes_in_group("food_sources"):
		food_sources.append(food)

	ant_manager = AntManager.new()
	add_child(ant_manager)
	ant_manager.setup(self, ant_count)


## Builds the procedural level, installs its walls into the shared solid grid
## and replaces the hand-placed food with the level's own piles. Runs during
## `_ready` (before the ant manager) so the colony starts on the spawn cell.
func _generate_level(cfg: GameConfig) -> void:
	combo = cfg.enemies.duplicate()
	level_seed = cfg.level_seed
	var params: Dictionary = cfg.gen_params.duplicate(true)
	if cfg.mode == cfg.Mode.PROCEDURAL_1:
		generator_version = 1
		level = LevelGenerator1.generate(cols, rows, level_seed, combo, params)
	else:
		generator_version = 2
		level = LevelGenerator2.generate(cols, rows, level_seed, combo, params)
	field_manager.solid = level.solid
	_build_wall_rects()
	for f in get_tree().get_nodes_in_group("food_sources"):
		f.remove_from_group("food_sources")
		f.queue_free()
	for entry in level.food:
		var food := FoodSource.new()
		food.position = cell_to_world(entry["cell"])
		food.amount = int(entry["amount"])
		add_child(food)
	nest_cell = level.spawn_cell


## Merges each row's solid runs into a single rectangle so the draw pass never
## walks the grid cell-by-cell.
func _build_wall_rects() -> void:
	_wall_rects.clear()
	if field_manager == null or field_manager.solid.size() < cols * rows:
		return
	for y in range(rows):
		var x: int = 0
		while x < cols:
			if field_manager.solid[y * cols + x] == 1:
				var run_start: int = x
				while x < cols and field_manager.solid[y * cols + x] == 1:
					x += 1
				var pos := Vector2(origin.x + float(run_start) * cell_size, origin.y + float(y) * cell_size)
				_wall_rects.append(Rect2(pos, Vector2(float(x - run_start) * cell_size, cell_size)))
			else:
				x += 1


## The nest source follows this node (e.g. the player). Its position is the
## home-pheromone source every frame, so the nest field travels with it.
func set_nest_carrier(node: Node2D) -> void:
	nest_carrier = node


## Turn the persistent nest (home) pheromone emission on or off. Casts can
## still temporarily suppress it via `_nest_suppress_timer`; this is the
## all-time master switch (N key).
func set_nest_emit_enabled(enabled: bool) -> void:
	nest_emit_enabled = enabled


## Mechanic stage seam, called by the player on stage change.
## LOCKOUT zeroes every pheromone field and suppresses nest emission so ants
## run on their base movement physics with no field influence (random wander).
## CONTROL/CARNAGE also zero the fields, but command ants directly instead.
## Every other stage just restores normal emission.
func set_mode(stage: int) -> void:
	_pheromone_locked = (stage == Player.Stage.LOCKOUT or stage == Player.Stage.CONTROL or stage == Player.Stage.CARNAGE)
	if _pheromone_locked:
		_nest_suppress_timer = 9999.0
		_zero_all_fields()
	else:
		_nest_suppress_timer = minf(_nest_suppress_timer, 0.0)

	match stage:
		Player.Stage.CONTROL:
			command_mode = COMMAND_CONTROL
			_clear_commands()
		Player.Stage.CARNAGE:
			command_mode = COMMAND_CARNAGE
			_clear_commands()
		_:
			command_mode = COMMAND_NONE
			_clear_commands()


## Wipes every ant's direct command (and any persistent rally/bomb state) so
## they fall back to field behaviour. Also called on every stage switch so no
## order leaks from one stage into the next.
func _clear_commands() -> void:
	_rally_active = false
	_rally_follow_carrier = false
	_rally_pos = Vector2.ZERO
	_bomb_cell = Vector2i(-1, -1)
	_bomb_timer = 0.0
	if ant_manager == null:
		return
	for agent in ant_manager.agents:
		if is_instance_valid(agent):
			agent.command_active = false
			agent.command_target = null
			agent.command_wp.clear()
			agent.command_flee = Vector2i(-1, -1)
			agent.command_flee_radius = 0


## Direct-order wrappers: CONTROL issues straight (no-pheromone) commands. The
## four hunt patterns are implemented as steering shapes, not scalar fields.

## Plain DIRECT: steer the whole swarm toward `world_pos` (or `target`, which
## is re-aimed every step and so is tracked until it dies).
func command_swarm_at(world_pos: Vector2, target: Node2D = null) -> void:
	command_swarm_pattern(world_pos, Vector2.RIGHT, Player.HuntPattern.DIRECT, target)


## Pattern-aware direct order. `pattern` is Player.HuntPattern:
##   DIRECT - whole swarm straight to the anchor (tracking `target` if set).
##   LOOP   - half the swarm loops the anchor clockwise, half counter-clockwise
##            (approach flank -> anchor -> retreat flank -> back home).
##   MULTI  - every ant hunts the enemy nearest to it; a scattered front that
##            splits across all targets.
##   BOUNCE - zig-zag approach (two alternating offsets) to the anchor.
func command_swarm_pattern(world_pos: Vector2, aim_dir: Vector2, pattern: int, target: Node2D = null) -> void:
	if ant_manager == null:
		return
	var anchor: Vector2i
	if target != null and is_instance_valid(target):
		anchor = _clamp_cell(world_to_cell(target.global_position))
	else:
		anchor = _clamp_cell(world_to_cell(world_pos))

	match pattern:
		Player.HuntPattern.MULTI:
			for agent in ant_manager.agents:
				if not is_instance_valid(agent):
					continue
				var near: Node2D = nearest_target_to(cell_to_world(Vector2i(agent.x, agent.y)))
				if near != null:
					_issue_direct(agent, _clamp_cell(world_to_cell(near.global_position)), near)
				else:
					_issue_direct(agent, anchor, null)
			return
		Player.HuntPattern.LOOP:
			var i := 0
			var side := 1.0
			var home := anchor
			if nest_carrier != null and is_instance_valid(nest_carrier):
				home = _clamp_cell(world_to_cell(nest_carrier.global_position))
			for agent in ant_manager.agents:
				if not is_instance_valid(agent):
					continue
				side = -side if i % 2 == 0 else side
				i += 1
				var approach := _clamp_cell(anchor + Vector2i(int(20.0 * side), 0))
				var retreat := _clamp_cell(anchor + Vector2i(0, int(20.0 * side)))
				_issue_direct(agent, anchor, null, [approach, anchor, retreat, home])
			return
		Player.HuntPattern.BOUNCE:
			var i := 0
			var amp := 8.0 if aim_dir != Vector2.ZERO else 2.0
			for agent in ant_manager.agents:
				if not is_instance_valid(agent):
					continue
				var start := Vector2i(agent.x, agent.y)
				var side := 1.0 if i % 2 == 0 else -1.0
				i += 1
				var z1 := _clamp_cell(anchor + Vector2i(int((start.x - anchor.x) * 0.45), int((start.y - anchor.y) * 0.45)) + Vector2i(int(amp * side), 0))
				var z2 := _clamp_cell(anchor + Vector2i(int((start.x - anchor.x) * 0.7), int((start.y - anchor.y) * 0.7)) + Vector2i(0, int(amp * side)))
				_issue_direct(agent, anchor, null, [z1, z2])
			return
		_:
			for agent in ant_manager.agents:
				if is_instance_valid(agent):
					_issue_direct(agent, anchor, target)


func _issue_direct(agent: Node, goal: Vector2i, target: Node2D = null, wp: Array = []) -> void:
	agent.command_active = true
	agent.command_goal = goal
	agent.command_target = target if (target != null and is_instance_valid(target)) else null
	agent.command_wp.clear()
	for c in wp:
		agent.command_wp.append(c)
	agent.command_flee = Vector2i(-1, -1)
	agent.command_flee_radius = 0


## Direct eminate while held: ATTRACT = gather the swarm at the player (the
## nest), SCATTER = flee the player's cell until clear. No pheromone.
func command_eminate(world_pos: Vector2, mode: int, active: bool) -> void:
	if not active:
		_rally_active = false
		_rally_pos = Vector2.ZERO
		return
	if mode == Player.EminateMode.SCATTER:
		_rally_active = false
		_rally_pos = Vector2.ZERO
		if ant_manager == null:
			return
		var cell := _clamp_cell(world_to_cell(world_pos))
		for agent in ant_manager.agents:
			if not is_instance_valid(agent):
				continue
			agent.command_active = true
			agent.command_target = null
			agent.command_wp.clear()
			agent.command_goal = Vector2i(agent.x, agent.y)
			agent.command_flee = cell
			agent.command_flee_radius = 14
		return
	_rally_active = true
	_rally_pos = world_pos


## Direct nest/rally toggle: ON orders the swarm to gather at `world_pos` and
## keep following it; OFF releases them. Stands in for the nest pheromone in
## CONTROL where scalar fields are locked out. `follow_carrier` ties the rally
## to the player so the flock keeps a moving target (the N-toggle), while the
## held eminate passes a fresh position every frame instead.
func command_rally(world_pos: Vector2, on: bool, follow_carrier: bool = true) -> void:
	_rally_active = on
	_rally_follow_carrier = on and follow_carrier
	_rally_pos = world_pos


## Direct bomb: ATTRACT = every ant is ordered to the reticle cell and kept
## there for `bomb_attract_duration` (persistently re-issued). SCATTER = every
## ant flees the reticle cell until it is >14 cells clear.
func command_point_bomb(world_pos: Vector2, mode: int) -> void:
	if mode == Player.BombMode.ATTRACT:
		_bomb_cell = _clamp_cell(world_to_cell(world_pos))
		_bomb_mode = mode
		_bomb_timer = bomb_attract_duration
		_issue_bomb_attract()
		return
	if ant_manager == null:
		return
	var cell := _clamp_cell(world_to_cell(world_pos))
	for agent in ant_manager.agents:
		if not is_instance_valid(agent):
			continue
		agent.command_active = true
		agent.command_target = null
		agent.command_wp.clear()
		agent.command_goal = Vector2i(agent.x, agent.y)
		agent.command_flee = cell
		agent.command_flee_radius = 14


func _issue_bomb_attract() -> void:
	if ant_manager == null:
		return
	for agent in ant_manager.agents:
		if is_instance_valid(agent):
			_issue_direct(agent, _bomb_cell, null)


## The enemies the swarm is allowed to engage: `swarm_targets` minus any that
## are `swarm_immune`. Lure enemies (Broodmother, Siren) are excluded here, so
## the swarm never targets them — while the player's melee keeps reading the raw
## "swarm_targets" group and can still finish them.
func swarm_targets() -> Array:
	var out: Array = []
	for t in get_tree().get_nodes_in_group("swarm_targets"):
		if not is_instance_valid(t):
			continue
		if t.swarm_immune:
			continue
		out.append(t)
	return out


## CARNAGE hook: every ant re-targets the nearest enemy each step (via
## `nearest_target_to`), steering straight at it until it dies, then the next.
func nearest_target_to(world_pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for t in swarm_targets():
		if not is_instance_valid(t):
			continue
		var dist := world_pos.distance_squared_to(t.global_position)
		if dist < best_dist:
			best_dist = dist
			best = t
	return best


## True while a hunt cast is active. Gates the agents' hunt-cast lock-on attack.
func hunt_cast_active() -> bool:
	return not _active_cast.is_empty()


## The active cast's funnel source: its world origin and normalized aim. Returned
## as {"origin": Vector2, "dir": Vector2} while a hunt cast is running, else an
## empty Dictionary. The ant-side funnel ANIMATION reads this to scoop up ants
## standing on the player and flick them into the trail. Purely kinematic — it
## writes no pheromone; the cast's pheromone is stamped separately by
## `_apply_cast`.
func active_cast_funnel() -> Dictionary:
	if _active_cast.is_empty():
		return {}
	var d: Vector2 = _active_cast["aim_dir"]
	if d.length() < 0.001:
		d = Vector2.RIGHT
	return {"origin": _active_cast["world_pos"], "dir": d.normalized(), "seq": int(_active_cast.get("seq", 0))}


## True while a bomb is active. Lets the same hunt-cast lock-on attack also be
## triggered by a bomb's field instead of a cast. An attract bomb writes positive
## hunt scent (lock-on can engage); a scatter bomb writes negative scent, so the
## agent's existing "must sit in positive hunt" check keeps ants fleeing it.
func bomb_active() -> bool:
	return not _active_bomb.is_empty()


## True when `world_pos` lies inside the active cast's funnel capture zone (the
## immediate vicinity of the cast origin). Ants inside this zone are under the
## cast's command and must march out rather than divert to a lock-on attack — this
## is what stops a point-blank enemy from hijacking the cast. Returns false when
## no cast is active, so bomb-driven lock-on is unaffected.
func funnel_captures(world_pos: Vector2) -> bool:
	if _active_cast.is_empty():
		return false
	var origin: Vector2 = _active_cast["world_pos"]
	var r: float = funnel_capture_radius_cells * cell_size
	return world_pos.distance_squared_to(origin) <= r * r


## The enemy the active cast is pinned to: the stop anchor resolved ONCE at cast
## time, returned as a live node so ants can attack it on arrival. Returns null
## when there is no active cast or the cast has no stop anchor. Lock-on must only
## ever target THIS enemy — re-deriving "nearest enemy" each time is what let a
## point-blank enemy hijack the march.
func cast_pinned_target() -> Node2D:
	if _active_cast.is_empty():
		return null
	var stop_cell: Vector2i = _active_cast.get("stop_cell", Vector2i(-1, -1))
	if stop_cell.x < 0 or stop_cell.y < 0:
		return null
	var best: Node2D = null
	var best_d := INF
	for t in swarm_targets():
		if not is_instance_valid(t):
			continue
		# A couple of cells of tolerance so ordinary enemy jitter does not drop
		# the hold the instant it takes a step.
		var d := Vector2(_clamp_cell(world_to_cell(t.global_position)) - stop_cell).length()
		if d > float(PIN_HOLD_CELLS):
			continue
		if d < best_d:
			best_d = d
			best = t
	return best


## The nearest `swarm_targets` node within `radius_cells` of `world_pos`, or null.
## A casted ant uses this to decide when it has reached enemy vicinity.
func nearest_target_within_radius(world_pos: Vector2, radius_cells: float) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	var r := radius_cells * cell_size
	for t in swarm_targets():
		if not is_instance_valid(t):
			continue
		var dist := world_pos.distance_squared_to(t.global_position)
		if dist <= r * r and dist < best_dist:
			best_dist = dist
			best = t
	return best


## Wipes the four shared scalar fields to zero. Used far from the ants' step so
## their next read sees no pheromone anywhere.
func _zero_all_fields() -> void:
	for name in [
		ScalarFieldManager.FIELD_HOME_PHER,
		ScalarFieldManager.FIELD_FOOT_TRAIL,
		ScalarFieldManager.FIELD_HUNT_PHER,
		ScalarFieldManager.FIELD_PLAYER_FRESH,
	]:
		var field: ScalarField = field_manager.get_field(name)
		if field != null:
			field.data.fill(0.0)


func _physics_process(delta: float) -> void:
	if _pheromone_locked:
		_zero_all_fields()
	_firewalls = get_tree().get_nodes_in_group("firewalls")
	# CONTROL rally order: follow the (moving) rally point once it is active.
	if _rally_active and command_mode == COMMAND_CONTROL:
		if ant_manager != null:
			var rally_ref := _rally_pos
			if _rally_follow_carrier and nest_carrier != null and is_instance_valid(nest_carrier):
				rally_ref = nest_carrier.global_position
			var rally_cell := _clamp_cell(world_to_cell(rally_ref))
			for agent in ant_manager.agents:
				if is_instance_valid(agent):
					_issue_direct(agent, rally_cell, null)
	# CONTROL bomb attract: keep the swarm bunched on the bomb cell while it
	# burns, mirroring the scalar attract bomb window.
	if _bomb_timer > 0.0:
		_bomb_timer = maxf(0.0, _bomb_timer - delta)
		if command_mode == COMMAND_CONTROL:
			_issue_bomb_attract()
	var home_field: ScalarField = field_manager.get_field(ScalarFieldManager.FIELD_HOME_PHER)
	var move_strength := 0.0
	if nest_carrier != null and is_instance_valid(nest_carrier):
		nest_cell = world_to_cell(nest_carrier.global_position).clamp(Vector2i.ZERO, Vector2i(cols - 1, rows - 1))
		if nest_carrier is CharacterBody2D:
			var speed := (nest_carrier as CharacterBody2D).velocity.length()
			if speed > 0.01:
				_sticky_timer = sticky_hold_sec
			elif _sticky_timer > 0.0:
				_sticky_timer = maxf(0.0, _sticky_timer - delta)
			move_strength = clampf(maxf(speed / carrier_speed_ref, _sticky_timer / sticky_hold_sec), 0.0, 1.0)
	var emit := lerpf(nest_emit_per_sec, carrier_emit_per_sec, move_strength)
	var radius := maxi(nest_radius_cells, carrier_aura_radius_cells) if move_strength > 0.0 else nest_radius_cells + 1
	if _nest_suppress_timer > 0.0:
		_nest_suppress_timer = maxf(0.0, _nest_suppress_timer - delta)
	elif nest_emit_enabled:
		home_field.stamp(nest_cell.x, nest_cell.y, radius, emit * delta, params_sat_cap)
	if move_strength > 0.0:
		home_field.boost_decay(delta, stale_decay_boost * move_strength)

	_update_accum += delta
	if _update_accum >= _step_every:
		_update_accum = fmod(_update_accum, _step_every)
		field_manager.step(_step_dt)
		ant_manager.step(_step_dt)

	if not _active_cast.is_empty():
		var timer: float = _active_cast["timer"] - delta
		if timer <= 0.0:
			_active_cast = {}
		else:
			_active_cast["timer"] = timer
			_active_cast["elapsed"] = float(_active_cast["elapsed"]) + delta
			# Re-stamp every frame so the trail does not decay out from under the
			# ants that are following it.
			_apply_cast(
				_active_cast["world_pos"],
				_active_cast["aim_dir"],
				_active_cast["pattern"],
				_active_cast["target"],
				_active_cast["elapsed"]
			)

	if not _active_bomb.is_empty():
		var timer: float = _active_bomb["timer"] - delta
		if timer <= 0.0:
			_active_bomb = {}
		else:
			_active_bomb["timer"] = timer
			var cell: Vector2i = _active_bomb["cell"]
			var mode: int = _active_bomb["mode"]
			var sign: float = 1.0 if mode == 0 else -1.0
			var hunt_field: ScalarField = field_manager.get_field(ScalarFieldManager.FIELD_HUNT_PHER)
			hunt_field.set_stamp_falloff(cell.x, cell.y, bomb_radius_cells, sign)

	if show_pheromone_vis:
		_vis_timer -= delta
		if _vis_timer <= 0.0:
			_vis_timer = VIS_REFRESH_INTERVAL * (_step_every / (1.0 / 60.0) if _step_every > 0 else 1.0)
			_update_vis()
		_vis_shown = true
	elif _vis_shown:
		# Toggled off at runtime: one pass to hide the overlay sprites.
		_vis_shown = false
		_update_vis()
	# Walls, the arena border and the (player-following) nest are all drawn in
	# `_draw`, so keep the canvas fresh even with the overlay hidden.
	queue_redraw()


## Player emit: stamps the shared hunt field at the emitter's cell.
## ATTRACT adds hunt pheromone (ants flock to it); SCATTER subtracts it,
## leaving a void the ants avoid. Player → scalar field → ant; no direct orders.
func eminate_at(world_pos: Vector2, mode: int) -> void:
	var cell := world_to_cell(world_pos).clamp(Vector2i.ZERO, Vector2i(cols - 1, rows - 1))
	var hunt_field: ScalarField = field_manager.get_field(ScalarFieldManager.FIELD_HUNT_PHER)
	var strength: float = eminate_emit_per_sec
	if mode == Player.EminateMode.SCATTER:
		strength = -strength
	hunt_field.stamp(cell.x, cell.y, eminate_radius_cells, strength, params_sat_cap)


## Bait seam: an enemy paints positive hunt pheromone (the same channel the
## player's ATTRACT uses) to lure foraging ants toward `world_pos`. Added each
## frame while active, saturating at `params_sat_cap`, so it competes on equal
## terms with the player's own attract just like any other stamp.
func stamp_lure_field(world_pos: Vector2, radius_cells: int, strength: float) -> void:
	var cell := _clamp_cell(world_to_cell(world_pos))
	var hunt_field: ScalarField = field_manager.get_field(ScalarFieldManager.FIELD_HUNT_PHER)
	hunt_field.stamp(cell.x, cell.y, radius_cells, strength, params_sat_cap)


## Hijack seam: an enemy paints home pheromone so returning (carrying) foragers
## climb toward it as if it were a nest. Purely field-based — the ants' own
## loyalty does the work; nothing here commands them.
func stamp_home_field(world_pos: Vector2, radius_cells: int, strength: float) -> void:
	var cell := _clamp_cell(world_to_cell(world_pos))
	var home_field: ScalarField = field_manager.get_field(ScalarFieldManager.FIELD_HOME_PHER)
	home_field.stamp(cell.x, cell.y, radius_cells, strength, params_sat_cap)


## Enemy effect seam: enemy → shared scalar field → swarm response. A negative
## `strength` lays a repulsive fear gradient (strongest at the centre, fading
## to zero at the rim) that ants climb out of; positive attracts. The enemy
## never commands an ant directly, mirroring the player's pheromone pipeline.
func stamp_enemy_field(world_pos: Vector2, radius_cells: int, strength: float) -> void:
	var cell := _clamp_cell(world_to_cell(world_pos))
	var hunt_field: ScalarField = field_manager.get_field(ScalarFieldManager.FIELD_HUNT_PHER)
	hunt_field.set_stamp_falloff(cell.x, cell.y, radius_cells, strength)


## Bomb drop: stamps a saturating burst of hunt pheromone around the impact
## point and re-stamps it every frame for `bomb_attract_duration` seconds so
## ants have time to converge. ATTRACT pulls ants in; SCATTER pushes them out.
## Also suppresses nest emission temporarily.
func drop_bomb(world_pos: Vector2, mode: int = 0) -> void:
	var cell := _clamp_cell(world_to_cell(world_pos))
	var hunt_field: ScalarField = field_manager.get_field(ScalarFieldManager.FIELD_HUNT_PHER)
	var strength: float = bomb_strength if mode == 0 else -bomb_strength
	hunt_field.stamp(cell.x, cell.y, bomb_radius_cells, strength, params_sat_cap)
	_active_bomb = {
		"world_pos": world_pos,
		"cell": cell,
		"timer": bomb_attract_duration,
		"mode": mode,
	}
	_nest_suppress_timer = bomb_nest_suppress_seconds


## Cast the active hunt pattern by stamping the shared hunt pheromone field, then
## re-stamping it every frame for `cast_effect_seconds` so the trail stays strong
## enough for ants to follow. The cast IS a smell: ants are never commanded, they
## simply find this trail more attractive than the alternatives and walk down it.
## The player casts into the same scalar field the rest of the simulation uses —
## home, foot-trail, bombs and cast all compete on equal terms, which is the point.
## pattern: "direct" | "loop" | "multi" | "bounce"
func cast_hunt(world_pos: Vector2, aim_dir: Vector2, pattern: String, target: Node2D = null) -> void:
	_cast_seq += 1
	var dir_n := aim_dir.normalized()
	if dir_n == Vector2.ZERO:
		dir_n = Vector2.RIGHT
	_active_cast = {
		"pattern": pattern,
		"world_pos": world_pos,
		"aim_dir": dir_n,
		"target": target,
		"timer": cast_effect_seconds,
		"elapsed": 0.0,
		"stop_cell": _resolve_stop_cell(_clamp_cell(world_to_cell(world_pos)), dir_n, target),
		"seq": _cast_seq,
	}
	_nest_suppress_timer = nest_suppress_seconds
	_apply_cast(world_pos, dir_n, pattern, target, 0.0)


## The cell where a marching swarm should stop and attack, resolved ONCE at cast
## time and then fixed (no lock-on). Prefers the aimed-at target; otherwise picks
## the first enemy (smallest forward distance) sitting near the march lane, so a
## cast that merely passes an enemy still halts there and attacks. Returns
## Vector2i(-1, -1) when no enemy is near the path -> the march runs long.
func _resolve_stop_cell(start: Vector2i, aim_dir: Vector2, target: Node2D = null) -> Vector2i:
	# A swarm-immune enemy is not a valid stop: the marching swarm would only
	# pile onto something it cannot hurt, so the cast passes it by instead.
	if target != null and is_instance_valid(target) and target.is_in_group("swarm_targets") and not target.swarm_immune:
		return _clamp_cell(world_to_cell(target.global_position))
	var dir_n := aim_dir.normalized()
	if dir_n == Vector2.ZERO:
		dir_n = Vector2.RIGHT
	var perp := Vector2(dir_n.y, -dir_n.x)
	var reach := float(maxi(1, cast_reach_cells))
	var lane_slope: float = tan(deg_to_rad(30.0))
	var margin := float(STOP_CORRIDOR_MARGIN_CELLS)
	var best := Vector2i(-1, -1)
	var best_along := INF
	for t in swarm_targets():
		if not is_instance_valid(t):
			continue
		var cell := _clamp_cell(world_to_cell(t.global_position))
		var off := Vector2(cell - start)
		var along := off.dot(dir_n)
		if along < 1.0 or along > reach:
			continue
		var lat: float = absf(off.dot(perp))
		if lat > lane_slope * along + margin:
			continue
		if along < best_along:
			best_along = along
			best = cell
	return best


func _apply_cast(world_pos: Vector2, aim_dir: Vector2, pattern: String, target: Node2D = null, elapsed: float = 0.0) -> void:
	var start := _clamp_cell(world_to_cell(world_pos))
	var dir_n := aim_dir.normalized()
	if dir_n == Vector2.ZERO:
		dir_n = Vector2.RIGHT
	match pattern:
		"direct":
			_stamp_direct_hunt(start, dir_n)
		"loop":
			_stamp_loop_hunt(start, dir_n, target, elapsed)
		"multi":
			_stamp_multi_hunt(start, dir_n)
		"bounce":
			_stamp_bounce_hunt(start, dir_n, target)
	_stamp_terminus_hold(start, dir_n)


## The cast's stop anchor, re-stamped every frame with the rest of the cast.
## When an enemy is on the march path its cell was pinned once at cast time: a
## dense arrive basin is stamped there and a wall of zero hunt blocks continued
## travel in that direction, so the swarm stops at the anchor and attacks via
## the pinned lock-on. The anchor is never re-derived while the enemy moves, so
## there is no chasing.
func _stamp_terminus_hold(start: Vector2i, dir_n: Vector2) -> void:
	var stop_cell: Vector2i = _active_cast.get("stop_cell", Vector2i(-1, -1))
	if stop_cell.x < 0 or stop_cell.y < 0:
		return
	# Nothing left to attack at the anchor (it died, or walked clear of it): drop
	# the hold entirely rather than leave a stale sink. The trail then runs on to
	# its natural end and the swarm disperses instead of milling on empty ground.
	if cast_pinned_target() == null:
		return
	# Repelling void across the whole trail just PAST the anchor, so the swarm
	# arrives and stops instead of walking past. The cast fans out to a +/-30
	# degree wedge, so the void has to span that wedge at the anchor's distance or
	# ants simply stroll around its edge. Negative because a void of zero is just
	# "no smell", which home pheromone out-competes anyway.
	var along := Vector2(stop_cell - start).dot(dir_n)
	var half_w := int(tan(deg_to_rad(30.0)) * along) + 2
	var perp := Vector2(dir_n.y, -dir_n.x)
	for t in range(1, terminus_void_len_cells + 1):
		var band := stop_cell + Vector2i(round(dir_n.x * float(t)), round(dir_n.y * float(t)))
		for s in range(-half_w, half_w + 1):
			_hunt_set_disc(_clamp_cell(band + Vector2i(round(perp.x * float(s)), round(perp.y * float(s)))), 1, -terminus_void_strength)
	# The attract basin goes on last so the wall's encroachment cannot erode the
	# sink the swarm is meant to settle into. Fixed cell, never re-derived: no
	# chasing, and the anchor stays put even if the enemy walks away.
	_hunt_set_disc(stop_cell, arrive_hold_cells, arrive_hold_strength)


func _hunt_stamp(c: Vector2i, r: int, v: float) -> void:
	var hunt_field: ScalarField = field_manager.get_field(ScalarFieldManager.FIELD_HUNT_PHER)
	hunt_field.stamp(c.x, c.y, r, v, params_sat_cap)


## Sets every cell within radius `r` of `c` to `v` (no accumulation, no cap),
## so re-stamping keeps an exact gradient instead of saturating it flat.
func _hunt_set_disc(c: Vector2i, r: int, v: float) -> void:
	var hunt_field: ScalarField = field_manager.get_field(ScalarFieldManager.FIELD_HUNT_PHER)
	for yy in range(c.y - r, c.y + r + 1):
		for xx in range(c.x - r, c.x + r + 1):
			if xx < 0 or xx >= cols or yy < 0 or yy >= rows:
				continue
			hunt_field.data[hunt_field.idx(xx, yy)] = v


## Sets a band of cells along the line from `start` to `end`, with hunt values
## ramping from `base` at the start to `peak` at the end. The rising gradient
## is what makes ants march along the pattern toward its focus.
func _hunt_set_line(start: Vector2i, end: Vector2i, r: int, base: float, peak: float) -> void:
	var cells := _line_cells(start, end)
	var span := maxf(1.0, float(cells.size() - 1))
	for i in range(cells.size()):
		_hunt_set_disc(cells[i], r, lerpf(base, peak, float(i) / span))


func _clamp_cell(c: Vector2i) -> Vector2i:
	return c.clamp(Vector2i.ZERO, Vector2i(cols - 1, rows - 1))


## The pattern's focus cell: the aimed-at target if any, else a point
## `cast_reach_cells` ahead along the aim direction.
func _anchor_cell(start: Vector2i, dir_n: Vector2, target: Node2D) -> Vector2i:
	if target != null and is_instance_valid(target):
		return _clamp_cell(world_to_cell(target.global_position))
	return _clamp_cell(start + Vector2i(round(dir_n.x * cast_reach_cells), round(dir_n.y * cast_reach_cells)))


## Wide fan of hunt pheromone toward the aim, filled densely across a +/-30
## degree wedge with a rising gradient from a warm start at the cast point to a
## hot far end. The gradient is what makes ants march outward along the cast
## direction; exact-set values (no accumulation) keep it intact while re-stamping.
func _stamp_direct_hunt(start: Vector2i, dir_n: Vector2) -> void:
	var spread := deg_to_rad(30.0)
	var perp := Vector2(dir_n.y, -dir_n.x)
	var peak := cast_strength
	var base: float = peak * 0.45
	_hunt_set_disc(start, 2, base)
	for t in range(1, cast_reach_cells + 1):
		var along := dir_n * float(t)
		var half_w := tan(spread) * float(t)
		var steps := maxi(1, int(half_w))
		var val := lerpf(base, peak, float(t) / float(cast_reach_cells))
		for s in range(-steps, steps + 1):
			var cell := start + Vector2i(round(along.x + perp.x * float(s)), round(along.y + perp.y * float(s)))
			_hunt_set_disc(cell, 1, val)
	var end := _clamp_cell(start + Vector2i(round(dir_n.x * cast_reach_cells), round(dir_n.y * cast_reach_cells)))
	_hunt_set_disc(end, 4, peak * 1.3)


## Loop Hunt: two-phase out-and-back along the aim. For the first
## `loop_out_seconds` the swarm marches out along a rising lane from the player
## to the cast-field edge; afterwards the lane is weakened and a hot far arc
## plus return lane (rising toward the player) pull the swarm back around to
## the nest, so they cycle out-and-back while the cast effect lasts.
func _stamp_loop_hunt(start: Vector2i, dir_n: Vector2, _target: Node2D, elapsed: float) -> void:
	var far := _clamp_cell(start + Vector2i(round(dir_n.x * cast_reach_cells), round(dir_n.y * cast_reach_cells)))
	var perp := Vector2(dir_n.y, -dir_n.x)
	if elapsed < loop_out_seconds:
		_stamp_loop_outbound(start, far, dir_n, perp)
	else:
		_stamp_loop_return(start, far, dir_n, perp)


## Rising lane from the player to the cast-field edge: a few parallel tracks
## so the swarm spreads out, all climbing toward the far end so ants march out.
func _stamp_loop_outbound(start: Vector2i, far: Vector2i, dir_n: Vector2, perp: Vector2) -> void:
	var base: float = cast_strength * 0.4
	var peak: float = cast_strength
	_hunt_set_disc(start, 3, base)
	for k in range(-2, 3):
		var off := perp * float(k)
		var a := _clamp_cell(start + Vector2i(round(off.x), round(off.y)))
		var b := _clamp_cell(far + Vector2i(round(off.x), round(off.y)))
		_hunt_set_line(a, b, 1, base, peak)


## Phase two: weaken the outbound lane so it stops pulling, then lay a hot
## turnaround arc at the far edge and a return lane that climbs back toward
## the player, carrying the swarm home. The whole return path is hotter than
## the weakened lane so any ant in reach gets captured and routed back.
func _stamp_loop_return(start: Vector2i, far: Vector2i, dir_n: Vector2, perp: Vector2) -> void:
	var half := float(loop_radius_cells)
	var weak: float = cast_strength * 0.3
	var arc_v0: float = cast_strength * 0.8
	var arc_v1: float = cast_strength * 1.3
	var ret_v1: float = cast_strength * 1.6

	for k in range(-2, 3):
		var off := perp * float(k)
		var a := _clamp_cell(start + Vector2i(round(off.x), round(off.y)))
		var b := _clamp_cell(far + Vector2i(round(off.x), round(off.y)))
		_hunt_set_line(a, b, 1, weak, weak)

	var prev := _clamp_cell(far + Vector2i(round(-perp.x * half), round(-perp.y * half)))
	var arc_pts := 10
	for i in range(1, arc_pts + 1):
		var ang := -PI * 0.5 + PI * float(i) / float(arc_pts)
		var off := dir_n * cos(ang) * half + perp * sin(ang) * half
		var c := _clamp_cell(far + Vector2i(round(off.x), round(off.y)))
		_hunt_set_line(prev, c, 2, arc_v0, arc_v1)
		prev = c

	var far_ret := _clamp_cell(far + Vector2i(round(perp.x * half), round(perp.y * half)))
	_hunt_set_line(far_ret, start, 2, arc_v1, ret_v1)


## A hunt burst on every enemy target plus a scent line toward each, so the
## swarm splits into streams toward every target.
func _stamp_multi_hunt(start: Vector2i, dir_n: Vector2) -> void:
	var targets := swarm_targets()
	if targets.is_empty():
		_stamp_direct_hunt(start, dir_n)
		return
	for t in targets:
		if not is_instance_valid(t):
			continue
		var cell := _clamp_cell(world_to_cell(t.global_position))
		for c in _line_cells(start, cell):
			_hunt_stamp(c, 1, cast_strength)
		_hunt_stamp(cell, 4, cast_strength * 1.3)


## Zigzag chain of hunt pheromone bouncing toward the anchor.
func _stamp_bounce_hunt(start: Vector2i, dir_n: Vector2, target: Node2D) -> void:
	var anchor := _anchor_cell(start, dir_n, target)
	var perp := Vector2(dir_n.y, -dir_n.x)
	var waypoints: Array = [start]
	var start_v := Vector2(start)
	var anchor_v := Vector2(anchor)
	for i in range(1, bounce_waypoint_count + 1):
		var t := float(i) / float(bounce_waypoint_count)
		var side := 1.0 if i % 2 == 0 else -1.0
		var point_v := start_v.lerp(anchor_v, t) + perp * side * (bounce_side_cells * (1.0 - t))
		waypoints.append(_clamp_cell(Vector2i(round(point_v.x), round(point_v.y))))
	_hunt_stamp(start, 3, cast_strength)
	for i in range(waypoints.size() - 1):
		for c in _line_cells(waypoints[i], waypoints[i + 1]):
			_hunt_stamp(c, 2, cast_strength)
	_hunt_stamp(waypoints[waypoints.size() - 1], 4, cast_strength * 1.2)


## Bresenham line of grid cells between two cells.
func _line_cells(a: Vector2i, b: Vector2i) -> Array:
	var cells: Array = []
	var x0 := a.x
	var y0 := a.y
	var x1 := b.x
	var y1 := b.y
	var dx := absi(x1 - x0)
	var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0)
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		cells.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return cells


## Amplified Nest: a large, strong home-pheromone burst at the nest source
## (the player). Player → scalar field → ants; never a direct command.
func trigger_amplified_nest() -> void:
	var home_field: ScalarField = field_manager.get_field(ScalarFieldManager.FIELD_HOME_PHER)
	home_field.stamp(nest_cell.x, nest_cell.y, amplified_radius_cells, amplified_strength, params_sat_cap)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		show_overlay = not show_overlay
		queue_redraw()


func _draw() -> void:
	if not _wall_rects.is_empty():
		_draw_walls()
	if show_overlay:
		_draw_field(ScalarFieldManager.FIELD_HOME_PHER, Color(0.56, 0.75, 0.29), 0.02)
		_draw_field(ScalarFieldManager.FIELD_FOOT_TRAIL, Color(0.29, 0.78, 0.83), 0.015)
		_draw_field(ScalarFieldManager.FIELD_HUNT_PHER, Color(0.76, 0.55, 0.17), 0.018)

	_draw_arena_border()
	_draw_nest()
	for food in food_sources:
		_draw_food(food)


func _draw_walls() -> void:
	var fill := Color(0.10, 0.11, 0.15, 1.0)
	var edge := Color(0.24, 0.27, 0.34, 1.0)
	for rect in _wall_rects:
		draw_rect(rect, fill)
		draw_rect(rect, edge, false, 1.0)


func _setup_vis() -> void:
	if cols <= 0 or rows <= 0:
		return
	var layers: Array = [
		{"field": ScalarFieldManager.FIELD_HOME_PHER, "color": vis_home_color},
		{"field": ScalarFieldManager.FIELD_FOOT_TRAIL, "color": vis_foot_color},
		{"field": ScalarFieldManager.FIELD_HUNT_PHER, "color": vis_hunt_color},
		{"field": ScalarFieldManager.FIELD_PLAYER_FRESH, "color": vis_fresh_color},
	]
	_vis_layers.clear()
	for layer in layers:
		var sprite := Sprite2D.new()
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		sprite.material = mat
		sprite.centered = false
		sprite.position = origin
		sprite.scale = Vector2(cell_size, cell_size)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.visible = show_pheromone_vis
		sprite.texture = ImageTexture.create_from_image(Image.create_empty(cols, rows, false, Image.FORMAT_RGBA8))
		add_child(sprite)
		_vis_layers.append({"field": layer["field"], "color": layer["color"], "sprite": sprite})


## Copies each pheromone field (the exact array the ants read) into a
## 1px-per-cell texture: value -> additive glow. Zero stays invisible.
func _update_vis() -> void:
	for layer in _vis_layers:
		var sprite: Sprite2D = layer["sprite"]
		if not show_pheromone_vis:
			sprite.visible = false
			continue
		sprite.visible = true
		var field: ScalarField = field_manager.get_field(layer["field"])
		if field == null or field.data.size() != cols * rows:
			continue
		var color: Color = layer["color"]
		var bytes := PackedByteArray()
		bytes.resize(cols * rows * 4)
		var i := 0
		while i < cols * rows:
			var v: float = field.data[i]
			var a: float = clampf(v / vis_strength_ref, 0.0, 1.0)
			if vis_gamma != 1.0:
				a = pow(a, vis_gamma)
			if a <= 0.001:
				bytes[i * 4] = 0
				bytes[i * 4 + 1] = 0
				bytes[i * 4 + 2] = 0
				bytes[i * 4 + 3] = 0
			else:
				var m: float = a * vis_intensity
				bytes[i * 4] = int(clampi(int(color.r * m * 255.0), 0, 255))
				bytes[i * 4 + 1] = int(clampi(int(color.g * m * 255.0), 0, 255))
				bytes[i * 4 + 2] = int(clampi(int(color.b * m * 255.0), 0, 255))
				bytes[i * 4 + 3] = int(clampi(int(a * 255.0), 0, 255))
			i += 1
		var img := Image.create_from_data(cols, rows, false, Image.FORMAT_RGBA8, bytes)
		sprite.texture = ImageTexture.create_from_image(img)


func _draw_field(field_name: String, color: Color, threshold: float) -> void:
	var field: ScalarField = field_manager.get_field(field_name)
	if field == null:
		return
	for y in range(rows):
		for x in range(cols):
			var v: float = field.data[field.idx(x, y)]
			if v <= threshold:
				continue
			var alpha: float = minf(0.55, v * 0.55)
			var col: Color = color
			col.a = alpha
			draw_rect(Rect2(cell_to_world(Vector2i(x, y)) - Vector2(cell_size, cell_size) * 0.5, Vector2(cell_size, cell_size)), col)


func _draw_arena_border() -> void:
	if cols <= 0 or rows <= 0:
		return
	var field_size := Vector2(float(cols), float(rows)) * cell_size
	var rect := Rect2(origin, field_size)
	draw_rect(rect, Color(0.55, 0.85, 1.0, 0.06), true)
	draw_rect(rect, Color(0.45, 0.80, 1.0, 0.85), false, 3.0)
	draw_rect(rect.grow(-6.0), Color(0.45, 0.80, 1.0, 0.28), false, 1.0)
	var tick := 26.0
	var col := Color(0.70, 0.92, 1.0, 0.95)
	draw_line(rect.position, rect.position + Vector2(tick, 0.0), col, 4.0)
	draw_line(rect.position, rect.position + Vector2(0.0, tick), col, 4.0)
	draw_line(rect.position + Vector2(field_size.x, 0.0), rect.position + Vector2(field_size.x - tick, 0.0), col, 4.0)
	draw_line(rect.position + Vector2(field_size.x, 0.0), rect.position + field_size, col, 4.0)
	draw_line(rect.position + Vector2(0.0, field_size.y), rect.position + Vector2(0.0, field_size.y - tick), col, 4.0)
	draw_line(rect.position + field_size, rect.position + field_size - Vector2(tick, 0.0), col, 4.0)


func _draw_nest() -> void:
	var center := cell_to_world(nest_cell)
	draw_circle(center, cell_size * float(nest_radius_cells), Color(0.16, 0.36, 0.24, 0.55))


func _draw_food(food: FoodSource) -> void:
	var center := cell_to_world(food.cell_pos)
	var r: float = cell_size * float(food.radius_cells)
	draw_rect(Rect2(center - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), Color(0.77, 0.57, 0.19, 0.8))
	var ratio: float = clampf(float(food.amount) / 200.0, 0.0, 1.0)
	draw_circle(center, r * 0.35, Color(1.0, 0.96, 0.78, 0.3 + 0.5 * ratio))


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(
		origin.x + (float(cell.x) + 0.5) * cell_size,
		origin.y + (float(cell.y) + 0.5) * cell_size
	)


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor((world_pos.x - origin.x) / cell_size)),
		int(floor((world_pos.y - origin.y) / cell_size))
	)


func blocked(cx: int, cy: int) -> bool:
	if cx < 0 or cx >= cols or cy < 0 or cy >= rows:
		return true
	return field_manager.solid[cy * cols + cx] == 1


## Nearest open cell to `cell` (BFS over the grid), used to free anything that
## finds itself embedded in solid terrain — e.g. an ant spawned inside a wall.
## Returns `cell` unchanged when it is already open.
func nearest_open_cell(cell: Vector2i) -> Vector2i:
	var c := cell.clamp(Vector2i.ZERO, Vector2i(cols - 1, rows - 1))
	if not blocked(c.x, c.y):
		return c
	var seen := {c: true}
	var queue: Array = [c]
	var head: int = 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var neighbours := [
			cur + Vector2i(1, 0), cur + Vector2i(-1, 0),
			cur + Vector2i(0, 1), cur + Vector2i(0, -1),
		]
		for n in neighbours:
			var nx: Vector2i = n
			if nx.x < 0 or nx.x >= cols or nx.y < 0 or nx.y >= rows:
				continue
			if seen.has(nx):
				continue
			if not blocked(nx.x, nx.y):
				return nx
			seen[nx] = true
			queue.append(nx)
	return c


func saturation_penalty(v: float) -> float:
	var opt: float = params_sat_cap * 0.5
	if v < opt:
		return 1.0
	var excess: float = (v - opt) / (params_sat_cap - opt + 0.000001)
	return maxf(params_sat_pen, 1.0 - excess * (1.0 - params_sat_pen))


func get_field(field_name: String) -> ScalarField:
	return field_manager.get_field(field_name)


## Firewall query seam. Returns the strongest distortion field's influence at
## `world_pos`, or an empty dictionary when outside every field. Effects do not
## stack: only the single most-influential Firewall is returned. The caller uses
## `influence` to scale zero-mean noise (sampled once so it cannot bias
## direction) and `rim_push` for a soft outward nudge near the edge.
func firewall_influence_at(world_pos: Vector2) -> Dictionary:
	if _firewalls.is_empty():
		return {}
	var best: float = 0.0
	var source: Node = null
	for fw in _firewalls:
		if not is_instance_valid(fw):
			continue
		var radius: float = fw.firewall_field_radius
		if radius <= 0.0:
			continue
		var dist: float = world_pos.distance_to(fw.global_position)
		if dist >= radius:
			continue
		var influence: float = pow(1.0 - dist / radius, fw.firewall_falloff_pow)
		if influence > best:
			best = influence
			source = fw
	if source == null or best <= 0.0:
		return {}
	return {
		"influence": best,
		"center": source.global_position,
		"radius": source.firewall_field_radius,
		"noise": source.firewall_noise,
		"rim_push": source.firewall_rim_push,
	}


func notify_delivery() -> void:
	deliveries += 1
	deliveries_changed.emit(deliveries)
