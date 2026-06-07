# Swarm Combat Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder `cast`/`eminate`/`Attack` stubs in the existing Godot player with a combat system where the player commands a personal ant swarm — directing it with cast patterns (Hunt/Scatter/Loop Hunt/Bounce Hunt), recalling it, managing its Strength Pool, and falling back on personal melee — validated against a placeholder enemy.

**Architecture:** A `SwarmController` (child of Player) owns a pool of `SwarmAgent`s that steer (orbit/seek/separate) rather than run a diffusion grid. Casting spawns a temporary decaying `CastField` shaped by the active `CastPattern`; agents sample it for direction+strength while in `DIRECTED` state, and resolve combat (DOT out, counter-damage in) via Area2D overlap with anything in the `swarm_targets` group. `player.gd` is extended (not rewritten) to compute cast direction/anchor from the active aiming mode and delegate to the controller.

**Tech Stack:** Godot 4.3 (GDScript, `gl_compatibility` renderer), `CharacterBody2D`/`Area2D`/`Node2D` scene composition. No automated test framework is present in this project (no GUT) — every task ends with a manual playtest checkpoint that states exactly what to press and what you should observe in the running game (press F6 to run the current scene, or F5 for the main scene).

---

## Before You Start

The `.tscn`/`.gd` files in this repo reference paths like `res://scenes/Player.tscn`, `res://scripts/player.gd`, `res://assets/...`, but the files currently live flat at the project root (this happened because earlier commits were pushed via GitHub's web "Add files via upload", which doesn't preserve folder structure). Open the project in the Godot 4.3 editor first:

- If it opens cleanly and the game runs (F5) with the player animating and casting, the editor has already resolved the paths via resource UIDs — proceed with the plan as written, creating new files at the project root alongside `player.gd` and `game.tscn` (matching their *current* actual location).
- If you see "broken resource path" errors, the missing `scenes/`, `scripts/`, `assets/` folders need to be recreated (move the existing files into them to match the paths the `.tscn` files expect) before any of this plan's manual playtests will work. This is a pre-existing repo issue, not part of this feature — fix it first, commit it separately, then start Task 1.

All file paths in this plan assume the project root layout (current actual location of `player.gd`, `game.tscn`, `Player.tscn`, `rift_projectile.gd/.tscn`).

---

## File Structure

New files (created at project root, alongside `player.gd`):
- `swarm_target.gd` — thin base class / contract for anything the swarm can damage
- `placeholder_enemy.gd` + `placeholder_enemy.tscn` — test dummy implementing the contract, deals counter-damage
- `swarm_agent.gd` + `swarm_agent.tscn` — one ant: steering state machine (idle orbit / directed / combat resolution)
- `cast_pattern.gd` — data definition for a cast pattern (shape + tuning numbers)
- `cast_field.gd` — temporary decaying directional gradient spawned at cast time
- `swarm_controller.gd` — owns the agent pool, Strength Pool, pattern unlock/cycling, cast/recall

Modified files:
- `player.gd` — aiming-mode resolution, cast/eminate/Attack now do real things
- `Player.tscn` — gains a `SwarmController` child node
- `game.tscn` — gains a `PlaceholderEnemy` instance for in-game testing

Deleted files (Task 14):
- `rift_projectile.gd`, `rift_projectile.tscn`

---

## Task 1: `SwarmTarget` contract + `PlaceholderEnemy` test dummy

**Files:**
- Create: `swarm_target.gd`
- Create: `placeholder_enemy.gd`
- Create: `placeholder_enemy.tscn`
- Modify: `game.tscn`

This task stands alone — it doesn't depend on the swarm existing yet. We build the thing the swarm will fight first so every later task has something to test against.

- [ ] **Step 1: Create the `SwarmTarget` base class**

Write `swarm_target.gd`:

```gdscript
extends Area2D
class_name SwarmTarget

## Minimal contract for anything the swarm can engage. Extend this and
## override take_damage() — registration in the "swarm_targets" group is
## handled here so SwarmAgents can detect any subclass. World position is
## just the inherited Node2D `global_position` — no need to wrap it; later
## tasks read `target.global_position` directly.

func _ready() -> void:
	add_to_group("swarm_targets")

func take_damage(_amount: float) -> void:
	pass
```

- [ ] **Step 2: Create the `PlaceholderEnemy` script**

Write `placeholder_enemy.gd`:

```gdscript
extends SwarmTarget
class_name PlaceholderEnemy

@export var max_hp: float = 100.0
@export var counter_damage: float = 4.0
@export var counter_damage_interval: float = 1.0

var hp: float

@onready var counter_damage_timer: Timer = $CounterDamageTimer
@onready var hp_label: Label = $HPLabel

func _ready() -> void:
	super._ready()
	hp = max_hp
	_update_label()
	counter_damage_timer.wait_time = counter_damage_interval
	counter_damage_timer.timeout.connect(_on_counter_damage_timeout)
	counter_damage_timer.start()

func take_damage(amount: float) -> void:
	hp = max(hp - amount, 0.0)
	_update_label()
	if hp <= 0.0:
		queue_free()

func _on_counter_damage_timeout() -> void:
	for area in get_overlapping_areas():
		if area.is_in_group("swarm_agents") and area.has_method("take_counter_damage"):
			area.take_counter_damage(counter_damage)

func _update_label() -> void:
	hp_label.text = "HP: %d / %d" % [int(hp), int(max_hp)]
```

- [ ] **Step 3: Build the `PlaceholderEnemy` scene**

Write `placeholder_enemy.tscn`:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://placeholder_enemy.gd" id="1_enemy"]

[sub_resource type="CircleShape2D" id="CircleShape2D_enemy"]
radius = 16.0

[node name="PlaceholderEnemy" type="Area2D"]
script = ExtResource("1_enemy")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_enemy")

[node name="CounterDamageTimer" type="Timer" parent="."]

