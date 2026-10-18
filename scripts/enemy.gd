extends SwarmTarget
class_name Enemy

## Generic enemy. Behaviour is driven entirely by `type`; every future enemy
## type lands a new case in `_physics_process` rather than a new class. Like
## the swarm, an enemy never commands an ant directly — it expresses through
## the shared pheromone fields and the swarm reacts via its own scoring.

enum Type { PLACEHOLDER, ASSASSIN, PREDATOR, FIREWALL, BROODMOTHER, SIREN }

## Hades-style duel loop for the ASSASSIN: readable rhythm, dodgeable strikes,
## vulnerable recovery. It ignores the swarm and hunts only the player.
enum DuelState { STALK, WINDUP, STRIKE, BACKOFF, RECOVER }
enum PredState { SEARCH, CHARGE, RECOVER }
enum FirewallState { IDLE, MOVE }
enum SirenState { LURE, WINDUP, SNAP, RECOVER }

@export var type: Type = Type.PLACEHOLDER:
	set(value):
		type = value
		if is_node_ready():
			_apply_type()

@export_group("Shared")
@export var max_hp: float = 150.0
@export var counter_damage: float = 4.0
@export var counter_damage_interval: float = 1.0

@export_group("Assassin")
@export var assassin_max_hp: float = 600.0
@export var move_speed: float = 90.0
## Distance at which the assassin stops stalking and begins a wind-up.
@export var strike_range: float = 45.0
@export var windup_time: float = 0.6
@export var lunge_speed: float = 420.0
@export var lunge_time: float = 0.22
@export var strike_damage: float = 12.0
@export var backoff_time: float = 0.4
@export var backoff_speed: float = 160.0
@export var recover_time: float = 0.8
## Combo pacing: with a Firewall in the level, the Assassin holds its strike
## until the Firewall is within strike_range * 1.5 of the player (the pin) —
## then gives up waiting after this many seconds, so it can never softlock.
@export var pin_fallback_time: float = 4.0
var _stalk_in_range: float = 0.0

@export_group("Predator")
@export var pred_search_radius: float = 151.0
@export var pred_cluster_threshold: int = 5
@export var pred_search_speed: float = 60.0
@export var pred_charge_speed: float = 320.0
@export var pred_charge_damage: float = 15.0
@export var pred_charge_duration: float = 0.6
@export var pred_recover_time: float = 0.4
## How often (seconds) SEARCH runs its full cluster scan. Drift movement keeps
## running every tick between scans, so only the (expensive) scan is throttled.
@export var pred_search_interval: float = 0.15
var _pred_search_timer: float = 0.0
## How long (s) a Predator waits after waking before it starts hunting (was a
## flat 15s — long enough to sit out the entire opening of a fight).
@export var pred_grace_time: float = 3.0
## Combo link: when an awake Siren is laying a lure within this radius, her
## clump counts as a cluster and the Predator charges the bait spot — the
## clump-and-pounce pair fires on its own.
@export var pred_lure_link_radius: float = 400.0
## Fear flare (WINDUP + STRIKE only): radius in cells and the absolute hunt
## value stamped at the centre each frame while flaring. Negative scatters
## ants; positive would draw them in. Set to 0 to disable the flare entirely
## (currently off).
@export var aura_radius_cells: int = 5
@export var aura_strength: float = 0.0

var hp: float
var dead: bool = false

var duel_state: int = DuelState.STALK
var state_timer: float = 0.0
var aim_dir: Vector2 = Vector2.RIGHT
var struck_this_strike: bool = false

var pred_state: int = PredState.SEARCH
var pred_state_timer: float = 0.0
var pred_charge_dir: Vector2 = Vector2.RIGHT
var pred_hit_set: Dictionary = {}
var pred_grace_elapsed: float = 0.0
var pred_kill_chance: float = 0.125

