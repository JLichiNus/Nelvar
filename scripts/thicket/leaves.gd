class_name NelvarLeaves
extends Node2D
## Big leaves gliding down from the crowns of the giant forest: a few near the player at a
## time, spinning slowly as they swing from side to side, their shadow on the floor under
## them. Harmless. Drawn in whole art pixels above everything (the shadow on everything too:
## the leaf is high above).

const STEP := NelvarEarthData.PIXEL
const COUNT := Vector2i(3, 6)
const HEIGHT := Vector2(380.0, 720.0)
const SPEED := Vector2(28.0, 46.0)
const SIZE := Vector2(40.0, 90.0)
const SHADOW := Color(0.05, 0.05, 0.02, 0.22)
const PALETTES: Array = [
	[Color8(96, 54, 26), Color8(150, 92, 38), Color8(198, 140, 62), Color8(232, 188, 104)],
	[Color8(54, 98, 40), Color8(84, 132, 52), Color8(122, 166, 70), Color8(170, 198, 104)],
	[Color8(150, 116, 30), Color8(196, 160, 44), Color8(230, 200, 80), Color8(248, 230, 140)],
]


class Leaf:
	var ground := Vector2.ZERO
	var height := 500.0
	var speed := 36.0
	var phase := 0.0
	var size := 3
	var palette := 0
	var landed := 0.0


var player: Node2D
var leaves: Array[Leaf] = []
## Frames per size and palette: [flat, tilted, edge on, tilted the other way].
var _frames := {}
var _rng := RandomNumberGenerator.new()


func setup(world_seed: int, watched: Node2D) -> void:
	player = watched
	_rng.seed = ("%d:leaves" % world_seed).hash()
	z_index = 22
	z_as_relative = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for size in 3:
		for palette in PALETTES.size():
			var frames: Array[ImageTexture] = []
			for frame in 4:
				frames.append(_bake(size, palette, frame))
			_frames[Vector2i(size, palette)] = frames
	for i in _rng.randi_range(COUNT.x, COUNT.y):
		var leaf := Leaf.new()
		_place(leaf, true)
		leaves.append(leaf)


func _place(leaf: Leaf, anywhere: bool) -> void:
	var center := player.global_position if is_instance_valid(player) else Vector2.ZERO
	leaf.ground = center + Vector2(_rng.randf_range(-700.0, 700.0), _rng.randf_range(-420.0, 520.0))
	leaf.height = _rng.randf_range(HEIGHT.x, HEIGHT.y) * (_rng.randf() if anywhere else 1.0)
	leaf.speed = _rng.randf_range(SPEED.x, SPEED.y)
	leaf.phase = _rng.randf() * TAU
	leaf.size = _rng.randi_range(0, 2)
	leaf.palette = _rng.randi_range(0, PALETTES.size() - 1)
	leaf.landed = 0.0


## A leaf `size` (0..2) in `palette`, seen flat, tilted or edge on.
func _bake(size: int, palette: int, frame: int) -> ImageTexture:
	var length := lerpf(SIZE.x, SIZE.y, size / 2.0) / STEP
	var width: float = length * float([0.45, 0.32, 0.14, 0.32][frame])
	var w := int(ceil(length)) + 2
	var h := int(ceil(length)) + 2
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var colors: Array = PALETTES[palette]
	var axis := Vector2.from_angle(float([0.3, 0.8, 1.2, -0.5][frame]))
	var center := Vector2(w, h) * 0.5
	for y in h:
		for x in w:
			var local := Vector2(x + 0.5, y + 0.5) - center
			var u := local.dot(axis) / (length * 0.5)
			var v := local.dot(axis.orthogonal()) / maxf(width * 0.5, 0.6)
			if absf(u) > 1.0 or absf(v) > sin((u + 1.0) * PI * 0.5) * 1.0:
				continue
			var level := 0.5 + v * 0.25 - u * 0.1
			var index := clampi(int(level * colors.size()), 0, colors.size() - 1)
			if absf(v) < 0.18 and frame != 2:
				index = 0
			image.set_pixel(x, y, colors[index])
	return ImageTexture.create_from_image(image)


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var center := player.global_position
	for leaf in leaves:
		if leaf.height > 0.0:
			leaf.phase += delta * 1.6
			leaf.height -= leaf.speed * delta
			leaf.ground.x += sin(leaf.phase) * 26.0 * delta + 6.0 * delta
			if leaf.height <= 0.0:
				leaf.height = 0.0
		else:
			leaf.landed += delta
			if leaf.landed > 1.2:
				_place(leaf, false)
		if leaf.ground.distance_to(center) > 1100.0:
			_place(leaf, false)
	queue_redraw()


func _draw() -> void:
	for leaf in leaves:
		var frames: Array = _frames[Vector2i(leaf.size, leaf.palette)]
		var frame := 0 if leaf.height <= 0.0 else int(fposmod(leaf.phase / TAU * 4.0, 4.0))
		var texture: ImageTexture = frames[frame]
		var size := texture.get_size() * STEP
		# The shadow, down and to the left of the leaf the higher it is.
		var shadow := ((leaf.ground + Vector2(-0.3, 0.2) * leaf.height * 0.2) / STEP).floor() * STEP
		if leaf.height > 0.0:
			draw_rect(Rect2(shadow - Vector2(size.x * 0.3, STEP * 0.5), Vector2(size.x * 0.6, STEP * 2.0)), SHADOW)
		var at := ((leaf.ground - Vector2(0.0, leaf.height)) / STEP).floor() * STEP - size * 0.5
		var alpha := 1.0 if leaf.height > 0.0 else clampf(1.0 - leaf.landed / 1.2, 0.0, 1.0)
		draw_texture_rect(texture, Rect2(at, size), false, Color(1, 1, 1, alpha))
