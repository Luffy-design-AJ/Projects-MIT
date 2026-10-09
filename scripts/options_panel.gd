extends Control
class_name OptionsPanel

const PANEL_WIDTH := 400.0
const PANEL_HEIGHT := 660.0
const MARGIN := 10

var _world: SwarmWorld = null
var _rows: Array = []
var _updating: bool = false
var _pause_button: Button = null


func setup(world: SwarmWorld) -> void:
	_world = world
	_build()
	_apply_defaults()


func toggle() -> void:
	visible = not visible


## Handles the pause hotkey here rather than in game.gd: this panel runs
## PROCESS_MODE_ALWAYS, so it still receives input while the tree is paused.
## Anywhere else would let key 2 pause but not resume it.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_pause"):
		_toggle_paused()
		get_viewport().set_input_as_handled()


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	if _pause_button != null:
		_pause_button.text = "Resume" if paused else "Pause"


func _toggle_paused() -> void:
	_set_paused(not get_tree().paused)


func _build() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -PANEL_WIDTH - 12.0
	offset_right = -12.0
	offset_top = 12.0
	offset_bottom = 12.0 + PANEL_HEIGHT
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	visible = false

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", MARGIN)
	margin.add_theme_constant_override("margin_right", MARGIN)
	margin.add_theme_constant_override("margin_top", MARGIN)
	margin.add_theme_constant_override("margin_bottom", MARGIN)
	panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	_header(list)
	_section(list, "Swarm Behaviour")
	_slider(list, "Exploration", _world, &"params_explore", 0.0, 0.30, 0.005)
	_slider(list, "Variability (noise)", _world, &"params_noise", 0.0, 0.30, 0.005)
	_slider(list, "Return noise", _world, &"params_return_noise", 0.0, 0.40, 0.005)
	_slider(list, "Saturation cap", _world, &"params_sat_cap", 0.2, 3.0, 0.05)
	_slider(list, "Saturation penalty", _world, &"params_sat_pen", 0.0, 2.0, 0.05)
	_slider(list, "Home weight", _world, &"params_home_w", 0.0, 6.0, 0.1)
	_slider(list, "Fresh bonus", _world, &"params_fresh_bonus", 0.0, 8.0, 0.1)
	_slider(list, "Trail deposit", _world, &"params_ft_deposit", 0.0, 0.40, 0.005)
	_slider(list, "Trail return weight", _world, &"params_ft_return_w", 0.0, 4.0, 0.05)
	_slider(list, "Forage highway", _world, &"params_forag_hwy_w", 0.0, 3.0, 0.05)

	_section(list, "Nest")
	_slider(list, "Nest radius (cells)", _world, &"nest_radius_cells", 1.0, 12.0, 1.0)
	_slider(list, "Nest emit / sec", _world, &"nest_emit_per_sec", 0.0, 8.0, 0.1)
	_slider(list, "Carrier emit / sec", _world, &"carrier_emit_per_sec", 0.0, 8.0, 0.1)
	_slider(list, "Carrier aura (cells)", _world, &"carrier_aura_radius_cells", 0.0, 16.0, 1.0)

	_section(list, "Eminate")
	_slider(list, "Radius (cells)", _world, &"eminate_radius_cells", 2.0, 32.0, 1.0)
	_slider(list, "Emit / sec", _world, &"eminate_emit_per_sec", 0.0, 4.0, 0.05)

	_section(list, "Cast (pheromone trail)")
	_slider(list, "Strength", _world, &"cast_strength", 0.0, 3.0, 0.05)
	_slider(list, "Reach (cells)", _world, &"cast_reach_cells", 5.0, 80.0, 1.0)
	_slider(list, "Duration (sec)", _world, &"cast_effect_seconds", 0.5, 10.0, 0.1)
	_slider(list, "Arrive hold (cells)", _world, &"arrive_hold_cells", 0.0, 6.0, 1.0)
	_slider(list, "Arrive hold strength", _world, &"arrive_hold_strength", 0.0, 12.0, 0.1)

	_section(list, "Funnel (animation only)")
	_slider(list, "Capture radius (cells)", _world, &"funnel_capture_radius_cells", 0.0, 16.0, 1.0)
	_slider(list, "Scoop time (sec)", _world, &"funnel_seconds", 0.05, 1.5, 0.05)
	_slider(list, "Turns", _world, &"funnel_turns", 0.0, 3.0, 0.1)
	_slider(list, "Travel (cells)", _world, &"funnel_travel_cells", 0.0, 8.0, 0.5)
	_slider(list, "Drop distance (cells)", _world, &"funnel_launch_cells", 0.0, 10.0, 1.0)

	_section(list, "Lock-on Attack")
	_slider(list, "Lock-on time (sec)", null, &"hunt_lockon_seconds", 0.0, 5.0, 0.1)
	_slider(list, "Lock-on radius (cells)", null, &"hunt_lockon_radius_cells", 0.0, 10.0, 0.25)

	_section(list, "Bomb")
	_slider(list, "Radius (cells)", _world, &"bomb_radius_cells", 2.0, 40.0, 1.0)
	_slider(list, "Strength", _world, &"bomb_strength", 0.0, 6.0, 0.05)
	_slider(list, "Attract duration (sec)", _world, &"bomb_attract_duration", 0.0, 15.0, 0.25)
	_slider(list, "Nest suppress (sec)", _world, &"bomb_nest_suppress_seconds", 0.0, 15.0, 0.25)

	_section(list, "Simulation")
	_slider(list, "Ant step rate (sec)", _world, &"step_rate", 0.02, 0.50, 0.005)

	_section(list, "Visualization")
	_toggle(list, "Show pheromones", _world, &"show_pheromone_vis")
	_slider(list, "Intensity", _world, &"vis_intensity", 0.0, 2.0, 0.05)
	_slider(list, "Strength ref", _world, &"vis_strength_ref", 0.05, 2.0, 0.05)
	_slider(list, "Gamma", _world, &"vis_gamma", 0.2, 3.0, 0.05)


