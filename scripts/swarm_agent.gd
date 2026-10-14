extends Area2D
class_name SwarmAgent

## Faithful port of the JS prototype's `updateAnt()`: the ant holds only a
## grid position, an 8-way heading, memory, and a small carry state. It never
## receives a target or a vector; it reads the shared scalar fields at a few
## neighbouring cells and picks a movement probabilistically.

const DIRS_8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

const DOT_PER_SECOND := 6.0
const VISUAL_LERP_PER_SEC := 6.0
## How far (in cells, along the aim) past the terminus the ant is carried before
## the march lets go of it, so the swarm overshoots slightly and settles onto the
## target rather than stopping short of it.
const MARCH_RELEASE_CELLS := 2.0

## How hard a Firewall's scramble perturbs an ant's per-candidate score. The
## enemy supplies the 0..1 amplitude (scaled by field influence); this converts
## it into score units comparable to the base and directional bonuses.
const FW_SCORE_SCALE := 3.0

var swarm_world: SwarmWorld = null

var x: int = 0
var y: int = 0
var dir: int = 0
var carry: bool = false

var hp: float = 1.0
var dead: bool = false

var straightness: float = 1.0
var confidence: float = 0.0
var prev_pf: float = 0.0
var prev_hf: float = 0.0
var prev_ft: float = 0.0
var ever_delivered: bool = false

var fresh_home_set: Dictionary = {}
var fresh_home_age: int = 0

var visual_jitter: Vector2 = Vector2.ZERO

## Direct-command state (CONTROL / CARNAGE stages). When `command_active` is
## true the ant steers straight toward `command_goal` (or `command_target` if
## set) instead of reading the pheromone fields. `command_wp` may hold extra
## waypoints (e.g. a loop flank or bounce zigzag).
var command_active: bool = false
var command_target: Node2D = null
var command_goal: Vector2i = Vector2i.ZERO
var command_wp: Array = []
var command_flee: Vector2i = Vector2i(-1, -1)
var command_flee_radius: int = 0

## Hunt-cast lock-on attack: once a casted ant (one sitting under the active hunt
## cast's influence) reaches enemy vicinity, it locks onto that enemy and attacks
## it for `hunt_lockon_seconds`. While loc \ked the ant steers straight at the moving
## target and the existing overlap DOT keeps it under attack. Bounded by the cast.
@export var hunt_lockon_seconds: float = 1.5
## Cell radius around a commanded ant within which a nearby enemy triggers lock-on.
@export var hunt_lockon_radius_cells: float = 1.5
## Hunt-field value an ant must be sitting in to count as "commanded" (under the
## cast's or an attract bomb's influence). Elsewhere it is near zero, so this
## selects only ants the player actually reached with a cast/bomb.
const HUNT_LOCKON_MIN_HUNT := 0.1
var lock_timer: float = 0.0

## Cast funnel — PURE ANIMATION, writes no pheromone.
##
## The cast itself is a pheromone trail in the shared scalar field (see
## SwarmWorld._apply_cast); ants follow that trail by ordinary field sensing, the
## same way they follow home and foot-trail. The funnel is NOT part of that
## system. It is a brief, local animation whose only job is to scoop up the ants
## standing on top of the player and flick them out into the trail, so the crowd
## milling at the nest does not smother the cast as it leaves the body.
##
## It is deliberately short (see `funnel_seconds`). A long funnel is just an ant
## standing still, which is precisely the problem it is meant to solve. When the
## animation ends the ant is dropped into the trail and normal field-driven
## movement resumes immediately.
var funnel_active: bool = false
## 0 → 1 across the animation.
var funnel_t: float = 0.0
var funnel_origin: Vector2 = Vector2.ZERO
var funnel_dir: Vector2 = Vector2.RIGHT
## The ant's own lateral offset from the aim axis, in pixels, preserved from
## where it stood. Every ant keeps a DIFFERENT offset, so they spill into the
## trail as a spread-out front instead of piling onto one shared point.
var funnel_lane: float = 0.0
var funnel_entry_angle: float = 0.0
var funnel_entry_radius: float = 0.0
## Cast-pheromone level at which the funnel considers the handover complete and
## stops nudging: the ant is standing in a real trail, so the field will take
## it from here.
const HUNT_TRAIL_MIN := 0.25
## Short lockout after launch so a freshly dropped ant is not immediately
## re-scooped by the still-active cast.
var funnel_cooldown: float = 0.0
var funnel_done_seq: int = -1


