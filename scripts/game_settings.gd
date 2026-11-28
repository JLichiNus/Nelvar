extends Node
## Autoload: player settings that persist between launches (user://settings.cfg).
## F12 (input action "toggle_info_panel") shows or hides the in-game info panel
## from anywhere; the menu's settings panel edits the same value. F11 (see
## FullscreenToggle) switches between a window and the last full-screen mode.

signal info_panel_changed(shown: bool)
## The developer start changed (dev_start; empty: none).
signal dev_start_changed(id: StringName)
signal damage_vignette_changed()
signal volume_changed(bus: StringName, value: float)
signal display_changed()
signal audio_changed()
signal game_changed()
## The game window gained or lost focus (see is_window_focused()).
signal window_focus_changed(focused: bool)

const PATH := "user://settings.cfg"
## Developer start flags of settings saved before the catalog, in the order they were
## read then, and the maps they stand for.
const LEGACY_STARTS := {
	"start_in_void": &"void", "start_in_air": &"air_islands", "start_on_earth": &"earth_valley",
	"start_on_earth2": &"earth_forest", "start_in_fire": &"fire_forge", "start_on_ice": &"ice_valley",
	"start_in_fire2": &"fire_volcano", "start_on_ice2": &"ice_cave",
}

## Frame rate cap set by the game, frames per second; 0 is no cap. Separate
## from VSync: VSync holds frames to the monitor's refresh, the cap limits
## how many the game draws (the lower of the two wins). The defaults are
## Godot's: no cap, VSync on.
const MAX_FPS_MIN := 30
const MAX_FPS_MAX := 240
const MAX_FPS_STEP := 10
var max_fps := 0
var vsync := true

## How the game window takes the screen. BORDERLESS covers the screen with an
## ordinary window (quick to switch away from); EXCLUSIVE takes the monitor
## over (can lower latency a little). The game starts BORDERLESS, as
## display/window/size/mode in project.godot does.
enum WindowMode { WINDOWED, BORDERLESS, EXCLUSIVE }
const WINDOW_MODE_NAMES: Array[String] = ["Окно", "Без рамки", "Полный экран"]
const WINDOWED_SIZE := Vector2i(1280, 800)
var window_mode := WindowMode.BORDERLESS
## F11 from a window goes back to this one.
var _last_full_screen := WindowMode.BORDERLESS

## Frame rate cap while the game window is not focused (another window on
## top, or minimized); 0 keeps the usual one. Saves power and fan noise.
const BACKGROUND_FPS: Array[int] = [0, 30, 10]
const BACKGROUND_FPS_NAMES: Array[String] = ["Как обычно", "30 FPS", "10 FPS"]
var background_fps := 30
var _focused := true

## Gamma over the whole picture: above 1 lifts the mid tones, below 1 darkens
## them; black and white stay. Drawn by DisplayOverlay.
const BRIGHTNESS_MIN := 0.5
const BRIGHTNESS_MAX := 1.5
const BRIGHTNESS_STEP := 0.05
var brightness := 1.0
## Frames per second in the top right corner (DisplayOverlay).
var show_fps := false

## In-game panel with the seed, world stats and controls. Hidden by default.
var show_info_panel := false
## Red vignette when the player is hurt: its strength 0..1 (0 is off), set
## in steps of VIGNETTE_STEP.
const VIGNETTE_STEP := 0.1
## Older settings files kept a level (index into these) instead.
const LEGACY_VIGNETTE_LEVELS: Array[float] = [0.0, 0.4, 0.7, 1.0]

