## MatchManager.gd
## Singleton for managing match state, logic ticks, and game flow
## This is an Autoload singleton
extends Node

# ============================================================================
# SIGNALS
# ============================================================================
signal match_started()
signal match_ended(home_score: int, away_score: int)
signal goal_scored(team_side: String, scorer: Player)
signal half_ended(half_number: int)
signal match_tick(tick_count: int)

# ============================================================================
# MATCH STATE
# ============================================================================
enum MatchState {
	NOT_STARTED,
	FIRST_HALF,
	HALF_TIME,
	SECOND_HALF,
	FULL_TIME
}

var current_state: MatchState = MatchState.NOT_STARTED

# Teams
var home_team: Team = null
var away_team: Team = null

# Score
var home_score: int = 0
var away_score: int = 0

# Time
var match_time_seconds: float = 0.0
const HALF_LENGTH_SECONDS: float = 45.0 * 60.0  # 45 minutes in seconds
const MATCH_LENGTH_SECONDS: float = 90.0 * 60.0  # 90 minutes in seconds

# Logic Tick System
var logic_tick_count: int = 0
var logic_tick_rate: float = 0.5  # Ticks per second (2 ticks per second)
var time_since_last_tick: float = 0.0

# Ball state
var ball_position: Vector2 = Vector2.ZERO
var ball_possessor: Player = null  # Who currently has the ball
var ball_in_play: bool = false

# ============================================================================
# COMMAND METER (Manager Shouts)
# ============================================================================
var command_meter: float = 100.0
const MAX_COMMAND_METER: float = 100.0
const COMMAND_REGEN_RATE: float = 5.0  # Points per second

# Shout costs
const SHOUT_COSTS = {
	"individual": 20.0,  # Individual player shouts
	"team": 40.0         # Team-wide shouts
}

# ============================================================================
# INITIALIZATION
# ============================================================================
func _ready() -> void:
	print("MatchManager initialized")

# ============================================================================
# CORE UPDATE LOOP
# ============================================================================
func _process(delta: float) -> void:
	if current_state == MatchState.NOT_STARTED or current_state == MatchState.FULL_TIME:
		return
	
	if current_state == MatchState.HALF_TIME:
		return
	
	# Update match time
	match_time_seconds += delta
	
	# Update logic tick
	time_since_last_tick += delta
	if time_since_last_tick >= (1.0 / logic_tick_rate):
		_process_logic_tick()
		time_since_last_tick = 0.0
	
	# Regenerate command meter
	_regenerate_command_meter(delta)
	
	# Check for half/full time
	_check_match_time()

# ============================================================================
# MATCH CONTROL
# ============================================================================

## Start a new match between two teams
func start_match(home: Team, away: Team) -> void:
	home_team = home
	away_team = away
	home_score = 0
	away_score = 0
	match_time_seconds = 0.0
	logic_tick_count = 0
	command_meter = MAX_COMMAND_METER
	
	current_state = MatchState.FIRST_HALF
	ball_in_play = true
	
	# Reset player match states
	_reset_player_match_states(home_team)
	_reset_player_match_states(away_team)
	
	# Position ball at center
	ball_position = Vector2.ZERO
	
	print("Match started: ", home_team.team_name, " vs ", away_team.team_name)
	match_started.emit()

## End the current match
func end_match() -> void:
	current_state = MatchState.FULL_TIME
	ball_in_play = false
	
	print("Match ended: ", home_team.team_name, " ", home_score, " - ", away_score, " ", away_team.team_name)
	match_ended.emit(home_score, away_score)
	
	# Award XP to manager if present
	if DataManager.current_manager != null:
		var won = _did_player_win()
		var drew = home_score == away_score
		DataManager.current_manager.record_match_result(won, drew)
		
		# Small XP gain
		var xp_gain = 10
		if won:
			xp_gain = 30
		elif drew:
			xp_gain = 15
		
		DataManager.current_manager.add_xp(xp_gain)