func _ready() -> void:
	add_to_group("swarm_agents")
	visual_jitter = Vector2(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35)) * swarm_world.cell_size
	position = _cell_visual_pos()


func _physics_process(delta: float) -> void:
	if swarm_world == null:
		return
	queue_redraw()
	if funnel_active:
		# The funnel animation owns this frame's position. Still tick contact
		# damage so a scooping ant that brushes an enemy keeps biting.
		_advance_funnel(delta)
		_resolve_combat(delta)
		return
	position = position.lerp(_cell_visual_pos(), 1.0 - exp(-VISUAL_LERP_PER_SEC * delta))
	_advance_hunt_lockon(delta)
	_resolve_combat(delta)
	if funnel_cooldown > 0.0:
		funnel_cooldown -= delta
	_try_capture_funnel()


func _draw() -> void:
	var r: float = swarm_world.cell_size * 0.28
	if carry:
		draw_circle(Vector2.ZERO, r, Color(0.965, 0.753, 0.29, 1.0))
	else:
		draw_circle(Vector2.ZERO, r, Color(0.94, 0.92, 0.83, 1.0))
	draw_line(Vector2.ZERO, Vector2(DIRS_8[dir]) * r, Color(0.0, 0.0, 0.0, 0.35), 1.0)


func _cell_visual_pos() -> Vector2:
	return swarm_world.cell_to_world(Vector2i(x, y)) + visual_jitter


