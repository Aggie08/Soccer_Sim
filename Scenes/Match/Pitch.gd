## Pitch.gd
## The soccer pitch with zones, goals, and boundaries
extends Node2D

# ============================================================================
# PITCH DIMENSIONS (in pixels)
# ============================================================================
const PITCH_WIDTH = 1000.0
const PITCH_HEIGHT = 700.0
const GOAL_WIDTH = 80.0
const GOAL_DEPTH = 20.0
const CENTER_CIRCLE_RADIUS = 80.0

# ============================================================================
# ZONES (For AI positioning)
# ============================================================================
enum Zone {
	DEF_LEFT,
	DEF_CENTER,
	DEF_RIGHT,
	MID_LEFT,
	MID_CENTER,
	MID_RIGHT,
	ATK_LEFT,
	ATK_CENTER,
	ATK_RIGHT
}

# Zone boundaries (calculated in _ready)
var zone_positions: Dictionary = {}

# ============================================================================
# CHILD NODES
# ============================================================================
@onready var field_bg: ColorRect = $FieldBackground
@onready var center_line: Line2D = $CenterLine
@onready var center_circle: Line2D = $CenterCircle
@onready var home_goal: Area2D = $HomeGoal
@onready var away_goal: Area2D = $AwayGoal

# ============================================================================
# INITIALIZATION
# ============================================================================
func _ready() -> void:
	_setup_pitch_visuals()
	_calculate_zones()

## Setup visual elements of the pitch
func _setup_pitch_visuals() -> void:
	# Field background
	if field_bg:
		field_bg.size = Vector2(PITCH_WIDTH, PITCH_HEIGHT)
		field_bg.position = Vector2(-PITCH_WIDTH/2, -PITCH_HEIGHT/2)
		field_bg.color = Color(0.2, 0.6, 0.2)  # Green
	
	# Center line
	if center_line:
		center_line.clear_points()
		center_line.add_point(Vector2(0, -PITCH_HEIGHT/2))
		center_line.add_point(Vector2(0, PITCH_HEIGHT/2))
		center_line.default_color = Color.WHITE
		center_line.width = 2.0
	
	# Center circle
	if center_circle:
		_draw_circle_line(center_circle, Vector2.ZERO, CENTER_CIRCLE_RADIUS)

## Draw a circle using Line2D
func _draw_circle_line(line: Line2D, center: Vector2, radius: float) -> void:
	line.clear_points()
	var points = 32
	for i in range(points + 1):
		var angle = (float(i) / points) * TAU
		var point = center + Vector2(cos(angle), sin(angle)) * radius
		line.add_point(point)
	line.default_color = Color.WHITE
	line.width = 2.0

## Calculate zone center positions for AI
func _calculate_zones() -> void:
	var zone_width = PITCH_WIDTH / 3.0
	var zone_height = PITCH_HEIGHT / 3.0
	
	# Defensive zones (left third for home)
	zone_positions[Zone.DEF_LEFT] = Vector2(-PITCH_WIDTH/2 + zone_width/2, -zone_height)
	zone_positions[Zone.DEF_CENTER] = Vector2(-PITCH_WIDTH/2 + zone_width/2, 0)
	zone_positions[Zone.DEF_RIGHT] = Vector2(-PITCH_WIDTH/2 + zone_width/2, zone_height)
	
	# Midfield zones (middle third)
	zone_positions[Zone.MID_LEFT] = Vector2(0, -zone_height)
	zone_positions[Zone.MID_CENTER] = Vector2(0, 0)
	zone_positions[Zone.MID_RIGHT] = Vector2(0, zone_height)
	
	# Attacking zones (right third for home)
	zone_positions[Zone.ATK_LEFT] = Vector2(PITCH_WIDTH/2 - zone_width/2, -zone_height)
	zone_positions[Zone.ATK_CENTER] = Vector2(PITCH_WIDTH/2 - zone_width/2, 0)
	zone_positions[Zone.ATK_RIGHT] = Vector2(PITCH_WIDTH/2 - zone_width/2, zone_height)

# ============================================================================
# POSITION HELPERS
# ============================================================================

## Get the center position of a zone
func get_zone_position(zone: Zone) -> Vector2:
	return zone_positions.get(zone, Vector2.ZERO)

## Convert a formation position string to a pitch position
## e.g., "GK" -> left side, "ST" -> right side (horizontal pitch)
func get_formation_position(position_name: String, is_home_team: bool) -> Vector2:
	var base_x_offset = PITCH_WIDTH / 2.0 - 50.0  # Keep players inside pitch
	var x_multiplier = -1.0 if is_home_team else 1.0  # Home on left (-X), away on right (+X)
	
	match position_name:
		"GK":
			return Vector2(x_multiplier * base_x_offset, 0)
		"LB":
			return Vector2(x_multiplier * (base_x_offset - 100), -PITCH_HEIGHT/3)
		"CB1":
			return Vector2(x_multiplier * (base_x_offset - 100), -80)
		"CB2":
			return Vector2(x_multiplier * (base_x_offset - 100), 80)
		"RB":
			return Vector2(x_multiplier * (base_x_offset - 100), PITCH_HEIGHT/3)
		"LM":
			return Vector2(x_multiplier * (base_x_offset - 250), -PITCH_HEIGHT/3)
		"CM1":
			return Vector2(x_multiplier * (base_x_offset - 250), -80)
		"CM2":
			return Vector2(x_multiplier * (base_x_offset - 250), 80)
		"RM":
			return Vector2(x_multiplier * (base_x_offset - 250), PITCH_HEIGHT/3)
		"ST1":
			return Vector2(x_multiplier * (base_x_offset - 400), -80)
		"ST2":
			return Vector2(x_multiplier * (base_x_offset - 400), 80)
		_:
			return Vector2.ZERO

## Get the center of the pitch
func get_center_position() -> Vector2:
	return Vector2.ZERO

## Check if a position is inside the pitch boundaries
func is_position_in_bounds(pos: Vector2) -> bool:
	return abs(pos.x) <= PITCH_WIDTH/2 and abs(pos.y) <= PITCH_HEIGHT/2

## Clamp a position to be within pitch boundaries
func clamp_to_pitch(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, -PITCH_WIDTH/2, PITCH_WIDTH/2),
		clampf(pos.y, -PITCH_HEIGHT/2, PITCH_HEIGHT/2)
	)

# ============================================================================
# GOAL DETECTION
# ============================================================================

## Check if a position is inside the home goal
func is_in_home_goal(pos: Vector2) -> bool:
	return pos.x < -PITCH_WIDTH/2 + GOAL_DEPTH and abs(pos.y) < GOAL_WIDTH/2

## Check if a position is inside the away goal
func is_in_away_goal(pos: Vector2) -> bool:
	return pos.x > PITCH_WIDTH/2 - GOAL_DEPTH and abs(pos.y) < GOAL_WIDTH/2

## Get the home goal center position
func get_home_goal_position() -> Vector2:
	return Vector2(-PITCH_WIDTH/2, 0)  # Home goal on LEFT

## Get the away goal center position
func get_away_goal_position() -> Vector2:
	return Vector2(PITCH_WIDTH/2, 0)  # Away goal on RIGHT
