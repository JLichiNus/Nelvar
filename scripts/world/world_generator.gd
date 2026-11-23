class_name NelvarWorldGenerator
extends RefCounted
## Bounded deterministic pipeline: layout -> shores -> bridges -> chunks -> borders.

const LAYOUT_ATTEMPTS := 16
const PLACEMENT_SAMPLES := 180
const SHORE_ENVELOPE := 1.17
const GEOMETRY_EPSILON := 0.01
## Exposed edge pieces shorter than this are numerical slivers where a bridge meets a
## shore; far narrower than any body, so dropping them leaves no gap to slip through.
const MIN_BORDER_LENGTH := 0.5


func generate(config: NelvarWorldConfig, world_seed: int) -> NelvarWorldData:
	var error := config.validation_error()
	if not error.is_empty():
		push_error(error)
		return null
	for attempt in LAYOUT_ATTEMPTS:
		var data := NelvarWorldData.new()
		data.world_seed = world_seed
		var rng := _rng(world_seed, "layout:%d" % attempt)
		if not _place_islands(data, config, rng):
			continue
		_shape_islands(data, config, _rng(world_seed, "shores:%d" % attempt))
		if not _connect_islands(data, config):
			continue
		var island_ids: Array[int] = []
		var bridge_ids: Array[int] = []
		for island in data.islands:
			island_ids.append(island.id)
		for i in data.bridges.size():
			bridge_ids.append(i)
		var extent := Vector2.ONE * config.world_size
		data.root = _build_chunk(data, config, Rect2(-extent * 0.5, extent),
			0, island_ids, bridge_ids)
		_build_borders(data, config)
		data.spawn_position = data.islands[0].center
		if data.has_clearance(data.spawn_position, config.character_width):
			return data
	push_error("Unable to build a connected map for seed %d." % world_seed)
	return null


