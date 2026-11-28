class_name NelvarLocation
extends Node2D
## One map of a reality: what every map does the same way, so the maps themselves only
## build and run their own world (_build()).
##
## A location scene has the player at Actors/Player (an EnemySpawner beside it, if the
## map has enemies) and the shared interface at Interface (ui/location_ui/location_ui.tscn:
## HUD, mutations, pause, cursor). This class wires the interface to the player and the
## reality before anything is ready, starts the reality's music, picks the seed, and
## handles the keys all maps share: the mouse wheel zooms, F3 toggles the map's debug view
## (_set_debug()).

const ZOOM_STEP := 1.15

## The reality this map belongs to: colours, cursor, pause menu, music (its id).
@export var reality: NelvarMenuElement
## The info panel's title, before the seed: "ЛЁД 2 · ПЕЩЕРА".
@export var title := ""
## The info panel's controls line: what the keys do on this map.
@export_multiline var controls := ""
## Seconds a message (say()) stays up.
@export var message_hold := 3.0

## This visit's seed (_pick_seed()), set before _build().
var world_seed := 0
## F3 view on.
var show_debug := false
## The interface's message line (the tests read it) and the info panel's status line.
var message: Label:
	get:
		return ui.message
var status_label: Label:
	get:
		return ui.status_label

@onready var player: NelvarPlayer = $Actors/Player
@onready var enemy_spawner: NelvarEnemySpawner = get_node_or_null(^"Actors/EnemySpawner")
@onready var ui: NelvarLocationUI = $Interface


func _enter_tree() -> void:
	var interface := get_node(^"Interface") as NelvarLocationUI
	interface.player = get_node(^"Actors/Player") as NelvarPlayer
	interface.reality = reality
	interface.controls = controls


func _ready() -> void:
	if reality != null and GameMusic.PLAYLISTS.has(reality.id):
		GameMusic.start(reality.id)
	else:
		GameMusic.stop()
	world_seed = _pick_seed()
	_build()


## Builds and starts the map for world_seed. On a generation failure: fail().
func _build() -> void:
	pass


## A fresh random seed; `--seed=N` after `--` on the command line reproduces a map, and
## the tests set the meta `seed_override` before the scene enters the tree.
func _pick_seed() -> int:
	if has_meta("seed_override"):
		return get_meta("seed_override")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			var value := argument.trim_prefix("--seed=")
			if value.is_valid_int():
				return value.to_int()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return int(rng.randi())


## The map could not be built (`what`: "Пещера не сложилась"): the error is shown and the
## player stands still.
func fail(what: String) -> void:
	ui.show_error("%s · сид %d" % [what, world_seed])
	player.set_physics_process(false)
	player.set_process(false)


## The info panel's title with the seed.
func show_seed() -> void:
	ui.seed_label.text = "%s · СИД %d" % [title, world_seed]


func set_status(text: String) -> void:
	ui.status_label.text = text


## A line over the game (a hint after a fall, a warning): `hold` seconds, message_hold if
## not given.
func say(text: String, hold := -1.0) -> void:
	ui.say(text, hold if hold >= 0.0 else message_hold)


## F3: the map shows (or hides) its colliders and outlines. False if the map has no debug
## view (the key is left to others).
func _set_debug(_shown: bool) -> bool:
	return false


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		show_debug = not show_debug
		if _set_debug(show_debug):
			get_viewport().set_input_as_handled()
		else:
			show_debug = false
		return
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			player.adjust_zoom(ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			player.adjust_zoom(1.0 / ZOOM_STEP)
			get_viewport().set_input_as_handled()
