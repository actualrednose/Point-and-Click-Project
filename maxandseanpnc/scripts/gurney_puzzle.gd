extends Node2D
## Gurney puzzle conductor — the opening sequence.
##
## 1) On ready the player is strapped to the gurney (player.set_restrained(true)).
## 2) Cheese taken: the normal pickup fires instantly (item into the bag, cheese
##    gone from the shelf) and this script plays the choreography on top:
##    head lunges up -> *BONK* -> a cheese sprite tumbles into the mouth -> *chomp*.
## 3) Cheese used on the straps: straps turn cheesy, the mouse is summoned, runs
##    over, jumps onto the gurney, chews through the straps -> *SNAP!* ->
##    player stands up, mouse hops down and resumes patrolling.
##
## Solved-state persistence: RoomState flag keyed to this node. Re-entering a
## solved room leaves the player free (straps restore their own broken state).

@export var player: Node2D
@export var head_pivot: Node2D
@export var mouse: Node2D
@export var straps_interactable: Node2D

@export_group("Stage props (children of this node)")
@export var falling_cheese: Sprite2D
@export var shelf_point: Marker2D
@export var mouth_point: Marker2D
@export var chew_point: Marker2D

@export_group("Tuning")
## Which way + how far the head lunges for the bonk (local to the player).
@export var head_bonk_offset: Vector2 = Vector2(-14.0, -26.0)
@export var chew_duration: float = 2.5

const FloatingTextScene: PackedScene = preload("res://scenes/floating_text.tscn")

var bonked := false
var cheesed := false
var solved := false
var sequence_active := false

var _head_rest_pos: Vector2
var _mouse_stage: String = ""  # "", "to_straps", "retreat"


func _ready() -> void:
	# Stage props auto-resolve from this node's children if the exports
	# weren't dragged (children just need the exact names below):
	if falling_cheese == null:
		falling_cheese = get_node_or_null("FallingCheese") as Sprite2D
	if shelf_point == null:
		shelf_point = get_node_or_null("ShelfPoint") as Marker2D
	if mouth_point == null:
		mouth_point = get_node_or_null("MouthPoint") as Marker2D
	if chew_point == null:
		chew_point = get_node_or_null("ChewPoint") as Marker2D
	if head_pivot == null and player != null:
		head_pivot = player.get_node_or_null("HeadPivot") as Node2D

	if falling_cheese != null:
		falling_cheese.visible = false

	if mouse != null and mouse.has_signal("arrived"):
		mouse.arrived.connect(_on_mouse_arrived)
		mouse.action_finished.connect(_on_mouse_action_finished)
	else:
		push_warning("GurneyPuzzle: Mouse not wired (or wrong node).")

	if RoomState.get_flag(self, "solved", false):
		# Returning to a solved room: stay free. The straps object restores
		# its own broken visual from its own RoomState flag.
		solved = true
		return

	if player != null and player.has_method("set_restrained"):
		# call_deferred: the player's @onready vars are guaranteed to exist
		# no matter which node became ready first (tree order).
		player.set_restrained.call_deferred(true)
	else:
		push_warning("GurneyPuzzle: Player not wired, or player.gd is missing set_restrained() (Part 1).")


# ---------------- beat 1: the bonk ----------------

## Called by shelf_cheese.gd right after a successful pickup.
func on_cheese_taken() -> void:
	if bonked or sequence_active or solved:
		return
	if not _is_strapped():
		return
	bonked = true
	_run_bonk_sequence()


func _run_bonk_sequence() -> void:
	if head_pivot == null or shelf_point == null or mouth_point == null or falling_cheese == null:
		push_warning("GurneyPuzzle: bonk wiring incomplete (head_pivot / shelf_point / mouth_point / falling_cheese).")
		sequence_active = false
		return
	sequence_active = true
	_head_rest_pos = head_pivot.position
	var tw := create_tween()
	# head lunges up toward the shelf
	tw.tween_property(head_pivot, "position", _head_rest_pos + head_bonk_offset, 0.13)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _say("*BONK*", shelf_point.global_position))
	tw.tween_interval(0.12)
	# head drops back with a little bounce
	tw.tween_property(head_pivot, "position", _head_rest_pos, 0.24)\
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	# the dislodged cheese tumbles into the mouth
	tw.tween_callback(_drop_cheese)


func _drop_cheese() -> void:
	falling_cheese.visible = true
	falling_cheese.global_position = shelf_point.global_position
	var tw := create_tween()
	tw.tween_property(falling_cheese, "global_position", mouth_point.global_position, 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(falling_cheese, "rotation", falling_cheese.rotation + TAU, 0.5)
	tw.tween_callback(_chomp)


func _chomp() -> void:
	falling_cheese.visible = false
	_say("*chomp*", mouth_point.global_position)
	sequence_active = false


# ---------------- beat 2: the straps ----------------

## Called by gurney_straps.gd when the cheese is used on the straps.
func try_cheese_on_straps(item: ItemDef) -> void:
	if sequence_active or solved or cheesed or not _is_strapped():
		return  # mid-sequence or already done — swallow the click quietly
	cheesed = true
	sequence_active = true

	Inventory.remove_item(item)  # consume the cheese (auto-deselects, like the key on the door)
	if straps_interactable != null and straps_interactable.has_method("apply_cheesy_visual"):
		straps_interactable.apply_cheesy_visual()

	if mouse == null or chew_point == null:
		push_warning("GurneyPuzzle: mouse / chew_point missing — freeing the player directly.")
		_break_straps()
		return

	_say("I slobber the cheese all over the straps...", _at(chew_point))
	_mouse_stage = "to_straps"
	mouse.go_to(chew_point.global_position.x)


func _on_mouse_arrived() -> void:
	if _mouse_stage == "to_straps":
		mouse.face_toward(player.global_position.x)
		mouse.do_jump(chew_point.global_position)


func _on_mouse_action_finished(action: String) -> void:
	if action == "jump" and _mouse_stage == "to_straps":
		mouse.face_toward(player.global_position.x)
		mouse.do_chew(chew_duration)
		_say("*nibble nibble nibble*", _at(chew_point))
	elif action == "chew" and _mouse_stage == "to_straps":
		_break_straps()
	elif action == "jump" and _mouse_stage == "retreat":
		_mouse_stage = ""
		sequence_active = false
		mouse.resume_patrol()


func _break_straps() -> void:
	_say("*SNAP!*", _at(chew_point))
	if straps_interactable != null and straps_interactable.has_method("apply_broken_visual"):
		straps_interactable.apply_broken_visual()
	if player != null and player.has_method("set_restrained"):
		player.set_restrained(false)
	solved = true
	RoomState.set_flag(self, "solved", true)
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_callback(func(): _say("(I'm free!)", _at(mouth_point)))
	if mouse != null:
		_mouse_stage = "retreat"
		mouse.jump_back_to_floor()
	else:
		sequence_active = false


# ---------------- helpers ----------------

func _is_strapped() -> bool:
	return player != null and player.get("restrained") == true


func _at(p: Node2D) -> Vector2:
	## Null-safe anchor: a marker's position, or this node's own position.
	if p != null:
		return p.global_position
	return global_position


func _say(what: String, at: Vector2) -> void:
	var line := FloatingTextScene.instantiate()
	get_tree().current_scene.add_child(line)
	line.setup(what, at)
