class_name NelvarHealthBar
extends Control
## Player health: a horizontal bar in a thin white frame, green inside, with
## "current / max" in white across its middle. Sizes are whole art pixels
## (the UI is drawn at 3x).

const ART_PIXEL := 3.0
## 3x the 11 px bitmap font: one font pixel = one art pixel, so the digits
## scale as evenly as the rest of the art on non-integer window scales.
const FONT_SIZE := 33
## Label top inside the bar: puts the digits one art pixel inside the fill.
const TEXT_TOP := 3.0

@export var player: Node
@export var frame_color := Color.WHITE
@export var back_color := Color(0.05, 0.06, 0.08, 0.75)
@export var fill_color := Color(0.3, 0.82, 0.36)
@export var text_color := Color.WHITE

var _current := 0.0
var _maximum := 1.0
var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label.offset_top = TEXT_TOP
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_color", text_color)
	# A one-pixel dark shadow keeps the white text readable over the green.
	_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	_label.add_theme_constant_override("shadow_offset_x", 0)
	_label.add_theme_constant_override("shadow_offset_y", int(ART_PIXEL))
	add_child(_label)
	if player == null or not player.has_signal("health_changed"):
		push_warning("Полоске HP не назначен игрок.")
		return
	player.connect("health_changed", _on_health_changed)
	_on_health_changed(player.get("health"), player.get("max_health"))


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, back_color)
	draw_rect(rect.grow(-ART_PIXEL / 2.0), frame_color, false, ART_PIXEL)
	# Fill sits one art pixel inside the frame, snapped to whole art pixels.
	var inner := rect.grow(-ART_PIXEL * 2.0)
	var ratio := clampf(_current / _maximum, 0.0, 1.0) if _maximum > 0.0 else 0.0
	var width := ceilf(inner.size.x * ratio / ART_PIXEL) * ART_PIXEL
	if width > 0.0:
		draw_rect(Rect2(inner.position, Vector2(width, inner.size.y)), fill_color)


func _on_health_changed(current: float, maximum: float) -> void:
	_current = current
	_maximum = maximum
	_label.text = "%d / %d" % [ceili(current), roundi(maximum)]
	queue_redraw()
