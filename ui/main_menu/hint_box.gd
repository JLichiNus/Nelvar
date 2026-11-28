class_name NelvarHintBox
extends PanelContainer
## The hint of the settings row under the cursor or in focus, in its own
## frame beside the settings panel (main menu: right of the risen logo; pause
## menu: above the panel). Fades in when a row with a hint is pointed at and
## out when none is, so no empty frame hangs on screen.
##
## NelvarPanelMorph places it and drives `reveal`: it is the last thing to
## appear when the settings open and the first to go when they close.

const FADE_TIME := 0.12
## Room for this many lines, so the frame never changes height.
const LINES := 2
const FONT_SIZE := 22
const TEXT_COLOR := Color(0.93, 0.9, 0.8)
## Slides in from the right by this much while revealed (whole art pixels).
const SLIDE := 12.0
const ART_PIXEL := 3.0

## 0..1 from the settings animation.
var reveal := 0.0:
	set(value):
		reveal = value
		_update()

var _presence := 0.0
var _tween: Tween
var _home := Vector2.ZERO
var _label: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	# In the tree: the theme's font and line spacing are known now.
	var font := _label.get_theme_font("font")
	var spacing := _label.get_theme_constant("line_spacing")
	_label.custom_minimum_size.y = font.get_height(FONT_SIZE) * LINES + spacing * (LINES - 1)
	_update()


## Height the frame needs for LINES of text; owners lay it out with this.
func frame_height() -> float:
	return _label.custom_minimum_size.y + get_theme_stylebox("panel").get_minimum_size().y


## Puts the frame in `rect` (global coordinates).
func place(rect: Rect2) -> void:
	_home = rect.position
	# The text wraps at the frame's width: a wrapping label is as tall as its
	# width makes it, and on its own it would start out 0 wide.
	var margins := get_theme_stylebox("panel").get_minimum_size()
	_label.custom_minimum_size.x = maxf(rect.size.x - margins.x, 0.0)
	size = rect.size
	_update()


func show_hint(text: String) -> void:
	if not text.is_empty():
		_label.text = text
	# An empty hint fades out with the last text still in the frame.
	_fade_to(0.0 if text.is_empty() else 1.0)


## No hint, at once (the settings are opening anew).
func clear() -> void:
	if _tween != null:
		_tween.kill()
	_presence = 0.0
	_label.text = ""
	_update()


func _fade_to(target: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_presence, _presence, target, FADE_TIME * absf(target - _presence))


func _set_presence(value: float) -> void:
	_presence = value
	_update()


func _update() -> void:
	modulate.a = reveal * _presence
	visible = modulate.a > 0.0
	var slide := snappedf(SLIDE * (1.0 - reveal), ART_PIXEL)
	global_position = _home + Vector2(slide, 0.0)
