extends Node2D
## Key theft — the second lab puzzle beat.
##
## The player reaches for the key on the table, knocks it off (arc
## tumble to the floor), and the mouse dashes over, snatches it, and
## scurries into the mousehole with it. The key is gone for now —
## getting it back is a puzzle for later (this beat intentionally
## dead-ends: the door CANNOT be unlocked this session).
##
## Persistence, for free: the key object is mark_taken'd at the snatch —
## the base interactable self-frees on room reload exactly like a normal
## pickup (no custom code in table_key.gd). This node's "stolen" flag
## hides the mouse in the hole on re-entry.
##
## The mouse's signals are stage-gated ("to_key" / "to_hole"), so other
## conductors (GurneyPuzzle) can listen to the same mouse safely.

@export var mouse: Node2D
## Optional: the MouseHole interactable — gets look_text_after_theft
## swapped in at the snatch (session-only; author the hole's real
## look_text for the long-term state).
@export var hole_interactable: Node2D

@export_group("Stage points (children of this node)")
@export var key_floor_point: Marker2D
@export var hole_point: Marker2D

@export_group("Tuning")
## How long the key takes to tumble from table to floor.
@export var knock_duration: float = 0.45
## How high the key hops off the table edge before falling.
@export var knock_arc_height: float = 60.0
## Beat between the mouse reaching the key and grabbing it.
@export var snatch_pause: float = 0.35
## Line the hole says when clicked after the theft (empty = no swap).
@export var look_text_after_theft: String = ""

const FloatingTextScene: PackedScene = preload("res://scenes/floating_text.tscn")

var stolen := false
var sequence_active := false

var _stage := ""  # "", "to_key", "to_hole"
var _key_object: Node2D
var _key_from: Vector2
var _key_to: Vector2


func _ready() -> void:
	# Stage points auto-resolve from this node's children if the exports
	# weren't dragged (children just need the exact names below):
	if key_floor_point == null:
		key_floor_point = get_node_or_null("KeyFloorPoint") as Marker2D
	if hole_point == null:
		hole_point = get_node_or_null("HolePoint") as Marker2D

	if mouse != null and mouse.has_signal("arrived"):
		mouse.arrived.connect(_on_mouse_arrived)
		mouse.action_finished.connect(_on_mouse_action_finished)
	else:
		push_warning("KeyTheft: Mouse not wired (or wrong node).")

	if RoomState.get_flag(self, "stolen", false):
		stolen = true
		# The mouse already lives in the hole with the key. Deferred so
		# it runs after every _ready in the tree — the mouse STARTS its
		# patrol in _ready, so stopping it must come after.
		_hide_mouse_in_hole.call_deferred()


# ---------------- the theft ----------------

## Called by table_key.gd when the player interacts with the key.
func try_take_key(key_object: Node2D) -> void:
	if stolen or sequence_active:
		return
	if key_floor_point == null or mouse == null:
		push_warning("KeyTheft: KeyFloorPoint / mouse missing — theft can't play.")
		return
	sequence_active = true
	_key_object = key_object
	_key_from = key_object.global_position
	_key_to = key_floor_point.global_position

	_say("Oops!", _key_from)
	var tw := create_tween()
	tw.tween_method(_set_key_arc, 0.0, 1.0, knock_duration)
	tw.parallel().tween_property(key_object, "rotation",
		key_object.rotation + TAU, knock_duration)
	tw.tween_callback(func():
		_say("*Clunk!", _key_to)
		_stage = "to_key"
		mouse.go_to(_key_to.x))


func _set_key_arc(t: float) -> void:
	if _key_object == null or not is_instance_valid(_key_object):
		return
	var pos := _key_from.lerp(_key_to, t)
	pos.y -= sin(t * PI) * knock_arc_height
	_key_object.global_position = pos


func _on_mouse_arrived() -> void:
	if _stage == "to_key":
		mouse.face_toward(_key_to.x)
		var tw := create_tween()
		tw.tween_interval(snatch_pause)
		tw.tween_callback(_snatch)
	elif _stage == "to_hole":
		mouse.do_jump(hole_point.global_position)


func _snatch() -> void:
	if _key_object != null and is_instance_valid(_key_object):
		RoomState.mark_taken(_key_object)  # base self-frees it on reload
		_key_object.queue_free()
	stolen = true
	RoomState.set_flag(self, "stolen", true)
	if hole_interactable != null and not look_text_after_theft.is_empty():
		hole_interactable.look_text = look_text_after_theft
	_dash_to_hole()
	var tw := create_tween()
	tw.tween_interval(0.5)


func _dash_to_hole() -> void:
	if mouse == null or hole_point == null:
		sequence_active = false
		return
	_stage = "to_hole"
	mouse.go_to(hole_point.global_position.x)


func _on_mouse_action_finished(action: String) -> void:
	if action == "jump" and _stage == "to_hole":
		_hide_mouse_in_hole()
		_say("Damn.", _at(hole_point))
		_stage = ""
		sequence_active = false


# ---------------- helpers ----------------

func _hide_mouse_in_hole() -> void:
	if mouse == null:
		return
	mouse.stop()  # IDLE — patrol stays off until something summons it again
	mouse.visible = false


func _at(p: Node2D) -> Vector2:
	## Null-safe anchor: a marker's position, or this node's own position.
	if p != null:
		return p.global_position
	return global_position


func _say(what: String, at: Vector2) -> void:
	var line := FloatingTextScene.instantiate()
	get_tree().current_scene.add_child(line)
	line.setup(what, at)
