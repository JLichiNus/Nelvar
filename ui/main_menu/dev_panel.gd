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
@onready var start_on_earth_check: CheckButton = %StartOnEarth
@onready var start_in_fire_check: CheckButton = %StartInFire
@onready var start_hint: Label = %StartHint


func _ready() -> void:
	super()
	top_level = true
	start_in_void_check.set_pressed_no_signal(GameSettings.start_in_void)
	start_in_void_check.toggled.connect(GameSettings.set_start_in_void)
	GameSettings.start_in_void_changed.connect(start_in_void_check.set_pressed_no_signal)
	start_on_earth_check.set_pressed_no_signal(GameSettings.start_on_earth)
	start_on_earth_check.toggled.connect(GameSettings.set_start_on_earth)
	GameSettings.start_on_earth_changed.connect(start_on_earth_check.set_pressed_no_signal)
	start_in_fire_check.set_pressed_no_signal(GameSettings.start_in_fire)
	start_in_fire_check.toggled.connect(GameSettings.set_start_in_fire)
	GameSettings.start_in_fire_changed.connect(start_in_fire_check.set_pressed_no_signal)
	# The start options exclude each other; the hint names what "Играть" opens.
	GameSettings.start_in_void_changed.connect(_update_hint.unbind(1))
	GameSettings.start_on_earth_changed.connect(_update_hint.unbind(1))
	GameSettings.start_in_fire_changed.connect(_update_hint.unbind(1))
	_update_hint()


func _update_hint() -> void:
	if GameSettings.start_in_void:
		start_hint.text = "«Играть» откроет Пустоту"
	elif GameSettings.start_on_earth:
		start_hint.text = "«Играть» откроет земляную долину"
	elif GameSettings.start_in_fire:
		start_hint.text = "«Играть» откроет огненную кузню"
	else:
		start_hint.text = "«Играть» откроет небесные острова"


## Puts the panel to the left of `anchor` (a rect in canvas coordinates),
## top edges aligned.
func place_left_of(anchor: Rect2) -> void:
	reset_size()
	position = Vector2(maxf(SCREEN_MARGIN, anchor.position.x - GAP - size.x), anchor.position.y)
