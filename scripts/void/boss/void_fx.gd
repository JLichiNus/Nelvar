class_name NelvarVoidFx
extends RefCounted
## Shared effects of the Void fight: soft violet light that the boss and its attacks
## cast on the dark arena, one-shot bursts of pixel sparks, and access to the
## screen effects (NelvarVoidScreen). Lights and particles are cheap ones: a few
## PointLight2D at a time and CPU particles with tiny square textures.

const VIOLET := Color(0.62, 0.4, 1.0)
const PALE := Color(0.9, 0.84, 1.0)
const DEEP := Color(0.32, 0.12, 0.7)
const DARK := Color(0.03, 0.01, 0.07)
## Particles are squares this many world units wide, on the art's 3-unit grid.
const SPARK_SIZE := 3.0

static var _light_texture: Texture2D
static var _spark_texture: Texture2D


## A soft round light: bright centre, long fade. Shared by every light here.
static func light_texture() -> Texture2D:
	if _light_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.65, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55),
			Color(1, 1, 1, 0.12), Color(1, 1, 1, 0)])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 128
		texture.height = 128
		_light_texture = texture
	return _light_texture


static func spark_texture() -> Texture2D:
	if _spark_texture == null:
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_spark_texture = ImageTexture.create_from_image(image)
	return _spark_texture


## Light of `color` reaching about `radius` world units.
static func make_light(color: Color, energy: float, radius: float) -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = light_texture()
	light.texture_scale = radius / 64.0
	light.color = color
	light.energy = energy
	light.blend_mode = Light2D.BLEND_MODE_ADD
	return light


## A light that flares up at `at` and dies away by itself.
static func flash_light(parent: Node, at: Vector2, color: Color, energy: float, radius: float,
		time: float) -> void:
	var light := make_light(color, energy, radius)
	light.position = at
	parent.add_child(light)
	var tween := light.create_tween()
	tween.tween_property(light, "energy", 0.0, time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_callback(light.queue_free)


## Pixel sparks that fly from `at` (or a `ring` of that radius) and fade; frees itself.
## A negative `speed` pulls them inwards instead.
static func burst(parent: Node, at: Vector2, amount: int, color: Color, speed: float,
		lifetime: float, ring := 0.0, additive := true) -> CPUParticles2D:
	var particles := spark_emitter(color, additive)
	particles.position = at
	particles.amount = amount
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.lifetime = lifetime
	particles.spread = 180.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = absf(speed) * 0.45
	particles.initial_velocity_max = absf(speed)
	particles.damping_min = absf(speed) * 0.6
	particles.damping_max = absf(speed) * 1.4
	if ring > 0.0:
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
		particles.emission_sphere_radius = ring
	if speed < 0.0:
		particles.initial_velocity_min = 0.0
		particles.initial_velocity_max = 20.0
		particles.radial_accel_min = speed * 2.2
		particles.radial_accel_max = speed * 1.6
		particles.damping_min = 0.0
		particles.damping_max = 0.0
	parent.add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
	return particles


## A square-pixel particle system that fades out over its life.
static func spark_emitter(color: Color, additive := true) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.texture = spark_texture()
	particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	particles.scale_amount_min = SPARK_SIZE
	particles.scale_amount_max = SPARK_SIZE * 2.0
	particles.local_coords = false
	particles.color = color
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	ramp.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	particles.color_ramp = ramp
	if additive:
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		particles.material = add
	return particles


static func screen(node: Node) -> NelvarVoidScreen:
	if not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group("void_screen") as NelvarVoidScreen


## Shockwave rippling out from a world point (and a little glitch if `strength` is big).
static func shock(node: Node, at: Vector2, strength: float) -> void:
	var effects := screen(node)
	if effects != null:
		effects.shock(at, strength)


static func glitch(node: Node, duration: float, strength: float) -> void:
	var effects := screen(node)
	if effects != null:
		effects.glitch(duration, strength)


static func flash(node: Node, color: Color, amount: float, duration: float) -> void:
	var effects := screen(node)
	if effects != null:
		effects.flash(color, amount, duration)


## Everything slows for a moment (real time), then speeds back up.
static func slow_motion(node: Node, scale: float, duration: float) -> void:
	var effects := screen(node)
	if effects != null:
		effects.slow_motion(scale, duration)
