class_name NelvarThicketPainter
extends NelvarEarthPainter
## Bakes the small things of the giant forest, grown huge (Земля 2): acorns like boulders,
## mushrooms with caps like roofs, grass blades taller than the player, clover, flowers,
## fallen leaves like rafts, twigs like logs, snail shells, feathers, dew drops, amber with
## creatures caught in it, bones, the flytraps and the puffballs. Everything familiar is
## painted with more pixels than in the valley, never stretched; the valley's own kinds
## (rocks, statues) come from NelvarEarthPainter.
##
## Stateless: one painter can paint from many worker threads at once.

const FADES := NelvarGiantPainter.FADES

const ACORN: Array[Color] = [Color8(70, 42, 22), Color8(112, 70, 32), Color8(156, 104, 46), Color8(196, 146, 72), Color8(232, 196, 120)]
const ACORN_GREEN: Array[Color] = [Color8(70, 74, 30), Color8(104, 110, 44), Color8(146, 150, 64), Color8(190, 190, 98)]
const CUP: Array[Color] = [Color8(58, 48, 36), Color8(92, 78, 58), Color8(128, 112, 84), Color8(164, 148, 112)]
const KERNEL: Array[Color] = [Color8(190, 160, 110), Color8(224, 202, 156), Color8(246, 232, 196)]
const SPROUT: Array[Color] = [Color8(150, 50, 60), Color8(200, 86, 92), Color8(236, 140, 136)]
const BOLETE: Array[Color] = [Color8(76, 42, 26), Color8(114, 66, 36), Color8(154, 98, 54), Color8(192, 138, 80), Color8(222, 178, 118)]
const PARASOL: Array[Color] = [Color8(150, 134, 112), Color8(190, 176, 150), Color8(222, 212, 190), Color8(244, 238, 222)]
const GILLS: Array[Color] = [Color8(90, 70, 54), Color8(140, 116, 92)]
const STALK: Array[Color] = [Color8(150, 140, 120), Color8(196, 188, 168), Color8(230, 224, 206), Color8(246, 242, 230)]
const GLOW_CAP: Array[Color] = [Color8(70, 130, 140), Color8(110, 190, 190), Color8(170, 236, 226), Color8(222, 255, 244)]
const BLADE: Array[Color] = [Color8(26, 62, 40), Color8(38, 84, 48), Color8(56, 110, 56), Color8(86, 142, 66), Color8(126, 176, 84), Color8(170, 204, 112)]
const CLOVER: Array[Color] = [Color8(32, 84, 46), Color8(48, 112, 56), Color8(72, 140, 66), Color8(104, 166, 82)]
const CLOVER_MARK := Color8(170, 204, 150)
const DANDELION: Array[Color] = [Color8(190, 128, 20), Color8(234, 178, 30), Color8(252, 218, 70), Color8(255, 242, 150)]
const BELL: Array[Color] = [Color8(54, 54, 140), Color8(84, 88, 186), Color8(124, 132, 224), Color8(176, 184, 246)]
const PETALS: Array[Color] = [Color8(196, 196, 200), Color8(228, 228, 232), Color8(250, 250, 248)]
const DISC: Array[Color] = [Color8(196, 140, 30), Color8(236, 190, 50), Color8(252, 226, 110)]
const OAK_LEAF: Array[Color] = [Color8(96, 54, 26), Color8(140, 84, 36), Color8(180, 118, 48), Color8(210, 156, 68), Color8(232, 192, 104)]
const BIRCH_LEAF: Array[Color] = [Color8(150, 120, 30), Color8(196, 164, 46), Color8(226, 200, 76), Color8(244, 228, 130)]
const NEEDLE: Array[Color] = [Color8(96, 48, 28), Color8(138, 74, 38), Color8(176, 106, 54)]
const VEIN := Color8(84, 50, 24)
const SHELL: Array[Color] = [Color8(90, 58, 34), Color8(136, 94, 54), Color8(184, 140, 86), Color8(222, 190, 136), Color8(244, 226, 186)]
const SHELL_BAND := Color8(70, 42, 26)
const FEATHER: Array[Color] = [Color8(70, 66, 64), Color8(110, 104, 98), Color8(156, 150, 140), Color8(204, 198, 186), Color8(236, 232, 222)]
const DEW := Color(0.72, 0.9, 0.96, 0.78)
const DEW_DARK := Color(0.32, 0.52, 0.62, 0.85)
const AMBER: Array[Color] = [Color(0.52, 0.24, 0.04, 0.95), Color(0.74, 0.4, 0.06, 0.9), Color(0.92, 0.6, 0.14, 0.86),
	Color(0.98, 0.78, 0.32, 0.86), Color(1.0, 0.92, 0.62, 0.9)]
const CAUGHT := Color(0.22, 0.12, 0.06, 0.95)
const BONE: Array[Color] = [Color8(150, 140, 118), Color8(196, 188, 166), Color8(228, 222, 204), Color8(246, 242, 230)]
const BONE_SHADE := Color8(98, 90, 76)
const ROOT_BARK: Array[Color] = [Color8(54, 40, 32), Color8(84, 64, 48), Color8(116, 90, 66)]
const PAD: Array[Color] = [Color8(30, 86, 50), Color8(44, 112, 58), Color8(66, 140, 68), Color8(98, 168, 84), Color8(136, 194, 104)]
const PAD_RIM := Color8(24, 60, 42)
const TRAP_GREEN: Array[Color] = [Color8(40, 90, 40), Color8(62, 122, 48), Color8(98, 156, 62), Color8(146, 190, 86)]
const TRAP_RED: Array[Color] = [Color8(110, 24, 30), Color8(160, 36, 40), Color8(206, 64, 58), Color8(236, 112, 92)]
const TRAP_HAIR := Color8(250, 226, 160)
const PUFF: Array[Color] = [Color8(150, 140, 110), Color8(196, 186, 156), Color8(226, 220, 196), Color8(246, 242, 228)]
const PUFF_SKIN: Array[Color] = [Color8(88, 70, 48), Color8(124, 102, 72), Color8(160, 138, 102)]
const REED_GREEN: Array[Color] = [Color8(34, 78, 50), Color8(50, 102, 56), Color8(84, 138, 72), Color8(150, 176, 106)]


