extends Node2D
## Cursor-tracking head. Attach to the HeadPivot Node2D placed at the neck.

@export_group("Tracking")
## Max tilt upward, degrees.
@export var max_up_deg: float = 75.0
## Max tilt downward, degrees.
@export var max_down_deg: float = 40.0
## How fast the head turns (higher = snappier).
@export var smoothing: float = 10.0
## Cursor closer than this to the neck holds the head still (avoids jitter).
@export var deadzone_radius: float = 24.0

@export_group("Auto Flip")
## Flip the head when the cursor crosses the head's x axis.
@export var auto_flip: bool = true
## Cursor must be at least this far past the head on the opposite side
## before flipping (stops flip-flopping while hovering on the crossing line).
@export var flip_margin: float = 8.0

## 1 = facing right, -1 = facing left. Driven by player.gd and, when
## auto_flip is on, overridden by the cursor crossing the head.
var facing: int = 1

@onready var head_sprite: Sprite2D = $Head

func set_facing(dir: int) -> void:
	if dir == facing:
		return
	facing = dir
	head_sprite.flip_h = dir == -1
	# Mirror the current tilt at the instant of the flip so the head
	# doesn't visibly sweep to the opposite side.
	rotation = -rotation

func _process(delta: float) -> void:
	var to_cursor: Vector2 = get_global_mouse_position() - global_position

	# Auto flip: cursor crossed to the other side of the head on the x axis.
	# Runs before the deadzone check so a crossing right next to the neck
	# still flips, while flip_margin stops hover-on-the-line flip-flopping.
	if auto_flip:
		var side := int(signf(to_cursor.x))
		if side != 0 and side != facing and absf(to_cursor.x) > flip_margin:
			set_facing(side)

	if to_cursor.length() < deadzone_radius:
		return  # Cursor is basically on the neck — hold the current tilt.

	var cursor_angle: float = atan2(to_cursor.y, to_cursor.x)
	var forward: float = 0.0 if facing == 1 else PI
	var rel: float = angle_difference(forward, cursor_angle)

	# Positive rotation is clockwise. Clockwise means "down" while facing
	# right but "up" while facing left, so the clamp window swaps sides.
	var lo: float
	var hi: float
	if facing == 1:
		lo = -deg_to_rad(max_up_deg)
		hi = deg_to_rad(max_down_deg)
	else:
		lo = -deg_to_rad(max_down_deg)
		hi = deg_to_rad(max_up_deg)

	var target: float = clampf(rel, lo, hi)
	rotation = lerp_angle(rotation, target, 1.0 - exp(-smoothing * delta))
