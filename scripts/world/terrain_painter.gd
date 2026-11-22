class_name NelvarTerrainPainter
extends RefCounted
## Rasterizes existing island geometry once, then paints a deterministic pixel skin.

const MARGIN := 14
const GRASS_CELL := 9
const GRASS_PALETTE: Array[Color] = [
	Color("718745"), Color("7d934c"), Color("899e54"), Color("96a95e"),
]
const DIRT_PALETTE: Array[Color] = [Color("9c8d5d"), Color("ab9866"), Color("b4a16e")]
const OUTLINE := Color("3f5134")
const RIM_LIGHT := Color("c2c577")
const RIM_DARK := Color("728247")
const ROOT_OUTLINE := Color("3e322a")
const ROOT_BODY := Color("79583d")
const ROOT_LIGHT := Color("b38a56")

class Raster:
	var width: int
	var height: int
	var mask: PackedByteArray
	var distance: PackedByteArray
	var bottom: PackedInt32Array
	var spans: Array[Vector3i] = []


func paint(data: NelvarWorldData, style: NelvarTerrainStyle) -> Array[NelvarIslandArt]:
	var result: Array[NelvarIslandArt] = []
	for island in data.islands:
		result.append(_paint_island(island, data, style))
	return result


func _paint_island(island: NelvarWorldData.Island, data: NelvarWorldData,
		style: NelvarTerrainStyle) -> NelvarIslandArt:
	var art := NelvarIslandArt.new()
	art.pixel_size = maxi(1, style.pixel_size)
	var step := float(art.pixel_size)
	var origin := (island.bounds.position / step).floor() * step - Vector2.ONE * MARGIN * step
	var width := ceili((island.bounds.end.x - origin.x) / step) + MARGIN
	var ground_height := ceili((island.bounds.end.y - origin.y) / step) + MARGIN
	var height := ground_height + style.cliff_depth + style.root_length + MARGIN
	art.world_rect = Rect2(origin, Vector2(width, height) * step)
	art.surface_image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	art.underside_image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	var raster := _rasterize(island.polygon, origin, step, width, ground_height)
	var paint_seed := ("%d:terrain:%d" % [data.world_seed, island.id]).hash()
	var noise := FastNoiseLite.new()
	noise.seed = paint_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	_paint_ground(art, raster, noise, paint_seed)
	_paint_roots(art, raster, style, paint_seed)
	_paint_cliff(art, raster, style, paint_seed)
	_paint_grass(art, raster, data, style, noise, paint_seed)
	art.surface_texture = ImageTexture.create_from_image(art.surface_image)
	art.underside_texture = ImageTexture.create_from_image(art.underside_image)
	return art


func _rasterize(polygon: PackedVector2Array, origin: Vector2, step: float,
		width: int, height: int) -> Raster:
	var raster := Raster.new()
	raster.width = width
	raster.height = height
	raster.mask.resize(width * height)
	raster.distance.resize(width * height)
	raster.bottom.resize(width)
	raster.bottom.fill(-1)
	# Pixel centers are tested against horizontal polygon slices. Shared world
	# coordinates keep the silhouette aligned across all chunk boundaries.
	for y in height:
		var scan_y := origin.y + (float(y) + 0.5) * step
		var crossings: Array[float] = []
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			if (a.y > scan_y) == (b.y > scan_y):
				continue
			crossings.append(a.x + (scan_y - a.y) * (b.x - a.x) / (b.y - a.y))
		crossings.sort()
		for pair in range(0, crossings.size() - 1, 2):
			var left := maxi(1, ceili((crossings[pair] - origin.x) / step - 0.5))
			var right := mini(width - 1, ceili((crossings[pair + 1] - origin.x) / step - 0.5))
			if right <= left:
				continue
			raster.spans.append(Vector3i(y, left, right))
			for x in range(left, right):
				var index := y * width + x
				raster.mask[index] = 1
				raster.bottom[x] = y
				raster.distance[index] = mini(254,
					mini(raster.distance[index - 1], raster.distance[index - width]) + 1)
	for row in range(raster.spans.size() - 1, -1, -1):
		var span := raster.spans[row]
		for x in range(span.z - 1, span.y - 1, -1):
			var index := span.x * width + x
			raster.distance[index] = mini(raster.distance[index],
				mini(raster.distance[index + 1], raster.distance[index + width]) + 1)
	return raster


