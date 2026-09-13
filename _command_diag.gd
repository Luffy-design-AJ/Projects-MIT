extends SceneTree

## Headless verification for the two direct-command stages:
##   CONTROL  - a cast issues a persistent direct order; ants steer straight at
##              the enemy (no pheromone) and the order persists until it dies.
##   CARNAGE  - no casts needed: every ant autonomously targets the nearest
##              enemy and attacks until it dies, then re-targets.

var ticks := 0
var world: SwarmWorld
var player: Player
var phase := 0
var enemy: Enemy

var control_go := Vector2i.ZERO
var control_ok := false
var carnage_damage_before := 0.0
var carnage_hit := false
var carnage_reached := false
var carnage_released := false


func _initialize() -> void:
	var scene: PackedScene = load("res://game.tscn")
	root.add_child(scene.instantiate())


func _physics_process(delta: float) -> bool:
	ticks += 1
	if world == null:
		world = root.get_child(0).get_node_or_null("SwarmWorld")
		player = root.get_child(0).get_node_or_null("Player")
		if world == null or player == null:
			return false
		# Use Enemy1 (assassin) as the moving attack target; it is a SwarmTarget.
		for child in root.get_child(0).get_children():
			if child is Enemy and child.type == Enemy.Type.ASSASSIN:
				enemy = child
		if enemy == null:
			print("FAIL: no ASSASSIN enemy")
			quit(1)
			return true
		return false

	match phase:
		0:
			player.set_stage(Player.Stage.CONTROL)
			print("t%d | stage=%s | input_locked=%s | ants=%d" % [
				ticks, player.stage_name(), player.input_locked, _live_count()])
			phase = 1
		1:
			if ticks == 20:
				control_go = world.world_to_cell(enemy.global_position)
				var mid := _avg_ant_cell()
				var d0 := float(_cell_dist(mid, control_go))
				player._resolve_and_cast()
				print("t%d | CONTROL cast | avg-ant-to-enemy-cfg start=%.1f cells (cnt each run varies)" % [ticks, d0])
				phase = 2
		2:
			if ticks == 220:
				# After ~200 physics ticks the swarm should have converged around
				# the enemy (persistent order, straight steering, no pheromone).
				var mid := _avg_ant_cell()
				var cur_enemy := world.world_to_cell(enemy.global_position) if is_instance_valid(enemy) else control_go
				var d := float(_cell_dist(mid, cur_enemy))
				var assembled := d < 40.0
				print("t%d | CONTROL avg-ant dist to enemy = %.1f cells (assembled: %s)" % [
					ticks, d, "YES" if assembled else "NO"])
				control_ok = assembled
				# Empty the swarm's command so it does not leak into CARNAGE test
				# (clear via stage switch below).
				player.set_stage(Player.Stage.CARNAGE)
				print("t%d | -> CARNAGE | input_locked=%s" % [ticks, player.input_locked])
				if is_instance_valid(enemy):
					enemy.max_hp = 100.0
					enemy.hp = 100.0
					carnage_damage_before = enemy.hp
				phase = 3
		3:
			if ticks == 320:
				# Without any cast the ants should have closed on and started
				# damaging the nearest enemy on their own.
				var mid := _avg_ant_cell()
				var cur_enemy := world.world_to_cell(enemy.global_position) if is_instance_valid(enemy) else control_go
				var d := float(_cell_dist(mid, cur_enemy))
				carnage_reached = d < 40.0
				if is_instance_valid(enemy):
					carnage_hit = enemy.hp < carnage_damage_before
				print("t%d | CARNAGE avg-ant dist=%.1f (converged: %s) | enemy hp %.0f->%.0f (damaged: %s)" % [
					ticks, d,
					"YES" if carnage_reached else "NO",
					carnage_damage_before,
					enemy.hp if is_instance_valid(enemy) else -1.0,
					"YES" if carnage_hit else "NO"])
				phase = 4
		4:
			if is_instance_valid(enemy):
				pass
			if ticks == 1000 and not is_instance_valid(enemy):
				carnage_released = true
				print("t%d | CARNAGE enemy killed (attack persisted until death: YES)" % ticks)
			if ticks == 1100:
				if not carnage_released and not is_instance_valid(enemy):
					carnage_released = true
					print("t1100 | CARNAGE enemy died (persisted until death: YES)")
				_finish()
				return true

	return false


func _finish() -> void:
	var enemy_state := "killed" if not is_instance_valid(enemy) else "alive(%.0f hp)" % enemy.hp
	print("SUMMARY| CONTROL assembled: %s | CARNAGE converged: %s | damage-dealt: %s | persist-until-death: %s (enemy %s)" % [
		"YES" if control_ok else "NO",
		"YES" if carnage_reached else "NO",
		"YES" if carnage_hit else "NO",
		"YES" if carnage_released else "NO",
		enemy_state,
	])
	quit(0)


func _live_count() -> int:
	var n := 0
	for a in world.ant_manager.agents:
		if is_instance_valid(a):
			n += 1
	return n


func _avg_ant_cell() -> Vector2i:
	var cx := 0
	var cy := 0
	var n := 0
	for a in world.ant_manager.agents:
		if is_instance_valid(a):
			cx += a.x
			cy += a.y
			n += 1
	if n == 0:
		return Vector2i.ZERO
	return Vector2i(int(cx / n), int(cy / n))


func _cell_dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))