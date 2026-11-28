class_name NelvarForestGenerator
extends RefCounted
## Bounded clustered placement with clear hubs, bridge paths and trunk spacing.


func generate(world: NelvarWorldData, config: NelvarForestConfig) -> NelvarForestData:
	var result := NelvarForestData.new()
	for island in world.islands:
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%d:forest:%d" % [world.world_seed, island.id]).hash()
		var group_range := config.large_island_groups if island.large else config.small_island_groups
		var group_count := rng.randi_range(group_range.x, group_range.y)
		if not island.large and rng.randf() >= config.small_island_grove_chance:
			group_count = 0
		for group in group_count:
			var best_cluster: NelvarForestData.Cluster
			var best_trees: Array[NelvarForestData.TreeSpec] = []
			for trial in 3:
				var cluster := _cluster(island, result, world, config, rng)
				if cluster == null:
					continue
				var trees := _members(cluster, island, result, world, config, rng)
				if trees.size() > best_trees.size():
					best_cluster = cluster
					best_trees = trees
				if trees.size() >= 3:
					break
			if best_trees.size() < 2:
				continue
			best_cluster.id = result.clusters.size()
			for tree in best_trees:
				tree.id = result.trees.size()
				tree.cluster_id = best_cluster.id
				best_cluster.tree_ids.append(tree.id)
				result.trees.append(tree)
			result.clusters.append(best_cluster)
	return result


func _cluster(island: NelvarWorldData.Island, existing: NelvarForestData,
		world: NelvarWorldData, config: NelvarForestConfig,
		rng: RandomNumberGenerator) -> NelvarForestData.Cluster:
	var cluster := NelvarForestData.Cluster.new()
	cluster.island_id = island.id
	cluster.radius = minf(rng.randf_range(config.group_radius.x, config.group_radius.y),
		island.radius * 0.55)
	cluster.stretch = rng.randf_range(0.72, 1.0)
	cluster.rotation = rng.randf() * TAU
	cluster.palette = rng.randi_range(0, 2)
	cluster.form = rng.randi_range(0, 2)
	for attempt in 160:
		var center := island.center + Vector2.from_angle(rng.randf() * TAU) \
			* rng.randf_range(0.3, 0.70) * island.radius
		if center.distance_to(island.center) < config.hub_radius + 24.0:
			continue
		if in_path(center, 20.0, island, world, config):
			continue
		if not inside_shore(center, island, 56.0):
			continue
		var overlaps := false
		for other in existing.clusters:
			if other.island_id == island.id \
					and center.distance_to(other.center) < (cluster.radius + other.radius) * 0.80:
				overlaps = true
				break
		if not overlaps:
			cluster.center = center
			return cluster
	return null


func _members(cluster: NelvarForestData.Cluster, island: NelvarWorldData.Island,
		existing: NelvarForestData, world: NelvarWorldData, config: NelvarForestConfig,
		rng: RandomNumberGenerator) -> Array[NelvarForestData.TreeSpec]:
	var result: Array[NelvarForestData.TreeSpec] = []
	var count_range := config.large_group_trees if island.large else config.small_group_trees
	var target := rng.randi_range(count_range.x, count_range.y)
	for attempt in target * 100:
		if result.size() >= target:
			break
		var offset := Vector2(rng.randfn(0.0, 0.44), rng.randfn(0.0, 0.44))
		if offset.length_squared() > 1.0:
			continue
		offset *= Vector2(cluster.radius, cluster.radius * cluster.stretch)
		var tree := NelvarForestData.TreeSpec.new()
		tree.position = cluster.center + offset.rotated(cluster.rotation)
		tree.island_id = island.id
		var scale := _size_scale(config, rng)
		# Trunks thicken slower than crowns grow, so young trees stay slender.
		tree.trunk_radius = rng.randf_range(config.trunk_radius.x, config.trunk_radius.y) * sqrt(scale)
		tree.canopy_radius = rng.randf_range(config.canopy_radius.x, config.canopy_radius.y) * scale
		tree.trunk_height = rng.randf_range(config.trunk_height.x, config.trunk_height.y) \
			* scale * rng.randf_range(0.85, 1.15)
		tree.lean = rng.randf_range(3.0, 15.0)  # ветер дует вправо
		tree.palette = cluster.palette if rng.randf() < 0.8 else rng.randi_range(0, 2)
		tree.form = cluster.form if rng.randf() < 0.8 else rng.randi_range(0, 2)
		tree.appearance_seed = int(rng.randi())
		if _fits(tree, island, existing, result, world, config):
			result.append(tree)
	return result


