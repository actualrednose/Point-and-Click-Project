extends "res://interactable.gd"
## The mousehole: a tiny exit — and the place mixtures get DRUNK.
## Only a shrunken player fits through. Using a potion here triggers
## its effect: GREEN shrinks & climbs in; ORANGE / PURPLE play their
## (placeholder) gags on the player.

@export var puzzle: Node2D  # drag the PotionPuzzle node here

func interact() -> void:
	if puzzle != null and puzzle.has_method("player_is_small") \
			and puzzle.player_is_small():
		puzzle.enter_hole(self)
		return
	super()  # full-sized (or unwired): the "too small" interact text

func on_use_item(item: ItemDef) -> void:
	if puzzle != null:
		match item.id:
			&"green_potion":
				if puzzle.has_method("drink_and_enter"):
					puzzle.drink_and_enter(self, item)
					return
			&"orange_potion", &"purple_potion":
				if puzzle.has_method("drink_potion"):
					_face_player_toward()
					puzzle.drink_potion(item)
					return
	super(item)  # anything else: base rejection
