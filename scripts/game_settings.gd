extends Node
## Autoload: player settings that persist between launches (user://settings.cfg).
## F12 (input action "toggle_info_panel") shows or hides the in-game info panel
## from anywhere; the menu's settings panel edits the same value.

signal info_panel_changed(shown: bool)
signal start_in_void_changed(enabled: bool)
signal start_on_earth_changed(enabled: bool)
signal start_in_fire_changed(enabled: bool)

const PATH := "user://settings.cfg"

## In-game panel with the seed, world stats and controls. Hidden by default.
var show_info_panel := false
## Developer menu: "Играть" opens the Void (scenes/void.tscn) instead of the usual world.
var start_in_void := false
## Developer menu: "Играть" opens the earth valley (scenes/earth.tscn).
var start_on_earth := false
## Developer menu: "Играть" opens the fire forge (scenes/fire.tscn). Only one of the
## start options is on at a time.
var start_in_fire := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		show_info_panel = config.get_value("hud", "show_info_panel", show_info_panel)
		start_in_void = config.get_value("dev", "start_in_void", start_in_void)
		start_on_earth = config.get_value("dev", "start_on_earth", start_on_earth) and not start_in_void
		start_in_fire = config.get_value("dev", "start_in_fire", start_in_fire) \
			and not start_in_void and not start_on_earth


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


func _save() -> void:
	var config := ConfigFile.new()
	config.load(PATH)  # keep any other sections already saved
	config.set_value("hud", "show_info_panel", show_info_panel)
	config.set_value("dev", "start_in_void", start_in_void)
	config.set_value("dev", "start_on_earth", start_on_earth)
	config.set_value("dev", "start_in_fire", start_in_fire)
	var error := config.save(PATH)
	if error != OK:
		push_warning("Не удалось сохранить настройки: %s" % error_string(error))
