class_name NelvarMountainPainter
extends RefCounted
## Peaks round the earth valley, in the palette of the snowy range of the "Земля" menu,
## but seen like everything else on the map: from above, at an angle.
##
## A peak is a height field over a round base (a wobbly ellipse, flattened by the view)
## drawn in the map's oblique projection: every ground pixel of the base becomes a
## column as tall as the ground there, front to back, so nearer slopes hide the ones
## behind them. Seen this way the tops, ridges, saddles and snowfields face the camera,
## the base is a curve that sinks into the ground instead of a straight cut, and the
## light comes from the slopes themselves: the sun of the menu art (upper right) lights
## the tops and the eastern slopes, the western ones fall into shade. A light rim marks
## the lit crests where a nearer ridge stands against the slope behind it.
##
## Snow lies on the high, gentle ground and slides off the cliffs; grass and firs climb
## the low slopes and the gullies running down from the summit. The rock carries a
## small grain at the same pixel scale on every peak, so a giant is no smoother than a
## crag. Every peak has a look (NelvarEarthData.Peak): a summit with shoulders, a broad
## massif of several tops, a cluster of rocky needles, a flat-topped mesa in layered
## rock, a giant with glaciers in its gullies, or a low crag on the uplands; the rock
## takes one of a few tints. Some carry a waterfall (Thing.accent): its water and foam
## are keyed by alpha and animated by waterfall.gdshader.
##
## The art keeps the highest ground of each column (NelvarEarthArt.relief):
## NelvarMountainField casts the peak's shadow on the ground from it.

const STEP := NelvarEarthData.PIXEL
const Peak = NelvarEarthData.Peak
## Depth of a peak's round base on screen, as a share of its half-width (the view
## flattens it).
const DEPTH := 0.42
## How much of the layout's peak height the art shows: a bit lower and broader than a
## standing cut-out, the rest of the height is the base seen from above.
const LOWER := 0.82
## The sun of the menu art (NelvarPixelArt.LIGHT, upper right on screen) turned into
## the ground's frame — x east, y south, z up — for a camera looking down at about 45°:
## high, a little east. Tops are brightest, eastern slopes lit, western ones in shade.
const SUN := Vector3(0.42, 0.08, 0.9)

enum Ground { NONE, ROCK, SNOW, FOOT }
## Steps of the noise tables round a base or a flat top.
const RING := 64

## Rock tints of the nearest row, dark to light: cool grey-blue, warm grey-brown, slate.
const ROCK_TINTS: Array = [
	[Color8(66, 76, 94), Color8(88, 100, 116), Color8(114, 124, 138), Color8(144, 152, 160),
		Color8(176, 182, 186)],
	[Color8(74, 68, 72), Color8(98, 90, 90), Color8(126, 116, 108), Color8(156, 146, 132),
		Color8(186, 176, 158)],
	[Color8(52, 60, 80), Color8(70, 80, 102), Color8(92, 102, 124), Color8(120, 128, 146),
		Color8(152, 158, 172)],
]
## Rock of the menu's hazy far range: the rows behind the nearest one lean towards it a
## little (seen from above they are not much further away).
const ROCK_FAR: Array[Color] = [Color8(76, 104, 138), Color8(98, 128, 158), Color8(124, 154, 178),
	Color8(150, 178, 196), Color8(176, 198, 212)]
const SNOW: Array[Color] = [Color8(176, 196, 214), Color8(214, 226, 236), Color8(244, 248, 250)]
const OUTLINE := Color8(44, 52, 70)
const HAZE := Color8(178, 210, 222)
## The menu's green foothills and treeline.
const FOOT: Array[Color] = [Color8(40, 86, 68), Color8(56, 104, 82), Color8(70, 124, 88),
	Color8(88, 144, 94)]
## The uplands' grass: the valley's, faded towards the haze (earth_ground.gdshader,
## UPLAND_HAZE and UPLAND_FADE). The feet of everything beyond the nearest row.
const MEADOW: Array[Color] = [Color8(86, 123, 89), Color8(95, 135, 92), Color8(106, 148, 95),
	Color8(119, 158, 100)]
