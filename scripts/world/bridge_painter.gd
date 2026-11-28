class_name NelvarBridgePainter
extends RefCounted
## Paints rope-and-plank bridges in the island skin: mauve wood, the cool dark outline
## every object wears, a plank face below the deck where it hangs over the sky, posts
## at the shore and trodden earth where the deck meets the grass. Shapes are built in
## bridge coordinates and sampled at world pixel centers; the image is never rotated.

## Plank pitch along the bridge, in terrain texels.
const PLANK_TEXELS := 5
## Rows of plank face shown below the deck where it hangs over the sky.
const FACE_DEPTH := 2
## How far trodden earth reaches beyond a landing, in terrain texels.
const APRON_TEXELS := 5
## Weathered planks, a little warmer and darker than the island earth.
const PLANKS: Array[Color] = [
	Color("b09a8c"), Color("b8a294"), Color("a89286"), Color("bca698"),
]
const PLANK_LIGHT := Color("c8b6a8")
const PLANK_GAP := Color("8a767a")
const ROPE := Color("7e6a6c")
const ROPE_LIGHT := Color("a08a84")
const FACE_TOP := Color("8c787a")
const FACE := Color("6e5e66")
const OUTLINE := Color("4a4256")
const POST_TOP := Color("c4b0a0")
const POST_SIDE := Color("8a7470")

enum { EMPTY, DECK, FACE_CELL, LINE, EARTH }


func paint(data: NelvarWorldData, style: NelvarTerrainStyle) -> Array[NelvarBridgeArt]:
	var result: Array[NelvarBridgeArt] = []
	for bridge in data.bridges:
		result.append(_paint_bridge(bridge, data, maxi(1, style.pixel_size)))
	return result


