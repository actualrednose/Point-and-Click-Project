extends "res://interactable.gd"
## The flasks object in the lab. LOCKED until the mouse steals the key,
## and closed again while the player CARRIES a mixture (both gates live
## inside PotionPuzzle — one place, every entry path). A plain click
## opens the first-person close-up. Potions are NOT drunk here anymore:
## mixtures get used out in the room — on the mousehole, for now.

@export var puzzle: Node2D  # drag the PotionPuzzle node here

@export_group("Lines")
## Shown when a finished MIXTURE is used here (they're drunk at the
## mousehole now, not at the table they were mixed on).
@export var potion_redirect_text := "Not here. This needs drinking somewhere it counts — the mousehole, maybe?"
## Shown when the blue vial is used here (unchanged behavior).
@export var vial_hint_text := "I should tip this into the blue flask — up close."

func interact() -> void:
	if puzzle != null and puzzle.has_method("open_closeup"):
		puzzle.open_closeup()  # the locked/unlocked + mixture gates happen inside
		return
	super()  # unwired: behave like a plain object

func on_use_item(item: ItemDef) -> void:
	if puzzle != null and puzzle.has_method("vials_unlocked"):
		if not puzzle.vials_unlocked():
			# Locked is locked, whatever's in hand (the blue vial counts).
			_face_player_toward()
			puzzle.refuse_vials()
			Inventory.deselect_item()
			return
		match item.id:
			&"orange_potion", &"purple_potion", &"green_potion":
				_face_player_toward()
				show_comment(potion_redirect_text)
				Inventory.deselect_item()
				return
			&"blue_vial":
				_face_player_toward()
				if puzzle.has_method("has_mixture") and puzzle.has_mixture():
					# Station's closed while a mixture's in the pocket —
					# the vial waits its turn (drink the mixture first).
					puzzle.refuse_mixture()
				else:
					show_comment(vial_hint_text)
				Inventory.deselect_item()
				return
	super(item)  # unwired or wrong item: base rejection
