extends "res://interactable.gd"
## The key on the table. Reaching for it goes wrong: the knock-off and
## mouse theft are orchestrated by the KeyTheft node; this override just
## hands the click over. Persistence needs NOTHING here — the conductor
## mark_takens the key at the snatch, and the base class already
## self-frees taken objects on room reload.

@export var puzzle: Node2D  # drag the KeyTheft node here


func interact() -> void:
	if puzzle != null and puzzle.has_method("try_take_key"):
		puzzle.try_take_key(self)
		return
	super()  # unwired: behave like a normal object
