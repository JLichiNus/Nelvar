extends CanvasLayer
## Pause: resume, inventory, settings, back to the main menu, quit.
##
## Opening takes a moment: the game behind drains of color, darkens and
## blurs (pause_backdrop.gdshader), the music goes "under water"
## (GameMusic.set_muffled) and the dialog fades in, settling down into place.
## Resuming gives the game back at once and lets the menu fade out over it.
## Esc during that fade opens the pause again.
##
## Styled after the scene's reality (`reality`): its accent on the rule and
## on the highlighted button, its font on the header and the buttons. The
## buttons sound and light up like the main menu's (the mouse takes focus).
## «В главное меню» and «Выйти из игры» ask once more, since the run is
## lost: the first press turns the button into a question, the second one
## goes; moving away or Esc takes the question back.
##
## The settings grow out of their button like in the main menu
## (NelvarPanelMorph): the dialog's other rows and its frame fade first.
## The pause opens by itself when the window loses focus (a setting).

const BACKDROP_SHADER := preload("res://ui/pause_menu/pause_backdrop.gdshader")
const HOVER_SOUND := preload("res://assets/audio/sfx/ui_hover.wav")
const CLICK_SOUND := preload("res://assets/audio/sfx/ui_click.wav")
const OPEN_TIME := 0.18
const CLOSE_TIME := 0.12
## The dialog drops into place from this far above (whole art pixels).
const SLIDE := 24.0
const ART_PIXEL := 3.0
## Button text: idle and highlighted, as in the main menu.
const IDLE_TEXT := Color(0.78, 0.78, 0.78)
const CONFIRM_TEXT := "Точно? Забег пропадёт"
const CONFIRM_COLOR := Color(1.0, 0.58, 0.48)

## Settings progress (0..1) over which the dialog's other rows fade, nearest
## to «Настройки» first, and then its frame.
const FADE_LENGTH := 0.18
const FADE_STAGGER := 0.05
const FRAME_FROM := 0.1
const FRAME_TO := 0.35
## Largest settings panel; smaller windows keep this margin around the
## panel and the hint frame above it.
const SETTINGS_MAX := Vector2(1150, 640)
const SETTINGS_MARGIN := Vector2(96, 64)
## The hint frame sits above the panel at its right edge, this wide a share of it.
const HINT_GAP := 12.0
const HINT_SHARE := 0.6

## The reality this scene belongs to (ui/main_menu/elements/).
@export var reality: NelvarMenuElement

var _settings_morph: NelvarPanelMorph
## Open or opening (the menu may still be fading out while false).
var _open := false
var _progress := 0.0
var _tween: Tween
## The exit button that is asking "are you sure?", and its own text.
var _confirming: Button
var _confirm_back_text := ""
var _highlight_style: StyleBox
var _pressed_style: StyleBox
var _idle_style: StyleBox
var _hover_sound: AudioStreamPlayer
var _click_sound: AudioStreamPlayer

@onready var dialog: PanelContainer = %Dialog
@onready var resume_button: Button = %Resume
@onready var settings_button: Button = %Settings
@onready var inventory_button: Button = %Inventory
@onready var main_menu_button: Button = %MainMenu
@onready var quit_button: Button = %Quit
@onready var inventory_panel: NelvarMutationInventory = %InventoryPanel
@onready var settings_panel: NelvarSettingsPanel = %SettingsPanel
@onready var shade: ColorRect = $Shade
@onready var center: CenterContainer = $Shade/Center
@onready var dialog_rows: VBoxContainer = $Shade/Center/Dialog/Rows
@onready var header: Label = $Shade/Center/Dialog/Rows/Header
@onready var rule: ColorRect = $Shade/Center/Dialog/Rows/Rule


func _ready() -> void:
	var backdrop := ShaderMaterial.new()
	backdrop.shader = BACKDROP_SHADER
	shade.material = backdrop
	_apply_reality()

	_hover_sound = _make_player(HOVER_SOUND)
	_click_sound = _make_player(CLICK_SOUND)
	# Every button here sounds, also the settings' and the inventory's,
	# including ones added later. Hooked up before the buttons' own handlers,
	# so the click is already playing when a button leaves the scene.
	for button in find_children("*", "BaseButton", true, false):
		_add_button_sounds(button)
	get_tree().node_added.connect(_on_node_added)

	resume_button.pressed.connect(_resume)
	settings_button.pressed.connect(_open_settings)
	inventory_button.pressed.connect(_open_inventory)
	inventory_panel.back_button.pressed.connect(_close_inventory)
	main_menu_button.pressed.connect(_ask_or_do.bind(main_menu_button, _return_to_menu))
	quit_button.pressed.connect(_ask_or_do.bind(quit_button, GameMusic.quit_game))
	for button in _dialog_buttons():
		button.mouse_entered.connect(_focus_on_hover.bind(button))
		button.focus_entered.connect(_on_button_focus_entered.bind(button))
		button.focus_exited.connect(_on_button_focus_exited.bind(button))
		_set_highlight(button, false)

	settings_panel.back_button.pressed.connect(_close_settings)
	# Drawn above the settings panel: added after it.
	_settings_morph = NelvarPanelMorph.new()
	shade.add_child(_settings_morph)
	_settings_morph.setup(settings_panel, settings_button, _highlight_style)
	_settings_morph.target_rect = _settings_rect
	_settings_morph.hint_rect = _hint_rect
	_settings_morph.progress_changed.connect(_fade_dialog)
	_settings_morph.opened.connect(_on_settings_opened)
	_settings_morph.closed.connect(_on_settings_closed)

	GameSettings.window_focus_changed.connect(_on_window_focus_changed)
	_set_progress(0.0)
	hide()


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if not _open:
		open_pause()
	elif _settings_morph.is_active():
		# Esc while the settings are already closing waits for them.
		_close_settings()
	elif inventory_panel.visible:
		_close_inventory()
	elif _confirming != null:
		_take_back_question()
	else:
		_resume()


