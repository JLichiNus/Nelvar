extends SceneTree
## Every location: it builds on the shared frame (NelvarLocation) and gets the shared
## interface (ui/location_ui/location_ui.tscn) bound to its own player — health, abilities,
## level, the damage vignette, the mutations, the pause menu and the cursor of its reality,
## the info panel's title with the seed; F3 and the wheel are handled.
## Run: godot --headless --path . --script tests/test_locations.gd

const SCENES: Array[String] = [
	"res://scenes/main.tscn", "res://scenes/earth.tscn", "res://scenes/earth2.tscn",
	"res://scenes/fire.tscn", "res://scenes/fire2.tscn", "res://scenes/ice.tscn",
	"res://scenes/ice2.tscn", "res://scenes/void.tscn",
]
## Maps without a debug view on F3.
const NO_DEBUG: Array[String] = ["res://scenes/void.tscn"]
const SEED := 20261128

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path in SCENES:
		await _check_location(path)
	if _failures.is_empty():
		print("PASS: %d location checks; %d maps on the shared frame and interface." % [_checks, SCENES.size()])
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


## Untyped: the locations and their interface use autoloads, which a test cannot name at
## compile time.
func _check_location(path: String) -> void:
	var game = (load(path) as PackedScene).instantiate()
	game.set_meta("seed_override", SEED)
	root.add_child(game)
	for frame in 3:
		await process_frame
	var name := path.get_file()
	_check(_extends(game.get_script(), "res://core/location.gd"), "%s is not a NelvarLocation" % name)
	_check(game.world_seed == SEED, "%s did not take the seed" % name)
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
	_check(game.show_debug == not NO_DEBUG.has(path), "%s: F3 does not toggle the debug view as it should" % name)
	var zoom: Vector2 = player.camera.zoom
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	game._unhandled_input(wheel)
	_check(player.camera.zoom != zoom, "%s: the wheel does not zoom" % name)
	game.queue_free()
	await process_frame
	await process_frame


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
