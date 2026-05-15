## PlayerAI.gd
## Enhanced AI brain for player tokens with tick-based processing
## Zone-aware decision making with proper attacking build-up
class_name PlayerAI
extends Node

# ============================================================================
# SIGNALS
# ============================================================================
signal state_changed(old_state: int, new_state: int)

# ============================================================================
# CONSTANTS
# ============================================================================
# Pitch boundaries (centered origin, matches Pitch.gd)
const PITCH_HALF_W = 500.0
const PITCH_HALF_H = 350.0
const PITCH_MARGIN = 20.0

# Zone thirds (X-axis, measured from center)
const THIRD_BOUNDARY = 166.0

# Distances (in pixels)
const BALL_CONTROL_DIST = 30.0
const CLOSE_SUPPORT_DIST = 100.0
const MID_SUPPORT_DIST = 200.0
const FAR_SUPPORT_DIST = 350.0
const MARKING_DIST = 50.0
const PRESSING_TRIGGER_DIST = 120.0
const TACKLE_RANGE = 35.0
const SHORT_PASS_MAX = 200.0
const LONG_PASS_MIN = 200.0
const LONG_PASS_MAX = 500.0

# Shooting distances — expanded so attackers actually shoot
const SHOOT_CLOSE_DIST = 180.0
const SHOOT_MED_DIST = 300.0
const SHOOT_LONG_DIST = 420.0

# Goalkeeper constants
const GK_SAVE_RANGE = 100.0

# Speed multipliers
const SPRINT_MULT = 1.0
const JOG_MULT = 0.6
const WALK_MULT = 0.35

# Decision cooldowns (in ticks)
const MIN_DECISION_TICKS = 1
const MAX_DECISION_TICKS = 3
const POST_ACTION_COOLDOWN = 2

# How far each role pushes forward when team HAS the ball (pixels)
const ROLE_POSSESSION_PUSH = {
	"GK": 0.0,
	"DEF": 80.0,
	"MID": 120.0,
	"ATT": 200.0
}

# How strongly each role shifts toward ball when DEFENDING
const ROLE_BALL_PULL_DEFEND = {
	"GK": 0.0,
	"DEF": 0.15,
	"MID": 0.25,
	"ATT": 0.30
}

# ============================================================================
# AI STATES
# ============================================================================
enum AIState {
	IDLE,
	POSITIONING,
	WITH_BALL,
	DRIBBLING,
	PASSING,
	SHOOTING,
	RECEIVING,
	CHASING_LOOSE,
	PRESSING,
	MARKING,
	COVERING,
	TRACKING_BACK,
	SUPPORTING,
	MAKING_RUN,
	GK_POSITIONING,
	GK_SAVING,
	GK_CATCHING,
	GK_DISTRIBUTING,
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

var team_key: String = ""
var is_home_team: bool = true
var player_idx: int = 0
var position_role: String = ""

var teammates: Array[Node2D] = []
var opponents: Array[Node2D] = []

# ============================================================================
# AI STATE VARIABLES
# ============================================================================
var target_position: Vector2 = Vector2.ZERO
var formation_position: Vector2 = Vector2.ZERO
var pass_target: Node2D = null
var marking_target: Node2D = null

var current_speed_mult: float = JOG_MULT
var base_speed: float = 100.0

var ticks_since_decision: int = 0
var decision_cooldown: int = 1
var action_cooldown: int = 0

var distance_to_ball: float = 999.0
var distance_to_own_goal: float = 999.0
var distance_to_opp_goal: float = 999.0
var nearby_opponents: Array[Node2D] = []
var nearby_teammates: Array[Node2D] = []
var pressure_level: float = 0.0

var own_goal_pos: Vector2 = Vector2.ZERO
var opp_goal_pos: Vector2 = Vector2.ZERO
var attack_direction: float = 1.0  # +1 attacks right, -1 attacks left

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
	attack_direction = 1.0 if home else -1.0

	if match_scene:
		pitch = match_scene.pitch
		ball = match_scene.ball
		match_engine = match_scene.match_engine if "match_engine" in match_scene else null

