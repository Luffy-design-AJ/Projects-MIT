extends RefCounted
class_name LevelGenerator2

## "Procedural 2" - the open arena generator.
##
## DESIGN: an open arena of obstacle set-pieces, not a carved maze. The arena is
## bigger than a screen (so it must be explored), walls cover roughly 30-40% of
## the floor, and the gaps between blocks stay several cells wide, so the swarm
## always has room to flow. The enemy combo picks an *archetype* (open field /
## lanes / ring / quadrants / scatter) that decides the shape of the cover; a
## bounded "densify" pass then adds fill until the floor sits in the openness
## band. The seed varies the exact placement, not the archetype.
##
## Determinism: the same (seed, combo, params) always yields the same level, and
## a different combo with the same seed yields a different layout. All randomness
## comes from one RNG seeded by a hash of those three.
##
## Performance: O(cells) per attempt (two grid sweeps + bounded placement). No
## pathfinding, because the swarm follows pheromone values, not routes.

class Level:
	var cols: int = 0
	var rows: int = 0
	## 1 = solid (blocks ants and pheromone diffusion), 0 = open.
	var solid: PackedByteArray = PackedByteArray()
	## [{ "cell": Vector2i, "amount": int }, ...]
	var food: Array = []
	var spawn_cell: Vector2i = Vector2i.ZERO
	## [{ "type": int (Enemy.Type), "cell": Vector2i }, ...]
	var enemies: Array = []
	var seed: int = 0
	## Diagnostics for the chosen attempt.
	var stats: Dictionary = {}


const DIRS4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Fixed order, used to break archetype ties deterministically.
const ARCH_ORDER := ["open_field", "lanes", "ring", "quadrants", "scatter"]

const DEFAULTS := {
	"border": 1,
	# Archetype set by _apply_motifs from the combo.
	"archetype": "scatter",
	# Target width of the lanes between obstacles, in world px (scaled per grid).
	"lane_px": 24.0,
	"open_lo": 0.50,
	"open_hi": 0.70,
	## Keep stamping cover until openness falls to at most this (per-archetype).
	"densify_to": 0.64,
	"reach_lo": 0.98,
	"spawn_clear": 2,
	"enemy_clear": 2,
	"enemy_ring_min": 0.32,
	"enemy_ring_max": 0.72,
	"enemy_min_sep": 6,
	## Threat budget. The arena fields at least this many enemies (scaled by its
	## world area and how open it is), so a bigger / airier arena is not easier.
	## The player's hand-picked combo is always a floor. Set threat_scaling=false
	## to place exactly the picked combo again.
	"threat_scaling": true,
	"enemy_budget_base": 6,
	"enemy_budget_ref_area": 1280.0 * 800.0,
	"enemy_budget_ref_open": 0.60,
	## Score band (in cells) within which a post is preferred if it has no line
	## of sight to the nest — i.e. it hides behind cover for an ambush.
	"ambush_band": 6.0,
	## World px of the cell size the grid was built at, so the budget can measure
	## the arena's real footprint regardless of how coarse the grid is.
	"cell_size": 10.0,
	"food_count": 3,
	"food_amount": 200,
	"food_min_sep": 8,
	"max_attempts": 24,
}

# ---------------------------------------------------------------------------
# Entry points
# ---------------------------------------------------------------------------

static func generate(cols: int, rows: int, seed_value: int, combo: Array, params: Dictionary = {}) -> Level:
	var p: Dictionary = DEFAULTS.duplicate(true)
	for k in params.keys():
		p[k] = params[k]
	var motif := _apply_motifs(p, combo)
	# Obstacles are sized in cells, but the arena has a fixed world size, so scale
	# block dimensions by the grid to keep the same *world* footprint (and
	# therefore the same openness) at any cell size. Reference: 230 cols at a 10 px
	# cell ~= the 2304 px open arena, so `k` is cells-per-reference-cell.
	# Lanes and margins scale too, so the space between obstacles stays a
	# consistent world width (~`lane_px`) and never a 1-cell maze corridor.
	var k: float = clampf(float(cols) / 80.0, 0.45, 2.0)
	motif["scale"] = k
	motif["gap"] = maxi(2, int(round(float(motif["lane_px"]) * k / 10.0)))
	motif["margin"] = maxi(3, int(motif["border"]) + int(motif["gap"]))
	motif["spawn_clear"] = maxi(2, int(round(float(motif["spawn_clear"]) * k)))
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