## Firs on the uplands, faded like the meadow.
const MEADOW_FIRS: Array[Color] = [Color8(74, 102, 87), Color8(80, 112, 90)]
## Waterfall pixels: the alpha keys waterfall.gdshader animates, and the colours they
## show without it.
const WATER_KEY := 250
const FOAM_KEY := 251
const MIST_KEY := 252
const WATER := Color8(104, 168, 196, WATER_KEY)
const FOAM := Color8(236, 246, 248, FOAM_KEY)
const MIST := Color8(220, 236, 242, MIST_KEY)


## A top of the peak: a cone (or a flat-topped mesa) over an ellipse of the ground.
## Ground art pixels around the origin: x right, y down (south), heights up.
class Summit:
	var x: float
	var y: float
	var top: float
	var rx: float
	var ry: float
	## Steepness of the flanks: above 1 they flare out towards the foot.
	var sharp := 1.45
	## Share of the radius that is a flat top (mesas, crags).
	var flat := 0.0
	## Walls under a flat top instead of flaring flanks.
	var cliff := false
	## How far the rim of a flat top wanders, round the summit (_ring).
	var rim := PackedFloat32Array()


## How a look shapes the peak: snow depth (share of the height), how far glaciers run
## down the gullies (share of the height), layered rock on the walls.
class Style:
	var snow := Vector2(0.26, 0.4)
	var glacier := 0.0
	var strata := false


## Everything a pixel's colour depends on, per peak.
class Look:
	var rock: Array[Color] = []
	var snow: Array[Color] = []
	var foot: Array[Color] = []
	var outline: Color
	var edge: Color
	var style: Style
	var summits: Array[Summit] = []
	var half := 0.0
	var depth := 0.0
	var tall := 0.0
	var salt := 0
	var snow_depth := 0.0
	var gullies := 3.0
	## Typical slope of this peak: snow and grass judge steepness against it.
	var steep := 1.0
	## How far the edge of the base wanders, round the base (_ring).
	var base_ring := PackedFloat32Array()