var damage_vignette := 0.7
## Show only the side of the vignette facing whatever hurt the player.
var damage_vignette_directional := false
## Developer menu: «Играть» opens this map (NelvarLocationDef.id in the catalog)
## instead of a random one; empty: a random one. Public builds ignore it.
var dev_start := StringName()
## Volume per audio bus, 0..1 (default_bus_layout.tres): everything, music,
## sound effects.
const VOLUME_BUSES: Array[StringName] = [&"Master", &"Music", &"SFX"]
const VOLUME_NAMES: Array[String] = ["Общая громкость", "Музыка", "Звуки"]
var volumes := {&"Master": 1.0, &"Music": 1.0, &"SFX": 1.0}
## Music fades out while the game window is not focused and back in when it is.
var mute_music_in_background := false
## Seconds for the music to fade out / back in.
const MUSIC_FADE_OUT := 0.4
const MUSIC_FADE_IN := 0.8
## The Music bus is played at volumes[&"Music"] times this (0..1).
var _music_gain := 1.0
var _music_tween: Tween

## The window's focus is followed through the engine's notifications and, in
## case a window manager drops one (some Linux WMs do), also polled this often.
const FOCUS_POLL_INTERVAL := 0.25
var _focus_poll_wait := 0.0
## Set once the window has been focused at least once: a window manager can
## leave a new window unfocused at start, which is not the player leaving.
var _had_focus := false

## The run pauses (the pause menu opens) when the window loses focus.
var pause_on_focus_loss := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		show_info_panel = config.get_value("hud", "show_info_panel", show_info_panel)
		dev_start = _load_dev_start(config)
		if config.has_section_key("hud", "damage_vignette"):
			damage_vignette = _snap_vignette(float(config.get_value("hud", "damage_vignette")))
		elif config.has_section_key("hud", "damage_vignette_level"):
			var level := clampi(int(config.get_value("hud", "damage_vignette_level")), 0,
				LEGACY_VIGNETTE_LEVELS.size() - 1)
			damage_vignette = LEGACY_VIGNETTE_LEVELS[level]
		damage_vignette_directional = config.get_value("hud", "damage_vignette_directional",
			damage_vignette_directional)
		for bus in VOLUME_BUSES:
			volumes[bus] = clampf(float(config.get_value("audio", String(bus).to_lower(),
				volumes[bus])), 0.0, 1.0)
		mute_music_in_background = bool(config.get_value("audio", "mute_music_in_background",
			mute_music_in_background))
		pause_on_focus_loss = bool(config.get_value("game", "pause_on_focus_loss",
			pause_on_focus_loss))
		max_fps = _snap_max_fps(int(config.get_value("display", "max_fps", max_fps)))
		vsync = bool(config.get_value("display", "vsync", vsync))
		window_mode = clampi(int(config.get_value("display", "window_mode", window_mode)),
			0, WindowMode.size() - 1) as WindowMode
		var background := int(config.get_value("display", "background_fps", background_fps))
		background_fps = background if background in BACKGROUND_FPS else background_fps
		brightness = _snap_brightness(float(config.get_value("display", "brightness", brightness)))
		show_fps = bool(config.get_value("display", "show_fps", show_fps))
	if window_mode != WindowMode.WINDOWED:
		_last_full_screen = window_mode
	for bus in VOLUME_BUSES:
		_apply_volume(bus)
	_apply_window_mode()
	_apply_display()


func _notification(what: int) -> void:
	match what:
		# The window's own notification comes first (the application's about
		# 0.25 s later); either one is enough.
		NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_set_focused(false)
		NOTIFICATION_WM_WINDOW_FOCUS_IN, NOTIFICATION_APPLICATION_FOCUS_IN:
			_set_focused(true)


func _process(delta: float) -> void:
	# Headless runs (the tests) have no window to be focused.
	if DisplayServer.get_name() == "headless":
		return
	_focus_poll_wait -= delta
	if _focus_poll_wait > 0.0:
		return
	_focus_poll_wait = FOCUS_POLL_INTERVAL
	var window := get_window()
	_set_focused(DisplayServer.window_is_focused() and window.mode != Window.MODE_MINIMIZED)


## Whether the player is looking at the game: drives the background frame
## cap, the background music fade and the pause on focus loss.
func is_window_focused() -> bool:
	return _focused


## The window has been focused since the game started: losing focus now
## means the player went elsewhere.
func window_had_focus() -> bool:
	return _had_focus


