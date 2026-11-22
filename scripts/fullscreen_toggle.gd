extends Node
## Autoload: toggles between fullscreen and windowed mode on F11
## (input action "toggle_fullscreen"). The game starts in fullscreen
## via display/window/size/mode in project.godot.

const WINDOWED_SIZE := Vector2i(1280, 800)


func _ready() -> void:
	# Keep working while the game tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	var window := get_window()
	if window.mode == Window.MODE_FULLSCREEN or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		window.mode = Window.MODE_WINDOWED
		# Starting in fullscreen leaves no previous windowed size to restore,
		# so set it explicitly and center the window on its current screen.
		window.size = WINDOWED_SIZE
		window.move_to_center()
	else:
		window.mode = Window.MODE_FULLSCREEN
