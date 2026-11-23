class_name NelvarTheOnePainter
extends RefCounted
## Bakes the parts of the Only One (Единственный) as pixel art, one texture per
## part so the body can come apart in later phases: an elongated faceless head,
## a narrow torso with a hole through the chest, a normal right arm with overlong
## fingers, a huge left arm that reaches the ground, thin legs with wrong joints.
## Dark grey-blue, almost black, with rare pale violet cracks.
##
## Every part also gets a glow layer (the cracks, drawn additively) and a contour:
## only its outline, which the body draws where the part *was* a moment ago.
## Coordinates are in texels; the body is drawn at TEXEL world units per texel.

const TEXEL := 3.0
const MARGIN := 2

const BODY: Array[Color] = [Color("0a0c13"), Color("111520"), Color("181d2b"), Color("212839"),
	Color("2b3349")]
const OUTLINE := Color("04050a")
const HEAD_RIM := Color("1d2233")
const CRACK := Color("5e4c9e")
const CRACK_GLOW := Color(0.6, 0.45, 0.95)
const HOLE_RIM := Color("47357e")
const CONTOUR := Color(0.78, 0.72, 1.0)

static var _parts := {}


class Part:
	var texture: ImageTexture
	var glow: ImageTexture
	var contour: ImageTexture
	## Torso only: white where the hole through the chest is (a window into the Void).
	var hole: ImageTexture
	## Where the part hangs from (shoulder, hip, neck...), texels from the image's corner.
	var pivot: Vector2
	var size: Vector2


## name -> Part: head, torso, arm_r, arm_l, leg_l, leg_r. Baked once per run.
static func parts() -> Dictionary:
	if _parts.is_empty():
		var painter := NelvarTheOnePainter.new()
		_parts = painter._paint_all()
	return _parts


## Where the limbs attach on the torso, world units from the hips.
const SHOULDER_L := Vector2(5.0, -20.0) * TEXEL
const SHOULDER_R := Vector2(-5.0, -20.0) * TEXEL
const NECK := Vector2(0.0, -22.0) * TEXEL
const HIP_L := Vector2(2.4, -0.5) * TEXEL
const HIP_R := Vector2(-2.4, -0.5) * TEXEL
## Hips above the feet.
const HIP_HEIGHT := 16.0 * TEXEL


func _paint_all() -> Dictionary:
	var result := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x0E1D
	# Head: a long tilted oval of pure black, no face at all.
	result["head"] = _make(Vector2i(10, 14), Vector2(5, 13), rng, 0, func(p: Vector2) -> bool:
		var q := (p - Vector2(5.0, 6.5)).rotated(-0.22)
		return (q.x * q.x) / (2.9 * 2.9) + (q.y * q.y) / (6.0 * 6.0) <= 1.0, true)
	# Torso: shoulder bar, a long narrow ribcage, a spine-thin waist, the pelvis.
	result["torso"] = _make(Vector2i(13, 23), Vector2(6.5, 22), rng, 4, func(p: Vector2) -> bool:
		var half := 0.0
		if p.y < 1.0:
			return false
		elif p.y < 4.0:
			half = 5.2
		elif p.y < 14.0:
			half = 2.7 + 0.6 * (14.0 - p.y) / 10.0
		elif p.y < 18.0:
			half = 1.2
		else:
			half = 2.3
		return absf(p.x - 6.5) <= half, false, false, true)
	result["arm_r"] = _make(Vector2i(12, 26), Vector2(3, 1), rng, 2, func(p: Vector2) -> bool:
		if _near_polyline(p, [Vector2(3, 1), Vector2(4, 9), Vector2(3, 16)], 1.0):
			return true
		for tip: Vector2 in [Vector2(0.5, 24), Vector2(2.5, 25), Vector2(4.5, 24.5), Vector2(6.8, 23)]:
			if _near_polyline(p, [Vector2(3, 16), tip], 0.5):
				return true
		return false, false)
	result["arm_l"] = _make(Vector2i(16, 37), Vector2(5, 1), rng, 4, func(p: Vector2) -> bool:
		var width := lerpf(2.0, 1.45, clampf(p.y / 26.0, 0.0, 1.0))
		if _near_polyline(p, [Vector2(5, 1), Vector2(8, 13), Vector2(7, 25)], width):
			return true
		if p.distance_to(Vector2(7.2, 28.0)) <= 3.1:
			return true
		for tip: Vector2 in [Vector2(3.0, 35), Vector2(7.0, 35.8), Vector2(11.2, 34)]:
			if _near_polyline(p, [Vector2(7.2, 28), tip], 0.75):
				return true
		return false, false)
	var leg := func(p: Vector2) -> bool:
		return _near_polyline(p, [Vector2(4, 0.5), Vector2(6.2, 5), Vector2(2.4, 9),
			Vector2(5.2, 14), Vector2(7.6, 16)], 0.8)
	result["leg_l"] = _make(Vector2i(9, 17), Vector2(4, 0.5), rng, 1, leg, false)
	result["leg_r"] = _make(Vector2i(9, 17), Vector2(4, 0.5), rng, 1, leg, false, true)
	return result


