class_name NelvarIcePainter
extends RefCounted
## Bakes everything that stands in the ice valley in the style of the "Лёд" menu
## background: pines under snow with caps on every tier, grey dead trees, rocks and the
## petrified creature in cool stone with snow caps and icicles, low drifts, blocks of blue
## ice with lit facets, dry stems and bare shrubs poking out of the snow; soft bluish
## shadows on the snow. Also the creatures frozen into the lakes, seen through the ice.
## Peaks are NelvarFrostPainter's; the plateau's boulders are rocks (paint_boulder).
##
## Stateless: one painter can paint from many worker threads at once.

const Kind = NelvarIceData.Kind
const Creature = NelvarIceData.Creature
const Block = NelvarIceData.Block
const STEP := NelvarIceData.PIXEL

# Palettes of the menu's ice reality (tools/gen_menu_backgrounds.py, ice()), dark to light.
const SNOW: Array[Color] = [Color8(176, 182, 194), Color8(198, 204, 214), Color8(218, 222, 230),
	Color8(236, 238, 242), Color8(250, 251, 252)]
const SNOWCAP: Array[Color] = [Color8(196, 202, 212), Color8(222, 226, 232), Color8(240, 242, 245),
	Color8(252, 252, 253)]
## The shaded rim of a drift against the snow behind it.
const SNOW_RIM := Color8(150, 158, 178)
const TRUNK: Array[Color] = [Color8(56, 50, 52), Color8(74, 66, 66), Color8(94, 84, 82)]
const NEEDLES: Array[Color] = [Color8(44, 60, 60), Color8(58, 76, 74), Color8(76, 94, 90),
	Color8(98, 114, 108)]
const OUTLINE := Color8(34, 42, 46)
## Grey weathered wood of the dead trees.
const DEAD_BARK: Array[Color] = [Color8(70, 64, 64), Color8(96, 88, 86), Color8(126, 116, 110),
	Color8(156, 146, 138)]
const DEAD_OUTLINE := Color8(40, 38, 42)
const STONE: Array[Color] = [Color8(92, 96, 104), Color8(118, 122, 130), Color8(146, 150, 156),
	Color8(172, 176, 182), Color8(196, 200, 204)]
const STONE_OUTLINE := Color8(58, 62, 70)
const STONE_CRACK := Color8(76, 80, 90)
const ICICLE: Array[Color] = [Color8(196, 214, 220), Color8(224, 236, 240), Color8(246, 250, 252)]
## Blocks of lake ice: blue, darker where light does not reach through.
const ICE: Array[Color] = [Color8(74, 112, 146), Color8(104, 146, 176), Color8(146, 186, 208),
	Color8(192, 220, 232), Color8(236, 247, 250)]
const ICE_OUTLINE := Color8(44, 72, 102)
const ICE_VEIN := Color8(214, 236, 244)
const STEMS: Array[Color] = [Color8(120, 112, 100), Color8(150, 140, 122), Color8(176, 166, 144),
	Color8(204, 196, 176)]
const STEM_DARK := Color8(92, 80, 74)
const TWIG: Array[Color] = [Color8(58, 48, 48), Color8(82, 70, 66), Color8(110, 96, 88)]
const BERRY := Color8(190, 44, 58)
const BERRY_LIGHT := Color8(238, 110, 108)
## Creatures under the ice: dim and cold, mid-dark so they read against the dark water.
const FROZEN: Array[Color] = [Color8(38, 58, 80), Color8(52, 76, 100), Color8(70, 96, 120),
	Color8(92, 118, 140), Color8(120, 144, 162)]
const FROZEN_OUTLINE := Color8(20, 32, 50)
const FROZEN_PALE := Color8(150, 172, 188)
const BUBBLE := Color8(140, 178, 198)
## Ground shadow on the snow: cool and translucent.
const SHADOW := Color(0.4, 0.45, 0.58, 0.26)


func paint(thing: NelvarIceData.Thing) -> NelvarIceArt:
	var rng := RandomNumberGenerator.new()
	rng.seed = thing.appearance_seed
	match thing.kind:
		Kind.PINE:
			return _pine(thing, rng)
		Kind.DEAD_TREE:
			return _dead_tree(thing, rng)
		Kind.ROCK:
			return _rock(thing.position, thing.radius, thing.accent, rng)
		Kind.STATUE:
			return _statue(thing, rng)
		Kind.DRIFT:
			return _drift(thing, rng)
		Kind.ICE_BLOCK:
			return _ice_block(thing, rng)
		Kind.DRY_GRASS:
			return _dry_grass(thing, rng)
		Kind.SHRUB:
			return _shrub(thing, rng)
	return _rock(thing.position, thing.radius, false, rng)


## A boulder on the plateau beyond the mountains.
func paint_boulder(peak: NelvarEarthData.Thing) -> NelvarIceArt:
	var rng := RandomNumberGenerator.new()
	rng.seed = peak.appearance_seed
	return _rock(peak.position, peak.radius, peak.accent, rng)


# --- Shared --------------------------------------------------------------------------

## Soft bluish shadow on the snow: a dithered ellipse that only darkens empty pixels.
static func _shadow(canvas: NelvarEarthCanvas, center: Vector2, reach: Vector2) -> void:
	var from := canvas.pixel(center - reach)
	var to := canvas.pixel(center + reach)
	for y in range(maxi(0, from.y), mini(canvas.size.y, to.y + 1)):
		for x in range(maxi(0, from.x), mini(canvas.size.x, to.x + 1)):
			if canvas.body[y * canvas.size.x + x] == 1 or canvas.image.get_pixel(x, y).a > 0.0:
				continue
			var color := NelvarPixelArt.shadow_at(canvas.center_of(x, y), center, reach, canvas.grid + Vector2i(x, y))
			if color.a > 0.0:
				canvas.image.set_pixel(x, y, SHADOW)


## A one-pixel line; returns the pixels it covers.
static func _line(canvas: NelvarEarthCanvas, from: Vector2, to: Vector2, color: Color,
		level: float) -> Array[Vector2i]:
	var steps := maxi(1, ceili(from.distance_to(to) * 1.5))
	var pixels: Array[Vector2i] = []
	for k in steps + 1:
		var p := canvas.pixel(from.lerp(to, float(k) / steps))
		if pixels.is_empty() or pixels[pixels.size() - 1] != p:
			pixels.append(p)
			canvas.put(p.x, p.y, color, level)
	return pixels


## Top-left corner of a pixel, art pixels from the origin (the eye's and sparkles' frame).
static func _corner(canvas: NelvarEarthCanvas, p: Vector2i) -> Vector2:
	return canvas.center_of(p.x, p.y) - Vector2(0.5, 0.5)


## Topmost painted pixel of a column, -1 for none.
static func _surface(canvas: NelvarEarthCanvas, x: int) -> int:
	if x < 0 or x >= canvas.size.x:
		return -1
	for y in canvas.size.y:
		if canvas.is_body(x, y):
			return y
	return -1


## Snow lying over the top of everything painted, `depth` pixels at most; its upper
## edge is pale on the shaded left and bright on the lit right. Icicles hang from its
## lower edge now and then (their tips glint).
func _snow_cap(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, depth: float, icicles: bool,
		art_sparkles: Array) -> void:
	var salt := rng.randi() & 0xffff
	var left := canvas.size.x
	var right := -1
	for x in canvas.size.x:
		if _surface(canvas, x) >= 0:
			left = mini(left, x)
			right = maxi(right, x)
	if right < 0:
		return
	var split := lerpf(float(left), float(right), 0.42)
	for x in range(left, right + 1):
		var top := _surface(canvas, x)
		if top < 0:
			continue
		var cell := canvas.grid + Vector2i(x, top)
		var limit := int(NelvarPixelArt.value_noise(cell.x * 0.3, 0.5, salt) * depth + 0.5) + 1
		var rows := 0
		var y := top
		while y < canvas.size.y and canvas.is_body(x, y) and rows < limit:
			var open_left := not canvas.is_body(x - 1, y)
			var level := 0.74 - (0.3 if open_left else 0.0) - float(rows) / maxf(1.0, limit) * 0.16 \
				+ canvas.grain(x, y, 0.5, salt + 3) * 0.3
			var color := canvas.ramp(SNOWCAP, level, x, y)
			if rows == 0:
				color = SNOWCAP[0] if float(x) < split else SNOWCAP[3]
			canvas.image.set_pixel(x, y, color)
			canvas.levels[y * canvas.size.x + x] = level
			rows += 1
			y += 1
		if icicles and rng.randf() < 0.22 and canvas.is_body(x, y) and canvas.is_body(x, y + 1):
			var length := rng.randi_range(1, 3)
			for k in length:
				if not canvas.is_body(x, y + k):
					break
				canvas.image.set_pixel(x, y + k, ICICLE[2 - mini(2, k)])
			art_sparkles.append(_corner(canvas, Vector2i(x, y + length - 1)))


func _finish(canvas: NelvarEarthCanvas, sparkles: Array = [], sway: int = 0) -> NelvarIceArt:
	var art := NelvarIceArt.of(canvas)
	art.sway = sway
	for point: Vector2 in sparkles:
		art.sparkles.append(point)
	return art


# --- Trees ---------------------------------------------------------------------------

