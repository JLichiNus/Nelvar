extends CanvasLayer
## Autoload (DevConsole): the developer console, opened with "/" during a run
## in debug builds (editor runs and debug exports), like a game chat with
## commands.
##
## While it is open the game stands still. Above the input line it lists what
## may be typed next and greys out the rest of the chosen word right in the
## line; Tab takes it, ↑↓ walk the list (or the history when there is no
## list), Enter runs the command and closes the console, Esc just closes it.
## The answers stay over the game for a while and fade, the mouse wheel
## scrolls them back while the console is open.
##
## The commands themselves are in NelvarConsoleCommands.

const LAYER := 120
const FONT_SIZE := 22
const MARGIN := 12.0
const INPUT_HEIGHT := 38.0
const LOG_WIDTH := 820.0
## The log ends this far above the screen bottom, clear of the HUD's lower
## left corner (health, level, adaptation).
const LOG_BOTTOM := 196.0
## Stored lines; older ones are dropped.
const LOG_LIMIT := 200
## Lines shown at once while open.
const LOG_SHOWN_OPEN := 14
## While closed: the newest lines stay this many seconds and fade at the end.
const LOG_SHOWN_CLOSED := 8
const LOG_LIFETIME := 9.0
const LOG_FADE := 1.2
const SUGGESTIONS_SHOWN := 9
const HISTORY_LIMIT := 50

const OUTPUT_COLORS := {
	NelvarCommandTree.Output.INFO: Color(0.88, 0.88, 0.88),
	NelvarCommandTree.Output.GOOD: Color(0.6, 0.95, 0.58),
	NelvarCommandTree.Output.ERROR: Color(1.0, 0.46, 0.4),
	NelvarCommandTree.Output.ECHO: Color(0.58, 0.6, 0.66),
}
const SELECTED_COLOR := Color(1.0, 0.88, 0.38)
const OPTION_COLOR := Color(0.78, 0.78, 0.8)
const HINT_COLOR := Color(0.5, 0.52, 0.58)
const GHOST_COLOR := Color(0.5, 0.5, 0.54)
## The greyed rest of the word starts this far after the text (past the caret).
const GHOST_GAP := 3.0
const ERROR_COLOR := Color(1.0, 0.46, 0.4)

var commands := NelvarCommandTree.new()

var _open := false
var _was_paused := false
var _root: Control
var _line: LineEdit
var _ghost: Label
var _status: Label
var _suggestions: PanelContainer
var _rows: VBoxContainer
var _log: VBoxContainer
## [{"label": Label, "time": msec}]
var _entries: Array[Dictionary] = []
var _scroll := 0
var _history: Array[String] = []
## -1: not walking the history.
var _history_index := -1
var _draft := ""
var _hint := {}
var _selected := 0
var _seen_text := ""
var _seen_caret := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = LAYER
	if not OS.is_debug_build():
		set_process(false)
		set_process_input(false)
		return
	_build()
	commands.printed.connect(_print)
	NelvarConsoleCommands.new(commands, get_tree()).register()
	commands.add(NelvarConsoleNode.literal("clear", "очистить консоль").runs(
		func(_a: Dictionary) -> void: _clear()))


func _exit_tree() -> void:
	commands.clear()


func is_open() -> bool:
	return _open


## The console can open during a run that is going on (not under the pause
## menu or a mutation choice).
func can_open() -> bool:
	return OS.is_debug_build() and not _open and not get_tree().paused \
		and get_tree().get_first_node_in_group(&"player") != null


func open(text: String = "/") -> void:
	if _open:
		return
	_open = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_scroll = 0
	_history_index = -1
	_line.text = text
	_line.caret_column = text.length()
	_line.show()
	_line.grab_focus()
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	get_tree().paused = _was_paused
	_line.release_focus()
	_line.hide()
	_suggestions.hide()
	_status.hide()
	_scroll = 0


func _input(event: InputEvent) -> void:
	if _open:
		var button := event as InputEventMouseButton
		if button != null and button.pressed:
			if button.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll = mini(_scroll + 1, maxi(_entries.size() - LOG_SHOWN_OPEN, 0))
				get_viewport().set_input_as_handled()
			elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll = maxi(_scroll - 1, 0)
				get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	# The slash key itself, whatever the layout types on it (on the Russian
	# one it is "."), or a "/" typed some other way.
	if key.physical_keycode == KEY_SLASH or key.unicode == 47:
		if can_open():
			get_viewport().set_input_as_handled()
			open()


func _process(_delta: float) -> void:
	if _open and (_line.text != _seen_text or _line.caret_column != _seen_caret):
		_refresh()
	_layout_log()


# --- Input line ------------------------------------------------------------

func _on_text_changed(_text: String) -> void:
	_history_index = -1
	_selected = 0
	_refresh()


