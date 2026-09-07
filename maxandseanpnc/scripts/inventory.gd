extends Node
## Global inventory state + selection. Register as autoload "Inventory".

signal item_added(item: ItemDef)
signal item_removed(item: ItemDef)
signal selection_changed(item: ItemDef)  # null = nothing selected

var items: Array[ItemDef] = []
var selected_item: ItemDef = null

func add_item(item: ItemDef) -> bool:
	if item == null or item.id == &"":
		push_warning("Inventory: item has no id — not added.")
		return false
	if has_item(item.id):
		push_warning("Inventory: '%s' already carried." % item.display_name)
		return false
	items.append(item)
	item_added.emit(item)
	# Debug visibility until the Phase 7 UI exists.
	print("[Inventory] added '%s' — %d items" % [item.display_name, items.size()])
	return true

func remove_item(item: ItemDef) -> bool:
	var idx := items.find(item)
	if idx == -1:
		return false
	items.remove_at(idx)
	if selected_item == item:
		deselect_item()  # Never leave a removed item "held".
	item_removed.emit(item)
	return true

func has_item(id: StringName) -> bool:
	for i in items:
		if i.id == id:
			return true
	return false

func select_item(item: ItemDef) -> void:
	if not items.has(item):
		return
	selected_item = item
	selection_changed.emit(item)
	CursorManager.select_item(item.icon)

func deselect_item() -> void:
	if selected_item == null:
		return
	selected_item = null
	selection_changed.emit(null)
	CursorManager.deselect_item()

func _unhandled_input(event: InputEvent) -> void:
	## A click that reached here was consumed by NOTHING — no object,
	## no UI. But if the cursor is over an interactable, the click
	## belongs to that object (its input_event simply hasn't run yet),
	## so it must NOT deselect. Classic point-and-click: only a true
	## empty-space click puts the held item away.
	if event.is_action_pressed("click") and not CursorManager.has_hover():
		deselect_item()
