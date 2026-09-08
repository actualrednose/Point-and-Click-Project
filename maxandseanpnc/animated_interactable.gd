extends Area2D
## Base class for anything the player can look at or interact with.

signal hover_changed(is_hovered: bool)

const FLOATING_TEXT := preload("res://scenes/floating_text.tscn")

@export_group("Identity")
@export var display_name: String = "Object"
@export_multiline var look_text: String = "Nothing special."
## Shown when interacting in range and no object-specific script
## overrides interact().
@export var interact_text: String = "Nothing happens."
## Shown when using an item that has no effect here. Empty = an
## automatic line naming the item ("I can't use the X here.").
@export var reject_item_text: String = ""
## Shown when clicking (item held) from too far away.
@export var too_far_text: String = "I'd need to get closer."

@export_group("Interaction")
## How close (horizontal px) the player must stand to interact
## instead of just looking. Measured player.x -> InteractionPoint.x.
@export var interaction_range: float = 140.0
## If set, interacting with this object picks the item up and
## removes the object from the room.
@export var pickup_item: ItemDef
## Comment shown when the item is picked up.
@export var pickup_text: String = "Taken."

@export_group("Glow")
@export var glow_color: Color = Color(1.0, 0.84, 0.31, 1.0)

@onready var sprite: Sprite2D = $Sprite
@onready var interaction_point: Marker2D = $InteractionPoint

var _hovered: bool = false
var _glow_tween: Tween
var _active_text: Node
var _used_rect: Rect2i
var _used_rect_tex: Texture2D  # Texture the cache came from.
var _used_rect_known := false

func _ready() -> void:
	# Already taken this session? Vanish silently on room re-entry.
	if RoomState.is_taken(self):
		call_deferred("queue_free")
		return
	add_to_group("interactables")
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)
	_own_material()

func _exit_tree() -> void:
	# Freed while hovered (e.g. picked up): clear cursor/glow.
	if _hovered:
		CursorManager.notify_hover(self, false)

func _own_material() -> void:
	# Instances would otherwise SHARE one material and its `hovered`
	# uniform — everyone would glow at once.
	if sprite.material is ShaderMaterial:
		sprite.material = sprite.material.duplicate()
		sprite.material.set_shader_parameter("glow_color", glow_color)
		sprite.material.set_shader_parameter("hovered", 0.0)
	else:
		push_warning("%s: Sprite has no ShaderMaterial — hover glow disabled." % name)

# ---------- Hover ----------

func _on_mouse_entered() -> void:
	_set_hovered(true)

func _on_mouse_exited() -> void:
	_set_hovered(false)

func _set_hovered(value: bool) -> void:
	if value == _hovered:
		return
	_hovered = value
	hover_changed.emit(value)
	CursorManager.notify_hover(self, value)
	_fade_glow(1.0 if value else 0.0)

func _fade_glow(target: float) -> void:
	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = create_tween()
	_glow_tween.tween_property(sprite, "material:shader_parameter/hovered", target, 0.15)

# ---------- Clicks ----------

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event.is_action_pressed("click"):
		# Object clicks must not reach the empty-space fallback.
		get_viewport().set_input_as_handled()
		handle_click()

## Final routing — don't override this. Object scripts override
## look() / interact() / on_use_item() instead.
func handle_click() -> void:
	print("[DBG] %s clicked — held: %s" % [name, Inventory.selected_item])
	if Inventory.selected_item:
		if player_is_in_range():
			on_use_item(Inventory.selected_item)
		else:
			show_comment(too_far_text)  # Item stays held.
		return
	if player_is_in_range():
		interact()
	else:
		look()

## Out of range: examine from where you stand.
func look() -> void:
	show_comment(look_text)

## In range. Picks the item up when pickup_item is set; otherwise
## just talks. Override in object scripts (door.gd is the example).
func interact() -> void:
	if pickup_item:
		_do_pickup()
		return
	_face_player_toward()
	show_comment(interact_text)

func _do_pickup() -> void:
	_face_player_toward()
	show_comment(pickup_text)
	if not Inventory.add_item(pickup_item):
		return  # Already owned (or bad id) — keep the object.
	RoomState.mark_taken(self)
	# Clear hover BEFORE freeing, so cursor and glow can't get stuck.
	if _hovered:
		_set_hovered(false)
	queue_free()

## Clicking this object while holding an item. Base: polite
## rejection, item goes back. Override in object scripts — door.gd
## is the working example.
func on_use_item(item: ItemDef) -> void:
	_face_player_toward()
	var line := reject_item_text
	if line.is_empty():
		line = "I can't use the %s here." % item.display_name.to_lower()
	show_comment(line)
	Inventory.deselect_item()

# ---------- Helpers ----------

func player_is_in_range() -> bool:
	var player := _get_player()
	if player == null:
		return false
	return absf(player.global_position.x
		- interaction_point.global_position.x) <= interaction_range

func _get_player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D

func _face_player_toward() -> void:
	var player := _get_player()
	if player and player.has_method("set_facing"):
		var dir: int = 1 if interaction_point.global_position.x >= player.global_position.x else -1
		player.set_facing(dir)

func show_comment(line: String) -> void:
	if line.is_empty():
		return
	if is_instance_valid(_active_text):
		_active_text.queue_free()  # A new click replaces the current line.
	var t := FLOATING_TEXT.instantiate() as Label
	get_tree().current_scene.add_child(t)
	t.setup(line, _comment_anchor())
	_active_text = t

## Global point 26px above the VISIBLE art — whatever transparent
## margins, offsets, or scaling the sprite has.
func _comment_anchor() -> Vector2:
	var top_px := 0.0
	var used := _visible_pixels()
	if used.has_area():
		if sprite.flip_v:
			top_px = sprite.texture.get_height() - used.position.y - used.size.y
		else:
			top_px = used.position.y
	var rect := sprite.get_rect()  # Texture rect in the sprite's local space.
	var top_local := Vector2(rect.get_center().x, rect.position.y + top_px)
	return sprite.to_global(top_local) - Vector2(0.0, 26.0)

## Bounding box of the non-transparent pixels in the sprite's
## texture — re-scanned if the texture changes at runtime
## (e.g. a door swapping to its open art).
func _visible_pixels() -> Rect2i:
	if sprite.texture and (not _used_rect_known or _used_rect_tex != sprite.texture):
		_used_rect_known = true
		_used_rect_tex = sprite.texture
		var img := sprite.texture.get_image()
		if img.is_compressed():
			img.decompress()
		_used_rect = img.get_used_rect()
	return _used_rect
