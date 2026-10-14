extends Node
class_name GameConfig

## Selection passed from the main menu to `game.tscn`.

enum Choice { NONE, ASSASSIN, PREDATOR, FIREWALL, BROODMOTHER, SIREN }

## Sandbox = the original hand-authored arena with a single enemy choice.
## Procedural = a seeded, combo-driven generated level with a multi-select combo.
enum Mode { SANDBOX, PROCEDURAL }

## --- Sandbox ---
var choice: Choice = Choice.NONE

## --- Procedural ---
var mode: Mode = Mode.SANDBOX
## Selected Enemy.Type ints (order-independent; the combo shapes the layout).
var enemies: Array = []
## Base seed. LevelGenerator mixes the combo and params into the actual stream,
## so the same (seed, combo, params) always reproduces the same level.
var level_seed: int = 1337
## Grid cell size in px: 10 = existing scale, 16/20 = coarser cells.
var cell_size: float = 10.0
var arena_size: Vector2 = Vector2(1280.0, 800.0)
## Extra generator params. Usually empty — the combo supplies the motif weights.
var gen_params: Dictionary = {}
