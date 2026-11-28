class_name NelvarMutationIcon
extends Control
## A received mutation as a small pixel tile: the first letter of its name,
## a frame in the colour of the version that picked its latest stage, a mark
## of its layer in the corner and one pip per stage. With `hint` on, the tile
## takes the mouse so its owner can show build_hint() on mouse_entered.

const ART_PIXEL := 3.0
const SIDE := 42.0
const FONT_SIZE := 22
const HINT_FONT_SIZE := 33
const BACK := Color(0.05, 0.06, 0.08, 0.82)
const EDGE := Color(0.02, 0.03, 0.05, 0.9)
const MutationText := preload("res://ui/mutations/mutation_text.gd")

## Take the mouse for a hover hint.
@export var hint := true
## Tile side and letter size; a bigger tile keeps the letter's font pixel
## equal to the art pixel with font_size = 33 (3x the 11 px font).
@export var side := SIDE
@export var font_size := FONT_SIZE

var mutation: NelvarMutation
var stage := 1
## Who picked each stage (NelvarMutation.Version or SPONTANEOUS).
var owners: Array[int] = []


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func setup(entry_mutation: NelvarMutation, entry_stage: int, entry_owners: Array) -> void:
	mutation = entry_mutation
	stage = entry_stage
	owners.assign(entry_owners)
	custom_minimum_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_PASS if hint else Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func owner_color() -> Color:
	if owners.is_empty():
		return Color.WHITE
	return NelvarMutation.version_color(owners[-1])


func _draw() -> void:
	if mutation == null:
		return
	var rect := Rect2(Vector2.ZERO, Vector2(side, side))
	var color := owner_color()
	draw_rect(rect.grow(ART_PIXEL), EDGE)
	draw_rect(rect, BACK)
	draw_rect(rect.grow(-ART_PIXEL / 2.0), color, false, ART_PIXEL)
	_draw_layer_mark(color)
	# Stage pips along the bottom edge.
	for i in stage:
		var pip := Vector2(ART_PIXEL * 3.0 + i * ART_PIXEL * 2.0, side - ART_PIXEL * 3.0)
		draw_rect(Rect2(pip, Vector2.ONE * ART_PIXEL), color)
	var font := get_theme_font("font", "Label")
	var letter := mutation.title.left(1)
	var width := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := side / 2.0 + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	var origin := Vector2(snappedf((side - width) / 2.0, ART_PIXEL), snappedf(baseline, ART_PIXEL))
	draw_string(font, origin + Vector2(0.0, ART_PIXEL), letter, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, font_size, EDGE)
	draw_string(font, origin, letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color.WHITE)


# Top-right corner: a dot for body, a bar for ability, a cross for rule.
func _draw_layer_mark(color: Color) -> void:
	var corner := Vector2(side - ART_PIXEL * 4.0, ART_PIXEL * 2.0)
	var cells: Array[Vector2] = []
	match mutation.layer:
		NelvarMutation.Layer.STATS:
			cells = [Vector2(1, 1)]
		NelvarMutation.Layer.ABILITY:
			cells = [Vector2(0, 1), Vector2(1, 1), Vector2(2, 1)]
		NelvarMutation.Layer.RULE:
			cells = [Vector2(0, 0), Vector2(2, 0), Vector2(1, 1), Vector2(0, 2), Vector2(2, 2)]
	for cell in cells:
		draw_rect(Rect2(corner + cell * ART_PIXEL, Vector2.ONE * ART_PIXEL), color)


## The hover hint's content: name and the one-line summary.
func build_hint() -> Control:
	if mutation == null:
		return null
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	# 3x the 11 px bitmap font: one font pixel = one art pixel, so the text
	# scales as evenly as the rest of the art on non-integer window scales.
	rows.add_child(MutationText.line(mutation.title, owner_color(), HINT_FONT_SIZE))
	rows.add_child(MutationText.line(mutation.summary, Color.WHITE, HINT_FONT_SIZE))
	# The hint takes the content's minimum size: wrapped labels would make
	# it as tall as one word per line.
	for label: Label in rows.get_children():
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return rows
