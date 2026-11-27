class_name NelvarAbilityBar
extends Control
## The player's four abilities as squares in a row, framed like the HP bar.
## An ability on cooldown darkens and shows the whole seconds left in the
## middle; one in use (flight in the air) is dark without a number.

const ART_PIXEL := 3.0
## Ability id (see NelvarPlayer.ability_cooldown_left) and its icon.
const ABILITIES: Array[StringName] = [&"primary", &"wave", &"flight", &"compression"]
const ICONS: Array[Texture2D] = [
	preload("res://assets/textures/ui/ability_primary.png"),
	preload("res://assets/textures/ui/ability_wave.png"),
	preload("res://assets/textures/ui/ability_flight.png"),
	preload("res://assets/textures/ui/ability_compression.png"),
]
## Icons are 24x24 art pixels, stored already scaled by ICON_SCALE
## (see tools/gen_ui.py) and drawn 1:1.
const ICON_SCALE := 2.0
const ICON_SIZE := 24.0 * ICON_SCALE
## One square: frame + one-pixel gap (UI art pixels) around the icon.
const SQUARE := ICON_SIZE + ART_PIXEL * 4.0
const GAP := 12.0
const FONT_SIZE := 33

@export var player: NelvarPlayer
@export var frame_color := Color.WHITE
@export var back_color := Color(0.05, 0.06, 0.08, 0.75)
@export var dim_color := Color(0.3, 0.3, 0.36)
@export var text_color := Color.WHITE

## Last drawn state per ability: -1 ready, 0 dark without a number, n seconds.
var _shown: Array[int] = [-1, -1, -1, -1]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(SQUARE * ABILITIES.size() + GAP * (ABILITIES.size() - 1), SQUARE)
	if player == null:
		push_warning("Панели способностей не назначен игрок.")
		set_process(false)


func _process(_delta: float) -> void:
	var changed := false
	for i in ABILITIES.size():
		var state := _state(ABILITIES[i])
		if state != _shown[i]:
			_shown[i] = state
			changed = true
	if changed:
		queue_redraw()


func _state(ability: StringName) -> int:
	if player.is_ability_active(ability):
		return 0
	var left := player.ability_cooldown_left(ability)
	return ceili(left) if left > 0.0 else -1


func _draw() -> void:
	var font := get_theme_font("font", "Label")
	for i in ABILITIES.size():
		var rect := Rect2(Vector2((SQUARE + GAP) * i, 0.0), Vector2(SQUARE, SQUARE))
		draw_rect(rect, back_color)
		draw_rect(rect.grow(-ART_PIXEL / 2.0), frame_color, false, ART_PIXEL)
		var state := _shown[i]
		var icon_rect := rect.grow(-ART_PIXEL * 2.0)
		draw_texture_rect(ICONS[i], icon_rect, false, Color.WHITE if state < 0 else dim_color)
		if state > 0:
			var text := str(state)
			var baseline := rect.get_center().y \
				+ (font.get_ascent(FONT_SIZE) - font.get_descent(FONT_SIZE)) / 2.0
			var origin := Vector2(rect.position.x, baseline)
			# One-pixel dark shadow, as on the HP bar.
			draw_string(font, origin + Vector2(0.0, ART_PIXEL), text, HORIZONTAL_ALIGNMENT_CENTER,
				SQUARE, FONT_SIZE, Color(0.0, 0.0, 0.0, 0.6))
			draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, SQUARE, FONT_SIZE, text_color)
