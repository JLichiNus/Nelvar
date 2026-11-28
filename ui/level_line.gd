class_name NelvarLevelLine
extends Control
## Player level above the HP bar: a thin white line with a gap in the middle
## holding "3 ур.". The line also shows kills toward the next level: the
## earned part is solid white, the rest faint.

const ART_PIXEL := 3.0
## 3x the 11 px bitmap font, so a font pixel matches an art pixel.
const FONT_SIZE := 33
## Space between the line and the text in the gap.
const TEXT_PADDING := 9.0

@export var player: NelvarPlayer
@export var line_color := Color.WHITE
@export var rest_color := Color(1.0, 1.0, 1.0, 0.35)
@export var text_color := Color.WHITE
## Dark edge around the line and the text so they read over white clouds too.
@export var edge_color := Color(0.05, 0.06, 0.08, 0.7)

var _level := 1
var _progress := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if player == null:
		push_warning("Строке уровня не назначен игрок.")
		return
	player.level_changed.connect(_on_level_changed)
	_on_level_changed(player.level, player.level_kills, player.kills_to_next_level())


func _on_level_changed(level: int, kills: int, kills_needed: int) -> void:
	_level = level
	_progress = clampf(float(kills) / kills_needed, 0.0, 1.0) if kills_needed > 0 else 0.0
	queue_redraw()


func _draw() -> void:
	var font := get_theme_font("font", "Label")
	var text := "%d ур." % _level
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var gap_half := snappedf(text_width / 2.0 + TEXT_PADDING, ART_PIXEL)
	var center := snappedf(size.x / 2.0, ART_PIXEL)
	var line_y := snappedf(size.y / 2.0 - ART_PIXEL / 2.0, ART_PIXEL)
	var filled := snappedf(size.x * _progress, ART_PIXEL)
	# Left and right pieces of the line, each split into earned and remaining.
	for piece in [Vector2(0.0, center - gap_half), Vector2(center + gap_half, size.x)]:
		if piece.y > piece.x:
			draw_rect(Rect2(piece.x - ART_PIXEL, line_y - ART_PIXEL, piece.y - piece.x + ART_PIXEL * 2.0,
				ART_PIXEL * 3.0), edge_color)
		var split := clampf(filled, piece.x, piece.y)
		if split > piece.x:
			draw_rect(Rect2(piece.x, line_y, split - piece.x, ART_PIXEL), line_color)
		if piece.y > split:
			draw_rect(Rect2(split, line_y, piece.y - split, ART_PIXEL), rest_color)
	var baseline := size.y / 2.0 + (font.get_ascent(FONT_SIZE) - font.get_descent(FONT_SIZE)) / 2.0
	var origin := Vector2(0.0, baseline)
	for offset in [Vector2(-ART_PIXEL, 0.0), Vector2(ART_PIXEL, 0.0), Vector2(0.0, -ART_PIXEL),
			Vector2(0.0, ART_PIXEL)]:
		draw_string(font, origin + offset, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, FONT_SIZE, edge_color)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, FONT_SIZE, text_color)
