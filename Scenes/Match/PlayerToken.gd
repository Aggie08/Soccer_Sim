## PlayerToken.gd
## Visual representation of a player on the pitch
## CharacterBody2D for movement and positioning
## Upgraded for tick-based match engine integration
class_name PlayerToken
extends CharacterBody2D

# ============================================================================
# SIGNALS
# ============================================================================
signal stamina_changed(new_stamina: float)
signal rating_changed(new_rating: float)

# ============================================================================
# REFERENCES
# ============================================================================
var player_data: Player = null  # Reference to the Player resource
var team_color: Color = Color.BLUE
var is_home_team: bool = true
var player_idx: int = 0  # Index in lineup (0-10)
var team_key: String = "home"  # "home" or "away"
var ai_controller: PlayerAI = null  # AI brain
var match_engine: Node = null  # Reference to MatchEngine

# ============================================================================
# MOVEMENT & AI
# ============================================================================
var target_position: Vector2 = Vector2.ZERO
var has_movement_target: bool = false  # Flag to track if we should move
var move_speed: float = 100.0  # Base speed (modified by player stats)
var current_speed_multiplier: float = 1.0  # Sprint, jog, walk multipliers

# ============================================================================
# MATCH STATE
# ============================================================================
var has_ball: bool = false
var is_selected: bool = false  # For tactical UI selection

# Stamina system
var current_stamina: float = 100.0  # 0-100
var stamina_drain_rate: float = 0.05  # Per tick when active
var stamina_recovery_rate: float = 0.02  # Per tick when resting

# Match rating (6.0 - 10.0)
var match_rating: float = 6.0
var rating_events: Array[Dictionary] = []  # Track actions for rating calculation

# ============================================================================
# CHILD NODES (Set in _ready)
# ============================================================================
@onready var sprite: ColorRect = $ColorRect
@onready var name_label: Label = $NameLabel
@onready var selection_indicator: ColorRect = $SelectionIndicator

# ============================================================================
# INITIALIZATION
# ============================================================================
func _ready() -> void:
	# Visual setup
	if sprite:
		sprite.color = team_color
	
	# Update name label
	if player_data and name_label:
		name_label.text = player_data.player_name.substr(0, 3).to_upper()  # First 3 letters
	
	# Hide selection indicator by default
	if selection_indicator:
		selection_indicator.visible = false

# ============================================================================
# SETUP
# ============================================================================

## Initialize the token with player data and match engine
func setup(
	player: Player, 
	color: Color, 
	home_team: bool, 
	idx: int,
	engine: Node,
	match_scene_ref: Node2D = null
) -> void:
	player_data = player
	team_color = color
	is_home_team = home_team
	player_idx = idx
	team_key = "home" if home_team else "away"
	match_engine = engine
	
	# Initialize stamina from player data
	if player_data:
		current_stamina = player_data.current_stamina_percent
	
	# Calculate move speed based on player's speed stat
	if player_data:
		var speed_stat = player_data.speed if player_data.speed else 10
		move_speed = 50.0 + (speed_stat * 5.0)  # 55-150 range
	
	# Create AI controller
	if match_scene_ref:
		print("    Creating AI for ", player_data.player_name if player_data else "Unknown", "...")
		ai_controller = PlayerAI.new()
		print("      PlayerAI instance created")
		add_child(ai_controller)
		print("      PlayerAI added as child")
		ai_controller.setup(self, player_data, match_scene_ref, home_team)
		print("      AI setup complete for ", player_data.player_name)
	else:
		print("    ERROR: No match_scene_ref for ", player_data.player_name if player_data else "Unknown")
	
	# Connect to match engine tick signal
	if match_engine and match_engine.has_signal("engine_tick"):
		match_engine.engine_tick.connect(_on_engine_tick)
	
	# Update visuals if already in scene tree
	if is_inside_tree():
		_update_visuals()

## Update visual elements
func _update_visuals() -> void:
	if sprite:
		sprite.color = team_color
		
		# Darker shade if has ball
		if has_ball:
			sprite.color = team_color.darkened(0.3)
	
	if name_label and player_data:
		name_label.text = player_data.player_name.substr(0, 3).to_upper()
	
	if selection_indicator:
		selection_indicator.visible = is_selected

# ============================================================================
# MOVEMENT
# ============================================================================

func _physics_process(delta: float) -> void:
	# AI processing is now tick-based via MatchEngine signals
	# No need to call AI here - it processes on engine_tick
	
	# Execute movement if we have a target
	if has_movement_target:
		_move_towards_target(delta)

## Move towards the target position
func _move_towards_target(delta: float) -> void:
	var direction = (target_position - global_position).normalized()
	var distance = global_position.distance_to(target_position)
	
	# Debug first few movements
	if player_data and randf() < 0.01:  # Print occasionally
		print(player_data.player_name, " moving to ", target_position, " (dist: ", int(distance), ")")
	
	# Stop if close enough
	if distance < 5.0:
		velocity = Vector2.ZERO
		has_movement_target = false  # Reached target
		return
	
	# Calculate velocity with speed stat
	var current_speed = move_speed
	
	# Reduce speed if stamina is low
	if player_data:
		var stamina_factor = player_data.current_stamina_percent / 100.0
		current_speed *= max(stamina_factor, 0.5)  # Min 50% speed
	
	velocity = direction * current_speed
	move_and_slide()

## Set a new target position for the player to move to
func set_target_position(pos: Vector2) -> void:
	if player_data and randf() < 0.01:  # Debug occasionally
		print("    ", player_data.player_name, " target set to: ", pos, " (current: ", global_position, ")")
	target_position = pos
	has_movement_target = true  # Enable movement