## The menu's pine under snow: tiers capped with snow, snow on the tips of the lowest
## rows, little drops of snow hanging at the edges of each tier. `accent`: deep snow.
func _pine(thing: NelvarIceData.Thing, rng: RandomNumberGenerator) -> NelvarIceArt:
	var half := thing.size.x / STEP
	var total := thing.size.y / STEP
	var canvas := NelvarEarthCanvas.new(thing.position,
		Rect2(-half - 4.0, -total - 4.0, half * 2.0 + 8.0, total + 8.0))
	_shadow(canvas, Vector2(-1.5, 0.5), Vector2(half * 0.9, 3.0))
	var trunk_height := total * 0.14
	var salt := rng.randi() & 0xffff
	canvas.trunk(0.0, -trunk_height - 4.0, 0.0, maxf(1.2, thing.radius / STEP * 0.42), TRUNK, OUTLINE, salt)
	var deep := thing.accent
	var tiers := 5 if total > 52.0 else 4
	var crown := total - trunk_height
	var glints: Array[Vector2] = []
	# Top tier first, as on the menu: each tier below lays its snowy top over the hem of
	# the one above.
	for i in tiers:
		var tier_top := -total + i * crown * (0.8 / (tiers - 1))
		var tier_height := crown * (0.3 + i * 0.035)
		var width := half * (0.34 + 0.66 * float(i) / (tiers - 1))
		var rows := int(tier_height)
		var snow_rows := maxf(2.0, tier_height * (0.46 if deep else 0.3))
		for k in rows:
			var frac := float(k) / tier_height
			var y := canvas.pixel(Vector2(0, tier_top + k)).y
			var wiggle := (NelvarPixelArt.value_noise(k * 0.7, i, salt) - 0.5) * 2.0
			var reach := width * pow(frac, 0.85) + wiggle
			var left := canvas.pixel(Vector2(-reach, 0)).x
			var right := canvas.pixel(Vector2(reach, 0)).x
			for x in range(left, right + 1):
				var u := canvas.center_of(x, y).x / maxf(1.0, reach)
				var level := 0.45 + u * 0.35 - frac * 0.25 + canvas.grain(x, y, 0.6, salt + i) * 0.8
				var color := canvas.ramp(NEEDLES, level, x, y)
				var drift := (NelvarPixelArt.value_noise(x * 0.5, i, salt + 9) - 0.5) * 2.5
				var tips := frac > (0.7 if deep else 0.8) and absf(u) > (0.7 if deep else 0.8)
				# Snow lies along the sloping top of the tier, where the tier above leaves
				# it in view.
				var edge: float = tier_height * pow(clampf(absf(canvas.center_of(x, y).x) / maxf(1.0, width),
					0.0, 1.0), 1.0 / 0.85)
				var lying: bool = k - edge < (3.2 if deep else 1.8) + drift * 0.5
				var snowy: bool = k < snow_rows * (1.0 - absf(u) * 0.5) + drift or tips or lying
				if snowy:
					color = canvas.ramp(SNOWCAP, level + 0.25, x, y)
					if deep and level > 0.7 and k == 0 and rng.randf() < 0.5:
						glints.append(_corner(canvas, Vector2i(x, y)))
				if x == left:
					# The shaded edge keeps its dark line below the tier's cap.
					color = SNOWCAP[0] if snowy and k < snow_rows else OUTLINE
				elif k == rows - 1 and level < 0.55 and not snowy:
					color = OUTLINE
				canvas.put(x, y, color, level)
		# Drops of snow hanging at the tier's edges.
		var bottom := canvas.pixel(Vector2(0, tier_top + rows - 1)).y
		for side: float in [-1.0, 1.0]:
			var ex := canvas.pixel(Vector2(side * width, 0)).x
			for k in rng.randi_range(1, 3 if deep else 2):
				canvas.put(ex, bottom + 1 + k, SNOWCAP[2], 0.9)
	# A heap of snow round the foot of the trunk.
	var heap := NelvarEarthCanvas.make_blob(rng, Vector2(rng.randf_range(-0.5, 0.5), -0.6),
		Vector2(maxf(2.5, half * 0.32), 1.6), 0.15, 0.06, 0.4, 0.15)
	heap.rim = SNOW_RIM
	heap.rim_level = 0.4
	canvas.blob(heap, SNOW)
	return _finish(canvas, glints.slice(0, 3), 1)


## A dead standing tree: a bare grey trunk broken off at the top, a few bare branches
## reaching up and out, thin lines of snow along their upper sides.
func _dead_tree(thing: NelvarIceData.Thing, rng: RandomNumberGenerator) -> NelvarIceArt:
	var reach := thing.size.x / STEP
	var total := thing.size.y / STEP
	var canvas := NelvarEarthCanvas.new(thing.position,
		Rect2(-reach - 4.0, -total - 4.0, reach * 2.0 + 8.0, total + 8.0))
	_shadow(canvas, Vector2(-1.5, 0.5), Vector2(maxf(4.0, reach * 0.6), 2.4))
	var salt := rng.randi() & 0xffff
	var half_width := maxf(1.2, thing.radius / STEP * 0.45)
	var lean := rng.randf_range(-2.0, 2.0)
	var top := -total * rng.randf_range(0.8, 0.94)
	canvas.trunk(0.0, top, 0.0, half_width, DEAD_BARK, DEAD_OUTLINE, salt, true, lean)
	var wood: Array[Vector2i] = []
	# The broken top: splinters of uneven length.
	for k in rng.randi_range(2, 3):
		var x := lean + rng.randf_range(-half_width, half_width)
		var length := rng.randf_range(1.0, 4.0)
		wood.append_array(_line(canvas, Vector2(x, top + 0.5), Vector2(x + rng.randf_range(-0.8, 0.8), top - length),
			DEAD_BARK[2] if x > lean else DEAD_BARK[1], 0.5))
	var count := rng.randi_range(3, 6)
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	for b in count:
		side = -side if rng.randf() < 0.8 else side
		var t := lerpf(0.3, 0.92, (float(b) + rng.randf()) / count)
		var y := top * t
		var cx := lean * t * t
		var length := reach * rng.randf_range(0.45, 1.0) * (1.15 - t * 0.5)
		var direction := Vector2(side, -rng.randf_range(0.35, 1.0)).normalized()
		var from := Vector2(cx + side * half_width * 0.8, y)
		var to := from + direction * length
		var color := DEAD_BARK[2] if side > 0.0 else DEAD_BARK[1]
		wood.append_array(_line(canvas, from, to, color, 0.5))
		# A twig off the branch, further up.
		var fork := from.lerp(to, rng.randf_range(0.45, 0.7))
		var twig := Vector2(direction.x * 0.5, -1.0).normalized() * length * rng.randf_range(0.25, 0.45)
		wood.append_array(_line(canvas, fork, fork + twig, DEAD_BARK[1], 0.5))
	# Snow along the upper side of the branches and on the broken top.
	for p in wood:
		if not canvas.is_body(p.x, p.y - 1) and rng.randf() < 0.6:
			canvas.put(p.x, p.y - 1, SNOWCAP[2] if rng.randf() < 0.7 else SNOWCAP[1], 0.9)
	var heap := NelvarEarthCanvas.make_blob(rng, Vector2(0.0, -0.5), Vector2(half_width + 2.5, 1.4),
		0.15, 0.06, 0.4, 0.15)
	heap.rim = SNOW_RIM
	heap.rim_level = 0.4
	canvas.blob(heap, SNOW)
	return _finish(canvas, [], 1)


