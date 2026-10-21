extends RefCounted
class_name LevelGenerator1

## "Procedural 1" - the original BSP/maze generator, kept selectable from the
## menu. Rooms split out of a binary space partition, joined by corridors and
## dotted with pillars: a chokepoint-heavy, maze-like arena. The newer open
## generator lives in `level_generator_2.gd` ("Procedural 2").
##
## Pure and deterministic: (seed, combo, params) -> identical layout, and a
## different combo reshapes the *terrain* (not just enemy cells), because the
## combo changes both the RNG stream and the generator's motif weights.
##
## It is intentionally cheap: BSP rooms + corridors + pillars, then two linear
## grid passes (distance-to-wall, reachability from spawn) and placement. No
## pathfinding — the swarm follows pheromone gradients and only needs a
## connected, diffusion-friendly grid. Everything is O(cells).
##
## Output is a plain data grid, so swapping the wall renderer for a TileMap
## later is a rendering-only change.

class Level:
	var cols: int = 0
	var rows: int = 0
	## 1 = wall (blocks swarm movement and pheromone diffusion), 0 = open.
	var solid: PackedByteArray = PackedByteArray()
	## [{ "cell": Vector2i, "amount": int }, ...]
	var food: Array = []
	var spawn_cell: Vector2i = Vector2i.ZERO
	## [{ "type": int (Enemy.Type), "cell": Vector2i }, ...]
	var enemies: Array = []
	var seed: int = 0
	## Diagnostics for the chosen attempt (valid flag, openness, chokepoints...).
	var stats: Dictionary = {}


const DIRS4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Base tuning. Every value can be overridden by the caller.
const DEFAULTS := {
	"border": 1,
	"room_min": 6,
	"room_max": 16,
	"bsp_depth": 5,
	"room_margin": 2,
	"corridor_width": 3,
	"extra_link_chance": 0.4,
	"pillar_chance": 0.35,
	"pillar_max": 3,
	"food_count": 3,
	"food_amount": 200,
	"food_min_sep": 7,
	"enemy_min_sep": 6,
	"max_attempts": 24,
	"open_lo": 0.30,
	"open_hi": 0.82,
	"reach_lo": 0.90,
	"choke_min": 14,
}


## Generate a level. `combo` is an Array of Enemy.Type ints (may be empty).
static func generate(cols: int, rows: int, seed_value: int, combo: Array, params: Dictionary = {}) -> Level:
	var p: Dictionary = DEFAULTS.duplicate(true)
	for k in params.keys():
		p[k] = params[k]
	var motif := _apply_motifs(p, combo)
	var base_key: String = "%d|%d|%s" % [seed_value, combo_signature(combo), _param_key(motif)]
	var attempts: int = maxi(1, int(motif.get("max_attempts", 24)))
	var last: Level = null
	for attempt in range(attempts):
		var rng := RandomNumberGenerator.new()
		rng.seed = _fnv(base_key + ":" + str(attempt))
		var lvl := _attempt(cols, rows, rng, motif, combo)
		lvl.seed = seed_value
		last = lvl
		if bool(lvl.stats.get("valid", false)):
			return lvl
	return last


## Turn a user-entered seed string into an int. Pure integers are used as typed;
## any other text is hashed so a word is still a stable, shareable seed.
static func parse_seed(text: String) -> int:
	var t := text.strip_edges()
	if t == "":
		return 0
	if t.is_valid_int():
		return int(t)
	return _fnv(t)


## Order-independent combo signature, so picking the same enemies yields the same
## level for a given seed.
static func combo_signature(combo: Array) -> int:
	var ids: Array = []
	for c in combo:
		ids.append(int(c))
	ids.sort()
	var s := "c"
	for i in ids:
		s += ":" + str(i)
	return _fnv(s)


## FNV-1a over a string. Explicit so determinism does not depend on String.hash().
static func _fnv(s: String) -> int:
	var h: int = 0x811c9dc5
	for i in s.length():
		h = h ^ s.unicode_at(i)
		h = (h * 0x01000193) & 0xffffffff
	return h


