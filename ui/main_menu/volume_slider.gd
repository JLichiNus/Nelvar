class_name NelvarVolumeSlider
extends Control
## One volume in the settings: its name and percent on top, a pixel bar
## below, drawn like the HUD bars (whole art pixels, white frame). Click or
## drag on the bar, or press left/right while it is focused (5% a step).
## Reads and writes GameSettings.volumes[bus].

const ART_PIXEL := 3.0
const FONT_SIZE := 22
const STEP := 0.05
const BAR_HEIGHT := 18.0
const GAP := 9.0

@export var bus: StringName = &"Master"
@export var title := "Громкость"
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
	_value = GameSettings.volume(bus)
	GameSettings.volume_changed.connect(_on_volume_changed)
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _get_minimum_size() -> Vector2:
	var font := get_theme_font("font", "Label")
	return Vector2(0.0, font.get_height(FONT_SIZE) + GAP + BAR_HEIGHT)


func value() -> float:
	return _value


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		if button.pressed:
			grab_focus()
			_set_from_x(button.position.x)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_set_from_x((event as InputEventMouseMotion).position.x)
		accept_event()
	elif event.is_action_pressed("ui_left", true):
		_set_value(_value - STEP)
		accept_event()
	elif event.is_action_pressed("ui_right", true):
		_set_value(_value + STEP)
		accept_event()


func _set_from_x(x: float) -> void:
	var bar := _bar_rect()
	_set_value((x - bar.position.x) / maxf(bar.size.x, 1.0))


# Snapped to whole steps, so the percent always reads 0, 5, 10...
func _set_value(new_value: float) -> void:
	new_value = clampf(snappedf(new_value, STEP), 0.0, 1.0)
	if is_equal_approx(new_value, _value):
		return
	_value = new_value
	GameSettings.set_volume(bus, _value)
	queue_redraw()


func _on_volume_changed(changed_bus: StringName, new_value: float) -> void:
	if changed_bus == bus and not is_equal_approx(new_value, _value):
		_value = new_value
		queue_redraw()


func _set_hovered(hovered: bool) -> void:
	_hovered = hovered
	queue_redraw()


func _bar_rect() -> Rect2:
	var top := snappedf(size.y - BAR_HEIGHT, ART_PIXEL)
	return Rect2(Vector2(0.0, top), Vector2(snappedf(size.x, ART_PIXEL), BAR_HEIGHT))


func _draw() -> void:
	var font := get_theme_font("font", "Label")
	var active := has_focus() or _hovered or _dragging
	var label_color := focus_color if active else text_color
	var baseline := font.get_ascent(FONT_SIZE)
	draw_string(font, Vector2(0.0, baseline), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		FONT_SIZE, label_color)
	var percent := "%d%%" % roundi(_value * 100.0)
	var width := font.get_string_size(percent, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	draw_string(font, Vector2(size.x - width, baseline), percent, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, FONT_SIZE, label_color)

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