# --- Stone ---------------------------------------------------------------------------

## A boulder of cool grey stone with a snow cap (`big`: a deep one), sometimes a lower
## shoulder behind it, and snow banked against its foot.
func _rock(origin: Vector2, radius: float, big: bool, rng: RandomNumberGenerator) -> NelvarIceArt:
	var r := radius / STEP
	var canvas := NelvarEarthCanvas.new(origin, Rect2(-r * 1.4 - 3.0, -r * 2.0 - 4.0,
		r * 2.8 + 6.0, r * 2.4 + 6.0))
	_shadow(canvas, Vector2(-r * 0.12, r * 0.08), Vector2(r * 1.15, r * 0.5 + 0.5))
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
	var glints := []
	_snow_cap(canvas, rng, clampf(r * (0.42 if big else 0.2), 1.5, 9.0), r >= 6.0, glints)
	if r >= 4.0 and rng.randf() < 0.65:
		var bank := NelvarEarthCanvas.make_blob(rng, Vector2(side * r * 0.45, -r * 0.12),
			Vector2(r * 0.6, maxf(1.5, r * 0.26)), 0.12, 0.06, 0.55, 0.14)
		bank.rim = SNOW_RIM
		bank.rim_level = 0.42
		canvas.blob(bank, SNOW)
	return _finish(canvas, glints.slice(0, 3))


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


## The menu's petrified creature in cool stone: a boulder body with a shoulder, a head
## with a closed eye, cracks, a cap of snow and icicles. Facing right, or left when
## `accent`.
func _statue(thing: NelvarIceData.Thing, rng: RandomNumberGenerator) -> NelvarIceArt:
	var r := thing.radius / STEP
	var s := r / 17.0
	var facing := -1.0 if thing.accent else 1.0
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-46.0 * s - 3.0, -50.0 * s - 4.0,
		92.0 * s + 6.0, 56.0 * s + 6.0))
	_shadow(canvas, Vector2(-2.0 * s, 1.0), Vector2(36.0 * s, 7.0 * s))
	canvas.blob(NelvarEarthCanvas.make_blob(rng, Vector2(-16.0 * facing, -20.0) * s, Vector2(13, 11) * s,
		-0.06, 0.14, 2.0, 0.12), STONE)
	canvas.blob(NelvarEarthCanvas.make_blob(rng, Vector2(0.0, -15.0) * s, Vector2(29, 18) * s,
		0.0, 0.14, 0.85, 0.12), STONE)
	canvas.blob(NelvarEarthCanvas.make_blob(rng, Vector2(18.0 * facing, -34.0) * s, Vector2(12, 10) * s,
		0.0, 0.12, 2.0, 0.12), STONE)
	canvas.outline_silhouette(STONE_OUTLINE, 0.62)
	_cracks(canvas, rng, 3)
	var glints := []
	_snow_cap(canvas, rng, 3.5, true, glints)
	# The closed eyelid with a few lashes.
	var eye := Vector2(20.0 * facing, -34.0) * s
	var half := maxi(2, roundi(4.0 * s))
	var center := canvas.pixel(eye)
	for dx in range(-half, half + 1):
		canvas.put(center.x + dx, center.y + (1 if absi(dx) == half else 0), STONE_OUTLINE, 0.0)
	for dx in [-half + 1, 0, half - 1]:
		canvas.image.set_pixel(center.x + dx, center.y + 1, STONE_OUTLINE.lerp(STONE[1], 0.5))
	var art := _finish(canvas, glints.slice(0, 4))
	art.eye = _corner(canvas, center)
	return art


# --- Snow and ice ---------------------------------------------------------------------

