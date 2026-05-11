## PlayerAI.gd
## Enhanced AI brain for player tokens with tick-based processing
## Upgraded with pressure awareness, better passing, and role-based behavior
class_name PlayerAI
extends Node

# ============================================================================
# SIGNALS
# ============================================================================
signal state_changed(old_state: int, new_state: int)

# ============================================================================
# CONSTANTS
# ============================================================================
# Distances (in pixels)
const BALL_CONTROL_DIST = 30.0
const CLOSE_SUPPORT_DIST = 100.0
const MID_SUPPORT_DIST = 200.0
const FAR_SUPPORT_DIST = 350.0
const MARKING_DIST = 50.0
const PRESSING_TRIGGER_DIST = 120.0
const TACKLE_RANGE = 35.0
const SHOOT_CLOSE_DIST = 150.0
const SHOOT_MED_DIST = 250.0
const SHOOT_FAR_DIST = 350.0
const SHORT_PASS_MAX = 200.0
const LONG_PASS_MIN = 200.0
const LONG_PASS_MAX = 500.0

# Goalkeeper constants
const GK_PENALTY_AREA_WIDTH = 300.0
const GK_PENALTY_AREA_DEPTH = 120.0
const GK_SAVE_RANGE = 100.0
const GK_RUSH_DISTANCE = 150.0
const GK_DISTRIBUTION_RANGE = 400.0

# Speed multipliers
const SPRINT_MULT = 1.0
const JOG_MULT = 0.6
const WALK_MULT = 0.35

# Decision cooldowns (in ticks)
const MIN_DECISION_TICKS = 1
const MAX_DECISION_TICKS = 3
const POST_ACTION_COOLDOWN = 2

# ============================================================================
# AI STATES - ENHANCED
# ============================================================================
enum AIState {
	IDLE,
	POSITIONING,       # Moving to tactical position
	WITH_BALL,         # Has possession
	DRIBBLING,         # Moving with ball
	PASSING,           # Executing pass
	SHOOTING,          # Taking a shot
	RECEIVING,         # Moving to receive pass
	CHASING_LOOSE,     # Going for loose ball
	PRESSING,          # Pressuring opponent with ball
	MARKING,           # Marking a specific opponent
	COVERING,          # Covering space/zone
	TRACKING_BACK,     # Recovering defensive position
	SUPPORTING,        # Supporting teammate with ball
	MAKING_RUN,        # Making attacking run
	GK_POSITIONING,    # GK positioning
	GK_SAVING,         # GK attempting save
	GK_CATCHING,       # GK catching loose ball
	GK_DISTRIBUTING,   # GK distributing ball
}

var current_state: AIState = AIState.IDLE
var previous_state: AIState = AIState.IDLE

# ============================================================================
# REFERENCES
# ============================================================================
var player_token: CharacterBody2D = null
var player_data: Player = null
var match_scene: Node2D = null
var match_engine: Node = null
var pitch: Node2D = null
var ball: Area2D = null

# Team context
var team_key: String = ""  # "home" or "away"
var is_home_team: bool = true
var player_idx: int = 0  # Index in lineup (0 = GK)
var position_role: String = ""  # "GK", "DEF", "MID", "ATT"

# Team references
var teammates: Array[Node2D] = []
var opponents: Array[Node2D] = []

# ============================================================================
# AI STATE VARIABLES
# ============================================================================
# Targets and positions
var target_position: Vector2 = Vector2.ZERO
var formation_position: Vector2 = Vector2.ZERO
var tactical_position: Vector2 = Vector2.ZERO
var pass_target: Node2D = null
var marking_target: Node2D = null
var support_target: Node2D = null

# Movement
var current_speed_mult: float = JOG_MULT
var base_speed: float = 100.0

# Decision timing
var ticks_since_decision: int = 0
var decision_cooldown: int = 1
var action_cooldown: int = 0

# Spatial awareness (updated each tick)
var distance_to_ball: float = 999.0
var distance_to_own_goal: float = 999.0
var distance_to_opp_goal: float = 999.0
var nearby_opponents: Array[Node2D] = []
var nearby_teammates: Array[Node2D] = []
var pressure_level: float = 0.0  # 0-1, how much pressure from opponents

