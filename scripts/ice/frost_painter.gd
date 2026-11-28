class_name NelvarFrostPainter
extends NelvarMountainPainter
## The mountains round the ice valley, painted by NelvarMountainPainter's height field in
## the palette of the "Лёд" menu: grey-blue rock, the further rows leaning into the pale
## winter haze, deep snow on every peak with glaciers down the gullies of most, snow
## instead of grass at the foot, and pines in hoarfrost on it. No waterfalls: everything
## is frozen. The giant stays a great glaciated peak.

## Rock of the menu's ice range and two neighbours of it, dark to light.
const FROST_TINTS: Array = [
	[Color8(84, 90, 104), Color8(110, 116, 130), Color8(140, 146, 158), Color8(172, 178, 188),
		Color8(206, 209, 214)],
	[Color8(76, 86, 106), Color8(100, 112, 132), Color8(128, 140, 158), Color8(160, 170, 186),
		Color8(196, 204, 216)],
	[Color8(88, 88, 96), Color8(116, 116, 124), Color8(146, 146, 152), Color8(176, 176, 182),
		Color8(206, 206, 210)],
]
## The menu's far range in its haze: rows further out lean towards it.
const FROST_FAR: Array[Color] = [Color8(150, 156, 170), Color8(170, 176, 188), Color8(192, 197, 206),
	Color8(212, 216, 223), Color8(228, 231, 236)]
const FROST_SNOW: Array[Color] = [Color8(190, 195, 204), Color8(216, 220, 227), Color8(236, 238, 242),
	Color8(250, 250, 251)]
const ICE_HAZE := Color8(226, 229, 234)
const FROST_OUTLINE := Color8(58, 64, 80)
## Snow at the foot: the valley's snow; on the plateau a little greyer, as in the haze.
const SNOW_FOOT: Array[Color] = [Color8(176, 182, 194), Color8(198, 204, 214), Color8(218, 222, 230),
	Color8(236, 238, 242)]
const SNOW_FOOT_FAR: Array[Color] = [Color8(184, 190, 202), Color8(200, 206, 215), Color8(216, 220, 228),
	Color8(230, 233, 238)]
## Pines in hoarfrost on the foot (the menu's treeline with its caps).
const FIR_NEEDLES: Array[Color] = [Color8(44, 60, 60), Color8(58, 76, 74)]
const FIR_CAP: Array[Color] = [Color8(222, 226, 232), Color8(244, 246, 248)]
const FIR_OUTLINE := Color8(34, 42, 46)


func _look(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarMountainPainter.Look:
	var look := super(thing, rng)
	var shape: int = thing.variant
	var far := 0.08 if shape == Peak.CRAG or thing.row >= 3 else minf(0.45, thing.row * 0.15)
	var tint: Array = FROST_TINTS[look.salt % FROST_TINTS.size()]
	var rock: Array[Color] = []
	for i in FROST_FAR.size():
		var near: Color = tint[i]
		rock.append(near.lerp(FROST_FAR[i], far))
	look.rock = rock
	var snow: Array[Color] = []
	for color in FROST_SNOW:
		snow.append(color.lerp(ICE_HAZE, far * 0.3))
	look.snow = snow
	look.foot = SNOW_FOOT_FAR if look.on_plateau else SNOW_FOOT
	look.outline = FROST_OUTLINE.lerp(look.rock[1], far * 0.6)
	look.edge = look.rock[0].lerp(FROST_OUTLINE, 0.35)
	look.rim = look.rock[4].lerp(Color8(252, 252, 252), 0.5)
	return look


func _style(shape: int, rng: RandomNumberGenerator) -> NelvarMountainPainter.Style:
	var style := NelvarMountainPainter.Style.new()
	match shape:
		Peak.SUMMIT:
			style.snow = Vector2(0.45, 0.6)
			style.glacier = 0.25 if rng.randf() < 0.7 else 0.12
		Peak.MASSIF:
			style.snow = Vector2(0.5, 0.65)
			style.glacier = 0.25
		Peak.NEEDLES:
			style.snow = Vector2(0.18, 0.3)
			style.glacier = 0.1
		Peak.MESA:
			style.snow = Vector2(0.15, 0.26)
			style.glacier = 0.1
			style.strata = true
		Peak.GIANT:
			style.snow = Vector2(0.55, 0.7)
			style.glacier = 0.45
		Peak.CRAG:
			style.snow = Vector2(0.3, 0.45)
			style.glacier = 0.15
			style.strata = rng.randf() < 0.5
	return style


## The foot is snow (a rock showing through here and there); the rest as the earth's.
func _color(look: NelvarMountainPainter.Look, ground: int, level: float, cell: Vector2i) -> Color:
	if ground == Ground.FOOT:
		if NelvarPixelArt.hash01(cell.x, cell.y, look.salt + 11) < 0.04:
			return look.rock[1] if level > 0.45 else look.rock[0]
		return NelvarPixelArt.ramp(look.foot, level * 0.7 + 0.3, cell)
	return super(look, ground, level, cell)


## Little pines in hoarfrost on the snowy foot, in stands; back to front, so nearer ones
## stand over further ones.
func _decorate(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, look: NelvarMountainPainter.Look,
		heights: PackedFloat32Array, grounds: PackedByteArray, back: int, rows: int) -> void:
	var w := canvas.size.x
	var share := 0.22 if look.on_plateau else 0.42
	var needles: Array[Color] = []
	for color in FIR_NEEDLES:
		needles.append(color.lerp(ICE_HAZE, 0.3 if look.on_plateau else 0.0))
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
				_frosted_pine(canvas, point, rng.randf_range(4.0, 7.0) + minf(2.0, look.tall * 0.02), needles)
			x += rng.randi_range(3, 6)
		j += rng.randi_range(2, 4)


## A small cone of dark needles with snow on its tip and on the lit side of each tier.
static func _frosted_pine(canvas: NelvarEarthCanvas, point: Vector2, tall: float,
		needles: Array[Color]) -> void:
	for k in int(tall):
		var reach := int(k * 0.4)
		for dx in range(-reach, reach + 1):
			var color := needles[0] if dx <= 0 else needles[1]
			if dx == -reach:
				color = FIR_OUTLINE
			if k == 0 or (k % 3 == 1 and dx >= 0):
				color = FIR_CAP[1] if dx > 0 or k == 0 else FIR_CAP[0]
			canvas.put_at(point + Vector2(dx, -tall + k), color, 0.3)


## Everything is frozen: no waterfalls.
func _has_waterfall(_thing: NelvarEarthData.Thing) -> bool:
	return false


func _finish(art: NelvarEarthArt, _look_used: NelvarMountainPainter.Look,
		_thing: NelvarEarthData.Thing) -> NelvarEarthArt:
	return NelvarIceArt.adopt(art)