func _paint_bridge(bridge: NelvarWorldData.Bridge, data: NelvarWorldData,
		pixel_size: int) -> NelvarBridgeArt:
	var art := NelvarBridgeArt.new()
	art.pixel_size = pixel_size
	var step := float(pixel_size)
	var bounds := bridge.bounds.grow(step * (APRON_TEXELS + FACE_DEPTH + 4))
	var origin := (bounds.position / step).floor() * step
	var size := Vector2i(((bounds.end - origin) / step).ceil())
	art.world_rect = Rect2(origin, Vector2(size) * step)
	art.image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var grid := Vector2i((origin / step).round())
	var direction := bridge.start.direction_to(bridge.finish)
	var side := direction.orthogonal()
	var length := bridge.start.distance_to(bridge.finish)
	var half_width := bridge.width * 0.5
	var land_a := data.islands[bridge.island_a].polygon
	var land_b := data.islands[bridge.island_b].polygon
	# The ropes hang between posts standing on land just before each shore.
	var shore_a := _shore(land_a, bridge.start, direction, length, step)
	var shore_b := length - _shore(land_b, bridge.finish, -direction, length, step)
	var post_a := maxf(step, shore_a - step * 2.0)
	var post_b := minf(length - step, shore_b + step * 2.0)
	var rope_width := step * 1.5
	var plank_count := maxi(1, roundi(length / (step * PLANK_TEXELS)))
	var plank_step := length / plank_count
	# A seam must span at least a terrain pixel to stay continuous after sampling.
	var gap_width := minf(plank_step * 0.4, step * 1.05)
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:bridge:%d:%d" % [data.world_seed, bridge.island_a, bridge.island_b]).hash()
	var boards: Array[Color] = []
	for i in plank_count:
		boards.append(PLANKS[rng.randi_range(0, PLANKS.size() - 1)])
	var paint_seed := rng.randi()
	var cells := PackedByteArray()
	cells.resize(size.x * size.y)
	var near_land := step * (APRON_TEXELS + 8)
	var is_land := func(point: Vector2, along: float) -> bool:
		if along < shore_a + near_land:
			return Geometry2D.is_point_in_polygon(point, land_a)
		if along > shore_b - near_land:
			return Geometry2D.is_point_in_polygon(point, land_b)
		return false

	# Deck: planks across the bridge, ropes along both edges between the posts.
	for y in size.y:
		for x in size.x:
			var local := _center(origin, x, y, step) - bridge.start
			var along := local.dot(direction)
			var across := local.dot(side)
			if along < 0.0 or along > length or absf(across) > half_width:
				continue
			var plank := clampi(floori(along / plank_step), 0, plank_count - 1)
			var phase := along - plank * plank_step
			var color := boards[plank]
			if phase >= plank_step - gap_width:
				color = PLANK_GAP
			elif phase < step * 0.9:
				color = PLANK_LIGHT
			if absf(across) > half_width - rope_width and along > post_a and along < post_b:
				var twist := posmod(floori(along / step), 3) == 0
				color = ROPE_LIGHT if twist else ROPE
			cells[y * size.x + x] = DECK
			art.image.set_pixel(x, y, color)

	# Face: the deck's plank ends seen from the south wherever it hangs over the sky.
	for y in size.y:
		for x in size.x:
			if cells[y * size.x + x] != EMPTY:
				continue
			for k in range(1, FACE_DEPTH + 1):
				if y - k < 0 or cells[(y - k) * size.x + x] != DECK:
					continue
				var point := _center(origin, x, y, step)
				if not is_land.call(point, (point - bridge.start).dot(direction)):
					cells[y * size.x + x] = FACE_CELL
					art.image.set_pixel(x, y, FACE_TOP if k == 1 else FACE)
				break

	# A one-texel outline around deck and face, as on islands, trees and rocks.
	for y in size.y:
		for x in size.x:
			if cells[y * size.x + x] != EMPTY:
				continue
			for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n := Vector2i(x, y) + offset
				if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y:
					continue
				var cell := cells[n.y * size.x + n.x]
				if cell == DECK or cell == FACE_CELL:
					cells[y * size.x + x] = LINE
					art.image.set_pixel(x, y, OUTLINE)
					break

	# Trodden earth around both landings, kept clear of the island outline.
	var reach := step * (APRON_TEXELS + 3)
	for y in size.y:
		for x in size.x:
			if cells[y * size.x + x] != EMPTY:
				continue
			var point := _center(origin, x, y, step)
			var local := point - bridge.start
			var along := local.dot(direction)
			if along > post_a and along < post_b:
				continue
			var beyond := maxf(maxf(-along, along - length), 0.0)
			var aside := maxf(absf(local.dot(side)) - half_width, 0.0)
			var key := _hash(grid.x + x, grid.y + y, paint_seed)
			var limit := step * (1.5 + float(key % 4))
			if Vector2(beyond * 0.55, aside).length() > limit or beyond > reach:
				continue
			if not _inland(point, along, step * 3.0, is_land):
				continue
			cells[y * size.x + x] = EARTH
			var earth := NelvarTerrainPainter.DIRT_PALETTE
			art.image.set_pixel(x, y, earth[(key >> 4) % earth.size()])

	for along in [post_a, post_b]:
		for sign_value in [-1.0, 1.0]:
			var point: Vector2 = bridge.start + direction * along + side * sign_value * half_width
			_post(art.image, Vector2i(((point - origin) / step).floor()))
	art.texture = ImageTexture.create_from_image(art.image)
	return art


## Distance along the centerline from `from` to where it leaves `polygon`.
func _shore(polygon: PackedVector2Array, from: Vector2, direction: Vector2,
		length: float, step: float) -> float:
	var along := 0.0
	while along < length and Geometry2D.is_point_in_polygon(from + direction * along, polygon):
		along += step * 0.5
	return along


func _inland(point: Vector2, along: float, margin: float, is_land: Callable) -> bool:
	for offset: Vector2 in [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		if not is_land.call(point + offset * margin, along):
			return false
	return true


## A short post: a light top above a darker side, both outlined.
func _post(image: Image, top_left: Vector2i) -> void:
	var origin := top_left - Vector2i(1, 2)
	for y in range(-1, 5):
		for x in range(-1, 4):
			var corner := (x == -1 or x == 3) and (y == -1 or y == 4)
			if corner:
				continue
			var color := OUTLINE
			if x >= 0 and x <= 2 and y >= 0 and y <= 3:
				color = POST_TOP if y < 2 else POST_SIDE
			var pixel := origin + Vector2i(x, y)
			if Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel):
				image.set_pixelv(pixel, color)


func _center(origin: Vector2, x: int, y: int, step: float) -> Vector2:
	return origin + Vector2(x + 0.5, y + 0.5) * step


func _hash(x: int, y: int, salt: int) -> int:
	var value := (x * 374761393 + y * 668265263 + salt) & 0x7fffffff
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
	return (value ^ (value >> 16)) & 0x7fffffff