## Canonical string of every param that shapes geometry, so the RNG stream is a
## function of (seed, combo, params) only.
static func _param_key(p: Dictionary) -> String:
	return "%d_%d_%d_%d_%d_%d_%d_%d_%d" % [
		int(p.get("room_min", 0)),
		int(p.get("room_max", 0)),
		int(p.get("bsp_depth", 0)),
		int(p.get("room_margin", 0)),
		int(p.get("corridor_width", 0)),
		int(round(float(p.get("extra_link_chance", 0.0)) * 1000.0)),
		int(round(float(p.get("pillar_chance", 0.0)) * 1000.0)),
		int(p.get("pillar_max", 0)),
		int(p.get("food_count", 0)),
	]


## Enemies bias the layout so their simple rule becomes relevant. Applied before
## carving, so the combo changes topology, not just enemy cells.
static func _apply_motifs(p: Dictionary, combo: Array) -> Dictionary:
	var m: Dictionary = p.duplicate(true)
	for c in combo:
		match int(c):
			Enemy.Type.PREDATOR:
				# Force clumping: fewer escape loops, tighter corridors.
				m["room_max"] = maxi(int(m["room_min"]) + 2, int(m["room_max"]) - 3)
				m["corridor_width"] = maxi(2, int(m["corridor_width"]) - 1)
				m["extra_link_chance"] = maxf(0.0, float(m["extra_link_chance"]) - 0.22)
			Enemy.Type.SIREN:
				# Bigger gathering basins for the lure to punish.
				m["room_min"] = int(m["room_min"]) + 2
			Enemy.Type.FIREWALL:
				# More internal structure -> a landmark region it can deny.
				m["pillar_chance"] = float(m["pillar_chance"]) + 0.18
			Enemy.Type.BROODMOTHER:
				# Longer, more subdivided routes for the economy to bleed along.
				m["bsp_depth"] = int(m["bsp_depth"]) + 1
				m["room_max"] = maxi(int(m["room_min"]) + 2, int(m["room_max"]) - 2)
			Enemy.Type.ASSASSIN:
				# Keep an open field to duel in.
				m["pillar_chance"] = maxf(0.0, float(m["pillar_chance"]) - 0.28)
	m["room_min"] = maxi(4, int(m["room_min"]))
	m["room_max"] = maxi(int(m["room_min"]) + 2, int(m["room_max"]))
	return m


# ---------------------------------------------------------------------------
# One attempt
# ---------------------------------------------------------------------------

static func _attempt(cols: int, rows: int, rng: RandomNumberGenerator, p: Dictionary, combo: Array) -> Level:
	var lvl := Level.new()
	lvl.cols = cols
	lvl.rows = rows
	lvl.solid.resize(cols * rows)
	lvl.solid.fill(1)

	var rooms := _carve_rooms(lvl, rng, p)
	if rooms.is_empty():
		lvl.stats = {"valid": false, "why": "no_rooms"}
		return lvl
	_carve_links(lvl, rooms, rng, p)
	_carve_extra_links(lvl, rooms, rng, p)
	_carve_pillars(lvl, rooms, rng, p)

	var dist_wall := _distance_to_wall(lvl.solid, cols, rows)
	lvl.spawn_cell = _pick_spawn(lvl, dist_wall, rng)

	var reach := _reachable(lvl.solid, cols, rows, lvl.spawn_cell)
	_place_food(lvl, reach, rng, p)
	_place_enemies(lvl, reach, dist_wall, rng, p, combo)

	lvl.stats = _validate(lvl, dist_wall, reach, p, combo)
	return lvl


# ---------------------------------------------------------------------------
# Terrain
# ---------------------------------------------------------------------------

