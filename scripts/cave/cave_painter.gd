class_name NelvarCavePainter
extends NelvarIcePainter
## Bakes what the ice cave adds to the valley's things: crystals — shards, druses,
## hexagonal columns, slabs and fans, clear blue, deep blue or now and then pale violet,
## some glowing — smooth boulders of ice with a pebble or bubbles inside, stalagmites of
## ice or of mineral under the drips, bones half frozen into the floor, creatures caught
## in ice flows at the foot of the walls, the travertine mounds of the geysers' mouths,
## and the bodies floating on open water. Everything else is NelvarIcePainter's (the
## rocks in the dark get a cap of frost: Thing.variant 1).
##
## Stateless: one painter can paint from many worker threads at once.

const Crystal = NelvarCaveData.Crystal
const Tint = NelvarCaveData.Tint
const Part = NelvarCaveData.Part

const CLEAR: Array[Color] = [Color8(70, 122, 162), Color8(104, 162, 198), Color8(150, 202, 226),
	Color8(198, 234, 246), Color8(242, 252, 255)]
const DEEP: Array[Color] = [Color8(30, 52, 112), Color8(44, 80, 152), Color8(70, 116, 192),
	Color8(114, 162, 224), Color8(184, 216, 248)]
const VIOLET: Array[Color] = [Color8(62, 46, 108), Color8(94, 72, 150), Color8(134, 108, 192),
	Color8(178, 156, 226), Color8(228, 214, 252)]
const CRYSTAL_OUTLINE: Array[Color] = [Color8(34, 66, 98), Color8(18, 30, 70), Color8(36, 24, 66)]
## Lit from within: the glowing crystals.
const GLOW: Array[Color] = [Color8(120, 196, 232), Color8(168, 228, 250), Color8(214, 246, 255),
	Color8(246, 255, 255)]
const ICE_STONE: Array[Color] = [Color8(88, 132, 166), Color8(122, 168, 198), Color8(160, 200, 222),
	Color8(200, 228, 240), Color8(236, 248, 252)]
const PEBBLE: Array[Color] = [Color8(70, 76, 90), Color8(96, 102, 114), Color8(126, 130, 140)]
const TRAVERTINE: Array[Color] = [Color8(128, 102, 74), Color8(164, 138, 98), Color8(198, 176, 134),
	Color8(226, 212, 176), Color8(244, 238, 218)]
const TRAVERTINE_OUTLINE := Color8(84, 66, 52)
const POOL: Array[Color] = [Color8(26, 52, 62), Color8(44, 84, 96), Color8(80, 132, 142), Color8(150, 200, 206)]
const BONE: Array[Color] = [Color8(132, 126, 114), Color8(168, 162, 146), Color8(202, 196, 180),
	Color8(230, 226, 214)]
const BONE_OUTLINE := Color8(84, 80, 78)
const GLAZE := Color(0.72, 0.86, 0.96, 0.55)
## The ice flows the creatures are caught in at the foot of the walls.
const FLOW: Array[Color] = [Color8(96, 146, 190), Color8(132, 182, 216), Color8(170, 212, 234),
	Color8(208, 236, 248), Color8(240, 252, 255)]
const FLOW_OUTLINE := Color8(40, 70, 112)
const FANG := Color8(226, 232, 222)
## Bodies on the water: pale and swollen, darker under the waterline.
const CORPSE_TINT := Color(0.78, 0.8, 0.84)


func paint(thing: NelvarIceData.Thing) -> NelvarIceArt:
	var rng := RandomNumberGenerator.new()
	rng.seed = thing.appearance_seed
	match thing.kind:
		Kind.CRYSTAL:
			return _crystal(thing, rng)
		Kind.ICE_STONE:
			return _ice_stone(thing, rng)
		Kind.STALAGMITE:
			return _stalagmite(thing, rng)
		Kind.BONES:
			return _bones(thing, rng)
		Kind.EMBEDDED:
			return _embedded(thing, rng)
		Kind.VENT:
			return _vent(thing, rng)
	return super(thing)


# --- Crystals ---------------------------------------------------------------------------

