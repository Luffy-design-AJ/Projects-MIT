extends SceneTree

var ticks := 0
var player: Player
var world: SwarmWorld
var enemy_cell: Vector2i = Vector2i(-1, -1)
var tracked: Array = []

func _initialize() -> void:
	var scene: PackedScene = load("res://game.tscn")
	root.add_child(scene.instantiate())

func _physics_process(_delta: float) -> bool:
	ticks += 1
	if world == null:
		world = root.get_child(0).get_node_or_null("SwarmWorld")
		player = root.get_child(0).get_node_or_null("Player")
		if world == null or player == null:
			return false
		for child in root.get_child(0).get_children():
			if child is Enemy and child.type == Enemy.Type.ASSASSIN:
				child.type = Enemy.Type.PLACEHOLDER
		return false
	if ticks == 40:
		enemy_cell = world.world_to_cell(root.get_child(0).get_node("Enemy2").global_position)
		var dists: Array = []
		for agent in world.ant_manager.agents:
			var d: float = Vector2i(agent.x, agent.y).distance_to(world.world_to_cell(player.global_position))
			dists.append([d, agent])
		dists.sort_custom(func(a, b): return a[0] < b[0])
		for i in range(10):
			tracked.append(dists[i][1])
	if ticks == 60:
		player._resolve_and_cast()
	if ticks == 90 or ticks == 150 or ticks == 240 or ticks == 360:
		_report("t+%.2fs" % (float(ticks - 60) / 60.0))
	if ticks == 400:
		quit(0)
		return true
	return false

func _report(tag: String) -> void:
	var near_enemy := 0
	var on_enemy := 0
	var dist_sum := 0.0
	var alive := 0
	for agent in tracked:
		if not is_instance_valid(agent):
			continue
		alive += 1
		var c: Vector2i = Vector2i(agent.x, agent.y)
		var d: float = c.distance_to(enemy_cell)
		dist_sum += d
		if d <= 6.0:
			near_enemy += 1
		if d <= 2.0:
			on_enemy += 1
	if alive == 0:
		return
	print("%s: 10 tracked ants -> avg dist to enemy = %.2f, near(<=6) = %d, on(<=2) = %d" % [tag, dist_sum / float(alive), near_enemy, on_enemy])
