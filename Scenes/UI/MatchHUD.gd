## MatchHUD.gd
## Main HUD for match display with tactical controls
extends CanvasLayer

# ============================================================================
# SIGNALS
# ============================================================================
signal tactics_button_pressed()
signal substitution_button_pressed()
signal formation_button_pressed()
signal pause_button_pressed()
signal back_to_menu_pressed()

# ============================================================================
# CHILD NODES
# ============================================================================
@onready var score_label: Label = $TopBar/ScoreLabel
@onready var time_label: Label = $TopBar/TimeLabel
@onready var command_meter_bar: ProgressBar = $TopBar/CommandMeterBar
@onready var tactics_button: Button = $BottomBar/TacticsButton
@onready var substitution_button: Button = $BottomBar/SubstitutionButton
@onready var formation_button: Button = $BottomBar/FormationButton
@onready var pause_button: Button = $TopBar/PauseButton
@onready var back_to_menu_button: Button = $TopBar/BackToMenuButton

# Stats display nodes (optional - will create if don't exist)
@onready var stats_panel: Panel = $StatsPanel if has_node("StatsPanel") else null
@onready var possession_label: Label = $StatsPanel/PossessionLabel if stats_panel and stats_panel.has_node("PossessionLabel") else null
@onready var possession_bar_home: ProgressBar = $StatsPanel/PossessionBarHome if stats_panel and stats_panel.has_node("PossessionBarHome") else null
@onready var possession_bar_away: ProgressBar = $StatsPanel/PossessionBarAway if stats_panel and stats_panel.has_node("PossessionBarAway") else null
@onready var shots_label: Label = $StatsPanel/ShotsLabel if stats_panel and stats_panel.has_node("ShotsLabel") else null
@onready var passes_label: Label = $StatsPanel/PassesLabel if stats_panel and stats_panel.has_node("PassesLabel") else null
@onready var xg_label: Label = $StatsPanel/XGLabel if stats_panel and stats_panel.has_node("XGLabel") else null

# Tactical panels (hidden by default)
@onready var tactics_panel: Panel = $TacticsPanel
@onready var formation_panel: Panel = $FormationPanel
@onready var substitution_panel: Panel = $SubstitutionPanel

# ============================================================================
# STATE
# ============================================================================
var home_score: int = 0
var away_score: int = 0
var current_match_time: String = "00:00"
var command_meter_value: float = 100.0

# ============================================================================
# INITIALIZATION
# ============================================================================
func _ready() -> void:
	_connect_signals()
	_hide_all_panels()
	update_display()

## Connect button signals
func _connect_signals() -> void:
	if tactics_button:
		tactics_button.pressed.connect(_on_tactics_pressed)
	if substitution_button:
		substitution_button.pressed.connect(_on_substitution_pressed)
	if formation_button:
		formation_button.pressed.connect(_on_formation_pressed)
	if pause_button:
		pause_button.pressed.connect(_on_pause_pressed)
	if back_to_menu_button:
		back_to_menu_button.pressed.connect(_on_back_to_menu_pressed)
	
	# Connect close buttons on panels
	if tactics_panel and tactics_panel.has_node("CloseButton"):
		tactics_panel.get_node("CloseButton").pressed.connect(hide_all_panels)
	if formation_panel and formation_panel.has_node("CloseButton"):
		formation_panel.get_node("CloseButton").pressed.connect(hide_all_panels)
	if substitution_panel and substitution_panel.has_node("CloseButton"):
		substitution_panel.get_node("CloseButton").pressed.connect(hide_all_panels)

## Hide all tactical panels
func _hide_all_panels() -> void:
	if tactics_panel:
		tactics_panel.visible = false
	if formation_panel:
		formation_panel.visible = false
	if substitution_panel:
		substitution_panel.visible = false

# ============================================================================
# UPDATE DISPLAY
# ============================================================================

## Update all HUD elements
func update_display() -> void:
	_update_score()
	_update_time()
	_update_command_meter()

## Update score display
func _update_score() -> void:
	if score_label:
		score_label.text = "%d - %d" % [home_score, away_score]

## Update time display
func _update_time() -> void:
	if time_label:
		time_label.text = current_match_time

## Update command meter bar
func _update_command_meter() -> void:
	if command_meter_bar:
		command_meter_bar.value = command_meter_value

# ============================================================================
# PUBLIC UPDATE METHODS (called from MatchScene)
# ============================================================================

## Update score from external source (MatchScene)
func update_score(home: int, away: int) -> void:
	home_score = home
	away_score = away
	_update_score()

## Update match time from external source (MatchScene)
func update_time(minute: int, half: int) -> void:
	current_match_time = "%d' (%s)" % [minute, "1st" if half == 1 else "2nd"]
	_update_time()