func _crystal_palette(thing: NelvarIceData.Thing) -> Array[Color]:
	match int(thing.size.x):
		Tint.DEEP:
			return DEEP
		Tint.VIOLET:
			return VIOLET
	return CLEAR


func _crystal(thing: NelvarIceData.Thing, rng: RandomNumberGenerator) -> NelvarIceArt:
	var r := maxf(1.6, thing.radius / STEP)
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 2.6 - 4.0, -r * 4.4 - 5.0, r * 5.2 + 8.0,
		r * 5.0 + 8.0))
	_shadow(canvas, Vector2(-r * 0.2, 0.3), Vector2(r * 1.1 + 0.5, r * 0.35 + 0.8))
	var palette := _crystal_palette(thing)
	var glowing := thing.size.y > 0.5
	if glowing:
		palette = _brighter(palette)
	var glints: Array[Vector2] = []
	match thing.variant:
		Crystal.SHARD:
			_shard(canvas, rng, Vector2.ZERO, r, rng.randf_range(2.2, 3.4), rng.randf_range(-0.5, 0.5), palette, glints)
		Crystal.CLUSTER:
			var shards: Array[Vector4] = []
			for i in rng.randi_range(3, 7):
				var x := rng.randf_range(-0.65, 0.65) * r
				shards.append(Vector4(x, rng.randf_range(-0.3, 0.25) * r, rng.randf_range(1.1, 3.0) * (1.0 - absf(x) / r * 0.4),
					x / r * 0.9 + rng.randf_range(-0.3, 0.3)))
			shards.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.y < b.y)
			for shard in shards:
				_shard(canvas, rng, Vector2(shard.x, shard.y), r * rng.randf_range(0.45, 0.75), shard.z, shard.w,
					palette, glints)
		Crystal.COLUMN:
			var height := r * rng.randf_range(2.0, 3.2)
			var tilt := rng.randf_range(-0.25, 0.25) * r
			_block(canvas, rng, Vector2.ZERO, Vector2(r * 0.62, r * 0.4), height, 0.9, tilt, glints, palette, false, 6)
			_block(canvas, rng, Vector2(tilt, -height + 0.5), Vector2(r * 0.56, r * 0.36), r * rng.randf_range(0.6, 1.1),
				0.06, rng.randf_range(-0.1, 0.1) * r, glints, palette, false, 6)
			if rng.randf() < 0.6:
				_shard(canvas, rng, Vector2(r * 0.7 * (-1.0 if rng.randf() < 0.5 else 1.0), r * 0.1), r * 0.5,
					rng.randf_range(1.0, 1.6), rng.randf_range(-0.6, 0.6), palette, glints)
		Crystal.SLAB:
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			for i in rng.randi_range(2, 4):
				var x := rng.randf_range(-0.5, 0.5) * r
				_block(canvas, rng, Vector2(x, rng.randf_range(-0.2, 0.2) * r), Vector2(r * 0.7, r * 0.14),
					r * rng.randf_range(0.9, 1.7), rng.randf_range(0.5, 0.75), side * rng.randf_range(0.4, 1.0) * r,
					glints, palette, false, 4)
				side = -side if rng.randf() < 0.4 else side
		_:
			var count := rng.randi_range(4, 6)
			for i in count:
				var t := lerpf(-1.0, 1.0, float(i) / (count - 1))
				_shard(canvas, rng, Vector2(t * r * 0.2, absf(t) * -0.1 * r), r * 0.5, rng.randf_range(1.8, 2.9) * (1.0 - absf(t) * 0.3),
					t * 1.25, palette, glints)
	canvas.outline_silhouette(CRYSTAL_OUTLINE[int(thing.size.x)] if not glowing else palette[0], 0.42)
	# Pale streaks of light inside, a bright core when it glows.
	for p in canvas.interior():
		var level := canvas.levels[p.y * canvas.size.x + p.x]
		if glowing and level > 0.55 and rng.randf() < 0.35:
			canvas.image.set_pixelv(p, GLOW[rng.randi_range(2, 3)])
		elif level > 0.7 and rng.randf() < 0.06:
			canvas.image.set_pixelv(p, palette[palette.size() - 1])
	var picked: Array[Vector2] = []
	for i in mini(glints.size(), rng.randi_range(2, 4) if r > 3.0 else 1):
		picked.append(glints[rng.randi_range(0, glints.size() - 1)])
	return _finish(canvas, picked)


