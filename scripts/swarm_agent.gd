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

var swarm_world: SwarmWorld = null

var x: int = 0
var y: int = 0
var dir: int = 0
var carry: bool = false

var straightness: float = 1.0
var confidence: float = 0.0
var prev_pf: float = 0.0
var prev_hf: float = 0.0
var prev_ft: float = 0.0
var ever_delivered: bool = false

var fresh_home_set: Dictionary = {}
var fresh_home_age: int = 0

var visual_jitter: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("swarm_agents")
	visual_jitter = Vector2(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35)) * swarm_world.cell_size
	position = _cell_visual_pos()


func _physics_process(delta: float) -> void:
	if swarm_world == null:
		return
	position = position.lerp(_cell_visual_pos(), 1.0 - exp(-VISUAL_LERP_PER_SEC * delta))
	queue_redraw()
	_resolve_combat(delta)


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
	var world: SwarmWorld = swarm_world
	var home_field: ScalarField = world.get_field(ScalarFieldManager.FIELD_HOME_PHER)
	var player_field: ScalarField = world.get_field(ScalarFieldManager.FIELD_HUNT_PHER)
	var foot_field: ScalarField = world.get_field(ScalarFieldManager.FIELD_FOOT_TRAIL)
	var fresh_field: ScalarField = world.get_field(ScalarFieldManager.FIELD_PLAYER_FRESH)

	var noise: float = world.params_noise
	var prev_x := x
	var prev_y := y

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


func _resolve_combat(delta: float) -> void:
	for area in get_overlapping_areas():
		if area.is_in_group("swarm_targets") and area.has_method("take_damage"):
			area.take_damage(DOT_PER_SECOND * delta)


func take_counter_damage(_amount: float) -> void:
	pass
