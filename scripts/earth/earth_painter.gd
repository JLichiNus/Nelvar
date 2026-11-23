class_name NelvarEarthPainter
extends RefCounted
## Bakes everything that stands in the earth valley in the style of the "Земля" menu
## background: deep greens lit from the upper right, dark green-brown outlines on
## shaded edges, soft shadows on the grass. Peaks are NelvarMountainPainter's.
##
## Stateless: one painter can paint from many worker threads at once.

const Kind = NelvarEarthData.Kind
const Species = NelvarEarthData.Species
const STEP := NelvarEarthData.PIXEL

# Palettes of the menu's earth reality (tools/gen_menu_backgrounds.py, earth()), dark to light.
const LEAVES: Array[Color] = [Color8(34, 84, 56), Color8(46, 108, 62), Color8(64, 134, 68),
	Color8(92, 160, 76), Color8(136, 188, 92)]
const OUTLINE := Color8(26, 50, 40)
const BARK: Array[Color] = [Color8(74, 50, 40), Color8(98, 68, 50), Color8(124, 88, 62),
	Color8(150, 110, 78)]
const BIRCH_LEAVES: Array[Color] = [Color8(62, 112, 58), Color8(86, 140, 62), Color8(120, 168, 72),
	Color8(160, 194, 96), Color8(204, 222, 134)]
const BIRCH_BARK: Array[Color] = [Color8(168, 164, 154), Color8(208, 204, 192), Color8(236, 234, 224)]
const BIRCH_MARK := Color8(46, 44, 48)
const NEEDLES: Array[Color] = [Color8(26, 62, 52), Color8(36, 82, 60), Color8(50, 102, 66),
	Color8(72, 126, 74), Color8(104, 150, 86)]
const PINE_OUTLINE := Color8(18, 38, 34)
const SNOW: Array[Color] = [Color8(176, 196, 214), Color8(214, 226, 236), Color8(244, 248, 250)]
const BLOSSOM: Array[Color] = [Color8(170, 92, 122), Color8(206, 126, 154), Color8(234, 164, 186),
	Color8(248, 200, 214), Color8(255, 234, 240)]
const BLOSSOM_OUTLINE := Color8(98, 52, 72)
const PETAL := Color8(255, 244, 248)
const APPLE_LEAVES: Array[Color] = [Color8(38, 94, 58), Color8(54, 120, 64), Color8(76, 146, 72),
	Color8(106, 170, 82), Color8(150, 198, 100)]
const APPLE: Array[Color] = [Color8(150, 30, 40), Color8(196, 52, 52), Color8(238, 112, 100)]
const WILLOW_LEAVES: Array[Color] = [Color8(50, 98, 64), Color8(68, 122, 70), Color8(94, 148, 78),
	Color8(130, 174, 92), Color8(172, 200, 118)]
const WILLOW_BARK: Array[Color] = [Color8(80, 66, 54), Color8(106, 88, 70), Color8(134, 112, 86)]
const GOLD: Array[Color] = [Color8(142, 78, 40), Color8(192, 112, 44), Color8(224, 154, 58),
	Color8(240, 196, 92), Color8(250, 228, 150)]
const GOLD_OUTLINE := Color8(92, 50, 30)
# The menu's petrified creature and pebbles.
const STONE: Array[Color] = [Color8(84, 88, 92), Color8(112, 114, 112), Color8(142, 142, 132),
	Color8(170, 168, 150), Color8(196, 192, 170)]
const STONE_OUTLINE := Color8(46, 50, 54)
const STONE_CRACK := Color8(66, 70, 72)
## Olive moss: yellower than the grass, so a mossy top still reads against it.
const MOSS: Array[Color] = [Color8(78, 108, 50), Color8(112, 140, 58), Color8(150, 172, 78)]
const MOSS_EDGE := Color8(40, 66, 40)
const WOOD_TOP: Array[Color] = [Color8(150, 110, 72), Color8(190, 150, 100), Color8(222, 186, 132)]
const WOOD_RING := Color8(132, 94, 62)
const BERRY := Color8(214, 72, 84)
const BUSH_BLOSSOM: Array[Color] = [Color8(250, 246, 238), Color8(244, 188, 206)]
const GRASS_BLADES: Array[Color] = [Color8(30, 70, 46), Color8(44, 92, 52), Color8(62, 116, 58),
	Color8(98, 152, 72), Color8(136, 188, 92)]
const SEED_HEAD: Array[Color] = [Color8(170, 150, 90), Color8(214, 196, 124)]
const FERN: Array[Color] = [Color8(32, 86, 54), Color8(48, 112, 60), Color8(74, 142, 70),
	Color8(112, 172, 84)]
const STEM := Color8(52, 106, 56)
const DAISY := Color8(246, 246, 238)
const DAISY_CENTER := Color8(238, 204, 80)
const POPPY: Array[Color] = [Color8(170, 34, 40), Color8(222, 66, 58), Color8(246, 120, 96)]
const LUPINE: Array[Color] = [Color8(92, 82, 176), Color8(128, 116, 214), Color8(170, 160, 238),
	Color8(214, 206, 250)]
const LUPINE_PINK: Array[Color] = [Color8(156, 70, 128), Color8(204, 104, 164), Color8(234, 152, 196),
	Color8(250, 206, 228)]
