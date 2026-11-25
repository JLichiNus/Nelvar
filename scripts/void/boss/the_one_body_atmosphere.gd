extends RefCounted
## Paints the Only One's corona, ground seal and orbiting debris on its art grid.
## The large fields are baked once; only their modulation and the small moving
## details change during the fight.

const PIXEL := NelvarTheOnePainter.TEXEL
const VIOLET := Color(0.62, 0.4, 1.0)
const PALE := Color(0.9, 0.84, 1.0)
const DEEP := Color(0.32, 0.12, 0.7)
const DARK := Color(0.02, 0.0, 0.05)
const SHARDS: Array[int] = [8, 14, 19, 24]
const ORBIT_SPEED: Array[float] = [0.44, 0.68, 0.91, 1.16]

static var _pools: Array[ImageTexture] = []
static var _seals: Array[ImageTexture] = []
static var _corona: ImageTexture
static var _core_glow: ImageTexture


static func prepare() -> void:
	if not _pools.is_empty():
		return
	for i in 5:
		_bake_ground(0.86 + i * 0.05)

	var corona_image := Image.create(65, 65, false, Image.FORMAT_RGBA8)
	for y in corona_image.get_height():
		for x in corona_image.get_width():
			var p := Vector2(x - 32, y - 32) / Vector2(24.0, 30.0)
			var r := p.length()
			var edge := 0.82 + 0.04 * sin(p.angle() * 9.0) + 0.025 * cos(p.angle() * 17.0)
			var grain := NelvarPixelArt.hash01(x, y, 0xD0)
			var inner := clampf((edge - r) * 5.0, 0.0, 1.0)
			var rim := maxf(0.0, 1.0 - absf(r - edge) * 14.0)
			var alpha := maxf(inner * 0.67, rim * (0.17 + 0.22 * grain))
			if alpha > 0.01:
				var ink := DARK.lerp(DEEP, rim * (0.38 + 0.45 * grain))
				corona_image.set_pixel(x, y, Color(ink, alpha))
	_corona = ImageTexture.create_from_image(corona_image)
	var core_image := Image.create(19, 13, false, Image.FORMAT_RGBA8)
	for y in core_image.get_height():
		for x in core_image.get_width():
			var p := Vector2(x - 9, y - 6)
			var halo := maxf(0.0, 1.0 - (p / Vector2(7.0, 5.0)).length())
			var ray := maxf(0.0, 1.0 - absf(p.x) / 9.0) * maxf(0.0, 1.0 - absf(p.y) * 0.6)
			var alpha := roundf(maxf(halo * 0.9, ray * 0.58) * 7.0) / 7.0
			core_image.set_pixel(x, y, Color(DEEP.lerp(VIOLET, halo), alpha))
	_core_glow = ImageTexture.create_from_image(core_image)


static func _bake_ground(breath: float) -> void:
	var pool_image := Image.create(73, 27, false, Image.FORMAT_RGBA8)
	var seal_image := Image.create(73, 27, false, Image.FORMAT_RGBA8)
	for y in pool_image.get_height():
		for x in pool_image.get_width():
			var p := Vector2(x - 36, y - 13) / (Vector2(32.0, 10.0) * breath)
			var r := p.length()
			var angle := p.angle()
			var edge := 0.9 + 0.08 * sin(angle * 7.0) + 0.04 * cos(angle * 11.0)
			var dither := NelvarPixelArt.bayer(Vector2i(x, y)) / 16.0
			var shade := clampf((edge - r) * 3.0, 0.0, 1.0)
			if shade > dither:
				pool_image.set_pixel(x, y, Color(DARK.lerp(DEEP, 0.13 * r), 0.91))
			var sector := absf(wrapf(angle, -PI / 6.0, PI / 6.0))
			var ink := 0.0
			if absf(r - 0.79) < 0.054 and sector > 0.075:
				ink = 0.62
			if absf(r - 0.59) < 0.047 and sector < 0.18:
				ink = 0.28
			if absf(r - 0.89) * 4.0 + sector < 0.2:
				ink = 0.92
			if ink > 0.0:
				seal_image.set_pixel(x, y, Color(VIOLET, ink))
	_pools.append(ImageTexture.create_from_image(pool_image))
	_seals.append(ImageTexture.create_from_image(seal_image))


