class_name NelvarSettingsPanel
extends NelvarMenuPanel
## Settings: categories on the left, the chosen category's rows on the right
## (one line each, scrolled when they do not fit). The hint of the row under
## the cursor or in focus (rows keep it in `metadata/hint`) is sent out with
## `hint_changed`; NelvarPanelMorph shows it in its own frame (NelvarHintBox).
## Q/E or the gamepad shoulders switch categories from anywhere in the panel.
## «Разработчик» exists only in debug builds (editor runs and debug exports).
##
## The same panel serves the main menu and the pause menu. Both grow it out
## of their «Настройки» button with NelvarPanelMorph, which shows the content
## through `set_reveal`.

signal hint_changed(text: String)

const HINT_META := &"hint"

## Step ticks closer together than this are skipped: dragging a slider
## crosses many 1% steps a frame, held arrows repeat fast.
const STEP_SOUND_GAP_MS := 45

## Next/previous category (physical keys, so they work in any layout).
const NEXT_KEY := KEY_E
const PREVIOUS_KEY := KEY_Q

@onready var fullscreen_check: CheckButton = %Fullscreen
@onready var vsync_check: CheckButton = %VSync
## The frame rate cap; its last step, past GameSettings.MAX_FPS_MAX, is "no cap".
@onready var fps_limit: NelvarSlider = %FpsLimit
@onready var info_panel_check: CheckButton = %InfoPanel
@onready var vignette_level: NelvarSlider = %VignetteLevel
@onready var vignette_direction_check: CheckButton = %VignetteDirection
@onready var start_in_void_check: CheckButton = %StartInVoid
@onready var categories: VBoxContainer = %Categories
@onready var pages: VBoxContainer = %Pages
@onready var scroll: ScrollContainer = %Scroll
@onready var body: HBoxContainer = %Body
@onready var footer: HBoxContainer = %Footer
@onready var divider: ColorRect = %Body/Divider
## Ticks on every step of a slider or a value row (the menu's hover sound).
@onready var step_sound: AudioStreamPlayer = %StepSound

var _tabs: Array[Button] = []
var _pages: Array[Control] = []
var _current := 0
var _focused_row: Control
var _hovered_row: Control
## Off while the panel grows or shrinks: nothing in it takes focus or input.
var _interactive := true
var _last_step_sound_ms := -STEP_SOUND_GAP_MS


func _ready() -> void:
	super()
	for child in categories.get_children():
		if child is Button:
			_tabs.append(child)
	for child in pages.get_children():
		_pages.append(child)
	if OS.is_debug_build():
		start_in_void_check.set_pressed_no_signal(GameSettings.start_in_void)
		start_in_void_check.toggled.connect(GameSettings.set_start_in_void)
		GameSettings.start_in_void_changed.connect(start_in_void_check.set_pressed_no_signal)
	else:
		# Public builds: no developer category at all.
		_tabs.pop_back()
		_pages.pop_back()
		for node: Node in [%DevTab, %DevRule, %DevPage]:
			node.get_parent().remove_child(node)
			node.queue_free()

	for i in _tabs.size():
		var tab := _tabs[i]
		tab.toggled.connect(_on_tab_toggled.bind(i))
		# Moving through the list with the keyboard opens each category.
		tab.focus_entered.connect(show_tab.bind(i))
		var rows := _rows(_pages[i])
		if not rows.is_empty():
			tab.focus_neighbor_right = tab.get_path_to(rows[0])
		for row in rows:
			if row is NelvarSlider:
				(row as NelvarSlider).value_changed.connect(_play_step.unbind(1))
			row.focus_neighbor_left = row.get_path_to(tab)
			row.focus_entered.connect(_set_focused_row.bind(row))
			row.focus_exited.connect(_set_focused_row.bind(null))
			row.mouse_entered.connect(_set_hovered_row.bind(row))
			row.mouse_exited.connect(_set_hovered_row.bind(null))

	fullscreen_check.set_pressed_no_signal(FullscreenToggle.is_fullscreen())
	fullscreen_check.toggled.connect(FullscreenToggle.set_fullscreen)
	FullscreenToggle.fullscreen_changed.connect(fullscreen_check.set_pressed_no_signal)
	vsync_check.toggled.connect(GameSettings.set_vsync)
	fps_limit.min_value = GameSettings.MAX_FPS_MIN
	fps_limit.max_value = GameSettings.MAX_FPS_MAX + GameSettings.MAX_FPS_STEP
	fps_limit.step = GameSettings.MAX_FPS_STEP
	fps_limit.value_changed.connect(_on_fps_limit_changed)
	GameSettings.display_changed.connect(_show_display_settings)
	_show_display_settings()
	info_panel_check.set_pressed_no_signal(GameSettings.show_info_panel)
	info_panel_check.toggled.connect(GameSettings.set_show_info_panel)
	GameSettings.info_panel_changed.connect(info_panel_check.set_pressed_no_signal)
	vignette_level.step = GameSettings.VIGNETTE_STEP
	vignette_level.value_changed.connect(GameSettings.set_damage_vignette)
	vignette_direction_check.toggled.connect(GameSettings.set_damage_vignette_directional)
	GameSettings.damage_vignette_changed.connect(_show_vignette_settings)
	_show_vignette_settings()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not _interactive:
		return
	var step := 0
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.physical_keycode == NEXT_KEY:
			step = 1
		elif key.physical_keycode == PREVIOUS_KEY:
			step = -1
	var pad := event as InputEventJoypadButton
	if pad != null and pad.pressed:
		if pad.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			step = 1
		elif pad.button_index == JOY_BUTTON_LEFT_SHOULDER:
			step = -1
	if step == 0:
		return
	get_viewport().set_input_as_handled()
	var next := posmod(_current + step, _tabs.size())
	show_tab(next)
	_tabs[next].grab_focus()


