class_name NelvarFirePainter
extends RefCounted
## Bakes everything that stands in the fire forge in the style of the "Огонь" menu
## background: charred trunks with glowing seams, black basalt lit from the upper right
## with a near-black outline, grey ash, and the few colours the heat allows — the
## emberleaf's red crown, blue-green crystals, yellow sulfur. Ridges and volcanoes are
## NelvarVolcanoPainter's; the plateau's boulders are rocks.
##
## Glowing pixels are keyed by alpha (NelvarFireArt) and animated by
## fire_molten.gdshader. Stateless: one painter can paint from many threads at once.

const Kind = NelvarFireData.Kind
const Species = NelvarFireData.Species
const Stone = NelvarFireData.Stone
const STEP := NelvarFireData.PIXEL

# Palettes, dark to light (the menu's fire(): trunk_c, basalt, sprinkle).
const CHAR: Array[Color] = [Color8(20, 13, 15), Color8(32, 21, 23), Color8(46, 31, 31), Color8(64, 44, 42)]
const CHAR_OUTLINE := Color8(10, 6, 8)
const ASH_BARK: Array[Color] = [Color8(82, 76, 78), Color8(110, 102, 100), Color8(144, 136, 130),
	Color8(178, 170, 162)]
const ASH_OUTLINE := Color8(44, 38, 40)
const EMBERLEAF: Array[Color] = [Color8(104, 24, 26), Color8(150, 38, 30), Color8(196, 66, 36),
	Color8(232, 112, 50), Color8(252, 170, 86)]
const EMBERLEAF_OUTLINE := Color8(58, 14, 18)
const BASALT: Array[Color] = [Color8(34, 24, 28), Color8(48, 34, 36), Color8(64, 46, 46),
	Color8(84, 62, 58), Color8(108, 82, 72)]
const BASALT_OUTLINE := Color8(14, 8, 12)
const BASALT_CRACK := Color8(22, 14, 16)
## Glassy glints on obsidian-smooth stone.
const GLOSS := Color8(156, 140, 144)
const ASH: Array[Color] = [Color8(98, 92, 92), Color8(128, 120, 116), Color8(162, 154, 146),
	Color8(196, 188, 178)]
const ASH_EDGE := Color8(58, 52, 54)
const CRYSTAL: Array[Color] = [Color8(18, 64, 74), Color8(28, 104, 110), Color8(52, 152, 148),
	Color8(118, 212, 192), Color8(206, 248, 232)]
const CRYSTAL_PALE: Array[Color] = [Color8(30, 70, 92), Color8(46, 112, 136), Color8(82, 160, 180),
	Color8(150, 214, 224), Color8(226, 248, 250)]
const CRYSTAL_OUTLINE := Color8(10, 32, 40)
const SULFUR: Array[Color] = [Color8(150, 124, 34), Color8(204, 176, 54), Color8(236, 214, 92),
	Color8(250, 240, 160)]
const STALK: Array[Color] = [Color8(28, 20, 22), Color8(44, 30, 30), Color8(66, 44, 40)]
const PETAL: Array[Color] = [Color8(150, 144, 140), Color8(198, 192, 186), Color8(240, 236, 230)]
const PETAL_PINK: Array[Color] = [Color8(150, 118, 120), Color8(198, 160, 158), Color8(238, 206, 200)]
const SHRUB: Array[Color] = [Color8(38, 24, 24), Color8(56, 34, 30), Color8(80, 46, 38), Color8(108, 62, 46)]
const EMBER := Color8(226, 92, 40)
const HOT := Color8(255, 196, 96)
const CHARCOAL := Color8(26, 18, 20)
const ASH_FLECK := Color8(120, 112, 108)
## Ground shadow on ash and basalt.
const SHADOW := Color(0.04, 0.02, 0.03, 0.32)
const LITTER: Array[Color] = [ASH_FLECK, CHARCOAL]
const SOOT: Array[Color] = [ASH_FLECK, CHARCOAL, CHARCOAL]


func paint(thing: NelvarFireData.Thing) -> NelvarFireArt:
	var rng := RandomNumberGenerator.new()
	rng.seed = thing.appearance_seed
	match thing.kind:
		Kind.TREE:
			return _tree(thing, rng)
		Kind.SNAG:
			return _snag(thing, rng)
		Kind.LOG:
			return _log(thing, rng)
		Kind.ROCK:
			return _rock(thing, rng)
		Kind.CRYSTALS:
			return _crystals(thing, rng)
		Kind.VENT:
			return _vent(thing, rng)
		Kind.EMBER_GRASS:
			return _ember_grass(thing, rng)
		Kind.ASH_FLOWER:
			return _ash_flower(thing, rng)
		Kind.SHRUB:
			return _shrub(thing, rng)
	return null


