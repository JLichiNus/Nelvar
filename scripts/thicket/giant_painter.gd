class_name NelvarGiantPainter
extends RefCounted
## Paints the giants of the forest (Земля 2) in the style of the valley's art: lit from the
## upper right, Bayer-dithered palettes on the world's art pixel grid, dark outlines on the
## shaded edges. A trunk is a wall wider than the screen: its foot with the flare and the
## bark going up out of the top of the screen, melting into the dark of the crown. The
## roots, the fallen giant and its root plate lie along the ground and are cut into pieces
## that each sort by their own lowest point.
##
## A big thing is painted with more pixels, never stretched. Stateless: one painter paints
## from many worker threads at once.

const STEP := NelvarEarthData.PIXEL
const Wood = NelvarThicketData.Wood
const Part = NelvarThicketData.Part
## Alpha of the pixels that thin out while the player is behind (see giant_trunk.gdshader).
const FADES := 240
## The foot of a trunk this many art pixels high never thins out.
const FOOT_BAND := 40.0
## The sun from the upper right, high: (x right, y towards the bottom of the screen, up).
const SUN := Vector3(0.46, -0.42, 0.78)

const BARK := {
	Wood.OAK: [Color8(50, 40, 36), Color8(76, 60, 48), Color8(104, 82, 62), Color8(134, 108, 80), Color8(166, 140, 106)],
	Wood.PINE: [Color8(64, 32, 26), Color8(102, 54, 36), Color8(142, 80, 48), Color8(178, 112, 66), Color8(212, 152, 96)],
	Wood.BIRCH: [Color8(96, 94, 90), Color8(150, 148, 140), Color8(196, 194, 184), Color8(228, 226, 216), Color8(246, 244, 236)],
	Wood.DEAD: [Color8(58, 54, 52), Color8(88, 82, 76), Color8(120, 112, 102), Color8(156, 148, 134), Color8(188, 180, 164)],
}
## Size of a pine's bark plate, art pixels (around the trunk, along it).
const PINE_PLATE := Vector2(12.0, 40.0)
const OUTLINE := Color8(22, 18, 16)
const CROWN_DARK := Color8(20, 28, 20)
const MOSS: Array[Color] = [Color8(44, 68, 34), Color8(66, 96, 44), Color8(98, 130, 58), Color8(136, 162, 78)]
const FOOT_MOSS: Array[Color] = [Color8(36, 50, 30), Color8(50, 70, 38), Color8(70, 92, 48), Color8(94, 114, 60)]
const SOIL: Array[Color] = [Color8(46, 34, 26), Color8(70, 52, 38), Color8(98, 74, 52)]
const TINDER: Array[Color] = [Color8(84, 54, 32), Color8(128, 88, 50), Color8(180, 136, 82), Color8(222, 196, 146)]
const HOLLOW := Color8(14, 10, 10)
const RESIN: Array[Color] = [Color8(150, 82, 18), Color8(214, 142, 36), Color8(248, 206, 104)]
const BIRCH_MARK := Color8(36, 34, 38)
const CHAGA: Array[Color] = [Color8(24, 18, 16), Color8(46, 34, 28), Color8(70, 52, 40)]
const ROT: Array[Color] = [Color8(30, 20, 16), Color8(46, 32, 24), Color8(64, 46, 32), Color8(86, 62, 42)]
const SPLINTER: Array[Color] = [Color8(112, 88, 64), Color8(152, 126, 92), Color8(190, 164, 124)]
const FERN: Array[Color] = [Color8(30, 76, 46), Color8(46, 104, 54), Color8(76, 138, 66)]
const DARK_HOLE: Array[Color] = [Color8(8, 6, 6), Color8(18, 13, 11), Color8(30, 22, 18)]
const STONE: Array[Color] = [Color8(84, 84, 82), Color8(120, 118, 110), Color8(160, 156, 144)]


## A piece of something long, sorted by its own lowest point (`origin`, world units).
class Piece:
	var origin := Vector2.ZERO
	var art: NelvarEarthArt
	## Along its root or trunk, from the start (world units).
	var along := 0.0


