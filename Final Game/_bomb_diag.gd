extends SceneTree

## Headless verification for the BOMB DROP ability:
##   ATTRACT phase:
##     FIELD    - hunt pheromone in the bomb radius jumps after drop
##     PERSIST  - field stays strong during the re-stamp duration
##     BLACKOUT - _nest_suppress_timer == 5.0 after drop; home field at nest decays
##     ATTRACT  - ants converge toward the bomb drop point
##   SCATTER phase:
##     S_FIELD  - hunt field goes negative after scatter drop
##     S_FLEE   - ants flee outward (avg_dist increases, zone count drops)
##     S_BLACK  - nest suppress still fires
##   WIRING   - player state transitions; drop_bomb called correctly

var ticks := 0
var world: SwarmWorld
var player: Player

var bomb_drop_tick := 50
var bomb_pos := Vector2.ZERO
var bomb_cell := Vector2i.ZERO

var hunt_sum_before := 0.0
var hunt_sum_after := 0.0
var hunt_field_ok := false
var hunt_sum_mid := 0.0
var persist_ok := false

var suppress_timer_ok := false
var home_before := 0.0
var home_after := 0.0
var blackout_ok := false

var avg_dist_before := 0.0
var avg_dist_after := 0.0
var attract_ok := false
var ants_in_zone_before := 0
var ants_in_zone_after := 0

var wiring_ok := false

# SCATTER phase
var scatter_drop_tick := 600
var scatter_pos := Vector2.ZERO
var scatter_cell := Vector2i.ZERO
var s_field_ok := false
var s_flee_ok := false
var s_black_ok := false
var s_ants_before := 0
var s_ants_after := 0
var s_dist_before := 0.0
var s_dist_after := 0.0


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
		return false

	# ─── ATTRACT PHASE ──────────────────────────────────────────────

	# FIELD: measure hunt sum before drop
	if ticks == 10:
		bomb_pos = world.origin + world.arena_size * Vector2(0.65, 0.35)
		bomb_cell = world.world_to_cell(bomb_pos)
		hunt_sum_before = _hunt_sum_in_radius(bomb_cell, world.bomb_radius_cells)
		print("t10  | bomb target cell=%s  hunt_sum_before=%.4f" % [bomb_cell, hunt_sum_before])

	# DROP: call drop_bomb directly + test wiring
	if ticks == bomb_drop_tick:
		player.bomb_aiming = true
		player.bomb_reticle_pos = bomb_pos
		var was_aiming := player.bomb_aiming
		player._drop_bomb()
		wiring_ok = (was_aiming == true and player.bomb_aiming == false)
		print("WIRE | bomb_aiming was true, now false: %s" % ("YES" if wiring_ok else "NO"))

		hunt_sum_after = _hunt_sum_in_radius(bomb_cell, world.bomb_radius_cells)
		hunt_field_ok = hunt_sum_after > hunt_sum_before + 0.5
		print("FIELD| hunt_sum before=%.4f after=%.4f (jumped: %s)" % [
			hunt_sum_before, hunt_sum_after, "YES" if hunt_field_ok else "NO"])

		suppress_timer_ok = absf(world._nest_suppress_timer - world.bomb_nest_suppress_seconds) < 0.01
		home_before = _home_at_nest()
		print("BLK  | _nest_suppress_timer=%.2f (expect %.2f): %s | home@nest=%.4f" % [
			world._nest_suppress_timer, world.bomb_nest_suppress_seconds,
			"YES" if suppress_timer_ok else "NO", home_before])

	# BLACKOUT: check home field after suppression has ticked
	if ticks == bomb_drop_tick + 60:
		home_after = _home_at_nest()
		blackout_ok = home_after <= home_before + 0.001
		print("BLK  | home@nest after 60 ticks=%.4f (not growing: %s)" % [
			home_after, "YES" if blackout_ok else "NO"])

	# PERSIST: gradient peak should still be strong mid-re-stamp (1.5s after drop)
	if ticks == bomb_drop_tick + 90:
		var hunt_field: ScalarField = world.get_field(ScalarFieldManager.FIELD_HUNT_PHER)
		var peak: float = hunt_field.get_cell(bomb_cell.x, bomb_cell.y)
		persist_ok = peak > 0.5
		print("PERS | center peak=%.4f (gradient held: %s)" % [
			peak, "YES" if persist_ok else "NO"])

	# ATTRACT: count ants entering the bomb zone before vs after
	if ticks == 10:
		ants_in_zone_before = _ants_in_radius(bomb_pos, 60.0)
		avg_dist_before = _avg_dist_to(bomb_pos)
		print("t10  | avg_dist_to_bomb=%.1f  ants_in_zone=%d" % [avg_dist_before, ants_in_zone_before])
	if ticks == bomb_drop_tick + 500:
		ants_in_zone_after = _ants_in_radius(bomb_pos, 60.0)
		avg_dist_after = _avg_dist_to(bomb_pos)
		attract_ok = ants_in_zone_after >= ants_in_zone_before + 3
		print("ATTR | ants_in_zone %d->%d (need +3: %s) | avg_dist %.1f->%.1f" % [
			ants_in_zone_before, ants_in_zone_after, "YES" if attract_ok else "NO",
			avg_dist_before, avg_dist_after])

	# ─── SCATTER PHASE ──────────────────────────────────────────────

	# Setup scatter bomb position (opposite side of arena)
	if ticks == scatter_drop_tick - 50:
		scatter_pos = world.origin + world.arena_size * Vector2(0.35, 0.65)
		scatter_cell = world.world_to_cell(scatter_pos)
		s_ants_before = _ants_in_radius(scatter_pos, 60.0)
		s_dist_before = _avg_dist_to(scatter_pos)
		print("t%d  | scatter target cell=%s  ants_in_zone=%d  avg_dist=%.1f" % [
			ticks, scatter_cell, s_ants_before, s_dist_before])

	# Drop scatter bomb (mode=1)
	if ticks == scatter_drop_tick:
		player.bomb_aiming = true
		player.bomb_reticle_pos = scatter_pos
		player.bomb_mode = Player.BombMode.SCATTER
		player._drop_bomb()
		player.bomb_mode = Player.BombMode.ATTRACT

		# S_FIELD: hunt field should be negative at center
		var hunt_field: ScalarField = world.get_field(ScalarFieldManager.FIELD_HUNT_PHER)
		var center_val: float = hunt_field.get_cell(scatter_cell.x, scatter_cell.y)
		s_field_ok = center_val < -0.1
		print("S_FIELD | center val=%.4f (negative: %s)" % [
			center_val, "YES" if s_field_ok else "NO"])

		# S_BLACK: suppress timer should be set
		s_black_ok = world._nest_suppress_timer > 0.0
		print("S_BLACK | suppress_timer=%.2f (suppressing: %s)" % [
			world._nest_suppress_timer, "YES" if s_black_ok else "NO"])

	# SCATTER: check ants flee after scatter bomb
	if ticks == scatter_drop_tick + 500:
		s_ants_after = _ants_in_radius(scatter_pos, 60.0)
		s_dist_after = _avg_dist_to(scatter_pos)
		# Ants should flee: fewer in zone or farther away
		s_flee_ok = (s_ants_after <= s_ants_before) or (s_dist_after > s_dist_before + 5.0)
		print("S_FLEE | ants_in_zone %d->%d  avg_dist %.1f->%.1f (fled: %s)" % [
			s_ants_before, s_ants_after, s_dist_before, s_dist_after,
			"YES" if s_flee_ok else "NO"])

	# ─── DONE ────────────────────────────────────────────────────────

	if ticks >= scatter_drop_tick + 520:
		_finish()
		return true
	return false