		if player_token and "player_idx" in player_token:
			player_idx = player_token.player_idx

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

	_calculate_speeds()

	if pitch:
		own_goal_pos = pitch.get_home_goal_position() if is_home_team else pitch.get_away_goal_position()
		opp_goal_pos = pitch.get_away_goal_position() if is_home_team else pitch.get_home_goal_position()

	if pitch and player_data:
		formation_position = pitch.get_formation_position(player_data.current_position, is_home_team)

	if match_engine and match_engine.has_signal("engine_tick"):
		match_engine.engine_tick.connect(_on_engine_tick)

	current_state = AIState.POSITIONING
	print("      AI setup: ", player_data.player_name, " (", position_role, ") at ", formation_position)

func _calculate_speeds() -> void:
	if not player_data:
		base_speed = 100.0
		return
	var speed_stat = player_data.speed if player_data.speed else 10
	base_speed = 50.0 + (speed_stat * 5.0)

func set_ball(ball_ref: Area2D) -> void:
	ball = ball_ref

func set_team_references(team_mates: Array[Node2D], opps: Array[Node2D]) -> void:
	teammates = team_mates
	opponents = opps

func set_formation_position(pos: Vector2) -> void:
	formation_position = pos

# ============================================================================
# PITCH HELPERS
# ============================================================================

func _clamp_to_pitch(pos: Vector2) -> Vector2:
	var lx = PITCH_HALF_W - PITCH_MARGIN
	var ly = PITCH_HALF_H - PITCH_MARGIN
	return Vector2(clampf(pos.x, -lx, lx), clampf(pos.y, -ly, ly))

func _is_in_attacking_third(pos: Vector2) -> bool:
	if is_home_team:
		return pos.x > THIRD_BOUNDARY
	else:
		return pos.x < -THIRD_BOUNDARY

func _is_in_defensive_third(pos: Vector2) -> bool:
	if is_home_team:
		return pos.x < -THIRD_BOUNDARY
	else:
		return pos.x > THIRD_BOUNDARY

func _get_forward_progress(pos: Vector2) -> float:
	if is_home_team:
		return pos.x - own_goal_pos.x
	else:
		return own_goal_pos.x - pos.x

# ============================================================================
# TICK PROCESSING
# ============================================================================

func _on_engine_tick(tick_data: Dictionary) -> void:
	if not player_token or not is_instance_valid(player_token):
		return

	_update_awareness(tick_data)

	if action_cooldown > 0:
		action_cooldown -= 1

	ticks_since_decision += 1

	if ticks_since_decision >= decision_cooldown and action_cooldown == 0:
		_make_decision(tick_data)
		ticks_since_decision = 0
		decision_cooldown = _calculate_decision_cooldown()

func _calculate_decision_cooldown() -> int:
	if current_state == AIState.WITH_BALL or pressure_level > 0.5:
		return MIN_DECISION_TICKS
	return MIN_DECISION_TICKS + randi_range(0, MAX_DECISION_TICKS - MIN_DECISION_TICKS)

# ============================================================================
# AWARENESS
# ============================================================================

func _update_awareness(tick_data: Dictionary) -> void:
	if not player_token:
		return

	var my_pos = player_token.global_position
	var ball_pos: Vector2 = tick_data.get("ball_position", Vector2.ZERO)
	distance_to_ball = my_pos.distance_to(ball_pos)
	distance_to_own_goal = my_pos.distance_to(own_goal_pos)
	distance_to_opp_goal = my_pos.distance_to(opp_goal_pos)

	nearby_opponents.clear()
	nearby_teammates.clear()

	for opp in opponents:
		if is_instance_valid(opp) and my_pos.distance_to(opp.global_position) < PRESSING_TRIGGER_DIST * 2:
			nearby_opponents.append(opp)

	for tm in teammates:
		if is_instance_valid(tm) and tm != player_token and my_pos.distance_to(tm.global_position) < FAR_SUPPORT_DIST:
			nearby_teammates.append(tm)