func _exit_tree() -> void:
	# Back to the main menu or the game quits: leave nothing paused or muffled.
	if _open:
		get_tree().paused = false
	GameMusic.set_muffled(false, true)


func open_pause() -> void:
	if _open:
		return
	_open = true
	get_tree().paused = true
	# Only scenes with a mutating player have an inventory.
	inventory_button.visible = _mutations() != null
	show()
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_dialog_input(true)
	GameMusic.set_muffled(true)
	_animate(OPEN_TIME)
	resume_button.grab_focus()


## The game runs again at once; the menu fades out over it.
func _resume() -> void:
	if not _open:
		return
	_open = false
	_take_back_question()
	get_tree().paused = false
	GameMusic.set_muffled(false)
	# The fading menu must not take the game's clicks or keys.
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_dialog_input(false)
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()
	_animate(CLOSE_TIME)


func _animate(full_time: float) -> void:
	if _tween != null:
		_tween.kill()
	var goal := 1.0 if _open else 0.0
	_tween = create_tween()
	_tween.tween_method(_set_progress, _progress, goal, full_time * absf(goal - _progress))
	if not _open:
		_tween.tween_callback(hide)


## 0 = no menu, 1 = fully open.
func _set_progress(value: float) -> void:
	_progress = value
	var shown := value * value * (3.0 - 2.0 * value)
	(shade.material as ShaderMaterial).set_shader_parameter("amount", shown)
	center.modulate.a = shown
	center.position.y = -snappedf(SLIDE * (1.0 - shown), ART_PIXEL)


func _set_dialog_input(enabled: bool) -> void:
	for button in _dialog_buttons():
		button.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE


## The window lost focus: pause the run, if the player wants that and the
## game is actually running (not already paused by something else).
func _on_window_focus_changed(focused: bool) -> void:
	if focused or _open or not GameSettings.pause_on_focus_loss:
		return
	if not GameSettings.window_had_focus() or get_tree().paused:
		return
	open_pause()


# --- Look ------------------------------------------------------------------

## The reality's accent and font on the dialog, as in the main menu.
func _apply_reality() -> void:
	var accent := reality.accent if reality != null else Color.WHITE
	settings_panel.accent = accent
	rule.color = accent
	_idle_style = resume_button.get_theme_stylebox("normal")
	var hover := resume_button.get_theme_stylebox("hover").duplicate() as StyleBoxTexture
	hover.modulate_color = accent
	_highlight_style = hover
	var pressed := resume_button.get_theme_stylebox("pressed").duplicate() as StyleBoxTexture
	pressed.modulate_color = accent.darkened(0.2)
	_pressed_style = pressed
	var font: Font = reality.font if reality != null else null
	if font != null:
		header.add_theme_font_override("font", font)
		header.material = reality.text_material
	header.add_theme_color_override("font_color", Color.WHITE)
	header.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	var widest := 0.0
	for button in _dialog_buttons():
		if font != null:
			button.add_theme_font_override("font", font)
		# The highlight below is drawn for mouse and keyboard alike.
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("pressed", _pressed_style)
		button.add_theme_stylebox_override("hover_pressed", _pressed_style)
		widest = maxf(widest, button.get_combined_minimum_size().x)
	# Wide enough for the "are you sure?" text, so asking does not resize it.
	for button: Button in [main_menu_button, quit_button]:
		var text := button.text
		button.text = CONFIRM_TEXT
		widest = maxf(widest, button.get_combined_minimum_size().x)
		button.text = text
	dialog_rows.custom_minimum_size.x = widest


