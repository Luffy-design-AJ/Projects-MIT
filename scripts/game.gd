extends Node2D

@onready var swarm_world: SwarmWorld = get_node_or_null("SwarmWorld") as SwarmWorld
@onready var player: Player = get_node_or_null("Player") as Player
@onready var deliveries_label: Label = get_node_or_null("CanvasLayer/StrengthLabel") as Label
@onready var ants_label: Label = get_node_or_null("CanvasLayer/Label") as Label
@onready var eminate_label: Label = get_node_or_null("CanvasLayer/EminateModeLabel") as Label
@onready var cast_label: Label = get_node_or_null("CanvasLayer/CastLabel") as Label

func _ready() -> void:
	Engine.max_fps = 60
	if swarm_world == null:
		push_warning("Game UI could not find SwarmWorld. Run res://game.tscn as the main scene.")
		return
	swarm_world.deliveries_changed.connect(_on_deliveries_changed)
	_on_deliveries_changed(swarm_world.deliveries)

func _process(_delta: float) -> void:
	if ants_label != null and swarm_world != null:
		ants_label.text = "Ants: %d" % swarm_world.ant_manager.agents.size()
	if eminate_label != null and player != null:
		eminate_label.text = "Eminate: %s (E)" % player.eminate_mode_name()
	if cast_label != null and player != null:
		cast_label.text = "Cast: %s (V)" % player.hunt_pattern_name()

func _on_deliveries_changed(count: int) -> void:
	if deliveries_label != null:
		deliveries_label.text = "Deliveries: %d" % count
