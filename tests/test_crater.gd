extends SceneTree
## The volcano (Огонь 2): layout rules (the rim, the capes, broad floes of crust sharing
## out most of the lake and stones between them, never touching the shore or each other,
## drifting slowly and making a way on foot from the shore to the middle, some stones
## sinking; geysers and things on the rock), the ground and light maps, the floes' masks,
## and the real scene: a step into the lava is a fall that throws the player back hurt (onto the floe
## they last stood on safely, if it never sinks), the summit's edge holds them, a floe holds and carries
## them unharmed, a sinking floe takes them down, geysers throw them, splashes burn,
## hoppers die in the lava, off the edge and on a sinking floe.
## Run: godot --headless --path . --script tests/test_crater.gd -- --seeds=6

const Kind = NelvarFireData.Kind
const STEP := NelvarFireData.PIXEL

var _failures: Array[String] = []
var _checks := 0
## NelvarCraterMain's constants (read from the scene's script: compiling against it here
## would need the autoloads).
var _rules := {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var count := 6
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			count = maxi(1, argument.trim_prefix("--seeds=").to_int())
	var config := NelvarCraterConfig.new()
	var generator := NelvarCraterGenerator.new()
	var started := Time.get_ticks_msec()
	var floes := 0
	for index in count:
		var world_seed := 20261125 + index * 7919
		var data := generator.generate(config, world_seed)
		_check(data != null, "Seed %d: generation failed" % world_seed)
		if data == null:
			continue
		floes += data.floes.size()
		_check_layout(data, config)
		_check_floes(data, config)
		if index < 2:
			_check(_fingerprint(generator.generate(config, world_seed)) == _fingerprint(data),
				"Seed %d: layout is not reproducible" % world_seed)
		if index == 0:
			_check_field(data)
			_check_art(data)
	print("Volcano: %d seeds in %.2f s · %.1f floes each" % [count,
		float(Time.get_ticks_msec() - started) / 1000.0, float(floes) / count])
	await _check_scene()
	if _failures.is_empty():
		print("PASS: %d checks; volcano layout, floes, maps, art, falls, rides, geysers, splashes and the scene behave" % _checks)
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
	_check(data.geysers.size() >= config.geysers.x - 1, context + "%d geysers" % data.geysers.size())
	_check(data.boils.size() >= 2, context + "too few boiling patches")
	_check(not data.smoke_banks.is_empty(), context + "no smoke banks")
	# The spawn: on the southern terrace, free, near the lake.
	_check(data.has_clearance(data.spawn_position, NelvarPlayer.BODY_RADIUS + 20.0), context + "the spawn is blocked")
	_check(data.spawn_position.y > data.vent.y + 600.0, context + "the spawn is not in the south")
	_check(data.lava_depth(data.spawn_position) > -320.0, context + "the spawn is far from the lake")
	# Capes reach into the lake as far as asked.
	for cape in data.capes:
		var length := data.lake.radius_at(cape.angle) - data.vent.distance_to(cape.apex())
		_check(length >= config.cape_length.x - 1.0 and length <= config.cape_length.y + 1.0, context + "a cape is %.0f long" % length)
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


## Broad floes cover most of the lake, stones lie between; floes stay in the lava
## wherever their sway takes them, never touch each other, drift slowly, and make a way on
## foot: from the shore to every floe and to the middle, no step wider than a run. Some
## stones sink, broad floes never do.
func _check_floes(data: NelvarCraterData, config: NelvarCraterConfig) -> void:
	var context := "Seed %d: " % data.world_seed
	var broad := 0
	var area := 0.0
	for floe in data.floes:
		if floe.broad:
			broad += 1
			for r in floe.radii:
				area += 0.5 * r * r * TAU / floe.radii.size()
	var lake := 0.0
	for i in 360:
		lake += 0.5 * pow(data.lake.radius_at(TAU * i / 360.0), 2.0) * TAU / 360.0
	_check(broad >= 8 and area > lake * 0.45 and data.floes.size() - broad <= config.stones.y,
		context + "%d broad floes covering %.2f of the lake, %d stones" % [broad, area / lake, data.floes.size() - broad])
	var aground := 0
	var touching := 0
	var fastest := 0.0
	var near := {}
	for i in data.floes.size():
		var floe := data.floes[i]
		near[i] = []
		for j in data.floes.size():
			var other := data.floes[j]
			if j != i and floe.center.distance_to(other.center) < floe.outer + other.outer + 120.0:
				near[i].append(j)
		for s in 12:
			var time := 13.7 * s
			var at := floe.position_at(time)
			fastest = maxf(fastest, at.distance_to(floe.position_at(time + 0.1)) / 0.1)
			for k in range(0, floe.outline.size(), 4):
				if data.lava_depth(at + floe.outline[k]) <= 0.0:
					aground += 1
			for j: int in near[i]:
				if j > i and NelvarCraterData.floe_gap(floe, data.floes[j], time) <= 0.0:
					touching += 1
	_check(aground == 0, context + "floes run aground %d times" % aground)
	_check(touching == 0, context + "floes touch %d times" % touching)
	_check(fastest < 20.0, context + "a floe drifts at %.0f" % fastest)
	# On foot from the shore.
	var reached := {}
	var queue: Array[int] = []
	for i in data.floes.size():
		if _floe_reaches(data, data.floes[i], func(point: Vector2) -> bool: return data.lava_depth(point) < NelvarCraterData.RUN_GAP):
			reached[i] = true
			queue.append(i)
	while not queue.is_empty():
		var i: int = queue.pop_back()
		for j: int in near[i]:
			if not reached.has(j) and NelvarCraterData.floe_gap(data.floes[i], data.floes[j], 0.0) <= NelvarCraterData.RUN_GAP:
				reached[j] = true
				queue.append(j)
	var middle := INF
	var sinking := 0
	var broad_sinking := 0
	for i in data.floes.size():
		if reached.has(i):
			middle = minf(middle, data.floes[i].center.distance_to(data.vent) - data.floes[i].outer)
		if data.floes[i].sinks():
			sinking += 1
			if data.floes[i].broad:
				broad_sinking += 1
	_check(reached.size() == data.floes.size() and middle < data.vent_radius + config.vent_moat + 200.0,
		context + "on foot: %d of %d floes, nearest the vent %.0f" % [reached.size(), data.floes.size(), middle])
	_check(sinking > 0 and broad_sinking == 0, context + "%d stones sink, %d broad floes sink" % [sinking - broad_sinking, broad_sinking])


## Whether a point of the floe's outline at time 0 passes `test`.
func _floe_reaches(_data: NelvarCraterData, floe: NelvarCraterData.Isle, test: Callable) -> bool:
	var at := floe.position_at(0.0)
	for point in floe.outline:
		if test.call(at + point):
			return true
	return false


func _fingerprint(data: NelvarCraterData) -> int:
	var parts: Array = [data.spawn_position, data.summit.radii, data.flows.size(), data.capes.size()]
	for floe in data.floes:
		parts.append([floe.center, floe.drift, floe.radii, floe.sink_period, floe.sink_phase])
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
		var point := data.vent + Vector2.from_angle(angle) * data.lake.radius_at(angle) * 0.5
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
	var some: Array[NelvarCraterData.Isle] = data.floes.filter(func(isle: NelvarCraterData.Isle) -> bool: return isle.broad).slice(0, 2)
	some.append_array(data.floes.filter(func(isle: NelvarCraterData.Isle) -> bool: return not isle.broad).slice(0, 6))
	var bad := 0
	for isle in some:
		var mask := NelvarCraterIsland.bake_mask(isle)
		var inside := 0
		var core := 0
		var faces := 0
		# The mask's R is quarters of an art pixel in from the edge.
		var deep := minf(isle.inner / STEP, 60.0) * 0.5 * 4.0 / 255.0
		for y in mask.get_height():
			for x in mask.get_width():
				var pixel := mask.get_pixel(x, y)
				if pixel.a > 0.5:
					inside += 1
					if pixel.r > deep:
						core += 1
					if roundi(pixel.g * 255.0) == 1:
						faces += 1
		if inside < PI * pow(isle.inner / STEP, 2.0) * 0.9 or core == 0 or faces <= 4:
			bad += 1
	_check(bad == 0, "%d floe masks are too small, have no core or no south face" % bad)
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
	var on_floes := 0
	for enemy in get_nodes_in_group("enemies"):
		_check(data.can_spawn_at(enemy.global_position, 20.0), "An enemy appeared off the rock and the floes")
		if data.steady_floe_at(enemy.global_position) != null:
			on_floes += 1
		enemy.queue_free()
	_check(on_floes > 0, "No enemy appeared on the floes")
	game.enemy_spawner.set_process(false)
	game.splashes.set("_next", INF)
	await physics_frame
	_check(game.thing_nodes.size() == data.things.size(), "Some things are missing")
	_check(game.isle_nodes.size() == data.floes.size(), "Some floes are missing")
	_check(game.below.layer < game.ground.layer, "The clouds are not under the floor")
	_check(player.collision_mask & NelvarFireData.LAVA_LAYER == 0, "The lava is a wall")
	await _check_floe(game, data, player)
	await _check_falls(game, data, player)
	await _check_sinking(game, data, player)
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


## A floe holds the player unharmed and carries them exactly as far as it drifts; a fall
## into the lava from there brings them back onto it.
func _check_floe(game: Node, data: NelvarCraterData, player: NelvarPlayer) -> void:
	var floe: NelvarCraterData.Isle = null
	for candidate in data.floes:
		if not candidate.sinks() and candidate.inner > 80.0:
			floe = candidate
			break
	if floe == null:
		_check(false, "No broad floe that never sinks")
		return
	var offset := Vector2(6.0, 4.0)
	_reset(player, floe.position_at(game.clock) + offset)
	var burns: int = game.burns
	var health := player.health
	for i in 90:
		await physics_frame
	var expected: Vector2 = floe.position_at(game.clock) + offset
	_check(player.global_position.distance_to(expected) < 1.5,
		"The floe did not carry the player (%.1f off)" % player.global_position.distance_to(expected))
	_check(game.burns == burns, "Standing on a floe was a fall")
	_check(is_equal_approx(player.health, health), "A floe hurt the player")
	# Into the lava by the vent: back onto that floe.
	player.position = data.vent + Vector2(data.vent_radius + 40.0, 0.0)
	await create_timer(1.2).timeout
	_check(game.burns == burns + 1 and data.carrier_at(player.global_position, game.clock) == floe,
		"A fall did not bring the player back onto the floe they stood on")


func _check_falls(game: Node, data: NelvarCraterData, player: NelvarPlayer) -> void:
	var angle := _plain_angle(data)
	var inward := -Vector2.from_angle(angle)
	# Walking into the lava: a moment over it, then a fall; back on the rim, hurt.
	var start := _rim(data, angle, 0.35)
	_reset(player, start)
	for i in 8:
		await physics_frame
	var burns: int = game.burns
	var floes := _without_floes(data)
	await _walk(player, inward, 90)
	await create_timer(1.0).timeout
	_restore_floes(data, floes)
	_check(game.burns == burns + 1, "Walking into the lava was not a fall")
	_check(player.health <= player.max_health - _rule("LAVA_DAMAGE") + 0.5, "The lava did no damage")
	_check(data.lava_depth(player.global_position) < -NelvarPlayer.BODY_RADIUS and data.rim_depth(player.global_position) > 0.0,
		"The player did not come back on the rim")
	_check(not player.is_falling(), "The player did not come back from the lava")
	# The edge holds: walking out leaves the player on the rim, unhurt.
	_reset(player, _rim(data, angle, 0.6))
	for i in 8:
		await physics_frame
	await _walk(player, -inward, 90)
	await create_timer(0.5).timeout
	_check(not player.is_falling() and player.health == player.max_health and data.rim_depth(player.global_position) >= 0.0,
		"The player walked off the edge")
	# A step over the lava and straight back holds.
	_reset(player, _rim(data, angle, 0.0) - inward * (NelvarPlayer.BODY_RADIUS + 2.0))
	await physics_frame
	burns = game.burns
	await _walk(player, inward, 4)
	await _walk(player, -inward, 12)
	await create_timer(0.4).timeout
	_check(game.burns == burns, "A moment over the lava was already a fall")


## A floe that sinks takes whoever stands on it down: they burn and are told why.
func _check_sinking(game: Node, data: NelvarCraterData, player: NelvarPlayer) -> void:
	var floe: NelvarCraterData.Isle = null
	for candidate in data.floes:
		if candidate.sinks() and candidate.inner > 40.0:
			floe = candidate
			break
	if floe == null:
		_check(false, "No floe sinks")
		return
	game.clock = _before_descent(floe, game.clock) - 0.3
	_reset(player, floe.position_at(game.clock))
	await physics_frame
	var burns: int = game.burns
	await create_timer(NelvarCraterData.DESCENT + 0.4).timeout
	_check(game.burns == burns + 1, "A sinking floe did not take the player down")
	await create_timer(0.9).timeout
	_check(game.message.text == game.HINT_SINK, "Going down with a floe said nothing")


## The first time after `after` the floe starts going down.
func _before_descent(floe: NelvarCraterData.Isle, after: float) -> float:
	var down := floe.sink_period - floe.sink_under - NelvarCraterData.DESCENT
	return after + fposmod(down - floe.sink_phase - after, floe.sink_period) + floe.sink_period


## Takes the floes away (to test the lava itself) and gives them back.
func _without_floes(data: NelvarCraterData) -> Array[NelvarCraterData.Isle]:
	var floes := data.floes
	data.floes = []
	data.index_floes()
	return floes


func _restore_floes(data: NelvarCraterData, floes: Array[NelvarCraterData.Isle]) -> void:
	data.floes = floes
	data.index_floes()


## A geyser: 6 damage, a throw that lands where the run-up carries; landing in lava burns.
func _check_geyser(game: Node, data: NelvarCraterData, player: NelvarPlayer) -> void:
	var tried := 0
	var burnt := false
	var floes := _without_floes(data)
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
	_restore_floes(data, floes)
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


## Hoppers blown into the lava burn, off the edge they die, on a sinking floe they burn.
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
	var floe: NelvarCraterData.Isle = null
	for candidate in data.floes:
		if candidate.sinks() and candidate.inner > 40.0:
			floe = candidate
			break
	if floe != null:
		game.clock = _before_descent(floe, game.clock) - 0.3
		var rider: Node2D = spawn.call(floe.position_at(game.clock))
		await physics_frame
		_check(is_instance_valid(rider) and not rider.call("is_dead"), "A hopper on a floe died at once")
		await create_timer(NelvarCraterData.DESCENT + 0.5).timeout
		_check(not is_instance_valid(rider) or rider.call("is_dead"), "A hopper on a sinking floe did not burn")
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
