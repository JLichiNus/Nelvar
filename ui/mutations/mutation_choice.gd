extends ColorRect
## Paused mutation chooser: the offered mutations as large tiles, so a player
## who knows them picks at a glance; the pointed-at or focused tile's full
## description is shown under them for one who does not. The HUD must follow
## PauseMenu among scene siblings so this _input sees Escape first (input
## dispatch traverses in reverse order).

const MutationText := preload("res://ui/mutations/mutation_text.gd")
## The tile as in the inventory, framed by a card border with room around it.
const TILE_SIDE := 63.0
const TILE_FONT_SIZE := 33
const CARD_SIDE := 99.0
const SHORTCUTS := [KEY_1, KEY_2, KEY_3]
const KEYPAD_SHORTCUTS := [KEY_KP_1, KEY_KP_2, KEY_KP_3]

var _director: NelvarMutationDirector
var _buttons: Array[Button] = []
var _descriptions: Array[Control] = []

@onready var _cards: HBoxContainer = %Cards
@onready var _details: MarginContainer = %Details


func bind(director: NelvarMutationDirector) -> void:
	_director = director
	director.pending_changed.connect(_on_pending_changed)


func _input(event: InputEvent) -> void:
	if not is_instance_valid(_director):
		return

	var mutate := event.is_action_pressed("mutate")
	if visible:
		if mutate or event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_close()
			return

		var key := event as InputEventKey
		if key == null or not key.pressed or key.echo:
			return
		var index := SHORTCUTS.find(key.keycode)
		if index == -1:
			index = KEYPAD_SHORTCUTS.find(key.keycode)
		if index >= 0 and index < _buttons.size():
			get_viewport().set_input_as_handled()
			_choose(index)
	elif mutate and not get_tree().paused and _director.has_pending():
		get_viewport().set_input_as_handled()
		_open()


func _open() -> void:
	var offers := _director.pending_offers()
	if offers.is_empty():
		return
	for container in [_cards, _details]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	_buttons.clear()
	_descriptions.clear()
	for index in offers.size():
		_add_card(offers[index], index)

	get_tree().paused = true
	show()
	_buttons[0].grab_focus()
	_show_description(0)


func _close() -> void:
	if visible:
		hide()
		get_tree().paused = false


func _on_pending_changed(pending: bool) -> void:
	if not pending:
		_close()


func _choose(index: int) -> void:
	if visible and _director.has_pending():
		_director.choose(index)
		_close()


## Index of the card whose description is shown (-1: none).
func shown_card() -> int:
	for index in _descriptions.size():
		if _descriptions[index].modulate.a > 0.0:
			return index
	return -1


func _add_card(mutation: NelvarMutation, index: int) -> void:
	var stage := _director.next_stage(mutation)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	_cards.add_child(column)

	# A real button provides mouse and keyboard focus; the tile sits on it.
	var button := Button.new()
	button.custom_minimum_size = Vector2.ONE * CARD_SIDE
	button.pressed.connect(_choose.bind(index))
	# Dim until selected: the selected card is the one described below.
	button.add_theme_stylebox_override("normal", _card_style(
		Color(0.075, 0.09, 0.12), Color(0.4, 0.44, 0.5)))
	button.add_theme_stylebox_override("hover", _card_style(
		Color(0.12, 0.17, 0.21), Color(0.64, 0.9, 1.0)))
	button.add_theme_stylebox_override("pressed", _card_style(
		Color(0.15, 0.22, 0.27), Color.WHITE))
	var selected := _card_style(Color.TRANSPARENT, Color(0.64, 0.9, 1.0))
	selected.draw_center = false
	button.add_theme_stylebox_override("focus", selected)
	# Pointing at a tile selects it, so the mouse and the keys show the same.
	button.mouse_entered.connect(button.grab_focus)
	button.focus_entered.connect(_show_description.bind(index))
	column.add_child(button)
	_buttons.append(button)

	var icon := NelvarMutationIcon.new()
	icon.hint = false
	icon.side = TILE_SIDE
	icon.font_size = TILE_FONT_SIZE
	icon.setup(mutation, stage, [])
	icon.position = Vector2.ONE * (CARD_SIDE - TILE_SIDE) / 2.0
	button.add_child(icon)

	# Its key under it: the only hint that 1 / 2 / 3 choose.
	var key := MutationText.line(str(index + 1), MutationText.MUTED_COLOR)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(key)

	# Every description stays in the layout, only the shown one is opaque:
	# the panel keeps the tallest one's height and does not jump.
	var favored := mutation.favored_version(stage)
	var notes: Array[Label] = [MutationText.line(
		"по душе: %s" % NelvarMutation.version_name(favored),
		NelvarMutation.version_color(favored))]
	var description := MutationText.describe(mutation, stage, Color.WHITE, notes)
	description.modulate.a = 0.0
	_details.add_child(description)
	_descriptions.append(description)


func _show_description(index: int) -> void:
	for i in _descriptions.size():
		_descriptions[i].modulate.a = 1.0 if i == index else 0.0


func _card_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(3)
	return style


func _exit_tree() -> void:
	_close()
