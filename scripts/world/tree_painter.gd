class_name NelvarTreePainter
extends RefCounted
## Wind-swept trees in the style of the air-realm menu: the crown is stacked tiers of flat
## leaf pads, each lit like a sphere from the upper right, Bayer-dithered, with a cool
## outline only on shaded edges. Pixels are baked on the world grid.

const WOBBLE := 0.16
const LEAF_TEXTURE := 0.18
const OUTLINE_LEVEL := 0.6

## Pale airy foliage (bushes share these ramps), dark to light.
const MINT: Array[Color] = [Color("529e88"), Color("6ab696"), Color("8ccea8"),
	Color("b6e6c6"), Color("def8e4")]
const MEADOW: Array[Color] = [Color("5e9c70"), Color("78b67e"), Color("9ace92"),
	Color("c0e4ae"), Color("e8f6d2")]
const TEAL: Array[Color] = [Color("46907e"), Color("5aa68c"), Color("78be9c"),
	Color("a2dab8"), Color("ccf0d6")]
const OUTLINES: Array[Color] = [Color("3e4a64"), Color("3c5052"), Color("384a5a")]
const TRUNK: Array[Color] = [Color("6e5c5e"), Color("8a7470"), Color("a69286")]

class LeafMass:
	var center: Vector2
	var axes: Vector2
	var phase: Vector2
	var salt: int
	var bias: float


func paint(tree: NelvarForestData.TreeSpec, style: NelvarTerrainStyle) -> NelvarTreeArt:
	var art := NelvarTreeArt.new()
	art.pixel_size = maxi(1, style.pixel_size)
	var step := float(art.pixel_size)
	var rng := RandomNumberGenerator.new()
	rng.seed = tree.appearance_seed
	var masses := _build_crown(tree, rng)
	var bounds := Rect2(Vector2(minf(0.0, tree.lean) - tree.trunk_radius * 1.8, -tree.trunk_height),
		Vector2(absf(tree.lean) + tree.trunk_radius * 3.6, tree.trunk_height + tree.trunk_radius))
	for mass in masses:
		var reach := mass.axes * (1.0 + WOBBLE)
		bounds = bounds.merge(Rect2(mass.center - reach, reach * 2.0))
	bounds = bounds.grow(step * 2.0)
	var world_origin := ((tree.position + bounds.position) / step).floor() * step
	var size := ((tree.position + bounds.end - world_origin) / step).ceil()
	art.local_rect = Rect2(world_origin - tree.position, size * step)
	art.image = Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGBA8)
	var grid := Vector2i((world_origin / step).round())
	var salt := tree.appearance_seed & 0xffff
	for y in int(size.y):
		for x in int(size.x):
			var point := art.local_rect.position + Vector2(x + 0.5, y + 0.5) * step
			var color := _trunk(point, tree, step, grid + Vector2i(x, y), salt)
			if color.a == 0.0:
				color = _shadow(point, tree, step, grid + Vector2i(x, y))
			if color.a > 0.0:
				art.image.set_pixel(x, y, color)
	var leaves := foliage(tree.palette)
	var outline := OUTLINES[clampi(tree.palette, 0, OUTLINES.size() - 1)]
	for mass in masses:
		_paint_mass(art, mass, step, grid, leaves, outline)
	_drop_stray_outline(art.image, outline, leaves[0])
	art.texture = ImageTexture.create_from_image(art.image)
	return art


static func foliage(palette: int) -> Array[Color]:
	if palette == 1:
		return MEADOW
	if palette == 2:
		return TEAL
	return MINT


## Tiers of wide, overlapping pads; upper tiers drift downwind (to the right).
func _build_crown(tree: NelvarForestData.TreeSpec, rng: RandomNumberGenerator) -> Array[LeafMass]:
	var axes := tree.canopy_axes()
	var center := tree.canopy_center()
	var tiers := 4 if tree.form == 1 else 3
	var tier_step := axes.y * 2.0 / (float(tiers) + 0.7)
	var tier_height := tier_step * 0.95
	var drift := axes.x * 0.16
	var masses: Array[LeafMass] = []
	for k in tiers:
		var v := float(k) / float(tiers - 1)
		var half_width := axes.x * (0.80 + 0.24 * sin(PI * v) - 0.08 * v) * rng.randf_range(0.92, 1.04)
		var tier_x := center.x + drift * (v - 0.35) + rng.randf_range(-0.05, 0.05) * axes.x
		var tier_y := center.y + axes.y - tier_height - tier_step * k
		var count := clampi(roundi(half_width / (tier_height * 1.6)) + int(rng.randf() < 0.3), 1, 3)
		var segment := half_width * 2.0 / count
		for i in count:
			var mass := _mass(rng, 0.04 * v)
			var x := tier_x - half_width + segment * (i + 0.5) + rng.randf_range(-0.12, 0.12) * segment
			var spread := absf(x - tier_x) / half_width
			mass.axes.y = tier_height * rng.randf_range(0.82, 1.04)
			mass.axes.x = maxf(segment * 0.5 * rng.randf_range(1.2, 1.5), mass.axes.y * 1.5)
			mass.center = Vector2(x, tier_y + mass.axes.y * (0.2 * spread + rng.randf_range(-0.1, 0.1)))
			masses.append(mass)
		if k == tiers / 2:
			# A small pad blown out on the downwind side, like a flag.
			var tip := _mass(rng, 0.04 * v)
			tip.axes = Vector2(tier_height * 0.95, tier_height * 0.55)
			tip.center = Vector2(tier_x + half_width + tip.axes.x * 0.1,
				tier_y + rng.randf_range(-0.2, 0.1) * tier_height)
			masses.append(tip)
	# Lower pads first, so each upper pad's shaded rim cuts a line across the ones below.
	masses.sort_custom(func(a: LeafMass, b: LeafMass) -> bool: return a.center.y > b.center.y)
	return masses


