extends Node
## Autoload: what the screen settings draw over the whole game, menus included
## (GameSettings): the brightness curve and the frames-per-second counter.
## Both sit on canvas layers above everything else and ignore the mouse.
## Brightness at 100% is not drawn at all, so it costs nothing by default.

const SHADER := preload("res://ui/brightness.gdshader")
## Above every game layer (the pause menu is 10); the counter above the
## brightness pass, so it reads the same at any brightness.
const BRIGHTNESS_LAYER := 126
const COUNTER_LAYER := 127
const COUNTER_MARGIN := 12.0
const COUNTER_FONT_SIZE := 22
const COUNTER_INTERVAL := 0.25

var _brightness: ColorRect
var _counter: Label
var _counter_wait := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var brightness_layer := CanvasLayer.new()
	brightness_layer.layer = BRIGHTNESS_LAYER
	add_child(brightness_layer)
	_brightness = ColorRect.new()
	_brightness.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brightness.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	_brightness.material = material
	brightness_layer.add_child(_brightness)

	var counter_layer := CanvasLayer.new()
	counter_layer.layer = COUNTER_LAYER
	add_child(counter_layer)
	_counter = Label.new()
	_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The pixel font is a bitmap: without this it is drawn with the
	# project's default (linear) filter and comes out blurry.
	_counter.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_counter.add_theme_font_size_override("font_size", COUNTER_FONT_SIZE)
	counter_layer.add_child(_counter)
	# Grows to the left from the top right corner as the number gets longer.
	_counter.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_counter.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_counter.offset_right = -COUNTER_MARGIN
	_counter.offset_top = COUNTER_MARGIN

	GameSettings.display_changed.connect(_apply)
	_apply()


func _process(delta: float) -> void:
	if not _counter.visible:
		return
	_counter_wait -= delta
	if _counter_wait <= 0.0:
		_counter_wait = COUNTER_INTERVAL
		_counter.text = "%d FPS" % roundi(Engine.get_frames_per_second())


func _apply() -> void:
	var gamma := GameSettings.brightness
	_brightness.visible = not is_equal_approx(gamma, 1.0)
	(_brightness.material as ShaderMaterial).set_shader_parameter("gamma", gamma)
	_counter.visible = GameSettings.show_fps
	_counter_wait = 0.0
