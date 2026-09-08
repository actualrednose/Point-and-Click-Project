extends "res://interactable.gd"
## Sleeping mouse — the stolen key's snoring bodyguard.
##
## While it sleeps it BARRICADES the room with TWO walls that agree:
##
##   1. The player's own room limit — player.gd clamps position.x to
##      room_left_limit/room_right_limit every physics frame, so
##      changing a limit IS a wall. No physics, nothing to collide
##      with, and it comes down the instant the limit is restored.
##
##   2. A real StaticBody2D bar the script builds at runtime, just
##      outside the mouse's body. If anything ever goes wrong with the
##      limits (a stale player reference, node-order quirks, script
##      edits), the physics bar still stops the player dead. Belt and
##      suspenders: both sit at the same standoff, so the player never
##      touches the bar unless the limit already failed.
##
## THE WAKE-UP IS BUILT IN. Use the LIT CANDLE on the mouse and:
##      1. The snoring stops and the barricade drops — the player can
##         move immediately.
##      2. The mouse startles (hop + *SQUEAK!!*), panics back and
##         forth for ~panic_time seconds,
##      3. sprints to the room's exit (the mousehole — auto-found,
##         or set hole_x_override) and dives in, shrinking out of
##         sight. Gone.
## An unlit candle gets a snarky line; anything else gets the base
## rejection. The candle is NOT consumed — you keep it.
##
## Persistence is free: "awake" flag + mark_taken, so on room
## re-entry the node frees itself in _ready (base class) and the way
## stays clear for the rest of the session.
##
## The player is only walled once it actually EXISTS. If the room's
## nodes entered the tree in an order where the player isn't in the
## "player" group yet (an editor re-save can shuffle children), the
## script waits a few frames and walls the moment it shows up — and
## says so loudly in the console if it never does.

@export_group("Player block")
## Air kept between the mouse's edge and the player's edge while asleep.
@export var block_margin: float = 24.0
## Thickness of the invisible physics bar. The player moves ~6 px per
## physics frame, so anything over 12 px can't be tunnelled through.
@export var wall_thickness: float = 40.0
## Frames to wait for a player to appear before warning loudly.
@export var player_wait_frames: int = 10

@export_group("Wake-up (lit candle)")
@export var lit_candle_id: StringName = &"lit_candle"
@export var unlit_candle_id: StringName = &"unlit_candle"
## Line for using the UNLIT candle (cold candle, sleeping mouse).
@export var unlit_text: String = "It's asleep, not frozen. A cold candle won't wake it."
## Player line the instant the flame touches the whiskers.
@export var use_text: String = "The flame singes its whiskers!"
@export var squeak_text: String = "*SQUEAK!!*"
@export var flee_text: String = "Eeeeek!"
## Total seconds of panicking back and forth before the sprint.
@export var panic_time: float = 1.0
## Pixels of each back-and-forth lunge while panicking.
@export var panic_amplitude: float = 42.0
## Height of the initial startle hop (px).
@export var panic_hop_height: float = 36.0
## Seconds each panic lunge takes (short = frantic).
@export var panic_step_time: float = 0.11
## Sprint speed toward the hole (px/s). Player walks at 350.
@export var sprint_speed: float = 1500.0
## Mouse stops this far (px) right of the hole before diving in.
@export var dive_standoff: float = 20.0
## Seconds the dive-in (shrinking) takes.
@export var dive_time: float = 0.28
## Scale the mouse shrinks to as it dives into the hole.
@export var dive_scale: float = 0.1
## true if MouseAsleep.png is drawn facing RIGHT — flips the fleeing
## sprite so it runs nose-first. Toggle if it backpedals.
@export var art_faces_right: bool = true
## Global x of the hole to dive into. -1 = auto-find the room's exit
## node (the mousehole). Set only if auto-detection ever misfires.
@export var hole_x_override: float = -1.0

## 0 = not blocking, 1 = wall on the player's right, -1 = wall on
## their left (kept for a future right-side arrival; today spawn and
## the exit back to the lab are both LEFT of the mouse).
var _blocked_side := 0
var _saved_limit := 0.0
var _walled_player: Node2D = null
var _wall: StaticBody2D = null

var _awake := false       # Wake-up has begun (or happened in a past visit).
var _waking := false      # Wake-up sequence is currently playing.
var _home_x := 0.0        # Resting spot — panic lunges pivot around it.
var _home_y := 0.0


func _ready() -> void:
	super()
	if RoomState.is_taken(self) or RoomState.get_flag(self, "awake", false):
		# Already chased off — the base _ready has queued our free.
		return
	_home_x = position.x
	_home_y = position.y
	start_blocking()

# ---------------- the wall ----------------

## Wall the player off. Idempotent, but re-callable: it reads the
## CURRENT collision rect, so after moving the mouse (a wake-up
## shuffle, say) stop_blocking() then start_blocking() re-walls the
## new position.
func start_blocking() -> void:
	if _blocked_side != 0 or _awake:
		return  # Already walled — or awake, no more walls ever.
	var rect := _body_rect()
	if not rect.has_area():
		push_warning("SleepingMouse: no rectangular CollisionShape2D — can't place the wall.")
		return
	var player := _get_room_player()
	if player == null:
		_wait_for_player_and_wall()
		return
	_wall_player_off(player, rect)