	pressure_level = 0.0
	for opp in nearby_opponents:
		var dist = my_pos.distance_to(opp.global_position)
		if dist < PRESSING_TRIGGER_DIST:
			pressure_level += (1.0 - dist / PRESSING_TRIGGER_DIST) * 0.5
	pressure_level = minf(pressure_level, 1.0)

# ============================================================================
# DECISION MAKING
# ============================================================================

func _make_decision(tick_data: Dictionary) -> void:
	if not ball or not player_token:
		return

	if position_role == "GK":
		_make_gk_decision(tick_data)
		return

	var possessing_team: String = tick_data.get("possessing_team", "")
	var ball_possessor: Node2D = tick_data.get("ball_possessor", null)

	if ball_possessor == player_token or player_token.has_ball:
		_decide_with_ball(tick_data)
		return

	if possessing_team == team_key:
		_decide_team_has_ball(tick_data, ball_possessor)
		return

	if possessing_team != "" and possessing_team != team_key:
		_decide_opponent_has_ball(tick_data, ball_possessor)
		return

	_decide_loose_ball(tick_data)

# ============================================================================
# WITH BALL — ZONE-AWARE
# ============================================================================

func _decide_with_ball(tick_data: Dictionary) -> void:
	_change_state(AIState.WITH_BALL)

	var my_pos = player_token.global_position
	var in_att_third = _is_in_attacking_third(my_pos)
	var in_def_third = _is_in_defensive_third(my_pos)

	# === ATTACKING THIRD ===
	if in_att_third:
		# Close range — always shoot
		if distance_to_opp_goal < SHOOT_CLOSE_DIST:
			_try_shoot(tick_data)
			return
		# Medium range — shoot if clear
		if distance_to_opp_goal < SHOOT_MED_DIST and _has_clear_shot():
			_try_shoot(tick_data)
			return
		# Long range — shoot if great stats and low pressure
		if distance_to_opp_goal < SHOOT_LONG_DIST and _get_stat("shot_accuracy") >= 14 and pressure_level < 0.3:
			_try_shoot(tick_data)
			return
		# Heavy pressure — pass to keep possession
		if pressure_level > 0.5:
			if _try_pass(tick_data):
				return
		# Dribble closer to goal
		_execute_dribble_toward_goal(tick_data)
		return

	# === DEFENSIVE THIRD ===
	if in_def_third:
		if _try_pass(tick_data):
			return
		_execute_dribble_toward_goal(tick_data)
		return

	# === MIDDLE THIRD ===
	# Try a forward pass first
	if _try_forward_pass(tick_data):
		return
	# No forward pass and low pressure — dribble forward
	if pressure_level < 0.4:
		_execute_dribble_toward_goal(tick_data)
		return
	# Under pressure — any safe pass
	if _try_pass(tick_data):
		return
	# Last resort
	_execute_dribble_toward_goal(tick_data)

# ============================================================================
# SHOOTING
# ============================================================================

func _try_shoot(tick_data: Dictionary) -> bool:
	var distance = distance_to_opp_goal
	var xg = _calculate_xg(distance, pressure_level)

	var shot_stat = _get_stat("shot_accuracy")
	var shot_pow = _get_stat("shot_power")
	var intelligence = _get_stat("intelligence")
	var success_prob = (shot_stat * 4.0 + intelligence) / 120.0
	success_prob *= (1.0 - pressure_level * 0.3)

	if match_engine and match_engine.has_method("get_action_modifier"):
		success_prob *= match_engine.get_action_modifier(team_key, player_data)

	success_prob = clampf(success_prob, 0.1, 0.95)

	var on_target = randf() < success_prob
	var is_goal = on_target and randf() < xg

	if ball:
		var direction = (opp_goal_pos - player_token.global_position).normalized()
		if not on_target:
			direction = direction.rotated(randf_range(-0.5, 0.5))
		var power = 400.0 + (shot_pow * 15.0)
		ball.shoot(direction, power)

	player_token.release_ball()

	if player_token.has_method("record_shot"):
		player_token.record_shot(on_target, is_goal)

