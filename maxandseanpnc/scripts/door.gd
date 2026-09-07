extends "res://interactable.gd"
## A locked door that a specific key opens — and, optionally, leads
## somewhere. The working example of the object-script pattern:
##   - Override only what you need (on_use_item, interact, _ready).
##   - State changes = mutating your own exported texts.
##   - Visual change = swapping the Sprite texture at runtime.
##   - Persistence = RoomState flags (survive room transitions).

@export_group("Door")
## The ItemDef id that opens this door.
@export var key_id: StringName = &"key"
@export var unlock_text: String = "The key turns with a grinding click."
@export var open_texture: Texture2D
@export var unlocked_look_text: String = "The door stands open."
@export var unlocked_interact_text: String = "It's open. Cold air drifts out."

@export_group("Exit")
## Where this door leads once open. Leave empty for a door to nowhere.
## (Path string, NOT a scene resource — rooms referencing each other
## as PackedScene resources create a circular dependency the loader
## can't resolve. Paths are only resolved at click time.)
@export_file("*.tscn") var target_room_path: String = ""
## Name of the Marker2D in the target room to appear at.
@export var spawn_name: String = ""

var _unlocked := false

func _ready() -> void:
	super()
	# Returning to this room? Restore unlocked state.
	if RoomState.get_flag(self, "unlocked", false):
		_apply_unlocked()

func on_use_item(item: ItemDef) -> void:
	if _unlocked or item.id != key_id:
		super(item)  # Wrong item (or already open): base rejection.
		return
	# The right key.
	_face_player_toward()
	show_comment(unlock_text)
	Inventory.remove_item(item)  # Consumed — auto-deselects.
	RoomState.set_flag(self, "unlocked", true)
	_apply_unlocked()

## Walk through an open door that leads somewhere.
func interact() -> void:
	if _unlocked and not target_room_path.is_empty():
		RoomManager.goto_room(target_room_path, spawn_name)
		return
	super()  # Locked: "Locked tight". Open, no target: open text.

func _apply_unlocked() -> void:
	# Shared by the unlock action AND the _ready restore.
	_unlocked = true
	look_text = unlocked_look_text
	interact_text = unlocked_interact_text
	if open_texture:
		sprite.texture = open_texture
