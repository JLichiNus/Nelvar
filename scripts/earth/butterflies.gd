class_name NelvarButterflies
extends Node2D
## Butterflies over the earth valley: they flutter from flower to flower, rest on one
## with their wings slowly opening and closing, and scatter when the player comes
## close. A small flock stays around the player: those left far behind reappear at
## flowers out of sight ahead. Drawn in whole art pixels of the world grid, with a
## faint shadow on the grass below each one.
##
## `wing_scale` above 1 (the giant forest, Земля 2) makes them huge: a wingspan of a few
## hundred, flying high (mostly only their shadow passes over the floor), resting on the
## giant flowers' heads; painted with more pixels, not stretched.

const STEP := NelvarEarthData.PIXEL
const FLEE_DISTANCE := 110.0
const KEEP_DISTANCE := 1500.0
const SPAWN_DISTANCE := Vector2(380.0, 900.0)
## Wing colours, lit and shaded, of the five kinds; and the body.
const WING_LIGHT: Array[Color] = [Color8(250, 248, 236), Color8(250, 220, 90), Color8(150, 176, 244),
	Color8(246, 156, 70), Color8(240, 172, 206)]
const WING_DARK: Array[Color] = [Color8(206, 204, 188), Color8(214, 164, 42), Color8(96, 116, 206),
	Color8(196, 96, 44), Color8(198, 112, 156)]
const BODY := Color8(46, 34, 36)
const SHADOW := Color(0.05, 0.14, 0.08, 0.3)

enum State { FLY, REST, FLEE }


class Butterfly:
	var position := Vector2.ZERO
	var height := 24.0
	var velocity := Vector2.ZERO
	var target := Vector2.ZERO
	var state := State.FLY
	var timer := 0.0
	var phase := 0.0
	var palette := 0
	var wander := 0.0
	## Height it settles at on a flower.
	var rest := 2.0


@export var count := 16
## 1: the valley's butterflies; more: the giant forest's, this many times bigger.
@export var wing_scale := 1

var player: Node2D
var _flowers := PackedVector2Array()
## A flower's head height (giant flowers), by its place.
var _tops := {}
var _flock: Array[Butterfly] = []
var _rng := RandomNumberGenerator.new()
## Giant wings: frames (spread, half, folded) per palette.
var _giant_frames: Array = []


func setup(data: NelvarEarthData, watched: Node2D) -> void:
	player = watched
	_rng.seed = ("%d:butterflies" % data.world_seed).hash()
	for thing in data.things:
		if wing_scale > 1:
			if thing.kind == NelvarEarthData.Kind.GIANT_FLOWER:
				_flowers.append(thing.position)
				_tops[thing.position] = thing.size.y
		elif thing.kind == NelvarEarthData.Kind.FLOWERS or thing.kind == NelvarEarthData.Kind.BUSH \
				and thing.variant == 2:
			_flowers.append(thing.position + Vector2(0, -thing.radius * 0.8))
	if wing_scale > 1:
		for palette in WING_LIGHT.size():
			var frames: Array[ImageTexture] = []
			for frame in 3:
				frames.append(_bake_giant(palette, frame))
			_giant_frames.append(frames)
	if _flowers.is_empty():
		_flowers.append(data.spawn_position)
	for i in count:
		var butterfly := Butterfly.new()
		butterfly.palette = _rng.randi_range(0, WING_LIGHT.size() - 1)
		butterfly.phase = _rng.randf() * TAU
		butterfly.wander = _rng.randf() * TAU
		_place(butterfly, data.spawn_position, Vector2(160.0, 700.0))
		_flock.append(butterfly)
	z_index = 15
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _place(butterfly: Butterfly, around: Vector2, distance: Vector2) -> void:
	var best := _flowers[_rng.randi_range(0, _flowers.size() - 1)]
	for attempt in 12:
		var flower := _flowers[_rng.randi_range(0, _flowers.size() - 1)]
		var d := flower.distance_to(around)
		if d >= distance.x and d <= distance.y:
			best = flower
			break
	butterfly.position = best + Vector2(_rng.randf_range(-60.0, 60.0), _rng.randf_range(-40.0, 40.0)) * _scale()
	butterfly.height = _rng.randf_range(16.0, 40.0) * _high()
	butterfly.state = State.FLY
	butterfly.target = _next_flower(butterfly.position)
	butterfly.rest = _tops.get(butterfly.target, 2.0)


