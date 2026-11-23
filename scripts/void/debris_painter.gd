class_name NelvarDebrisPainter
extends RefCounted
## Bakes the pixel art of a piece of the Void: its top surface, the torn underside
## hanging below it and an optional glow layer (drawn additively: lava, crystal
## edges, runes). Everything that fell into the Void has lost most of its colour;
## the undersides dissolve into it.

const PIXEL := 4
const MARGIN := 3
## How far the underside may reach below the lowest surface pixel, texels.
const UNDERSIDE_ROOM := 40
const MONOLITH_UNDERSIDE_ROOM := 90

const OUTLINE := Color("060609")
const VOID_TINT := Color("1c1030")
const GLOW_VIOLET := Color(0.62, 0.36, 1.0)

const EARTH: Array[Color] = [Color("232c27"), Color("2c3830"), Color("364338"), Color("424f43"),
	Color("4f5c4f")]
const ASH: Array[Color] = [Color("2a2624"), Color("332e2b"), Color("3d3733")]
const ROCK: Array[Color] = [Color("1a1a22"), Color("23232c"), Color("2d2d38"), Color("383845"),
	Color("454554")]
const BARK: Array[Color] = [Color("1c1515"), Color("271e1c"), Color("332824"), Color("40322c"),
	Color("4e3d35")]
const WOOD: Array[Color] = [Color("4a3c32"), Color("5c4a3c"), Color("6e5a48")]
const ICE: Array[Color] = [Color("15253a"), Color("1c3350"), Color("264566"), Color("33587c"),
	Color("466e92"), Color("6189a8")]
const BASALT: Array[Color] = [Color("110b0d"), Color("191113"), Color("22171a"), Color("2c1f21"),
	Color("372828")]
const CLOUD_STONE: Array[Color] = [Color("2c3046"), Color("363a54"), Color("414562"), Color("4e5272"),
	Color("5c6084")]
const RUIN: Array[Color] = [Color("1b1a23"), Color("23212c"), Color("2c2a36"), Color("363441"),
	Color("42404e")]
const SHARD: Array[Color] = [Color("180c2a"), Color("261440"), Color("361d5a"), Color("4a2a78"),
	Color("62409a"), Color("8462c0")]
const MONOLITH: Array[Color] = [Color("0b0b0f"), Color("111116"), Color("17171e"), Color("1e1e27"),
	Color("262630"), Color("2f2f3a")]

## Light rim along north-facing edges, per kind.
const RIMS := {
	NelvarVoidData.Kind.EARTH: Color("5e6c5c"), NelvarVoidData.Kind.ROCK: Color("55556a"),
	NelvarVoidData.Kind.LOG: Color("5e4a40"), NelvarVoidData.Kind.ICE: Color("86b4cc"),
	NelvarVoidData.Kind.FIRE: Color("4a3432"), NelvarVoidData.Kind.AIR: Color("727896"),
	NelvarVoidData.Kind.RUIN: Color("54525f"), NelvarVoidData.Kind.SHARD: Color("b48ef0"),
	NelvarVoidData.Kind.MONOLITH: Color("3c3c4a"),
}
## Underside: lip, body, darker body, dangling things.
const CLIFFS := {
	NelvarVoidData.Kind.EARTH: [Color("2c2624"), Color("221d1c"), Color("1a1617"), Color("15111a")],
	NelvarVoidData.Kind.ROCK: [Color("2a2a34"), Color("1f1f28"), Color("18181f"), Color("2a2a34")],
	NelvarVoidData.Kind.LOG: [Color("2a201e"), Color("1e1716"), Color("161112"), Color("2a201e")],
	NelvarVoidData.Kind.ICE: [Color("2a4864"), Color("1c3048"), Color("15233a"), Color("5c8cac")],
	NelvarVoidData.Kind.FIRE: [Color("2a1c1c"), Color("1a1012"), Color("120a0c"), Color("6a2414")],
	NelvarVoidData.Kind.AIR: [Color("3e4260"), Color("32354e"), Color("282b40"), Color("4a4e6c")],
	NelvarVoidData.Kind.RUIN: [Color("2c2a36"), Color("211f29"), Color("19181f"), Color("3a3844")],
	NelvarVoidData.Kind.SHARD: [Color("4a2a78"), Color("2c1848"), Color("1e1034"), Color("62409a")],
	NelvarVoidData.Kind.MONOLITH: [Color("1a1a22"), Color("0e0e13"), Color("09090c"), Color("16161d")],
}
## 3x5 runes: rows top to bottom, bit 2 = left column.
const RUNES: Array[PackedInt32Array] = [
	[7, 2, 7, 5, 5], [5, 7, 2, 2, 7], [2, 5, 7, 1, 1], [6, 1, 2, 4, 3], [7, 5, 2, 5, 7],
	[1, 3, 7, 6, 4], [4, 6, 7, 3, 1], [7, 1, 7, 4, 7],
]