## A boulder of the plateau beyond the ridges, as a rock of the basin.
func paint_boulder(peak: NelvarEarthData.Thing) -> NelvarFireArt:
	var rock := NelvarFireData.Thing.new()
	rock.kind = Kind.ROCK
	rock.position = peak.position
	rock.radius = peak.radius
	rock.appearance_seed = peak.appearance_seed
	rock.variant = Stone.EMBER if peak.accent else (Stone.ASHEN if peak.appearance_seed % 3 == 0 else Stone.PLAIN)
	return paint(rock)


static func _ember(canvas: NelvarEarthCanvas, x: int, y: int) -> void:
	canvas.put(x, y, NelvarFireArt.keyed(EMBER, NelvarFireArt.EMBER_KEY), 0.9)


static func _hot(canvas: NelvarEarthCanvas, x: int, y: int) -> void:
	canvas.put(x, y, NelvarFireArt.keyed(HOT, NelvarFireArt.HOT_KEY), 1.0)


func _shadow(canvas: NelvarEarthCanvas, center: Vector2, reach: Vector2) -> void:
	var from := canvas.pixel(center - reach)
	var to := canvas.pixel(center + reach)
	for y in range(maxi(0, from.y), mini(canvas.size.y, to.y + 1)):
		for x in range(maxi(0, from.x), mini(canvas.size.x, to.x + 1)):
			if canvas.is_body(x, y) or canvas.image.get_pixel(x, y).a > 0.0:
				continue
			var color := NelvarPixelArt.shadow_at(canvas.center_of(x, y), center, reach, canvas.grid + Vector2i(x, y))
			if color.a > 0.0:
				canvas.image.set_pixel(x, y, SHADOW)


## Ash flecks and bits of charcoal round the foot, on empty pixels.
func _litter(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, reach: Vector2, count: int,
		colors: Array[Color]) -> void:
	for i in count:
		var p := canvas.pixel(Vector2(rng.randf_range(-1.0, 1.0) * reach.x, rng.randf_range(-1.0, 1.0) * reach.y))
		if canvas.inside(p.x, p.y) and not canvas.is_body(p.x, p.y):
			canvas.image.set_pixelv(p, colors[rng.randi_range(0, colors.size() - 1)])


# --- Trees ----------------------------------------------------------------------

func _tree(thing: NelvarFireData.Thing, rng: RandomNumberGenerator) -> NelvarFireArt:
	match thing.variant:
		Species.SMOULDERING:
			return _smouldering(thing, rng)
		Species.EMBERLEAF:
			return _emberleaf(thing, rng)
		Species.ASHEN:
			return _bare_tree(thing, rng, ASH_BARK, ASH_OUTLINE, 0.0)
	return _bare_tree(thing, rng, CHAR, CHAR_OUTLINE, 0.45)


## The menu's burnt tree: a dark trunk and bare branches forking towards the sky; the
## charred ones keep embers at some tips and glowing seams in the bark, the ashen ones
## are grey all over.
func _bare_tree(thing: NelvarFireData.Thing, rng: RandomNumberGenerator, bark: Array[Color],
		outline: Color, embers: float) -> NelvarFireArt:
	var reach := thing.size.x / STEP
	var total := thing.size.y / STEP
	var trunk := maxf(1.5, thing.radius / STEP * 0.5)
	var canvas := NelvarEarthCanvas.new(thing.position,
		Rect2(-reach * 1.4 - 4.0, -total - 6.0, reach * 2.8 + 8.0, total + 10.0))
	_shadow(canvas, Vector2(-trunk * 0.4, 0.5), Vector2(reach * 0.55, maxf(2.5, trunk * 0.6)))
	var salt := rng.randi() & 0xffff
	var lean := rng.randf_range(-2.0, 2.0)
	var top := -total * rng.randf_range(0.62, 0.72)
	canvas.trunk(0.0, top, 0.0, trunk, bark, outline, salt, true, lean)
	var tips := PackedVector2Array()
	var crown_top := Vector2(lean, top)
	# The leader carries on up; two to four limbs leave the upper trunk.
	_branch(canvas, rng, crown_top + Vector2(0, 1), -PI * 0.5 + rng.randf_range(-0.2, 0.2),
		total * 0.3, 2, bark, tips)
	for i in rng.randi_range(2, 4):
		var side := -1.0 if i % 2 == 0 else 1.0
		var at := Vector2(lean * 0.8, top + rng.randf_range(0.0, total * 0.22))
		var angle := -PI * 0.5 + side * rng.randf_range(0.45, 1.05)
		_branch(canvas, rng, at, angle, reach * rng.randf_range(0.5, 0.8), 2, bark, tips)
	var art_sparks := PackedVector2Array()
	if embers > 0.0:
		for tip in tips:
			if rng.randf() < embers:
				var p := canvas.pixel(tip)
				_ember(canvas, p.x, p.y)
				if rng.randf() < 0.4:
					_hot(canvas, p.x, p.y - 1)
				art_sparks.append(tip)
		_seams(canvas, rng, top, trunk, lean, rng.randi_range(2, 3))
	_litter(canvas, rng, Vector2(reach * 0.6, 3.0), 10, LITTER)
	var art := NelvarFireArt.of(canvas)
	art.molten = embers > 0.0
	art.sparks = art_sparks
	return art


