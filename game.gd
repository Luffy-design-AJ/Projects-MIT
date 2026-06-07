extends Node2D

@onready var strength_label: Label = $CanvasLayer/StrengthLabel

func _ready() -> void:
	var swarm_controller := $Player/SwarmController
	swarm_controller.strength_changed.connect(_on_strength_changed)
	_on_strength_changed(swarm_controller.strength_current, swarm_controller.strength_cap())

func _on_strength_changed(current: float, cap: float) -> void:
	strength_label.text = "Strength: %d / %d" % [int(current), int(cap)]
