## MatchEngine.gd
## Tick-based match engine - Central coordinator for match simulation
## Handles tick processing, statistics, and tactical modifiers
extends Node

# ============================================================================
# SIGNALS - For UI and visual layer
# ============================================================================
signal engine_tick(tick_data: Dictionary)
signal match_started()
signal match_paused()
signal match_resumed()
signal half_time()
signal full_time()
signal goal_scored(team: String, scorer_idx: int, minute: int, xg: float)
signal possession_changed(team: String, player_idx: int)
signal stats_updated(stats: Dictionary)
signal commentary_event(text: String, priority: int)

# ============================================================================
# CONSTANTS
# ============================================================================
const TICK_INTERVAL = 0.25  # Quarter-second ticks
const MATCH_DURATION_MINUTES = 90
const TIME_SCALE = 20.0  # 20x speed: 4.5 min real time = 90 min match
const HALF_TIME_MINUTE = 45

# Pitch dimensions (logical units)
const PITCH_WIDTH = 1000.0
const PITCH_HEIGHT = 700.0
const GOAL_WIDTH = 100.0
const PENALTY_BOX_WIDTH = 300.0
const PENALTY_BOX_DEPTH = 120.0

# ============================================================================
# MATCH STATE
# ============================================================================
var is_initialized = false
var is_running = false
var is_paused = false
var match_minute = 0.0
var current_half = 1
var stoppage_time = 0.0
var tick_accumulator = 0.0
var total_ticks = 0

# Score
var home_score: int = 0
var away_score: int = 0

# ============================================================================
# TEAM DATA
# ============================================================================
var home_team: Team = null
var away_team: Team = null
var home_lineup: Array[Player] = []  # Starting 11
var away_lineup: Array[Player] = []

# Player tokens (visual representations)
var home_tokens: Array = []
var away_tokens: Array = []

# Ball
var ball: Node2D = null
var ball_position = Vector2(PITCH_WIDTH / 2, PITCH_HEIGHT / 2)
var ball_velocity = Vector2.ZERO
var ball_possessor: Node2D = null
var possessing_team = ""  # "home", "away", or ""

# ============================================================================
# SEEDED RANDOMNESS
# ============================================================================
var rng = RandomNumberGenerator.new()
var match_seed: int = 0

# ============================================================================
# MODIFIERS SYSTEM
# ============================================================================
var modifiers = {
	"home": {
		"home_advantage": 1.05,  # 5% boost
		"morale": 1.0,          # 0.85 - 1.15
		"form": 1.0,            # 0.9 - 1.1
		"fatigue": 1.0,         # 0.7 - 1.0 (decreases over time)
		"tactics_bonus": 1.0,   # From manager's Tactical IQ
		"reputation": 1.0       # From team/player reputation
	},
	"away": {
		"home_advantage": 1.0,
		"morale": 1.0,
		"form": 1.0,
		"fatigue": 1.0,
		"tactics_bonus": 1.0,
		"reputation": 1.0
	}
}

# ============================================================================
# TACTICS (Live - changeable mid-match)
# ============================================================================
var tactics = {
	"home": {
		"formation": "4-4-2",
		"mentality": 50,           # 0=Ultra Defensive, 100=Ultra Attacking
		"pressing_intensity": 50,  # 0=Drop Deep, 100=Gegenpressing
		"passing_style": 50,       # 0=Direct/Long, 100=Possession/Short
		"defensive_line": 50,      # 0=Deep, 100=High
		"width": 50,               # 0=Narrow, 100=Wide
		"tempo": 50,               # 0=Slow, 100=Fast
		"time_wasting": false,
		"counter_attack": false
	},
	"away": {
		"formation": "4-4-2",
		"mentality": 50,
		"pressing_intensity": 50,
		"passing_style": 50,
		"defensive_line": 50,
		"width": 50,
		"tempo": 50,
		"time_wasting": false,
		"counter_attack": false
	}
}