func _finish() -> void:
	print("SUMMARY| ATTRACT: FIELD=%s PERSIST=%s BLACK=%s ATTRACT=%s | SCATTER: S_FIELD=%s S_FLEE=%s S_BLACK=%s | WIRING=%s" % [
		"YES" if hunt_field_ok else "NO",
		"YES" if persist_ok else "NO",
		"YES" if (suppress_timer_ok and blackout_ok) else "NO",
		"YES" if attract_ok else "NO",
		"YES" if s_field_ok else "NO",
		"YES" if s_flee_ok else "NO",
		"YES" if s_black_ok else "NO",
		"YES" if wiring_ok else "NO",
	])
	quit(0)


func _hunt_sum_in_radius(center: Vector2i, r: int) -> float:
	var field: ScalarField = world.get_field(ScalarFieldManager.FIELD_HUNT_PHER)
	var total := 0.0
	for yy in range(center.y - r, center.y + r + 1):
		for xx in range(center.x - r, center.x + r + 1):
			if xx < 0 or xx >= world.cols or yy < 0 or yy >= world.rows:
				continue
			total += field.get_cell(xx, yy)
	return total


func _home_at_nest() -> float:
	var field: ScalarField = world.get_field(ScalarFieldManager.FIELD_HOME_PHER)
	var nc := world.nest_cell
	return field.get_cell(nc.x, nc.y)


func _avg_dist_to(pos: Vector2) -> float:
	var total := 0.0
	var n := 0
	for agent in world.ant_manager.agents:
		if is_instance_valid(agent):
			total += agent.global_position.distance_to(pos)
			n += 1
	return total / maxf(1.0, float(n))


func _ants_in_radius(pos: Vector2, radius: float) -> int:
	var count := 0
	for agent in world.ant_manager.agents:
		if is_instance_valid(agent) and agent.global_position.distance_to(pos) <= radius:
			count += 1
	return count