## Young, grown or old: groves mix trees of clearly different sizes.
func _size_scale(config: NelvarForestConfig, rng: RandomNumberGenerator) -> float:
	var roll := rng.randf()
	if roll < config.young_tree_chance:
		return rng.randf_range(config.young_tree_scale.x, config.young_tree_scale.y)
	if roll < config.young_tree_chance + config.old_tree_chance:
		return rng.randf_range(config.old_tree_scale.x, config.old_tree_scale.y)
	return rng.randf_range(0.85, 1.12)


func _fits(tree: NelvarForestData.TreeSpec, island: NelvarWorldData.Island,
		existing: NelvarForestData, local_trees: Array[NelvarForestData.TreeSpec],
		world: NelvarWorldData, config: NelvarForestConfig) -> bool:
	var point := tree.position
	if point.distance_to(island.center) < config.hub_radius + tree.trunk_radius:
		return false
	if point.distance_to(world.spawn_position) < config.spawn_radius + tree.trunk_radius:
		return false
	# The initial camera view should reveal the dummy instead of spawning it
	# beneath a nearby southern canopy. Other canopies can overlap the player.
	var crown := tree.position + tree.canopy_center()
	var axes := tree.canopy_axes() * 1.25 + Vector2.ONE * 48.0
	if ((world.spawn_position - crown) / axes).length_squared() < 1.0:
		return false
	if in_path(point, tree.trunk_radius, island, world, config):
		return false
	for other in existing.trees:
		if not _separated(tree, other, config):
			return false
	for other in local_trees:
		if not _separated(tree, other, config):
			return false
	return inside_shore(point, island, tree.trunk_radius + config.shore_margin)


func _separated(a: NelvarForestData.TreeSpec, b: NelvarForestData.TreeSpec,
		config: NelvarForestConfig) -> bool:
	# Big crowns need more room, young trees may stand closer.
	var typical := (config.canopy_radius.x + config.canopy_radius.y) * 0.5
	var crowns := (a.canopy_radius + b.canopy_radius) * 0.5 / typical
	var room := config.tree_spacing * clampf(crowns, 0.7, 1.5)
	var spacing := maxf(room, a.trunk_radius + b.trunk_radius + config.passage_width)
	return a.position.distance_squared_to(b.position) >= spacing * spacing


## True when a circle crosses the reserved route from the island hub to one of its bridges.
static func in_path(point: Vector2, radius: float, island: NelvarWorldData.Island,
		world: NelvarWorldData, config: NelvarForestConfig) -> bool:
	for bridge in world.bridges:
		var landing: Vector2
		if bridge.island_a == island.id:
			landing = bridge.start
		elif bridge.island_b == island.id:
			landing = bridge.finish
		else:
			continue
		var closest := Geometry2D.get_closest_point_to_segment(point, island.center, landing)
		if point.distance_to(closest) < config.path_half_width + radius:
			return true
	return false


## True when the point is on the island and at least `clearance` away from its shore.
static func inside_shore(point: Vector2, island: NelvarWorldData.Island, clearance: float) -> bool:
	if not Geometry2D.is_point_in_polygon(point, island.polygon):
		return false
	for i in island.polygon.size():
		var closest := Geometry2D.get_closest_point_to_segment(point,
			island.polygon[i], island.polygon[(i + 1) % island.polygon.size()])
		if point.distance_squared_to(closest) < clearance * clearance:
			return false
	return true
