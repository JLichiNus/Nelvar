class_name NelvarGeysers
extends Node2D
## What rises over the volcano's top, drawn over everything that stands: the geysers'
## columns of steam with a fiery core when they erupt, and the lava fountains of the
## vent — drops of lava thrown up on arcs that fall back and splash. Puffs are pixel
## discs lit from the upper right (as NelvarSmoke's), drops whole art pixels, all on the
## world's art pixel grid.

const STEP := NelvarFireData.PIXEL
const WIND := NelvarEmbers.WIND
const STEAM: Array[Color] = [Color8(138, 128, 128), Color8(176, 168, 164), Color8(212, 206, 200),
	Color8(240, 236, 230)]
const FIRE: Array[Color] = [Color8(170, 44, 24), Color8(226, 92, 40), Color8(255, 168, 70),
	Color8(255, 232, 150)]
const DROP: Array[Color] = [Color8(255, 236, 160), Color8(255, 196, 96), Color8(246, 130, 52),
	Color8(212, 76, 34), Color8(118, 26, 20)]
const MAX_RADIUS := 12
## Gravity of the fountains' drops, world units per second squared.
const GRAVITY := 520.0


class Puff:
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var radius := 3.0
	var grow := 6.0
	var age := 0.0
	var life := 1.6
	var fire := false


class Drop:
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var height := 0.0
	var lift := 0.0
	var age := 0.0


var data: NelvarCraterData
## The shared clock (NelvarCraterMain): the geysers' cycles follow it.
var clock := 0.0
## Columns erupted and fountains thrown so far (the tests count them).
var columns := 0
var fountains := 0

var _puffs: Array[Puff] = []
var _drops: Array[Drop] = []
var _textures := {}
var _rng := RandomNumberGenerator.new()
var _fountain_timer := 0.0
var _burst_timer := 2.0
var _embers: NelvarEmbers


func setup(crater: NelvarCraterData, embers: NelvarEmbers) -> void:
	data = crater
	_embers = embers
	_rng.seed = ("%d:geysers" % crater.world_seed).hash()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for palette_index in 2:
		for r in range(2, MAX_RADIUS + 1):
			_textures[Vector2i(palette_index, r)] = _bake(r, STEAM if palette_index == 0 else FIRE)


func _bake(radius: int, palette: Array[Color]) -> ImageTexture:
	var size := radius * 2 + 1
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var light := Vector2(0.55, -0.65)
	for y in size:
		for x in size:
			var d := Vector2(x - radius, y - radius) / (radius + 0.5)
			if d.length() > 1.0:
				continue
			var lit := 0.5 + d.dot(light) * 0.45 + (1.0 - d.length()) * 0.2
			var cell := Vector2i(x, y)
			var level := clampf(lit, 0.0, 0.999) * (palette.size() - 1)
			var index := int(level)
			if (level - index) * 16.0 > NelvarPixelArt.bayer(cell) + 0.5:
				index += 1
			if d.length() > 0.8 and NelvarPixelArt.bayer(cell) < 8:
				continue
			image.set_pixel(x, y, palette[mini(index, palette.size() - 1)])
	return ImageTexture.create_from_image(image)


## Geyser `index` erupts: a column of steam round a core of fire.
func erupt(index: int) -> void:
	var at := data.geysers[index].position
	columns += 1
	for i in 26:
		var puff := Puff.new()
		puff.position = at + Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-4.0, 2.0))
		puff.velocity = Vector2(_rng.randf_range(-26.0, 26.0), -_rng.randf_range(160.0, 440.0))
		puff.radius = _rng.randf_range(2.5, 5.0)
		puff.grow = _rng.randf_range(4.0, 8.0)
		puff.life = _rng.randf_range(1.1, 1.9)
		puff.age = -i * 0.02
		_puffs.append(puff)
	for i in 12:
		var puff := Puff.new()
		puff.fire = true
		puff.position = at + Vector2(_rng.randf_range(-3.0, 3.0), 0.0)
		puff.velocity = Vector2(_rng.randf_range(-14.0, 14.0), -_rng.randf_range(180.0, 330.0))
		puff.radius = _rng.randf_range(2.0, 3.5)
		puff.grow = _rng.randf_range(1.0, 2.5)
		puff.life = _rng.randf_range(0.45, 0.75)
		puff.age = -i * 0.04
		_puffs.append(puff)


## How many of something happen this frame at `rate` (fractions by chance).
func _count(rate: float) -> int:
	var whole := int(rate)
	return whole + (1 if _rng.randf() < rate - whole else 0)


