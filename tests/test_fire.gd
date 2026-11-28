extends SceneTree
## The fire forge: layout rules (lava, crossings, roads, passages), reachability over
## the crossings, artwork, the ground map, the start setting, and the real scene: lava
## stops the walking player, the flight carries them over it, coming down in it burns
## and throws them back, hoppers blown into it burn, fissures erupt, salamanders dive,
## the wind blows the smoke away.
## Run: godot --headless --path . --script tests/test_fire.gd -- --seeds=30

const Kind = NelvarFireData.Kind

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var count := 30
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			count = maxi(1, argument.trim_prefix("--seeds=").to_int())
	var config := NelvarFireConfig.new()
	var generator := NelvarFireGenerator.new()
	var started := Time.get_ticks_msec()
	var reached := 0.0
	var streams := 0
	for index in count:
		var world_seed := 20261124 + index * 7919
		var data := generator.generate(config, world_seed)
		_check(data != null, "Seed %d: generation failed" % world_seed)
		if data == null:
			continue
		streams += data.streams.size()
		_check_layout(data, config)
		if index < 4:
			_check(_fingerprint(generator.generate(config, world_seed)) == _fingerprint(data),
				"Seed %d: layout is not reproducible" % world_seed)
		if index < 8:
			reached += _check_reachability(data)
		if index == 0:
			_check_art(data)
			_check_field(data)
	_check(streams >= count, "Only %d lava streams over %d forges" % [streams, count])
	print("Fire: %d seeds in %.2f s · %d streams · %.1f%% of open ground reachable" % [count,
		float(Time.get_ticks_msec() - started) / 1000.0, streams, reached / mini(count, 8) * 100.0])
	_check_settings()
	await _check_scene()
	if _failures.is_empty():
		print("PASS: %d checks; forge layout, crossings, art, lava, flight, eruptions and the scene behave" % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FAIL: %d failures / %d checks" % [_failures.size(), _checks])
		quit(1)


# --- Layout --------------------------------------------------------------------

func _check_layout(data: NelvarFireData, config: NelvarFireConfig) -> void:
	var context := "Seed %d: " % data.world_seed
	_check(data.boundary.size() == config.boundary_vertices, context + "the ridges' foot is not closed")
	_check(data.has_clearance(data.spawn_position, NelvarPlayer.BODY_RADIUS + 20.0), context + "the spawn is blocked")
	_check(data.lakes.size() >= config.lake_count.x and data.lakes.size() <= config.lake_count.y,
		context + "%d lava lakes" % data.lakes.size())
	_check(not data.volcano_angles.is_empty(), context + "no great volcano")
	for i in data.lakes.size():
		for point in data.lake_polygons[i]:
			_check(data.basin.signed_distance(point) > config.lake_margin * 0.5,
				context + "lake %d touches the ridges" % i)
	for island in data.islands:
		_check(data.lakes[island.lake].signed_distance(island.shape.center) > island.shape.reach(),
			context + "an island is not in its lake")
		_check(data.lava_depth(island.shape.center) < 0.0, context + "an island is lava")
	for stream in data.streams:
		var inside := 0.0
		var along := 0.0
		while along < stream.length():
			if data.basin.signed_distance(stream.point_at(along)) > 200.0:
				inside += 10.0
			along += 10.0
		if inside > config.crossing_spacing:
			_check(not stream.crossings.is_empty(), context + "a long stream has no crossing")
		for crossing in stream.crossings:
			_check(data.lava_depth(crossing.center) < -crossing.half_length * 0.5,
				context + "a crossing is lava")
			_check(data.lava_depth(crossing.center + crossing.direction * (crossing.half_length + 14.0)) > 0.0,
				context + "lava does not resume past a crossing")
			_check(data.is_open_ground(crossing.center, NelvarPlayer.BODY_RADIUS), context + "a crossing is blocked")
	for flow in data.flows:
		for point in flow.points:
			_check(data.lava_depth(point) < -flow.half_width * 0.5, context + "a road runs into the lava")
	for clearing in data.clearings:
		_check(data.has_clearance(clearing.center, NelvarPlayer.BODY_RADIUS), context + "a clearing is blocked")
	_check(data.fissures.size() >= config.fissures.x, context + "too few fissures")
	var active := 0
	for fissure in data.fissures:
		if fissure.active:
			active += 1
		for point in fissure.points:
			_check(data.lava_depth(point) < -60.0, context + "a fissure runs into the lava")
	_check(active > 0 or data.fissures.size() < 3, context + "no fissure erupts")
	_check(not data.smoke_banks.is_empty(), context + "no smoke banks")
	var species := {}
	var solids: Array[NelvarFireData.Thing] = []
	for thing in data.things:
		if thing.kind == Kind.TREE:
			species[thing.variant] = true
		_check(data.basin.signed_distance(thing.position) > thing.spread(),
			context + "%s %d stands in the ridges" % [Kind.keys()[thing.kind], thing.id])
		_check(data.lava_depth(thing.position) < -thing.spread() * 0.5,
			context + "%s %d stands in the lava" % [Kind.keys()[thing.kind], thing.id])
		_check(not data.on_island(thing.position), context + "something stands on an island")
		if thing.solid:
			solids.append(thing)
			_check(data.distance_to_flows(thing.position) >= thing.spread() - 0.5,
				context + "%s %d blocks a road" % [Kind.keys()[thing.kind], thing.id])
			_check(thing.position.distance_to(data.spawn_position) >= config.spawn_clearance,
				context + "something solid stands at the spawn")
	_check(species.size() >= 3, context + "only %d kinds of trees" % species.size())
	_check(data.count(Kind.TREE) >= 25, context + "only %d trees" % data.count(Kind.TREE))
	_check(data.count(Kind.ROCK) >= 25, context + "only %d rocks" % data.count(Kind.ROCK))
	_check(data.count(Kind.VENT) >= 2, context + "too few vents")
	for a in solids.size():
		for b in range(a + 1, solids.size()):
			var first := solids[a]
			var second := solids[b]
			var distance := first.position.distance_to(second.position)
			if distance > 400.0:
				continue
			_check(distance >= first.spread() + second.spread() + NelvarPlayer.BODY_RADIUS * 2.0,
				context + "no passage between %s %d and %s %d" % [Kind.keys()[first.kind], first.id,
					Kind.keys()[second.kind], second.id])
	var angles: Array[float] = []
	for peak in data.peaks:
		if peak.row == 0:
			var angle := (peak.position - data.basin.center).angle()
			angles.append(angle)
			# A great volcano covers a wide stretch of the ring by itself.
			if peak.size.x >= NelvarVolcanoPainter.GREAT_WIDTH:
				var half := peak.size.x * 0.3 / data.basin.radius_at(angle)
				angles.append(wrapf(angle - half, -PI, PI))
				angles.append(wrapf(angle + half, -PI, PI))
	angles.sort()
	var widest := TAU - (angles[angles.size() - 1] - angles[0])
	for i in angles.size() - 1:
		widest = maxf(widest, angles[i + 1] - angles[i])
	_check(widest < 0.3, context + "a gap of %.2f rad in the ridges" % widest)


## Share of open ground (where the player fits) reachable on foot from the spawn: the
## lava splits the basin only where crossings join it again.
func _check_reachability(data: NelvarFireData) -> float:
	const CELL := 24.0
	var bounds := Rect2(data.boundary[0], Vector2.ZERO)
	for point in data.boundary:
		bounds = bounds.expand(point)
	var origin := bounds.position
	var size := Vector2i((bounds.size / CELL).ceil()) + Vector2i.ONE
	var open := PackedByteArray()
	open.resize(size.x * size.y)
	var total := 0
	for y in size.y:
		for x in size.x:
			if data.has_clearance(origin + Vector2(x + 0.5, y + 0.5) * CELL, NelvarPlayer.BODY_RADIUS):
				open[y * size.x + x] = 1
				total += 1
	var start := Vector2i(((data.spawn_position - origin) / CELL).floor())
	var queue: Array[Vector2i] = [start]
	var seen := {start: true}
	var i := 0
	while i < queue.size():
		var cell := queue[i]
		i += 1
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + step
			if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y or seen.has(next):
				continue
			if open[next.y * size.x + next.x] == 1:
				seen[next] = true
				queue.append(next)
	var share := float(queue.size()) / maxf(1.0, total)
	_check(share > 0.96, "Seed %d: only %.1f%% of open ground is reachable" % [data.world_seed, share * 100.0])
	return share


func _fingerprint(data: NelvarFireData) -> int:
	var parts: Array = [data.spawn_position, data.boundary, data.flows.size(), data.streams.size()]
	for stream in data.streams:
		parts.append([stream.points, stream.crossings.size()])
	for thing in data.things:
		parts.append([thing.kind, thing.variant, thing.position, thing.radius, thing.size, thing.accent,
			thing.appearance_seed])
	for peak in data.peaks:
		parts.append([peak.variant, peak.position, peak.size, peak.accent])
	return hash(parts)


# --- Art and the ground map ---------------------------------------------------------

func _check_art(data: NelvarFireData) -> void:
	var painter := NelvarFirePainter.new()
	var seen := {}
	var images := {}
	for thing in data.things:
		var key := "%d:%d" % [thing.kind, thing.variant]
		if seen.get(key, 0) >= 2:
			continue
		seen[key] = seen.get(key, 0) + 1
		var art := painter.paint(thing)
		var name: String = Kind.keys()[thing.kind]
		_check(art != null and art.image != null and not art.image.is_invisible(), name + " has no art")
		if art == null:
			continue
		_check(art.image.get_data() == painter.paint(thing).image.get_data(), name + " art is not reproducible")
		var grid: Vector2 = (thing.position + art.local_rect.position) / NelvarFireData.PIXEL
		_check(grid.is_equal_approx(grid.round()), name + " art is off the world grid")
		images[hash(art.image.get_data())] = true
		if thing.kind == Kind.VENT:
			_check(art.vent.is_finite(), "A vent has no mouth for its smoke")
	_check(images.size() == seen.values().reduce(func(a: int, b: int) -> int: return a + b, 0),
		"Two things share identical art")
	for species in NelvarFireData.Species.size():
		var tree := NelvarFireData.Thing.new()
		tree.kind = Kind.TREE
		tree.variant = species
		tree.radius = 14.0
		tree.size = Vector2(44.0, 170.0)
		tree.appearance_seed = 77 + species
		_check(not painter.paint(tree).image.is_invisible(), "Species %d has no art" % species)
	# Volcanoes: a crater with a vent; a great one is molten with lava keyed for the shader.
	var volcano_painter := NelvarVolcanoPainter.new()
	var great := 0
	for peak in data.peaks:
		if peak.variant != NelvarEarthData.Peak.GIANT or peak.size.x < NelvarVolcanoPainter.GREAT_WIDTH:
			continue
		var art: NelvarFireArt = volcano_painter.paint(peak)
		great += 1
		_check(art.vent.is_finite(), "A volcano has no crater")
		var keyed := 0
		for y in art.image.get_height():
			for x in art.image.get_width():
				if roundi(art.image.get_pixel(x, y).a * 255.0) == NelvarFireArt.FLOW_KEY:
					keyed += 1
		_check(keyed > 20, "A great volcano has no lava running down it")
		_check(art.image.get_data() == volcano_painter.paint(peak).image.get_data(), "Volcano art is not reproducible")
		break
	_check(great > 0, "No great volcano to paint")


func _check_field(data: NelvarFireData) -> void:
	var field := NelvarFireField.build(data)
	var at := func(point: Vector2, channel: int) -> int:
		var p := Vector2i((point / NelvarFireData.PIXEL).floor()) - field.origin
		return field.data[(p.y * field.size.x + p.x) * 4 + channel]
	for lake in data.lakes:
		_check(at.call(lake.point_at(0.3, 40.0), 0) > 135, "The ground map has no lava in a lake")
		_check(at.call(lake.point_at(0.3, -60.0), 0) < 128, "The ground map spills a lake on its shore")
	for island in data.islands:
		_check(at.call(island.shape.center, 0) < 128, "The ground map floods an island")
		_check(at.call(island.shape.center, 3) == NelvarFireField.PLATES, "An island has no plates")
	for stream in data.streams:
		for crossing in stream.crossings:
			_check(at.call(crossing.center, 0) < 128, "The ground map floods a crossing")
		var middle := stream.point_at(stream.length() * 0.5)
		if data.lava_depth(middle) > 8.0:
			_check(at.call(middle, 0) > 130 and at.call(middle, 1) < 255, "A stream has no flowing lava")
	for flow in data.flows:
		var middle := flow.points[flow.points.size() / 2]
		_check(at.call(middle, 1) < 20, "The ground map misses a road")
	for fissure in data.fissures:
		_check(at.call(fissure.points[1], 2) < 16, "The ground map misses a fissure")
	var lit := 0
	for value in field.glow.size() / 4:
		if field.glow[value * 4] > 200:
			lit += 1
	_check(lit > 20, "The light map is dark")


# --- The start setting -------------------------------------------------------------

## The start options exclude each other. The saved settings are put back as they were.
func _check_settings() -> void:
	var settings: Node = root.get_node("GameSettings")
	var path: String = settings.PATH
	var saved := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	var was := [settings.start_in_void, settings.start_on_earth, settings.start_in_fire, settings.start_on_ice,
		settings.start_in_fire2, settings.start_on_ice2, settings.start_on_earth2, settings.start_in_air]
	settings.set_start_on_earth(true)
	settings.set_start_in_fire(true)
	_check(settings.start_in_fire and not settings.start_on_earth and not settings.start_in_void,
		"The fire did not replace the earth at start")
	settings.set_start_in_void(true)
	_check(settings.start_in_void and not settings.start_in_fire, "The Void did not replace the fire at start")
	settings.set_start_in_fire(true)
	_check(settings.start_in_fire and not settings.start_in_void, "The fire did not replace the Void at start")
	settings.set_start_on_ice(true)
	_check(settings.start_on_ice and not settings.start_in_fire and not settings.start_on_earth
		and not settings.start_in_void, "The ice did not replace the fire at start")
	settings.set_start_on_earth(true)
	_check(settings.start_on_earth and not settings.start_on_ice, "Earth did not replace the ice at start")
	settings.set_start_in_fire2(true)
	_check(settings.start_in_fire2 and not settings.start_on_earth and not settings.start_in_fire,
		"The volcano did not replace the earth at start")
	settings.set_start_in_fire(true)
	_check(settings.start_in_fire and not settings.start_in_fire2, "The forge did not replace the volcano at start")
	settings.set_start_on_ice2(true)
	_check(settings.start_on_ice2 and not settings.start_in_fire, "The ice cave did not replace the forge at start")
	settings.set_start_in_fire(true)
	_check(settings.start_in_fire and not settings.start_on_ice2, "The forge did not replace the ice cave at start")
	settings.set_start_on_earth2(true)
	_check(settings.start_on_earth2 and not settings.start_in_fire, "The giant forest did not replace the forge at start")
	settings.set_start_in_fire(true)
	_check(settings.start_in_fire and not settings.start_on_earth2, "The forge did not replace the giant forest at start")
	settings.set_start_in_air(true)
	_check(settings.start_in_air and not settings.start_in_fire, "The air did not replace the forge at start")
	settings.set_start_in_fire(true)
	_check(settings.start_in_fire and not settings.start_in_air, "The forge did not replace the air at start")
	settings.start_in_void = was[0]
	settings.start_on_earth = was[1]
	settings.start_in_fire = was[2]
	settings.start_on_ice = was[3]
	settings.start_in_fire2 = was[4]
	settings.start_on_ice2 = was[5]
	settings.start_on_earth2 = was[6]
	settings.start_in_air = was[7]
	if saved.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	var menu := FileAccess.get_file_as_string("res://ui/main_menu/main_menu.gd")
	_check(menu.contains("res://scenes/fire.tscn") and menu.contains("GameSettings.start_in_fire"),
		"«Играть» does not open the forge")
	var panel: Node = load("res://ui/main_menu/settings_panel.tscn").instantiate()
	_check(panel.get_node_or_null("Rows/Body/PageColumn/Scroll/Pages/DevPage/StartInFire") is CheckButton, "The developer menu has no fire start")
	_check(panel.get_node_or_null("Rows/Body/PageColumn/Scroll/Pages/DevPage/StartOnIce") is CheckButton, "The developer menu has no ice start")
	_check(menu.contains("res://scenes/ice.tscn") and menu.contains("GameSettings.start_on_ice"),
		"«Играть» does not open the ice valley")
	panel.free()


# --- The scene ---------------------------------------------------------------------

func _check_scene() -> void:
	var game = load("res://scenes/fire.tscn").instantiate()
	game.set_meta("seed_override", _scene_seed())
	root.add_child(game)
	game.finish_painting()
	await physics_frame
	await physics_frame
	var data: NelvarFireData = game.data
	var player: NelvarPlayer = game.player
	for enemy in get_nodes_in_group("enemies"):
		_check(data.has_clearance(enemy.global_position, 20.0), "An enemy appeared in a wall or the lava")
		enemy.queue_free()
	game.enemy_spawner.set_process(false)
	await physics_frame
	_check(player.collision_mask & NelvarFireData.LAVA_LAYER != 0, "The walking player does not collide with lava")
	_check(game.peak_nodes.size() == data.peaks.size(), "Some ridges are missing")
	_check(game.thing_nodes.size() == data.things.size(), "Some things are missing")
	# A lake stops the walking player; walking along it does not burn them.
	var lake := data.lakes[0]
	var shore := lake.point_at(PI * 0.5, -46.0)
	player.position = shore
	player.velocity = Vector2.ZERO
	var burns: int = game.burns
	await _hold(Vector2.UP, 50)
	_check(data.lava_depth(player.position) < -NelvarPlayer.BODY_RADIUS + 3.0, "The player walked into the lava")
	_check(game.burns == burns, "Walking up to the lava burnt the player")
	# The flight carries the player over the lava and off its far side.
	player.health = player.max_health
	var start := lake.point_at(PI * 0.5, -40.0)
	var across := lake.point_at(-PI * 0.5, -60.0)
	player.position = start
	player.velocity = Vector2.ZERO
	player.call("_try_speed_boost")
	await physics_frame
	_check(player.collision_mask & NelvarFireData.LAVA_LAYER == 0, "The flying player still collides with lava")
	player.speed_boost_duration = 10.0
	var frames := 0
	Input.action_press("move_up")
	while player.position.y > across.y and frames < 400:
		await physics_frame
		frames += 1
	Input.action_release("move_up")
	_check(player.position.y <= across.y + 4.0, "The flight did not carry the player over a lake")
	_check(game.burns == burns, "Flying over the lava burnt the player")
	player.call("_land")
	player.speed_boost_duration = 2.0
	await physics_frame
	# Coming down in the lava burns and throws the player back on safe ground.
	var safe := lake.point_at(0.0, -120.0)
	player.position = safe
	for i in 6:
		await physics_frame
	player.health = player.max_health
	player.position = lake.center + (lake.point_at(0.0, 30.0) - lake.center) * 0.3
	if data.lava_depth(player.position) < 10.0:
		player.position = lake.point_at(0.0, 30.0)
	await create_timer(1.2).timeout
	_check(game.burns == burns + 1, "Coming down in the lava did not burn the player")
	_check(player.health < player.max_health, "The lava did no damage")
	_check(data.lava_depth(player.global_position) < -NelvarPlayer.BODY_RADIUS,
		"The player was not thrown back on safe ground")
	_check(not player.is_falling(), "The player did not come back from the lava")
	# Streams stop the walking player between crossings and let them over a crossing.
	for stream in data.streams:
		if stream.crossings.is_empty():
			continue
		var crossing := stream.crossings[0]
		var side := crossing.direction.orthogonal()
		player.position = crossing.center + side * (stream.half_width + 50.0)
		player.velocity = Vector2.ZERO
		player.health = player.max_health
		await physics_frame
		var target := crossing.center - side * (stream.half_width + 40.0)
		await _walk_to(player, target, 120)
		_check(player.position.distance_to(target) < 30.0, "The player could not walk over a crossing")
		var beside := stream.point_at(clampf(crossing.along + crossing.half_length + stream.half_width + 60.0,
			0.0, stream.length()))
		if data.has_clearance(beside + side * (stream.half_width + 50.0), NelvarPlayer.BODY_RADIUS):
			player.position = beside + side * (stream.half_width + 50.0)
			player.velocity = Vector2.ZERO
			await _walk_to(player, beside - side * (stream.half_width + 50.0), 80)
			_check(data.lava_depth(player.position) < 0.0 and player.position.distance_to(beside
				+ side * (stream.half_width + 50.0)) < stream.half_width + 60.0, "A stream did not stop the player")
		break
	# A hopper blown into the lava burns.
	var hopper: Node2D = game.enemy_spawner.enemy_scene.instantiate()
	hopper.position = lake.point_at(-PI * 0.5, -40.0)
	game.enemy_spawner.add_child(hopper)
	await physics_frame
	hopper.call("apply_knockback", (lake.center - hopper.position).normalized() * 900.0)
	await create_timer(0.8).timeout
	_check(not is_instance_valid(hopper) or hopper.call("is_dead"), "A hopper blown into the lava did not burn")
	# Hoppers on the forge do not jump into the lava themselves.
	var landing: Variant = game.enemy_spawner.call("_pick_spawn_point")
	if landing != null:
		game.enemy_spawner.call("_try_spawn")
		await physics_frame
		for enemy in get_nodes_in_group("enemies"):
			_check(enemy.get("ground") == data, "A hopper does not know the forge's lava")
	# Active fissures erupt and the burst hurts whoever stands on the crack.
	var active: NelvarFireData.Fissure = null
	var active_index := -1
	for i in data.fissures.size():
		if data.fissures[i].active:
			active = data.fissures[i]
			active_index = i
			break
	if active != null:
		player.position = active.points[active.points.size() / 2]
		player.velocity = Vector2.ZERO
		player.health = player.max_health
		player.set("_invulnerability_left", 0.0)
		var eruptions: int = game.eruptions
		var waited := 0.0
		while game.get("_fissure_state")[active_index] != 2 and waited < active.period + 1.0:
			await physics_frame
			player.position = active.points[active.points.size() / 2]
			waited += 1.0 / 60.0
		await physics_frame
		_check(game.eruptions > eruptions, "An active fissure did not erupt")
		_check(player.health < player.max_health, "An eruption did not hurt the player on the crack")
	# Salamanders dive into the lava when the player comes near.
	var critters: NelvarFireCritters = game.critters
	var basking: Variant = null
	for lizard in critters.get("_lizards"):
		if lizard.state == NelvarFireCritters.State.BASK:
			basking = lizard
			break
	if basking != null:
		var dives := critters.dives
		player.position = basking.position + Vector2(60.0, 0.0)
		player.velocity = Vector2.ZERO
		await create_timer(1.8).timeout
		_check(critters.dives > dives, "A salamander did not dive from the player")
	# The wind blows a smoke bank thin.
	var smoke: NelvarSmoke = game.smoke
	if not data.smoke_banks.is_empty():
		var bank := data.smoke_banks[0]
		var before := smoke.bank_density(0)
		var center := Vector2(bank.x, bank.y)
		for i in 24:
			smoke.gusts = [[center + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * bank.z * 0.6,
				Vector2(700, 0), 90.0]]
			smoke.call("_process", 0.05)
		smoke.gusts = []
		_check(smoke.bank_density(0) < before, "The wind did not thin a smoke bank")
	# Sparks and ash fly; F3 shows the walls.
	_check(game.embers.get("_motes").size() > 0, "No ash or sparks in the air")
	var key := InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	game._unhandled_input(key)
	_check(game.get("_outlines").visible, "F3 does not show the walls")
	game.queue_free()
	await process_frame


## A seed whose forge has a stream with a crossing and an active fissure.
func _scene_seed() -> int:
	var generator := NelvarFireGenerator.new()
	for i in 40:
		var world_seed := 20261124 + i * 104729
		var data := generator.generate(NelvarFireConfig.new(), world_seed)
		if data == null:
			continue
		var crossing := false
		for stream in data.streams:
			if not stream.crossings.is_empty():
				crossing = true
		var active := false
		for fissure in data.fissures:
			active = active or fissure.active
		if crossing and active:
			return world_seed
	return 20261124


func _walk_to(player: NelvarPlayer, target: Vector2, frames: int) -> void:
	for frame in frames:
		var offset := target - player.position
		if offset.length() < 8.0:
			break
		for name: String in ["move_left", "move_right", "move_up", "move_down"]:
			Input.action_release(name)
		if offset.x < -4.0:
			Input.action_press("move_left")
		elif offset.x > 4.0:
			Input.action_press("move_right")
		if offset.y < -4.0:
			Input.action_press("move_up")
		elif offset.y > 4.0:
			Input.action_press("move_down")
		await physics_frame
	for name: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(name)


func _hold(direction: Vector2, frames: int) -> void:
	var action := "move_right"
	if direction == Vector2.LEFT:
		action = "move_left"
	elif direction == Vector2.UP:
		action = "move_up"
	elif direction == Vector2.DOWN:
		action = "move_down"
	Input.action_press(action)
	for frame in frames:
		await physics_frame
	for name: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(name)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition and _failures.size() < 30:
		_failures.append(message)