func paint(thing: NelvarEarthData.Thing) -> NelvarEarthArt:
	var rng := RandomNumberGenerator.new()
	rng.seed = thing.appearance_seed
	match thing.kind:
		Kind.ACORN:
			return _acorn(thing, rng)
		Kind.GIANT_MUSHROOM:
			return _giant_mushroom(thing, rng)
		Kind.GRASS_BLADES:
			return _blades(thing, rng)
		Kind.CLOVER:
			return _clover(thing, rng)
		Kind.GIANT_FLOWER:
			return _giant_flower(thing, rng)
		Kind.LEAF:
			return _leaf(thing, rng)
		Kind.TWIG:
			return _twig(thing, rng)
		Kind.SHELL:
			return _shell(thing, rng)
		Kind.FEATHER:
			return _feather(thing, rng)
		Kind.DEW:
			return _dew(thing, rng)
		Kind.AMBER:
			return _amber(thing, rng)
		Kind.BONES:
			return _bones(thing, rng)
		Kind.RIB:
			return _rib(thing, rng)
		Kind.LILY:
			return _pad(thing, rng)
		Kind.REEDS:
			return _tall_reeds(thing, rng)
		Kind.STATUE:
			var art := _statue(thing, rng)
			if thing.variant >= 1:
				_overgrow(art, thing, rng)
			return art
		Kind.ROCK:
			return _rock(thing, rng)
	return super.paint(thing)


# --- Acorns and mushrooms -----------------------------------------------------------------

## An acorn lying on its side like a boulder: glossy, its scaly cup at one end; cracked,
## sprouted (a pink root curling out), or only the cup lying apart.
func _acorn(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.4 - 4.0, -r * 1.6 - 6.0, r * 2.8 + 8.0, r * 2.2 + 8.0))
	var facing := -1.0 if rng.randf() < 0.5 else 1.0
	if thing.variant == 3:
		# The cup alone, lying on its side, its hollow towards us.
		canvas.shadow(Vector2(-1.0, 0.5), Vector2(r * 0.8, r * 0.25 + 0.5))
		var cup := NelvarEarthCanvas.make_blob(rng, Vector2(0.0, -r * 0.35), Vector2(r * 0.75, r * 0.4), 0.0, 0.3, 0.6)
		canvas.blob(cup, CUP)
		_scales(canvas, rng)
		for y in range(-int(r * 0.3), 1):
			for x in range(-int(r * 0.45), int(r * 0.45) + 1):
				var q := Vector2(x / (r * 0.5), (y + r * 0.35) / (r * 0.22))
				if q.length() < 1.0:
					canvas.put_at(Vector2(x, y - r * 0.35), ramp_at(canvas, CUP, 0.1 + q.y * 0.15, x, y))
		canvas.outline_silhouette(OUTLINE, 0.45)
		return NelvarEarthArt.from_canvas(canvas)
	canvas.shadow(Vector2(-1.0, 0.5), Vector2(r * 1.05, r * 0.32 + 0.5))
	var body := NelvarEarthCanvas.make_blob(rng, Vector2(-facing * r * 0.12, -r * 0.62), Vector2(r * 0.95, r * 0.6),
		0.05, 0.08, 2.0, 0.04)
	canvas.blob(body, ACORN if rng.randf() < 0.75 else ACORN_GREEN)
	# The cup over the end toward `facing`.
	var cup := NelvarEarthCanvas.make_blob(rng, Vector2(facing * r * 0.62, -r * 0.64), Vector2(r * 0.42, r * 0.66), -0.05, 0.35, 2.0, 0.1)
	canvas.blob(cup, CUP)
	_scales(canvas, rng, facing * r * 0.62, r * 0.42)
	# A glossy highlight.
	var shine := canvas.pixel(Vector2(-facing * r * 0.05 + r * 0.25, -r * 0.95))
	for dx in range(0, maxi(2, int(r * 0.3))):
		canvas.image.set_pixel(clampi(shine.x + dx, 0, canvas.size.x - 1), clampi(shine.y, 0, canvas.size.y - 1), Color8(250, 236, 200))
	# The stalk and the pointed tip.
	canvas.put_at(Vector2(facing * (r * 1.06), -r * 0.66), CUP[0], 0.2)
	canvas.put_at(Vector2(facing * (r * 1.16), -r * 0.7), CUP[1], 0.3)
	canvas.put_at(Vector2(-facing * (r * 1.06), -r * 0.6), ACORN[0], 0.2)
	canvas.outline_silhouette(OUTLINE, 0.42)
	if thing.variant == 1:
		# Split open: a crack with the pale kernel showing.
		var x := canvas.pixel(Vector2(-facing * r * 0.25, 0.0)).x
		for k in int(r * 1.0):
			var p := canvas.pixel(Vector2(-facing * r * 0.25 + sin(k * 0.9) * 1.2, -r * 1.12 + k))
			if canvas.is_body(p.x, p.y):
				canvas.image.set_pixelv(p, OUTLINE)
				if canvas.is_body(p.x + 1, p.y):
					canvas.image.set_pixel(p.x + 1, p.y, KERNEL[1 + (k % 2)])
		x += 0
	elif thing.variant == 2:
		# Sprouted: a root curls out of the tip, a first leaf on it.
		var at := Vector2(-facing * r * 1.0, -r * 0.6)
		for k in int(r * 1.3):
			var t := k / (r * 1.3)
			var p := at + Vector2(-facing * k * 0.8, -sin(t * PI) * r * 0.5 + t * r * 0.5)
			canvas.put_at(p, SPROUT[1] if k % 3 else SPROUT[2], 0.7)
			canvas.put_at(p + Vector2(0, 1), SPROUT[0], 0.5)
		var leaf := at + Vector2(-facing * r * 0.3, -r * 0.6)
		for k in 4:
			canvas.put_at(leaf + Vector2(-facing * k * 0.7, -k * 0.6), BLADE[3], 0.8)
			canvas.put_at(leaf + Vector2(-facing * k * 0.7, -k * 0.6 + 1), BLADE[2], 0.6)
	return NelvarEarthArt.from_canvas(canvas)


func ramp_at(canvas: NelvarEarthCanvas, colors: Array[Color], level: float, x: int, y: int) -> Color:
	return canvas.ramp(colors, level, x, y)


## The scales of an acorn cup: dark pixel edges in rows over what is painted with CUP.
func _scales(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, center_x: float = 0.0, reach: float = 1e6) -> void:
	for y in canvas.size.y:
		for x in canvas.size.x:
			if not canvas.is_body(x, y):
				continue
			var at := canvas.center_of(x, y)
			if absf(at.x - center_x) > reach * 1.1:
				continue
			var color := canvas.image.get_pixel(x, y)
			if not CUP.has(Color8(color.r8, color.g8, color.b8)):
				continue
			var cell := canvas.grid + Vector2i(x, y)
			if (cell.y % 2 == 0 and (cell.x + cell.y / 2) % 3 == 0):
				canvas.image.set_pixel(x, y, CUP[0])