static func draw_shadow(layer: Node2D, center: Vector2, time: float, phase: int,
		presence: float, flare: float, feet: Vector2) -> void:
	_draw_field(layer, _pools[_breath_frame(time, flare)], Vector2.ZERO, presence)
	var veil := 0.72 + phase * 0.07 + 0.07 * sin(time * 3.5)
	_draw_field(layer, _corona, center, presence * veil)
	if phase == 3:
		_draw_tethers(layer, time, presence, feet)


static func draw_light(layer: Node2D, center: Vector2, core: Vector2, time: float,
		phase: int, presence: float, flare: float, charge: float) -> void:
	var pulse := 0.36 + 0.07 * sin(time * 3.0) + 0.06 * phase + 0.18 * charge + 0.24 * flare
	var seal := _seals[_breath_frame(time, flare)]
	_draw_field(layer, seal, Vector2.ZERO, clampf(pulse, 0.0, 1.0) * presence)
	_draw_fissures(layer, time, phase, presence, pulse, flare)
	_draw_orbit(layer, center, time, phase, presence, flare)
	var glimmer := 0.37 + 0.13 * sin(time * 3.8) + 0.32 * charge + 0.24 * flare
	_draw_field(layer, _core_glow, core, glimmer * presence)
	_draw_charge(layer, core, time, presence * charge)


static func _breath_frame(time: float, flare: float) -> int:
	return clampi(roundi(1.2 + sin(time * 2.5) + 2.6 * flare), 0, _pools.size() - 1)


static func _draw_field(layer: Node2D, texture: ImageTexture, center: Vector2, opacity: float) -> void:
	var size := texture.get_size() * PIXEL
	var corner := _snap(center) - ((texture.get_size() * 0.5).floor() * PIXEL)
	layer.draw_texture_rect(texture, Rect2(corner, size), false, Color(1.0, 1.0, 1.0, opacity))


## Broken lines inside the seal light from the center out during a flare.
static func _draw_fissures(layer: Node2D, time: float, phase: int, presence: float,
		pulse: float, flare: float) -> void:
	for ray in 7:
		var angle := ray * TAU / 7.0 + 0.24
		var axis := Vector2.from_angle(angle)
		var extent := 9 + (ray * 7) % 9 + phase
		var wave := 0.5 + 0.5 * sin(time * 3.6 + float(ray) * 1.8)
		for step in range(3, extent):
			var along := float(step) / float(extent)
			var kink := float((step / 3 + ray * 7) % 5 - 2)
			var point := (axis * step + axis.orthogonal() * kink) * Vector2(PIXEL, PIXEL * 0.36)
			var front := maxf(0.0, 1.0 - absf(along - (1.0 - flare)) * 3.0)
			var surge := front * flare
			var ink := VIOLET.lerp(PALE, surge)
			var glow := (1.0 - along) * pulse * wave + surge * 0.72
			_pixel(layer, point, Color(ink, clampf(glow, 0.0, 0.9) * presence))