## One puff of a geyser's column: steam, or the fiery core low in it.
func _jet(at: Vector2, fire: bool, power: float) -> void:
	var puff := Puff.new()
	puff.fire = fire
	puff.position = at + Vector2(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-3.0, 1.0))
	if fire:
		puff.velocity = Vector2(_rng.randf_range(-12.0, 12.0), -_rng.randf_range(200.0, 340.0) * power)
		puff.radius = _rng.randf_range(2.0, 3.0)
		puff.grow = _rng.randf_range(1.0, 2.0)
		puff.life = _rng.randf_range(0.35, 0.6)
	else:
		puff.velocity = Vector2(_rng.randf_range(-34.0, 34.0), -_rng.randf_range(260.0, 480.0) * power)
		puff.radius = _rng.randf_range(2.5, 4.0)
		puff.grow = _rng.randf_range(5.0, 8.0)
		puff.life = _rng.randf_range(1.0, 1.6)
	_puffs.append(puff)


## Drops of lava thrown up from `at`.
func fountain(at: Vector2, count: int, power: float) -> void:
	fountains += 1
	for i in count:
		var drop := Drop.new()
		drop.position = at + Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-6.0, 6.0))
		drop.velocity = Vector2(_rng.randf_range(-60.0, 60.0), _rng.randf_range(-30.0, 30.0)) * power
		drop.lift = _rng.randf_range(180.0, 340.0) * power
		_drops.append(drop)


func _process(delta: float) -> void:
	if data == null:
		return
	var viewport := get_viewport()
	var to_world := viewport.get_canvas_transform().affine_inverse()
	var view := Rect2(to_world * Vector2.ZERO, to_world.basis_xform(viewport.get_visible_rect().size)).grow(300.0)
	# The vent spits lava all the time, now and then a big burst.
	if view.has_point(data.vent):
		_fountain_timer -= delta
		_burst_timer -= delta
		if _fountain_timer <= 0.0:
			_fountain_timer = _rng.randf_range(0.15, 0.4)
			var spot := data.vent + Vector2.from_angle(_rng.randf() * TAU) * data.vent_radius * 0.6 * sqrt(_rng.randf())
			fountain(spot, _rng.randi_range(2, 5), 0.6)
		if _burst_timer <= 0.0:
			_burst_timer = _rng.randf_range(2.5, 6.0)
			fountain(data.vent, _rng.randi_range(16, 26), 1.0)
	# An erupting geyser keeps pouring out its column; a warning one steams harder.
	for geyser in data.geysers:
		if not view.has_point(geyser.position):
			continue
		var stage := geyser.stage_at(clock)
		var progress := geyser.progress_at(clock)
		if stage == 2:
			var power := 1.0 - progress * 0.6
			for i in _count(delta * 46.0 * power):
				_jet(geyser.position, false, power)
			for i in _count(delta * 26.0 * power):
				_jet(geyser.position, true, power)
		elif stage == 1:
			for i in _count(delta * 7.0 * progress):
				_jet(geyser.position, false, 0.25)
	var keep: Array[Puff] = []
	for puff in _puffs:
		puff.age += delta
		if puff.age < 0.0:
			keep.append(puff)
			continue
		if puff.age >= puff.life:
			continue
		puff.velocity = puff.velocity.lerp(Vector2(WIND.x * 1.5, -30.0), minf(1.0, delta * 1.6))
		puff.position += puff.velocity * delta
		puff.radius = minf(puff.radius + puff.grow * delta, MAX_RADIUS)
		keep.append(puff)
	_puffs = keep
	var falling: Array[Drop] = []
	for drop in _drops:
		drop.age += delta
		drop.lift -= GRAVITY * delta
		drop.height += drop.lift * delta
		drop.position += drop.velocity * delta
		if drop.height <= 0.0 and drop.lift < 0.0:
			if _embers != null and _rng.randf() < 0.3:
				_embers.burst(drop.position, 1, 0.4)
			continue
		falling.append(drop)
	_drops = falling
	queue_redraw()


func _draw() -> void:
	for puff in _puffs:
		if puff.age < 0.0:
			continue
		var r := clampi(roundi(puff.radius), 2, MAX_RADIUS)
		var texture: ImageTexture = _textures[Vector2i(1 if puff.fire else 0, r)]
		var at := (puff.position / STEP).floor() * STEP - Vector2.ONE * r * STEP
		var fade := 1.0 - puff.age / puff.life
		var alpha := clampf(fade * 1.6, 0.0, 0.9) if not puff.fire else clampf(fade * 2.0, 0.0, 1.0)
		draw_texture_rect(texture, Rect2(at, Vector2.ONE * (r * 2 + 1) * STEP), false, Color(1, 1, 1, alpha))
	var cell := Vector2.ONE * STEP
	for drop in _drops:
		var at := ((drop.position - Vector2(0.0, drop.height)) / STEP).floor() * STEP
		var heat := clampi(int(drop.age * 3.0), 0, DROP.size() - 2)
		draw_rect(Rect2(at, cell), DROP[heat])
		var trail := Vector2(0.0, STEP if drop.lift > 0.0 else -STEP)
		draw_rect(Rect2(at + trail, cell), DROP[heat + 1])