## Pixels of one picture on the world's art pixel grid: `corner` is the world art pixel of
## its top-left; `owner` keeps which piece each pixel belongs to (-1: none).
class Sheet:
	var corner := Vector2i.ZERO
	var size := Vector2i.ONE
	var data := PackedByteArray()
	var owner := PackedInt32Array()
	var level := PackedFloat32Array()

	func _init(from: Vector2i, to: Vector2i) -> void:
		corner = from
		size = (to - from + Vector2i.ONE).max(Vector2i.ONE)
		data.resize(size.x * size.y * 4)
		owner.resize(size.x * size.y)
		owner.fill(-1)
		level.resize(size.x * size.y)

	func inside(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < size.x and y < size.y

	func put(x: int, y: int, color: Color, alpha: int = 255, piece: int = -1, lit: float = 0.5) -> void:
		if not inside(x, y):
			return
		var i := y * size.x + x
		data[i * 4] = color.r8
		data[i * 4 + 1] = color.g8
		data[i * 4 + 2] = color.b8
		data[i * 4 + 3] = alpha
		owner[i] = piece
		level[i] = lit

	func alpha(x: int, y: int) -> int:
		if not inside(x, y):
			return 0
		return data[(y * size.x + x) * 4 + 3]

	func is_body(x: int, y: int) -> bool:
		return alpha(x, y) > 200

	func image() -> Image:
		return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, data)

	## Dark outline on the shaded outer edge (the lit upper right stays open).
	func outline(color: Color, limit: float) -> void:
		var marks: Array[Vector2i] = []
		for y in size.y:
			for x in size.x:
				if not is_body(x, y) or level[y * size.x + x] >= limit:
					continue
				if not is_body(x - 1, y) or not is_body(x + 1, y) or not is_body(x, y - 1) or not is_body(x, y + 1):
					marks.append(Vector2i(x, y))
		for p in marks:
			var i := (p.y * size.x + p.x) * 4
			data[i] = color.r8
			data[i + 1] = color.g8
			data[i + 2] = color.b8

	## The pixels of each piece as their own picture.
	func cut(pieces: int, origins: Array[Vector2], alongs: PackedFloat32Array) -> Array[Piece]:
		var result: Array[Piece] = []
		var from: Array[Vector2i] = []
		var to: Array[Vector2i] = []
		for k in pieces:
			from.append(Vector2i(size.x, size.y))
			to.append(Vector2i(-1, -1))
		for y in size.y:
			for x in size.x:
				var k := owner[y * size.x + x]
				if k < 0 or k >= pieces or data[(y * size.x + x) * 4 + 3] == 0:
					continue
				from[k] = from[k].min(Vector2i(x, y))
				to[k] = to[k].max(Vector2i(x, y))
		for k in pieces:
			if to[k].x < 0 or not origins[k].is_finite():
				continue
			var w := to[k].x - from[k].x + 1
			var h := to[k].y - from[k].y + 1
			var bytes := PackedByteArray()
			bytes.resize(w * h * 4)
			for y in h:
				for x in w:
					var source := (from[k].y + y) * size.x + from[k].x + x
					if owner[source] != k:
						continue
					for c in 4:
						bytes[(y * w + x) * 4 + c] = data[source * 4 + c]
			var piece := Piece.new()
			piece.origin = origins[k]
			piece.along = alongs[k]
			piece.art = NelvarEarthArt.new()
			piece.art.image = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
			piece.art.local_rect = Rect2(Vector2(corner + from[k]) * STEP - piece.origin, Vector2(w, h) * STEP)
			result.append(piece)
		return result


static func ramp(colors: Array, level: float, x: int, y: int) -> Color:
	var t := clampf(level, 0.0, 0.9999) * (colors.size() - 1)
	var index := int(t)
	if (t - index) * 16.0 > NelvarPixelArt.bayer(Vector2i(x, y)) + 0.5:
		index += 1
	return colors[mini(index, colors.size() - 1)]


static func noise(x: float, y: float, salt: int) -> float:
	return NelvarPixelArt.value_noise(x, y, salt)


# --- Trunks -------------------------------------------------------------------------------

## A giant's trunk: the foot along the front of its base circle with a flare, the bark of
## its kind lit from the right with a bright rim, moss at the foot, shelf fungi, now and then
## a hollow; the top third melts into the dark of the crown. `eye` is the hollow's middle.
func paint_trunk(giant: NelvarThicketData.Giant) -> NelvarEarthArt:
	var rng := RandomNumberGenerator.new()
	rng.seed = giant.appearance_seed
	var r := giant.radius / STEP
	var h := giant.height / STEP
	var center := giant.center / STEP
	var flare := 0.16
	var reach := r * (1.0 + flare) + 14.0
	var sheet := Sheet.new(Vector2i((center + Vector2(-reach, -h - 2.0)).floor()),
		Vector2i((center + Vector2(reach, r + 3.0)).ceil()))
	var colors: Array = BARK[giant.species]
	var salt := rng.randi() & 0xffff
	var slant := rng.randf_range(-0.05, 0.05)
	# Buttresses: ridges of the foot running down into the roots (x, half width, reach, height).
	var buttresses: Array[Vector4] = []
	for i in rng.randi_range(5, 7):
		var at := lerpf(-0.92, 0.92, (i + rng.randf_range(0.2, 0.8)) / 6.5)
		buttresses.append(Vector4(at * r * (1.0 + flare), r * rng.randf_range(0.1, 0.18),
			r * rng.randf_range(0.08, 0.2), r * rng.randf_range(0.35, 0.7)))
	for y in sheet.size.y:
		for x in sheet.size.x:
			var world := Vector2(sheet.corner + Vector2i(x, y))
			var local := world + Vector2(0.5, 0.5) - center
			# Height above the ground in this column: the base is the front of the circle,
			# pushed out where a buttress runs down.
			var bottom := r * sqrt(maxf(0.0, 1.0 - pow(local.x / (r * (1.0 + flare)), 2.0)))
			var ridge := 0.0
			var ridge_side := 0.0
			for b in buttresses:
				var dx := (local.x - b.x) / b.y
				if absf(dx) < 1.0:
					var bump := (1.0 - dx * dx)
					if bump * b.z > ridge:
						ridge = bump * b.z
						ridge_side = dx * minf(1.0, b.w / maxf(1.0, bottom + b.z - local.y))
			bottom += ridge
			var above := bottom - local.y
			if above < 0.0 or local.y < -h:
				continue
			var half := r * (1.0 + flare * exp(-above / (r * 0.32)))
			var lean := slant * maxf(0.0, -local.y)
			var u := (local.x - lean) / half
			if absf(u) > 1.0:
				continue
			var top := clampf((-local.y - 0.62 * h) / (0.38 * h), 0.0, 1.0)
			var gx := sheet.corner.x + x
			var gy := sheet.corner.y + y
			if top * 16.0 > NelvarPixelArt.bayer(Vector2i(gx, gy)) + 0.5:
				continue
			var nz := sqrt(maxf(0.0, 1.0 - u * u))
			var lit := u * SUN.x + nz * 0.72
			var level := 0.3 + lit * 0.5
			if ridge > 0.0 and above < r * 0.7:
				# The flanks of a buttress: lit on the right, shaded on the left.
				level += ridge_side * 0.35 * (1.0 - above / (r * 0.7))
			# Around the trunk, along its bark: the pattern of each kind.
			var around := asin(clampf(u, -1.0, 1.0)) * r
			var color := _bark(giant.species, colors, around, local.y, above, level, gx, gy, salt)
			if u > 0.88 and giant.species != Wood.BIRCH:
				color = color.lerp(colors[colors.size() - 1], 0.45)
			# Moss and soil at the foot, in patches, more on the shaded side.
			var foot := 3.0 + noise(around * 0.15, 0.0, salt + 7) * 12.0 + (1.0 - u) * 4.0
			if above < foot * (0.5 if giant.species == Wood.BIRCH else 1.0):
				if above < 2.5:
					color = ramp(SOIL, level - 0.1, gx, gy)
				elif noise(gx * 0.3, gy * 0.3, salt + 13) > 0.42:
					color = ramp(FOOT_MOSS, level, gx, gy)
			if absf(u) > 0.97:
				color = OUTLINE if u < 0.0 else color.lerp(colors[colors.size() - 1], 0.6)
			if above < 1.0:
				color = color.darkened(0.45)
			color = color.lerp(CROWN_DARK, top * 0.9)
			sheet.put(x, y, color, FADES if above > FOOT_BAND else 255, -1, level)
	var art := NelvarEarthArt.new()
	_trunk_marks(sheet, giant, rng, r, h, center, salt)
	art.image = sheet.image()
	art.local_rect = Rect2(Vector2(sheet.corner) * STEP - giant.center, Vector2(sheet.size) * STEP)
	art.eye = _hollow(sheet, giant, rng, r, h, center)
	return art