const BUTTERCUP: Array[Color] = [Color8(220, 172, 40), Color8(246, 214, 76), Color8(255, 240, 150)]
const AGARIC: Array[Color] = [Color8(150, 30, 36), Color8(198, 48, 46), Color8(230, 88, 72)]
const MUSHROOM_STEM: Array[Color] = [Color8(196, 186, 168), Color8(232, 226, 210)]
const BROWN_CAP: Array[Color] = [Color8(110, 70, 46), Color8(150, 102, 64), Color8(194, 148, 100)]
const PALE_CAP: Array[Color] = [Color8(184, 172, 150), Color8(226, 216, 194), Color8(246, 240, 226)]
const REED: Array[Color] = [Color8(38, 84, 54), Color8(56, 108, 60), Color8(96, 146, 76),
	Color8(172, 188, 118)]
const CATTAIL: Array[Color] = [Color8(92, 58, 36), Color8(130, 86, 52)]
const RIPPLE := Color(0.82, 0.92, 0.95, 0.45)
const LILY: Array[Color] = [Color8(40, 100, 58), Color8(60, 132, 68), Color8(96, 164, 84),
	Color8(136, 190, 104)]
const LILY_OUTLINE := Color8(28, 68, 52)
const LILY_FLOWER: Array[Color] = [Color8(212, 150, 186), Color8(236, 196, 220), Color8(255, 240, 246)]

## Crown lumps (x, y, radius x, radius y) of the menu's round tree, in its pixels.
const ROUND_LUMPS: Array[Vector4] = [Vector4(0, -9, 13, 10), Vector4(-10, -2, 9, 7),
	Vector4(10, -3, 10, 7), Vector4(-5, -16, 8, 6), Vector4(7, -15, 8, 6), Vector4(0, 2, 11, 6),
	Vector4(-13, 3, 6, 5), Vector4(13, 3, 6, 5)]
const BROAD_LUMPS: Array[Vector4] = [Vector4(0, -8, 14, 8), Vector4(-12, -2, 10, 6),
	Vector4(12, -2, 10, 6), Vector4(-6, -13, 9, 6), Vector4(7, -13, 9, 6), Vector4(0, 2, 13, 5),
	Vector4(-17, 2, 6, 4), Vector4(17, 2, 6, 4)]
const TALL_LUMPS: Array[Vector4] = [Vector4(0, -12, 11, 10), Vector4(-8, -3, 9, 8),
	Vector4(8, -4, 9, 8), Vector4(-4, -21, 8, 7), Vector4(5, -20, 8, 7), Vector4(0, 3, 10, 6),
	Vector4(0, -27, 6, 5)]
const BUSH_LUMPS: Array[Vector4] = [Vector4(-5, -4, 6, 5), Vector4(5, -4, 6, 5), Vector4(0, -7, 7, 6)]


func paint(thing: NelvarEarthData.Thing) -> NelvarEarthArt:
	var rng := RandomNumberGenerator.new()
	rng.seed = thing.appearance_seed
	var art: NelvarEarthArt
	match thing.kind:
		Kind.TREE:
			art = _tree(thing, rng)
		Kind.ROCK:
			art = _rock(thing, rng)
		Kind.STATUE:
			art = _statue(thing, rng)
		Kind.STUMP:
			art = _stump(thing, rng)
		Kind.LOG:
			art = _log(thing, rng)
		Kind.BUSH:
			art = _bush(thing, rng)
		Kind.TALL_GRASS:
			art = _tall_grass(thing, rng)
		Kind.FERN:
			art = _fern(thing, rng)
		Kind.FLOWERS:
			art = _flowers(thing, rng)
		Kind.MUSHROOMS:
			art = _mushrooms(thing, rng)
		Kind.REEDS:
			art = _reeds(thing, rng)
		Kind.LILY:
			art = _lily(thing, rng)
		Kind.PEAK:
			art = NelvarMountainPainter.new().paint(thing)
	return art


# --- Trees ----------------------------------------------------------------------

