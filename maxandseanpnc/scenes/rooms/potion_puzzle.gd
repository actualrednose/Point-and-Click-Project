extends Node2D
## Potion puzzle — the third lab beat. Conductor node: place as a child
## of the lab room (like GurneyPuzzle / KeyTheft).
##
## Owns ALL state and logic: what's in the cup, whether the blue flask
## has been refilled, the mixing table, inventory, and the drink effects
## (grow / stretch / shrink). flask_closeup.gd is the dumb UI;
## flask_table.gd and mousehole.gd are the room-side interactables that
## hand control here.
##
## Flow:
##   click the flasks      -> LOCKED until the mouse steals the key:
##                            "No time for that, I gotta go find the
##                            Master." (no sequence break before then)
##   click the flasks      -> also closed while CARRYING a mixture:
##                            "I've already got a mixture." (one at a
##                            time — drink it, then brew again)
##   click the flasks      -> open_closeup()  (first-person view)
##   flask, then cup       -> pour; second color -> mixed potion -> inventory
##   use a potion ON THE MOUSEHOLE -> drink it THERE; effects play on
##                            the player (green shrinks & climbs in)
##   click the hole while small -> climb in -> next room (or placeholder)
##
## Persistence (RoomState keys off this node = "lab.tscn/PotionPuzzle"):
##   "blue_refilled" — the vial was poured into the blue flask
##   "small"         — the player is currently shrunk
## The sequence gate stores nothing itself: it READS KeyTheft's own
## "stolen" flag through the node reference (same session store, so
## the flag name is guaranteed to match on both sides).

@export var closeup_scene: PackedScene
@export_group("Sequence gate")
## Drag lab.tscn's KeyTheft node here. Until the mouse snatches the key
## (KeyTheft sets its "stolen" flag at the snatch), the vials refuse to
## open. An EMPTY export reads as locked and pushes a warning into the
## Output panel — fail loud, not silent.
@export var key_theft: Node2D
## Refusal line (player speech) while the vials are locked.
@export var locked_line := "No time for that, I gotta go find the Master."
@export_group("Mixture limit")
## Refusal line (player speech) while a finished mixture is already
## in the inventory — the table brews one mixture at a time.
@export var mixture_line := "I've already got a mixture."
@export_group("Potions (drag the .tres files in)")
@export var orange_potion: ItemDef
@export var purple_potion: ItemDef
@export var green_potion: ItemDef
@export_group("Effects")
## Target scale when grown (absolute — head should reach the ceiling).
@export var grow_scale := 3.0
## SIDEWAYS stretch MULTIPLIER (relative — works from any size).
@export var stretch_scale := 2.2
## Target scale when shrunk (absolute — small enough for the hole).
@export var shrink_scale := 0.35
@export var grow_time := 0.45
@export var stretch_time := 0.4
@export var shrink_time := 0.5
@export var revert_time := 0.55
## Distance from the player's ORIGIN down to its FEET. The player's
## origin sits mid-body, so raw scaling would sink the feet into the
## floor — every scale change compensates position.y with this value
## so the feet stay planted. Calibrate: giant's feet sinking -> raise;
## floating above the floor -> lower.
@export var player_feet_offset := 105.0
@export_group("Hole exit")
## Where the mousehole leads once the tiny player climbs in. Leave
## empty until that room exists — the player then peeks in, stays tiny.
@export_file("*.tscn") var next_room_path: String = ""
@export var spawn_name: String = ""
@export var enter_walk_time := 0.8
## Seconds the brewed potion lingers in the cup before auto-closing.
@export var mix_close_delay := 1.6

const FALLBACK_CLOSEUP := "res://scenes/flask_closeup.tscn"
const FLOATING_TEXT := preload("res://scenes/floating_text.tscn")
## Mixed result by sorted color pair.
const MIX_RESULTS := {
	"blue+red": "purple",
	"blue+yellow": "green",
	"red+yellow": "orange",
}

var _closeup: Node
var _cup_contents := ""  # "", "red", "yellow", "blue" (mixed potions leave immediately)
var _effect_busy := false
var _entering := false
var _auto_close_tw: Tween
var _scale_from := Vector2.ONE
var _pre_effect_scale := Vector2.ONE
var _feet_y := 0.0

func _ready() -> void:
	if player_is_small():
		# Deferred: the player's _ready must run first (it joins the
		# "player" group); also survives node order in the scene tree.
		_apply_small_scale.call_deferred()

# ---------------- the close-up ----------------