## A giant mushroom: a stem one can walk round, a cap high above like a roof (the cap thins
## out while the player is under or behind it). The tunnel's small ones glow.
func _giant_mushroom(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var cap := thing.size.x / STEP
	var height := thing.size.y / STEP
	var stem := maxf(1.5, thing.radius / STEP)
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-cap - 4.0, -height - cap * 0.6 - 4.0, cap * 2.0 + 8.0, height + cap * 0.6 + 8.0))
	var glowing := thing.variant == 2
	canvas.shadow(Vector2(-cap * 0.25, 1.0), Vector2(cap * (0.5 if glowing else 0.9), maxf(2.0, cap * 0.22)))
	var salt := rng.randi() & 0xffff
	var lean := rng.randf_range(-0.12, 0.12) * height
	# The stem: a pale column, thicker at the foot.
	for y in range(0, int(height) + 1):
		var t := y / height
		var w := stem * (1.0 + (1.0 - t) * (1.0 - t) * 0.6)
		var cx := lean * t * t
		for x in range(int(floor(cx - w)), int(ceil(cx + w)) + 1):
			var u := (x + 0.5 - cx) / w
			if absf(u) > 1.0:
				continue
			var level := 0.45 + u * 0.35 + canvas.grain(x, y, 0.4, salt) * 0.2
			var color := canvas.ramp(STALK if not glowing else GLOW_CAP, level - (0.2 if glowing else 0.0), x, y)
			if u < -0.8:
				color = OUTLINE
			canvas.put_at(Vector2(x, -0.5 - y), color, level)
	var top := Vector2(lean, -height)
	var colors := GLOW_CAP if glowing else (BOLETE if thing.variant == 0 else PARASOL)
	# The cap: a dome, its dark gills along the underside.
	var dome := Vector2(cap, cap * (0.55 if thing.variant == 0 else 0.4))
	var from := canvas.pixel(top - dome - Vector2.ONE)
	var to := canvas.pixel(top + Vector2(dome.x, dome.y * 0.35) + Vector2.ONE)
	for y in range(maxi(0, from.y), mini(canvas.size.y, to.y + 1)):
		for x in range(maxi(0, from.x), mini(canvas.size.x, to.x + 1)):
			var local := canvas.center_of(x, y) - top
			var q := Vector2(local.x / dome.x, local.y / dome.y)
			if q.y > 0.3 or q.length() > 1.0 + 0.05 * sin(atan2(q.y, q.x) * 7.0):
				continue
			var nz := sqrt(maxf(0.0, 1.0 - q.length_squared()))
			var level := 0.35 + 0.5 * (q.x * 0.42 - q.y * 0.58 * 0.5 + nz * 0.6)
			var color := canvas.ramp(colors, level + canvas.grain(x, y, 0.5, salt + 1) * 0.15, x, y)
			if q.y > 0.05:
				color = canvas.ramp(GILLS if not glowing else GLOW_CAP, 0.3 + q.x * 0.2, x, y)
			elif thing.variant == 1 and not glowing and NelvarPixelArt.hash01(canvas.grid.x + x, canvas.grid.y + y, salt) < 0.07:
				color = PARASOL[0]
			canvas.image.set_pixel(x, y, Color(color, FADES / 255.0) if not glowing else color)
			canvas.body[y * canvas.size.x + x] = 1
			canvas.levels[y * canvas.size.x + x] = level
	canvas.outline_silhouette(OUTLINE, 0.36)
	# The outline must keep the cap's alpha (the part that thins out).
	for y in canvas.size.y:
		for x in canvas.size.x:
			if canvas.is_body(x, y) and canvas.center_of(x, y).y < top.y + dome.y * 0.35 and not glowing:
				var c := canvas.image.get_pixel(x, y)
				canvas.image.set_pixel(x, y, Color(c, FADES / 255.0))
	var art := NelvarEarthArt.from_canvas(canvas)
	return art


# --- Plants -------------------------------------------------------------------------------

## A clump of grass blades taller than the player: a few broad blades bending outwards,
## dark at the foot, light at the tips; some carry a seed head.
func _blades(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var height := thing.size.y / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 2.4 - 4.0, -height - 6.0, r * 4.8 + 8.0, height + 9.0))
	canvas.shadow(Vector2(-1.0, 0.5), Vector2(r * 1.2, 2.5))
	var blades: Array[Vector4] = []
	for i in rng.randi_range(4, 7):
		var base := rng.randf_range(-1.0, 1.0) * r * 0.7
		var tall := height * rng.randf_range(0.55, 1.0)
		var bend := (base / maxf(r, 1.0)) * 0.6 + rng.randf_range(-0.35, 0.35)
		blades.append(Vector4(base, tall, bend, rng.randf_range(1.6, 3.0)))
	blades.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.y > b.y)
	var seeds := rng.randf() < 0.35
	for blade in blades:
		var length := int(blade.y)
		for k in length:
			var t := float(k) / maxf(1.0, blade.y)
			var center := Vector2(blade.x + blade.z * t * t * blade.y * 0.5, -0.5 - k)
			var w := blade.w * (1.0 - t * 0.85)
			for dx in range(-int(ceil(w)), int(ceil(w)) + 1):
				if absf(dx) > w:
					continue
				var u := dx / maxf(w, 0.5)
				var level := 0.12 + t * 0.7 + u * 0.18
				var p := center + Vector2(dx, 0)
				var color := canvas.ramp(BLADE, level, canvas.pixel(p).x, canvas.pixel(p).y)
				if dx == -int(ceil(w)) and t < 0.9:
					color = BLADE[0]
				elif absf(u) < 0.25 and t > 0.1 and t < 0.85:
					color = BLADE[mini(5, 2 + int(t * 3.0))]
				canvas.put_at(p, color, level)
		if seeds and blade.y > height * 0.8:
			var tip := Vector2(blade.x + blade.z * blade.y * 0.5, -blade.y)
			for k in 5:
				canvas.put_at(tip + Vector2(0, -k), SEED_HEAD[1] if k % 2 else SEED_HEAD[0], 0.8)
				canvas.put_at(tip + Vector2(1, -k), SEED_HEAD[0], 0.6)
	var art := NelvarEarthArt.from_canvas(canvas)
	art.sway = 2
	return art


## A clover: three heart-shaped leaflets with a pale mark, on a short stem.
func _clover(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var stem := r * rng.randf_range(0.5, 0.8)
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.6 - 4.0, -stem - r * 1.4 - 6.0, r * 3.2 + 8.0, stem + r * 1.4 + 9.0))
	canvas.shadow(Vector2(-1.0, 0.5), Vector2(r * 1.1, 2.0))
	for k in int(stem):
		canvas.put_at(Vector2(sin(k * 0.3) * 0.5, -0.5 - k), CLOVER[1], 0.3)
	var top := Vector2(0.0, -stem)
	var turn := rng.randf() * TAU
	var leaflets: Array[Vector2] = []
	for i in 3:
		var angle := turn + TAU * i / 3.0
		leaflets.append(top + Vector2(cos(angle), sin(angle) * 0.55) * r * 0.55)
	leaflets.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)
	for leaf in leaflets:
		var b := NelvarEarthCanvas.make_blob(rng, leaf, Vector2(r * 0.55, r * 0.38), 0.0, 0.12, 2.0, 0.18)
		b.rim = CLOVER[0]
		canvas.blob(b, CLOVER)
		# The pale chevron across the leaflet.
		var mark := canvas.pixel(leaf)
		for dx in range(-2, 3):
			canvas.image.set_pixel(clampi(mark.x + dx, 0, canvas.size.x - 1), clampi(mark.y - absi(dx) / 2, 0, canvas.size.y - 1), CLOVER_MARK)
	var art := NelvarEarthArt.from_canvas(canvas)
	art.sway = 1
	return art