func _paint_ground(art: NelvarIslandArt, raster: Raster, noise: FastNoiseLite,
		paint_seed: int) -> void:
	var grid_origin := Vector2i((art.world_rect.position / art.pixel_size).round())
	for span in raster.spans:
		var y := span.x
		for x in range(span.y, span.z):
			var gx := grid_origin.x + x
			var gy := grid_origin.y + y
			var index := y * raster.width + x
			var edge_distance := raster.distance[index]
			var grain := _hash(gx, gy, paint_seed)
			var patch := noise.get_noise_2d(gx, gy)
			var shade := clampi(floori((patch + 0.48) * 3.6), 0, GRASS_PALETTE.size() - 1)
			var color := GRASS_PALETTE[shade]
			if _is_dirt(patch, grain) and edge_distance > 4:
				color = DIRT_PALETTE[grain % DIRT_PALETTE.size()]
			elif grain % 113 < 2 and edge_distance > 3:
				color = GRASS_PALETTE[clampi(shade + (1 if grain % 2 == 0 else -1), 0, 3)]
			if edge_distance == 1:
				color = OUTLINE
			elif edge_distance == 2:
				var north := raster.mask[index - raster.width * 2] == 0
				color = RIM_LIGHT if north else RIM_DARK
			elif edge_distance == 3 and raster.mask[index - raster.width * 3] == 0:
				color = Color("a7b561")
			art.surface_image.set_pixel(x, y, color)


func _paint_cliff(art: NelvarIslandArt, raster: Raster, style: NelvarTerrainStyle,
		paint_seed: int) -> void:
	var grid_origin := Vector2i((art.world_rect.position / art.pixel_size).round())
	for x in raster.width:
		var bottom := raster.bottom[x]
		if bottom < 0:
			continue
		var gx := grid_origin.x + x
		var depth := _cliff_depth(gx, style, paint_seed)
		for drop in range(1, depth + 1):
			var y := bottom + drop
			var block := _hash(floori(float(gx) / 7.0), drop / 3, paint_seed ^ 0x73A1)
			var color := Color("806043")
			if drop <= 2:
				color = Color("55432e")
			elif drop <= 4:
				color = Color("a18051") if block % 3 == 0 else Color("947148")
			elif drop >= depth - 1:
				color = Color("44382d")
			elif block % 5 == 0:
				color = Color("936c47")
			elif block % 5 == 1:
				color = Color("6d513b")
			if drop > 3 and drop < depth - 1:
				if _hash(gx, 0, paint_seed ^ 0xA713) % 23 == 0:
					color = Color("503e2e")
				elif _hash(gx, drop, paint_seed) % 79 == 0:
					color = Color("ba9763")
			art.underside_image.set_pixel(x, y, color)


func _paint_roots(art: NelvarIslandArt, raster: Raster, style: NelvarTerrainStyle,
		paint_seed: int) -> void:
	var grid_origin := Vector2i((art.world_rect.position / art.pixel_size).round())
	for cell in range(MARGIN, raster.width - MARGIN, 18):
		var key := _hash(grid_origin.x + cell, 0, paint_seed ^ 0x72B3)
		if key % 100 < 24:
			continue
		var x := clampi(cell + key % 9 - 4, MARGIN, raster.width - MARGIN - 1)
		var bottom := raster.bottom[x]
		if bottom < 0:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = _hash(grid_origin.x + x, grid_origin.y + bottom, paint_seed)
		var depth := _cliff_depth(grid_origin.x + x, style, paint_seed)
		var length := rng.randi_range(maxi(8, style.root_length / 2), style.root_length)
		var start := Vector2i(x, bottom + depth - 3)
		var points: Array[Vector2i] = [start]
		var tip := start
		while tip.y < start.y + length:
			tip.x = clampi(tip.x + rng.randi_range(-2, 2), start.x - 7, start.x + 7)
			tip.y = mini(tip.y + rng.randi_range(3, 5), start.y + length)
			points.append(tip)
		var branch := points[points.size() / 2]
		var sign_value := -1 if key % 2 == 0 else 1
		var branch_end := branch + Vector2i(sign_value * rng.randi_range(4, 7), 5)
		_pixel_line(art.underside_image, branch, branch_end, 2, ROOT_OUTLINE)
		_pixel_line(art.underside_image, branch + Vector2i(0, 1), branch_end, 1, ROOT_BODY)
		for i in range(1, points.size()):
			var thickness := 3 if i < points.size() / 2 else 2
			if i == points.size() - 1:
				thickness = 1
			_pixel_line(art.underside_image, points[i - 1], points[i], thickness, ROOT_OUTLINE)
			if thickness > 1:
				_pixel_line(art.underside_image, points[i - 1], points[i], thickness - 1, ROOT_BODY)
			if thickness > 2:
				_pixel_line(art.underside_image, points[i - 1] + Vector2i(-1, 0),
					points[i] + Vector2i(-1, 0), 1, ROOT_LIGHT)