func update_step() -> void:
	# While the funnel animation is playing, the ant is mid-handover: skip the
	# field-scoring step so the pheromone it is being dropped into does not fight
	# the animation for its position. As soon as the animation ends it is back
	# under full field control.
	if funnel_active:
		return
	if command_active or (swarm_world != null and swarm_world.command_mode == SwarmWorld.COMMAND_CARNAGE):
		if lock_timer <= 0.0:
			refresh_carnage_command()
		if command_active:
			_step_direct()
			_check_pickup_and_delivery(swarm_world)
			return
	var world: SwarmWorld = swarm_world
	var home_field: ScalarField = world.get_field(ScalarFieldManager.FIELD_HOME_PHER)
	var player_field: ScalarField = world.get_field(ScalarFieldManager.FIELD_HUNT_PHER)
	var foot_field: ScalarField = world.get_field(ScalarFieldManager.FIELD_FOOT_TRAIL)
	var fresh_field: ScalarField = world.get_field(ScalarFieldManager.FIELD_PLAYER_FRESH)

	var noise: float = world.params_noise
	var prev_x := x
	var prev_y := y

	# Firewall noise zone. Amplitude is sampled ONCE from the ant's own cell, then
	# used as zero-mean jitter on each candidate's final score, so the field
	# scrambles decisions without pulling ants any direction (the old per-cell
	# attenuation biased them outward; this does not). A soft rim push keeps the
	# parked boundary fuzzy.
	var fw_here: Dictionary = world.firewall_influence_at(world.cell_to_world(Vector2i(x, y)))
	var fw_noise := 0.0
	var fw_rim_step := 0.0
	var fw_center := Vector2.ZERO
	var fw_cur_dist := 0.0
	if not fw_here.is_empty():
		var fw_inf: float = fw_here["influence"]
		fw_noise = fw_here["noise"] * fw_inf
		fw_center = fw_here["center"]
		var fw_radius := maxf(fw_here["radius"], 0.001)
		fw_cur_dist = world.cell_to_world(Vector2i(x, y)).distance_to(fw_center)
		var edge := clampf(fw_cur_dist / fw_radius, 0.0, 1.0)
		var rim_weight := clampf((edge - 0.4) / 0.6, 0.0, 1.0)
		fw_rim_step = fw_here["rim_push"] * rim_weight / maxf(world.cell_size, 0.001)

	var candidates: Array = []

	for offset in range(-2, 3):
		var d := (dir + offset + 8) % 8
		var nx := x + DIRS_8[d].x
		var ny := y + DIRS_8[d].y
		if world.blocked(nx, ny):
			continue

		var hf: float = home_field.get_cell(nx, ny)
		var pf: float = player_field.get_cell(nx, ny)
		var ft: float = foot_field.get_cell(nx, ny)
		var pfr: float = fresh_field.get_cell(nx, ny)

		var hf_s: float = world.saturation_penalty(hf)
		var pf_s: float = world.saturation_penalty(pf)

		var base_score: float = 0.3 - absi(offset) * 0.08

		var d_pf: float = pf - prev_pf
		var d_hf: float = hf - prev_hf
		var d_ft: float = ft - prev_ft

		var fresh_mult: float = 1.0 + pfr * world.params_fresh_bonus
		var player_score: float = pf * pf_s * fresh_mult

		var score: float = 0.0

		if not carry:
			score += base_score
			score += player_score * 7.0
			score += hf * 0.8 * hf_s

			var local_fresh: float = fresh_field.get_cell(x, y)
			if local_fresh < 0.15 and ever_delivered:
				score += ft * world.params_forag_hwy_w
				score += hf * world.params_forag_hwy_w * 0.8

			if pf < 0.03 and hf < 0.03 and ft < 0.03:
				score += world.params_explore * 0.9
		else:
			var cell_key := "%d,%d" % [nx, ny]
			var is_own_fresh_home: bool = fresh_home_set.has(cell_key)

			var dir_bonus := 1.0
			if absi(offset) == 0:
				dir_bonus = 1.2
			elif absi(offset) == 1:
				dir_bonus = 1.5
			else:
				dir_bonus = 0.5

			var gradient_score: float = d_hf * 0.7 + d_ft * 0.5

			var home_contrib: float
			if is_own_fresh_home:
				home_contrib = hf * hf_s * 0.05
			else:
				home_contrib = hf * hf_s * world.params_home_w * 1.1
			var ft_contrib: float = ft * world.params_ft_return_w * 0.9
			var player_contrib: float = player_score * 4.0

			score = dir_bonus + gradient_score + home_contrib + ft_contrib + player_contrib
			score += straightness * 0.9

			var conf_noise: float = world.params_return_noise * 0.35 if confidence > 0.65 else world.params_return_noise
			score += randf_range(-conf_noise, conf_noise)

			score *= world.saturation_penalty(maxf(hf, maxf(ft, pf)))

		# Firewall scramble: zero-mean jitter on the candidate's FINAL score. It is
		# applied here, after every nonlinearity, so nothing can rectify it into a
		# directional bias (scaling the raw samples would, via the saturation
		# penalty, and would push ants outward again).
		if fw_noise > 0.0:
			score += randf_range(-fw_noise, fw_noise) * FW_SCORE_SCALE

		# Soft outward push, strongest near the rim: reward candidates that move
		# the ant farther from the field centre. Small enough that a committed
		# attract can still hold the swarm inside.
		if fw_rim_step > 0.0:
			var cand_dist: float = world.cell_to_world(Vector2i(nx, ny)).distance_to(fw_center)
			score += fw_rim_step * (cand_dist - fw_cur_dist)

		score += randf_range(-noise, noise)
		candidates.append({"d": d, "nx": nx, "ny": ny, "score": score})

	prev_pf = player_field.get_cell(x, y)
	prev_hf = home_field.get_cell(x, y)
	prev_ft = foot_field.get_cell(x, y)

	if candidates.is_empty():
		dir = (dir + 4) % 8
		return

	candidates.sort_custom(func(a, b): return a.score > b.score)
	var chosen: Dictionary = candidates[0]

	var variability_chance := 0.15
	if carry:
		variability_chance = 0.10
	elif not ever_delivered:
		variability_chance = 0.15
	else:
		variability_chance = 0.20
	if candidates.size() > 1 and randf() < variability_chance:
		chosen = candidates[1]

	var turn := _wrapped_delta(dir, chosen.d)
	if absi(turn) > 1 and randf() < 0.5:
		dir = (dir + signi(turn) + 8) % 8
		var ndx: int = DIRS_8[dir].x
		var ndy: int = DIRS_8[dir].y
		if not world.blocked(x + ndx, y + ndy):
			x += ndx
			y += ndy
	else:
		dir = chosen.d
		x = chosen.nx
		y = chosen.ny

	var moved: bool = x != prev_x or y != prev_y
	straightness = 0.8 * straightness + 0.2 * (1.0 if absi(turn) <= 1 else 0.3)
	confidence = 0.9 * confidence + 0.1 * minf(1.0, maxf(0.0, straightness))

	if moved:
		var foot_cap: float = world.params_sat_cap * 1.5
		var fi := foot_field.idx(x, y)
		foot_field.data[fi] = minf(foot_field.data[fi] + world.params_ft_deposit, foot_cap)

	if carry and confidence > 0.20 and moved:
		home_field.stamp(x, y, 1, 0.12, world.params_sat_cap)
		var cell_key := "%d,%d" % [x, y]
		fresh_home_set[cell_key] = true
		fresh_home_age += 1
		if fresh_home_age % 60 == 0:
			fresh_home_set.clear()
			fresh_home_set[cell_key] = true

	_check_pickup_and_delivery(world)