@export_group("Firewall")
## Distortion enemy: attacks the player's CONTROL rather than ants or health.
## Inside the field the swarm's pheromone reading is scrambled (zero-mean noise)
## and the rim gives a soft outward nudge, so ants still enter but cannot hold
## formation and parking the swarm there is a losing battle. Field effects do
## not stack — only the strongest Firewall influences a given point.
@export var firewall_max_hp: float = 350.0
@export var firewall_speed: float = 20.0
@export var firewall_accel: float = 200.0
@export var firewall_field_radius: float = 95.0
## Core scramble: zero-mean jitter added to each candidate direction's final
## score inside the field (0.55 = a large kick relative to the base bonuses).
## Zero-mean and applied after the scoring nonlinearities, so unlike the old
## one-sided attenuation it never biases direction — ants still follow the
## attract in, they simply cannot hold a formation while inside.
@export var firewall_noise: float = 0.55
## Soft outward push felt near the field's rim (score units per cell step), so
## the swarm's parked edge stays fuzzy instead of snapping to a hard disc. Kept
## small so parking the swarm is effortful, not impossible.
@export var firewall_rim_push: float = 0.4
@export var firewall_falloff_pow: float = 1.5
var firewall_state: int = FirewallState.MOVE
var firewall_vel: Vector2 = Vector2.ZERO

@export_group("Broodmother")
## Heavy hijacker: paints home pheromone so returning foragers treat it as a
## nest, then skims the food they bring. It does not kill ants — it starves
## your economy. Very slow, very tanky.
@export var broodmother_max_hp: float = 500.0
@export var broodmother_speed: float = 12.0
@export var broodmother_field_radius_cells: int = 6
@export var broodmother_emit_per_sec: float = 3.0
@export var broodmother_steal_radius_cells: float = 4.0
@export var broodmother_steal_heal: float = 10.0
## How often (seconds) the delivery-skim scan runs. Throttled from every
## physics tick; radius, heal and counters are unchanged.
@export var broodmother_steal_interval: float = 0.12
## Alternate pay-off while food is disabled (FoodSource.ENABLED == false): no
## deliveries exist to skim, so she siphons from ants gathered around the
## beacon instead — up to broodmother_siphon_max_ants every steal interval,
## healing broodmother_siphon_heal each (~20 HP/s at 6 ants / 0.12s). Still
## never kills ants; flipping food back on restores the delivery-skim path.
@export var broodmother_siphon_heal: float = 0.4
@export var broodmother_siphon_max_ants: int = 6
var brood_stolen: int = 0
var _brood_steal_timer: float = 0.0

@export_group("Siren")
## Heavy bait: mimics the player's ATTRACT to gather the swarm, then snaps shut
## and devours everything caught in the lure. Lure → windup → snap → recover.
@export var siren_max_hp: float = 300.0
@export var siren_speed: float = 14.0
@export var siren_lure_radius_cells: int = 8
@export var siren_lure_emit_per_sec: float = 4.0
@export var siren_threshold: int = 6
@export var siren_windup_time: float = 0.9
@export var siren_snap_radius_cells: float = 5.0
@export var siren_snap_damage: float = 1000.0
@export var siren_recover_time: float = 1.6
## How often (seconds) the LURE state counts agents around the bait. Same
## threshold check, just fewer scans per second.
@export var siren_count_interval: float = 0.15
var siren_state: int = SirenState.LURE
var siren_timer: float = 0.0
var siren_snaps: int = 0
var _siren_count_timer: float = 0.0

@onready var counter_damage_timer: Timer = $CounterDamageTimer
@onready var hp_label: Label = $HPLabel

@export_group("Navigation (procedural)")
## Procedural enemies route around walls through the world's shared flow field
## instead of grinding straight along them. Sandbox ignores this entirely.
@export var use_navigation: bool = true
## A procedural enemy holds its post until the player comes within this many
## world px (or damages it), then wakes and pursues for good.
@export var awake_radius: float = 260.0
## How far an un-woken enemy may drift from its post before it walks back.
@export var post_leash: float = 48.0

@export_group("Coordination (procedural)")
## When this enemy wakes (player close, or damaged), dormant allies within this
## radius receive a staggered assist: they hold post a moment longer, then join
## the fight. Group engagements instead of a conveyor belt of 1v1 duels.
@export var assist_link_radius: float = 300.0
@export var assist_delay_min: float = 0.5
@export var assist_delay_max: float = 1.5
## While approaching from further than this (px), a flanking ally heads for its
## personal slot on the ring around the player instead of walking the shared
## flow gradient straight in; inside it, it closes in normally.
@export var flank_radius: float = 250.0

var assist_pending: bool = false
var assist_timer: float = 0.0
var flank_slot: int = -1

var awake: bool = false
var post_pos: Vector2 = Vector2.ZERO
var _post_assigned: bool = false