[node name="HPLabel" type="Label" parent="."]
offset_left = -24.0
offset_top = -36.0
offset_right = 24.0
offset_bottom = -16.0
horizontal_alignment = 1
```

- [ ] **Step 4: Place an instance in `game.tscn` for testing**

Open `game.tscn` in the editor, drag `placeholder_enemy.tscn` into the scene as a child of `Game`, and position it a couple hundred pixels to the right of the player's start position (e.g. `position = Vector2(200, 0)`) so it's reachable. Save the scene.

- [ ] **Step 5: Playtest checkpoint**

Run the main scene (F5). You should see the player and, to its right, a small circle with an "HP: 100 / 100" label above it that ticks down by 4 every second (because nothing is overlapping it yet, the loop runs but finds no `swarm_agents` — confirm this by temporarily adding `print("tick")` inside `_on_counter_damage_timeout` and watching the Output panel print once per second; then remove the print). Confirm there are no script errors in the Output/Debugger panel.

- [ ] **Step 6: Commit**

```bash
git add swarm_target.gd placeholder_enemy.gd placeholder_enemy.tscn game.tscn
git commit -m "Add SwarmTarget contract and PlaceholderEnemy test dummy"
```

---

## Task 2: `SwarmAgent` — idle orbit steering

**Files:**
- Create: `swarm_agent.gd`
- Create: `swarm_agent.tscn`

One ant that, given an anchor to orbit, drifts around it organically (separation + light noise). No combat or directed behavior yet — that comes in Tasks 5–6. We build this in isolation so the steering can be eyeballed before the controller wires dozens of them together.

- [ ] **Step 1: Write the `SwarmAgent` script**

Write `swarm_agent.gd`:

```gdscript
extends Area2D
class_name SwarmAgent

enum State { IDLE, DIRECTED }

const SEPARATION_RADIUS := 16.0
const SEPARATION_FORCE := 80.0
const NOISE_STRENGTH := 18.0
const STEER_LERP := 0.12
const DIRECTED_BASE_SPEED := 220.0
const DOT_PER_SECOND := 6.0

var state: int = State.IDLE
var velocity: Vector2 = Vector2.ZERO

# Idle orbit
var orbit_anchor: Node2D = null
var orbit_angle: float = 0.0
var orbit_radius: float = 40.0
var orbit_speed: float = 90.0

# Directed (cast) movement — set by SwarmController.enter_directed()
var cast_field = null
var directed_speed: float = DIRECTED_BASE_SPEED

# Wiring set by SwarmController at spawn time
var swarm_controller: Node = null
var neighbors: Array = []

var _noise_offset: float = 0.0

func _ready() -> void:
	add_to_group("swarm_agents")
	_noise_offset = randf() * TAU
	orbit_angle = randf() * TAU

func _physics_process(delta: float) -> void:
	var steer := Vector2.ZERO
	match state:
		State.IDLE:
			steer = _idle_steering(delta)
		State.DIRECTED:
			steer = _directed_steering()
	steer += _separation_steering()
	velocity = velocity.lerp(steer, STEER_LERP)
	global_position += velocity * delta
	_resolve_combat(delta)

func _idle_steering(delta: float) -> Vector2:
	if orbit_anchor == null:
		return Vector2.ZERO
	orbit_angle += (orbit_speed / orbit_radius) * delta
	var orbit_target: Vector2 = orbit_anchor.global_position + Vector2.RIGHT.rotated(orbit_angle) * orbit_radius
	var to_target := orbit_target - global_position
	var noise := Vector2.RIGHT.rotated(_noise_offset + Time.get_ticks_msec() * 0.001) * NOISE_STRENGTH
	return to_target.normalized() * orbit_speed + noise

func _directed_steering() -> Vector2:
	return Vector2.ZERO  # filled in by Task 5

