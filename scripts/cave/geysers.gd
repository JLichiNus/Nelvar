class_name NelvarCaveGeysers
extends Node2D
## What rises from the cave's geysers, drawn over everything that stands: the water
## boiling in each mouth (harder while it bubbles up before an eruption), and the
## eruption — a column of water and steam of pixel discs, drops of water thrown up on
## arcs that fall back and splash. Puffs are lit from the upper right (as NelvarSmoke's),
## drops whole art pixels, all on the world's art pixel grid. The steam that hangs over
## them is NelvarSmoke's.

const STEP := NelvarIceData.PIXEL
const STEAM: Array[Color] = [Color8(150, 170, 186), Color8(188, 204, 216), Color8(220, 230, 238),
	Color8(244, 248, 252)]
const SPRAY: Array[Color] = [Color8(104, 156, 178), Color8(150, 200, 216), Color8(206, 236, 244)]
const BUBBLE := Color8(214, 240, 246)
const MAX_RADIUS := 11
const GRAVITY := 520.0


class Puff:
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var radius := 3.0
	var grow := 6.0
	var age := 0.0
	var life := 1.6


class Drop:
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var height := 0.0
	var lift := 0.0


var data: NelvarCaveData
## The shared clock (NelvarCaveMain): the cycles follow it.
var clock := 0.0
## Eruptions drawn so far (the tests count them).
var columns := 0

var _puffs: Array[Puff] = []
var _drops: Array[Drop] = []
var _bubbles := PackedVector3Array()
var _textures := {}
var _rng := RandomNumberGenerator.new()


func setup(cave: NelvarCaveData) -> void:
	data = cave
	_rng.seed = ("%d:cave:geysers" % cave.world_seed).hash()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for r in range(2, MAX_RADIUS + 1):
		_textures[r] = _bake(r)


func _bake(radius: int) -> ImageTexture:
	var size := radius * 2 + 1
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var light := Vector2(0.55, -0.65)
	for y in size:
		for x in size:
			var d := Vector2(x - radius, y - radius) / (radius + 0.5)
			if d.length() > 1.0:
				continue
			var cell := Vector2i(x, y)
			if d.length() > 0.8 and NelvarPixelArt.bayer(cell) < 8:
				continue
			var lit := clampf(0.5 + d.dot(light) * 0.45 + (1.0 - d.length()) * 0.2, 0.0, 0.999) * (STEAM.size() - 1)
			var index := int(lit)
			if (lit - index) * 16.0 > NelvarPixelArt.bayer(cell) + 0.5:
				index += 1
			image.set_pixel(x, y, STEAM[mini(index, STEAM.size() - 1)])
	return ImageTexture.create_from_image(image)


## Geyser `index` erupts: a column of water and steam, drops thrown up all round.
func erupt(index: int) -> void:
	var at := data.geysers[index].position + Vector2(0.0, -6.0)
	columns += 1
	for i in 30:
		var puff := Puff.new()
		puff.position = at + Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-4.0, 2.0))
		puff.velocity = Vector2(_rng.randf_range(-22.0, 22.0), -_rng.randf_range(180.0, 460.0))
		puff.radius = _rng.randf_range(2.5, 5.0)
		puff.grow = _rng.randf_range(4.0, 8.0)
		puff.life = _rng.randf_range(1.2, 2.0)
		puff.age = -i * 0.02
		_puffs.append(puff)
	_throw(at, 26, 1.0)


func _throw(at: Vector2, count: int, power: float) -> void:
	for i in count:
		var drop := Drop.new()
		drop.position = at + Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-4.0, 4.0))
		drop.velocity = Vector2(_rng.randf_range(-90.0, 90.0), _rng.randf_range(-40.0, 40.0)) * power
		drop.lift = _rng.randf_range(220.0, 420.0) * power
		_drops.append(drop)


