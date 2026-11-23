class_name NelvarMountainPainter
extends RefCounted
## Peaks round the earth valley, painted like the snowy range of the "Земля" menu: a
## lit right face and a shaded left one split by a wandering ridge, gullies running
## down from the summit, a ragged snow cap, and a green foot of grass and fir where
## the nearest row meets the valley. Further rows fade into the bluish haze.
##
## Every peak has a look (NelvarEarthData.Peak): a summit with shoulders, a broad
## massif of several tops, a cluster of rocky needles, a flat-topped mesa in layered
## rock, a giant with glaciers running down its gullies, or a low crag on the plateau.
## The rock of each peak takes one of a few tints, so the range is not one colour.

const STEP := NelvarEarthData.PIXEL
const Peak = NelvarEarthData.Peak

## Rock tints of the nearest row, dark to light: cool grey-blue, warm grey-brown, slate.
const ROCK_TINTS: Array = [
	[Color8(66, 76, 94), Color8(88, 100, 116), Color8(114, 124, 138), Color8(144, 152, 160),
		Color8(176, 182, 186)],
	[Color8(74, 68, 72), Color8(98, 90, 90), Color8(126, 116, 108), Color8(156, 146, 132),
		Color8(186, 176, 158)],
	[Color8(52, 60, 80), Color8(70, 80, 102), Color8(92, 102, 124), Color8(120, 128, 146),
		Color8(152, 158, 172)],
]
## Rock of the farthest row (the menu's hazy blue): every tint fades towards it.
const ROCK_FAR: Array[Color] = [Color8(76, 104, 138), Color8(98, 128, 158), Color8(124, 154, 178),
	Color8(150, 178, 196), Color8(176, 198, 212)]
const SNOW: Array[Color] = [Color8(176, 196, 214), Color8(214, 226, 236), Color8(244, 248, 250)]
const OUTLINE := Color8(44, 52, 70)
const HAZE := Color8(178, 210, 222)
## The menu's green foothills and treeline.
const FOOT: Array[Color] = [Color8(40, 86, 68), Color8(56, 104, 82), Color8(70, 124, 88),
	Color8(88, 144, 94)]
## Turf of the high plateau (earth_ground.gdshader, TURF): the crags' feet.
const TURF: Array[Color] = [Color8(70, 96, 72), Color8(88, 116, 80), Color8(110, 138, 88),
	Color8(138, 160, 100)]
const SHADOW := Color(0.1, 0.14, 0.2, 0.32)


class Summit:
	var x: float
	var top: float
	var left_slope: float
	var right_slope: float
	## Half-width of a flat top (mesas), art pixels.
	var flat := 0.0


## How a look shapes the peak: snow depth (share of the height), teeth of the ridge,
## and how far glaciers run down the gullies (share of the height).
class Style:
	var snow := Vector2(0.26, 0.4)
	var teeth := 1.0
	var glacier := 0.0
	var strata := false