## Rasterises `inside` (texel coordinates) and shades it. `cracks` is how many pale
## violet cracks run over it; a `void_fill` part is pure black inside its rim; a
## `hole` part gets the hole through the chest.
func _make(size: Vector2i, pivot: Vector2, rng: RandomNumberGenerator, cracks: int,
		inside: Callable, void_fill: bool, mirror := false, hole := false) -> Part:
	var w := size.x + MARGIN * 2
	var h := size.y + MARGIN * 2
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in h:
		for x in w:
			var p := Vector2(x - MARGIN + 0.5, y - MARGIN + 0.5)
			if mirror:
				p.x = size.x - p.x
			if inside.call(p):
				mask[y * w + x] = 1
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var glow := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var contour := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var filled := mask[y * w + x] == 1
			var edge := 0
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if _at(mask, w, h, x + offset.x, y + offset.y) == 0:
					edge += 1
			if not filled:
				if edge < 4:
					image.set_pixel(x, y, OUTLINE)
					contour.set_pixel(x, y, CONTOUR)
				continue
			if void_fill:
				image.set_pixel(x, y, HEAD_RIM if edge > 0 else Color.BLACK)
				# The empty face has a cold glowing rim.
				if edge > 0:
					glow.set_pixel(x, y, Color(CRACK_GLOW, 0.55))
				continue
			# Lit from the upper right: open space there brightens, below-left darkens.
			var level := 0.35
			if _at(mask, w, h, x + 1, y) == 0 or _at(mask, w, h, x + 1, y - 1) == 0:
				level += 0.3
			if _at(mask, w, h, x, y - 1) == 0:
				level += 0.15
			if _at(mask, w, h, x - 1, y) == 0 or _at(mask, w, h, x, y + 1) == 0:
				level -= 0.2
			level += (NelvarPixelArt.hash01(x, y, 0x1D) - 0.5) * 0.18
			image.set_pixel(x, y, NelvarPixelArt.ramp(BODY, level, Vector2i(x, y)))
	var hole_image: Image
	if hole:
		hole_image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		_cut_hole(image, mask, w, h, Vector2(6.5 + MARGIN, 9.5 + MARGIN), rng, hole_image)
	for i in cracks:
		_crack(image, glow, mask, w, h, rng)
	var part := Part.new()
	part.texture = ImageTexture.create_from_image(image)
	part.glow = ImageTexture.create_from_image(glow)
	part.contour = ImageTexture.create_from_image(contour)
	if hole_image != null:
		part.hole = ImageTexture.create_from_image(hole_image)
	part.pivot = pivot + Vector2(MARGIN, MARGIN)
	if mirror:
		part.pivot.x = size.x - pivot.x + MARGIN
	part.size = Vector2(w, h)
	return part


## An irregular hole through the chest: the Void shows through it.
func _cut_hole(image: Image, mask: PackedByteArray, w: int, h: int, center: Vector2,
		rng: RandomNumberGenerator, hole_image: Image) -> void:
	var lobes := Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf_range(1.7, 2.1))
	for y in h:
		for x in w:
			var d := Vector2(x + 0.5, y + 0.5) - center
			var reach := lobes.z + 0.5 * sin(d.angle() * 3.0 + lobes.x) + 0.3 * sin(d.angle() * 5.0 + lobes.y)
			var r := d.length()
			if r <= reach:
				image.set_pixel(x, y, Color.TRANSPARENT)
				hole_image.set_pixel(x, y, Color.WHITE)
				mask[y * w + x] = 0
			elif r <= reach + 1.0 and mask[y * w + x] == 1:
				image.set_pixel(x, y, HOLE_RIM)


## A short pale violet crack wandering over the part.
func _crack(image: Image, glow: Image, mask: PackedByteArray, w: int, h: int,
		rng: RandomNumberGenerator) -> void:
	for attempt in 30:
		var p := Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1))
		if mask[p.y * w + p.x] == 0:
			continue
		var length := rng.randi_range(2, 5)
		for step in length:
			if _at(mask, w, h, p.x, p.y) == 0:
				break
			image.set_pixelv(p, CRACK)
			glow.set_pixelv(p, CRACK_GLOW)
			p += [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 0)][rng.randi_range(0, 3)]
		return


func _at(mask: PackedByteArray, w: int, h: int, x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return 0
	return mask[y * w + x]


static func _near_polyline(p: Vector2, points: Array, radius: float) -> bool:
	for i in range(1, points.size()):
		var closest := Geometry2D.get_closest_point_to_segment(p, points[i - 1], points[i])
		if p.distance_to(closest) <= radius:
			return true
	return false