func _rng(world_seed: int, stage: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:%s" % [world_seed, stage]).hash()
	return rng


func _place_islands(data: NelvarWorldData, config: NelvarWorldConfig,
		rng: RandomNumberGenerator) -> bool:
	var large_count := rng.randi_range(config.large_count_min, config.large_count_max)
	var small_count := rng.randi_range(config.small_count_min, config.small_count_max)
	for id in large_count + small_count:
		var island := NelvarWorldData.Island.new()
		island.id = id
		island.large = id < large_count
		var radius_range := config.large_radius if island.large else config.small_radius
		island.radius = rng.randf_range(radius_range.x, radius_range.y)
		if id == 0:
			island.center = Vector2.ZERO
		else:
			var best_score := INF
			for sample in PLACEMENT_SAMPLES:
				var parent := data.islands[rng.randi_range(0, data.islands.size() - 1)]
				var distance := (parent.radius + island.radius) * SHORE_ENVELOPE
				distance += rng.randf_range(config.island_gap.x, config.island_gap.y)
				var candidate := parent.center + Vector2.from_angle(rng.randf() * TAU) * distance
				if not _position_fits(candidate, island.radius, data, config):
					continue
				# Compact composition with variation, rather than a long chain.
				var score := candidate.length() + rng.randf_range(0.0, 240.0)
				if score < best_score:
					best_score = score
					island.center = candidate
			if best_score == INF:
				return false
		data.islands.append(island)
	return true


func _position_fits(center: Vector2, radius: float, data: NelvarWorldData,
		config: NelvarWorldConfig) -> bool:
	var edge := config.world_size * 0.5 - radius * SHORE_ENVELOPE - 128.0
	if absf(center.x) > edge or absf(center.y) > edge:
		return false
	for other in data.islands:
		var clearance := (radius + other.radius) * SHORE_ENVELOPE + config.island_gap.x
		if center.distance_to(other.center) < clearance:
			return false
	return true


func _shape_islands(data: NelvarWorldData, config: NelvarWorldConfig,
		rng: RandomNumberGenerator) -> void:
	for island in data.islands:
		var phases := Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		var stretch := Vector2(rng.randf_range(0.91, 1.0), rng.randf_range(0.86, 1.0))
		for i in config.shore_vertices:
			var angle := TAU * float(i) / config.shore_vertices
			# Broad lobes, smaller bays, then fine shoreline detail.
			var factor := 1.0 + 0.085 * sin(angle * 3.0 + phases.x)
			factor += 0.045 * sin(angle * 7.0 + phases.y)
			factor += 0.018 * sin(angle * 13.0 + phases.z)
			island.polygon.append(island.center + Vector2.from_angle(angle)
				* island.radius * factor * stretch)
		island.bounds = _polygon_bounds(island.polygon)
		if island.id == 0:
			data.bounds = island.bounds
		else:
			data.bounds = data.bounds.merge(island.bounds)


func _connect_islands(data: NelvarWorldData, config: NelvarWorldConfig) -> bool:
	var candidates: Array[NelvarWorldData.Bridge] = []
	for a in data.islands.size():
		for b in range(a + 1, data.islands.size()):
			var bridge := _bridge_between(data.islands[a], data.islands[b], config.bridge_width())
			if not _hits_other_island(bridge, data):
				candidates.append(bridge)
	candidates.sort_custom(func(a: NelvarWorldData.Bridge, b: NelvarWorldData.Bridge) -> bool:
		return a.start.distance_squared_to(a.finish) < b.start.distance_squared_to(b.finish))
	var groups: Array[int] = []
	for i in data.islands.size():
		groups.append(i)
	for bridge in candidates:
		if groups[bridge.island_a] == groups[bridge.island_b]:
			continue
		if _hits_bridge(bridge, data):
			continue
		var old_group := groups[bridge.island_b]
		var new_group := groups[bridge.island_a]
		for i in groups.size():
			if groups[i] == old_group:
				groups[i] = new_group
		data.bridges.append(bridge)
	if data.bridges.size() != data.islands.size() - 1:
		return false
	var extras := 0
	for bridge in candidates:
		if extras >= config.extra_connections:
			break
		if data.bridges.has(bridge) or _hop_distance(bridge.island_a, bridge.island_b, data) < 3:
			continue
		if not _hits_bridge(bridge, data):
			data.bridges.append(bridge)
			extras += 1
	return true


func _bridge_between(a: NelvarWorldData.Island, b: NelvarWorldData.Island,
		width: float) -> NelvarWorldData.Bridge:
	var bridge := NelvarWorldData.Bridge.new()
	bridge.island_a = a.id
	bridge.island_b = b.id
	bridge.width = width
	var direction := a.center.direction_to(b.center)
	var side := direction.orthogonal() * width * 0.5
	bridge.start = _shore_point(a, direction)
	bridge.finish = _shore_point(b, -direction)
	# Both corners of each landing must be supported by the island.
	for step in 16:
		if Geometry2D.is_point_in_polygon(bridge.start + side, a.polygon) \
				and Geometry2D.is_point_in_polygon(bridge.start - side, a.polygon):
			break
		bridge.start -= direction * 8.0
	for step in 16:
		if Geometry2D.is_point_in_polygon(bridge.finish + side, b.polygon) \
				and Geometry2D.is_point_in_polygon(bridge.finish - side, b.polygon):
			break
		bridge.finish += direction * 8.0
	bridge.start -= direction * 16.0
	bridge.finish += direction * 16.0
	bridge.polygon = PackedVector2Array([
		bridge.start + side, bridge.finish + side,
		bridge.finish - side, bridge.start - side,
	])
	bridge.bounds = _polygon_bounds(bridge.polygon)
	return bridge


func _shore_point(island: NelvarWorldData.Island, direction: Vector2) -> Vector2:
	var finish := island.center + direction * island.radius * 2.0
	var nearest := finish
	for i in island.polygon.size():
		var hit: Variant = Geometry2D.segment_intersects_segment(island.center, finish,
			island.polygon[i], island.polygon[(i + 1) % island.polygon.size()])
		if hit is Vector2 and island.center.distance_squared_to(hit) \
				< island.center.distance_squared_to(nearest):
			nearest = hit
	return nearest


func _hits_other_island(bridge: NelvarWorldData.Bridge, data: NelvarWorldData) -> bool:
	for island in data.islands:
		if island.id == bridge.island_a or island.id == bridge.island_b:
			continue
		if bridge.bounds.intersects(island.bounds) \
				and not Geometry2D.intersect_polygons(bridge.polygon, island.polygon).is_empty():
			return true
	return false


func _hits_bridge(candidate: NelvarWorldData.Bridge, data: NelvarWorldData) -> bool:
	for other in data.bridges:
		if not candidate.bounds.intersects(other.bounds):
			continue
		for overlap in Geometry2D.intersect_polygons(candidate.polygon, other.polygon):
			var on_shared_island := false
			for id in [candidate.island_a, candidate.island_b]:
				if id != other.island_a and id != other.island_b:
					continue
				on_shared_island = true
				for point in overlap:
					if not Geometry2D.is_point_in_polygon(point, data.islands[id].polygon):
						on_shared_island = false
						break
				if on_shared_island:
					break
			if not on_shared_island:
				return true
	return false


func _hop_distance(start: int, finish: int, data: NelvarWorldData) -> int:
	var distances := {start: 0}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for bridge in data.bridges:
			var next := -1
			if bridge.island_a == current:
				next = bridge.island_b
			elif bridge.island_b == current:
				next = bridge.island_a
			if next < 0 or distances.has(next):
				continue
			distances[next] = distances[current] + 1
			if next == finish:
				return distances[next]
			queue.append(next)
	return -1


func _build_chunk(data: NelvarWorldData, config: NelvarWorldConfig, rect: Rect2,
		depth: int, island_ids: Array[int], bridge_ids: Array[int]) -> NelvarWorldData.Chunk:
	var chunk := NelvarWorldData.Chunk.new()
	chunk.rect = rect
	chunk.depth = depth
	var square := PackedVector2Array([rect.position,
		rect.position + Vector2(rect.size.x, 0.0), rect.end,
		rect.position + Vector2(0.0, rect.size.y)])
	var completely_covered := false
	for id in island_ids:
		if not rect.intersects(data.islands[id].bounds):
			continue
		var pieces := Geometry2D.intersect_polygons(data.islands[id].polygon, square)
		if pieces.is_empty():
			continue
		chunk.island_ids.append(id)
		for piece in pieces:
			if _polygon_area(piece) < GEOMETRY_EPSILON:
				continue
			chunk.ground_polygons.append(piece)
			chunk.ground_ids.append(id)
			if absf(_polygon_area(piece) - rect.get_area()) < 0.1:
				completely_covered = true
	for id in bridge_ids:
		if not rect.intersects(data.bridges[id].bounds):
			continue
		var pieces := Geometry2D.intersect_polygons(data.bridges[id].polygon, square)
		if pieces.is_empty():
			continue
		chunk.bridge_ids.append(id)
		for piece in pieces:
			if _polygon_area(piece) >= GEOMETRY_EPSILON:
				chunk.bridge_polygons.append(piece)
	if chunk.island_ids.is_empty() and chunk.bridge_ids.is_empty():
		return chunk
	if depth >= config.chunk_depth or completely_covered:
		data.leaves.append(chunk)
		return chunk
	# Interior chunks can stay large; shore and bridge chunks subdivide further.
	chunk.ground_polygons.clear()
	chunk.ground_ids.clear()
	chunk.bridge_polygons.clear()
	var half := rect.size * 0.5
	for y in 2:
		for x in 2:
			chunk.children.append(_build_chunk(data, config,
				Rect2(rect.position + half * Vector2(x, y), half), depth + 1,
				chunk.island_ids, chunk.bridge_ids))
	return chunk


func _build_borders(data: NelvarWorldData, config: NelvarWorldConfig) -> void:
	var polygons: Array[PackedVector2Array] = []
	var bounds: Array[Rect2] = []
	for island in data.islands:
		polygons.append(island.polygon)
		bounds.append(island.bounds)
	for bridge in data.bridges:
		polygons.append(bridge.polygon)
		bounds.append(bridge.bounds)
	# Split edges at intersections and keep only exposed parts of the union.
	# This also preserves the sky holes enclosed by cycles of bridges.
	for owner in polygons.size():
		var polygon := polygons[owner]
		var neighbors: Array[int] = []
		for other in polygons.size():
			if other != owner and bounds[owner].intersects(bounds[other]):
				neighbors.append(other)
		for edge in polygon.size():
			var start := polygon[edge]
			var finish := polygon[(edge + 1) % polygon.size()]
			var delta := finish - start
			var cuts: Array[float] = [0.0, 1.0]
			for other in neighbors:
				var other_polygon := polygons[other]
				for j in other_polygon.size():
					var hit: Variant = Geometry2D.segment_intersects_segment(start, finish,
						other_polygon[j], other_polygon[(j + 1) % other_polygon.size()])
					if hit is Vector2:
						cuts.append(clampf((hit - start).dot(delta) / delta.length_squared(), 0.0, 1.0))
			cuts.sort()
			for i in range(1, cuts.size()):
				if (cuts[i] - cuts[i - 1]) * delta.length() < MIN_BORDER_LENGTH:
					continue
				var middle := start + delta * (cuts[i] + cuts[i - 1]) * 0.5
				var hidden := false
				for other in neighbors:
					if Geometry2D.is_point_in_polygon(middle, polygons[other]):
						hidden = true
						break
				if not hidden:
					_add_border(data, config, start + delta * cuts[i - 1],
						start + delta * cuts[i], owner < data.islands.size())


func _add_border(data: NelvarWorldData, config: NelvarWorldConfig,
		start: Vector2, finish: Vector2, shore: bool) -> void:
	# Split at the smallest grid so collision segments belong to their own chunk.
	var cuts: Array[float] = [0.0, 1.0]
	var delta := finish - start
	var grid := config.smallest_chunk_size()
	for axis in 2:
		if absf(delta[axis]) < GEOMETRY_EPSILON:
			continue
		var low := minf(start[axis], finish[axis])
		var high := maxf(start[axis], finish[axis])
		var line := (floorf(low / grid) + 1.0) * grid
		while line < high:
			cuts.append((line - start[axis]) / delta[axis])
			line += grid
	cuts.sort()
	for i in range(1, cuts.size()):
		var a := start + delta * cuts[i - 1]
		var b := start + delta * cuts[i]
		if a.distance_to(b) < MIN_BORDER_LENGTH:
			continue
		var border := NelvarWorldData.Border.new()
		border.start = a
		border.finish = b
		border.shore = shore
		data.borders.append(border)
		var middle := (a + b) * 0.5
		var leaf := data.root.find_leaf(middle)
		# A point exactly on a grid edge can resolve into an empty neighbor.
		if leaf == null or (leaf.island_ids.is_empty() and leaf.bridge_ids.is_empty()):
			var normal := (b - a).orthogonal().normalized() * 0.1
			leaf = data.root.find_leaf(middle + normal)
			if leaf == null or (leaf.island_ids.is_empty() and leaf.bridge_ids.is_empty()):
				leaf = data.root.find_leaf(middle - normal)
		if leaf != null:
			leaf.borders.append(border)


func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	var rect := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		rect = rect.expand(point)
	return rect


func _polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for i in polygon.size():
		area += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return absf(area) * 0.5
