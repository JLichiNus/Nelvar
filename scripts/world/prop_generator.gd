class_name NelvarPropGenerator
extends RefCounted
## Scatters rocks and bushes over each island after the forest. Rocks keep hubs, bridge
## routes, the spawn area and passages open just like trunks do; bushes gather at the
## foot of trees and in the open. Nothing is placed where a tree crown would hide it.

const ATTEMPTS_PER_PROP := 40


func generate(world: NelvarWorldData, forest: NelvarForestData,
		forest_config: NelvarForestConfig, config: NelvarPropConfig) -> NelvarPropData:
	var result := NelvarPropData.new()
	for island in world.islands:
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%d:props:%d" % [world.world_seed, island.id]).hash()
		# A crown on a neighbouring island can reach over this one's edge.
		var trees: Array[NelvarForestData.TreeSpec] = []
		for tree in forest.trees:
			if tree.island_id == island.id \
					or tree.position.distance_to(island.center) < island.radius * 1.2 + 400.0:
				trees.append(tree)
		_place_rocks(island, trees, world, forest_config, config, rng, result)
		_place_bushes(island, trees, world, forest_config, config, rng, result)
	return result


func _place_rocks(island: NelvarWorldData.Island, trees: Array[NelvarForestData.TreeSpec],
		world: NelvarWorldData, forest_config: NelvarForestConfig, config: NelvarPropConfig,
		rng: RandomNumberGenerator, result: NelvarPropData) -> void:
	var count_range := config.large_island_rocks if island.large else config.small_island_rocks
	var target := rng.randi_range(count_range.x, count_range.y)
	var placed := 0
	for attempt in target * ATTEMPTS_PER_PROP:
		if placed >= target:
			break
		var radius := rng.randf_range(config.rock_radius.x, config.rock_radius.y)
		if rng.randf() < config.boulder_chance:
			radius = rng.randf_range(config.boulder_radius.x, config.boulder_radius.y)
		var point := _random_point(island, rng)
		if not _rock_fits(point, radius, null, island, trees, world, forest_config, result):
			continue
		var rock := _add(result, NelvarPropData.Kind.ROCK, island, point, radius, rng)
		rock.accent = rng.randf() < config.moss_chance
		placed += 1
		if rng.randf() >= config.companion_chance:
			continue
		# A small stone resting against the rock's side, slightly in front of it.
		var small := maxf(11.0, radius * rng.randf_range(0.38, 0.55))
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var spot := point + Vector2(side * (radius + small) * rng.randf_range(0.72, 0.86),
			radius * NelvarPropData.FOOTPRINT * rng.randf_range(0.2, 0.7))
		if _rock_fits(spot, small, rock, island, trees, world, forest_config, result):
			var stone := _add(result, NelvarPropData.Kind.ROCK, island, spot, small, rng)
			stone.anchor_id = rock.id
			stone.accent = rock.accent and rng.randf() < 0.5


func _place_bushes(island: NelvarWorldData.Island, trees: Array[NelvarForestData.TreeSpec],
		world: NelvarWorldData, forest_config: NelvarForestConfig, config: NelvarPropConfig,
		rng: RandomNumberGenerator, result: NelvarPropData) -> void:
	var count_range := config.large_island_bushes if island.large else config.small_island_bushes
	var target := rng.randi_range(count_range.x, count_range.y)
	var own: Array[NelvarForestData.TreeSpec] = []
	for tree in trees:
		if tree.island_id == island.id:
			own.append(tree)
	var placed := 0
	for attempt in target * ATTEMPTS_PER_PROP:
		if placed >= target:
			break
		var radius := rng.randf_range(config.bush_radius.x, config.bush_radius.y)
		var palette := rng.randi_range(0, 2)
		var point: Vector2
		if not own.is_empty() and rng.randf() < config.grove_bush_share:
			# At the foot of a tree, beside or in front of the trunk, and in its colours.
			var tree := own[rng.randi_range(0, own.size() - 1)]
			var angle := rng.randf_range(-0.12, 1.12) * PI
			point = tree.position + Vector2.from_angle(angle) \
				* (tree.trunk_radius + radius * rng.randf_range(0.7, 1.3))
			palette = tree.palette
		else:
			point = _random_point(island, rng)
		if not _bush_fits(point, radius, island, trees, world, forest_config, result):
			continue
		var bush := _add(result, NelvarPropData.Kind.BUSH, island, point, radius, rng)
		bush.palette = palette
		bush.accent = rng.randf() < config.blossom_chance
		placed += 1