func _on_line_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_TAB:
			_complete()
		KEY_UP:
			if _arrows_walk_list():
				_move_selection(-1)
			else:
				_walk_history(-1)
		KEY_DOWN:
			if _arrows_walk_list():
				_move_selection(1)
			else:
				_walk_history(1)
		KEY_ESCAPE:
			close()
		_:
			return
	_line.accept_event()


func _on_submitted(text: String) -> void:
	var line := text.strip_edges()
	if line.is_empty() or line == "/":
		close()
		return
	if not line.begins_with("/"):
		line = "/" + line
	if _history.is_empty() or _history.back() != line:
		_history.append(line)
		if _history.size() > HISTORY_LIMIT:
			_history.pop_front()
	_print(line, NelvarCommandTree.Output.ECHO)
	close()
	commands.execute(line)


func _complete() -> void:
	if not _list_shown():
		return
	var candidate: Dictionary = _hint["candidates"][_selected]
	var caret := _line.caret_column
	var start: int = _hint["start"]
	var after := _line.text.substr(caret)
	var word: String = candidate["text"]
	if after.is_empty() and candidate["more"]:
		word += " "
	_line.text = _line.text.substr(0, start) + word + after
	_line.caret_column = start + word.length()
	_selected = 0
	_refresh()


func _move_selection(step: int) -> void:
	var count: int = _hint["candidates"].size()
	_selected = posmod(_selected + step, count)
	_refresh()


func _walk_history(step: int) -> void:
	if _history.is_empty():
		return
	if _history_index == -1:
		if step > 0:
			return
		_draft = _line.text
		_history_index = _history.size() - 1
	else:
		_history_index += step
	if _history_index >= _history.size():
		_history_index = -1
		_line.text = _draft
	else:
		_history_index = maxi(_history_index, 0)
		_line.text = _history[_history_index]
	_line.caret_column = _line.text.length()
	_selected = 0
	_refresh()


# --- Hints -----------------------------------------------------------------

func _list_shown() -> bool:
	return _open and _suggestions.visible and not _hint.get("candidates", []).is_empty()


## ↑↓ go through the hints, except on a bare "/" (the console just opened:
## the last commands are wanted more than the list of all of them) and while
## already walking the history.
func _arrows_walk_list() -> bool:
	return _list_shown() and _history_index == -1 and _line.text.strip_edges() != "/"


func _refresh() -> void:
	_seen_text = _line.text
	_seen_caret = _line.caret_column
	var before := _line.text.substr(0, _line.caret_column)
	_hint = commands.suggest(before)
	var candidates: Array = _hint["candidates"]
	var prefix: String = _hint["prefix"]
	# The word is already typed in full and nothing else fits: no list.
	if candidates.size() == 1 and String(candidates[0]["text"]).to_lower() == prefix.to_lower():
		candidates = []
		_hint["candidates"] = candidates
	_selected = clampi(_selected, 0, maxi(candidates.size() - 1, 0))
	var at_end := _line.caret_column == _line.text.length()

	_status.visible = not _hint["error"].is_empty()
	_status.text = _hint["error"]

	var ghost := ""
	if not candidates.is_empty():
		var chosen := String(candidates[_selected]["text"])
		if chosen.to_lower().begins_with(prefix.to_lower()):
			ghost = chosen.substr(prefix.length())
	elif prefix.is_empty() and _hint["error"].is_empty():
		ghost = " ".join(_hint["expected"])
	_ghost.visible = at_end and not ghost.is_empty()
	_ghost.text = ghost
	_ghost.position.x = _text_x(_line.text.length()) + GHOST_GAP

	_suggestions.visible = not candidates.is_empty()
	if _suggestions.visible:
		_fill_suggestions(candidates)
		_suggestions.position.x = _line.position.x + _text_x(_hint["start"]) - 8.0
	_place_above_line(_suggestions if _suggestions.visible else _status)


func _fill_suggestions(candidates: Array) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var first := clampi(_selected - SUGGESTIONS_SHOWN / 2, 0, maxi(candidates.size() - SUGGESTIONS_SHOWN, 0))
	for i in range(first, mini(first + SUGGESTIONS_SHOWN, candidates.size())):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_label(candidates[i]["text"], SELECTED_COLOR if i == _selected else OPTION_COLOR))
		if not String(candidates[i]["hint"]).is_empty():
			row.add_child(_label(candidates[i]["hint"], HINT_COLOR))
		_rows.add_child(row)
	_suggestions.reset_size()


func _place_above_line(control: Control) -> void:
	if not control.visible:
		return
	control.reset_size()
	control.position.y = _line.position.y - control.size.y - 4.0
	var right_limit := _root.size.x - MARGIN - control.size.x
	control.position.x = clampf(control.position.x, MARGIN, maxf(right_limit, MARGIN))


