extends Control

## Main menu. Two modes:
##   Sandbox    - the original hand-authored arena + one enemy choice.
##   Procedural - multi-select enemy combo + seed + cell scale, with a live
##                minimap preview generated *before* the match starts. The
##                preview and the match call the same deterministic generator,
##                so what you see is what you play.

const MODE_SANDBOX := 0
const MODE_PROC_1 := 1
const MODE_PROC_2 := 2

const CELL_SIZES := [10.0, 16.0, 20.0]
const CELL_LABELS := ["10 px (fine)", "16 px", "20 px (coarse)"]
## Procedural 1 = the classic BSP/maze arena. Procedural 2 = the open arena.
## At the sandbox/player zoom (8x) the visible window is ~144x81 px, so the open
## arena is sized to ~2x2 of those frames (4 screens of area): it takes roaming to
## see it all, but the camera stays locked on the player.
const ARENA_1 := Vector2(1280.0, 800.0)
const ARENA_2 := Vector2(1280.0, 800.0)
const MAX_PER_TYPE := 4
const MAX_TOTAL := 10

const ENEMIES := [
	{"name": "Assassin", "type": Enemy.Type.ASSASSIN, "color": Color(0.95, 0.35, 0.35)},
	{"name": "Predator", "type": Enemy.Type.PREDATOR, "color": Color(0.90, 0.50, 0.15)},
	{"name": "Firewall", "type": Enemy.Type.FIREWALL, "color": Color(0.35, 0.75, 0.95)},
	{"name": "Broodmother", "type": Enemy.Type.BROODMOTHER, "color": Color(0.78, 0.45, 0.95)},
	{"name": "Siren", "type": Enemy.Type.SIREN, "color": Color(0.95, 0.82, 0.30)},
]

var _mode_button: OptionButton
var _sandbox_box: VBoxContainer
var _sandbox_option: OptionButton
var _proc_box: VBoxContainer
var _counts: Dictionary = {}
var _count_labels: Dictionary = {}
var _combo_label: Label
var _seed_edit: LineEdit
var _cell_button: OptionButton
var _preview: TextureRect
var _stats_label: Label

var _mode: int = MODE_SANDBOX


func _ready() -> void:
	_build_ui()
	_mode_button.select(MODE_SANDBOX)
	_apply_mode()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.10)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	center.add_child(row)

	row.add_child(_build_form())
	row.add_child(_build_preview_panel())


