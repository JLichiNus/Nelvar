class_name NelvarCloudSea
extends CanvasLayer
## Sea of clouds below the floating islands, drawn behind the world by
## cloud_sea.gdshader. The sea lies deeper than the islands: it follows the camera
## only by `parallax` and drifts with the wind, sliding smoothly underneath.
##
## The shader runs once per cloud pixel in a small viewport (a cloud pixel spans many
## screen pixels); a sprite stretches it over the screen, shifted by the sub-pixel
## remainder so the sea moves smoothly instead of in whole-pixel steps.

const SEA_SHADER := preload("res://scripts/world/cloud_sea.gdshader")

## 1 = moves together with the islands, 0 = fixed on screen.
@export_range(0.0, 1.0, 0.01) var parallax: float = 0.6
## Drift of the sea, world units per second. The wind blows to the right.
@export var wind := Vector2(9.0, 1.2)
## World units per cloud pixel; main.gd matches it to the terrain pixel size.
@export var texel_size: float = 4.0
## Share of the sea torn open to the sky below: 0 = solid cover.
@export_range(0.0, 0.6, 0.01) var hole_amount: float = 0.14
## What fills the backdrop; the Void draws its own sky with the same uniforms.
@export var shader: Shader = SEA_SHADER

var _viewport: SubViewport
var _sea: ColorRect
var _sprite: Sprite2D
var _material: ShaderMaterial
var _drift := Vector2.ZERO
var _time := 0.0


func _ready() -> void:
	layer = -1
	# The sea keeps drifting under the pause menu. Late priority: read the camera
	# only after it has moved this frame, so the sea never lags behind it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100
	_viewport = SubViewport.new()
	_viewport.name = "SeaPixels"
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.size = Vector2i(2, 2)
	add_child(_viewport)
	_material = ShaderMaterial.new()
	_material.shader = shader
	_sea = ColorRect.new()
	_sea.material = _material
	_viewport.add_child(_sea)
	_sprite = Sprite2D.new()
	_sprite.name = "Sea"
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.texture = _viewport.get_texture()
	add_child(_sprite)
	_update_view()


## Each world gets its own cloud layout.
func set_world_seed(world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:clouds" % world_seed).hash()
	_material.set_shader_parameter("seed_offset",
		Vector2(rng.randi_range(-8192, 8192), rng.randi_range(-8192, 8192)))


## The backdrop's ShaderMaterial, for shader-specific parameters.
func backdrop_material() -> ShaderMaterial:
	return _material


## Draws over the world instead of behind it (the earth valley's cloud shadows):
## on canvas layer `on_layer`, blended by `blend` (e.g. a multiply CanvasItemMaterial).
func use_as_overlay(on_layer: int, blend: Material) -> void:
	layer = on_layer
	_sprite.material = blend


func _process(delta: float) -> void:
	_drift += wind * delta
	_time += delta
	_update_view()


func _update_view() -> void:
	var viewport := get_viewport()
	var to_world := viewport.get_canvas_transform().affine_inverse()
	var screen := viewport.get_visible_rect().size
	var top_left := to_world * Vector2.ZERO
	var extent := to_world.basis_xform(screen)
	var center := top_left + extent * 0.5
	# Sea coordinates of the screen's top-left corner, in cloud pixels.
	var corner := (top_left + center * (parallax - 1.0) - _drift) / texel_size
	var base := corner.floor()
	var pixels := Vector2i((extent / texel_size).ceil()) + Vector2i(2, 2)
	if _viewport.size != pixels:
		_viewport.size = pixels
		_sea.size = Vector2(pixels)
	var pixel_on_screen := screen.x / extent.x * texel_size
	_sprite.scale = Vector2.ONE * pixel_on_screen
	_sprite.position = -(corner - base) * pixel_on_screen
	_material.set_shader_parameter("base_pixel", base)
	_material.set_shader_parameter("sea_size", Vector2(pixels))
	_material.set_shader_parameter("breath_time", _time)
	_material.set_shader_parameter("hole_amount", hole_amount)