# Cached calculations
var own_goal_pos: Vector2 = Vector2.ZERO
var opp_goal_pos: Vector2 = Vector2.ZERO

# ============================================================================
# INITIALIZATION
# ============================================================================

func setup(
	token: CharacterBody2D,
	data: Player,
	scene: Node2D,
	home: bool
) -> void:
	player_token = token
	player_data = data
	match_scene = scene
	is_home_team = home
	team_key = "home" if home else "away"
	
	# Get references from match scene
	if match_scene:
		pitch = match_scene.pitch
		ball = match_scene.ball
		match_engine = match_scene.match_engine if "match_engine" in match_scene else null
		
		# Get player index from token
		if player_token and "player_idx" in player_token:
			player_idx = player_token.player_idx
		
		# Determine position role
		if player_data:
			var pos = player_data.current_position
			if pos == "GK":
				position_role = "GK"
			elif pos in ["LB", "CB1", "CB2", "RB"]:
				position_role = "DEF"
			elif pos in ["LM", "CM1", "CM2", "RM"]:
				position_role = "MID"
			else:
				position_role = "ATT"
	
	# Calculate speeds
	_calculate_speeds()
	
	# Set goal positions
	if pitch:
		own_goal_pos = pitch.get_home_goal_position() if is_home_team else pitch.get_away_goal_position()
		opp_goal_pos = pitch.get_away_goal_position() if is_home_team else pitch.get_home_goal_position()
	
	# Connect to match engine tick if available
	if match_engine and match_engine.has_signal("engine_tick"):
		match_engine.engine_tick.connect(_on_engine_tick)
	
	current_state = AIState.POSITIONING
	print("      AI setup complete: ", player_data.player_name, " (", position_role, ")")

func _calculate_speeds() -> void:
	if not player_data:
		base_speed = 100.0
		return
	
	var speed_stat = player_data.speed if player_data.speed else 10
	base_speed = 50.0 + (speed_stat * 5.0)  # 55-150 range

func set_ball(ball_ref: Area2D) -> void:
	ball = ball_ref

func set_team_references(team_mates: Array[Node2D], opps: Array[Node2D]) -> void:
	teammates = team_mates
	opponents = opps

func set_formation_position(pos: Vector2) -> void:
	formation_position = pos
	if current_state == AIState.IDLE or current_state == AIState.POSITIONING:
		target_position = pos

# ============================================================================
# TICK-BASED PROCESSING
# ============================================================================

func _on_engine_tick(tick_data: Dictionary) -> void:
	if not player_token or not is_instance_valid(player_token):
		return
	
	# Update spatial awareness
	_update_awareness(tick_data)
	
	# Decrement cooldowns
	if action_cooldown > 0:
		action_cooldown -= 1
	
	ticks_since_decision += 1
	
	# Make decision if cooldown expired
	if ticks_since_decision >= decision_cooldown and action_cooldown == 0:
		_make_decision(tick_data)
		ticks_since_decision = 0
		decision_cooldown = _calculate_decision_cooldown()

func _calculate_decision_cooldown() -> int:
	# Faster decisions when under pressure or with ball
	if current_state == AIState.WITH_BALL or pressure_level > 0.5:
		return MIN_DECISION_TICKS
	return MIN_DECISION_TICKS + randi_range(0, MAX_DECISION_TICKS - MIN_DECISION_TICKS)

# ============================================================================
# AWARENESS SYSTEM
# ============================================================================

func _update_awareness(tick_data: Dictionary) -> void:
	if not player_token:
		return
	
	var my_pos = player_token.global_position
	
	# Ball distance
	var ball_pos: Vector2 = tick_data.get("ball_position", Vector2.ZERO)
	distance_to_ball = my_pos.distance_to(ball_pos)
	
	# Goal distances
	distance_to_own_goal = my_pos.distance_to(own_goal_pos)
	distance_to_opp_goal = my_pos.distance_to(opp_goal_pos)
	
	# Find nearby players
	nearby_opponents.clear()
	nearby_teammates.clear()
	
	for opp in opponents:
		if not is_instance_valid(opp):
			continue
		var dist = my_pos.distance_to(opp.global_position)
		if dist < PRESSING_TRIGGER_DIST * 2:
			nearby_opponents.append(opp)
	
	for tm in teammates:
		if not is_instance_valid(tm) or tm == player_token:
			continue
		var dist = my_pos.distance_to(tm.global_position)
		if dist < FAR_SUPPORT_DIST:
			nearby_teammates.append(tm)
	
	# Calculate pressure level
	pressure_level = 0.0
	for opp in nearby_opponents:
		var dist = my_pos.distance_to(opp.global_position)
		if dist < PRESSING_TRIGGER_DIST:
			pressure_level += (1.0 - dist / PRESSING_TRIGGER_DIST) * 0.5
	pressure_level = minf(pressure_level, 1.0)
	
	# Update tactical position from match engine
	if match_engine and match_engine.has_method("get_tactical_position"):
		tactical_position = match_engine.get_tactical_position(player_idx, team_key)