@export_group("Rendering")
## Enemies re-tessellate their canvas only when their look actually changes —
## state transitions and damage force one; everything else is capped at this
## rate. Without the cap, a dozen awake enemies re-draw every single frame,
## which is a large part of the Procedural 3 frame-time spikes.
@export var redraw_interval: float = 0.1
var _redraw_accum: float = 0.0
var _redraw_due: bool = true
var _redraw_force: bool = false


## Refresh the canvas at most `redraw_interval` times a second (or immediately
## after `_force_redraw()` was requested).
func _maybe_redraw() -> void:
	if _redraw_due:
		queue_redraw()


func _force_redraw() -> void:
	_redraw_force = true


## Advances the redraw throttle; called first thing each physics tick.
func _tick_redraw(delta: float) -> void:
	_redraw_accum += delta
	_redraw_due = _redraw_force or _redraw_accum >= redraw_interval
	if _redraw_due:
		_redraw_accum = 0.0
		_redraw_force = false


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	hp = max_hp
	_update_label()
	if type == Type.PLACEHOLDER:
		counter_damage_timer.wait_time = counter_damage_interval
		counter_damage_timer.timeout.connect(_on_counter_damage_timeout)
		counter_damage_timer.start()
	_apply_type()


## Applies configuration that depends on `type`. Called from `_ready()` and
## whenever `type` changes after the node is in the tree (e.g. `game.gd`
## selects the enemy once the scene, and therefore this node, is already ready).
func _apply_type() -> void:
	if type == Type.FIREWALL:
		max_hp = firewall_max_hp
		hp = max_hp
		firewall_vel = Vector2.ZERO
		if not is_in_group("firewalls"):
			add_to_group("firewalls")
		_update_label()
	elif type == Type.BROODMOTHER:
		max_hp = broodmother_max_hp
		hp = max_hp
		brood_stolen = 0
		_update_label()
	elif type == Type.SIREN:
		max_hp = siren_max_hp
		hp = max_hp
		siren_state = SirenState.LURE
		siren_timer = 0.0
		siren_snaps = 0
		_update_label()
	elif type == Type.ASSASSIN:
		max_hp = assassin_max_hp
		hp = max_hp
		_update_label()
	# Enemies the swarm simply cannot bite: the Predator soaks up ants without
	# taking damage from them, and the lure enemies (Broodmother, Siren) would
	# otherwise be destroyed by the very ants they attract. All three stay in the
	# "swarm_targets" group on purpose so the player's melee can still finish them.
	swarm_immune = type == Type.PREDATOR or type == Type.BROODMOTHER or type == Type.SIREN


func _physics_process(delta: float) -> void:
	_tick_redraw(delta)
	if not _post_assigned:
		post_pos = global_position
		_post_assigned = true
	var world := _get_world()
	if world != null and world.procedural and not awake:
		if assist_pending:
			assist_timer -= delta
			if assist_timer <= 0.0:
				assist_pending = false
				awake = true
				_force_redraw()
		if not awake:
			var player := _nearest_player()
			if player != null and global_position.distance_to(player.global_position) <= awake_radius:
				awake = true
				_force_redraw()
				_call_for_help(world)
			else:
				# Ambush: stay put (behind cover) until the player gets close
				# enough, an ally calls for help, or it is attacked. No field is
				# stamped while dormant.
				_hold_post(world, delta)
				_maybe_redraw()
				return
	match type:
		Type.ASSASSIN:
			_behave_assassin(delta)
		Type.PREDATOR:
			_behave_predator(delta)
		Type.FIREWALL:
			_behave_firewall(delta)
		Type.BROODMOTHER:
			_behave_broodmother(delta)
		Type.SIREN:
			_behave_siren(delta)


## Keeps an un-woken enemy near the post it was placed at, so it guards the spot
## rather than wandering off. Only runs in procedural modes.
func _hold_post(world: SwarmWorld, delta: float) -> void:
	var to_post := post_pos - global_position
	if to_post.length() > post_leash:
		_move_clamped(to_post.normalized() * move_speed * 0.6 * delta, world)


