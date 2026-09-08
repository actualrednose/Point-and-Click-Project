extends CanvasLayer
## Reusable dialogue close-up UI.
##
## The NPC supplies the character ID and four DialogueChoice resources.
## This scene owns presentation, button input, dialogue history display,
## portrait animation, and returning to the choice menu after each response.

signal closed
signal choice_selected(choice: DialogueChoice)

const DIALOGUE_HISTORY_PREFIX := "dialogue/"

const NORMAL_TEXT_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const SEEN_TEXT_COLOR := Color(0.48, 0.48, 0.48, 1.0)
const HOVER_TEXT_COLOR := Color(1.0, 0.84, 0.31, 1.0)

var _character_id: StringName = &""
var _choices: Array[DialogueChoice] = []
var _portrait_texture: Texture2D
var _portrait_frames: SpriteFrames

var _root: Control
var _backdrop: Control
var _portrait_image: TextureRect
var _portrait_animation: AnimatedSprite2D
var _dialogue_bar: Control
var _response_label: Label
var _choices_box: VBoxContainer
var _close_button: BaseButton

var _choice_buttons: Array[Button] = []
var _response_tween: Tween
var _closing := false
var _speaking := false
var _is_ready := false


func _ready() -> void:
	layer = 20
	_is_ready = true

	_root = get_node_or_null("Root") as Control
	_backdrop = get_node_or_null("Root/Backdrop") as Control
	_portrait_image = get_node_or_null(
		"Root/PortraitArea/PortraitImage"
	) as TextureRect
	_portrait_animation = get_node_or_null(
		"Root/PortraitArea/PortraitAnimation"
	) as AnimatedSprite2D
	_dialogue_bar = get_node_or_null("Root/DialogueBar") as Control
	_response_label = get_node_or_null(
		"Root/DialogueBar/Content/ResponseLabel"
	) as Label
	_choices_box = get_node_or_null(
		"Root/DialogueBar/Content/Choices"
	) as VBoxContainer
	_close_button = get_node_or_null("Root/CloseButton") as BaseButton

	_configure_input()
	_apply_portrait()
	_build_choice_buttons()
	_show_open_animation()

	CursorManager.clear_hover()


func setup(
	character_id: StringName,
	choices: Array[DialogueChoice],
	portrait_texture: Texture2D = null,
	portrait_frames: SpriteFrames = null
) -> void:
	_character_id = character_id
	_choices = choices.duplicate()
	_portrait_texture = portrait_texture
	_portrait_frames = portrait_frames

	_validate_setup()

	if _is_ready:
		_apply_portrait()
		_build_choice_buttons()


func _validate_setup() -> void:
	if _character_id == &"":
		push_warning("DialogueCloseup: character_id is empty.")

	if _choices.size() != 4:
		push_warning(
			"DialogueCloseup: expected exactly 4 choices, got %d."
			% _choices.size()
		)

	var seen_ids: Dictionary = {}

	for choice in _choices:
		if choice == null:
			push_warning("DialogueCloseup: one of the choices is null.")
			continue

		if choice.id == &"":
			push_warning("DialogueCloseup: a choice has an empty id.")
		elif seen_ids.has(choice.id):
			push_warning(
				"DialogueCloseup: duplicate choice id '%s'."
				% choice.id
			)
		else:
			seen_ids[choice.id] = true

		if choice.option_text.is_empty():
			push_warning(
				"DialogueCloseup: choice '%s' has no option text."
				% choice.id
			)

		if choice.response_text.is_empty():
			push_warning(
				"DialogueCloseup: choice '%s' has no response text."
				% choice.id
			)

func _configure_input() -> void:
	if _root != null:
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if _backdrop != null:
		_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		_backdrop.gui_input.connect(_on_backdrop_input)

	if _dialogue_bar != null:
		_dialogue_bar.mouse_filter = Control.MOUSE_FILTER_STOP

	if _portrait_image != null:
		_portrait_image.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if _close_button != null:
		_close_button.focus_mode = Control.FOCUS_NONE
		_close_button.pressed.connect(_close)

func _apply_portrait() -> void:
	var portrait_area := get_node_or_null(
		"Root/PortraitArea"
	) as Control

	var image_texture: Texture2D = null
	if _portrait_image != null:
		image_texture = _portrait_texture
		if image_texture == null:
			image_texture = _portrait_image.texture

	var use_animation := false

	if _portrait_frames != null:
		use_animation = true
	elif image_texture == null \
			and _portrait_animation != null \
			and _portrait_animation.sprite_frames != null:
		use_animation = true

	# Configure the TextureRect portrait.
	if _portrait_image != null:
		_portrait_image.set_anchors_and_offsets_preset(
			Control.PRESET_FULL_RECT
		)
		_portrait_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_portrait_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_portrait_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_portrait_image.visible = not use_animation

		if image_texture != null:
			_portrait_image.texture = image_texture

	# Configure the AnimatedSprite2D portrait.
	if _portrait_animation != null:
		if _portrait_frames != null:
			_portrait_animation.sprite_frames = _portrait_frames

		_portrait_animation.visible = use_animation
		_portrait_animation.centered = true

		if portrait_area != null:
			_portrait_animation.position = portrait_area.size / 2.0

		if use_animation \
				and _portrait_animation.sprite_frames != null \
				and _portrait_animation.sprite_frames.has_animation("idle"):
			_portrait_animation.play("idle")