## Check if player's team won (assumes player manages home team)
func _did_player_win() -> bool:
	if DataManager.player_team == home_team:
		return home_score > away_score
	elif DataManager.player_team == away_team:
		return away_score > home_score
	return false

## Reset all players' match state
func _reset_player_match_states(team: Team) -> void:
	for player in team.roster:
		player.reset_match_state()

## Check if it's half-time or full-time
func _check_match_time() -> void:
	if current_state == MatchState.FIRST_HALF and match_time_seconds >= HALF_LENGTH_SECONDS:
		_trigger_half_time()
	
	if current_state == MatchState.SECOND_HALF and match_time_seconds >= MATCH_LENGTH_SECONDS:
		end_match()

## Trigger half-time
func _trigger_half_time() -> void:
	current_state = MatchState.HALF_TIME
	ball_in_play = false
	half_ended.emit(1)
	print("Half-time")
	
	# Auto-resume after a delay (in real implementation, you'd wait for user)
	await get_tree().create_timer(2.0).timeout
	_start_second_half()

## Start second half
func _start_second_half() -> void:
	current_state = MatchState.SECOND_HALF
	ball_in_play = true
	ball_position = Vector2.ZERO
	print("Second half started")

# ============================================================================
# LOGIC TICK SYSTEM
# ============================================================================

## Process one logic tick - the core decision-making cycle
func _process_logic_tick() -> void:
	logic_tick_count += 1
	match_tick.emit(logic_tick_count)
	
	# This is where the AI decisions happen
	# For now, just a placeholder
	_update_ball_state()
	_update_player_decisions()

## Update ball physics/position
func _update_ball_state() -> void:
	# Placeholder - will be implemented with actual physics
	pass

## Update all player AI decisions
func _update_player_decisions() -> void:
	# Placeholder - will be implemented with DecisionEngine
	pass

# ============================================================================
# SCORING
# ============================================================================

## Register a goal
func score_goal(scoring_team: Team, scorer: Player) -> void:
	var team_side = "home" if scoring_team == home_team else "away"
	
	if team_side == "home":
		home_score += 1
	else:
		away_score += 1
	
	print("GOAL! ", scorer.player_name, " scores for ", scoring_team.team_name)
	goal_scored.emit(team_side, scorer)
	
	# Reset for kickoff
	ball_position = Vector2.ZERO
	ball_possessor = null

# ============================================================================
# COMMAND METER & SHOUTS
# ============================================================================

## Regenerate command meter over time
func _regenerate_command_meter(delta: float) -> void:
	command_meter = minf(command_meter + (COMMAND_REGEN_RATE * delta), MAX_COMMAND_METER)

## Attempt to use a shout (costs command meter)
func use_shout(shout_type: String, target_player: Player) -> bool:
	var cost = SHOUT_COSTS.get(shout_type, 20.0)
	
	if command_meter < cost:
		print("Not enough command meter for shout")
		return false
	
	# Check if shout is successful (player listens)
	if DataManager.current_manager == null:
		return false
	
	var success = DecisionEngine.check_shout_success(target_player, DataManager.current_manager)
	
	if success:
		command_meter -= cost
		print("Shout successful to ", target_player.player_name)
		return true
	else:
		# Failed shouts still cost half
		command_meter -= (cost * 0.5)
		print("Shout failed - player ignored it")
		return false

# ============================================================================
# GETTERS
# ============================================================================

## Get current match time as a formatted string (MM:SS)
func get_match_time_string() -> String:
	var total_seconds = int(match_time_seconds)
	var minutes = total_seconds / 60
	var seconds = total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]

## Get current half (1 or 2)
func get_current_half() -> int:
	if current_state == MatchState.FIRST_HALF or current_state == MatchState.HALF_TIME:
		return 1
	else:
		return 2

## Check if match is active
func is_match_active() -> bool:
	return current_state in [MatchState.FIRST_HALF, MatchState.SECOND_HALF]