## The pattern of the bark: furrows of an oak, plates of a pine, the white of a birch with
## black marks, the bare cracked wood of a dead trunk.
func _bark(species: int, colors: Array, around: float, y: float, above: float, level: float,
		gx: int, gy: int, salt: int) -> Color:
	match species:
		Wood.OAK:
			var furrow := noise(around * 0.32, y * 0.035, salt)
			var plates := noise(around * 0.32, y * 0.16, salt + 3)
			if furrow < 0.36:
				if furrow < 0.3 and above < 120.0 and noise(around * 0.5, y * 0.08, salt + 5) > 0.55:
					return ramp(MOSS, level - 0.05, gx, gy)
				return ramp(colors, level - 0.4, gx, gy)
			if plates < 0.2:
				return ramp(colors, level - 0.25, gx, gy)
			return ramp(colors, level + (furrow - 0.5) * 0.4, gx, gy)
		Wood.PINE:
			# Thick plates of an old pine: irregular, much longer than wide, split by furrows that
			# wander up the trunk (cells of a jittered grid measured stretched along the trunk).
			var warp := (noise(around * 0.04, y * 0.015, salt) - 0.5) * 10.0
			var q := Vector2(around + warp, y) / PINE_PLATE
			var base := Vector2i(q.floor())
			var f1 := INF
			var f2 := INF
			var near := Vector2.ZERO
			var second := Vector2.ZERO
			var plate := Vector2i.ZERO
			for j in range(-1, 2):
				for i in range(-1, 2):
					var c := base + Vector2i(i, j)
					var p := Vector2(c) + Vector2(0.15 + 0.7 * NelvarPixelArt.hash01(c.x, c.y, salt + 1),
						0.1 + 0.8 * NelvarPixelArt.hash01(c.x, c.y, salt + 2))
					var d := q.distance_to(p)
					if d < f1:
						f2 = f1
						second = near
						f1 = d
						near = p
						plate = c
					elif d < f2:
						f2 = d
						second = p
			# Distance to the furrow in art pixels (roughly). The furrows between plates side by
			# side run up the trunk wide and deep; the cracks between plates one above the
			# other are thin.
			var normal := (second - near).normalized() * PINE_PLATE
			var edge := (f2 - f1) * 0.5 * normal.length()
			var across := absf(normal.normalized().x)
			var furrow := (0.7 + noise(around * 0.2, y * 0.05, salt + 6) * 1.6) * lerpf(0.4, 1.0, across)
			if edge < furrow:
				return ramp(colors, level - (0.75 if edge < furrow * 0.5 and across > 0.5 else 0.55), gx, gy)
			var o := q - near
			var tone := NelvarPixelArt.hash01(plate.x, plate.y, salt + 3) - 0.5
			# A flat plate, its edge along a deep furrow lit on the right side, shaded on the left;
			# its lower lip in shadow.
			var shade := tone * 0.25 + o.x * 0.12
			if edge < furrow + 1.5:
				if across > 0.5:
					shade += 0.15 if second.x < near.x else -0.18
				elif second.y > near.y:
					shade -= 0.15
			# Fibres along the trunk, and the orange underneath where the top layer flaked off.
			var fibre := noise(around * 0.6, y * 0.07, salt + 4)
			var flake := noise(around * 0.15, y * 0.04, salt + 5)
			if flake > 0.72 and tone > -0.2:
				return ramp(colors, level + 0.25 + (fibre - 0.5) * 0.2, gx, gy)
			return ramp(colors, level + shade + (fibre - 0.5) * 0.25, gx, gy)
		Wood.BIRCH:
			if above < 90.0 * noise(around * 0.1, 0.0, salt + 2) + 20.0:
				# The rough black foot of an old birch.
				var crack := noise(around * 0.4, y * 0.05, salt)
				if crack < 0.45:
					return ramp(CHAGA, level, gx, gy)
			var mark := NelvarPixelArt.hash01(floori(around / 4.0), gy, salt + 9)
			if mark < 0.05 or (mark < 0.12 and noise(around * 0.3, y * 0.5, salt + 4) > 0.6):
				return BIRCH_MARK
			return ramp(colors, level + 0.1, gx, gy)
	# Dead: bare grey wood, long cracks, a scrap of bark here and there.
	var crack := absf(noise(around * 0.5, y * 0.012, salt) - 0.5)
	if crack < 0.03:
		return OUTLINE
	if noise(around * 0.08, y * 0.03, salt + 8) > 0.72:
		return ramp(BARK[Wood.OAK], level - 0.1, gx, gy)
	return ramp(colors, level, gx, gy)


