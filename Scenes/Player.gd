## Player.gd
## Represents a single player with all attributes on the 1-20 scale
class_name Player
extends Resource

# ============================================================================
# CONSTANTS
# ============================================================================
const MAX_ATTRIBUTE_VALUE := 20
const MIN_ATTRIBUTE_VALUE := 1
const MAX_POTENTIAL_CAP := 250

# ============================================================================
# PLAYER IDENTITY
# ============================================================================
@export var player_name: String = "Unknown Player"
@export var player_id: String = ""  # Unique identifier
@export var age: int = 18
@export var nationality: String = "Unknown"

# ============================================================================
# PHYSICAL ATTRIBUTES (1-20)
# ============================================================================
@export_range(1, 20) var speed: int = 10
@export_range(1, 20) var acceleration: int = 10
@export_range(1, 20) var strength: int = 10
@export_range(1, 20) var stamina: int = 10

# ============================================================================
# MENTAL ATTRIBUTES (1-20)
# ============================================================================
@export_range(1, 20) var vision: int = 10
@export_range(1, 20) var intelligence: int = 10
@export_range(1, 20) var marking: int = 10
@export_range(1, 20) var positioning: int = 10

# ============================================================================
# TECHNICAL ATTRIBUTES (1-20)
# ============================================================================
@export_range(1, 20) var dribbling: int = 10
@export_range(1, 20) var ball_control: int = 10
@export_range(1, 20) var short_pass: int = 10
@export_range(1, 20) var long_pass: int = 10
@export_range(1, 20) var crossing: int = 10
@export_range(1, 20) var shot_power: int = 10
@export_range(1, 20) var shot_accuracy: int = 10
@export_range(1, 20) var tackling: int = 10
@export_range(1, 20) var heading: int = 10

# ============================================================================
# GOALKEEPER ATTRIBUTES (1-20)
# ============================================================================
@export_range(1, 20) var reflexes: int = 10
@export_range(1, 20) var diving: int = 10
@export_range(1, 20) var handling: int = 10

# ============================================================================
# POTENTIAL & DEVELOPMENT
# ============================================================================
@export_range(19, MAX_POTENTIAL_CAP) var potential_cap: int = 190
@export var current_attribute_total: int = 190  # Sum of all 19 attributes

# ============================================================================
# POSITION KNOWLEDGE
# ============================================================================
enum PositionFamiliarity {
	PRIMARY,      # 100% stats
	FAMILIAR,     # -15% mental stats
	OUT_OF_POSITION  # -30% mental stats
}

@export var primary_position: String = "CM"  # e.g., ST, CM, CB, GK
@export var familiar_positions: Array[String] = []  # Can play with -15% mental
@export var current_position: String = "CM"  # Position they're playing NOW

# ============================================================================
# MATCH STATE (Runtime only, not saved)
# ============================================================================
var current_morale: int = 50  # 0-100
var current_stamina_percent: float = 100.0  # 0-100
var match_rating: float = 6.0  # 1-10 scale
var is_on_pitch: bool = false

# ============================================================================
# INITIALIZATION
# ============================================================================
func _init() -> void:
	if player_id.is_empty():
		player_id = _generate_unique_id()
	_calculate_attribute_total()

# ============================================================================
# CORE METHODS
# ============================================================================

## Generate a unique ID for this player
func _generate_unique_id() -> String:
	return "PLR_" + str(Time.get_unix_time_from_system()) + "_" + str(randi())

## Calculate the total of all 19 attributes
func _calculate_attribute_total() -> int:
	current_attribute_total = (
		# Physical
		speed + acceleration + strength + stamina +
		# Mental
		vision + intelligence + marking + positioning +
		# Technical
		dribbling + ball_control + short_pass + long_pass +
		crossing + shot_power + shot_accuracy + tackling + heading +
		# Goalkeeper
		reflexes + diving + handling
	)
	return current_attribute_total

## Get the familiarity level for a given position
func get_position_familiarity(position: String) -> PositionFamiliarity:
	if position == primary_position:
		return PositionFamiliarity.PRIMARY
	elif position in familiar_positions:
		return PositionFamiliarity.FAMILIAR
	else:
		return PositionFamiliarity.OUT_OF_POSITION

