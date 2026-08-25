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
@export var show_pheromone_vis: bool = true
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

var field_manager: ScalarFieldManager
var ant_manager: AntManager
var _sticky_timer: float = 0.0
var _vis_timer: float = 0.0
var _vis_layers: Array = []
var _active_cast: Dictionary = {}
var _active_bomb: Dictionary = {}
var _nest_suppress_timer: float = 0.0
var nest_emit_enabled: bool = true

const VIS_REFRESH_INTERVAL: float = 0.1


func _ready() -> void:
	cols = maxi(1, int(arena_size.x / cell_size))
	rows = maxi(1, int(arena_size.y / cell_size))
	origin = arena_center - arena_size * 0.5

	_setup_vis()

	field_manager = ScalarFieldManager.new()
	field_manager.setup(cols, rows)
	add_child(field_manager)

	nest_cell = world_to_cell(nest_position)

	for food in get_tree().get_nodes_in_group("food_sources"):
		food_sources.append(food)

	ant_manager = AntManager.new()
	add_child(ant_manager)
	ant_manager.setup(self, ant_count)


## The nest source follows this node (e.g. the player). Its position is the
## home-pheromone source every frame, so the nest field travels with it.
func set_nest_carrier(node: Node2D) -> void:
	nest_carrier = node


## Turn the persistent nest (home) pheromone emission on or off. Casts can
## still temporarily suppress it via `_nest_suppress_timer`; this is the
## all-time master switch (N key).
func set_nest_emit_enabled(enabled: bool) -> void:
	nest_emit_enabled = enabled


func _physics_process(delta: float) -> void:
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

	field_manager.step(delta)
	ant_manager.step(delta)

	if not _active_cast.is_empty():
		var timer: float = _active_cast["timer"] - delta
		if timer <= 0.0:
			_active_cast = {}
		else:
			_active_cast["timer"] = timer
			_active_cast["elapsed"] = float(_active_cast["elapsed"]) + delta
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
			_vis_timer = VIS_REFRESH_INTERVAL
			_update_vis()
		queue_redraw()
	elif show_overlay:
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


## Cast the active hunt pattern by stamping the shared hunt field, then
## re-stamping it every frame for `cast_effect_seconds` so the structure stays
## strong enough for ants to follow. Player → scalar field → ant; never a
## direct command.
## pattern: "direct" | "loop" | "multi" | "bounce"
func cast_hunt(world_pos: Vector2, aim_dir: Vector2, pattern: String, target: Node2D = null) -> void:
	_active_cast = {
		"pattern": pattern,
		"world_pos": world_pos,
		"aim_dir": aim_dir,
		"target": target,
		"timer": cast_effect_seconds,
		"elapsed": 0.0,
	}
	_nest_suppress_timer = nest_suppress_seconds
	_apply_cast(world_pos, aim_dir, pattern, target, 0.0)


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
	var targets := get_tree().get_nodes_in_group("swarm_targets")
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
	if show_overlay:
		_draw_field(ScalarFieldManager.FIELD_HOME_PHER, Color(0.56, 0.75, 0.29), 0.02)
		_draw_field(ScalarFieldManager.FIELD_FOOT_TRAIL, Color(0.29, 0.78, 0.83), 0.015)
		_draw_field(ScalarFieldManager.FIELD_HUNT_PHER, Color(0.76, 0.55, 0.17), 0.018)

	_draw_arena_border()
	_draw_nest()
	for food in food_sources:
		_draw_food(food)


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
	draw_rect(Rect2(origin, arena_size), Color(0.6, 0.6, 0.6, 0.4), false, 1.0)


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


func saturation_penalty(v: float) -> float:
	var opt: float = params_sat_cap * 0.5
	if v < opt:
		return 1.0
	var excess: float = (v - opt) / (params_sat_cap - opt + 0.000001)
	return maxf(params_sat_pen, 1.0 - excess * (1.0 - params_sat_pen))


func get_field(field_name: String) -> ScalarField:
	return field_manager.get_field(field_name)


func notify_delivery() -> void:
	deliveries += 1
	deliveries_changed.emit(deliveries)
