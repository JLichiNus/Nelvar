extends SceneTree
## The volcano (Огонь 2): layout rules (the rim, the capes, the rings of islands that never
## collide and always come within a run of something, geysers and things on the rock,
## the front slope's table), the ground and light maps, the islands' masks, the start
## setting, and the real scene: a step into the lava or off the edge is a fall that
## throws the player back hurt, a narrow gap to an island is crossed at a run, an island
## carries the player exactly as far as it moves, a raft sinks under them, geysers throw
## them, splashes burn, hoppers die in the lava, off the edge and on a sinking island.
## Run: godot --headless --path . --script tests/test_crater.gd -- --seeds=30

const Kind = NelvarFireData.Kind
const IsleKind = NelvarCraterData.IsleKind
const STEP := NelvarFireData.PIXEL

var _failures: Array[String] = []
var _checks := 0
## NelvarCraterMain's constants (read from the scene's script: compiling against it here
## would need the autoloads).
var _rules := {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var count := 30
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			count = maxi(1, argument.trim_prefix("--seeds=").to_int())
	var config := NelvarCraterConfig.new()
	var generator := NelvarCraterGenerator.new()
	var started := Time.get_ticks_msec()
	var isles := 0
	for index in count:
		var world_seed := 20261125 + index * 7919
		var data := generator.generate(config, world_seed)
		_check(data != null, "Seed %d: generation failed" % world_seed)
		if data == null:
			continue
		isles += data.isles.size()
		_check_layout(data, config)
		_check_islands(data, config)
		if index < 4:
			_check(_fingerprint(generator.generate(config, world_seed)) == _fingerprint(data),
				"Seed %d: layout is not reproducible" % world_seed)
		if index == 0:
			_check_field(data)
			_check_art(data)
	print("Volcano: %d seeds in %.2f s · %.1f islands each" % [count,
		float(Time.get_ticks_msec() - started) / 1000.0, float(isles) / count])
	_check_settings()
	await _check_scene()
	if _failures.is_empty():
		print("PASS: %d checks; volcano layout, islands, maps, art, falls, rides, geysers, splashes and the scene behave" % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FAIL: %d failures / %d checks" % [_failures.size(), _checks])
		quit(1)


# --- Layout --------------------------------------------------------------------

func _check_layout(data: NelvarCraterData, config: NelvarCraterConfig) -> void:
	var context := "Seed %d: " % data.world_seed
	var narrowest := INF
	for i in 720:
		narrowest = minf(narrowest, data.rim_width_at(TAU * i / 720.0))
	_check(narrowest >= config.rim_min - 1.0, context + "the rim narrows to %.0f" % narrowest)
	_check(data.terraces.size() >= config.terraces.x, context + "%d terraces" % data.terraces.size())
	_check(data.capes.size() >= config.capes.x, context + "%d capes" % data.capes.size())
	_check(data.count_isles(IsleKind.ANCHOR) >= config.anchors.x, context + "too few anchors")
	_check(data.count_isles(IsleKind.PLATE) >= 5, context + "%d plates" % data.count_isles(IsleKind.PLATE))
	_check(data.count_isles(IsleKind.RAFT) >= 4, context + "%d rafts" % data.count_isles(IsleKind.RAFT))
	_check(data.geysers.size() >= config.geysers.x - 1, context + "%d geysers" % data.geysers.size())
	_check(data.boils.size() >= 2, context + "too few boiling patches")
	_check(not data.smoke_banks.is_empty(), context + "no smoke banks")
	# The spawn: on the southern terrace, free, near the lake.
	_check(data.has_clearance(data.spawn_position, NelvarPlayer.BODY_RADIUS + 20.0), context + "the spawn is blocked")
	_check(data.spawn_position.y > data.vent.y + 600.0, context + "the spawn is not in the south")
	_check(data.lava_depth(data.spawn_position) > -320.0, context + "the spawn is far from the lake")
	# Capes reach for the outer ring, and they are capes, not peninsulas.
	var tip_reach := data.rings[data.rings.size() - 1].y + config.ring_gap
	for cape in data.capes:
		_check(absf(data.vent.distance_to(cape.apex()) - tip_reach) < 1.0, context + "a cape's tip is off the outer ring")
		var length := data.lake.radius_at(cape.angle) - data.vent.distance_to(cape.apex())
		_check(length >= config.cape_min_length - 1.0 and length < 520.0, context + "a cape is %.0f long" % length)
		_check(data.lava_depth(cape.apex() - cape.base.direction_to(cape.tip) * 10.0) < 0.0, context + "a cape's tip is lava")
	# Geysers and things stand on rock, out of the lava and off the edge.
	var at_capes := 0
	for geyser in data.geysers:
		_check(data.rim_depth(geyser.position) > geyser.radius + 10.0 and data.lava_depth(geyser.position) < -(geyser.radius + 10.0),
			context + "a geyser is not on rock")
		_check(geyser.position.distance_to(data.spawn_position) >= config.geyser_spacing - 1.0, context + "a geyser at the spawn")
		if geyser.cape >= 0:
			at_capes += 1
	_check(at_capes >= mini(config.cape_geysers, data.capes.size()) - 1, context + "no geysers at the capes")
	for i in data.geysers.size():
		for j in range(i + 1, data.geysers.size()):
			_check(data.geysers[i].position.distance_to(data.geysers[j].position) >= config.geyser_spacing - 1.0,
				context + "two geysers too close")
	var solids: Array[NelvarFireData.Thing] = []
	var trees := 0
	for thing in data.things:
		var name: String = Kind.keys()[thing.kind]
		_check(data.rim_depth(thing.position) > thing.spread() * 0.5, context + "%s %d hangs off the edge" % [name, thing.id])
		_check(data.lava_depth(thing.position) < -thing.spread() * 0.5, context + "%s %d stands in the lava" % [name, thing.id])
		if thing.kind == Kind.TREE:
			trees += 1
		if thing.solid:
			solids.append(thing)
			_check(data.distance_to_flows(thing.position) >= thing.spread() - 0.5,
				context + "%s %d blocks a road" % [name, thing.id])
			_check(thing.position.distance_to(data.spawn_position) >= config.spawn_clearance,
				context + "something solid stands at the spawn")
	_check(trees <= config.trees.y, context + "too many trees on a volcano's top")
	_check(data.count(Kind.ROCK) >= 12, context + "only %d rocks" % data.count(Kind.ROCK))
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
	# The ring road goes all the way round on rock: the way round is never blocked.
	var ring := data.flows[0]
	_check(ring.points[0].is_equal_approx(ring.points[ring.points.size() - 1]), context + "the ring road is not closed")
	for flow in data.flows:
		for point in flow.points:
			_check(data.lava_depth(point) < -flow.half_width * 0.5 and data.rim_depth(point) > flow.half_width,
				context + "a road leaves the rock")
	# The front slope's table follows the summit's south edge.
	var field := NelvarCraterField.new()
	field.call("_slope", data)
	var checked := 0
	for c in range(0, field.slope.size(), 7):
		var top := field.slope[c]
		if top < 0.0:
			continue
		var x := (field.slope_origin + c + 0.5) * STEP
		checked += 1
		_check(data.rim_depth(Vector2(x, (top - 1.5) * STEP)) > -3.0 and data.rim_depth(Vector2(x, (top + 1.5) * STEP)) < 3.0,
			context + "the slope's table misses the edge at column %d" % c)
	_check(checked > 50, context + "the slope's table is empty")


## Over a full turn: islands never touch each other, a cape, an anchor or the shore, and
## every floating one comes within a run of something.
func _check_islands(data: NelvarCraterData, config: NelvarCraterConfig) -> void:
	var context := "Seed %d: " % data.world_seed
	var moving := data.moving_isles()
	for isle in data.isles:
		_check(data.lava_depth(isle.position_at(0.0)) < 0.0 or isle.moving(), context + "an anchor is lava")
		if isle.moving():
			_check(isle.orbit - isle.outer >= config.vent_clearance - 1.0, context + "an island comes near the vent")
	for anchor in data.anchors():
		_check(data.vent.distance_to(anchor.center) - anchor.outer >= config.vent_clearance - 1.0,
			context + "an anchor stands in the vent")
	var closest := {}
	for a in moving:
		closest[a] = INF
	for i in moving.size():
		var a := moving[i]
		for j in range(i + 1, moving.size()):
			var b := moving[j]
			var period := TAU / maxf(absf(a.speed - b.speed), 0.0001) if a.ring != b.ring else 1.0
			var gap := INF
			for s in 240:
				gap = minf(gap, NelvarCraterData.isle_gap(a, b, period * s / 240.0))
			_check(gap >= NelvarCraterData.MIN_GAP - 0.5, context + "islands %d and %d touch (%.1f)" % [a.id, b.id, gap])
			closest[a] = minf(closest[a], gap)
			closest[b] = minf(closest[b], gap)
		var turn := TAU / absf(a.speed)
		for anchor in data.anchors():
			var gap := INF
			for s in 240:
				gap = minf(gap, NelvarCraterData.isle_gap(a, anchor, turn * s / 240.0))
			_check(gap >= NelvarCraterData.MIN_GAP - 0.5, context + "island %d touches an anchor" % a.id)
			closest[a] = minf(closest[a], gap)
		for cape in data.capes:
			var gap := INF
			for s in 240:
				gap = minf(gap, NelvarCraterData.cape_gap(a, cape, turn * s / 240.0))
			_check(gap >= NelvarCraterData.MIN_GAP - 0.5, context + "island %d touches a cape" % a.id)
			closest[a] = minf(closest[a], gap)
		# The shore: every point of its outline stays in open lava all the way round.
		for s in 48:
			var time := turn * s / 48.0
			var at := a.position_at(time)
			for k in 12:
				var angle := TAU * k / 12.0
				var point := at + Vector2.from_angle(angle) * a.shape.radius_at(angle)
				if data.lava_depth(point) <= 0.0:
					_check(false, context + "island %d runs aground" % a.id)
					break
	for a in moving:
		_check(closest[a] <= NelvarCraterData.RUN_GAP, context + "island %d never comes within a run (%.0f)" % [a.id, closest[a]])


func _fingerprint(data: NelvarCraterData) -> int:
	var parts: Array = [data.spawn_position, data.summit.radii, data.flows.size(), data.capes.size()]
	for isle in data.isles:
		parts.append([isle.kind, isle.center, isle.orbit, isle.phase, isle.speed, isle.shape.axes, isle.sink_period])
	for geyser in data.geysers:
		parts.append([geyser.position, geyser.period, geyser.phase])
	for thing in data.things:
		parts.append([thing.kind, thing.variant, thing.position, thing.radius, thing.appearance_seed])
	return hash(parts)


# --- Maps and art ----------------------------------------------------------------------

func _check_field(data: NelvarCraterData) -> void:
	var field := NelvarCraterField.build_crater(data)
	_check(field.edge == data.summit.radii, "The edge table differs from the summit's profile")
	var light := func(point: Vector2) -> Vector3:
		var cell := Vector2i(((point / STEP - Vector2(field.glow_origin)) / NelvarFireField.GLOW_SCALE).floor())
		var index := (cell.y * field.glow_size.x + cell.x) * 4
		return Vector3(field.glow[index], field.glow[index + 1], field.glow[index + 2]) / 255.0
	# Strong along the shores and over the vent, moderate over the open lake.
	var shore := data.vent + Vector2.UP * (data.lake.radius_at(-PI * 0.5) - 40.0)
	if data.lava_depth(shore) > 20.0:
		_check(light.call(shore).x > 0.8, "The shore is not lit")
	_check(light.call(data.vent).x > 0.9, "The vent is not lit")
	var open := Vector2.INF
	for i in 64:
		var angle := TAU * i / 64.0
		var point := data.vent + Vector2.from_angle(angle) * (data.rings[1].x + data.rings[1].y) * 0.5
		var clear := data.lava_depth(point) > 300.0
		for boil in data.boils:
			clear = clear and point.distance_to(Vector2(boil.x, boil.y)) > boil.z + 260.0
		if clear:
			open = point
			break
	if open.is_finite():
		var lit: Vector3 = light.call(open)
		_check(lit.x > 0.3 and lit.x < 0.7, "The open lake's light is %.2f" % lit.x)
		_check(lit.z < 0.05, "The air shimmers over the open lake")
	_check(light.call(data.vent).z > 0.9, "No haze over the vent")
	for bank in data.smoke_banks:
		_check(light.call(Vector2(bank.x, bank.y)).z > 0.5, "No haze over a smoke bank")
	# The light stops at the edge.
	var beyond := data.vent + Vector2.UP * (data.summit.radius_at(-PI * 0.5) + 200.0)
	_check(light.call(beyond).x < 0.02, "The clouds below are lit by the lake")
	# Sulfur round each geyser, roads on the map.
	for geyser in data.geysers:
		var p := Vector2i((geyser.position / STEP).floor()) - field.origin
		_check(field.data[(p.y * field.size.x + p.x) * 4 + 3] > 0, "No sulfur round a geyser")
	var middle := data.flows[0].points[40]
	var q := Vector2i((middle / STEP).floor()) - field.origin
	_check(field.data[(q.y * field.size.x + q.x) * 4 + 1] < 20, "The ground map misses the ring road")


func _check_art(data: NelvarCraterData) -> void:
	for isle in data.moving_isles():
		var mask := NelvarCraterIsland.bake_mask(isle)
		var inside := 0
		var core := 0
		var faces := 0
		for y in mask.get_height():
			for x in mask.get_width():
				var pixel := mask.get_pixel(x, y)
				if pixel.a > 0.5:
					inside += 1
					if pixel.r > 0.75:
						core += 1
					if roundi(pixel.g * 255.0) == 1:
						faces += 1
		var expected := PI * pow(isle.inner / STEP, 2.0)
		_check(inside > expected * 0.9, "Island %d's mask is too small" % isle.id)
		_check(core > 0 and faces > 4, "Island %d's mask has no core or no south face" % isle.id)
	var painter := NelvarFirePainter.new()
	var seen := {}
	for thing in data.things:
		if seen.has(thing.kind):
			continue
		seen[thing.kind] = true
		var art := painter.paint(thing)
		_check(art != null and not art.image.is_invisible(), "%s has no art" % Kind.keys()[thing.kind])
	# Shaders compile (a broken one would print errors; it also must load).
	for path in ["res://scripts/crater/crater_ground.gdshader", "res://scripts/crater/crater_below.gdshader",
			"res://scripts/crater/crater_island.gdshader", "res://scripts/crater/lava_splashes.gdshader"]:
		_check(load(path) is Shader, path + " does not load")


# --- The start setting -------------------------------------------------------------

## The five start options exclude each other. The saved settings are put back as they were.
func _check_settings() -> void:
	var settings: Node = root.get_node("GameSettings")
	var path: String = settings.PATH
	var saved := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	var was := [settings.start_in_void, settings.start_on_earth, settings.start_in_fire, settings.start_on_ice,
		settings.start_in_fire2]
	var setters := ["set_start_in_void", "set_start_on_earth", "set_start_in_fire", "set_start_on_ice",
		"set_start_in_fire2"]
	var flags := ["start_in_void", "start_on_earth", "start_in_fire", "start_on_ice", "start_in_fire2"]
	for i in setters.size():
		settings.call(setters[i], true)
		for j in flags.size():
			_check(bool(settings.get(flags[j])) == (i == j), "Start options %s and %s do not exclude each other" % [flags[i], flags[j]])
	settings.set_start_in_fire2(true)
	settings.set_start_in_fire2(false)
	for flag in flags:
		_check(not settings.get(flag), "Turning Fire 2 off left %s on" % flag)
	for i in flags.size():
		settings.set(flags[i], was[i])
	if saved.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	var menu := FileAccess.get_file_as_string("res://ui/main_menu/main_menu.gd")
	_check(menu.contains("res://scenes/fire2.tscn") and menu.contains("GameSettings.start_in_fire2"),
		"«Играть» does not open the volcano")
	var panel: Node = load("res://ui/main_menu/dev_panel.tscn").instantiate()
	var check: Node = panel.get_node_or_null("Rows/StartInFire2")
	_check(check is CheckButton and (check as CheckButton).text == "Запускать игру в Огне 2",
		"The developer menu has no Fire 2 start")
	panel.free()


# --- The scene ---------------------------------------------------------------------

func _check_scene() -> void:
	var game = load("res://scenes/fire2.tscn").instantiate()
	game.set_meta("seed_override", 20261125)
	root.add_child(game)
	await physics_frame
	await physics_frame
	_rules = (game.get_script() as Script).get_script_constant_map()
	var data: NelvarCraterData = game.data
	var player: NelvarPlayer = game.player
	_check(data != null, "The volcano did not load")
	if data == null:
		game.queue_free()
		return
	for enemy in get_nodes_in_group("enemies"):
		_check(data.has_clearance(enemy.global_position, 20.0), "An enemy appeared off the rock")
		enemy.queue_free()
	game.enemy_spawner.set_process(false)
	game.splashes.set("_next", INF)
	await physics_frame
	_check(game.thing_nodes.size() == data.things.size(), "Some things are missing")
	_check(game.isle_nodes.size() == data.moving_isles().size(), "Some islands are missing")
	_check(game.below.layer < game.ground.layer, "The clouds are not under the floor")
	_check(player.collision_mask & NelvarFireData.LAVA_LAYER == 0, "The lava is a wall")
	await _check_falls(game, data, player)
	await _check_ride(game, data, player)
	await _check_gap(game, data, player)
	await _check_raft(game, data, player)
	await _check_geyser(game, data, player)
	await _check_splash(game, data, player)
	await _check_hoppers(game, data)
	# Things in the air; F3 shows the outlines.
	_check(game.embers.get("_motes").size() > 0, "No ash or sparks in the air")
	var key := InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	game._unhandled_input(key)
	_check(game.get("_outlines").visible, "F3 does not show the outlines")
	game.queue_free()
	await process_frame


func _reset(player: NelvarPlayer, at: Vector2) -> void:
	player.position = at
	player.velocity = Vector2.ZERO
	player.health = player.max_health
	player.set("_invulnerability_left", 0.0)
	player.move_scale = 1.0


## A point of the rim `across` of its width out from the shore, in direction `angle`.
func _rim(data: NelvarCraterData, angle: float, across: float) -> Vector2:
	return data.vent + Vector2.from_angle(angle) * (data.lake.radius_at(angle) + data.rim_width_at(angle) * across)


## A direction where the rim is plain: no cape, no geyser, nothing solid across it.
func _plain_angle(data: NelvarCraterData) -> float:
	for i in 72:
		var angle := TAU * (i + 0.5) / 72.0
		var ok := true
		for cape in data.capes:
			ok = ok and absf(angle_difference(angle, cape.angle)) > 0.3
		for k in 11:
			var point := _rim(data, angle, k / 10.0)
			ok = ok and data.geyser_at(point, 80.0) == null
			for thing in data.things:
				if thing.solid and thing.position.distance_to(point) < thing.spread() + 36.0:
					ok = false
		if ok:
			return angle
	return PI * 0.5


func _check_falls(game: Node, data: NelvarCraterData, player: NelvarPlayer) -> void:
	var angle := _plain_angle(data)
	var inward := -Vector2.from_angle(angle)
	# Walking into the lava: a moment over it, then a fall; back on the rim, hurt.
	var start := _rim(data, angle, 0.35)
	_reset(player, start)
	for i in 8:
		await physics_frame
	var burns: int = game.burns
	await _walk(player, inward, 90)
	await create_timer(1.0).timeout
	_check(game.burns == burns + 1, "Walking into the lava was not a fall")
	_check(player.health <= player.max_health - _rule("LAVA_DAMAGE") + 0.5, "The lava did no damage")
	_check(data.lava_depth(player.global_position) < -NelvarPlayer.BODY_RADIUS and data.rim_depth(player.global_position) > 0.0,
		"The player did not come back on the rim")
	_check(not player.is_falling(), "The player did not come back from the lava")
	# Off the edge: the same, into the clouds.
	_reset(player, _rim(data, angle, 0.6))
	for i in 8:
		await physics_frame
	var drops: int = game.drops
	await _walk(player, -inward, 90)
	await create_timer(1.3).timeout
	_check(game.drops == drops + 1, "Walking off the edge was not a fall")
	_check(player.health <= player.max_health - _rule("CLIFF_DAMAGE") + 0.5, "The fall did no damage")
	_check(data.rim_depth(player.global_position) > NelvarPlayer.BODY_RADIUS, "The player did not come back on the rim")
	# A step over the lava and straight back holds.
	_reset(player, _rim(data, angle, 0.0) - inward * (NelvarPlayer.BODY_RADIUS + 2.0))
	await physics_frame
	burns = game.burns
	await _walk(player, inward, 4)
	await _walk(player, -inward, 12)
	await create_timer(0.4).timeout
	_check(game.burns == burns, "A moment over the lava was already a fall")


## Standing on a floating island moves the player exactly as far as it moves.
func _check_ride(game: Node, data: NelvarCraterData, player: NelvarPlayer) -> void:
	var isle: NelvarCraterData.Isle = null
	for candidate in data.moving_isles():
		if candidate.kind == IsleKind.PLATE and candidate.sink_at(game.clock) == 0.0 \
				and candidate.sink_at(game.clock + 3.0) == 0.0:
			isle = candidate
			break
	if isle == null:
		_check(false, "No plate afloat to ride")
		return
	var offset := Vector2(10.0, -6.0)
	_reset(player, isle.position_at(game.clock) + offset)
	var burns: int = game.burns
	for i in 60:
		await physics_frame
	var expected: Vector2 = isle.position_at(game.clock) + offset
	_check(player.global_position.distance_to(expected) < 1.5,
		"The island did not carry the player (%.1f off)" % player.global_position.distance_to(expected))
	_check(game.burns == burns, "Riding an island burnt the player")
	isle.weight = 0.0


## A cape's tip and an island of the outer ring as they pass: a run gets across.
func _check_gap(game: Node, data: NelvarCraterData, player: NelvarPlayer) -> void:
	var best_gap := INF
	var best_time := 0.0
	var best_isle: NelvarCraterData.Isle = null
	var best_cape: NelvarCraterData.Cape = null
	for isle in data.moving_isles():
		if isle.ring != data.rings.size() - 1 or isle.kind != IsleKind.PLATE:
			continue
		var turn := TAU / absf(isle.speed)
		for cape in data.capes:
			for s in 720:
				var time: float = game.clock + 5.0 + turn * s / 720.0
				var gap := NelvarCraterData.cape_gap(isle, cape, time)
				if gap < best_gap and isle.sink_at(time) == 0.0 and isle.sink_at(time + 3.0) == 0.0:
					best_gap = gap
					best_time = time
					best_isle = isle
					best_cape = cape
	if best_isle == null:
		_check(false, "No plate passes a cape")
		return
	_check(best_gap <= NelvarCraterData.RUN_GAP, "The closest pass of a plate to a cape is %.0f" % best_gap)
	# Half a second before the pass the player runs from the tip towards the plate.
	game.clock = best_time - 0.4
	var toward := best_cape.apex().direction_to(best_isle.position_at(best_time))
	_reset(player, best_cape.apex() - toward * 40.0)
	await physics_frame
	var burns: int = game.burns
	_press(toward)
	await physics_frame
	player.set("_is_running", true)
	for i in 40:
		await physics_frame
		if data.carrier_at(player.global_position, game.clock, -20.0) != null:
			break
	_release()
	for i in 20:
		await physics_frame
	_check(game.burns == burns, "Running over a narrow gap to an island burnt the player (gap %.0f)" % best_gap)
	_check(data.carrier_at(player.global_position, game.clock) != null, "The run did not reach the island")
	best_isle.weight = 0.0


## Standing still on a raft sinks it, and the player burns.
func _check_raft(game: Node, data: NelvarCraterData, player: NelvarPlayer) -> void:
	var raft: NelvarCraterData.Isle = null
	for isle in data.moving_isles():
		if isle.kind == IsleKind.RAFT:
			raft = isle
			break
	if raft == null:
		_check(false, "No raft")
		return
	_reset(player, raft.position_at(game.clock))
	var burns: int = game.burns
	var sunk: int = game.sunk
	await create_timer(raft.hold_time + NelvarCraterData.DESCENT + 1.2).timeout
	_check(game.sunk == sunk + 1, "A raft did not sink under the player")
	_check(game.burns == burns + 1, "Sinking with a raft did not burn the player")
	await create_timer(0.3).timeout


## A geyser: 6 damage, a throw that lands where the run-up carries; landing in lava burns.
func _check_geyser(game: Node, data: NelvarCraterData, player: NelvarPlayer) -> void:
	var tried := 0
	var burnt := false
	for geyser in data.geysers:
		if geyser.cape >= 0:
			continue
		var toward := geyser.position.direction_to(data.vent)
		var landing := geyser.position + toward * 300.0 * _rule("LAUNCH_BOOST") * _rule("LAUNCH_TIME")
		# Just before it bursts.
		var c := fposmod(game.clock + geyser.phase, geyser.period)
		game.clock += fposmod(geyser.period - NelvarCraterData.Geyser.BURST_TIME - c, geyser.period) - 0.05
		_reset(player, geyser.position)
		await physics_frame
		var health := player.health
		var burns: int = game.burns
		for i in 8:
			# A walking player crossing the mouth (no input: the speed is held by hand).
			player.position = geyser.position
			player.velocity = toward * 300.0
			await physics_frame
			if player.is_launched():
				break
		_check(player.is_launched(), "A geyser did not throw the player")
		_check(game.geysers.columns > 0, "A geyser erupted without a column")
		_check(is_equal_approx(player.health, health - _rule("GEYSER_DAMAGE")),
			"A geyser did %.1f damage" % (health - player.health))
		while player.is_launched():
			await physics_frame
		var travelled := player.global_position.distance_to(geyser.position)
		_check(travelled > 360.0 and travelled < 560.0, "A geyser threw a walking player %.0f" % travelled)
		var lava := data.lava_depth_at(player.global_position, game.clock) > 0.0
		await create_timer(1.0).timeout
		if lava:
			burnt = true
			_check(game.burns > burns, "Landing in the lava from a geyser did not burn")
		tried += 1
		if tried >= 3 and burnt:
			break
	_check(tried > 0, "No geyser on the rim to try")
	_check(burnt, "No geyser throw ended in the lava")


## A splash: the blow, the burning fresh lava that slows, the safe crust.
func _check_splash(game: Node, data: NelvarCraterData, player: NelvarPlayer) -> void:
	var splashes: NelvarLavaSplashes = game.splashes
	var angle := _plain_angle(data)
	var splash := NelvarLavaSplashes.Splash.new()
	splash.origin = _rim(data, angle, 0.0) + Vector2.from_angle(angle) * 2.0
	splash.direction = Vector2.from_angle(angle)
	splash.width = 140.0
	splash.reach = 100.0
	splash.start = game.clock
	splashes.add(splash)
	var inside := splash.origin + splash.direction * 40.0
	_reset(player, inside)
	var health := player.health
	await create_timer(NelvarLavaSplashes.WARN_TIME + 0.15).timeout
	_check(player.health <= health - _rule("SPLASH_DAMAGE") + 0.5, "A splash did not hurt the player")
	_check((player.global_position - inside).dot(splash.direction) > 10.0, "A splash did not throw the player back")
	_reset(player, inside)
	health = player.health
	for i in 75:
		player.position = inside
		await physics_frame
	_check(player.health < health, "Fresh lava did not burn")
	_check(is_equal_approx(player.move_scale, _rule("FRESH_SLOW")), "Fresh lava did not slow the player")
	splash.start = game.clock - NelvarLavaSplashes.WARN_TIME - NelvarLavaSplashes.FRESH_TIME - 1.0
	_reset(player, inside)
	health = player.health
	for i in 90:
		player.position = inside
		await physics_frame
	_check(is_equal_approx(player.health, health), "The cooled crust still burns")
	_check(is_equal_approx(player.move_scale, 1.0), "The cooled crust still slows")


## Hoppers blown into the lava burn, off the edge they die, on a sinking island they burn.
func _check_hoppers(game: Node, data: NelvarCraterData) -> void:
	var angle := _plain_angle(data)
	var spawn := func(at: Vector2) -> Node2D:
		var hopper: Node2D = game.enemy_spawner.enemy_scene.instantiate()
		hopper.position = at
		hopper.set("ground", data)
		game.enemy_spawner.add_child(hopper)
		return hopper
	var lava: Node2D = spawn.call(_rim(data, angle, 0.15))
	var edge: Node2D = spawn.call(_rim(data, angle, 0.85))
	await physics_frame
	lava.call("apply_knockback", -Vector2.from_angle(angle) * 900.0)
	edge.call("apply_knockback", Vector2.from_angle(angle) * 900.0)
	await create_timer(0.8).timeout
	_check(not is_instance_valid(lava) or lava.call("is_dead"), "A hopper blown into the lava did not burn")
	_check(not is_instance_valid(edge) or edge.call("is_dead"), "A hopper blown off the edge did not die")
	var plate: NelvarCraterData.Isle = null
	for isle in data.moving_isles():
		if isle.kind == IsleKind.PLATE and isle.sink_at(game.clock) == 0.0:
			plate = isle
			break
	if plate != null:
		var rider: Node2D = spawn.call(plate.position_at(game.clock))
		await physics_frame
		_check(is_instance_valid(rider) and not rider.call("is_dead"), "A hopper on a plate died at once")
		plate.sank_at = game.clock - NelvarCraterData.DESCENT
		await create_timer(0.5).timeout
		_check(not is_instance_valid(rider) or rider.call("is_dead"), "A hopper on a sinking plate did not burn")
	# Hoppers never pick lava, the edge or a geyser to land on.
	for geyser in data.geysers:
		_check(not data.is_safe_landing(geyser.position), "A hopper may land in a geyser")
	_check(not data.is_safe_landing(data.vent), "A hopper may land in the lake")


func _rule(name: String) -> float:
	return float(_rules.get(name, 0.0))


func _press(direction: Vector2) -> void:
	_release()
	if direction.x < -0.1:
		Input.action_press("move_left", -direction.x)
	elif direction.x > 0.1:
		Input.action_press("move_right", direction.x)
	if direction.y < -0.1:
		Input.action_press("move_up", -direction.y)
	elif direction.y > 0.1:
		Input.action_press("move_down", direction.y)


func _release() -> void:
	for name: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(name)


func _walk(player: NelvarPlayer, direction: Vector2, frames: int) -> void:
	_press(direction)
	for frame in frames:
		await physics_frame
		if player.is_falling():
			break
	_release()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition and _failures.size() < 40:
		_failures.append(message)
