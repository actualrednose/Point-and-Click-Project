extends "res://interactable.gd"

@export_group("Candle")
@export var unlit_candle_id: StringName = &"unlit_candle"
@export var lit_candle: ItemDef
@export var light_text: String = "The candle catches fire."

func on_use_item(item: ItemDef) -> void:
	if item.id != unlit_candle_id:
		super(item)
		return

	_face_player_toward()

	if lit_candle == null:
		push_warning("Sconce: lit_candle has not been assigned.")
		return

	if not Inventory.remove_item(item):
		return

	if not Inventory.add_item(lit_candle):
		# This should normally never happen because removing the candle
		# frees the inventory slot, but keep the failure safe.
		Inventory.add_item(item)
		return

	show_comment(light_text)