# ============================================================================
# MATCH STATISTICS
# ============================================================================
var stats = {
	"home": {
		"shots": 0, "shots_on_target": 0, "shots_blocked": 0,
		"xg": 0.0, "xg_against": 0.0,
		"possession_ticks": 0,
		"passes_attempted": 0, "passes_completed": 0,
		"long_balls_attempted": 0, "long_balls_completed": 0,
		"crosses_attempted": 0, "crosses_completed": 0,
		"tackles_attempted": 0, "tackles_won": 0,
		"interceptions": 0, "clearances": 0,
		"corners": 0, "free_kicks": 0,
		"fouls": 0, "yellow_cards": 0, "red_cards": 0,
		"offsides": 0
	},
	"away": {
		"shots": 0, "shots_on_target": 0, "shots_blocked": 0,
		"xg": 0.0, "xg_against": 0.0,
		"possession_ticks": 0,
		"passes_attempted": 0, "passes_completed": 0,
		"long_balls_attempted": 0, "long_balls_completed": 0,
		"crosses_attempted": 0, "crosses_completed": 0,
		"tackles_attempted": 0, "tackles_won": 0,
		"interceptions": 0, "clearances": 0,
		"corners": 0, "free_kicks": 0,
		"fouls": 0, "yellow_cards": 0, "red_cards": 0,
		"offsides": 0
	}
}

# Player-specific stats (indexed by player_idx)
var player_stats = {
	"home": [],  # Array of dicts
	"away": []
}

# ============================================================================
# INITIALIZATION
# ============================================================================

func initialize_match(h_team: Team, a_team: Team, seed: int = 0) -> void:
	home_team = h_team
	away_team = a_team
	home_lineup = h_team.get_starting_11()
	away_lineup = a_team.get_starting_11()
	
	# Set seed (0 = random)
	match_seed = seed if seed != 0 else randi()
	rng.seed = match_seed
	
	# Initialize player stats
	player_stats["home"].clear()
	player_stats["away"].clear()
	for i in range(11):
		player_stats["home"].append(_create_player_stat_dict())
		player_stats["away"].append(_create_player_stat_dict())
	
	# Calculate initial modifiers
	_calculate_modifiers()
	
	# Set initial tactics from managers
	if home_team.manager:
		_apply_manager_tactics("home", home_team.manager)
	if away_team.manager:
		_apply_manager_tactics("away", away_team.manager)
	
	is_initialized = true
	print("MatchEngine initialized: ", home_team.team_name, " vs ", away_team.team_name)
	print("  Match seed: ", match_seed)

func _create_player_stat_dict() -> Dictionary:
	return {
		"passes": 0, "passes_completed": 0,
		"shots": 0, "tackles": 0, "interceptions": 0,
		"rating": 6.0, "stamina": 100.0
	}

func _apply_manager_tactics(team_key: String, manager: Manager) -> void:
	# Apply manager's tactical preferences (if they exist)
	if "tactical_preferences" in manager and manager.tactical_preferences:
		if manager.tactical_preferences.has("mentality"):
			tactics[team_key]["mentality"] = manager.tactical_preferences["mentality"]
		if manager.tactical_preferences.has("pressing"):
			tactics[team_key]["pressing_intensity"] = manager.tactical_preferences["pressing"]
	
	# Apply tactical IQ bonus (if property exists)
	if "tactical_iq" in manager:
		var tac_iq = manager.tactical_iq if manager.tactical_iq else 10
		var tac_bonus = 1.0 + (tac_iq / 100.0)  # 1.0 to 1.2
		modifiers[team_key]["tactics_bonus"] = tac_bonus
	else:
		# No tactical IQ - use default bonus
		modifiers[team_key]["tactics_bonus"] = 1.0

func _calculate_modifiers() -> void:
	# Home team gets home advantage
	modifiers["home"]["home_advantage"] = 1.05
	
	# Calculate morale modifiers (based on team morale)
	# For now, use default 1.0 - can be updated based on form/recent results
	modifiers["home"]["morale"] = 1.0
	modifiers["away"]["morale"] = 1.0
	
	# Form (can be based on recent match results)
	modifiers["home"]["form"] = 1.0
	modifiers["away"]["form"] = 1.0
	
	# Fatigue starts at 1.0
	modifiers["home"]["fatigue"] = 1.0
	modifiers["away"]["fatigue"] = 1.0