## A flower taller than the player: a dandelion, a bluebell or a daisy; leaves at its foot.
func _giant_flower(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var height := thing.size.y / STEP
	var head := height * 0.18 + 4.0
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-head * 2.2 - 8.0, -height - head * 1.6 - 6.0, head * 4.4 + 16.0, height + head * 1.6 + 9.0))
	canvas.shadow(Vector2(-head * 0.4, 0.5), Vector2(head * 1.2, 2.5))
	var lean := rng.randf_range(-0.12, 0.12) * height
	var salt := rng.randi() & 0xffff
	# Leaves at the foot.
	for i in rng.randi_range(3, 5):
		var side := -1.0 if i % 2 == 0 else 1.0
		var length := rng.randf_range(0.18, 0.3) * height
		for k in int(length):
			var t := k / length
			var p := Vector2(side * k * 0.8, -t * length * 0.5 + t * t * length * 0.35)
			var w := 1.5 * sin(t * PI) + 0.5
			for dy in range(-int(w), int(w) + 1):
				canvas.put_at(p + Vector2(0, dy), canvas.ramp(BLADE, 0.3 + t * 0.4 - dy * 0.1, 0, 0), 0.5)
	# The stem.
	var stem := Vector2.ZERO
	for k in int(height):
		var t := k / height
		stem = Vector2(lean * t * t, -0.5 - k)
		canvas.put_at(stem, BLADE[2], 0.5)
		canvas.put_at(stem + Vector2(1, 0), BLADE[3], 0.6)
		canvas.put_at(stem + Vector2(-1, 0), BLADE[1], 0.3)
	var crown := Vector2(lean, -height)
	match thing.variant:
		0:
			# Dandelion: a dense head of narrow petals.
			for ring in range(int(head), 0, -1):
				var count := int(ring * 4.5) + 4
				for i in count:
					var angle := TAU * (i + NelvarPixelArt.hash01(ring, i, salt)) / count
					var p := crown + Vector2(cos(angle), sin(angle) * 0.75) * ring
					var level := 0.35 + float(int(head) - ring) / head * 0.5 + cos(angle - 0.8) * 0.15
					canvas.put_at(p, canvas.ramp(DANDELION, level, canvas.pixel(p).x, canvas.pixel(p).y), level)
			canvas.put_at(crown, DANDELION[3], 1.0)
		1:
			# Bluebell: the stem arches over, bells hang from it.
			var bells := rng.randi_range(3, 4)
			for i in bells:
				var t := (i + 0.5) / bells
				var at := crown + Vector2(t * head * 2.2, -sin(t * PI) * head * 0.5 + t * head * 0.8)
				for k in 2:
					canvas.put_at(at + Vector2(0, k), BLADE[2], 0.5)
				var bell := at + Vector2(0, 2.0 + head * 0.45)
				var size := head * 0.42
				for y in range(-int(size), int(size) + 1):
					var w := size * (0.5 + 0.5 * (y + size) / (2.0 * size))
					for x in range(-int(w), int(w) + 1):
						var level := 0.3 + x / maxf(w, 1.0) * 0.3 - y / size * 0.15
						var color := canvas.ramp(BELL, level, x, y)
						if y >= int(size):
							color = BELL[0] if x % 2 == 0 else BELL[3]
						canvas.put_at(bell + Vector2(x, y), color, level)
		_:
			# Daisy: white rays round a yellow disc.
			var rays := rng.randi_range(14, 20)
			for i in rays:
				var angle := TAU * i / rays
				for k in range(int(head * 0.35), int(head * 1.05)):
					var p := crown + Vector2(cos(angle), sin(angle) * 0.6) * k
					var level := 0.5 + cos(angle - 0.8) * 0.3
					canvas.put_at(p, canvas.ramp(PETALS, level, 0, 0), level)
					if k > head * 0.5:
						canvas.put_at(p + Vector2(-sin(angle), cos(angle) * 0.6), PETALS[1], level)
			for y in range(-int(head * 0.35), int(head * 0.35) + 1):
				for x in range(-int(head * 0.4), int(head * 0.4) + 1):
					if Vector2(x / (head * 0.4), y / (head * 0.3)).length() < 1.0:
						canvas.put_at(crown + Vector2(x, y), canvas.ramp(DISC, 0.5 + x / head - y / head, x, y), 0.8)
	canvas.outline_silhouette(OUTLINE, 0.25)
	var art := NelvarEarthArt.from_canvas(canvas)
	art.sway = 1
	return art


## Reeds taller than the player at the shore; some carry brown heads.
func _tall_reeds(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var height := thing.size.y / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.6 - 4.0, -height - 6.0, r * 3.2 + 8.0, height + 9.0))
	for dx in range(-int(r) - 1, int(r) + 2):
		if absi(dx) > 1 and rng.randf() < 0.6:
			var p := canvas.pixel(Vector2(dx, 0.5))
			canvas.image.set_pixelv(p.clamp(Vector2i.ZERO, canvas.size - Vector2i.ONE), RIPPLE)
	for i in rng.randi_range(6, 10):
		var base := rng.randf_range(-r, r)
		var tall := height * rng.randf_range(0.55, 1.0)
		var lean := rng.randf_range(-0.12, 0.25)
		var with_head := rng.randf() < 0.45
		for k in int(tall):
			var t := k / tall
			var point := Vector2(base + lean * t * t * tall * 0.4, -0.5 - k)
			var color := canvas.ramp(REED_GREEN, 0.12 + t * 0.7, 0, 0)
			if with_head and k >= int(tall) - 9 and k < int(tall) - 2:
				color = CATTAIL[1] if k % 2 == 0 else CATTAIL[0]
				canvas.put_at(point + Vector2(1, 0), CATTAIL[0], t)
			canvas.put_at(point, color, t)
			if k < tall * 0.7:
				canvas.put_at(point + Vector2(1, 0), REED_GREEN[0 if k % 3 else 1], t)
	var art := NelvarEarthArt.from_canvas(canvas)
	art.sway = 1
	return art