## Shelf fungi on the bark; streaks of resin down a pine; lumps of chaga on a birch.
func _trunk_marks(sheet: Sheet, giant: NelvarThicketData.Giant, rng: RandomNumberGenerator, r: float, h: float,
		center: Vector2, salt: int) -> void:
	for i in rng.randi_range(2, 4):
		var u := rng.randf_range(-0.95, 0.95)
		var at := center + Vector2(u * r, -rng.randf_range(0.12, 0.55) * h)
		var axes := Vector2(rng.randf_range(6.0, 12.0), rng.randf_range(2.5, 4.5))
		if absf(u) > 0.8:
			at.x += signf(u) * axes.x * 0.5
		_shelf(sheet, at, axes, salt + i)
	if giant.species == Wood.PINE:
		for i in rng.randi_range(4, 7):
			var x := center.x + rng.randf_range(-0.8, 0.8) * r
			var from := center.y - rng.randf_range(0.1, 0.6) * h
			var length := rng.randf_range(10.0, 44.0)
			for k in int(length):
				var p := Vector2i(Vector2(x + sin(k * 0.3) * 0.6, from + k).floor()) - sheet.corner
				if sheet.is_body(p.x, p.y):
					var t := float(k) / length
					sheet.put(p.x, p.y, RESIN[2] if k == 0 else (RESIN[1] if t < 0.7 else RESIN[0]), FADES)
					if k % 3 == 0 and sheet.is_body(p.x + 1, p.y):
						sheet.put(p.x + 1, p.y, RESIN[0], FADES)
	elif giant.species == Wood.BIRCH:
		for i in rng.randi_range(1, 3):
			var at := center + Vector2(rng.randf_range(-0.8, 0.8) * r, -rng.randf_range(0.15, 0.5) * h)
			var size := rng.randf_range(3.0, 6.0)
			for y in range(-int(size) - 1, int(size) + 2):
				for x in range(-int(size) - 1, int(size) + 2):
					var d := Vector2(x, y).length() / (size * (0.8 + noise(x * 0.7, y * 0.7, salt) * 0.4))
					var p := Vector2i(at.floor()) + Vector2i(x, y) - sheet.corner
					if d < 1.0 and sheet.inside(p.x, p.y):
						sheet.put(p.x, p.y, ramp(CHAGA, 0.6 - y / size * 0.3 + x / size * 0.2, p.x, p.y), FADES)


func _shelf(sheet: Sheet, at: Vector2, axes: Vector2, salt: int) -> void:
	for y in range(-int(axes.y) - 1, int(axes.y) + 2):
		for x in range(-int(axes.x) - 1, int(axes.x) + 2):
			var q := Vector2(x, y) / axes
			# The top half of an ellipse with a flat underside.
			if q.length() > 1.0 or y > 1:
				continue
			var p := Vector2i(at.floor()) + Vector2i(x, y) - sheet.corner
			if not sheet.inside(p.x, p.y):
				continue
			var level := 0.75 - q.y * 0.3 + q.x * 0.15
			var color := ramp(TINDER, level, p.x, p.y)
			if y == 1 or (y == 0 and absf(q.x) > 0.85):
				color = TINDER[0]
			elif y < 0 and absf(fmod(q.length() * 3.0, 1.0) - 0.5) < 0.12:
				color = TINDER[1]
			sheet.put(p.x, p.y, color, FADES)