## A limb drawn as a line of pixels, thick at its base, bending a little as it grows
## and forking at its end; `tips` collects the ends.
func _branch(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, from: Vector2, angle: float,
		length: float, depth: int, bark: Array[Color], tips: PackedVector2Array) -> void:
	var bend := rng.randf_range(-0.03, 0.03)
	var point := from
	var steps := int(length / 0.7)
	for k in steps:
		angle += bend
		point += Vector2.from_angle(angle) * 0.7
		var lit := 0.35 + Vector2.from_angle(angle).x * 0.3 + float(depth) * 0.08
		var p := canvas.pixel(point)
		canvas.put(p.x, p.y, bark[clampi(int(lit * bark.size()), 0, bark.size() - 1)], lit)
		if depth >= 2 or (depth == 1 and k < steps * 0.5):
			canvas.put(p.x + 1, p.y, bark[mini(bark.size() - 1, 1 + int(lit * 2.0))], lit)
	if depth <= 0 or length < 3.0:
		tips.append(point)
		return
	for side: float in [-1.0, 1.0]:
		if depth == 1 and rng.randf() < 0.25:
			tips.append(point)
			continue
		_branch(canvas, rng, point, angle + side * rng.randf_range(0.32, 0.7),
			length * rng.randf_range(0.52, 0.68), depth - 1, bark, tips)