# ============================================================================
# DECISION MAKING
# ============================================================================

func _make_decision(tick_data: Dictionary) -> void:
	if not ball or not player_token:
		return
	
	# Goalkeepers use specialized logic
	if position_role == "GK":
		_make_gk_decision(tick_data)
		return
	
	var old_state = current_state
	var possessing_team: String = tick_data.get("possessing_team", "")
	var ball_possessor: Node2D = tick_data.get("ball_possessor", null)
	
	# Debug: Print decision info occasionally
	if randi() % 40 == 0:  # ~2.5% of decisions
		print("[AI] ", player_data.player_name, " - State: ", AIState.keys()[current_state], 
			  " | Poss: ", possessing_team, " | HasBall: ", player_token.has_ball)
	
	# Check if I have the ball
	if ball_possessor == player_token or player_token.has_ball:
		_decide_with_ball(tick_data)
		return
	
	# My team has ball
	if possessing_team == team_key:
		_decide_team_has_ball(tick_data, ball_possessor)
		return
	
	# Opponent has ball
	if possessing_team != "" and possessing_team != team_key:
		_decide_opponent_has_ball(tick_data, ball_possessor)
		return
	
	# Ball is loose
	_decide_loose_ball(tick_data)

# ============================================================================
# WITH BALL DECISIONS
# ============================================================================

func _decide_with_ball(tick_data: Dictionary) -> void:
	_change_state(AIState.WITH_BALL)
	
	# Quick decisions with ball
	var distance_to_goal = distance_to_opp_goal
	
	# Debug: Print WITH_BALL state
	print("[WITH_BALL] ", player_data.player_name, " has ball | Dist to goal: ", int(distance_to_goal), 
		  " | Pressure: ", "%.2f" % pressure_level)
	
	# Try to shoot if in range and has clear shot
	if distance_to_goal < SHOOT_MED_DIST and _has_clear_shot():
		print("  → Attempting shot...")
		if _try_shoot(tick_data):
			return
	
	# Try to pass if under pressure or good target available
	if pressure_level > 0.4 or _has_good_pass_target():
		print("  → Attempting pass (pressure: ", "%.2f" % pressure_level, ")...")
		if _try_pass(tick_data, false):
			return
	
	# Dribble forward
	print("  → Dribbling forward...")
	_execute_dribble(tick_data)

func _try_shoot(tick_data: Dictionary) -> bool:
	var distance = distance_to_opp_goal
	
	# Calculate xG (expected goals)
	var xg = _calculate_xg(distance, pressure_level)
	
	# Decision to shoot
	var shot_stat = _get_stat("shot_accuracy")
	var intelligence = _get_stat("intelligence")
	var success_prob = (shot_stat * 4.0 + intelligence) / 120.0
	
	# Apply pressure penalty
	success_prob *= (1.0 - pressure_level * 0.3)
	
	# Apply match engine modifiers
	if match_engine and match_engine.has_method("get_action_modifier"):
		success_prob *= match_engine.get_action_modifier(team_key, player_data)
	
	success_prob = clampf(success_prob, 0.1, 0.95)
	
	var roll = randf()
	var success = roll < success_prob
	
	# Execute shot
	var on_target = success
	var is_goal = false
	
	if on_target:
		# Check if it's a goal (based on xG)
		is_goal = randf() < xg
	
	# Actually kick the ball toward goal
	if ball:
		var direction = (opp_goal_pos - player_token.global_position).normalized()
		var power = 600.0  # Shot power
		
		# Add some randomness for off-target shots
		if not on_target:
			var angle_offset = randf_range(-0.5, 0.5)  # Radians
			direction = direction.rotated(angle_offset)
		
		ball.shoot(direction, power)
	
	# Release ball from player
	if player_token.has_method("release_ball"):
		player_token.release_ball()
	
	# Record shot
	if player_token and player_token.has_method("record_shot"):
		player_token.record_shot(on_target, is_goal)
	
	# Visual feedback
	if is_goal:
		print(player_data.player_name, " SCORES! (xG: ", "%.2f" % xg, ")")
	elif on_target:
		print(player_data.player_name, " shot on target (saved)")
	else:
		print(player_data.player_name, " shot off target")
	
	action_cooldown = POST_ACTION_COOLDOWN * 2
	return true