	if is_goal:
		print(player_data.player_name, " SCORES! (xG: ", "%.2f" % xg, ")")
	elif on_target:
		print(player_data.player_name, " shot on target")
	else:
		print(player_data.player_name, " shot off target")

	action_cooldown = POST_ACTION_COOLDOWN * 2
	return true

func _calculate_xg(distance: float, pressure: float) -> float:
	var base_xg: float
	if distance < SHOOT_CLOSE_DIST:
		base_xg = 0.55
	elif distance < SHOOT_MED_DIST:
		base_xg = 0.30
	elif distance < SHOOT_LONG_DIST:
		base_xg = 0.12
	else:
		base_xg = 0.05

	base_xg *= (1.0 - pressure * 0.4)

	# Angle penalty
	var my_pos = player_token.global_position
	var goal_dir = (opp_goal_pos - my_pos).normalized()
	var straight = Vector2(attack_direction, 0)
	base_xg *= clampf(goal_dir.dot(straight), 0.3, 1.0)

	return clampf(base_xg, 0.01, 0.99)

func _has_clear_shot() -> bool:
	var my_pos = player_token.global_position
	var dir_to_goal = (opp_goal_pos - my_pos).normalized()
	var blocking = 0
	for opp in nearby_opponents:
		if not is_instance_valid(opp):
			continue
		var to_opp = (opp.global_position - my_pos).normalized()
		if dir_to_goal.dot(to_opp) > 0.7 and my_pos.distance_to(opp.global_position) < 120:
			blocking += 1
	return blocking < 2

# ============================================================================
# PASSING
# ============================================================================

func _try_forward_pass(tick_data: Dictionary) -> bool:
	var target = _find_forward_pass_target()
	if not target:
		return false
	return _execute_pass_to(target, tick_data)

func _try_pass(tick_data: Dictionary, is_gk_distribution: bool = false) -> bool:
	var target = _find_best_pass_target()
	if not target:
		return false
	return _execute_pass_to(target, tick_data, is_gk_distribution)

func _execute_pass_to(target: Node2D, tick_data: Dictionary, is_gk_distribution: bool = false) -> bool:
	var distance = player_token.global_position.distance_to(target.global_position)
	var is_long = distance > SHORT_PASS_MAX

	var pass_stat = _get_stat("long_pass") if is_long else _get_stat("short_pass")
	var vision = _get_stat("vision")
	var success_prob = (pass_stat * 4.0 + vision) / 120.0

	if not is_gk_distribution:
		success_prob *= (1.0 - pressure_level * 0.2)

	if match_engine and match_engine.has_method("get_action_modifier"):
		success_prob *= match_engine.get_action_modifier(team_key, player_data)

	success_prob = clampf(success_prob, 0.2, 0.95)
	var success = randf() < success_prob

	if player_token.has_method("record_pass"):
		player_token.record_pass(success, is_long)

	if success:
		pass_target = target
		_change_state(AIState.PASSING)

		if ball:
			var pass_power = 400.0 if is_long else 250.0
			ball.pass_ball(target.global_position, pass_power)

		player_token.release_ball()

		if target.has_method("give_ball"):
			target.give_ball()
			if ball:
				ball.give_possession(target)
		if match_engine and match_engine.has_method("set_possession"):
			match_engine.set_possession(team_key, target)
	else:
		if ball:
			var rand_angle = randf_range(-PI / 4, PI / 4)
			var dir = (target.global_position - player_token.global_position).normalized()
			ball.kick(dir.rotated(rand_angle), 200.0)
		player_token.release_ball()

	action_cooldown = POST_ACTION_COOLDOWN
	return true

func _find_forward_pass_target() -> Node2D:
	var best_target: Node2D = null
	var best_score: float = -999.0
	var my_progress = _get_forward_progress(player_token.global_position)

	for tm in teammates:
		if not is_instance_valid(tm) or tm == player_token:
			continue
		var tm_pos = tm.global_position
		var dist = player_token.global_position.distance_to(tm_pos)
		if dist < 40.0 or dist > LONG_PASS_MAX:
			continue

		var progress_gain = _get_forward_progress(tm_pos) - my_progress
		# Only forward passes
		if progress_gain <= 0:
			continue

