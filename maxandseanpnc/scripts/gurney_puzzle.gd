extends Node2D
## Gurney puzzle conductor — the opening sequence.
##
## 1) On ready the player is strapped to the gurney (player.set_restrained(true)).
## 2) Cheese taken: the normal pickup fires instantly (item into the bag, cheese
##    object freed) and this script takes over the visuals with zero gap:
##    FallingCheese appears on the shelf the same frame the object vanishes,
##    head lunges up -> *BONK* -> the cheese bounces in an arc into the mouth
##    -> *chomp*.
## 3) Cheese used on the straps: straps turn cheesy, the mouse is summoned, runs
##    over, jumps onto the gurney, chews through the straps -> *SNAP!* ->
##    player stands up, mouse hops down and resumes patrolling.
##
## Solved-state persistence: RoomState flag keyed to this node. Re-entering a
## solved room leaves the player free (straps restore their own broken state).

@export var player: Node2D
## Optional — the head that bonks the shelf. Leave EMPTY: it auto-resolves
## at bonk time to the player's live pose pivot (LyingHeadPivot while
## strapped, HeadPivot otherwise). Only drag something here if the bonk
## should use a different node than the live head.
@export var head_pivot: Node2D
@export var mouse: Node2D
@export var straps_interactable: Node2D

@export_group("Stage props (children of this node)")
@export var falling_cheese: Sprite2D
@export var shelf_point: Marker2D
@export var mouth_point: Marker2D
@export var chew_point: Marker2D

@export_group("Tuning")
## Which way + how far the head lunges for the bonk, LOCAL to the head
## pivot. Up-left lunges toward a shelf left of the head; tune per room.
@export var head_bonk_offset: Vector2 = Vector2(-14.0, -26.0)
## How long the cheese takes to fall from shelf to mouth.
@export var fall_duration: float = 0.5
## How high the cheese hops up before falling (px). 0 = straight line.
@export var fall_arc_height: float = 70.0
@export var chew_duration: float = 2.5

const FloatingTextScene: PackedScene = preload("res://scenes/floating_text.tscn")

var bonked := false
var cheesed := false
var solved := false
var sequence_active := false

var _head_rest_pos: Vector2
var _mouse_stage: String = ""  # "", "to_straps", "retreat"
var _cheese_from: Vector2
var _cheese_to: Vector2


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
		push_warning("GurneyPuzzle: Player not wired, or player.gd is missing set_restrained().")


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
	# The bonking head is whichever pose is live: the lying head while
	# strapped (LyingHeadPivot), the standing head otherwise. Resolved
	# HERE, not in _ready(), because the pose swap happens after _ready.
	if head_pivot == null:
		head_pivot = _resolve_head_pivot()
	if head_pivot == null or shelf_point == null or mouth_point == null or falling_cheese == null:
		push_warning("GurneyPuzzle: bonk wiring incomplete (head_pivot / shelf_point / mouth_point / falling_cheese).")
		sequence_active = false
		return
	sequence_active = true

	# The shelf object was freed the instant the cheese was taken — the
	# FallingCheese sprite takes its place THIS frame, so the cheese is
	# never missing between the pickup and the bonk. (ShelfPoint must sit
	# exactly where the Cheese object's sprite was, or the hand-off shows.)
	falling_cheese.visible = true
	falling_cheese.global_position = shelf_point.global_position

	_head_rest_pos = head_pivot.position
	var tw := create_tween()
	# head lunges up toward the shelf
	tw.tween_property(head_pivot, "position", _head_rest_pos + head_bonk_offset, 0.13)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# IMPACT: the cheese is dislodged the instant the head hits the shelf.
	# _drop_cheese() starts its OWN tween, so the fall runs in parallel
	# with the head bouncing back below — impact, cheese gone, head
	# retracts underneath the falling cheese.
	tw.tween_callback(func():
		_say("*Doof*", shelf_point.global_position)
		_drop_cheese())
	# head drops back with a little bounce (cheese already falling)
	tw.tween_property(head_pivot, "position", _head_rest_pos, 0.24)\
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _drop_cheese() -> void:
	_cheese_from = falling_cheese.global_position  # already sitting on the shelf
	_cheese_to = mouth_point.global_position
	var tw := create_tween()
	# Arc: rises first (fall_arc_height above the line at the halfway
	# point), then comes down — same math as the mouse's jump.
	tw.tween_method(_set_cheese_arc, 0.0, 1.0, fall_duration)
	tw.parallel().tween_property(falling_cheese, "rotation", falling_cheese.rotation + TAU, fall_duration)
	tw.tween_callback(_chomp)


func _set_cheese_arc(t: float) -> void:
	var pos := _cheese_from.lerp(_cheese_to, t)
	pos.y -= sin(t * PI) * fall_arc_height
	falling_cheese.global_position = pos


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
	if mouse != null:
		_mouse_stage = "retreat"
		mouse.jump_back_to_floor()
	else:
		sequence_active = false


# ---------------- helpers ----------------

func _resolve_head_pivot() -> Node2D:
	## The live pose's head pivot: LyingHeadPivot while restrained,
	## HeadPivot otherwise.
	if player == null:
		return null
	for node_name in ["LyingHeadPivot", "HeadPivot"]:
		var candidate := player.get_node_or_null(node_name) as Node2D
		if candidate != null and candidate.visible:
			return candidate
	return player.get_node_or_null("HeadPivot") as Node2D


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
