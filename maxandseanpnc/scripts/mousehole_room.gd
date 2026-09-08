extends Node2D

const SHRINK_SCALE := 0.35

func _ready() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return

	player.scale = Vector2.ONE * SHRINK_SCALE
