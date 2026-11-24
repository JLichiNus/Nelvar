extends ColorRect
## Paused mutation chooser. The HUD must follow PauseMenu among scene siblings
## so this _input sees Escape first (input dispatch traverses in reverse order).

const MutationText := preload("res://ui/mutations/mutation_text.gd")
const CARD_WIDTH := 342.0
const SHORTCUTS := [KEY_1, KEY_2, KEY_3]
const KEYPAD_SHORTCUTS := [KEY_KP_1, KEY_KP_2, KEY_KP_3]

var _director: NelvarMutationDirector
var _buttons: Array[Button] = []

@onready var _scroll: ScrollContainer = %ChoiceScroll
@onready var _cards: GridContainer = %Cards
@onready var _owned: Label = %Owned


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
	for card in _cards.get_children():
		_cards.remove_child(card)
		card.queue_free()
	_buttons.clear()
	for index in offers.size():
		_add_card(offers[index], index)

	var titles := PackedStringArray()
	for entry in _director.owned():
		var mutation: NelvarMutation = entry["mutation"]
		titles.append("%s %s" % [mutation.title, NelvarMutation.stage_name(entry["stage"])])
	_owned.text = "пока нет мутаций" if titles.is_empty() else "Уже есть · " + ", ".join(titles)

	get_tree().paused = true
	show()
	_scroll.scroll_vertical = 0
	_buttons[0].grab_focus()


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


func _add_card(mutation: NelvarMutation, index: int) -> void:
	var stage := _director.next_stage(mutation)
	var slot := PanelContainer.new()
	slot.custom_minimum_size.x = CARD_WIDTH
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_cards.add_child(slot)

	# A real button provides mouse and keyboard focus; the labels sit above it.
	var button := Button.new()
	button.pressed.connect(_choose.bind(index))
	button.add_theme_stylebox_override("normal", _card_style(
		Color(0.075, 0.09, 0.12), Color(0.87, 0.9, 0.95)))
	button.add_theme_stylebox_override("hover", _card_style(
		Color(0.12, 0.17, 0.21), Color(0.64, 0.9, 1.0)))
	button.add_theme_stylebox_override("pressed", _card_style(
		Color(0.15, 0.22, 0.27), Color.WHITE))
	slot.add_child(button)
	_buttons.append(button)

	var padding := MarginContainer.new()
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 15)
	slot.add_child(padding)

	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 6)
	padding.add_child(rows)

	rows.add_child(MutationText.line(mutation.title, Color.WHITE, 27))
	var tag: String = NelvarMutation.LAYER_NAMES[mutation.layer]
	if stage > 1:
		tag += " · " + NelvarMutation.stage_name(stage)
	rows.add_child(MutationText.line(tag, MutationText.MUTED_COLOR))
	MutationText.add_effects(rows, mutation, stage)
	var favored := mutation.favored_version(stage)
	rows.add_child(MutationText.line("по душе: %s" % NelvarMutation.version_name(favored),
		NelvarMutation.version_color(favored)))


func _card_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(3)
	return style


func _exit_tree() -> void:
	_close()