## A low drift: lumps of snow lit from the upper right with a shaded rim, a bright
## wind-cut lip on the lit side, a few dry stems poking out.
func _drift(thing: NelvarIceData.Thing, rng: RandomNumberGenerator) -> NelvarIceArt:
	var r := thing.radius / STEP
	var h := r * rng.randf_range(0.36, 0.48)
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.3 - 3.0, -h * 1.7 - 8.0,
		r * 2.6 + 6.0, h * 1.7 + 11.0))
	_shadow(canvas, Vector2(-r * 0.15, 0.4), Vector2(r * 1.1, r * 0.3 + 1.0))
	var lumps := rng.randi_range(1, 2)
	for i in lumps:
		var side := -1.0 if (i == 0) == (rng.randf() < 0.5) else 1.0
		var lump := NelvarEarthCanvas.make_blob(rng, Vector2(side * r * rng.randf_range(0.4, 0.6), -h * 0.3),
			Vector2(r * rng.randf_range(0.42, 0.55), h * rng.randf_range(0.6, 0.8)), 0.1, 0.06, 0.45, 0.16)
		lump.rim = SNOW_RIM
		lump.rim_level = 0.42
		canvas.blob(lump, SNOW)
	var main := NelvarEarthCanvas.make_blob(rng, Vector2(rng.randf_range(-0.1, 0.1) * r, -h * 0.55),
		Vector2(r * 0.82, h), 0.12, 0.06, 0.55, 0.14)
	main.rim = SNOW_RIM
	main.rim_level = 0.42
	canvas.blob(main, SNOW)
	# The wind-cut lip along the lit top.
	var left := canvas.size.x
	var right := -1
	for x in canvas.size.x:
		if _surface(canvas, x) >= 0:
			left = mini(left, x)
			right = maxi(right, x)
	for x in range(int(lerpf(left, right, 0.45)), right):
		var y := _surface(canvas, x)
		if y >= 0:
			canvas.image.set_pixel(x, y, SNOW[4])
	# Dry stems poking out of the snow.
	for i in rng.randi_range(2, 4):
		var x := canvas.pixel(Vector2(rng.randf_range(-0.6, 0.6) * r, 0)).x
		var y := _surface(canvas, x)
		if y < 0:
			continue
		var tall := rng.randi_range(2, 5)
		var lean := 1 if rng.randf() < 0.5 else 0
		for k in tall:
			canvas.put(x + (k * lean) / 3, y + 1 - k, STEM_DARK if k < tall - 1 else STEMS[1], 0.4)
	return _finish(canvas)


## A block of lake ice (CHUNK) or a pressure ridge of tilted slabs (RIDGE): flat facets
## lit by the sun, a dusting of snow on top, bright edges that glint.
func _ice_block(thing: NelvarIceData.Thing, rng: RandomNumberGenerator) -> NelvarIceArt:
	var r := thing.radius / STEP
	var ridge := thing.variant == Block.RIDGE
	var height := r * (1.2 if ridge else 1.5)
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.5 - 4.0, -height - r - 6.0,
		r * 3.0 + 8.0, height + r * 1.7 + 10.0))
	_shadow(canvas, Vector2(-r * 0.15, r * 0.1), Vector2(r * 1.2, r * 0.6 + 0.5))
	var glints: Array[Vector2] = []
	if ridge:
		var slabs: Array[Vector4] = []
		var count := rng.randi_range(3, 5)
		for i in count:
			var x := lerpf(-0.75, 0.75, (float(i) + rng.randf_range(0.2, 0.8)) / count) * r
			slabs.append(Vector4(x, rng.randf_range(-0.25, 0.25) * r, r * rng.randf_range(0.22, 0.32),
				r * rng.randf_range(0.55, 1.15)))
		slabs.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.y < b.y)
		for slab in slabs:
			_block(canvas, rng, Vector2(slab.x, slab.y), Vector2(slab.z, r * rng.randf_range(0.14, 0.22)),
				slab.w, rng.randf_range(0.5, 0.75), rng.randf_range(-0.3, 0.3) * r, glints)
	else:
		_block(canvas, rng, Vector2.ZERO, Vector2(r, r * 0.6), r * rng.randf_range(0.9, 1.45),
			rng.randf_range(0.58, 0.8), rng.randf_range(-0.25, 0.25) * r, glints)
	canvas.outline_silhouette(ICE_OUTLINE, 0.6)
	# Pale veins frozen inside.
	var inner := canvas.interior()
	for i in mini(inner.size() / 40, 4):
		var p := inner[rng.randi_range(0, inner.size() - 1)]
		for length in rng.randi_range(2, 4):
			if not canvas.is_body(p.x, p.y) or canvas.levels[p.y * canvas.size.x + p.x] > 0.8:
				break
			canvas.image.set_pixelv(p, ICE_VEIN)
			p += Vector2i(rng.randi_range(-1, 1), rng.randi_range(0, 1))
	var picked: Array[Vector2] = []
	for i in mini(glints.size(), rng.randi_range(2, 4)):
		picked.append(glints[rng.randi_range(0, glints.size() - 1)])
	return _finish(canvas, picked)