func paint(thing: NelvarEarthData.Thing) -> NelvarEarthArt:
	var rng := RandomNumberGenerator.new()
	rng.seed = thing.appearance_seed
	var shape: int = thing.variant
	var look := Look.new()
	look.half = thing.size.x / STEP * 0.5
	look.depth = look.half * DEPTH
	look.tall = maxf(6.0, thing.size.y / STEP * LOWER - look.depth)
	var plateau := shape == Peak.CRAG
	# Everything but the nearest row stands on the uplands: its foot is their meadow.
	var on_plateau := plateau or thing.row > 0
	var haze := clampf(thing.row * 0.05, 0.0, 0.15) if not plateau else 0.04
	var tint: Array = ROCK_TINTS[rng.randi_range(0, ROCK_TINTS.size() - 1)]
	for i in ROCK_FAR.size():
		var near: Color = tint[i]
		look.rock.append(near.lerp(ROCK_FAR[i], minf(0.4, thing.row * 0.12) if not plateau else 0.05)
			.lerp(HAZE, haze * 0.5))
	for color in SNOW:
		look.snow.append(color.lerp(HAZE, haze * 0.3))
	look.foot = MEADOW if on_plateau else FOOT
	look.outline = OUTLINE.lerp(look.rock[1], haze)
	look.edge = look.rock[0].lerp(OUTLINE, 0.35)
	look.style = _style(shape, rng)
	look.summits = _summits(shape, rng, look.half, look.depth, look.tall)
	look.salt = rng.randi() & 0xffff
	look.snow_depth = rng.randf_range(look.style.snow.x, look.style.snow.y)
	# About the same number of gullies on every peak: a giant gets broader ones.
	look.gullies = clampf(look.half / 18.0, 2.0, 4.5)
	look.steep = maxf(0.6, look.tall / look.half * 1.2)
	look.base_ring = _ring(look.salt + 1, 7.0, 2.2)
	for summit in look.summits:
		if summit.flat > 0.0:
			summit.rim = _ring(look.salt + 12, summit.x, 1.8)
	var main := look.summits[0]
	var reach := look.tall * 1.15 + 4.0
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-look.half - 2.0,
		-2.0 * look.depth - reach - 2.0, look.half * 2.0 + 4.0, 2.0 * look.depth + reach + 4.0))
	var w := canvas.size.x
	var h := canvas.size.y
	# The ground rows of the base, back (north) to front (the origin's row).
	var back := maxi(0, int(floor(-2.0 * look.depth * 1.12 - 1.0 - canvas.offset.y)))
	var front := mini(h - 1, int(floor(-0.5 - canvas.offset.y)))
	var rows := front - back + 1
	var heights := PackedFloat32Array()
	heights.resize(w * rows)
	var gullies := PackedFloat32Array()
	gullies.resize(w * rows)
	var relief := PackedFloat32Array()
	relief.resize(w)
	# The relief is smooth: worked out on every other pixel, filled in between.
	var cw := (w >> 1) + 2
	var ch := (rows >> 1) + 2
	var coarse := PackedVector2Array()
	coarse.resize(cw * ch)
	for k in ch:
		var gy := canvas.offset.y + back + k * 2 + 0.5
		for i in cw:
			coarse[k * cw + i] = _relief(Vector2(canvas.offset.x + i * 2 + 0.5, gy), look)
	for j in rows:
		var k := j >> 1
		var fy := (j % 2) * 0.5
		for x in w:
			var i := x >> 1
			var fx := (x % 2) * 0.5
			var ground := coarse[k * cw + i].lerp(coarse[k * cw + i + 1], fx).lerp(
				coarse[(k + 1) * cw + i].lerp(coarse[(k + 1) * cw + i + 1], fx), fy)
			heights[j * w + x] = ground.x
			gullies[j * w + x] = ground.y
			relief[x] = maxf(relief[x], ground.x)
	# Front to back, column by column: each ground pixel rises as a column of its own
	# height and only shows where nothing nearer stands in front of it.
	var sun := SUN.normalized()
	var data := PackedByteArray()
	data.resize(w * h * 4)
	var grounds := PackedByteArray()
	grounds.resize(w * h)
	var crests := PackedByteArray()
	crests.resize(w * h)
	var tops := PackedInt32Array()
	tops.resize(w)
	var bottoms := PackedInt32Array()
	bottoms.resize(w)
	for x in w:
		var highest := h
		var hidden := 0
		bottoms[x] = -1
		var gx := canvas.offset.x + x + 0.5
		for j in range(rows - 1, -1, -1):
			var height := heights[j * w + x]
			if height < 0.4:
				continue
			var row := back + j
			var cell := canvas.grid + Vector2i(x, row)
			# The thin edge of the base dissolves into the ground.
			if height < 1.4 and float(NelvarPixelArt.bayer(cell)) / 16.0 >= height - 0.4:
				continue
			var top := maxi(0, row - int(ceil(height - 0.5)))
			if top >= highest:
				hidden += 1
				continue
			if hidden >= 3 and highest < h:
				# A nearer ridge stands against the slope behind it.
				crests[highest * w + x] = 1
			hidden = 0
			# Slopes over two pixels each way: the light follows the landforms, not
			# the grain of single pixels.
			var left := heights[j * w + maxi(x - 2, 0)]
			var right := heights[j * w + mini(x + 2, w - 1)]
			var north := heights[maxi(j - 2, 0) * w + x]
			var south := heights[mini(j + 2, rows - 1) * w + x]
			# The view squeezes the ground north to south (DEPTH): undo it for the slope.
			var slope := Vector2((right - left) * 0.25, (south - north) * 0.25 * DEPTH)
			var lit := Vector3(-slope.x, -slope.y, 1.0).normalized().dot(sun)
			var gy := canvas.offset.y + row + 0.5
			var steep := slope.length() / look.steep
			var ground := _ground(look, height, steep, gullies[j * w + x], gx, gy)
			var level := 0.1 + lit * 0.85 - gullies[j * w + x] * 0.12
			if look.style.strata and ground == Ground.ROCK and steep > 0.6:
				# Layered rock on the walls: lighter and darker bands.
				var band := maxf(3.0, look.tall * 0.1)
				var wobble := (NelvarPixelArt.value_noise(gx * 0.08, 2.5, look.salt + 8) - 0.5) * band * 0.8
				level += 0.08 if int(floor((height + wobble) / band)) % 2 == 0 else -0.06
			var bottom := mini(highest - 1, row)
			for y in range(top, bottom + 1):
				var spot := canvas.grid + Vector2i(x, y)
				var shade := level + (NelvarPixelArt.hash01(spot.x, spot.y, look.salt) - 0.5) * 0.08
				var color := _color(look, ground, shade, spot)
				var index := y * w + x
				data.encode_u32(index * 4, color.to_abgr32())
				grounds[index] = ground
				canvas.body[index] = 1
				canvas.levels[index] = shade
			if bottoms[x] < 0:
				bottoms[x] = bottom
			highest = top
		tops[x] = highest
	_edges(look, data, grounds, crests, canvas.levels, w, h)
	canvas.image = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	_firs(canvas, rng, look, heights, grounds, back, rows,
		MEADOW_FIRS if on_plateau else FOOT.slice(0, 2), 0.3 if on_plateau else 0.5)
	var art := NelvarEarthArt.from_canvas(canvas)
	art.relief = relief
	if thing.accent and shape in [Peak.SUMMIT, Peak.MASSIF, Peak.MESA, Peak.GIANT]:
		art.waterfall = _waterfall(canvas, rng, look, main, tops, bottoms, grounds)
	return art