## Distances grow with the wings (half as fast); heights with the wings.
func _scale() -> float:
	return 1.0 + (wing_scale - 1) * 0.5


func _high() -> float:
	return float(wing_scale) * 4.0 if wing_scale > 1 else 1.0


func _next_flower(from: Vector2) -> Vector2:
	var best := _flowers[_rng.randi_range(0, _flowers.size() - 1)]
	for attempt in 8:
		var flower := _flowers[_rng.randi_range(0, _flowers.size() - 1)]
		if flower.distance_to(from) < best.distance_to(from) and flower.distance_to(from) > 40.0:
			best = flower
	return best


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var center := player.global_position
	for butterfly in _flock:
		_update(butterfly, delta, center)
	queue_redraw()


func _update(butterfly: Butterfly, delta: float, center: Vector2) -> void:
	var to_player := butterfly.position - center
	var size := _scale()
	var high := _high()
	if to_player.length() > KEEP_DISTANCE * size:
		_place(butterfly, center, SPAWN_DISTANCE * size)
		return
	if to_player.length() < FLEE_DISTANCE * size and butterfly.state != State.FLEE:
		butterfly.state = State.FLEE
		butterfly.timer = _rng.randf_range(1.2, 2.0)
		butterfly.velocity = to_player.normalized().rotated(_rng.randf_range(-0.6, 0.6)) * 150.0 * size
	match butterfly.state:
		State.REST:
			butterfly.phase += delta * 1.4
			butterfly.height = move_toward(butterfly.height, butterfly.rest, delta * 30.0 * high)
			butterfly.timer -= delta
			if butterfly.timer <= 0.0:
				butterfly.state = State.FLY
				butterfly.target = _next_flower(butterfly.position)
				butterfly.rest = _tops.get(butterfly.target, 2.0)
		State.FLEE:
			butterfly.phase += delta * 26.0 / size
			butterfly.position += butterfly.velocity * delta
			butterfly.height = move_toward(butterfly.height, 56.0 * high, delta * 50.0 * high)
			butterfly.timer -= delta
			if butterfly.timer <= 0.0:
				butterfly.state = State.FLY
				butterfly.target = _next_flower(butterfly.position + butterfly.velocity)
				butterfly.rest = _tops.get(butterfly.target, 2.0)
		State.FLY:
			butterfly.phase += delta * 18.0 / size
			butterfly.wander += delta * _rng.randf_range(1.0, 4.0)
			var heading := butterfly.position.direction_to(butterfly.target)
			var flutter := heading.rotated(sin(butterfly.wander) * 1.1)
			butterfly.velocity = butterfly.velocity.lerp(flutter * 52.0 * size, minf(1.0, delta * 3.0))
			butterfly.position += butterfly.velocity * delta
			var low := 8.0 * high
			if butterfly.position.distance_to(butterfly.target) < 260.0 * (size - 1.0):
				# Coming down to the flower's head.
				low = minf(low, butterfly.rest)
			butterfly.height = clampf(butterfly.height + sin(butterfly.phase * 0.23) * delta * 30.0 * high, low, 48.0 * high)
			if butterfly.position.distance_to(butterfly.target) < 10.0 * size:
				butterfly.state = State.REST
				butterfly.timer = _rng.randf_range(2.0, 6.0)


func _draw() -> void:
	if wing_scale > 1:
		_draw_giants()
		return
	var cell := Vector2.ONE * STEP
	for butterfly in _flock:
		var ground := (butterfly.position / STEP).floor()
		var body := ground - Vector2(0, roundf(butterfly.height / STEP))
		if butterfly.height > 6.0:
			draw_rect(Rect2(ground * STEP, Vector2(STEP * 2.0, STEP)), SHADOW)
		var light := WING_LIGHT[butterfly.palette]
		var dark := WING_DARK[butterfly.palette]
		var frame := int(butterfly.phase) % 3 if butterfly.state != State.REST \
			else (0 if sin(butterfly.phase) > 0.3 else 2)
		match frame:
			0:
				# Wings spread: two pixels a side, the upper pixel lit.
				for side in [-1, 1]:
					draw_rect(Rect2((body + Vector2(side, -1)) * STEP, cell), light)
					draw_rect(Rect2((body + Vector2(side * 2, -1)) * STEP, cell), light)
					draw_rect(Rect2((body + Vector2(side, 0)) * STEP, cell), dark)
			1:
				for side in [-1, 1]:
					draw_rect(Rect2((body + Vector2(side, -1)) * STEP, cell), light)
					draw_rect(Rect2((body + Vector2(side, 0)) * STEP, cell), dark)
			2:
				# Folded up over the back.
				draw_rect(Rect2((body + Vector2(0, -2)) * STEP, cell), light)
				draw_rect(Rect2((body + Vector2(1, -2)) * STEP, cell), dark)
		draw_rect(Rect2((body + Vector2(0, -1)) * STEP, cell), BODY)
		draw_rect(Rect2(body * STEP, cell), BODY)