# ============================================================================
# MATCH FLOW
# ============================================================================

func start_match() -> void:
	if not is_initialized:
		push_error("Cannot start match - not initialized!")
		return
	
	is_running = true
	is_paused = false
	match_minute = 0.0
	current_half = 1
	tick_accumulator = 0.0
	total_ticks = 0
	
	emit_signal("match_started")
	print("Match started!")

func pause_match() -> void:
	if is_running and not is_paused:
		is_paused = true
		emit_signal("match_paused")

func resume_match() -> void:
	if is_running and is_paused:
		is_paused = false
		emit_signal("match_resumed")

func end_match() -> void:
	is_running = false
	emit_signal("full_time")
	print("Full time! Final score: ", home_score, " - ", away_score)
	_print_final_stats()

# ============================================================================
# TICK PROCESSING
# ============================================================================

func _process(delta: float) -> void:
	if not is_running or is_paused:
		return
	
	tick_accumulator += delta
	
	# Process ticks at fixed intervals
	while tick_accumulator >= TICK_INTERVAL:
		tick_accumulator -= TICK_INTERVAL
		_process_tick()

func _process_tick() -> void:
	total_ticks += 1
	
	# Update match time (scaled)
	var real_time_per_tick = TICK_INTERVAL
	var match_time_per_tick = (real_time_per_tick * TIME_SCALE) / 60.0  # Convert to minutes
	match_minute += match_time_per_tick
	
	# Check for half-time
	if current_half == 1 and match_minute >= HALF_TIME_MINUTE:
		_trigger_half_time()
		return
	
	# Check for full-time
	if current_half == 2 and match_minute >= MATCH_DURATION_MINUTES:
		end_match()
		return
	
	# Update fatigue
	_update_fatigue()
	
	# Track possession
	if possessing_team != "":
		stats[possessing_team]["possession_ticks"] += 1
	
	# Build tick data
	var tick_data = _build_tick_data()
	
	# Emit tick for AI and visual layer
	emit_signal("engine_tick", tick_data)
	
	# Periodic stats update (every 20 ticks = 5 seconds)
	if total_ticks % 20 == 0:
		emit_signal("stats_updated", _get_stats_summary())

func _build_tick_data() -> Dictionary:
	return {
		"tick": total_ticks,
		"minute": int(match_minute),
		"half": current_half,
		"ball_position": ball_position,
		"ball_velocity": ball_velocity,
		"ball_possessor": ball_possessor,
		"possessing_team": possessing_team,
		"home_score": home_score,
		"away_score": away_score
	}

func _trigger_half_time() -> void:
	is_paused = true
	emit_signal("half_time")
	print("Half-time! Score: ", home_score, " - ", away_score)
	
	# Auto-resume after 2 seconds (or wait for user input)
	await get_tree().create_timer(2.0).timeout
	
	# Start second half
	current_half = 2
	match_minute = HALF_TIME_MINUTE
	
	# Reset fatigue slightly
	modifiers["home"]["fatigue"] = minf(modifiers["home"]["fatigue"] + 0.1, 1.0)
	modifiers["away"]["fatigue"] = minf(modifiers["away"]["fatigue"] + 0.1, 1.0)
	
	resume_match()
	print("Second half started!")

func _update_fatigue() -> void:
	# Fatigue increases gradually over the match
	# Drops from 1.0 to ~0.75 by the end of 90 minutes
	var fatigue_rate = 0.25 / (MATCH_DURATION_MINUTES * 4)  # Per tick
	modifiers["home"]["fatigue"] = maxf(modifiers["home"]["fatigue"] - fatigue_rate, 0.7)
	modifiers["away"]["fatigue"] = maxf(modifiers["away"]["fatigue"] - fatigue_rate, 0.7)

# ============================================================================
# POSSESSION MANAGEMENT
# ============================================================================

func set_possession(team: String, possessor: Node2D) -> void:
	var old_team = possessing_team
	possessing_team = team
	ball_possessor = possessor
	
	if old_team != team and team != "":
		var player_idx = _get_player_index(possessor, team)
		emit_signal("possession_changed", team, player_idx)