## The monolith never changes; bake it once per run.
static var _monolith_art: Art


class Art:
	## Image rectangle relative to the piece origin, world units.
	var rect: Rect2
	var surface: ImageTexture
	var underside: ImageTexture
	## Additive light; null when the piece has none.
	var glow: ImageTexture
	## Painted pixels; turned into the textures above by bake().
	var surface_image: Image
	var underside_image: Image
	var glow_image: Image

	## Makes the textures (on the main thread: painting may run on a worker).
	func bake() -> Art:
		surface = ImageTexture.create_from_image(surface_image)
		underside = ImageTexture.create_from_image(underside_image)
		if glow_image != null:
			glow = ImageTexture.create_from_image(glow_image)
		return self


class Raster:
	var origin: Vector2
	var width: int
	var height: int
	var ground_height: int
	var mask: PackedByteArray
	var distance: PackedByteArray
	var bottom: PackedInt32Array


static func clear_cache() -> void:
	_monolith_art = null


## The baked monolith if it has been painted this run, else null.
static func cached_monolith() -> Art:
	return _monolith_art


## Keeps a monolith painted elsewhere (e.g. on a worker thread) for later Voids.
static func remember_monolith(art: Art) -> void:
	_monolith_art = art


func paint(piece: NelvarVoidData.Debris) -> Art:
	if piece.kind == NelvarVoidData.Kind.MONOLITH and _monolith_art != null:
		return _monolith_art
	var art := paint_images(piece).bake()
	if piece.kind == NelvarVoidData.Kind.MONOLITH:
		_monolith_art = art
	return art


## Paints without touching the renderer, so it is safe on a worker thread.
func paint_images(piece: NelvarVoidData.Debris) -> Art:
	var room := MONOLITH_UNDERSIDE_ROOM if piece.kind == NelvarVoidData.Kind.MONOLITH else UNDERSIDE_ROOM
	var raster := _rasterize(piece.polygon, room)
	var surface := Image.create(raster.width, raster.height, false, Image.FORMAT_RGBA8)
	var underside := Image.create(raster.width, raster.height, false, Image.FORMAT_RGBA8)
	var glow := Image.create(raster.width, raster.height, false, Image.FORMAT_RGBA8)
	var salt := piece.appearance_seed & 0xffffff
	var glowing := _paint_surface(piece, raster, surface, glow, salt)
	_paint_edges(piece, raster, surface)
	if piece.relic:
		_paint_rune(raster, surface, glow, Vector2i(raster.width / 2, raster.ground_height / 2),
			salt, 2)
		glowing = true
	_paint_underside(piece, raster, underside, glow, salt)
	if piece.kind == NelvarVoidData.Kind.FIRE or piece.kind == NelvarVoidData.Kind.SHARD \
			or piece.kind == NelvarVoidData.Kind.MONOLITH:
		glowing = true
	var art := Art.new()
	art.rect = Rect2(raster.origin, Vector2(raster.width, raster.height) * PIXEL)
	art.surface_image = surface
	art.underside_image = underside
	if glowing:
		art.glow_image = glow
	return art


