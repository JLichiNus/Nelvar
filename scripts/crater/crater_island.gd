class_name NelvarCraterIsland
extends Node2D
## A floe of magma crust on the volcano's lake on screen: dark plates with glowing seams
## drawn by crater_island.gdshader from a mask baked once:
##   R — how far in from the edge, in quarters of an art pixel (255 from about 64 in);
##       sinking eats it from the edge up to Isle.sink_depth() (the same rule as
##       NelvarCraterData.Isle.depth_at);
##   G — the south face: 1 on the lowest row above the lava, 2 on the one above it;
##   A — 255 on the floe.
## The pattern belongs to the floe and floats with it. The node sits on whole art
## pixels (the floe's exact place is the logic's); NelvarCraterMain syncs it with the
## shared clock every frame.

const SHADER := preload("res://scripts/crater/crater_island.gdshader")
const STEP := NelvarFireData.PIXEL

var isle: NelvarCraterData.Isle
var mask: ImageTexture
## Art pixels from the node's origin to the mask's corner.
var reach := 0

var _material: ShaderMaterial
var _rect := Rect2()


func setup(spec: NelvarCraterData.Isle, image: Image) -> void:
	isle = spec
	name = "Isle_%d" % spec.id
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	reach = (image.get_width() - 1) / 2
	mask = ImageTexture.create_from_image(image)
	_rect = Rect2(Vector2(-reach, -reach) * STEP, Vector2(image.get_size()) * STEP)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	var rng := RandomNumberGenerator.new()
	rng.seed = spec.appearance_seed
	_material.set_shader_parameter("seed_offset", Vector2(rng.randi_range(-4096, 4096), rng.randi_range(-4096, 4096)))
	_material.set_shader_parameter("sink_px", spec.sink_depth() / STEP)
	material = _material
	sync(0.0, 0.0)


## The mask of a floe's shape (on a worker thread: no textures here).
static func bake_mask(spec: NelvarCraterData.Isle) -> Image:
	var r := ceili(spec.outer / STEP) + 2
	var size := r * 2 + 1
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var inside := PackedFloat32Array()
	inside.resize(size * size)
	for y in size:
		for x in size:
			var local := (Vector2(x - r, y - r) + Vector2(0.5, 0.5)) * STEP
			inside[y * size + x] = spec.signed_distance(local)
	for y in size:
		for x in size:
			var depth := inside[y * size + x]
			if depth <= 0.0:
				continue
			var face := 0
			if y + 1 >= size or inside[(y + 1) * size + x] <= 0.0:
				face = 1
			elif y + 2 >= size or inside[(y + 2) * size + x] <= 0.0:
				face = 2
			image.set_pixel(x, y, Color8(clampi(roundi(depth / STEP * 4.0), 1, 255), face, 0, 255))
	return image


func _draw() -> void:
	if mask != null:
		draw_texture_rect(mask, _rect, false)


## Place and state at `time` (the shared clock), on whole art pixels; `clock` animates.
func sync(time: float, clock: float) -> void:
	position = (isle.position_at(time) / STEP).round() * STEP
	_material.set_shader_parameter("time", clock)
	_material.set_shader_parameter("sink", isle.sink_at(time))
	_material.set_shader_parameter("warn", isle.warn_at(time))
	_material.set_shader_parameter("hot", isle.hot_at(time))
