class_name NelvarBlizzard
extends CanvasLayer
## The blizzard over the screen (blizzard.gdshader): a pale veil and dashes of snow as
## strong as the blizzard where the player stands, and before one arrives, snow
## streaming along the edge of the screen it comes from. Drawn over the world, under
## the HUD, like the forge's heat haze. NelvarIceMain sets `strength`, `warning` and
## `warning_side`.

const SHADER := preload("res://scripts/ice/blizzard.gdshader")

var strength := 0.0
var warning := 0.0
var warning_side := Vector2.RIGHT

var _rect: ColorRect
var _material: ShaderMaterial
var _time := 0.0


func _ready() -> void:
	layer = 2
	process_priority = 100
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect.material = _material
	add_child(_rect)


func material() -> ShaderMaterial:
	return _material


func _process(delta: float) -> void:
	_time += delta
	_rect.visible = strength > 0.005 or warning > 0.005
	if not _rect.visible:
		return
	var viewport := get_viewport()
	var to_world := viewport.get_canvas_transform().affine_inverse()
	_material.set_shader_parameter("view_origin", to_world * Vector2.ZERO)
	_material.set_shader_parameter("view_scale", to_world.x.length())
	_material.set_shader_parameter("texel_size", float(NelvarIceData.PIXEL))
	_material.set_shader_parameter("time", _time)
	_material.set_shader_parameter("strength", strength)
	_material.set_shader_parameter("warning", warning)
	_material.set_shader_parameter("warning_side", warning_side)