## One block: a base polygon round `center` (art pixels, on the ground) rising `height`
## to a smaller top shifted sideways by `tilt`. Facets back to front, then the top.
func _block(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, center: Vector2, axes: Vector2,
		height: float, taper: float, tilt: float, glints: Array[Vector2]) -> void:
	var count := rng.randi_range(5, 7)
	var start := rng.randf() * TAU
	var base := PackedVector2Array()
	var top := PackedVector2Array()
	for i in count:
		var angle := start + TAU * (float(i) + rng.randf_range(-0.25, 0.25)) / count
		var p := Vector2(cos(angle) * axes.x, sin(angle) * axes.y) * rng.randf_range(0.78, 1.05)
		base.append(center + p)
		top.append(center + p * taper * rng.randf_range(0.85, 1.1) + Vector2(tilt, -height))
	var sun := Vector2(0.9, -0.43).normalized()
	var sides: Array = []
	for i in count:
		var j := (i + 1) % count
		var edge := base[j] - base[i]
		var normal := Vector2(edge.y, -edge.x).normalized()
		sides.append([PackedVector2Array([base[i], base[j], top[j], top[i]]), normal,
			(base[i].y + base[j].y) * 0.5])
	sides.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])
	var salt := rng.randi() & 0xffff
	for side: Array in sides:
		var normal: Vector2 = side[1]
		var level := 0.38 + 0.36 * normal.dot(sun) + 0.06 * normal.y
		_facet(canvas, side[0], level, height, salt, false)
	_facet(canvas, top, 0.86, height, salt, true)
	# Bright edges where the top meets the facets facing the camera; they glint.
	for i in count:
		var j := (i + 1) % count
		var edge := top[j] - top[i]
		var normal := Vector2(edge.y, -edge.x).normalized()
		if normal.y <= 0.1:
			continue
		var pixels := _line(canvas, top[i], top[j], ICE[4], 0.95)
		if not pixels.is_empty() and normal.dot(sun) > -0.4:
			glints.append(_corner(canvas, pixels[pixels.size() / 2]))


## Fills a facet of a block: the ice brighter towards its top, with upright streaks
## where the light runs through; the top facet carries a dusting of snow.
func _facet(canvas: NelvarEarthCanvas, polygon: PackedVector2Array, level: float, height: float,
		salt: int, upper: bool) -> void:
	var low := polygon[0]
	var high := polygon[0]
	for point in polygon:
		low = low.min(point)
		high = high.max(point)
	var from := canvas.pixel(low).max(Vector2i.ZERO)
	var to := canvas.pixel(high).min(canvas.size - Vector2i.ONE)
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var p := canvas.center_of(x, y)
			if not Geometry2D.is_point_in_polygon(p, polygon):
				continue
			var v := clampf((p.y - low.y) / maxf(1.0, high.y - low.y), 0.0, 1.0)
			var shade := level + (1.0 - v) * 0.1 \
				+ (NelvarPixelArt.value_noise((canvas.grid.x + x) * 0.55, (canvas.grid.y + y) * 0.07, salt) - 0.5) * 0.24
			var color := canvas.ramp(ICE, shade, x, y)
			if upper and NelvarPixelArt.value_noise((canvas.grid.x + x) * 0.4, (canvas.grid.y + y) * 0.4, salt + 5) > 0.42:
				color = canvas.ramp(SNOWCAP, shade, x, y)
			canvas.put(x, y, color, shade)


# --- Plants ----------------------------------------------------------------------------

## Dry stems poking out of the snow, leaning outwards; some carry seed heads.
func _dry_grass(thing: NelvarIceData.Thing, rng: RandomNumberGenerator) -> NelvarIceArt:
	var r := thing.radius / STEP
	var height := r * rng.randf_range(1.6, 2.5)
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.6 - 3.0, -height - 3.0,
		r * 3.2 + 6.0, height + 6.0))
	_shadow(canvas, Vector2(-0.5, 0.5), Vector2(r * 0.8, 1.4))
	var specs: Array[Vector3] = []
	for i in rng.randi_range(5, 9):
		var base := rng.randf_range(-1.0, 1.0)
		base = base * absf(base) * r * 0.8
		var tall := height * rng.randf_range(0.5, 1.0) * (1.0 - absf(base) / maxf(r, 1.0) * 0.3)
		specs.append(Vector3(base, tall, base / maxf(r, 1.0) * 0.6 + rng.randf_range(-0.25, 0.4)))
	specs.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y > b.y)
	for spec in specs:
		var length := int(spec.y)
		var seeds := thing.variant == 1 and rng.randf() < 0.6
		for k in length:
			var t := float(k) / maxf(1.0, spec.y)
			var point := Vector2(spec.x + spec.z * t * t * spec.y * 0.45, -0.5 - k)
			var level := 0.15 + t * 0.75
			var p := canvas.pixel(point)
			var color := canvas.ramp(STEMS, level, p.x, p.y)
			if seeds and k >= length - 2:
				color = STEMS[3] if k == length - 1 else STEMS[2]
			canvas.put(p.x, p.y, color, level)
	# A little snow heaped round the stems.
	for dx in range(-ceili(r * 0.6), ceili(r * 0.6) + 1):
		var p := canvas.pixel(Vector2(dx, -0.5))
		canvas.put(p.x, p.y, SNOW[3] if dx > 0 else SNOW[2], 0.8)
		if absf(dx) < r * 0.3 and rng.randf() < 0.6:
			canvas.put(p.x, p.y - 1, SNOW[4] if dx >= 0 else SNOW[3], 0.9)
	return _finish(canvas, [], 2 if height > 9.0 else 1)


