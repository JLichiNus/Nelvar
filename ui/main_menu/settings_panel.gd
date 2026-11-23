class_name NelvarSettingsPanel
extends NelvarMenuPanel
## "Меню разработчика" opens the developer panel to the left of this one;
## it closes together with the settings. The screen that holds this panel
## makes room for it on `dev_panel_toggled`.

signal dev_panel_toggled(open: bool)

@onready var fullscreen_check: CheckButton = %Fullscreen
@onready var info_panel_check: CheckButton = %InfoPanel
@onready var dev_menu_button: Button = %DevMenu
@onready var dev_panel: NelvarDevPanel = %DevPanel


func _ready() -> void:
	super()
	fullscreen_check.set_pressed_no_signal(FullscreenToggle.is_fullscreen())
	fullscreen_check.toggled.connect(FullscreenToggle.set_fullscreen)
	FullscreenToggle.fullscreen_changed.connect(fullscreen_check.set_pressed_no_signal)
	info_panel_check.set_pressed_no_signal(GameSettings.show_info_panel)
	info_panel_check.toggled.connect(GameSettings.set_show_info_panel)
	GameSettings.info_panel_changed.connect(info_panel_check.set_pressed_no_signal)
	dev_menu_button.toggled.connect(_set_dev_panel_open)
	# Arrow keys move between the button and the panel it opened.
	dev_menu_button.focus_neighbor_left = dev_menu_button.get_path_to(dev_panel.start_in_void_check)
	dev_panel.start_in_void_check.focus_neighbor_right = \
		dev_panel.start_in_void_check.get_path_to(dev_menu_button)
	# Follow this panel when the window is resized.
	item_rect_changed.connect(_place_dev_panel)


func play_open() -> void:
	_close_dev_panel()
	super()


func play_close() -> void:
	_close_dev_panel()
	super()


func close_now() -> void:
	_close_dev_panel()
	super()


func _set_dev_panel_open(open: bool) -> void:
	dev_panel_toggled.emit(open)
	if open:
		# After the holder has re-laid this panel out to make room (its
		# containers re-sort deferred, before this call).
		_open_dev_panel.call_deferred()
	else:
		dev_panel.play_close()


func _open_dev_panel() -> void:
	if not dev_menu_button.button_pressed:
		return
	dev_panel.place_left_of(get_global_rect())
	dev_panel.play_open()


func _close_dev_panel() -> void:
	if not dev_menu_button.button_pressed:
		return
	dev_menu_button.set_pressed_no_signal(false)
	dev_panel.close_now()
	dev_panel_toggled.emit(false)


func _place_dev_panel() -> void:
	if dev_panel.visible and dev_menu_button.button_pressed:
		dev_panel.place_left_of(get_global_rect())
