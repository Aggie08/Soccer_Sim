## Ball.gd
## Physical ball object using Area2D (no physics engine gravity issues!)
class_name Ball
extends Area2D

# ============================================================================
# CONSTANTS
# ============================================================================
const MAX_BALL_SPEED = 800.0
const DRAG_FACTOR = 0.98  # Ball slows down over time

# ============================================================================
# STATE
# ============================================================================
var possessor: Node2D = null  # PlayerToken that has possession
var is_in_play: bool = true
var velocity: Vector2 = Vector2.ZERO  # Manual velocity for Area2D
var spin: float = 0.0  # Ball spin/rotation

# ============================================================================
# CHILD NODES
# ============================================================================
@onready var sprite: ColorRect = $ColorRect

# ============================================================================
# INITIALIZATION
# ============================================================================
func _ready() -> void:
	# No physics setup needed for Area2D!
	print("Ball initialized at position: ", global_position)

# ============================================================================
# PHYSICS
# ============================================================================
func _physics_process(delta: float) -> void:
	# If ball has a possessor, stick to them
	if possessor and is_instance_valid(possessor):
		global_position = possessor.global_position
		velocity = Vector2.ZERO
		return
	
	# Apply manual velocity
	if velocity.length() > 0:
		# Apply drag to slow ball down
		velocity *= DRAG_FACTOR
		
		# Stop if moving very slowly
		if velocity.length() < 1.0:
			velocity = Vector2.ZERO
		else:
			# Move the ball
			global_position += velocity * delta
			
			# Apply spin
			rotation += spin * delta
			spin *= 0.95  # Spin decay

# ============================================================================
# POSSESSION
# ============================================================================

## Give possession to a player
func give_possession(player_token: Node2D) -> void:
	possessor = player_token
	velocity = Vector2.ZERO  # Stop ball movement
	spin = 0.0  # Stop spin

## Remove possession (ball becomes free)
func release_possession() -> void:
	possessor = null

## Check if ball has a possessor
func has_possessor() -> bool:
	return possessor != null and is_instance_valid(possessor)

# ============================================================================
# BALL MOVEMENT
# ============================================================================

## Kick the ball in a direction with power
func kick(direction: Vector2, power: float) -> void:
	release_possession()
	
	var kick_velocity = direction.normalized() * power
	kick_velocity = kick_velocity.limit_length(MAX_BALL_SPEED)
	
	velocity = kick_velocity
	
	# Add some spin
	spin = randf_range(-5.0, 5.0)

## Pass the ball (medium power, accurate)
func pass_ball(target_position: Vector2, pass_power: float = 300.0) -> void:
	var direction = (target_position - global_position).normalized()
	kick(direction, pass_power)

## Shoot the ball (high power)
func shoot(direction: Vector2, shot_power: float = 600.0) -> void:
	kick(direction, shot_power)

# ============================================================================
# POSITION
# ============================================================================

## Place ball at a specific position (for kickoff, throw-ins, etc.)
func place_at(position: Vector2) -> void:
	release_possession()
	global_position = position
	velocity = Vector2.ZERO
	spin = 0.0
	print("Ball placed at ", position)

# ============================================================================
# UTILITY
# ============================================================================

## Get the closest player to the ball from a list
static func get_closest_player(ball_position: Vector2, players: Array) -> Node2D:
	var closest: Node2D = null
	var closest_distance = INF
	
	for player in players:
		if not is_instance_valid(player):
			continue
		
		var distance = ball_position.distance_to(player.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest = player
	
	return closest
