class_name NelvarSlider
extends Control
## One settings row with a number: its name on the left, a pixel bar and the
## value on the right, drawn like the HUD bars (whole art pixels, white
## frame). The value runs from `min_value` to `max_value` (0..1 shown as a
## percent by default; `percent` off shows the number with `suffix`). Click
## or drag on the bar, turn the mouse wheel over the row, or press left/right
## while it is focused; every way moves by whole `step`s. Emits
## `value_changed` only for the player's changes; `set_value_no_signal` shows
## a value set elsewhere.

signal value_changed(value: float)

const ART_PIXEL := 3.0
const FONT_SIZE := 22
const BAR_HEIGHT := 18.0
## Widest the bar gets; narrower rows give it 45% of their width.
const BAR_WIDTH := 330.0
## Same height as a CheckButton row (theme: 6 above and below the text).
const PADDING := 6.0

@export var title := ""
@export var min_value := 0.0
@export var max_value := 1.0
## One click of the wheel or one arrow press; the value always stays
## `min_value` plus a whole number of steps.
@export var step := 0.01
## On: 0..1 reads "0%".."100%". Off: the number itself, with `suffix`.
@export var percent := true
@export var suffix := ""
## Shown instead of the number at the ends of the range when set (e.g.
## "выкл." at 0, "Без ограничения" at the top).
@export var min_text := ""
@export var max_text := ""
## Column right of the bar for the value, the same for every slider so the
## bars line up; wide enough for the longest text ("Без ограничения").
const VALUE_WIDTH := 201.0
## Between the bar and its value.
const VALUE_GAP := 15.0
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
	_value = clampf(new_value, min_value, max_value)
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
	var share := (x - bar.position.x) / maxf(bar.size.x, 1.0)
	_set_value(lerpf(min_value, max_value, share))


# Snapped to whole steps from `min_value`.
func _set_value(new_value: float) -> void:
	var steps := roundf((new_value - min_value) / step)
	# Fractional steps are divided rather than multiplied back, so 97 steps of
	# 0.01 are exactly 0.97 and not 0.9700000000000001 in the settings file.
	var offset := steps / roundf(1.0 / step) if step < 1.0 else steps * step
	new_value = clampf(min_value + offset, min_value, max_value)
	if is_equal_approx(new_value, _value):
		return
	_value = new_value
	queue_redraw()
	value_changed.emit(_value)


func _set_hovered(hovered: bool) -> void:
	_hovered = hovered
	queue_redraw()


func _value_text() -> String:
	if is_equal_approx(_value, min_value) and not min_text.is_empty():
		return min_text
	if is_equal_approx(_value, max_value) and not max_text.is_empty():
		return max_text
	if percent:
		return "%d%%" % roundi(_value * 100.0)
	return "%d%s" % [roundi(_value), suffix]


## 0..1: how far along the range the value is.
func _share() -> float:
	return clampf((_value - min_value) / maxf(max_value - min_value, 0.0001), 0.0, 1.0)


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
	var bar := _bar_rect()
	draw_string(font, Vector2(bar.end.x + VALUE_GAP, baseline), _value_text(),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, label_color)

	draw_rect(bar, back_color)
	draw_rect(bar.grow(-ART_PIXEL / 2.0), focus_color if active else frame_color, false, ART_PIXEL)
	var inner := bar.grow(-ART_PIXEL * 2.0)
	var fill := snappedf(inner.size.x * _share(), ART_PIXEL)
	if fill > 0.0:
		draw_rect(Rect2(inner.position, Vector2(fill, inner.size.y)), fill_color)
	# A notch where the value is, so even 0% shows where the handle sits.
	var notch_x := inner.position.x + clampf(fill - ART_PIXEL, 0.0, inner.size.x - ART_PIXEL)
	draw_rect(Rect2(Vector2(notch_x, bar.position.y), Vector2(ART_PIXEL, bar.size.y)),
		focus_color if active else frame_color)
