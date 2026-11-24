class_name NelvarLocationCursor
extends Node
## Mouse cursor of a location: put one in a game scene and it shows that
## location's cursor (the same arrows as the main menu realities,
## tools/gen_ui.py) for as long as the scene is open.

## Tip of the cursors: art pixel (1, 1) at 2x.
const HOTSPOT := Vector2(2, 2)

@export var cursor: Texture2D


static func apply(texture: Texture2D) -> void:
	Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, HOTSPOT)


func _enter_tree() -> void:
	apply(cursor)


func _exit_tree() -> void:
	apply(null)
