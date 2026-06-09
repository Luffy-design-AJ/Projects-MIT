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
