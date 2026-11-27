class_name NelvarMutationInventory
extends PanelContainer
## The pause menu's inventory: a long, low grid of the received mutations'
## tiles. Pointing at a tile (or moving the keyboard focus onto it) shows a
## card under the plate with the full description — what the mutation is, its exact
## gains and costs at the stage reached, its layer and who picked each stage.
##
## The card is drawn inside the panel rather than as Godot's tooltip, as in
## the HUD strip: a tooltip waits before it appears and lives in its own
## popup window, where the pixel font is filtered smoothly and looks blurry.

const MutationText := preload("res://ui/mutations/mutation_text.gd")
## Long and low: 21 mutations fit in two rows.
const COLUMNS := 11
## 21 art pixels; with the 3x font the letter's pixels match the art's.
const TILE_SIDE := 63.0
const TILE_FONT_SIZE := 33
const TILE_GAP := 12
## Room around a tile for the focus frame.
const SLOT_PADDING := 6.0
## Space between the plate and the card, and the card's distance from screen edges.
const CARD_OFFSET := 12.0

var back_button: Button

var _info: Label
var _grid: GridContainer
var _empty: Label
var _card: PanelContainer
var _player_version := NelvarMutation.Version.AIR
var _hovered: Button
var _shown: Button


func _init() -> void:
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	# A full row of tiles sets the panel's width, however few there are.
	rows.custom_minimum_size.x = _grid_width(COLUMNS)
	add_child(rows)

	# The title on the left, the counts on the right of the same line.
	var top := HBoxContainer.new()
	rows.add_child(top)
	var header := Label.new()
	header.text = "Инвентарь"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_font_size_override("font_size", 33)
	top.add_child(header)
	_info = MutationText.line("", MutationText.MUTED_COLOR)
	_info.autowrap_mode = TextServer.AUTOWRAP_OFF
	_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_info)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0.0, 3.0)
	rule.color = NelvarMutation.version_color(NelvarMutation.Version.AIR)
	rows.add_child(rule)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", TILE_GAP)
	_grid.add_theme_constant_override("v_separation", TILE_GAP)
	rows.add_child(_grid)
	_empty = MutationText.line(
		"Мутаций пока нет. Шкала адаптации над уровнем копится от ран, убийств и времени.",
		MutationText.MUTED_COLOR)
	rows.add_child(_empty)

	back_button = Button.new()
	back_button.text = "Назад"
	back_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back_button.add_theme_font_size_override("font_size", 33)
	rows.add_child(back_button)

	_card = PanelContainer.new()
	# Out of the panel's layout, but still inheriting its theme. A top-level
	# item does not inherit the texture filter, so the nearest filter that
	# keeps the pixel font sharp is set on it directly.
	_card.top_level = true
	_card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	add_child(_card)
	visibility_changed.connect(func() -> void:
		if not visible:
			_hovered = null
			_show_card(null))


## Fills the panel from `director` (null: nothing to show).
func refresh(director: NelvarMutationDirector) -> void:
	_hovered = null
	_show_card(null)
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var entries: Array[Dictionary] = director.owned() if director != null else []
	_empty.visible = entries.is_empty()
	_grid.visible = not entries.is_empty()
	if director != null:
		_player_version = director.player_version
		_info.text = "Мутаций: %d   ·   выбираешь ты: %d%%" % [
			director.mutation_count, roundi(director.player_share() * 100.0)]
	else:
		_info.text = ""
	for entry in entries:
		_grid.add_child(_slot(entry))


## The tile the card is about (null when hidden).
func shown_slot() -> Button:
	return _shown if _card.visible else null


func _grid_width(columns: int) -> float:
	return columns * (TILE_SIDE + SLOT_PADDING * 2.0) + (columns - 1) * TILE_GAP