## Height of the ground (x) and how deep in a gully it lies (y, 0..1) at a ground point.
func _relief(p: Vector2, look: Look) -> Vector2:
	# The round base, its edge wandering.
	var from_center := Vector2(p.x / look.half, (p.y + look.depth) / look.depth)
	var e := from_center.length()
	if e > 1.2:
		return Vector2.ZERO
	var edge := 1.0 + (_on_ring(look.base_ring, from_center) - 0.5) * 0.3
	if e >= edge:
		return Vector2.ZERO
	var height := 0.0
	for s in look.summits:
		var q := Vector2((p.x - s.x) / s.rx, (p.y - s.y) / s.ry)
		var d := q.length()
		if s.flat > 0.0:
			# A flat top with a wandering rim, not a drum.
			d *= 1.0 + (_on_ring(s.rim, q) - 0.5) * 0.5
			d = maxf(0.0, d - s.flat) / (1.0 - s.flat)
		if d >= 1.0:
			continue
		var t := 1.0 - d
		var v := s.top * (1.0 - pow(1.0 - t, 3.0) if s.cliff else pow(t, s.sharp))
		height = maxf(height, v)
	var main := look.summits[0]
	var gully := 0.0
	if height > 0.5:
		# Gullies running down from the main summit, curving a little; none at the top.
		var away := p - Vector2(main.x, main.y)
		var distance := away.length()
		var spoke := away / maxf(distance, 0.001)
		var g := NelvarPixelArt.value_noise(spoke.x * look.gullies + distance * 0.035,
			spoke.y * look.gullies + 11.0, look.salt + 2)
		gully = 1.0 - absf(g * 2.0 - 1.0)
		gully *= gully
		height *= 1.0 - gully * 0.3 * smoothstep(0.02, 0.35, 1.0 - height / main.top)
		# Rocky grain at the same pixel scale on every peak.
		height += (NelvarPixelArt.value_noise(p.x * 0.09, p.y * 0.12, look.salt + 3) - 0.5) \
			* minf(10.0, look.tall * 0.12) * smoothstep(0.0, 4.0, height)
	# Low foothills round the foot (only where the peak itself is low).
	var hills := (4.0 + look.tall * 0.12) * (1.0 - e / edge) * 1.2
	if height < hills:
		var hill := NelvarPixelArt.value_noise(p.x * 0.07 + 31.0, p.y * 0.1, look.salt + 5)
		height = maxf(height, maxf(0.0, hill - 0.4) / 0.6 * hills)
	# The base sinks into the ground towards its edge.
	height *= 1.0 - smoothstep(edge * 0.72, edge, e)
	return Vector2(maxf(0.0, height), gully)


## Noise round a circle, sampled into a table (cheaper than noise per pixel).
static func _ring(salt: int, phase: float, scale: float) -> PackedFloat32Array:
	var table := PackedFloat32Array()
	table.resize(RING + 1)
	for i in RING + 1:
		var angle := TAU * float(i) / RING
		table[i] = NelvarPixelArt.value_noise(cos(angle) * scale + phase, sin(angle) * scale, salt)
	return table