func _calculate_xg(distance: float, pressure: float) -> float:
	# Base xG on distance
	var base_xg = 1.0
	
	if distance < SHOOT_CLOSE_DIST:
		base_xg = 0.5  # 50% from close
	elif distance < SHOOT_MED_DIST:
		base_xg = 0.25  # 25% from medium
	else:
		base_xg = 0.1  # 10% from far
	
	# Reduce by pressure
	base_xg *= (1.0 - pressure * 0.4)
	
	# Reduce by angle (simple approximation)
	var angle_factor = 1.0
	if own_goal_pos.x != opp_goal_pos.x:
		var lateral_dist = abs(player_token.global_position.x - opp_goal_pos.x)
		angle_factor = clampf(1.0 - (lateral_dist / 200.0), 0.5, 1.0)
	
	base_xg *= angle_factor
	
	return clampf(base_xg, 0.01, 0.99)

func _has_clear_shot() -> bool:
	# Check if path to goal is relatively clear
	var my_pos = player_token.global_position
	var dir_to_goal = (opp_goal_pos - my_pos).normalized()
	
	# Check for opponents in shooting lane
	var blocking_opponents = 0
	for opp in nearby_opponents:
		if not is_instance_valid(opp):
			continue
		var to_opp = (opp.global_position - my_pos).normalized()
		var dot = dir_to_goal.dot(to_opp)
		if dot > 0.8:  # Opponent in front
			var dist = my_pos.distance_to(opp.global_position)
			if dist < 100:
				blocking_opponents += 1
	
	return blocking_opponents < 2

func _has_good_pass_target() -> bool:
	return _find_best_pass_target() != null

func _try_pass(tick_data: Dictionary, is_gk_distribution: bool = false) -> bool:
	var target = _find_best_pass_target()
	
	if not target:
		return false
	
	# Calculate pass success
	var distance = player_token.global_position.distance_to(target.global_position)
	var is_long = distance > SHORT_PASS_MAX
	
	var pass_stat = _get_stat("long_pass") if is_long else _get_stat("short_pass")
	var vision = _get_stat("vision")
	var success_prob = (pass_stat * 4.0 + vision) / 120.0
	
	# Apply pressure penalty
	if not is_gk_distribution:
		success_prob *= (1.0 - pressure_level * 0.2)
	
	# Apply modifiers
	if match_engine and match_engine.has_method("get_action_modifier"):
		success_prob *= match_engine.get_action_modifier(team_key, player_data)
	
	success_prob = clampf(success_prob, 0.2, 0.95)
	
	var success = randf() < success_prob
	
	# Record pass
	if player_token and player_token.has_method("record_pass"):
		player_token.record_pass(success, is_long)
	
	# Execute pass and transfer ball
	if success:
		pass_target = target
		_change_state(AIState.PASSING)
		
		print("    ✅ Pass successful to ", target.player_data.player_name if target.has("player_data") else "teammate")
		
		# Actually move the ball toward target
		if ball:
			var pass_power = 400.0 if is_long else 250.0
			ball.pass_ball(target.global_position, pass_power)
		
		# Release from current player
		if player_token.has_method("release_ball"):
			player_token.release_ball()
		
		# Target will pick up ball when it gets close (handled by MatchScene._check_for_ball_pickup)
		# But also update match engine immediately for possession stats
		if match_engine and match_engine.has_method("set_possession"):
			match_engine.set_possession(team_key, target)
	else:
		print("    ❌ Pass failed!")
		# Failed pass - ball goes in random direction
		if ball:
			var random_angle = randf_range(-PI/2, PI/2)
			var target_dir = (target.global_position - player_token.global_position).normalized()
			var failed_dir = target_dir.rotated(random_angle)
			ball.kick(failed_dir, 200.0)
		
		if player_token.has_method("release_ball"):
			player_token.release_ball()
	
	action_cooldown = POST_ACTION_COOLDOWN
	return true

