extends RefCounted
## Text styling shared by mutation cards and notices.

const GAIN_COLOR := Color(0.67, 0.91, 0.57)
const COST_COLOR := Color(1.0, 0.58, 0.56)
const MUTED_COLOR := Color(0.75, 0.79, 0.85)
## Widths of the full description's two columns.
const ABOUT_WIDTH := 378.0
const NUMBERS_WIDTH := 342.0


static func line(value: String, color: Color, font_size: int = 22) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	return label


static func add_effects(rows: VBoxContainer, mutation: NelvarMutation, stage: int) -> void:
	var description := mutation.describe(stage)
	for gain: String in description["gains"]:
		rows.add_child(line(gain, GAIN_COLOR))
	for cost: String in description["costs"]:
		rows.add_child(line(cost, COST_COLOR))


## The full description, wide and low: what the mutation is on the left
## (title, summary), its exact numbers on the right with
## `notes` under them.
static func describe(mutation: NelvarMutation, stage: int, title_color: Color,
		notes: Array[Label] = []) -> HBoxContainer:
	var columns := HBoxContainer.new()
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_theme_constant_override("separation", 30)

	var about := _column(ABOUT_WIDTH)
	columns.add_child(about)
	about.add_child(line(mutation.title, title_color, 33))
	about.add_child(_gap())
	about.add_child(line(mutation.summary, Color.WHITE))

	var numbers := _column(NUMBERS_WIDTH)
	columns.add_child(numbers)
	add_effects(numbers, mutation, stage)
	if not notes.is_empty():
		numbers.add_child(_gap())
	for note in notes:
		numbers.add_child(note)
	return columns


static func _column(width: float) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = width
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	return column


static func _gap() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = 6.0
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap
