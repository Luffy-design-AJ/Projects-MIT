extends SceneTree

## Control-mode direct-command verification (deterministic).
## Arena: world origin center -> cell ~(64,40); x in [-640,640], y in [-400,400].
## Cast patterns are checked structurally (waypoint geometry + target wiring)
## and behaviourally (convergence). Rally / eminate / bomb checked in-arena.

var ticks := 0
var world: SwarmWorld
var player: Player
var enemies: Array = []
var phase := 0
var phase_tick := 0

var multi_ok := false
var loop_ok := false
var bounce_ok := false
var direct_ok := false
var converge_ok := false
var rally_ok := false
var scatter_ok := false
var bomb_attract_ok := false
var bomb_scatter_ok := false

var bomb_attract_cell := Vector2(0.0, 0.0)


func _initialize() -> void:
	var scene: PackedScene = load("res://game.tscn")
	root.add_child(scene.instantiate())


func _physics_process(delta: float) -> bool:
	ticks += 1
	phase_tick += 1
	if ticks > 3200:
		_finish()
		return true
	if world == null and root.get_child_count() > 0:
		var game := root.get_child(0)
		world = game.get_node_or_null("SwarmWorld")
		player = game.get_node_or_null("Player")
		if world == null or player == null:
			return false
		player.set_stage(Player.Stage.CONTROL)
		player.global_position = Vector2(0.0, 0.0)
		player.last_direction = Vector2.RIGHT
		for i in ["Enemy1", "Enemy2", "Enemy3", "Enemy4"]:
			var e: Node2D = game.get_node_or_null(i)
			if e != null:
				e.type = Enemy.Type.PLACEHOLDER
				e.max_hp = 100000.0
				e.hp = 100000.0
				if e.counter_damage_timer != null:
					e.counter_damage_timer.paused = true
				enemies.append(e)
		_scatter_enemies()
		print("setup | enemies=%d swarm=%d arena=%s" % [enemies.size(), _live_count(), world.arena_size])

	match phase:
		0:
			world.command_swarm_pattern(Vector2(300.0, 200.0), Vector2.RIGHT, Player.HuntPattern.MULTI, null)
			multi_ok = _all_have_targets()
			_report("cast MULTI  every ant targeted", "YES" if multi_ok else "NO")
			phase = 1; phase_tick = 0
		1:
			if phase_tick >= 60:
				world.command_swarm_pattern(Vector2(300.0, 200.0), Vector2.RIGHT, Player.HuntPattern.LOOP, enemies[0])
				loop_ok = _all_wp_size(4)
				_report("cast LOOP  waypoint chain == 4", "YES" if loop_ok else "NO")
				phase = 2; phase_tick = 0
		2:
			if phase_tick >= 60:
				world.command_swarm_pattern(Vector2(300.0, 200.0), Vector2.RIGHT, Player.HuntPattern.BOUNCE, enemies[0])
				bounce_ok = _all_wp_size(2)
				_report("cast BOUNCE  waypoint chain == 2", "YES" if bounce_ok else "NO")
				phase = 3; phase_tick = 0
		3:
			if phase_tick >= 60:
				world.command_swarm_pattern(Vector2(300.0, 200.0), Vector2.RIGHT, Player.HuntPattern.DIRECT, enemies[1])
				direct_ok = _all_have_targets() and _all_wp_size(0)
				_report("cast DIRECT  target + no waypoints", "YES" if direct_ok else "NO")
				phase = 4; phase_tick = 0
		4:
			if ticks >= 600:
				# DIRECT convergence at a target the swarm has marched toward only
				# if commanded, far from other enemies.
				var target = enemies[2]
				target.global_position = Vector2(400.0, 250.0)
				world.command_swarm_pattern(Vector2(400.0, 250.0), Vector2.RIGHT, Player.HuntPattern.DIRECT, target)
				phase = 5; phase_tick = 0
		5:
			if phase_tick >= 240:
				var d := float(_av_dist_to_point(Vector2(400.0, 250.0)))
				converge_ok = d < 12.0
				_report("DIRECT  avg-ant->target cell", "%.1f (<=12 %s)" % [d, "YES" if converge_ok else "NO"])
				phase = 6; phase_tick = 0
		6:
			if phase_tick >= 30:
				world.command_rally(player.global_position, true, false)
				phase = 7; phase_tick = 0
		7:
			if phase_tick >= 420:
				var d := float(_av_dist_to_point(player.global_position))
				rally_ok = d < 10.0
				_report("rally ON  avg-ant->player cell", "%.1f (<=10 %s)" % [d, "YES" if rally_ok else "NO"])
				world.command_rally(player.global_position, false, false)
				phase = 8; phase_tick = 0
		8:
			if phase_tick >= 30:
				world.command_eminate(player.global_position, Player.EminateMode.SCATTER, true)
				phase = 9; phase_tick = 0
		9:
			if phase_tick >= 160:
				var d := float(_av_dist_to_point(player.global_position))
				scatter_ok = d >= 14.0
				_report("eminate SCATTER  avg-ant->player", "%.1f (>=14 %s)" % [d, "YES" if scatter_ok else "NO"])
				world.command_eminate(player.global_position, Player.EminateMode.SCATTER, false)
				phase = 10; phase_tick = 0
		10:
			if phase_tick == 10:
				world.command_point_bomb(bomb_attract_cell, Player.BombMode.ATTRACT)
			if phase_tick >= 180:
				var d := float(_av_dist_to_point(bomb_attract_cell))
				bomb_attract_ok = d < 12.0
				_report("bomb ATTRACT  avg-ant->cell", "%.1f (<=12 %s)" % [d, "YES" if bomb_attract_ok else "NO"])
				world.command_point_bomb(Vector2(-400.0, -300.0), Player.BombMode.SCATTER)
				phase = 11; phase_tick = 0
		11:
			if phase_tick >= 160:
				var d := float(_av_dist_to_point(Vector2(-400.0, -300.0)))
				bomb_scatter_ok = d >= 14.0
				_report("bomb SCATTER  avg-ant-from-cell", "%.1f (>=14 %s)" % [d, "YES" if bomb_scatter_ok else "NO"])
				_finish()
				return true

	return false


