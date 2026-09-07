extends Label
## A line of commentary that pops in above an object, holds while
## you read, then fades out and frees itself. Created at runtime by
## interactable.show_comment() — never add this to a scene manually.

@export_group("Timing")
@export var pop_time: float = 0.18
@export var fade_time: float = 0.45
## Hold time clamps; the actual hold scales with text length.
@export var hold_min: float = 2.2
@export var hold_max: float = 5.0

# All styling lives here — nothing to set in the Inspector.
const FONT_SIZE := 26
const OUTLINE_SIZE := 8
const OUTLINE_COLOR := Color(0.12, 0.12, 0.12, 1.0)

func setup(line: String, anchor: Vector2) -> void:
	text = line
	mouse_filter = MOUSE_FILTER_IGNORE  # Text must never block clicks.
	add_theme_font_size_override("font_size", FONT_SIZE)
	add_theme_constant_override("outline_size", OUTLINE_SIZE)
	add_theme_color_override("font_outline_color", OUTLINE_COLOR)

	# Measure the line, then centre the label on the anchor point.
	var f: Font = get_theme_font("font")
	var width := f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	size = Vector2(width, FONT_SIZE * 1.5)
	pivot_offset = size / 2.0
	position = Vector2(anchor.x - width / 2.0, anchor.y)
	position.x = clampf(position.x, 90.0, 1830.0)
	position.y = maxf(position.y, 50.0)

	# Pop in, hold, fade, self-destruct.
	scale = Vector2(0.75, 0.75)
	modulate.a = 0.0
	var hold := clampf(1.8 + line.length() * 0.05, hold_min, hold_max)

	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, pop_time)
	tw.parallel().tween_property(self, "scale", Vector2.ONE, pop_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(hold)
	tw.tween_property(self, "modulate:a", 0.0, fade_time)
	tw.tween_callback(queue_free)
