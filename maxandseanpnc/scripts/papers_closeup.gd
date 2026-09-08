extends CanvasLayer

@onready var root: Control = $Root
@onready var board: Control = $Root/Board
@onready var paper: TextureRect = $Root/Board/Paper

func _ready() -> void:
	layer = 20

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

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var mouse_position: Vector2 = event.position

			if not paper.get_global_rect().has_point(mouse_position):
				get_viewport().set_input_as_handled()
				_close()

func _close() -> void:
	var tween := create_tween()
	tween.tween_property(root, "modulate:a", 0.0, 0.12)
	await tween.finished
	queue_free()