## Turn a user-entered seed string into an int. Integers are used as typed; any
## other text is hashed so a word is still a stable, shareable seed.
static func parse_seed(text: String) -> int:
	var t := text.strip_edges()
	if t == "":
		return 0
	if t.is_valid_int():
		return int(t)
	return _fnv(t)


## Order-independent combo signature. Duplicates matter, so a combo of
## [PREDATOR, PREDATOR, SIREN] hashes differently from [PREDATOR, SIREN].
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
	var h: int = 2166136261
	for i in range(s.length()):
		h = h ^ s.unicode_at(i)
		h = (h * 16777619) & 0xFFFFFFFF
	return h


## Stable string of every param, so any override changes the RNG stream.
static func _param_key(p: Dictionary) -> String:
	var keys: Array = p.keys()
	keys.sort()
	var s := ""
	for k in keys:
		s += "%s=%s;" % [str(k), str(p[k])]
	return s


## Enemy type -> arena archetype.
static func _archetype_for(type: int) -> String:
	match type:
		Enemy.Type.ASSASSIN:
			return "open_field"
		Enemy.Type.PREDATOR:
			return "lanes"
		Enemy.Type.FIREWALL:
			return "quadrants"
		Enemy.Type.BROODMOTHER:
			return "scatter"
		Enemy.Type.SIREN:
			return "ring"
	return "scatter"


## How dense each archetype is allowed to get (openness ceiling; lower = denser).
## The open field stays airiest for a duel; quadrants packs the tightest.
const DENSIFY_TARGETS := {
	"open_field": 0.67,
	"lanes": 0.64,
	"ring": 0.62,
	"quadrants": 0.60,
	"scatter": 0.61,
}


## Count-weighted pick: the most numerous type decides the arena, ties resolved
## by a fixed order so the choice is deterministic.
static func _apply_motifs(p: Dictionary, combo: Array) -> Dictionary:
	var m: Dictionary = p.duplicate(true)
	var weights: Dictionary = {}
	for c in combo:
		var a: String = _archetype_for(int(c))
		weights[a] = int(weights.get(a, 0)) + 1
	if weights.is_empty():
		return m
	var best := "scatter"
	var best_w := -1
	for key in ARCH_ORDER:
		var w: int = int(weights.get(key, 0))
		if w > best_w:
			best_w = w
			best = key
	m["archetype"] = best
	m["densify_to"] = float(DENSIFY_TARGETS.get(best, 0.64))
	return m


# ---------------------------------------------------------------------------
# One attempt
# ---------------------------------------------------------------------------

static func _attempt(cols: int, rows: int, rng: RandomNumberGenerator, p: Dictionary, combo: Array) -> Level:
	var lvl := Level.new()
	lvl.cols = cols
	lvl.rows = rows
	lvl.solid.resize(cols * rows)
	lvl.solid.fill(0)
	_seal_border(lvl, p)
	_stamp_archetype(lvl, rng, p)
	# Reserve an open basin at the centre for the nest, then fill in cover around
	# it. This guarantees the spawn always has clearance no matter how dense the
	# rest of the arena gets.
	var half: int = maxi(2, int(p["spawn_clear"]) + 1)
	var bc := Vector2i(cols / 2, rows / 2)
	var basin := Rect2i(bc - Vector2i(half, half), Vector2i(half * 2 + 1, half * 2 + 1))
	_clear_rect(lvl, basin)
	_densify(lvl, rng, p, basin)

	var dist_wall := _distance_to_wall(lvl.solid, cols, rows)
	lvl.spawn_cell = _pick_spawn(lvl, dist_wall, rng, p)

	var reach := _reachable(lvl.solid, cols, rows, lvl.spawn_cell)
	_place_food(lvl, reach, rng, p)
	# Threat scales with the arena's real footprint and how open it is, so a
	# larger / airier layout is not quietly easier than a cramped one.
	var openness := _openness_frac(lvl)
	var target := _enemy_target_count(p, cols, rows, openness, combo)
	p["enemy_target"] = target
	_place_enemies(lvl, reach, dist_wall, rng, p, combo, target)

	lvl.stats = _validate(lvl, dist_wall, reach, p, combo)
	return lvl


