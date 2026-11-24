extends RefCounted
## Text styling shared by mutation cards and notices.

const GAIN_COLOR := Color(0.67, 0.91, 0.57)
const COST_COLOR := Color(1.0, 0.58, 0.56)
const MUTED_COLOR := Color(0.75, 0.79, 0.85)


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