func _check_pickup_and_delivery(world: SwarmWorld) -> void:
	for food: FoodSource in world.food_sources:
		if food.amount > 0 and not carry:
			var dx: int = x - food.cell_pos.x
			var dy: int = y - food.cell_pos.y
			if dx * dx + dy * dy <= food.radius_cells * food.radius_cells:
				carry = true
				food.amount -= 1
				dir = (dir + 4) % 8
				fresh_home_set.clear()
				fresh_home_age = 0
				return

	var ndx := x - world.nest_cell.x
	var ndy := y - world.nest_cell.y
	if carry and ndx * ndx + ndy * ndy <= world.nest_radius_cells * world.nest_radius_cells:
		carry = false
		dir = (dir + floori(randf_range(-1.0, 2.0)) + 8) % 8
		fresh_home_set.clear()
		fresh_home_age = 0
		ever_delivered = true
		world.notify_delivery()


func _wrapped_delta(a: int, b: int) -> int:
	var d := (b - a + 8) % 8
	if d > 4:
		d -= 8
	return d


## CARNAGE hook: if the world is in CARNAGE mode, re-target whatever enemy is
## currently nearest this ant and treat it as an active command.
func refresh_carnage_command() -> void:
	if swarm_world == null or swarm_world.command_mode != SwarmWorld.COMMAND_CARNAGE:
		return
	var t: Node2D = swarm_world.nearest_target_to(_cell_visual_pos())
	if t == null:
		command_active = false
		command_target = null
		return
	command_active = true
	command_target = t
	command_goal = _clamp_cell(swarm_world.world_to_cell(t.global_position))
	command_wp.clear()


## Ticks the hunt-cast lock-on attack. While a lock is active it counts down and,
## on expiry (or if the target dies), releases the command so the ant returns to
## field-driven movement. When not locked, a casted ant that has reached enemy
## vicinity engages a fresh lock-on against that enemy.
func _advance_hunt_lockon(delta: float) -> void:
	if lock_timer > 0.0:
		lock_timer -= delta
		if lock_timer <= 0.0 or not is_instance_valid(command_target):
			lock_timer = 0.0
			command_target = null
			command_active = false
		return
	_try_engage_hunt_lockon()