func _tree(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	match thing.variant:
		Species.BIRCH:
			return _birch(thing, rng)
		Species.PINE:
			return _pine(thing, rng)
		Species.WILLOW:
			return _willow(thing, rng)
	var leaves := LEAVES
	var outline := OUTLINE
	var lumps := ROUND_LUMPS
	match thing.variant:
		Species.OAK:
			var shapes: Array = [ROUND_LUMPS, ROUND_LUMPS, BROAD_LUMPS, TALL_LUMPS]
			lumps = shapes[rng.randi_range(0, shapes.size() - 1)]
			# Each oak a little warmer, cooler or darker than the next.
			var tints := [Color8(150, 190, 80), Color8(60, 120, 110), Color8(30, 60, 40)]
			leaves = NelvarEarthCanvas.tinted(LEAVES, tints[rng.randi_range(0, 2)], rng.randf_range(0.0, 0.12))
		Species.BLOSSOM:
			leaves = BLOSSOM
			outline = BLOSSOM_OUTLINE
		Species.APPLE:
			leaves = APPLE_LEAVES
		Species.MAPLE:
			leaves = GOLD
			outline = GOLD_OUTLINE
			lumps = BROAD_LUMPS if rng.randf() < 0.5 else ROUND_LUMPS
	var canvas := _round_tree(thing, rng, lumps, leaves, outline, BARK)
	var crown := canvas.interior()
	match thing.variant:
		Species.BLOSSOM:
			for i in rng.randi_range(16, 28):
				var p := crown[rng.randi_range(0, crown.size() - 1)]
				canvas.image.set_pixelv(p, PETAL)
			_litter(canvas, thing, rng, [BLOSSOM[3], PETAL], 10)
		Species.APPLE:
			for i in rng.randi_range(8, 14):
				var p := crown[rng.randi_range(0, crown.size() - 1)]
				_apple(canvas, p)
			_litter(canvas, thing, rng, [APPLE[1]], 2)
		Species.MAPLE:
			_litter(canvas, thing, rng, [GOLD[2], GOLD[1], GOLD[3]], 12)
	var art := NelvarEarthArt.from_canvas(canvas)
	art.sway = 1
	return art


## The menu's round tree: a short trunk under a crown of overlapping lit lumps.
func _round_tree(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator, lumps: Array[Vector4],
		leaves: Array[Color], outline: Color, bark: Array[Color]) -> NelvarEarthCanvas:
	var crown := thing.size.x / STEP
	var total := thing.size.y / STEP
	var s := crown / 23.0
	var top := -total + 22.0 * s
	var trunk := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position,
		Rect2(-crown * 1.35 - 3.0, -total - 4.0, crown * 2.7 + 6.0, total + 8.0))
	canvas.shadow(Vector2(-trunk * 0.4, 0.5), Vector2(crown * 0.72, maxf(2.5, trunk * 0.55)))
	canvas.trunk(0.0, top + 4.0 * s, 0.0, maxf(1.5, trunk * 0.55), bark, outline, rng.randi() & 0xffff)
	var order := lumps.duplicate()
	order.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.y > b.y)
	for lump: Vector4 in order:
		var center := Vector2(lump.x + rng.randf_range(-1.5, 1.5), lump.y + rng.randf_range(-1.0, 1.0)) * s
		var axes := Vector2(lump.z, lump.w) * s * rng.randf_range(0.88, 1.12)
		var b := NelvarEarthCanvas.make_blob(rng, center + Vector2(0, top), axes, 0.0, 0.22, 2.0, 0.16)
		b.rim = outline
		canvas.blob(b, leaves)
	return canvas


func _apple(canvas: NelvarEarthCanvas, p: Vector2i) -> void:
	canvas.image.set_pixelv(p, APPLE[1])
	if canvas.is_body(p.x + 1, p.y):
		canvas.image.set_pixel(p.x + 1, p.y, APPLE[2])
	if canvas.is_body(p.x, p.y + 1):
		canvas.image.set_pixel(p.x, p.y + 1, APPLE[0])


## Petals, leaves or fruit fallen round the trunk, on the shadow.
func _litter(canvas: NelvarEarthCanvas, thing: NelvarEarthData.Thing, rng: RandomNumberGenerator,
		colors: Array, count: int) -> void:
	var reach := Vector2(thing.size.x / STEP * 0.75, 3.0)
	for i in count:
		var point := Vector2(rng.randf_range(-1.0, 1.0) * reach.x, rng.randf_range(-1.0, 1.0) * reach.y)
		var p := canvas.pixel(point)
		if canvas.inside(p.x, p.y) and not canvas.is_body(p.x, p.y):
			canvas.image.set_pixelv(p, colors[rng.randi_range(0, colors.size() - 1)])


