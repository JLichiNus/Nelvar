extends Node
## Autoload: F11 (input action "toggle_fullscreen") switches between a window
## and the full-screen mode used last, from anywhere, also while paused. The
## window mode itself is a setting: GameSettings.window_mode.


func _ready() -> void:
	# Keep working while the game tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		GameSettings.toggle_full_screen()
		get_viewport().set_input_as_handled()