func _get_player_index(token: Node2D, team: String) -> int:
	var tokens = home_tokens if team == "home" else away_tokens
	return tokens.find(token)

# ============================================================================
# STATISTICS RECORDING
# ============================================================================

func record_shot(team: String, player_idx: int, on_target: bool, xg_value: float) -> void:
	stats[team]["shots"] += 1
	if on_target:
		stats[team]["shots_on_target"] += 1
	stats[team]["xg"] += xg_value
	
	# Opponent xG against
	var opp_team = "away" if team == "home" else "home"
	stats[opp_team]["xg_against"] += xg_value
	
	# Player stats
	if player_idx >= 0 and player_idx < player_stats[team].size():
		player_stats[team][player_idx]["shots"] += 1

func record_pass(team: String, player_idx: int, success: bool, is_long: bool = false) -> void:
	if is_long:
		stats[team]["long_balls_attempted"] += 1
		if success:
			stats[team]["long_balls_completed"] += 1
	else:
		stats[team]["passes_attempted"] += 1
		if success:
			stats[team]["passes_completed"] += 1
	
	# Player stats
	if player_idx >= 0 and player_idx < player_stats[team].size():
		player_stats[team][player_idx]["passes"] += 1
		if success:
			player_stats[team][player_idx]["passes_completed"] += 1

func record_tackle(team: String, player_idx: int, success: bool, is_foul: bool = false) -> void:
	stats[team]["tackles_attempted"] += 1
	if success:
		stats[team]["tackles_won"] += 1
	
	if is_foul:
		stats[team]["fouls"] += 1
	
	# Player stats
	if player_idx >= 0 and player_idx < player_stats[team].size():
		player_stats[team][player_idx]["tackles"] += 1

func record_interception(team: String, player_idx: int) -> void:
	stats[team]["interceptions"] += 1
	if player_idx >= 0 and player_idx < player_stats[team].size():
		player_stats[team][player_idx]["interceptions"] += 1

func record_card(team: String, player_idx: int, is_red: bool) -> void:
	if is_red:
		stats[team]["red_cards"] += 1
	else:
		stats[team]["yellow_cards"] += 1

func record_goal(team: String, scorer_idx: int, xg_value: float) -> void:
	if team == "home":
		home_score += 1
	else:
		away_score += 1
	
	var minute = int(match_minute)
	emit_signal("goal_scored", team, scorer_idx, minute, xg_value)
	
	var team_obj = home_team if team == "home" else away_team
	var lineup = home_lineup if team == "home" else away_lineup
	var scorer_name = lineup[scorer_idx].player_name if scorer_idx >= 0 and scorer_idx < lineup.size() else "Unknown"
	
	print("GOAL! ", team_obj.team_name, " - ", scorer_name, " (", minute, "')")
	
	# Commentary
	emit_signal("commentary_event", "GOAL! " + scorer_name + " scores for " + team_obj.team_name + "!", 3)

# ============================================================================
# ACTION MODIFIERS
# ============================================================================

func get_action_modifier(team: String, player_data: Player) -> float:
	var mod = 1.0
	
	# Apply all team modifiers
	for key in modifiers[team]:
		mod *= modifiers[team][key]
	
	# Player-specific modifiers (stamina, morale)
	if player_data:
		# Check stamina
		if "current_stamina_percent" in player_data:
			var stamina_factor = player_data.current_stamina_percent / 100.0
			mod *= (0.7 + stamina_factor * 0.3)  # 70-100% effectiveness based on stamina
		
		# Check morale (Player class uses 'current_morale')
		if "current_morale" in player_data:
			var morale_factor = player_data.current_morale / 100.0
			mod *= (0.85 + morale_factor * 0.3)  # 85-115% effectiveness based on morale
	
	return mod

# ============================================================================
# TACTICAL POSITION CALCULATION
# ============================================================================