## The ring's value in a direction.
static func _on_ring(table: PackedFloat32Array, direction: Vector2) -> float:
	var f := fposmod(atan2(direction.y, direction.x) / TAU, 1.0) * RING
	var i := mini(int(f), RING - 1)
	return lerpf(table[i], table[i + 1], f - i)


## What covers the ground (`slope` against the peak's typical one): snow on the high,
## gentle ground (further down the gullies on glaciated peaks), grass on the low slopes,
## up the gullies and on gentle ground below the snow, rock elsewhere.
func _ground(look: Look, height: float, slope: float, gully: float, gx: float, gy: float) -> int:
	var rel := height / look.summits[0].top
	var noise := NelvarPixelArt.value_noise(gx * 0.08, gy * 0.11, look.salt + 6)
	if look.snow_depth > 0.0:
		var line := 1.0 - look.snow_depth + (noise - 0.5) * 0.16 \
			- maxf(0.0, gully - 0.4) / 0.6 * look.style.glacier
		if rel > line and slope < 1.25 + (rel - line) * 5.0:
			return Ground.SNOW
	var foot := (2.0 + look.tall * 0.1) * (0.6 + 0.8 * noise) + gully * look.tall * 0.14
	if height < foot and slope < 1.4:
		return Ground.FOOT
	# Alpine meadows on the gentle ground up high: shoulders, saddles, flat tops.
	if slope < 0.22 + (noise - 0.5) * 0.2 and rel < 0.97:
		return Ground.FOOT
	return Ground.ROCK


func _color(look: Look, ground: int, level: float, cell: Vector2i) -> Color:
	match ground:
		Ground.SNOW:
			return NelvarPixelArt.ramp(look.snow, level + 0.15, cell)
		Ground.FOOT:
			if NelvarPixelArt.hash01(cell.x, cell.y, look.salt + 11) < 0.05:
				return look.rock[1] if level > 0.45 else look.rock[0]
			return NelvarPixelArt.ramp(look.foot, level * 0.85 + 0.05, cell)
	return NelvarPixelArt.ramp(look.rock, level, cell)


## Edges: a dark line on the shaded skyline and sides, a lit rim on the sunny skyline
## and on the lit crests in front of the slopes behind them. The base and the grassy
## foot get no line: they sink into the ground.
func _edges(look: Look, data: PackedByteArray, grounds: PackedByteArray, crests: PackedByteArray,
		levels: PackedFloat32Array, w: int, h: int) -> void:
	var marks := {}
	for y in h:
		for x in w:
			var index := y * w + x
			var ground := grounds[index]
			if ground == Ground.NONE or ground == Ground.FOOT:
				continue
			var level := levels[index]
			var open_up := y == 0 or grounds[index - w] == Ground.NONE
			var open_side := x == 0 or x == w - 1 or grounds[index - 1] == Ground.NONE \
				or grounds[index + 1] == Ground.NONE
			var color := Color(0, 0, 0, 0)
			if open_up or open_side:
				if level < 0.45:
					color = look.outline if open_up else look.edge
				elif open_up:
					color = look.snow[2] if ground == Ground.SNOW else look.rock[4]
			elif crests[index] == 1:
				if level >= 0.45:
					color = look.snow[2] if ground == Ground.SNOW else look.rock[4]
				else:
					color = look.snow[0] if ground == Ground.SNOW else look.rock[0]
			if color.a > 0.0:
				marks[index] = color
	for index: int in marks:
		data.encode_u32(index * 4, (marks[index] as Color).to_abgr32())


func _style(shape: int, rng: RandomNumberGenerator) -> Style:
	var style := Style.new()
	match shape:
		Peak.SUMMIT:
			style.glacier = 0.12 if rng.randf() < 0.4 else 0.0
		Peak.MASSIF:
			style.snow = Vector2(0.3, 0.45)
			style.glacier = 0.1
		Peak.NEEDLES:
			style.snow = Vector2(0.06, 0.12)
		Peak.MESA:
			style.snow = Vector2(0.02, 0.04) if rng.randf() < 0.5 else Vector2.ZERO
			style.strata = true
		Peak.GIANT:
			style.snow = Vector2(0.4, 0.5)
			style.glacier = 0.32
		Peak.CRAG:
			style.snow = Vector2(0.08, 0.14) if rng.randf() < 0.25 else Vector2.ZERO
			style.strata = rng.randf() < 0.5
	return style


