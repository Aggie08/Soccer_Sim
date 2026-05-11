## MatchScene.gd
## Main match scene that orchestrates gameplay
## Upgraded to work with tick-based MatchEngine
extends Node2D

# ============================================================================
# CONSTANTS
# ============================================================================
const PLAYER_TOKEN_SCENE = preload("res://Scenes/Match/PlayerToken.tscn")
const HOME_TEAM_COLOR = Color(0, 0.5, 1)  # Blue
const AWAY_TEAM_COLOR = Color(1, 0, 0)     # Red

# ============================================================================
# CHILD NODES
# ============================================================================
@onready var pitch: Node2D = $Pitch
@onready var ball: Area2D = $Ball
@onready var hud: CanvasLayer = $MatchHUD
@onready var home_team_container: Node2D = $HomeTeamPlayers
@onready var away_team_container: Node2D = $AwayTeamPlayers

# ============================================================================
# MATCH ENGINE
# ============================================================================
var match_engine: Node = null  # MatchEngine instance

# ============================================================================
# MATCH DATA
# ============================================================================
var home_team: Team = null
var away_team: Team = null
var home_players: Array[Node2D] = []  # PlayerToken nodes
var away_players: Array[Node2D] = []  # PlayerToken nodes

# ============================================================================
# MATCH STATE
# ============================================================================
var match_started: bool = false
var ball_possessor: Node2D = null

# ============================================================================
# INITIALIZATION
# ============================================================================
func _ready() -> void:
	_connect_signals()
	# Defer setup to ensure all nodes are fully ready
	call_deferred("_setup_test_match")
	# Also ensure ball starts at center
	if ball:
		call_deferred("_initialize_ball")

## Connect signals from managers and HUD
func _connect_signals() -> void:
	# OLD: MatchManager signals (replaced by MatchEngine)
	# MatchManager.match_started.connect(_on_match_started)
	# MatchManager.goal_scored.connect(_on_goal_scored)
	# MatchManager.match_ended.connect(_on_match_ended)
	# MatchManager.match_tick.connect(_on_match_tick)
	
	# Note: MatchEngine signals are connected in _create_match_engine()
	
	# Connect HUD buttons
	if hud:
		hud.tactics_button_pressed.connect(_on_tactics_pressed)
		hud.formation_button_pressed.connect(_on_formation_pressed)
		hud.substitution_button_pressed.connect(_on_substitution_pressed)
		hud.pause_button_pressed.connect(_on_pause_pressed)
		hud.back_to_menu_pressed.connect(_on_back_to_menu_pressed)
	
	# Connect goal area signals
	if pitch:
		var home_goal = pitch.get_node_or_null("HomeGoal")
		var away_goal = pitch.get_node_or_null("AwayGoal")
		
		if home_goal:
			home_goal.body_entered.connect(_on_home_goal_entered)
		if away_goal:
			away_goal.body_entered.connect(_on_away_goal_entered)

# ============================================================================
# MATCH SETUP
# ============================================================================

## Setup a match with two teams
func setup_match(home: Team, away: Team) -> void:
	home_team = home
	away_team = away
	
	# Create and initialize match engine
	_create_match_engine()
	
	# Spawn players
	_spawn_team_players(home_team, true)
	_spawn_team_players(away_team, false)
	
	# Register tokens with match engine
	match_engine.register_tokens(home_players, away_players)
	match_engine.register_ball(ball)
	
	# Set team references for AI
	_set_team_references()
	
	# Position players for kickoff
	_position_players_for_kickoff()
	
	# Start the match engine
	match_engine.start_match()
	
	print("Match setup complete!")

## Create and configure match engine
func _create_match_engine() -> void:
	# Load MatchEngine script
	var MatchEngineScript = load("res://Global/MatchEngine.gd")
	match_engine = MatchEngineScript.new()
	match_engine.name = "MatchEngine"
	add_child(match_engine)
	
	# Initialize with teams
	match_engine.initialize_match(home_team, away_team, 0)  # 0 = random seed
	
	# Connect signals
	match_engine.goal_scored.connect(_on_engine_goal_scored)
	match_engine.match_started.connect(_on_engine_match_started)
	match_engine.full_time.connect(_on_engine_full_time)
	match_engine.half_time.connect(_on_engine_half_time)
	match_engine.stats_updated.connect(_on_engine_stats_updated)
	match_engine.engine_tick.connect(_on_engine_tick)
	
	print("MatchEngine created and initialized")