## Stop all movement
func stop_movement() -> void:
	target_position = Vector2.ZERO
	has_movement_target = false  # Disable movement
	velocity = Vector2.ZERO

# ============================================================================
# BALL INTERACTION
# ============================================================================

## Give possession of the ball to this player
func give_ball() -> void:
	has_ball = true
	_update_visuals()

## Take the ball away from this player
func remove_ball() -> void:
	has_ball = false
	_update_visuals()

# ============================================================================
# SELECTION (For Tactical UI)
# ============================================================================

## Select this player (show indicator)
func select() -> void:
	is_selected = true
	_update_visuals()

## Deselect this player
func deselect() -> void:
	is_selected = false
	_update_visuals()

# ============================================================================
# GETTERS
# ============================================================================

## Get the player's position on the field
func get_position_on_field() -> String:
	if player_data:
		return player_data.current_position
	return "UNKNOWN"

## Get player's effective stats for current position
func get_effective_stat(stat_name: String) -> int:
	if not player_data:
		return 10
	
	match stat_name:
		"vision":
			return player_data.get_effective_vision()
		"intelligence":
			return player_data.get_effective_intelligence()
		"marking":
			return player_data.get_effective_marking()
		"positioning":
			return player_data.get_effective_positioning()
		_:
			return player_data.get(stat_name) if player_data.get(stat_name) != null else 10

# ============================================================================
# TICK-BASED PROCESSING
# ============================================================================

## Called every engine tick (0.25 seconds)
func _on_engine_tick(tick_data: Dictionary) -> void:
	# Update stamina
	_process_stamina(tick_data)
	
	# Update player data stamina for modifier calculations
	if player_data:
		player_data.current_stamina_percent = current_stamina

## Process stamina drain/recovery
func _process_stamina(tick_data: Dictionary) -> void:
	var old_stamina = current_stamina
	
	# Drain stamina based on movement intensity
	var distance_to_target = global_position.distance_to(target_position) if has_movement_target else 0.0
	
	if distance_to_target > 10.0:
		# Moving - drain stamina
		var drain = stamina_drain_rate
		
		# Sprint drains more
		if current_speed_multiplier > 0.9:
			drain *= 1.5
		
		# Has ball drains slightly more
		if has_ball:
			drain *= 1.2
		
		current_stamina -= drain
	else:
		# Standing still or walking slowly - recover slightly
		current_stamina += stamina_recovery_rate
	
	# Clamp stamina
	current_stamina = clampf(current_stamina, 0.0, 100.0)
	
	# Emit signal if changed significantly
	if abs(old_stamina - current_stamina) > 0.5:
		emit_signal("stamina_changed", current_stamina)
	
	# Update move speed based on stamina
	_update_speed_from_stamina()

func _update_speed_from_stamina() -> void:
	if not player_data:
		return
	
	# Base speed from stats
	var base = 50.0 + (player_data.speed * 5.0)
	
	# Stamina modifier: 70% speed at 0 stamina, 100% at full
	var stamina_mod = 0.7 + (current_stamina / 100.0) * 0.3
	
	move_speed = base * stamina_mod

# ============================================================================
# MATCH RATING SYSTEM
# ============================================================================

## Record an action that affects match rating
func record_rating_event(event_type: String, success: bool, impact: float = 1.0) -> void:
	rating_events.append({
		"type": event_type,
		"success": success,
		"impact": impact,
		"tick": match_engine.total_ticks if match_engine else 0
	})
	
	# Recalculate rating
	_calculate_match_rating()

func _calculate_match_rating() -> void:
	if rating_events.is_empty():
		return
	
	var rating = 6.0  # Base rating
	
	# Tally positive and negative contributions
	var positive_actions = 0
	var negative_actions = 0
	
	for event in rating_events:
		if event["success"]:
			positive_actions += event["impact"]
		else:
			negative_actions += event["impact"]
	
	# Calculate rating (6.0 - 10.0 scale)
	var net_contribution = positive_actions - (negative_actions * 0.5)
	rating += net_contribution * 0.1
	
	# Bonus for key actions
	var goals = rating_events.filter(func(e): return e["type"] == "goal").size()
	var assists = rating_events.filter(func(e): return e["type"] == "assist").size()
	rating += goals * 1.5
	rating += assists * 1.0
	
	# Clamp to valid range
	rating = clampf(rating, 3.0, 10.0)
	
	# Update
	if abs(match_rating - rating) > 0.1:
		match_rating = rating
		emit_signal("rating_changed", match_rating)

## Helper functions for recording specific events
func record_shot(on_target: bool, is_goal: bool) -> void:
	if is_goal:
		record_rating_event("goal", true, 3.0)
		if match_engine:
			match_engine.record_goal(team_key, player_idx, 0.5)  # Default xG
	else:
		record_rating_event("shot", on_target, 0.5)
		if match_engine:
			var xg = 0.3 if on_target else 0.1
			match_engine.record_shot(team_key, player_idx, on_target, xg)

func record_pass(success: bool, is_long: bool = false) -> void:
	record_rating_event("pass", success, 0.2)
	if match_engine:
		match_engine.record_pass(team_key, player_idx, success, is_long)

func record_tackle(success: bool, is_foul: bool = false) -> void:
	record_rating_event("tackle", success, 0.3)
	if match_engine:
		match_engine.record_tackle(team_key, player_idx, success, is_foul)

func record_interception() -> void:
	record_rating_event("interception", true, 0.4)
	if match_engine:
		match_engine.record_interception(team_key, player_idx)

# ============================================================================
# UTILITY
# ============================================================================

func get_stamina_percentage() -> float:
	return current_stamina

func get_match_rating() -> float:
	return match_rating

func is_exhausted() -> bool:
	return current_stamina < 20.0
