class_name NelvarSlider
extends Control
## One settings row with a value from 0 to 1: its name on the left, a pixel
## bar and the value in percent on the right, drawn like the HUD bars (whole
## art pixels, white frame). Click or drag on the bar, turn the mouse wheel
## over the row, or press left/right while it is focused; every way moves by
## whole `step`s. Emits `value_changed` only for the player's changes;
## `set_value_no_signal` shows a value set elsewhere.

signal value_changed(value: float)

const ART_PIXEL := 3.0
const FONT_SIZE := 22
const BAR_HEIGHT := 18.0
## Widest the bar gets; narrower rows give it 45% of their width.
const BAR_WIDTH := 330.0
## Column right of the bar for the value ("100%", "выкл.").
const VALUE_WIDTH := 72.0
## Same height as a CheckButton row (theme: 6 above and below the text).
const PADDING := 6.0

@export var title := ""
## One click of the wheel or one arrow press; the value always stays a whole
## number of steps.
@export_range(0.01, 1.0, 0.01) var step := 0.01
## Shown instead of "0%" when set.
@export var zero_text := ""
@export var text_color := Color(0.93, 0.9, 0.8)
@export var frame_color := Color(0.93, 0.9, 0.8)
@export var focus_color := Color.WHITE
@export var back_color := Color(0.05, 0.06, 0.08, 0.75)
@export var fill_color := Color(0.64, 0.9, 1.0)

var _value := 1.0
var _dragging := false
var _hovered := false


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _get_minimum_size() -> Vector2:
	var font := get_theme_font("font", "Label")
	return Vector2(0.0, maxf(font.get_height(FONT_SIZE), BAR_HEIGHT) + PADDING * 2.0)


func value() -> float:
	return _value


func set_value_no_signal(new_value: float) -> void:
	_value = clampf(new_value, 0.0, 1.0)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_RIGHT,
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT]:
		# Up/right is more. Taken even at 0% or 100%, so the page behind
		# does not scroll away from under the cursor.
		var more := button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_RIGHT]
		_set_value(_value + (step if more else -step))
		accept_event()
	elif button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		if button.pressed:
			grab_focus()
			_set_from_x(button.position.x)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_set_from_x((event as InputEventMouseMotion).position.x)
		accept_event()
	elif event.is_action_pressed("ui_left", true):
		_set_value(_value - step)
		accept_event()
	elif event.is_action_pressed("ui_right", true):
		_set_value(_value + step)
		accept_event()


func _set_from_x(x: float) -> void:
	var bar := _bar_rect()
	_set_value((x - bar.position.x) / maxf(bar.size.x, 1.0))


# Snapped to whole steps, so the percent always reads a multiple of the step.
func _set_value(new_value: float) -> void:
	# Divided rather than multiplied back, so 97 steps of 0.01 are exactly
	# 0.97 and not 0.9700000000000001 in the settings file.
	new_value = clampf(roundf(new_value / step) / roundf(1.0 / step), 0.0, 1.0)
	if is_equal_approx(new_value, _value):
		return
	_value = new_value
	queue_redraw()
	value_changed.emit(_value)


func _set_hovered(hovered: bool) -> void:
	_hovered = hovered
	queue_redraw()


func _value_text() -> String:
	if _value <= 0.0 and not zero_text.is_empty():
		return zero_text
	return "%d%%" % roundi(_value * 100.0)


func _bar_rect() -> Rect2:
	var width := snappedf(minf(BAR_WIDTH, size.x * 0.45), ART_PIXEL)
	var left := snappedf(size.x - VALUE_WIDTH - width, ART_PIXEL)
	var top := snappedf((size.y - BAR_HEIGHT) / 2.0, ART_PIXEL)
	return Rect2(Vector2(left, top), Vector2(width, BAR_HEIGHT))


func _draw() -> void:
	var font := get_theme_font("font", "Label")
	var active := has_focus() or _hovered or _dragging
	var label_color := focus_color if active else text_color
	var baseline := (size.y - font.get_height(FONT_SIZE)) / 2.0 + font.get_ascent(FONT_SIZE)
	draw_string(font, Vector2(PADDING, baseline), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		FONT_SIZE, label_color)
	var text := _value_text()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	draw_string(font, Vector2(size.x - width - PADDING, baseline), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, label_color)

	var bar := _bar_rect()
	draw_rect(bar, back_color)
	draw_rect(bar.grow(-ART_PIXEL / 2.0), focus_color if active else frame_color, false, ART_PIXEL)
	var inner := bar.grow(-ART_PIXEL * 2.0)
	var fill := snappedf(inner.size.x * _value, ART_PIXEL)
	if fill > 0.0:
		draw_rect(Rect2(inner.position, Vector2(fill, inner.size.y)), fill_color)
	# A notch where the value is, so even 0% shows where the handle sits.
	var notch_x := inner.position.x + clampf(fill - ART_PIXEL, 0.0, inner.size.x - ART_PIXEL)
	draw_rect(Rect2(Vector2(notch_x, bar.position.y), Vector2(ART_PIXEL, bar.size.y)),
		focus_color if active else frame_color)
