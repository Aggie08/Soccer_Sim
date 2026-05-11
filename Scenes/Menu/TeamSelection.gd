## TeamSelection.gd
## Screen for selecting home and away teams for Play Now mode
extends Control

# ============================================================================
# SIGNALS
# ============================================================================
signal teams_selected(home_team: Team, away_team: Team)

# ============================================================================
# CHILD NODES
# ============================================================================
@onready var home_team_list: ItemList = $PanelContainer/VBoxContainer/TeamsPanel/HomeTeamPanel/HomeTeamList
@onready var away_team_list: ItemList = $PanelContainer/VBoxContainer/TeamsPanel/AwayTeamPanel/AwayTeamList
@onready var home_team_label: Label = $PanelContainer/VBoxContainer/TeamsPanel/HomeTeamPanel/SelectedLabel
@onready var away_team_label: Label = $PanelContainer/VBoxContainer/TeamsPanel/AwayTeamPanel/SelectedLabel
@onready var start_match_button: Button = $PanelContainer/VBoxContainer/ButtonPanel/StartMatchButton
@onready var back_button: Button = $PanelContainer/VBoxContainer/ButtonPanel/BackButton

# ============================================================================
# STATE
# ============================================================================
var all_teams: Array[Team] = []
var selected_home_team: Team = null
var selected_away_team: Team = null

# ============================================================================
# INITIALIZATION
# ============================================================================
func _ready() -> void:
	_connect_signals()
	_load_teams()
	_update_ui()

func _connect_signals() -> void:
	if home_team_list:
		home_team_list.item_selected.connect(_on_home_team_selected)
	if away_team_list:
		away_team_list.item_selected.connect(_on_away_team_selected)
	if start_match_button:
		start_match_button.pressed.connect(_on_start_match_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

# ============================================================================
# TEAM LOADING
# ============================================================================
func _load_teams() -> void:
	# Get teams from DataManager
	all_teams = DataManager.all_teams.duplicate()
	
	if all_teams.is_empty():
		print("WARNING: No teams loaded! Creating test teams...")
		_create_test_teams()
	
	# Populate both lists
	_populate_team_lists()

func _create_test_teams() -> void:
	# Create a few test teams if none exist
	for i in range(4):
		var team = Team.new()
		team.team_name = "Team " + str(i + 1)
		team.team_id = "TEST_TEAM_" + str(i + 1)
		
		# Create 11 test players
		for j in range(11):
			var player = Player.new()
			player.player_name = "Player " + str(j + 1)
			player.player_id = "PLAYER_" + str(i) + "_" + str(j)
			player.current_position = ["GK", "LB", "CB1", "CB2", "RB", "LM", "CM1", "CM2", "RM", "ST1", "ST2"][j]
			player.primary_position = player.current_position
			team.roster.append(player)
		
		all_teams.append(team)

func _populate_team_lists() -> void:
	if not home_team_list or not away_team_list:
		return
	
	home_team_list.clear()
	away_team_list.clear()
	
	for team in all_teams:
		var team_name = team.team_name if team.team_name else "Unnamed Team"
		home_team_list.add_item(team_name)
		away_team_list.add_item(team_name)

# ============================================================================
# CALLBACKS
# ============================================================================
func _on_home_team_selected(index: int) -> void:
	if index >= 0 and index < all_teams.size():
		selected_home_team = all_teams[index]
		print("Home team selected: ", selected_home_team.team_name)
		_update_ui()

func _on_away_team_selected(index: int) -> void:
	if index >= 0 and index < all_teams.size():
		selected_away_team = all_teams[index]
		print("Away team selected: ", selected_away_team.team_name)
		_update_ui()

func _on_start_match_pressed() -> void:
	if not selected_home_team or not selected_away_team:
		print("ERROR: Both teams must be selected!")
		return
	
	if selected_home_team == selected_away_team:
		print("ERROR: Cannot select the same team twice!")
		return
	
	print("Starting match: ", selected_home_team.team_name, " vs ", selected_away_team.team_name)
	
	# Store teams in a temporary global (we'll pass them to MatchScene)
	get_tree().root.set_meta("play_now_home_team", selected_home_team)
	get_tree().root.set_meta("play_now_away_team", selected_away_team)
	
	# Load match scene
	get_tree().change_scene_to_file("res://Scenes/Match/MatchScene.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/Menu/MainMenu.tscn")

# ============================================================================
# UI UPDATE
# ============================================================================
func _update_ui() -> void:
	# Update labels
	if home_team_label:
		if selected_home_team:
			home_team_label.text = "Selected: " + selected_home_team.team_name
		else:
			home_team_label.text = "Select Home Team"
	
	if away_team_label:
		if selected_away_team:
			away_team_label.text = "Selected: " + selected_away_team.team_name
		else:
			away_team_label.text = "Select Away Team"
	
	# Enable start button only if both teams selected and different
	if start_match_button:
		var both_selected = selected_home_team != null and selected_away_team != null
		var teams_different = both_selected and (selected_home_team != selected_away_team)
		var can_start = both_selected and teams_different
		
		start_match_button.disabled = not can_start
		
		# Update button text with helpful message
		if not both_selected:
			start_match_button.text = "Select both teams to start"
		elif not teams_different:
			start_match_button.text = "⚠️ Cannot select the same team twice!"
		else:
			start_match_button.text = "▶ Start Match"
