extends Node

const MENU_MUSIC: AudioStream = preload(
	"res://music/menu_music.mp3"
)
const GAMEPLAY_MUSIC: AudioStream = preload(
	"res://music/gameplay_music.mp3"
)
const NORMAL_CUTOFF_HZ := 20000.0
const MOUSEHOLE_CUTOFF_HZ := 850.0
const FILTER_FADE_DURATION := 0.8

var _music_player: AudioStreamPlayer
var _music_bus_index := -1
var _low_pass_filter: AudioEffectLowPassFilter
var _filter_tween: Tween
var _current_track: AudioStream


func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)

	_music_bus_index = AudioServer.get_bus_index("Music")

	if _music_bus_index == -1:
		push_error("MusicManager could not find the Music audio bus.")
		return

	var effect := AudioServer.get_bus_effect(_music_bus_index, 0)
	_low_pass_filter = effect as AudioEffectLowPassFilter

	if _low_pass_filter == null:
		push_error("MusicManager requires an AudioEffectLowPassFilter as the first effect on the Music bus.")


func play_menu_music() -> void:
	_play_track(MENU_MUSIC)


func play_gameplay_music() -> void:
	_play_track(GAMEPLAY_MUSIC)


func _play_track(track: AudioStream) -> void:
	if _current_track == track and _music_player.playing:
		return

	_current_track = track
	_music_player.stream = track
	_music_player.play()


func set_mousehole_filter(enabled: bool) -> void:
	if _low_pass_filter == null:
		return

	if _filter_tween != null and _filter_tween.is_running():
		_filter_tween.kill()

	var target_cutoff := NORMAL_CUTOFF_HZ

	if enabled:
		target_cutoff = MOUSEHOLE_CUTOFF_HZ

	_filter_tween = create_tween()
	_filter_tween.set_trans(Tween.TRANS_SINE)
	_filter_tween.set_ease(Tween.EASE_IN_OUT)
	_filter_tween.tween_property(_low_pass_filter, "cutoff_hz", target_cutoff, FILTER_FADE_DURATION)
