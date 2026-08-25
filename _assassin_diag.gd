extends SceneTree

## Headless verification for the reworked ASSASSIN (Hades-style duelist):
##   CHASE      - closes on the PLAYER (it ignores ants)
##   SWARM-SAFE - zero ant casualties across the whole run
##   RHYTHM     - player hp only ever drops in whole strike_damage steps
##   DODGE      - sidestepping during WINDUP makes the lunge miss
##   FEAR       - the attack flare scatters an ant placed inside it

var ticks := 0
var player: Player
var world: SwarmWorld
var assassin: Enemy

var ants_at_start := 0
var chase0 := 0.0
var chase_min := 9999.0
var chase_ok := false

var swarm_counts: Array = []
var hp_samples: Array = []

var dodge_stage := 0          # 0 idle, 1 waiting for windup, 2 strike pending, 3 done
var dodge_timer := 0
var dodge_hp := 0.0
var dodge_result := ""
var dodge_printed := false

var probe_phase := 0          # 0 not started, 1 running, 2 done
var probe_tick := 0
var probe_ant: SwarmAgent = null
var probe_start := 0.0
var probe_min := 9999.0
var fear_text := "SKIP"

var assassin_dead := false


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
				assassin = child
		if assassin == null:
			print("FAIL: no ASSASSIN-type Enemy found in scene")
			quit(1)
			return true
		return false

	if not is_instance_valid(assassin):
		if not assassin_dead:
			assassin_dead = true
			print("NOTE | assassin died to swarm DOT at tick %d" % ticks)
			if dodge_stage == 1 or dodge_stage == 2:
				dodge_stage = 3
				dodge_result = "SKIP (assassin died)"
			if probe_phase == 1:
				probe_phase = 2
				fear_text = "SKIP (assassin died)"
	elif probe_phase == 1:
		_run_probe()

	if is_instance_valid(assassin) and ticks > 10 and ticks <= 150:
		chase_min = minf(chase_min, assassin.global_position.distance_to(player.global_position))

	# Fixed-time reports
	if ticks == 10:
		ants_at_start = _live_count()
		chase0 = assassin.global_position.distance_to(player.global_position)
		print("t0   | live=%d  dist-to-player=%.1f  hp=%.0f" % [ants_at_start, chase0, player.hp])
	elif ticks == 150:
		chase_ok = chase_min <= 60.0
		print("CHASE| dist-to-player %.1f -> min %.1f (reached strike range: %s)" % [chase0, chase_min, "YES" if chase_ok else "NO"])
		dodge_stage = 1
		dodge_timer = 260
	elif ticks == 320 or ticks == 440 or ticks == 560 or ticks == 660:
		swarm_counts.append(_live_count())
		hp_samples.append([ticks, player.hp])

	# DODGE watch: sidestep the player the instant a windup starts
	if is_instance_valid(assassin) and dodge_stage == 1:
		dodge_timer -= 1
		if assassin.duel_state == Enemy.DuelState.WINDUP:
			player.global_position += Vector2(-assassin.aim_dir.y, assassin.aim_dir.x) * 140.0
			dodge_hp = player.hp
			dodge_stage = 2
			dodge_timer = 120
		elif dodge_timer <= 0:
			dodge_stage = 3
			dodge_result = "SKIP (no windup observed)"
	elif is_instance_valid(assassin) and dodge_stage == 2:
		dodge_timer -= 1
		if assassin.duel_state == Enemy.DuelState.BACKOFF:
			dodge_stage = 3
			var missed := absf(player.hp - dodge_hp) < 0.01
			dodge_result = "MISS confirmed" if missed else "HIT (dodge failed)"
		elif dodge_timer <= 0:
			dodge_stage = 3
			dodge_result = "TIMEOUT"
	if dodge_stage == 3 and not dodge_printed:
		dodge_printed = true
		print("DODGE| %s (hp before=%.0f after=%.0f)" % [dodge_result, dodge_hp, player.hp])
		if is_instance_valid(assassin):
			_start_probe()

	if ticks >= 700:
		_finish()
		return true
	return false


