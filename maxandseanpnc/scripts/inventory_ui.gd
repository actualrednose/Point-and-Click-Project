extends CanvasLayer
## Bag-style inventory: a chromeless bag button in the bottom-left
## corner. Clicking it opens the item bar, which unrolls rightward
## out of the bag — bare icons, no boxes. Hovering an item glows
## gold via the same shader the room interactables use, and the
## glow stays PINNED ON while the item is selected (held).
## Drag this scene into a room ONCE.

const GLOW_SHADER := preload("res://shaders/hover_outline.gdshader")
const GLOW_GOLD := Color(1.0, 0.84, 0.31, 1.0)
const SELECTED_TINT := Color(1.0, 0.88, 0.45, 1.0)

const SCREEN := Vector2(1920, 1080)
const MARGIN := 30.0
const BAG_SIZE := Vector2(80, 80)
const GAP := 14.0            # Space between bag and bar.
const SLOT_SIZE := Vector2(72, 72)

const PATH_BAG := "res://assets/bag.png"
const PATH_BAG_OPEN := "res://assets/bag_open.png"
const CHEESE_ID: StringName = &"cheese"
const BAG_HINT_DISMISSED_FLAG := "inventory_bag_hint_dismissed"

const OPEN_TIME := 0.28
const CLOSE_TIME := 0.18

var _open := false
var _bag: Button
var _bag_image: TextureRect
var _bag_tex_closed: Texture2D
var _bag_tex_open: Texture2D
var _bag_glow_material: ShaderMaterial
var _clip: Control            # Width of this is what animates.
var _panel: PanelContainer    # Invisible — layout + measurement only.
var _hbox: HBoxContainer
var _size_tween: Tween
var _bag_hint_tween: Tween
var _bag_hint_active := false
var _slot_by_item: Dictionary = {}      # ItemDef -> Control
var _hover_tweens: Dictionary = {}      # ItemDef -> Tween
var _hovered_items: Array[ItemDef] = [] # Slots under the mouse now.
var _bag_sb_normal: StyleBoxFlat
var _bag_sb_hover: StyleBoxFlat
var _bag_sb_open: StyleBoxFlat
# Only used for the no-bag-art / no-icon text fallbacks.
var _text_sb := StyleBoxEmpty.new()


func _ready() -> void:
	layer = 10
	_bag_tex_closed = _load_optional(PATH_BAG)
	_bag_tex_open = _load_optional(PATH_BAG_OPEN)
	_make_styleboxes()
	_build_ui()

	Inventory.item_added.connect(_on_item_added)
	Inventory.item_removed.connect(_on_item_removed)
	Inventory.selection_changed.connect(_on_selection_changed)

	for item in Inventory.items:
		_add_slot(item, false)  # Entering a room already holding items.

	if _should_show_bag_hint():
		_start_bag_hint()


func _load_optional(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


# ---------- Layout ----------

func _build_ui() -> void:
	# Fills the screen but NEVER blocks world clicks itself.
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- The bag button, bottom-left corner. ---
	_bag = Button.new()
	_bag.name = "BagButton"
	_bag.position = Vector2(MARGIN, SCREEN.y - MARGIN - BAG_SIZE.y)
	_bag.size = BAG_SIZE
	_bag.pivot_offset = BAG_SIZE / 2.0
	_bag.focus_mode = Control.FOCUS_NONE
	_bag.tooltip_text = "Inventory"
	_bag.pressed.connect(_on_bag_pressed)

	_bag_image = TextureRect.new()
	_bag_image.name = "BagImage"
	_bag_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bag_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bag_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_bag_image.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_bag_glow_material = ShaderMaterial.new()
	_bag_glow_material.shader = GLOW_SHADER
	_bag_glow_material.set_shader_parameter("glow_color", GLOW_GOLD)
	_bag_glow_material.set_shader_parameter("hovered", 0.0)

	_bag_image.material = _bag_glow_material
	_bag.add_child(_bag_image)

	_apply_bag_icon()
	root.add_child(_bag)

	# --- The reveal clip: a PLAIN Control (no children-driven
	# minimum, so its size animates freely) that crops the bar. ---
	_clip = Control.new()
	_clip.name = "RevealClip"
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.visible = false
	root.add_child(_clip)

	# --- Invisible layout container: sizes the HBox, measures the
	# bar, draws nothing, stops clicks over the icon row. ---
	_panel = PanelContainer.new()
	_panel.name = "ItemBar"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _text_sb)
	_clip.add_child(_panel)

	_hbox = HBoxContainer.new()
	_hbox.add_theme_constant_override("separation", 10)
	_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_hbox)


# ---------- Bag open / close ----------

func _on_bag_pressed() -> void:
	if Inventory.items.is_empty():
		_shake_bag()
		return

	_dismiss_bag_hint()
	_set_open(not _open)


func _should_show_bag_hint() -> bool:
	return not Inventory.items.is_empty() \
		and Inventory.has_item(CHEESE_ID) \
		and not RoomState.get_global_flag(
			BAG_HINT_DISMISSED_FLAG,
			false
		)