## Update statistics (called from MatchScene every 5 seconds)
func update_stats(stats: Dictionary) -> void:
	# Extract home and away stats
	var home_stats = stats.get("home", {})
	var away_stats = stats.get("away", {})
	
	# Calculate possession percentage
	var home_poss = home_stats.get("possession_ticks", 0)
	var away_poss = away_stats.get("possession_ticks", 0)
	var total_poss = home_poss + away_poss
	
	var home_poss_pct = 50.0
	var away_poss_pct = 50.0
	
	if total_poss > 0:
		home_poss_pct = (float(home_poss) / float(total_poss)) * 100.0
		away_poss_pct = 100.0 - home_poss_pct
	
	# If stats panel exists, update visual display
	if stats_panel:
		# Update possession display
		if possession_label:
			possession_label.text = "Possession: %d%% - %d%%" % [int(home_poss_pct), int(away_poss_pct)]
		
		if possession_bar_home:
			possession_bar_home.value = home_poss_pct
		
		if possession_bar_away:
			possession_bar_away.value = away_poss_pct
		
		# Update shots display
		if shots_label:
			var home_shots = home_stats.get("shots", 0)
			var away_shots = away_stats.get("shots", 0)
			var home_on_target = home_stats.get("shots_on_target", 0)
			var away_on_target = away_stats.get("shots_on_target", 0)
			shots_label.text = "Shots: %d (%d) - %d (%d)" % [home_shots, home_on_target, away_shots, away_on_target]
		
		# Update passes display
		if passes_label:
			var home_completed = home_stats.get("passes_completed", 0)
			var home_attempted = home_stats.get("passes_attempted", 0)
			var away_completed = away_stats.get("passes_completed", 0)
			var away_attempted = away_stats.get("passes_attempted", 0)
			
			var home_pct = 0
			var away_pct = 0
			if home_attempted > 0:
				home_pct = int((float(home_completed) / float(home_attempted)) * 100.0)
			if away_attempted > 0:
				away_pct = int((float(away_completed) / float(away_attempted)) * 100.0)
			
			passes_label.text = "Passes: %d/%d (%d%%) - %d/%d (%d%%)" % [
				home_completed, home_attempted, home_pct,
				away_completed, away_attempted, away_pct
			]
		
		# Update xG display
		if xg_label:
			var home_xg = home_stats.get("xg", 0.0)
			var away_xg = away_stats.get("xg", 0.0)
			xg_label.text = "xG: %.2f - %.2f" % [home_xg, away_xg]
	
	# Fallback: Print to console if no stats panel
	else:
		var home_shots = home_stats.get("shots", 0)
		var away_shots = away_stats.get("shots", 0)
		var home_xg = home_stats.get("xg", 0.0)
		var away_xg = away_stats.get("xg", 0.0)
		
		print("📊 Stats Update | Possession: %d%% - %d%% | Shots: %d - %d | xG: %.2f - %.2f" % [
			int(home_poss_pct), int(away_poss_pct),
			home_shots, away_shots,
			home_xg, away_xg
		])

# ============================================================================
# PUBLIC METHODS (Called by MatchScene)
# ============================================================================

## Set the score
func set_score(home: int, away: int) -> void:
	home_score = home
	away_score = away
	_update_score()

## Set the match time
func set_time(time_string: String) -> void:
	current_match_time = time_string
	_update_time()

## Set the command meter value (0-100)
func set_command_meter(value: float) -> void:
	command_meter_value = clampf(value, 0.0, 100.0)
	_update_command_meter()

# ============================================================================
# TACTICAL PANEL CONTROLS
# ============================================================================

## Show the tactics panel (mentality, pressing, etc.)
func show_tactics_panel() -> void:
	_hide_all_panels()
	if tactics_panel:
		tactics_panel.visible = true

## Show the formation panel
func show_formation_panel() -> void:
	_hide_all_panels()
	if formation_panel:
		formation_panel.visible = true

## Show the substitution panel
func show_substitution_panel() -> void:
	_hide_all_panels()
	if substitution_panel:
		substitution_panel.visible = true

## Hide all panels
func hide_all_panels() -> void:
	_hide_all_panels()
	# Unpause the game when closing panels
	if get_tree():
		get_tree().paused = false

# ============================================================================
# BUTTON CALLBACKS
# ============================================================================

func _on_tactics_pressed() -> void:
	show_tactics_panel()
	tactics_button_pressed.emit()

func _on_substitution_pressed() -> void:
	show_substitution_panel()
	substitution_button_pressed.emit()

func _on_formation_pressed() -> void:
	show_formation_panel()
	formation_button_pressed.emit()

func _on_pause_pressed() -> void:
	pause_button_pressed.emit()

func _on_back_to_menu_pressed() -> void:
	back_to_menu_pressed.emit()