func get_tactical_position(player_idx: int, team: String) -> Vector2:
	# Get base formation position
	var lineup = home_lineup if team == "home" else away_lineup
	if player_idx < 0 or player_idx >= lineup.size():
		return Vector2.ZERO
	
	var player = lineup[player_idx]
	var formation_pos = _get_formation_position(player.current_position, team == "home")
	
	# Adjust based on tactics
	var tac = tactics[team]
	var adjusted_pos = formation_pos
	
	# Mentality adjustment (push forward/back)
	var mentality_shift = (tac["mentality"] - 50.0) / 100.0  # -0.5 to +0.5
	if team == "home":
		adjusted_pos.x += mentality_shift * 100.0
	else:
		adjusted_pos.x -= mentality_shift * 100.0
	
	# Width adjustment
	var width_factor = tac["width"] / 100.0  # 0 to 1
	var center_x = PITCH_WIDTH / 2.0
	var x_diff = adjusted_pos.x - center_x
	adjusted_pos.x = center_x + (x_diff * (0.7 + width_factor * 0.6))  # 70% to 130% width
	
	return adjusted_pos

func _get_formation_position(position: String, is_home: bool) -> Vector2:
	# Basic 4-4-2 formation positions
	var base_x = PITCH_WIDTH / 2.0
	var base_y = PITCH_HEIGHT / 2.0
	var multiplier = 1.0 if is_home else -1.0
	
	match position:
		"GK":
			return Vector2(base_x + multiplier * 450, base_y)
		"LB":
			return Vector2(base_x + multiplier * 350, base_y - 200)
		"CB1":
			return Vector2(base_x + multiplier * 350, base_y - 60)
		"CB2":
			return Vector2(base_x + multiplier * 350, base_y + 60)
		"RB":
			return Vector2(base_x + multiplier * 350, base_y + 200)
		"LM":
			return Vector2(base_x + multiplier * 150, base_y - 200)
		"CM1":
			return Vector2(base_x + multiplier * 150, base_y - 60)
		"CM2":
			return Vector2(base_x + multiplier * 150, base_y + 60)
		"RM":
			return Vector2(base_x + multiplier * 150, base_y + 200)
		"ST1":
			return Vector2(base_x + multiplier * 50, base_y - 80)
		"ST2":
			return Vector2(base_x + multiplier * 50, base_y + 80)
	
	return Vector2(base_x, base_y)

# ============================================================================
# STATS RETRIEVAL
# ============================================================================

func _get_stats_summary() -> Dictionary:
	var total_poss = stats["home"]["possession_ticks"] + stats["away"]["possession_ticks"]
	var home_poss = 0.0
	var away_poss = 0.0
	
	if total_poss > 0:
		home_poss = (float(stats["home"]["possession_ticks"]) / total_poss) * 100.0
		away_poss = (float(stats["away"]["possession_ticks"]) / total_poss) * 100.0
	
	return {
		"home_possession": home_poss,
		"away_possession": away_poss,
		"home_stats": stats["home"],
		"away_stats": stats["away"],
		"minute": int(match_minute),
		"half": current_half
	}

func _print_final_stats() -> void:
	print("\n=== MATCH STATISTICS ===")
	print("Possession: ", int(_get_stats_summary()["home_possession"]), "% - ", int(_get_stats_summary()["away_possession"]), "%")
	print("Shots: ", stats["home"]["shots"], " - ", stats["away"]["shots"])
	print("Shots on Target: ", stats["home"]["shots_on_target"], " - ", stats["away"]["shots_on_target"])
	print("xG: ", "%.2f" % stats["home"]["xg"], " - ", "%.2f" % stats["away"]["xg"])
	print("Passes: ", stats["home"]["passes_completed"], "/", stats["home"]["passes_attempted"], " - ", stats["away"]["passes_completed"], "/", stats["away"]["passes_attempted"])
	print("========================\n")

# ============================================================================
# VISUAL LAYER INTEGRATION
# ============================================================================

func register_ball(ball_ref: Node2D) -> void:
	ball = ball_ref

func register_tokens(home: Array, away: Array) -> void:
	home_tokens = home
	away_tokens = away

func update_ball_position(pos: Vector2) -> void:
	ball_position = pos

func update_ball_velocity(vel: Vector2) -> void:
	ball_velocity = vel
