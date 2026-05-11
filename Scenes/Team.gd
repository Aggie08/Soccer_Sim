## Team.gd
## Represents a soccer team with roster and manager reference
## Tactical settings come from the team's manager
class_name Team
extends Resource

# ============================================================================
# TEAM IDENTITY
# ============================================================================
@export var team_name: String = "Unknown Team"
@export var team_id: String = ""
@export var nation: String = "Unknown"
@export var tier: int = 3  # 1 = Top tier, 3 = Bottom tier

# ============================================================================
# MANAGER REFERENCE
# ============================================================================
@export var manager_id: String = ""  # References a Manager by ID
var manager: Manager = null  # Cached manager instance (loaded at runtime)

# ============================================================================
# ROSTER
# ============================================================================
@export var roster: Array[Player] = []
@export var max_roster_size: int = 25

# ============================================================================
# FORMATION & LINEUP
# ============================================================================
# Starting 11 (by position on pitch)
@export var starting_lineup: Dictionary = {
	"GK": null,   # Player reference
	"LB": null,
	"CB1": null,
	"CB2": null,
	"RB": null,
	"LM": null,
	"CM1": null,
	"CM2": null,
	"RM": null,
	"ST1": null,
	"ST2": null
}

# ============================================================================
# TEAM STATS (Aggregate)
# ============================================================================
var team_morale: int = 50  # 0-100, affects all players
var team_chemistry: int = 50  # 0-100, affects passing/coordination

# ============================================================================
# FINANCIAL (Career Mode)
# ============================================================================
@export var transfer_budget: int = 1000000
@export var wage_budget: int = 100000

# ============================================================================
# INITIALIZATION
# ============================================================================
func _init() -> void:
	if team_id.is_empty():
		team_id = _generate_unique_id()

# ============================================================================
# CORE METHODS
# ============================================================================

## Generate unique team ID
func _generate_unique_id() -> String:
	return "TEAM_" + str(Time.get_unix_time_from_system()) + "_" + str(randi())

## Add a player to the roster
func add_player(player: Player) -> bool:
	if roster.size() >= max_roster_size:
		push_warning("Roster full, cannot add player: " + player.player_name)
		return false
	
	roster.append(player)
	return true

## Remove a player from the roster
func remove_player(player: Player) -> bool:
	var index = roster.find(player)
	if index == -1:
		return false
	
	roster.remove_at(index)
	
	# Clear from starting lineup if present
	for position in starting_lineup.keys():
		if starting_lineup[position] == player:
			starting_lineup[position] = null
	
	return true

## Set a player in the starting lineup at a specific position
func set_starter(position: String, player: Player) -> bool:
	if not position in starting_lineup:
		push_warning("Invalid position: " + position)
		return false
	
	if not player in roster:
		push_warning("Player not in roster: " + player.player_name)
		return false
	
	starting_lineup[position] = player
	player.current_position = position
	return true

## Get all players currently in the starting 11
func get_starting_11() -> Array[Player]:
	var starters: Array[Player] = []
	for position in starting_lineup.values():
		if position != null:
			starters.append(position)
	
	if starters.is_empty():
		print("WARNING: No starting lineup found for ", team_name, "!")
		print("  Starting lineup dict: ", starting_lineup)
		print("  Roster size: ", roster.size())
	
	return starters

## Get team average rating (all attributes)
func get_team_average_rating() -> float:
	if roster.is_empty():
		return 0.0
	
	var total = 0
	for player in roster:
		total += player._calculate_attribute_total()
	
	return float(total) / (roster.size() * 19.0)

## Get starting 11 average rating
func get_starting_11_average() -> float:
	var starters = get_starting_11()
	if starters.is_empty():
		return 0.0
	
	var total = 0
	for player in starters:
		total += player._calculate_attribute_total()
	
	return float(total) / (starters.size() * 19.0)

