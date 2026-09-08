extends "res://interactable.gd"
## The flasks object in the lab. LOCKED until the mouse steals the key,
## and closed again while the player CARRIES a mixture (both gates live
## inside PotionPuzzle — one place, every entry path). A plain click
## opens the first-person close-up. Potions are NOT drunk here anymore:
## mixtures get used out in the room — on the mousehole, for now.
##
## Room-scale art: the Sprite's texture swaps to refilled_texture
## the moment the blue vial tops the blue flask up (inside the
## close-up), so the room view shows the refill. Two paths, same
## result: the blue_flask_refilled signal (live, self-connected —
## no editor wiring) and a RoomState flag re-check in _ready()
## (re-entering the lab later still shows the full flask). Hover
## glow and the comment anchor follow the new texture
## automatically — the base class re-scans the visible pixels when
## the texture changes.

@export var puzzle: Node2D  # drag the PotionPuzzle node here

@export_group("Lines")
## Shown when a finished MIXTURE is used here (they're drunk at the
## mousehole now, not at the table they were mixed on).
@export var potion_redirect_text := "I don't think this is useful here."
## Shown when the blue vial is used here (unchanged behavior).
@export var vial_hint_text := "I should tip this into the blue flask — up close."

@export_group("Blue refill art")
## The vials art with the blue flask FULL — room scale, same framing
## and canvas size as the default art (Vials1.png). If one of your
## other Vials PNGs is the refilled variant, drag that one in. Left
## empty, the swap is a loud no-op: a warning in the Output panel
## every time it should have fired.
@export var refilled_texture: Texture2D

func _ready() -> void:
	super()  # base setup first: taken-check, group, hover, glow material
	# Self-connecting listener: live as soon as BOTH scripts are the
	# new versions. An old conductor without the signal just fails
	# the has_signal check — the RoomState sync below still covers
	# room re-entries, so mixed old/new files can't crash.
	if puzzle != null and puzzle.has_signal("blue_flask_refilled"):
		puzzle.blue_flask_refilled.connect(_on_blue_flask_refilled)
	_sync_refill_art()

# ---------------- room-scale refill art ----------------

## Signal path — the vial went in while the close-up was open; the
## room sits behind the overlay, so the swap is simply waiting for
## it to lift.
func _on_blue_flask_refilled() -> void:
	_apply_refill_art()

## Flag path — covers re-entering the lab AFTER a refill (the scene
## reloads, _ready runs again, RoomState still remembers). Reads
## through the SAME puzzle node the exports already point at, so
## the RoomState key matches the one potion_puzzle.gd writes to.
func _sync_refill_art() -> void:
	if puzzle == null:
		return
	if RoomState.get_flag(puzzle, "blue_refilled", false):
		_apply_refill_art()

## One-way swap — a refilled flask never drains again. Idempotent,
## so the signal path and the flag path can both arrive without
## redoing work.
func _apply_refill_art() -> void:
	if refilled_texture == null:
		push_warning("FlaskTable: refilled_texture export is empty — the blue refill won't show on the room-scale vials. Drag the full-flask art in.")
		return
	if sprite == null:
		push_warning("FlaskTable: no Sprite child on this node — the art swap needs the Sprite node from interactable.tscn.")
		return
	if sprite.texture == refilled_texture:
		return  # already showing the full flask
	sprite.texture = refilled_texture

func interact() -> void:
	if puzzle != null and puzzle.has_method("open_closeup"):
		puzzle.open_closeup()  # the locked/unlocked gate check happens inside
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
