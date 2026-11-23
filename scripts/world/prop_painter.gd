class_name NelvarPropPainter
extends RefCounted
## Bakes rocks and bushes on the world pixel grid in the style of the air menu: blobs lit
## like spheres from the upper right and Bayer-dithered, outlined only on shaded edges.
## Rocks are cool lavender stone (the menu's statue), sometimes under a cap of moss;
## bushes are clumps of tree foliage, some with pale blossoms.

## Shaded edges darker than this get the outline; stone is outlined further round.
const ROCK_OUTLINE_LEVEL := 0.7
const BUSH_OUTLINE_LEVEL := 0.6
const STONE: Array[Color] = [Color("787e96"), Color("949aae"), Color("b0b6c6"),
	Color("ccd2de"), Color("e6eaf2")]
const STONE_OUTLINE := Color("464c68")
const STONE_CRACK := Color("6a7088")
const MOSS: Array[Color] = [Color("6aa676"), Color("88c088"), Color("a8d8a0"), Color("c8ecbc")]
const BLOSSOMS: Array[Color] = [Color("fbe6ef"), Color("f4bace"), Color("fff4d6"), Color("ddd2f8")]
## Bush clumps as (x, y, radius x, radius y) in units of radius / 11 — the menu's bush.
const BUSH_ROUND: Array[Vector4] = [Vector4(-5, -4, 6, 5), Vector4(5, -4, 6, 5), Vector4(0, -7, 7, 6)]
const BUSH_WIDE: Array[Vector4] = [Vector4(-7, -3, 5, 4), Vector4(7, -3, 5, 4),
	Vector4(-2, -7, 6, 5), Vector4(4, -8, 5, 5)]

class Blob:
	var center: Vector2
	var axes: Vector2
	## Unit height below which the blob is cut flat; 1 or more keeps it round.
	var flat := 1.0
	var wobble := 0.12
	var texture := 0.12
	var bias := 0.0
	var phase: Vector2
	var salt: int


func paint(prop: NelvarPropData.PropSpec, style: NelvarTerrainStyle) -> NelvarPropArt:
	var art := NelvarPropArt.new()
	art.pixel_size = maxi(1, style.pixel_size)
	var step := float(art.pixel_size)
	var rng := RandomNumberGenerator.new()
	rng.seed = prop.appearance_seed
	var solid := prop.is_solid()
	var blobs := _rock(prop, rng) if solid else _bush(prop, rng)
	# The shadow falls slightly left: the sun is upper right.
	var shadow_center := Vector2(-0.12, 0.1) * prop.radius
	var shadow_reach := prop.radius * (Vector2(1.15, 0.5) if solid else Vector2(1.1, 0.38)) \
		+ Vector2.ONE * step * 0.5
	var bounds := Rect2(shadow_center - shadow_reach, shadow_reach * 2.0)
	for blob in blobs:
		var reach := blob.axes * (1.0 + blob.wobble)
		bounds = bounds.merge(Rect2(blob.center - reach, reach * 2.0))
	bounds = bounds.grow(step * 2.0)
	var world_origin := ((prop.position + bounds.position) / step).floor() * step
	var size := Vector2i(((prop.position + bounds.end - world_origin) / step).ceil())
	art.local_rect = Rect2(world_origin - prop.position, Vector2(size) * step)
	art.image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var grid := Vector2i((world_origin / step).round())
	for y in size.y:
		for x in size.x:
			var point := art.local_rect.position + Vector2(x + 0.5, y + 0.5) * step
			var shade := NelvarPixelArt.shadow_at(point, shadow_center, shadow_reach, grid + Vector2i(x, y))
			if shade.a > 0.0:
				art.image.set_pixel(x, y, shade)
	var body := PackedByteArray()
	body.resize(size.x * size.y)
	var colors := STONE if solid else NelvarTreePainter.foliage(prop.palette)
	var outline := STONE_OUTLINE if solid \
		else NelvarTreePainter.OUTLINES[clampi(prop.palette, 0, NelvarTreePainter.OUTLINES.size() - 1)]
	var levels := PackedFloat32Array()
	levels.resize(size.x * size.y)
	for blob in blobs:
		_paint_blob(art, blob, step, grid, colors, body, levels)
	_outline_silhouette(art, body, levels, outline,
		ROCK_OUTLINE_LEVEL if solid else BUSH_OUTLINE_LEVEL)
	if solid:
		if prop.radius >= 20.0:
			_cracks(art, body, rng)
		if prop.accent and prop.radius >= 22.0:
			_moss(art, body, grid, prop.appearance_seed & 0xffff)
	elif prop.accent:
		_blossoms(art, body, rng)
	art.texture = ImageTexture.create_from_image(art.image)
	return art


