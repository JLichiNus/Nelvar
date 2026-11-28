class_name NelvarVolcanoPainter
extends NelvarMountainPainter
## The ridges, volcanoes and cinder cones round the fire forge, painted by
## NelvarMountainPainter's height field in the palette of the "Огонь" menu: black-brown
## basalt with a fiery rim on the skyline, grey ash where snow would lie, cinder slopes
## with dead snags at the foot instead of grass and firs, columnar basalt on the walls.
##
## The giant's look is a volcano here: a cone with a crater. A molten one (Thing.accent)
## holds lava in its crater, and a great volcano (the nearest row, wide) sends it down
## its front to the foot, where a lava stream of the basin begins. A molten massif or
## mesa pours a lavafall (the earth's waterfall, re-keyed). Lava pixels are keyed for
## fire_molten.gdshader; the art keeps the crater's mouth as its vent (smoke rises there).

## Ground of the crater's pool and of the lava running down the front.
const LAVA_POOL := 4
const LAVA_FLOW := 5
## The floor of a crater gone cold.
const CRATER_FLOOR := 6
## A great volcano: its lava runs down the front.
const GREAT_WIDTH := 700.0

## Basalt of the menu's fire reality and two neighbours of it, dark to light.
const BASALT_TINTS: Array = [
	[Color8(34, 22, 26), Color8(48, 32, 34), Color8(64, 42, 42), Color8(84, 56, 50), Color8(108, 72, 60)],
	[Color8(36, 24, 32), Color8(52, 36, 44), Color8(70, 50, 56), Color8(92, 66, 68), Color8(118, 86, 82)],
	[Color8(30, 26, 28), Color8(44, 38, 40), Color8(60, 52, 52), Color8(80, 70, 66), Color8(104, 92, 84)],
]
## The menu's far range in its fiery haze: rows further out lean towards it.
const BASALT_FAR: Array[Color] = [Color8(56, 28, 32), Color8(74, 38, 40), Color8(96, 50, 48),
	Color8(118, 64, 56), Color8(140, 80, 66)]
## Ash: dull and warm, so it never reads as snow under the lava's light.
const ASH: Array[Color] = [Color8(72, 62, 64), Color8(92, 80, 80), Color8(114, 100, 96)]
## Cinder slopes at the foot: red-brown scoria; duller on the plateau.
const CINDER: Array[Color] = [Color8(60, 32, 32), Color8(78, 42, 38), Color8(98, 54, 44),
	Color8(120, 68, 52)]
const CINDER_FAR: Array[Color] = [Color8(66, 42, 42), Color8(80, 52, 48), Color8(96, 62, 54),
	Color8(112, 74, 62)]
const FIRE_OUTLINE := Color8(16, 8, 12)
## The menu's fiery contour along the ridge.
const FIRE_RIM := Color8(214, 108, 60)
const SNAG := Color8(22, 14, 16)
const LAVA := Color8(246, 130, 52)
const LAVA_HOT := Color8(255, 196, 96)
const EMBER := Color8(226, 92, 40)