## Slender white trunk with black marks under an airy crown of small light lumps.
func _birch(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var crown := thing.size.x / STEP
	var total := thing.size.y / STEP
	var canvas := NelvarEarthCanvas.new(thing.position,
		Rect2(-crown * 1.3 - 3.0, -total - 4.0, crown * 2.6 + 6.0, total + 8.0))
	var trunk := maxf(1.2, thing.radius / STEP * 0.45)
	canvas.shadow(Vector2(-1.0, 0.5), Vector2(crown * 0.8, 2.6))
	var crown_center := Vector2(rng.randf_range(-1.0, 1.0), -total + crown * 1.15)
	var lean := rng.randf_range(-1.5, 2.5)
	canvas.trunk(0.0, crown_center.y - crown * 0.4, 0.0, trunk, BIRCH_BARK, OUTLINE,
		rng.randi() & 0xffff, true, lean)
	# Black lenticels across the bark.
	var from := canvas.pixel(Vector2(0, crown_center.y))
	var to := canvas.pixel(Vector2(0, -2.0))
	for y in range(from.y, to.y):
		if rng.randf() < 0.3:
			var at := canvas.center_of(0, y).y
			var progress := clampf(-at / maxf(1.0, -crown_center.y), 0.0, 1.0)
			var x := canvas.pixel(Vector2(lean * progress * progress + rng.randf_range(-trunk, trunk), at)).x
			if canvas.is_body(x, y):
				canvas.image.set_pixel(x, y, BIRCH_MARK)
	var lumps := rng.randi_range(7, 10)
	var blobs: Array[NelvarEarthCanvas.Blob] = []
	for i in lumps:
		var angle := rng.randf() * TAU
		var spot := crown_center + Vector2(cos(angle) * crown * 0.62, sin(angle) * crown * 0.95) \
			* sqrt(rng.randf())
		var b := NelvarEarthCanvas.make_blob(rng, spot,
			Vector2(crown * rng.randf_range(0.38, 0.5), crown * rng.randf_range(0.3, 0.4)), 0.02, 0.2, 2.0, 0.18)
		b.rim = OUTLINE
		blobs.append(b)
	blobs.sort_custom(func(a: NelvarEarthCanvas.Blob, b: NelvarEarthCanvas.Blob) -> bool:
		return a.center.y > b.center.y)
	for b in blobs:
		canvas.blob(b, BIRCH_LEAVES)
	var art := NelvarEarthArt.from_canvas(canvas)
	art.sway = 1
	return art


## The menu's pine (from the ice reality) in summer green; near the snow it keeps a dusting.
func _pine(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var half := thing.size.x / STEP
	var total := thing.size.y / STEP
	var canvas := NelvarEarthCanvas.new(thing.position,
		Rect2(-half - 4.0, -total - 4.0, half * 2.0 + 8.0, total + 8.0))
	canvas.shadow(Vector2(-1.0, 0.5), Vector2(half * 0.85, 2.8))
	var trunk_height := total * 0.14
	var salt := rng.randi() & 0xffff
	canvas.trunk(0.0, -trunk_height - 4.0, 0.0, maxf(1.2, thing.radius / STEP * 0.42), BARK, PINE_OUTLINE, salt)
	var tiers := 5 if total > 54.0 else 4
	var crown := total - trunk_height
	for i in tiers:
		var tier_top := -total + i * crown * 0.2
		var tier_height := crown * (0.3 + i * 0.035)
		var width := half * (0.34 + 0.66 * float(i) / (tiers - 1))
		var rows := int(tier_height)
		for k in rows:
			var frac := float(k) / tier_height
			var y := canvas.pixel(Vector2(0, tier_top + k)).y
			var wiggle := (NelvarPixelArt.value_noise(k * 0.7, i, salt) - 0.5) * 2.0
			var reach := width * pow(frac, 0.85) + wiggle
			var left := canvas.pixel(Vector2(-reach, 0)).x
			var right := canvas.pixel(Vector2(reach, 0)).x
			var snow_rows := maxf(2.0, tier_height * 0.28)
			for x in range(left, right + 1):
				var u := (canvas.center_of(x, y).x) / maxf(1.0, reach)
				var level := 0.45 + u * 0.35 - frac * 0.25 + canvas.grain(x, y, 0.6, salt + i) * 0.8
				var color := canvas.ramp(NEEDLES, level, x, y)
				if thing.accent:
					var drift := (NelvarPixelArt.value_noise(x * 0.5, i, salt + 9) - 0.5) * 2.5
					if k < snow_rows * (1.0 - absf(u) * 0.5) + drift:
						color = canvas.ramp(SNOW, level + 0.25, x, y)
				if x == left:
					color = PINE_OUTLINE if not (thing.accent and k < snow_rows) else SNOW[0]
				elif k == rows - 1 and level < 0.55:
					color = PINE_OUTLINE
				canvas.put(x, y, color, level)
	var art := NelvarEarthArt.from_canvas(canvas)
	art.sway = 1
	return art


## A wide dome with long strands of leaves hanging down to the grass.
func _willow(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var crown := thing.size.x / STEP
	var total := thing.size.y / STEP
	var canvas := NelvarEarthCanvas.new(thing.position,
		Rect2(-crown * 1.3 - 3.0, -total - 4.0, crown * 2.6 + 6.0, total + 8.0))
	canvas.shadow(Vector2(-1.0, 0.5), Vector2(crown * 0.85, 3.2))
	var dome_center := Vector2(0.0, -total + crown * 0.55)
	var lean := rng.randf_range(-3.0, 3.0)
	canvas.trunk(0.0, dome_center.y, 0.0, maxf(1.8, thing.radius / STEP * 0.6), WILLOW_BARK, OUTLINE,
		rng.randi() & 0xffff, true, lean)
	var lumps := [Vector4(0, 0, 0.62, 0.5), Vector4(-0.55, 0.22, 0.45, 0.36),
		Vector4(0.55, 0.2, 0.45, 0.36), Vector4(-0.25, -0.3, 0.42, 0.34), Vector4(0.3, -0.28, 0.42, 0.34)]
	lumps.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.y > b.y)
	for lump: Vector4 in lumps:
		var b := NelvarEarthCanvas.make_blob(rng, dome_center + Vector2(lump.x, lump.y) * crown,
			Vector2(lump.z, lump.w) * crown * rng.randf_range(0.92, 1.08), 0.0, 0.2, 2.0, 0.14)
		b.rim = OUTLINE
		canvas.blob(b, WILLOW_LEAVES)
	# Strands from the lower edge of the dome; a few gaps show the trunk.
	var salt := rng.randi() & 0xffff
	var left := canvas.pixel(Vector2(-crown * 1.05, 0)).x
	var right := canvas.pixel(Vector2(crown * 1.05, 0)).x
	for x in range(left, right + 1):
		if rng.randf() < 0.22:
			continue
		var bottom := -1
		for y in canvas.size.y:
			if canvas.is_body(x, y) and canvas.center_of(x, y).y < dome_center.y + crown * 0.6:
				bottom = y
		if bottom < 0:
			continue
		var u := canvas.center_of(x, 0).x / crown
		var length := int(total * rng.randf_range(0.32, 0.56) * (1.0 - absf(u) * 0.25))
		var drift := signf(u) * rng.randf_range(0.0, 0.12)
		for k in length:
			var px := x + int(round(drift * k))
			var py := bottom + k
			var level := 0.42 + u * 0.3 - float(k) / length * 0.25 + canvas.grain(px, py, 0.5, salt) * 0.4
			var color := canvas.ramp(WILLOW_LEAVES, level, px, py)
			if k == length - 1:
				color = WILLOW_LEAVES[3]
			canvas.put(px, py, color, level)
	var art := NelvarEarthArt.from_canvas(canvas)
	art.sway = 2
	return art


# --- Stone ----------------------------------------------------------------------

## A boulder: the main body, sometimes a lower shoulder behind it and a smaller stone on top.
func _rock(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.4 - 3.0, -r * 2.0 - 4.0,
		r * 2.8 + 6.0, r * 2.4 + 6.0))
	canvas.shadow(Vector2(-r * 0.12, r * 0.08), Vector2(r * 1.15, r * 0.5 + 0.5))
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var tall := rng.randf_range(0.85, 1.1)
	var base := 0.5 - 0.72 * tall
	if r >= 5.0 and rng.randf() < 0.6:
		canvas.blob(NelvarEarthCanvas.make_blob(rng, Vector2(-side * 0.42, 0.0) * r,
			Vector2(0.55, 0.55) * r, -0.12, 0.14, 0.7), STONE)
	canvas.blob(NelvarEarthCanvas.make_blob(rng, Vector2(rng.randf_range(-0.06, 0.06), base) * r,
		Vector2(0.92, tall) * r, -0.06, 0.14, 0.72), STONE)
	if r >= 6.0 and rng.randf() < 0.45:
		canvas.blob(NelvarEarthCanvas.make_blob(rng, Vector2(side * 0.28, base - tall * 0.8) * r,
			Vector2(0.46, 0.4) * r, 0.04, 0.12, 0.85), STONE)
	canvas.outline_silhouette(STONE_OUTLINE, 0.7)
	if r >= 5.0:
		_cracks(canvas, rng, rng.randi_range(1, 2))
	if thing.accent and r >= 5.0:
		_moss_cap(canvas, rng.randi() & 0xffff, 2.5)
	return NelvarEarthArt.from_canvas(canvas)


func _cracks(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, count: int) -> void:
	var inner := canvas.interior()
	if inner.is_empty():
		return
	for crack in count:
		var p := inner[rng.randi_range(0, inner.size() - 1)]
		for length in rng.randi_range(2, 5):
			if not canvas.is_body(p.x, p.y):
				break
			canvas.image.set_pixelv(p, STONE_CRACK)
			p += Vector2i(rng.randi_range(-1, 1), 1)


## Moss over the top of the stone, darker on the shaded left rim (the menu statue's cap).
func _moss_cap(canvas: NelvarEarthCanvas, salt: int, depth: float) -> void:
	for x in canvas.size.x:
		var rows := 0
		for y in canvas.size.y:
			if not canvas.is_body(x, y):
				if rows > 0:
					break
				continue
			var cell := canvas.grid + Vector2i(x, y)
			if rows > int(NelvarPixelArt.value_noise(cell.x * 0.35, 0.5, salt) * depth + 0.5) + 1:
				break
			var open_left := not canvas.is_body(x - 1, y)
			var level := 0.7 - (0.3 if open_left else 0.0) + canvas.grain(x, y, 0.5, salt + 3) * 0.4
			# A dark rim along the top keeps the moss apart from the grass behind.
			canvas.image.set_pixel(x, y, MOSS_EDGE if rows == 0 else canvas.ramp(MOSS, level, x, y))
			rows += 1


## The menu's petrified creature: a boulder body with a shoulder, a head with a closed
## eye, cracks and a cap of moss. Facing right, or left when `accent`.
func _statue(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var s := r / 17.0
	var facing := -1.0 if thing.accent else 1.0
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-46.0 * s - 3.0, -50.0 * s - 4.0,
		92.0 * s + 6.0, 56.0 * s + 6.0))
	canvas.shadow(Vector2(-2.0 * s, 1.0), Vector2(36.0 * s, 7.0 * s))
	# Menu coordinates: body centre 15 px above the ground line.
	canvas.blob(NelvarEarthCanvas.make_blob(rng, Vector2(-16.0 * facing, -20.0) * s, Vector2(13, 11) * s,
		-0.06, 0.14, 2.0, 0.12), STONE)
	canvas.blob(NelvarEarthCanvas.make_blob(rng, Vector2(0.0, -15.0) * s, Vector2(29, 18) * s,
		0.0, 0.14, 0.85, 0.12), STONE)
	canvas.blob(NelvarEarthCanvas.make_blob(rng, Vector2(18.0 * facing, -34.0) * s, Vector2(12, 10) * s,
		0.0, 0.12, 2.0, 0.12), STONE)
	canvas.outline_silhouette(STONE_OUTLINE, 0.62)
	_cracks(canvas, rng, 3)
	_moss_cap(canvas, rng.randi() & 0xffff, 3.5)
	# The closed eyelid with a few lashes.
	var eye := Vector2(20.0 * facing, -34.0) * s
	var half := maxi(2, roundi(4.0 * s))
	var center := canvas.pixel(eye)
	for dx in range(-half, half + 1):
		canvas.put(center.x + dx, center.y + (1 if absi(dx) == half else 0), STONE_OUTLINE, 0.0)
	for dx in [-half + 1, 0, half - 1]:
		canvas.image.set_pixel(center.x + dx, center.y + 1, STONE_OUTLINE.lerp(STONE[1], 0.5))
	var art := NelvarEarthArt.from_canvas(canvas)
	art.eye = canvas.center_of(center.x, center.y) - Vector2(0.5, 0.5)
	return art