## The giant forest's butterflies: a wide soft shadow on the floor, the butterfly high above
## it with its wings spread, half closed or folded.
func _draw_giants() -> void:
	for butterfly in _flock:
		var frames: Array = _giant_frames[butterfly.palette]
		var frame := int(butterfly.phase) % 3 if butterfly.state != State.REST \
			else (0 if sin(butterfly.phase) > 0.3 else 2)
		var texture: ImageTexture = frames[frame]
		var size := texture.get_size() * STEP
		var ground := (butterfly.position / STEP).floor() * STEP
		if butterfly.height > 12.0:
			var span := size.x * (1.0 if frame == 0 else (0.6 if frame == 1 else 0.25))
			var shadow := ground + Vector2(-0.25, 0.15) * butterfly.height * 0.3
			_shadow_ellipse(shadow, Vector2(span * 0.5, size.y * 0.18))
		var at := ((butterfly.position - Vector2(0.0, butterfly.height)) / STEP).floor() * STEP - size * 0.5
		draw_texture_rect(texture, Rect2(at, size), false)


func _shadow_ellipse(center: Vector2, axes: Vector2) -> void:
	var from := ((center - axes) / STEP).floor()
	var to := ((center + axes) / STEP).ceil()
	for y in range(int(from.y), int(to.y) + 1):
		for x in range(int(from.x), int(to.x) + 1):
			var d := (((Vector2(x, y) + Vector2(0.5, 0.5)) * STEP - center) / axes).length_squared()
			if d < 1.0 and (d < 0.55 or NelvarPixelArt.bayer(Vector2i(x, y)) < 8):
				draw_rect(Rect2(Vector2(x, y) * STEP, Vector2.ONE * STEP), SHADOW)


## A giant butterfly in `palette`: wings spread (0), half closed (1) or folded up (2): a
## forewing and a hindwing a side, a dark band along their edge with pale spots, the body.
func _bake_giant(palette: int, frame: int) -> ImageTexture:
	var span := 6 * wing_scale
	var w := span * 2 + 3
	var h := span + 6
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var light := WING_LIGHT[palette]
	var dark := WING_DARK[palette]
	var edge := dark.darkened(0.5)
	var squeeze: float = [1.0, 0.55, 0.18][frame]
	var center := Vector2(w * 0.5, h * 0.55)
	for y in h:
		for x in w:
			var local := Vector2(x + 0.5, y + 0.5) - center
			var side := signf(local.x)
			var lx := absf(local.x) / maxf(squeeze, 0.01)
			var fore := Vector2(lx - span * 0.48, local.y + span * 0.2) / Vector2(span * 0.5, span * 0.38)
			var hind := Vector2(lx - span * 0.3, local.y - span * 0.22) / Vector2(span * 0.32, span * 0.3)
			if frame == 2:
				fore = Vector2(local.x / (span * 0.12), (local.y + span * 0.32) / (span * 0.42))
				hind = Vector2(2.0, 2.0)
			var f := fore.length()
			var g := hind.length()
			if f > 1.0 and g > 1.0:
				continue
			var color := light if f <= 1.0 else dark
			var rim := f if f <= 1.0 else g
			if rim > 0.78:
				color = edge
				if f <= 1.0 and fposmod(atan2(fore.y, fore.x) * 5.0, 1.0) < 0.3 and frame != 2:
					color = Color8(246, 242, 228)
			elif f <= 1.0 and rim < 0.4 and frame != 2:
				color = light.lerp(dark, 0.4)
			if side == 0.0:
				color = BODY
			image.set_pixel(x, y, color)
	# The body down the middle.
	for y in range(int(center.y - span * 0.35), int(center.y + span * 0.4)):
		image.set_pixel(int(center.x), y, BODY)
		image.set_pixel(int(center.x) - 1, y, BODY)
	return ImageTexture.create_from_image(image)
