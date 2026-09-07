extends "res://interactable.gd"
## The gurney straps — accept the cheese (id match, door-key style) and
## hand the whole sequence to the gurney puzzle. Also owns its own two
## visual states: cheesy and broken.

@export var cheese_id: StringName = &"cheese"  # must match cheese.tres id exactly (case-sensitive)
@export var puzzle: Node2D                       # drag the GurneyPuzzle node here

## Optional art swaps (leave empty to skip that stage):
@export var cheesy_texture: Texture2D  # straps with cheese smeared on them
@export var broken_texture: Texture2D  # chewed-through straps; if empty, the straps just vanish when broken

var _broken := false


func _ready() -> void:
	super()
	if RoomState.get_flag(self, "broken", false):
		apply_broken_visual()


func on_use_item(item: ItemDef) -> void:
	if not _broken and puzzle != null and item != null and item.id == cheese_id \
			and puzzle.has_method("try_cheese_on_straps"):
		puzzle.try_cheese_on_straps(item)
	else:
		super(item)  # standard rejection line + deselect


# --- visual states (called by the puzzle; safe to call anytime) ---

func apply_cheesy_visual() -> void:
	if cheesy_texture != null:
		sprite.texture = cheesy_texture


func apply_broken_visual() -> void:
	if _broken:
		return
	_broken = true
	RoomState.set_flag(self, "broken", true)
	if broken_texture != null:
		sprite.texture = broken_texture
	else:
		sprite.visible = false
	input_pickable = false  # chewed through — no longer a target
