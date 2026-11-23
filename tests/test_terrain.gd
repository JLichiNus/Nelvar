extends SceneTree
## Checks that the pixel skin is reproducible and cannot change map geometry.

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config := NelvarWorldConfig.new()
	var style := NelvarTerrainStyle.new()
	var generator := NelvarWorldGenerator.new()
	var data := generator.generate(config, 20261120)
	var before := _geometry_fingerprint(data)
	var painter := NelvarTerrainPainter.new()
	var artwork := painter.paint(data, style)
	var bridge_painter := NelvarBridgePainter.new()
	var bridge_artwork := bridge_painter.paint(data, style)
	_check(before == _geometry_fingerprint(data), "Painting changed map geometry or collisions")
	# Changing the spatial partition must not change the painted world.
	config.chunk_depth = 3
	var repartitioned := generator.generate(config, 20261120)
	var repeated := painter.paint(repartitioned, style)
	var repeated_bridges := bridge_painter.paint(repartitioned, style)
	var grassless := style.duplicate() as NelvarTerrainStyle
	grassless.grass_density = 0.0
	var without_grass := painter.paint(data, grassless)
	var grassless_bridges := bridge_painter.paint(data, grassless)
	var flowerless := style.duplicate() as NelvarTerrainStyle
	flowerless.flower_density = 0.0
	var without_flowers := painter.paint(data, flowerless)
	var only_flowers := style.duplicate() as NelvarTerrainStyle
	only_flowers.flower_density = 1.0
	var all_flowers := painter.paint(data, only_flowers)
	_check(artwork.size() == data.islands.size(), "An island has no pixel artwork")
	for i in artwork.size():
		var art := artwork[i]
		var island := data.islands[i]
		_check(art.surface_image.get_data() == repeated[i].surface_image.get_data(),
			"Ground pixels depend on chunk subdivision")
		_check(art.underside_image.get_data() == repeated[i].underside_image.get_data(),
			"Cliff or roots depend on chunk subdivision")
		_check(art.surface_image.get_data() != without_grass[i].surface_image.get_data(),
			"Grass density has no visible effect")
		_check(art.underside_image.get_data() == without_grass[i].underside_image.get_data(),
			"Changing grass density changed roots or cliffs")
		_check(art.underside_image.get_data() == without_flowers[i].underside_image.get_data(),
			"Changing flower density changed roots or cliffs")
		var tufts := _count_colors(without_flowers[i].surface_image,
			[NelvarTerrainPainter.TUFT_TIP, NelvarTerrainPainter.TUFT_TIP_BRIGHT])
		var flowers := _count_colors(art.surface_image, NelvarTerrainPainter.FLOWER_PETALS)
		var crowded := _count_colors(all_flowers[i].surface_image, NelvarTerrainPainter.FLOWER_PETALS)
		_check(flowers == 0 or flowers < tufts, "Flowers are not rarer than grass tufts")
		_check(crowded > flowers or tufts == 0, "Flower density has no visible effect")
		_check(_count_colors(without_flowers[i].surface_image, NelvarTerrainPainter.FLOWER_PETALS) == 0,
			"Flowers appear with zero flower density")
		var origin := art.world_rect.position / art.pixel_size
		_check(origin.is_equal_approx(origin.round()), "Artwork is not aligned to the world pixel grid")
		_check(art.world_rect.size == Vector2(art.surface_image.get_size()) * art.pixel_size,
			"Texture scale does not match the world rectangle")
		for y in range(2, art.surface_image.get_height(), 11):
			for x in range(2, art.surface_image.get_width(), 11):
				var point := art.world_rect.position + Vector2(x + 0.5, y + 0.5) * art.pixel_size
				var expected := Geometry2D.is_point_in_polygon(point, island.polygon)
				_check((art.surface_image.get_pixel(x, y).a > 0.5) == expected,
					"Surface pixels do not match the generated island silhouette")
		var below_ground := ceili((island.bounds.end.y - art.world_rect.position.y) / art.pixel_size)
		var root_pixels := 0
		for y in range(below_ground + style.cliff_depth + 3, art.underside_image.get_height(), 2):
			for x in range(0, art.underside_image.get_width(), 2):
				if art.underside_image.get_pixel(x, y).a > 0.5:
					root_pixels += 1
		_check(root_pixels > 0, "Island has no hanging root pixels below the cliff")
	_check_bridges(data, bridge_artwork, repeated_bridges, grassless_bridges, style)
	if _failures.is_empty():
		print("PASS: %d terrain checks; islands and bridges share a deterministic pixel grid." % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _check_bridges(data: NelvarWorldData, artwork: Array[NelvarBridgeArt],
		repeated: Array[NelvarBridgeArt], grassless: Array[NelvarBridgeArt],
		style: NelvarTerrainStyle) -> void:
	_check(artwork.size() == data.bridges.size(), "A bridge has no baked artwork")
	for i in artwork.size():
		var art := artwork[i]
		var bridge := data.bridges[i]
		_check(art.pixel_size == style.pixel_size, "Bridge and terrain pixel sizes differ")
		var origin := art.world_rect.position / art.pixel_size
		_check(origin.is_equal_approx(origin.round()), "Bridge is not aligned to the world grid")
		_check(art.world_rect.size == Vector2(art.image.get_size()) * art.pixel_size,
			"Baked bridge image is stretched")
		_check(art.image.get_data() == repeated[i].image.get_data(),
			"Bridge painting depends on chunk subdivision")
		_check(art.image.get_data() == grassless[i].image.get_data(),
			"Grass density changed bridge artwork")
		var pixels := art.image.get_data()
		for alpha in range(3, pixels.size(), 68):
			_check(pixels[alpha] == 0 or pixels[alpha] == 255,
				"Baked bridge has blurred pixel edges")
		var side := bridge.start.direction_to(bridge.finish).orthogonal()
		for along in range(1, 10):
			for offset: float in [-1.0, 0.0, 1.0]:
				var point := bridge.start.lerp(bridge.finish, float(along) / 10.0)
				point += side * offset * (bridge.width * 0.5 - art.pixel_size * 2.0)
				var cell := Vector2i(((point - art.world_rect.position) / art.pixel_size).floor())
				_check(art.image.get_pixelv(cell).a > 0.5, "Hole in the visible bridge deck")


func _count_colors(image: Image, colors: Array[Color]) -> int:
	var total := 0
	for y in image.get_height():
		for x in image.get_width():
			if colors.has(image.get_pixel(x, y)):
				total += 1
	return total


func _geometry_fingerprint(data: NelvarWorldData) -> int:
	var parts: Array = [data.spawn_position]
	for island in data.islands:
		parts.append(island.polygon)
	for bridge in data.bridges:
		parts.append(bridge.polygon)
	for border in data.borders:
		parts.append([border.start, border.finish])
	return hash(parts)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition and _failures.size() < 20:
		_failures.append(message)