## One approach step toward the player: straight in sandbox, routed around walls
## and through doorways via the world's flow field in procedural levels. While
## still far out, an ally also commits to its personal flank lane so a group
## closes from several angles instead of queueing behind the same gradient.
func _chase_step(speed: float, delta: float, world: SwarmWorld, player: Node2D) -> void:
	if player == null:
		return
	var to_player := player.global_position - global_position
	var dir := to_player
	if dir.length_squared() > 0.0001:
		dir = dir.normalized()
	else:
		dir = Vector2.ZERO
	if use_navigation and world.procedural:
		var nav: Vector2 = world.path_dir(global_position, player.global_position)
		if nav != Vector2.ZERO:
			dir = nav
		# The shared flow field keeps exactly one target (the player) so rebuilds
		# never thrash. The flank is a local override on top: head for a slot on
		# the ring around the player until you're inside engagement distance,
		# and only if that slot isn't buried in a wall (otherwise keep the nav
		# direction). The 5% hysteresis stops the lane/goal flip-flop right at
		# the ring's edge.
		if to_player.length() <= flank_radius and dir != Vector2.ZERO:
			var ring := 70.0 * world.cell_size / 10.0
			if to_player.length() > ring * 1.05:
				if flank_slot < 0:
					flank_slot = world.next_flank_slot()
				var ang := TAU * float(flank_slot) / float(SwarmWorld.FLANK_SLOTS)
				var spot: Vector2 = player.global_position + Vector2(cos(ang), sin(ang)) * ring
				if not _pos_blocked(world, spot):
					var fl := spot - global_position
					if fl.length_squared() > 1.0:
						dir = fl.normalized()
	if dir != Vector2.ZERO:
		_move_clamped(dir * speed * delta, world)


func take_damage(amount: float) -> void:
	var was_awake := awake
	awake = true
	_force_redraw()
	if not was_awake:
		_call_for_help(_get_world())
	hp = maxf(hp - amount, 0.0)
	_update_label()
	if hp <= 0.0 and not dead:
		dead = true
		queue_free()


## Ignores the swarm entirely and duels the player in a readable rhythm:
## stalk, telegraphed wind-up (the aim locks here, so the lunge is dodgeable),
## a single-hit lunge, a back-off hop away from the player, then a stationary
## vulnerable recovery. The fear field flares only while attacking and decays
## naturally through normal diffusion afterwards. No continuous contact
## damage; the swarm hurting this node on overlap is the counterplay.
func _behave_assassin(delta: float) -> void:
	var world := _get_world()
	var player := _nearest_player()
	if world == null or player == null:
		return

	state_timer -= delta
	match duel_state:
		DuelState.STALK:
			var to_player: Vector2 = player.global_position - global_position
			if to_player.length() <= strike_range:
				aim_dir = to_player.normalized()
				if _pin_gate_open(world, player, delta):
					struck_this_strike = false
					_enter_state(DuelState.WINDUP, windup_time)
			else:
				_stalk_in_range = 0.0
				_chase_step(move_speed, delta, world, player)
		DuelState.WINDUP:
			if aura_strength != 0.0:
				world.stamp_enemy_field(global_position, aura_radius_cells, aura_strength)
			if state_timer <= 0.0:
				_enter_state(DuelState.STRIKE, lunge_time)
		DuelState.STRIKE:
			if aura_strength != 0.0:
				world.stamp_enemy_field(global_position, aura_radius_cells, aura_strength)
			_move_clamped(aim_dir * lunge_speed * delta, world)
			if not struck_this_strike:
				for body in get_overlapping_bodies():
					if body is Player and body.has_method("take_damage"):
						body.take_damage(strike_damage, global_position)
						struck_this_strike = true
						break
			if state_timer <= 0.0:
				_enter_state(DuelState.BACKOFF, backoff_time)
		DuelState.BACKOFF:
			var away: Vector2 = (global_position - player.global_position).normalized()
			if away == Vector2.ZERO:
				away = -aim_dir
			_move_clamped(away * backoff_speed * delta, world)
			if state_timer <= 0.0:
				_enter_state(DuelState.RECOVER, recover_time)
		DuelState.RECOVER:
			if state_timer <= 0.0:
				duel_state = DuelState.STALK

	_maybe_redraw()


func _enter_state(next: int, duration: float) -> void:
	duel_state = next
	state_timer = duration
	_force_redraw()


