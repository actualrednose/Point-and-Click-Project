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

# --- opening restraint ---------------------------------------------------
@export_group("Opening Restraint")
## While true: cannot walk. The GurneyPuzzle sets this via set_restrained().
@export var restrained := false
## Lying-down art. Assign these on the PLAYER INSTANCE in the opening room —
## NOT in player.tscn itself, or every room gets the lying art.
@export var lying_body_texture: Texture2D
@export var lying_head_texture: Texture2D
## How far the HeadPivot shifts when lying (the lying neck sits somewhere
## else than the standing neck). (0,0) = no shift.
@export var lying_head_pivot_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("player")

func _physics_process(_delta: float) -> void:
	if restrained:
		return   # strapped down — no walking, no flipping
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
	
func set_restrained(value: bool) -> void:
	if restrained == value:
		return
	restrained = value
	if value:
		# stash the standing look, then swap to the lying look
		_stand_body_tex = $Body.texture
		_stand_head_tex = $HeadPivot/Head.texture
		_stand_pivot_pos = $HeadPivot.position
		if lying_body_texture != null:
			$Body.texture = lying_body_texture
		if lying_head_texture != null:
			$HeadPivot/Head.texture = lying_head_texture
		$HeadPivot.position = _stand_pivot_pos + lying_head_pivot_offset
	else:
		# stand up: restore exactly what was stashed
		if _stand_body_tex != null:
			$Body.texture = _stand_body_tex
		if _stand_head_tex != null:
			$HeadPivot/Head.texture = _stand_head_tex
		if _lie_stashed:
			$HeadPivot.position = _stand_pivot_pos

var _stand_body_tex: Texture2D
var _stand_head_tex: Texture2D
var _stand_pivot_pos: Vector2
var _lie_stashed := false
