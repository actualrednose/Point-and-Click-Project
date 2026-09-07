extends "res://interactable.gd"
## Cheese on the shelf — a normal pickup, plus one extra beat: when the
## pickup completes, tell the gurney puzzle so it can play the
## head-bonk / falling-cheese choreography.

@export var puzzle: Node2D  # drag the GurneyPuzzle node here

func interact() -> void:
	super()
	# super() ran the pickup branch (pickup_item is assigned on this
	# instance). If the object queued itself for deletion, the cheese
	# made it into the bag — that's our cue.
	if is_queued_for_deletion() and puzzle != null and puzzle.has_method("on_cheese_taken"):
		puzzle.on_cheese_taken()
