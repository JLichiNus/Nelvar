class_name NelvarTreePainter
extends RefCounted
## Generates a unique trunk and layered leaf masses, then bakes world-grid pixels.

const OAK: Array[Color] = [Color("263f2d"), Color("36552f"), Color("486d36"),
	Color("648744"), Color("86a752"), Color("afc16b")]
const SAGE: Array[Color] = [Color("294732"), Color("40633c"), Color("567d49"),
	Color("759958"), Color("9ab56d"), Color("c1cf8d")]
const OLIVE: Array[Color] = [Color("35452a"), Color("4a5e30"), Color("667938"),
	Color("859647"), Color("a6b35c"), Color("c9cc7e")]

class LeafMass:
	var center: Vector2
	var axes: Vector2


func paint(tree: NelvarForestData.TreeSpec, style: NelvarTerrainStyle) -> NelvarTreeArt:
	var art := NelvarTreeArt.new()
	art.pixel_size = maxi(1, style.pixel_size)
	var step := float(art.pixel_size)
	var rng := RandomNumberGenerator.new()
	rng.seed = tree.appearance_seed
	var axes := tree.canopy_axes()
	var center := tree.canopy_center()
	var masses: Array[LeafMass] = []
	var core := LeafMass.new()
	core.center = center
	core.axes = axes * Vector2(0.78, 0.80)
	masses.append(core)
	var count := rng.randi_range(7, 10)
	var phase := rng.randf() * TAU
	for i in count:
		var angle := TAU * float(i) / count + phase + rng.randf_range(-0.12, 0.12)
		var mass := LeafMass.new()
		mass.center = center + Vector2.from_angle(angle) * axes * rng.randf_range(0.48, 0.60)
		mass.axes = axes * Vector2(rng.randf_range(0.40, 0.56), rng.randf_range(0.39, 0.54))
		masses.append(mass)
	var bounds := Rect2(Vector2(-tree.trunk_radius * 1.6, -tree.trunk_height),
		Vector2(tree.trunk_radius * 3.2, tree.trunk_height + tree.trunk_radius))
	for mass in masses:
		bounds = bounds.merge(Rect2(mass.center - mass.axes, mass.axes * 2.0))
	bounds = bounds.grow(step * 2.0)
	var world_origin := ((tree.position + bounds.position) / step).floor() * step
	var size := ((tree.position + bounds.end - world_origin) / step).ceil()
	art.local_rect = Rect2(world_origin - tree.position, size * step)
	art.image = Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGBA8)
	var palette := OAK
	if tree.palette == 1:
		palette = SAGE
	elif tree.palette == 2:
		palette = OLIVE
	var noise := FastNoiseLite.new()
	noise.seed = tree.appearance_seed
	noise.frequency = 0.15
	noise.fractal_octaves = 2
	for y in int(size.y):
		for x in int(size.x):
			var point := art.local_rect.position + Vector2(x + 0.5, y + 0.5) * step
			var color := _trunk(point, tree, step)
			if color.a == 0.0:
				var shadow := point / Vector2(tree.trunk_radius * 1.5, tree.trunk_radius * 0.4)
				if shadow.length_squared() < 1.0:
					color = Color(0.12, 0.19, 0.12, 0.22)
			var field := _leaf_field(point, masses)
			if field.x <= 0.0:
				var mass := masses[int(field.y)]
				var normal := (point - mass.center) / mass.axes
				var patch := noise.get_noise_2d(point.x / step, point.y / step)
				var light := -normal.x * 0.28 - normal.y * 0.52
				light += -(mass.center - center).y / axes.y * 0.35
				var shade := clampi(3 + floori(light * 2.0 + patch * 2.5), 1, 5)
				color = palette[shade]
				if field.x > -step * 0.65:
					color = palette[0]
				elif field.x > -step * 1.5 and normal.y < -0.1:
					color = palette[mini(5, shade + 1)]
				elif field.x < -step * 2.0 and _hash(x, y, tree.appearance_seed) % 43 == 0:
					color = palette[mini(5, shade + 1)]
			if color.a > 0.0:
				art.image.set_pixel(x, y, color)
	art.texture = ImageTexture.create_from_image(art.image)
	return art


func _leaf_field(point: Vector2, masses: Array[LeafMass]) -> Vector2:
	var nearest := INF
	var owner := 0
	for i in masses.size():
		var mass := masses[i]
		var q := ((point - mass.center) / mass.axes).length_squared()
		var distance := (q - 1.0) * minf(mass.axes.x, mass.axes.y) * 0.5
		if distance < nearest:
			nearest = distance
			owner = i
	return Vector2(nearest, owner)


func _trunk(point: Vector2, tree: NelvarForestData.TreeSpec, step: float) -> Color:
	var top := -tree.trunk_height - tree.canopy_axes().y * 0.4
	if point.y < top or point.y > step * 1.5:
		return Color.TRANSPARENT
	var progress := clampf(-point.y / -top, 0.0, 1.0)
	var center := tree.lean * progress
	var width := tree.trunk_radius * (0.76 - progress * 0.3)
	if point.y > -tree.trunk_radius * 0.4:
		width += tree.trunk_radius * 0.35 * (1.0 - absf(point.y) / (tree.trunk_radius * 0.4))
	var across := (point.x - center) / width
	if absf(across) > 1.0:
		return Color.TRANSPARENT
	if absf(across) > 0.78 or point.y > step:
		return Color("3e332a")
	var color := Color("85613e")
	if across < -0.25:
		color = Color("b08a54")
	elif across > 0.30:
		color = Color("604932")
	if _hash(floori(point.x / step), floori(point.y / (step * 3.0)), tree.appearance_seed) % 7 == 0:
		color = Color("6d5036")
	return color


func _hash(x: int, y: int, salt: int) -> int:
	var value := (x * 374761393 + y * 668265263 + salt) & 0x7fffffff
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
	return (value ^ (value >> 16)) & 0x7fffffff
