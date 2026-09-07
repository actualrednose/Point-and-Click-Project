extends "res://interactable.gd"
## A simple always-open exit: a doorway, gap, staircase. Clicking it
## in range walks you through. From far away it's just lookable.
## Rooms link by path string — see door.gd for why.

@export_group("Exit")
## The .tscn to travel to. Pick via the file picker in the Inspector.
@export_file("*.tscn") var target_room_path: String = ""
## Name of the Marker2D in the target room to appear at.
@export var spawn_name: String = ""

func interact() -> void:
	if target_room_path.is_empty():
		super()  # No target configured — behaves like a plain object.
		return
	RoomManager.goto_room(target_room_path, spawn_name)
