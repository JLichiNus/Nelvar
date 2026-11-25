class_name NelvarCraterField
extends NelvarFireField
## What the volcano's ground shader reads besides the shapes it computes itself (the
## lake, the capes and the anchors are worked out there as in NelvarCraterData), one
## pixel per art pixel round the summit:
##   R — 0 (unused);
##   G — distance from a road's centre line in its half widths × 64, 255 far away;
##   B — 255 (unused);
##   A — 1..100 sulfur round the vents and the geysers, 0 bare ground.
## The coarse light map, one texel per GLOW_SCALE art pixels (the glow and the heat haze
## filter it):
##   R — the lava's light: moderate over the open lake, strong along its shores and over
##       the vent, falling off over GLOW_REACH on the rock, gone past the edge;
##   G — the boiling patches' and the vent's glow;
##   B — where the air shimmers (heat_haze.gdshader with use_haze_mask): over the vent,
##       the boiling patches and the smoke banks only; the open lake stays still.
## Two lookup tables:
##   edge  — the summit's radius in each of its profile's directions (R), world units;
##   slope — per art pixel column, the art pixel row (fractional) where the summit ends
##           on its south side: the front slope hangs below it. -1 where it has none.
## Built on a worker thread; the textures are made on the main thread.

## Light over the open lake (the shores and the vent get the full light).
const LAKE_LIGHT := 0.42
## World units from the shore over which the shore's strong light fades into it.
const SHORE_GLOW := 150.0

var edge: PackedFloat32Array
## World art pixel column of slope[0].
var slope_origin := 0
var slope: PackedFloat32Array


static func build_crater(crater: NelvarCraterData) -> NelvarCraterField:
	var field := NelvarCraterField.new()
	var bounds := Rect2(crater.boundary[0], Vector2.ZERO)
	for point in crater.boundary:
		bounds = bounds.expand(point)
	field.origin = Vector2i((bounds.position / STEP).floor()) - Vector2i.ONE * MARGIN
	field.size = Vector2i((bounds.size / STEP).ceil()) + Vector2i.ONE * MARGIN * 2
	var blank := Image.create(field.size.x, field.size.y, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0.0, 1.0, 1.0, 0.0))
	field.data = blank.get_data()
	field._flows(crater)
	field._deposits(crater)
	field._geysers(crater)
	field._crater_light(crater)
	field._edge(crater)
	field._slope(crater)
	return field


func edge_texture() -> ImageTexture:
	var image := Image.create_from_data(edge.size(), 1, false, Image.FORMAT_RF, edge.to_byte_array())
	return ImageTexture.create_from_image(image)


func slope_texture() -> ImageTexture:
	var image := Image.create_from_data(slope.size(), 1, false, Image.FORMAT_RF, slope.to_byte_array())
	return ImageTexture.create_from_image(image)


## Sulfur round the geysers' mouths, wider than a vent's.
func _geysers(crater: NelvarCraterData) -> void:
	for geyser in crater.geysers:
		var radius := geyser.radius * 2.6
		var box := _box(geyser.position - Vector2.ONE * radius, geyser.position + Vector2.ONE * radius)
		for y in range(box.position.y, box.end.y + 1):
			for x in range(box.position.x, box.end.x + 1):
				var d := (_world(x, y) - geyser.position).length() / radius
				if d >= 1.0:
					continue
				var index := (y * size.x + x) * 4 + 3
				if data[index] <= 100:
					data[index] = maxi(data[index], roundi((1.0 - d) * 70.0))


func _crater_light(crater: NelvarCraterData) -> void:
	glow_origin = Vector2i((Vector2(origin) / GLOW_SCALE).floor()) * GLOW_SCALE
	glow_size = Vector2i((Vector2(size) / GLOW_SCALE).ceil()) + Vector2i.ONE * 2
	glow = PackedByteArray()
	glow.resize(glow_size.x * glow_size.y * 4)
	for y in glow_size.y:
		for x in glow_size.x:
			var point := (Vector2(glow_origin) + (Vector2(x, y) + Vector2(0.5, 0.5)) * GLOW_SCALE) * STEP
			var index := (y * glow_size.x + x) * 4
			glow[index + 3] = 255
			var light := _light_at(crater, point)
			glow[index] = roundi(clampf(light.x, 0.0, 1.0) * 255.0)
			glow[index + 1] = roundi(clampf(light.y, 0.0, 1.0) * 255.0)
			glow[index + 2] = roundi(clampf(light.z, 0.0, 1.0) * 255.0)


## (lava light, magma light, haze) at a world point.
static func _light_at(crater: NelvarCraterData, point: Vector2) -> Vector3:
	var edge_depth := crater.rim_depth(point)
	if edge_depth < -GLOW_REACH:
		return Vector3.ZERO
	var depth := crater.lava_depth(point)
	var vent := point.distance_to(crater.vent)
	var lava := 0.0
	if depth >= 0.0:
		lava = LAKE_LIGHT + (1.0 - LAKE_LIGHT) * (1.0 - smoothstep(0.0, SHORE_GLOW, depth))
		lava = maxf(lava, 1.0 - smoothstep(crater.vent_radius, crater.vent_radius + 300.0, vent))
	else:
		lava = pow(1.0 - clampf(-depth / GLOW_REACH, 0.0, 1.0), 2.0)
	# The light stops at the edge: nothing below is lit by the lake.
	lava *= smoothstep(-24.0, 40.0, edge_depth)
	var magma := (1.0 - smoothstep(crater.vent_radius * 0.5, crater.vent_radius + 220.0, vent)) * 0.9
	var haze := 1.0 - smoothstep(crater.vent_radius + 80.0, crater.vent_radius + 280.0, vent)
	for boil in crater.boils:
		var d := point.distance_to(Vector2(boil.x, boil.y))
		magma = maxf(magma, (1.0 - smoothstep(boil.z * 0.5, boil.z * 1.8, d)) * 0.7)
		haze = maxf(haze, 1.0 - smoothstep(boil.z, boil.z + 90.0, d))
	for bank in crater.smoke_banks:
		var d := point.distance_to(Vector2(bank.x, bank.y))
		haze = maxf(haze, (1.0 - smoothstep(bank.z * 0.6, bank.z * 1.15, d)) * 0.75)
	return Vector3(lava, magma, haze)


## The summit's radii as its profile has them (the shader interpolates them the same way).
func _edge(crater: NelvarCraterData) -> void:
	edge = crater.summit.radii.duplicate()


## Per column: the lowest point of the summit's outline on screen (its south side).
func _slope(crater: NelvarCraterData) -> void:
	var outline := crater.summit.polygon(crater.summit.radii.size())
	var left := INF
	var right := -INF
	for point in outline:
		left = minf(left, point.x / STEP)
		right = maxf(right, point.x / STEP)
	slope_origin = floori(left) - 1
	var columns := ceili(right) - slope_origin + 2
	slope = PackedFloat32Array()
	slope.resize(columns)
	slope.fill(-1.0)
	for i in outline.size():
		var a := outline[i] / STEP
		var b := outline[(i + 1) % outline.size()] / STEP
		if a.x > b.x:
			var swap := a
			a = b
			b = swap
		for column in range(ceili(a.x - 0.5), floori(b.x - 0.5) + 1):
			var x := column + 0.5
			if x < a.x or x > b.x:
				continue
			var t := 0.0 if is_equal_approx(a.x, b.x) else (x - a.x) / (b.x - a.x)
			var y := lerpf(a.y, b.y, t)
			var c := column - slope_origin
			if c >= 0 and c < columns:
				slope[c] = maxf(slope[c], y)