## Set team references for all AI controllers
func _set_team_references() -> void:
	# Home team AI - knows about teammates and opponents
	for token in home_players:
		if token.ai_controller:
			token.ai_controller.set_team_references(home_players, away_players)
			token.ai_controller.set_ball(ball)
	
	# Away team AI
	for token in away_players:
		if token.ai_controller:
			token.ai_controller.set_team_references(away_players, home_players)
			token.ai_controller.set_ball(ball)

## Spawn player tokens for a team
func _spawn_team_players(team: Team, is_home: bool) -> void:
	var container = home_team_container if is_home else away_team_container
	var color = HOME_TEAM_COLOR if is_home else AWAY_TEAM_COLOR
	var players_array = home_players if is_home else away_players
	
	# Get starting 11
	var starting_11 = team.get_starting_11()
	
	print("Spawning ", starting_11.size(), " players for ", "home" if is_home else "away", " team")
	
	var player_idx = 0
	for player in starting_11:
		if player == null:
			continue
		
		# Instance player token
		var token: CharacterBody2D = PLAYER_TOKEN_SCENE.instantiate()
		container.add_child(token)
		
		# Setup the token with player index and match engine reference
		token.setup(player, color, is_home, player_idx, match_engine, self)
		players_array.append(token)
		
		print("  - Spawned [", player_idx, "]: ", player.player_name, " at position ", player.current_position)
		player_idx += 1

## Position all players according to formation for kickoff
func _position_players_for_kickoff() -> void:
	print("Positioning players for kickoff...")
	
	# Home team (bottom)
	for token in home_players:
		var position_name = token.get_position_on_field()
		var pitch_pos = pitch.get_formation_position(position_name, true)
		token.global_position = pitch_pos
		token.set_target_position(pitch_pos)
		print("  Home: ", token.player_data.player_name, " at ", pitch_pos)
	
	# Away team (top)
	for token in away_players:
		var position_name = token.get_position_on_field()
		var pitch_pos = pitch.get_formation_position(position_name, false)
		token.global_position = pitch_pos
		token.set_target_position(pitch_pos)
		print("  Away: ", token.player_data.player_name, " at ", pitch_pos)
	
	# Place ball at center
	if ball:
		var center_pos = pitch.get_center_position()
		ball.place_at(center_pos)
		print("Ball placed at: ", center_pos)
		
		# Start kickoff sequence after a short delay
		await get_tree().create_timer(0.5).timeout
		_execute_kickoff()

## Temporary test setup - loads example teams
func _setup_test_match() -> void:
	# Check if we're coming from Play Now mode
	var play_now_home = get_tree().root.get_meta("play_now_home_team", null)
	var play_now_away = get_tree().root.get_meta("play_now_away_team", null)
	
	if play_now_home and play_now_away:
		print("Setting up Play Now match...")
		# Clear the metadata
		get_tree().root.remove_meta("play_now_home_team")
		get_tree().root.remove_meta("play_now_away_team")
		# Setup the selected teams
		setup_match(play_now_home, play_now_away)
		return
	
	# Otherwise, load test match
	# Load game data
	DataManager.load_all_game_data()
	
	# For testing, create two simple teams if no teams loaded
	if DataManager.all_teams.size() >= 2:
		setup_match(DataManager.all_teams[0], DataManager.all_teams[1])
	else:
		# Create test teams
		var test_home = _create_test_team("Home FC", true)
		var test_away = _create_test_team("Away FC", false)
		setup_match(test_home, test_away)

## Initialize ball position
func _initialize_ball() -> void:
	if ball and pitch:
		var center = pitch.get_center_position()
		ball.global_position = center
		ball.velocity = Vector2.ZERO
		print("Ball initialized at center: ", center, " (actual position: ", ball.global_position, ")")

## Execute kickoff - striker passes to teammate
func _execute_kickoff() -> void:
	# Determine which team kicks off (home for first half)
	# In future: away team kicks off for second half
	var kicking_team = home_players
	var kicking_team_is_home = true
	
	print("Executing kickoff...")
	
	# Find the striker closest to center
	var striker: Node2D = null
	var closest_distance = INF
	
	for token in kicking_team:
		if not token.player_data:
			continue
		var pos_name = token.player_data.current_position
		if pos_name in ["ST1", "ST2", "ST", "CF"]:
			var distance = token.global_position.distance_to(ball.global_position)
			if distance < closest_distance:
				closest_distance = distance
				striker = token
	
	if not striker:
		# No striker found, use any forward player
		for token in kicking_team:
			var distance = token.global_position.distance_to(ball.global_position)
			if distance < closest_distance:
				closest_distance = distance
				striker = token
	
	if not striker:
		print("ERROR: No player found for kickoff!")
		return
	
	# Give ball to striker and update match engine
	_give_ball_to_player(striker)  # This calls match_engine.set_possession and prints message
	
	# Find a nearby teammate to pass to
	var pass_target: Node2D = null
	var best_distance = INF
	
	for token in kicking_team:
		if token == striker:
			continue  # Don't pass to self
		var distance = striker.global_position.distance_to(token.global_position)
		if distance < 150.0 and distance < best_distance:  # Within reasonable range
			best_distance = distance
			pass_target = token
	
	# Wait a moment then execute the pass
	await get_tree().create_timer(0.3).timeout
	
	if pass_target:
		print("Kickoff: ", striker.player_data.player_name, " passes to ", pass_target.player_data.player_name)
		ball.pass_ball(pass_target.global_position, 200.0)
		striker.remove_ball()
	else:
		# No good pass target, just kick it forward
		var forward_dir = Vector2(0, -1) if kicking_team_is_home else Vector2(0, 1)
		ball.kick(forward_dir, 250.0)
		striker.remove_ball()
		print("Kickoff: ", striker.player_data.player_name, " kicks forward")