## Kinematic step kept inside the arena rectangle and, in procedural levels, out
## of walls. Movement is resolved per-axis so an enemy slides along a wall
## instead of sticking to it. Sandbox behaviour is byte-identical to before; the
## AI above this function is unchanged in both modes.
func _move_clamped(step: Vector2, world: SwarmWorld) -> void:
	if world == null:
		global_position += step
		return
	if not world.procedural:
		global_position += step
		_clamp_to_arena(world)
		return
	var cur := global_position
	var target := cur + step
	var nx := target.x
	if _pos_blocked(world, Vector2(nx, cur.y)):
		nx = cur.x
	var ny := target.y
	if _pos_blocked(world, Vector2(cur.x, ny)):
		ny = cur.y
	if _pos_blocked(world, Vector2(nx, ny)):
		nx = cur.x
		ny = cur.y
	global_position = Vector2(nx, ny)
	_clamp_to_arena(world)


func _clamp_to_arena(world: SwarmWorld) -> void:
	var margin := 16.0
	global_position.x = clampf(global_position.x, world.origin.x + margin, world.origin.x + world.arena_size.x - margin)
	global_position.y = clampf(global_position.y, world.origin.y + margin, world.origin.y + world.arena_size.y - margin)


func _pos_blocked(world: SwarmWorld, pos: Vector2) -> bool:
	if world == null:
		return false
	var cell := world.world_to_cell(pos)
	return world.blocked(cell.x, cell.y)


func _nearest_player() -> Node2D:
	var parent := get_parent()
	if parent == null:
		return null
	var p := parent.get_node_or_null("Player")
	if p != null and is_instance_valid(p):
		return p
	return null


func _get_world() -> SwarmWorld:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("SwarmWorld") as SwarmWorld


## Staggered assist: on the wake transition, dormant allies nearby receive a
## delayed join request instead of an instant dogpile — each ally holds its post
## a little longer, then enters the fight. Procedural only; sandbox untouched.
func _call_for_help(world: SwarmWorld) -> void:
	if world == null or not world.procedural:
		return
	for e in world.get_enemies():
		if e == self or not is_instance_valid(e) or not (e is Enemy):
			continue
		var ally := e as Enemy
		if ally.awake or ally.assist_pending:
			continue
		if global_position.distance_to(ally.global_position) <= assist_link_radius:
			ally.assist_pending = true
			ally.assist_timer = randf_range(assist_delay_min, assist_delay_max)


## Assassin pin gate: with a Firewall in the combo, strikes start only once the
## Firewall is close enough to actually pin the player (or the fallback timer
## expires — no softlock). No Firewall in the level, or sandbox: always open.
func _pin_gate_open(world: SwarmWorld, player: Node2D, delta: float) -> bool:
	if not world.procedural or not _combo_has_firewall(world):
		return true
	if _firewall_pinning(world, player.global_position):
		_stalk_in_range = 0.0
		return true
	_stalk_in_range += delta
	return _stalk_in_range >= pin_fallback_time


func _combo_has_firewall(world: SwarmWorld) -> bool:
	for t in world.combo:
		if int(t) == Type.FIREWALL:
			return true
	return false


func _firewall_pinning(world: SwarmWorld, at: Vector2) -> bool:
	var reach := strike_range * 1.5
	for e in world.get_enemies():
		if not is_instance_valid(e) or not (e is Enemy):
			continue
		var f := e as Enemy
		if f.type != Type.FIREWALL or not f.awake:
			continue
		if f.global_position.distance_to(at) <= reach:
			return true
	return false


## Nearest awake Siren actively laying a lure within pred_lure_link_radius — the
## Predator's half of the clump-and-pounce combo. Returns a position or null.
func _siren_lure_point(world: SwarmWorld) -> Variant:
	var best: Variant = null
	var best_d := pred_lure_link_radius
	for e in world.get_enemies():
		if not is_instance_valid(e) or e == self or not (e is Enemy):
			continue
		var s := e as Enemy
		if s.type != Type.SIREN or not s.awake:
			continue
		if s.siren_state != SirenState.LURE and s.siren_state != SirenState.WINDUP:
			continue
		var d := global_position.distance_to(s.global_position)
		if d <= best_d:
			best_d = d
			best = s.global_position
	return best


func _on_counter_damage_timeout() -> void:
	for area in get_overlapping_areas():
		if area.is_in_group("swarm_agents") and area.has_method("take_damage"):
			area.take_damage(counter_damage)


func _update_label() -> void:
	if hp_label == null:
		return
	var text := "HP: %d / %d" % [int(hp), int(max_hp)]
	if type == Type.BROODMOTHER:
		text += "  Stolen: %d" % brood_stolen
	elif type == Type.SIREN:
		text += "  %s" % SirenState.keys()[siren_state]
	hp_label.text = text


