extends Node
class_name AntManager

## Owns the ant instances and advances them at a fixed step rate. All ants
## read the same shared fields; the manager never tells an ant where to go.

const AGENT_SCENE := preload("res://swarm_agent.tscn")

var world: SwarmWorld = null
var agents: Array = []

var _step_accumulator: float = 0.0


func setup(p_world: SwarmWorld, count: int) -> void:
	world = p_world
	for i in range(count):
		var agent: SwarmAgent = AGENT_SCENE.instantiate()
		agent.swarm_world = world
		agent.x = world.nest_cell.x + randi_range(-2, 2)
		agent.y = world.nest_cell.y + randi_range(-2, 2)
		agent.dir = randi_range(0, 7)
		add_child(agent)
		agents.append(agent)


func step(dt: float) -> void:
	if world == null:
		return
	_step_accumulator += dt
	while _step_accumulator >= world.step_rate:
		for agent in agents:
			if is_instance_valid(agent):
				agent.update_step()
		_step_accumulator -= world.step_rate
	agents = agents.filter(func(a): return is_instance_valid(a))


## Called by an ant right before it frees itself. Keeps `agents` (and the HUD
## ant count) live so dead ants don't linger in the simulation.
func remove_agent(agent: Node) -> void:
	agents.erase(agent)
