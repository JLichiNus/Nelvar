extends SceneTree
## Clustered placement, reproducible pixel artwork, trunk collision and traversal.

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var generator := NelvarWorldGenerator.new()
	var forest_generator := NelvarForestGenerator.new()
	var config := NelvarForestConfig.new()
	var style := NelvarTerrainStyle.new()
	var painter := NelvarTreePainter.new()
	for index in 12:
		var data := generator.generate(NelvarWorldConfig.new(), 20261120 + index * 7919)
		var layout := forest_generator.generate(data, config)
		_check(layout.clusters.size() >= 3 and layout.trees.size() >= 6, "Map has too few groves")
		_check(layout.has_clearance(data.spawn_position, NelvarPlayer.BODY_RADIUS), "Spawn is obstructed")
		for cluster in layout.clusters:
			_check(cluster.tree_ids.size() >= 2, "A grove is an isolated tree")
		for tree in layout.trees:
			var cluster := layout.clusters[tree.cluster_id]
			_check(cluster.tree_ids.has(tree.id), "Tree is missing from its grove")
			var local := (tree.position - cluster.center).rotated(-cluster.rotation)
			local /= Vector2(cluster.radius, cluster.radius * cluster.stretch)
			_check(local.length_squared() <= 1.0001, "Tree is outside its grove")
			_check(data.has_clearance(tree.position, tree.trunk_radius + config.shore_margin - 0.1),
				"Tree trunk is too close to the shore")
			var island := data.islands[tree.island_id]
			for bridge in data.bridges:
				var landing: Vector2
				if bridge.island_a == tree.island_id:
					landing = bridge.start
				elif bridge.island_b == tree.island_id:
					landing = bridge.finish
				else:
					continue
				var closest := Geometry2D.get_closest_point_to_segment(tree.position, island.center, landing)
				_check(tree.position.distance_to(closest) >= config.path_half_width + tree.trunk_radius - 0.1,
					"A trunk obstructs a reserved bridge route")
			for other in layout.trees:
				if other.id <= tree.id:
					continue
				_check(tree.position.distance_to(other.position) >= tree.trunk_radius
					+ other.trunk_radius + config.passage_width - 0.1, "No passage between trunks")
		if index < 3:
			var repeat := forest_generator.generate(data, config)
			_check(_fingerprint(layout) == _fingerprint(repeat), "Forest layout is not reproducible")
		if index == 0:
			var images: Dictionary = {}
			for i in mini(6, layout.trees.size()):
				var tree := layout.trees[i]
				var art := painter.paint(tree, style)
				var repeat := painter.paint(tree, style)
				_check(art.image.get_data() == repeat.image.get_data(), "Tree pixels are not reproducible")
				var grid_origin := (tree.position + art.local_rect.position) / art.pixel_size
				_check(grid_origin.is_equal_approx(grid_origin.round()), "Tree pixels are off the world grid")
				images[hash(art.image.get_data())] = true
			_check(images.size() >= 3, "Trees all have identical artwork")
	await _physics_check()
	if _failures.is_empty():
		print("PASS: %d forest checks; 12 seeds, groups, paths, unique trees and trunk collision." % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _physics_check() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	await physics_frame
	var player: NelvarPlayer = game.player
	_check(game.actors.y_sort_enabled, "Actors do not use Y-sort")
	var chosen: NelvarTree
	for node: NelvarTree in game.tree_nodes:
		_check(node.z_index == player.z_index, "Tree cannot sort against the player")
		var collider: CollisionShape2D = node.get_node("TrunkCollision")
		_check(collider.shape is CircleShape2D and collider.position == Vector2.ZERO,
			"Trunk collider is not a circle at the base")
		_check(is_equal_approx(collider.shape.radius, node.tree_data.trunk_radius), "Wrong trunk radius")
		if chosen == null and game.world_data.has_clearance(node.position,
			node.tree_data.trunk_radius + NelvarPlayer.BODY_RADIUS * 2.0 + 14.0):
			chosen = node
	_check(chosen != null, "No tree with enough surrounding ground for a walking test")
	if chosen == null:
		game.queue_free()
		return
	var center := chosen.position
	var contact := chosen.tree_data.trunk_radius + NelvarPlayer.BODY_RADIUS
	player.position = center - Vector2(contact + 38.0, 0)
	_press(Vector2.RIGHT)
	for frame in 30:
		await physics_frame
	_release()
	_check(player.position.x < center.x and player.position.distance_to(center) >= contact - 0.3,
		"Player passed through the trunk")
	_check(player.position.distance_to(center) < contact + 4.0, "Player did not reach the trunk")
	var radius := contact + 10.0
	player.position = center - Vector2(radius, 0)
	for i in range(1, 7):
		var target := center + Vector2.from_angle(PI + PI * float(i) / 6.0) * radius
		_check(await _walk_to(player, target), "Player cannot walk around the circular trunk")
	_release()
	_check(player.position.x > center.x + contact, "Player did not reach the opposite side of the tree")
	_check(game.forest_data.has_clearance(player.position, NelvarPlayer.BODY_RADIUS - 0.3),
		"Player ended inside a trunk")
	var key := InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	game._unhandled_input(key)
	_check(chosen.show_collision, "F3 does not show trunk collision circles")
	game.queue_free()
	await process_frame


func _walk_to(player: NelvarPlayer, target: Vector2) -> bool:
	for frame in 50:
		var offset := target - player.position
		if offset.length() < 4.0:
			_release()
			return true
		_press(offset.normalized())
		await physics_frame
	_release()
	return false


func _press(direction: Vector2) -> void:
	_release()
	if direction.x > 0:
		Input.action_press("move_right", direction.x)
	elif direction.x < 0:
		Input.action_press("move_left", -direction.x)
	if direction.y > 0:
		Input.action_press("move_down", direction.y)
	elif direction.y < 0:
		Input.action_press("move_up", -direction.y)


func _release() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)


func _fingerprint(layout: NelvarForestData) -> int:
	var parts: Array = []
	for tree in layout.trees:
		parts.append([tree.position, tree.cluster_id, tree.trunk_radius, tree.canopy_radius,
			tree.trunk_height, tree.form, tree.palette, tree.appearance_seed])
	return hash(parts)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition and _failures.size() < 20:
		_failures.append(message)