## One pointed shard: a narrow six-sided block tapering to a point, leaning by `lean`
## (a share of its height).
func _shard(canvas: NelvarEarthCanvas, rng: RandomNumberGenerator, at: Vector2, r: float, tall: float, lean: float,
		palette: Array[Color], glints: Array[Vector2]) -> void:
	var height := r * tall
	_block(canvas, rng, at, Vector2(r * 0.42, r * 0.28) + Vector2.ONE * 0.4, height, rng.randf_range(0.12, 0.3),
		lean * height * 0.45, glints, palette, false, 6 if r > 2.0 else 4)


func _brighter(palette: Array[Color]) -> Array[Color]:
	var result: Array[Color] = []
	for color in palette:
		result.append(color.lerp(Color(0.86, 0.97, 1.0), 0.28))
	return result


# --- Stone and ice --------------------------------------------------------------------

## A smooth boulder of ice, lit like glass: a pebble or bubbles caught inside, a bright
## highlight, frost round its foot.
func _ice_stone(thing: NelvarIceData.Thing, rng: RandomNumberGenerator) -> NelvarIceArt:
	var r := thing.radius / STEP
	var tall := rng.randf_range(0.72, 1.0)
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.4 - 3.0, -r * 1.9 - 4.0, r * 2.8 + 6.0, r * 2.3 + 6.0))
	_shadow(canvas, Vector2(-r * 0.1, r * 0.1), Vector2(r * 1.15, r * 0.45 + 0.5))
	var base := 0.5 - 0.72 * tall
	if r >= 6.0 and rng.randf() < 0.5:
		canvas.blob(NelvarEarthCanvas.make_blob(rng, Vector2(rng.randf_range(-0.4, 0.4), 0.0) * r,
			Vector2(0.5, 0.45) * r, -0.05, 0.06, 0.75, 0.08), ICE_STONE)
	canvas.blob(NelvarEarthCanvas.make_blob(rng, Vector2(0.0, base) * r, Vector2(0.94, tall) * r, 0.04, 0.05, 0.7, 0.08),
		ICE_STONE)
	# What is caught inside: a dark pebble seen through the ice, or bubbles.
	var inner := canvas.interior()
	if thing.accent and not inner.is_empty():
		var center := canvas.pixel(Vector2(rng.randf_range(-0.25, 0.25) * r, base * r + rng.randf_range(-0.1, 0.2) * r))
		var size := maxf(1.0, r * rng.randf_range(0.2, 0.32))
		for p in inner:
			var d := Vector2(p - center) / Vector2(size * 1.2, size)
			if d.length() < 1.0:
				var color := NelvarPixelArt.ramp(PEBBLE, 0.6 - d.y * 0.4, canvas.grid + p)
				canvas.image.set_pixelv(p, color.lerp(ICE_STONE[2], 0.35))
	else:
		for i in rng.randi_range(2, 6):
			if inner.is_empty():
				break
			var p := inner[rng.randi_range(0, inner.size() - 1)]
			canvas.image.set_pixelv(p, ICE_STONE[4])
			if rng.randf() < 0.4 and canvas.is_body(p.x, p.y + 1):
				canvas.image.set_pixel(p.x, p.y + 1, ICE_STONE[1])
	canvas.outline_silhouette(ICE_OUTLINE, 0.5)
	# The highlight, up and to the right.
	var glints: Array[Vector2] = []
	var top := canvas.pixel(Vector2(r * 0.35, (base - tall * 0.55) * r))
	for offset: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)]:
		if canvas.is_body(top.x + offset.x, top.y + offset.y):
			canvas.image.set_pixel(top.x + offset.x, top.y + offset.y, ICE_STONE[4])
	if canvas.is_body(top.x, top.y):
		glints.append(_corner(canvas, top))
	_frost(canvas, rng, 0.04)
	return _finish(canvas, glints)