func _header(list: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	list.add_child(head)

	var title := Label.new()
	title.text = "Options"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	head.add_child(title)

	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.focus_mode = Control.FOCUS_NONE
	head.add_child(reset)
	reset.pressed.connect(_apply_defaults)

	_pause_button = Button.new()
	_pause_button.text = "Pause"
	_pause_button.focus_mode = Control.FOCUS_NONE
	head.add_child(_pause_button)
	_pause_button.pressed.connect(_toggle_paused)
	
	var menu_button := Button.new()
	menu_button.text = "Back to Menu"
	menu_button.focus_mode = Control.FOCUS_NONE
	head.add_child(menu_button)
	menu_button.pressed.connect(_back_to_menu)

	var hint := Label.new()
	hint.text = "Tab to close  •  2 to pause/resume"
	hint.add_theme_font_size_override("font_size", 12)
	list.add_child(hint)


func _section(list: VBoxContainer, title: String) -> void:
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 6)
	list.add_child(pad)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 17)
	list.add_child(label)
	list.add_child(HSeparator.new())


func _slider(list: VBoxContainer, label_text: String, target: Object, prop: StringName, minv: float, maxv: float, stepv: float) -> void:
	var value: float = _read(target, prop)

	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 0)
	list.add_child(row)

	var head := HBoxContainer.new()
	row.add_child(head)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)

	var value_label := Label.new()
	value_label.text = _fmt(value, stepv)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = minv
	slider.max_value = maxv
	slider.step = stepv
	slider.value = value
	slider.focus_mode = Control.FOCUS_NONE
	slider.custom_minimum_size = Vector2(0, 18)
	row.add_child(slider)

	_rows.append({
		"kind": "slider",
		"target": target,
		"prop": prop,
		"step": stepv,
		"default": value,
		"slider": slider,
		"label": value_label,
	})

	slider.value_changed.connect(func(v: float) -> void:
		if _updating:
			return
		value_label.text = _fmt(v, stepv)
		_write(target, prop, v))


func _toggle(list: VBoxContainer, label_text: String, target: Object, prop: StringName) -> void:
	var value: bool = _read(target, prop)

	var row := HBoxContainer.new()
	list.add_child(row)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var check := CheckButton.new()
	check.button_pressed = value
	check.focus_mode = Control.FOCUS_NONE
	row.add_child(check)

	_rows.append({
		"kind": "toggle",
		"target": target,
		"prop": prop,
		"default": value,
		"check": check,
	})

	check.toggled.connect(func(on: bool) -> void:
		if _updating:
			return
		_write(target, prop, on))


func _read(target: Object, prop: StringName) -> Variant:
	if target != null:
		return target.get(prop)
	var agents := _agents()
	if agents.is_empty():
		return 0.0
	return agents[0].get(prop)


func _write(target: Object, prop: StringName, value: Variant) -> void:
	if target != null:
		target.set(prop, value)
		return
	for agent in _agents():
		agent.set(prop, value)


func _agents() -> Array:
	if _world == null or _world.ant_manager == null:
		return []
	return _world.ant_manager.agents


func _apply_defaults() -> void:
	_updating = true
	for row in _rows:
		var d: Variant = row["default"]
		if row["kind"] == "slider":
			var slider: HSlider = row["slider"]
			slider.value = d
			row["label"].text = _fmt(d, row["step"])
		else:
			var check: CheckButton = row["check"]
			check.button_pressed = d
		_write(row["target"], row["prop"], d)
	_updating = false


func _fmt(v: float, stepv: float) -> String:
	var decimals := 3
	if stepv >= 1.0:
		decimals = 0
	elif stepv >= 0.1:
		decimals = 1
	elif stepv >= 0.01:
		decimals = 2
	return String.num(v, decimals)


func _back_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://main_menu.tscn")
