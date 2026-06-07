extends Node2D
class_name SwarmController

const AGENT_SCENE := preload("res://swarm_agent.tscn")
const AGENT_COUNT := 28
const AGENT_BASE_ORBIT_RADIUS := 40.0
const STRENGTH_REGEN_PER_SECOND := 4.0
const STRENGTH_CAP_BASE := 100.0
const STRENGTH_CAP_PER_LEVEL := 20.0

signal strength_changed(current: float, cap: float)

enum DirectiveState { ORBIT, CASTING, RECALLING }

@export var player: Node2D

var agents: Array = []
var directive_state: int = DirectiveState.ORBIT
var strength_current: float = STRENGTH_CAP_BASE
var player_level: int = 1

var all_patterns: Array = []
var unlocked_pattern_count: int = 1
var active_pattern_index: int = 0
var active_field: CastField = null

func _ready() -> void:
	_build_patterns()
	for i in range(AGENT_COUNT):
		var agent: SwarmAgent = AGENT_SCENE.instantiate()
		agent.swarm_controller = self
		agent.orbit_anchor = player
		agent.orbit_radius = AGENT_BASE_ORBIT_RADIUS + randf_range(-8.0, 8.0)
		agent.neighbors = agents
		add_child(agent)
		agents.append(agent)
		agent.global_position = player.global_position

func _physics_process(delta: float) -> void:
	var cap := strength_cap()
	if strength_current < cap:
		strength_current = min(strength_current + STRENGTH_REGEN_PER_SECOND * delta, cap)
		strength_changed.emit(strength_current, cap)

func strength_cap() -> float:
	return STRENGTH_CAP_BASE + float(player_level - 1) * STRENGTH_CAP_PER_LEVEL

func deplete_strength(amount: float) -> void:
	strength_current = max(strength_current - amount, 0.0)
	strength_changed.emit(strength_current, strength_cap())

func _build_patterns() -> void:
	all_patterns = [
		CastPattern.new("hunt", "Hunt", CastPattern.Shape.PULSE, 1.0, 1.6),
		CastPattern.new("scatter", "Scatter", CastPattern.Shape.CONE, 0.7, 1.0, 0.9),
		CastPattern.new("loop_hunt", "Loop Hunt", CastPattern.Shape.TANGENTIAL, 1.0, 1.1, 0.6, 1.0),
	]

func active_pattern() -> CastPattern:
	return all_patterns[active_pattern_index]

func cast(direction: Vector2, target: Node2D = null) -> void:
	var pattern := active_pattern()
	var field := CastField.new()
	field.pattern = pattern
	field.direction = direction.normalized()
	field.anchor = target.global_position if target != null else player.global_position + direction.normalized() * 220.0
	# Add as a sibling of Player (child of Game), NOT a child of SwarmController/Player —
	# otherwise the field would be parented to a moving node and drift along with the
	# player instead of staying anchored at the world point where it was cast.
	player.get_parent().add_child(field)
	field.global_position = player.global_position
	active_field = field
	directive_state = DirectiveState.CASTING
	for agent in agents:
		agent.enter_directed(field, pattern.speed_multiplier)

func recall() -> void:
	directive_state = DirectiveState.ORBIT
	if active_field != null and is_instance_valid(active_field):
		active_field.queue_free()
	active_field = null
	for agent in agents:
		agent.return_to_idle()
