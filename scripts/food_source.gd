extends Node2D
class_name FoodSource

## A food pile the swarm can harvest. Position (world coords) maps to a grid
## cell; ants pick up one unit when they step within `radius_cells`.

## Global kill-switch for the whole food system. While false, food does not
## exist in any mode: piles never register with the world, so none are spawned,
## drawn, or harvested. The generators still compute food positions (preserving
## the dormant placement hook and level determinism), so flipping this back to
## true restores food everywhere at once.
const ENABLED := false

@export var amount: int = 200
@export var radius_cells: int = 3

var cell_pos: Vector2i = Vector2i.ZERO


func _ready() -> void:
	if not ENABLED:
		queue_free()
		return
	add_to_group("food_sources")
	var world := get_parent()
	if world is SwarmWorld:
		cell_pos = world.world_to_cell(global_position)
