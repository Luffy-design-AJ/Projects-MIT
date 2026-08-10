extends SwarmTarget
class_name PlaceholderEnemy

@export var max_hp: float = 100.0
@export var counter_damage: float = 4.0
@export var counter_damage_interval: float = 1.0

var hp: float

@onready var counter_damage_timer: Timer = $CounterDamageTimer
@onready var hp_label: Label = $HPLabel

func _ready() -> void:
	super._ready()
	hp = max_hp
	_update_label()
	counter_damage_timer.wait_time = counter_damage_interval
	counter_damage_timer.timeout.connect(_on_counter_damage_timeout)
	counter_damage_timer.start()

func take_damage(amount: float) -> void:
	hp = max(hp - amount, 0.0)
	_update_label()
	if hp <= 0.0:
		queue_free()

func _on_counter_damage_timeout() -> void:
	for area in get_overlapping_areas():
		if area.is_in_group("swarm_agents") and area.has_method("take_counter_damage"):
			area.take_counter_damage(counter_damage)

func _update_label() -> void:
	hp_label.text = "HP: %d / %d" % [int(hp), int(max_hp)]