## Glowing seams in the bark: short jagged lines running up the trunk.
func _seams(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, top: float, trunk: float,
		lean: float, count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in count:
		var y := rng.randf_range(top + 3.0, -3.0)
		var progress := clampf(-y / maxf(1.0, -top), 0.0, 1.0)
		var x := lean * progress * progress + rng.randf_range(-trunk * 0.4, trunk * 0.5)
		for k in rng.randi_range(2, 5):
			var p := canvas.pixel(Vector2(x, y - k))
			if canvas.is_body(p.x, p.y):
				if k % 3 == 1:
					_hot(canvas, p.x, p.y)
				else:
					_ember(canvas, p.x, p.y)
			x += rng.randf_range(-0.6, 0.6)
		points.append(Vector2(x, y))
	return points


## A thick trunk split high up into two broken prongs, glowing where they snapped; its
## bark is split by glowing seams, a stub or two of limbs remain; smoke rises from the
## break of the accent ones.
func _smouldering(thing: NelvarFireData.Thing, rng: RandomNumberGenerator) -> NelvarFireArt:
	var reach := thing.size.x / STEP
	var total := thing.size.y / STEP
	var trunk := maxf(2.2, thing.radius / STEP * 0.75)
	var canvas := NelvarEarthCanvas.new(thing.position,
		Rect2(-reach * 1.4 - 5.0, -total - 6.0, reach * 2.8 + 10.0, total + 10.0))
	_shadow(canvas, Vector2(-trunk * 0.4, 0.5), Vector2(reach * 0.7, maxf(3.0, trunk * 0.7)))
	var salt := rng.randi() & 0xffff
	var lean := rng.randf_range(-1.5, 1.5)
	var fork := -total * rng.randf_range(0.66, 0.76)
	canvas.trunk(0.0, fork, 0.0, trunk, CHAR, CHAR_OUTLINE, salt, true, lean)
	var tips := PackedVector2Array()
	var sparks := PackedVector2Array()
	var vent := Vector2(lean, fork)
	for side: float in [-1.0, 1.0]:
		var height := total * (1.0 if side < 0.0 else rng.randf_range(0.8, 0.92))
		var x0 := lean + side * trunk * 0.5
		var prong := trunk * 0.5
		canvas.trunk(x0, -height, fork + 2.0, prong, CHAR, CHAR_OUTLINE, salt + int(side + 2.0), false,
			side * rng.randf_range(0.5, 2.0))
		var top := Vector2(x0 + side * 0.8, -height)
		_snapped(canvas, rng, top, prong)
		sparks.append(top)
		if side < 0.0:
			vent = top
	for i in rng.randi_range(1, 2):
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var at := Vector2(lean * 0.6, fork + rng.randf_range(4.0, -fork * 0.35))
		_branch(canvas, rng, at, -PI * 0.5 + side * rng.randf_range(0.7, 1.2),
			reach * rng.randf_range(0.6, 0.9), 1, CHAR, tips)
	sparks.append_array(_seams(canvas, rng, fork, trunk, lean, rng.randi_range(5, 8)))
	_litter(canvas, rng, Vector2(reach * 0.7, 3.0), 14, SOOT)
	var art := NelvarFireArt.of(canvas)
	art.molten = true
	art.sparks = sparks
	if thing.accent:
		art.vent = vent
	return art


## The jagged end of a snapped trunk, glowing inside.
func _snapped(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, top: Vector2, half_width: float) -> void:
	var left := canvas.pixel(top - Vector2(half_width + 1.0, 0)).x
	var right := canvas.pixel(top + Vector2(half_width + 1.0, 0)).x
	var row := canvas.pixel(top).y
	for x in range(left, right + 1):
		var bite := rng.randi_range(0, 2)
		for k in bite:
			if canvas.inside(x, row + k):
				canvas.image.set_pixel(x, row + k, Color(0, 0, 0, 0))
				canvas.body[(row + k) * canvas.size.x + x] = 0
		if canvas.is_body(x, row + bite) and x > left and x < right:
			if rng.randf() < 0.45:
				_hot(canvas, x, row + bite)
			else:
				_ember(canvas, x, row + bite)


## The tree that lives in the heat: a dark twisted trunk under a crown of red leaves
## glowing like coals; some of them have fallen, still warm.
func _emberleaf(thing: NelvarFireData.Thing, rng: RandomNumberGenerator) -> NelvarFireArt:
	var crown := thing.size.x / STEP
	var total := thing.size.y / STEP
	var s := crown / 23.0
	var top := -total + 22.0 * s
	var trunk := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position,
		Rect2(-crown * 1.35 - 3.0, -total - 4.0, crown * 2.7 + 6.0, total + 8.0))
	_shadow(canvas, Vector2(-trunk * 0.4, 0.5), Vector2(crown * 0.7, maxf(2.5, trunk * 0.55)))
	canvas.trunk(0.0, top + 4.0 * s, 0.0, maxf(1.5, trunk * 0.5), CHAR, CHAR_OUTLINE,
		rng.randi() & 0xffff, true, rng.randf_range(-3.0, 3.0))
	var lumps: Array[Vector4] = NelvarEarthPainter.ROUND_LUMPS if rng.randf() < 0.6 else NelvarEarthPainter.BROAD_LUMPS
	var order := lumps.duplicate()
	order.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.y > b.y)
	for lump: Vector4 in order:
		var center := Vector2(lump.x + rng.randf_range(-1.5, 1.5), lump.y + rng.randf_range(-1.0, 1.0)) * s
		var axes := Vector2(lump.z, lump.w) * s * rng.randf_range(0.82, 1.05)
		var b := NelvarEarthCanvas.make_blob(rng, center + Vector2(0, top), axes, -0.04, 0.24, 2.0, 0.2)
		b.rim = EMBERLEAF_OUTLINE
		canvas.blob(b, EMBERLEAF)
	# Leaves that glow: brighter where the crown is lit.
	var inner := canvas.interior()
	var sparks := PackedVector2Array()
	for i in rng.randi_range(14, 24):
		var p := inner[rng.randi_range(0, inner.size() - 1)]
		if canvas.levels[p.y * canvas.size.x + p.x] > 0.5 and rng.randf() < 0.4:
			_hot(canvas, p.x, p.y)
		else:
			_ember(canvas, p.x, p.y)
		if i < 4:
			sparks.append(canvas.center_of(p.x, p.y))
	# Fallen leaves round the foot, a few still glowing.
	for i in rng.randi_range(6, 10):
		var p := canvas.pixel(Vector2(rng.randf_range(-crown * 0.8, crown * 0.8), rng.randf_range(-2.5, 2.5)))
		if canvas.inside(p.x, p.y) and not canvas.is_body(p.x, p.y):
			if rng.randf() < 0.35:
				_ember(canvas, p.x, p.y)
			else:
				canvas.image.set_pixelv(p, EMBERLEAF[rng.randi_range(0, 2)])
	var art := NelvarFireArt.of(canvas)
	art.sway = 1
	art.molten = true
	art.sparks = sparks
	return art


# --- Snags and logs --------------------------------------------------------------