func _draw() -> void:
	match type:
		Type.ASSASSIN:
			_draw_assassin()
		Type.PREDATOR:
			draw_circle(Vector2.ZERO, 16.0, Color(0.8, 0.3, 0.1, 0.95))
		Type.FIREWALL:
			_draw_firewall()
		Type.BROODMOTHER:
			_draw_broodmother()
		Type.SIREN:
			_draw_siren()
		_:
			draw_circle(Vector2.ZERO, 14.0, Color(0.55, 0.4, 0.75, 0.9))


## State read at a glance: dim red stalking, brightening pulse + growing aim
## line and danger ring while winding up, hot flash on the lunge, muted hop
## backing off, dark and desaturated while recovering.

func _behave_firewall(delta: float) -> void:
	var world := _get_world()
	var player := _nearest_player()
	if world == null:
		return
	var target: Vector2 = global_position
	if player != null:
		target = player.global_position
	var to_target: Vector2 = target - global_position
	var dir := Vector2.ZERO
	if to_target.length_squared() > 0.01:
		dir = to_target.normalized()
	if use_navigation and world.procedural and player != null:
		var nav: Vector2 = world.path_dir(global_position, player.global_position)
		if nav != Vector2.ZERO:
			dir = nav
	var desired_vel := dir * firewall_speed
	firewall_vel = firewall_vel.move_toward(desired_vel, firewall_accel * delta)
	_move_clamped(firewall_vel * delta, world)


## Heavy hijacker. Crawls toward the player while continuously painting home
## pheromone around itself, so carrying foragers climb to it as if it were a
## nest and deposit their food — which the Broodmother skims, healing itself
## and starving the player's delivery economy. It never kills ants directly.
func _behave_broodmother(delta: float) -> void:
	var world := _get_world()
	if world == null:
		return
	var player := _nearest_player()
	if player != null:
		_chase_step(broodmother_speed, delta, world, player)
	# Hijack beacon — the swarm's own loyalty does the pulling.
	world.stamp_home_field(global_position, broodmother_field_radius_cells, broodmother_emit_per_sec * delta)
	# Get paid: skim deliveries from carrying ants that reach the beacon. With
	# food disabled there are no deliveries, so she siphons from the ants
	# gathered around the beacon instead. Throttled to the steal interval.
	_brood_steal_timer -= delta
	if _brood_steal_timer <= 0.0:
		_brood_steal_timer = broodmother_steal_interval
		var steal_px: float = broodmother_steal_radius_cells * world.cell_size
		if FoodSource.ENABLED:
			var stole := false
			for agent in world.get_swarm_agents():
				if not is_instance_valid(agent) or not agent.carry:
					continue
				if global_position.distance_to(agent.global_position) <= steal_px:
					agent.carry = false
					brood_stolen += 1
					hp = minf(hp + broodmother_steal_heal, max_hp)
					stole = true
			if stole:
				_update_label()
		else:
			var siphoned := 0
			for agent in world.get_swarm_agents():
				if not is_instance_valid(agent):
					continue
				if global_position.distance_to(agent.global_position) > steal_px:
					continue
				hp = minf(hp + broodmother_siphon_heal, max_hp)
				brood_stolen += 1
				siphoned += 1
				if siphoned >= broodmother_siphon_max_ants:
					break
			if siphoned > 0:
				_update_label()
	_maybe_redraw()


## Heavy bait. Mimics the player's ATTRACT to gather the swarm, telegraphs a
## windup, then snaps shut and devours everything in the lure. Then it recovers,
## giving the player a window to scatter the swarm or strike it.
func _behave_siren(delta: float) -> void:
	var world := _get_world()
	if world == null:
		return
	siren_timer -= delta
	var player := _nearest_player()
	if player != null:
		if siren_state != SirenState.SNAP:
			_chase_step(siren_speed, delta, world, player)
	match siren_state:
		SirenState.LURE:
			world.stamp_lure_field(global_position, siren_lure_radius_cells, siren_lure_emit_per_sec * delta)
			_siren_count_timer -= delta
			if _siren_count_timer <= 0.0:
				_siren_count_timer = siren_count_interval
				if _agents_within(world, siren_lure_radius_cells) >= siren_threshold:
					siren_state = SirenState.WINDUP
					siren_timer = siren_windup_time
		SirenState.WINDUP:
			# Keep baiting so the swarm does not wander off before the bite.
			world.stamp_lure_field(global_position, siren_lure_radius_cells, siren_lure_emit_per_sec * delta)
			if siren_timer <= 0.0:
				_siren_snap(world)
				siren_state = SirenState.RECOVER
				siren_timer = siren_recover_time
		SirenState.RECOVER:
			if siren_timer <= 0.0:
				siren_state = SirenState.LURE
				_siren_count_timer = 0.0  # count immediately on re-entry, as before
	_maybe_redraw()


