class_name NelvarDevPanel
extends NelvarMenuPanel
## Developer settings: opened from the settings panel's "Меню разработчика"
## button and shown to the left of it. Top-level, so the settings panel's
## container does not lay it out; the settings panel places it.

## Gap between this panel and the settings panel, in UI units (3 art pixels).
const GAP := 18.0
## Smallest distance kept from the screen edge.
const SCREEN_MARGIN := 12.0

@onready var start_in_void_check: CheckButton = %StartInVoid


func _ready() -> void:
	super()
	top_level = true
	start_in_void_check.set_pressed_no_signal(GameSettings.start_in_void)
	start_in_void_check.toggled.connect(GameSettings.set_start_in_void)
	GameSettings.start_in_void_changed.connect(start_in_void_check.set_pressed_no_signal)


## Puts the panel to the left of `anchor` (a rect in canvas coordinates),
## top edges aligned.
func place_left_of(anchor: Rect2) -> void:
	reset_size()
	position = Vector2(maxf(SCREEN_MARGIN, anchor.position.x - GAP - size.x), anchor.position.y)