## A burnt trunk broken off near the ground: a jagged top with a ring of embers.
func _snag(thing: NelvarFireData.Thing, rng: RandomNumberGenerator) -> NelvarFireArt:
	var r := thing.radius / STEP
	var height := thing.size.y / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r - 4.0, -height - 4.0,
		r * 2.0 + 8.0, height + 8.0))
	_shadow(canvas, Vector2(-r * 0.2, 0.5), Vector2(r * 1.3, r * 0.45 + 0.5))
	canvas.trunk(0.0, -height, 0.0, r * 0.8, CHAR, CHAR_OUTLINE, rng.randi() & 0xffff, true)
	var left := canvas.pixel(Vector2(-r * 0.8, -height)).x
	var right := canvas.pixel(Vector2(r * 0.8, -height)).x
	var row := canvas.pixel(Vector2(0, -height)).y
	var sparks := PackedVector2Array()
	for x in range(left, right + 1):
		# A splintered break: spikes of different height.
		var spike := rng.randi_range(0, 4)
		for k in spike:
			canvas.put(x, row - k, CHAR[1] if x > (left + right) / 2 else CHAR[0], 0.3)
		if thing.accent and x > left and x < right and rng.randf() < 0.5:
			_ember(canvas, x, row + 1)
			if sparks.size() < 3:
				sparks.append(canvas.center_of(x, row))
	if thing.accent:
		_seams(canvas, rng, -height, r * 0.8, 0.0, 2)
	_litter(canvas, rng, Vector2(r * 1.4, 2.5), 8, LITTER)
	var art := NelvarFireArt.of(canvas)
	art.molten = thing.accent
	art.sparks = sparks
	if thing.accent:
		art.vent = Vector2(0.0, -height)
	return art


## A charred log lying on the ash; the burning ones glow along a crack and at the cut.
func _log(thing: NelvarFireData.Thing, rng: RandomNumberGenerator) -> NelvarFireArt:
	var half := thing.size.x / STEP * 0.5
	var r := thing.radius / STEP * 0.9
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-half - 4.0, -r * 2.0 - 4.0,
		half * 2.0 + 8.0, r * 2.0 + 7.0))
	_shadow(canvas, Vector2(-1.0, 0.0), Vector2(half + 2.0, r * 0.7 + 0.5))
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
			if p.x < -half + r * 0.4 * (1.0 - sqrt(maxf(0.0, 1.0 - v * v))) * 2.0:
				continue
			var level := 0.72 - (v + 1.0) * 0.32 + canvas.grain(x, y, 0.25, salt) * 0.35
			# Charred bark breaks into a checker of blocks.
			if int(floor(p.x / 3.0) + floor(p.y / 2.0)) % 2 == 0:
				level -= 0.08
			var color := canvas.ramp(CHAR, level, x, y)
			if v > 0.78 or p.x < -half + 1.0:
				color = CHAR_OUTLINE
			canvas.put(x, y, color, level)
	var sparks := PackedVector2Array()
	if thing.accent:
		var y := canvas.pixel(Vector2(0, center_y - r * 0.35)).y
		var x0 := canvas.pixel(Vector2(-half * 0.7, 0)).x
		var x1 := canvas.pixel(Vector2(half * 0.6, 0)).x
		var x := x0
		while x < x1:
			if canvas.is_body(x, y):
				_ember(canvas, x, y)
				if rng.randf() < 0.3:
					_hot(canvas, x, y)
			x += 1
			if rng.randf() < 0.3:
				y += 1 if rng.randf() < 0.5 else -1
				y = clampi(y, canvas.pixel(Vector2(0, center_y - r * 0.6)).y, canvas.pixel(Vector2(0, center_y)).y)
		sparks.append(Vector2(0.0, center_y - r))
	# The cut end: rings of charcoal round a glowing heart.
	var cut := Vector2(half - r * 0.25, center_y)
	var axes := Vector2(r * 0.5 + 0.5, r + 0.3)
	var cut_from := canvas.pixel(cut - axes)
	var cut_to := canvas.pixel(cut + axes)
	for y in range(cut_from.y, cut_to.y + 1):
		for x in range(cut_from.x, cut_to.x + 1):
			var d := ((canvas.center_of(x, y) - cut) / axes).length()
			if d > 1.0:
				continue
			if d < 0.35 and thing.accent:
				_hot(canvas, x, y)
			elif d < 0.6 and thing.accent:
				_ember(canvas, x, y)
			else:
				canvas.put(x, y, CHAR[2] if d < 0.8 else CHAR[1], 0.6)
	var art := NelvarFireArt.of(canvas)
	art.molten = thing.accent
	art.sparks = sparks
	return art


# --- Stone ----------------------------------------------------------------------