## The player wasn't findable yet (node-order quirks, a late spawn, an
## editor re-save) — retry for a few frames before giving up loudly.
func _wait_for_player_and_wall() -> void:
	for i in player_wait_frames:
		await get_tree().process_frame
		if _awake or not is_inside_tree():
			return  # Candle beat us to it — no wall, ever again.
		var player := _get_room_player()
		if player != null:
			_wall_player_off(player, _body_rect())
			return
	push_warning("SleepingMouse: no player found after %d frames — the room is NOT blocked."
			% player_wait_frames)


## Both walls go up here: the player's room limit AND the physics bar.
func _wall_player_off(player: Node2D, rect: Rect2) -> void:
	if _blocked_side != 0 or _awake or not is_inside_tree():
		return
	var half_w := _player_half_width(player)
	var new_limit := 0.0
	if player.global_position.x < rect.get_center().x:
		# Normal arrival: the player is LEFT of the mouse.
		_blocked_side = 1
		_saved_limit = float(player.get("room_right_limit"))
		new_limit = rect.position.x - block_margin - half_w
		player.set("room_right_limit", new_limit)
	else:
		# Arrived on the right (not reachable today — kept safe anyway).
		_blocked_side = -1
		_saved_limit = float(player.get("room_left_limit"))
		new_limit = rect.end.x + block_margin + half_w
		player.set("room_left_limit", new_limit)
	_walled_player = player
	_build_wall(rect)
	print("[SleepingMouse] block ON — side=%d, player=%s, limit %.1f -> %.1f, physics wall up"
			% [_blocked_side, player.name, _saved_limit, new_limit])


## Build the physics bar. It lives as a child of the mouse so it dies
## with the room and follows any editor re-positioning; its position
## goes through to_local() so scaling the mouse instance can't
## displace it.
func _build_wall(rect: Rect2) -> void:
	_free_wall()
	_wall = StaticBody2D.new()
	_wall.name = "BlockWall"
	var bar := RectangleShape2D.new()
	# Tall bar: the mouse's full body height plus generous head-room,
	# so no player pose or scale ever steps over it.
	bar.size = Vector2(wall_thickness, rect.size.y + 600.0)
	var cs := CollisionShape2D.new()
	cs.shape = bar
	_wall.add_child(cs)
	var center_x := 0.0
	if _blocked_side == 1:
		# Bar's LEFT face sits block_margin off the mouse's left edge.
		center_x = rect.position.x - block_margin + wall_thickness / 2.0
	else:
		# Bar's RIGHT face sits block_margin off the mouse's right edge.
		center_x = rect.end.x + block_margin - wall_thickness / 2.0
	_wall.position = to_local(Vector2(center_x, rect.get_center().y))
	add_child(_wall)


## Take both walls down and give the player their old limit back.
func stop_blocking() -> void:
	if _blocked_side == 0:
		return
	# Restore the exact player we walled (it lives and dies with this
	# room, same as us) — not whatever is first in the group right now.
	if _walled_player != null and is_instance_valid(_walled_player):
		if _blocked_side == 1:
			_walled_player.set("room_right_limit", _saved_limit)
		else:
			_walled_player.set("room_left_limit", _saved_limit)
	_blocked_side = 0
	_walled_player = null
	_free_wall()
	print("[SleepingMouse] block OFF — limit restored to %.1f" % _saved_limit)


func is_blocking() -> bool:
	return _blocked_side != 0


func _free_wall() -> void:
	if _wall != null and is_instance_valid(_wall):
		_wall.queue_free()
	_wall = null

# ---------------- the wake-up ----------------

## Item routing: LIT candle = the wake-up; unlit = a snarky line;
## anything else = the base rejection (with its auto line + deselect).
func on_use_item(item: ItemDef) -> void:
	if item.id == lit_candle_id:
		_wake_up()
		return
	if item.id == unlit_candle_id:
		_face_player_toward()
		show_comment(unlit_text)
		Inventory.deselect_item()
		return
	super(item)


## One singed whisker too many. Idempotent — fire and forget.
func _wake_up() -> void:
	if _awake or _waking:
		return
	_waking = true
	_awake = true
	_face_player_toward()
	show_comment(use_text)
	Inventory.deselect_item()  # The candle stays in your pocket.

	# Persist NOW (mid-sequence room exits included): awake stops the
	# block from re-arming, taken frees the node on room re-entry.
	RoomState.set_flag(self, "awake", true)
	RoomState.mark_taken(self)

	# No more clicks, and no hover glow/cursor stuck on a fleeing mouse.
	input_pickable = false
	if _hovered:
		_set_hovered(false)

	# The barricade comes down the moment the whisker singes — the
	# chase is on. (The physics wall is a child of us and dies here too.)
	stop_blocking()
	_stop_zzz()

	_wake_sequence()


func _stop_zzz() -> void:
	var zzz := get_node_or_null("Zzz") as AnimatedSprite2D
	if zzz != null:
		zzz.stop()
		zzz.visible = false


