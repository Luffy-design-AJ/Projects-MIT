extends Node
class_name GameConfig

## Selection passed from the main menu to `game.tscn`.

enum Choice { NONE, ASSASSIN, PREDATOR, FIREWALL, BROODMOTHER, SIREN }

## Sandbox = the original hand-authored arena with a single enemy choice.
## Procedural 1 = the original BSP/maze generator.
## Procedural 2 = the newer open, combo-driven arena (flat threat budget).
## Procedural 3 = the same open arena, but enemy pressure scales with how many
##                enemies the player picked instead of a flat budget.
enum Mode { SANDBOX, PROCEDURAL_1, PROCEDURAL_2, PROCEDURAL_3 }

## --- Sandbox ---
var choice: Choice = Choice.NONE

## --- Procedural ---
var mode: Mode = Mode.SANDBOX
## Selected Enemy.Type ints (order-independent; the combo shapes the layout).
var enemies: Array = []
## Base seed. The level generator mixes the combo and params into the actual
## stream, so the same (seed, combo, params) always reproduces the same level.
var level_seed: int = 1337
## Grid cell size in px: 10 = existing scale, 16/20 = coarser cells.
var cell_size: float = 10.0
var arena_size: Vector2 = Vector2(1280.0, 800.0)
## Extra generator params. Usually empty — the combo supplies the motif weights.
var gen_params: Dictionary = {}