static func _carve_rooms(lvl: Level, rng: RandomNumberGenerator, p: Dictionary) -> Array:
	var leaves: Array = []
	_split_leaf(Rect2i(1, 1, lvl.cols - 2, lvl.rows - 2), rng, p, leaves, 0)
	var rooms: Array = []
	for leaf in leaves:
		var margin: int = int(p["room_margin"])
		var max_w: int = leaf.size.x - margin * 2
		var max_h: int = leaf.size.y - margin * 2
		if max_w < int(p["room_min"]) or max_h < int(p["room_min"]):
			continue
		max_w = mini(max_w, int(p["room_max"]))
		max_h = mini(max_h, int(p["room_max"]))
		var rw: int = rng.randi_range(int(p["room_min"]), max_w)
		var rh: int = rng.randi_range(int(p["room_min"]), max_h)
		var rx: int = leaf.position.x + rng.randi_range(margin, leaf.size.x - margin - rw)
		var ry: int = leaf.position.y + rng.randi_range(margin, leaf.size.y - margin - rh)
		var room := Rect2i(Vector2i(rx, ry), Vector2i(rw, rh))
		rooms.append(room)
		_carve_rect(lvl, room)
	return rooms


static func _split_leaf(leaf: Rect2i, rng: RandomNumberGenerator, p: Dictionary, leaves: Array, depth: int) -> void:
	var min_leaf: int = int(p["room_min"]) + int(p["room_margin"]) * 2
	var can_x: bool = leaf.size.x >= min_leaf * 2
	var can_y: bool = leaf.size.y >= min_leaf * 2
	if depth >= int(p["bsp_depth"]) or (not can_x and not can_y):
		leaves.append(leaf)
		return
	var split_x: bool
	if can_x and can_y:
		split_x = leaf.size.x >= leaf.size.y
	elif can_x:
		split_x = true
	else:
		split_x = false
	if split_x:
		var cut: int = rng.randi_range(min_leaf, leaf.size.x - min_leaf)
		_split_leaf(Rect2i(leaf.position, Vector2i(cut, leaf.size.y)), rng, p, leaves, depth + 1)
		_split_leaf(Rect2i(leaf.position + Vector2i(cut, 0), Vector2i(leaf.size.x - cut, leaf.size.y)), rng, p, leaves, depth + 1)
	else:
		var cut2: int = rng.randi_range(min_leaf, leaf.size.y - min_leaf)
		_split_leaf(Rect2i(leaf.position, Vector2i(leaf.size.x, cut2)), rng, p, leaves, depth + 1)
		_split_leaf(Rect2i(leaf.position + Vector2i(0, cut2), Vector2i(leaf.size.x, leaf.size.y - cut2)), rng, p, leaves, depth + 1)


static func _carve_links(lvl: Level, rooms: Array, rng: RandomNumberGenerator, p: Dictionary) -> void:
	var w: int = int(p["corridor_width"])
	for i in range(1, rooms.size()):
		_carve_corridor(lvl, _room_center(rooms[i - 1]), _room_center(rooms[i]), w, rng)


static func _carve_extra_links(lvl: Level, rooms: Array, rng: RandomNumberGenerator, p: Dictionary) -> void:
	if rooms.size() < 3:
		return
	var w: int = maxi(2, int(p["corridor_width"]) - 1)
	for i in range(rooms.size()):
		if rng.randf() < float(p["extra_link_chance"]):
			var j: int = rng.randi_range(0, rooms.size() - 1)
			if j != i:
				_carve_corridor(lvl, _room_center(rooms[i]), _room_center(rooms[j]), w, rng)


static func _carve_pillars(lvl: Level, rooms: Array, rng: RandomNumberGenerator, p: Dictionary) -> void:
	for room in rooms:
		if rng.randf() >= float(p["pillar_chance"]):
			continue
		var blocks: int = rng.randi_range(1, maxi(1, int(p["pillar_max"])))
		for _b in range(blocks):
			var size: int = rng.randi_range(1, 2)
			# Keep a 2-cell margin so pillars never seal a room or a doorway.
			if room.size.x - 4 < size or room.size.y - 4 < size:
				continue
			var px: int = room.position.x + rng.randi_range(2, room.size.x - 2 - size)
			var py: int = room.position.y + rng.randi_range(2, room.size.y - 2 - size)
			for y in range(py, py + size):
				for x in range(px, px + size):
					if x >= 1 and x < lvl.cols - 1 and y >= 1 and y < lvl.rows - 1:
						lvl.solid[y * lvl.cols + x] = 1


