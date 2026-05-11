## Manager.gd
## Represents the user's manager with leveling, attributes, and reputation
class_name Manager
extends Resource

# ============================================================================
# CONSTANTS
# ============================================================================
const MAX_LEVEL = 20
const MAX_ATTRIBUTE = 20
const MAX_REPUTATION = 5  # 5-star rating
const MAX_INFLUENCE = 100

# ============================================================================
# MANAGER IDENTITY
# ============================================================================
@export var manager_name: String = "New Manager"
@export var manager_id: String = ""
@export var nationality: String = "Unknown"
@export var age: int = 35

# ============================================================================
# LEVELING SYSTEM (1-20)
# ============================================================================
@export_range(1, 20) var level: int = 1
@export var current_xp: int = 0
@export var xp_to_next_level: int = 100  # Scales with level

# ============================================================================
# MANAGER ATTRIBUTES (1-20 Scale)
# ============================================================================
@export_range(1, 20) var persuasion: int = 10      # Affects player morale, contract negotiations
@export_range(1, 20) var authority: int = 10       # Affects shout success, player discipline
@export_range(1, 20) var tactical_iq: int = 10     # Unlocks advanced tactics, better AI
@export_range(1, 20) var training_savvy: int = 10  # Speeds up training, reduces injury risk
@export_range(1, 20) var eye_for_talent: int = 10  # Better scouting, reveals potential faster

# ============================================================================
# REPUTATION SYSTEM
# ============================================================================
@export_range(0, MAX_REPUTATION) var reputation_stars: int = 1  # 1-5 stars
@export_range(0, MAX_INFLUENCE) var influence_meter: int = 0    # 0-100, drives star rating

# Reputation thresholds
const REPUTATION_THRESHOLDS = {
	1: 0,    # 1 star: 0-19 influence
	2: 20,   # 2 stars: 20-39 influence
	3: 40,   # 3 stars: 40-59 influence
	4: 60,   # 4 stars: 60-79 influence
	5: 80    # 5 stars: 80-100 influence
}

# ============================================================================
# ARCHETYPE SYSTEM
# ============================================================================
enum ManagerArchetype {
	NONE,
	ATTACKING_FOCUS,    # Unlocked at Level 5
	DEFENSIVE_WALL,     # Unlocked at Level 5
	TACTICAL_GENIUS,    # Unlocked at Level 10
	MOTIVATOR,          # Unlocked at Level 10
	SCOUT_MASTER,       # Unlocked at Level 15
	FINANCIAL_WIZARD    # Unlocked at Level 15
}

@export var unlocked_archetypes: Array[ManagerArchetype] = []
@export var active_archetypes: Array[ManagerArchetype] = []  # Max 3
const MAX_ACTIVE_ARCHETYPES = 3

# Archetype unlock levels
const ARCHETYPE_UNLOCK_LEVELS = {
	ManagerArchetype.ATTACKING_FOCUS: 5,
	ManagerArchetype.DEFENSIVE_WALL: 5,
	ManagerArchetype.TACTICAL_GENIUS: 10,
	ManagerArchetype.MOTIVATOR: 10,
	ManagerArchetype.SCOUT_MASTER: 15,
	ManagerArchetype.FINANCIAL_WIZARD: 15
}

# ============================================================================
# TACTICAL PREFERENCES (Used for AI managers and player defaults)
# ============================================================================
@export var preferred_formation: String = "4-4-2"
@export_range(0, 100) var preferred_attacking_mentality: int = 50
@export_range(0, 100) var preferred_pressing_intensity: int = 50
@export_range(0, 100) var preferred_tempo: int = 50
@export_range(0, 100) var preferred_width: int = 50

# ============================================================================
# CAREER STATS
# ============================================================================
@export var matches_managed: int = 0
@export var wins: int = 0
@export var draws: int = 0
@export var losses: int = 0
@export var trophies_won: int = 0

# ============================================================================
# INITIALIZATION
# ============================================================================
func _init() -> void:
	if manager_id.is_empty():
		manager_id = _generate_unique_id()
	_update_reputation()

# ============================================================================
# CORE METHODS
# ============================================================================

## Generate unique manager ID
func _generate_unique_id() -> String:
	return "MGR_" + str(Time.get_unix_time_from_system()) + "_" + str(randi())

## Add XP and handle leveling
func add_xp(amount: int) -> void:
	current_xp += amount
	
	# Check for level up
	while current_xp >= xp_to_next_level and level < MAX_LEVEL:
		_level_up()

## Handle level up logic
func _level_up() -> void:
	current_xp -= xp_to_next_level
	level += 1
	
	# Scale XP requirement for next level
	xp_to_next_level = _calculate_xp_for_level(level + 1)
	
	# Check if new archetypes are unlocked
	_check_archetype_unlocks()
	
	print("Manager leveled up to Level ", level)

## Calculate XP required for a specific level
func _calculate_xp_for_level(target_level: int) -> int:
	# Simple exponential scaling: 100 * (level ^ 1.5)
	return int(100.0 * pow(target_level, 1.5))

## Update reputation stars based on influence meter
func _update_reputation() -> void:
	for stars in range(MAX_REPUTATION, 0, -1):
		if influence_meter >= REPUTATION_THRESHOLDS[stars]:
			reputation_stars = stars
			return

