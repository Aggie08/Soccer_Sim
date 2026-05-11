## DecisionEngine.gd
## Core decision-making system for the match engine
## Implements the P(Success) formula and action resolution
class_name DecisionEngine
extends Node

# ============================================================================
# CONSTANTS
# ============================================================================

# Difficulty modifiers for different actions
enum ActionDifficulty {
	VERY_EASY,    # +0.3
	EASY,         # +0.2
	NORMAL,       # +0.1
	HARD,         # +0.0
	VERY_HARD     # -0.1
}

const DIFFICULTY_MODIFIERS = {
	ActionDifficulty.VERY_EASY: 0.3,
	ActionDifficulty.EASY: 0.2,
	ActionDifficulty.NORMAL: 0.1,
	ActionDifficulty.HARD: 0.0,
	ActionDifficulty.VERY_HARD: -0.1
}

# Action types that players can perform
enum ActionType {
	SHORT_PASS,
	LONG_PASS,
	THROUGH_BALL,
	CROSS,
	SHOT,
	DRIBBLE,
	TACKLE,
	INTERCEPTION,
	CLEARANCE,
	HEADER,
	GK_SAVE,
	GK_CLAIM
}

# Stat weights for different actions (which stats matter most)
const ACTION_STAT_WEIGHTS = {
	ActionType.SHORT_PASS: {"primary": "short_pass", "secondary": "vision"},
	ActionType.LONG_PASS: {"primary": "long_pass", "secondary": "vision"},
	ActionType.THROUGH_BALL: {"primary": "short_pass", "secondary": "vision"},
	ActionType.CROSS: {"primary": "crossing", "secondary": "vision"},
	ActionType.SHOT: {"primary": "shot_accuracy", "secondary": "shot_power"},
	ActionType.DRIBBLE: {"primary": "dribbling", "secondary": "ball_control"},
	ActionType.TACKLE: {"primary": "tackling", "secondary": "strength"},
	ActionType.INTERCEPTION: {"primary": "marking", "secondary": "positioning"},
	ActionType.CLEARANCE: {"primary": "positioning", "secondary": "heading"},
	ActionType.HEADER: {"primary": "heading", "secondary": "positioning"},
	ActionType.GK_SAVE: {"primary": "reflexes", "secondary": "positioning"},
	ActionType.GK_CLAIM: {"primary": "handling", "secondary": "positioning"}
}

# ============================================================================
# CORE DECISION FORMULA
# ============================================================================

## Calculate success probability using the core formula:
## P(Success) = Difficulty Modifier + (Relevant Stat × 4) + (Intelligence × 1)
## Returns a value between 0.0 and 1.0
static func calculate_success_probability(
	player: Player,
	action_type: ActionType,
	difficulty: ActionDifficulty,
	opposing_player: Player = null
) -> float:
	
	# Get relevant stats for this action
	var stat_config = ACTION_STAT_WEIGHTS[action_type]
	var primary_stat = _get_player_stat(player, stat_config["primary"])
	var intelligence = player.get_effective_intelligence()
	
	# Base calculation: (Stat × 4) + (Intelligence × 1)
	var base_value = (primary_stat * 4.0) + (intelligence * 1.0)
	
	# Apply difficulty modifier
	var difficulty_mod = DIFFICULTY_MODIFIERS[difficulty]
	var final_value = base_value + (difficulty_mod * 100.0)
	
	# If there's opposition, subtract their defensive contribution
	if opposing_player != null:
		var opposition_value = _calculate_opposition_value(opposing_player, action_type)
		final_value -= opposition_value
	
	# Normalize to 0.0 - 1.0 range
	# Max possible: (20 * 4) + (20 * 1) + 30 = 130
	# Min possible: (1 * 4) + (1 * 1) - 10 = -5
	var probability = clampf(final_value / 130.0, 0.0, 1.0)
	
	return probability

## Calculate the opposing player's defensive contribution
static func _calculate_opposition_value(defender: Player, action_type: ActionType) -> float:
	match action_type:
		ActionType.SHOT:
			# For shots, use marking + positioning
			return (defender.get_effective_marking() * 2.0) + defender.get_effective_positioning()
		
		ActionType.DRIBBLE:
			# For dribbles, use tackling + positioning
			return (defender.tackling * 2.0) + defender.get_effective_positioning()
		
		ActionType.SHORT_PASS, ActionType.LONG_PASS, ActionType.THROUGH_BALL:
			# For passes, use marking + intelligence
			return (defender.get_effective_marking() * 2.0) + defender.get_effective_intelligence()
		
		ActionType.TACKLE, ActionType.INTERCEPTION:
			# For defending actions, use the attacker's strength/control
			return (defender.strength * 1.5) + (defender.ball_control * 1.5)
		
		_:
			# Default opposition
			return defender.get_effective_positioning() * 2.0

