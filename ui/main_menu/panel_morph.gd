class_name NelvarPanelMorph
extends Control
## Grows the settings panel out of the button that opens it and shrinks it
## back into the button. One progress value (0 = only the button, 1 = the
## panel fully open) drives everything, so closing is the opening played
## backwards, and either can turn around midway (Esc while it opens, the
## button again while it closes).
##
## Progress timeline:
##   0.00 - 0.40  the owner's part, sent through `progress_changed`: the main
##                menu folds its other buttons away and lifts the logo
##   0.25 - 0.78  the button's frame grows into the panel's frame, its text
##                flies to the panel's header
##   0.78 - 1.00  the panel's content appears (NelvarSettingsPanel.set_reveal)
##
## A full-rect overlay that must be drawn above the panel (add it after the
## panel). It holds the growing frame and the flying title, and blocks the
## mouse while the animation runs.

signal progress_changed(progress: float)
signal opened
signal closed

## Seconds for the whole way; a reversal midway takes the share left.
const OPEN_TIME := 0.45
const CLOSE_TIME := 0.35
const GROW_FROM := 0.25
const GROW_TO := 0.78
## Frames move and grow by whole art pixels (the UI is drawn at 3x).
const ART_PIXEL := 3.0

var panel: NelvarSettingsPanel
var button: Button
## Label that draws the button's text (main menu); null when the button draws
## its own text (pause menu).
var button_label: Label
## Global rect the panel opens to: `func() -> Rect2`.
var target_rect: Callable
## 0..1, see the timeline above.
var progress := 0.0

var _goal := 0.0
var _tween: Tween
var _button_look: Panel
var _panel_look: Panel
var _title: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_button_look = Panel.new()
	_panel_look = Panel.new()
	_title = Label.new()
	# Top: the header is a one-line label, so its text starts at its top edge.
	_title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_title.clip_text = false
	for node: Control in [_button_look, _panel_look, _title]:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.hide()
		add_child(node)
	resized.connect(refresh)


## `look` is how the button looks highlighted: the growing frame starts as it.
func setup(settings_panel: NelvarSettingsPanel, from_button: Button, look: StyleBox,
		text_label: Label = null) -> void:
	panel = settings_panel
	button = from_button
	button_label = text_label
	_button_look.add_theme_stylebox_override("panel", look)
	_panel_look.add_theme_stylebox_override("panel", panel.get_theme_stylebox("panel"))
	panel.hide()


## Open or opening.
func is_open() -> bool:
	return _goal == 1.0


## On screen in any way: open, opening or closing.
func is_active() -> bool:
	return _goal == 1.0 or progress > 0.0


func open() -> void:
	if _goal == 1.0:
		return
	_goal = 1.0
	if progress == 0.0:
		_begin()
	_run(OPEN_TIME)


func close() -> void:
	if _goal == 0.0:
		return
	_goal = 0.0
	panel.set_interactive(false)
	panel.begin_hide()
	_run(CLOSE_TIME)


## Back to the button at once (the screen is going away).
func close_now() -> void:
	if _tween != null:
		_tween.kill()
	_goal = 0.0
	_set_progress(0.0)
	_end()


## Lays everything out again for the current progress (after a resize).
func refresh() -> void:
	if progress > 0.0:
		_set_progress(progress)


func _begin() -> void:
	_copy_title_style()
	panel.set_interactive(false)
	panel.reset_view()
	panel.self_modulate.a = 0.0
	panel.show()


func _run(full_time: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_progress, progress, _goal, full_time * absf(_goal - progress))
	_tween.tween_callback(_finish)


func _finish() -> void:
	if _goal == 1.0:
		panel.set_interactive(true)
		panel.finish_reveal()
		opened.emit()
	else:
		_end()
		closed.emit()


func _end() -> void:
	panel.hide()
	_button_look.hide()
	_panel_look.hide()
	_title.hide()
	_set_button_alpha(1.0)