func _paint_grass(art: NelvarIslandArt, raster: Raster, data: NelvarWorldData,
		style: NelvarTerrainStyle, noise: FastNoiseLite, paint_seed: int) -> void:
	var grid_origin := Vector2i((art.world_rect.position / art.pixel_size).round())
	for cell_y in range(MARGIN, raster.height - MARGIN, GRASS_CELL):
		for cell_x in range(MARGIN, raster.width - MARGIN, GRASS_CELL):
			var key := _hash(grid_origin.x + cell_x, grid_origin.y + cell_y, paint_seed ^ 0x617A)
			if float(key % 1000) / 1000.0 >= style.grass_density:
				continue
			var x := cell_x + (key >> 10) % 5 - 2
			var y := cell_y + (key >> 15) % 5 - 2
			if raster.distance[y * raster.width + x] < 6:
				continue
			var patch := noise.get_noise_2d(grid_origin.x + x, grid_origin.y + y)
			if _is_dirt(patch, _hash(grid_origin.x + x, grid_origin.y + y, paint_seed)):
				continue
			var world_point := art.world_rect.position + Vector2(x + 0.5, y + 0.5) * art.pixel_size
			if _near_bridge(world_point, data, float(art.pixel_size) * 5.0):
				continue
			_tuft(art.surface_image, Vector2i(x, y), 3 + key % 3, key)


func _tuft(image: Image, base: Vector2i, height: int, key: int) -> void:
	var shadow := Color("536d37")
	var stem := Color("637f3c")
	var tip := Color("b5c76f") if key % 4 != 0 else Color("d0d58a")
	_pixel_line(image, base + Vector2i(-1, 0), base + Vector2i(2, 0), 1, shadow)
	_pixel_line(image, base, base + Vector2i(0, -height), 1, stem)
	_pixel_line(image, base + Vector2i(-1, -1), base + Vector2i(-2, -height + 1), 1, shadow)
	_pixel_line(image, base + Vector2i(1, -1), base + Vector2i(3, -height + 1), 1, stem)
	image.set_pixelv(base + Vector2i(0, -height), tip)
	image.set_pixelv(base + Vector2i(3, -height + 1), tip)
	if key % 3 == 0:
		image.set_pixelv(base + Vector2i(-2, -height + 1), Color("9fb45c"))


func _near_bridge(point: Vector2, data: NelvarWorldData, margin: float) -> bool:
	for bridge in data.bridges:
		if not bridge.bounds.grow(margin).has_point(point):
			continue
		var closest := Geometry2D.get_closest_point_to_segment(point, bridge.start, bridge.finish)
		if point.distance_to(closest) < bridge.width * 0.5 + margin:
			return true
	return false


func _is_dirt(patch: float, grain: int) -> bool:
	return patch > 0.39 or (patch > 0.31 and grain % 5 < 2)


func _cliff_depth(gx: int, style: NelvarTerrainStyle, paint_seed: int) -> int:
	return style.cliff_depth + _hash(floori(float(gx) / 6.0), 0, paint_seed ^ 0x4321) % 4 - 1


func _hash(x: int, y: int, salt: int) -> int:
	var value := (x * 374761393 + y * 668265263 + salt) & 0x7fffffff
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
	return (value ^ (value >> 16)) & 0x7fffffff


func _pixel_line(image: Image, start: Vector2i, finish: Vector2i,
		thickness: int, color: Color) -> void:
	var point := start
	var dx := absi(finish.x - start.x)
	var dy := absi(finish.y - start.y)
	var sx := 1 if start.x < finish.x else -1
	var sy := 1 if start.y < finish.y else -1
	var error := dx - dy
	while true:
		var origin := point - Vector2i.ONE * (thickness >> 1)
		var rect := Rect2i(origin, Vector2i.ONE * thickness)
		rect = rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		if rect.has_area():
			image.fill_rect(rect, color)
		if point == finish:
			break
		var doubled := error * 2
		if doubled > -dy:
			error -= dy
			point.x += sx
		if doubled < dx:
			error += dx
			point.y += sy
