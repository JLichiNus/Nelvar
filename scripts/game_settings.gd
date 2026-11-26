extends Node
## Autoload: player settings that persist between launches (user://settings.cfg).
## F12 (input action "toggle_info_panel") shows or hides the in-game info panel
## from anywhere; the menu's settings panel edits the same value.

signal info_panel_changed(shown: bool)
signal start_in_void_changed(enabled: bool)
signal start_on_earth_changed(enabled: bool)
signal start_in_fire_changed(enabled: bool)
signal start_on_ice_changed(enabled: bool)
signal start_in_fire2_changed(enabled: bool)
signal start_on_ice2_changed(enabled: bool)
signal damage_vignette_changed()
signal volume_changed(bus: StringName, value: float)

const PATH := "user://settings.cfg"

## In-game panel with the seed, world stats and controls. Hidden by default.
var show_info_panel := false
## Red vignette when the player is hurt: strength per level, the first is off.
const VIGNETTE_LEVELS: Array[float] = [0.0, 0.4, 0.7, 1.0]
const VIGNETTE_NAMES: Array[String] = ["выкл.", "слабая", "средняя", "сильная"]

## Index into VIGNETTE_LEVELS.
var damage_vignette_level := 2
## Show only the side of the vignette facing whatever hurt the player.
var damage_vignette_directional := false
## Developer menu: "Играть" opens the Void (scenes/void.tscn) instead of the usual world.
var start_in_void := false
## Developer menu: "Играть" opens the earth valley (scenes/earth.tscn).
var start_on_earth := false
## Developer menu: "Играть" opens the fire forge (scenes/fire.tscn).
var start_in_fire := false
## Developer menu: "Играть" opens the ice valley (scenes/ice.tscn).
var start_on_ice := false
## Developer menu: "Играть" opens the volcano (scenes/fire2.tscn).
var start_in_fire2 := false
## Developer menu: "Играть" opens the ice cave (scenes/ice2.tscn). Only one of the start
## options is on at a time.
var start_on_ice2 := false
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
		start_on_earth = config.get_value("dev", "start_on_earth", start_on_earth) and not start_in_void
		start_in_fire = config.get_value("dev", "start_in_fire", start_in_fire) \
			and not start_in_void and not start_on_earth
		start_on_ice = config.get_value("dev", "start_on_ice", start_on_ice) \
			and not start_in_void and not start_on_earth and not start_in_fire
		start_in_fire2 = config.get_value("dev", "start_in_fire2", start_in_fire2) \
			and not start_in_void and not start_on_earth and not start_in_fire and not start_on_ice
		start_on_ice2 = config.get_value("dev", "start_on_ice2", start_on_ice2) \
			and not start_in_void and not start_on_earth and not start_in_fire and not start_on_ice \
			and not start_in_fire2
		damage_vignette_level = clampi(config.get_value("hud", "damage_vignette_level",
			damage_vignette_level), 0, VIGNETTE_LEVELS.size() - 1)
		damage_vignette_directional = config.get_value("hud", "damage_vignette_directional",
			damage_vignette_directional)
		for bus in VOLUME_BUSES:
			volumes[bus] = clampf(float(config.get_value("audio", String(bus).to_lower(),
				volumes[bus])), 0.0, 1.0)
	for bus in VOLUME_BUSES:
		_apply_volume(bus)


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


func set_start_in_void(enabled: bool) -> void:
	if enabled == start_in_void:
		return
	start_in_void = enabled
	if enabled:
		_turn_off_other_starts(&"void")
	_save()
	start_in_void_changed.emit(enabled)


func set_start_on_earth(enabled: bool) -> void:
	if enabled == start_on_earth:
		return
	start_on_earth = enabled
	if enabled:
		_turn_off_other_starts(&"earth")
	_save()
	start_on_earth_changed.emit(enabled)


func set_start_in_fire(enabled: bool) -> void:
	if enabled == start_in_fire:
		return
	start_in_fire = enabled
	if enabled:
		_turn_off_other_starts(&"fire")
	_save()
	start_in_fire_changed.emit(enabled)


func set_start_on_ice(enabled: bool) -> void:
	if enabled == start_on_ice:
		return
	start_on_ice = enabled
	if enabled:
		_turn_off_other_starts(&"ice")
	_save()
	start_on_ice_changed.emit(enabled)


func set_start_in_fire2(enabled: bool) -> void:
	if enabled == start_in_fire2:
		return
	start_in_fire2 = enabled
	if enabled:
		_turn_off_other_starts(&"fire2")
	_save()
	start_in_fire2_changed.emit(enabled)


func set_start_on_ice2(enabled: bool) -> void:
	if enabled == start_on_ice2:
		return
	start_on_ice2 = enabled
	if enabled:
		_turn_off_other_starts(&"ice2")
	_save()
	start_on_ice2_changed.emit(enabled)


## The start options exclude each other: turning one on turns the others off.
func _turn_off_other_starts(kept: StringName) -> void:
	if kept != &"void" and start_in_void:
		start_in_void = false
		start_in_void_changed.emit(false)
	if kept != &"earth" and start_on_earth:
		start_on_earth = false
		start_on_earth_changed.emit(false)
	if kept != &"fire" and start_in_fire:
		start_in_fire = false
		start_in_fire_changed.emit(false)
	if kept != &"ice" and start_on_ice:
		start_on_ice = false
		start_on_ice_changed.emit(false)
	if kept != &"fire2" and start_in_fire2:
		start_in_fire2 = false
		start_in_fire2_changed.emit(false)
	if kept != &"ice2" and start_on_ice2:
		start_on_ice2 = false
		start_on_ice2_changed.emit(false)


func damage_vignette_strength() -> float:
	return VIGNETTE_LEVELS[damage_vignette_level]


func set_damage_vignette_level(level: int) -> void:
	level = clampi(level, 0, VIGNETTE_LEVELS.size() - 1)
	if level == damage_vignette_level:
		return
	damage_vignette_level = level
	_save()
	damage_vignette_changed.emit()


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
	config.set_value("dev", "start_on_earth", start_on_earth)
	config.set_value("dev", "start_in_fire", start_in_fire)
	config.set_value("dev", "start_on_ice", start_on_ice)
	config.set_value("dev", "start_in_fire2", start_in_fire2)
	config.set_value("dev", "start_on_ice2", start_on_ice2)
	config.set_value("hud", "damage_vignette_level", damage_vignette_level)
	config.set_value("hud", "damage_vignette_directional", damage_vignette_directional)
	for bus in VOLUME_BUSES:
		config.set_value("audio", String(bus).to_lower(), volumes[bus])
	var error := config.save(PATH)
	if error != OK:
		push_warning("Не удалось сохранить настройки: %s" % error_string(error))