## Outer ring of solid cells, so the arena is always sealed (ants and diffusion
## stay inside). Everything else starts open.
static func _seal_border(lvl: Level, p: Dictionary) -> void:
	var b: int = maxi(1, int(p["border"]))
	for y in range(lvl.rows):
		for x in range(lvl.cols):
			if x < b or x >= lvl.cols - b or y < b or y >= lvl.rows - b:
				lvl.solid[y * lvl.cols + x] = 1


# ---------------------------------------------------------------------------
# Obstacle archetypes
# ---------------------------------------------------------------------------

static func _stamp_archetype(lvl: Level, rng: RandomNumberGenerator, p: Dictionary) -> void:
	match str(p.get("archetype", "scatter")):
		"open_field":
			_stamp_open_field(lvl, rng, p)
		"quadrants":
			_stamp_quadrants(lvl, rng, p)
		"ring":
			_stamp_ring(lvl, rng, p)
		"lanes":
			_stamp_lanes(lvl, rng, p)
		_:
			_stamp_scatter(lvl, rng, p)


## A duelling field: a few big cover pillars with room to circle them.
static func _stamp_open_field(lvl: Level, rng: RandomNumberGenerator, p: Dictionary) -> void:
	var placed: Array = []
	var count := rng.randi_range(4, 6)
	for _i in range(count):
		var w := _scaled(p, rng, 5, 9)
		var h := _scaled(p, rng, 5, 9)
		if not _random_block(lvl, rng, p, placed, w, h):
			continue


## Cell dimensions scale with the grid so all cell sizes share a look.
static func _scaled(p: Dictionary, rng: RandomNumberGenerator, lo: int, hi: int) -> int:
	var k: float = float(p.get("scale", 1.0))
	return maxi(1, int(round(float(rng.randi_range(lo, hi)) * k)))


## Keeps stamping medium cover blocks until the arena is dense enough to land in
## the openness band (tracked incrementally so the loop never rescans the grid).
## Each block keeps a clear `gap` band from every existing solid cell and never
## intrudes on the reserved spawn basin, so lanes stay wide and the result reads
## as cover dotted through the room, not a maze. The loop is bounded: a grid that
## cannot reach the target simply stops and is rejected by the validator.
static func _densify(lvl: Level, rng: RandomNumberGenerator, p: Dictionary, basin: Rect2i) -> void:
	var total: int = lvl.cols * lvl.rows
	var solid: int = 0
	for i in range(total):
		solid += lvl.solid[i]
	var target: float = float(p.get("densify_to", 0.64))
	var guard: int = 0
	while float(total - solid) / float(total) > target and guard < 200:
		guard += 1
		# Big blocks first (best coverage), falling back to small ones so leftover
		# pockets still get filled. The schedule steps down every few placements so
		# even a cramped grid reaches the small blocks that still fit.
		var placed_this: bool = false
		for attempt in range(48):
			var lo: int = maxi(2, 14 - (attempt / 4) * 2)
			var w := _scaled(p, rng, lo, mini(lo + 4, 18))
			var h := _scaled(p, rng, lo, mini(lo + 4, 18))
			if _place_free_block(lvl, rng, p, w, h, basin):
				solid += w * h
				placed_this = true
				break
		if not placed_this:
			# No legal spot left; stop rather than spin. The validator rejects the
			# level if it still did not reach the band.
			break