func _agents_within(world: SwarmWorld, radius_cells: float) -> int:
	var r: float = radius_cells * world.cell_size
	var n := 0
	for agent in world.get_swarm_agents():
		if is_instance_valid(agent) and global_position.distance_to(agent.global_position) <= r:
			n += 1
	return n


func _siren_snap(world: SwarmWorld) -> void:
	var r: float = siren_snap_radius_cells * world.cell_size
	for agent in world.get_swarm_agents():
		if is_instance_valid(agent) and global_position.distance_to(agent.global_position) <= r:
			agent.take_damage(siren_snap_damage)
	siren_snaps += 1
	_update_label()


func _behave_predator(delta: float) -> void:
	var world := _get_world()
	if world == null:
		return
	pred_state_timer -= delta
	pred_grace_elapsed += delta
	_pred_search_timer -= delta
	if pred_grace_elapsed < pred_grace_time:
		return
	match pred_state:
		PredState.SEARCH:
			if _pred_search_timer <= 0.0:
				_pred_search_timer = pred_search_interval
				var sum := Vector2.ZERO
				var count: int = 0
				var agents = world.get_swarm_agents()
				for agent in agents:
					if not is_instance_valid(agent):
						continue
					var dist := global_position.distance_to(agent.global_position)
					if dist <= pred_search_radius:
						sum += agent.global_position
						count += 1
				# Combo link: an awake Siren actively laying a lure nearby is the
				# clump — charge the bait spot while she's pulling the swarm in.
				if count < pred_cluster_threshold:
					var lure = _siren_lure_point(world)
					if lure != null:
						# sum gets averaged by count below, so scale it to match.
						sum = Vector2(lure) * float(pred_cluster_threshold)
						count = pred_cluster_threshold
				# Also check swarm density near player if player is in range
				var player := _nearest_player()
				if count < pred_cluster_threshold and player != null and global_position.distance_to(player.global_position) <= pred_search_radius * 1.2:
					var pcount: int = 0
					var psum := Vector2.ZERO
					for agent in agents:
						if not is_instance_valid(agent):
							continue
						var dist := player.global_position.distance_to(agent.global_position)
						if dist <= 90.0:
							psum += agent.global_position
							pcount += 1
					if pcount >= pred_cluster_threshold:
						sum = psum
						count = pcount
				if count >= pred_cluster_threshold:
					var centroid = sum / float(count)
					pred_charge_dir = (centroid - global_position)
					if pred_charge_dir.length() < 0.001:
						pred_charge_dir = Vector2.RIGHT
					else:
						pred_charge_dir = pred_charge_dir.normalized()
					pred_hit_set.clear()
					pred_state = PredState.CHARGE
					pred_state_timer = pred_charge_duration
				else:
					_move_clamped(pred_charge_dir * pred_search_speed * 0.1 * delta, world)
			else:
				# Between throttled scans: keep drifting along the last heading,
				# exactly as the per-tick scan did when it found no cluster.
				_move_clamped(pred_charge_dir * pred_search_speed * 0.1 * delta, world)
		PredState.CHARGE:
			_move_clamped(pred_charge_dir * pred_charge_speed * delta, world)
			for area in get_overlapping_areas():
				if area.is_in_group("swarm_agents") and area.has_method("take_damage"):
					var id: int = area.get_instance_id()
					if not pred_hit_set.has(id):
						pred_hit_set[id] = true
						if randf() < pred_kill_chance:
							if area.has_method("take_damage"):
								area.take_damage(250.0)
			if pred_state_timer <= 0.0:
				pred_state = PredState.RECOVER
				pred_state_timer = pred_recover_time
		PredState.RECOVER:
			if pred_state_timer <= 0.0:
				pred_state = PredState.SEARCH
	_maybe_redraw()
