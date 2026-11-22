class_name NelvarCloudPainter
extends RefCounted
## Bakes soft pixel cumulus in the terrain pixel grid. Colours stay close to the
## sky so the clouds read as distant haze below the islands, not as foreground.

const HIGHLIGHT := Color("b3cadd")
const BODY := Color("93b0ca")
const SHADE := Color("7896b4")
const EDGE_ALPHA := 0.55
const MARGIN := 3

class Cloud:
	var texture: ImageTexture
	var size: Vector2
	var position: Vector2
	var speed: float
	var opacity: float


class Blob:
	var center: Vector2
	var radius: Vector2


func paint(data: NelvarWorldData, style: NelvarTerrainStyle, sky: Rect2,
		count: int) -> Array[Cloud]:
	var step := float(maxi(1, style.pixel_size))
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:sky" % data.world_seed).hash()
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.11
	var result: Array[Cloud] = []
	for i in count:
		# Far clouds are fainter and slower, which gives a hint of depth.
		var depth := rng.randf()
		var cloud := Cloud.new()
		cloud.texture = _paint_cloud(rng, noise, rng.randf_range(20.0, 46.0) * lerpf(0.8, 1.2, depth))
		cloud.size = Vector2(cloud.texture.get_size()) * step
		cloud.position = Vector2(
			rng.randf_range(sky.position.x, sky.end.x),
			rng.randf_range(sky.position.y, sky.end.y))
		cloud.speed = lerpf(2.5, 7.0, depth)
		cloud.opacity = lerpf(0.16, 0.34, depth)
		result.append(cloud)
	# Painter's order: faint distant clouds first.
	result.sort_custom(func(a: Cloud, b: Cloud) -> bool: return a.opacity < b.opacity)
	return result


func _paint_cloud(rng: RandomNumberGenerator, noise: FastNoiseLite, radius: float) -> ImageTexture:
	# A row of overlapping puffs sitting on a shared, slightly flattened base.
	var blobs: Array[Blob] = []
	var puffs := rng.randi_range(3, 6)
	var span := radius * lerpf(1.1, 1.7, float(puffs - 3) / 3.0)
	for p in puffs:
		var t := lerpf(-1.0, 1.0, float(p) / float(puffs - 1)) + rng.randf_range(-0.12, 0.12)
		var r := radius * (1.0 - 0.45 * absf(t)) * rng.randf_range(0.75, 1.05)
		var blob := Blob.new()
		blob.radius = Vector2(r, r * 0.72)
		blob.center = Vector2(t * span, -blob.radius.y * rng.randf_range(0.35, 0.65))
		blobs.append(blob)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for blob in blobs:
		lo = lo.min(blob.center - blob.radius)
		hi = hi.max(blob.center + blob.radius)
	hi.y = minf(hi.y, radius * 0.18)
	var origin := lo.floor() - Vector2.ONE * MARGIN
	var width := ceili(hi.x - origin.x) + MARGIN
	var height := ceili(hi.y - origin.y) + MARGIN
	var base := hi.y - origin.y
	var offset := Vector2(rng.randf_range(-5000.0, 5000.0), rng.randf_range(-5000.0, 5000.0))

	var mask := PackedFloat32Array()
	mask.resize(width * height)
	var light := PackedFloat32Array()
	light.resize(width * height)
	for y in height:
		for x in width:
			var point := Vector2(x, y) + origin + Vector2(0.5, 0.5)
			var wobble := noise.get_noise_2d(x + offset.x, y + offset.y) * 0.16
			var best := INF
			var normal := Vector2.ZERO
			for blob in blobs:
				var local := (point - blob.center) / blob.radius
				var d := local.length()
				if d < best:
					best = d
					normal = local
			var index := y * width + x
			if best < 1.0 + wobble and float(y) < base + wobble * 6.0:
				mask[index] = 1.0
				# Sun from the upper left; the flat underside sits in shadow.
				light[index] = -0.45 * normal.x - 0.9 * normal.y - 0.5 * clampf(
					(float(y) - base + 4.0) / 4.0, 0.0, 1.0)

	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in range(1, height - 1):
		for x in range(1, width - 1):
			var index := y * width + x
			if mask[index] == 0.0:
				continue
			var color := BODY
			if light[index] > 0.42:
				color = HIGHLIGHT
			elif light[index] < -0.28:
				color = SHADE
			var edge := mask[index - 1] == 0.0 or mask[index + 1] == 0.0 \
				or mask[index - width] == 0.0 or mask[index + width] == 0.0
			if edge:
				color.a = EDGE_ALPHA
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
