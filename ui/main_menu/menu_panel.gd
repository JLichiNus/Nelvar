class_name NelvarMenuPanel
extends PanelContainer
## Animated menu panel ("Настройки", "Об игре"): slides in along the pixel grid,
## fades in its header, draws its rule from the center, then reveals the content
## one item after another. An optional `typed_text` label is typed out with pauses
## after punctuation (a click or Enter reveals it at once). The back button shows
## up last, when everything else is on screen.
##
## Expected layout: Rows (VBoxContainer) with Header, Rule (Control) > Line
## (ColorRect), then any content.

## Slide distance and step; movement snaps to whole art pixels (UI is drawn at 3x).
const SLIDE := 30.0
const ART_PIXEL := 3.0
const OPEN_TIME := 0.25
const CLOSE_TIME := 0.15
const ITEM_DELAY := 0.08
const ITEM_FADE := 0.18
const CHAR_DELAY := 0.01
const PAUSES := {".": 0.22, "!": 0.22, "?": 0.22, ",": 0.08, "—": 0.1}

## Rule color: the accent of the reality this panel belongs to.
@export var accent := Color.WHITE:
	set(value):
		accent = value
		if is_node_ready():
			rule_line.color = value
## Optional label typed out letter by letter.
@export var typed_text: Label
## Shown (and clickable) only once the rest of the panel is revealed.
@export var back_button: Button

var _run := 0
var _tween: Tween
var _rule_tween: Tween
var _typing := false
var _type_wait := 0.0
var _type_index := 0
var _type_total := 0
## Printable characters only (spaces and newlines are not counted by the label).
var _printable := ""

@onready var rows: VBoxContainer = $Rows
@onready var header: Label = $Rows/Header
## The rule is a line inside a plain Control: containers reset their children's
## scale, so the line is grown by its offsets instead.
@onready var rule: Control = $Rows/Rule
@onready var rule_line: ColorRect = $Rows/Rule/Line


func _ready() -> void:
	rule_line.color = accent
	if typed_text != null:
		# Lay out the full text up front so lines don't jump while it is typed.
		typed_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
		_printable = typed_text.text.replace(" ", "").replace("\n", "")


func _process(delta: float) -> void:
	if not _typing:
		return
	_type_wait -= delta
	while _typing and _type_wait <= 0.0:
		_type_index += 1
		typed_text.visible_characters = _type_index
		if _type_index >= _type_total:
			_finish_typing()
			return
		var typed := _printable[_type_index - 1] if _type_index <= _printable.length() else ""
		_type_wait += CHAR_DELAY + PAUSES.get(typed, 0.0)


func _input(event: InputEvent) -> void:
	if not _typing or not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.pressed:
		_finish_typing()
	elif event.is_action_pressed("ui_accept"):
		_finish_typing()
		get_viewport().set_input_as_handled()


func play_open() -> void:
	_run += 1
	var run := _run
	_stop()
	show()
	modulate.a = 0.0
	header.modulate.a = 0.0
	_set_rule_width(0.0)
	for item in _items():
		item.modulate.a = 0.0
	if typed_text != null:
		typed_text.visible_characters = 0
	if back_button != null:
		back_button.modulate.a = 0.0
		back_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Let the container place the panel before sliding it in.
	await get_tree().process_frame
	if run != _run:
		return
	var target := position
	_tween = create_tween()
	_tween.tween_method(_slide.bind(target), SLIDE, 0.0, OPEN_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(self, "modulate:a", 1.0, OPEN_TIME)
	_tween.tween_property(header, "modulate:a", 1.0, 0.15)
	_tween.tween_method(_set_rule_width, 0.0, 1.0, 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_pulse_rule)
	# Content items one after another.
	var items := _items()
	for i in items.size():
		var fade := _tween.parallel() if i > 0 else _tween
		fade.tween_property(items[i], "modulate:a", 1.0, ITEM_FADE).set_delay(i * ITEM_DELAY)
	_tween.tween_callback(_start_typing)


func play_close() -> void:
	_run += 1
	_stop()
	var start := position
	_tween = create_tween()
	_tween.tween_method(_slide.bind(start), 0.0, SLIDE * 0.6, CLOSE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(self, "modulate:a", 0.0, CLOSE_TIME)
	_tween.tween_callback(hide)


## Hide at once (another panel is opening in its place).
func close_now() -> void:
	_run += 1
	_stop()
	hide()


## Content revealed one by one: everything after the rule except the back button.
func _items() -> Array[Control]:
	var items: Array[Control] = []
	var after_rule := false
	for child in rows.get_children():
		if child == rule:
			after_rule = true
		elif after_rule and child != back_button and child is Control:
			items.append(child)
	return items


func _start_typing() -> void:
	if typed_text == null:
		_show_back()
		return
	_type_total = typed_text.get_total_character_count()
	_type_index = 0
	_type_wait = CHAR_DELAY
	_typing = true


func _finish_typing() -> void:
	_typing = false
	typed_text.visible_characters = -1
	_show_back()


func _show_back() -> void:
	if back_button == null:
		return
	back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(back_button, "modulate:a", 1.0, 0.2)


## The rule slowly breathes once it is drawn.
func _pulse_rule() -> void:
	_rule_tween = create_tween().set_loops()
	_rule_tween.tween_property(rule_line, "modulate:a", 0.5, 1.2).set_trans(Tween.TRANS_SINE)
	_rule_tween.tween_property(rule_line, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE)


## Grows the rule from its center; `amount` 0..1, snapped to whole art pixels.
func _set_rule_width(amount: float) -> void:
	var half := roundf(rule.size.x * amount / 2.0 / ART_PIXEL) * ART_PIXEL
	rule_line.offset_left = -half
	rule_line.offset_right = half


func _slide(offset: float, origin: Vector2) -> void:
	position.x = origin.x + roundf(offset / ART_PIXEL) * ART_PIXEL


func _stop() -> void:
	_typing = false
	for tween in [_tween, _rule_tween]:
		if tween != null:
			tween.kill()
	rule_line.modulate.a = 1.0
