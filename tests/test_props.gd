extends SceneTree
## Rocks and bushes: placement rules, reproducible artwork, rock collision, walk-through bushes.
## Run: godot --headless --path . --script tests/test_props.gd

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var generator := NelvarWorldGenerator.new()
	var forest_config := NelvarForestConfig.new()
	var config := NelvarPropConfig.new()
	var style := NelvarTerrainStyle.new()
	var painter := NelvarPropPainter.new()
	for index in 10:
		var world := generator.generate(NelvarWorldConfig.new(), 20261120 + index * 7919)
		var forest := NelvarForestGenerator.new().generate(world, forest_config)
		var props := NelvarPropGenerator.new().generate(world, forest, forest_config, config)
		var context := "Seed %d: " % world.world_seed
		_check(props.count(NelvarPropData.Kind.ROCK) >= world.islands.size(), context + "too few rocks")
		_check(props.count(NelvarPropData.Kind.BUSH) >= world.islands.size() * 2, context + "too few bushes")
		_check(props.has_clearance(world.spawn_position, NelvarPlayer.BODY_RADIUS),
			context + "a rock blocks the spawn")
		for prop in props.props:
			_check_prop(prop, props, world, forest, forest_config, context)
		var repeat := NelvarPropGenerator.new().generate(world, forest, forest_config, config)
		_check(_fingerprint(props) == _fingerprint(repeat), context + "prop layout is not reproducible")
		if index == 0:
			var images: Dictionary = {}
			for prop in props.props.slice(0, 12):
				var art := painter.paint(prop, style)
				_check(art.image.get_data() == painter.paint(prop, style).image.get_data(),
					"Prop pixels are not reproducible")
				var grid_origin: Vector2 = (prop.position + art.local_rect.position) / art.pixel_size
				_check(grid_origin.is_equal_approx(grid_origin.round()), "Prop pixels are off the world grid")
				images[hash(art.image.get_data())] = true
			_check(images.size() >= 10, "Props share identical artwork")
	await _physics_check()
	if _failures.is_empty():
		print("PASS: %d prop checks; placement, artwork, solid rocks and walk-through bushes." % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _check_prop(prop: NelvarPropData.PropSpec, props: NelvarPropData, world: NelvarWorldData,
		forest: NelvarForestData, forest_config: NelvarForestConfig, context: String) -> void:
	var island := world.islands[prop.island_id]
	_check(NelvarForestGenerator.inside_shore(prop.position, island, prop.radius),
		context + "a prop hangs over the shore")
	for tree in forest.trees:
		if prop.position.y < tree.position.y:
			var crown := tree.position + tree.canopy_center()
			_check(((prop.position - crown) / tree.canopy_axes()).length_squared() >= 1.0,
				context + "a prop hides under a tree crown")
	if not prop.is_solid():
		_check(not NelvarForestGenerator.in_path(prop.position, 0.0, island, world, forest_config),
			context + "a bush stands on a bridge route")
		return
	_check(NelvarForestGenerator.inside_shore(prop.position, island,
		prop.radius + forest_config.shore_margin - 0.1), context + "a rock is too close to the shore")
	_check(prop.position.distance_to(island.center) >= forest_config.hub_radius + prop.radius - 0.1,
		context + "a rock blocks an island hub")
	_check(prop.position.distance_to(world.spawn_position) >= forest_config.spawn_radius + prop.radius - 0.1,
		context + "a rock blocks the spawn area")
	_check(not NelvarForestGenerator.in_path(prop.position, prop.radius - 0.1, island, world, forest_config),
		context + "a rock blocks a bridge route")
	for tree in forest.trees:
		_check(prop.position.distance_to(tree.position)
			>= prop.radius + tree.trunk_radius + forest_config.passage_width - 0.1,
			context + "no passage between a rock and a trunk")
	for other in props.props:
		if other.id <= prop.id or not other.is_solid():
			continue
		if other.anchor_id == prop.id or prop.anchor_id == other.id:
			continue
		_check(prop.position.distance_to(other.position)
			>= prop.radius + other.radius + forest_config.passage_width - 0.1,
			context + "no passage between two rocks")


func _physics_check() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	await physics_frame
	for enemy in get_nodes_in_group("enemies"):
		enemy.queue_free()
	game.enemy_spawner.set_process(false)
	var player: NelvarPlayer = game.player
	var rock: NelvarProp
	var bush: NelvarProp
	for node: NelvarProp in game.prop_nodes:
		_check(node.get_parent() == game.actors and node.z_index == player.z_index,
			"Prop cannot sort against the player")
		var collider := node.get_node_or_null("RockCollision") as CollisionShape2D
		if node.prop_data.is_solid():
			_check(collider != null and node.collision_layer == NelvarProp.rock_layer(node.prop_data.radius),
				"A rock has no collider")
			if rock == null and _open_around(game, node.position, node.prop_data.radius + 60.0):
				rock = node
		else:
			_check(collider == null and node.collision_layer == 0, "A bush blocks movement")
			if bush == null and _open_around(game, node.position, node.prop_data.radius + 50.0, node):
				bush = node
	_check(rock != null, "No rock with open ground around it for a walking test")
	_check(bush != null, "No bush with open ground around it for a walking test")
	if rock != null:
		var contact := rock.prop_data.radius + NelvarPlayer.BODY_RADIUS
		player.position = rock.position - Vector2(contact + 30.0, 0.0)
		player.velocity = Vector2.ZERO
		await _hold(Vector2.RIGHT, 40)
		_check(player.position.x < rock.position.x - rock.prop_data.radius,
			"Player walked through a rock")
		_check(player.position.distance_to(rock.position) < contact + 4.0, "Player did not reach the rock")
	if bush != null:
		var start := bush.position - Vector2(bush.prop_data.radius + 30.0, 0.0)
		player.position = start
		player.velocity = Vector2.ZERO
		await _hold(Vector2.RIGHT, 40)
		_check(player.position.x > bush.position.x + bush.prop_data.radius, "A bush stopped the player")
	var key := InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	game._unhandled_input(key)
	if rock != null:
		_check(rock.show_collision, "F3 does not show rock colliders")
	game.queue_free()
	await process_frame


## Free ground (no shore, trunk or other prop) on a horizontal line through the point.
func _open_around(game: Node, point: Vector2, reach: float, except: NelvarProp = null) -> bool:
	for offset in range(-int(reach), int(reach) + 1, 6):
		var sample := point + Vector2(offset, 0.0)
		if not game.world_data.has_clearance(sample, NelvarPlayer.BODY_RADIUS + 2.0):
			return false
		if not game.forest_data.has_clearance(sample, NelvarPlayer.BODY_RADIUS + 2.0):
			return false
	for other: NelvarProp in game.prop_nodes:
		if other == except:
			continue
		var gap := absf(other.position.y - point.y)
		if other.prop_data.is_solid() and other.position.distance_to(point) < reach + other.prop_data.radius \
				and gap < other.prop_data.radius + NelvarPlayer.BODY_RADIUS + 2.0 and other.position != point:
			return false
	return true


func _hold(direction: Vector2, frames: int) -> void:
	Input.action_press("move_right" if direction.x > 0.0 else "move_left")
	for frame in frames:
		await physics_frame
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)


func _fingerprint(props: NelvarPropData) -> int:
	var parts: Array = []
	for prop in props.props:
		parts.append([prop.kind, prop.position, prop.radius, prop.anchor_id, prop.accent,
			prop.palette, prop.appearance_seed])
	return hash(parts)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition and _failures.size() < 30:
		_failures.append(message)