# --- Wood -----------------------------------------------------------------------

func _stump(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var height := r * rng.randf_range(0.8, 1.15)
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r - 4.0, -height - r * 0.6 - 3.0,
		r * 2.0 + 8.0, height + r * 0.6 + 6.0))
	canvas.shadow(Vector2(-r * 0.2, 0.5), Vector2(r * 1.3, r * 0.45 + 0.5))
	var salt := rng.randi() & 0xffff
	canvas.trunk(0.0, -height, 0.0, r, BARK, OUTLINE, salt, true)
	# The cut: an ellipse of pale wood with rings.
	var top := Vector2(0.0, -height)
	var axes := Vector2(r + 0.5, r * 0.42 + 0.5)
	var from := canvas.pixel(top - axes)
	var to := canvas.pixel(top + axes)
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var d := ((canvas.center_of(x, y) - top) / axes).length()
			if d > 1.0:
				continue
			var level := 0.55 + (canvas.center_of(x, y).x - top.x) / axes.x * 0.25 \
				+ canvas.grain(x, y, 0.6, salt) * 0.3
			var color := canvas.ramp(WOOD_TOP, level, x, y)
			if d > 0.82:
				color = BARK[2] if canvas.center_of(x, y).y < top.y else BARK[1]
			elif absf(d - 0.55) < 0.12 or absf(d - 0.25) < 0.1:
				color = WOOD_RING
			canvas.put(x, y, color, level)
	if thing.accent:
		_moss_cap(canvas, salt + 11, 1.5)
	return NelvarEarthArt.from_canvas(canvas)


