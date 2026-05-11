## DataManager.gd
## Singleton for managing all game data (loading/saving teams, players, managers)
## This is an Autoload singleton
extends Node

# ============================================================================
# CONSTANTS
# ============================================================================
const SAVE_DIR = "user://saves/"
const TEAMS_DIR = "res://Data/Teams/"
const MANAGERS_DIR = "res://Data/Managers/"
const SAVE_FILE_EXTENSION = ".json"

# ============================================================================
# RUNTIME DATA
# ============================================================================
var current_manager: Manager = null  # The player's manager (for Career Mode)
var player_team: Team = null  # The team the player manages
var all_teams: Array[Team] = []  # All teams in the world
var all_managers: Dictionary = {}  # All loaded managers, keyed by manager_id

# ============================================================================
# INITIALIZATION
# ============================================================================
func _ready() -> void:
	_ensure_save_directory_exists()
	print("DataManager initialized")

# ============================================================================
# DIRECTORY MANAGEMENT
# ============================================================================

## Ensure the save directory exists
func _ensure_save_directory_exists() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)

# ============================================================================
# MANAGER OPERATIONS
# ============================================================================

## Create a new manager for the player
func create_new_manager(name: String, nationality: String = "Unknown") -> Manager:
	current_manager = Manager.new()
	current_manager.manager_name = name
	current_manager.nationality = nationality
	return current_manager

## Load a manager from JSON file (for premade managers)
func load_manager_from_json(file_path: String) -> Manager:
	if not FileAccess.file_exists(file_path):
		push_error("Manager file does not exist: " + file_path)
		return null
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open manager file: " + file_path)
		return null
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		push_error("Failed to parse manager JSON: " + file_path)
		return null
	
	var manager_data: Dictionary = json.data
	var manager = Manager.from_dict(manager_data)
	
	print("Manager loaded: " + manager.manager_name)
	return manager

## Load all managers from the managers directory
func load_all_managers_from_directory(directory: String = MANAGERS_DIR) -> Dictionary:
	var managers: Dictionary = {}
	var dir = DirAccess.open(directory)
	
	print(directory)
	
	if dir == null:
		push_error("Failed to open managers directory: " + directory)
		return managers
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full_path = directory + file_name
			var manager = load_manager_from_json(full_path)
			if manager != null:
				managers[manager.manager_id] = manager
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	all_managers = managers
	print("Loaded ", managers.size(), " managers from ", directory)
	return managers

## Get a manager by ID from the loaded managers
func get_manager_by_id(manager_id: String) -> Manager:
	return all_managers.get(manager_id, null)

## Save player's manager data to file
func save_manager(filename: String = "manager_save") -> bool:
	if current_manager == null:
		push_error("No manager to save")
		return false
	
	var save_path = SAVE_DIR + filename + SAVE_FILE_EXTENSION
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	
	if file == null:
		push_error("Failed to open save file: " + save_path)
		return false
	
	var save_data = {
		"manager": current_manager.to_dict(),
		"timestamp": Time.get_unix_time_from_system()
	}
	
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	
	print("Manager saved to: " + save_path)
	return true

## Load player's manager data from file
func load_manager(filename: String = "manager_save") -> bool:
	var save_path = SAVE_DIR + filename + SAVE_FILE_EXTENSION
	
	if not FileAccess.file_exists(save_path):
		push_error("Save file does not exist: " + save_path)
		return false
	
	var file = FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open save file: " + save_path)
		return false
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		push_error("Failed to parse JSON: " + save_path)
		return false
	
	var save_data: Dictionary = json.data
	
	if not "manager" in save_data:
		push_error("Invalid save data structure")
		return false
	
	current_manager = Manager.from_dict(save_data["manager"])
	print("Manager loaded from: " + save_path)
	return true

# ============================================================================
# TEAM OPERATIONS (JSON Loading)
# ============================================================================

## Load a team from JSON file
func load_team_from_json(file_path: String) -> Team:
	if not FileAccess.file_exists(file_path):
		push_error("Team file does not exist: " + file_path)
		return null
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open team file: " + file_path)
		return null
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		push_error("Failed to parse team JSON: " + file_path)
		return null
	
	var team_data: Dictionary = json.data
	var team = Team.from_dict(team_data)
	
	# Link manager if manager_id is present
	if not team.manager_id.is_empty():
		team.manager = get_manager_by_id(team.manager_id)
		if team.manager == null:
			push_warning("Manager not found for team: " + team.team_name + " (Manager ID: " + team.manager_id + ")")
	
	print("Team loaded: " + team.team_name)
	return team