## A stalagmite under a drip: a cone with ring ridges, ice or (by the geysers) pale
## mineral, now and then a smaller one beside it; a wet dark spot at its foot.
func _stalagmite(thing: NelvarIceData.Thing, rng: RandomNumberGenerator) -> NelvarIceArt:
	var w := maxf(1.5, thing.radius / STEP * 0.5)
	var height := maxf(5.0, thing.size.y / STEP)
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-w * 3.0 - 3.0, -height - 4.0, w * 6.0 + 6.0, height + 7.0))
	var mineral := thing.variant == 1
	var palette := TRAVERTINE if mineral else ICE_STONE
	var outline := TRAVERTINE_OUTLINE if mineral else ICE_OUTLINE
	_shadow(canvas, Vector2(-w * 0.5, 0.4), Vector2(w * 1.6 + 0.5, 1.4))
	var cones: Array[Vector3] = [Vector3(0.0, w, height)]
	if rng.randf() < 0.55:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		cones.append(Vector3(side * w * rng.randf_range(1.4, 2.0), w * rng.randf_range(0.5, 0.7), height * rng.randf_range(0.35, 0.6)))
	cones.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z > b.z)
	var salt := rng.randi() & 0xffff
	for cone in cones:
		var rows := int(cone.z)
		for k in rows:
			var t := float(k) / maxf(1.0, cone.z - 1.0)
			var ring := 1.0 + 0.18 * sin(float(k) * 1.7 + float(salt % 7))
			var half := cone.y * pow(t, 0.75) * ring + 0.35
			var y := canvas.pixel(Vector2(0.0, -cone.z + k)).y
			var left := canvas.pixel(Vector2(cone.x - half, 0.0)).x
			var right := canvas.pixel(Vector2(cone.x + half, 0.0)).x
			for x in range(left, right + 1):
				var u := (canvas.center_of(x, y).x - cone.x) / maxf(half, 0.5)
				var level := 0.42 + u * 0.32 + (1.0 - t) * 0.15 + canvas.grain(x, y, 0.5, salt) * 0.3
				canvas.put(x, y, canvas.ramp(palette, level, x, y), level)
	canvas.outline_silhouette(outline, 0.5)
	# The wet spot the drip keeps at its foot.
	var foot := canvas.pixel(Vector2(0.0, -0.5))
	for dx in range(-ceili(w * 1.6), ceili(w * 1.6) + 1):
		if not canvas.is_body(foot.x + dx, foot.y) and canvas.inside(foot.x + dx, foot.y):
			canvas.image.set_pixel(foot.x + dx, foot.y, Color(0.1, 0.14, 0.2, 0.35))
	var tip := canvas.pixel(Vector2(cones[0].x, -cones[0].z + 0.5))
	return _finish(canvas, [_corner(canvas, tip)] if canvas.is_body(tip.x, tip.y) else [])