## A fallen trunk lying across the grass, its cut end towards the light.
func _log(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var half := thing.size.x / STEP * 0.5
	var r := thing.radius / STEP * 0.9
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-half - 4.0, -r * 2.0 - 4.0,
		half * 2.0 + 8.0, r * 2.0 + 7.0))
	canvas.shadow(Vector2(-1.0, 0.0), Vector2(half + 2.0, r * 0.7 + 0.5))
	var salt := rng.randi() & 0xffff
	var center_y := -r
	var from := canvas.pixel(Vector2(-half, -r * 2.0))
	var to := canvas.pixel(Vector2(half, 0.0))
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var p := canvas.center_of(x, y)
			var v := (p.y - center_y) / r
			if absf(v) > 1.0:
				continue
			# The left end is rounded off; the right is the cut face.
			if p.x < -half + r * 0.4 * (1.0 - sqrt(maxf(0.0, 1.0 - v * v))) * 2.0:
				continue
			var level := 0.72 - (v + 1.0) * 0.32 + canvas.grain(x, y, 0.25, salt) * 0.35 \
				+ (NelvarPixelArt.value_noise(x * 0.15, y * 1.2, salt + 1) - 0.5) * 0.3
			var color := canvas.ramp(BARK, level, x, y)
			if v > 0.78 or p.x < -half + 1.0:
				color = OUTLINE
			canvas.put(x, y, color, level)
	var cut := Vector2(half - r * 0.25, center_y)
	var axes := Vector2(r * 0.5 + 0.5, r + 0.3)
	var cut_from := canvas.pixel(cut - axes)
	var cut_to := canvas.pixel(cut + axes)
	for y in range(cut_from.y, cut_to.y + 1):
		for x in range(cut_from.x, cut_to.x + 1):
			var d := ((canvas.center_of(x, y) - cut) / axes).length()
			if d > 1.0:
				continue
			var color := canvas.ramp(WOOD_TOP, 0.6 + canvas.grain(x, y, 0.6, salt + 2) * 0.3, x, y)
			if d > 0.8:
				color = BARK[1]
			elif absf(d - 0.45) < 0.14:
				color = WOOD_RING
			canvas.put(x, y, color, 0.6)
	if thing.accent:
		for i in rng.randi_range(3, 6):
			var x := canvas.pixel(Vector2(rng.randf_range(-half * 0.8, half * 0.5), 0)).x
			for y in canvas.size.y:
				if canvas.is_body(x, y):
					canvas.image.set_pixel(x, y, MOSS[rng.randi_range(1, 2)])
					if canvas.is_body(x + 1, y):
						canvas.image.set_pixel(x + 1, y, MOSS[0])
					break
	return NelvarEarthArt.from_canvas(canvas)


# --- Plants ---------------------------------------------------------------------

## The menu's bush: three lit clumps, some with red berries or pale blossoms.
func _bush(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var s := r / 11.0
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.3 - 3.0, -r * 1.4 - 3.0,
		r * 2.6 + 6.0, r * 1.4 + 6.0))
	canvas.shadow(Vector2(-1.0, 0.5), Vector2(r * 1.05, r * 0.25 + 1.0))
	# A deeper green than the grass around, so the bush reads against it.
	var leaves := NelvarEarthCanvas.tinted(LEAVES, Color8(20, 56, 44), rng.randf_range(0.18, 0.3))
	for lump in BUSH_LUMPS:
		var jitter := Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.6, 0.6))
		var b := NelvarEarthCanvas.make_blob(rng, (Vector2(lump.x, lump.y) + jitter) * s,
			Vector2(lump.z, lump.w) * s * rng.randf_range(0.9, 1.1), 0.0, 0.2, 0.7, 0.15)
		b.rim = OUTLINE
		canvas.blob(b, leaves)
	var inner := canvas.interior()
	if not inner.is_empty():
		if thing.variant == 1:
			for i in rng.randi_range(5, 9):
				canvas.image.set_pixelv(inner[rng.randi_range(0, inner.size() - 1)], BERRY)
		elif thing.variant == 2:
			var color := BUSH_BLOSSOM[rng.randi_range(0, 1)]
			for i in rng.randi_range(5, 9):
				canvas.image.set_pixelv(inner[rng.randi_range(0, inner.size() - 1)], color)
	var art := NelvarEarthArt.from_canvas(canvas)
	art.sway = 1
	return art


