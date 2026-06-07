extends Node2D

@onready var strength_label: Label = $CanvasLayer/StrengthLabel
@onready var cast_label: Label = $CanvasLayer/Label

func _ready() -> void:
	var swarm_controller := $Player/SwarmController
	swarm_controller.strength_changed.connect(_on_strength_changed)
	swarm_controller.pattern_changed.connect(_on_pattern_changed)
	_on_strength_changed(swarm_controller.strength_current, swarm_controller.strength_cap())
	_on_pattern_changed(swarm_controller.active_pattern())

func _on_strength_changed(current: float, cap: float) -> void:
	strength_label.text = "Strength: %d / %d" % [int(current), int(cap)]

func _on_pattern_changed(pattern: CastPattern) -> void:
	cast_label.text = "Current Cast: %s" % pattern.display_name