## The summits of a look; the first is the highest. `depth`: half-depth of the base,
## `tall`: height of the main summit (art pixels).
func _summits(shape: int, rng: RandomNumberGenerator, half: float, depth: float,
		tall: float) -> Array[Summit]:
	var summits: Array[Summit] = []
	var main := _summit(rng.randf_range(-0.28, 0.28) * half, -depth * rng.randf_range(0.85, 1.15),
		tall, half, depth)
	summits.append(main)
	match shape:
		Peak.SUMMIT, Peak.GIANT:
			var shoulders := rng.randi_range(0, 2) if shape == Peak.SUMMIT else 2
			for i in shoulders:
				var side := -1.0 if rng.randf() < 0.5 else 1.0
				if shape == Peak.GIANT:
					side = -1.0 if i == 0 else 1.0
				summits.append(_shoulder(main, rng, side * rng.randf_range(0.44, 0.72) * half,
					tall * rng.randf_range(0.5, 0.78), half, depth))
		Peak.MASSIF:
			# Several tops of nearly the same height along a broad ridge.
			main.sharp = 1.2
			var count := rng.randi_range(2, 3)
			for i in count:
				var at := lerpf(-0.72, 0.72, (i + rng.randf_range(0.1, 0.9)) / count) * half
				if absf(at - main.x) < half * 0.24:
					at += signf(at - main.x + 0.01) * half * 0.28
				var top := _shoulder(main, rng, at - main.x, tall * rng.randf_range(0.72, 0.94), half, depth)
				top.sharp = 1.3
				summits.append(top)
		Peak.NEEDLES:
			# Narrow spires on a low rocky base.
			main.rx = half * 0.3
			main.ry = depth * 0.4
			main.sharp = 0.9
			for i in rng.randi_range(2, 3):
				var spire := _summit(rng.randf_range(-0.72, 0.72) * half, -depth * rng.randf_range(0.6, 1.4),
					tall * rng.randf_range(0.45, 0.85), half, depth)
				spire.rx = half * rng.randf_range(0.16, 0.26)
				spire.ry = depth * rng.randf_range(0.25, 0.4)
				spire.sharp = 0.9
				summits.append(spire)
			var base := _summit(0.0, -depth, tall * rng.randf_range(0.26, 0.34), half, depth)
			base.sharp = 1.3
			summits.append(base)
		Peak.MESA:
			# A flat top over steep layered walls, sometimes a lower step beside it.
			main.x *= 0.5
			main.flat = rng.randf_range(0.22, 0.36)
			main.cliff = true
			main.rx = half * 0.95
			main.ry = depth * 0.95
			if rng.randf() < 0.55:
				var side := -1.0 if rng.randf() < 0.5 else 1.0
				var step := _summit(main.x + side * half * 0.55, -depth * rng.randf_range(0.8, 1.2),
					tall * rng.randf_range(0.5, 0.68), half, depth)
				step.rx = half * 0.45
				step.ry = depth * 0.6
				step.flat = 0.25
				step.cliff = true
				summits.append(step)
		Peak.CRAG:
			# A low outcrop: a rocky knob with a few lower teeth beside it.
			main.flat = rng.randf_range(0.0, 0.25)
			main.sharp = 1.1
			for i in rng.randi_range(1, 3):
				var side := -1.0 if rng.randf() < 0.5 else 1.0
				summits.append(_shoulder(main, rng, side * rng.randf_range(0.36, 0.68) * half,
					tall * rng.randf_range(0.4, 0.8), half, depth))
	return summits


## A summit whose flanks reach the edge of the base.
func _summit(x: float, y: float, top: float, half: float, depth: float) -> Summit:
	var summit := Summit.new()
	summit.x = x
	summit.y = y
	summit.top = top
	summit.rx = half - absf(x) * 0.3
	summit.ry = depth
	return summit


func _shoulder(main: Summit, rng: RandomNumberGenerator, offset: float, top: float, half: float,
		depth: float) -> Summit:
	var shoulder := _summit(clampf(main.x + offset, -half * 0.8, half * 0.8),
		-depth * rng.randf_range(0.6, 1.4), top, half, depth)
	shoulder.rx = half * rng.randf_range(0.45, 0.6)
	shoulder.ry = depth * rng.randf_range(0.6, 0.85)
	return shoulder