# Where the character at `index` of the input line starts, from the line's left.
func _text_x(index: int) -> float:
	var font := _line.get_theme_font(&"font")
	var size := _line.get_theme_font_size(&"font_size")
	var style := _line.get_theme_stylebox(&"normal")
	var width := font.get_string_size(_line.text.substr(0, index), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return style.get_margin(SIDE_LEFT) + width


# --- Log -------------------------------------------------------------------

func _print(text: String, kind: int) -> void:
	var label := _label(text, OUTPUT_COLORS.get(kind, OUTPUT_COLORS[NelvarCommandTree.Output.INFO]))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = LOG_WIDTH
	label.add_theme_stylebox_override(&"normal", _box(Color(0.02, 0.02, 0.04, 0.6), 8.0, 2.0))
	_log.add_child(label)
	_entries.append({"label": label, "time": Time.get_ticks_msec()})
	while _entries.size() > LOG_LIMIT:
		var old: Label = _entries.pop_front()["label"]
		old.queue_free()
	_scroll = 0
	print("[console] ", text)


func _clear() -> void:
	for entry in _entries:
		(entry["label"] as Label).queue_free()
	_entries.clear()
	_scroll = 0


func _layout_log() -> void:
	var now := Time.get_ticks_msec()
	var newest := _entries.size() - 1 - (_scroll if _open else 0)
	var count := LOG_SHOWN_OPEN if _open else LOG_SHOWN_CLOSED
	for i in _entries.size():
		var label: Label = _entries[i]["label"]
		var shown := i <= newest and i > newest - count
		var alpha := 1.0
		if shown and not _open:
			var age := (now - int(_entries[i]["time"])) / 1000.0
			alpha = clampf((LOG_LIFETIME - age) / LOG_FADE, 0.0, 1.0)
			shown = alpha > 0.0
		label.visible = shown
		label.modulate.a = alpha
	var bottom := minf(_root.size.y - LOG_BOTTOM, _line.position.y - 8.0)
	# The log sits above the hints so they do not cover it.
	for over: Control in [_suggestions, _status]:
		if _open and over.visible:
			bottom = minf(bottom, over.position.y - 6.0)
	_log.reset_size()
	_log.position = Vector2(MARGIN, bottom - _log.size.y)


# --- Building --------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The pixel font is a bitmap: nearest filtering keeps it sharp.
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_root)

	_log = VBoxContainer.new()
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_constant_override("separation", 0)
	_root.add_child(_log)

	_line = LineEdit.new()
	_line.anchor_top = 1.0
	_line.anchor_bottom = 1.0
	_line.anchor_right = 1.0
	_line.offset_left = MARGIN
	_line.offset_right = -MARGIN
	_line.offset_bottom = -MARGIN
	_line.offset_top = -MARGIN - INPUT_HEIGHT
	_line.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_line.add_theme_color_override(&"font_color", Color(0.95, 0.95, 0.95))
	_line.add_theme_color_override(&"caret_color", Color(0.95, 0.95, 0.95))
	_line.add_theme_color_override(&"selection_color", Color(0.4, 0.55, 0.9, 0.5))
	# Nearly opaque: the HUD's health bar lies right under the line.
	var style := _box(Color(0.02, 0.02, 0.04, 0.9), 10.0, 6.0)
	_line.add_theme_stylebox_override(&"normal", style)
	_line.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	_line.context_menu_enabled = false
	_line.caret_blink = true
	_line.keep_editing_on_text_submit = true
	_line.text_changed.connect(_on_text_changed)
	_line.text_submitted.connect(_on_submitted)
	_line.gui_input.connect(_on_line_input)
	# A click into the game must not take the typing away.
	_line.focus_exited.connect(func() -> void:
		if _open:
			_line.grab_focus.call_deferred())
	_line.hide()
	_root.add_child(_line)

	_ghost = _label("", GHOST_COLOR)
	_ghost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ghost.anchor_bottom = 1.0
	_line.add_child(_ghost)

	_suggestions = PanelContainer.new()
	_suggestions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_suggestions.add_theme_stylebox_override(&"panel", _box(Color(0.02, 0.02, 0.04, 0.92), 8.0, 4.0))
	_suggestions.hide()
	_root.add_child(_suggestions)
	_rows = VBoxContainer.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override("separation", 0)
	_suggestions.add_child(_rows)

	_status = _label("", ERROR_COLOR)
	_status.add_theme_stylebox_override(&"normal", _box(Color(0.02, 0.02, 0.04, 0.92), 8.0, 3.0))
	_status.position.x = MARGIN
	_status.hide()
	_root.add_child(_status)


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.add_theme_color_override(&"font_color", color)
	return label


static func _box(color: Color, horizontal: float, vertical: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.content_margin_left = horizontal
	box.content_margin_right = horizontal
	box.content_margin_top = vertical
	box.content_margin_bottom = vertical
	return box