## Places a block only where it keeps a clear `gap` band from every existing
## solid cell (never sealing a region or leaving a 1-cell passage) and stays out
## of the reserved spawn basin.
static func _place_free_block(lvl: Level, rng: RandomNumberGenerator, p: Dictionary, w: int, h: int, basin: Rect2i) -> bool:
	var margin: int = int(p.get("margin", 4))
	var gap: int = int(p.get("gap", 3))
	if lvl.cols - margin * 2 < w or lvl.rows - margin * 2 < h:
		return false
	var r := Rect2i(
		rng.randi_range(margin, lvl.cols - margin - w),
		rng.randi_range(margin, lvl.rows - margin - h),
		w, h
	)
	if r.intersects(basin):
		return false
	var band := r.grow(gap)
	var x0: int = maxi(0, band.position.x)
	var y0: int = maxi(0, band.position.y)
	var x1: int = mini(lvl.cols, band.position.x + band.size.x)
	var y1: int = mini(lvl.rows, band.position.y + band.size.y)
	for yy in range(y0, y1):
		for xx in range(x0, x1):
			if lvl.solid[yy * lvl.cols + xx] == 1:
				return false
	_fill_rect(lvl, r)
	return true


## Long partial dividers with wide ends: funnels without chokepoints.
static func _stamp_lanes(lvl: Level, rng: RandomNumberGenerator, p: Dictionary) -> void:
	var placed: Array = []
	var count := rng.randi_range(3, 4)
	for _i in range(count):
		var horizontal := rng.randf() < 0.5
		var r: Rect2i
		if horizontal:
			var len := rng.randi_range(int(lvl.cols * 0.35), int(lvl.cols * 0.6))
			var thick := _scaled(p, rng, 2, 3)
			r = Rect2i(rng.randi_range(0, lvl.cols - len), rng.randi_range(0, lvl.rows - thick), len, thick)
		else:
			var len2 := rng.randi_range(int(lvl.rows * 0.35), int(lvl.rows * 0.6))
			var thick2 := _scaled(p, rng, 2, 3)
			r = Rect2i(rng.randi_range(0, lvl.cols - thick2), rng.randi_range(0, lvl.rows - len2), thick2, len2)
		_try_place_rect(lvl, r, placed, p)


## Four big blocks in the quadrants plus a centre landmark: a wide cross of
## lanes through the middle, which is where a Firewall wants to stand.
static func _stamp_quadrants(lvl: Level, rng: RandomNumberGenerator, p: Dictionary) -> void:
	var placed: Array = []
	var anchors := [
		Vector2i(lvl.cols / 4, lvl.rows / 4),
		Vector2i(3 * lvl.cols / 4, lvl.rows / 4),
		Vector2i(lvl.cols / 4, 3 * lvl.rows / 4),
		Vector2i(3 * lvl.cols / 4, 3 * lvl.rows / 4),
	]
	for a in anchors:
		var w := _scaled(p, rng, 8, 12)
		var h := _scaled(p, rng, 8, 12)
		var pos: Vector2i = a - Vector2i(w / 2, h / 2) + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
		if not _try_place_rect(lvl, Rect2i(pos, Vector2i(w, h)), placed, p):
			var fw := _scaled(p, rng, 4, 6)
			_try_place_rect(lvl, Rect2i(pos, Vector2i(fw, fw)), placed, p)
	var cw := _scaled(p, rng, 4, 6)
	var ch := _scaled(p, rng, 4, 6)
	var c := Vector2i(lvl.cols / 2, lvl.rows / 2)
	_try_place_rect(lvl, Rect2i(c - Vector2i(cw / 2, ch / 2), Vector2i(cw, ch)), placed, p)


## Loose ring of blocks: a landmark band to fight around, with an open basin in
## the middle and open space outside it.
static func _stamp_ring(lvl: Level, rng: RandomNumberGenerator, p: Dictionary) -> void:
	var placed: Array = []
	var cx := lvl.cols / 2
	var cy := lvl.rows / 2
	var base_r := float(mini(lvl.cols, lvl.rows)) * 0.30
	var count := rng.randi_range(7, 10)
	for i in range(count):
		var ang := TAU * float(i) / float(count) + rng.randf_range(-0.2, 0.2)
		var rr := base_r + rng.randf_range(-2.0, 2.0)
		var w := _scaled(p, rng, 3, 6)
		var h := _scaled(p, rng, 3, 6)
		var px := int(round(float(cx) + cos(ang) * rr)) - w / 2
		var py := int(round(float(cy) + sin(ang) * rr)) - h / 2
		_try_place_rect(lvl, Rect2i(px, py, w, h), placed, p)