## The whole beat: startle hop -> panic lunges -> sprint -> dive.
## Coroutine — runs on its own; every await is on a node-bound tween,
## so leaving the room mid-beat simply stops it (state is already saved).
func _wake_sequence() -> void:
	# 1. Startle: straight up, then a heavy landing.
	var hop := create_tween()
	hop.tween_property(self, "position:y", _home_y - panic_hop_height, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	hop.tween_property(self, "position:y", _home_y, 0.09).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await hop.finished
	if not is_inside_tree():
		return
	show_comment(squeak_text)

	# 2. Panic: rapid back-and-forth lunges, flipping to face each dash.
	var elapsed := 0.0
	var dir := 1  # Player stands left — first lunge is AWAY from them.
	while elapsed < panic_time:
		var shuffle := create_tween()
		shuffle.tween_property(self, "position:x", _home_x + dir * panic_amplitude, panic_step_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		sprite.flip_h = _faces_travel(dir)
		await shuffle.finished
		if not is_inside_tree():
			return
		elapsed += panic_step_time
		dir = -dir

	# 3. Sprint to the hole mouth (fast start, accelerating scramble).
	var hole := _hole_dive_point()
	var sprint_x: float = hole.x + dive_standoff if hole.x < position.x else hole.x - dive_standoff
	sprite.flip_h = _faces_travel(signf(sprint_x - position.x))
	show_comment(flee_text)
	var sprint := create_tween()
	var dur := maxf(absf(sprint_x - position.x) / sprint_speed, 0.15)
	sprint.tween_property(self, "position:x", sprint_x, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# A running bob on top of the sprint, so it scurries instead of gliding.
	var bob := create_tween().set_loops()
	bob.tween_property(self, "position:y", _home_y - 7.0, 0.09).set_trans(Tween.TRANS_SINE)
	bob.tween_property(self, "position:y", _home_y + 3.0, 0.09).set_trans(Tween.TRANS_SINE)
	await sprint.finished
	bob.kill()
	if not is_inside_tree():
		return

	# 4. Dive into the hole: shrink and slide into the mouth together.
	var dive := create_tween().set_parallel(true)
	dive.tween_property(self, "scale", Vector2.ONE * dive_scale, dive_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	dive.tween_property(self, "global_position", hole, dive_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await dive.finished
	if not is_inside_tree():
		return
	visible = false
	print("[SleepingMouse] fled into the mouse hole — the way is clear.")


## flip_h for travelling in direction dir_x, given the art's rest facing.
func _faces_travel(dir_x: float) -> bool:
	if dir_x == 0.0:
		return sprite.flip_h
	return (dir_x < 0.0) if art_faces_right else (dir_x > 0.0)


## The hole mouth (global) to dive into: the room's exit node — the
## one with "hole" in its name if there are several. hole_x_override
## wins if set. No exit at all? Flee left and vanish there.
func _hole_dive_point() -> Vector2:
	var exit_node := _find_hole_exit()
	if exit_node != null:
		var p := exit_node.global_position
		if hole_x_override >= 0.0:
			p.x = hole_x_override
		return p
	push_warning("SleepingMouse: no exit node found — fleeing left and vanishing.")
	var x: float = hole_x_override if hole_x_override >= 0.0 else position.x - 500.0
	return Vector2(x, position.y - 30.0)


## Room-scan for the hole exit: a direct child of the room root that
## has exit.gd's target_room_path property, "hole"-named preferred.
func _find_hole_exit() -> Node2D:
	var room_root := owner  # Scene root this mouse was placed in.
	if room_root == null:
		return null
	var fallback: Node2D = null
	for child in room_root.get_children():
		if not (child is Node2D):
			continue
		var target = child.get("target_room_path")
		if typeof(target) != TYPE_STRING or (target as String).is_empty():
			continue  # Not a configured exit.
		if "hole" in child.name.to_lower():
			return child
		if fallback == null:
			fallback = child
	return fallback

# ---------------- measuring ----------------

## The player THIS mouse should wall: the one saved in the same room
## scene (same owner). get_first_node_in_group() alone can grab a
## stale player from another scene if two ever coexist; this can't.
## Falls back to the group lookup for simple setups.
func _get_room_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	var room_root := owner  # Scene root this mouse was placed in.
	if room_root != null:
		for p in players:
			if (p as Node).owner == room_root:
				return p
	return players[0] as Node2D

## World rect of the collision box — by construction (the scene), the
## mouse's body. Read live so the wall follows any editor re-position.
func _body_rect() -> Rect2:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null or not (cs.shape is RectangleShape2D):
		push_warning("SleepingMouse: no rectangular CollisionShape2D — can't place the wall.")
		return Rect2()
	var size: Vector2 = cs.shape.size * cs.global_transform.get_scale()
	return Rect2(cs.global_position - size / 2.0, size)


## The player's half width at their CURRENT scale — the wall respects
## both the full-size player and the shrunken one.
func _player_half_width(player: Node2D) -> float:
	var cs := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		return cs.shape.size.x * player.global_transform.get_scale().x / 2.0
	return 50.0
