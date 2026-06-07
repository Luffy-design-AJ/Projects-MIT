# Swarm Combat Mode — Design Spec

**Date:** 2026-06-07
**Context:** Porting the emergent-pheromone concept from the "Ant Lab" HTML simulation (`Ant Game v5.txt`) into the existing Godot project (`project.godot`, `player.gd`, `game.tscn`), reimagined as an active combat system rather than a passive puzzle/observation sim.

## 1. Core Concept & Loop

The player commands a **personal swarm** — a horde of dozens of ants that follows/orbits them like a companion cloud. The swarm *is* the player's primary weapon:

- **Cast** sends the swarm hunting in a chosen direction with a chosen movement pattern. On contact, the swarm deals damage-over-time to anything it reaches.
- **Eminate** recalls the swarm to regroup/orbit the player — a defensive reset.
- **Attack** is a separate personal melee strike for close-range self-defense when the swarm is elsewhere or depleted.

The swarm carries a **Strength Pool** (its size/power): it depletes when worn down by tougher enemies or hazards, regenerates passively up to a level-scaling cap, and can temporarily exceed that cap through foraging.

This replaces the current placeholder behavior of `cast` (which spawns a generic `rift_projectile`) and gives the previously inert `eminate`/`Attack` stubs concrete purposes. The existing UI label "Current Cast: Scatter" in `game.tscn` already anticipated a cast-mode system — this spec wires that up.

## 2. Architecture & Components

Built on top of the existing `CharacterBody2D` player and `game.tscn` scene tree:

### `SwarmController` (new node, child of/sibling to Player)
Owns:
- The collection of `SwarmAgent` instances
- The Strength Pool (current value, level-scaled cap, regen rate)
- Current directive state machine: `Idle/Orbit → Cast-Active → Recalling`
- Progression data: which cast patterns are unlocked, current cap level

### `SwarmAgent` (new lightweight scene/script)
One ant. Steering-based (no per-agent diffusion grid):
- **Idle:** orbits/trails the player with separation + cohesion + light noise (organic cloud movement)
- **Directed:** seeks the active `CastField`'s sampled gradient, with pattern-specific modifiers (speed boost, spread, curve bias, waypoint chasing)
- **Combat:** on overlap with a `SwarmTarget`, applies its share of DOT; takes its share of counter-damage from tough targets/hazards (feeds Strength Pool depletion)

Target count: dozens of individual agents (not a particle mass) — enough to read as "a swarm" while staying performant and tunable.

### `CastField` (new lightweight resource/node)
A temporary, decaying directional gradient spawned at cast-time. Agents sample it as a `(direction_vector, strength)` pair based on proximity/distance-falloff — **not** a full grid diffusion simulation. This is the "hybrid" approach: keeps the *feel* of "follow the scent" from Ant Lab without porting its computationally heavy scalar-field engine.

Decays over a short lifetime; if agents reach its source/anchor before it expires, pattern-specific follow-up behavior takes over (e.g., orbiting for Loop Hunt, chaining to the next waypoint for Bounce Hunt).

### `CastPattern` (data definitions, one per mode)
Defines how a `CastField` is shaped and how `SwarmAgent`s interpret it. See section 3.

### `SwarmTarget` (interface/contract)
Minimal contract any engageable entity implements:
- `take_damage(amount: float)`
- `get_position() -> Vector2`
- Detectable via proximity (e.g., a group tag or detection `Area2D`)

### `PlaceholderEnemy` (new minimal scene/script)
A simple HP-bearing entity implementing `SwarmTarget`, used to validate detection, contact DOT, and Strength Pool depletion end-to-end. Not final enemy design — just a test dummy (static or simple wandering, visible HP).

### Player changes (`player.gd`)
- **Cast** input now: (a) determines direction/anchor via the active aiming mode, (b) tells `SwarmController` to spawn a `CastField` shaped by the currently-selected `CastPattern`. The existing `rift_projectile` spawn is replaced by this swarm-direction call.
- **Cast-mode cycling**: a button/key cycles through *unlocked* patterns only; new patterns unlock through progression (UI label updates to reflect current selection — reusing the existing "Current Cast: X" label).
- **Eminate** now calls `SwarmController.recall()` — swarm breaks off whatever it's doing and returns to orbit the player.
- **Attack** now performs a personal melee strike (hitbox + damage), independent of the swarm.
- **Aiming mode** becomes a player-level setting (see section 3) affecting how cast direction/anchor is computed.

## 3. Cast Pattern Mechanics

| Pattern | `CastField` shape | Agent behavior |
|---|---|---|
| **Hunt** | Narrow, fast directional pulse along cast direction | Agents break orbit and beeline toward the field with elevated speed/cohesion — tight, fast pursuit pack |
| **Scatter** | Wide cone, lower per-agent pull strength | Agents fan out across the cone's width, sweeping a broad area — area denial / hits groups |
| **Loop Hunt** | Field anchored near the target/point that exerts a *tangential* (curving) pull rather than radial | Agents arc outward then orbit/encircle the anchor from multiple sides — surrounds rather than charges head-on |
| **Bounce Hunt** | Chain of short-lived sequential waypoint fields (zigzag) | Agents chase each waypoint in turn, ricocheting toward the final target — covers ground unpredictably, can chain across multiple enemies |

**Unlock & switching:** Patterns unlock progressively through the game. The player cycles through *currently unlocked* patterns with a dedicated input (button/scroll), and the active pattern is shown via the existing UI label.

**Aiming modes** (all three available; switchable in settings):
1. **Directional** — uses facing/last-moved direction, matching the existing input scheme (`last_direction` already tracked in `player.gd`)
2. **Mouse-aim / free-aim** — direction computed from cursor position relative to player
3. **Lock-on** — automatically targets nearest/selected `SwarmTarget`

The active aiming mode determines how the `CastField`'s direction or anchor point is computed at cast-time; the rest of the pipeline (field → pattern shaping → agent steering) is unaffected by which aiming mode is active.

## 4. Combat Resolution & Strength Pool

- **Damage to targets:** On contact/overlap, each engaged `SwarmAgent` ticks DOT against the `SwarmTarget` it's touching (`take_damage`)
- **Damage to swarm:** Tougher enemies and hazards (e.g. fire) deal counter-damage back to engaged agents, depleting the **Strength Pool**
- **Regeneration:** The pool passively regenerates over time up to a **level-scaled cap** (cap increases with player progression)
- **Foraging:** A separate action/mechanic (echoing Ant Lab's sugar-foraging theme — likely consuming defeated enemies or world resources) lets the pool temporarily exceed its normal cap
- The Strength Pool is the resource-management layer: aggressive, sustained engagement against tough enemies risks running the swarm down; the player must balance pressure with recovery (regen) and opportunism (forage)

## 5. Out of Scope (for this spec)

- Final enemy AI/design (only a `PlaceholderEnemy` test dummy is included here; real enemies plug into the `SwarmTarget` interface later)
- Foraging mechanic's exact implementation (resource sources, consumption rules) — flagged as a dependency but not detailed here
- Visual/art direction for the swarm's appearance and `CastField` VFX
- Progression/unlock curve specifics (which patterns unlock when, cap scaling numbers)

## 6. Testing & Validation

End-to-end validation path: spawn `PlaceholderEnemy` → cast in its direction with each pattern → confirm agents follow the expected shape/behavior, apply DOT, and that counter-damage depletes the Strength Pool correctly → confirm `Eminate` recalls mid-engagement → confirm regen brings the pool back to cap over time.