func paint(thing: NelvarEarthData.Thing) -> NelvarEarthArt:
	var rng := RandomNumberGenerator.new()
	rng.seed = thing.appearance_seed
	var shape: int = thing.variant
	var width := thing.size.x / STEP
	var height := thing.size.y / STEP
	var half := width * 0.5
	var plateau := shape == Peak.CRAG
	# Everything but the nearest row stands on the plateau: a turf foot and a shadow.
	var on_plateau := plateau or thing.row > 0
	var below := 4.0 + height * 0.1 if on_plateau else 2.0
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-half - 2.0, -height - 4.0,
		width + 4.0, height + 4.0 + below))
	# Seen from above the far rows stand on the same plateau: only a little haze.
	var haze := clampf(thing.row * 0.1, 0.0, 0.3) if not plateau else 0.06
	var tint: Array = ROCK_TINTS[rng.randi_range(0, ROCK_TINTS.size() - 1)]
	var rock: Array[Color] = []
	for i in ROCK_FAR.size():
		var near: Color = tint[i]
		rock.append(near.lerp(ROCK_FAR[i], minf(1.0, thing.row * 0.22) if not plateau else 0.05)
			.lerp(HAZE, haze * 0.5))
	var snow: Array[Color] = []
	for color in SNOW:
		snow.append(color.lerp(HAZE, haze * 0.3))
	var outline := OUTLINE.lerp(rock[1], haze)
	var style := _style(shape, rng)
	var summits := _summits(shape, rng, width, height)
	var main := summits[0]
	var salt := rng.randi() & 0xffff
	var snow_depth := height * rng.randf_range(style.snow.x, style.snow.y) + (4.0 if style.snow.y > 0.0 else 0.0)
	var foot_height := height * 0.1 + 3.0 if thing.row == 0 and not plateau else 0.0
	if on_plateau:
		foot_height = height * 0.05 + 2.0
	var glacier := height * style.glacier
	var band := maxf(4.0, height * rng.randf_range(0.09, 0.12))
	var w := canvas.size.x
	var h := canvas.size.y
	# Pass 1, per column: the skyline (the lowest-reaching summit owns the column; the
	# ridge is ragged), the snow line and the top of the green foot.
	var tops := PackedInt32Array()
	tops.resize(w)
	var owners: Array[Summit] = []
	owners.resize(w)
	var snow_lines := PackedFloat32Array()
	snow_lines.resize(w)
	var foot_lines := PackedFloat32Array()
	foot_lines.resize(w)
	var skyline := PackedFloat32Array()
	skyline.resize(w)
	for x in w:
		tops[x] = h
		var column := canvas.center_of(x, 0).x
		if absf(column) > half:
			continue
		var top := INF
		var owner := main
		var on_flat := false
		for summit in summits:
			# Steep under the summit, flaring out towards the foot; a mesa keeps its top.
			var distance := column - summit.x
			var past := maxf(0.0, absf(distance) - summit.flat)
			var span := -summit.top / (summit.left_slope if distance < 0.0 else summit.right_slope)
			var u := past / span
			if u >= 1.0:
				continue
			var y := summit.top - summit.top * (1.45 * u - 0.45 * u * u)
			if y < top:
				top = y
				owner = summit
				on_flat = past <= 0.0 and summit.flat > 0.0
		if top == INF:
			continue
		# A ragged ridge: broad shoulders and small teeth, the summit itself kept.
		var near_summit := clampf((maxf(0.0, absf(column - owner.x) - owner.flat)) / 6.0, 0.0, 1.0)
		var broad := (NelvarPixelArt.value_noise(column * 0.06, 0.5, salt + 6) - 0.5) * minf(12.0, height * 0.09)
		var teeth := (NelvarPixelArt.value_noise(column * 0.35, 0.5, salt) - 0.5) * 3.0 * style.teeth
		if on_flat:
			broad *= 0.12
			teeth *= 0.4
			near_summit = 1.0
		top += (broad + teeth) * near_summit
		if top >= -0.5:
			continue
		owners[x] = owner
		skyline[x] = top
		tops[x] = maxi(0, canvas.pixel(Vector2(column, top)).y)
		snow_lines[x] = owner.top + snow_depth * (owner.top / main.top) \
			* (0.55 + 0.9 * NelvarPixelArt.value_noise(column * 0.12, 3.5, salt + 1)) \
			+ (NelvarPixelArt.value_noise(column * 0.5, 1.5, salt + 2) - 0.5) * 4.0
		if snow_depth <= 0.0:
			snow_lines[x] = -INF
		foot_lines[x] = -foot_height * (0.6 + 0.8 * NelvarPixelArt.value_noise(column * 0.2, 7.5, salt + 3))
	# The wandering ridge of each summit, per row (on a mesa it leaves the top's left part
	# in shade).
	var ridges := {}
	for summit in summits:
		var ridge := PackedFloat32Array()
		ridge.resize(h)
		for y in h:
			var at := canvas.center_of(0, y).y
			ridge[y] = summit.x - summit.flat * 0.3 + (NelvarPixelArt.value_noise(at * 0.12, summit.x * 0.1,
				salt + 4) - 0.5) * (at - summit.top) * 0.5
		ridges[summit] = ridge
	# Pass 2: the pixels, written straight into the image data. The foot dissolves
	# raggedly into the ground instead of ending in a straight line.
	var bottom := mini(h - 1, canvas.pixel(Vector2(0.0, -0.5)).y)
	var fade := 4.0 + height * 0.035
	var data := PackedByteArray()
	data.resize(w * h * 4)
	for x in w:
		if tops[x] >= h:
			continue
		var owner := owners[x]
		var column := canvas.center_of(x, 0).x
		var ridge: PackedFloat32Array = ridges[owner]
		var left_top := tops[x - 1] if x > 0 else h
		var dissolve := -fade * (0.35 + 0.65 * NelvarPixelArt.value_noise(column * 0.18, 9.5, salt + 7))
		var wobble := (NelvarPixelArt.value_noise(column * 0.08, 2.5, salt + 8) - 0.5) * band * 0.8
		for y in range(tops[x], bottom + 1):
			var at := canvas.center_of(x, y).y
			if at > dissolve and float(NelvarPixelArt.bayer(canvas.grid + Vector2i(x, y))) / 16.0 \
					< (at - dissolve) / -dissolve:
				continue
			var below_top := at - owner.top
			var lit := column > ridge[y]
			var gully := NelvarPixelArt.value_noise((column - owner.x) / (below_top + 6.0) * 7.0,
				owner.x * 0.1, salt + 5)
			var cell := canvas.grid + Vector2i(x, y)
			var level := (0.66 if lit else 0.26) + (gully - 0.5) * 0.35 \
				+ (NelvarPixelArt.hash01(cell.x, cell.y, salt) - 0.5) * 0.12 - (at - skyline[x]) * 0.002
			var seam := false
			if style.strata and below_top < band * 3.2:
				# A cap of layered rock under the top: a few bands, a seam between them.
				var layer := (below_top + wobble) / band
				level += 0.06 if int(floor(layer)) % 2 == 0 else -0.04
				seam = layer - floor(layer) < 1.0 / band and at > skyline[x] + 2.0 and layer > 0.6
			var color: Color
			# Glaciers: the snow runs further down the deepest gullies.
			var tongue := maxf(0.0, gully - 0.56) / 0.44 * glacier
			if at < snow_lines[x] + (gully - 0.5) * 6.0 + tongue:
				color = NelvarPixelArt.ramp(snow, level + 0.12 + (0.0 if at < snow_lines[x] else -0.1), cell)
			elif at > foot_lines[x] and foot_height > 0.0:
				# Grass (and by the valley firs) climbing the foot, ragged against the rock.
				color = NelvarPixelArt.ramp(TURF if on_plateau else FOOT,
					(0.55 if lit else 0.25) + (gully - 0.5) * 0.3, cell)
			else:
				color = NelvarPixelArt.ramp(rock, level, cell)
				if seam:
					color = rock[0] if lit else outline
			# Outline on the shaded skyline and down the left edge of the silhouette.
			if (y == tops[x] and not lit) or (y < left_top and at < -1.0):
				color = outline
			data.encode_u32((y * w + x) * 4, color.to_abgr32())
			canvas.body[y * w + x] = 1
			canvas.levels[y * w + x] = level
	canvas.image = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	if thing.row == 0 and not plateau:
		_firs(canvas, rng, half, foot_height)
	if on_plateau:
		_shadow(canvas, half, height)
	return NelvarEarthArt.from_canvas(canvas)


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
			style.teeth = 2.2
		Peak.MESA:
			style.snow = Vector2(0.02, 0.04) if rng.randf() < 0.5 else Vector2.ZERO
			style.strata = true
			style.teeth = 1.4
		Peak.GIANT:
			style.snow = Vector2(0.4, 0.5)
			style.glacier = 0.32
		Peak.CRAG:
			style.snow = Vector2(0.08, 0.14) if rng.randf() < 0.25 else Vector2.ZERO
			style.teeth = 1.8
			style.strata = rng.randf() < 0.5
	return style