## Engages the lock-on when this ant is under an active hunt cast OR an active
## bomb and an enemy is within `hunt_lockon_radius_cells`. Sets the enemy as
## `command_target` so the normal command steering tracks it and the overlap DOT
## keeps it under attack.
func _try_engage_hunt_lockon() -> void:
	if command_active or lock_timer > 0.0:
		return
	if swarm_world == null:
		return
	if not (swarm_world.hunt_cast_active() or swarm_world.bomb_active()):
		return
	# While a cast is running, ants still inside the cast origin's march zone must
	# march out in the cast direction and must NOT divert to a point-blank enemy.
	# Past that zone they may lock on as usual (e.g. at the stop basin).
	if swarm_world.funnel_captures(_cell_visual_pos()):
		return
	var hunt: ScalarField = swarm_world.get_field(ScalarFieldManager.FIELD_HUNT_PHER)
	if hunt.get_cell(x, y) <= HUNT_LOCKON_MIN_HUNT:
		return
	# Prefer the enemy the cast is PINNED to, so an unrelated enemy standing beside
	# the player cannot hijack the march. The pin is only a preference, never a
	# gate: when it has died, wandered off its pinned cell, or was never resolved,
	# fall back to the nearest enemy in reach so the swarm always attacks whatever
	# it actually walks into.
	var enemy: Node2D = null
	if swarm_world.hunt_cast_active():
		var anchor: Node2D = swarm_world.cast_pinned_target()
		if anchor != null and _target_lockable(anchor):
			enemy = anchor
	if enemy == null:
		enemy = swarm_world.nearest_target_within_radius(_cell_visual_pos(), hunt_lockon_radius_cells)
	if enemy == null:
		return
	command_active = true
	command_target = enemy
	command_goal = _clamp_cell(swarm_world.world_to_cell(enemy.global_position))
	command_wp.clear()
	lock_timer = hunt_lockon_seconds


