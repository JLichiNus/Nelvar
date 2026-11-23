extends CanvasLayer

@export var settings_element: NelvarMenuElement

@onready var dialog: PanelContainer = %Dialog
@onready var resume_button: Button = %Resume
@onready var settings_button: Button = %Settings
@onready var settings_panel: NelvarSettingsPanel = %SettingsPanel
@onready var center: CenterContainer = $Shade/Center


func _ready() -> void:
	settings_panel.accent = settings_element.accent
	resume_button.pressed.connect(_resume)
	settings_button.pressed.connect(_open_settings)
	%MainMenu.pressed.connect(_return_to_menu)
	%Quit.pressed.connect(get_tree().quit)
	settings_panel.back_button.pressed.connect(_close_settings)
	settings_panel.dev_panel_toggled.connect(_on_dev_panel_toggled)


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if not visible:
		get_tree().paused = true
		show()
		resume_button.grab_focus()
	elif settings_panel.visible:
		_close_settings()
	else:
		_resume()


func _resume() -> void:
	hide()
	get_tree().paused = false


func _open_settings() -> void:
	dialog.hide()
	settings_panel.play_open()
	settings_panel.fullscreen_check.grab_focus()


func _close_settings() -> void:
	settings_panel.close_now()
	dialog.show()
	settings_button.grab_focus()


## The developer panel opens left of the settings: center the pair, not the
## settings alone.
func _on_dev_panel_toggled(open: bool) -> void:
	var dev := settings_panel.dev_panel
	center.offset_left = dev.get_combined_minimum_size().x + dev.GAP if open else 0.0


func _return_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _exit_tree() -> void:
	if visible:
		get_tree().paused = false
