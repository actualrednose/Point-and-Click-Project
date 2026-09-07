extends CharacterBody2D
## Lateral movement for the point-and-click player.

@export_group("Movement")
@export var move_speed: float = 350.0
## Horizontal walk bounds for the current room, in world x coordinates.
## Override these on the Player *instance* in each room scene.
@export var room_left_limit: float = 60.0
@export var room_right_limit: float = 1860.0

## 1 = facing right, -1 = facing left.
var facing: int = 1

@onready var body_sprite: Sprite2D = $Body
@onready var head_pivot: Node2D = $HeadPivot

func _ready() -> void:
	add_to_group("player")

func _physics_process(_delta: float) -> void:
	var axis: float = Input.get_axis("move_left", "move_right")
	if absf(axis) > 0.05:
		velocity.x = axis * move_speed
		set_facing(1 if axis > 0.0 else -1)
	else:
		velocity.x = 0.0
	move_and_slide()
	position.x = clampf(position.x, room_left_limit, room_right_limit)

func set_facing(dir: int) -> void:
	if dir == facing:
		return
	facing = dir
	body_sprite.flip_h = dir == -1
	head_pivot.set_facing(dir)