		var opp_near = _count_opponents_near(tm_pos, 60.0)
		var score = progress_gain * 1.0 - (dist * 0.03) - (opp_near * 25.0)

		if _is_in_attacking_third(tm_pos):
			score += 40.0
		if opp_near == 0:
			score += 20.0

		if score > best_score:
			best_score = score
			best_target = tm

	return best_target

func _find_best_pass_target() -> Node2D:
	var best_target: Node2D = null
	var best_score: float = -999.0
	var my_progress = _get_forward_progress(player_token.global_position)

	for tm in teammates:
		if not is_instance_valid(tm) or tm == player_token:
			continue
		var tm_pos = tm.global_position
		var dist = player_token.global_position.distance_to(tm_pos)
		if dist < 40.0 or dist > LONG_PASS_MAX:
			continue

		var progress_gain = _get_forward_progress(tm_pos) - my_progress
		var opp_near = _count_opponents_near(tm_pos, 60.0)

		var score = progress_gain * 0.5 - (dist * 0.05) - (opp_near * 30.0)

		if tm.has_method("get_position_on_field"):
			var pos = tm.get_position_on_field()
			if pos in ["ST1", "ST2"]:
				score += 25.0
			elif pos in ["LM", "RM"]:
				score += 10.0

		if opp_near == 0:
			score += 15.0

		if score > best_score:
			best_score = score
			best_target = tm

	return best_target

func _count_opponents_near(pos: Vector2, radius: float) -> int:
	var count = 0
	for opp in opponents:
		if is_instance_valid(opp) and pos.distance_to(opp.global_position) < radius:
			count += 1
	return count

# ============================================================================
# DRIBBLING
# ============================================================================

func _execute_dribble_toward_goal(tick_data: Dictionary) -> void:
	_change_state(AIState.DRIBBLING)

	var to_goal = (opp_goal_pos - player_token.global_position).normalized()
	var lateral = Vector2(-to_goal.y, to_goal.x) * randf_range(-0.4, 0.4)
	var direction = (to_goal + lateral).normalized()

	target_position = _clamp_to_pitch(player_token.global_position + direction * 60.0)
	current_speed_mult = 0.55
	player_token.set_target_position(target_position)

# ============================================================================
# TEAM HAS BALL — PUSH FORWARD
# ============================================================================

func _decide_team_has_ball(tick_data: Dictionary, ball_carrier: Node2D) -> void:
	# Attackers make runs into the box
	if position_role == "ATT" and randf() < 0.35:
		_execute_attacking_run(tick_data)
		return

	# Wide midfielders push up on flank
	if position_role == "MID" and player_data.current_position in ["LM", "RM"] and randf() < 0.2:
		_execute_wide_run(tick_data)
		return

	# Everyone else: push formation forward
	_execute_possession_support(tick_data, ball_carrier)

func _execute_attacking_run(tick_data: Dictionary) -> void:
	_change_state(AIState.MAKING_RUN)

	# Sprint toward the penalty area
	var lateral = randf_range(-100, 100)
	var run_x = opp_goal_pos.x - (attack_direction * 120.0)
	target_position = _clamp_to_pitch(Vector2(run_x, lateral))
	current_speed_mult = SPRINT_MULT
	player_token.set_target_position(target_position)

func _execute_wide_run(tick_data: Dictionary) -> void:
	_change_state(AIState.MAKING_RUN)

	var is_left = player_data.current_position == "LM"
	var flank_y = -250.0 if is_left else 250.0
	var push_x = formation_position.x + (attack_direction * ROLE_POSSESSION_PUSH["MID"])

	target_position = _clamp_to_pitch(Vector2(push_x, flank_y))
	current_speed_mult = SPRINT_MULT
	player_token.set_target_position(target_position)

func _execute_possession_support(tick_data: Dictionary, ball_carrier: Node2D) -> void:
	_change_state(AIState.SUPPORTING)

	# Push formation forward in possession
	var push = ROLE_POSSESSION_PUSH.get(position_role, 80.0)
	var pushed_pos = formation_position + Vector2(attack_direction * push, 0)

