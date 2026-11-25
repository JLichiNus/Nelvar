class_name NelvarSmoke
extends Node2D
## Smoke over the fire forge, drawn over everything that stands. Thin wisps rise from
## the vents and the smouldering trunks (and the volcano's geysers, which also throw up
## a cloud as they burst: puff()); a heavy plume climbs from each molten crater;
## over the fumarole fields lie banks of smoke thick enough to hide whoever walks in
## them. The player's wind (NelvarEmbers.gusts_in) blows puffs away and thins them out;
## a dispersed bank grows back from its vents in a few seconds.
##
## Puffs are pixel discs lit from the upper right, baked once per size and drawn on the
## world's art pixel grid.

const STEP := NelvarFireData.PIXEL
const WIND := NelvarEmbers.WIND
## Grey smoke of the vents and banks, dark to light; the volcanoes' darker plume.
const GREY: Array[Color] = [Color8(70, 62, 66), Color8(96, 88, 90), Color8(124, 116, 116), Color8(150, 142, 140)]
const PLUME: Array[Color] = [Color8(44, 26, 32), Color8(62, 38, 42), Color8(86, 54, 54), Color8(110, 74, 66)]
const MAX_RADIUS := 12

enum Source { WISP, PLUME, BANK }


class Puff:
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var radius := 3.0
	var grow := 0.6
	var alpha := 0.6
	var age := 0.0
	var life := 4.0
	var source := Source.WISP
	var bank := -1
	var phase := 0.0
	## Thinned by the wind: fades this much faster.
	var thinning := 0.0


## Points smoke rises from: vents and smouldering tops (wisps), craters (plumes).
var wisps := PackedVector2Array()
var plumes := PackedVector2Array()
## Wind attacks this frame (NelvarEmbers.gusts_in).
var gusts: Array = []

var _banks: Array[Vector3] = []
var _puffs: Array[Puff] = []
var _textures := {}
var _rng := RandomNumberGenerator.new()
var _timers := PackedFloat32Array()
var _bank_timers := PackedFloat32Array()


func setup(fire: NelvarFireData, wisp_points: PackedVector2Array, plume_points: PackedVector2Array) -> void:
	_rng.seed = ("%d:smoke" % fire.world_seed).hash()
	wisps = wisp_points
	plumes = plume_points
	_banks = fire.smoke_banks
	_timers.resize(wisps.size() + plumes.size())
	for i in _timers.size():
		_timers[i] = _rng.randf()
	_bank_timers.resize(_banks.size())
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for palette_index in 2:
		for r in range(2, MAX_RADIUS + 1):
			_textures[Vector2i(palette_index, r)] = _bake(r, GREY if palette_index == 0 else PLUME)
	# The banks lie there from the start.
	for b in _banks.size():
		for i in _bank_target(b):
			_puffs.append(_bank_puff(b, true))


## How many puffs make up a full bank.
func _bank_target(bank: int) -> int:
	return clampi(int(_banks[bank].z / 11.0), 10, 22)


## Puffs of bank `bank` now.
func bank_density(bank: int) -> int:
	var total := 0
	for puff in _puffs:
		if puff.bank == bank and puff.alpha > 0.25:
			total += 1
	return total


func _bake(radius: int, palette: Array[Color]) -> ImageTexture:
	var size := radius * 2 + 1
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var light := Vector2(0.55, -0.65)
	for y in size:
		for x in size:
			var d := Vector2(x - radius, y - radius) / (radius + 0.5)
			if d.length() > 1.0:
				continue
			var lit := 0.5 + d.dot(light) * 0.45 + (1.0 - d.length()) * 0.15
			var cell := Vector2i(x, y)
			var level := clampf(lit, 0.0, 0.999) * (palette.size() - 1)
			var index := int(level)
			if (level - index) * 16.0 > NelvarPixelArt.bayer(cell) + 0.5:
				index += 1
			var color := palette[mini(index, palette.size() - 1)]
			# The rim thins out in a dither.
			if d.length() > 0.8 and NelvarPixelArt.bayer(cell) < 8:
				continue
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


func _bank_puff(bank: int, settled: bool) -> Puff:
	var area := _banks[bank]
	var puff := Puff.new()
	puff.source = Source.BANK
	puff.bank = bank
	puff.position = Vector2(area.x, area.y) + Vector2.from_angle(_rng.randf() * TAU) \
		* area.z * sqrt(_rng.randf()) * Vector2(1.0, 0.7)
	puff.radius = _rng.randf_range(7.0, 11.0) if settled else _rng.randf_range(4.0, 6.0)
	puff.grow = _rng.randf_range(0.4, 0.9)
	puff.alpha = _rng.randf_range(0.55, 0.78) if settled else 0.0
	puff.life = INF
	puff.phase = _rng.randf() * TAU
	return puff


