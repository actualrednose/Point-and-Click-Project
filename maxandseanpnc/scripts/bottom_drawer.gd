extends "res://interactable.gd"
## The bottom drawer beside the gurney. Clicking it the first time
## slides it open and turns up the spare blue vial — straight into the
## inventory; the vial never exists as a world object. After that the
## drawer just hangs open with nothing else inside.
##
## Persistence: a plain RoomState flag ("vial_taken"), NOT
## mark_taken() — the drawer must stay in the room forever, and
## mark_taken is what makes the base class self-free picked-up
## objects on room reload.

@export_group("Vial drawer")
@export var vial_item: ItemDef
@export var found_text: String = "Tucked away at the back — a little vial of blue. Into the pocket."
@export var empty_text: String = "There's nothing else inside."
## look() line once the drawer has been emptied.
@export var open_look_text: String = "The drawer hangs open. Empty now."
## The painted open-drawer art, once it exists. Until then the closed
## art is nudged down by open_offset so the state change is visible.
@export var open_texture: Texture2D
## Placeholder "pulled open" look: how far the drawer front slides
## down when no open art is assigned yet.
@export var open_offset: Vector2 = Vector2(0.0, 14.0)

var _opened := false

func _ready() -> void:
	# Base wires hover/click/glow. Its is_taken() self-free can never
	# trip for this node — we deliberately never mark_taken it.
	super()
	if RoomState.get_flag(self, "vial_taken", false):
		# Room reloaded after the vial was found — restore the look.
		_apply_open()

func interact() -> void:
	_face_player_toward()
	if vial_item == null:
		push_warning("BottomDrawer: vial_item not assigned — drag items/blue_vial.tres into the export.")
		super()  # unwired: behave like a plain closed drawer
		return
	if RoomState.get_flag(self, "vial_taken", false):
		show_comment(empty_text)
		return
	RoomState.set_flag(self, "vial_taken", true)
	_apply_open()
	if Inventory.add_item(vial_item):
		show_comment(found_text)
	else:
		# Already carrying one (e.g. from an older test build of the
		# vial pickup). The drawer still opens; the puzzle stays solvable.
		show_comment("I'm already carrying a vial just like it. The drawer's empty otherwise.")

func _apply_open() -> void:
	if _opened:
		return
	_opened = true
	look_text = open_look_text
	if open_texture != null:
		# Real art swap. The base class rescans the visible pixels when
		# the texture changes, so floating comments re-anchor to the
		# new art automatically.
		sprite.texture = open_texture
	else:
		# Placeholder until the art exists: slide the drawer front down
		# a touch, like it's been pulled out.
		sprite.position += open_offset