## Get an attribute value modified by position familiarity (for mental stats)
func get_modified_mental_stat(base_stat: int, position: String) -> int:
	var familiarity := get_position_familiarity(position)
	
	match familiarity:
		PositionFamiliarity.PRIMARY:
			return base_stat
		PositionFamiliarity.FAMILIAR:
			return int(base_stat * 0.85)  # -15%
		PositionFamiliarity.OUT_OF_POSITION:
			return int(base_stat * 0.70)  # -30%
	
	return base_stat

## Get effective vision based on current position
func get_effective_vision() -> int:
	return get_modified_mental_stat(vision, current_position)

## Get effective intelligence based on current position
func get_effective_intelligence() -> int:
	return get_modified_mental_stat(intelligence, current_position)

## Get effective marking based on current position
func get_effective_marking() -> int:
	return get_modified_mental_stat(marking, current_position)

## Get effective positioning based on current position
func get_effective_positioning() -> int:
	return get_modified_mental_stat(positioning, current_position)

## Check if player can be upgraded (hasn't hit potential cap)
func can_upgrade() -> bool:
	_calculate_attribute_total()
	return current_attribute_total < potential_cap

## Upgrade a specific attribute by 1 (respects cap)
func upgrade_attribute(attribute_name: String) -> bool:
	if not can_upgrade():
		return false
	
	var current_value = get(attribute_name)
	if current_value >= MAX_ATTRIBUTE_VALUE:
		return false
	
	set(attribute_name, current_value + 1)
	_calculate_attribute_total()
	return true

## Reset match state (call at start of each match)
func reset_match_state() -> void:
	current_stamina_percent = 100.0
	match_rating = 6.0
	is_on_pitch = false

## Serialize player to dictionary for JSON export
func to_dict() -> Dictionary:
	return {
		"player_name": player_name,
		"player_id": player_id,
		"age": age,
		"nationality": nationality,
		# Physical
		"speed": speed,
		"acceleration": acceleration,
		"strength": strength,
		"stamina": stamina,
		# Mental
		"vision": vision,
		"intelligence": intelligence,
		"marking": marking,
		"positioning": positioning,
		# Technical
		"dribbling": dribbling,
		"ball_control": ball_control,
		"short_pass": short_pass,
		"long_pass": long_pass,
		"crossing": crossing,
		"shot_power": shot_power,
		"shot_accuracy": shot_accuracy,
		"tackling": tackling,
		"heading": heading,
		# Goalkeeper
		"reflexes": reflexes,
		"diving": diving,
		"handling": handling,
		# Meta
		"potential_cap": potential_cap,
		"primary_position": primary_position,
		"familiar_positions": familiar_positions,
		"current_position": current_position
	}

## Load player from dictionary (JSON import)
static func from_dict(data: Dictionary) -> Player:
	var player := Player.new()
	
	# Identity
	player.player_name = data.get("player_name", "Unknown")
	player.player_id = data.get("player_id", "")
	player.age = data.get("age", 18)
	player.nationality = data.get("nationality", "Unknown")
	
	# Physical
	player.speed = data.get("speed", 10)
	player.acceleration = data.get("acceleration", 10)
	player.strength = data.get("strength", 10)
	player.stamina = data.get("stamina", 10)
	
	# Mental
	player.vision = data.get("vision", 10)
	player.intelligence = data.get("intelligence", 10)
	player.marking = data.get("marking", 10)
	player.positioning = data.get("positioning", 10)
	
	# Technical
	player.dribbling = data.get("dribbling", 10)
	player.ball_control = data.get("ball_control", 10)
	player.short_pass = data.get("short_pass", 10)
	player.long_pass = data.get("long_pass", 10)
	player.crossing = data.get("crossing", 10)
	player.shot_power = data.get("shot_power", 10)
	player.shot_accuracy = data.get("shot_accuracy", 10)
	player.tackling = data.get("tackling", 10)
	player.heading = data.get("heading", 10)
	
	# Goalkeeper
	player.reflexes = data.get("reflexes", 10)
	player.diving = data.get("diving", 10)
	player.handling = data.get("handling", 10)
	
	# Meta
	player.potential_cap = data.get("potential_cap", 190)
	player.primary_position = data.get("primary_position", "CM")
	
	# Load familiar positions - convert from array to typed array
	var familiar_data: Array = data.get("familiar_positions", [])
	for position in familiar_data:
		if position is String:
			player.familiar_positions.append(position)
	
	player.current_position = data.get("current_position", player.primary_position)
	
	player._calculate_attribute_total()
	return player
