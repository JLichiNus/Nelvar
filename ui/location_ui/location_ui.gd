class_name NelvarLocationUI
extends Node
## Everything a location shows over the world, the same on every map: health, abilities
## and level, the damage vignette, the mutations (NelvarMutationHud), the pause menu, the
## reality's cursor, the info panel (seed, status, controls; F12) and the messages.
##
## NelvarLocation sets `player`, `reality` and `controls` in its _enter_tree, before any of
## the widgets below are ready, so they all bind to the location's own player.

const MESSAGE_FADE := 0.6

var player: NelvarPlayer
var reality: NelvarMenuElement
## The info panel's controls line: what this map's keys do.
var controls := ""

var _message_tween: Tween

@onready var info_panel: Control = $HUD/Margin/Stack/Panel
@onready var seed_label: Label = $HUD/Margin/Stack/Panel/Padding/Rows/Seed
@onready var status_label: Label = $HUD/Margin/Stack/Panel/Padding/Rows/Status
@onready var controls_label: Label = $HUD/Margin/Stack/Panel/Padding/Rows/Controls
@onready var message: Label = $HUD/Message


func _enter_tree() -> void:
	for path: NodePath in [^"HUD/DamageVignette", ^"HUD/HealthBar", ^"HUD/AbilityBar", ^"HUD/LevelLine",
			^"MutationHud"]:
		get_node(path).set(&"player", player)
	(get_node(^"PauseMenu") as NelvarPauseMenu).reality = reality
	if reality != null:
		(get_node(^"LocationCursor") as NelvarLocationCursor).cursor = reality.cursor


func _ready() -> void:
	info_panel.visible = GameSettings.show_info_panel
	GameSettings.info_panel_changed.connect(info_panel.set_visible)
	controls_label.text = controls
	message.modulate.a = 0.0
	if reality != null:
		seed_label.add_theme_color_override(&"font_color", reality.hud_color)
		message.add_theme_color_override(&"font_color", reality.message_color)
		message.add_theme_color_override(&"font_outline_color", reality.message_outline)


## A line over the game: fades in, holds `hold` seconds, fades out.
func say(text: String, hold: float) -> void:
	if _message_tween != null:
		_message_tween.kill()
	message.text = text
	_message_tween = create_tween()
	_message_tween.tween_property(message, "modulate:a", 1.0, MESSAGE_FADE)
	_message_tween.tween_interval(hold)
	_message_tween.tween_property(message, "modulate:a", 0.0, MESSAGE_FADE)


## The map could not be built: the error stays on the panel even if it is turned off.
func show_error(text: String) -> void:
	seed_label.text = text
	status_label.text = "Ошибка генерации. Подробности в Output."
	info_panel.show()