func _mass(rng: RandomNumberGenerator, bias: float) -> LeafMass:
	var mass := LeafMass.new()
	mass.phase = Vector2(rng.randf_range(0.0, 64.0), rng.randf_range(0.0, 64.0))
	mass.salt = rng.randi() & 0xffff
	mass.bias = bias
	return mass


func _paint_mass(art: NelvarTreeArt, mass: LeafMass, step: float, grid: Vector2i,
		leaves: Array[Color], outline: Color) -> void:
	var reach := mass.axes * (1.0 + WOBBLE)
	var from := ((mass.center - reach - art.local_rect.position) / step).floor()
	var to := ((mass.center + reach - art.local_rect.position) / step).ceil()
	var size := art.image.get_size()
	for y in range(maxi(0, int(from.y)), mini(size.y, int(to.y) + 1)):
		for x in range(maxi(0, int(from.x)), mini(size.x, int(to.x) + 1)):
			var point := art.local_rect.position + Vector2(x + 0.5, y + 0.5) * step
			var local := _inside(mass, point)
			if local.x == INF:
				continue
			var cell := grid + Vector2i(x, y)
			var nz := sqrt(maxf(0.0, 1.0 - local.length_squared()))
			var light := NelvarPixelArt.LIGHT
			var lit := local.x * light.x + local.y * light.y + nz * light.z
			var grain := NelvarPixelArt.value_noise(cell.x * 0.45, cell.y * 0.45, mass.salt + 5) - 0.5
			var level := 0.32 + 0.5 * lit + mass.bias + grain * LEAF_TEXTURE * 2.0
			var color := NelvarPixelArt.ramp(leaves, level, cell)
			if level < OUTLINE_LEVEL and _on_edge(mass, point, step):
				color = outline
			art.image.set_pixel(x, y, color)


## Tiny outline fragments inside the crown read as specks, not as pad rims.
func _drop_stray_outline(image: Image, outline: Color, replacement: Color) -> void:
	var size := image.get_size()
	var seen: Dictionary = {}
	for y in size.y:
		for x in size.x:
			var start := Vector2i(x, y)
			if seen.has(start) or image.get_pixelv(start) != outline:
				continue
			var piece: Array[Vector2i] = [start]
			seen[start] = true
			var i := 0
			while i < piece.size():
				var p := piece[i]
				i += 1
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var q := p + Vector2i(dx, dy)
						if q.x >= 0 and q.y >= 0 and q.x < size.x and q.y < size.y \
								and not seen.has(q) and image.get_pixelv(q) == outline:
							seen[q] = true
							piece.append(q)
			if piece.size() < 4:
				for p in piece:
					image.set_pixelv(p, replacement)


## Position inside the pad's wobbly ellipse in unit coordinates, or INF when outside.
func _inside(mass: LeafMass, point: Vector2) -> Vector2:
	var local := (point - mass.center) / mass.axes
	var distance := local.length()
	var edge := 1.0
	if distance > 0.0:
		var direction := local / distance
		edge += WOBBLE * (NelvarPixelArt.value_noise(direction.x * 1.7 + mass.phase.x,
			direction.y * 1.7 + mass.phase.y, 7) * 2.0 - 1.0)
	if distance > edge:
		return Vector2(INF, INF)
	return local / edge


func _on_edge(mass: LeafMass, point: Vector2, step: float) -> bool:
	for offset: Vector2 in [Vector2(step, 0), Vector2(-step, 0), Vector2(0, step), Vector2(0, -step)]:
		if _inside(mass, point + offset).x == INF:
			return true
	return false


## Thin trunk bent downwind, darkened on its left (shaded) edge, with a small root flare.
func _trunk(point: Vector2, tree: NelvarForestData.TreeSpec, step: float, cell: Vector2i,
		salt: int) -> Color:
	var top := tree.canopy_center().y
	if point.y < top or point.y > step * 0.5:
		return Color.TRANSPARENT
	var progress := clampf(point.y / top, 0.0, 1.0)
	var center := tree.lean * pow(progress, 1.4)
	var width := tree.trunk_radius * (0.58 - 0.18 * progress)
	if point.y > -step * 2.5:
		width += step
	if point.y > -step:
		width += step
	var across := (point.x - center) / width
	if absf(across) > 1.0:
		return Color.TRANSPARENT
	if (point.x - step - center) / width < -1.0:
		return OUTLINES[0]
	var grain := NelvarPixelArt.value_noise(cell.x * 0.6, cell.y * 0.22, salt) - 0.5
	return NelvarPixelArt.ramp(TRUNK, 0.15 + (across + 1.0) * 0.375 + grain * 0.35, cell)


func _shadow(point: Vector2, tree: NelvarForestData.TreeSpec, step: float, cell: Vector2i) -> Color:
	var reach := Vector2(tree.trunk_radius * 1.7, tree.trunk_radius * 0.5 + step * 0.5)
	return NelvarPixelArt.shadow_at(point, Vector2.ZERO, reach, cell)