## Load all teams from a directory
func load_all_teams_from_directory(directory: String = TEAMS_DIR) -> Array[Team]:
	var teams: Array[Team] = []
	var dir = DirAccess.open(directory)
	
	if dir == null:
		push_error("Failed to open teams directory: " + directory)
		return teams
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full_path = directory + file_name
			var team = load_team_from_json(full_path)
			if team != null:
				teams.append(team)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	all_teams = teams
	print("Loaded ", teams.size(), " teams from ", directory)
	return teams

## Load both managers and teams (proper order: managers first, then teams)
func load_all_game_data() -> void:
	print("\n=== Loading Game Data ===")
	load_all_managers_from_directory()
	load_all_teams_from_directory()
	print("=== Game Data Loaded ===\n")

# ============================================================================
# TEAM OPERATIONS (Resource Saving)
# ============================================================================

## Save a team as a Godot Resource (.tres)
func save_team_resource(team: Team, filename: String) -> bool:
	var save_path = SAVE_DIR + filename + ".tres"
	var error = ResourceSaver.save(team, save_path)
	
	if error != OK:
		push_error("Failed to save team resource: " + save_path)
		return false
	
	print("Team resource saved: " + save_path)
	return true

## Load a team from a Godot Resource (.tres)
func load_team_resource(filename: String) -> Team:
	var load_path = SAVE_DIR + filename + ".tres"
	
	if not ResourceLoader.exists(load_path):
		push_error("Team resource does not exist: " + load_path)
		return null
	
	var team = ResourceLoader.load(load_path) as Team
	
	if team == null:
		push_error("Failed to load team resource: " + load_path)
		return null
	
	print("Team resource loaded: " + team.team_name)
	return team

# ============================================================================
# PLAYER OPERATIONS (Resource)
# ============================================================================

## Save a player as a Godot Resource (.tres)
func save_player_resource(player: Player, filename: String) -> bool:
	var save_path = SAVE_DIR + filename + ".tres"
	var error = ResourceSaver.save(player, save_path)
	
	if error != OK:
		push_error("Failed to save player resource: " + save_path)
		return false
	
	print("Player resource saved: " + save_path)
	return true

## Load a player from a Godot Resource (.tres)
func load_player_resource(filename: String) -> Player:
	var load_path = SAVE_DIR + filename + ".tres"
	
	if not ResourceLoader.exists(load_path):
		push_error("Player resource does not exist: " + load_path)
		return null
	
	var player = ResourceLoader.load(load_path) as Player
	
	if player == null:
		push_error("Failed to load player resource: " + load_path)
		return null
	
	print("Player resource loaded: " + player.player_name)
	return player

# ============================================================================
# SAVE GAME OPERATIONS (Full Career Save)
# ============================================================================

## Save the entire game state (manager + team + all teams)
func save_game_state(save_name: String = "career_save") -> bool:
	if current_manager == null:
		push_error("No manager to save")
		return false
	
	var save_path = SAVE_DIR + save_name + SAVE_FILE_EXTENSION
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	
	if file == null:
		push_error("Failed to create save file: " + save_path)
		return false
	
	# Compile all data
	var save_data = {
		"version": "1.0",
		"timestamp": Time.get_unix_time_from_system(),
		"manager": current_manager.to_dict() if current_manager else null,
		"player_team": player_team.to_dict() if player_team else null,
		"all_teams": []
	}
	
	# Save all teams
	for team in all_teams:
		save_data["all_teams"].append(team.to_dict())
	
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	
	print("Game state saved to: " + save_path)
	return true

## Load the entire game state
func load_game_state(save_name: String = "career_save") -> bool:
	var save_path = SAVE_DIR + save_name + SAVE_FILE_EXTENSION
	
	if not FileAccess.file_exists(save_path):
		push_error("Save file does not exist: " + save_path)
		return false
	
	var file = FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open save file: " + save_path)
		return false
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		push_error("Failed to parse save JSON")
		return false
	
	var save_data: Dictionary = json.data
	
	# Load manager
	if "manager" in save_data and save_data["manager"] != null:
		current_manager = Manager.from_dict(save_data["manager"])
	
	# Load player team
	if "player_team" in save_data and save_data["player_team"] != null:
		player_team = Team.from_dict(save_data["player_team"])
	
	# Load all teams
	if "all_teams" in save_data:
		all_teams.clear()
		for team_data in save_data["all_teams"]:
			all_teams.append(Team.from_dict(team_data))
	
	print("Game state loaded from: " + save_path)
	return true

# ============================================================================
# UTILITY
# ============================================================================

## Get list of all save files
func get_save_files() -> Array[String]:
	var saves: Array[String] = []
	var dir = DirAccess.open(SAVE_DIR)
	
	if dir == null:
		return saves
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(SAVE_FILE_EXTENSION):
			saves.append(file_name.get_basename())
		file_name = dir.get_next()
	
	dir.list_dir_end()
	return saves
