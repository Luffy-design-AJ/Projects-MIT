extends Control

@onready var option: OptionButton = $VBoxContainer/OptionButton
@onready var start_button: Button = $VBoxContainer/StartButton

func _ready() -> void:
	if start_button != null:
		start_button.pressed.connect(_on_start_pressed)
	if option != null:
		option.clear()
		option.add_item("No Enemy", 0)
		option.add_item("Assassin", 1)
		option.select(0)

func _on_start_pressed() -> void:
	if option != null:
		var id = option.get_selected_id()
		if id == 1:
			get_node("/root/GameConfig").choice = get_node("/root/GameConfig").Choice.ASSASSIN
		else:
			get_node("/root/GameConfig").choice = get_node("/root/GameConfig").Choice.NONE
	get_tree().change_scene_to_file("res://game.tscn")