## Bones lying half frozen into the floor: a ribcage on its spine, a skull with empty
## sockets (horned, `accent`), or a pair of great horns; a glaze of ice over their lower
## side.
func _bones(thing: NelvarIceData.Thing, rng: RandomNumberGenerator) -> NelvarIceArt:
	var r := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.5 - 3.0, -r * 1.2 - 3.0, r * 3.0 + 6.0, r * 2.0 + 6.0))
	var facing := -1.0 if rng.randf() < 0.5 else 1.0
	match thing.variant:
		0:
			var spine_from := Vector2(-r * 1.0, rng.randf_range(-0.2, 0.2) * r)
			var spine_to := Vector2(r * 1.0, rng.randf_range(-0.2, 0.2) * r)
			_line(canvas, spine_from, spine_to, BONE[1], 0.5)
			var count := rng.randi_range(4, 6)
			for i in count:
				var t := lerpf(0.15, 0.85, float(i) / (count - 1))
				var at := spine_from.lerp(spine_to, t)
				var reach := r * (0.55 + 0.35 * sin(t * PI))
				for side: float in [-1.0, 1.0]:
					var mid := at + Vector2(rng.randf_range(-0.1, 0.1) * r, side * reach * 0.6)
					var tip := at + Vector2(facing * 0.25 * r, side * reach * 0.9)
					_line(canvas, at, mid, BONE[3 if side < 0.0 else 2], 0.7)
					_line(canvas, mid, tip, BONE[2], 0.6)
		1:
			var skull := NelvarEarthCanvas.make_blob(rng, Vector2(0.0, -r * 0.15), Vector2(r * 0.7, r * 0.5), 0.05, 0.08, 2.0, 0.08)
			canvas.blob(skull, BONE)
			canvas.blob(NelvarEarthCanvas.make_blob(rng, Vector2(facing * r * 0.62, r * 0.05), Vector2(r * 0.42, r * 0.26),
				0.0, 0.08, 2.0, 0.08), BONE)
			for side: float in [-1.0, 1.0]:
				var socket := canvas.pixel(Vector2(facing * r * 0.18 + side * r * 0.22, -r * 0.2))
				for dx in 2:
					canvas.put(socket.x + dx, socket.y, BONE_OUTLINE, 0.0)
				canvas.put(socket.x, socket.y + 1, BONE_OUTLINE, 0.0)
			for k in 4:
				var tooth := canvas.pixel(Vector2(facing * r * (0.5 + k * 0.12), r * 0.28))
				canvas.put(tooth.x, tooth.y, FANG, 0.9)
			if thing.accent:
				for side: float in [-1.0, 1.0]:
					var root := Vector2(side * r * 0.4, -r * 0.5)
					_line(canvas, root, root + Vector2(side * r * 0.5, -r * 0.4), BONE[2], 0.7)
					_line(canvas, root + Vector2(side * r * 0.5, -r * 0.4), root + Vector2(side * r * 0.9, -r * 0.2), BONE[1], 0.6)
		_:
			for side: float in [-1.0, 1.0]:
				var points: Array[Vector2] = []
				for k in 8:
					var t := float(k) / 7.0
					var angle := lerpf(0.2, 2.4, t) * side
					points.append(Vector2(side * r * 0.15, 0.0) + Vector2(sin(angle) * r * (0.4 + t * 0.6), -cos(angle) * r * 0.5))
				for k in points.size() - 1:
					var thick := 1 if k > 4 else 2
					for d in thick:
						_line(canvas, points[k] + Vector2(0.0, d), points[k + 1] + Vector2(0.0, d), BONE[2 - d], 0.6)
	canvas.outline_silhouette(BONE_OUTLINE, 0.45)
	# The ice that holds them: a glaze over the lower side.
	var lowest := 0
	for y in canvas.size.y:
		for x in canvas.size.x:
			if canvas.is_body(x, y):
				lowest = maxi(lowest, y)
	for y in canvas.size.y:
		for x in canvas.size.x:
			if canvas.is_body(x, y) and (y > lowest - 2 or rng.randf() < 0.12):
				canvas.image.set_pixel(x, y, canvas.image.get_pixel(x, y).lerp(GLAZE, 0.5))
	return _finish(canvas)


# --- Faces, vents, the water --------------------------------------------------------------

