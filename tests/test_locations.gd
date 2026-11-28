extends SceneTree
## The locations: the catalog (locations/) knows every map and «Играть» starts where it
## should; the developer start is one setting (old saved flags carry over) shown as one
## option per map. Every map builds on the shared frame (NelvarLocation) and gets the
## shared interface (ui/location_ui/location_ui.tscn) bound to its own player — health,
## abilities, level, the damage vignette, the mutations, the pause menu and the cursor of
## its reality, the info panel's title with the seed; F3 and the wheel are handled.
## Run: godot --headless --path . --script tests/test_locations.gd

## Maps without a debug view on F3.
const NO_DEBUG: Array[StringName] = [&"void"]
## The maps «Играть» picks among.
const RANDOM_STARTS: Array[StringName] = [&"air_islands", &"fire_volcano", &"ice_cave", &"earth_forest"]
const SEED := 20261128

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := NelvarLocations.catalog()
	_check_catalog(catalog)
	await _check_dev_start(catalog)
	for location in catalog.locations:
		await _check_location(location)
	if _failures.is_empty():
		print("PASS: %d location checks; the catalog, the developer start and %d maps on the shared frame and interface." % [
			_checks, catalog.locations.size()])
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


## Untyped: the locations and their interface use autoloads, which a test cannot name at
## compile time.
func _check_location(location: NelvarLocationDef) -> void:
	var path := location.scene
	var game = (load(path) as PackedScene).instantiate()
	game.set_meta("seed_override", SEED)
	root.add_child(game)
	for frame in 3:
		await process_frame
	var name := path.get_file()
	_check(_extends(game.get_script(), "res://core/location.gd"), "%s is not a NelvarLocation" % name)
	_check(game.world_seed == SEED, "%s did not take the seed" % name)
	_check(game.definition == location, "%s does not point back to its catalog entry" % name)
	var player: NelvarPlayer = game.player
	var ui = game.ui
	_check(player != null and ui != null, "%s has no player or no interface" % name)
	if player == null or ui == null:
		game.queue_free()
		await process_frame
		return
	for widget in [^"HUD/DamageVignette", ^"HUD/HealthBar", ^"HUD/AbilityBar", ^"HUD/LevelLine", ^"MutationHud"]:
		_check(ui.get_node(widget).get(&"player") == player, "%s: %s is not bound to the player" % [name, widget])
	var mutations: NelvarMutationHud = ui.get_node(^"MutationHud")
	_check(mutations.visible and mutations.process_mode != Node.PROCESS_MODE_DISABLED,
		"%s: the mutations are not shown" % name)
	_check(game.reality != null and ui.get_node(^"PauseMenu").get(&"reality") == game.reality,
		"%s: the pause menu does not know the reality" % name)
	_check(game.reality != null and (ui.get_node(^"LocationCursor") as NelvarLocationCursor).cursor == game.reality.cursor,
		"%s: the cursor is not the reality's" % name)
	_check(ui.seed_label.text == "%s · СИД %d" % [game.title, SEED], "%s: the panel's title is «%s»" % [name, ui.seed_label.text])
	_check(not ui.controls_label.text.is_empty(), "%s: no controls on the panel" % name)
	game.say("проверка")
	await process_frame
	_check(ui.message.text == "проверка", "%s: say() shows nothing" % name)
	var key := InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	game._unhandled_input(key)
	_check(game.show_debug == not NO_DEBUG.has(location.id), "%s: F3 does not toggle the debug view as it should" % name)
	var zoom: Vector2 = player.camera.zoom
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	game._unhandled_input(wheel)
	_check(player.camera.zoom != zoom, "%s: the wheel does not zoom" % name)
	game.queue_free()
	await process_frame
	await process_frame


# --- The catalog and the developer start ---------------------------------------------

func _check_catalog(catalog: NelvarLocationCatalog) -> void:
	var ids := {}
	for location in catalog.locations:
		_check(not ids.has(location.id), "Two maps are called %s" % location.id)
		ids[location.id] = true
		_check(ResourceLoader.exists(location.scene), "%s: no scene at %s" % [location.id, location.scene])
		_check(location.reality != null and not location.title.is_empty() and not location.dev_label.is_empty()
			and not location.dev_hint.is_empty(), "%s: reality, title or developer option missing" % location.id)
	var scenes := Array(DirAccess.get_files_at("res://scenes")).filter(
		func(file: String) -> bool: return file.ends_with(".tscn") and file != "main_menu.tscn")
	for file: String in scenes:
		_check(catalog.locations.any(func(location: NelvarLocationDef) -> bool: return location.scene == "res://scenes/" + file),
			"scenes/%s is not in the catalog" % file)
	var random := catalog.random_starts().map(func(location: NelvarLocationDef) -> StringName: return location.id)
	_check(random == RANDOM_STARTS, "«Играть» picks among %s" % [random])
	_check(catalog.start_location(&"ice_cave").id == &"ice_cave", "The developer start is not where «Играть» opens")
	for dev_start: StringName in [&"", &"no_such_map"]:
		for i in 20:
			_check(RANDOM_STARTS.has(catalog.start_location(dev_start).id),
				"Without a developer start «Играть» opened a map off the random list")


## One setting, any map of the catalog; the old flags carry over; the developer menu shows
## one option per map and they exclude each other. The saved settings are put back.
func _check_dev_start(catalog: NelvarLocationCatalog) -> void:
	var settings: Node = root.get_node("GameSettings")
	var path: String = settings.PATH
	var saved := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	var was: StringName = settings.dev_start
	for location in catalog.locations:
		settings.set_dev_start(location.id)
		_check(settings.dev_start == location.id, "The developer start did not take %s" % location.id)
	var legacy := ConfigFile.new()
	legacy.set_value("dev", "start_in_air", false)
	legacy.set_value("dev", "start_on_ice2", true)
	_check(settings._load_dev_start(legacy) == &"ice_cave", "An old saved start flag did not carry over")
	var panel: Control = load("res://ui/main_menu/settings_panel.tscn").instantiate()
	root.add_child(panel)
	await process_frame
	var page: Node = panel.get_node("%DevPage")
	var checks := page.get_children().filter(func(child: Node) -> bool: return child is CheckButton)
	_check(checks.size() == catalog.locations.size(), "The developer menu has %d start options" % checks.size())
	var forge: CheckButton = page.get_node_or_null("Start_fire_forge")
	var cave: CheckButton = page.get_node_or_null("Start_ice_cave")
	if forge != null and cave != null:
		cave.button_pressed = true
		forge.button_pressed = true
		_check(settings.dev_start == &"fire_forge" and forge.button_pressed and not cave.button_pressed,
			"The developer start options do not exclude each other")
		_check(forge.get_meta(&"hint") == catalog.find(&"fire_forge").dev_hint, "A start option has no hint")
		forge.button_pressed = false
		_check(settings.dev_start.is_empty(), "Turning the option off did not go back to a random map")
	else:
		_check(false, "The developer menu has no forge or cave start")
	panel.queue_free()
	await process_frame
	settings.dev_start = was
	if saved.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()


# --- Every map -------------------------------------------------------------------------

func _extends(script: Script, path: String) -> bool:
	while script != null:
		if script.resource_path == path:
			return true
		script = script.get_base_script()
	return false


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