func _start_bag_hint() -> void:
	if _bag_hint_active or _bag_glow_material == null:
		return

	_bag_hint_active = true
	_bag_hint_tween = create_tween().set_loops()

	_bag_hint_tween.tween_method(
		func(value: float) -> void:
			_set_bag_hint_glow(value),
		0.0,
		1.0,
		0.42
	)

	_bag_hint_tween.tween_interval(0.16)

	_bag_hint_tween.tween_method(
		func(value: float) -> void:
			_set_bag_hint_glow(value),
		1.0,
		0.0,
		0.42
	)

	_bag_hint_tween.tween_interval(0.34)


func _set_bag_hint_glow(value: float) -> void:
	if _bag_glow_material:
		_bag_glow_material.set_shader_parameter("hovered", value)


func _dismiss_bag_hint() -> void:
	if not _bag_hint_active:
		return

	RoomState.set_global_flag(BAG_HINT_DISMISSED_FLAG, true)
	_bag_hint_active = false

	if _bag_hint_tween and _bag_hint_tween.is_valid():
		_bag_hint_tween.kill()
		_bag_hint_tween = null

	_set_bag_hint_glow(0.0)


func _set_open(value: bool) -> void:
	if value == _open:
		return

	_open = value
	_apply_bag_icon()
	_pop_bag()

	if _open:
		var natural := _panel_natural()
		_panel.size = natural

		_clip.position = Vector2(
			MARGIN + BAG_SIZE.x + GAP,
			_bar_center_y() - natural.y / 2.0
		)

		_clip.size = Vector2(0.0, natural.y)
		_clip.visible = true
		_tween_clip(_target_width(), OPEN_TIME, false, true)
	else:
		_tween_clip(0.0, CLOSE_TIME, true, false)


func _panel_natural() -> Vector2:
	return _panel.get_combined_minimum_size()


func _bar_center_y() -> float:
	return SCREEN.y - MARGIN - BAG_SIZE.y / 2.0


## Max width the bar may reach (design space), keeping it on-screen.
func _target_width() -> float:
	var natural_x := _panel_natural().x

	return minf(
		natural_x,
		SCREEN.x - (MARGIN + BAG_SIZE.x + GAP) - MARGIN
	)


func _tween_clip(
	target: float,
	time: float,
	hide_when_done: bool,
	springy: bool
) -> void:
	if _size_tween and _size_tween.is_valid():
		_size_tween.kill()

	_size_tween = create_tween()

	var step := _size_tween.tween_property(
		_clip,
		"size:x",
		target,
		time
	)

	if springy:
		step.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		step.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	if hide_when_done:
		_size_tween.tween_callback(
			func() -> void:
				_clip.visible = false
		)


## Re-run after slot count changes while open.
func _retarget_width() -> void:
	call_deferred("_retarget_width_now")


func _retarget_width_now() -> void:
	if not _open:
		return

	var natural := _panel_natural()
	_panel.size = natural

	_clip.position = Vector2(
		MARGIN + BAG_SIZE.x + GAP,
		_bar_center_y() - natural.y / 2.0
	)

	_clip.size.y = natural.y
	_tween_clip(_target_width(), 0.18, false, true)


# ---------- Bag presentation ----------

func _apply_bag_icon() -> void:
	if _bag_tex_closed:
		var tex: Texture2D = (
			_bag_tex_open
			if (_open and _bag_tex_open)
			else _bag_tex_closed
		)

		_bag.icon = null
		_bag.text = ""
		_bag.rotation = 0.0

		_bag_image.texture = tex
		_bag_image.visible = true

		_bag.add_theme_stylebox_override(
			"normal",
			_bag_sb_open if _open else _bag_sb_normal
		)
		_bag.add_theme_stylebox_override("hover", _bag_sb_hover)
		_bag.add_theme_stylebox_override("pressed", _bag_sb_hover)
	else:
		# No art yet — text needs a box to sit in.
		_bag.icon = null
		_bag.text = "Bag"
		_bag.rotation = 0.12 if _open else 0.0

		_bag_image.texture = null
		_bag_image.visible = false

		_bag.add_theme_stylebox_override("normal", _text_sb)
		_bag.add_theme_stylebox_override("hover", _text_sb)
		_bag.add_theme_stylebox_override("pressed", _text_sb)