func _set_focused(focused: bool) -> void:
	if focused:
		_had_focus = true
	if focused == _focused:
		return
	_focused = focused
	_apply_display()
	_fade_music()
	window_focus_changed.emit(focused)


func set_pause_on_focus_loss(enabled: bool) -> void:
	if enabled == pause_on_focus_loss:
		return
	pause_on_focus_loss = enabled
	_save()
	game_changed.emit()


func set_mute_music_in_background(enabled: bool) -> void:
	if enabled == mute_music_in_background:
		return
	mute_music_in_background = enabled
	_fade_music()
	_save()
	audio_changed.emit()


func _fade_music() -> void:
	var target := 0.0 if mute_music_in_background and not _focused else 1.0
	if _music_tween != null:
		_music_tween.kill()
	if is_equal_approx(target, _music_gain):
		return
	var time := MUSIC_FADE_OUT if target < _music_gain else MUSIC_FADE_IN
	_music_tween = create_tween()
	_music_tween.tween_method(_set_music_gain, _music_gain, target,
		time * absf(target - _music_gain))


func _set_music_gain(gain: float) -> void:
	_music_gain = gain
	_apply_volume(&"Music")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_info_panel"):
		set_show_info_panel(not show_info_panel)
		get_viewport().set_input_as_handled()


func set_show_info_panel(shown: bool) -> void:
	if shown == show_info_panel:
		return
	show_info_panel = shown
	_save()
	info_panel_changed.emit(shown)


## `fps` 0 is no cap; anything else is kept within MAX_FPS_MIN..MAX_FPS_MAX.
func set_max_fps(fps: int) -> void:
	fps = _snap_max_fps(fps)
	if fps == max_fps:
		return
	max_fps = fps
	_apply_display()
	_save()
	display_changed.emit()


func set_vsync(enabled: bool) -> void:
	if enabled == vsync:
		return
	vsync = enabled
	_apply_display()
	_save()
	display_changed.emit()


func _snap_max_fps(fps: int) -> int:
	if fps <= 0:
		return 0
	fps = roundi(float(fps) / MAX_FPS_STEP) * MAX_FPS_STEP
	return clampi(fps, MAX_FPS_MIN, MAX_FPS_MAX)


func set_window_mode(mode: WindowMode) -> void:
	if mode == window_mode:
		return
	window_mode = mode
	if mode != WindowMode.WINDOWED:
		_last_full_screen = mode
	_apply_window_mode()
	_save()
	display_changed.emit()


## F11: a window <-> the full-screen mode used last.
func toggle_full_screen() -> void:
	set_window_mode(_last_full_screen if window_mode == WindowMode.WINDOWED
		else WindowMode.WINDOWED)


func set_background_fps(fps: int) -> void:
	if fps == background_fps or fps not in BACKGROUND_FPS:
		return
	background_fps = fps
	_apply_display()
	_save()
	display_changed.emit()


func set_brightness(value: float) -> void:
	value = _snap_brightness(value)
	if is_equal_approx(value, brightness):
		return
	brightness = value
	_save()
	display_changed.emit()


func set_show_fps(shown: bool) -> void:
	if shown == show_fps:
		return
	show_fps = shown
	_save()
	display_changed.emit()


## Whole steps, divided rather than multiplied back so 1.15 is saved as 1.15.
func _snap_brightness(value: float) -> float:
	var steps := roundf((value - BRIGHTNESS_MIN) / BRIGHTNESS_STEP)
	return clampf(BRIGHTNESS_MIN + steps / roundf(1.0 / BRIGHTNESS_STEP),
		BRIGHTNESS_MIN, BRIGHTNESS_MAX)


## The frame cap now: the player's, or the background one if it is lower and
## the window is not focused.
func _frame_cap() -> int:
	if _focused or background_fps == 0:
		return max_fps
	return background_fps if max_fps == 0 else mini(max_fps, background_fps)