## A boulder: the main body, sometimes a lower shoulder behind it and a smaller stone on top.
func _rock(prop: NelvarPropData.PropSpec, rng: RandomNumberGenerator) -> Array[Blob]:
	var r := prop.radius
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var tall := rng.randf_range(0.9, 1.1)
	# The flat base of the main body sits at the front of the collision footprint.
	var base := 0.5 - 0.72 * tall
	var blobs: Array[Blob] = []
	if r >= 18.0 and rng.randf() < 0.6:
		blobs.append(_blob(rng, Vector2(-side * 0.42, 0.0) * r, Vector2(0.55, 0.55) * r, 0.7, -0.12, 0.14))
	blobs.append(_blob(rng, Vector2(rng.randf_range(-0.06, 0.06), base) * r, Vector2(0.92, tall) * r,
		0.72, -0.06, 0.14))
	if r >= 22.0 and rng.randf() < 0.45:
		blobs.append(_blob(rng, Vector2(side * 0.28, base - tall * 0.8) * r, Vector2(0.46, 0.4) * r,
			0.85, 0.04, 0.12))
	return blobs


func _bush(prop: NelvarPropData.PropSpec, rng: RandomNumberGenerator) -> Array[Blob]:
	var unit := prop.radius / 11.0
	var layout := BUSH_WIDE if rng.randf() < 0.4 else BUSH_ROUND
	var blobs: Array[Blob] = []
	for clump in layout:
		var jitter := Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.6, 0.6))
		var scale := rng.randf_range(0.9, 1.1)
		blobs.append(_blob(rng, (Vector2(clump.x, clump.y) + jitter) * unit,
			Vector2(clump.z, clump.w) * scale * unit, 0.7, 0.0, 0.2, 0.15))
	return blobs


func _blob(rng: RandomNumberGenerator, center: Vector2, axes: Vector2, flat: float,
		bias: float, texture: float, wobble := 0.12) -> Blob:
	var blob := Blob.new()
	blob.center = center
	blob.axes = axes
	blob.flat = flat
	blob.bias = bias
	blob.texture = texture
	blob.wobble = wobble
	blob.phase = Vector2(rng.randf_range(0.0, 64.0), rng.randf_range(0.0, 64.0))
	blob.salt = rng.randi() & 0xffff
	return blob


## Paints a lit blob over the ones before it. Where its own shaded rim crosses earlier
## blobs it darkens to the deepest shade, which separates the clumps softly; the hard
## outline goes only round the outer silhouette (see _outline_silhouette).
func _paint_blob(art: NelvarPropArt, blob: Blob, step: float, grid: Vector2i,
		colors: Array[Color], body: PackedByteArray, levels: PackedFloat32Array) -> void:
	var reach := blob.axes * (1.0 + blob.wobble)
	var from := ((blob.center - reach - art.local_rect.position) / step).floor()
	var to := ((blob.center + reach - art.local_rect.position) / step).ceil()
	var size := art.image.get_size()
	var light := NelvarPixelArt.LIGHT
	for y in range(maxi(0, int(from.y)), mini(size.y, int(to.y) + 1)):
		for x in range(maxi(0, int(from.x)), mini(size.x, int(to.x) + 1)):
			var point := art.local_rect.position + Vector2(x + 0.5, y + 0.5) * step
			var local := _inside(blob, point)
			if local.x == INF:
				continue
			var cell := grid + Vector2i(x, y)
			var nz := sqrt(maxf(0.0, 1.0 - local.length_squared()))
			var lit := local.x * light.x + local.y * light.y + nz * light.z
			var grain := NelvarPixelArt.value_noise(cell.x * 0.45, cell.y * 0.45, blob.salt + 5) - 0.5
			var level := 0.35 + 0.5 * lit + blob.bias + grain * blob.texture * 2.0
			var color := NelvarPixelArt.ramp(colors, level, cell)
			if level < BUSH_OUTLINE_LEVEL and _on_edge(blob, point, step):
				color = colors[0]
			art.image.set_pixel(x, y, color)
			body[y * size.x + x] = 1
			levels[y * size.x + x] = level