## A clump of long blades bending outwards and with the wind; some carry seed heads.
func _tall_grass(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var height := r * rng.randf_range(2.0, 2.8)
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.6 - 3.0, -height - 3.0,
		r * 3.2 + 6.0, height + 6.0))
	canvas.shadow(Vector2(-0.5, 0.5), Vector2(r * 0.9, 1.6))
	var blades := rng.randi_range(9, 14)
	var specs: Array[Vector3] = []
	for i in blades:
		var base := rng.randf_range(-1.0, 1.0)
		base = base * absf(base) * r
		var tall := height * rng.randf_range(0.55, 1.0) * (1.0 - absf(base) / r * 0.35)
		specs.append(Vector3(base, tall, base / r * 0.5 + rng.randf_range(-0.2, 0.45)))
	# Taller blades behind, shorter in front.
	specs.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y > b.y)
	for spec in specs:
		var length := int(spec.y)
		var seeds := thing.variant == 2 and rng.randf() < 0.6
		for k in length:
			var t := float(k) / maxf(1.0, spec.y)
			var point := Vector2(spec.x + spec.z * t * t * spec.y * 0.45, -0.5 - k)
			var level := 0.15 + t * 0.75
			var color := canvas.ramp(GRASS_BLADES, level, canvas.pixel(point).x, canvas.pixel(point).y)
			if seeds and k >= length - 2:
				color = SEED_HEAD[1] if k == length - 1 else SEED_HEAD[0]
			canvas.put_at(point, color, level)
	var art := NelvarEarthArt.from_canvas(canvas)
	art.sway = 2
	return art


## Fronds fanning up and out, drooping at the tips, with leaflets along them.
func _fern(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 2.0 - 3.0, -r * 1.8 - 3.0,
		r * 4.0 + 6.0, r * 1.8 + 6.0))
	canvas.shadow(Vector2(-0.5, 0.5), Vector2(r * 1.2, 2.0))
	var fronds := rng.randi_range(5, 7)
	for i in fronds:
		var angle := lerpf(-PI + 0.35, -0.35, (float(i) + rng.randf_range(-0.2, 0.2)) / (fronds - 1))
		var length := r * rng.randf_range(1.3, 1.8) * (1.0 - absf(angle + PI * 0.5) * 0.2)
		var direction := Vector2.from_angle(angle)
		var steps := int(length * 1.4)
		for k in steps:
			var t := float(k) / steps
			# The tip bows down under its own weight.
			var point := direction * t * length + Vector2(0, t * t * length * 0.55)
			var lit := 0.3 + 0.4 * (direction.x * 0.5 + 0.5) + t * 0.2
			canvas.put_at(point, canvas.ramp(FERN, lit, 0, 0), lit)
			if k % 2 == 0 and t > 0.12 and t < 0.92:
				var side := direction.orthogonal()
				var leaf := maxf(1.0, (1.0 - t) * 2.2)
				canvas.put_at(point + side * leaf, FERN[mini(3, 1 + int(lit * 3.0))], lit)
				canvas.put_at(point - side * leaf, FERN[1], lit)
	var art := NelvarEarthArt.from_canvas(canvas)
	art.sway = 1
	return art


## A few flowers on short stems over a tuft of leaves: daisies, poppies, lupines or buttercups.
func _flowers(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r - 4.0, -r * 2.6 - 6.0,
		r * 2.0 + 8.0, r * 2.6 + 9.0))
	for i in rng.randi_range(5, 8):
		var leaf := Vector2(rng.randf_range(-r * 0.8, r * 0.8), rng.randf_range(-1.5, 0.0))
		canvas.put_at(leaf, GRASS_BLADES[rng.randi_range(1, 3)], 0.4)
		canvas.put_at(leaf + Vector2(signf(leaf.x), -1.0), GRASS_BLADES[2], 0.4)
	var count := rng.randi_range(3, 6) if thing.variant != 3 else rng.randi_range(6, 10)
	for i in count:
		var base := Vector2(rng.randf_range(-r * 0.85, r * 0.85), rng.randf_range(-1.0, 0.5))
		match thing.variant:
			0, 1:
				var stem := rng.randi_range(2, 5)
				for k in stem:
					canvas.put_at(base + Vector2(0, -k), STEM, 0.4)
				var head := base + Vector2(0, -stem)
				if thing.variant == 0:
					for offset: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
						canvas.put_at(head + offset, DAISY, 0.9)
					canvas.put_at(head, DAISY_CENTER, 0.9)
				else:
					canvas.put_at(head, POPPY[1], 0.8)
					canvas.put_at(head + Vector2(1, 0), POPPY[2], 0.9)
					canvas.put_at(head + Vector2(0, -1), POPPY[2], 0.9)
					canvas.put_at(head + Vector2(1, -1), POPPY[1], 0.8)
					canvas.put_at(head + Vector2(-1, 0), POPPY[0], 0.6)
			2:
				var colors := LUPINE if thing.accent else LUPINE_PINK
				var spike := rng.randi_range(5, 8)
				canvas.put_at(base, STEM, 0.4)
				for k in spike:
					var t := float(k) / spike
					var level := 0.2 + t * 0.75
					canvas.put_at(base + Vector2(0, -1 - k), NelvarPixelArt.ramp(colors, level,
						canvas.grid + canvas.pixel(base) + Vector2i(0, -k)), level)
					if k < spike - 2 and k % 2 == 0:
						canvas.put_at(base + Vector2(1, -1 - k), colors[1], level)
			3:
				var stem := rng.randi_range(1, 3)
				for k in stem:
					canvas.put_at(base + Vector2(0, -k), STEM, 0.4)
				canvas.put_at(base + Vector2(0, -stem), BUTTERCUP[1], 0.9)
				if rng.randf() < 0.5:
					canvas.put_at(base + Vector2(1, -stem), BUTTERCUP[2], 0.9)
	var art := NelvarEarthArt.from_canvas(canvas)
	art.sway = 1
	return art