func _rock_fits(point: Vector2, radius: float, anchor: NelvarPropData.PropSpec,
		island: NelvarWorldData.Island, trees: Array[NelvarForestData.TreeSpec],
		world: NelvarWorldData, forest_config: NelvarForestConfig, result: NelvarPropData) -> bool:
	if not NelvarForestGenerator.inside_shore(point, island, radius + forest_config.shore_margin):
		return false
	if point.distance_to(island.center) < forest_config.hub_radius + radius:
		return false
	if point.distance_to(world.spawn_position) < forest_config.spawn_radius + radius:
		return false
	if NelvarForestGenerator.in_path(point, radius, island, world, forest_config):
		return false
	for tree in trees:
		if point.distance_to(tree.position) < tree.trunk_radius + radius + forest_config.passage_width:
			return false
		if _behind_crown(point, radius, tree):
			return false
	for other in result.props:
		if not other.is_solid():
			continue
		var spacing := radius + other.radius + forest_config.passage_width
		if other == anchor:
			# A stone may lean against its rock: together they are one obstacle.
			spacing = (radius + other.radius) * 0.6
		if point.distance_to(other.position) < spacing:
			return false
	return true


func _bush_fits(point: Vector2, radius: float, island: NelvarWorldData.Island,
		trees: Array[NelvarForestData.TreeSpec], world: NelvarWorldData,
		forest_config: NelvarForestConfig, result: NelvarPropData) -> bool:
	# Bushes do not block movement, but they keep the routes and the start readable.
	if not NelvarForestGenerator.inside_shore(point, island, radius + 8.0):
		return false
	if point.distance_to(island.center) < forest_config.hub_radius + radius * 0.5:
		return false
	if point.distance_to(world.spawn_position) < forest_config.spawn_radius * 0.75 + radius:
		return false
	if NelvarForestGenerator.in_path(point, radius * 0.5, island, world, forest_config):
		return false
	for tree in trees:
		if point.distance_to(tree.position) < tree.trunk_radius + radius * 0.7:
			return false
		if _behind_crown(point, radius, tree):
			return false
	for other in result.props:
		var spacing := (radius + other.radius) * (1.0 if other.is_solid() else 0.85)
		if point.distance_to(other.position) < spacing:
			return false
	return true


## True when a prop standing behind the trunk would disappear under the tree's crown.
static func _behind_crown(point: Vector2, radius: float, tree: NelvarForestData.TreeSpec) -> bool:
	if point.y > tree.position.y:
		return false
	var crown := tree.position + tree.canopy_center()
	var reach := tree.canopy_axes() * Vector2(1.25, 1.1) + Vector2.ONE * radius
	var top := point - Vector2(0.0, radius * 0.4)
	return ((top - crown) / reach).length_squared() < 1.0


static func _random_point(island: NelvarWorldData.Island, rng: RandomNumberGenerator) -> Vector2:
	return island.center + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * island.radius


static func _add(result: NelvarPropData, kind: NelvarPropData.Kind, island: NelvarWorldData.Island,
		point: Vector2, radius: float, rng: RandomNumberGenerator) -> NelvarPropData.PropSpec:
	var prop := NelvarPropData.PropSpec.new()
	prop.id = result.props.size()
	prop.kind = kind
	prop.island_id = island.id
	prop.position = point
	prop.radius = radius
	prop.appearance_seed = int(rng.randi())
	result.props.append(prop)
	return prop