## A bare shrub: twigs fanning up from the snow, forking, with snow on their upper
## sides; `accent`: red berries at the tips.
func _shrub(thing: NelvarIceData.Thing, rng: RandomNumberGenerator) -> NelvarIceArt:
	var r := thing.radius / STEP
	var h := r * rng.randf_range(1.0, 1.35)
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.5 - 3.0, -h * 1.4 - 4.0,
		r * 3.0 + 6.0, h * 1.4 + 7.0))
	_shadow(canvas, Vector2(-1.0, 0.5), Vector2(r * 0.95, r * 0.22 + 1.0))
	var wood: Array[Vector2i] = []
	var tips: Array[Vector2] = []
	var count := rng.randi_range(5, 8)
	for i in count:
		var angle := lerpf(-PI + 0.45, -0.45, (float(i) + rng.randf_range(0.1, 0.9)) / count)
		var from := Vector2(rng.randf_range(-0.15, 0.15) * r, -0.5)
		_twig(canvas, rng, from, angle, h * rng.randf_range(0.65, 1.05), 2, wood, tips)
	for p in wood:
		if not canvas.is_body(p.x, p.y - 1) and rng.randf() < 0.45:
			canvas.put(p.x, p.y - 1, SNOWCAP[2] if rng.randf() < 0.6 else SNOWCAP[1], 0.9)
	if thing.accent:
		for i in mini(tips.size(), rng.randi_range(5, 9)):
			var tip := tips[rng.randi_range(0, tips.size() - 1)]
			var p := canvas.pixel(tip)
			canvas.put(p.x, p.y, BERRY, 0.6)
			if rng.randf() < 0.5:
				canvas.put(p.x + 1, p.y, BERRY_LIGHT, 0.8)
	var heap := NelvarEarthCanvas.make_blob(rng, Vector2(0.0, -0.6), Vector2(r * 0.6, maxf(1.4, r * 0.22)),
		0.15, 0.06, 0.45, 0.15)
	heap.rim = SNOW_RIM
	heap.rim_level = 0.4
	canvas.blob(heap, SNOW)
	return _finish(canvas, [], 1)


func _twig(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, from: Vector2, angle: float,
		length: float, forks: int, wood: Array[Vector2i], tips: Array[Vector2]) -> void:
	var to := from + Vector2.from_angle(angle) * length
	var color := TWIG[2] if cos(angle) > 0.0 else TWIG[1]
	if forks == 2:
		color = TWIG[0] if cos(angle) <= 0.0 else TWIG[1]
	wood.append_array(_line(canvas, from, to, color, 0.4))
	if forks <= 0 or length < 2.5:
		tips.append(to)
		return
	var at := from.lerp(to, rng.randf_range(0.5, 0.7))
	_twig(canvas, rng, at, angle + rng.randf_range(0.35, 0.7), length * rng.randf_range(0.4, 0.6), forks - 1,
		wood, tips)
	_twig(canvas, rng, to, angle - rng.randf_range(0.0, 0.4), length * rng.randf_range(0.3, 0.5), forks - 1,
		wood, tips)


# --- Under the ice ---------------------------------------------------------------------

## A creature frozen into a lake, lying flat under the ice and seen from above through
## it: dim and cold, with a huge closed eye (art.eye: the node opens it). The origin is
## the middle of the body.
func paint_frozen(creature: NelvarIceData.Frozen) -> NelvarIceArt:
	var rng := RandomNumberGenerator.new()
	rng.seed = creature.appearance_seed
	var r := creature.radius / STEP
	var facing := -1.0 if creature.facing_left else 1.0
	var canvas := NelvarEarthCanvas.new(creature.position, Rect2(-r * 1.35 - 3.0, -r * 0.95 - 3.0,
		r * 2.7 + 6.0, r * 1.9 + 6.0))
	var eye := Vector2.ZERO
	match creature.variant:
		Creature.FISH:
			eye = _fish(canvas, rng, r, facing)
		Creature.SERPENT:
			eye = _serpent(canvas, rng, r, facing)
		_:
			eye = _beast(canvas, rng, r, facing)
	canvas.outline_silhouette(FROZEN_OUTLINE, 0.55)
	# Bubbles caught in the ice round it.
	for i in rng.randi_range(4, 9):
		var spot := Vector2(rng.randf_range(-1.2, 1.2) * r, rng.randf_range(-0.8, 0.8) * r)
		var p := canvas.pixel(spot)
		if canvas.inside(p.x, p.y) and not canvas.is_body(p.x, p.y):
			canvas.put(p.x, p.y, BUBBLE, 0.8)
	var half := 3 if r > 15.0 else 2
	var center := canvas.pixel(eye)
	for dx in range(-half, half + 1):
		canvas.put(center.x + dx, center.y + (1 if absi(dx) == half else 0), FROZEN_OUTLINE, 0.0)
	for dx in [-half + 1, half - 1]:
		canvas.put(center.x + dx, center.y + 1, FROZEN_OUTLINE.lerp(FROZEN[2], 0.5), 0.0)
	var art := _finish(canvas)
	art.eye = _corner(canvas, center)
	return art


func _frozen_blob(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, center: Vector2, axes: Vector2,
		bias: float = 0.0) -> void:
	canvas.blob(NelvarEarthCanvas.make_blob(rng, center, axes, bias - 0.08, 0.12, 2.0, 0.1), FROZEN)