## Now and then a hollow: dark inside, a ring of swollen bark; its middle (art pixels from
## the trunk's origin), or INF without one.
func _hollow(sheet: Sheet, giant: NelvarThicketData.Giant, rng: RandomNumberGenerator, r: float, h: float,
		center: Vector2) -> Vector2:
	if rng.randf() > 0.45 or giant.species == Wood.BIRCH:
		return Vector2.INF
	var at := center + Vector2(rng.randf_range(-0.5, 0.5) * r, -rng.randf_range(0.2, 0.45) * h)
	var axes := Vector2(rng.randf_range(4.0, 7.0), rng.randf_range(6.0, 10.0))
	var colors: Array = BARK[giant.species]
	for y in range(-int(axes.y) - 2, int(axes.y) + 3):
		for x in range(-int(axes.x) - 2, int(axes.x) + 3):
			var d := (Vector2(x, y) / axes).length()
			var p := Vector2i(at.floor()) + Vector2i(x, y) - sheet.corner
			if not sheet.is_body(p.x, p.y):
				continue
			if d < 1.0:
				sheet.put(p.x, p.y, HOLLOW if y > -axes.y * 0.6 else ramp(DARK_HOLE, 0.5, p.x, p.y), FADES)
			elif d < 1.35:
				sheet.put(p.x, p.y, ramp(colors, 0.75 - y / axes.y * 0.2 + x / axes.x * 0.2, p.x, p.y), FADES)
	return at.floor() - center


# --- Roots ----------------------------------------------------------------------------------

## A root lying along the ground: a ridge of bark, lit from above and the right, moss on
## top, soil and rootlets at its flanks; an arch stands off the ground; under a trail only a
## hump of soil shows. Cut into pieces of NelvarThicketData.PIECE along it.
func paint_root(root: NelvarThicketData.Root, species: int) -> Array[Piece]:
	var rng := RandomNumberGenerator.new()
	rng.seed = root.appearance_seed
	var colors: Array = BARK[species] if species != Wood.DEAD else BARK[Wood.OAK]
	if species == Wood.BIRCH:
		colors = [Color8(70, 66, 62), Color8(112, 106, 98), Color8(158, 152, 140), Color8(196, 190, 178), Color8(222, 218, 206)]
	var salt := rng.randi() & 0xffff
	var points := PackedVector2Array()
	for p in root.points:
		points.append(p / STEP)
	var lo := Vector2.INF
	var hi := -Vector2.INF
	var tallest := 0.0
	for i in points.size():
		var half := root.widths[i] / STEP * 0.5 + 2.0
		lo = lo.min(points[i] - Vector2.ONE * half)
		hi = hi.max(points[i] + Vector2.ONE * half)
		tallest = maxf(tallest, root.heights[i])
	lo.y -= tallest + 2.0
	var sheet := Sheet.new(Vector2i(lo.floor()), Vector2i(hi.ceil()))
	# The ground under the root: for each pixel the nearest point on the line.
	var count := sheet.size.x * sheet.size.y
	var distance := PackedFloat32Array()
	distance.resize(count)
	distance.fill(INF)
	var along := PackedFloat32Array()
	along.resize(count)
	var side := PackedVector2Array()
	side.resize(count)
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var reach := maxf(root.widths[i], root.widths[i + 1]) / STEP * 0.5 + 1.0
		var from := Vector2i((a.min(b) - Vector2.ONE * reach).floor()) - sheet.corner
		var to := Vector2i((a.max(b) + Vector2.ONE * reach).ceil()) - sheet.corner
		var ab := b - a
		var length_squared := maxf(ab.length_squared(), 0.0001)
		var normal := ab.normalized().orthogonal()
		for y in range(maxi(0, from.y), mini(sheet.size.y, to.y + 1)):
			for x in range(maxi(0, from.x), mini(sheet.size.x, to.x + 1)):
				var p := Vector2(sheet.corner + Vector2i(x, y)) + Vector2(0.5, 0.5)
				var t := clampf((p - a).dot(ab) / length_squared, 0.0, 1.0)
				var d := p.distance_to(a + ab * t)
				var index := y * sheet.size.x + x
				if d < distance[index]:
					distance[index] = d
					along[index] = (i + t) * NelvarThicketData.ROOT_STEP
					side[index] = normal * signf((p - a).dot(normal))
	var pieces := int(root.length() / NelvarThicketData.PIECE) + 1
	var origins: Array[Vector2] = []
	origins.resize(pieces)
	origins.fill(Vector2.INF)
	var alongs := PackedFloat32Array()
	alongs.resize(pieces)
	# Columns of the ridge, from the back rows to the front ones: the front covers the back.
	for y in sheet.size.y:
		for x in sheet.size.x:
			var index := y * sheet.size.x + x
			if distance[index] == INF:
				continue
			var s := along[index]
			var k := clampi(int(s / NelvarThicketData.ROOT_STEP), 0, points.size() - 2)
			var t := s / NelvarThicketData.ROOT_STEP - k
			var half := lerpf(root.widths[k], root.widths[k + 1], t) / STEP * 0.5
			var across := distance[index] / half
			if across > 1.0:
				continue
			var part := root.parts[k] if t < 0.5 else root.parts[k + 1]
			var top := lerpf(root.heights[k], root.heights[k + 1], t)
			var lift := lerpf(root.lifts[k], root.lifts[k + 1], t)
			var profile := sqrt(1.0 - across * across)
			var low := 0.0
			var high := top * profile
			if lift > 0.0:
				var body := top - lift
				low = lift + body * 0.5 * (1.0 - profile)
				high = lift + body * (0.5 + 0.5 * profile)
			var piece := clampi(int(s / NelvarThicketData.PIECE), 0, pieces - 1)
			var ground := Vector2(sheet.corner + Vector2i(x, y)) + Vector2(1.0, 1.0)
			if not origins[piece].is_finite() or ground.y * STEP > origins[piece].y:
				origins[piece] = ground * STEP
				alongs[piece] = s
			var normal: Vector2 = side[index] * across
			var shade := normal.x * SUN.x + normal.y * SUN.y + profile * SUN.z
			var level := 0.25 + shade * 0.55
			var gx := sheet.corner.x + x
			var gy := sheet.corner.y + y
			var steps := maxi(1, int(round(high - low)) + 1)
			for z in steps:
				var height := high - z
				var py := y - int(round(height))
				var color: Color
				if part == Part.PASS:
					color = ramp(SOIL, level + 0.15, gx, gy) if noise(gx * 0.6, gy * 0.6, salt) < 0.6 \
						else ramp(colors, level, gx, gy)
				elif z == 0:
					color = _root_top(colors, s, across, level, gx, gy, salt, top)
				else:
					color = ramp(colors, level - 0.22 - z * 0.015, gx, gy - z)
					if height < 1.5 and lift <= 0.0:
						color = ramp(SOIL, 0.35 + noise(gx, gy, salt + 3) * 0.4, gx, gy)
				sheet.put(x, py, color, 255, piece, level - (0.0 if z == 0 else 0.3))
	sheet.outline(OUTLINE, 0.42)
	_rootlets(sheet, root, points, salt)
	return sheet.cut(pieces, origins, alongs)