## A lily pad as big as a room: a disc with its notch, veins from the middle, a rim; now
## and then a flower or a drop of dew on it.
func _pad(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r - 3.0, -r - 6.0, r * 2.0 + 6.0, r * 2.0 + 9.0))
	var notch := rng.randf() * TAU
	var salt := rng.randi() & 0xffff
	var from := canvas.pixel(-Vector2.ONE * (r + 1.0))
	var to := canvas.pixel(Vector2.ONE * (r + 1.0))
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var local := canvas.center_of(x, y)
			var d := local.length() / r
			var angle := local.angle()
			var edge := 1.0 + 0.03 * sin(angle * 9.0 + salt)
			if d > edge:
				continue
			if d > 0.08 and absf(angle_difference(angle, notch)) < 0.16:
				continue
			var level := 0.5 + local.x / r * 0.2 - local.y / r * 0.2 + canvas.grain(x, y, 0.3, salt) * 0.25
			var color := canvas.ramp(PAD, level, x, y)
			var vein := absf(fposmod(angle * 14.0 / TAU + 0.5, 1.0) - 0.5)
			if vein < 0.05 and d > 0.1 and d < 0.92:
				color = PAD[3]
			if d > edge - 0.08:
				color = PAD_RIM if local.y > 0.0 else PAD[1]
			canvas.put(x, y, color, level)
	if thing.accent:
		var flower := Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.2)) * r
		for i in 8:
			var angle := TAU * i / 8.0
			for k in range(1, 4):
				canvas.put_at(flower + Vector2(cos(angle), sin(angle) * 0.7) * k + Vector2(0, -2), LILY_FLOWER[mini(2, k - 1)])
		canvas.put_at(flower + Vector2(0, -2), DISC[1])
	for i in rng.randi_range(0, 2):
		var drop := Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5)) * r
		_drop_pixels(canvas, drop, rng.randf_range(1.5, 2.5))
	return NelvarEarthArt.from_canvas(canvas)


# --- Litter ---------------------------------------------------------------------------------

## A fallen leaf as big as a raft, flat on the ground: an oak's lobed leaf, a birch's, or a
## tuft of pine needles; veins, a curled edge throwing a little shadow.
func _leaf(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r - 4.0, -r - 4.0, r * 2.0 + 8.0, r * 2.0 + 8.0))
	var angle := rng.randf() * TAU
	var axis := Vector2.from_angle(angle)
	var salt := rng.randi() & 0xffff
	if thing.variant == 2:
		# Pine needles: long thin lines from one point.
		var root := Vector2.ZERO
		for i in rng.randi_range(5, 9):
			var direction := axis.rotated(rng.randf_range(-0.6, 0.6))
			var length := r * rng.randf_range(0.6, 1.0)
			for k in int(length):
				var p := root + direction * (k - length * 0.4)
				canvas.put_at(p, canvas.ramp(NEEDLE, 0.3 + k / length * 0.5, 0, 0), 0.5)
		return NelvarEarthArt.from_canvas(canvas)
	var colors := OAK_LEAF if thing.variant == 0 else BIRCH_LEAF
	var from := canvas.pixel(-Vector2.ONE * (r + 1.0))
	var to := canvas.pixel(Vector2.ONE * (r + 1.0))
	var lobes := 4.0 if thing.variant == 0 else 0.0
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var local := canvas.center_of(x, y)
			var u := local.dot(axis) / r
			var v := local.dot(axis.orthogonal()) / r
			if absf(u) > 1.0:
				continue
			# The leaf's half width along it: an oval, lobed for an oak, toothed for a birch.
			var t := (u + 1.0) * 0.5
			var half := sin(t * PI) * (0.36 if thing.variant == 1 else 0.42) * (1.0 - t * 0.15)
			if lobes > 0.0:
				half *= 0.72 + 0.28 * absf(sin(t * PI * lobes))
			else:
				half *= 0.95 + 0.05 * sin(t * 60.0)
			if absf(v) > half:
				continue
			var level := 0.45 + v * 0.4 + canvas.grain(x, y, 0.35, salt) * 0.25
			var color := canvas.ramp(colors, level, x, y)
			if absf(v) < 0.025 or (absf(absf(v) - absf(fmod(u + 2.0, 0.28) - 0.14) * 1.2) < 0.02 and absf(v) < half * 0.8):
				color = VEIN
			if absf(v) > half - 0.035:
				color = colors[0]
			canvas.put(x, y, color, level)
	# The stalk.
	for k in int(r * 0.25):
		canvas.put_at(-axis * (r + k * 0.8), VEIN, 0.3)
	return NelvarEarthArt.from_canvas(canvas)


## A twig lying like a log: bark, a couple of side shoots, a broken end.
func _twig(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var art := _log(thing, rng)
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(art.local_rect.position / STEP - Vector2(0, 8),
		art.local_rect.size / STEP + Vector2(0, 8)))
	canvas.image.blit_rect(art.image, Rect2i(Vector2i.ZERO, art.image.get_size()), Vector2i(0, 8))
	for y in canvas.size.y:
		for x in canvas.size.x:
			if canvas.image.get_pixel(x, y).a > 0.9:
				canvas.body[y * canvas.size.x + x] = 1
	var half := thing.size.x / STEP * 0.5
	var r := thing.radius / STEP
	for i in rng.randi_range(1, 3):
		var at := Vector2(rng.randf_range(-half * 0.6, half * 0.4), -r * 1.6)
		var direction := Vector2(rng.randf_range(-0.6, 0.6), -1.0).normalized()
		var length := rng.randf_range(4.0, 9.0)
		for k in int(length):
			var p := at + direction * k
			var px := canvas.pixel(p)
			if canvas.inside(px.x, px.y) and not canvas.is_body(px.x, px.y):
				canvas.put(px.x, px.y, BARK[1] if k % 2 else BARK[2], 0.5)
				canvas.put(px.x + 1, px.y, OUTLINE, 0.2)
	return NelvarEarthArt.from_canvas(canvas)