## Create a basic test team with 11 players
func _create_test_team(team_name: String, is_home: bool) -> Team:
	var team = Team.new()
	team.team_name = team_name
	
	# Create a manager
	var manager = Manager.new()
	manager.manager_name = "Test Manager " + team_name
	manager.preferred_formation = "4-4-2"
	team.manager = manager
	
	# Create 11 players with basic positions
	var positions = ["GK", "LB", "CB1", "CB2", "RB", "LM", "CM1", "CM2", "RM", "ST1", "ST2"]
	
	for i in range(11):
		var player = Player.new()
		player.player_name = "Player %d" % (i + 1)
		player.primary_position = positions[i]
		player.current_position = positions[i]
		
		# Set some random stats
		player.speed = randi_range(8, 16)
		player.stamina = randi_range(8, 16)
		player.short_pass = randi_range(8, 16)
		player.shot_accuracy = randi_range(8, 16)
		
		team.add_player(player)
		team.starting_lineup[positions[i]] = player
	
	return team

# ============================================================================
# MATCH FLOW
# ============================================================================

func _process(delta: float) -> void:
	if match_started:
		_update_hud()
		_update_ball_possession()

## Update HUD elements
func _update_hud() -> void:
	if hud:
		hud.set_score(MatchManager.home_score, MatchManager.away_score)
		hud.set_time(MatchManager.get_match_time_string())
		hud.set_command_meter(MatchManager.command_meter)

## Update ball possession logic
func _update_ball_possession() -> void:
	if not ball or not ball.is_in_play:
		return
	
	# If ball has no possessor, check for nearby players
	if not ball.has_possessor():
		_check_for_ball_pickup()

## Check if any player is close enough to pick up the ball
func _check_for_ball_pickup() -> void:
	const PICKUP_DISTANCE = 30.0
	var ball_pos = ball.global_position
	
	var all_players = home_players + away_players
	var closest_player: Node2D = null
	var closest_distance = PICKUP_DISTANCE
	
	for player in all_players:
		if not is_instance_valid(player):
			continue
		
		var distance = player.global_position.distance_to(ball_pos)
		if distance < closest_distance:
			closest_distance = distance
			closest_player = player
	
	if closest_player:
		_give_ball_to_player(closest_player)

## Give the ball to a specific player
func _give_ball_to_player(player_token: Node2D) -> void:
	ball_possessor = player_token
	ball.give_possession(player_token)
	player_token.give_ball()
	
	# Update match engine possession
	if match_engine:
		var team = "home" if player_token in home_players else "away"
		match_engine.set_possession(team, player_token)
	
	print(player_token.player_data.player_name, " has the ball")

# ============================================================================
# MATCH ENGINE CALLBACKS
# ============================================================================

func _on_engine_match_started() -> void:
	match_started = true
	print("Match started! (from MatchEngine)")

func _on_engine_goal_scored(team: String, scorer_idx: int, minute: int, xg: float) -> void:
	var scoring_team = home_team if team == "home" else away_team
	var scoring_players = home_players if team == "home" else away_players
	
	var scorer_name = "Unknown"
	if scorer_idx >= 0 and scorer_idx < scoring_players.size():
		var token = scoring_players[scorer_idx]
		if token and token.player_data:
			scorer_name = token.player_data.player_name
	
	print("⚽ GOAL! ", scorer_name, " scores for ", scoring_team.team_name, " (", minute, "', xG: ", "%.2f" % xg, ")")
	
	# Reset positions for kickoff
	await get_tree().create_timer(2.0).timeout
	_position_players_for_kickoff()