func open_closeup() -> void:
	if not vials_unlocked():
		refuse_vials()
		return
	if has_mixture():
		refuse_mixture()
		return
	if is_instance_valid(_closeup):
		return  # already open
	if closeup_scene == null:
		if ResourceLoader.exists(FALLBACK_CLOSEUP):
			closeup_scene = load(FALLBACK_CLOSEUP)
		else:
			push_warning("PotionPuzzle: closeup_scene not wired and %s doesn't exist." % FALLBACK_CLOSEUP)
			return
	_closeup = closeup_scene.instantiate()
	get_tree().current_scene.add_child(_closeup)
	_closeup.pour_requested.connect(_on_pour_requested)
	_closeup.flask_clicked.connect(_on_flask_clicked)
	_closeup.close_requested.connect(_on_closeup_closed)
	_closeup.setup_state(blue_refilled(), _cup_contents)
	_clear_stale_cursor()

# ---------------- sequence gate ----------------

## True once the mouse has stolen the key. Reads KeyTheft's own
## "stolen" flag through the exported node reference, so the RoomState
## key is identical on both sides. Unwired export = locked (loud).
func vials_unlocked() -> bool:
	if key_theft == null:
		push_warning("PotionPuzzle: key_theft export is empty — the vials stay locked. Drag lab.tscn's KeyTheft node in.")
		return false
	return RoomState.get_flag(key_theft, "stolen", false)

## The locked refusal, spoken BY THE PLAYER (anchored over their head,
## not over the table). Shared by open_closeup() and flask_table.gd's
## item-use path so the line exists in exactly one place.
func refuse_vials() -> void:
	_say(locked_line, _player_anchor())

# ---------------- one-mixture gate ----------------

## True while the player carries any finished mixture — the mixing
## table brews one at a time. Reads the exported ItemDefs, so unwired
## .tres exports read as "no mixture" (never a false lock).
func has_mixture() -> bool:
	for pdef in [orange_potion, purple_potion, green_potion]:
		if pdef != null and Inventory.has_item(pdef.id):
			return true
	return false

## The one-mixture refusal, spoken BY THE PLAYER. Used by
## open_closeup() and flask_table.gd's blue-vial path, so the line
## exists in exactly one place.
func refuse_mixture() -> void:
	_say(mixture_line, _player_anchor())

func blue_refilled() -> bool:
	return RoomState.get_flag(self, "blue_refilled", false)

## An EMPTY flask was clicked. Only blue starts empty; pouring the
## replacement vial in is the puzzle's gating step.
func _on_flask_clicked(color: String) -> void:
	if not is_instance_valid(_closeup) or color != "blue" or blue_refilled():
		return
	var vial := _find_item(&"blue_vial")
	if vial == null:
		_closeup.say("The blue flask is bone dry. I'd need a replacement vial...")
		return
	Inventory.remove_item(vial)  # auto-deselects if somehow held
	RoomState.set_flag(self, "blue_refilled", true)
	_closeup.set_flask_full("blue", true)
	_closeup.say("You tip the whole vial in. The blue flask is full again.")

func _on_pour_requested(color: String) -> void:
	if not is_instance_valid(_closeup):
		return
	_kill_auto_close()  # a fresh pour cancels any pending auto-close
	if _cup_contents.is_empty():
		_cup_contents = color
		_closeup.set_cup(color)
		_closeup.say("The cup fills with %s liquid." % color)
		return
	if _cup_contents == color:
		_closeup.say("The cup is already full of %s." % color)
		return
	_mix(color)

func _mix(second: String) -> void:
	var pair := [_cup_contents, second]
	pair.sort()
	var result: String = MIX_RESULTS.get(pair[0] + "+" + pair[1], "")
	var def: ItemDef = null
	match result:
		"orange":
			def = orange_potion
		"purple":
			def = purple_potion
		"green":
			def = green_potion
	if result.is_empty() or def == null:
		push_warning("PotionPuzzle: the %s potion ItemDef isn't assigned — drag its .tres into the exports." % [result if not result.is_empty() else "mixed"])
		_cup_contents = ""
		_closeup.set_cup("")
		_closeup.say("...the mixture just fizzles out.")
		return
	if Inventory.has_item(def.id):
		_closeup.say("I already have a %s potion." % result)
		return
	Inventory.add_item(def)
	_cup_contents = ""
	_closeup.set_cup(result)  # display-only: cup shows the brewed color as we leave
	_closeup.say("*fizz!* A %s potion. Into the pocket." % result)
	_kill_auto_close()
	_auto_close_tw = create_tween()
	_auto_close_tw.tween_interval(mix_close_delay)
	_auto_close_tw.tween_callback(_close_after_mix)

