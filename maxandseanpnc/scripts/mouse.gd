extends Node2D
## Mouse NPC — runs back and forth across the room, pausing to sniff.
## The gurney puzzle can command it: go_to() / do_jump() / do_chew().
##
## Signals:
##   arrived				 -> a go_to() run finished
##   action_finished(action) -> a jump or chew finished ("jump" / "chew")
##
## Needs an AnimatedSprite2D child with animations named exactly:
##   "run", "sniff", "jump", "chew"
## (single placeholder frames are fine — the motion works regardless;
## missing names are skipped with no error).

signal arrived
signal action_finished(action: String)

enum State { RUN, SNIFF, GO_TO, JUMP, CHEW, IDLE }

@export var animated_sprite: AnimatedSprite2D
## true if the mouse art is drawn facing right; flips automatically when
## running the other way. Set false if your art faces left.
@export var art_faces_right: bool = true

@export_group("Patrol")
## Left / right ends of the patrol band (world x coordinates).
@export var run_left_x: float = 300.0
@export var run_right_x: float = 900.0
## The floor line the mouse runs on (world y).
@export var floor_y: float = 640.0
@export var run_speed: float = 240.0
## Waypoints are re-rolled until at least this far from the current spot,
## so the mouse never jitters in place.
@export var min_run_distance: float = 140.0
@export var sniff_chance: float = 0.4
@export var sniff_time_min: float = 0.6
@export var sniff_time_max: float = 1.8

@export_group("Jump")
@export var jump_duration: float = 0.45
@export var jump_arc_height: float = 110.0

var state: int = State.IDLE
var _waypoint_x: float = 0.0
var _sniff_left: float = 0.0
var _jump_from: Vector2
var _jump_to: Vector2


func _ready() -> void:
	if animated_sprite == null:
		animated_sprite = get_node_or_null("AnimatedSprite2D")  # auto-resolve
	global_position.y = floor_y
	_pick_waypoint()
	state = State.RUN


func _process(delta: float) -> void:
	match state:
		State.RUN:
			_step_run(delta)
		State.SNIFF:
			_step_sniff(delta)
		State.GO_TO:
			_step_go_to(delta)
		_:
			pass  # JUMP / CHEW are tween-driven; IDLE waits for a command


# ---------------- patrol ----------------

func _step_run(delta: float) -> void:
	_play("run")
	var dir: float = signf(_waypoint_x - global_position.x)
	_set_facing(dir)
	global_position.x += dir * run_speed * delta
	if absf(_waypoint_x - global_position.x) <= run_speed * delta:
		global_position.x = _waypoint_x
		if randf() < sniff_chance:
			state = State.SNIFF
			_sniff_left = randf_range(sniff_time_min, sniff_time_max)
		else:
			_pick_waypoint()


func _step_sniff(delta: float) -> void:
	_play("sniff")
	_sniff_left -= delta
	if _sniff_left <= 0.0:
		_pick_waypoint()
		state = State.RUN


func _step_go_to(delta: float) -> void:
	_play("run")
	var dir: float = signf(_waypoint_x - global_position.x)
	_set_facing(dir)
	global_position.x += dir * run_speed * delta
	if absf(_waypoint_x - global_position.x) <= run_speed * delta:
		global_position.x = _waypoint_x
		state = State.IDLE
		arrived.emit()


func _pick_waypoint() -> void:
	var x: float = global_position.x
	for i in 10:
		var candidate: float = randf_range(run_left_x, run_right_x)
		if absf(candidate - x) >= min_run_distance:
			_waypoint_x = candidate
			return
	_waypoint_x = run_left_x if x > (run_left_x + run_right_x) * 0.5 else run_right_x


# ---------------- commands (called by the puzzle) ----------------

## Run to x — any x, even outside the patrol band. Emits "arrived".
func go_to(x: float) -> void:
	if _is_busy():
		return
	_waypoint_x = x
	state = State.GO_TO


## Jump in an arc to a global position. Emits action_finished("jump").
func do_jump(to_global: Vector2) -> void:
	if _is_busy():
		return
	state = State.JUMP
	_jump_from = global_position
	_jump_to = to_global
	_set_facing(signf(to_global.x - global_position.x))
	_play("jump")
	var tw := create_tween()
	tw.tween_method(_set_arc_position, 0.0, 1.0, jump_duration)
	tw.finished.connect(_on_jump_finished)

## Play the chew animation for a while. Emits action_finished("chew").
func do_chew(seconds: float) -> void:
	if _is_busy():
		return
	state = State.CHEW
	_play("chew")
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.finished.connect(_on_chew_finished)

## Hop back down to floor_y (same x).
func jump_back_to_floor() -> void:
	do_jump(Vector2(global_position.x, floor_y))

## Face toward a world x position (used after landing somewhere).
func face_toward(x: float) -> void:
	_set_facing(signf(x - global_position.x))

## Return to normal wandering.
func resume_patrol() -> void:
	_pick_waypoint()
	state = State.RUN

## Freeze in place (IDLE). Patrol stays off until resume_patrol() or
## another command. Does NOT change visibility — callers hide/show the
## node themselves (e.g. KeyTheft tucks the mouse into its hole).
func stop() -> void:
	state = State.IDLE

# ---------------- internals ----------------

func _is_busy() -> bool:
	if state == State.JUMP or state == State.CHEW:
		push_warning("Mouse: ignored a command while " + State.keys()[state] + " is playing.")
		return true
	return false

func _on_jump_finished() -> void:
	global_position = _jump_to
	state = State.IDLE
	action_finished.emit("jump")

func _on_chew_finished() -> void:
	state = State.IDLE
	action_finished.emit("chew")

func _set_arc_position(t: float) -> void:
	var pos := _jump_from.lerp(_jump_to, t)
	pos.y -= sin(t * PI) * jump_arc_height
	global_position = pos

func _set_facing(dir_x: float) -> void:
	if animated_sprite == null or dir_x == 0.0:
		return
	animated_sprite.flip_h = (dir_x < 0.0) if art_faces_right else (dir_x > 0.0)

func _play(anim: String) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if animated_sprite.sprite_frames.has_animation(anim):
		if animated_sprite.animation != anim or not animated_sprite.is_playing():
			animated_sprite.play(anim)
