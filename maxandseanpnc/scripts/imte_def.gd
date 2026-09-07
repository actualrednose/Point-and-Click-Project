extends Resource
class_name ItemDef
## A definition of an inventory item. Author these as .tres files
## in res://items/ — no code needed to add new items to the game.

@export var id: StringName = &""
@export var display_name: String = "Item"
@export_multiline var description: String = "Some kind of thing."
@export var icon: Texture2D