func _set_progress(value: float) -> void:
	progress = value
	var animating := progress > 0.0 and progress < 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP if animating else Control.MOUSE_FILTER_IGNORE
	progress_changed.emit(progress)

	var to := _panel_rect()
	panel.global_position = to.position
	panel.size = to.size

	# The button gives way to its copy as soon as the copy starts to grow.
	var grow := _phase(progress, GROW_FROM, GROW_TO)
	var growing := progress > GROW_FROM and progress < GROW_TO
	_set_button_alpha(0.0 if progress > GROW_FROM else 1.0)
	var eased := _ease_in_out(grow)
	var from := button.get_global_rect()
	var frame := _snapped_lerp(from, to, eased)
	for look: Panel in [_button_look, _panel_look]:
		look.visible = growing
		look.global_position = frame.position
		look.size = frame.size
	# The button's look melts into the panel's on the way.
	_button_look.modulate.a = 1.0 - _phase(grow, 0.1, 0.6)
	_panel_look.modulate.a = _phase(grow, 0.0, 0.5)
	panel.self_modulate.a = 1.0 if progress >= GROW_TO else 0.0

	var reveal := _phase(progress, GROW_TO, 1.0)
	panel.set_reveal(reveal)
	# The button's text flies to the header and fades into it.
	var title_alpha := 1.0 - panel.header.modulate.a
	_title.visible = progress > GROW_FROM and title_alpha > 0.0
	if _title.visible:
		var title_rect := _snapped_lerp(_button_text_rect(), panel.header.get_global_rect(), eased)
		_title.global_position = title_rect.position
		_title.size = title_rect.size
		_title.modulate.a = title_alpha


## Where the panel goes: the owner's rect, but never smaller than the panel.
func _panel_rect() -> Rect2:
	var rect: Rect2 = target_rect.call()
	rect.size = rect.size.max(panel.get_combined_minimum_size())
	return rect


## The line of the button's text (it is centered in the button).
func _button_text_rect() -> Rect2:
	var rect: Rect2
	if button_label != null:
		rect = button_label.get_global_rect()
	else:
		var style := button.get_theme_stylebox("normal")
		rect = button.get_global_rect()
		rect.position.x += style.content_margin_left
		rect.size.x -= style.content_margin_left + style.content_margin_right
	var line := _title.get_theme_font("font").get_height(_title.get_theme_font_size("font_size"))
	rect.position.y += (rect.size.y - line) / 2.0
	rect.size.y = line
	return rect


func _copy_title_style() -> void:
	if button_label != null:
		_title.text = button_label.text
		_title.add_theme_font_override("font", button_label.get_theme_font("font"))
		_title.add_theme_font_size_override("font_size", button_label.get_theme_font_size("font_size"))
		_title.material = button_label.material
	else:
		_title.text = button.text
		_title.add_theme_font_override("font", button.get_theme_font("font"))
		_title.add_theme_font_size_override("font_size", button.get_theme_font_size("font_size"))
	_title.add_theme_color_override("font_color", Color.WHITE)
	_title.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)


## Hides the button without moving it out of its container. self_modulate:
## the menus tween the button's own modulate for their highlight effects.
func _set_button_alpha(alpha: float) -> void:
	if button == null:
		return
	button.self_modulate.a = alpha
	if button_label != null:
		button_label.modulate.a = alpha


## Moves from `from` to `to` by whole art pixels, landing exactly on both ends.
func _snapped_lerp(from: Rect2, to: Rect2, weight: float) -> Rect2:
	if weight <= 0.0:
		return from
	if weight >= 1.0:
		return to
	var position_step := ((to.position - from.position) * weight).snappedf(ART_PIXEL)
	var size_step := ((to.size - from.size) * weight).snappedf(ART_PIXEL)
	return Rect2(from.position + position_step, from.size + size_step)


static func _phase(value: float, from: float, to: float) -> float:
	return clampf((value - from) / (to - from), 0.0, 1.0)


## Cubic: a slow start, a fast middle and a soft landing.
static func _ease_in_out(x: float) -> float:
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0