static func _carve_corridor(lvl: Level, a: Vector2i, b: Vector2i, w: int, rng: RandomNumberGenerator) -> void:
	if rng.randf() < 0.5:
		_carve_h(lvl, a.x, b.x, a.y, w)
		_carve_v(lvl, a.y, b.y, b.x, w)
	else:
		_carve_v(lvl, a.y, b.y, a.x, w)
		_carve_h(lvl, a.x, b.x, b.y, w)


static func _carve_h(lvl: Level, x0: int, x1: int, y: int, w: int) -> void:
	var half: int = w / 2
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		for dy in range(-half, half + 1):
			_open_if_in(lvl, x, y + dy)


static func _carve_v(lvl: Level, y0: int, y1: int, x: int, w: int) -> void:
	var half: int = w / 2
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		for dx in range(-half, half + 1):
			_open_if_in(lvl, x + dx, y)


static func _carve_rect(lvl: Level, room: Rect2i) -> void:
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			_open_if_in(lvl, x, y)


static func _open_if_in(lvl: Level, x: int, y: int) -> void:
	if x < 1 or x >= lvl.cols - 1 or y < 1 or y >= lvl.rows - 1:
		return
	lvl.solid[y * lvl.cols + x] = 0


static func _room_center(room: Rect2i) -> Vector2i:
	return room.position + room.size / 2


# ---------------------------------------------------------------------------
# Grid features
# ---------------------------------------------------------------------------

## Manhattan distance from every cell to the nearest wall (wall cells = 0).
static func _distance_to_wall(solid: PackedByteArray, cols: int, rows: int) -> PackedInt32Array:
	var n: int = cols * rows
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(1 << 30)
	var queue := PackedInt32Array()
	for i in range(n):
		if solid[i] == 1:
			dist[i] = 0
			queue.append(i)
	var head: int = 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var x: int = i % cols
		var y: int = i / cols
		var d: int = dist[i] + 1
		for dir in DIRS4:
			var nx: int = x + dir.x
			var ny: int = y + dir.y
			if nx < 0 or nx >= cols or ny < 0 or ny >= rows:
				continue
			var ni: int = ny * cols + nx
			if d < dist[ni]:
				dist[ni] = d
				queue.append(ni)
	return dist


## BFS over open cells from `start`.
## Returns { dist: PackedInt32Array (-1 = unreachable), cells: Array[int], count, maxd }.
static func _reachable(solid: PackedByteArray, cols: int, rows: int, start: Vector2i) -> Dictionary:
	var n: int = cols * rows
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var cells: Array = []
	var start_i: int = start.y * cols + start.x
	if start_i < 0 or start_i >= n or solid[start_i] == 1:
		return {"dist": dist, "cells": cells, "count": 0, "maxd": 0}
	dist[start_i] = 0
	var queue := PackedInt32Array([start_i])
	cells.append(start_i)
	var head: int = 0
	var maxd: int = 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var x: int = i % cols
		var y: int = i / cols
		var nd: int = dist[i] + 1
		for dir in DIRS4:
			var nx: int = x + dir.x
			var ny: int = y + dir.y
			if nx < 0 or nx >= cols or ny < 0 or ny >= rows:
				continue
			var ni: int = ny * cols + nx
			if solid[ni] == 1 or dist[ni] != -1:
				continue
			dist[ni] = nd
			queue.append(ni)
			cells.append(ni)
			maxd = maxi(maxd, nd)
	return {"dist": dist, "cells": cells, "count": cells.size(), "maxd": maxd}


# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

static func _pick_spawn(lvl: Level, dist_wall: PackedInt32Array, rng: RandomNumberGenerator) -> Vector2i:
	var center := Vector2(lvl.cols - 1, lvl.rows - 1) * 0.5
	var best_score := INF
	var best := Vector2i(lvl.cols / 2, lvl.rows / 2)
	for y in range(1, lvl.rows - 1):
		for x in range(1, lvl.cols - 1):
			var i: int = y * lvl.cols + x
			if lvl.solid[i] == 1 or dist_wall[i] < 3:
				continue
			var score: float = Vector2(x, y).distance_to(center) + rng.randf() * 3.0
			if score < best_score:
				best_score = score
				best = Vector2i(x, y)
	if best_score == INF:
		# Relaxed fallback: any open cell nearest the centre.
		for y in range(1, lvl.rows - 1):
			for x in range(1, lvl.cols - 1):
				if lvl.solid[y * lvl.cols + x] == 0:
					var s := Vector2(x, y).distance_to(center)
					if s < best_score:
						best_score = s
						best = Vector2i(x, y)
	return best