## Default: a few medium blocks scattered with breathing room.
static func _stamp_scatter(lvl: Level, rng: RandomNumberGenerator, p: Dictionary) -> void:
	var placed: Array = []
	var count := rng.randi_range(8, 12)
	for _i in range(count):
		var w := _scaled(p, rng, 5, 8)
		var h := _scaled(p, rng, 5, 8)
		_random_block(lvl, rng, p, placed, w, h)


## Tries one free block of the given size. Returns false when it found no legal
## spot (so an archetype can silently place fewer blocks rather than overlap).
static func _random_block(lvl: Level, rng: RandomNumberGenerator, p: Dictionary, placed: Array, w: int, h: int) -> bool:
	return _try_place_rect(lvl, Rect2i(0, 0, w, h), placed, p, true, rng)


## Places `r`, respecting the border margin and the inter-obstacle gap. When
## `randomize_position` is true the position is rolled from the RNG instead.
static func _try_place_rect(lvl: Level, r: Rect2i, placed: Array, p: Dictionary, randomize_position: bool = false, rng: RandomNumberGenerator = null) -> bool:
	var margin: int = int(p.get("margin", 4))
	var gap: int = int(p.get("gap", 3))
	if randomize_position:
		if lvl.cols - margin * 2 < r.size.x or lvl.rows - margin * 2 < r.size.y:
			return false
		r.position = Vector2i(
			rng.randi_range(margin, lvl.cols - margin - r.size.x),
			rng.randi_range(margin, lvl.rows - margin - r.size.y)
		)
	if r.position.x < margin or r.position.y < margin:
		return false
	if r.position.x + r.size.x > lvl.cols - margin or r.position.y + r.size.y > lvl.rows - margin:
		return false
	for pr in placed:
		var prect: Rect2i = pr
		if r.grow(gap).intersects(prect):
			return false
	_fill_rect(lvl, r)
	placed.append(r)
	return true


static func _fill_rect(lvl: Level, r: Rect2i) -> void:
	for yy in range(r.position.y, r.position.y + r.size.y):
		for xx in range(r.position.x, r.position.x + r.size.x):
			if xx >= 0 and xx < lvl.cols and yy >= 0 and yy < lvl.rows:
				lvl.solid[yy * lvl.cols + xx] = 1


static func _clear_rect(lvl: Level, r: Rect2i) -> void:
	for yy in range(r.position.y, r.position.y + r.size.y):
		for xx in range(r.position.x, r.position.x + r.size.x):
			if xx > 0 and xx < lvl.cols - 1 and yy > 0 and yy < lvl.rows - 1:
				lvl.solid[yy * lvl.cols + xx] = 0


# ---------------------------------------------------------------------------
# Grid features
# ---------------------------------------------------------------------------

## Manhattan distance from every cell to the nearest solid cell.
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

## A central clearing the colony can start in.
static func _pick_spawn(lvl: Level, dist_wall: PackedInt32Array, rng: RandomNumberGenerator, p: Dictionary) -> Vector2i:
	var center := Vector2(lvl.cols - 1, lvl.rows - 1) * 0.5
	var need: int = maxi(1, int(p["spawn_clear"]))
	var best_score := INF
	var best := Vector2i(lvl.cols / 2, lvl.rows / 2)
	for y in range(1, lvl.rows - 1):
		for x in range(1, lvl.cols - 1):
			var i: int = y * lvl.cols + x
			if lvl.solid[i] == 1 or dist_wall[i] < need:
				continue
			var score: float = Vector2(x, y).distance_to(center) + rng.randf() * 3.0
			if score < best_score:
				best_score = score
				best = Vector2i(x, y)
	if best_score == INF:
		for y in range(1, lvl.rows - 1):
			for x in range(1, lvl.cols - 1):
				if lvl.solid[y * lvl.cols + x] == 0:
					var s := Vector2(x, y).distance_to(center)
					if s < best_score:
						best_score = s
						best = Vector2i(x, y)
	return best


