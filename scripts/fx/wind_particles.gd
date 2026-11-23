class_name NelvarWindParticles
extends CPUParticles2D
## Wind streaks over the world, as in the air reality of the main menu: thin white
## dashes flying with the wind. They are emitted over the camera view but live in world
## space, so they stay in the world while the camera moves.

## Streaks alive per million square world units of view.
@export var density: float = 56.0
## World units per streak pixel; main.gd matches it to the terrain pixel size.
@export var texel_size: float = 4.0:
	set(value):
		texel_size = value
		scale_amount_min = value
		scale_amount_max = value
## Streak length in its own pixels (the menu uses 1 x 7).
@export var streak_length: int = 7
## The wind blows to the right, slightly downwards — like the menu and the tree crowns.
@export var wind_direction := Vector2(1.0, 0.08)
## Speed range, world units per second.
@export var speed := Vector2(360.0, 580.0)

## View area the current particle amount was sized for.
var _area := 0.0


func _ready() -> void:
	# The wind does not stop under the pause menu. Late priority: follow the camera
	# only after it has moved this frame.
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	local_coords = false
	emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particle_flag_align_y = true
	direction = wind_direction
	spread = 6.0
	gravity = Vector2.ZERO
	initial_velocity_min = speed.x
	initial_velocity_max = speed.y
	lifetime = 1.8
	preprocess = lifetime
	texel_size = texel_size
	var image := Image.create(1, streak_length, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	texture = ImageTexture.create_from_image(image)
	color = Color(1.0, 1.0, 1.0, 0.6)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.8, 1.0])
	ramp.colors = PackedColorArray([
		Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	color_ramp = ramp
	_follow_view()


func _process(_delta: float) -> void:
	_follow_view()


func _follow_view() -> void:
	var viewport := get_viewport()
	var to_world := viewport.get_canvas_transform().affine_inverse()
	var top_left := to_world * Vector2.ZERO
	var size := to_world.basis_xform(viewport.get_visible_rect().size)
	global_position = top_left + size * 0.5
	emission_rect_extents = size * 0.5 + Vector2.ONE * texel_size * streak_length
	# Keep the same density when zooming; resizing restarts the system, so only do it
	# when the view changes noticeably.
	var area := size.x * size.y
	if absf(area - _area) > _area * 0.15:
		_area = area
		amount = clampi(roundi(area / 1.0e6 * density), 12, 600)
		restart()
