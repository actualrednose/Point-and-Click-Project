extends Node
## Session-level room state persistence. Rooms reload fresh on every
## transition — this remembers what changed: items taken, flags set
## (unlocked doors, etc). Lives for the session only: F5 = fresh
## world. A future save system would serialize these two dicts.

var _flags := {}  # "room_path/node_name" -> { String: Variant }
var _taken := {}  # "room_path/node_name" -> true

## Stable identity: the scene the object was PLACED in (its .owner)
## plus the node's name. Renaming rooms or objects changes the key —
## rename before players care, not after.
func object_key(obj: Node) -> String:
	var room_path := ""
	if obj.owner and obj.owner.scene_file_path != "":
		room_path = obj.owner.scene_file_path
	return room_path + "/" + obj.name

func mark_taken(obj: Node) -> void:
	_taken[object_key(obj)] = true

func is_taken(obj: Node) -> bool:
	return _taken.has(object_key(obj))

func set_flag(obj: Node, flag: String, value: Variant) -> void:
	var key := object_key(obj)
	if not _flags.has(key):
		_flags[key] = {}
	_flags[key][flag] = value

func get_flag(obj: Node, flag: String, default: Variant = null) -> Variant:
	var key := object_key(obj)
	if _flags.has(key) and _flags[key].has(flag):
		return _flags[key][flag]
	return default