## Get a specific stat from a player by name
static func _get_player_stat(player: Player, stat_name: String) -> int:
	# Handle special cases for effective stats
	match stat_name:
		"vision":
			return player.get_effective_vision()
		"intelligence":
			return player.get_effective_intelligence()
		"marking":
			return player.get_effective_marking()
		"positioning":
			return player.get_effective_positioning()
		_:
			return player.get(stat_name)

# ============================================================================
# ACTION RESOLUTION
# ============================================================================

## Roll the dice - does the action succeed?
static func resolve_action(probability: float) -> bool:
	return randf() <= probability

## Perform a complete action check (calculate + resolve)
static func check_action_success(
	player: Player,
	action_type: ActionType,
	difficulty: ActionDifficulty,
	opposing_player: Player = null
) -> bool:
	
	var probability = calculate_success_probability(
		player,
		action_type,
		difficulty,
		opposing_player
	)
	
	return resolve_action(probability)

# ============================================================================
# CONTEXTUAL DIFFICULTY CALCULATION
# ============================================================================

## Calculate difficulty based on context (distance, pressure, etc.)
static func calculate_contextual_difficulty(
	action_type: ActionType,
	distance: float = 0.0,
	pressure_level: int = 0,  # 0-3: none, light, moderate, heavy
	weather_modifier: float = 0.0
) -> ActionDifficulty:
	
	# Start with normal difficulty
	var difficulty_score = 2  # NORMAL = 2
	
	# Adjust based on distance (for passing/shooting)
	match action_type:
		ActionType.LONG_PASS, ActionType.SHOT:
			if distance > 30.0:
				difficulty_score += 2  # Harder
			elif distance > 20.0:
				difficulty_score += 1
		
		ActionType.SHORT_PASS, ActionType.THROUGH_BALL:
			if distance > 15.0:
				difficulty_score += 1
	
	# Adjust based on pressure
	difficulty_score += pressure_level
	
	# Clamp to valid difficulty range
	difficulty_score = clampi(difficulty_score, 0, 4)
	
	return difficulty_score as ActionDifficulty

# ============================================================================
# QUALITY RATING (How well was the action performed?)
# ============================================================================

## Get a quality rating (0-10) for how well an action was performed
## Used for pass accuracy, shot power variation, etc.
static func get_action_quality(
	player: Player,
	action_type: ActionType,
	success_probability: float
) -> float:
	
	# Base quality on the probability and a random factor
	var base_quality = success_probability * 10.0
	var random_variance = randf_range(-2.0, 2.0)
	
	# Adjust by the secondary stat
	var stat_config = ACTION_STAT_WEIGHTS[action_type]
	if "secondary" in stat_config:
		var secondary_stat = _get_player_stat(player, stat_config["secondary"])
		var secondary_bonus = (secondary_stat - 10.0) / 10.0  # -1 to +1
		base_quality += secondary_bonus
	
	return clampf(base_quality + random_variance, 0.0, 10.0)

# ============================================================================
# SHOUT SUCCESS (Manager intervention)
# ============================================================================

## Check if a manager shout is successfully received by a player
## Depends on player's morale, intelligence, and manager's authority
static func check_shout_success(
	player: Player,
	manager: Manager
) -> bool:
	
	# Base probability from manager's authority
	var base_prob = manager.authority / 20.0  # 0.05 to 1.0
	
	# Modified by player's intelligence
	var intelligence_bonus = (player.get_effective_intelligence() - 10.0) / 20.0
	
	# Modified by player's morale
	var morale_bonus = (player.current_morale - 50.0) / 100.0
	
	var final_prob = clampf(base_prob + intelligence_bonus + morale_bonus, 0.0, 1.0)
	
	return randf() <= final_prob

# ============================================================================
# CUSTOM ACTION CHECKS
# ============================================================================

## Simple custom action check with a stat value vs difficulty
## Useful for specialized checks like goalkeeper saves with combined stats
static func check_custom_action_success(stat_value: int, difficulty_value: int) -> bool:
	# Simple formula: stat_value vs difficulty_value
	# Higher stat = better chance
	var probability = float(stat_value) / float(stat_value + difficulty_value)
	probability = clampf(probability, 0.0, 1.0)
	return randf() <= probability