## Auto-fill starting lineup with best available players (simple algorithm)
func auto_select_starting_11() -> void:
	# Sort roster by attribute total (highest first)
	var sorted_roster = roster.duplicate()
	sorted_roster.sort_custom(func(a: Player, b: Player): 
		return a.current_attribute_total > b.current_attribute_total
	)
	
	# Simple position assignment (just fills slots with best players)
	# In a real implementation, you'd match players to their primary positions
	var position_keys = starting_lineup.keys()
	for i in min(position_keys.size(), sorted_roster.size()):
		starting_lineup[position_keys[i]] = sorted_roster[i]
		sorted_roster[i].current_position = position_keys[i]

# ============================================================================
# TACTICAL SETTINGS (Delegated to Manager)
# ============================================================================

## Get formation from manager (or default if no manager)
func get_formation() -> String:
	if manager != null:
		return manager.preferred_formation
	return "4-4-2"  # Default

## Get attacking mentality from manager
func get_attacking_mentality() -> int:
	if manager != null:
		return manager.preferred_attacking_mentality
	return 50  # Default

## Get pressing intensity from manager
func get_pressing_intensity() -> int:
	if manager != null:
		return manager.preferred_pressing_intensity
	return 50  # Default

## Get tempo from manager
func get_tempo() -> int:
	if manager != null:
		return manager.preferred_tempo
	return 50  # Default

## Get width from manager
func get_width() -> int:
	if manager != null:
		return manager.preferred_width
	return 50  # Default

# ============================================================================
# SERIALIZATION
# ============================================================================

## Serialize to dictionary for JSON export
func to_dict() -> Dictionary:
	var roster_data: Array = []
	for player in roster:
		roster_data.append(player.to_dict())
	
	var lineup_data = {}
	for pos in starting_lineup.keys():
		if starting_lineup[pos] != null:
			lineup_data[pos] = starting_lineup[pos].player_id
		else:
			lineup_data[pos] = null
	
	return {
		"team_name": team_name,
		"team_id": team_id,
		"nation": nation,
		"tier": tier,
		"manager_id": manager_id,  # Store manager ID, not full manager object
		"roster": roster_data,
		"starting_lineup": lineup_data,
		"transfer_budget": transfer_budget,
		"wage_budget": wage_budget
	}

## Load team from dictionary (JSON import)
static func from_dict(data: Dictionary) -> Team:
	var team = Team.new()
	
	# Identity
	team.team_name = data.get("team_name", "Unknown Team")
	team.team_id = data.get("team_id", "")
	team.nation = data.get("nation", "Unknown")
	team.tier = data.get("tier", 3)
	
	# Manager reference (will be loaded separately)
	team.manager_id = data.get("manager_id", "")
	
	# Roster
	var roster_data: Array = data.get("roster", [])
	for player_data in roster_data:
		var player = Player.from_dict(player_data)
		team.roster.append(player)
	
	# Financials
	team.transfer_budget = data.get("transfer_budget", 1000000)
	team.wage_budget = data.get("wage_budget", 100000)
	
	# Starting lineup (rebuild references from player IDs)
	var lineup_data: Dictionary = data.get("starting_lineup", {})
	for pos in lineup_data.keys():
		var player_id = lineup_data[pos]
		if player_id != null:
			# Find player in roster by ID
			for player in team.roster:
				if player.player_id == player_id:
					team.starting_lineup[pos] = player
					player.current_position = pos
					break
	
	# If starting_lineup is empty, auto-populate from roster
	if team.starting_lineup.values().filter(func(p): return p != null).is_empty():
		print("Auto-populating starting lineup for ", team.team_name)
		# Use first 11 players from roster based on their primary_position
		for player in team.roster:
			if player.primary_position in team.starting_lineup:
				# Only set if position not already filled
				if team.starting_lineup[player.primary_position] == null:
					team.starting_lineup[player.primary_position] = player
					player.current_position = player.primary_position
	
	return team