## Fly agarics, brown caps or a cluster of tiny pale ones.
func _mushrooms(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r - 5.0, -r * 2.2 - 5.0,
		r * 2.0 + 10.0, r * 2.2 + 8.0))
	var count := rng.randi_range(1, 3) if thing.variant == 0 else rng.randi_range(2, 5)
	var caps := AGARIC if thing.variant == 0 else (BROWN_CAP if thing.variant == 1 else PALE_CAP)
	var spots: Array[Vector3] = []
	for i in count:
		var size := rng.randf_range(1.6, 2.8) if thing.variant == 0 else rng.randf_range(1.0, 2.0)
		spots.append(Vector3(rng.randf_range(-r * 0.7, r * 0.7), rng.randf_range(-1.0, 0.6), size))
	spots.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
	for spot in spots:
		var base := Vector2(spot.x, spot.y)
		var stem := int(spot.z * 1.3) + 1
		canvas.shadow(base + Vector2(-0.5, 0.5), Vector2(spot.z + 1.0, 1.0))
		for k in stem:
			canvas.put_at(base + Vector2(0, -k), MUSHROOM_STEM[1], 0.8)
			canvas.put_at(base + Vector2(-1, -k), MUSHROOM_STEM[0], 0.5)
		var cap := base + Vector2(0, -stem)
		var w := int(spot.z) + 1
		for dx in range(-w, w + 1):
			var rows := 2 if absi(dx) < w else 1
			for dy in rows:
				var level := 0.45 + float(dx) / w * 0.3 + 0.2 * (1 - dy)
				canvas.put_at(cap + Vector2(dx, -dy), canvas.ramp(caps, level, 0, 0), level)
		if thing.variant == 0:
			canvas.put_at(cap + Vector2(-1, -1), DAISY, 0.9)
			canvas.put_at(cap + Vector2(1, 0), DAISY, 0.9)
	return NelvarEarthArt.from_canvas(canvas)


## Reeds in the shallows; some carry brown cattail heads. A pale ripple rings the base.
func _reeds(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var height := r * rng.randf_range(2.6, 3.6)
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.3 - 3.0, -height - 3.0,
		r * 2.6 + 6.0, height + 6.0))
	for dx in range(-int(r) - 1, int(r) + 2):
		if absi(dx) > 1 and rng.randf() < 0.6:
			var p := canvas.pixel(Vector2(dx, 0.5))
			canvas.image.set_pixelv(p.clamp(Vector2i.ZERO, canvas.size - Vector2i.ONE), RIPPLE)
	for i in rng.randi_range(5, 8):
		var base := rng.randf_range(-r, r)
		var tall := height * rng.randf_range(0.6, 1.0)
		var lean := rng.randf_range(-0.15, 0.3)
		var head := thing.variant == 0 and rng.randf() < 0.6
		for k in int(tall):
			var t := k / tall
			var point := Vector2(base + lean * t * tall * 0.3, -k)
			var color := canvas.ramp(REED, 0.15 + t * 0.6, 0, 0)
			if head and k >= int(tall) - 5 and k < int(tall) - 1:
				color = CATTAIL[1] if k % 2 == 0 else CATTAIL[0]
			elif not head and k == int(tall) - 1:
				color = REED[3]
			canvas.put_at(point, color, t)
	var art := NelvarEarthArt.from_canvas(canvas)
	art.sway = 1
	return art


## A floating pad with a notch, sometimes with a pink flower.
func _lily(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r - 3.0, -r - 4.0, r * 2.0 + 6.0, r * 2.0 + 6.0))
	var axes := Vector2(r, r * 0.66)
	var notch := rng.randf() * TAU
	var salt := rng.randi() & 0xffff
	var from := canvas.pixel(-axes - Vector2.ONE)
	var to := canvas.pixel(axes + Vector2.ONE)
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var local := canvas.center_of(x, y) / axes
			if local.length() > 1.0:
				continue
			if local.length() > 0.2 and absf(angle_difference(local.angle(), notch)) < 0.32:
				continue
			var level := 0.5 + local.x * 0.2 - local.y * 0.25 + canvas.grain(x, y, 0.5, salt) * 0.3
			var color := canvas.ramp(LILY, level, x, y)
			if local.length() > 0.8 and local.y > 0.0:
				color = LILY_OUTLINE
			canvas.put(x, y, color, level)
	if thing.accent:
		var flower := Vector2(rng.randf_range(-0.3, 0.3) * r, -0.8)
		canvas.put_at(flower, LILY_FLOWER[1])
		canvas.put_at(flower + Vector2(1, 0), LILY_FLOWER[0])
		canvas.put_at(flower + Vector2(-1, 0), LILY_FLOWER[1])
		canvas.put_at(flower + Vector2(0, -1), LILY_FLOWER[2])
	return NelvarEarthArt.from_canvas(canvas)