func _find_best_pass_target() -> Node2D:
	var best_target: Node2D = null
	var best_score: float = -999.0
	
	for tm in teammates:
		if not is_instance_valid(tm) or tm == player_token:
			continue
		
		var tm_pos = tm.global_position
		var dist = player_token.global_position.distance_to(tm_pos)
		
		# Skip if too far
		if dist > LONG_PASS_MAX:
			continue
		
		# Calculate forward progress
		var forward_progress = _get_forward_progress(tm_pos)
		var my_progress = _get_forward_progress(player_token.global_position)
		var progress_gain = forward_progress - my_progress
		
		# Count opponents near target
		var opp_pressure = 0.0
		for opp in opponents:
			if not is_instance_valid(opp):
				continue
			var dist_to_tm = tm_pos.distance_to(opp.global_position)
			if dist_to_tm < 60:
				opp_pressure += 1.0
		
		# Score: forward progress - distance penalty - opponent pressure
		var score = progress_gain - (dist * 0.1) - (opp_pressure * 30.0)
		
		# Bonus for attackers
		if tm.has_method("get_position_on_field"):
			var pos = tm.get_position_on_field()
			if pos in ["ST1", "ST2"]:
				score += 20.0
		
		if score > best_score:
			best_score = score
			best_target = tm
	
	return best_target

func _get_forward_progress(pos: Vector2) -> float:
	# How far forward toward opponent goal (horizontal pitch)
	if is_home_team:
		# Home attacks right (positive X direction)
		return pos.x - own_goal_pos.x  # More positive = more forward
	else:
		# Away attacks left (negative X direction)
		return own_goal_pos.x - pos.x  # More positive = more forward

func _execute_dribble(tick_data: Dictionary) -> void:
	_change_state(AIState.DRIBBLING)
	
	# Dribble toward opponent goal
	var direction = (opp_goal_pos - player_token.global_position).normalized()
	target_position = player_token.global_position + (direction * 50.0)
	
	current_speed_mult = 0.5  # Slower when dribbling
	player_token.set_target_position(target_position)

# ============================================================================
# TEAM HAS BALL DECISIONS
# ============================================================================

func _decide_team_has_ball(tick_data: Dictionary, ball_carrier: Node2D) -> void:
	# Support teammate or make a run
	
	# Attackers make runs
	if position_role == "ATT" and randf() < 0.3:
		_execute_attacking_run(tick_data)
		return
	
	# Otherwise support
	_execute_supporting(tick_data, ball_carrier)

func _execute_attacking_run(tick_data: Dictionary) -> void:
	_change_state(AIState.MAKING_RUN)
	
	# Run toward opponent goal, slightly wide
	var lateral_offset = randf_range(-100, 100)
	target_position = Vector2(
		opp_goal_pos.x + lateral_offset,
		opp_goal_pos.y + randf_range(-50, 50)
	)
	
	current_speed_mult = SPRINT_MULT
	player_token.set_target_position(target_position)

func _execute_supporting(tick_data: Dictionary, ball_carrier: Node2D) -> void:
	_change_state(AIState.SUPPORTING)
	
	if not is_instance_valid(ball_carrier):
		target_position = tactical_position
	else:
		# Position to receive pass
		var carrier_pos = ball_carrier.global_position
		var angle = randf_range(-PI/3, PI/3)
		var support_dist = MID_SUPPORT_DIST
		var offset = Vector2(cos(angle), sin(angle)) * support_dist
		target_position = carrier_pos + offset
	
	current_speed_mult = JOG_MULT
	player_token.set_target_position(target_position)

# ============================================================================
# OPPONENT HAS BALL DECISIONS
# ============================================================================

