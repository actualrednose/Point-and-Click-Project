extends CanvasLayer
## First-person close-up of the flasks table. Instantiated at RUNTIME
## by PotionPuzzle.open_closeup() — never place this scene in a room.
##
## Deliberately DUMB UI: it renders whatever state the conductor pushes
## (setup_state / set_flask_full / set_cup) and reports intent upward
## via signals. All game logic — mixing, inventory, effects — lives in
## potion_puzzle.gd.
##
## Placeholders until the painted art exists: every clickable is a plain
## ColorRect. When the close-up art is ready, swap the ColorRects for
## TextureRect / TextureButton nodes with the SAME NAMES — the script
## finds everything by name and it keeps working. (Classic liquid
## trick: paint the cup's liquid shape pure WHITE, put it on CupLiquid,
## and the script's tint colors show through. Same idea works for
## flask liquid sprites later.)

signal pour_requested(color: String)  ## Full flask selected, cup clicked.
signal flask_clicked(color: String)   ## An EMPTY flask was clicked.
signal close_requested                ## Fully faded out and about to free.

const COLORS := {
	"red": Color(0.92, 0.22, 0.22),
	"yellow": Color(0.98, 0.82, 0.25),
	"blue": Color(0.30, 0.45, 0.95),
	"orange": Color(0.95, 0.55, 0.15),
	"purple": Color(0.62, 0.30, 0.80),
	"green": Color(0.35, 0.75, 0.35),
}

const FLOATING_TEXT := preload("res://scenes/floating_text.tscn")

## Which flasks hold liquid. "blue" starts empty until the vial is
## poured in (the conductor pushes the real value at open time).
var _full_flasks := {"red": true, "yellow": true, "blue": false}
var _selected := ""
var _closing := false

var _flasks := {}  # color -> Control
var _root: Control
var _board: Control
var _cup: Control
var _cup_liquid: Control

func _ready() -> void:
	layer = 20  # Above the inventory bag (10), below the room fade (100).
	_root = get_node_or_null("Root") as Control
	_board = get_node_or_null("Root/Board") as Control
	_cup = get_node_or_null("Root/Board/Cup") as Control
	_cup_liquid = get_node_or_null("Root/Board/Cup/CupLiquid") as Control

	_wire_flask("red", "FlaskRed")
	_wire_flask("yellow", "FlaskYellow")
	_wire_flask("blue", "FlaskBlue")

	if _cup != null:
		_cup.mouse_filter = Control.MOUSE_FILTER_STOP
		_cup.gui_input.connect(_on_cup_input)
	else:
		push_warning("FlaskCloseup: Root/Board/Cup missing — the cup won't be clickable.")

	var backdrop := get_node_or_null("Root/Backdrop") as Control
	if backdrop != null:
		backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		backdrop.gui_input.connect(_on_backdrop_input)
	else:
		push_warning("FlaskCloseup: Root/Backdrop missing — clicks leak to the room.")

	var back := get_node_or_null("Root/BackButton") as BaseButton
	if back != null:
		back.focus_mode = Control.FOCUS_NONE
		back.pressed.connect(_request_close)
	else:
		push_warning("FlaskCloseup: Root/BackButton missing — only the backdrop closes.")

	# Filters the scene MUST have for input to route correctly. Done in
	# code so an art swap can never get them wrong:
	#   Root/Board pass clicks through; Panel is an inert click-catcher
	#   (clicking the table art does NOT close the view); CupLiquid
	#   must not steal the cup's clicks.
	if _root != null:
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _board != null:
		_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := get_node_or_null("Root/Board/Panel") as Control
	if panel != null:
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if _cup_liquid != null:
		_cup_liquid.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Pop in.
	if _root != null:
		_root.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(_root, "modulate:a", 1.0, 0.15)
	if _board != null:
		_board.pivot_offset = _board.size / 2.0
		_board.scale = Vector2(0.92, 0.92)
		var tw2 := create_tween()
		tw2.tween_property(_board, "scale", Vector2.ONE, 0.22) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_refresh_all()

# ---------------- input wiring ----------------

func _wire_flask(color: String, node_name: String) -> void:
	var c := get_node_or_null("Root/Board/" + node_name) as Control
	if c == null:
		push_warning("FlaskCloseup: Root/Board/%s missing — that flask won't be clickable." % node_name)
		return
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.gui_input.connect(_on_flask_input.bind(color))
	_flasks[color] = c

func _on_flask_input(event: InputEvent, color: String) -> void:
	if _closing or not event.is_action_pressed("click"):
		return
	if not _full_flasks.get(color, false):
		flask_clicked.emit(color)  # empty — the conductor decides (vial / text)
		return
	# Full flask: pick it up, or put it back down.
	_selected = "" if _selected == color else color
	_refresh_selection()

func _on_cup_input(event: InputEvent) -> void:
	if _closing or not event.is_action_pressed("click"):
		return
	if _selected.is_empty():
		say("I should pick up a flask first.")
		return
	var color := _selected
	_selected = ""
	_refresh_selection()
	pour_requested.emit(color)

func _on_backdrop_input(event: InputEvent) -> void:
	if not _closing and event.is_action_pressed("click"):
		_request_close()

# ---------------- open / close ----------------

## Public: the conductor calls this (e.g. after a mix resolves).
func close() -> void:
	_request_close()

func _request_close() -> void:
	if _closing:
		return
	_closing = true
	_selected = ""
	_refresh_selection()
	if _root == null:
		_finish_close()
		return
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.15)
	tw.tween_callback(_finish_close)

func _finish_close() -> void:
	close_requested.emit()
	queue_free()

# ---------------- state pushed by the conductor ----------------

## Called once at open with the saved world state.
func setup_state(blue_full: bool, cup_color: String) -> void:
	_full_flasks["blue"] = blue_full
	_refresh_all()
	set_cup(cup_color)

func set_flask_full(color: String, full: bool) -> void:
	_full_flasks[color] = full
	_refresh_flask_visual(color)

func set_cup(color: String) -> void:
	## "" = empty cup; otherwise the (mixed) color shown in the cup.
	if _cup_liquid == null:
		return
	if color.is_empty():
		_cup_liquid.visible = false
	else:
		_cup_liquid.visible = true
		_cup_liquid.modulate = COLORS.get(color, Color.WHITE)

## Commentary anchored above the cup, inside this layer.
func say(text: String) -> void:
	if text.is_empty():
		return
	var line := FLOATING_TEXT.instantiate()
	add_child(line)
	var anchor := Vector2(960.0, 600.0)
	if _cup != null:
		anchor = _cup.get_global_rect().get_center() - Vector2(0.0, 90.0)
	line.setup(text, anchor)

# ---------------- rendering ----------------

func _refresh_all() -> void:
	for color in _flasks:
		_refresh_flask_visual(color)
	_refresh_selection()

func _refresh_flask_visual(color: String) -> void:
	var c := _flasks.get(color) as Control
	if c == null:
		return
	# Empty flasks dim to a dusty gray; full flasks sit at full brightness.
	c.modulate = Color(0.45, 0.45, 0.5) \
			if not _full_flasks.get(color, false) else Color.WHITE

func _refresh_selection() -> void:
	for color in _flasks:
		var c := _flasks[color] as Control
		c.pivot_offset = c.size / 2.0
		c.scale = Vector2(1.08, 1.08) if color == _selected else Vector2.ONE