func _process(delta: float) -> void:
	var viewport := get_viewport()
	var to_world := viewport.get_canvas_transform().affine_inverse()
	var view := Rect2(to_world * Vector2.ZERO, to_world.basis_xform(viewport.get_visible_rect().size)).grow(400.0)
	var points := wisps + plumes
	for i in points.size():
		var plume := i >= wisps.size()
		if not view.grow(800.0 if plume else 0.0).has_point(points[i]):
			continue
		_timers[i] -= delta
		if _timers[i] <= 0.0:
			_timers[i] = _rng.randf_range(0.7, 1.2) if plume else _rng.randf_range(0.35, 0.8)
			_emit(points[i], plume)
	for b in _banks.size():
		_bank_timers[b] -= delta
		if _bank_timers[b] <= 0.0:
			_bank_timers[b] = 0.5
			if bank_density(b) < _bank_target(b):
				_puffs.append(_bank_puff(b, false))
	var keep: Array[Puff] = []
	for puff in _puffs:
		if _update(puff, delta):
			keep.append(puff)
	_puffs = keep
	queue_redraw()


## A cloud of `count` puffs thrown up at `at` (a geyser bursting).
func puff(at: Vector2, count: int) -> void:
	for i in count:
		var cloud := Puff.new()
		cloud.source = Source.WISP
		cloud.position = at + Vector2(_rng.randf_range(-14.0, 14.0), _rng.randf_range(-8.0, 4.0))
		cloud.phase = _rng.randf() * TAU
		cloud.radius = _rng.randf_range(4.0, 7.0)
		cloud.grow = _rng.randf_range(1.0, 1.8)
		cloud.velocity = Vector2(_rng.randf_range(-24.0, 24.0), _rng.randf_range(-70.0, -36.0))
		cloud.alpha = 0.7
		cloud.life = _rng.randf_range(2.6, 4.2)
		_puffs.append(cloud)


func _emit(at: Vector2, plume: bool) -> void:
	var puff := Puff.new()
	puff.position = at + Vector2(_rng.randf_range(-4.0, 4.0), 0.0)
	puff.phase = _rng.randf() * TAU
	if plume:
		puff.source = Source.PLUME
		puff.radius = _rng.randf_range(5.0, 8.0)
		puff.grow = _rng.randf_range(0.5, 0.9)
		puff.velocity = Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-34.0, -24.0))
		puff.alpha = 0.85
		puff.life = _rng.randf_range(9.0, 13.0)
	else:
		puff.source = Source.WISP
		puff.radius = 2.0
		puff.grow = _rng.randf_range(0.5, 0.9)
		puff.velocity = Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-26.0, -16.0))
		puff.alpha = 0.55
		puff.life = _rng.randf_range(3.0, 4.5)
	_puffs.append(puff)


## False once the puff is gone.
func _update(puff: Puff, delta: float) -> bool:
	puff.age += delta
	puff.phase += delta * 0.6
	for gust: Array in gusts:
		var offset: Vector2 = puff.position - gust[0]
		var reach: float = gust[2] + puff.radius * STEP
		if offset.length_squared() < reach * reach:
			var push: Vector2 = gust[1] * 0.45 + offset.normalized() * 80.0
			puff.velocity = puff.velocity.lerp(push, minf(1.0, delta * 6.0))
			puff.thinning = minf(puff.thinning + delta * 6.0, 2.5)
	match puff.source:
		Source.BANK:
			var area := _banks[puff.bank]
			var home := Vector2(area.x, area.y)
			var drift := Vector2(sin(puff.phase) * 6.0, cos(puff.phase * 0.7) * 4.0) + WIND * 0.25
			# A bank stays over its field: puffs that wander off are pulled back.
			if puff.position.distance_to(home) > area.z and puff.thinning <= 0.0:
				drift += puff.position.direction_to(home) * 14.0
			puff.velocity = puff.velocity.lerp(drift, minf(1.0, delta * 0.7))
			puff.radius = minf(puff.radius + puff.grow * delta, 11.0)
			if puff.thinning > 0.0:
				puff.alpha -= delta * puff.thinning * 0.5
				puff.thinning = maxf(0.0, puff.thinning - delta * 0.5)
			else:
				puff.alpha = minf(puff.alpha + delta * 0.12, 0.78)
		_:
			puff.velocity = puff.velocity.lerp(Vector2(WIND.x * (0.9 if puff.source == Source.PLUME else 0.6),
				puff.velocity.y), minf(1.0, delta * 0.5))
			puff.radius = minf(puff.radius + puff.grow * delta, MAX_RADIUS)
			var fade := 1.0 - puff.age / puff.life
			puff.alpha = minf(puff.alpha, fade * (0.85 if puff.source == Source.PLUME else 0.55)) \
				- puff.thinning * delta * 0.5
	puff.position += puff.velocity * delta
	return puff.alpha > 0.02 and puff.age < puff.life


func _draw() -> void:
	for puff in _puffs:
		var r := clampi(roundi(puff.radius), 2, MAX_RADIUS)
		var texture: ImageTexture = _textures[Vector2i(1 if puff.source == Source.PLUME else 0, r)]
		var at := (puff.position / STEP).floor() * STEP - Vector2.ONE * r * STEP
		draw_texture_rect(texture, Rect2(at, Vector2.ONE * (r * 2 + 1) * STEP), false,
			Color(1, 1, 1, clampf(puff.alpha, 0.0, 1.0)))