static func _place_food(lvl: Level, reach: Dictionary, rng: RandomNumberGenerator, p: Dictionary) -> void:
	var reach_dist: PackedInt32Array = reach["dist"]
	var maxd: int = maxi(1, int(reach["maxd"]))
	var chosen: Array = []
	for frac in _tier_fractions(int(p["food_count"])):
		var target: float = float(frac) * float(maxd)
		var best_score := INF
		var best := Vector2i(-1, -1)
		for i in reach["cells"]:
			var x: int = i % lvl.cols
			var y: int = i / lvl.cols
			var d: int = reach_dist[i]
			if d < 4:
				continue
			if _too_close(Vector2i(x, y), chosen, int(p["food_min_sep"])):
				continue
			var score: float = absf(float(d) - target) + rng.randf() * 0.75
			if score < best_score:
				best_score = score
				best = Vector2i(x, y)
		if best.x >= 0:
			chosen.append(best)
			lvl.food.append({"cell": best, "amount": int(p["food_amount"])})


static func _tier_fractions(count: int) -> Array:
	match count:
		1:
			return [0.5]
		2:
			return [0.3, 0.75]
		3:
			return [0.28, 0.58, 0.88]
		_:
			var out: Array = []
			for k in range(count):
				out.append(lerpf(0.25, 0.9, float(k) / float(maxi(1, count - 1))))
			return out


static func _place_enemies(lvl: Level, reach: Dictionary, dist_wall: PackedInt32Array, rng: RandomNumberGenerator, p: Dictionary, combo: Array) -> void:
	var reach_dist: PackedInt32Array = reach["dist"]
	var maxd: int = maxi(1, int(reach["maxd"]))
	var placed: Array = []
	var food_cells: Array = []
	for f in lvl.food:
		food_cells.append(f["cell"])
	# Fixed order (sorted), so the seed — not the pick order — varies the layout.
	var order: Array = []
	for c in combo:
		order.append(int(c))
	order.sort()
	for type in order:
		var cell := _candidate_for(type, lvl, reach_dist, dist_wall, maxd, placed, food_cells, rng, p)
		if cell.x >= 0:
			placed.append(cell)
			lvl.enemies.append({"type": type, "cell": cell})


static func _candidate_for(type: int, lvl: Level, reach_dist: PackedInt32Array, dist_wall: PackedInt32Array, maxd: int, placed: Array, food_cells: Array, rng: RandomNumberGenerator, p: Dictionary) -> Vector2i:
	# Pass 0: strict predicate + strict separation. Pass 1: relaxed, so a combo
	# never silently drops an enemy on an unlucky layout.
	for relax in range(2):
		var relaxed: bool = relax == 1
		var sep: int = int(p["enemy_min_sep"]) if not relaxed else maxi(2, int(p["enemy_min_sep"]) / 2)
		var best := Vector2i(-1, -1)
		var best_score := INF
		for y in range(1, lvl.rows - 1):
			for x in range(1, lvl.cols - 1):
				var i: int = y * lvl.cols + x
				if lvl.solid[i] == 1 or reach_dist[i] < 0:
					continue
				var cell := Vector2i(x, y)
				if _too_close(cell, placed, sep):
					continue
				var score := _candidate_score(type, cell, reach_dist[i], dist_wall[i], maxd, food_cells, relaxed)
				if score == INF:
					continue
				score += rng.randf() * 0.5
				if score < best_score:
					best_score = score
					best = cell
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Lower is better; INF means the cell fails the type's predicate.
static func _candidate_score(type: int, cell: Vector2i, d: int, w: int, maxd: int, food_cells: Array, relaxed: bool) -> float:
	match type:
		Enemy.Type.PREDATOR:
			# Ambush from a chokepoint (narrow cells) along the middle of the map.
			# Needs a little clearance so its body is not half-inside the wall.
			if w > (3 if relaxed else 2):
				return INF
			if d < 0.20 * maxd or d > 0.85 * maxd:
				return INF
			return float(w) * 1.5 + absf(float(d) - 0.5 * maxd) * 0.5
		Enemy.Type.SIREN:
			# A big basin, far from the nest, where a lure can trap a crowd.
			if w < (2 if relaxed else 3):
				return INF
			if d < (0.45 if relaxed else 0.55) * maxd:
				return INF
			return absf(float(d) - 0.8 * maxd)
		Enemy.Type.FIREWALL:
			# A room with a landmark feel, denying the mid/far basin.
			if w < (2 if relaxed else 3):
				return INF
			if d < (0.25 if relaxed else 0.35) * maxd:
				return INF
			return absf(float(d) - 0.6 * maxd)
		Enemy.Type.BROODMOTHER:
			# Sits on a food->nest route so it can farm the carriers.
			var fd: int = _nearest_food_dist(cell, food_cells)
			if fd > (12 if relaxed else 7):
				return INF
			return float(fd) + absf(float(d) - 0.5 * maxd) * 0.2
		Enemy.Type.ASSASSIN:
			# The far, open half of the map: a clean duelling lane.
			if w < (1 if relaxed else 2):
				return INF
			if d < (0.5 if relaxed else 0.6) * maxd:
				return INF
			return -float(d)
		_:
			return float(d)
	return INF


