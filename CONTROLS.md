# Controls

All bindings below are the current defaults for the playable build. Keyboard
and gamepad both work; where a gamepad mapping exists it is listed in the same
row.

> **Note:** WASD is currently mapped to **bomb reticle aiming**, not player
> movement. Player movement is **arrow keys** only.

## Movement

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Move up | `Up Arrow` | Left stick |
| Move down | `Down Arrow` | Left stick |
| Move left | `Left Arrow` | Left stick |
| Move right | `Right Arrow` | Left stick |
| Dash | `Space` | A / Cross |

## Swarm abilities

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Eminate (attract/scatter the swarm) | `Z` (hold) | LT / `axis 4` |
| Cast (hunt pheromone trail) | `X` | RT / `axis 5` |
| Cycle cast pattern | `V` | R3 |
| Cycle eminate mode (attract ↔ scatter) | `E` | L3 |
| Melee attack | `C` | Y / Triangle |
| Toggle nest pheromone (beacon) | `N` | D-pad Up |

## Bomb

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Drop bomb | `B` | B / Circle |
| Aim reticle (while aiming) | `W` `A` `S` `D` | Right stick |
| Cycle bomb mode (attract ↔ scatter) | `H` | R1 |

> **Aiming the bomb** is a two-step action: press `B` to enter aiming mode, move
> the reticle with `WASD`, then press `B` again to drop. Arrow keys still move
> the player while aiming.

## Aiming

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Cycle aim mode | `G` | R2 |

Aim modes cycle through three options, shown in the console on change:

1. **DIRECTIONAL** — casts fire in the direction you last moved.
2. **MOUSE** — casts fire toward the mouse cursor.
3. **LOCK_ON** — casts auto-target the nearest enemy.

## Progression

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Advance the mechanic ladder (`SPRAY → EMINATE → BEACON → HUNT → BOMB`) | `P` | — |
| Cycle every stage live, including `CONTROL` / `CARNAGE` / `LOCKOUT` | `F` | D-pad Down |

The game **spawns in `BOMB` mode**, so every mechanic is unlocked from the
start. `F` walks the full stage list in enum order and wraps around:
`CONTROL → CARNAGE → LOCKOUT → SPRAY → EMINATE → BEACON → HUNT → BOMB`.

Stage meaning:

| Stage | Effect |
| --- | --- |
| `CONTROL` | Direct-command mode — abilities issue orders to ants instead of stamping pheromone. |
| `CARNAGE` | Direct-command mode — every ant autonomously chases the nearest enemy. |
| `LOCKOUT` | Player input frozen; all pheromone fields zeroed so ants wander on base physics. |
| `SPRAY` | Scalar-field ladder begins. |
| `EMINATE` | Unlocks Eminate. |
| `BEACON` | Unlocks the nest pheromone beacon. |
| `HUNT` | Unlocks Cast. |
| `BOMB` | Unlocks the bomb. Top of the ladder. |

## UI

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Toggle options panel | `Tab` | L2 |
| Pause / resume | `2` | LB |
| Toggle pheromone overlay | `T` | — |

## Mouse

| Action | Effect |
| --- | --- |
| Mouse move | Aim direction in `MOUSE` aim mode. |
| Mouse click | Currently unused — all actions are keyboard/gamepad. |

The options panel captures mouse input while open (sliders, toggles, buttons).

## Card

Quick reference:

```text
Move         Arrows            Dash         Space
Eminate      Z (hold)          Cast         X
Melee        C                 Nest beacon  N
Cast pattern V                 Eminate mode E
Drop bomb    B                 Bomb aim     WASD
Bomb mode    H                 Aim mode     G
Ladder       P                 All stages   F
Options      Tab               Pause        2
Overlay      T
```
