extends "res://interactable.gd"

@export var closeup_scene: PackedScene

var closeup_open := false

func interact() -> void:
	if closeup_open:
		return
	if closeup_scene == null:
		return
	var closeup := closeup_scene.instantiate()
	get_tree().current_scene.add_child(closeup)
	closeup_open = true
	closeup.tree_exited.connect(_on_closeup_closed)

func _on_closeup_closed() -> void:
	closeup_open = false