## Little dark firs on the grassy foot, in stands rather than in a row; `share` of the
## spots in a stand get one. Back to front, so nearer firs stand over further ones.
func _firs(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, look: Look,
		heights: PackedFloat32Array, grounds: PackedByteArray, back: int, rows: int,
		colors: Array[Color], share: float) -> void:
	var w := canvas.size.x
	var j := rng.randi_range(0, 2)
	while j < rows:
		var x := rng.randi_range(0, 3)
		while x < w:
			var height := heights[j * w + x]
			var gx := canvas.offset.x + x + 0.5
			var gy := canvas.offset.y + back + j + 0.5
			var stand := NelvarPixelArt.value_noise(gx * 0.06, gy * 0.09, look.salt + 9)
			var point := Vector2(gx, gy - height)
			var p := canvas.pixel(point)
			if height > 1.0 and stand > 0.55 and rng.randf() < share and canvas.inside(p.x, p.y) \
					and grounds[p.y * w + p.x] == Ground.FOOT:
				var tall := rng.randf_range(4.0, 7.0) + minf(2.0, look.tall * 0.02)
				for k in int(tall):
					var reach := int(k * 0.4)
					for dx in range(-reach, reach + 1):
						var color := colors[0] if dx <= 0 else colors[1]
						if dx == -reach:
							color = NelvarEarthPainter.PINE_OUTLINE
						canvas.put_at(point + Vector2(dx, -tall + k), color, 0.3)
			x += rng.randi_range(3, 6)
		j += rng.randi_range(2, 4)


## A waterfall down the face near the summit: from under the snow (or a third of the
## way down) to the foot. A thin thread at the top, it spreads as it falls, with ragged
## edges and a little white water; at small ledges it steps sideways in a burst of
## spray; where it lands, foam and drifting mist. False when the face has no room.
func _waterfall(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, look: Look, main: Summit,
		tops: PackedInt32Array, bottoms: PackedInt32Array, grounds: PackedByteArray) -> bool:
	var w := canvas.size.x
	var widest := clampf(look.tall * 0.03, 1.5, 3.5)
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var x := float(canvas.pixel(Vector2(main.x + side * rng.randf_range(0.08, 0.22) * look.half, 0.0)).x)
	var column := int(x)
	if column < 6 or column >= w - 6 or bottoms[column] < 0:
		return false
	var bottom := bottoms[column] - 1
	var top := maxi(tops[column] + 3, bottom - int((bottom - tops[column]) * 0.66))
	while top < bottom and grounds[top * w + column] == Ground.SNOW:
		top += 1
	top += 2
	if bottom - top < 10:
		return false
	var ledge := top + rng.randi_range(8, 14)
	var spray := 0
	for y in range(top, bottom + 1):
		var fall := float(y - top) / float(bottom - top)
		var half := lerpf(0.4, widest, sqrt(fall))
		if y == ledge:
			x += (1.0 if rng.randf() < 0.5 else -1.0) * rng.randi_range(1, 2)
			ledge = y + rng.randi_range(8, 14)
			spray = 2
		var left := roundi(x - half) - (1 if rng.randf() < 0.25 else 0)
		var right := roundi(x + half) + (1 if rng.randf() < 0.25 else 0)
		for px in range(left, right + 1):
			canvas.put(px, y, FOAM if rng.randf() < 0.08 else WATER)
		if spray > 0:
			# Spray thrown out on both sides of the ledge.
			for px in range(left - 2, right + 3):
				if (px < left or px > right) and rng.randf() < 0.45:
					canvas.put(px, y, FOAM)
			spray -= 1
	# Where it lands: foam, and mist above it.
	var reach := roundi(widest) + 3
	for dy in range(-4, 2):
		for dx in range(-reach - 1, reach + 2):
			var spot := Vector2(dx / float(reach + 1), (dy + 0.5) / 2.0)
			if dy >= -1 and spot.length() <= 1.05:
				canvas.put(roundi(x) + dx, bottom + dy, FOAM)
			elif dy < -1 and absi(dx) <= reach and rng.randf() < 0.35:
				canvas.put(roundi(x) + dx, bottom + dy, MIST)
	return true