## A beast curled on its side: a tail, a hind paw, the body with a hump of a back, a
## forepaw reaching out with pale claws, the big head with a snout and horns.
func _beast(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, r: float, f: float) -> Vector2:
	var curl := rng.randf_range(0.6, 1.2)
	for k in 6:
		var t := float(k) / 5.0
		var spot := Vector2((-0.66 - t * 0.28) * f, 0.05 - t * curl * 0.45 + t * t * curl * 0.2) * r
		_frozen_blob(canvas, rng, spot, Vector2.ONE * r * (0.11 - t * 0.05) + Vector2.ONE * 0.8)
	_frozen_blob(canvas, rng, Vector2(-0.5 * f, 0.38) * r, Vector2(0.2, 0.09) * r + Vector2.ONE * 0.6, -0.05)
	_frozen_blob(canvas, rng, Vector2(-0.1 * f, 0.05) * r, Vector2(0.6, 0.34) * r)
	_frozen_blob(canvas, rng, Vector2(-0.24 * f, -0.13) * r, Vector2(0.38, 0.24) * r, 0.06)
	var paw := Vector2(0.56 * f, 0.38) * r
	_frozen_blob(canvas, rng, paw, Vector2(0.24, 0.09) * r + Vector2.ONE * 0.6)
	for k in 3:
		var claw := canvas.pixel(paw + Vector2((0.24 * r + 0.8) * f, (float(k) - 1.0) * maxf(1.0, r * 0.05)))
		canvas.put(claw.x, claw.y, FROZEN_PALE, 0.9)
	var head := Vector2(0.62 * f, -0.06) * r
	for side: float in [-1.0, 1.0]:
		var horn := head + Vector2(side * 0.12 * r, -0.22 * r)
		_line(canvas, horn, horn + Vector2(side * 0.08 * r - 0.1 * r * f, -0.16 * r), FROZEN[3], 0.7)
	_frozen_blob(canvas, rng, head, Vector2(0.3, 0.27) * r, 0.04)
	_frozen_blob(canvas, rng, Vector2(0.86 * f, 0.03) * r, Vector2(0.14, 0.11) * r + Vector2.ONE * 0.5, 0.02)
	return head + Vector2(0.06 * f, -0.05) * r


## A great fish: a spindle of a body, a forked tail, spines along its back and a fin.
func _fish(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, r: float, f: float) -> Vector2:
	var tail := Vector2(-0.6 * f, 0.0) * r
	var spread := rng.randf_range(0.24, 0.34) * r
	var from := canvas.pixel(Vector2(-0.98, -0.4) * r)
	var to := canvas.pixel(Vector2(0.98, 0.4) * r)
	var low := Vector2i(mini(from.x, to.x), from.y)
	var high := Vector2i(maxi(from.x, to.x), to.y)
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var p := canvas.center_of(x, y)
			var back := (tail.x - p.x) * f
			if back < 0.0 or back > 0.36 * r:
				continue
			var notch := absf(p.y) < back * 0.35 and back > 0.22 * r
			if absf(p.y) <= spread * back / (0.36 * r) + 0.6 and not notch:
				canvas.put(x, y, canvas.ramp(FROZEN, 0.35 + p.y / spread * -0.15, x, y), 0.4)
	_frozen_blob(canvas, rng, Vector2(0.05 * f, 0.0) * r, Vector2(0.64, 0.25) * r)
	_frozen_blob(canvas, rng, Vector2(0.42 * f, -0.02) * r, Vector2(0.26, 0.2) * r, 0.05)
	for k in rng.randi_range(4, 6):
		var at := Vector2(lerpf(-0.4, 0.25, float(k) / 5.0) * f, -0.25) * r
		_line(canvas, at, at + Vector2(-0.05 * r * f, -0.1 * r - 1.0), FROZEN[3], 0.7)
	_frozen_blob(canvas, rng, Vector2(0.12 * f, 0.22) * r, Vector2(0.14, 0.07) * r + Vector2.ONE * 0.5, -0.04)
	return Vector2(0.44 * f, -0.06) * r


## A serpent: a long body winding back from a heavy head, spines along it.
func _serpent(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, r: float, f: float) -> Vector2:
	var phase := rng.randf() * TAU
	var waves := rng.randf_range(1.8, 2.6)
	var count := 18
	var spots: Array[Vector3] = []
	for k in count:
		var t := float(k) / (count - 1)
		var x := lerpf(0.8, -0.98, t)
		var y := sin(t * PI * waves + phase) * 0.36 * (0.4 + t * 0.6)
		spots.append(Vector3(x * f * r, y * r, lerpf(0.2, 0.05, t) * r + 0.7))
	for k in range(count - 1, -1, -1):
		var spot := spots[k]
		_frozen_blob(canvas, rng, Vector2(spot.x, spot.y), Vector2(spot.z, spot.z * 0.82), 0.02 if k % 2 == 0 else -0.02)
		if k % 3 == 1 and k > 1:
			var p := canvas.pixel(Vector2(spot.x, spot.y - spot.z * 0.9))
			canvas.put(p.x, p.y, FROZEN[4], 0.8)
	var head := Vector2(spots[0].x, spots[0].y)
	_frozen_blob(canvas, rng, head + Vector2(0.06 * f, 0.0) * r, Vector2(0.24, 0.18) * r, 0.05)
	return head + Vector2(0.08 * f, -0.05) * r