## An empty snail shell as big as a boulder: a spiral of brown bands, the dark mouth.
func _shell(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.3 - 4.0, -r * 1.8 - 5.0, r * 2.6 + 8.0, r * 2.2 + 8.0))
	canvas.shadow(Vector2(-1.0, 0.5), Vector2(r * 1.05, r * 0.3 + 0.5))
	var center := Vector2(rng.randf_range(-0.1, 0.1) * r, -r * 0.85)
	var facing := -1.0 if rng.randf() < 0.5 else 1.0
	var salt := rng.randi() & 0xffff
	var from := canvas.pixel(center - Vector2.ONE * (r + 1.0))
	var to := canvas.pixel(center + Vector2.ONE * (r + 1.0))
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var local := (canvas.center_of(x, y) - center) / r
			var d := local.length()
			if d > 1.0 or local.y > 0.85:
				continue
			var angle := atan2(local.y, local.x * facing)
			# The spiral: bands winding in towards the apex.
			var turn := fposmod(log(maxf(d, 0.05)) / log(0.58) * TAU - angle, TAU) / TAU
			var nz := sqrt(maxf(0.0, 1.0 - d * d))
			var level := 0.35 + local.x * 0.25 - local.y * 0.2 + nz * 0.3
			var color := canvas.ramp(SHELL, level + canvas.grain(x, y, 0.5, salt) * 0.15, x, y)
			if turn < 0.08:
				color = SHELL_BAND
			elif turn < 0.16:
				color = canvas.ramp(SHELL, level - 0.3, x, y)
			canvas.put(x, y, color, level)
	# The mouth, dark, on the lower side.
	var mouth := center + Vector2(-facing * r * 0.55, r * 0.45)
	for y in range(-int(r * 0.4), int(r * 0.3)):
		for x in range(-int(r * 0.45), int(r * 0.45) + 1):
			var q := Vector2(x / (r * 0.45), y / (r * 0.35))
			if q.length() < 1.0:
				canvas.put_at(mouth + Vector2(x, y), HOLLOW_DARK if q.length() < 0.7 else SHELL[3], 0.1)
	canvas.outline_silhouette(OUTLINE, 0.4)
	return NelvarEarthArt.from_canvas(canvas)

const HOLLOW_DARK := Color8(30, 20, 16)


## A feather lying flat: the shaft and the vane with its barred pattern.
func _feather(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var length := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-length - 4.0, -length - 4.0, length * 2.0 + 8.0, length * 2.0 + 8.0))
	var axis := Vector2.from_angle(rng.randf() * TAU)
	var normal := axis.orthogonal()
	var curve := rng.randf_range(-0.15, 0.15)
	var salt := rng.randi() & 0xffff
	for k in int(length * 2.0):
		var t := k / (length * 2.0)
		var spine := axis * (k - length) + normal * curve * sin(t * PI) * length
		var vane := sin(clampf(t * 1.15, 0.0, 1.0) * PI) * length * 0.22 + 1.0
		for side: float in [-1.0, 1.0]:
			for j in range(1, int(vane * (0.85 if side < 0.0 else 1.0)) + 1):
				var p := spine + normal * side * j - axis * j * 0.35
				var bar := fposmod(k * 0.5 + j * 0.2, 3.0) < 1.0
				var level := 0.4 + side * 0.15 + canvas.grain(k, j, 0.4, salt) * 0.3 - (0.2 if bar else 0.0)
				canvas.put_at(p, canvas.ramp(FEATHER, level, k, j), level)
		canvas.put_at(spine, FEATHER[4], 0.8)
	return NelvarEarthArt.from_canvas(canvas)


## A drop of dew the size of the player's head: clear, a bright highlight, a dark rim below.
func _dew(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r - 3.0, -r * 2.0 - 3.0, r * 2.0 + 6.0, r * 2.0 + 5.0))
	_drop_pixels(canvas, Vector2(0.0, -r * 0.9), r)
	return NelvarEarthArt.from_canvas(canvas)


func _drop_pixels(canvas: NelvarEarthCanvas, center: Vector2, r: float) -> void:
	for y in range(-int(ceil(r)) - 1, int(ceil(r)) + 2):
		for x in range(-int(ceil(r)) - 1, int(ceil(r)) + 2):
			var q := Vector2(x + 0.5, y + 0.5) / r
			if q.length() > 1.0 or q.y > 0.85:
				continue
			var color := DEW
			if q.y > 0.4 or (q.x < -0.6 and q.y > -0.2):
				color = DEW_DARK
			if (q - Vector2(0.35, -0.4)).length() < 0.28:
				color = Color(1, 1, 1, 0.95)
			canvas.put_at(center + Vector2(x, y), color, 0.9)


## A drop of amber, translucent gold, with a creature caught in it: a beetle, a centipede
## or a lizard; `accent`: the creature's eye watches (the thing's eye).
func _amber(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.3 - 4.0, -r * 2.2 - 4.0, r * 2.6 + 8.0, r * 2.6 + 7.0))
	canvas.shadow(Vector2(-1.0, 0.5), Vector2(r * 1.05, r * 0.3 + 0.5))
	var center := Vector2(0.0, -r * 0.95)
	var b := NelvarEarthCanvas.make_blob(rng, center, Vector2(r, r * 0.95), 0.05, 0.05, 2.0, 0.08)
	canvas.blob(b, AMBER)
	# The creature, dark through the gold.
	var head := Vector2.INF
	match thing.variant:
		0:
			for y in range(-int(r * 0.4), int(r * 0.4) + 1):
				for x in range(-int(r * 0.3), int(r * 0.3) + 1):
					if Vector2(x / (r * 0.3), y / (r * 0.42)).length() < 1.0:
						canvas.put_at(center + Vector2(x, y), CAUGHT, 0.2)
			for i in 3:
				for side: float in [-1.0, 1.0]:
					canvas.put_at(center + Vector2(side * (r * 0.3 + 1.0), -r * 0.2 + i * r * 0.2), CAUGHT, 0.2)
			head = center + Vector2(0.0, -r * 0.48)
		1:
			for k in int(r * 1.4):
				var p := center + Vector2(k - r * 0.7, sin(k * 0.6) * r * 0.2)
				canvas.put_at(p, CAUGHT, 0.2)
				if k % 2 == 0:
					canvas.put_at(p + Vector2(0, -1), CAUGHT, 0.2)
					canvas.put_at(p + Vector2(0, 1), CAUGHT, 0.2)
			head = center + Vector2(r * 0.7, 0.0)
		_:
			for k in int(r * 1.5):
				var t := float(k) / (r * 1.5)
				var p := center + Vector2(k - r * 0.75, sin(t * PI * 1.5) * r * 0.25)
				var w := 2 if t > 0.3 and t < 0.7 else (1 if t < 0.9 else 0)
				for dy in range(-w, w + 1):
					canvas.put_at(p + Vector2(0, dy), CAUGHT, 0.2)
			head = center + Vector2(r * 0.7, 0.0)
	# The light caught in the gold.
	var shine := center + Vector2(r * 0.35, -r * 0.5)
	canvas.put_at(shine, Color(1, 0.98, 0.86, 0.95), 1.0)
	canvas.put_at(shine + Vector2(1, 0), Color(1, 0.94, 0.7, 0.9), 1.0)
	canvas.put_at(shine + Vector2(0, 1), Color(1, 0.94, 0.7, 0.9), 1.0)
	var art := NelvarEarthArt.from_canvas(canvas)
	if thing.accent and head.is_finite():
		var p := canvas.pixel(head)
		art.eye = canvas.center_of(p.x, p.y) - Vector2(0.5, 0.5)
	return art