## True when `target` is a live, lockable enemy within the lock-on radius.
func _target_lockable(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var d: float = _cell_visual_pos().distance_to(target.global_position)
	return d <= hunt_lockon_radius_cells * swarm_world.cell_size


## Scoops this ant into the cast funnel if a hunt cast is running and the ant is
## within the small radius around the cast origin. This is pure animation: it
## writes no pheromone and consults no field. It exists purely to clear ants off
## the player so the pheromone trail they are meant to follow is not buried under
## the nest crowd.
func _try_capture_funnel() -> void:
	if funnel_active or lock_timer > 0.0 or funnel_cooldown > 0.0:
		return
	var cast: Dictionary = swarm_world.active_cast_funnel()
	if cast.is_empty():
		return
	var origin: Vector2 = cast["origin"]
	var r: float = swarm_world.funnel_capture_radius_cells * swarm_world.cell_size
	var off := _cell_visual_pos() - origin
	if off.length() > r:
		return
	var cdict: Dictionary = swarm_world.active_cast_funnel()
	var cseq: int = int(cdict.get("seq", 0))
	if cseq == funnel_done_seq:
		return
	funnel_active = true
	funnel_t = 0.0
	funnel_done_seq = cseq
	funnel_origin = origin
	funnel_dir = cast["dir"]
	funnel_entry_radius = off.length()
	funnel_entry_angle = off.angle()
	# Keep this ant's own offset from the aim axis. Every ant retains a different
	# one, so on launch they spread across the trail rather than converging on a
	# single cell (which is what made them pile up and stall there).
	var perp := Vector2(funnel_dir.y, -funnel_dir.x)
	funnel_lane = off.dot(perp)


## Drives the short gather animation. The corkscrew's centre travels outward along
## the aim while its radius collapses, so the ant visibly moves forward the whole
## time instead of spinning on the spot. On completion the ant is dropped into the
## pheromone trail a few cells out and immediately reverts to field-driven
## movement — the animation is over in a fraction of a second and is never a
## place an ant comes to rest.
func _advance_funnel(delta: float) -> void:
	var dur: float = maxf(0.05, swarm_world.funnel_seconds)
	funnel_t += delta / dur
	if funnel_t >= 1.0:
		_launch_from_funnel()
		return
	var t: float = clampf(funnel_t, 0.0, 1.0)
	var ang: float = funnel_entry_angle + swarm_world.funnel_turns * TAU * t
	var travel: float = swarm_world.funnel_travel_cells * swarm_world.cell_size * t
	var center: Vector2 = funnel_origin + funnel_dir * travel
	var perp := Vector2(funnel_dir.y, -funnel_dir.x)
	# The lane offset is held throughout, so the ant keeps its place in the front.
	var r: float = funnel_entry_radius * pow(1.0 - t, 1.3)
	position = center + perp * funnel_lane + Vector2(cos(ang), sin(ang)) * r


## Ends the animation and hands the ant back to the scalar field. It is dropped
## `funnel_launch_cells` down the trail, already facing the aim, so the pheromone
## it is now standing in immediately carries it further out. This is the handover
## point: from here the ant is moved by the cast's pheromone like any other.
func _launch_from_funnel() -> void:
	funnel_active = false
	funnel_t = 0.0
	funnel_cooldown = 0.5
	var world: SwarmWorld = swarm_world
	var perp := Vector2(funnel_dir.y, -funnel_dir.x)
	var drop: Vector2 = funnel_origin + funnel_dir * (world.funnel_travel_cells * world.cell_size) + perp * funnel_lane
	position = drop
	dir = _dir_index_from_vector(funnel_dir)
	var cell := _clamp_cell(world.world_to_cell(drop))
	for _i in range(maxi(1, world.funnel_launch_cells)):
		var step := cell + DIRS_8[dir]
		if not world.blocked(step.x, step.y):
			cell = step
	x = cell.x
	y = cell.y
	straightness = 1.0
	confidence = 0.6
	# Hand off to the trail: nudge forward until genuinely standing in the cast's
	# own pheromone. Each hunt pattern lays its trail somewhere different (multi
	# sprays toward every enemy, bounce runs a zigzag), so dropping blindly down
	# the aim could leave the ant in bare ground with no scent to follow — which
	# is what made them mill at the mouth. Scent-finding the handover works for
	# every pattern without the funnel needing to know the pattern's shape.
	_settle_into_trail()


## Steps this ant up to a few cells in whichever direction carries the strongest
## cast pheromone, stopping as soon as it is standing in a real trail. Falls back
## to the aim direction when no nearby cell has any scent at all. Purely a
## handover helper — it moves the ant ONTO the trail, it does not follow it.
func _settle_into_trail() -> void:
	var world: SwarmWorld = swarm_world
	var hunt: ScalarField = world.get_field(ScalarFieldManager.FIELD_HUNT_PHER)
	var here: float = hunt.get_cell(x, y)
	if here >= HUNT_TRAIL_MIN:
		return
	var best := Vector2i(x, y)
	var best_v := here
	for d in range(DIRS_8.size()):
			var nx: int = x + DIRS_8[d].x
			var ny: int = y + DIRS_8[d].y
			if world.blocked(nx, ny):
				continue
			var v: float = hunt.get_cell(nx, ny)
			if v > best_v:
				best_v = v
				best = Vector2i(nx, ny)
	if best_v > here:
		x = best.x
		y = best.y
		position = _cell_visual_pos()
		dir = _dir_index_from_vector(funnel_dir)


func _dir_index_from_vector(v: Vector2) -> int:
	if v.length() < 0.001:
		return dir
	var vn := v.normalized()
	var best := 0
	var best_dot := -INF
	for i in range(DIRS_8.size()):
		var d: float = Vector2(DIRS_8[i]).normalized().dot(vn)
		if d > best_dot:
			best_dot = d
			best = i
	return best


## Direct-command step (CARNAGE / lock-on). Steers the ant straight at its
## command goal, walking waypoints when a route is set, until it arrives or the
## command is cleared. A fleeing command instead picks the neighbour farthest
## from the danger cell. The target is re-read every step, so a live
## moving target is tracked to the death.
func _step_direct() -> void:
	if swarm_world == null:
		return
	var goal := command_goal

	# FLEE-FROM: pick the neighbour farthest from the danger cell; the command
	# ends once the ant escapes beyond `command_flee_radius`.
	if command_flee.x >= 0:
		var dx := x - command_flee.x
		var dy := y - command_flee.y
		var dist := maxi(absi(dx), absi(dy))
		if dist > command_flee_radius:
			command_active = false
			command_flee = Vector2i(-1, -1)
			return
		_step_flee()
		return

	# TRACK a live target, else walk the waypoint chain, else tail the goal.
	if command_target != null and is_instance_valid(command_target):
		goal = _clamp_cell(swarm_world.world_to_cell(command_target.global_position))
		command_goal = goal
	elif not command_wp.is_empty():
		goal = command_wp[0]
		if x == goal.x and y == goal.y:
			command_wp.pop_front()
			if not command_wp.is_empty():
				goal = command_wp[0]
	# Firewall influence at the ant's own cell. It degrades direct orders
	# (CONTROL casts / Rally) as well as the pheromone response, since manual
	# commands bypass the fields entirely.
	var fw_here: Dictionary = swarm_world.firewall_influence_at(swarm_world.cell_to_world(Vector2i(x, y)))
	var fw_direct_noise := 0.0
	if not fw_here.is_empty():
		fw_direct_noise = fw_here["noise"] * fw_here["influence"]

	if command_wp.is_empty() and command_target == null and x == goal.x and y == goal.y:
		# Arrived. Outside a field the ant simply holds. Inside a Firewall's
		# noise zone a "parked" ant occasionally slips to a random neighbour, so
		# a directly-commanded swarm cannot hold a tight formation there.
		if fw_direct_noise > 0.0 and randf() < fw_direct_noise * 0.4:
			_slip_step()
		command_active = false
		return

	var prev_x := x
	var prev_y := y
	var best_d := -1
	var best_score: float = INF
	for i in range(DIRS_8.size()):
		var nx := x + DIRS_8[i].x
		var ny := y + DIRS_8[i].y
		if swarm_world.blocked(nx, ny):
			continue
		if nx == goal.x and ny == goal.y:
			best_d = i
			best_score = 0.0
			break
		var dist := float((nx - goal.x) * (nx - goal.x) + (ny - goal.y) * (ny - goal.y))
		var turn := float(abs(_wrapped_delta(dir, i)))
		var straight := 1.0 - turn / 4.0
		var score := dist - straight * 4.0
		if fw_direct_noise > 0.0:
			score += randf_range(-fw_direct_noise, fw_direct_noise) * 6.0
		if score < best_score:
			best_score = score
			best_d = i

	if best_d >= 0:
		dir = best_d
		x = x + DIRS_8[dir].x
		y = y + DIRS_8[dir].y

	var moved: bool = x != prev_x or y != prev_y
	straightness = 0.8 * straightness + 0.2 * (1.0 if moved else 0.3)
	if command_target != null and not is_instance_valid(command_target):
		command_target = null
		command_active = false


## A single random step to a free neighbour, used by `_step_direct` to let a
## parked ant slip off its post inside a Firewall's noise zone.
func _slip_step() -> void:
	var opts: Array[int] = []
	for i in range(DIRS_8.size()):
		if not swarm_world.blocked(x + DIRS_8[i].x, y + DIRS_8[i].y):
			opts.append(i)
	if opts.is_empty():
		return
	dir = opts[randi() % opts.size()]
	x += DIRS_8[dir].x
	y += DIRS_8[dir].y


## Flee steering: choose the step (of the 8 neighbours) that maximises the
## Chebyshev distance to the danger cell, tie-broken by straightness so the
## ant keeps running in one direction instead of wiggling.
func _step_flee() -> void:
	var px := command_flee.x
	var py := command_flee.y
	var best_d := -1
	var best_score: float = -INF
	for i in range(DIRS_8.size()):
		var nx := x + DIRS_8[i].x
		var ny := y + DIRS_8[i].y
		if swarm_world.blocked(nx, ny):
			continue
		var dist := maxi(absi(nx - px), absi(ny - py))
		var turn := float(abs(_wrapped_delta(dir, i)))
		var straight := 1.0 - turn / 4.0
		var score := dist * 8.0 + straight * 3.0
		if score > best_score:
			best_score = score
			best_d = i

	if best_d >= 0:
		dir = best_d
		x = x + DIRS_8[dir].x
		y = y + DIRS_8[dir].y


func _clamp_cell(c: Vector2i) -> Vector2i:
	if swarm_world == null:
		return c
	return c.clamp(Vector2i.ZERO, Vector2i(swarm_world.cols - 1, swarm_world.rows - 1))


func _resolve_combat(delta: float) -> void:
	for area in get_overlapping_areas():
		if area.is_in_group("swarm_targets") and area.has_method("take_damage"):
			area.take_damage(DOT_PER_SECOND * delta)


func take_damage(amount: float) -> void:
	if dead:
		return
	hp -= amount
	if hp <= 0.0:
		dead = true
		if swarm_world != null and swarm_world.ant_manager != null:
			swarm_world.ant_manager.remove_agent(self)
		queue_free()