## Food at spread distances from the nest, never in a wall and never bunched.
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
	if count <= 0:
		return []
	if count == 1:
		return [0.6]
	if count == 2:
		return [0.4, 0.75]
	if count == 3:
		return [0.35, 0.6, 0.85]
	var out: Array = []
	for i in range(count):
		out.append(0.25 + 0.6 * float(i) / float(count - 1))
	return out


## Places every enemy with intent instead of sprinkling them on a clean ring:
## control types (Assassin, Firewall) are posted at the arena's doorways so they
## hold a route; Predators start close (they close fast); the landmark types
## (Siren, Broodmother) sit on open ground. Most posts are chosen to have no line
## of sight to the nest, so enemies start behind cover and ambush an exploring
## player. The budget can field more instances than were hand-picked.
static func _place_enemies(lvl: Level, reach: Dictionary, dist_wall: PackedInt32Array, rng: RandomNumberGenerator, p: Dictionary, combo: Array, target: int = -1) -> void:
	if combo.is_empty():
		return
	var reach_dist: PackedInt32Array = reach["dist"]
	var order: Array = []
	for c in combo:
		order.append(int(c))
	order.sort()
	if target < 0:
		target = order.size()
	target = maxi(target, order.size())

	# Fill the threat budget by cycling the chosen types, so any extra pressure is
	# still made of enemies the player actually selected.
	var plan: Array = []
	for i in range(target):
		plan.append(order[i % order.size()])

	var half := Vector2(float(lvl.cols), float(lvl.rows)) * 0.5
	var ring_scale := minf(half.x, half.y)
	var base_angle := rng.randf() * TAU
	var placed: Array = []
	var food_cells: Array = []
	for f in lvl.food:
		food_cells.append(f["cell"])
	var doors := _door_cells(lvl, dist_wall, reach_dist, lvl.spawn_cell)

	var n := plan.size()
	for k in range(n):
		var type: int = plan[k]
		var role := _placement_role(type)
		var desired: Vector2i
		if role == "door" and not doors.is_empty():
			desired = _pick_door(lvl, doors, placed, lvl.spawn_cell)
		else:
			var ang := base_angle + TAU * float(k) / float(n) + rng.randf_range(-0.15, 0.15)
			var lo := float(p["enemy_ring_min"]) * _ring_type_scale(type)
			var hi := float(p["enemy_ring_max"]) * _ring_type_scale(type)
			if role == "close":
				lo = minf(lo, 0.15)
				hi = minf(hi, 0.32)
			var rfrac := clampf(rng.randf_range(lo, hi), 0.12, 0.72)
			desired = Vector2i(
				int(round(float(lvl.spawn_cell.x) + cos(ang) * rfrac * ring_scale)),
				int(round(float(lvl.spawn_cell.y) + sin(ang) * rfrac * ring_scale))
			)
		# Control and landmark posts hide behind cover; a Predator charges in the
		# open, so it does not ask for a hidden post.
		var prefer_hidden: bool = role != "close"
		var cell := _find_enemy_cell(lvl, desired, reach_dist, dist_wall, placed, type, rng, p, food_cells, prefer_hidden)
		if cell.x >= 0:
			placed.append(cell)
			lvl.enemies.append({"type": type, "cell": cell})


## Which tactical role a type plays in placement.
static func _placement_role(type: int) -> String:
	match type:
		Enemy.Type.ASSASSIN, Enemy.Type.FIREWALL:
			return "door"      # holds a doorway / route
		Enemy.Type.PREDATOR:
			return "close"     # spawns near and closes fast, out in the open
	return "landmark"          # Siren / Broodmother / others: open ground