func _on_engine_half_time() -> void:
	print("⏸ Half-time! Score: ", match_engine.home_score, " - ", match_engine.away_score)
	# HUD could show half-time screen here

func _on_engine_full_time() -> void:
	match_started = false
	var home_score = match_engine.home_score
	var away_score = match_engine.away_score
	
	print("⏱ Full time! Final score: ", home_team.team_name, " ", home_score, " - ", away_score, " ", away_team.team_name)
	
	# Store match results for post-match screen
	get_tree().root.set_meta("match_home_team", home_team)
	get_tree().root.set_meta("match_away_team", away_team)
	get_tree().root.set_meta("match_home_score", home_score)
	get_tree().root.set_meta("match_away_score", away_score)
	
	# Transition to results screen after a brief delay
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://Scenes/Menu/PostMatchResults.tscn")

func _on_engine_stats_updated(stats: Dictionary) -> void:
	# Update HUD with latest statistics
	if hud and hud.has_method("update_stats"):
		hud.update_stats(stats)

func _on_engine_tick(tick_data: Dictionary) -> void:
	# Update ball position in engine
	if ball:
		match_engine.update_ball_position(ball.global_position)
		match_engine.update_ball_velocity(ball.velocity)
	
	# Update HUD score every tick
	if hud:
		hud.update_score(match_engine.home_score, match_engine.away_score)
		hud.update_time(int(match_engine.match_minute), match_engine.current_half)

# ============================================================================
# LEGACY MATCH MANAGER CALLBACKS (for compatibility)
# ============================================================================

func _on_match_started() -> void:
	match_started = true
	print("Match started!")

func _on_goal_scored(team_side: String, scorer: Player) -> void:
	print("GOAL! ", scorer.player_name, " scores for ", team_side)
	
	# Reset positions for kickoff
	_position_players_for_kickoff()

func _on_match_ended(home_score: int, away_score: int) -> void:
	match_started = false
	print("Match ended! Final score: ", home_score, " - ", away_score)
	
	# Store match results for post-match screen
	get_tree().root.set_meta("match_home_team", home_team)
	get_tree().root.set_meta("match_away_team", away_team)
	get_tree().root.set_meta("match_home_score", home_score)
	get_tree().root.set_meta("match_away_score", away_score)
	
	# Transition to results screen after a brief delay
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://Scenes/Menu/PostMatchResults.tscn")

func _on_match_tick(tick_count: int) -> void:
	# This is where AI decisions will happen
	pass

# ============================================================================
# HUD BUTTON CALLBACKS
# ============================================================================

func _on_tactics_pressed() -> void:
	print("Tactics panel opened")
	# Pause the match while tactics are being changed
	get_tree().paused = true

func _on_formation_pressed() -> void:
	print("Formation panel opened")
	get_tree().paused = true

func _on_substitution_pressed() -> void:
	print("Substitution panel opened")
	get_tree().paused = true

func _on_pause_pressed() -> void:
	get_tree().paused = not get_tree().paused
	print("Match paused: ", get_tree().paused)

func _on_back_to_menu_pressed() -> void:
	# Unpause before leaving
	get_tree().paused = false
	# Return to main menu
	get_tree().change_scene_to_file("res://Scenes/Menu/MainMenu.tscn")

# ============================================================================
# GOAL DETECTION
# ============================================================================

func _on_home_goal_entered(body: Node2D) -> void:
	# Check if it's the ball
	if body == ball:
		# Away team scored!
		_register_goal(away_team, "away")

func _on_away_goal_entered(body: Node2D) -> void:
	# Check if it's the ball
	if body == ball:
		# Home team scored!
		_register_goal(home_team, "home")

func _register_goal(scoring_team: Team, team_side: String) -> void:
	# Find who last touched the ball (scorer)
	var scorer_idx = -1
	var scoring_players = home_players if team_side == "home" else away_players
	
	# Find closest player to ball as scorer
	if ball_possessor and is_instance_valid(ball_possessor):
		# Use the player who has/had possession
		scorer_idx = scoring_players.find(ball_possessor)
	else:
		# Fallback: find closest player
		var closest_distance = INF
		var closest_idx = -1
		
		for i in range(scoring_players.size()):
			var token = scoring_players[i]
			if not is_instance_valid(token):
				continue
			var distance = token.global_position.distance_to(ball.global_position)
			if distance < closest_distance:
				closest_distance = distance
				closest_idx = i
		
		scorer_idx = closest_idx
	
	# Record goal in match engine (it will emit goal_scored signal)
	if match_engine and scorer_idx >= 0:
		match_engine.record_goal(team_side, scorer_idx, 0.5)  # Default xG for now
	
	print("GOAL! ", team_side, " team scores!")
