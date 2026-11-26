class_name NelvarOptionRow
extends Control
## A settings row that picks one of a few values: the name on the left,
## "< value >" on the right, drawn with pixel arrows (whole art pixels).
## Left/right while focused step through the values (no wrap-around); Enter
## or a click on the row moves to the next one (wrapping); a click on an
## arrow steps that way. Same height and focus frame as a CheckButton row.

signal index_changed(index: int)

const ART_PIXEL := 3.0
const FONT_SIZE := 22
## Same as the theme's CheckButton content margins.
const PADDING := 6.0
## Space for the value between the arrows; the widest value must fit.
const VALUE_WIDTH := 168.0
## Arrow: a pixel triangle ARROW_LENGTH art pixels long, 2 * ARROW_LENGTH - 1 tall.
const ARROW_LENGTH := 3

@export var title := ""
@export var options: PackedStringArray = []
@export var text_color := Color(0.93, 0.9, 0.8)
@export var focus_color := Color.WHITE
@export var dim_color := Color(0.62, 0.58, 0.54)

var index := 0:
	set(value):
		index = clampi(value, 0, maxi(options.size() - 1, 0))
		queue_redraw()

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
	var arrows := _arrow_width() * 2.0 + VALUE_WIDTH
	var label := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	return Vector2(label + arrows + PADDING * 4.0, font.get_height(FONT_SIZE) + PADDING * 2.0)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
		grab_focus()
		var value_box := _value_rect()
		if button.position.x < value_box.position.x and button.position.x >= _left_arrow_x():
			_step(-1, false)
		elif button.position.x >= value_box.end.x:
			_step(1, false)
		else:
			_step(1, true)
		accept_event()
	elif event.is_action_pressed("ui_left", true):
		_step(-1, false)
		accept_event()
	elif event.is_action_pressed("ui_right", true):
		_step(1, false)
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		_step(1, true)
		accept_event()


func _step(direction: int, wrap: bool) -> void:
	if options.is_empty():
		return
	var next := index + direction
	if wrap:
		next = posmod(next, options.size())
	next = clampi(next, 0, options.size() - 1)
	if next == index:
		return
	index = next
	index_changed.emit(index)


func _set_hovered(hovered: bool) -> void:
	_hovered = hovered
	queue_redraw()


func _arrow_width() -> float:
	return ARROW_LENGTH * ART_PIXEL


func _value_rect() -> Rect2:
	var right := size.x - PADDING - _arrow_width() - ART_PIXEL * 2.0
	return Rect2(Vector2(right - VALUE_WIDTH, 0.0), Vector2(VALUE_WIDTH, size.y))


func _left_arrow_x() -> float:
	return _value_rect().position.x - ART_PIXEL * 2.0 - _arrow_width()


func _draw() -> void:
	if has_focus():
		get_theme_stylebox("focus", "CheckButton").draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	var font := get_theme_font("font", "Label")
	var active := has_focus() or _hovered
	var color := focus_color if active else text_color
	var baseline := (size.y - font.get_height(FONT_SIZE)) / 2.0 + font.get_ascent(FONT_SIZE)
	draw_string(font, Vector2(PADDING, baseline), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		FONT_SIZE, color)
	if options.is_empty():
		return
	var box := _value_rect()
	draw_string(font, Vector2(box.position.x, baseline), options[index],
		HORIZONTAL_ALIGNMENT_CENTER, box.size.x, FONT_SIZE, color)
	var at_start := index == 0
	var at_end := index == options.size() - 1
	_draw_arrow(_left_arrow_x(), -1, dim_color if at_start else color)
	_draw_arrow(box.end.x + ART_PIXEL * 2.0, 1, dim_color if at_end else color)


## A pixel triangle starting at `x`, pointing left (-1) or right (1).
func _draw_arrow(x: float, direction: int, color: Color) -> void:
	var rows := ARROW_LENGTH * 2 - 1
	var top := snappedf((size.y - rows * ART_PIXEL) / 2.0, ART_PIXEL)
	x = snappedf(x, ART_PIXEL)
	for row in rows:
		var length := ARROW_LENGTH - absi(row - (ARROW_LENGTH - 1))
		var start := x if direction > 0 else x + (ARROW_LENGTH - length) * ART_PIXEL
		draw_rect(Rect2(start, top + row * ART_PIXEL, length * ART_PIXEL, ART_PIXEL), color)