func _separation_steering() -> Vector2:
	var push := Vector2.ZERO
	for neighbor in neighbors:
		if neighbor == self or not is_instance_valid(neighbor):
			continue
		var offset: Vector2 = global_position - neighbor.global_position
		var dist := offset.length()
		if dist > 0.0 and dist < SEPARATION_RADIUS:
			push += offset.normalized() * (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS
	return push * SEPARATION_FORCE

func _resolve_combat(_delta: float) -> void:
	pass  # filled in by Task 6

func return_to_idle() -> void:
	state = State.IDLE
	cast_field = null
```

- [ ] **Step 2: Build the `SwarmAgent` scene**

Write `swarm_agent.tscn`:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://swarm_agent.gd" id="1_agent"]

[sub_resource type="CircleShape2D" id="CircleShape2D_agent"]
radius = 4.0

[node name="SwarmAgent" type="Area2D"]
script = ExtResource("1_agent")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_agent")

[node name="ColorRect" type="ColorRect" parent="."]
offset_left = -3.0
offset_top = -3.0
offset_right = 3.0
offset_bottom = 3.0
color = Color(0.95, 0.78, 0.25, 1)
```

(The `ColorRect` is a placeholder visual — a small yellow square per agent — so you can see them move before any sprite work happens. Swap it for real art later; that's out of scope here.)

- [ ] **Step 3: Playtest checkpoint (manual, temporary scene)**

In the editor, create a new empty 2D scene, add a `Node2D` named "Anchor" at the origin, instance `swarm_agent.tscn` as its sibling, and in the agent's "Inspector → Node → Script Variables" set `orbit_anchor` to the Anchor node (drag it into the field — if the field doesn't appear because it's a plain `var`, instead temporarily add one line `@export var orbit_anchor: Node2D` for this test, run it, then revert that line). Run this scene (F6): the agent should circle the anchor smoothly with a slight organic wobble, not snap or jitter. Delete this temporary scene when done — it was only for eyeballing the steering in isolation.

- [ ] **Step 4: Commit**

```bash
git add swarm_agent.gd swarm_agent.tscn
git commit -m "Add SwarmAgent with idle-orbit steering"
```

---

## Task 3: `SwarmController` — spawn the pool, orbit the player

**Files:**
- Create: `swarm_controller.gd`
- Modify: `Player.tscn`

Wires up the first end-to-end visible result: dozens of agents trailing the player as a cloud.

- [ ] **Step 1: Write the `SwarmController` script**

Write `swarm_controller.gd`:

```gdscript
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
```

- [ ] **Step 2: Add the controller to `Player.tscn`**

Open `Player.tscn` in the editor. Select the root `Player` node, add a child node of type `Node2D`, rename it to `SwarmController`, and attach `swarm_controller.gd` to it. In the Inspector, set its exported `Player` field to the `Player` node itself (drag the root node onto the `player` export slot — it will resolve to the scene root at runtime since `Player.tscn` is instanced as the player in `game.tscn`).

- [ ] **Step 3: Playtest checkpoint**

Run the main scene (F5). You should see ~28 small yellow squares forming a loose, slightly wobbly ring around the player that follows as you move with `move_up/down/left/right`. They shouldn't all overlap into a single dot (separation is working) or fly off-screen (orbit anchoring is working).

- [ ] **Step 4: Commit**

```bash
git add swarm_controller.gd Player.tscn
git commit -m "Add SwarmController spawning an orbiting agent pool"
```

---

## Task 4: Strength Pool — passive regen toward a level-scaled cap

**Files:**
- Modify: `swarm_controller.gd`
- Modify: `game.tscn`

Adds the resource the rest of combat will deplete and replenish. We wire a temporary on-screen readout now so depletion (Task 6) is observable later without guesswork.

- [ ] **Step 1: Add Strength Pool state and regen to `SwarmController`**

In `swarm_controller.gd`, add near the top (after the existing consts):

```gdscript
const STRENGTH_REGEN_PER_SECOND := 4.0
const STRENGTH_CAP_BASE := 100.0
const STRENGTH_CAP_PER_LEVEL := 20.0

signal strength_changed(current: float, cap: float)
```

Add instance vars alongside `agents`:

```gdscript
var strength_current: float = STRENGTH_CAP_BASE
var player_level: int = 1
```

Add a `_physics_process` (the script doesn't have one yet):

```gdscript
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
```

- [ ] **Step 2: Add a temporary on-screen readout**

Open `game.tscn`, select the existing `CanvasLayer`, add a child `Label` named `StrengthLabel` positioned just below the existing "Current Cast: Scatter" label (e.g. `offset_top = -16.0`, `offset_bottom = 4.0`, same horizontal offsets), with placeholder `text = "Strength: 100 / 100"`.

Then, in `game.tscn`'s own script — it doesn't have one yet, so attach a new tiny script directly to the `Game` root node via the editor ("Attach Script", default path `res://game.gd`) containing:

```gdscript
extends Node2D

@onready var strength_label: Label = $CanvasLayer/StrengthLabel

func _ready() -> void:
	var swarm_controller := $Player/SwarmController
	swarm_controller.strength_changed.connect(_on_strength_changed)
	_on_strength_changed(swarm_controller.strength_current, swarm_controller.strength_cap())

func _on_strength_changed(current: float, cap: float) -> void:
	strength_label.text = "Strength: %d / %d" % [int(current), int(cap)]
```

- [ ] **Step 3: Playtest checkpoint**

Run the main scene (F5). The new "Strength: 100 / 100" label should appear and stay steady at the cap (nothing depletes it yet — that's Task 6). Temporarily call `swarm_controller.deplete_strength(30)` once from `game.gd`'s `_ready()` (after connecting the signal) to confirm the label updates to "Strength: 70 / 100" and then climbs back to 100 over ~7.5 seconds at 4/sec. Remove that temporary call once confirmed.

- [ ] **Step 4: Commit**

```bash
git add swarm_controller.gd game.tscn game.gd
git commit -m "Add Strength Pool with passive regen to a level-scaled cap"
```

---

## Task 5: `CastPattern` + `CastField` (Hunt only) — wire `cast` to the swarm

**Files:**
- Create: `cast_pattern.gd`
- Create: `cast_field.gd`
- Modify: `swarm_controller.gd`
- Modify: `swarm_agent.gd`
- Modify: `player.gd`

This is the spine of the feature: pressing `cast` now sends the swarm surging toward the cast direction instead of spawning a `rift_projectile`. Only the **Hunt** pattern is implemented in this task — the other three reuse this same pipeline in Tasks 9–11.

- [ ] **Step 1: Write `CastPattern`**

Write `cast_pattern.gd`:

```gdscript
extends RefCounted
class_name CastPattern

enum Shape { PULSE, CONE, TANGENTIAL, WAYPOINT }

var id: String
var display_name: String
var shape: int
var field_strength: float
var speed_multiplier: float
var cone_half_angle: float   # radians; used by CONE (Scatter)
var curve_bias: float        # used by TANGENTIAL (Loop Hunt)
var waypoint_count: int      # used by WAYPOINT (Bounce Hunt)

func _init(p_id: String, p_display_name: String, p_shape: int, p_field_strength: float = 1.0,
		p_speed_multiplier: float = 1.0, p_cone_half_angle: float = 0.6,
		p_curve_bias: float = 1.0, p_waypoint_count: int = 3) -> void:
	id = p_id
	display_name = p_display_name
	shape = p_shape
	field_strength = p_field_strength
	speed_multiplier = p_speed_multiplier
	cone_half_angle = p_cone_half_angle
	curve_bias = p_curve_bias
	waypoint_count = p_waypoint_count
```

- [ ] **Step 2: Write `CastField` with PULSE sampling only (Hunt's shape)**

Write `cast_field.gd`:

```gdscript
extends Node2D
class_name CastField

@export var lifetime: float = 1.2
@export var radius: float = 260.0

var direction: Vector2 = Vector2.RIGHT
var anchor: Vector2 = Vector2.ZERO
var pattern: CastPattern = null

var _age: float = 0.0

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()

## Returns [direction: Vector2, strength: float] for the given world position.
## strength is 0 once the field has nothing left to offer (out of range or expired).
func sample(world_pos: Vector2) -> Array:
	match pattern.shape:
		CastPattern.Shape.PULSE:
			return [direction, _falloff(global_position, world_pos) * pattern.field_strength]
		_:
			return [direction, 0.0]

func _falloff(reference_point: Vector2, world_pos: Vector2) -> float:
	var dist := world_pos.distance_to(reference_point)
	var distance_factor := clamp(1.0 - dist / radius, 0.0, 1.0)
	var age_factor := clamp(1.0 - _age / lifetime, 0.0, 1.0)
	return distance_factor * age_factor
```

- [ ] **Step 3: Add directed steering to `SwarmAgent`**

In `swarm_agent.gd`, replace the placeholder `_directed_steering`:

```gdscript
func _directed_steering() -> Vector2:
	if cast_field == null or not is_instance_valid(cast_field):
		state = State.IDLE
		return Vector2.ZERO
	var sample: Array = cast_field.sample(global_position)
	var sample_direction: Vector2 = sample[0]
	var sample_strength: float = sample[1]
	if sample_strength <= 0.0:
		state = State.IDLE
		cast_field = null
		return Vector2.ZERO
	return sample_direction * directed_speed * sample_strength
```

Add a setter the controller will call:

```gdscript
func enter_directed(field, speed_multiplier: float) -> void:
	state = State.DIRECTED
	cast_field = field
	directed_speed = DIRECTED_BASE_SPEED * speed_multiplier
```

- [ ] **Step 4: Add `cast()` to `SwarmController`**

In `swarm_controller.gd`, add the pattern list and a `cast()` entry point:

```gdscript
var all_patterns: Array = []
var unlocked_pattern_count: int = 1
var active_pattern_index: int = 0
var active_field: CastField = null

func _build_patterns() -> void:
	all_patterns = [
		CastPattern.new("hunt", "Hunt", CastPattern.Shape.PULSE, 1.0, 1.6),
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
```

Call `_build_patterns()` from `_ready()` — add the line `_build_patterns()` as the first line of the existing `_ready()` function.

- [ ] **Step 5: Replace the projectile spawn in `player.gd` with a swarm cast**

In `player.gd`:
1. Delete line 28 (`var projectile_scene = preload("res://scenes/rift_projectile.tscn")`) and line 29 (`var cast_projectile_pending = false`).
2. Add near the top (with the other `@onready` vars): `@onready var swarm_controller = $SwarmController`
3. Replace the line `cast_projectile_pending = true` (inside the `if Input.is_action_just_pressed("cast"):` block) with:

```gdscript
		swarm_controller.cast(last_direction)
```

4. Delete the entire "SPAWN PROJECTILE MID-CAST" block (lines 74–85: the `if is_casting and cast_projectile_pending and cast_timer <= 0.1:` block and its body).

The cast now fires the instant the button is pressed (at the start of the wind-up animation) rather than mid-animation; `CAST_DURATION`/`is_casting`/`cast_timer` stay exactly as they are, since they only drive the animation.

- [ ] **Step 6: Playtest checkpoint**

Run the main scene (F5). Move so you're facing the `PlaceholderEnemy`, then press `cast` (X). The swarm should break orbit and surge as a tight pack in the direction you're facing, then drift back into orbit a little over a second later (when the field expires and `sample_strength` drops to 0). Try casting while facing away from the enemy too — the swarm should surge in that empty direction and then return to orbiting you. No errors in the Output panel.

- [ ] **Step 7: Commit**

```bash
git add cast_pattern.gd cast_field.gd swarm_controller.gd swarm_agent.gd player.gd
git commit -m "Wire cast input to swarm via CastField/CastPattern (Hunt only)"
```

---

## Task 6: Combat resolution — DOT to targets, counter-damage to the swarm

**Files:**
- Modify: `swarm_agent.gd`

Closes the loop the spec calls out in section 6: agents damage what they touch, tough things damage agents back (depleting the Strength Pool you built in Task 4).

- [ ] **Step 1: Implement `_resolve_combat` and `take_counter_damage`**

In `swarm_agent.gd`, replace the placeholder `_resolve_combat`:

```gdscript
func _resolve_combat(delta: float) -> void:
	for area in get_overlapping_areas():
		if area.is_in_group("swarm_targets") and area.has_method("take_damage"):
			area.take_damage(DOT_PER_SECOND * delta)

func take_counter_damage(amount: float) -> void:
	if swarm_controller != null:
		swarm_controller.deplete_strength(amount)
```

- [ ] **Step 2: Playtest checkpoint**

Run the main scene (F5). Cast (X) toward the `PlaceholderEnemy` and hold position so agents stay overlapping it:
- The enemy's "HP: 100/100" label should tick down (each overlapping agent does `6 * delta` DOT — with several agents engaged you'll see it drop noticeably faster than the old 4/sec counter-damage tick).
- The "Strength: x / 100" label should simultaneously start dropping by 4 roughly once per second (the enemy's counter-damage timer hitting the engaged agents).
- Step away — the enemy stops losing HP (no more overlap) and, after a few seconds without engagement, your Strength readout should climb back toward 100 via passive regen.
- If you keep the swarm engaged long enough, the enemy's HP should hit 0 and `queue_free()` — it disappears.

- [ ] **Step 3: Commit**

```bash
git add swarm_agent.gd
git commit -m "Resolve swarm combat: DOT to targets, counter-damage depletes Strength Pool"
```

---

## Task 7: `Eminate` → recall the swarm

**Files:**
- Modify: `swarm_controller.gd`
- Modify: `player.gd`

- [ ] **Step 1: Add `recall()` to `SwarmController`**

In `swarm_controller.gd`:

```gdscript
func recall() -> void:
	directive_state = DirectiveState.ORBIT
	if active_field != null and is_instance_valid(active_field):
		active_field.queue_free()
	active_field = null
	for agent in agents:
		agent.return_to_idle()
```

- [ ] **Step 2: Call it from `player.gd`**

In the `if Input.is_action_just_pressed("eminate"):` block, after `eminate_timer = 1`, add:

```gdscript
		swarm_controller.recall()
```

- [ ] **Step 3: Playtest checkpoint**

Run the main scene (F5). Cast (X) toward the enemy, then — before the field would naturally expire — press `eminate` (Z). The swarm should immediately abandon the chase and snap back into orbiting you, and the "Eminate" animation should play (that wiring already existed). Confirm pressing `eminate` with the swarm already idle/orbiting is harmless (no errors, swarm just stays in orbit).

- [ ] **Step 4: Commit**

```bash
git add swarm_controller.gd player.gd
git commit -m "Wire eminate input to SwarmController.recall()"
```

---

## Task 8: `Attack` → personal melee strike

**Files:**
- Modify: `Player.tscn`
- Modify: `player.gd`

Gives the player a self-defense option independent of the swarm, per spec section 2.

- [ ] **Step 1: Add a melee hitbox to `Player.tscn`**

Open `Player.tscn`, select the `Player` root, add a child `Area2D` named `MeleeHitbox`, and give it a child `CollisionShape2D` with a `CircleShape2D` of radius `28.0`, positioned at the player's center (`position = Vector2(0, 0)`). Leave it as-is — `player.gd` will query its overlaps directly rather than connecting signals, so no script is needed on it.

- [ ] **Step 2: Trigger the strike from `player.gd`**

Add an `@onready` reference near the others: `@onready var melee_hitbox: Area2D = $MeleeHitbox`

In the `if Input.is_action_just_pressed("Attack"):` block, after `attack_timer = 0.5`, add:

```gdscript
		_perform_melee_strike()
```

Add the new function (anywhere below `_physics_process`, e.g. right after it ends):

```gdscript
const MELEE_DAMAGE := 18.0

func _perform_melee_strike() -> void:
	for area in melee_hitbox.get_overlapping_areas():
		if area.is_in_group("swarm_targets") and area.has_method("take_damage"):
			area.take_damage(MELEE_DAMAGE)
```

- [ ] **Step 3: Playtest checkpoint**

Run the main scene (F5). Walk the player directly adjacent to the `PlaceholderEnemy` (close enough to overlap the 28px hitbox) and press `Attack` (C). The "Attack" animation should play and the enemy's HP should drop by 18 instantly — independent of where the swarm currently is (try this with the swarm off chasing elsewhere via a fresh `cast` first, to confirm melee works without it). Pressing `Attack` while not adjacent to anything should do nothing but play the animation.

- [ ] **Step 4: Commit**

```bash
git add Player.tscn player.gd
git commit -m "Add personal melee strike to Attack input"
```

---

## Task 9: Scatter pattern (cone shape)

**Files:**
- Modify: `cast_field.gd`
- Modify: `swarm_controller.gd`

First of the three remaining patterns — adds the CONE sampling branch and registers Scatter.

- [ ] **Step 1: Implement CONE sampling in `CastField`**

In `cast_field.gd`, extend the `match` in `sample()`:

```gdscript
func sample(world_pos: Vector2) -> Array:
	match pattern.shape:
		CastPattern.Shape.PULSE:
			return [direction, _falloff(global_position, world_pos) * pattern.field_strength]
		CastPattern.Shape.CONE:
			return _sample_cone(world_pos)
		_:
			return [direction, 0.0]

func _sample_cone(world_pos: Vector2) -> Array:
	var to_pos := world_pos - global_position
	if to_pos.length() < 0.001:
		return [direction, pattern.field_strength]
	var outward := to_pos.normalized()
	var angle_diff: float = absf(direction.angle_to(outward))
	var cone_factor := clamp(1.0 - angle_diff / pattern.cone_half_angle, 0.0, 1.0)
	return [outward, _falloff(global_position, world_pos) * cone_factor * pattern.field_strength]
```

- [ ] **Step 2: Register the Scatter pattern**

In `swarm_controller.gd`'s `_build_patterns()`, add it to the array:

```gdscript
		CastPattern.new("scatter", "Scatter", CastPattern.Shape.CONE, 0.7, 1.0, 0.9),
```

(Keep `unlocked_pattern_count = 1` for now — Task 13 wires up progressive unlocking and cycling. For this playtest, temporarily set `active_pattern_index = 1` in `_ready()` after `_build_patterns()`, run the test, then set it back to `0`.)

- [ ] **Step 3: Playtest checkpoint**

With `active_pattern_index` temporarily forced to `1`, run the main scene (F5) and cast (X). Instead of a tight beeline, the swarm should fan out into a wide cone in the cast direction — agents on the cone's edges visibly diverge from the center line rather than clumping. Revert `active_pattern_index` to `0` when done.

- [ ] **Step 4: Commit**

```bash
git add cast_field.gd swarm_controller.gd
git commit -m "Add Scatter cast pattern (cone-shaped field)"
```

---

## Task 10: Loop Hunt pattern (tangential/orbiting shape)

**Files:**
- Modify: `cast_field.gd`
- Modify: `swarm_controller.gd`

- [ ] **Step 1: Implement TANGENTIAL sampling in `CastField`**

Add to the `match` in `sample()`:

```gdscript
		CastPattern.Shape.TANGENTIAL:
			return _sample_tangential(world_pos)
```

And the helper:

```gdscript
func _sample_tangential(world_pos: Vector2) -> Array:
	var to_anchor := anchor - world_pos
	if to_anchor.length() < 0.001:
		return [direction, pattern.field_strength]
	var radial := to_anchor.normalized()
	var tangent := radial.orthogonal()
	var blended := (radial + tangent * pattern.curve_bias).normalized()
	return [blended, _falloff(anchor, world_pos) * pattern.field_strength]
```

(Blending the inward pull toward the anchor with a perpendicular component is what produces the arc-then-orbit motion the spec describes — agents get pulled toward the anchor but keep curving past it instead of stopping on it, which naturally settles into an orbit. No separate "follow-up" state machine is needed.)

- [ ] **Step 2: Register the Loop Hunt pattern**

```gdscript
		CastPattern.new("loop_hunt", "Loop Hunt", CastPattern.Shape.TANGENTIAL, 1.0, 1.1, 0.6, 1.0),
```

Temporarily force `active_pattern_index = 2` for this playtest (revert after).

- [ ] **Step 3: Playtest checkpoint**

Cast (X) toward the `PlaceholderEnemy` (so it resolves as the anchor — see the anchor-resolution rule in the spec, implemented back in Task 5's `cast()`). The swarm should arc out past the enemy and curve around it rather than stopping dead-on — visibly encircling it from multiple sides over the field's lifetime. Cast toward empty space and confirm it still arcs around the fallback anchor point (220px out along your facing direction) rather than erroring.

- [ ] **Step 4: Commit**

```bash
git add cast_field.gd swarm_controller.gd
git commit -m "Add Loop Hunt cast pattern (tangential orbiting field)"
```

---

## Task 11: Bounce Hunt pattern (waypoint chain)

**Files:**
- Modify: `cast_field.gd`
- Modify: `swarm_controller.gd`

- [ ] **Step 1: Implement waypoint generation and WAYPOINT sampling in `CastField`**

Add fields near the top of `cast_field.gd`:

```gdscript
const WAYPOINT_HOLD_TIME := 0.35
const WAYPOINT_SIDE_OFFSET := 70.0

var waypoints: Array = []
var _waypoint_index: int = 0
var _waypoint_timer: float = 0.0
```

Update `_ready` (the script doesn't have one yet — add it) to build the chain when relevant:

```gdscript
func _ready() -> void:
	if pattern.shape == CastPattern.Shape.WAYPOINT:
		_build_waypoints()
```

Add the builder and advance-on-timer logic — extend `_physics_process`:

```gdscript
func _physics_process(delta: float) -> void:
	_age += delta
	if pattern.shape == CastPattern.Shape.WAYPOINT and _waypoint_index < waypoints.size() - 1:
		_waypoint_timer += delta
		if _waypoint_timer >= WAYPOINT_HOLD_TIME:
			_waypoint_timer = 0.0
			_waypoint_index += 1
	if _age >= lifetime:
		queue_free()

func _build_waypoints() -> void:
	var start := global_position
	var perpendicular := (anchor - start).orthogonal().normalized()
	waypoints.clear()
	for i in range(1, pattern.waypoint_count + 1):
		var t := float(i) / float(pattern.waypoint_count)
		var point := start.lerp(anchor, t)
		var side := -1.0 if i % 2 == 0 else 1.0
		point += perpendicular * side * WAYPOINT_SIDE_OFFSET * (1.0 - t)
		waypoints.append(point)
```

Add the sampling branch to `sample()`:

```gdscript
		CastPattern.Shape.WAYPOINT:
			return _sample_waypoint(world_pos)
```

And its helper:

```gdscript
func _sample_waypoint(world_pos: Vector2) -> Array:
	if waypoints.is_empty():
		return [direction, 0.0]
	var target: Vector2 = waypoints[_waypoint_index]
	var to_target := target - world_pos
	if to_target.length() < 0.001:
		return [direction, pattern.field_strength]
	return [to_target.normalized(), _falloff(target, world_pos) * pattern.field_strength]
```

Note: `_ready()` runs once when the field is added to the tree, but `cast()` in `SwarmController` sets `field.global_position` *after* calling `add_child`, and `_build_waypoints()` reads `global_position` as its start point. To keep the start point correct, change the `cast()` order in `swarm_controller.gd` so the position is set **before** adding to the tree:

```gdscript
func cast(direction: Vector2, target: Node2D = null) -> void:
	var pattern := active_pattern()
	var field := CastField.new()
	field.pattern = pattern
	field.direction = direction.normalized()
	field.anchor = target.global_position if target != null else player.global_position + direction.normalized() * 220.0
	field.global_position = player.global_position
	# Sibling of Player (child of Game) — see the comment in the original cast()
	# from Task 5: parenting to a moving node would drag the field along with it.
	player.get_parent().add_child(field)
	active_field = field
	directive_state = DirectiveState.CASTING
	for agent in agents:
		agent.enter_directed(field, pattern.speed_multiplier)
```

(`global_position` can be set on a `Node2D` before it's in the tree — Godot stores it as `position` relative to a null parent transform, which is equivalent to world position until it's reparented. Since we then add it directly under the same parent as the player, this is correct.)

- [ ] **Step 2: Register the Bounce Hunt pattern**

```gdscript
		CastPattern.new("bounce_hunt", "Bounce Hunt", CastPattern.Shape.WAYPOINT, 1.0, 1.2, 0.6, 1.0, 3),
```

Temporarily force `active_pattern_index = 3` for this playtest (revert after).

- [ ] **Step 3: Playtest checkpoint**

Cast (X) toward the enemy. The swarm should zigzag — visibly changing direction every ~0.35s as it advances toward each waypoint in turn — rather than moving in a straight line or smooth curve, eventually converging on the enemy/anchor. Confirm it doesn't get stuck oscillating on the first waypoint (the `_waypoint_index` should advance through all of them before the field expires at `lifetime = 1.2s` with `WAYPOINT_HOLD_TIME = 0.35s` × 3 waypoints ≈ 1.05s).

- [ ] **Step 4: Commit**

```bash
git add cast_field.gd swarm_controller.gd
git commit -m "Add Bounce Hunt cast pattern (zigzag waypoint chain)"
```

---

## Task 12: Aiming modes — directional, mouse-aim, lock-on

**Files:**
- Modify: `player.gd`
- Modify: `swarm_controller.gd`

Implements spec section 3's three switchable aiming modes and the anchor-resolution rule for Loop Hunt / Bounce Hunt.

- [ ] **Step 1: Add a `find_nearest_target` helper to `SwarmController`**

```gdscript
const TARGET_SEARCH_RADIUS := 320.0

func find_nearest_target(from_position: Vector2, preferred_direction: Vector2 = Vector2.ZERO, max_angle: float = TAU) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for target in get_tree().get_nodes_in_group("swarm_targets"):
		if not is_instance_valid(target):
			continue
		var to_target: Vector2 = target.global_position - from_position
		var dist := to_target.length()
		if dist > TARGET_SEARCH_RADIUS or dist >= best_dist:
			continue
		if preferred_direction != Vector2.ZERO:
			if absf(preferred_direction.angle_to(to_target.normalized())) > max_angle:
				continue
		best = target
		best_dist = dist
	return best
```

- [ ] **Step 2: Add an aiming-mode setting and resolver to `player.gd`**

Add near the top, with the other vars:

```gdscript
enum AimMode { DIRECTIONAL, MOUSE, LOCK_ON }
var aim_mode: int = AimMode.DIRECTIONAL
```

Add the resolver function (this is what Task 5's `cast` call site will use instead of the bare `last_direction`):

```gdscript
## Returns [direction: Vector2, target: Node2D (or null)] for the active aim mode.
func _resolve_cast_aim() -> Array:
	match aim_mode:
		AimMode.MOUSE:
			var to_cursor := get_global_mouse_position() - global_position
			if to_cursor.length() < 0.001:
				return [last_direction, null]
			var direction := to_cursor.normalized()
			return [direction, swarm_controller.find_nearest_target(global_position, direction, 0.5)]
		AimMode.LOCK_ON:
			var target := swarm_controller.find_nearest_target(global_position)
			if target != null:
				return [(target.global_position - global_position).normalized(), target]
			return [last_direction, null]
		_:
			return [last_direction, swarm_controller.find_nearest_target(global_position, last_direction, 0.5)]
```

(`max_angle = 0.5` radians ≈ 28.6° defines "within the cast direction/cone" for resolving an anchor in directional/mouse modes, per the spec's anchor-resolution rule — narrow enough that the swarm doesn't lock onto something far off to the side just because it's the nearest thing on the map.)

- [ ] **Step 3: Use the resolver at the cast call site**

In the `if Input.is_action_just_pressed("cast"):` block, replace `swarm_controller.cast(last_direction)` (added in Task 5 step 5) with:

```gdscript
		var aim := _resolve_cast_aim()
		swarm_controller.cast(aim[0], aim[1])
```

- [ ] **Step 4: Add an input action to switch aim modes**

Open `project.godot`, find the `[input]` section, and insert this new action block immediately after the closing `}` of the existing `Attack={...}` block (before the blank line that precedes `[rendering]`):

```
toggle_aim_mode={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":66,"key_label":0,"unicode":98,"location":0,"echo":false,"script":null)
]
}
```

(This binds `toggle_aim_mode` to the `B` key — physical keycode 66 / unicode 98, following the same pattern as the existing `cast`/`eminate`/`Attack` entries.)

- [ ] **Step 5: Wire the toggle into `player.gd`**

In `_physics_process`, alongside the other `Input.is_action_just_pressed` checks, add:

```gdscript
	if Input.is_action_just_pressed("toggle_aim_mode"):
		aim_mode = (aim_mode + 1) % 3
		print("Aim mode: ", AimMode.keys()[aim_mode])
```

(The `print` is a deliberate temporary readout — there's no settings UI yet per spec section 5's scope notes; swap this for a real settings toggle when one exists. Leave it in for now so the mode change is observable in the Output panel during the playtest below and beyond.)

- [ ] **Step 6: Playtest checkpoint**

Run the main scene (F5).
- **Directional** (default): face the enemy and cast — swarm should target it (anchor-dependent patterns like Loop Hunt curve around it). Face away and cast — swarm should go in your facing direction with no anchor lock.
- Press `B` (toggle to **Mouse**): move your mouse cursor over the enemy and cast — the swarm should head toward the cursor position and lock onto the enemy as anchor. Move the cursor to empty space and cast — swarm heads toward the cursor with no anchor.
- Press `B` again (toggle to **Lock-on**): regardless of where you're facing or pointing, casting should always send the swarm at the nearest `SwarmTarget` (the enemy, if within 320px).
- Press `B` a third time to confirm it cycles back to **Directional**. Watch the Output panel to confirm each press logs the new mode name.

- [ ] **Step 7: Commit**

```bash
git add player.gd swarm_controller.gd project.godot
git commit -m "Add directional/mouse/lock-on aiming modes with anchor resolution"
```

---

## Task 13: Cast-pattern cycling + UI label + progressive unlocking

**Files:**
- Modify: `player.gd`
- Modify: `swarm_controller.gd`
- Modify: `game.tscn` / `game.gd`

Wires up the "Current Cast: X" label that was already sitting in the scene as a clear signal the original developer anticipated this system (per spec section 1), and the progressive-unlock structure spec section 3 calls for (exact unlock thresholds are explicitly out of scope — this provides the mechanism with a sane default).

- [ ] **Step 1: Add cycling and a pattern-changed signal to `SwarmController`**

Add a signal near `strength_changed`:

```gdscript
signal pattern_changed(pattern: CastPattern)
```

Add the cycling function:

```gdscript
func cycle_pattern() -> void:
	if unlocked_pattern_count <= 1:
		return
	active_pattern_index = (active_pattern_index + 1) % unlocked_pattern_count
	pattern_changed.emit(active_pattern())

func unlock_next_pattern() -> void:
	if unlocked_pattern_count < all_patterns.size():
		unlocked_pattern_count += 1
```

Emit the initial state at the end of `_ready()` (after the agent-spawn loop): `pattern_changed.emit(active_pattern())`

- [ ] **Step 2: Add an input action for cycling**

In `project.godot`'s `[input]` section, add another block right after the `toggle_aim_mode` block you added in Task 12 step 4:

```
cycle_cast_pattern={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":86,"key_label":0,"unicode":118,"location":0,"echo":false,"script":null)
]
}
```

(Binds `cycle_cast_pattern` to the `V` key — physical keycode 86 / unicode 118.)

- [ ] **Step 3: Wire the input in `player.gd`**

In `_physics_process`, alongside the other input checks:

```gdscript
	if Input.is_action_just_pressed("cycle_cast_pattern"):
		swarm_controller.cycle_pattern()
```

- [ ] **Step 4: Drive the existing label from the signal**

Open `game.tscn`'s attached script (`game.gd`, created in Task 4 step 2). Add a reference and connection in `_ready`:

```gdscript
@onready var cast_label: Label = $CanvasLayer/Label

func _ready() -> void:
	var swarm_controller := $Player/SwarmController
	swarm_controller.strength_changed.connect(_on_strength_changed)
	swarm_controller.pattern_changed.connect(_on_pattern_changed)
	_on_strength_changed(swarm_controller.strength_current, swarm_controller.strength_cap())
	_on_pattern_changed(swarm_controller.active_pattern())

func _on_pattern_changed(pattern: CastPattern) -> void:
	cast_label.text = "Current Cast: %s" % pattern.display_name
```

(`_on_strength_changed` already exists from Task 4 — you're adding `_on_pattern_changed` alongside it.)

- [ ] **Step 5: Unlock all four patterns for testing, with a clear seam for real progression later**

In `swarm_controller.gd`'s `_ready()`, after `_build_patterns()`, add a single clearly-marked line:

```gdscript
	unlocked_pattern_count = all_patterns.size()  # TODO(progression): replace with real unlock-by-level data; see spec section 5
```

This isn't a placeholder for *missing functionality* — `cycle_pattern()` and `unlock_next_pattern()` both work correctly right now — it's an explicit, documented stand-in for the progression *curve* (which patterns unlock at which level), which the spec explicitly scopes out (section 5: "Progression/unlock curve specifics"). Without this line you'd be stuck testing only Hunt; `unlock_next_pattern()` is what a future leveling system will call instead.

- [ ] **Step 6: Playtest checkpoint**

Run the main scene (F5). The "Current Cast: X" label should read "Current Cast: Hunt" at start (overwriting the old hardcoded "Scatter" placeholder text). Press `V` repeatedly — the label should cycle through "Hunt" → "Scatter" → "Loop Hunt" → "Bounce Hunt" → back to "Hunt", and casting (X) after each press should visibly produce that pattern's movement shape (verified individually in Tasks 5/9/10/11 — this step confirms *switching* between them works and the label always matches what actually fires).

- [ ] **Step 7: Commit**

```bash
git add player.gd swarm_controller.gd project.godot game.tscn game.gd
git commit -m "Wire cast-pattern cycling to existing UI label with unlock seam"
```

---

## Task 14: Remove the obsolete `rift_projectile`

**Files:**
- Delete: `rift_projectile.gd`
- Delete: `rift_projectile.tscn`

The spec (section 2) calls this out explicitly: these files become unused once Task 5 replaces the projectile spawn with the swarm-direction call, and should be deleted rather than left as dead code.

- [ ] **Step 1: Confirm nothing still references them**

```bash
grep -rn "rift_projectile" --include="*.gd" --include="*.tscn" --include="*.godot" .
```

Expected: no output (Task 5 already removed the `preload` and instantiation from `player.gd`; `game.tscn` does not reference it — only `rift_projectile.tscn` referenced `game.tscn`, not the other way around).

- [ ] **Step 2: Delete the files**

```bash
git rm rift_projectile.gd rift_projectile.tscn
```

- [ ] **Step 3: Playtest checkpoint**

Run the main scene (F5) end to end one more time: move, dash, cast through all four patterns (cycling with `V`), eminate mid-cast, melee-attack the enemy, and watch the Strength Pool deplete and regen. No missing-resource errors should appear in the Output panel (which would indicate something still pointed at the deleted files).

- [ ] **Step 4: Commit**

```bash
git commit -m "Remove obsolete rift_projectile, fully replaced by swarm cast system"
```

---

## Coverage Check (spec → tasks)

- §1 Core loop (cast/eminate/attack roles, Strength Pool) → Tasks 5, 7, 8, 4/6
- §2 `SwarmController`/`SwarmAgent`/`CastField`/`CastPattern`/`SwarmTarget`/`PlaceholderEnemy` → Tasks 1–3, 5; player.gd changes → Tasks 5, 7, 8, 12, 13
- §3 Four cast patterns + anchor resolution + unlock/cycling + three aiming modes → Tasks 5, 9, 10, 11, 12, 13
- §4 Combat resolution + Strength Pool rules (damage out, counter-damage in, regen, foraging seam) → Tasks 4, 6 (foraging itself is explicitly out of scope per spec §5 — not built here)
- §5 Out of scope → respected: no final enemy AI, no foraging implementation, no art/VFX beyond placeholder shapes, no progression-curve numbers (Task 13 only adds the unlock *mechanism*)
- §6 Testing & validation path → covered end-to-end by the playtest checkpoints in Tasks 5, 6, 7 (cast → DOT/counter-damage → recall → regen)