## A basalt boulder: the main body, sometimes a shoulder behind it and a smaller stone
## on top; some wear a cap of ash, some glow through their cracks, some shine like glass.
func _rock(thing: NelvarFireData.Thing, rng: RandomNumberGenerator) -> NelvarFireArt:
	var r := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.4 - 3.0, -r * 2.0 - 4.0,
		r * 2.8 + 6.0, r * 2.4 + 6.0))
	_shadow(canvas, Vector2(-r * 0.12, r * 0.08), Vector2(r * 1.15, r * 0.5 + 0.5))
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var tall := rng.randf_range(0.8, 1.05)
	var base := 0.5 - 0.72 * tall
	if r >= 5.0 and rng.randf() < 0.6:
		canvas.blob(NelvarEarthCanvas.make_blob(rng, Vector2(-side * 0.42, 0.0) * r,
			Vector2(0.55, 0.55) * r, -0.12, 0.14, 0.7, 0.2), BASALT)
	# Basalt breaks in angular blocks: a stiffer, more faceted edge than the earth's.
	canvas.blob(NelvarEarthCanvas.make_blob(rng, Vector2(rng.randf_range(-0.06, 0.06), base) * r,
		Vector2(0.92, tall) * r, -0.04, 0.18, 0.72, 0.2), BASALT)
	if r >= 6.0 and rng.randf() < 0.45:
		canvas.blob(NelvarEarthCanvas.make_blob(rng, Vector2(side * 0.28, base - tall * 0.8) * r,
			Vector2(0.46, 0.4) * r, 0.04, 0.14, 0.85, 0.2), BASALT)
	canvas.outline_silhouette(BASALT_OUTLINE, 0.7)
	var sparks := PackedVector2Array()
	var molten := false
	match thing.variant:
		Stone.EMBER:
			sparks = _ember_cracks(canvas, rng, rng.randi_range(2, 4))
			molten = true
		Stone.ASHEN:
			_cracks(canvas, rng, rng.randi_range(1, 2))
			if r >= 4.0:
				_ash_cap(canvas, rng.randi() & 0xffff, 2.5 + r * 0.08)
		_:
			_cracks(canvas, rng, rng.randi_range(1, 2))
	if rng.randf() < 0.3:
		_gloss(canvas, rng)
	var art := NelvarFireArt.of(canvas)
	art.molten = molten
	art.sparks = sparks
	return art


func _cracks(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, count: int) -> void:
	var inner := canvas.interior()
	if inner.is_empty():
		return
	for crack in count:
		var p := inner[rng.randi_range(0, inner.size() - 1)]
		for length in rng.randi_range(2, 5):
			if not canvas.is_body(p.x, p.y):
				break
			canvas.image.set_pixelv(p, BASALT_CRACK)
			p += Vector2i(rng.randi_range(-1, 1), 1)


## Cooling basalt: cracks that glow from inside, hottest in the middle of each.
func _ember_cracks(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var inner := canvas.interior()
	if inner.is_empty():
		return points
	for crack in count:
		var p := inner[rng.randi_range(0, inner.size() - 1)]
		var length := rng.randi_range(3, 7)
		for k in length:
			if not canvas.is_body(p.x, p.y):
				break
			if k > 0 and k < length - 1 and k % 2 == 1:
				_hot(canvas, p.x, p.y)
			else:
				_ember(canvas, p.x, p.y)
			p += Vector2i(rng.randi_range(-1, 1), 1 if rng.randf() < 0.7 else 0)
		points.append(canvas.center_of(p.x, p.y))
	return points


## Grey ash settled on top of the stone, its edge darker so it reads against the ash
## around.
func _ash_cap(canvas: NelvarEarthCanvas, salt: int, depth: float) -> void:
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
			var level := 0.66 - (0.3 if open_left else 0.0) + canvas.grain(x, y, 0.5, salt + 3) * 0.4
			canvas.image.set_pixel(x, y, ASH_EDGE if rows == 0 else canvas.ramp(ASH, level, x, y))
			rows += 1


## A few glassy glints on the lit upper right.
func _gloss(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator) -> void:
	var inner := canvas.interior()
	for i in rng.randi_range(2, 4):
		if inner.is_empty():
			return
		var p := inner[rng.randi_range(0, inner.size() - 1)]
		if canvas.levels[p.y * canvas.size.x + p.x] > 0.62:
			canvas.image.set_pixelv(p, GLOSS)


## Blue-green crystals grown out of the rock: a few upright prisms, lit on the right,
## each with a pale tip, over a little rubble.
func _crystals(thing: NelvarFireData.Thing, rng: RandomNumberGenerator) -> NelvarFireArt:
	var r := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.4 - 4.0, -r * 3.2 - 4.0,
		r * 2.8 + 8.0, r * 3.2 + 8.0))
	_shadow(canvas, Vector2(-r * 0.15, 0.5), Vector2(r * 1.1, r * 0.4 + 0.5))
	var colors := CRYSTAL if thing.variant == 0 else CRYSTAL_PALE
	var prisms: Array[Vector4] = []
	for i in rng.randi_range(3, 6):
		var x := rng.randf_range(-r * 0.75, r * 0.75)
		var height := r * rng.randf_range(1.2, 2.9) * (1.0 - absf(x) / r * 0.4)
		prisms.append(Vector4(x, rng.randf_range(-1.5, 0.5), height, rng.randf_range(-0.35, 0.35)))
	# Back to front, so nearer prisms stand over further ones.
	prisms.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.y < b.y)
	for prism in prisms:
		var half := maxf(1.0, prism.z * 0.16)
		var tip := maxf(2.0, half * 1.6)
		for k in int(prism.z):
			var t := float(k)
			var narrow := clampf((prism.z - t) / tip, 0.0, 1.0)
			var width := half * narrow
			var cx := prism.x + prism.w * t
			var row := canvas.pixel(Vector2(0, prism.y - t)).y
			var left := canvas.pixel(Vector2(cx - width, 0)).x
			var right := canvas.pixel(Vector2(cx + width, 0)).x
			for x in range(left, right + 1):
				var u := float(x - left) / maxf(1.0, right - left)
				var level := 0.3 + u * 0.5 + t / prism.z * 0.15
				var color := colors[clampi(int(level * colors.size()), 0, colors.size() - 2)]
				if x == left:
					color = CRYSTAL_OUTLINE
				elif x == right and right > left + 1:
					color = colors[3]
				if k >= int(prism.z) - 1:
					color = colors[4]
				canvas.put(x, row, color, level)
	for i in rng.randi_range(3, 6):
		var p := canvas.pixel(Vector2(rng.randf_range(-r, r), rng.randf_range(-1.0, 0.8)))
		if canvas.inside(p.x, p.y):
			canvas.put(p.x, p.y, BASALT[rng.randi_range(1, 3)], 0.4)
	return NelvarFireArt.of(canvas)