func _close_after_mix() -> void:
	_auto_close_tw = null
	if is_instance_valid(_closeup):
		_closeup.close()

func _on_closeup_closed() -> void:
	_closeup = null
	_clear_stale_cursor()

func _kill_auto_close() -> void:
	if _auto_close_tw != null and _auto_close_tw.is_valid():
		_auto_close_tw.kill()
	_auto_close_tw = null

func _clear_stale_cursor() -> void:
	## A stale world hover would pin the cursor as EYE/HAND behind the
	## overlay. Needs cursor_manager.gd's clear_hover() (added for this).
	if CursorManager.has_method("clear_hover"):
		CursorManager.clear_hover()

# ---------------- drinking ----------------

## Called by mousehole.gd when the player uses a potion ON THE HOLE.
## Orange / purple play their (placeholder) gags on the player; green
## normally arrives via drink_and_enter() — drink, shrink, climb in,
## one move. Nothing drinks at the flasks table anymore.
func drink_potion(item: ItemDef) -> void:
	if _effect_busy or _entering:
		_say("Maybe let my body finish the last experiment first...", _player_anchor())
		return
	match item.id:
		&"orange_potion":
			_effect_grow(item)
		&"purple_potion":
			_effect_stretch(item)
		&"green_potion":
			_effect_shrink(item)

func _effect_grow(item: ItemDef) -> void:
	var p := _get_player()
	if p == null:
		return
	_effect_busy = true
	_pre_effect_scale = p.scale
	Inventory.remove_item(item)
	_say("*glug*", _player_anchor())
	var tw := create_tween()
	_tween_scale(tw, Vector2.ONE * grow_scale, grow_time,
			Tween.TRANS_QUINT, Tween.EASE_OUT)
	tw.tween_callback(_grow_bonk)
	tw.tween_interval(0.7)
	_tween_scale(tw, _pre_effect_scale, revert_time,
			Tween.TRANS_QUAD, Tween.EASE_IN)
	tw.tween_callback(_effect_done)

func _grow_bonk() -> void:
	_say("*DONK!* — OW! ...the ceiling won that round.", _player_anchor())

func _effect_stretch(item: ItemDef) -> void:
	var p := _get_player()
	if p == null:
		return
	_effect_busy = true
	_pre_effect_scale = p.scale
	Inventory.remove_item(item)
	_say("*glug*", _player_anchor())
	# ---- PLACEHOLDER VISUAL — swap point for the custom art ----------
	# Sideways scale tween standing in for the real thing. When the
	# custom stretch sprite/animation exists, replace ONLY the two
	# lines below (target + the _tween_scale call) with the animation
	# trigger — keep the scaffolding above and the comment/revert
	# chain after it. (If the custom stretch should PERSIST instead
	# of reverting, delete the revert chain — but keep a call that
	# clears _effect_busy somewhere, like _effect_done.)
	# ------------------------------------------------------------------
	var target := Vector2(p.scale.x * stretch_scale, p.scale.y)
	var tw := create_tween()
	_tween_scale(tw, target, stretch_time,
			Tween.TRANS_QUINT, Tween.EASE_OUT)
	# ---- end placeholder visual --------------------------------------
	tw.tween_callback(_stretch_comment)
	tw.tween_interval(0.9)
	_tween_scale(tw, _pre_effect_scale, revert_time,
			Tween.TRANS_QUAD, Tween.EASE_IN)
	tw.tween_callback(_effect_done)

func _stretch_comment() -> void:
	_say("I'm as wide as a barn door — and about as useful.", _player_anchor())

func _effect_shrink(item: ItemDef) -> void:
	var p := _get_player()
	if p == null:
		return
	if player_is_small():
		_say("I'm already tiny.", _player_anchor())
		return  # potion stays in the bag — not wasted
	_effect_busy = true
	Inventory.remove_item(item)
	_say("*glug*", _player_anchor())
	var tw := create_tween()
	_tween_scale(tw, Vector2.ONE * shrink_scale, shrink_time,
			Tween.TRANS_QUINT, Tween.EASE_OUT)
	tw.tween_callback(_shrink_arrived)

func _shrink_arrived() -> void:
	RoomState.set_flag(self, "small", true)
	_effect_busy = false
	_say("Whoa — everything's HUGE. That mousehole looks door-sized now.", _player_anchor())

func _effect_done() -> void:
	_effect_busy = false

# ---------------- the hole ----------------