## The summits of a look; the first is the highest.
func _summits(shape: int, rng: RandomNumberGenerator, width: float, height: float) -> Array[Summit]:
	var half := width * 0.5
	var summits: Array[Summit] = []
	var main := _summit(rng.randf_range(-0.14, 0.14) * width, -height, half)
	summits.append(main)
	match shape:
		Peak.SUMMIT, Peak.GIANT:
			var shoulders := rng.randi_range(0, 2) if shape == Peak.SUMMIT else 2
			for i in shoulders:
				var side := -1.0 if rng.randf() < 0.5 else 1.0
				if shape == Peak.GIANT:
					side = -1.0 if i == 0 else 1.0
				_add_shoulder(summits, main, rng, side * rng.randf_range(0.22, 0.36) * width,
					height * rng.randf_range(0.5, 0.78))
		Peak.MASSIF:
			# Several tops of nearly the same height along a broad ridge.
			main.left_slope *= 0.8
			main.right_slope *= 0.8
			var count := rng.randi_range(2, 3)
			for i in count:
				var at := lerpf(-0.36, 0.36, (i + rng.randf_range(0.1, 0.9)) / count) * width
				if absf(at - main.x) < width * 0.12:
					at += signf(at - main.x + 0.01) * width * 0.14
				_add_shoulder(summits, main, rng, at - main.x, height * rng.randf_range(0.72, 0.94))
		Peak.NEEDLES:
			# Narrow spires on a low rocky base.
			main.left_slope *= 2.6
			main.right_slope *= 2.6
			for i in rng.randi_range(2, 3):
				var spire := _summit(rng.randf_range(-0.36, 0.36) * width, -height * rng.randf_range(0.45, 0.85), half)
				spire.left_slope *= rng.randf_range(2.4, 3.4)
				spire.right_slope *= rng.randf_range(2.4, 3.4)
				summits.append(spire)
			var base := _summit(0.0, -height * rng.randf_range(0.26, 0.34), half)
			base.left_slope *= 0.6
			base.right_slope *= 0.6
			summits.append(base)
		Peak.MESA:
			# A flat top over steep layered walls, sometimes a lower step beside it.
			main.x *= 0.5
			main.flat = width * rng.randf_range(0.1, 0.18)
			main.left_slope = height / maxf(1.0, main.x - main.flat + half) * 1.15
			main.right_slope = height / maxf(1.0, half - main.x - main.flat) * 1.15
			if rng.randf() < 0.55:
				var side := -1.0 if rng.randf() < 0.5 else 1.0
				var step := _summit(main.x + side * (main.flat + width * 0.1), -height * rng.randf_range(0.5, 0.68), half)
				step.flat = width * rng.randf_range(0.06, 0.12)
				step.left_slope = main.left_slope
				step.right_slope = main.right_slope
				summits.append(step)
		Peak.CRAG:
			# A low outcrop: a rocky knob with a few lower teeth beside it.
			main.flat = width * rng.randf_range(0.0, 0.12)
			for i in rng.randi_range(1, 3):
				var side := -1.0 if rng.randf() < 0.5 else 1.0
				_add_shoulder(summits, main, rng, side * rng.randf_range(0.18, 0.34) * width,
					height * rng.randf_range(0.4, 0.8))
	for summit in summits:
		summit.x = clampf(summit.x, -half * 0.8, half * 0.8)
		summit.left_slope = maxf(summit.left_slope, -summit.top / maxf(1.0, summit.x - summit.flat + half))
		summit.right_slope = maxf(summit.right_slope, -summit.top / maxf(1.0, half - summit.x - summit.flat))
	return summits