## Scanline fill of the outline plus a two-pass distance to its edge, in texels.
func _rasterize(polygon: PackedVector2Array, room: int) -> Raster:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	var raster := Raster.new()
	raster.origin = (bounds.position / PIXEL).floor() * PIXEL - Vector2.ONE * MARGIN * PIXEL
	raster.width = ceili((bounds.end.x - raster.origin.x) / PIXEL) + MARGIN
	raster.ground_height = ceili((bounds.end.y - raster.origin.y) / PIXEL) + MARGIN
	raster.height = raster.ground_height + room
	raster.mask.resize(raster.width * raster.height)
	raster.distance.resize(raster.width * raster.height)
	raster.distance.fill(255)
	raster.bottom.resize(raster.width)
	raster.bottom.fill(-1)
	for y in raster.ground_height:
		var scan_y := raster.origin.y + (float(y) + 0.5) * PIXEL
		var crossings: Array[float] = []
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			if (a.y > scan_y) == (b.y > scan_y):
				continue
			crossings.append(a.x + (scan_y - a.y) * (b.x - a.x) / (b.y - a.y))
		crossings.sort()
		for pair in range(0, crossings.size() - 1, 2):
			var left := maxi(1, ceili((crossings[pair] - raster.origin.x) / PIXEL - 0.5))
			var right := mini(raster.width - 1, ceili((crossings[pair + 1] - raster.origin.x) / PIXEL - 0.5))
			for x in range(left, right):
				raster.mask[y * raster.width + x] = 1
				raster.bottom[x] = y
	# Chamfer distance: 0 outside, 1 on the edge pixel, growing inwards.
	var w := raster.width
	for y in raster.ground_height:
		for x in w:
			var index := y * w + x
			if raster.mask[index] == 0:
				raster.distance[index] = 0
			elif x > 0 and y > 0:
				raster.distance[index] = mini(raster.distance[index],
					mini(raster.distance[index - 1], raster.distance[index - w]) + 1)
	for y in range(raster.ground_height - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var index := y * w + x
			if raster.mask[index] == 0:
				continue
			var right := raster.distance[index + 1] if x + 1 < w else 0
			var down := raster.distance[index + w] if y + 1 < raster.ground_height else 0
			raster.distance[index] = mini(raster.distance[index], mini(right, down) + 1)
	return raster


# --- Surface -----------------------------------------------------------------

## Returns true if anything was painted into the glow layer.
func _paint_surface(piece: NelvarVoidData.Debris, raster: Raster, image: Image, glow: Image,
		salt: int) -> bool:
	var glowing := false
	var axis := Vector2.from_angle(-piece.angle)
	var half_width := _half_width(piece)
	for y in raster.ground_height:
		for x in raster.width:
			var index := y * raster.width + x
			if raster.mask[index] == 0:
				continue
			var cell := Vector2i(x, y)
			var local := raster.origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * PIXEL
			var t := Vector2(x, y)
			var color: Color
			match piece.kind:
				NelvarVoidData.Kind.EARTH:
					color = _earth(t, cell, salt)
				NelvarVoidData.Kind.ROCK:
					color = _rock(t, cell, salt)
				NelvarVoidData.Kind.LOG:
					color = _bark(local, axis, half_width, piece.radius, cell, salt)
				NelvarVoidData.Kind.ICE:
					color = _ice(t, cell, salt)
				NelvarVoidData.Kind.FIRE:
					var lava := _lava(t, salt)
					color = _basalt(t, cell, salt, lava)
					if lava > 0.0:
						glow.set_pixel(x, y, Color(1.0, 0.42, 0.12, lava))
						glowing = true
				NelvarVoidData.Kind.AIR:
					color = _cloud_stone(t, cell, salt)
				NelvarVoidData.Kind.RUIN:
					color = _ruin(local, axis, cell, salt)
				NelvarVoidData.Kind.SHARD:
					var edge := _crystal_edge(t, salt)
					color = NelvarPixelArt.ramp(SHARD, _facet_level(t, 6.0, salt) * 0.8 + edge * 0.5, cell)
					color.a = 0.9
					if edge > 0.0:
						glow.set_pixel(x, y, Color(GLOW_VIOLET, edge * 0.55))
						glowing = true
				NelvarVoidData.Kind.MONOLITH:
					color = _monolith(local, t, cell, glow, x, y, salt)
			image.set_pixel(x, y, color)
	return glowing


func _half_width(piece: NelvarVoidData.Debris) -> float:
	if piece.kind != NelvarVoidData.Kind.LOG:
		return 0.0
	var across := Vector2.from_angle(piece.angle).orthogonal()
	var half := 0.0
	for point in piece.polygon:
		half = maxf(half, absf(point.dot(across)))
	return half


func _noise(t: Vector2, scale: float, salt: int) -> float:
	return NelvarPixelArt.value_noise(t.x / scale, t.y / scale, salt)


## Jittered-grid Voronoi in texels: x = nearest distance, y = second nearest, z = cell id.
## `blocky` measures with the largest axis, so cells come out as angular blocks.
func _voronoi(t: Vector2, cell_size: float, salt: int, blocky := false) -> Vector3:
	var base := Vector2i(floori(t.x / cell_size), floori(t.y / cell_size))
	var best := Vector3(INF, INF, 0.0)
	for j in range(-1, 2):
		for i in range(-1, 2):
			var c := base + Vector2i(i, j)
			var site := (Vector2(c) + Vector2(NelvarPixelArt.hash01(c.x, c.y, salt),
				NelvarPixelArt.hash01(c.x, c.y, salt + 7)) * 0.8 + Vector2(0.1, 0.1)) * cell_size
			var delta := (t - site).abs()
			var d := maxf(delta.x, delta.y) if blocky else delta.length()
			if d < best.x:
				best = Vector3(d, best.x, float((c.x * 92821 + c.y * 68917) & 0xffff))
			elif d < best.y:
				best.y = d
	return best


## Flat-lit facets: each Voronoi cell gets its own tone.
func _facet_level(t: Vector2, cell_size: float, salt: int) -> float:
	var v := _voronoi(t, cell_size, salt)
	return 0.2 + 0.55 * NelvarPixelArt.hash01(int(v.z), 3, salt)


func _earth(t: Vector2, cell: Vector2i, salt: int) -> Color:
	var patch := _noise(t, 7.0, salt)
	if _noise(t, 11.0, salt + 3) > 0.64:
		return NelvarPixelArt.ramp(ASH, patch, cell)
	var color := NelvarPixelArt.ramp(EARTH, patch * 0.85 + 0.1, cell)
	# Dead tufts: grey stalks the colour has left.
	var key := NelvarPixelArt.hash01(floori(t.x / 6.0), floori(t.y / 6.0), salt + 11)
	if key < 0.3:
		var tuft := Vector2(floor(t.x / 6.0) * 6.0 + 2.0 + floor(key * 10.0) , floor(t.y / 6.0) * 6.0 + 3.0)
		if int(t.x) == int(tuft.x) and t.y >= tuft.y - 2.0 and t.y <= tuft.y:
			color = Color("6a7064") if int(t.y) == int(tuft.y) - 2 else Color("525a50")
	return color


func _rock(t: Vector2, cell: Vector2i, salt: int) -> Color:
	var v := _voronoi(t, 9.0, salt)
	if v.y - v.x < 0.8:
		return Color("121218")
	var level := 0.2 + 0.5 * NelvarPixelArt.hash01(int(v.z), 5, salt) + (_noise(t, 3.0, salt) - 0.5) * 0.2
	return NelvarPixelArt.ramp(ROCK, level, cell)


## A trunk lying along `axis`: lengthwise grooves, rounded shading, pale broken ends.
func _bark(local: Vector2, axis: Vector2, half_width: float, radius: float, cell: Vector2i,
		salt: int) -> Color:
	var along := local.rotated(axis.angle()).x
	var across := local.rotated(axis.angle()).y / maxf(half_width, 1.0)
	if absf(along) > radius - 18.0:
		return NelvarPixelArt.ramp(WOOD, 0.3 + _noise(Vector2(along, across * 10.0), 2.0, salt) * 0.6, cell)
	var round_light := sqrt(maxf(0.0, 1.0 - across * across)) - across * 0.35
	var groove := int(floor((across + 1.0) * half_width / PIXEL / 2.0 + _noise(Vector2(along / 24.0, 0.0), 1.0, salt) * 1.5))
	var level := 0.15 + round_light * 0.55
	if groove % 2 == 0:
		level -= 0.15
	var knot := NelvarPixelArt.hash01(floori(along / 40.0), 0, salt)
	var knot_at: float = (floorf(along / 40.0) + 0.3 + knot * 0.4) * 40.0
	if knot > 0.55 and absf(along - knot_at) < 6.0 and absf(across - (knot - 0.75) * 2.0) < 0.25:
		level = 0.05
	return NelvarPixelArt.ramp(BARK, level, cell)


func _ice(t: Vector2, cell: Vector2i, salt: int) -> Color:
	var v := _voronoi(t, 8.0, salt)
	if v.y - v.x < 0.7:
		return Color("7aa4bc")
	var level := 0.2 + 0.6 * NelvarPixelArt.hash01(int(v.z), 9, salt) + (t.x - t.y) * 0.002
	if NelvarPixelArt.hash01(cell.x, cell.y, salt + 1) > 0.993:
		return Color("b4d4e4")
	return NelvarPixelArt.ramp(ICE, level, cell)


## 0 = no lava; up to 1 in the brightest cracks.
func _lava(t: Vector2, salt: int) -> float:
	var v := _voronoi(t, 7.0, salt + 21)
	if _noise(t, 9.0, salt + 5) < 0.42:
		return 0.0
	var edge := v.y - v.x
	if edge < 0.7:
		return 0.95
	if edge < 1.6:
		return 0.3
	return 0.0


func _basalt(t: Vector2, cell: Vector2i, salt: int, lava: float) -> Color:
	if lava > 0.9:
		return Color("8a3018")
	if lava > 0.0:
		return Color("3e1812")
	var v := _voronoi(t, 7.0, salt + 21)
	if v.y - v.x < 0.7:
		return Color("0a0607")
	return NelvarPixelArt.ramp(BASALT, 0.25 + 0.5 * NelvarPixelArt.hash01(int(v.z), 2, salt), cell)


func _cloud_stone(t: Vector2, cell: Vector2i, salt: int) -> Color:
	var swirl := sin(t.x * 0.32 + t.y * 0.12 + _noise(t, 9.0, salt) * 7.0)
	var level := 0.45 + swirl * 0.2 + (_noise(t, 4.0, salt + 2) - 0.5) * 0.25
	return NelvarPixelArt.ramp(CLOUD_STONE, level, cell)


## Worn paving that follows the slab: tiles, seams, cracks, now and then a faint rune.
func _ruin(local: Vector2, axis: Vector2, cell: Vector2i, salt: int) -> Color:
	var p := local.rotated(axis.angle()) / PIXEL
	var tile := Vector2i(floori(p.x / 7.0), floori(p.y / 7.0))
	var inside := Vector2(fposmod(p.x, 7.0), fposmod(p.y, 7.0))
	if inside.x < 1.0 or inside.y < 1.0:
		return Color("121117")
	var key := NelvarPixelArt.hash01(tile.x, tile.y, salt)
	if key > 0.93:
		return Color("141319")
	if key > 0.82 and absf(inside.x - inside.y) < 0.8:
		return Color("17161d")
	return NelvarPixelArt.ramp(RUIN, 0.2 + key * 0.55 + (_noise(p, 3.0, salt) - 0.5) * 0.15, cell)


func _crystal_edge(t: Vector2, salt: int) -> float:
	var v := _voronoi(t, 6.0, salt)
	var edge := v.y - v.x
	if edge < 0.6:
		return 1.0
	if edge < 1.3:
		return 0.35
	return 0.0


## Black-grey plates of the monolith; seams sometimes hold a cold violet light. The
## arena sigil is cut into its centre (the piece origin).
func _monolith(local: Vector2, t: Vector2, cell: Vector2i, glow: Image, x: int, y: int,
		salt: int) -> Color:
	var r := local.length() / PIXEL
	var angle := local.angle()
	# Sigil: two rings, ticks between them, three spokes and an empty centre.
	var ring_outer := 44.0 * NelvarVoidData.MONOLITH_SCALE
	var ring_inner := 31.0 * NelvarVoidData.MONOLITH_SCALE
	var engraved := false
	var light := 0.0
	if absf(r - ring_outer) < 0.6 or absf(r - ring_inner) < 0.6:
		engraved = true
		light = 0.55
	elif r > ring_inner and r < ring_outer:
		var tick := fposmod(angle / TAU * 24.0, 1.0)
		if tick < 0.08 and fposmod(r, 3.0) < 2.0:
			engraved = true
			light = 0.35
	elif r < ring_inner - 3.0 and r > 6.0:
		var spoke := fposmod((angle + PI / 2.0) / TAU * 3.0, 1.0)
		if absf(spoke - 0.5) * r * TAU / 3.0 < 0.55:
			engraved = true
			light = 0.3
	elif r < 6.5 and r > 5.4:
		engraved = true
		light = 0.8
	if engraved:
		glow.set_pixel(x, y, Color(GLOW_VIOLET, light))
		return Color("07070a")
	var v := _voronoi(t, 20.0, salt, true)
	if v.y - v.x < 0.9:
		# Seams: a few carry the light, more of it closer to the arena.
		var vein := _noise(t, 22.0, salt + 9)
		if vein > 0.62:
			glow.set_pixel(x, y, Color(GLOW_VIOLET, (vein - 0.62) * 1.4))
		return Color("060609")
	var plate := NelvarPixelArt.hash01(int(v.z), 1, salt)
	# The arena floor is polished smoother and darker.
	var level := 0.18 + plate * 0.45
	if r < 75.0 * NelvarVoidData.MONOLITH_SCALE:
		level = 0.12 + plate * 0.2
	level += (_noise(t, 2.5, salt + 4) - 0.5) * 0.12
	return NelvarPixelArt.ramp(MONOLITH, level, cell)


## Dark outline on the edge, a cold rim on edges that face north (light comes from above).
func _paint_edges(piece: NelvarVoidData.Debris, raster: Raster, image: Image) -> void:
	var rim: Color = RIMS[piece.kind]
	var outline := Color("140a24") if piece.kind == NelvarVoidData.Kind.SHARD else OUTLINE
	for y in raster.ground_height:
		for x in raster.width:
			var index := y * raster.width + x
			var distance := raster.distance[index]
			if distance == 1:
				image.set_pixel(x, y, outline)
			elif distance == 2 and y >= 2 and raster.mask[index - raster.width * 2] == 0:
				image.set_pixel(x, y, rim)


## A 3x5 rune scaled by `scale`, cut into the surface and lit.
func _paint_rune(raster: Raster, image: Image, glow: Image, center: Vector2i, salt: int,
		scale: int) -> void:
	var rune := RUNES[salt % RUNES.size()]
	for row in 5:
		for column in 3:
			if (rune[row] >> (2 - column)) & 1 == 0:
				continue
			for sy in scale:
				for sx in scale:
					var p := center + Vector2i((column - 1) * scale + sx, (row - 2) * scale + sy)
					if p.x < 0 or p.y < 0 or p.x >= raster.width or p.y >= raster.ground_height:
						continue
					if raster.mask[p.y * raster.width + p.x] == 0:
						continue
					image.set_pixelv(p, Color("0a0712"))
					glow.set_pixelv(p, Color(GLOW_VIOLET, 0.9))


# --- Underside ---------------------------------------------------------------

func _paint_underside(piece: NelvarVoidData.Debris, raster: Raster, image: Image, glow: Image,
		salt: int) -> void:
	var colors: Array = CLIFFS[piece.kind]
	var base_depth := 12
	var dangle := 10
	match piece.kind:
		NelvarVoidData.Kind.LOG:
			base_depth = 5
			dangle = 6
		NelvarVoidData.Kind.EARTH:
			base_depth = 14
			dangle = 22
		NelvarVoidData.Kind.ICE:
			base_depth = 10
			dangle = 16
		NelvarVoidData.Kind.SHARD:
			base_depth = 8
			dangle = 18
		NelvarVoidData.Kind.MONOLITH:
			base_depth = 44
			dangle = 40
	var left := raster.width
	var right := 0
	for x in raster.width:
		if raster.bottom[x] >= 0:
			left = mini(left, x)
			right = maxi(right, x)
	var span := maxf(1.0, float(right - left))
	for x in raster.width:
		var bottom := raster.bottom[x]
		if bottom < 0:
			continue
		var depth := base_depth + int(NelvarPixelArt.hash01(x / 3, 0, salt + 31) * 4.0) - 1
		# Narrower towards the sides: the underside tapers like a broken-off root.
		var side := absf((float(x - left) / span) * 2.0 - 1.0)
		depth = maxi(2, int(depth * (1.0 - side * side * 0.6)))
		var lit := float(x - left) / span * 0.4
		for drop in range(1, depth + 1):
			var y := bottom + drop
			if y >= raster.height:
				break
			var cell := Vector2i(x, y)
			var color: Color = colors[1]
			if drop <= 2:
				color = colors[0]
			elif float(drop) / depth > 0.6:
				color = colors[2]
			elif NelvarPixelArt.bayer(cell) < int(lit * 10.0):
				color = colors[0]
			if piece.kind == NelvarVoidData.Kind.MONOLITH and drop > 2:
				# Angular ribs running down.
				if NelvarPixelArt.hash01(x / 5, 1, salt) > 0.7 and x % 5 == 0:
					color = colors[3]
				if x % 9 == 0 and NelvarPixelArt.hash01(x, 2, salt) > 0.75:
					glow.set_pixel(x, y, Color(GLOW_VIOLET, 0.18 * (1.0 - float(drop) / depth)))
			# The Void eats the bottom: it dissolves into dithered violet dark.
			var eaten := float(drop) / depth
			if eaten > 0.7:
				var fade := (eaten - 0.7) / 0.3
				if fade * 16.0 > NelvarPixelArt.bayer(cell) + 0.5:
					continue
				color = color.lerp(VOID_TINT, fade * 0.6)
			image.set_pixel(x, y, color)
		# Things hanging below: roots, icicles, drips, spikes.
		var key := NelvarPixelArt.hash01(x, 7, salt + 41)
		if key > 0.18 or dangle <= 0:
			continue
		var length := int(dangle * (0.35 + key * 3.6))
		var hang := colors[3] as Color
		for drop in range(depth - 1, depth + length):
			var y := bottom + drop
			if y >= raster.height:
				break
			var fade := float(drop - depth) / maxf(1.0, length)
			if fade > 0.5 and fade * 16.0 > NelvarPixelArt.bayer(Vector2i(x, y)) + 4.0:
				break
			image.set_pixel(x, y, hang.lerp(VOID_TINT, maxf(0.0, fade) * 0.5))
			if piece.kind == NelvarVoidData.Kind.FIRE:
				glow.set_pixel(x, y, Color(1.0, 0.35, 0.1, 0.5 * (1.0 - maxf(0.0, fade))))
			elif piece.kind == NelvarVoidData.Kind.SHARD:
				glow.set_pixel(x, y, Color(GLOW_VIOLET, 0.3 * (1.0 - maxf(0.0, fade))))