func _look(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarMountainPainter.Look:
	var look := super(thing, rng)
	var shape: int = thing.variant
	var far := 0.08 if shape == Peak.CRAG or thing.row >= 3 else minf(0.45, thing.row * 0.15)
	var tint: Array = BASALT_TINTS[look.salt % BASALT_TINTS.size()]
	var rock: Array[Color] = []
	for i in BASALT_FAR.size():
		var near: Color = tint[i]
		rock.append(near.lerp(BASALT_FAR[i], far))
	look.rock = rock
	var ash: Array[Color] = []
	for color in ASH:
		ash.append(color.lerp(BASALT_FAR[3], far * 0.5))
	look.snow = ash
	look.foot = CINDER_FAR if look.on_plateau else CINDER
	look.outline = FIRE_OUTLINE.lerp(look.rock[1], far * 0.6)
	look.edge = look.rock[0].lerp(FIRE_OUTLINE, 0.4)
	look.rim = FIRE_RIM.lerp(look.rock[3], far * 0.9)
	if shape == Peak.GIANT:
		var great := thing.size.x >= GREAT_WIDTH
		look.crater = 0.16 if great else 0.2
		look.molten = thing.accent
		look.channel = thing.accent and great and thing.row == 0
	return look


func _style(shape: int, rng: RandomNumberGenerator) -> NelvarMountainPainter.Style:
	var style := NelvarMountainPainter.Style.new()
	match shape:
		Peak.SUMMIT:
			style.snow = Vector2(0.06, 0.14)
			style.columns = rng.randf() < 0.4
		Peak.MASSIF:
			style.snow = Vector2(0.08, 0.16)
			style.columns = rng.randf() < 0.3
		Peak.NEEDLES:
			style.snow = Vector2(0.03, 0.08)
		Peak.MESA:
			style.snow = Vector2(0.0, 0.04)
			style.columns = true
		Peak.GIANT:
			# Ash lies thick on a volcano's upper slopes.
			style.snow = Vector2(0.16, 0.26)
		Peak.CRAG:
			style.snow = Vector2(0.04, 0.1) if rng.randf() < 0.3 else Vector2.ZERO
			style.columns = rng.randf() < 0.5
	return style


## The giant is a volcano: a cone that flares out towards its foot, flat on top round a
## crater, sometimes with a small parasitic cone on a flank. The rest as the earth's.
func _summits(shape: int, rng: RandomNumberGenerator, half: float, depth: float,
		tall: float) -> Array[NelvarMountainPainter.Summit]:
	if shape != Peak.GIANT:
		return super(shape, rng, half, depth, tall)
	var summits: Array[NelvarMountainPainter.Summit] = []
	var main := _summit(0.0, -depth, tall, half, depth)
	main.rx = half * 0.97
	main.ry = depth * 0.97
	main.sharp = 1.75
	main.flat = 0.2 if half < 80.0 else 0.17
	summits.append(main)
	if half > 60.0 and rng.randf() < 0.55:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var cone := _summit(side * half * rng.randf_range(0.42, 0.6), -depth * rng.randf_range(0.7, 1.1),
			tall * rng.randf_range(0.26, 0.38), half, depth)
		cone.rx = half * 0.26
		cone.ry = depth * 0.32
		cone.sharp = 1.2
		summits.append(cone)
	return summits


## A bowl sunk into the volcano's flat top: shallow enough that its pool shows over the
## front rim in the oblique view.
func _relief(p: Vector2, look: NelvarMountainPainter.Look) -> Vector2:
	var ground := super(p, look)
	if look.crater <= 0.0 or ground.x <= 0.0:
		return ground
	var d := _in_crater(look, p.x, p.y)
	if d < 1.0:
		var s := look.summits[0]
		var bowl := minf(s.top * 0.12, s.ry * look.crater * 0.85)
		ground.x = minf(ground.x, s.top - bowl * (1.0 - d * d))
	return ground


## Distance from the crater's middle in its radius (below 1 inside it).
func _in_crater(look: NelvarMountainPainter.Look, gx: float, gy: float) -> float:
	var s := look.summits[0]
	return Vector2((gx - s.x) / s.rx, (gy - s.y) / s.ry).length() / look.crater


func _ground(look: NelvarMountainPainter.Look, height: float, slope: float, gully: float,
		gx: float, gy: float) -> int:
	if look.crater > 0.0:
		var d := _in_crater(look, gx, gy)
		if d < 0.74:
			return LAVA_POOL if look.molten else CRATER_FLOOR
		if d < 1.0:
			return Ground.ROCK
		if look.channel and _in_channel(look, gx, gy) and height > 0.6:
			return LAVA_FLOW
	return super(look, height, slope, gully, gx, gy)


## The lava's path down the front of a great volcano: from the crater's front rim to the
## foot, wandering a little and widening as it goes.
func _in_channel(look: NelvarMountainPainter.Look, gx: float, gy: float) -> bool:
	var s := look.summits[0]
	var start := s.y + s.ry * look.crater * 0.7
	if gy < start:
		return false
	var progress := clampf((gy - start) / maxf(1.0, -start), 0.0, 1.0)
	var lean := (float(look.salt % 9) - 4.0) * 1.6
	var phase := float(look.salt % 97)
	var center := s.x + sin(gy * 0.11 + phase) * (1.0 + progress * 4.5) \
		+ sin(gy * 0.37 + phase * 2.0) * 0.8 + progress * progress * lean
	var half := 0.8 + progress * 2.0 + sin(gy * 0.5 + phase) * 0.5 * progress
	if absf(gx - center) <= half:
		return true
	# Near the foot it splits round a hump into a second arm.
	if progress > 0.6:
		var arm := center + (progress - 0.6) * 22.0 * (1.0 if look.salt % 2 == 0 else -1.0)
		return absf(gx - arm) <= half * 0.7
	return false


func _color(look: NelvarMountainPainter.Look, ground: int, level: float, cell: Vector2i) -> Color:
	match ground:
		LAVA_POOL:
			return NelvarFireArt.keyed(LAVA_HOT if level > 0.5 else LAVA, NelvarFireArt.HOT_KEY)
		LAVA_FLOW:
			return NelvarFireArt.keyed(LAVA, NelvarFireArt.FLOW_KEY)
		CRATER_FLOOR:
			return look.rock[0] if level < 0.6 else look.rock[1]
		Ground.FOOT:
			# Cinder with a scatter of darker clinker.
			if NelvarPixelArt.hash01(cell.x, cell.y, look.salt + 11) < 0.07:
				return look.rock[1] if level > 0.45 else look.rock[0]
			return NelvarPixelArt.ramp(look.foot, level * 0.85 + 0.05, cell)
	return super(look, ground, level, cell)


## Dead snags on the cinder slopes instead of firs, in loose stands; on a molten volcano
## some still glow at the tip.
func _decorate(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, look: NelvarMountainPainter.Look,
		heights: PackedFloat32Array, grounds: PackedByteArray, back: int, rows: int) -> void:
	var w := canvas.size.x
	var j := rng.randi_range(0, 2)
	while j < rows:
		var x := rng.randi_range(0, 4)
		while x < w:
			var height := heights[j * w + x]
			var gx := canvas.offset.x + x + 0.5
			var gy := canvas.offset.y + back + j + 0.5
			var stand := NelvarPixelArt.value_noise(gx * 0.06, gy * 0.09, look.salt + 9)
			var point := Vector2(gx, gy - height)
			var p := canvas.pixel(point)
			if height > 1.0 and stand > 0.6 and rng.randf() < 0.28 and canvas.inside(p.x, p.y) \
					and grounds[p.y * w + p.x] == Ground.FOOT:
				var tall := rng.randi_range(3, 6)
				for k in tall:
					canvas.put_at(point + Vector2(0, -k), SNAG, 0.2)
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				canvas.put_at(point + Vector2(side, -tall + 1 + rng.randi_range(0, 1)), SNAG, 0.2)
				if rng.randf() < (0.35 if look.molten else 0.08):
					canvas.put_at(point + Vector2(0, -tall), NelvarFireArt.keyed(EMBER, NelvarFireArt.EMBER_KEY), 0.9)
			x += rng.randi_range(4, 8)
		j += rng.randi_range(2, 4)


## Lavafalls pour from molten massifs and mesas; volcanoes keep their lava in the crater.
func _has_waterfall(thing: NelvarEarthData.Thing) -> bool:
	return thing.accent and thing.variant in [Peak.MASSIF, Peak.MESA]


func _finish(art: NelvarEarthArt, look: NelvarMountainPainter.Look,
		_thing: NelvarEarthData.Thing) -> NelvarEarthArt:
	var fire := NelvarFireArt.adopt(art)
	fire.molten = true
	if art.waterfall:
		_rekey_lavafall(fire.image)
	if look.crater > 0.0:
		var s := look.summits[0]
		fire.vent = Vector2(s.x, s.y - s.top + 1.0)
		if look.molten:
			for k in 3:
				fire.sparks.append(fire.vent + Vector2(float(k - 1) * s.rx * look.crater * 0.5, 0.0))
	return fire


## The waterfall's water, foam and mist become lava running down, hot spray and embers.
static func _rekey_lavafall(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var key := roundi(image.get_pixel(x, y).a * 255.0)
			match key:
				NelvarMountainPainter.WATER_KEY:
					image.set_pixel(x, y, NelvarFireArt.keyed(LAVA, NelvarFireArt.FLOW_KEY))
				NelvarMountainPainter.FOAM_KEY:
					image.set_pixel(x, y, NelvarFireArt.keyed(LAVA_HOT, NelvarFireArt.HOT_KEY))
				NelvarMountainPainter.MIST_KEY:
					image.set_pixel(x, y, NelvarFireArt.keyed(EMBER, NelvarFireArt.EMBER_KEY))
