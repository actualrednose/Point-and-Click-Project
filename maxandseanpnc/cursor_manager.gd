extends Node
## Global cursor controller — register as autoload "CursorManager".
## Swaps the mouse cursor between DEFAULT / EYE / HAND / ITEM states.
## While hovering an interactable, EYE vs HAND is re-decided every
## physics frame, so the cursor morphs live as the player walks.

enum State { DEFAULT, EYE, HAND, ITEM }

const PATH_POINTER := "res://assets/cursors/pointer.png"
const PATH_EYE := "res://assets/cursors/eye.png"
const PATH_HAND := "res://assets/cursors/hand.png"

# Click point of each cursor, in pixels from the texture's TOP-LEFT.
# Autoloads have no Inspector panel — tune these defaults in this file.
@export var hotspot_pointer: Vector2i = Vector2i(9, 9)
@export var hotspot_eye: Vector2i = Vector2i(23, 23)
@export var hotspot_hand: Vector2i = Vector2i(24, 25)
@export var hotspot_item: Vector2i = Vector2i(23, 23)

var _state: State = State.DEFAULT
var _hovered: Node = null
var _item_texture: Texture2D = null

var _tex_pointer: Texture2D
var _tex_eye: Texture2D
var _tex_hand: Texture2D

func _ready() -> void:
	_tex_pointer = _load_cursor(PATH_POINTER)
	_tex_eye = _load_cursor(PATH_EYE)
	_tex_hand = _load_cursor(PATH_HAND)

func _load_cursor(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	push_warning("CursorManager: '%s' not found — system cursor used for that state." % path)
	return null

## Called by interactables on hover enter/exit. The exit is
## identity-checked so a stale exit can't clear a newer hover.
func notify_hover(obj: Node, entered: bool) -> void:
	if entered:
		_hovered = obj
	elif _hovered == obj:
		_hovered = null
		
## True while the cursor is over an interactable. Inventory uses
## this to tell "click on an object" from "click on empty space" —
## object clicks arrive at _unhandled_input BEFORE the object
## itself receives them, so this is the only reliable test.
func has_hover() -> bool:
	return _hovered != null and is_instance_valid(_hovered)

## Phase 7 API: cursor becomes the held item's icon.
func select_item(texture: Texture2D) -> void:
	_item_texture = texture
	_set_state(State.ITEM)

func deselect_item() -> void:
	_item_texture = null
	_set_state(State.DEFAULT)

func _physics_process(_delta: float) -> void:
	if _state == State.ITEM:
		return  # While holding an item, the cursor IS the item.
	if is_instance_valid(_hovered) and _hovered.has_method("player_is_in_range"):
		var near: bool = _hovered.player_is_in_range()
		_set_state(State.HAND if near else State.EYE)
	else:
		_hovered = null
		_set_state(State.DEFAULT)

func _set_state(new_state: State) -> void:
	if new_state == _state:
		return  # Only touch the OS cursor on actual changes — no flicker.
	_state = new_state
	match _state:
		State.DEFAULT:
			_apply_cursor(_tex_pointer, hotspot_pointer)
		State.EYE:
			_apply_cursor(_tex_eye, hotspot_eye)
		State.HAND:
			_apply_cursor(_tex_hand, hotspot_hand)
		State.ITEM:
			_apply_cursor(_item_texture, hotspot_item)

func _apply_cursor(texture: Texture2D, hotspot: Vector2i) -> void:
	if texture == null:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
		return
	var tex := texture
	const MAX_PX := 48
	if tex.get_width() > MAX_PX or tex.get_height() > MAX_PX:
		var img := tex.get_image()
		var s := float(MAX_PX) / maxf(tex.get_width(), tex.get_height())
		img.resize(maxi(1, int(tex.get_width() * s)),
			maxi(1, int(tex.get_height() * s)), Image.INTERPOLATE_LANCZOS)
		tex = ImageTexture.create_from_image(img)
		hotspot = Vector2i(int(hotspot.x * s), int(hotspot.y * s))
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, hotspot)
