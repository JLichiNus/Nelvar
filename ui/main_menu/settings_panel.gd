class_name NelvarSettingsPanel
extends NelvarMenuPanel

@onready var fullscreen_check: CheckButton = %Fullscreen
@onready var info_panel_check: CheckButton = %InfoPanel


func _ready() -> void:
	super()
	fullscreen_check.set_pressed_no_signal(FullscreenToggle.is_fullscreen())
	fullscreen_check.toggled.connect(FullscreenToggle.set_fullscreen)
	FullscreenToggle.fullscreen_changed.connect(fullscreen_check.set_pressed_no_signal)
	info_panel_check.set_pressed_no_signal(GameSettings.show_info_panel)
	info_panel_check.toggled.connect(GameSettings.set_show_info_panel)
	GameSettings.info_panel_changed.connect(info_panel_check.set_pressed_no_signal)
