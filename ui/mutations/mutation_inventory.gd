class_name NelvarMutationInventory
extends PanelContainer
## The pause menu's inventory: every received mutation with its full
## description — exact gains and costs at the stage reached, its layer and
## which version picked each stage.

const MutationText := preload("res://ui/mutations/mutation_text.gd")
const WIDTH := 1080.0
const LIST_HEIGHT := 480.0
const ENTRY_WIDTH := 498.0

var back_button: Button

var _info: Label
var _list: GridContainer
var _empty: Label
var _scroll: ScrollContainer


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 0.0)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	add_child(rows)

	var header := Label.new()
	header.text = "Инвентарь"
	header.add_theme_font_size_override("font_size", 33)
	rows.add_child(header)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0.0, 3.0)
	rule.color = NelvarMutation.version_color(NelvarMutation.Version.AIR)
	rows.add_child(rule)
	_info = MutationText.line("", MutationText.MUTED_COLOR)
	rows.add_child(_info)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0.0, LIST_HEIGHT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	rows.add_child(_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(content)
	_empty = MutationText.line(
		"Мутаций пока нет. Шкала адаптации над уровнем копится от ран, убийств и времени.",
		MutationText.MUTED_COLOR)
	content.add_child(_empty)
	_list = GridContainer.new()
	_list.columns = 2
	_list.add_theme_constant_override("h_separation", 24)
	_list.add_theme_constant_override("v_separation", 21)
	content.add_child(_list)

	back_button = Button.new()
	back_button.text = "Назад"
	back_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back_button.add_theme_font_size_override("font_size", 33)
	rows.add_child(back_button)


## Fills the panel from `director` (null: nothing to show).
func refresh(director: NelvarMutationDirector) -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var entries: Array[Dictionary] = director.owned() if director != null else []
	_empty.visible = entries.is_empty()
	if director != null:
		_info.text = "Получено мутаций: %d   ·   твой выбор — %d%% следующих" % [
			director.mutation_count, roundi(director.player_share() * 100.0)]
	else:
		_info.text = ""
	for entry in entries:
		_list.add_child(_entry(entry, director.player_version))
	_scroll.scroll_vertical = 0


func _entry(entry: Dictionary, player_version: int) -> Control:
	var mutation: NelvarMutation = entry["mutation"]
	var stage: int = entry["stage"]
	var owners: Array = entry["owners"]
	var box := HBoxContainer.new()
	box.custom_minimum_size = Vector2(ENTRY_WIDTH, 0.0)
	box.add_theme_constant_override("separation", 15)

	var icon := NelvarMutationIcon.new()
	icon.hint = false
	icon.setup(mutation, stage, owners)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.add_child(icon)

	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 3)
	box.add_child(rows)
	var title := "%s %s" % [mutation.title, NelvarMutation.stage_name(stage)]
	if stage < mutation.max_stage:
		title += "  (из %s)" % NelvarMutation.stage_name(mutation.max_stage)
	rows.add_child(MutationText.line(title, icon.owner_color(), 27))
	var picks := PackedStringArray()
	for i in owners.size():
		var owner: int = owners[i]
		var who := "ты" if owner == player_version else NelvarMutation.version_name(owner)
		picks.append("%s — %s" % [NelvarMutation.stage_name(i + 1), who] if owners.size() > 1 else who)
	rows.add_child(MutationText.line("%s   ·   выбор: %s" % [
		NelvarMutation.LAYER_NAMES[mutation.layer], ", ".join(picks)], MutationText.MUTED_COLOR))
	rows.add_child(MutationText.line(mutation.summary, Color.WHITE))
	MutationText.add_effects(rows, mutation, stage)
	return box
