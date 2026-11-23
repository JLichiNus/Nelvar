class_name NelvarMountainPainter
extends RefCounted
## Peaks round the earth valley, painted like the snowy range of the "Земля" menu: a
## lit right face and a shaded left one split by a wandering ridge, gullies running
## down from the summit, a ragged snow cap, and a green foot of grass and fir where
## the nearest row meets the valley. Further rows fade into the bluish haze.

const STEP := NelvarEarthData.PIXEL

## Rock of the nearest row (neutral grey-blue) and of the farthest (the menu's hazy blue).
const ROCK_NEAR: Array[Color] = [Color8(66, 76, 94), Color8(88, 100, 116), Color8(114, 124, 138),
	Color8(144, 152, 160), Color8(176, 182, 186)]
const ROCK_FAR: Array[Color] = [Color8(76, 104, 138), Color8(98, 128, 158), Color8(124, 154, 178),
	Color8(150, 178, 196), Color8(176, 198, 212)]
const SNOW: Array[Color] = [Color8(176, 196, 214), Color8(214, 226, 236), Color8(244, 248, 250)]
const OUTLINE := Color8(44, 52, 70)
const HAZE := Color8(178, 210, 222)
## The menu's green foothills and treeline.
const FOOT: Array[Color] = [Color8(40, 86, 68), Color8(56, 104, 82), Color8(70, 124, 88),
	Color8(88, 144, 94)]


class Summit:
	var x: float
	var top: float
	var left_slope: float
	var right_slope: float


func paint(thing: NelvarEarthData.Thing) -> NelvarEarthArt:
	var rng := RandomNumberGenerator.new()
	rng.seed = thing.appearance_seed
	var width := thing.size.x / STEP
	var height := thing.size.y / STEP
	var half := width * 0.5
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-half - 2.0, -height - 4.0,
		width + 4.0, height + 6.0))
	var haze := clampf(thing.row * 0.22, 0.0, 0.6)
	var rock: Array[Color] = []
	for i in ROCK_NEAR.size():
		rock.append(ROCK_NEAR[i].lerp(ROCK_FAR[i], minf(1.0, thing.row * 0.45)).lerp(HAZE, haze * 0.5))
	var snow: Array[Color] = []
	for color in SNOW:
		snow.append(color.lerp(HAZE, haze * 0.3))
	var outline := OUTLINE.lerp(rock[1], haze)
	# The main summit and up to two lower shoulders.
	var summits: Array[Summit] = []
	var main := Summit.new()
	main.x = rng.randf_range(-0.14, 0.14) * width
	main.top = -height
	main.left_slope = height / (main.x + half)
	main.right_slope = height / (half - main.x)
	summits.append(main)
	for i in rng.randi_range(0, 2):
		var shoulder := Summit.new()
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		shoulder.x = main.x + side * rng.randf_range(0.22, 0.36) * width
		shoulder.top = -height * rng.randf_range(0.5, 0.78)
		shoulder.left_slope = main.left_slope * rng.randf_range(0.85, 1.3)
		shoulder.right_slope = main.right_slope * rng.randf_range(0.85, 1.3)
		summits.append(shoulder)
	var salt := rng.randi() & 0xffff
	var snow_depth := height * rng.randf_range(0.26, 0.4) + 4.0
	var foot_height := height * 0.1 + 3.0 if thing.row == 0 else 0.0
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
		for summit in summits:
			# Steep under the summit, flaring out towards the foot.
			var distance := column - summit.x
			var span := -summit.top / (summit.left_slope if distance < 0.0 else summit.right_slope)
			var u := absf(distance) / span
			if u >= 1.0:
				continue
			var y := summit.top - summit.top * (1.45 * u - 0.45 * u * u)
			if y < top:
				top = y
				owner = summit
		if top == INF:
			continue
		# A ragged ridge: broad shoulders and small teeth, the summit itself kept.
		var near_summit := clampf(absf(column - owner.x) / 6.0, 0.0, 1.0)
		top += ((NelvarPixelArt.value_noise(column * 0.06, 0.5, salt + 6) - 0.5) * minf(12.0, height * 0.09)
			+ (NelvarPixelArt.value_noise(column * 0.35, 0.5, salt) - 0.5) * 3.0) * near_summit
		if top >= -0.5:
			continue
		owners[x] = owner
		skyline[x] = top
		tops[x] = maxi(0, canvas.pixel(Vector2(column, top)).y)
		snow_lines[x] = owner.top + snow_depth * (owner.top / main.top) \
			* (0.55 + 0.9 * NelvarPixelArt.value_noise(column * 0.12, 3.5, salt + 1)) \
			+ (NelvarPixelArt.value_noise(column * 0.5, 1.5, salt + 2) - 0.5) * 4.0
		foot_lines[x] = -foot_height * (0.6 + 0.8 * NelvarPixelArt.value_noise(column * 0.2, 7.5, salt + 3))
	# The wandering ridge of each summit, per row.
	var ridges := {}
	for summit in summits:
		var ridge := PackedFloat32Array()
		ridge.resize(h)
		for y in h:
			var at := canvas.center_of(0, y).y
			ridge[y] = summit.x + (NelvarPixelArt.value_noise(at * 0.12, summit.x * 0.1, salt + 4) - 0.5) \
				* (at - summit.top) * 0.5
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
		for y in range(tops[x], bottom + 1):
			var at := canvas.center_of(x, y).y
			if at > dissolve and float(NelvarPixelArt.bayer(canvas.grid + Vector2i(x, y))) / 16.0 \
					< (at - dissolve) / -dissolve:
				continue
			var below := at - owner.top
			var lit := column > ridge[y]
			var gully := NelvarPixelArt.value_noise((column - owner.x) / (below + 6.0) * 7.0,
				owner.x * 0.1, salt + 5)
			var cell := canvas.grid + Vector2i(x, y)
			var level := (0.66 if lit else 0.26) + (gully - 0.5) * 0.35 \
				+ (NelvarPixelArt.hash01(cell.x, cell.y, salt) - 0.5) * 0.12 - (at - skyline[x]) * 0.002
			var color: Color
			if at < snow_lines[x] + (gully - 0.5) * 6.0:
				color = NelvarPixelArt.ramp(snow, level + 0.12, cell)
			elif at > foot_lines[x]:
				# Grass and firs climbing the foot, ragged against the rock.
				color = NelvarPixelArt.ramp(FOOT, (0.55 if lit else 0.25) + (gully - 0.5) * 0.3, cell)
			else:
				color = NelvarPixelArt.ramp(rock, level, cell)
			# Outline on the shaded skyline and down the left edge of the silhouette.
			if (y == tops[x] and not lit) or (y < left_top and at < -1.0):
				color = outline
			data.encode_u32((y * w + x) * 4, color.to_abgr32())
			canvas.body[y * w + x] = 1
			canvas.levels[y * w + x] = level
	canvas.image = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	if thing.row == 0:
		_firs(canvas, rng, half, foot_height)
	return NelvarEarthArt.from_canvas(canvas)


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