func _process(delta: float) -> void:
	if data == null:
		return
	var viewport := get_viewport()
	var to_world := viewport.get_canvas_transform().affine_inverse()
	var view := Rect2(to_world * Vector2.ZERO, to_world.basis_xform(viewport.get_visible_rect().size)).grow(300.0)
	_bubbles.clear()
	for geyser in data.geysers:
		if not view.has_point(geyser.position):
			continue
		var stage := geyser.stage_at(clock)
		var progress := geyser.progress_at(clock)
		# The pool boils; before an eruption it heaves.
		var boil := 3 if stage == 0 else (8 if stage == 1 else 12)
		for k in boil:
			var spot := Vector2.from_angle(_rng.randf() * TAU) * geyser.mouth * 0.42 * Vector2(1.0, 0.45) * sqrt(_rng.randf())
			_bubbles.append(Vector3(geyser.position.x + spot.x, geyser.position.y - geyser.mouth * 0.5 + spot.y,
				1.0 if stage > 0 and _rng.randf() < 0.3 else 0.0))
		if stage == 1 and _rng.randf() < delta * 10.0 * progress:
			_throw(geyser.position + Vector2(0.0, -geyser.mouth * 0.5), 1, 0.35)
		elif stage == 2:
			var power := 1.0 - progress * 0.6
			for i in _count(delta * 40.0 * power):
				var puff := Puff.new()
				puff.position = geyser.position + Vector2(_rng.randf_range(-5.0, 5.0), -geyser.mouth * 0.5)
				puff.velocity = Vector2(_rng.randf_range(-30.0, 30.0), -_rng.randf_range(260.0, 460.0) * power)
				puff.radius = _rng.randf_range(2.5, 4.0)
				puff.grow = _rng.randf_range(5.0, 8.0)
				puff.life = _rng.randf_range(1.0, 1.6)
				_puffs.append(puff)
			if _rng.randf() < delta * 30.0 * power:
				_throw(geyser.position + Vector2(0.0, -geyser.mouth * 0.5), 2, 0.8 * power)
	var keep: Array[Puff] = []
	for puff in _puffs:
		puff.age += delta
		if puff.age < 0.0:
			keep.append(puff)
			continue
		if puff.age >= puff.life:
			continue
		puff.velocity = puff.velocity.lerp(Vector2(NelvarEmbers.WIND.x, -26.0), minf(1.0, delta * 1.6))
		puff.position += puff.velocity * delta
		puff.radius = minf(puff.radius + puff.grow * delta, MAX_RADIUS)
		keep.append(puff)
	_puffs = keep
	var falling: Array[Drop] = []
	for drop in _drops:
		drop.lift -= GRAVITY * delta
		drop.height += drop.lift * delta
		drop.position += drop.velocity * delta
		if drop.height > 0.0 or drop.lift > 0.0:
			falling.append(drop)
	_drops = falling
	queue_redraw()


func _count(rate: float) -> int:
	var whole := int(rate)
	return whole + (1 if _rng.randf() < rate - whole else 0)


func _draw() -> void:
	var cell := Vector2.ONE * STEP
	for bubble in _bubbles:
		var at := (Vector2(bubble.x, bubble.y) / STEP).floor() * STEP
		draw_rect(Rect2(at, cell), BUBBLE if bubble.z < 0.5 else Color.WHITE)
	for puff in _puffs:
		if puff.age < 0.0:
			continue
		var r := clampi(roundi(puff.radius), 2, MAX_RADIUS)
		var at := (puff.position / STEP).floor() * STEP - Vector2.ONE * r * STEP
		var fade := 1.0 - puff.age / puff.life
		draw_texture_rect(_textures[r], Rect2(at, Vector2.ONE * (r * 2 + 1) * STEP), false,
			Color(1, 1, 1, clampf(fade * 1.5, 0.0, 0.85)))
	for drop in _drops:
		var at := ((drop.position - Vector2(0.0, drop.height)) / STEP).floor() * STEP
		draw_rect(Rect2(at, cell), SPRAY[2] if drop.lift > 0.0 else SPRAY[1])
		draw_rect(Rect2(at + Vector2(0.0, STEP if drop.lift > 0.0 else -STEP), cell), SPRAY[0])
