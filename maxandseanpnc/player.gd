extends CharacterBody2D
## Lateral movement + walk animation for the point-and-click player.
##
## Body must be an AnimatedSprite2D (named exactly "Body") with animations:
##   "idle"  - standing frame(s)
##   "walk"  - the walk cycle
## The script plays them automatically from _physics_process.
##
## Frame alignment: frames exported with different canvas sizes (idle and
## walk almost always differ) would make the body pop vertically when the
## walk starts, because every frame is centered on the node origin. At
## load, _compute_frame_alignment() measures each frame's visible pixels
## and offsets each animation so the FEET stay on one line — re-exported
## art never needs re-padding.

@export_group("Movement")
@export var move_speed: float = 350.0
## Horizontal walk bounds for the current room, in world x coordinates.
## Override these on the Player *instance* in each room scene.
@export var room_left_limit: float = 60.0
@export var room_right_limit: float = 1860.0

## 1 = facing right, -1 = facing left.
var facing: int = 1

@onready var body_sprite: AnimatedSprite2D = $Body
@onready var head_pivot: Node2D = $HeadPivot
@onready var lying_body: Sprite2D = get_node_or_null("LyingBody")
@onready var lying_head_pivot: Node2D = get_node_or_null("LyingHeadPivot")

# --- opening restraint ---------------------------------------------------

## While true: the player is strapped down. Walking and turning are locked,
## the lying-down nodes (LyingBody / LyingHeadPivot) are shown and the
## standing nodes (Body / HeadPivot) are hidden. The GurneyPuzzle sets
## this via set_restrained().
@export var restrained := false

# --- walk animation ------------------------------------------------------

## Per-animation offset (String -> Vector2) that keeps the feet planted
## across different frame canvas sizes. Computed once at load.
var _anim_offset: Dictionary = {}
var _walking := false

func _ready() -> void:
	add_to_group("player")
	# Enforce exactly one pose at runtime. In the EDITOR both poses are
	# visible (so the lying nodes can be placed against the room art);
	# this hides the lying pose unless the player is actually restrained.
	_sync_pose()
	_compute_frame_alignment()
	_check_body_animations()
	_play_body("idle")

func _physics_process(_delta: float) -> void:
	if restrained:
		return   # strapped down — no walking, no flipping
	var axis: float = Input.get_axis("move_left", "move_right")
	_walking = absf(axis) > 0.05
	if _walking:
		velocity.x = axis * move_speed
		set_facing(1 if axis > 0.0 else -1)
	else:
		velocity.x = 0.0
	move_and_slide()
	position.x = clampf(position.x, room_left_limit, room_right_limit)
	_play_body("walk" if _walking else "idle")

func set_facing(dir: int) -> void:
	if restrained:
		return  # strapped down — the body never turns toward anything
	if dir == facing:
		return
	facing = dir
	body_sprite.flip_h = dir == -1
	head_pivot.set_facing(dir)

## Restrain / free the player. Swaps which pose is visible.
func set_restrained(value: bool) -> void:
	if restrained == value:
		return
	restrained = value
	_sync_pose()

## Show exactly one pose: standing (Body + HeadPivot) or lying
## (LyingBody + LyingHeadPivot). Called by _ready() and set_restrained().
func _sync_pose() -> void:
	var lying := restrained
	body_sprite.visible = not lying
	head_pivot.visible = not lying
	if lying_body != null:
		lying_body.visible = lying
	if lying_head_pivot != null:
		lying_head_pivot.visible = lying
	if lying and lying_body == null and lying_head_pivot == null:
		push_warning("Player: restrained, but player.tscn has no LyingBody / "
			+ "LyingHeadPivot nodes (check the exact names).")

# ---------------- animation ----------------

func _play_body(anim: String) -> void:
	if body_sprite.sprite_frames == null or not body_sprite.sprite_frames.has_animation(anim):
		return
	if body_sprite.animation != anim or not body_sprite.is_playing():
		body_sprite.play(anim)
	# Feet alignment: switch offsets with the animation (idle and walk
	# frames rarely share a canvas size — see the header comment).
	if _anim_offset.has(anim):
		body_sprite.offset = _anim_offset[anim]

func _check_body_animations() -> void:
	var frames := body_sprite.sprite_frames
	if frames == null:
		push_warning("Player: Body has no SpriteFrames — create the 'idle' and 'walk' animations.")
		return
	for anim in ["idle", "walk"]:
		if not frames.has_animation(anim):
			push_warning("Player: Body SpriteFrames is missing the '%s' animation." % anim)

## Measure every frame's visible pixels; per animation, note the lowest
## feet and the average horizontal center; then give each animation an
## offset that lines its feet up with the lowest feet in the whole set.
## Result: no vertical pop when the walk starts or stops, regardless of
## how the art was exported. (Uses the bottom-most OPAQUE pixel as the
## "feet" — keep any painted shadows/effects above the feet line, or
## trim them consistently, or they'll skew the measurement.)
func _compute_frame_alignment() -> void:
	var frames := body_sprite.sprite_frames
	if frames == null:
		return
	var info: Dictionary = {}  # String -> { "feet": float, "cx": float }
	for anim_name in frames.get_animation_names():
		var anim := String(anim_name)
		var feet := -1.0e9
		var cx_sum := 0.0
		var n := 0
		for i in frames.get_frame_count(anim_name):
			var tex := frames.get_frame_texture(anim_name, i)
			if tex == null:
				continue
			var used := _used_rect(tex)
			if not used.has_area():
				continue
			# Feet position relative to the frame's CENTER (the origin).
			feet = maxf(feet, float(used.position.y + used.size.y) - tex.get_height() / 2.0)
			cx_sum += (used.position.x + used.size.x) / 2.0 - tex.get_width() / 2.0
			n += 1
		if n > 0:
			info[anim] = {"feet": feet, "cx": cx_sum / n}
	if info.is_empty():
		return
	var lowest_feet := -1.0e9
	for a in info:
		var f: float = info[a]["feet"]
		lowest_feet = maxf(lowest_feet, f)
	for a in info:
		var feet: float = info[a]["feet"]
		var cx: float = info[a]["cx"]
		_anim_offset[a] = Vector2(-cx, lowest_feet - feet)

## Bounding box of the non-transparent pixels in a texture — the same
## measurement interactable.gd uses for comment anchoring.
func _used_rect(tex: Texture2D) -> Rect2i:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	return img.get_used_rect()