## The control that takes focus when the panel opens.
func first_focus() -> Control:
	return _tabs[_current]


## While off, the panel's controls can't be focused or clicked and Q/E do
## nothing (it is half-transparent and moving).
func set_interactive(on: bool) -> void:
	_interactive = on
	focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED if on else Control.FOCUS_BEHAVIOR_DISABLED
	mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED if on else Control.MOUSE_BEHAVIOR_DISABLED


## Back to the first category, scrolled to the top, nothing revealed yet.
func reset_view() -> void:
	show_tab(0)
	_focused_row = null
	_hovered_row = null
	_refresh_hint()
	set_reveal(0.0)


func show_tab(index: int) -> void:
	if not _tabs[index].button_pressed:
		_tabs[index].button_pressed = true  # toggled -> _on_tab_toggled
	else:
		_on_tab_toggled(true, index)


func _on_tab_toggled(pressed: bool, index: int) -> void:
	if not pressed:
		return
	var changed := index != _current
	_current = index
	for i in _pages.size():
		_pages[i].visible = i == index
	if changed:
		scroll.scroll_vertical = 0
	_refresh_hint()


## Shows the content as the panel opens: 0 = only the frame, 1 = all of it.
## The header fades in, the rule is drawn from its center, then the columns
## and the footer follow one after another.
func set_reveal(amount: float) -> void:
	header.modulate.a = _phase(amount, 0.0, 0.45)
	_set_rule_width(ease(_phase(amount, 0.1, 0.7), 0.4))
	categories.modulate.a = _phase(amount, 0.2, 0.65)
	divider.modulate.a = categories.modulate.a
	scroll.get_parent().modulate.a = _phase(amount, 0.3, 0.8)
	footer.modulate.a = _phase(amount, 0.45, 1.0)


## Fully open: the rule starts breathing.
func finish_reveal() -> void:
	_stop()
	_pulse_rule()


## Closing: the rule stops breathing so `set_reveal` can take it back.
func begin_hide() -> void:
	_stop()


func _play_step() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_step_sound_ms < STEP_SOUND_GAP_MS:
		return
	_last_step_sound_ms = now
	step_sound.play()


func _on_fps_limit_changed(value: float) -> void:
	GameSettings.set_max_fps(0 if value > GameSettings.MAX_FPS_MAX else roundi(value))


func _show_display_settings() -> void:
	vsync_check.set_pressed_no_signal(GameSettings.vsync)
	var fps := GameSettings.max_fps
	fps_limit.set_value_no_signal(fps_limit.max_value if fps == 0 else float(fps))


func _show_vignette_settings() -> void:
	vignette_level.set_value_no_signal(GameSettings.damage_vignette)
	vignette_direction_check.set_pressed_no_signal(GameSettings.damage_vignette_directional)


## Focusable rows of a page (group headings and notes are skipped).
func _rows(page: Control) -> Array[Control]:
	var rows: Array[Control] = []
	for child in page.get_children():
		if child is Control and (child as Control).focus_mode != Control.FOCUS_NONE:
			rows.append(child)
	return rows


func _set_focused_row(row: Control) -> void:
	_focused_row = row
	_refresh_hint()


func _set_hovered_row(row: Control) -> void:
	_hovered_row = row
	_refresh_hint()


func _refresh_hint() -> void:
	hint_changed.emit(current_hint())


## Hint of the row under the cursor, else of the row in focus; "" if none.
func current_hint() -> String:
	var row := _hovered_row if _hovered_row != null else _focused_row
	if row != null and is_instance_valid(row) and row.is_visible_in_tree():
		return row.get_meta(HINT_META, "")
	return ""


static func _phase(amount: float, from: float, to: float) -> float:
	return clampf((amount - from) / (to - from), 0.0, 1.0)