static func _ring_type_scale(type: int) -> float:
	match type:
		Enemy.Type.ASSASSIN:
			return 1.25  # wants room to circle and strike
		Enemy.Type.PREDATOR:
			return 0.75  # closes in fast
		Enemy.Type.SIREN:
			return 1.1
		Enemy.Type.FIREWALL:
			return 0.95
	return 1.0


## Nearest open, reachable cell to `desired` that satisfies the type's clearance
## and the pack separation, preferring a post hidden from the nest when asked.
## Relaxes clearance and separation on later passes so a cell always lands.
static func _find_enemy_cell(lvl: Level, desired: Vector2i, reach_dist: PackedInt32Array, dist_wall: PackedInt32Array, placed: Array, type: int, rng: RandomNumberGenerator, p: Dictionary, food_cells: Array, prefer_hidden: bool = false) -> Vector2i:
	var clear: int = int(p["enemy_clear"])
	match type:
		Enemy.Type.ASSASSIN, Enemy.Type.SIREN:
			clear = 3
	var sep: int = int(p["enemy_min_sep"])
	var band: float = float(p.get("ambush_band", 6.0))
	for relax in range(3):
		var need_clear: int = maxi(1, clear - relax)
		var need_sep: int = maxi(3, sep - relax * 3)
		var best := Vector2i(-1, -1)
		var best_score := INF
		for y in range(1, lvl.rows - 1):
			for x in range(1, lvl.cols - 1):
				var i: int = y * lvl.cols + x
				if lvl.solid[i] == 1 or reach_dist[i] < 0 or dist_wall[i] < need_clear:
					continue
				if _too_close(Vector2i(x, y), placed, need_sep):
					continue
				var score := _enemy_score(lvl, Vector2i(x, y), desired, dist_wall, p, type, food_cells)
				if score < best_score:
					best_score = score
					best = Vector2i(x, y)
		if best.x < 0:
			continue
		if prefer_hidden:
			# Second pass, bounded to the near-best band, looking for a post that
			# is not visible from the nest (behind cover) so it can ambush.
			var hid := Vector2i(-1, -1)
			var hid_score := INF
			for y in range(1, lvl.rows - 1):
				for x in range(1, lvl.cols - 1):
					var i: int = y * lvl.cols + x
					if lvl.solid[i] == 1 or reach_dist[i] < 0 or dist_wall[i] < need_clear:
						continue
					if _too_close(Vector2i(x, y), placed, need_sep):
						continue
					var score := _enemy_score(lvl, Vector2i(x, y), desired, dist_wall, p, type, food_cells)
					if score <= best_score + band and score < hid_score and not _has_los(lvl, Vector2i(x, y), lvl.spawn_cell):
						hid_score = score
						hid = Vector2i(x, y)
			if hid.x >= 0:
				return hid
		return best
	return Vector2i(-1, -1)


## Placement score for a candidate cell: closeness to the desired post, nudged by
## type (Broodmother slightly toward food routes, Siren/Firewall toward open
## landmarks). Food is not a placement rule of its own — this is only a nudge.
static func _enemy_score(lvl: Level, cell: Vector2i, desired: Vector2i, dist_wall: PackedInt32Array, p: Dictionary, type: int, food_cells: Array) -> float:
	var score := Vector2(cell).distance_to(Vector2(desired))
	if type == Enemy.Type.BROODMOTHER:
		score += float(_nearest_food_dist(cell, food_cells)) * 0.4
	elif type == Enemy.Type.SIREN or type == Enemy.Type.FIREWALL:
		var i: int = cell.y * lvl.cols + cell.x
		score -= float(mini(dist_wall[i], 6)) * 0.6  # wants a big landmark
	return score


## Interior cells that sit in a pinch — few open cells in their 3x3 box and right
## next to a wall — i.e. the doorways between open regions. The nest basin and
## the outer border ring are excluded so a "door" is a real pinch, not the edge.
static func _door_cells(lvl: Level, dist_wall: PackedInt32Array, reach_dist: PackedInt32Array, spawn_cell: Vector2i) -> Array:
	var out: Array = []
	for y in range(2, lvl.rows - 2):
		for x in range(2, lvl.cols - 2):
			var i: int = y * lvl.cols + x
			if lvl.solid[i] == 1 or reach_dist[i] < 0 or dist_wall[i] > 1:
				continue
			var cell := Vector2i(x, y)
			if (cell - spawn_cell).length_squared() < 100:
				continue
			var open_nb: int = 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if lvl.solid[(y + dy) * lvl.cols + (x + dx)] == 0:
						open_nb += 1
			if open_nb <= 6:
				out.append(cell)
	return out


