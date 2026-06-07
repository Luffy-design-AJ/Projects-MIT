extends Node2D
class_name SwarmController

const AGENT_SCENE := preload("res://swarm_agent.tscn")
const AGENT_COUNT := 28
const AGENT_BASE_ORBIT_RADIUS := 40.0

enum DirectiveState { ORBIT, CASTING, RECALLING }

@export var player: Node2D

var agents: Array = []
var directive_state: int = DirectiveState.ORBIT

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