## A summit whose slopes reach the edges of the base.
func _summit(x: float, top: float, half: float) -> Summit:
	var summit := Summit.new()
	summit.x = x
	summit.top = top
	summit.left_slope = -top / maxf(1.0, x + half)
	summit.right_slope = -top / maxf(1.0, half - x)
	return summit


func _add_shoulder(summits: Array[Summit], main: Summit, rng: RandomNumberGenerator, offset: float,
		height: float) -> void:
	var shoulder := Summit.new()
	shoulder.x = main.x + offset
	shoulder.top = -height
	shoulder.left_slope = main.left_slope * rng.randf_range(0.85, 1.3)
	shoulder.right_slope = main.right_slope * rng.randf_range(0.85, 1.3)
	summits.append(shoulder)


## A shadow on the plateau, falling down-left like those in the valley.
func _shadow(canvas: NelvarEarthCanvas, half: float, height: float) -> void:
	var center := Vector2(-half * 0.1, 0.5)
	var reach := Vector2(half * 0.95, 2.0 + height * 0.08)
	var from := canvas.pixel(center - reach)
	var to := canvas.pixel(center + reach)
	for y in range(maxi(0, from.y), mini(canvas.size.y, to.y + 1)):
		for x in range(maxi(0, from.x), mini(canvas.size.x, to.x + 1)):
			if canvas.is_body(x, y):
				continue
			var color := NelvarPixelArt.shadow_at(canvas.center_of(x, y), center, reach,
				canvas.grid + Vector2i(x, y))
			if color.a > 0.0:
				canvas.image.set_pixel(x, y, SHADOW)


## Little dark firs along the green foot of the nearest row (the menu's treeline).
func _firs(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, half: float, foot: float) -> void:
	var x := -half + rng.randf_range(0.0, 4.0)
	while x < half:
		var tall := rng.randf_range(4.0, 7.0) + foot * 0.3
		var base := -rng.randf_range(0.0, foot * 0.5)
		var probe := canvas.pixel(Vector2(x, base - 1.0))
		if canvas.is_body(probe.x, probe.y):
			for k in int(tall):
				var reach := int(k * 0.38)
				for dx in range(-reach, reach + 1):
					var color := FOOT[0] if dx <= 0 else FOOT[1]
					if dx == -reach:
						color = NelvarEarthPainter.PINE_OUTLINE
					canvas.put_at(Vector2(x + dx, base - tall + k), color, 0.3)
		x += rng.randf_range(2.5, 6.0)