## A fumarole: a low mound of basalt crusted with yellow sulfur round a dark mouth,
## faintly glowing deep inside. Smoke rises from its mouth.
func _vent(thing: NelvarFireData.Thing, rng: RandomNumberGenerator) -> NelvarFireArt:
	var r := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.5 - 3.0, -r * 1.3 - 4.0,
		r * 3.0 + 6.0, r * 1.6 + 6.0))
	var mound := NelvarEarthCanvas.make_blob(rng, Vector2(0.0, -r * 0.3), Vector2(r * 1.15, r * 0.62),
		-0.05, 0.16, 0.75, 0.16)
	canvas.blob(mound, BASALT)
	canvas.outline_silhouette(BASALT_OUTLINE, 0.62)
	var mouth := Vector2(rng.randf_range(-r * 0.15, r * 0.15), -r * 0.62)
	var axes := Vector2(r * 0.34 + 0.6, r * 0.16 + 0.6)
	var salt := rng.randi() & 0xffff
	var from := canvas.pixel(mouth - axes * 2.4)
	var to := canvas.pixel(mouth + axes * 2.4)
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			if not canvas.is_body(x, y):
				continue
			var d := ((canvas.center_of(x, y) - mouth) / axes).length()
			if d < 1.0:
				var deep := canvas.center_of(x, y).y > mouth.y + axes.y * 0.2
				if deep and d < 0.6:
					_ember(canvas, x, y)
				else:
					canvas.image.set_pixel(x, y, BASALT_OUTLINE)
			elif d < 2.4:
				# Sulfur crust, thickest at the rim, broken up by noise.
				var crust := (2.4 - d) / 1.4 + (NelvarPixelArt.value_noise((canvas.grid.x + x) * 0.5,
					(canvas.grid.y + y) * 0.5, salt) - 0.5) * 0.9
				if crust > 0.35:
					var level := 0.4 + crust * 0.3 + canvas.grain(x, y, 0.7, salt + 1) * 0.4
					canvas.image.set_pixel(x, y, canvas.ramp(SULFUR, level, x, y))
	if thing.accent:
		# Bigger vents grow a few yellow crystals at the rim.
		for i in rng.randi_range(2, 4):
			var at := canvas.pixel(mouth + Vector2(rng.randf_range(-1.0, 1.0) * axes.x * 2.0, axes.y * 1.4))
			for k in rng.randi_range(1, 3):
				canvas.put(at.x, at.y - k, SULFUR[3] if k > 0 else SULFUR[2], 0.9)
	var art := NelvarFireArt.of(canvas)
	art.molten = true
	art.vent = mouth
	return art


# --- Plants ---------------------------------------------------------------------

