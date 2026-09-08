extends "res://interactable.gd"
## World interactable that opens a DialogueCloseup scene.

@export_group("Dialogue")
@export var dialogue_scene: PackedScene
@export var character_id: StringName = &""
@export var dialogue_choices: Array[DialogueChoice] = []

@export_group("Portrait")
@export var portrait_texture: Texture2D
@export var portrait_frames: SpriteFrames

var _dialogue_instance: Node


func interact() -> void:
	if is_instance_valid(_dialogue_instance):
		return

	if dialogue_scene == null:
		push_warning(
			"%s: dialogue_scene is not assigned."
			% name
		)
		return

	if character_id == &"":
		push_warning(
			"%s: character_id is empty."
			% name
		)
		return

	if dialogue_choices.size() != 4:
		push_warning(
			"%s: expected exactly 4 dialogue choices, got %d."
			% [name, dialogue_choices.size()]
		)
		return

	_face_player_toward()

	# Clear the world hover before the modal overlay appears.
	if _hovered:
		_set_hovered(false)
	CursorManager.clear_hover()

	_dialogue_instance = dialogue_scene.instantiate()
	if _dialogue_instance == null:
		push_warning(
			"%s: dialogue_scene could not be instantiated."
			% name
		)
		return

	if not _dialogue_instance.has_method("setup"):
		push_warning(
			"%s: dialogue scene does not have a setup() method."
			% name
		)
		_dialogue_instance.queue_free()
		_dialogue_instance = null
		return

	get_tree().current_scene.add_child(_dialogue_instance)

	_dialogue_instance.setup(
		character_id,
		dialogue_choices,
		portrait_texture,
		portrait_frames
	)

	if _dialogue_instance.has_signal("closed"):
		_dialogue_instance.closed.connect(_on_dialogue_closed)
	else:
		push_warning(
			"%s: dialogue scene does not have a closed signal."
			% name
		)


func _on_dialogue_closed() -> void:
	_dialogue_instance = null
