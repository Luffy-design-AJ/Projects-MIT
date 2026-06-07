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

func _ready() -> void:
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
