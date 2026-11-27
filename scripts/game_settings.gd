extends Node
## Autoload: player settings that persist between launches (user://settings.cfg).
## F12 (input action "toggle_info_panel") shows or hides the in-game info panel
## from anywhere; the menu's settings panel edits the same value.

signal info_panel_changed(shown: bool)
signal start_in_void_changed(enabled: bool)
signal damage_vignette_changed()
signal volume_changed(bus: StringName, value: float)
signal display_changed()

const PATH := "user://settings.cfg"

## Frame rate cap set by the game, frames per second; 0 is no cap. Separate
## from VSync: VSync holds frames to the monitor's refresh, the cap limits
## how many the game draws (the lower of the two wins). The defaults are
## Godot's: no cap, VSync on.
const MAX_FPS_MIN := 30
const MAX_FPS_MAX := 240
const MAX_FPS_STEP := 10
var max_fps := 0
var vsync := true

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
## Developer menu: "Играть" opens the Void (scenes/void.tscn) instead of the usual world.
var start_in_void := false
## Volume per audio bus, 0..1 (default_bus_layout.tres): everything, music,
## sound effects.
const VOLUME_BUSES: Array[StringName] = [&"Master", &"Music", &"SFX"]
const VOLUME_NAMES: Array[String] = ["Общая громкость", "Музыка", "Звуки"]
var volumes := {&"Master": 1.0, &"Music": 1.0, &"SFX": 1.0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		show_info_panel = config.get_value("hud", "show_info_panel", show_info_panel)
		start_in_void = config.get_value("dev", "start_in_void", start_in_void)
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
		max_fps = _snap_max_fps(int(config.get_value("display", "max_fps", max_fps)))
		vsync = bool(config.get_value("display", "vsync", vsync))
	for bus in VOLUME_BUSES:
		_apply_volume(bus)
	_apply_display()


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


func _apply_display() -> void:
	Engine.max_fps = max_fps
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func set_start_in_void(enabled: bool) -> void:
	if enabled == start_in_void:
		return
	start_in_void = enabled
	_save()
	start_in_void_changed.emit(enabled)


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
	AudioServer.set_bus_mute(index, value <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(value * value) if value > 0.0 else -80.0)


func _save() -> void:
	var config := ConfigFile.new()
	config.load(PATH)  # keep any other sections already saved
	config.set_value("hud", "show_info_panel", show_info_panel)
	config.set_value("dev", "start_in_void", start_in_void)
	config.set_value("hud", "damage_vignette", damage_vignette)
	if config.has_section_key("hud", "damage_vignette_level"):
		config.erase_section_key("hud", "damage_vignette_level")
	config.set_value("hud", "damage_vignette_directional", damage_vignette_directional)
	for bus in VOLUME_BUSES:
		config.set_value("audio", String(bus).to_lower(), volumes[bus])
	config.set_value("display", "max_fps", max_fps)
	config.set_value("display", "vsync", vsync)
	var error := config.save(PATH)
	if error != OK:
		push_warning("Не удалось сохранить настройки: %s" % error_string(error))