## A creature caught in an ice flow bulging from the foot of a south face: the flow, the
## head with its jaws open (its eye shut: art.eye), a paw reaching out with its claws, a
## curled tail or a wing; a skin of clear ice over it all.
func _embedded(thing: NelvarIceData.Thing, rng: RandomNumberGenerator) -> NelvarIceArt:
	var r := thing.radius / STEP
	var tall := float(NelvarCaveData.FACE) + 5.0
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.5 - 3.0, -tall - 6.0, r * 3.0 + 6.0, tall + 9.0))
	_shadow(canvas, Vector2(0.0, 0.0), Vector2(r * 1.0, 1.5))
	var flow := NelvarEarthCanvas.make_blob(rng, Vector2(0.0, -tall * 0.55), Vector2(r * 1.05, tall * 0.62), 0.08, 0.06, 0.88, 0.1)
	canvas.blob(flow, FLOW)
	var facing := -1.0 if rng.randf() < 0.5 else 1.0
	var eye := Vector2.INF
	var center := Vector2(0.0, -tall * 0.5)
	match thing.variant:
		Part.HEAD:
			var head := center + Vector2(-facing * r * 0.1, -1.0)
			_frozen_blob(canvas, rng, head, Vector2(r * 0.5, r * 0.34) + Vector2.ONE * 0.5, 0.06)
			# The jaws, open: an upper and a lower, fangs between.
			var snout := head + Vector2(facing * r * 0.45, r * 0.05)
			_frozen_blob(canvas, rng, snout + Vector2(0.0, -r * 0.12), Vector2(r * 0.34, r * 0.13) + Vector2.ONE * 0.4, 0.04)
			_frozen_blob(canvas, rng, snout + Vector2(-facing * r * 0.04, r * 0.24), Vector2(r * 0.3, r * 0.1) + Vector2.ONE * 0.4, -0.04)
			for k in 4:
				var x := snout.x + facing * (k - 1.5) * r * 0.16
				var upper := canvas.pixel(Vector2(x, snout.y - r * 0.0))
				canvas.put(upper.x, upper.y, FANG, 0.9)
				if k % 2 == 0:
					var lower := canvas.pixel(Vector2(x, snout.y + r * 0.14))
					canvas.put(lower.x, lower.y, FANG, 0.9)
			for side: float in [-1.0, 1.0]:
				var root := head + Vector2(side * r * 0.2 - facing * r * 0.1, -r * 0.28)
				_line(canvas, root, root + Vector2(side * r * 0.24 - facing * r * 0.3, -r * 0.3), FROZEN[3], 0.7)
			eye = head + Vector2(facing * r * 0.12, -r * 0.1)
		Part.PAW:
			var shoulder := center + Vector2(-facing * r * 0.35, -r * 0.25)
			var wrist := center + Vector2(facing * r * 0.3, r * 0.3)
			for k in 5:
				var t := float(k) / 4.0
				_frozen_blob(canvas, rng, shoulder.lerp(wrist, t), Vector2.ONE * (r * (0.22 - t * 0.06)) + Vector2.ONE * 0.5)
			for k in 4:
				var root := wrist + Vector2(facing * r * 0.12, (float(k) - 1.5) * r * 0.12)
				_line(canvas, root, root + Vector2(facing * r * 0.3, r * 0.16 + float(k) * 0.3), FANG, 0.9)
		Part.TAIL:
			var phase := rng.randf() * TAU
			for k in 10:
				var t := float(k) / 9.0
				var spot := center + Vector2(lerpf(-0.8, 0.8, t) * r * facing, sin(phase + t * 5.0) * r * 0.22)
				_frozen_blob(canvas, rng, spot, Vector2.ONE * (r * lerpf(0.2, 0.07, t) + 0.6), 0.03 if k % 2 == 0 else -0.03)
				if k % 2 == 1:
					var spine := canvas.pixel(spot + Vector2(0.0, -r * lerpf(0.2, 0.07, t) - 0.8))
					canvas.put(spine.x, spine.y, FROZEN[4], 0.8)
		_:
			var root := center + Vector2(-facing * r * 0.6, r * 0.2)
			for k in 5:
				var tip := root + Vector2(facing * r * lerpf(0.4, 1.3, float(k) / 4.0), -r * lerpf(0.7, 0.05, float(k) / 4.0))
				_line(canvas, root, tip, FROZEN[3], 0.7)
				if k < 4:
					var next := root + Vector2(facing * r * lerpf(0.4, 1.3, float(k + 1) / 4.0), -r * lerpf(0.7, 0.05, float(k + 1) / 4.0))
					_frozen_blob(canvas, rng, (tip + next) * 0.5 * 0.7 + root * 0.3, Vector2.ONE * (r * 0.14 + 0.5), -0.06)
	canvas.outline_silhouette(FLOW_OUTLINE, 0.4)
	# The clear ice over it: everything a little paler, light running down it, a lit rim.
	var salt := rng.randi() & 0xffff
	for y in canvas.size.y:
		for x in canvas.size.x:
			if not canvas.is_body(x, y):
				continue
			var color := canvas.image.get_pixel(x, y)
			var streak := NelvarPixelArt.hash01(canvas.grid.x + x, 0, salt) < 0.22
			canvas.image.set_pixel(x, y, color.lerp(FLOW[3], 0.38 if streak else 0.2))
	var glints: Array[Vector2] = []
	for x in canvas.size.x:
		var top := _surface(canvas, x)
		if top >= 0:
			canvas.image.set_pixel(x, top, FLOW[4])
			if rng.randf() < 0.08:
				glints.append(_corner(canvas, Vector2i(x, top)))
	var art := _finish(canvas, glints.slice(0, 3))
	if eye.is_finite():
		var at := canvas.pixel(eye)
		for dx in range(-1, 2):
			canvas.put(at.x + dx, at.y, FROZEN_OUTLINE, 0.0)
		art.eye = _corner(canvas, at)
	return art