	# Light pull toward ball for compactness (15% max)
	if is_instance_valid(ball_carrier):
		pushed_pos = pushed_pos.lerp(ball_carrier.global_position, 0.15)

	target_position = _clamp_to_pitch(pushed_pos)
	current_speed_mult = JOG_MULT
	player_token.set_target_position(target_position)

# ============================================================================
# OPPONENT HAS BALL — DEFEND
# ============================================================================

func _decide_opponent_has_ball(tick_data: Dictionary, ball_carrier: Node2D) -> void:
	if not is_instance_valid(ball_carrier):
		_decide_loose_ball(tick_data)
		return

	var dist_to_carrier = player_token.global_position.distance_to(ball_carrier.global_position)

	if _should_press(dist_to_carrier):
		_execute_pressing(tick_data, ball_carrier)
		return

	var threat = _find_marking_target()
	if threat:
		_execute_marking(tick_data, threat)
		return

	_execute_defensive_positioning(tick_data)

func _should_press(dist_to_carrier: float) -> bool:
	match position_role:
		"ATT":
			return dist_to_carrier < PRESSING_TRIGGER_DIST * 1.5
		"MID":
			return dist_to_carrier < PRESSING_TRIGGER_DIST
		"DEF":
			return dist_to_carrier < PRESSING_TRIGGER_DIST * 0.6
		"GK":
			return false
	return false

func _execute_pressing(tick_data: Dictionary, ball_carrier: Node2D) -> void:
	_change_state(AIState.PRESSING)
	marking_target = ball_carrier
	target_position = _clamp_to_pitch(ball_carrier.global_position)
	current_speed_mult = SPRINT_MULT
	player_token.set_target_position(target_position)

	if player_token.global_position.distance_to(ball_carrier.global_position) < TACKLE_RANGE:
		_attempt_tackle(ball_carrier)

func _attempt_tackle(opponent: Node2D) -> void:
	if action_cooldown > 0:
		return

	var tackling = _get_stat("tackling")
	var strength = _get_stat("strength")
	var intelligence = _get_stat("intelligence")

	var opp_dribbling = 10.0
	var opp_strength = 10.0
	if opponent.has_method("get_effective_stat"):
		opp_dribbling = opponent.get_effective_stat("dribbling")
		opp_strength = opponent.get_effective_stat("strength")

	var atk = (tackling * 2.0 + strength + intelligence) / 4.0
	var dfn = (opp_dribbling * 2.0 + opp_strength) / 3.0
	var success_prob = atk / (atk + dfn)

	if match_engine and match_engine.has_method("get_action_modifier"):
		success_prob *= match_engine.get_action_modifier(team_key, player_data)

	success_prob = clampf(success_prob, 0.15, 0.85)

	var success = randf() < success_prob
	var is_foul = randf() < (0.08 if success else 0.3)

	if player_token.has_method("record_tackle"):
		player_token.record_tackle(success, is_foul)

	if success and not is_foul:
		if opponent.has_method("release_ball"):
			opponent.release_ball()
		player_token.give_ball()
		if ball:
			ball.give_possession(player_token)
		if match_engine and match_engine.has_method("set_possession"):
			match_engine.set_possession(team_key, player_token)
		print(player_data.player_name, " wins the tackle!")
	elif is_foul:
		print(player_data.player_name, " commits a foul!")