static func _nearest_food_dist(cell: Vector2i, food_cells: Array) -> int:
	var best: int = 1 << 30
	for f in food_cells:
		var fc: Vector2i = f
		best = mini(best, absi(fc.x - cell.x) + absi(fc.y - cell.y))
	return best


static func _too_close(cell: Vector2i, cells: Array, sep: int) -> bool:
	for c in cells:
		var cc: Vector2i = c
		if absi(cc.x - cell.x) + absi(cc.y - cell.y) < sep:
			return true
	return false


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

static func _validate(lvl: Level, dist_wall: PackedInt32Array, reach: Dictionary, p: Dictionary, combo: Array) -> Dictionary:
	var n: int = lvl.cols * lvl.rows
	var open_count: int = 0
	for i in range(n):
		if lvl.solid[i] == 0:
			open_count += 1
	var reach_count: int = int(reach["count"])
	var reach_frac: float = float(reach_count) / float(maxi(1, open_count))
	var openness: float = float(open_count) / float(n)
	var reach_dist: PackedInt32Array = reach["dist"]

	var chokepoints: int = 0
	for i in reach["cells"]:
		if dist_wall[i] <= 1:
			chokepoints += 1

	var spawn_i: int = lvl.spawn_cell.y * lvl.cols + lvl.spawn_cell.x
	var spawn_basin: bool = dist_wall[spawn_i] >= 2

	var food_ok: bool = lvl.food.size() > 0
	for f in lvl.food:
		var c: Vector2i = f["cell"]
		if reach_dist[c.y * lvl.cols + c.x] < 0:
			food_ok = false

	var enemy_ok: bool = lvl.enemies.size() == combo.size()
	for e in lvl.enemies:
		var c: Vector2i = e["cell"]
		var i: int = c.y * lvl.cols + c.x
		if lvl.solid[i] == 1 or reach_dist[i] < 0:
			enemy_ok = false

	var valid: bool = (
		reach_frac >= float(p["reach_lo"])
		and openness >= float(p["open_lo"])
		and openness <= float(p["open_hi"])
		and chokepoints >= int(p["choke_min"])
		and spawn_basin
		and food_ok
		and enemy_ok
	)
	return {
		"valid": valid,
		"openness": openness,
		"reach_frac": reach_frac,
		"open_count": open_count,
		"reachable_count": reach_count,
		"chokepoints": chokepoints,
		"spawn_basin": spawn_basin,
		"food_ok": food_ok,
		"enemy_ok": enemy_ok,
		"food_count": lvl.food.size(),
		"enemy_count": lvl.enemies.size(),
		"max_dist": int(reach["maxd"]),
	}