## Only the focused button is highlighted (hovering takes focus), so the
## mouse and the keyboard never light up two buttons.
func _set_highlight(button: Button, highlighted: bool) -> void:
	# Hover looks like the rest: a button under a resting mouse while the
	# keyboard moved on stays dark.
	var look := _highlight_style if highlighted else _idle_style
	button.add_theme_stylebox_override("normal", look)
	button.add_theme_stylebox_override("hover", look)
	var asking := button == _confirming
	var idle := CONFIRM_COLOR if asking else IDLE_TEXT
	var lit := CONFIRM_COLOR if asking else Color.WHITE
	var text := lit if highlighted else idle
	for state in ["font_color", "font_focus_color", "font_hover_color"]:
		button.add_theme_color_override(state, text)
	for state in ["font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, lit)


func _focus_on_hover(button: Button) -> void:
	if button.focus_mode != Control.FOCUS_NONE and button.is_visible_in_tree():
		button.grab_focus()


func _on_button_focus_entered(button: Button) -> void:
	# Another button in focus takes back an "are you sure?".
	if _confirming != null and button != _confirming:
		_take_back_question()
	_set_highlight(button, true)


func _on_button_focus_exited(button: Button) -> void:
	if button == _confirming:
		_take_back_question()
	_set_highlight(button, false)


# --- Leaving the run -------------------------------------------------------

## First press: ask. Second press on the same button: do it.
func _ask_or_do(button: Button, action: Callable) -> void:
	if _confirming == button:
		_take_back_question()
		action.call()
		return
	_take_back_question()
	_confirming = button
	_confirm_back_text = button.text
	button.text = CONFIRM_TEXT
	_set_highlight(button, button.has_focus())


func _take_back_question() -> void:
	if _confirming == null:
		return
	var button := _confirming
	_confirming = null
	button.text = _confirm_back_text
	_set_highlight(button, button.has_focus())


func _return_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# --- Sounds ------------------------------------------------------------------

func _make_player(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = -6.0
	player.max_polyphony = 4
	add_child(player)
	return player


func _on_node_added(node: Node) -> void:
	if node is BaseButton and is_ancestor_of(node):
		_add_button_sounds(node)


func _add_button_sounds(button: BaseButton) -> void:
	if button.has_meta(&"button_sounds"):
		return
	button.set_meta(&"button_sounds", true)
	button.mouse_entered.connect(_on_button_hovered.bind(button))
	button.pressed.connect(_click_sound.play)


func _on_button_hovered(button: BaseButton) -> void:
	if not button.disabled and button.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_hover_sound.play()


# --- Settings ----------------------------------------------------------------

func _open_settings() -> void:
	_take_back_question()
	for button in _dialog_buttons():
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The settings button keeps focus until it is hidden under its copy.
		if button != settings_button:
			button.focus_mode = Control.FOCUS_NONE
	_settings_morph.open()


func _close_settings() -> void:
	if not _settings_morph.is_open():
		return
	_settings_morph.close()
	settings_button.focus_mode = Control.FOCUS_ALL
	settings_button.grab_focus()


func _on_settings_opened() -> void:
	settings_panel.first_focus().grab_focus()
	settings_button.focus_mode = Control.FOCUS_NONE


func _on_settings_closed() -> void:
	_set_dialog_input(true)


## The settings panel in the middle of the screen, as large as fits under
## the hint frame.
func _settings_rect() -> Rect2:
	return _settings_layout()[0]


func _hint_rect() -> Rect2:
	return _settings_layout()[1]


## [panel, hint frame]: the two stacked and centered together.
func _settings_layout() -> Array[Rect2]:
	var area := shade.get_global_rect()
	var hint_height := _settings_morph.hint_box.frame_height()
	var room := area.size - SETTINGS_MARGIN * 2.0 - Vector2(0.0, hint_height + HINT_GAP)
	var panel_size := room.min(SETTINGS_MAX).max(settings_panel.get_combined_minimum_size())
	var top := area.position.y + (area.size.y - panel_size.y - hint_height - HINT_GAP) / 2.0
	var left := area.position.x + (area.size.x - panel_size.x) / 2.0
	var hint_width := panel_size.x * HINT_SHARE
	return [
		Rect2(left, top + hint_height + HINT_GAP, panel_size.x, panel_size.y),
		Rect2(left + panel_size.x - hint_width, top, hint_width, hint_height),
	]


## The dialog's part of the settings animation: every row but «Настройки»
## fades, nearest first, then the dialog's frame, leaving the button alone.
func _fade_dialog(progress: float) -> void:
	var rows := dialog_rows.get_children()
	var settings_index := rows.find(settings_button)
	for i in rows.size():
		var row := rows[i] as CanvasItem
		if row == settings_button or row == null:
			continue
		var start := (absi(i - settings_index) - 1) * FADE_STAGGER
		row.modulate.a = 1.0 - clampf((progress - start) / FADE_LENGTH, 0.0, 1.0)
	dialog.self_modulate.a = 1.0 - clampf((progress - FRAME_FROM) / (FRAME_TO - FRAME_FROM), 0.0, 1.0)


func _dialog_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for row in dialog_rows.get_children():
		if row is Button:
			buttons.append(row)
	return buttons


# --- Inventory ---------------------------------------------------------------

func _open_inventory() -> void:
	_take_back_question()
	dialog.hide()
	inventory_panel.refresh(_mutations())
	inventory_panel.show()
	inventory_panel.back_button.grab_focus()


func _close_inventory() -> void:
	inventory_panel.hide()
	dialog.show()
	inventory_button.grab_focus()


func _mutations() -> NelvarMutationDirector:
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null:
		return null
	return player.get_node_or_null("Mutations") as NelvarMutationDirector