func _scatter_enemies() -> void:
	enemies[0].global_position = Vector2(-500.0, -300.0)
	enemies[1].global_position = Vector2(500.0, 300.0)
	enemies[2].global_position = Vector2(500.0, -300.0)
	enemies[3].global_position = Vector2(-500.0, 300.0)


func _all_have_targets() -> bool:
	for a in world.ant_manager.agents:
		if is_instance_valid(a) and a.command_target == null:
			return false
	return true


func _all_wp_size(n: int) -> bool:
	if world.ant_manager.agents.is_empty():
		return false
	for a in world.ant_manager.agents:
		if is_instance_valid(a) and a.command_wp.size() != n:
			return false
	return true


func _av_dist_to_point(p: Vector2) -> float:
	var total := 0
	var n := 0
	var cell := world.world_to_cell(p)
	for a in world.ant_manager.agents:
		if is_instance_valid(a):
			total += maxi(absi(a.x - cell.x), absi(a.y - cell.y))
			n += 1
	return float(total) / float(n) if n > 0 else 999.0


func _live_count() -> int:
	var n := 0
	for a in world.ant_manager.agents:
		if is_instance_valid(a):
			n += 1
	return n


func _report(tag: String, val: String) -> void:
	print("CHECK %-34s %s" % [tag, val])


func _finish() -> void:
	print("SUMMARY| multi=%s loop=%s bounce=%s direct=%s converge=%s rally=%s scatter=%s bomb-attr=%s bomb-scat=%s" % [
		"YES" if multi_ok else "NO",
		"YES" if loop_ok else "NO",
		"YES" if bounce_ok else "NO",
		"YES" if direct_ok else "NO",
		"YES" if converge_ok else "NO",
		"YES" if rally_ok else "NO",
		"YES" if scatter_ok else "NO",
		"YES" if bomb_attract_ok else "NO",
		"YES" if bomb_scatter_ok else "NO",
	])
	quit(0)