func _apply_display() -> void:
	Engine.max_fps = _frame_cap()
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func _apply_window_mode() -> void:
	var window := get_window()
	match window_mode:
		WindowMode.BORDERLESS:
			window.mode = Window.MODE_FULLSCREEN
		WindowMode.EXCLUSIVE:
			window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		_:
			if window.mode == Window.MODE_WINDOWED:
				return
			window.mode = Window.MODE_WINDOWED
			# Starting full screen leaves no previous windowed size to
			# restore, so set it and center the window on its screen.
			window.size = WINDOWED_SIZE
			window.move_to_center()


## Developer menu: «Играть» opens map `id` (empty: a random one; an id the catalog does not
## know counts as empty there, NelvarLocationCatalog.start_location()).
func set_dev_start(id: StringName) -> void:
	if id == dev_start:
		return
	dev_start = id
	_save()
	dev_start_changed.emit(id)


## The saved developer start. Settings saved before the catalog kept one flag per map;
## the first of them that is on is taken (they excluded each other).
static func _load_dev_start(config: ConfigFile) -> StringName:
	var id := StringName(config.get_value("dev", "start", ""))
	if id.is_empty():
		for key: String in LEGACY_STARTS:
			if bool(config.get_value("dev", key, false)):
				id = LEGACY_STARTS[key]
				break
	return id


func damage_vignette_strength() -> float:
	return damage_vignette


func set_damage_vignette(strength: float) -> void:
	strength = _snap_vignette(strength)
	if is_equal_approx(strength, damage_vignette):
		return
	damage_vignette = strength
	_save()
	damage_vignette_changed.emit()


## Whole steps, divided rather than multiplied back so 0.7 is saved as 0.7.
func _snap_vignette(strength: float) -> float:
	return clampf(roundf(strength / VIGNETTE_STEP) / roundf(1.0 / VIGNETTE_STEP), 0.0, 1.0)


func set_damage_vignette_directional(enabled: bool) -> void:
	if enabled == damage_vignette_directional:
		return
	damage_vignette_directional = enabled
	_save()
	damage_vignette_changed.emit()


func volume(bus: StringName) -> float:
	return volumes.get(bus, 1.0)


## `value` 0..1 as on the slider.
func set_volume(bus: StringName, value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if not volumes.has(bus) or is_equal_approx(value, volumes[bus]):
		return
	volumes[bus] = value
	_apply_volume(bus)
	_save()
	volume_changed.emit(bus, value)


# The slider is squared on the way to loudness, so its middle sounds like
# the middle (half is -12 dB) rather than barely quieter than full. Zero mutes.
func _apply_volume(bus: StringName) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		push_warning("Нет аудиошины %s." % bus)
		return
	var value: float = volumes[bus]
	if bus == &"Music":
		value *= _music_gain
	AudioServer.set_bus_mute(index, value <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(value * value) if value > 0.0 else -80.0)


func _save() -> void:
	var config := ConfigFile.new()
	config.load(PATH)  # keep any other sections already saved
	config.set_value("hud", "show_info_panel", show_info_panel)
	config.set_value("dev", "start", String(dev_start))
	for key: String in LEGACY_STARTS:
		if config.has_section_key("dev", key):
			config.erase_section_key("dev", key)
	config.set_value("hud", "damage_vignette", damage_vignette)
	if config.has_section_key("hud", "damage_vignette_level"):
		config.erase_section_key("hud", "damage_vignette_level")
	config.set_value("hud", "damage_vignette_directional", damage_vignette_directional)
	for bus in VOLUME_BUSES:
		config.set_value("audio", String(bus).to_lower(), volumes[bus])
	config.set_value("audio", "mute_music_in_background", mute_music_in_background)
	config.set_value("game", "pause_on_focus_loss", pause_on_focus_loss)
	config.set_value("display", "max_fps", max_fps)
	config.set_value("display", "vsync", vsync)
	config.set_value("display", "window_mode", window_mode)
	config.set_value("display", "background_fps", background_fps)
	config.set_value("display", "brightness", brightness)
	config.set_value("display", "show_fps", show_fps)
	var error := config.save(PATH)
	if error != OK:
		push_warning("Не удалось сохранить настройки: %s" % error_string(error))