func _decide_opponent_has_ball(tick_data: Dictionary, ball_carrier: Node2D) -> void:
	if not is_instance_valid(ball_carrier):
		_decide_loose_ball(tick_data)
		return
	
	var dist_to_carrier = player_token.global_position.distance_to(ball_carrier.global_position)
	
	# Decide whether to press
	if _should_press(dist_to_carrier):
		_execute_pressing(tick_data, ball_carrier)
		return
	
	# Mark nearby opponents or cover space
	var nearby_threat = _find_marking_target()
	if nearby_threat:
		_execute_marking(tick_data, nearby_threat)
		return
	
	# Default: defensive positioning
	_execute_defensive_positioning(tick_data)

func _should_press(dist_to_carrier: float) -> bool:
	# Role-based pressing
	match position_role:
		"ATT":
			return dist_to_carrier < PRESSING_TRIGGER_DIST * 1.5
		"MID":
			return dist_to_carrier < PRESSING_TRIGGER_DIST
		"DEF":
			return dist_to_carrier < PRESSING_TRIGGER_DIST * 0.7
		"GK":
			return false
	return false

func _execute_pressing(tick_data: Dictionary, ball_carrier: Node2D) -> void:
	_change_state(AIState.PRESSING)
	marking_target = ball_carrier
	
	target_position = ball_carrier.global_position
	current_speed_mult = SPRINT_MULT
	player_token.set_target_position(target_position)
	
	# Try to tackle if close
	var dist = player_token.global_position.distance_to(ball_carrier.global_position)
	if dist < TACKLE_RANGE:
		_attempt_tackle(ball_carrier)

func _attempt_tackle(opponent: Node2D) -> void:
	if action_cooldown > 0:
		return
	
	var tackling = _get_stat("tackling")
	var strength = _get_stat("strength")
	var intelligence = _get_stat("intelligence")
	
	# Opponent dribbling stats
	var opp_dribbling = 10.0
	var opp_strength = 10.0
	if opponent.has_method("get_effective_stat"):
		opp_dribbling = opponent.get_effective_stat("dribbling")
		opp_strength = opponent.get_effective_stat("strength")
	
	# Success calculation
	var attack_rating = (tackling * 2.0 + strength + intelligence) / 4.0
	var defend_rating = (opp_dribbling * 2.0 + opp_strength) / 3.0
	var success_prob = attack_rating / (attack_rating + defend_rating)
	
	# Apply modifiers
	if match_engine and match_engine.has_method("get_action_modifier"):
		success_prob *= match_engine.get_action_modifier(team_key, player_data)
	
	success_prob = clampf(success_prob, 0.15, 0.85)
	
	var success = randf() < success_prob
	var is_foul = randf() < (0.08 if success else 0.3)
	
	# Record tackle
	if player_token and player_token.has_method("record_tackle"):
		player_token.record_tackle(success, is_foul)
	
	if success and not is_foul:
		# Win ball
		if match_engine and match_engine.has_method("set_possession"):
			match_engine.set_possession(team_key, player_token)
		player_token.give_ball()
	
	action_cooldown = POST_ACTION_COOLDOWN * 2

func _find_marking_target() -> Node2D:
	var best_target: Node2D = null
	var best_score: float = -999.0
	
	for opp in nearby_opponents:
		if not is_instance_valid(opp):
			continue
		
		var dist_to_me = player_token.global_position.distance_to(opp.global_position)
		if dist_to_me > 200:
			continue
		
		var dist_to_goal = opp.global_position.distance_to(own_goal_pos)
		
		# Score: prefer close opponents who threaten goal
		var score = -dist_to_me * 0.4 - dist_to_goal * 0.3
		
		if dist_to_goal < 250:
			score += 50
		
		if score > best_score:
			best_score = score
			best_target = opp
	
	return best_target

func _execute_marking(tick_data: Dictionary, target: Node2D) -> void:
	_change_state(AIState.MARKING)
	marking_target = target
	
	var target_pos = target.global_position
	var to_goal = (own_goal_pos - target_pos).normalized()
	
	# Position between opponent and our goal
	target_position = target_pos + to_goal * MARKING_DIST
	current_speed_mult = JOG_MULT
	player_token.set_target_position(target_position)

