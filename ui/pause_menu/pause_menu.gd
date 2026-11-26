extends CanvasLayer
## Pause: resume, inventory, settings, back to the main menu, quit. The
## settings grow out of their button like in the main menu
## (NelvarPanelMorph): the dialog's other rows and its frame fade first.

## Settings progress (0..1) over which the dialog's other rows fade, nearest
## to «Настройки» first, and then its frame.
const FADE_LENGTH := 0.18
const FADE_STAGGER := 0.05
const FRAME_FROM := 0.1
const FRAME_TO := 0.35
## Largest settings panel; smaller windows keep this margin around it.
const SETTINGS_MAX := Vector2(1150, 640)
const SETTINGS_MARGIN := Vector2(96, 64)

@export var settings_element: NelvarMenuElement

var _settings_morph: NelvarPanelMorph

@onready var dialog: PanelContainer = %Dialog
@onready var resume_button: Button = %Resume
@onready var settings_button: Button = %Settings
@onready var inventory_button: Button = %Inventory
@onready var inventory_panel: NelvarMutationInventory = %InventoryPanel
@onready var settings_panel: NelvarSettingsPanel = %SettingsPanel
@onready var shade: ColorRect = $Shade
@onready var dialog_rows: VBoxContainer = $Shade/Center/Dialog/Rows


func _ready() -> void:
	settings_panel.accent = settings_element.accent
	resume_button.pressed.connect(_resume)
	settings_button.pressed.connect(_open_settings)
	inventory_button.pressed.connect(_open_inventory)
	inventory_panel.back_button.pressed.connect(_close_inventory)
	%MainMenu.pressed.connect(_return_to_menu)
	%Quit.pressed.connect(GameMusic.quit_game)
	settings_panel.back_button.pressed.connect(_close_settings)
	# Drawn above the settings panel: added after it.
	_settings_morph = NelvarPanelMorph.new()
	shade.add_child(_settings_morph)
	_settings_morph.setup(settings_panel, settings_button, settings_button.get_theme_stylebox("hover"))
	_settings_morph.target_rect = _settings_rect
	_settings_morph.progress_changed.connect(_fade_dialog)
	_settings_morph.opened.connect(_on_settings_opened)
	_settings_morph.closed.connect(_on_settings_closed)


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if not visible:
		get_tree().paused = true
		# Only scenes with a mutating player have an inventory.
		inventory_button.visible = _mutations() != null
		show()
		resume_button.grab_focus()
	elif _settings_morph.is_active():
		# Esc while the settings are already closing waits for them.
		_close_settings()
	elif inventory_panel.visible:
		_close_inventory()
	else:
		_resume()


func _resume() -> void:
	hide()
	get_tree().paused = false


func _open_settings() -> void:
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
	for button in _dialog_buttons():
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.focus_mode = Control.FOCUS_ALL


## The settings panel in the middle of the screen, as large as fits.
func _settings_rect() -> Rect2:
	var area := shade.get_global_rect()
	var panel_size := (area.size - SETTINGS_MARGIN * 2.0).min(SETTINGS_MAX)
	return Rect2(area.position + (area.size - panel_size) / 2.0, panel_size).abs()


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


func _open_inventory() -> void:
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


func _return_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _exit_tree() -> void:
	if visible:
		get_tree().paused = false