func _build_form() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(300.0, 0.0)

	var title := Label.new()
	title.text = "SWARM SANDBOX"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)

	# Mode
	var mode_row := HBoxContainer.new()
	box.add_child(mode_row)
	var mode_label := Label.new()
	mode_label.text = "Mode"
	mode_label.custom_minimum_size = Vector2(84.0, 0.0)
	mode_row.add_child(mode_label)
	_mode_button = OptionButton.new()
	_mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_button.add_item("Sandbox", MODE_SANDBOX)
	_mode_button.add_item("Procedural 1 (maze)", MODE_PROC_1)
	_mode_button.add_item("Procedural 2 (open)", MODE_PROC_2)
	_mode_button.item_selected.connect(_on_mode_selected)
	mode_row.add_child(_mode_button)

	# Sandbox enemy picker
	_sandbox_box = VBoxContainer.new()
	_sandbox_box.add_theme_constant_override("separation", 8)
	box.add_child(_sandbox_box)
	var s_label := Label.new()
	s_label.text = "Enemy"
	_sandbox_box.add_child(s_label)
	_sandbox_option = OptionButton.new()
	_sandbox_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sandbox_option.add_item("No Enemy", 0)
	_sandbox_option.add_item("Assassin", 1)
	_sandbox_option.add_item("Predator", 2)
	_sandbox_option.add_item("Firewall", 3)
	_sandbox_option.add_item("Broodmother", 4)
	_sandbox_option.add_item("Siren", 5)
	_sandbox_option.select(0)
	_sandbox_box.add_child(_sandbox_option)

	# Procedural controls
	_proc_box = VBoxContainer.new()
	_proc_box.add_theme_constant_override("separation", 8)
	box.add_child(_proc_box)

	var e_label := Label.new()
	e_label.text = "Enemies (combo drives the layout)"
	_proc_box.add_child(e_label)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	_proc_box.add_child(grid)
	for entry in ENEMIES:
		var t: int = entry["type"]
		_counts[t] = 0

		var name_label := Label.new()
		name_label.text = entry["name"]
		name_label.custom_minimum_size = Vector2(120.0, 0.0)
		grid.add_child(name_label)

		var minus := Button.new()
		minus.text = "-"
		minus.custom_minimum_size = Vector2(34.0, 0.0)
		minus.pressed.connect(_on_count_changed.bind(t, -1))
		grid.add_child(minus)

		var count_label := Label.new()
		count_label.text = "0"
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_label.custom_minimum_size = Vector2(26.0, 0.0)
		grid.add_child(count_label)
		_count_labels[t] = count_label

		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(34.0, 0.0)
		plus.pressed.connect(_on_count_changed.bind(t, 1))
		grid.add_child(plus)

	var cap := Label.new()
	cap.text = "Pick max %d per enemy, %d total. Bigger / more open arenas field extra." % [MAX_PER_TYPE, MAX_TOTAL]
	cap.add_theme_color_override("font_color", Color(0.65, 0.68, 0.74))
	_proc_box.add_child(cap)

	_combo_label = Label.new()
	_combo_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	_combo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_proc_box.add_child(_combo_label)

	# Seed
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	_proc_box.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_label.custom_minimum_size = Vector2(84.0, 0.0)
	seed_row.add_child(seed_label)
	_seed_edit = LineEdit.new()
	_seed_edit.text = "1337"
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.text_submitted.connect(func(_t): _refresh_preview())
	_seed_edit.focus_exited.connect(_refresh_preview)
	seed_row.add_child(_seed_edit)
	var random_button := Button.new()
	random_button.text = "Random"
	random_button.pressed.connect(_on_random_seed)
	seed_row.add_child(random_button)

	# Cell scale
	var cell_row := HBoxContainer.new()
	cell_row.add_theme_constant_override("separation", 8)
	_proc_box.add_child(cell_row)
	var cell_label := Label.new()
	cell_label.text = "Cell scale"
	cell_label.custom_minimum_size = Vector2(84.0, 0.0)
	cell_row.add_child(cell_label)
	_cell_button = OptionButton.new()
	_cell_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(CELL_SIZES.size()):
		_cell_button.add_item(CELL_LABELS[i], i)
	_cell_button.select(0)
	_cell_button.item_selected.connect(func(_i): _refresh_preview())
	cell_row.add_child(_cell_button)

	var regen := Button.new()
	regen.text = "Generate / Regenerate"
	regen.pressed.connect(_refresh_preview)
	_proc_box.add_child(regen)

	box.add_child(_spacer(8))

	var start_button := Button.new()
	start_button.text = "Start Game"
	start_button.add_theme_font_size_override("font_size", 18)
	start_button.pressed.connect(_on_start_pressed)
	box.add_child(start_button)

	return box


func _build_preview_panel() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = "Layout preview"
	box.add_child(label)

	var panel := PanelContainer.new()
	box.add_child(panel)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(440.0, 300.0)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	panel.add_child(_preview)

	_stats_label = Label.new()
	_stats_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	box.add_child(_stats_label)

	return box


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, height)
	return c


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

func _apply_mode() -> void:
	var procedural: bool = _mode != MODE_SANDBOX
	_sandbox_box.visible = not procedural
	_proc_box.visible = procedural
	_refresh_preview()


func _on_mode_selected(index: int) -> void:
	_mode = index
	_apply_mode()


func _on_count_changed(type: int, delta: int) -> void:
	var current := int(_counts.get(type, 0))
	var next := current + delta
	if next < 0 or next > MAX_PER_TYPE:
		return
	if delta > 0 and _total_count() >= MAX_TOTAL:
		return
	_counts[type] = next
	_count_labels[type].text = str(next)
	_refresh_preview()


func _total_count() -> int:
	var total := 0
	for t in _counts.keys():
		total += int(_counts[t])
	return total


func _on_random_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_seed_edit.text = str(rng.randi_range(1, 999999))
	_refresh_preview()


func _selected_types() -> Array:
	var out: Array = []
	for entry in ENEMIES:
		var t: int = entry["type"]
		for _i in range(int(_counts.get(t, 0))):
			out.append(t)
	return out