## Thin arcs frame the upper body. Shards run along two tilted orbits at
## different speeds, with the near side catching more light.
static func _draw_orbit(layer: Node2D, center: Vector2, time: float, phase: int,
		presence: float, flare: float) -> void:
	var turn := time * ORBIT_SPEED[phase]
	for arc in 5:
		var start := turn * 0.28 + arc * TAU / 5.0
		for step in 10:
			var angle := start + step * 0.052
			var point := center + Vector2.from_angle(angle) * Vector2(64.0, 80.0)
			var glint := 0.5 + 0.5 * sin(turn * 2.0 - arc + step * 0.3)
			var ink := DEEP.lerp(VIOLET, glint)
			var strength := (0.18 + 0.19 * glint + flare * 0.14) * sin((step + 1.0) * PI / 11.0)
			_pixel(layer, point, Color(ink, strength * presence))

	for i in SHARDS[phase]:
		var outer := i % 3 != 0
		var angle := i * 2.39996 + turn * (1.0 if outer else -1.27)
		var radius := Vector2(76.0, 51.0) if outer else Vector2(43.0, 28.0)
		radius *= 0.86 + 0.035 * (i % 8)
		var tilt := -0.38 if outer else 0.54
		var point := center + (Vector2.from_angle(angle) * radius).rotated(tilt)
		var trail_angle := angle - (0.09 if outer else -0.13)
		var trail := center + (Vector2.from_angle(trail_angle) * radius).rotated(tilt)
		var near_side := 0.5 + 0.5 * sin(angle)
		var shimmer := 0.66 + 0.34 * sin(time * 5.0 + i * 1.91)
		var opacity := (0.25 + 0.54 * near_side) * shimmer * presence
		_pixel(layer, trail, Color(DEEP, opacity * 0.65))
		_pixel(layer, point, Color(VIOLET.lerp(PALE, near_side * 0.7), opacity))
		if i % 3 == 0 or phase > 0 and i % 3 == 1:
			var slant := PIXEL if cos(angle) > 0.0 else -PIXEL
			_pixel(layer, point + Vector2(0.0, PIXEL), Color(DEEP, opacity))
			_pixel(layer, point + Vector2(slant, PIXEL), Color(VIOLET, opacity * 0.65))
			_pixel(layer, point + Vector2(slant, 2.0 * PIXEL), Color(DEEP, opacity * 0.8))


## Short streaks accelerate inwards and dissolve at the chest aperture.
static func _draw_charge(layer: Node2D, core: Vector2, time: float, opacity: float) -> void:
	if opacity <= 0.02:
		return
	for i in 13:
		var progress := fposmod(time * (0.95 + 0.08 * (i % 4)) + i * 0.618, 1.0)
		var angle := i * 2.39996 + progress * 0.58
		var radius := (1.0 - progress * progress) * (43.0 + (i % 6) * 9.0) + 8.0
		var axis := Vector2.from_angle(angle)
		var point := core + axis * radius
		var strength := sin(progress * PI) * opacity
		_pixel(layer, point + axis * 10.0, Color(DEEP, strength * 0.65))
		_pixel(layer, point + axis * 5.0, Color(VIOLET, strength * 0.8))
		_pixel(layer, point, Color(PALE, strength))


## In the last phase, strands drag from the hovering legs into the black pool.
static func _draw_tethers(layer: Node2D, time: float, presence: float, feet: Vector2) -> void:
	for i in 5:
		var start := feet + Vector2((i - 2) * 9.0, -25.0 + (i % 2) * 9.0)
		var finish := Vector2((i - 2) * 20.0 + sin(time * 2.2 + i) * 13.0, 5.0 + (i % 3) * 3.0)
		for step in 18:
			var along := step / 17.0
			var point := start.lerp(finish, along)
			point.x += sin(along * 9.0 - time * 4.0 + i) * 9.0 * sin(along * PI)
			var light := 0.24 + 0.17 * sin(time * 8.0 + along * 13.0 + i)
			layer.draw_rect(Rect2(_snap(point), Vector2(2.0, 1.0) * PIXEL),
				Color(DARK.lerp(DEEP, light), presence * (1.0 - along * 0.6)))


static func _pixel(layer: Node2D, point: Vector2, color: Color) -> void:
	layer.draw_rect(Rect2(_snap(point), Vector2.ONE * PIXEL), color)


static func _snap(point: Vector2) -> Vector2:
	return (point / PIXEL).round() * PIXEL