func _draw_assassin() -> void:
	match duel_state:
		DuelState.STALK:
			draw_circle(Vector2.ZERO, 14.0, Color(0.62, 0.2, 0.2, 0.85))
		DuelState.WINDUP:
			var t := clampf(1.0 - state_timer / maxf(windup_time, 0.001), 0.0, 1.0)
			draw_circle(Vector2.ZERO, 14.0, Color(0.95, 0.25, 0.2, 0.7 + 0.3 * t))
			draw_line(Vector2.ZERO, aim_dir * (22.0 + 52.0 * t), Color(1.0, 0.9, 0.6, 0.4 + 0.6 * t), 3.0)
			draw_arc(Vector2.ZERO, strike_range * t, 0.0, TAU, 24, Color(1.0, 0.55, 0.4, 0.25 + 0.45 * t), 2.0)
		DuelState.STRIKE:
			draw_circle(Vector2.ZERO, 15.0, Color(1.0, 0.55, 0.25, 0.95))
			draw_line(Vector2.ZERO, aim_dir * 28.0, Color(1.0, 0.85, 0.5, 0.9), 4.0)
		DuelState.BACKOFF:
			draw_circle(Vector2.ZERO, 13.0, Color(0.5, 0.22, 0.38, 0.85))
		DuelState.RECOVER:
			draw_circle(Vector2.ZERO, 12.0, Color(0.34, 0.17, 0.17, 0.65))
	draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 24, Color(0.95, 0.4, 0.4, 0.8), 2.0)

func _draw_firewall() -> void:
	# Faint ring telegraphs the noise zone's true extent; concentric dim rings
	# suggest the turbulence inside rather than a solid wall.
	draw_arc(Vector2.ZERO, firewall_field_radius, 0.0, TAU, 48, Color(0.4, 0.65, 1.0, 0.20), 2.0)
	draw_arc(Vector2.ZERO, firewall_field_radius * 0.66, 0.0, TAU, 40, Color(0.4, 0.65, 1.0, 0.10), 1.5)
	draw_arc(Vector2.ZERO, firewall_field_radius * 0.33, 0.0, TAU, 32, Color(0.4, 0.65, 1.0, 0.10), 1.5)
	draw_circle(Vector2.ZERO, 22.0, Color(0.25, 0.35, 0.6, 0.6))
	draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 24, Color(0.45, 0.7, 1.0, 0.9), 3.0)
	draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 16, Color(0.3, 0.5, 0.9, 0.7), 2.0)


func _draw_broodmother() -> void:
	var world := _get_world()
	if world != null:
		draw_arc(Vector2.ZERO, float(broodmother_field_radius_cells) * world.cell_size, 0.0, TAU, 48, Color(0.7, 0.9, 0.4, 0.16), 2.0)
	draw_circle(Vector2.ZERO, 26.0, Color(0.34, 0.16, 0.38, 0.75))
	draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 24, Color(0.85, 0.5, 1.0, 0.9), 3.0)
	draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 16, Color(0.95, 0.75, 1.0, 0.7), 2.0)


func _draw_siren() -> void:
	var world := _get_world()
	match siren_state:
		SirenState.LURE:
			draw_circle(Vector2.ZERO, 18.0, Color(0.18, 0.55, 0.5, 0.8))
			if world != null:
				draw_arc(Vector2.ZERO, float(siren_lure_radius_cells) * world.cell_size, 0.0, TAU, 48, Color(0.4, 0.95, 0.85, 0.16), 2.0)
		SirenState.WINDUP:
			var t := clampf(1.0 - siren_timer / maxf(siren_windup_time, 0.001), 0.0, 1.0)
			draw_circle(Vector2.ZERO, 18.0, Color(0.95, 0.7, 0.2, 0.7 + 0.3 * t))
			draw_arc(Vector2.ZERO, 18.0 + 22.0 * t, 0.0, TAU, 24, Color(1.0, 0.85, 0.4, 0.5 + 0.5 * t), 3.0)
		SirenState.SNAP:
			draw_circle(Vector2.ZERO, 24.0, Color(1.0, 0.32, 0.2, 0.95))
		SirenState.RECOVER:
			draw_circle(Vector2.ZERO, 16.0, Color(0.28, 0.34, 0.3, 0.6))
	draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 24, Color(0.5, 0.9, 0.8, 0.8), 2.0)