	action_cooldown = POST_ACTION_COOLDOWN * 2

func _find_marking_target() -> Node2D:
	var best: Node2D = null
	var best_score: float = -999.0
	for opp in nearby_opponents:
		if not is_instance_valid(opp):
			continue
		var dist_me = player_token.global_position.distance_to(opp.global_position)
		if dist_me > 200:
			continue
		var dist_goal = opp.global_position.distance_to(own_goal_pos)
		var score = -dist_me * 0.4 - dist_goal * 0.3
		if dist_goal < 250:
			score += 50
		if score > best_score:
			best_score = score
			best = opp
	return best

func _execute_marking(tick_data: Dictionary, target: Node2D) -> void:
	_change_state(AIState.MARKING)
	marking_target = target
	var to_goal = (own_goal_pos - target.global_position).normalized()
	target_position = _clamp_to_pitch(target.global_position + to_goal * MARKING_DIST)
	current_speed_mult = JOG_MULT
	player_token.set_target_position(target_position)

func _execute_defensive_positioning(tick_data: Dictionary) -> void:
	_change_state(AIState.COVERING)
	var ball_pos: Vector2 = tick_data.get("ball_position", Vector2.ZERO)
	var pull = ROLE_BALL_PULL_DEFEND.get(position_role, 0.15)
	var shifted = formation_position.lerp(ball_pos, pull * 0.5)
	target_position = _clamp_to_pitch(shifted)
	current_speed_mult = JOG_MULT
	player_token.set_target_position(target_position)

# ============================================================================
# LOOSE BALL
# ============================================================================

func _decide_loose_ball(tick_data: Dictionary) -> void:
	var chase_dist = _get_chase_distance()
	if distance_to_ball < chase_dist:
		_execute_chase_ball(tick_data)
	else:
		_execute_defensive_positioning(tick_data)

func _get_chase_distance() -> float:
	match position_role:
		"GK":  return 80.0
		"DEF": return 120.0
		"MID": return 200.0
		"ATT": return 300.0
	return 150.0

func _execute_chase_ball(tick_data: Dictionary) -> void:
	_change_state(AIState.CHASING_LOOSE)
	var ball_pos: Vector2 = tick_data.get("ball_position", Vector2.ZERO)
	target_position = _clamp_to_pitch(ball_pos)
	current_speed_mult = SPRINT_MULT
	player_token.set_target_position(target_position)

# ============================================================================
# GOALKEEPER
# ============================================================================

func _make_gk_decision(tick_data: Dictionary) -> void:
	var ball_pos: Vector2 = tick_data.get("ball_position", Vector2.ZERO)
	var my_pos = player_token.global_position
	var dist = my_pos.distance_to(ball_pos)
	var possessor: Node2D = tick_data.get("ball_possessor", null)

	if possessor == player_token or player_token.has_ball:
		if _try_pass(tick_data, true):
			return
		_execute_gk_kick(tick_data)
		return

	if dist < GK_SAVE_RANGE:
		_change_state(AIState.GK_SAVING)
		target_position = _clamp_to_pitch(ball_pos)
		current_speed_mult = 1.2
		player_token.set_target_position(target_position)
		return

	_execute_gk_positioning(tick_data, ball_pos)

func _execute_gk_positioning(tick_data: Dictionary, ball_pos: Vector2) -> void:
	_change_state(AIState.GK_POSITIONING)
	var goal = own_goal_pos
	var to_ball = ball_pos - goal
	var come_off = clampf(to_ball.length() / 10.0, 10, 80)
	var gk_pos = goal + to_ball.normalized() * come_off

	gk_pos.y = clampf(gk_pos.y, goal.y - 60, goal.y + 60)
	if is_home_team:
		gk_pos.x = clampf(gk_pos.x, own_goal_pos.x, own_goal_pos.x + 80)
	else:
		gk_pos.x = clampf(gk_pos.x, own_goal_pos.x - 80, own_goal_pos.x)

	target_position = _clamp_to_pitch(gk_pos)
	current_speed_mult = JOG_MULT
	player_token.set_target_position(target_position)

func _execute_gk_kick(tick_data: Dictionary) -> void:
	var best: Node2D = null
	var best_dist = 0.0
	for tm in teammates:
		if not is_instance_valid(tm) or tm == player_token:
			continue
		var d = player_token.global_position.distance_to(tm.global_position)
		if d > 150 and d > best_dist:
			best_dist = d
			best = tm

	if best and ball:
		ball.pass_ball(best.global_position, 500.0)
		player_token.release_ball()
	elif ball:
		ball.kick(Vector2(attack_direction, 0), 500.0)
		player_token.release_ball()

	action_cooldown = POST_ACTION_COOLDOWN * 2

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