func _enemy_name(type: int) -> String:
	for entry in ENEMIES:
		if int(entry["type"]) == type:
			return entry["name"]
	return "?"


func _enemy_color(type: int) -> Color:
	for entry in ENEMIES:
		if int(entry["type"]) == type:
			return entry["color"]
	return Color(1.0, 0.2, 0.2)


func _refresh_preview() -> void:
	if _mode == MODE_SANDBOX:
		return
	var combo := _selected_types()
	var parts: Array = []
	var total := 0
	for entry in ENEMIES:
		var c := int(_counts.get(int(entry["type"]), 0))
		if c > 0:
			parts.append("%s x%d" % [entry["name"], c])
			total += c
	if parts.is_empty():
		_combo_label.text = "Combo: (none) — empty arena, no enemies"
	else:
		_combo_label.text = "Combo: %s  (%d total)" % [" + ".join(parts), total]

	var cell: float = CELL_SIZES[_cell_button.selected]
	var arena := _arena()
	var cols: int = maxi(1, int(arena.x / cell))
	var rows: int = maxi(1, int(arena.y / cell))
	var seed_value := LevelGenerator2.parse_seed(_seed_edit.text)
	var level = _generate(cols, rows, seed_value, combo, cell)

	_preview.texture = _make_preview_texture(level)
	var stats: Dictionary = level.stats
	_stats_label.text = "seed %d  |  %dx%d cells  |  open %.0f%%  |  enemies %d" % [
		seed_value, cols, rows, float(stats.get("openness", 0.0)) * 100.0, level.enemies.size(),
	]


## The arena for the selected mode (Procedural 1 vs 2).
func _arena() -> Vector2:
	return ARENA_1 if _mode == MODE_PROC_1 else ARENA_2


## Runs the generator that matches the selected mode.
func _generate(cols: int, rows: int, seed_value: int, combo: Array, cell: float = 10.0):
	if _mode == MODE_PROC_1:
		return LevelGenerator1.generate(cols, rows, seed_value, combo, {})
	return LevelGenerator2.generate(cols, rows, seed_value, combo, {"cell_size": cell})


func _make_preview_texture(level) -> ImageTexture:
	var img := Image.create(level.cols, level.rows, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.10, 0.11, 0.15))
	var floor_col := Color(0.22, 0.24, 0.30)
	for y in range(level.rows):
		for x in range(level.cols):
			if level.solid[y * level.cols + x] == 0:
				img.set_pixel(x, y, floor_col)
	for f in level.food:
		_paint(img, f["cell"], 3, Color(0.95, 0.72, 0.25))
	_paint(img, level.spawn_cell, 3, Color(0.35, 1.0, 0.55))
	for e in level.enemies:
		_paint(img, e["cell"], 3, _enemy_color(int(e["type"])))
	return ImageTexture.create_from_image(img)


func _paint(img: Image, cell: Vector2i, radius: int, color: Color) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x: int = cell.x + dx
			var y: int = cell.y + dy
			if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
				img.set_pixel(x, y, color)


func _on_start_pressed() -> void:
	var cfg = get_node("/root/GameConfig")
	if cfg == null:
		return
	if _mode != MODE_SANDBOX:
		cfg.mode = cfg.Mode.PROCEDURAL_1 if _mode == MODE_PROC_1 else cfg.Mode.PROCEDURAL_2
		cfg.enemies = _selected_types()
		cfg.level_seed = LevelGenerator2.parse_seed(_seed_edit.text)
		cfg.cell_size = CELL_SIZES[_cell_button.selected]
		cfg.arena_size = _arena()
		cfg.gen_params = {}
	else:
		cfg.mode = cfg.Mode.SANDBOX
		cfg.choice = _sandbox_choice(cfg)
	get_tree().change_scene_to_file("res://game.tscn")


func _sandbox_choice(cfg) -> int:
	match _sandbox_option.get_selected_id():
		1:
			return cfg.Choice.ASSASSIN
		2:
			return cfg.Choice.PREDATOR
		3:
			return cfg.Choice.FIREWALL
		4:
			return cfg.Choice.BROODMOTHER
		5:
			return cfg.Choice.SIREN
		_:
			return cfg.Choice.NONE