## Called by mousehole.gd: a SMALL player clicked the hole.
func enter_hole(hole: Node2D) -> void:
	if _entering or _effect_busy:
		return
	var p := _get_player()
	if p == null or hole == null:
		return
	_entering = true
	if p.has_method("set_facing"):
		p.set_facing(1 if hole.global_position.x >= p.global_position.x else -1)
	_say("(Here goes nothing...)", hole.global_position - Vector2(0.0, 60.0))
	# Lock walking for the walk-in. NOT set_restrained — that's reserved
	# for the gurney lying pose and would flip the art. Zero move_speed
	# is the invisible lock.
	var saved_speed := float(p.get("move_speed"))
	p.set("move_speed", 0.0)
	var target: Vector2 = hole.global_position + Vector2(0.0, 12.0)
	var tw := create_tween()
	tw.tween_property(p, "global_position", target, enter_walk_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(p, "modulate:a", 0.0, enter_walk_time)
	tw.tween_callback(_on_reached_hole.bind(p, saved_speed))

func _on_reached_hole(player: Node2D, saved_speed: float) -> void:
	player.set("move_speed", saved_speed)
	if not next_room_path.is_empty():
		RoomManager.goto_room(next_room_path, spawn_name)
		return  # this room dies here — touch nothing afterwards
	# No next room yet: peek, fade back in, stay tiny at the hole mouth.
	_say("(It's pitch dark in there... the next room hasn't been built yet.)",
			player.global_position - Vector2(0.0, 80.0))
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(player, "modulate:a", 1.0, 0.3)
	tw.tween_callback(_exit_reset)

func _exit_reset() -> void:
	_entering = false

## Called by mousehole.gd: the GREEN potion was used ON the hole.
func drink_and_enter(hole: Node2D, item: ItemDef) -> void:
	if _entering or _effect_busy:
		return
	var p := _get_player()
	if p == null or hole == null or item.id != &"green_potion":
		return
	if player_is_small():
		enter_hole(hole)  # already tiny — straight to the climb (potion kept)
		return
	_effect_busy = true
	Inventory.remove_item(item)
	_say("*glug*", _player_anchor())
	var tw := create_tween()
	_tween_scale(tw, Vector2.ONE * shrink_scale, shrink_time,
			Tween.TRANS_QUINT, Tween.EASE_OUT)
	tw.tween_callback(_shrink_for_hole)
	tw.tween_interval(0.6)
	tw.tween_callback(_enter_hole_now.bind(hole))

func _shrink_for_hole() -> void:
	RoomState.set_flag(self, "small", true)
	_effect_busy = false
	_say("Everything's HUGE... and that hole looks door-sized.", _player_anchor())

func _enter_hole_now(hole: Node2D) -> void:
	enter_hole(hole)

# ---------------- player helpers ----------------

func player_is_small() -> bool:
	return RoomState.get_flag(self, "small", false)

func _get_player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D

## Text anchor: above the player's head, whatever the current scale.
func _player_anchor() -> Vector2:
	var p := _get_player()
	if p == null:
		return global_position
	return p.global_position + Vector2(0.0, -110.0 * p.scale.y - 60.0)

## Appends a feet-preserving scale step to a tween chain. The player's
## origin sits mid-body, so raw scaling would sink/lift the feet —
## position.y is compensated every frame to keep them planted.
func _tween_scale(tw: Tween, target: Vector2, time: float,
		trans: Tween.TransitionType, ease: Tween.EaseType) -> void:
	var p := _get_player()
	if p == null:
		return
	_scale_from = p.scale
	_feet_y = p.global_position.y + player_feet_offset * p.scale.y
	tw.tween_method(_set_scaled.bind(_scale_from, target), 0.0, 1.0, time) \
			.set_trans(trans).set_ease(ease)

func _set_scaled(t: float, from: Vector2, to: Vector2) -> void:
	var p := _get_player()
	if p == null:
		return
	var s := from.lerp(to, t)
	p.scale = s
	p.global_position.y = _feet_y - player_feet_offset * s.y

func _apply_small_scale() -> void:
	var p := _get_player()
	if p == null:
		return
	_feet_y = p.global_position.y + player_feet_offset * p.scale.y
	_set_scaled(1.0, p.scale, Vector2.ONE * shrink_scale)

# ---------------- helpers ----------------

func _find_item(id: StringName) -> ItemDef:
	for i in Inventory.items:
		if i.id == id:
			return i
	return null

func _say(what: String, at: Vector2) -> void:
	if what.is_empty():
		return
	var line := FLOATING_TEXT.instantiate()
	get_tree().current_scene.add_child(line)
	line.setup(what, at)