func _execute_defensive_positioning(tick_data: Dictionary) -> void:
	_change_state(AIState.COVERING)
	
	# Get tactical position
	target_position = tactical_position
	current_speed_mult = JOG_MULT
	player_token.set_target_position(target_position)

# ============================================================================
# LOOSE BALL DECISIONS
# ============================================================================

func _decide_loose_ball(tick_data: Dictionary) -> void:
	# Chase if close enough (role-based)
	var chase_dist = _get_chase_distance()
	
	if distance_to_ball < chase_dist:
		_execute_chase_ball(tick_data)
	else:
		_execute_defensive_positioning(tick_data)

func _get_chase_distance() -> float:
	match position_role:
		"GK":
			return 100.0
		"DEF":
			return 150.0
		"MID":
			return 250.0
		"ATT":
			return 350.0
	return 200.0

func _execute_chase_ball(tick_data: Dictionary) -> void:
	_change_state(AIState.CHASING_LOOSE)
	
	var ball_pos: Vector2 = tick_data.get("ball_position", Vector2.ZERO)
	target_position = ball_pos
	current_speed_mult = SPRINT_MULT
	player_token.set_target_position(target_position)

# ============================================================================
# GOALKEEPER DECISIONS
# ============================================================================

func _make_gk_decision(tick_data: Dictionary) -> void:
	var ball_pos: Vector2 = tick_data.get("ball_position", Vector2.ZERO)
	var my_pos = player_token.global_position
	var dist_to_ball = my_pos.distance_to(ball_pos)
	var ball_possessor: Node2D = tick_data.get("ball_possessor", null)
	
	# If GK has the ball
	if ball_possessor == player_token or player_token.has_ball:
		if _try_pass(tick_data, true):
			return
		_execute_gk_kick(tick_data)
		return
	
	# Ball very close - attempt save/collection
	if dist_to_ball < GK_SAVE_RANGE:
		_change_state(AIState.GK_SAVING)
		target_position = ball_pos
		current_speed_mult = 1.2
		player_token.set_target_position(target_position)
		return
	
	# Position based on ball location
	_execute_gk_positioning(tick_data, ball_pos)

func _execute_gk_positioning(tick_data: Dictionary, ball_pos: Vector2) -> void:
	_change_state(AIState.GK_POSITIONING)
	
	var goal_center = own_goal_pos
	var to_ball = ball_pos - goal_center
	var dist = to_ball.length()
	
	# Come off line based on ball distance
	var come_off = clampf(dist / 10.0, 10, 80)
	var gk_pos = goal_center + to_ball.normalized() * come_off
	
	# Clamp to goal area
	gk_pos.y = clampf(gk_pos.y, goal_center.y - 60, goal_center.y + 60)
	
	if is_home_team:
		gk_pos.x = clampf(gk_pos.x, own_goal_pos.x - 60, own_goal_pos.x + 60)
	else:
		gk_pos.x = clampf(gk_pos.x, own_goal_pos.x - 60, own_goal_pos.x + 60)
	
	target_position = gk_pos
	current_speed_mult = JOG_MULT
	player_token.set_target_position(target_position)

func _execute_gk_kick(tick_data: Dictionary) -> void:
	# Find target for long kick
	var best_target: Node2D = null
	var best_dist = 0.0
	
	for tm in teammates:
		if not is_instance_valid(tm) or tm == player_token:
			continue
		var dist = player_token.global_position.distance_to(tm.global_position)
		if dist > 200 and dist > best_dist:
			best_dist = dist
			best_target = tm
	
	if best_target:
		_try_pass(tick_data, true)

# ============================================================================
# UTILITY
# ============================================================================

func _get_stat(stat_name: String) -> float:
	if not player_data:
		return 10.0
	if stat_name in player_data:
		return float(player_data.get(stat_name))
	return 10.0

func _change_state(new_state: AIState) -> void:
	if new_state != current_state:
		previous_state = current_state
		current_state = new_state
		emit_signal("state_changed", previous_state, current_state)

func get_state_name() -> String:
	return AIState.keys()[current_state]

# ============================================================================
# LEGACY PROCESS (Fallback if no tick system)
# ============================================================================

func _process(delta: float) -> void:
	# Only used if not connected to tick system
	if match_engine:
		return  # Tick system handles it
	
	# Legacy continuous processing
	pass