## Add influence (positive actions: wins, trophies)
func add_influence(amount: int) -> void:
	influence_meter = clampi(influence_meter + amount, 0, MAX_INFLUENCE)
	_update_reputation()

## Remove influence (negative actions: losses, scandals)
func remove_influence(amount: int) -> void:
	influence_meter = clampi(influence_meter - amount, 0, MAX_INFLUENCE)
	_update_reputation()

## Check if new archetypes should be unlocked
func _check_archetype_unlocks() -> void:
	for archetype in ARCHETYPE_UNLOCK_LEVELS.keys():
		var required_level: int = ARCHETYPE_UNLOCK_LEVELS[archetype]
		if level >= required_level and archetype not in unlocked_archetypes:
			unlocked_archetypes.append(archetype)
			print("Archetype unlocked: ", ManagerArchetype.keys()[archetype])

## Activate an archetype (max 3)
func activate_archetype(archetype: ManagerArchetype) -> bool:
	if archetype not in unlocked_archetypes:
		push_warning("Archetype not unlocked")
		return false
	
	if archetype in active_archetypes:
		push_warning("Archetype already active")
		return false
	
	if active_archetypes.size() >= MAX_ACTIVE_ARCHETYPES:
		push_warning("Maximum archetypes already active")
		return false
	
	active_archetypes.append(archetype)
	return true

## Deactivate an archetype
func deactivate_archetype(archetype: ManagerArchetype) -> bool:
	var index = active_archetypes.find(archetype)
	if index == -1:
		return false
	
	active_archetypes.remove_at(index)
	return true

## Record a match result
func record_match_result(won: bool, drew: bool) -> void:
	matches_managed += 1
	if won:
		wins += 1
		add_influence(2)  # Small influence boost for win
	elif drew:
		draws += 1
	else:
		losses += 1
		remove_influence(1)  # Small influence penalty for loss

## Get win percentage
func get_win_percentage() -> float:
	if matches_managed == 0:
		return 0.0
	return (float(wins) / float(matches_managed)) * 100.0

## Serialize to dictionary
func to_dict() -> Dictionary:
	return {
		"manager_name": manager_name,
		"manager_id": manager_id,
		"nationality": nationality,
		"age": age,
		"level": level,
		"current_xp": current_xp,
		"xp_to_next_level": xp_to_next_level,
		"persuasion": persuasion,
		"authority": authority,
		"tactical_iq": tactical_iq,
		"training_savvy": training_savvy,
		"eye_for_talent": eye_for_talent,
		"reputation_stars": reputation_stars,
		"influence_meter": influence_meter,
		"preferred_formation": preferred_formation,
		"preferred_attacking_mentality": preferred_attacking_mentality,
		"preferred_pressing_intensity": preferred_pressing_intensity,
		"preferred_tempo": preferred_tempo,
		"preferred_width": preferred_width,
		"unlocked_archetypes": unlocked_archetypes,
		"active_archetypes": active_archetypes,
		"matches_managed": matches_managed,
		"wins": wins,
		"draws": draws,
		"losses": losses,
		"trophies_won": trophies_won
	}

## Load from dictionary
static func from_dict(data: Dictionary) -> Manager:
	var manager = Manager.new()
	
	manager.manager_name = data.get("manager_name", "New Manager")
	manager.manager_id = data.get("manager_id", "")
	manager.nationality = data.get("nationality", "Unknown")
	manager.age = data.get("age", 35)
	
	manager.level = data.get("level", 1)
	manager.current_xp = data.get("current_xp", 0)
	manager.xp_to_next_level = data.get("xp_to_next_level", 100)
	
	manager.persuasion = data.get("persuasion", 10)
	manager.authority = data.get("authority", 10)
	manager.tactical_iq = data.get("tactical_iq", 10)
	manager.training_savvy = data.get("training_savvy", 10)
	manager.eye_for_talent = data.get("eye_for_talent", 10)
	
	manager.reputation_stars = data.get("reputation_stars", 1)
	manager.influence_meter = data.get("influence_meter", 0)
	
	manager.preferred_formation = data.get("preferred_formation", "4-4-2")
	manager.preferred_attacking_mentality = data.get("preferred_attacking_mentality", 50)
	manager.preferred_pressing_intensity = data.get("preferred_pressing_intensity", 50)
	manager.preferred_tempo = data.get("preferred_tempo", 50)
	manager.preferred_width = data.get("preferred_width", 50)
	
	# Load archetypes - convert from int array to enum array
	var unlocked_data: Array = data.get("unlocked_archetypes", [])
	for archetype_int in unlocked_data:
		if archetype_int is int and archetype_int >= 0 and archetype_int < ManagerArchetype.size():
			manager.unlocked_archetypes.append(archetype_int as ManagerArchetype)
	
	var active_data: Array = data.get("active_archetypes", [])
	for archetype_int in active_data:
		if archetype_int is int and archetype_int >= 0 and archetype_int < ManagerArchetype.size():
			manager.active_archetypes.append(archetype_int as ManagerArchetype)
	
	manager.matches_managed = data.get("matches_managed", 0)
	manager.wins = data.get("wins", 0)
	manager.draws = data.get("draws", 0)
	manager.losses = data.get("losses", 0)
	manager.trophies_won = data.get("trophies_won", 0)
	
	return manager