## Shaded pixels on the outer edge of the whole prop get the dark outline; the brightly
## lit upper-right edge stays open, as in the menu art.
func _outline_silhouette(art: NelvarPropArt, body: PackedByteArray, levels: PackedFloat32Array,
		outline: Color, outline_level: float) -> void:
	var size := art.image.get_size()
	for y in size.y:
		for x in size.x:
			var index := y * size.x + x
			if body[index] == 0 or levels[index] >= outline_level:
				continue
			if x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1 \
					or body[index - 1] == 0 or body[index + 1] == 0 \
					or body[index - size.x] == 0 or body[index + size.x] == 0:
				art.image.set_pixel(x, y, outline)


## Position inside the blob's wobbly, flat-bottomed ellipse in unit coordinates, or INF.
func _inside(blob: Blob, point: Vector2) -> Vector2:
	var local := (point - blob.center) / blob.axes
	if local.y > blob.flat:
		return Vector2(INF, INF)
	var distance := local.length()
	var edge := 1.0
	if distance > 0.0:
		var direction := local / distance
		edge += blob.wobble * (NelvarPixelArt.value_noise(direction.x * 1.7 + blob.phase.x,
			direction.y * 1.7 + blob.phase.y, 7) * 2.0 - 1.0)
	if distance > edge:
		return Vector2(INF, INF)
	return local / edge


func _on_edge(blob: Blob, point: Vector2, step: float) -> bool:
	for offset: Vector2 in [Vector2(step, 0), Vector2(-step, 0), Vector2(0, step), Vector2(0, -step)]:
		if _inside(blob, point + offset).x == INF:
			return true
	return false


## A few short dark cracks running down the stone.
func _cracks(art: NelvarPropArt, body: PackedByteArray, rng: RandomNumberGenerator) -> void:
	var inner := _interior(body, art.image.get_size())
	if inner.is_empty():
		return
	var width := art.image.get_width()
	for crack in rng.randi_range(1, 2):
		var point := inner[rng.randi_range(0, inner.size() - 1)]
		for length in rng.randi_range(2, 4):
			if point.y >= art.image.get_height() or body[point.y * width + point.x] == 0:
				break
			art.image.set_pixelv(point, STONE_CRACK)
			point += Vector2i(rng.randi_range(-1, 1), 1)
			point.x = clampi(point.x, 0, width - 1)


## Moss on top of the rock: the first few stone pixels of every column, darker at the
## shaded left rim (the menu statue's cap).
func _moss(art: NelvarPropArt, body: PackedByteArray, grid: Vector2i, salt: int) -> void:
	var size := art.image.get_size()
	for x in size.x:
		var depth := 0
		for y in size.y:
			if body[y * size.x + x] == 0:
				if depth > 0:
					break
				continue
			var cell := grid + Vector2i(x, y)
			if depth > int(NelvarPixelArt.value_noise(cell.x * 0.35, 0.5, salt) * 2.5):
				break
			depth += 1
			var open_left := x == 0 or body[y * size.x + x - 1] == 0
			var level := 0.7 - (0.3 if open_left else 0.0) \
				+ (NelvarPixelArt.value_noise(cell.x * 0.5, cell.y * 0.5, salt + 3) - 0.5) * 0.4
			art.image.set_pixel(x, y, NelvarPixelArt.ramp(MOSS, level, cell))


func _blossoms(art: NelvarPropArt, body: PackedByteArray, rng: RandomNumberGenerator) -> void:
	var inner := _interior(body, art.image.get_size())
	if inner.is_empty():
		return
	var color := BLOSSOMS[rng.randi_range(0, BLOSSOMS.size() - 1)]
	for blossom in rng.randi_range(4, 6):
		art.image.set_pixelv(inner[rng.randi_range(0, inner.size() - 1)], color)


## Body pixels whose four neighbours are body pixels too.
func _interior(body: PackedByteArray, size: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(1, size.y - 1):
		for x in range(1, size.x - 1):
			var index := y * size.x + x
			if body[index] == 1 and body[index - 1] == 1 and body[index + 1] == 1 \
					and body[index - size.x] == 1 and body[index + size.x] == 1:
				result.append(Vector2i(x, y))
	return result