## Thin dark stalks whose tips glow like the ends of incense sticks.
func _ember_grass(thing: NelvarFireData.Thing, rng: RandomNumberGenerator) -> NelvarFireArt:
	var r := thing.radius / STEP
	var height := r * rng.randf_range(1.8, 2.6)
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.6 - 3.0, -height - 4.0,
		r * 3.2 + 6.0, height + 7.0))
	_shadow(canvas, Vector2(-0.5, 0.5), Vector2(r * 0.9, 1.6))
	var blades := rng.randi_range(6, 10)
	var specs: Array[Vector3] = []
	for i in blades:
		var base := rng.randf_range(-1.0, 1.0)
		base = base * absf(base) * r
		var tall := height * rng.randf_range(0.5, 1.0) * (1.0 - absf(base) / r * 0.3)
		specs.append(Vector3(base, tall, base / r * 0.5 + rng.randf_range(-0.2, 0.4)))
	specs.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y > b.y)
	var sparks := PackedVector2Array()
	for spec in specs:
		var length := int(spec.y)
		for k in length:
			var t := float(k) / maxf(1.0, spec.y)
			var point := Vector2(spec.x + spec.z * t * t * spec.y * 0.45, -0.5 - k)
			var p := canvas.pixel(point)
			if k >= length - 1:
				if thing.variant == 1 or rng.randf() < 0.5:
					_hot(canvas, p.x, p.y)
				else:
					_ember(canvas, p.x, p.y)
				if sparks.size() < 2:
					sparks.append(point)
			elif k == length - 2:
				_ember(canvas, p.x, p.y)
			else:
				canvas.put(p.x, p.y, STALK[clampi(int(t * 3.0), 0, 2)], 0.2 + t * 0.5)
	var art := NelvarFireArt.of(canvas)
	art.sway = 2
	art.molten = true
	art.sparks = sparks
	return art


## Pale flowers of the ash: grey petals round a glowing heart on dark stems.
func _ash_flower(thing: NelvarFireData.Thing, rng: RandomNumberGenerator) -> NelvarFireArt:
	var r := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r - 4.0, -r * 2.6 - 6.0,
		r * 2.0 + 8.0, r * 2.6 + 9.0))
	var petals := PETAL_PINK if thing.variant == 2 else PETAL
	for i in rng.randi_range(4, 7):
		var leaf := Vector2(rng.randf_range(-r * 0.8, r * 0.8), rng.randf_range(-1.5, 0.0))
		canvas.put_at(leaf, STALK[rng.randi_range(0, 2)], 0.3)
	for i in rng.randi_range(2, 4):
		var base := Vector2(rng.randf_range(-r * 0.8, r * 0.8), rng.randf_range(-1.0, 0.5))
		var stem := rng.randi_range(3, 6)
		var bend := rng.randf_range(-0.25, 0.25)
		for k in stem:
			canvas.put_at(base + Vector2(bend * k, -k), STALK[1], 0.3)
		var head := base + Vector2(bend * stem, -stem)
		if thing.variant == 1:
			# Drooping: the petals hang down round the heart.
			for offset: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)]:
				canvas.put_at(head + offset, petals[1 if offset.y > 0 else 2], 0.8)
		else:
			for offset: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				canvas.put_at(head + offset, petals[2 if offset.x > 0 or offset.y < 0 else 1], 0.8)
		var p := canvas.pixel(head)
		_hot(canvas, p.x, p.y)
	var art := NelvarFireArt.of(canvas)
	art.sway = 1
	art.molten = true
	return art


## A scorched shrub: a tangle of dark twigs, some still red at the ends.
func _shrub(thing: NelvarFireData.Thing, rng: RandomNumberGenerator) -> NelvarFireArt:
	var r := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.3 - 3.0, -r * 1.5 - 4.0,
		r * 2.6 + 6.0, r * 1.5 + 7.0))
	_shadow(canvas, Vector2(-1.0, 0.5), Vector2(r * 1.0, r * 0.25 + 1.0))
	var embers := 0.35 if thing.variant == 1 else 0.12
	var molten := false
	for i in rng.randi_range(9, 15):
		var angle := -PI * 0.5 + rng.randf_range(-1.2, 1.2)
		var point := Vector2(rng.randf_range(-r * 0.3, r * 0.3), 0.0)
		var length := r * rng.randf_range(0.7, 1.4)
		var steps := int(length / 0.8)
		for k in steps:
			angle += rng.randf_range(-0.25, 0.25)
			point += Vector2.from_angle(angle) * 0.8
			var lit := 0.3 + Vector2.from_angle(angle).x * 0.3 + float(k) / steps * 0.3
			canvas.put_at(point, SHRUB[clampi(int(lit * SHRUB.size()), 0, SHRUB.size() - 1)], lit)
		if rng.randf() < embers:
			var p := canvas.pixel(point)
			_ember(canvas, p.x, p.y)
			molten = true
	var art := NelvarFireArt.of(canvas)
	art.sway = 1
	art.molten = molten
	return art