func _root_top(colors: Array, along: float, across: float, level: float, gx: int, gy: int, salt: int,
		height: float) -> Color:
	var ridge := noise(along * 0.08, across * 2.0, salt)
	if level > 0.45 and across < 0.6 and height > 6.0 and noise(gx * 0.18, gy * 0.18, salt + 11) > 0.58:
		return ramp(MOSS, level - 0.1, gx, gy)
	if ridge < 0.3:
		return ramp(colors, level - 0.3, gx, gy)
	return ramp(colors, level + (ridge - 0.5) * 0.3, gx, gy)


## Fine rootlets running off the flanks into the soil, in the pieces they leave from.
func _rootlets(sheet: Sheet, root: NelvarThicketData.Root, points: PackedVector2Array, salt: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = salt
	for i in range(2, points.size() - 1, 3):
		if root.parts[i] == Part.PASS or root.parts[i] == Part.ARCH:
			continue
		var direction := points[i].direction_to(points[i + 1])
		var normal := direction.orthogonal() * (1.0 if rng.randf() < 0.5 else -1.0)
		var at := points[i] + normal * (root.widths[i] / STEP * 0.5)
		var length := rng.randi_range(2, 5)
		var piece := clampi(int(i * NelvarThicketData.ROOT_STEP / NelvarThicketData.PIECE), 0, 9999)
		for k in length:
			var p := Vector2i((at + normal * k + direction * sin(k * 1.3) * 0.7).floor()) - sheet.corner
			if sheet.inside(p.x, p.y) and not sheet.is_body(p.x, p.y):
				sheet.put(p.x, p.y, SOIL[0] if k > 1 else OUTLINE, 255, piece, 0.2)


# --- The fallen giant -------------------------------------------------------------------

## The fallen giant: a hollow trunk sunk a little into the ground, its bark half gone, moss,
## fungi and ferns on it; the broken end is open from above (its splintered rim, the rotten
## wood inside); breaches in the south side show the dark inside. Cut along its length.
func paint_fallen(fallen: NelvarThicketData.Fallen) -> Array[Piece]:
	var rng := RandomNumberGenerator.new()
	rng.seed = fallen.appearance_seed
	var salt := rng.randi() & 0xffff
	var axis := fallen.axis()
	var normal := fallen.normal()
	var start := fallen.start / STEP
	var length := fallen.length() / STEP
	# The trunk lies sunk into the ground: its footprint (the collision) is fallen.radius
	# across, the hollow's floor fallen.tunnel.
	var radius := fallen.radius / STEP / sqrt(1.0 - 0.35 * 0.35)
	var tunnel := fallen.tunnel / STEP / sqrt(1.0 - 0.4 * 0.4)
	var sink := radius * 0.35
	var hollow_center := tunnel * 0.4
	var top := sink + radius
	var ground_half := fallen.radius / STEP
	var open := rng.randf_range(34.0, 52.0)
	var lo := Vector2.INF
	var hi := -Vector2.INF
	for corner: Vector2 in [start + normal * ground_half, start - normal * ground_half,
			start + axis * length + normal * ground_half, start + axis * length - normal * ground_half]:
		lo = lo.min(corner)
		hi = hi.max(corner)
	lo -= Vector2(4.0, top + 6.0)
	hi += Vector2(4.0, 4.0)
	var sheet := Sheet.new(Vector2i(lo.floor()), Vector2i(hi.ceil()))
	var pieces := int(fallen.length() / NelvarThicketData.PIECE) + 1
	var origins: Array[Vector2] = []
	var alongs := PackedFloat32Array()
	for k in pieces:
		var s0 := k * NelvarThicketData.PIECE / STEP
		var s1 := minf((k + 1) * NelvarThicketData.PIECE / STEP, length)
		var a := start + axis * s0 + normal * ground_half
		var b := start + axis * s1 + normal * ground_half
		var low := a if a.y > b.y else b
		origins.append(Vector2((a.x + b.x) * 0.5, low.y + 1.0) * STEP)
		alongs.append(k * NelvarThicketData.PIECE)
	var c := normal.y
	for y in sheet.size.y:
		for x in sheet.size.x:
			var p := Vector2(sheet.corner + Vector2i(x, y)) + Vector2(0.5, 0.5)
			var q := (p - start).dot(normal)
			var outer := _span(q, c, sink, radius)
			if outer.y < 0.0:
				continue
			var z := outer.y
			var s := (p - start).dot(axis) + z * axis.y
			var cut := INF
			if s > length - open:
				var t := (s - (length - open)) / open
				cut = top * (1.0 - t * 0.55) - noise(s * 0.4, 0.0, salt) * top * 0.3 * t
			var surface := 0
			if z > cut:
				z = cut
				surface = 1
			if z < maxf(outer.x, 0.0):
				continue
			var hollow := _span(q, c, hollow_center, tunnel)
			if hollow.y >= 0.0 and z > hollow.x and z < hollow.y and surface == 1:
				# Looking into the hollow: its rotten bottom, or the floor of the tunnel.
				z = hollow.x
				surface = 2
				if z < 0.5:
					continue
			s = (p - start).dot(axis) + z * axis.y
			if s < 0.0 or s > length:
				continue
			var across := q + z * c
			var gx := sheet.corner.x + x
			var gy := sheet.corner.y + y
			var piece := clampi(int(s * STEP / NelvarThicketData.PIECE), 0, pieces - 1)
			var color: Color
			var level := 0.5
			match surface:
				0:
					var n := Vector3(normal.x * across / radius, normal.y * across / radius, (z - sink) / radius)
					var shade := n.x * SUN.x + n.y * SUN.y + n.z * SUN.z
					level = 0.28 + shade * 0.5
					color = _fallen_bark(s, across, z, level, gx, gy, salt, radius)
					if across > tunnel * 0.6 and z < top * 0.62 and fallen.in_breach(s * STEP):
						var breach := _breach_at(fallen, s * STEP)
						var arch := (1.0 - pow(absf(s * STEP - breach.x) / (breach.y * 0.5), 2.0)) * top * 0.62
						if z < arch - 1.0:
							color = ramp(DARK_HOLE, z / maxf(arch, 1.0), gx, gy)
							level = 0.1
						elif z < arch + 1.0:
							color = ramp(SPLINTER, 0.6, gx, gy)
				1:
					color = ramp(SPLINTER, 0.55 + noise(gx * 0.5, gy * 0.5, salt) * 0.4, gx, gy)
					level = 0.8
				2:
					color = ramp(ROT, 0.25 + z / maxf(1.0, tunnel) * 0.5 + noise(gx * 0.3, gy * 0.3, salt + 2) * 0.3, gx, gy)
					level = 0.3
					if NelvarPixelArt.hash01(floori(s / 5.0), floori(z / 3.0), salt + 4) < 0.05:
						color = SPLINTER[1]
					# Scratches on the walls, from the inside: three strokes at a time.
					var group := floori(s / 22.0)
					if NelvarPixelArt.hash01(group, 9, salt) < 0.3:
						var u := fposmod(s, 22.0)
						var stroke := fposmod(u - z * 0.6, 4.0)
						if u < 12.0 and stroke < 1.0 and z > tunnel * 0.3 and z < tunnel * 1.2:
							color = SPLINTER[2]
			sheet.put(x, y, color, 255 if z < 3.0 else FADES, piece, level)
	sheet.outline(OUTLINE, 0.36)
	_fallen_growth(sheet, fallen, rng, start, axis, normal, length, top, sink, radius, ground_half)
	return sheet.cut(pieces, origins, alongs)


## The range of heights a ray up from the ground point (q across, sloped by c) spends inside
## a circle of `radius` round `center` height above the axis: (from, to), to < 0 if none.
func _span(q: float, c: float, center: float, radius: float) -> Vector2:
	var a := c * c + 1.0
	var b := 2.0 * (q * c - center)
	var k := q * q + center * center - radius * radius
	var disc := b * b - 4.0 * a * k
	if disc < 0.0:
		return Vector2(0.0, -1.0)
	var root := sqrt(disc)
	return Vector2((-b - root) / (2.0 * a), (-b + root) / (2.0 * a))


func _breach_at(fallen: NelvarThicketData.Fallen, along: float) -> Vector2:
	for breach in fallen.breaches:
		if absf(along - breach.x) < breach.y * 0.5:
			return breach
	return Vector2(along, 1.0)


func _fallen_bark(s: float, across: float, z: float, level: float, gx: int, gy: int, salt: int, radius: float) -> Color:
	var bare := noise(s * 0.05, across * 0.08, salt + 1)
	var crack := noise(s * 0.012, across * 0.4, salt + 2)
	if level > 0.5 and z > radius * 0.9 and noise(gx * 0.12, gy * 0.12, salt + 3) > 0.45:
		return ramp(MOSS, level - 0.15, gx, gy)
	if bare > 0.7:
		# Bark gone: grey wood with long cracks along the trunk.
		if absf(crack - 0.5) < 0.04:
			return OUTLINE
		return ramp(BARK[Wood.DEAD], level, gx, gy)
	var furrow := noise(s * 0.03, across * 0.35, salt + 4)
	if furrow < 0.34:
		return ramp(BARK[Wood.OAK], level - 0.35, gx, gy)
	return ramp(BARK[Wood.OAK], level + (furrow - 0.5) * 0.3, gx, gy)


## Shelf fungi on the south side, ferns and grass on the top.
func _fallen_growth(sheet: Sheet, fallen: NelvarThicketData.Fallen, rng: RandomNumberGenerator, start: Vector2,
		axis: Vector2, normal: Vector2, length: float, top: float, sink: float, radius: float, ground_half: float) -> void:
	var salt := rng.randi() & 0xffff
	for i in rng.randi_range(4, 7):
		var s := rng.randf_range(20.0, length - 40.0)
		var z := rng.randf_range(0.2, 0.6) * top
		var across := sqrt(maxf(0.0, radius * radius - pow(z - sink, 2.0)))
		var at := start + axis * s + normal * across - Vector2(0.0, z)
		_shelf(sheet, at, Vector2(rng.randf_range(5.0, 10.0), rng.randf_range(2.0, 4.0)), salt + i)
	for i in rng.randi_range(6, 10):
		var s := rng.randf_range(16.0, length - 50.0)
		var base := start + axis * s - Vector2(0.0, top - 1.0)
		var fronds := rng.randi_range(3, 6)
		for f in fronds:
			var angle := lerpf(-PI + 0.5, -0.5, (f + 0.5) / fronds)
			var reach := rng.randf_range(5.0, 11.0)
			for k in int(reach * 1.3):
				var t := k / (reach * 1.3)
				var point := base + Vector2.from_angle(angle) * t * reach + Vector2(0.0, t * t * reach * 0.5)
				var p := Vector2i(point.floor()) - sheet.corner
				if sheet.inside(p.x, p.y):
					var piece := clampi(int(s * STEP / NelvarThicketData.PIECE), 0, 9999)
					sheet.put(p.x, p.y, FERN[clampi(int(t * 3.0), 0, 2)], FADES, piece, 0.6)


## The root plate torn out with the fallen giant: a wall of tangled roots and earth standing
## on edge, stones caught in it, rootlets hanging off.
func paint_plate(fallen: NelvarThicketData.Fallen) -> Piece:
	var rng := RandomNumberGenerator.new()
	rng.seed = fallen.appearance_seed + 17
	var salt := rng.randi() & 0xffff
	var axis := fallen.axis()
	var normal := fallen.normal()
	var center := fallen.plate_center / STEP
	var depth := fallen.plate_depth / STEP
	var half := fallen.plate_half / STEP
	var tall := half * 0.95
	var reach := half + depth + 4.0
	var sheet := Sheet.new(Vector2i((center - Vector2(reach, reach + tall + 4.0)).floor()),
		Vector2i((center + Vector2(reach, reach + 2.0)).ceil()))
	var bottom := -INF
	var origin := center
	for y in sheet.size.y:
		for x in sheet.size.x:
			var ground := Vector2(sheet.corner + Vector2i(x, y)) + Vector2(0.5, 0.5)
			var local := Vector2((ground - center).dot(axis) / depth, (ground - center).dot(normal) / half)
			var d := local.length()
			if d > 1.0:
				continue
			if ground.y > bottom:
				bottom = ground.y
				origin = ground + Vector2(0.0, 0.5)
			var height := tall * sqrt(maxf(0.0, 1.0 - local.y * local.y)) * (0.75 + 0.25 * sqrt(maxf(0.0, 1.0 - local.x * local.x)))
			var gx := sheet.corner.x + x
			var gy := sheet.corner.y + y
			for z in int(height) + 1:
				var h := height - z
				var py := y - int(round(h))
				# Strands of root fanning out from the stump's middle, earth between them.
				var spoke := atan2(h - tall * 0.45, local.y * half)
				var strand := sin(spoke * 11.0 + noise(local.y * 4.0, h * 0.08, salt) * 5.0)
				var level := 0.35 + local.y * 0.15 * normal.x + (h / tall) * 0.3 + (0.15 if z == 0 else -0.1)
				var color: Color
				if strand > 0.55:
					color = ramp(BARK[Wood.OAK], level + 0.1, gx, gy - z)
				elif NelvarPixelArt.hash01(floori(local.y * half / 3.0), floori(h / 3.0), salt) < 0.04:
					color = ramp(STONE, level, gx, gy - z)
				else:
					color = ramp(SOIL, level + noise(gx * 0.3, (gy - z) * 0.3, salt + 1) * 0.3, gx, gy - z)
				sheet.put(x, py, color, 255, 0, level)
	sheet.outline(OUTLINE, 0.4)
	# Rootlets hanging off the lower edge.
	for i in rng.randi_range(10, 18):
		var v := rng.randf_range(-0.9, 0.9)
		var at := center + normal * v * half - Vector2(0.0, tall * sqrt(1.0 - v * v) * rng.randf_range(0.1, 0.9))
		for k in rng.randi_range(3, 8):
			var p := Vector2i((at + Vector2(sin(k * 0.9 + i) * 0.6, k)).floor()) - sheet.corner
			if sheet.inside(p.x, p.y):
				sheet.put(p.x, p.y, SOIL[0] if k % 2 == 0 else OUTLINE, 255, 0, 0.2)
	var origins: Array[Vector2] = [origin * STEP]
	var pieces := sheet.cut(1, origins, PackedFloat32Array([0.0]))
	return pieces[0] if not pieces.is_empty() else null
