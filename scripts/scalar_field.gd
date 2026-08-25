extends RefCounted
class_name ScalarField

## A single shared scalar field on the swarm grid, faithful to the JS
## prototype's Float32Array fields. One instance per environmental quantity;
## every ant reads the same shared field.

const TICKS_PER_SEC := 11.36

const STYLE_BLOB := "blob"
const STYLE_TRAIL := "trail"
const STYLE_NONE := "none"

var cols: int
var rows: int
var data: PackedFloat32Array

var decay_per_sec: float = 0.0
var style: String = STYLE_BLOB
var trail_spread: float = 0.05


func _init(p_cols: int, p_rows: int, p_decay_per_sec: float = 0.0, p_style: String = STYLE_BLOB, p_trail_spread: float = 0.05) -> void:
	cols = p_cols
	rows = p_rows
	decay_per_sec = p_decay_per_sec
	style = p_style
	trail_spread = p_trail_spread
	data.resize(cols * rows)


func idx(x: int, y: int) -> int:
	return y * cols + x


func get_cell(x: int, y: int) -> float:
	x = clampi(x, 0, cols - 1)
	y = clampi(y, 0, rows - 1)
	return data[idx(x, y)]


func set_cell(x: int, y: int, v: float) -> void:
	if x < 0 or x >= cols or y < 0 or y >= rows:
		return
	data[idx(x, y)] = v


func add_cell(x: int, y: int, v: float) -> void:
	if x < 0 or x >= cols or y < 0 or y >= rows:
		return
	data[idx(x, y)] += v


func clear() -> void:
	data.fill(0.0)


## Square brush stamp with Manhattan-distance falloff, mirroring the JS
## `stamp()` helper: v * (1 - d/(r+1)), clamped to `cap`.
func stamp(cx: int, cy: int, r: int, v: float, cap: float) -> void:
	for yy in range(cy - r, cy + r + 1):
		for xx in range(cx - r, cx + r + 1):
			if xx < 0 or xx >= cols or yy < 0 or yy >= rows:
				continue
			var d := absi(xx - cx) + absi(yy - cy)
			if d <= r:
				var i := idx(xx, yy)
				data[i] = minf(data[i] + v * (1.0 - float(d) / float(r + 1)), cap)


## Set-stamp (no falloff, no cap clamp); used by freshness fields.
func set_stamp(cx: int, cy: int, r: int, v: float) -> void:
	for yy in range(cy - r, cy + r + 1):
		for xx in range(cx - r, cx + r + 1):
			if xx < 0 or xx >= cols or yy < 0 or yy >= rows:
				continue
			var d := absi(xx - cx) + absi(yy - cy)
			if d <= r:
				data[idx(xx, yy)] = v


## Set-stamp with radial falloff: exact-set (no accumulation, no cap clamp,
## signed) with v * (1 - d/(r+1)). Negative v lays a repulsive gradient the
## swarm can climb out of; positive attracts toward the centre.
func set_stamp_falloff(cx: int, cy: int, r: int, v: float) -> void:
	for yy in range(cy - r, cy + r + 1):
		for xx in range(cx - r, cx + r + 1):
			if xx < 0 or xx >= cols or yy < 0 or yy >= rows:
				continue
			var d := absi(xx - cx) + absi(yy - cy)
			if d <= r:
				data[idx(xx, yy)] = v * (1.0 - float(d) / float(r + 1))


## One diffusion + decay step, faithfully mirroring the JS prototype:
##  - STYLE_BLOB  (home/hunt): JS `diffuse()` — a cell never drops below 88%
##    of its prior value per tick, so lines/blobs persist as sharp structures.
##  - STYLE_TRAIL (foot trail): JS `diffuseFootTrail()` — near-zero spread.
##  - STYLE_NONE  (freshness): JS `decayPlayerFresh()` — decay only.
## dt-scaled so behaviour is independent of frame rate. Solid cells are emptied.
func step(dt: float, solid: PackedByteArray) -> void:
	var decay := exp(-decay_per_sec * dt)
	if style == STYLE_BLOB:
		_step_blob(dt, solid, decay)
	elif style == STYLE_TRAIL:
		_step_trail(dt, solid, decay)
	else:
		_step_decay_only(dt, decay)


## Extra multiplicative decay (e.g. fading stale home pheromone while the
## carried nest source is on the move). Sticky-nest tuning.
func boost_decay(dt: float, extra_per_sec: float) -> void:
	if extra_per_sec <= 0.0:
		return
	var factor := exp(-extra_per_sec * dt)
	for i in data.size():
		var v: float = data[i]
		if v > 0.0:
			v = v * factor
			data[i] = v if v > 0.001 else 0.0


func _step_blob(dt: float, solid: PackedByteArray, decay: float) -> void:
	var k := minf(TICKS_PER_SEC * dt, 1.0)
	var spread_w := 0.84 * k
	var floor_w := 1.0 - 0.12 * k
	var copy := data.duplicate()
	for y in range(1, rows - 1):
		for x in range(1, cols - 1):
			var i := idx(x, y)
			if solid[i] == 1:
				data[i] = 0.0
				continue
			var avg := (copy[i] * 4.0 + copy[i - 1] + copy[i + 1] + copy[i - cols] + copy[i + cols]) / 8.0
			var inflow := copy[i] * (1.0 - spread_w) + spread_w * avg
			data[i] = maxf(floor_w * copy[i], inflow) * decay


func _step_trail(dt: float, solid: PackedByteArray, decay: float) -> void:
	var k := minf(TICKS_PER_SEC * dt, 1.0)
	var diff_w := trail_spread * k
	var copy := data.duplicate()
	for y in range(1, rows - 1):
		for x in range(1, cols - 1):
			var i := idx(x, y)
			if solid[i] == 1:
				data[i] = 0.0
				continue
			var neighbors := copy[i - 1] + copy[i + 1] + copy[i - cols] + copy[i + cols]
			data[i] = (copy[i] * (1.0 - diff_w) + diff_w * 0.25 * neighbors) * decay


func _step_decay_only(dt: float, decay: float) -> void:
	for i in data.size():
		var v: float = data[i]
		if v > 0.0:
			v = v * decay
			data[i] = v if v > 0.001 else 0.0
