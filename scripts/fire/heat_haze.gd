class_name NelvarHeatHaze
extends CanvasLayer
## Heat haze of the fire forge: a full-screen pass (heat_haze.gdshader) over the world
## that makes the air shimmer above the lava, the fissures and the eruptions. Drawn
## under the HUD; reads the light map NelvarFireMain gives it.

const SHADER := preload("res://scripts/fire/heat_haze.gdshader")

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
	var viewport := get_viewport()
	var to_world := viewport.get_canvas_transform().affine_inverse()
	_material.set_shader_parameter("view_origin", to_world * Vector2.ZERO)
	_material.set_shader_parameter("view_scale", to_world.x.length())
	_material.set_shader_parameter("time", _time)
