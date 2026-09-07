extends Node
## Room transitions with a fade. Usage from any object script:
##   RoomManager.goto_room("res://scenes/room_corridor.tscn", "SpawnFromCellar")
## or pass a PackedScene. IMPORTANT: call it and return immediately —
## never touch the calling node afterwards (its room is about to die).

var _fade_rect: ColorRect
var _busy := false

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100  # Above everything, including the inventory.
	add_child(layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade_rect)

func goto_room(target: Variant, spawn_name: String) -> void:
	if _busy:
		return  # Double-clicks during a fade transition once.
	_busy = true
	var path: String = target if target is String \
		else (target as PackedScene).resource_path

	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, 0.3)
	await tw.finished

	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame  # Let the new room fully arrive.

	var scene := get_tree().current_scene
	if scene:
		var player := get_tree().get_first_node_in_group("player")
		var spawn := _find_by_name(scene, spawn_name)
		if player and spawn:
			(player as Node2D).global_position = (spawn as Node2D).global_position

	var tw2 := create_tween()
	tw2.tween_property(_fade_rect, "color:a", 0.0, 0.3)
	await tw2.finished
	_busy = false

func _find_by_name(parent: Node, node_name: String) -> Node:
	if parent.name == node_name:
		return parent
	for child in parent.get_children():
		var found := _find_by_name(child, node_name)
		if found:
			return found
	return null
