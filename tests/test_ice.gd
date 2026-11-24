extends SceneTree
## The ice valley: layout rules (lakes, thin ice, crevasses and their bridges, trails,
## passages, frozen creatures), reachability over the bridges, artwork, the floor map,
## the start setting, and the real scene: the ice is slippery, a wide crevasse drops a
## walking player and throws them back, the flight carries them over it and a run over a
## narrow one, thin ice breaks under a standing player and not under a running one, a
## hole freezes over, hoppers blown into a crevasse or a hole die, a blizzard slows the
## player and lets go, marks are left in the snow, a frozen creature opens its eye.
## Run: godot --headless --path . --script tests/test_ice.gd -- --seeds=30

const Kind = NelvarIceData.Kind
const BODY := NelvarPlayer.BODY_RADIUS

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var count := 30
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			count = maxi(1, argument.trim_prefix("--seeds=").to_int())
	var config := NelvarIceConfig.new()
	var generator := NelvarIceGenerator.new()
	var started := Time.get_ticks_msec()
	var reached := 0.0
	var crevasses := 0
	var bridges := 0
	for index in count:
		var world_seed := 20261124 + index * 7919
		var data := generator.generate(config, world_seed)
		_check(data != null, "Seed %d: generation failed" % world_seed)
		if data == null:
			continue
		crevasses += data.crevasses.size()
		bridges += data.bridge_count()
		_check_layout(data, config)
		if index < 4:
			_check(_fingerprint(generator.generate(config, world_seed)) == _fingerprint(data),
				"Seed %d: layout is not reproducible" % world_seed)
		if index < 8:
			reached += _check_reachability(data)
		if index == 0:
			_check_art(data)
			_check_field(data)
	_check(crevasses >= count * 2, "Only %d crevasses over %d valleys" % [crevasses, count])
	print("Ice: %d seeds in %.2f s · %d crevasses · %d bridges · %.1f%% of open ground reachable" % [count,
		float(Time.get_ticks_msec() - started) / 1000.0, crevasses, bridges, reached / mini(count, 8) * 100.0])
	_check_settings()
	await _check_scene()
	if _failures.is_empty():
		print("PASS: %d checks; valley layout, bridges, art, ice, crevasses, thin ice, blizzards and the scene behave" % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FAIL: %d failures / %d checks" % [_failures.size(), _checks])
		quit(1)


# --- Layout --------------------------------------------------------------------

func _check_layout(data: NelvarIceData, config: NelvarIceConfig) -> void:
	var context := "Seed %d: " % data.world_seed
	_check(data.boundary.size() == config.boundary_vertices, context + "the mountain foot is not closed")
	_check(data.has_clearance(data.spawn_position, BODY + 20.0), context + "the spawn is blocked")
	_check(data.ice_at(data.spawn_position) == NelvarIceData.Surface.SNOW
		and data.lake_depth(data.spawn_position) < -100.0, context + "the spawn is not on the snow")
	_check(data.lakes.size() >= config.lake_count.x and data.lakes.size() <= config.lake_count.y,
		context + "%d lakes" % data.lakes.size())
	var thin := 0
	for l in data.lakes.size():
		var lake := data.lakes[l]
		for point in data.lake_polygons[l]:
			_check(data.valley.signed_distance(point) > config.lake_margin * 0.5, context + "lake %d touches the mountains" % l)
		for patch in lake.thin:
			thin += 1
			for point in patch.polygon(24):
				_check(lake.shape.signed_distance(point) > 10.0, context + "thin ice spills out of lake %d" % l)
			_check(data.ice_at(patch.center) == NelvarIceData.Surface.THIN, context + "a thin patch is not thin ice")
	_check(thin >= data.lakes.size(), context + "too little thin ice")
	_check(data.crevasses.size() >= config.crevasse_count.x, context + "%d crevasses" % data.crevasses.size())
	for crevasse in data.crevasses:
		for i in crevasse.points.size():
			var point := crevasse.points[i]
			_check(data.lake_depth(point) < -(crevasse.half_widths[i] + config.ice_gap * 0.98),
				context + "a crevasse comes too close to the ice")
			_check(crevasse.half_widths[i] <= config.crevasse_half_width.y + 0.01, context + "a crevasse is too wide")
		var inside := 0.0
		var along := 0.0
		while along < crevasse.length():
			if data.valley.signed_distance(crevasse.point_at(along)) > 200.0 \
					and crevasse.half_width_at(along) > NelvarIceGenerator.TIP_HALF_WIDTH + 2.0:
				inside += 10.0
			along += 10.0
		if inside > config.bridge_spacing + config.bridge_half_length * 2.0:
			_check(not crevasse.bridges.is_empty(), context + "a long crevasse has no bridge")
		for bridge in crevasse.bridges:
			_check(data.crevasse_depth(bridge.center) < -bridge.half_length * 0.5, context + "a bridge is a crack")
			_check(data.crevasse_sample(bridge.center).x > 0.0, context + "a bridge spans nothing")
			_check(data.is_open_ground(bridge.center, BODY), context + "a bridge is blocked")
			var past := bridge.center + bridge.direction * (bridge.half_length + 12.0)
			if crevasse.half_width_at(bridge.along + bridge.half_length + 12.0) > 10.0:
				_check(data.crevasse_depth(past) > 0.0, context + "the crack does not resume past a bridge")
	for trail in data.trails:
		for point in trail.points:
			_check(data.crevasse_depth(point) < -trail.half_width * 0.5, context + "a trail runs into a crevasse")
			_check(data.lake_depth(point) < -trail.half_width * 0.5, context + "a trail runs onto the ice")
	for clearing in data.clearings:
		_check(data.has_clearance(clearing.center, BODY), context + "a clearing is blocked")
	_check(not data.frozen.is_empty(), context + "nothing is frozen into the lakes")
	var watching := false
	for creature in data.frozen:
		watching = watching or creature.eye
		_check(data.lakes[creature.lake].shape.signed_distance(creature.position) > creature.radius,
			context + "a frozen creature is not wholly under the ice")
	_check(watching, context + "no frozen creature watches")
	var solids: Array[NelvarIceData.Thing] = []
	for thing in data.things:
		var name: String = Kind.keys()[thing.kind]
		_check(data.valley.signed_distance(thing.position) > thing.spread(),
			context + "%s %d stands in the mountains" % [name, thing.id])
		_check(data.crevasse_sample(thing.position).x < -thing.spread() * 0.5,
			context + "%s %d stands in a crevasse" % [name, thing.id])
		_check(data.thin_depth(thing.position) < -thing.spread(), context + "%s %d stands on thin ice" % [name, thing.id])
		if thing.kind != Kind.ICE_BLOCK:
			_check(data.lake_depth(thing.position) < -thing.spread() * 0.5, context + "%s %d stands on the ice" % [name, thing.id])
		if thing.solid:
			solids.append(thing)
			_check(data.distance_to_trails(thing.position) >= thing.spread() - 0.5,
				context + "%s %d blocks a trail" % [name, thing.id])
			_check(thing.position.distance_to(data.spawn_position) >= config.spawn_clearance,
				context + "something solid stands at the spawn")
	_check(data.count(Kind.PINE) >= 30, context + "only %d pines" % data.count(Kind.PINE))
	_check(data.count(Kind.DEAD_TREE) >= 4, context + "only %d dead trees" % data.count(Kind.DEAD_TREE))
	_check(data.count(Kind.ROCK) >= 20, context + "only %d rocks" % data.count(Kind.ROCK))
	_check(data.count(Kind.DRIFT) >= 6, context + "only %d drifts" % data.count(Kind.DRIFT))
	_check(data.count(Kind.ICE_BLOCK) >= 4, context + "only %d blocks of ice" % data.count(Kind.ICE_BLOCK))
	_check(data.count(Kind.STATUE) >= 1, context + "no petrified creature")
	for a in solids.size():
		for b in range(a + 1, solids.size()):
			var first := solids[a]
			var second := solids[b]
			var distance := first.position.distance_to(second.position)
			if distance > 400.0:
				continue
			_check(distance >= first.spread() + second.spread() + BODY * 2.0,
				context + "no passage between %s %d and %s %d" % [Kind.keys()[first.kind], first.id,
					Kind.keys()[second.kind], second.id])
	var angles: Array[float] = []
	for peak in data.peaks:
		if peak.row == 0:
			angles.append((peak.position - data.valley.center).angle())
	angles.sort()
	var widest := TAU - (angles[angles.size() - 1] - angles[0])
	for i in angles.size() - 1:
		widest = maxf(widest, angles[i + 1] - angles[i])
	_check(widest < 0.3, context + "a gap of %.2f rad in the mountains" % widest)


## Share of open ground (where the player fits) reachable on foot from the spawn: the
## crevasses split the valley only where bridges join it again.
func _check_reachability(data: NelvarIceData) -> float:
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
			if data.has_clearance(origin + Vector2(x + 0.5, y + 0.5) * CELL, BODY):
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


func _fingerprint(data: NelvarIceData) -> int:
	var parts: Array = [data.spawn_position, data.boundary, data.trails.size(), data.crevasses.size()]
	for lake in data.lakes:
		parts.append([lake.shape.center, lake.shape.axes, lake.thin.size()])
	for crevasse in data.crevasses:
		parts.append([crevasse.points, crevasse.half_widths, crevasse.bridges.size()])
	for creature in data.frozen:
		parts.append([creature.position, creature.radius, creature.variant, creature.eye])
	for thing in data.things:
		parts.append([thing.kind, thing.variant, thing.position, thing.radius, thing.size, thing.accent,
			thing.appearance_seed])
	for peak in data.peaks:
		parts.append([peak.variant, peak.position, peak.size])
	return hash(parts)


# --- Art and the floor map ---------------------------------------------------------

func _check_art(data: NelvarIceData) -> void:
	var painter := NelvarIcePainter.new()
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
		var grid: Vector2 = (thing.position + art.local_rect.position) / NelvarIceData.PIXEL
		_check(grid.is_equal_approx(grid.round()), name + " art is off the world grid")
		images[hash(art.image.get_data())] = true
		if thing.kind == Kind.STATUE:
			_check(art.eye.is_finite(), "A petrified creature has no eye")
	_check(images.size() == seen.values().reduce(func(a: int, b: int) -> int: return a + b, 0),
		"Two things share identical art")
	for kind in Kind.size():
		_check(seen.has("%d:0" % kind) or seen.has("%d:1" % kind) or seen.has("%d:2" % kind),
			"No %s to paint" % Kind.keys()[kind])
	for creature in data.frozen.slice(0, 3):
		var art := painter.paint_frozen(creature)
		_check(art != null and not art.image.is_invisible() and art.eye.is_finite(), "A frozen creature has no art or eye")
		_check(art.image.get_data() == painter.paint_frozen(creature).image.get_data(), "Frozen art is not reproducible")
	var frost := NelvarFrostPainter.new()
	var shapes := {}
	for peak in data.peaks:
		if shapes.has(peak.variant):
			continue
		shapes[peak.variant] = true
		var art: NelvarIceArt = painter.paint_boulder(peak) if peak.variant == NelvarEarthData.Peak.BOULDER \
			else frost.paint(peak)
		_check(art != null and not art.image.is_invisible(), "Peak %d has no art" % peak.variant)
		if peak.variant != NelvarEarthData.Peak.BOULDER:
			_check(not art.relief.is_empty(), "A peak has no relief for its shadow")
	_check(shapes.size() >= 5, "Only %d looks of peaks" % shapes.size())


func _check_field(data: NelvarIceData) -> void:
	var field := NelvarIceField.build(data)
	var at := func(point: Vector2, channel: int) -> int:
		var p := Vector2i((point / NelvarIceData.PIXEL).floor()) - field.origin
		return field.data[(p.y * field.size.x + p.x) * 4 + channel]
	for lake in data.lakes:
		_check(at.call(lake.shape.point_at(0.3, 40.0), 0) > 135, "The floor map has no ice in a lake")
		_check(at.call(lake.shape.point_at(0.3, -60.0), 0) < 128, "The floor map spills a lake on its shore")
		for patch in lake.thin:
			var value: int = at.call(patch.center, 3)
			_check(value >= 1 and value <= NelvarIceField.THIN_MAX, "The floor map misses thin ice")
	for crevasse in data.crevasses:
		var middle := crevasse.point_at(crevasse.length() * 0.4)
		if data.crevasse_depth(middle) > 8.0:
			_check(at.call(middle, 2) > 130 and at.call(middle, 3) != NelvarIceField.BRIDGE, "The floor map misses a crack")
		for bridge in crevasse.bridges:
			_check(at.call(bridge.center, 3) == NelvarIceField.BRIDGE, "The floor map misses a bridge")
			_check(at.call(bridge.center, 2) >= 128, "A bridge spans no crack on the floor map")
	for trail in data.trails:
		_check(at.call(trail.points[trail.points.size() >> 1], 1) < 20, "The floor map misses a trail")
	var banks := 0
	for bank in data.snow_banks:
		var value: int = at.call(Vector2(bank.x, bank.y), 3)
		if value >= NelvarIceField.BANK_FROM and value <= 200:
			banks += 1
	_check(banks * 2 >= data.snow_banks.size(), "The floor map misses the drifted snow")


# --- The start setting -------------------------------------------------------------

## The four start options exclude each other; «Играть» opens the ice valley when its
## option is on. The saved settings are put back as they were.
func _check_settings() -> void:
	var settings: Node = root.get_node("GameSettings")
	var path: String = settings.PATH
	var saved := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	var was := [settings.start_in_void, settings.start_on_earth, settings.start_in_fire, settings.start_on_ice]
	settings.set_start_in_fire(true)
	settings.set_start_on_ice(true)
	_check(settings.start_on_ice and not settings.start_in_fire and not settings.start_on_earth
		and not settings.start_in_void, "The ice did not replace the fire at start")
	settings.set_start_in_void(true)
	_check(settings.start_in_void and not settings.start_on_ice, "The Void did not replace the ice at start")
	settings.set_start_on_ice(true)
	_check(settings.start_on_ice and not settings.start_in_void, "The ice did not replace the Void at start")
	settings.set_start_on_ice(false)
	_check(not (settings.start_on_ice or settings.start_in_void or settings.start_on_earth or settings.start_in_fire),
		"Turning the ice off left another start on")
	settings.start_in_void = was[0]
	settings.start_on_earth = was[1]
	settings.start_in_fire = was[2]
	settings.start_on_ice = was[3]
	if saved.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	_check(ResourceLoader.exists("res://scenes/ice.tscn"), "There is no ice scene")
	var menu := FileAccess.get_file_as_string("res://ui/main_menu/main_menu.gd")
	_check(menu.contains("res://scenes/ice.tscn") and menu.contains("GameSettings.start_on_ice"),
		"«Играть» does not open the ice valley")
	_check(not menu.contains("Ледяной долины ещё нет"), "«Играть» still falls back from the ice valley")
	var panel: Node = load("res://ui/main_menu/dev_panel.tscn").instantiate()
	_check(panel.get_node_or_null("Rows/StartOnIce") is CheckButton, "The developer menu has no ice start")
	panel.free()
	var hint := FileAccess.get_file_as_string("res://ui/main_menu/dev_panel.gd")
	_check(hint.contains("«Играть» откроет ледяную долину"), "The developer menu does not say «Играть» opens the ice")


# --- The scene ---------------------------------------------------------------------

func _check_scene() -> void:
	var picked := _scene_seed()
	var game = load("res://scenes/ice.tscn").instantiate()
	game.set_meta("seed_override", picked)
	root.add_child(game)
	await physics_frame
	await physics_frame
	var data: NelvarIceData = game.data
	var player: NelvarPlayer = game.player
	_check(data != null, "The ice scene did not generate")
	if data == null:
		return
	for enemy in get_nodes_in_group("enemies"):
		_check(data.has_clearance(enemy.global_position, 20.0), "An enemy appeared in a crack or a wall")
		_check(enemy.get("ground") == data, "A hopper does not know the valley")
		enemy.queue_free()
	game.enemy_spawner.set_process(false)
	# No blizzard during the tests but the one they make.
	for storm in game.storms:
		storm.start += 100000.0
	await physics_frame
	_check(game.peak_nodes.size() == data.peaks.size(), "Some peaks are missing")
	_check(game.thing_nodes.size() == data.things.size(), "Some things are missing")
	_check(game.depths.frozen_nodes.size() == data.frozen.size(), "Some frozen creatures are missing")
	_check(game.ground.transparent, "The floor does not let the depths show")
	await _check_sliding(game, data, player)
	await _check_crevasses(game, data, player)
	await _check_thin_ice(game, data, player)
	await _check_hoppers(game, data)
	await _check_blizzard(game, data, player)
	await _check_marks(game, data, player)
	await _check_eye(game, data, player)
	var key := InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	game._unhandled_input(key)
	_check(game.get("_outlines").visible, "F3 does not show the outlines")
	game.queue_free()
	await process_frame


## After the keys are let go, the player slides much further on the ice than on snow.
func _check_sliding(game: Node, data: NelvarIceData, player: NelvarPlayer) -> void:
	var on_snow := await _coast(player, data.spawn_position, _open_direction(data, data.spawn_position, 120.0, false))
	var lane := _ice_lane(data)
	if lane.is_empty():
		_check(false, "No free stretch of ice to slide on")
		return
	var on_ice := await _coast(player, lane[0], lane[1])
	_check(player.traction < 0.5, "The ice does not take the player's grip")
	_check(on_ice > on_snow * 3.0 and on_ice > 90.0,
		"The player slid %.0f on the ice and %.0f on snow" % [on_ice, on_snow])


## Distance the player coasts at full walking speed with the keys let go.
func _coast(player: NelvarPlayer, from: Vector2, direction: Vector2) -> float:
	await _place(player, from)
	player.velocity = direction * player.speed
	for i in 100:
		await physics_frame
	return player.position.distance_to(from)


## Straight free ice from a point of a lake: [start, direction] (empty if none).
func _ice_lane(data: NelvarIceData) -> Array:
	for lake in data.lakes:
		for k in 8:
			var direction := Vector2.from_angle(TAU * k / 8.0)
			var start := lake.shape.center - direction * lake.shape.axes.y * 0.5
			var free := true
			for step in 26:
				var point := start + direction * step * 10.0
				if not data.has_clearance(point, BODY + 6.0) or data.lake_depth(point) < 20.0 \
						or data.thin_depth(point) > -20.0:
					free = false
					break
			if free:
				return [start, direction]
	return []


## A direction from the point with `length` of free snow (or ground) ahead.
func _open_direction(data: NelvarIceData, from: Vector2, length: float, ice_ok: bool) -> Vector2:
	for k in 8:
		var direction := Vector2.from_angle(TAU * k / 8.0)
		var free := true
		for step in int(length / 10.0) + 1:
			var point := from + direction * step * 10.0
			if not data.has_clearance(point, BODY + 6.0) or (not ice_ok and data.lake_depth(point) > -20.0):
				free = false
				break
		if free:
			return direction
	return Vector2.RIGHT


## A wide crevasse drops a walking player (back on safe snow, hurt) and is flown over;
## a narrow one drops a walker too but is crossed at a run.
func _check_crevasses(game: Node, data: NelvarIceData, player: NelvarPlayer) -> void:
	var wide := _crossing_spot(data, false)
	var narrow := _crossing_spot(data, true)
	_check(not wide.is_empty(), "No wide stretch of crevasse to test")
	_check(not narrow.is_empty(), "No narrow stretch of crevasse to test")
	if not wide.is_empty():
		var center: Vector2 = wide[0]
		var normal: Vector2 = wide[1]
		var half: float = wide[2]
		var start := center + normal * (half + 70.0)
		await _place(player, start)
		player.health = player.max_health
		var falls: int = game.falls
		await _push(player, -normal, 1.0, false, 80, func() -> bool: return game.falls > falls)
		_check(game.falls == falls + 1, "Walking into a wide crevasse did not drop the player")
		await create_timer(game.FALL_TIME + 0.6).timeout
		_check(not player.is_falling(), "The player did not come back from the crevasse")
		_check(player.health < player.max_health, "The fall did no damage")
		_check(data.crevasse_depth(player.global_position) < -BODY and player.global_position.distance_to(start) < 120.0,
			"The player was not thrown back on safe snow")
		# The flight carries them over.
		await _place(player, start)
		falls = game.falls
		player.call("_try_speed_boost")
		var across := center - normal * (half + 60.0)
		await _push(player, -normal, 1.0, false, 120, func() -> bool:
			return (player.global_position - across).dot(normal) < 0.0)
		_check(game.falls == falls, "The flight did not carry the player over a crevasse")
		_check((player.global_position - center).dot(normal) < -half, "The flight did not reach the far side")
		player.call("_land")
		await physics_frame
	if not narrow.is_empty():
		var center: Vector2 = narrow[0]
		var normal: Vector2 = narrow[1]
		var half: float = narrow[2]
		var start := center + normal * (half + 80.0)
		var falls: int = game.falls
		await _place(player, start)
		player.velocity = -normal * player.speed
		await _push(player, -normal, 1.0, false, 60, func() -> bool: return game.falls > falls)
		_check(game.falls == falls + 1, "Walking over a narrow crevasse (%.0f wide) did not drop the player" % (half * 2.0))
		await create_timer(game.FALL_TIME + 0.6).timeout
		await _place(player, start)
		falls = game.falls
		player.velocity = -normal * player.speed * player.run_speed_multiplier
		var across := center - normal * (half + 40.0)
		await _push(player, -normal, 1.0, true, 60, func() -> bool:
			return (player.global_position - across).dot(normal) < 0.0)
		_check(game.falls == falls, "A run did not carry the player over a narrow crevasse (%.0f wide)" % (half * 2.0))
		_check((player.global_position - center).dot(normal) < -half, "The run did not reach the far side")


## A stretch of crevasse with open snow on both sides and nothing in the way: [centre,
## normal, half width]; narrow ones are at most about 31 wide, wide ones 52 and more.
func _crossing_spot(data: NelvarIceData, narrow: bool) -> Array:
	for c in data.crevasses.size():
		var crevasse := data.crevasses[c]
		var along := 60.0
		while along < crevasse.length() - 60.0:
			along += 8.0
			var half := crevasse.half_width_at(along)
			if (narrow and (half > 15.5 or half < 9.0)) or (not narrow and half < 26.0):
				continue
			if crevasse.direction_at(along - 40.0).dot(crevasse.direction_at(along + 40.0)) < 0.95:
				continue
			var near_bridge := false
			for bridge in crevasse.bridges:
				near_bridge = near_bridge or absf(bridge.along - along) < bridge.half_length + 120.0
			if near_bridge:
				continue
			var center := crevasse.point_at(along)
			if data.valley.signed_distance(center) < half + 220.0 or data.crevasse_depth(center) < half - 3.0:
				continue
			var lonely := true
			for o in data.crevasses.size():
				if o != c and NelvarFireData.polyline_distance(data.crevasses[o].points, center) < 220.0:
					lonely = false
			if not lonely:
				continue
			var a := crevasse.point_at(along - 14.0)
			var b := crevasse.point_at(along + 14.0)
			var normal := a.direction_to(b).orthogonal()
			var clear := true
			for side: float in [-1.0, 1.0]:
				var distance := half + BODY + 8.0
				while distance < half + 110.0:
					if not data.has_clearance(center + normal * side * distance, BODY + 4.0):
						clear = false
					distance += 8.0
			if clear:
				return [center, normal, half]
	return []


## Standing on thin ice breaks it and drops the player in the water; running over it
## leaves it whole; a hole freezes over again.
func _check_thin_ice(game: Node, data: NelvarIceData, player: NelvarPlayer) -> void:
	var patches: Array[NelvarEarthData.Radial] = []
	for lake in data.lakes:
		for patch in lake.thin:
			if data.thin_depth(patch.center) > 20.0 and data.has_clearance(patch.center, BODY + 6.0):
				patches.append(patch)
	_check(not patches.is_empty(), "No thin ice to stand on")
	if patches.is_empty():
		return
	var patch := patches[0]
	await _place(player, patch.center)
	player.health = player.max_health
	player.set("_invulnerability_left", 0.0)
	var plunges: int = game.plunges
	var cracks: int = game.cracks_made
	var holes: int = game.holes_broken
	for i in 120:
		await physics_frame
		if game.plunges > plunges:
			break
	_check(game.cracks_made > cracks, "Standing on thin ice did not crack it")
	_check(game.holes_broken > holes, "Thin ice did not break under a standing player")
	_check(game.plunges == plunges + 1, "The player did not fall into the hole")
	_check(not data.holes.is_empty() and data.hole_depth(patch.center) > 0.0, "No open hole where the ice broke")
	await create_timer(game.FALL_TIME + 0.6).timeout
	_check(not player.is_falling() and data.ice_at(player.global_position) == NelvarIceData.Surface.SNOW,
		"The player did not come back on the snow")
	_check(player.health < player.max_health, "The cold water did no damage")
	# A hole freezes over: open, then thin ice again, then gone into the patch.
	var hole: NelvarIceData.Hole = data.holes[data.holes.size() - 1]
	game.call("_update_holes", game.FREEZE_TIME * 0.85)
	_check(data.holes.has(hole) and not hole.is_open() and data.hole_depth(hole.center) < 0.0,
		"A hole did not freeze over")
	game.call("_update_holes", game.FREEZE_TIME * 0.2)
	_check(not data.holes.has(hole), "A frozen hole did not go")
	(game.get("_cracks") as Array).clear()
	# A run over the same patch leaves it whole.
	var route := _thin_route(data, patch)
	_check(not route.is_empty(), "No clear way over the thin ice")
	if route.is_empty():
		return
	var start: Vector2 = route[0]
	var direction: Vector2 = route[1]
	var end: Vector2 = route[2]
	await _place(player, start)
	cracks = game.cracks_made
	holes = game.holes_broken
	player.velocity = direction * player.speed
	await _push(player, direction, 1.0, false, 90, func() -> bool:
		return (player.global_position - end).dot(direction) > 0.0)
	_check((player.global_position - end).dot(direction) > -20.0, "The player did not get over the thin ice")
	_check(game.cracks_made == cracks and game.holes_broken == holes, "Thin ice broke under a running player")


## A straight way over a thin patch, clear of blocks: [start, direction, end].
func _thin_route(data: NelvarIceData, patch: NelvarEarthData.Radial) -> Array:
	for k in 8:
		var direction := Vector2.from_angle(TAU * k / 8.0)
		var start := patch.center - direction * (patch.reach() + 60.0)
		var end := patch.center + direction * (patch.reach() + 30.0)
		var free := true
		var step := 0.0
		while step < start.distance_to(end):
			if not data.has_clearance(start + direction * step, BODY + 6.0):
				free = false
				break
			step += 8.0
		if free:
			return [start, direction, end]
	return []


## Hoppers blown into a crevasse or an open hole die.
func _check_hoppers(game: Node, data: NelvarIceData) -> void:
	var wide := _crossing_spot(data, false)
	if not wide.is_empty():
		var center: Vector2 = wide[0]
		var normal: Vector2 = wide[1]
		var half: float = wide[2]
		var hopper := await _hopper(game, center + normal * (half + 40.0))
		hopper.call("apply_knockback", -normal * 900.0)
		await create_timer(0.8).timeout
		_check(not is_instance_valid(hopper) or hopper.call("is_dead"), "A hopper blown into a crevasse did not fall")
	var patch: NelvarEarthData.Radial = null
	for lake in data.lakes:
		for candidate in lake.thin:
			if data.has_clearance(candidate.center + Vector2(90.0, 0.0), 30.0):
				patch = candidate
	if patch != null:
		var hole := NelvarIceData.Hole.new()
		hole.center = patch.center
		data.holes.append(hole)
		var hopper := await _hopper(game, patch.center + Vector2(90.0, 0.0))
		hopper.call("apply_knockback", Vector2.LEFT * 900.0)
		await create_timer(0.8).timeout
		_check(not is_instance_valid(hopper) or hopper.call("is_dead"), "A hopper blown into a hole did not drown")
		data.holes.erase(hole)


func _hopper(game: Node, point: Vector2) -> Node2D:
	var hopper: Node2D = game.enemy_spawner.enemy_scene.instantiate()
	hopper.position = point
	hopper.set("ground", game.data)
	hopper.set("idle_time_min", 5.0)
	hopper.set("idle_time_max", 5.0)
	game.enemy_spawner.add_child(hopper)
	await physics_frame
	return hopper


## A blizzard over the player slows their moves and attacks; once it has gone they are
## as quick as before.
func _check_blizzard(game: Node, data: NelvarIceData, player: NelvarPlayer) -> void:
	await _place(player, data.spawn_position)
	var storm = game.storms[0]
	storm.from = data.spawn_position
	storm.to = data.spawn_position + Vector2(1.0, 0.0)
	storm.duration = 60.0
	storm.strength = 1.0
	storm.start = game.clock - 30.0
	for i in 70:
		await physics_frame
	_check(game.storm_level > 0.9, "The blizzard does not reach the player (%.2f)" % game.storm_level)
	_check(player.move_scale < 0.75 and player.attack_rate < 0.7,
		"The blizzard does not slow the player (move %.2f, attacks %.2f)" % [player.move_scale, player.attack_rate])
	_check(data.jump_scale_at(player.global_position) < 0.9, "Hoppers jump as far in a blizzard")
	var direction := _open_direction(data, player.global_position, 160.0, false)
	await _push(player, direction, 1.0, false, 30, func() -> bool: return false)
	_check(player.velocity.length() < player.speed * 0.75, "The player walks at full speed in a blizzard")
	for name: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(name)
	storm.start = game.clock + 100000.0
	for i in 70:
		await physics_frame
	_check(is_equal_approx(player.move_scale, 1.0) and is_equal_approx(player.attack_rate, 1.0),
		"The player stays slow after the blizzard")


## Walking over the snow leaves marks there.
func _check_marks(game: Node, data: NelvarIceData, player: NelvarPlayer) -> void:
	var marks: NelvarSnowMarks = game.snow_marks
	await _place(player, data.spawn_position)
	var stamps := marks.stamps
	var direction := _open_direction(data, data.spawn_position, 160.0, false)
	await _push(player, direction, 1.0, false, 30, func() -> bool: return false)
	_check(marks.stamps > stamps + 5, "Walking over the snow left no marks")
	_check(marks.fresh_near(player.global_position, 60.0) > 0, "No fresh marks behind the player")
	_check(marks.texture() != null, "The marks have no texture for the floor")


## Standing over a watching creature opens its eye.
func _check_eye(game: Node, data: NelvarIceData, player: NelvarPlayer) -> void:
	for node in game.depths.frozen_nodes:
		if not node.creature.eye:
			continue
		var over: Vector2 = node.global_position
		if not data.has_clearance(over, BODY) or data.thin_depth(over) > -40.0:
			continue
		await _place(player, over)
		for i in 30:
			player.global_position = over
			player.velocity = Vector2.ZERO
			await physics_frame
		for i in 60:
			player.global_position = node.global_position
			player.velocity = Vector2.ZERO
			await physics_frame
			if node.is_eye_open():
				break
		_check(node.is_eye_open(), "A frozen creature did not open its eye under the player")
		return


## A seed whose valley has a wide and a narrow stretch of crevasse to cross.
func _scene_seed() -> int:
	var generator := NelvarIceGenerator.new()
	for i in 60:
		var world_seed := 20261124 + i * 104729
		var data := generator.generate(NelvarIceConfig.new(), world_seed)
		if data != null and not _crossing_spot(data, true).is_empty() and not _crossing_spot(data, false).is_empty():
			return world_seed
	return 20261124


func _place(player: NelvarPlayer, point: Vector2) -> void:
	for name: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(name)
	player.global_position = point
	player.velocity = Vector2.ZERO
	for i in 4:
		await physics_frame
		player.global_position = point
		player.velocity = Vector2.ZERO
	await physics_frame


## Holds the keys towards `direction` (any angle) for up to `frames`, until `done`.
func _push(player: NelvarPlayer, direction: Vector2, strength: float, run: bool, frames: int,
		done: Callable) -> void:
	var d := direction.normalized() * strength
	var amounts := {"move_right": d.x, "move_left": -d.x, "move_down": d.y, "move_up": -d.y}
	for name: String in amounts:
		var amount: float = amounts[name]
		if amount > 0.001:
			Input.action_press(name, amount)
		else:
			Input.action_release(name)
	for frame in frames:
		if run:
			player.set("_is_running", true)
		await physics_frame
		if done.call():
			break
	for name: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(name)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition and _failures.size() < 30:
		_failures.append(message)