func _start_probe() -> void:
	if absf(assassin.aura_strength) < 0.001:
		probe_phase = 2
		fear_text = "SKIP (aura disabled)"
		print("FEAR | skipped: aura_strength = 0, fear pheromone disabled")
		return
	probe_phase = 1
	probe_tick = 0
	assassin.duel_state = Enemy.DuelState.WINDUP
	assassin.state_timer = 2.0
	assassin.struck_this_strike = true
	var ant := _any_live_ant(true)
	if ant != null:
		var cell := world.world_to_cell(assassin.global_position) + Vector2i(4, 0)
		ant.x = clampi(cell.x, 0, world.cols - 1)
		ant.y = clampi(cell.y, 0, world.rows - 1)
		ant.position = world.cell_to_world(Vector2i(ant.x, ant.y))
		probe_ant = ant
		probe_start = assassin.global_position.distance_to(ant.global_position)
		probe_min = probe_start
		print("FEAR | probe ant placed %.1fpx from flaring assassin; hunt field @ cell = %.3f" % [probe_start, _hunt_at(assassin.global_position)])
	else:
		probe_phase = 2
		fear_text = "SKIP (no forager)"
		print("FEAR | skipped (no forager available)")


func _run_probe() -> void:
	probe_tick += 1
	if probe_ant != null and is_instance_valid(probe_ant):
		probe_min = minf(probe_min, assassin.global_position.distance_to(probe_ant.global_position))
	if probe_tick < 30:
		return
	var end := -1.0
	if probe_ant != null and is_instance_valid(probe_ant):
		end = assassin.global_position.distance_to(probe_ant.global_position)
	var fled := end > probe_start + 5.0
	fear_text = ("fled outward %.1f -> %.1f" % [probe_start, end]) if fled else ("did NOT flee (%.1f -> %.1f)" % [probe_start, end])
	print("FEAR | probe dist %.1f -> %.1f (min %.1f; fled outward: %s)" % [probe_start, end, probe_min, "YES" if fled else "NO"])
	assassin.duel_state = Enemy.DuelState.STALK
	assassin.state_timer = 0.0
	probe_ant = null
	probe_phase = 2


func _finish() -> void:
	swarm_counts.append(_live_count())
	hp_samples.append([ticks, player.hp])

	var safe := true
	for c in swarm_counts:
		if c != ants_at_start:
			safe = false

	var sd: float = 12.0
	if is_instance_valid(assassin):
		sd = assassin.strike_damage
	var rhythmic := true
	var drained := false
	for i in range(1, hp_samples.size()):
		var d := float(hp_samples[i][1]) - float(hp_samples[i - 1][1])
		if d > 0.01:
			rhythmic = false
		elif d < -0.01:
			var k := absf(d) / maxf(sd, 0.001)
			if absf(k - roundf(k)) > 0.1:
				rhythmic = false
			if absf(d) < sd * 0.9:
				drained = true

	print("SUMMARY| CHASE closed-in: %s | SWARM-SAFE (36->%d): %s | RHYTHM stepwise-only: %s (continuous drain: %s) | DODGE: %s | FEAR: %s" % [
		"YES" if chase_ok else "NO",
		swarm_counts.back() if not swarm_counts.is_empty() else -1,
		"YES" if safe else "NO",
		"YES" if rhythmic else "NO",
		"YES" if drained else "NO",
		dodge_result if dodge_printed else "n/a",
		fear_text,
	])
	quit(0)


func _live_count() -> int:
	var n := 0
	for agent in world.ant_manager.agents:
		if is_instance_valid(agent):
			n += 1
	return n


func _any_live_ant(require_forager: bool) -> SwarmAgent:
	for agent in world.ant_manager.agents:
		if not is_instance_valid(agent):
			continue
		if require_forager and agent.carry:
			continue
		return agent
	return null


func _hunt_at(world_pos: Vector2) -> float:
	var cell := world.world_to_cell(world_pos)
	return world.get_field(ScalarFieldManager.FIELD_HUNT_PHER).get_cell(cell.x, cell.y)
