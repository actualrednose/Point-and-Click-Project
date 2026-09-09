extends Control
## Main menu controller.
## Handles scene navigation, options, and persistent settings.

const GAME_SCENE := "res://scenes/rooms/lab.tscn"
const SETTINGS_PATH := "user://settings.cfg"

const SETTINGS_SECTION_AUDIO := "audio"
const SETTINGS_SECTION_DISPLAY := "display"
const SETTINGS_MASTER_VOLUME := "master_volume"
const SETTINGS_FULLSCREEN := "fullscreen"

@onready var menu_panel: PanelContainer = $MenuPanel
@onready var options_panel: PanelContainer = $OptionsPanel

@onready var start_button: Button = $MenuPanel/Content/StartButton
@onready var options_button: Button = $MenuPanel/Content/OptionsButton
@onready var quit_button: Button = $MenuPanel/Content/QuitButton

@onready var volume_slider: HSlider = (
	$OptionsPanel/Content/VolumeSlider
)
@onready var fullscreen_check: BaseButton = (
	$OptionsPanel/Content/FullscreenCheck
)
@onready var back_button: Button = $OptionsPanel/Content/BackButton

var _settings := ConfigFile.new()
var _master_bus_index := -1
var _loading_settings := false


func _ready() -> void:
	_master_bus_index = AudioServer.get_bus_index("Master")
	MusicManager.play_menu_music()
	if _master_bus_index == -1:
		push_warning(
			"MainMenu: AudioServer Master bus was not found."
		)

	start_button.pressed.connect(_on_start_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	volume_slider.value_changed.connect(_on_volume_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	back_button.pressed.connect(_on_back_pressed)

	options_panel.visible = false
	_load_settings()


# ---------- Main menu ----------

func _on_start_pressed() -> void:
	MusicManager.play_gameplay_music()
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_options_pressed() -> void:
	menu_panel.visible = false
	options_panel.visible = true


func _on_quit_pressed() -> void:
	get_tree().quit()


# ---------- Options menu ----------

func _on_back_pressed() -> void:
	options_panel.visible = false
	menu_panel.visible = true


func _on_volume_changed(value: float) -> void:
	if _loading_settings:
		return

	_set_master_volume(value)
	_save_settings()


func _on_fullscreen_toggled(enabled: bool) -> void:
	if _loading_settings:
		return

	_set_fullscreen(enabled)
	_save_settings()


# ---------- Audio ----------

func _set_master_volume(value: float) -> void:
	if _master_bus_index == -1:
		return

	var volume := clampf(value, 0.0, 1.0)
	var volume_db := -80.0

	if volume > 0.001:
		volume_db = linear_to_db(volume)

	AudioServer.set_bus_volume_db(_master_bus_index, volume_db)


# ---------- Display ----------

func _set_fullscreen(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN
		)
	else:
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_WINDOWED
		)


func _is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()

	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN


# ---------- Settings persistence ----------

func _load_settings() -> void:
	_loading_settings = true

	var error := _settings.load(SETTINGS_PATH)

	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning(
			"MainMenu: could not load settings file. Error: %s"
			% error
		)

	var saved_volume: float = float(
		_settings.get_value(
			SETTINGS_SECTION_AUDIO,
			SETTINGS_MASTER_VOLUME,
			1.0
		)
	)

	var saved_fullscreen: bool = bool(
		_settings.get_value(
			SETTINGS_SECTION_DISPLAY,
			SETTINGS_FULLSCREEN,
			_is_fullscreen()
		)
	)

	saved_volume = clampf(saved_volume, 0.0, 1.0)

	volume_slider.value = saved_volume
	fullscreen_check.button_pressed = saved_fullscreen

	_set_master_volume(saved_volume)
	_set_fullscreen(saved_fullscreen)

	_loading_settings = false


func _save_settings() -> void:
	_settings.set_value(
		SETTINGS_SECTION_AUDIO,
		SETTINGS_MASTER_VOLUME,
		volume_slider.value
	)

	_settings.set_value(
		SETTINGS_SECTION_DISPLAY,
		SETTINGS_FULLSCREEN,
		fullscreen_check.button_pressed
	)

	var error := _settings.save(SETTINGS_PATH)

	if error != OK:
		push_warning(
			"MainMenu: could not save settings file. Error: %s"
			% error
	)