func _build_choice_buttons() -> void:
	if _choices_box == null:
		push_warning(
			"DialogueCloseup: Root/DialogueBar/Content/Choices is missing."
		)
		return

	for button in _choice_buttons:
		button.queue_free()

	_choice_buttons.clear()

	for index in _choices.size():
		var choice := _choices[index]
		if choice == null:
			continue

		var button := Button.new()
		button.name = "Choice%d" % (index + 1)
		button.text = choice.option_text
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0.0, 42.0)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		button.add_theme_color_override(
			"font_color",
			NORMAL_TEXT_COLOR
		)
		button.add_theme_color_override(
			"font_hover_color",
			HOVER_TEXT_COLOR
		)
		button.add_theme_color_override(
			"font_pressed_color",
			HOVER_TEXT_COLOR
		)

		button.mouse_entered.connect(
			_on_choice_hovered.bind(button)
		)
		button.mouse_exited.connect(
			_on_choice_unhovered.bind(button)
		)
		button.pressed.connect(
			_on_choice_pressed.bind(index)
		)

		_choices_box.add_child(button)
		_choice_buttons.append(button)

	_refresh_seen_states()


func _on_choice_hovered(button: Button) -> void:
	if _speaking or _closing:
		return

	button.add_theme_color_override(
		"font_color",
		HOVER_TEXT_COLOR
	)


func _on_choice_unhovered(button: Button) -> void:
	if _speaking or _closing:
		return

	var index := _choice_buttons.find(button)
	if index < 0 or index >= _choices.size():
		return

	var choice := _choices[index]
	var color := SEEN_TEXT_COLOR if _was_choice_seen(choice) \
		else NORMAL_TEXT_COLOR

	button.add_theme_color_override("font_color", color)


func _on_choice_pressed(index: int) -> void:
	if _speaking or _closing:
		return

	if index < 0 or index >= _choices.size():
		return

	var choice := _choices[index]
	if choice == null:
		return

	_speaking = true
	_mark_choice_seen(choice)
	_refresh_seen_states()
	choice_selected.emit(choice)

	if _choices_box != null:
		_choices_box.visible = false

	if _response_label != null:
		_response_label.text = choice.response_text
		_response_label.visible = true

	_play_portrait("talk")

	_response_tween = create_tween()
	_response_tween.tween_interval(_response_duration(choice.response_text))
	_response_tween.tween_callback(_finish_response)


func _finish_response() -> void:
	if _closing:
		return

	_response_tween = null
	_speaking = false

	if _response_label != null:
		_response_label.text = ""
		_response_label.visible = false

	if _choices_box != null:
		_choices_box.visible = true

	_play_portrait("idle")
	_refresh_seen_states()

func _refresh_seen_states() -> void:
	for index in _choice_buttons.size():
		if index >= _choices.size():
			continue

		var choice := _choices[index]
		if choice == null:
			continue

		var button := _choice_buttons[index]
		var color := SEEN_TEXT_COLOR if _was_choice_seen(choice) \
			else NORMAL_TEXT_COLOR

		button.add_theme_color_override("font_color", color)

func _was_choice_seen(choice: DialogueChoice) -> bool:
	if choice == null or choice.id == &"":
		return false

	var key := _history_key(choice)
	return RoomState.get_global_flag(key, false) == true

func _mark_choice_seen(choice: DialogueChoice) -> void:
	if choice == null or choice.id == &"":
		return

	RoomState.set_global_flag(_history_key(choice), true)

func _history_key(choice: DialogueChoice) -> String:
	return DIALOGUE_HISTORY_PREFIX \
		+ String(_character_id) \
		+ "/" \
		+ String(choice.id)

func _response_duration(text: String) -> float:
	# Longer responses stay visible longer, with sensible limits.
	return clampf(1.4 + text.length() * 0.035, 1.8, 6.0)


func _play_portrait(animation_name: StringName) -> void:
	if _portrait_animation == null:
		return

	if _portrait_animation.sprite_frames == null:
		return

	if not _portrait_animation.sprite_frames.has_animation(animation_name):
		if animation_name == &"talk":
			return

		if _portrait_animation.sprite_frames.has_animation("idle"):
			_portrait_animation.play("idle")

		return

	_portrait_animation.play(animation_name)

func _show_open_animation() -> void:
	if _root == null:
		return

	_root.modulate.a = 0.0

	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 1.0, 0.15)

func _on_backdrop_input(event: InputEvent) -> void:
	if _closing:
		return

	if event.is_action_pressed("click"):
		_close()

func _close() -> void:
	if _closing:
		return

	_closing = true
	_speaking = false

	if _response_tween != null and _response_tween.is_valid():
		_response_tween.kill()
		_response_tween = null

	CursorManager.clear_hover()

	if _root == null:
		_finish_close()
		return

	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.15)
	tween.tween_callback(_finish_close)

func _finish_close() -> void:
	closed.emit()
	queue_free()
