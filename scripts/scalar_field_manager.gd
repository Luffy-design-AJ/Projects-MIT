extends Node
class_name ScalarFieldManager

## Owns every shared scalar field in the world. All ants sample these shared
## fields; nothing is per-ant.

const FIELD_HOME_PHER := "home_pher"
const FIELD_FOOT_TRAIL := "foot_trail"
const FIELD_HUNT_PHER := "hunt_pher"
const FIELD_PLAYER_FRESH := "player_fresh"

## Per-second decay (lambda) and diffusion style, converted from the JS
## prototype's per-tick values at ~11.36 ticks/s (stepRate 0.088, see plan).
##  - homePher decays 0.9997/tick  -> 0.00342/s, JS `diffuse()` (STYLE_BLOB)
##  - playerPher  decays 0.9996/tick -> 0.00456/s, JS `diffuse()`
##  - footTrail   decays 0.9985/tick -> 0.01710/s, JS `diffuseFootTrail()`
##  - playerFresh decays 0.985/tick  -> 0.17250/s, JS `decayPlayerFresh()`
const HOME_DECAY := 0.00342
const FOOT_DECAY := 0.0171
const HUNT_DECAY := 0.00456
const FRESH_DECAY := 0.1725
const FOOT_SPREAD := 0.05

var fields: Dictionary = {}
var solid: PackedByteArray = []


func setup(p_cols: int, p_rows: int) -> void:
	fields[FIELD_HOME_PHER] = ScalarField.new(p_cols, p_rows, HOME_DECAY, ScalarField.STYLE_BLOB)
	fields[FIELD_FOOT_TRAIL] = ScalarField.new(p_cols, p_rows, FOOT_DECAY, ScalarField.STYLE_TRAIL, FOOT_SPREAD)
	fields[FIELD_HUNT_PHER] = ScalarField.new(p_cols, p_rows, HUNT_DECAY, ScalarField.STYLE_BLOB)
	fields[FIELD_PLAYER_FRESH] = ScalarField.new(p_cols, p_rows, FRESH_DECAY, ScalarField.STYLE_NONE)
	solid.resize(p_cols * p_rows)


func get_field(field_name: String) -> ScalarField:
	return fields.get(field_name)


func step(dt: float) -> void:
	for field in fields.values():
		(field as ScalarField).step(dt, solid)