## A geyser's mouth: a low mound of travertine terraces, white at their lips, ochre
## below, round a pool of boiling water; wet stone round its foot.
func _vent(thing: NelvarIceData.Thing, rng: RandomNumberGenerator) -> NelvarIceArt:
	var r := thing.radius / STEP
	var canvas := NelvarEarthCanvas.new(thing.position, Rect2(-r * 1.9 - 3.0, -r * 1.4 - 4.0, r * 3.8 + 6.0, r * 2.2 + 7.0))
	_shadow(canvas, Vector2(-r * 0.1, r * 0.1), Vector2(r * 1.6, r * 0.55 + 0.5))
	var tiers := 3
	for i in tiers:
		var scale := 1.0 - float(i) * 0.24
		var lip := NelvarEarthCanvas.make_blob(rng, Vector2(rng.randf_range(-0.08, 0.08) * r, -r * 0.1 - float(i) * r * 0.16),
			Vector2(r * 1.45 * scale, r * 0.62 * scale), 0.08 + i * 0.05, 0.12, 0.5, 0.1)
		lip.rim = TRAVERTINE[4]
		lip.rim_level = 0.62
		canvas.blob(lip, TRAVERTINE)
	canvas.outline_silhouette(TRAVERTINE_OUTLINE, 0.36)
	# The pool on top, steaming water.
	var pool_center := Vector2(0.0, -r * 0.1 - float(tiers - 1) * r * 0.16 - r * 0.05)
	var pool := Vector2(r * 0.5, r * 0.22) + Vector2.ONE * 0.6
	var from := canvas.pixel(pool_center - pool)
	var to := canvas.pixel(pool_center + pool)
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var d := (canvas.center_of(x, y) - pool_center) / pool
			if d.length() > 1.0:
				continue
			var level := 0.2 + d.y * 0.25 + (1.0 - d.length()) * 0.25
			canvas.put(x, y, canvas.ramp(POOL, level, x, y), 0.2)
			if d.length() > 0.8 and d.y < 0.0:
				canvas.image.set_pixel(x, y, TRAVERTINE_OUTLINE)
	return _finish(canvas)


## A body floating on open water: a creature as the ones under the ice, pale and
## swollen, the part under the waterline darker and dim (`sunk`: half of it).
func paint_floater(floater: NelvarCaveData.Floater) -> NelvarIceArt:
	var creature := NelvarIceData.Frozen.new()
	creature.position = floater.position
	creature.radius = floater.radius
	creature.variant = floater.variant
	creature.appearance_seed = floater.appearance_seed
	creature.facing_left = floater.facing_left
	var art := paint_frozen(creature)
	art.eye = Vector2.INF
	var image := art.image
	var waterline := int(image.get_height() * (0.5 if floater.sunk else 0.72))
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a <= 0.0:
				continue
			if color.is_equal_approx(BUBBLE):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var pale := Color(color.r * 0.45 + 0.52, color.g * 0.45 + 0.52, color.b * 0.45 + 0.56) * CORPSE_TINT
			if y >= waterline:
				pale = pale.darkened(0.45).lerp(Color(0.1, 0.22, 0.28), 0.35)
				pale.a = 0.72
			image.set_pixel(x, y, pale)
	return art