func _pop_bag() -> void:
	var tw := _bag.create_tween()

	tw.tween_property(
		_bag,
		"scale",
		Vector2(0.92, 0.92),
		0.08
	)

	tw.tween_property(
		_bag,
		"scale",
		Vector2.ONE,
		0.12
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _shake_bag() -> void:
	var base: float = _bag.position.x
	var tw := _bag.create_tween()

	tw.tween_property(_bag, "position:x", base + 6.0, 0.05)
	tw.tween_property(_bag, "position:x", base - 6.0, 0.05)
	tw.tween_property(_bag, "position:x", base + 4.0, 0.05)
	tw.tween_property(_bag, "position:x", base, 0.05)


# ---------- Slots ----------

func _add_slot(item: ItemDef, animate: bool = true) -> void:
	if _slot_by_item.has(item):
		return

	var btn: Control

	if item.icon:
		btn = _make_icon_slot(item)
	else:
		btn = _make_text_slot(item)

	_hbox.add_child(btn)
	_slot_by_item[item] = btn
	_update_glow(item)

	if animate:
		btn.pivot_offset = SLOT_SIZE / 2.0
		btn.scale = Vector2(0.1, 0.1)
		btn.modulate.a = 0.0

		var tw := btn.create_tween()

		tw.tween_property(
			btn,
			"scale",
			Vector2.ONE,
			0.22
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		tw.parallel().tween_property(
			btn,
			"modulate:a",
			1.0,
			0.12
		)


## An icon slot: TextureButton wearing the same glow shader the
## world interactables use.
func _make_icon_slot(item: ItemDef) -> TextureButton:
	var btn := TextureButton.new()

	btn.custom_minimum_size = SLOT_SIZE
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = "%s\n%s" % [
		item.display_name,
		item.description
	]
	btn.texture_normal = item.icon
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED

	var mat := ShaderMaterial.new()
	mat.shader = GLOW_SHADER
	mat.set_shader_parameter("glow_color", GLOW_GOLD)
	mat.set_shader_parameter("hovered", 0.0)

	btn.material = mat
	btn.mouse_entered.connect(_on_slot_hover.bind(item, true))
	btn.mouse_exited.connect(_on_slot_hover.bind(item, false))
	btn.pressed.connect(_on_slot_pressed.bind(item))

	return btn


## Fallback for items with no icon art yet.
func _make_text_slot(item: ItemDef) -> Button:
	var btn := Button.new()

	btn.custom_minimum_size = SLOT_SIZE
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = "%s\n%s" % [
		item.display_name,
		item.description
	]
	btn.text = item.display_name

	btn.add_theme_stylebox_override("normal", _text_sb)
	btn.add_theme_stylebox_override("hover", _text_sb)
	btn.add_theme_stylebox_override("pressed", _text_sb)

	btn.mouse_entered.connect(_on_slot_hover.bind(item, true))
	btn.mouse_exited.connect(_on_slot_hover.bind(item, false))
	btn.pressed.connect(_on_slot_pressed.bind(item))

	return btn


## Hover tracking only — the glow itself is decided by _update_glow.
func _on_slot_hover(item: ItemDef, entered: bool) -> void:
	if entered:
		if not _hovered_items.has(item):
			_hovered_items.append(item)
	else:
		_hovered_items.erase(item)

	_update_glow(item)


## Glow target = selected OR hovered.
## Selection pins the glow on; hover alone still glows unselected items.
func _update_glow(item: ItemDef) -> void:
	var btn: Control = _slot_by_item.get(item)

	if btn == null:
		return

	var on: bool = (
		Inventory.selected_item == item
		or _hovered_items.has(item)
	)

	var tw: Tween = _hover_tweens.get(item)

	if tw and tw.is_valid():
		tw.kill()

	if btn.material is ShaderMaterial:
		# Icon slot: fade the gold outline through the shader uniform.
		var mat: ShaderMaterial = btn.material
		var from_v: Variant = mat.get_shader_parameter("hovered")
		var from: float = from_v if from_v is float else 0.0
		var target: float = 1.0 if on else 0.0

		if absf(target - from) < 0.001:
			return

		tw = btn.create_tween()

		tw.tween_method(
			func(v: float) -> void:
				mat.set_shader_parameter("hovered", v),
			from,
			target,
			0.15
		)
	else:
		# Text fallback: gold tint stands in for the glow.
		var target_color := (
			SELECTED_TINT if on else Color.WHITE
		)

		if btn.modulate.is_equal_approx(target_color):
			return

		tw = btn.create_tween()
		tw.tween_property(
			btn,
			"modulate",
			target_color,
			0.15
		)

	_hover_tweens[item] = tw


func _on_slot_pressed(item: ItemDef) -> void:
	if Inventory.selected_item == item:
		Inventory.deselect_item()
	else:
		Inventory.select_item(item)


# ---------- Inventory signals ----------

func _on_item_added(item: ItemDef) -> void:
	_add_slot(item)

	if item.id == CHEESE_ID and _should_show_bag_hint():
		_start_bag_hint()

	if _open:
		_retarget_width()
	else:
		_pop_bag()


func _on_item_removed(item: ItemDef) -> void:
	var btn: Control = _slot_by_item.get(item)

	if btn:
		btn.queue_free()
		_slot_by_item.erase(item)
		_hover_tweens.erase(item)
		_hovered_items.erase(item)

	if Inventory.items.is_empty():
		_set_open(false)
	elif _open:
		_retarget_width()


func _on_selection_changed(_item: ItemDef) -> void:
	for item in _slot_by_item:
		_update_glow(item)


# ---------- Styling ----------

func _make_styleboxes() -> void:
	# Bag button — chromeless tints only.
	_bag_sb_normal = _bag_sb(Color(0.0, 0.0, 0.0, 0.0))
	_bag_sb_hover = _bag_sb(Color(0.0, 0.0, 0.0, 0.25))
	_bag_sb_open = _bag_sb(Color(1.0, 0.84, 0.31, 0.18))


func _bag_sb(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(16)
	return sb