## Picks the door farthest from the nest and from any already-placed enemy, so
## control enemies spread across separate routes. Deterministic.
static func _pick_door(lvl: Level, doors: Array, placed: Array, spawn_cell: Vector2i) -> Vector2i:
	var best: Vector2i = doors[0]
	var best_score := -1.0
	for d in doors:
		var dv := Vector2(d)
		var score := dv.distance_to(Vector2(spawn_cell))
		for c in placed:
			score += minf(dv.distance_to(Vector2(c)), 24.0) * 0.8
		if score > best_score:
			best_score = score
			best = d
	return best


## Bresenham line-of-sight on the grid: true when the straight line between two
## cells crosses no solid cell (the endpoints themselves are not tested).
static func _has_los(lvl: Level, a: Vector2i, b: Vector2i) -> bool:
	var x0: int = a.x
	var y0: int = a.y
	var dx: int = absi(b.x - x0)
	var dy: int = -absi(b.y - y0)
	var sx: int = 1 if x0 < b.x else -1
	var sy: int = 1 if y0 < b.y else -1
	var err: int = dx + dy
	while true:
		if not (x0 == a.x and y0 == a.y):
			if x0 < 0 or x0 >= lvl.cols or y0 < 0 or y0 >= lvl.rows:
				return false
			if lvl.solid[y0 * lvl.cols + x0] == 1:
				return false
		if x0 == b.x and y0 == b.y:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return true


## Open fraction of the whole grid (walls included), measured before enemies are
## placed so the threat budget can see how airy the arena ended up.
static func _openness_frac(lvl: Level) -> float:
	var n: int = lvl.cols * lvl.rows
	var open_count: int = 0
	for i in range(n):
		if lvl.solid[i] == 0:
			open_count += 1
	return float(open_count) / float(maxi(1, n))


## Enemy count the arena should field: the chosen combo is a floor, and a bigger,
## airier arena raises it (so open space is not free). Disabled by threat_scaling.
static func _enemy_target_count(p: Dictionary, cols: int, rows: int, openness: float, combo: Array) -> int:
	var base: int = combo.size()
	if base == 0 or not bool(p.get("threat_scaling", true)):
		return base
	var cell_px: float = float(p.get("cell_size", 10.0))
	var world_area: float = float(cols) * cell_px * float(rows) * cell_px
	var area_factor: float = world_area / float(p["enemy_budget_ref_area"])
	var open_factor: float = openness / maxf(0.01, float(p["enemy_budget_ref_open"]))
	var budget: int = int(round(float(p["enemy_budget_base"]) * area_factor * open_factor))
	return maxi(base, budget)


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
	var spawn_basin: bool = dist_wall[spawn_i] >= int(p["spawn_clear"])

	var food_ok: bool = lvl.food.size() > 0
	for f in lvl.food:
		var c: Vector2i = f["cell"]
		if reach_dist[c.y * lvl.cols + c.x] < 0:
			food_ok = false

	var enemy_target: int = int(p.get("enemy_target", combo.size()))
	var enemy_ok: bool = lvl.enemies.size() == enemy_target
	for e in lvl.enemies:
		var c: Vector2i = e["cell"]
		var i2: int = c.y * lvl.cols + c.x
		if lvl.solid[i2] == 1 or reach_dist[i2] < 0:
			enemy_ok = false

	var valid: bool = (
		reach_frac >= float(p["reach_lo"])
		and openness >= float(p["open_lo"])
		and openness <= float(p["open_hi"])
		and spawn_basin
		and food_ok
		and enemy_ok
	)
	return {
		"valid": valid,
		"archetype": str(p.get("archetype", "scatter")),
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
