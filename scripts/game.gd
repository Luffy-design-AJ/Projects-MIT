extends Node2D

@onready var swarm_world: SwarmWorld = get_node_or_null("SwarmWorld") as SwarmWorld
@onready var player: Player = get_node_or_null("Player") as Player
@onready var deliveries_label: Label = get_node_or_null("CanvasLayer/StrengthLabel") as Label
@onready var ants_label: Label = get_node_or_null("CanvasLayer/Label") as Label
@onready var eminate_label: Label = get_node_or_null("CanvasLayer/EminateModeLabel") as Label
@onready var cast_label: Label = get_node_or_null("CanvasLayer/CastLabel") as Label
@onready var nest_label: Label = get_node_or_null("CanvasLayer/NestPheromoneLabel") as Label
@onready var hp_label: Label = get_node_or_null("CanvasLayer/HPLabel") as Label
@onready var bomb_label: Label = get_node_or_null("CanvasLayer/BombModeLabel") as Label
@onready var stage_label: Label = get_node_or_null("CanvasLayer/ProgressStageLabel") as Label
@onready var canvas_layer: CanvasLayer = get_node_or_null("CanvasLayer") as CanvasLayer
@onready var options_panel: OptionsPanel = null
@onready var enemy1: Enemy = get_node_or_null("Enemy1") as Enemy

func _ready() -> void:
	Engine.max_fps = 60
	if swarm_world == null:
		push_warning("Game UI could not find SwarmWorld. Run res://game.tscn as the main scene.")
		return
	swarm_world.deliveries_changed.connect(_on_deliveries_changed)
	_on_deliveries_changed(swarm_world.deliveries)
	if canvas_layer != null:
		options_panel = OptionsPanel.new()
		canvas_layer.add_child(options_panel)
		options_panel.setup(swarm_world)
	var enemy2 = get_node_or_null("Enemy2") as Enemy
	var enemy3 = get_node_or_null("Enemy3") as Enemy
	var enemy4 = get_node_or_null("Enemy4") as Enemy
	if enemy1 != null or enemy2 != null or enemy3 != null or enemy4 != null:
		var cfg = get_node("/root/GameConfig")
		if cfg != null:
			var c = cfg.choice
			if c == cfg.Choice.NONE:
				if enemy1 != null: enemy1.queue_free()
				if enemy2 != null: enemy2.queue_free()
				if enemy3 != null: enemy3.queue_free()
				if enemy4 != null: enemy4.queue_free()
			elif c == cfg.Choice.ASSASSIN:
				if enemy1 != null:
					enemy1.type = Enemy.Type.ASSASSIN
				if enemy2 != null: enemy2.queue_free()
				if enemy3 != null: enemy3.queue_free()
				if enemy4 != null: enemy4.queue_free()

func _process(_delta: float) -> void:
	if ants_label != null and swarm_world != null:
		ants_label.text = "Ants: %d" % swarm_world.ant_manager.agents.size()
	if eminate_label != null and player != null:
		eminate_label.text = "Eminate: %s (E)" % ("LOCKED" if not player.eminate_unlocked else player.eminate_mode_name())
	if cast_label != null and player != null:
		var cast_text := "Direct Hunt"
		if player.is_control_mode:
			cast_text = "Command Swarm"
		elif player.all_hunt_unlocked:
			cast_text = player.hunt_pattern_name()
		elif not player.hunt_unlocked:
			cast_text = "LOCKED"
		cast_label.text = "Cast: %s (V)" % cast_text
	if nest_label != null and player != null:
		nest_label.text = "Nest beacon: %s (N)" % ("LOCKED" if not player.beacon_unlocked else ("ON" if player.nest_pheromone_enabled else "OFF"))
	if hp_label != null and player != null:
		hp_label.text = "HP: %.0f / %.0f" % [player.hp, player.MAX_HP]
	if bomb_label != null and player != null:
		bomb_label.text = "Bomb: %s (H)" % ("LOCKED" if not player.bomb_unlocked else player.bomb_mode_name())
	if stage_label != null and player != null:
		stage_label.text = "Progress: %s" % player.stage_name()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_options"):
		if options_panel != null:
			options_panel.toggle()
		return
	if player == null:
		return
	if event.is_action_pressed("cycle_progress"):
		player.advance_progress()
	elif event.is_action_pressed("cycle_stage_full"):
		player.cycle_stage()

func _on_deliveries_changed(count: int) -> void:
	if deliveries_label != null:
		deliveries_label.text = "Deliveries: %d" % count
