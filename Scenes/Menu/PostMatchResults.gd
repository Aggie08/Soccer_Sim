## PostMatchResults.gd
## Displays match results and options for next action
extends Control

# ============================================================================
# CHILD NODES
# ============================================================================
@onready var title_label: Label = $PanelContainer/VBoxContainer/TitleLabel
@onready var home_team_label: Label = $PanelContainer/VBoxContainer/ScorePanel/HomeTeamLabel
@onready var away_team_label: Label = $PanelContainer/VBoxContainer/ScorePanel/AwayTeamLabel
@onready var score_label: Label = $PanelContainer/VBoxContainer/ScorePanel/ScoreLabel
@onready var result_label: Label = $PanelContainer/VBoxContainer/ResultLabel
@onready var rematch_button: Button = $PanelContainer/VBoxContainer/ButtonPanel/RematchButton
@onready var new_match_button: Button = $PanelContainer/VBoxContainer/ButtonPanel/NewMatchButton
@onready var main_menu_button: Button = $PanelContainer/VBoxContainer/ButtonPanel/MainMenuButton

# ============================================================================
# MATCH DATA
# ============================================================================
var home_team: Team = null
var away_team: Team = null
var home_score: int = 0
var away_score: int = 0

# ============================================================================
# INITIALIZATION
# ============================================================================
func _ready() -> void:
	_connect_signals()
	_load_match_results()
	_display_results()

func _connect_signals() -> void:
	if rematch_button:
		rematch_button.pressed.connect(_on_rematch_pressed)
	if new_match_button:
		new_match_button.pressed.connect(_on_new_match_pressed)
	if main_menu_button:
		main_menu_button.pressed.connect(_on_main_menu_pressed)

# ============================================================================
# DATA LOADING
# ============================================================================
func _load_match_results() -> void:
	# Get match results from metadata
	home_team = get_tree().root.get_meta("match_home_team", null)
	away_team = get_tree().root.get_meta("match_away_team", null)
	home_score = get_tree().root.get_meta("match_home_score", 0)
	away_score = get_tree().root.get_meta("match_away_score", 0)
	
	if not home_team or not away_team:
		print("ERROR: No match data found!")
		home_team = Team.new()
		home_team.team_name = "Home Team"
		away_team = Team.new()
		away_team.team_name = "Away Team"

# ============================================================================
# UI DISPLAY
# ============================================================================
func _display_results() -> void:
	# Set team names
	if home_team_label:
		home_team_label.text = home_team.team_name if home_team.team_name else "Home Team"
	
	if away_team_label:
		away_team_label.text = away_team.team_name if away_team.team_name else "Away Team"
	
	# Set score
	if score_label:
		score_label.text = str(home_score) + "  -  " + str(away_score)
	
	# Set result message
	if result_label:
		if home_score > away_score:
			result_label.text = home_team.team_name + " WINS!"
			result_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))  # Green
		elif away_score > home_score:
			result_label.text = away_team.team_name + " WINS!"
			result_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))  # Green
		else:
			result_label.text = "IT'S A DRAW!"
			result_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.2))  # Yellow

# ============================================================================
# BUTTON CALLBACKS
# ============================================================================
func _on_rematch_pressed() -> void:
	print("Starting rematch...")
	# Store teams for rematch (swap home/away)
	get_tree().root.set_meta("play_now_home_team", away_team)
	get_tree().root.set_meta("play_now_away_team", home_team)
	
	# Clear results metadata
	get_tree().root.remove_meta("match_home_team")
	get_tree().root.remove_meta("match_away_team")
	get_tree().root.remove_meta("match_home_score")
	get_tree().root.remove_meta("match_away_score")
	
	# Load match scene
	get_tree().change_scene_to_file("res://Scenes/Match/MatchScene.tscn")

func _on_new_match_pressed() -> void:
	print("Selecting new teams...")
	# Clear results metadata
	get_tree().root.remove_meta("match_home_team")
	get_tree().root.remove_meta("match_away_team")
	get_tree().root.remove_meta("match_home_score")
	get_tree().root.remove_meta("match_away_score")
	
	# Go to team selection
	get_tree().change_scene_to_file("res://Scenes/Menu/TeamSelection.tscn")

func _on_main_menu_pressed() -> void:
	print("Returning to main menu...")
	# Clear all metadata
	get_tree().root.remove_meta("match_home_team")
	get_tree().root.remove_meta("match_away_team")
	get_tree().root.remove_meta("match_home_score")
	get_tree().root.remove_meta("match_away_score")
	
	# Go to main menu
	get_tree().change_scene_to_file("res://Scenes/Menu/MainMenu.tscn")