# A flat button around the tile: it takes the mouse and the keyboard focus,
# and its focus frame marks the selected tile.
func _slot(entry: Dictionary) -> Button:
	var slot := Button.new()
	slot.custom_minimum_size = Vector2.ONE * (TILE_SIDE + SLOT_PADDING * 2.0)
	for state in ["normal", "disabled"]:
		slot.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var lit := StyleBoxFlat.new()
	lit.bg_color = Color(1.0, 1.0, 1.0, 0.1)
	for state in ["hover", "pressed", "hover_pressed"]:
		slot.add_theme_stylebox_override(state, lit)
	slot.set_meta(&"entry", entry)

	var icon := NelvarMutationIcon.new()
	icon.hint = false
	icon.side = TILE_SIDE
	icon.font_size = TILE_FONT_SIZE
	icon.setup(entry["mutation"], entry["stage"], entry["owners"])
	icon.position = Vector2.ONE * SLOT_PADDING
	slot.add_child(icon)

	slot.mouse_entered.connect(func() -> void:
		_hovered = slot
		_update_card())
	slot.mouse_exited.connect(func() -> void:
		if _hovered == slot:
			_hovered = null
		_update_card())
	slot.focus_entered.connect(_update_card)
	slot.focus_exited.connect(_update_card.call_deferred)
	return slot


# The pointed-at tile wins; otherwise the focused one.
func _update_card() -> void:
	if not is_inside_tree():
		return
	var target := _hovered
	if target == null:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null and focused.get_parent() == _grid:
			target = focused
	_show_card(target)


func _show_card(slot: Button) -> void:
	if slot == _shown and (slot == null or _card.visible):
		return
	_shown = slot
	for child in _card.get_children():
		_card.remove_child(child)
		child.queue_free()
	if slot == null:
		_card.hide()
		return
	var entry: Dictionary = slot.get_meta(&"entry")
	_card.add_theme_stylebox_override("panel", _card_style(_owner_color(entry)))
	_card.add_child(_describe(entry))
	_card.show()
	_fit_card()
	# Wrapped lines know their height only after a layout pass.
	_fit_card.call_deferred()


func _fit_card() -> void:
	_card.reset_size()
	_place_card()


# Opaque, unlike the theme's tooltip: the tiles and text under it must not
# show through. The frame takes the colour of whoever picked the last stage.
func _card_style(border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.09, 0.12)
	style.border_color = border
	style.set_border_width_all(3)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 15.0
	style.content_margin_bottom = 15.0
	return style


func _owner_color(entry: Dictionary) -> Color:
	var owners: Array = entry["owners"]
	return NelvarMutation.version_color(owners[-1]) if not owners.is_empty() else Color.WHITE


# Under the plate, so it never hides a tile; centred on the tile and kept
# inside the screen. Above the plate when there is no room below.
func _place_card() -> void:
	if _shown == null or not _card.visible:
		return
	var tile := _shown.get_global_rect()
	var plate := get_global_rect()
	var card_size := _card.size
	var screen := get_viewport_rect().size
	# Within the plate's width when it fits, so the two line up.
	var x := clampf(tile.get_center().x - card_size.x / 2.0, plate.position.x,
		maxf(plate.end.x - card_size.x, plate.position.x))
	x = clampf(x, CARD_OFFSET, maxf(screen.x - card_size.x - CARD_OFFSET, CARD_OFFSET))
	var y := plate.end.y + CARD_OFFSET
	if y + card_size.y > screen.y - CARD_OFFSET:
		var above := plate.position.y - CARD_OFFSET - card_size.y
		y = above if above >= CARD_OFFSET else screen.y - card_size.y - CARD_OFFSET
	_card.position = Vector2(x, y).round()


func _describe(entry: Dictionary) -> Control:
	var mutation: NelvarMutation = entry["mutation"]
	var stage: int = entry["stage"]
	var owners: Array = entry["owners"]
	# One name when every stage was picked by the same one.
	var picks := PackedStringArray()
	if not owners.is_empty() and owners.count(owners[0]) == owners.size():
		picks.append(_who(owners[0]))
	else:
		for i in owners.size():
			picks.append("%s — %s" % [NelvarMutation.stage_name(i + 1), _who(owners[i])])
	var notes: Array[Label] = [
		MutationText.line("Выбор: %s" % ", ".join(picks), MutationText.MUTED_COLOR)]
	if stage < mutation.max_stage:
		notes.append(MutationText.line("Может выпасть снова и усилиться.",
			MutationText.MUTED_COLOR))
	return MutationText.describe(mutation, stage, _owner_color(entry), notes)


func _who(owner: int) -> String:
	if owner == _player_version:
		return "ты"
	if owner == NelvarMutation.SPONTANEOUS:
		return "спонтанно"
	return NelvarMutation.version_name(owner)

