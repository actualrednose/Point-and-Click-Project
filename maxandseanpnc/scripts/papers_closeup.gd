extends CanvasLayer

@onready var root: Control = $Root
@onready var board: Control = $Root/Board
@onready var paper: TextureRect = $Root/Board/Paper

var _closing := false

func _ready() -> void:
	layer = 20

	var backdrop := get_node_or_null("Root/Backdrop") as Control
	if backdrop != null:
		backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		backdrop.gui_input.connect(_on_backdrop_input)

	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	root.modulate.a = 0.0
	board.scale = Vector2(0.92, 0.92)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(root, "modulate:a", 1.0, 0.15)
	tween.tween_property(
		board,
		"scale",
		Vector2.ONE,
		0.15
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_backdrop_input(event: InputEvent) -> void:
	if _closing:
		return

	if event.is_action_pressed("click"):
		_close()

func _close() -> void:
	if _closing:
		return
	_closing = true
	var tween := create_tween()
	tween.tween_property(root, "modulate:a", 0.0, 0.12)
	await tween.finished

	queue_free()