## Bones lying about: a few ribs, a skull, a row of vertebrae, or the spine under the arch
## of ribs.
func _bones(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var r := thing.radius / STEP
	var reach := maxf(r, thing.size.x / STEP * 0.55 + 4.0)
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-reach - 4.0, -r - 6.0, reach * 2.0 + 8.0, r * 2.0 + 10.0))
	match thing.variant:
		0:
			for i in rng.randi_range(3, 5):
				var at := Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.4, 0.4)) * r
				var direction := Vector2.from_angle(rng.randf() * TAU)
				var length := r * rng.randf_range(0.6, 1.0)
				for k in int(length):
					var t := k / length
					var p := at + direction * k + direction.orthogonal() * sin(t * PI) * length * 0.2
					canvas.put_at(p, canvas.ramp(BONE, 0.6 - t * 0.2, 0, 0), 0.6)
					canvas.put_at(p + Vector2(0, 1), BONE_SHADE, 0.2)
		1:
			var b := NelvarEarthCanvas.make_blob(rng, Vector2(0.0, -r * 0.5), Vector2(r * 0.7, r * 0.55), 0.1, 0.05, 2.0, 0.05)
			canvas.blob(b, BONE)
			for side: float in [-1.0, 1.0]:
				for y in range(-1, 2):
					for x in range(-1, 2):
						canvas.put_at(Vector2(side * r * 0.3 + x, -r * 0.55 + y), HOLLOW_DARK, 0.0)
			for x in range(-int(r * 0.3), int(r * 0.3) + 1):
				canvas.put_at(Vector2(x, -r * 0.05), BONE_SHADE if x % 2 else BONE[2], 0.4)
			canvas.outline_silhouette(BONE_SHADE, 0.4)
		_:
			var length := thing.size.x / STEP if thing.variant == 3 else r * 1.8
			var count := maxi(3, int(length / 5.0))
			for i in count:
				var p := Vector2(-length * 0.5 + i * length / count, sin(i * 0.5) * 1.5)
				for y in range(-2, 3):
					for x in range(-2, 2):
						if Vector2(x + 0.5, y).length() < 2.4:
							canvas.put_at(p + Vector2(x, y), canvas.ramp(BONE, 0.6 + x * 0.1 - y * 0.1, x, y), 0.6)
				canvas.put_at(p + Vector2(0, -3), BONE[1], 0.5)
	return NelvarEarthArt.from_canvas(canvas)


## One rib of something enormous standing out of the ground and curving over, roots
## wound round it.
func _rib(thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> NelvarEarthArt:
	var height := thing.size.y / STEP
	var w := thing.radius / STEP * 0.6 + 1.0
	var side := -1.0 if thing.variant == 0 else 1.0
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-height * 0.6 - w - 4.0, -height - 6.0, height * 1.2 + w * 2.0 + 8.0, height + 10.0))
	canvas.shadow(Vector2(-2.0, 0.5), Vector2(w * 2.0 + 2.0, 2.0))
	var salt := rng.randi() & 0xffff
	for k in int(height * 1.2):
		var t := k / (height * 1.2)
		# Up, then curving over towards the spine across the way.
		var p := Vector2(side * sin(t * PI * 0.5) * t * height * 0.45, -sin(t * PI * 0.62) * height)
		var thick := w * (1.0 - t * 0.4)
		for dx in range(-int(ceil(thick)), int(ceil(thick)) + 1):
			var u := dx / thick
			var level := 0.45 + u * 0.35 + canvas.grain(k, dx, 0.4, salt) * 0.2
			canvas.put_at(p + Vector2(dx, 0), canvas.ramp(BONE, level, k, dx), level)
	canvas.outline_silhouette(BONE_SHADE, 0.3)
	# Roots wound round it.
	for i in rng.randi_range(2, 4):
		var from := rng.randf_range(0.0, 0.6) * height
		for k in int(height * 0.25):
			var y := -from - k
			var x := sin(k * 0.45 + i) * w * 1.2
			canvas.put_at(Vector2(x, y), ROOT_BARK[1 if k % 3 else 0], 0.3)
	return NelvarEarthArt.from_canvas(canvas)


## Roots grown over a petrified creature (it has sat here long), wood on the wanderer in
## the fallen giant.
func _overgrow(art: NelvarEarthArt, thing: NelvarEarthData.Thing, rng: RandomNumberGenerator) -> void:
	var image := art.image
	var w := image.get_width()
	var h := image.get_height()
	for i in rng.randi_range(4, 7):
		var x := rng.randf_range(0.1, 0.9) * w
		var drift := rng.randf_range(-0.6, 0.6)
		for y in range(int(h * rng.randf_range(0.1, 0.5)), h):
			var px := int(x + drift * y * 0.3 + sin(y * 0.4 + i) * 1.2)
			if px < 0 or px >= w:
				continue
			if image.get_pixel(px, y).a > 0.9:
				image.set_pixel(px, y, ROOT_BARK[(y + i) % 3])
				if px + 1 < w and image.get_pixel(px + 1, y).a > 0.9 and thing.variant == 1:
					image.set_pixel(px + 1, y, ROOT_BARK[0])


## A fallen leaf drifting on a pond as a raft: green or turning yellow, its veins, its edge
## curled up a little (a lit rim, a dark line where it meets the water).
func paint_raft(raft: NelvarThicketData.Raft) -> NelvarEarthArt:
	var rng := RandomNumberGenerator.new()
	rng.seed = raft.appearance_seed
	var half := Vector2(raft.length, raft.width) * 0.5 / STEP
	var reach := half.x + 3.0
	var canvas := NelvarEarthCanvas.new(Vector2.ZERO, Rect2(-reach, -reach, reach * 2.0, reach * 2.0))
	var axis := Vector2.from_angle(raft.angle)
	var colors := PAD if rng.randf() < 0.55 else BIRCH_LEAF
	var salt := rng.randi() & 0xffff
	for y in canvas.size.y:
		for x in canvas.size.x:
			var local := canvas.center_of(x, y)
			var u := local.dot(axis) / half.x
			var v := local.dot(axis.orthogonal()) / half.y
			if u * u + v * v > 1.0:
				continue
			var level := 0.5 + v * 0.2 - u * 0.1 + canvas.grain(x, y, 0.3, salt) * 0.2
			var color := canvas.ramp(colors, level, x, y)
			if absf(v) < 0.06 or absf(absf(v) - absf(fmod(u + 3.0, 0.4) - 0.2) * 1.6) < 0.05:
				color = colors[0]
			var edge := u * u + v * v
			if edge > 0.86:
				color = colors[colors.size() - 1] if local.y < 0.0 else PAD_RIM
			canvas.put(x, y, color, level)
	return NelvarEarthArt.from_canvas(canvas)


# --- The hazards' sprites -------------------------------------------------------------------

