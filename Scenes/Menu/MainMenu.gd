## MainMenu.gd
## Main menu scene - entry point for the game
extends Control

# ============================================================================
# CHILD NODES
# ============================================================================
@onready var title_label: Label = $CenterContainer/MenuPanel/VBoxContainer/TitleLabel
@onready var play_now_button: Button = $CenterContainer/MenuPanel/VBoxContainer/PlayNowButton
@onready var career_mode_button: Button = $CenterContainer/MenuPanel/VBoxContainer/CareerModeButton
@onready var online_mode_button: Button = $CenterContainer/MenuPanel/VBoxContainer/OnlineModeButton
@onready var test_match_button: Button = $CenterContainer/MenuPanel/VBoxContainer/TestMatchButton
@onready var settings_button: Button = $CenterContainer/MenuPanel/VBoxContainer/SettingsButton
@onready var quit_button: Button = $CenterContainer/MenuPanel/VBoxContainer/QuitButton
@onready var version_label: Label = $VersionLabel

# ============================================================================
# INITIALIZATION
# ============================================================================
func _ready() -> void:
	_connect_signals()
	_setup_ui()
	
	# Load game data on startup
	DataManager.load_all_game_data()

## Connect button signals
func _connect_signals() -> void:
	if play_now_button:
		play_now_button.pressed.connect(_on_play_now_pressed)
	if career_mode_button:
		career_mode_button.pressed.connect(_on_career_mode_pressed)
	if online_mode_button:
		online_mode_button.pressed.connect(_on_online_mode_pressed)
	if test_match_button:
		test_match_button.pressed.connect(_on_test_match_pressed)
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

## Setup UI elements
func _setup_ui() -> void:
	# Enable Play Now - it's ready!
	if play_now_button:
		play_now_button.disabled = false
		play_now_button.tooltip_text = "Quick match - select teams and play!"
	
	# Disable buttons for modes not yet implemented
	if career_mode_button:
		career_mode_button.disabled = true
		career_mode_button.tooltip_text = "Coming Soon!"
	
	if online_mode_button:
		online_mode_button.disabled = true
		online_mode_button.tooltip_text = "Coming Soon!"
	
	# Test match button always enabled
	if test_match_button:
		test_match_button.tooltip_text = "Test the match engine with random teams"
	
	# Version label
	if version_label:
		version_label.text = "v0.2.0 - Play Now Mode"

# ============================================================================
# BUTTON CALLBACKS
# ============================================================================

func _on_play_now_pressed() -> void:
	print("Loading Play Now mode...")
	_load_team_selection()

func _load_team_selection() -> void:
	var error := get_tree().change_scene_to_file("res://Scenes/Menu/TeamSelection.tscn")
	if error != OK:
		push_error("Failed to load TeamSelection scene: " + str(error))

func _on_career_mode_pressed() -> void:
	print("Career Mode - Not yet implemented")
	# Will load career mode setup/save selection
	pass

func _on_online_mode_pressed() -> void:
	print("Online Mode - Not yet implemented")
	# Will load online mode lobby/matchmaking
	pass

func _on_test_match_pressed() -> void:
	print("Loading test match...")
	_load_match_scene()

func _on_settings_pressed() -> void:
	print("Settings - Not yet implemented")
	# Will open settings panel/scene
	pass

func _on_quit_pressed() -> void:
	print("Quitting game...")
	get_tree().quit()

# ============================================================================
# SCENE LOADING
# ============================================================================

## Load the match scene for testing
func _load_match_scene() -> void:
	# Show loading indicator (optional - add later)
	var error := get_tree().change_scene_to_file("res://Scenes/Match/MatchScene.tscn")
	
	if error != OK:
		push_error("Failed to load MatchScene: " + str(error))