## A flytrap in one of its states: 0 open (flat on the ground, red inside, its teeth round
## the rim, three hairs in each lobe), 1 trembling (the hairs up, the lobes lifting), 2 shut
## (the lobes stood up and closed), 3 shut over prey (swollen).
func paint_flytrap(trap: NelvarThicketData.Flytrap, state: int) -> NelvarEarthArt:
	var rng := RandomNumberGenerator.new()
	rng.seed = trap.appearance_seed
	var r := trap.radius / STEP
	var canvas := NelvarEarthCanvas.new(trap.center, Rect2(-r - 6.0, -r * 1.6 - 6.0, r * 2.0 + 12.0, r * 2.6 + 12.0))
	var salt := rng.randi() & 0xffff
	# Leaves of the rosette under it.
	for i in 6:
		var angle := TAU * (i + 0.3) / 6.0 + rng.randf_range(-0.2, 0.2)
		var tip := Vector2(cos(angle), sin(angle) * 0.6) * r * 1.05
		for k in int(r * 0.9):
			var p := tip * (k / (r * 0.9))
			canvas.put_at(p, TRAP_GREEN[1], 0.4)
			canvas.put_at(p + Vector2(0, 1), TRAP_GREEN[0], 0.3)
	if state <= 1:
		var lift := 1.0 if state == 1 else 0.0
		var from := canvas.pixel(-Vector2(r, r * 0.8) - Vector2.ONE * 2.0)
		var to := canvas.pixel(Vector2(r, r * 0.8) + Vector2.ONE * 2.0)
		for y in range(from.y, to.y + 1):
			for x in range(from.x, to.x + 1):
				var local := canvas.center_of(x, y)
				var lobe := 1.0 if local.y > 0.0 else -1.0
				var q := Vector2(local.x / r, (local.y + lobe * lift) / (r * 0.78))
				var d := q.length()
				if d > 1.0 or absf(q.y) < 0.05:
					continue
				var level := 0.45 + q.x * 0.2 - q.y * 0.2 + canvas.grain(x, y, 0.5, salt) * 0.2
				var color := canvas.ramp(TRAP_RED, level, x, y)
				if d > 0.82:
					color = canvas.ramp(TRAP_GREEN, level, x, y)
				canvas.put(x, y, color, level)
		# Teeth along the rim.
		for i in 28:
			var angle := TAU * i / 28.0
			var base := Vector2(cos(angle) * r, sin(angle) * r * 0.78)
			for k in 3:
				canvas.put_at(base + Vector2(cos(angle), sin(angle) * 0.8) * (k + 1) - Vector2(0, lift * signf(sin(angle))),
					TRAP_GREEN[3] if k == 2 else TRAP_GREEN[2], 0.7)
		# The trigger hairs.
		for lobe: float in [-1.0, 1.0]:
			for i in 3:
				var at := Vector2((i - 1) * r * 0.3, lobe * r * 0.35)
				canvas.put_at(at, TRAP_HAIR, 0.9)
				if state == 1:
					canvas.put_at(at + Vector2(0, -1), TRAP_HAIR, 0.9)
					canvas.put_at(at + Vector2(0, -2), TRAP_HAIR, 0.9)
		return NelvarEarthArt.from_canvas(canvas)
	# Shut: the two lobes standing together, the teeth meshed along the top.
	var swell := 1.25 if state == 3 else 1.0
	var tall := r * 1.15 * swell
	for y in range(-int(tall) - 1, 1):
		for x in range(-int(r * swell) - 1, int(r * swell) + 2):
			var q := Vector2(x / (r * swell), (y + 0.5) / tall)
			if Vector2(q.x, q.y + 0.1).length() > 1.0 or q.y > 0.0:
				continue
			var nz := sqrt(maxf(0.0, 1.0 - q.length_squared()))
			var level := 0.35 + q.x * 0.3 + nz * 0.25
			var color := canvas.ramp(TRAP_GREEN, level, x, y)
			if absf(q.x) < 0.08:
				color = TRAP_RED[1]
			elif nz > 0.55 and absf(q.x) < 0.5:
				color = color.lerp(TRAP_RED[2], 0.35)
			canvas.put_at(Vector2(x, y - 0.5), color, level)
	for k in int(tall * 0.9):
		var y := -tall * 0.1 - k
		var side := 1.0 if k % 2 == 0 else -1.0
		for j in 3:
			canvas.put_at(Vector2(side * (j + 1), y - j * 0.3), TRAP_GREEN[3] if j == 2 else TRAP_GREEN[2], 0.7)
	canvas.outline_silhouette(OUTLINE, 0.4)
	return NelvarEarthArt.from_canvas(canvas)


## A puffball: whole (a pale ball with fine warts), or burst (a crumpled brown skin).
func paint_puffball(puffball: NelvarThicketData.Puffball, burst: bool) -> NelvarEarthArt:
	var rng := RandomNumberGenerator.new()
	rng.seed = puffball.appearance_seed
	var r := puffball.radius / STEP
	var canvas := NelvarEarthCanvas.new(puffball.center, Rect2(-r * 1.3 - 4.0, -r * 2.2 - 5.0, r * 2.6 + 8.0, r * 2.6 + 8.0))
	canvas.shadow(Vector2(-1.0, 0.5), Vector2(r * 1.05, r * 0.3 + 0.5))
	if burst:
		var skin := NelvarEarthCanvas.make_blob(rng, Vector2(0.0, -r * 0.35), Vector2(r * 0.95, r * 0.4), -0.1, 0.4, 2.0, 0.25)
		canvas.blob(skin, PUFF_SKIN)
		for y in range(-int(r * 0.25) - 1, 1):
			for x in range(-int(r * 0.3), int(r * 0.3) + 1):
				if Vector2(x / (r * 0.3), y / (r * 0.18)).length() < 1.0:
					canvas.put_at(Vector2(x, y - r * 0.55), HOLLOW_DARK, 0.1)
		canvas.outline_silhouette(OUTLINE, 0.45)
		return NelvarEarthArt.from_canvas(canvas)
	var ball := NelvarEarthCanvas.make_blob(rng, Vector2(0.0, -r * 0.95), Vector2(r, r * 0.92), 0.05, 0.12, 2.0, 0.06)
	canvas.blob(ball, PUFF)
	var inner := canvas.interior()
	for i in int(inner.size() * 0.06):
		var p := inner[rng.randi_range(0, inner.size() - 1)]
		canvas.image.set_pixelv(p, PUFF[0] if rng.randf() < 0.6 else PUFF[3])
	canvas.outline_silhouette(PUFF_SKIN[0], 0.42)
	# The little mouth at the top it bursts from.
	canvas.put_at(Vector2(0.0, -r * 1.82), PUFF_SKIN[1], 0.4)
	return NelvarEarthArt.from_canvas(canvas)
