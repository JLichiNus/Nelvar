extends SceneTree
## The giant forest, Земля 2: the layout (the clearings joined by the trails, roots crossing
## the trails only where they dip under them, room for a hopper between any two solid
## things, the floor walkable everywhere from the start, the start on a clearing with a
## giant right north of it, the hazards off the trails and the clearings' middles, the ponds
## and the tunnel never on the only way, a way over each pond, the arches lying across the
## screen and wider than a passage, the same layout for the same seed), the light map
## against the queries, the art (every kind paints, a root's pieces fit together), the start
## setting, and the real scene: loose earth gives under a stander and holds a runner, the
## water drops the player, a lily pad holds, a raft carries exactly its shift and a small
## one sinks, resin halves the speed, a flytrap snaps after its warning and spares a flier
## and a shot snaps it, a shot bursts a puffball into a cloud that hurts and the wave drives
## it, an acorn strikes only in its circle and only after its shadow, hoppers die in the
## water, a pit or a trap and stick in resin, a trunk thins out while the player is behind.
## Run: godot --headless --path . --script tests/test_thicket.gd -- --seeds=6

const Kind = NelvarEarthData.Kind
const Part = NelvarThicketData.Part
const State = NelvarThicketData.TrapState
const BODY := NelvarPlayer.BODY_RADIUS
const PIXEL := NelvarEarthData.PIXEL
## A hopper's collision radius and a little to spare.
const HOPPER := 20.0
const SCENE_SEED := 20261127

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var count := 6
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			count = maxi(1, argument.trim_prefix("--seeds=").to_int())
	var config := NelvarThicketConfig.new()
	var generator := NelvarThicketGenerator.new()
	var started := Time.get_ticks_msec()
	var roots := 0
	var arches := 0
	for index in count:
		var world_seed := 20261127 + index * 7919
		var data := generator.generate(config, world_seed)
		_check(data != null, "Seed %d: generation failed" % world_seed)
		if data == null:
			continue
		roots += data.roots.size()
		arches += data.arch_count()
		_check_layout(data, config)
		if index < 2:
			_check(_fingerprint(generator.generate(config, world_seed)) == _fingerprint(data),
				"Seed %d: the layout is not reproducible" % world_seed)
		if index < 3:
			_check_walkable(data)
		if index == 0:
			_check_field(data)
			_check_art(data)
	print("Thicket: %d seeds in %.1f s · %.1f roots and %.1f arches each" % [count,
		float(Time.get_ticks_msec() - started) / 1000.0, float(roots) / count, float(arches) / count])
	_check_settings()
	await _check_scene()
	if _failures.is_empty():
		print("PASS: %d checks; the giant forest's layout, floor, art, hazards and the scene behave" % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FAIL: %d failures / %d checks" % [_failures.size(), _checks])
		quit(1)


# --- Layout ----------------------------------------------------------------------------

func _check_layout(data: NelvarThicketData, config: NelvarThicketConfig) -> void:
	var context := "Seed %d: " % data.world_seed
	var inner := data.inner_giants().size()
	_check(inner >= config.giants.x - 1 and inner <= config.giants.y and data.giants.size() - inner >= config.ring_giants.x,
		context + "%d giants inside, %d in the ring" % [inner, data.giants.size() - inner])
	_check(data.clearings.size() >= 5 and data.fallen != null and not data.ponds.is_empty(),
		context + "%d clearings, fallen giant %s, %d ponds" % [data.clearings.size(), data.fallen != null, data.ponds.size()])
	# Every clearing joined to the start by the trails.
	var parent := []
	for i in data.clearings.size():
		parent.append(i)
	var find := func(i: int, f: Callable) -> int:
		return i if parent[i] == i else f.call(parent[i], f)
	for trail in data.trails:
		var ends: Array[int] = []
		for end in [trail.points[0], trail.points[trail.points.size() - 1]]:
			for c in data.clearings.size():
				if end.distance_to(data.clearings[c].center) < 1.0:
					ends.append(c)
		if ends.size() == 2:
			parent[find.call(ends[0], find)] = find.call(ends[1], find)
	var apart := 0
	for c in data.clearings.size():
		if find.call(c, find) != find.call(0, find):
			apart += 1
	_check(apart == 0, context + "%d clearings not joined to the start by the trails" % apart)
	# The trails keep off the water, the trunks and the fallen giant.
	var wet := 0
	for trail in data.trails:
		for point in trail.points:
			if data.pond_depth(point) > -trail.half_width or data.giant_at(point, trail.half_width) != null \
					or (data.fallen != null and data.fallen.covers(point, trail.half_width)):
				wet += 1
	_check(wet == 0, context + "%d trail points in the water, a trunk or the fallen giant" % wet)
	# Roots cross the trails only where they dip under them.
	var blocking := 0
	for root in data.roots:
		for i in root.points.size() - 1:
			if NelvarThicketData.segment_layer(root, i) == 0:
				continue
			for point in [root.points[i], root.points[i].lerp(root.points[i + 1], 0.5), root.points[i + 1]]:
				if data.distance_to_trails(point) < root.widths[i] * 0.5 - 2.0:
					blocking += 1
	_check(blocking == 0, context + "%d root walls on a trail" % blocking)
	# The start, the giant right north of it.
	var start := data.clearings[data.start_clearing]
	var north := false
	for giant in data.giants:
		var offset := data.spawn_position - giant.center
		if absf(offset.x) < giant.radius and offset.y >= 500.0 and offset.y <= 700.0:
			north = true
	_check(data.spawn_position.distance_to(start.center) < start.radius and north
		and data.has_clearance(data.spawn_position, BODY + 10.0),
		context + "the start is not clear on its clearing with a giant 500–700 north of it")
	# Hazards off the trails and the clearings' middles.
	var astray := 0
	for trap in data.flytraps:
		if data.distance_to_trails(trap.center) < trap.radius or (not trap.garden and _in_middle(data, trap.center, trap.radius)):
			astray += 1
	for puffball in data.puffballs:
		if data.distance_to_trails(puffball.center) < puffball.radius or _in_middle(data, puffball.center, puffball.radius):
			astray += 1
	for patch in data.loose:
		if data.distance_to_trails(patch.center) < patch.reach() or _in_middle(data, patch.center, 0.0):
			astray += 1
	for pool in data.resin:
		if data.distance_to_trails(pool.center) < pool.radius or _in_middle(data, pool.center, 0.0):
			astray += 1
	_check(astray == 0, context + "%d hazards on a trail or in a clearing's middle" % astray)
	# A way over every pond.
	for p in data.ponds.size():
		var lilies: Array[NelvarThicketData.Lily] = []
		var rafts: Array[NelvarThicketData.Raft] = []
		for lily in data.lilies:
			if lily.pond == p:
				lilies.append(lily)
		for raft in data.rafts:
			if raft.pond == p:
				rafts.append(raft)
		_check(NelvarThicketData.crossable(data.ponds[p], lilies, rafts), context + "no way over pond %d" % p)
	# Arches lie across the screen and leave more than a passage under them.
	var arches := 0
	for root in data.roots:
		var run := 0
		for k in root.parts.size():
			if root.parts[k] == Part.ARCH:
				run += 1
				var direction := root.points[k].direction_to(root.points[mini(k + 1, root.points.size() - 1)])
				if absf(direction.y) > sin(deg_to_rad(35.0)) + 0.02:
					arches += 1
			elif run > 0:
				if (run + 1) * NelvarThicketData.ROOT_STEP < config.passage_width + 10.0:
					arches += 1
				run = 0
	_check(arches == 0, context + "%d arches steep or narrower than a passage" % arches)
	# Room for a hopper between any two solid things, roots and trunks.
	var tight := _tight(data, config.passage_width - 6.0)
	_check(tight.is_empty(), context + "no room for a hopper: " + ", ".join(tight.slice(0, 3)))
	# Things where they belong.
	var misplaced := 0
	for thing in data.things:
		if data.valley.signed_distance(thing.position) < 0.0:
			misplaced += 1
		elif thing.kind != Kind.LILY and thing.kind != Kind.REEDS and data.pond_depth(thing.position) > 0.0:
			misplaced += 1
		elif thing.solid and data.distance_to_trails(thing.position) < (thing as NelvarThicketData.Item).spread() * 0.5:
			misplaced += 1
	_check(misplaced == 0, context + "%d things out of place" % misplaced)


func _in_middle(data: NelvarThicketData, point: Vector2, radius: float) -> bool:
	for clearing in data.clearings:
		if point.distance_to(clearing.center) < clearing.radius * 0.5 + radius * 0.5:
			return true
	return false


## Pairs of solid things (roots' walls, trunks, solid things) closer than `gap`.
func _tight(data: NelvarThicketData, gap: float) -> Array[String]:
	var found: Array[String] = []
	var solids := []
	for root in data.roots:
		for i in root.points.size() - 1:
			if NelvarThicketData.segment_layer(root, i) != 0:
				solids.append(["root %d" % root.id, root.points[i], root.points[i + 1], minf(root.widths[i], root.widths[i + 1]) * 0.5, root])
	for thing in data.things:
		if thing.solid:
			solids.append(["%s %d" % [Kind.keys()[thing.kind], thing.id], thing.position, thing.position, thing.spread(), null])
	for giant in data.inner_giants():
		solids.append(["giant %d" % giant.id, giant.center, giant.center, giant.radius, giant])
	# Filed by cell (each solid reaches at most a giant's radius past its cell).
	var cells := {}
	for i in solids.size():
		var key := Vector2i(((solids[i][1] as Vector2) / 256.0).floor())
		if not cells.has(key):
			cells[key] = []
		cells[key].append(i)
	for a in solids.size():
		var p: Array = solids[a]
		var key := Vector2i(((p[1] as Vector2) / 256.0).floor())
		var reach := 3
		for y in range(key.y - reach, key.y + reach + 1):
			for x in range(key.x - reach, key.x + reach + 1):
				for b: int in cells.get(Vector2i(x, y), []):
					if b <= a:
						continue
					var q: Array = solids[b]
					_pair(data, p, q, gap, found)
	return found


func _pair(data: NelvarThicketData, p: Array, q: Array, gap: float, found: Array[String]) -> void:
	if _related(data, p[4], q[4], p, q):
		return
	var gap_now := _segment_gap(p[1], p[2], q[1], q[2]) - float(p[3]) - float(q[3])
	if gap_now < gap:
		found.append("%s–%s (%.0f)" % [p[0], q[0], gap_now])


## Parts of one root, a root and its own trunk or its branch at the fork, two roots of one
## giant by its trunk: these may touch.
func _related(data: NelvarThicketData, a: Variant, b: Variant, p: Array, q: Array) -> bool:
	if a is NelvarThicketData.Root and b is NelvarThicketData.Root:
		var ra: NelvarThicketData.Root = a
		var rb: NelvarThicketData.Root = b
		if ra == rb or ra.parent == rb.id or rb.parent == ra.id:
			return true
		if ra.giant == rb.giant:
			var giant := data.giants[ra.giant]
			return giant.edge_distance(p[1]) < 200.0 or giant.edge_distance(q[1]) < 200.0
		return false
	if a is NelvarThicketData.Root and b is NelvarThicketData.Giant:
		return (a as NelvarThicketData.Root).giant == (b as NelvarThicketData.Giant).id
	if b is NelvarThicketData.Root and a is NelvarThicketData.Giant:
		return (b as NelvarThicketData.Root).giant == (a as NelvarThicketData.Giant).id
	return false


func _segment_gap(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	var best := INF
	for pair in [[a, c, d], [b, c, d], [c, a, b], [d, a, b]]:
		best = minf(best, (pair[0] as Vector2).distance_to(Geometry2D.get_closest_point_to_segment(pair[0], pair[1], pair[2])))
	return best


## The floor (out of the water, clear of everything solid by a body's width) is one piece
## reached from the start.
func _check_walkable(data: NelvarThicketData) -> void:
	var cell := 24.0
	var rect := Rect2(data.valley.center - data.valley.axes * 1.15, data.valley.axes * 2.3)
	var size := Vector2i((rect.size / cell).ceil())
	var free := PackedByteArray()
	free.resize(size.x * size.y)
	var total := 0
	for y in size.y:
		for x in size.x:
			var point := rect.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell
			if data.pond_depth(point) < -BODY and not data.is_blocked(point, BODY):
				free[y * size.x + x] = 1
				total += 1
	var start := Vector2i(((data.spawn_position - rect.position) / cell).floor())
	var queue: Array[Vector2i] = [start]
	var seen := {start: true}
	var head := 0
	while head < queue.size():
		var at := queue[head]
		head += 1
		for move: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := at + move
			if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y or seen.has(next):
				continue
			if free[next.y * size.x + next.x] == 1:
				seen[next] = true
				queue.append(next)
	var cut := total - queue.size() + 1
	_check(cut <= total / 200, "Seed %d: %d of %d floor cells cannot be reached on foot from the start" % [
		data.world_seed, cut, total])


func _fingerprint(data: NelvarThicketData) -> String:
	var parts: Array[String] = [str(data.spawn_position), str(data.giants.size()), str(data.roots.size())]
	for giant in data.giants:
		parts.append("%.1f,%.1f,%.1f" % [giant.center.x, giant.center.y, giant.radius])
	for root in data.roots:
		parts.append("%d:%s" % [root.points.size(), str(root.parts)])
	for thing in data.things:
		parts.append("%d@%.1f,%.1f" % [thing.kind, thing.position.x, thing.position.y])
	for trap in data.flytraps:
		parts.append(str(trap.center))
	return ",".join(parts).md5_text()


# --- The floor's maps ----------------------------------------------------------------------

func _check_field(data: NelvarThicketData) -> void:
	var field := NelvarThicketField.build(data)
	var wrong := 0
	var checked := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = data.world_seed
	var cell := float(PIXEL * NelvarThicketField.LIGHT_SCALE)
	for i in 3000:
		var texel := Vector2i(rng.randi_range(0, field.light_size.x - 1), rng.randi_range(0, field.light_size.y - 1))
		var point := (Vector2(field.light_origin + texel) + Vector2(0.5, 0.5)) * cell
		var light := field.light_at(texel)
		checked += 1
		if absf(light.r - data.sun_at(point)) > 0.01 or absf(light.g - data.damp_at(point)) > 0.01:
			wrong += 1
			continue
		var loose := data.loose_depth(point)
		if absf(loose) > 3.0 and is_finite(loose) and (light.b8 > 128) != (loose > 0.0) and loose > -250.0:
			wrong += 1
		var resin := data.resin_depth(point)
		if absf(resin) > 3.0 and is_finite(resin) and (light.a8 > 128) != (resin > 0.0) and resin > -250.0:
			wrong += 1
	_check(wrong == 0, "The light map disagrees with sun_at, damp_at, is_loose or resin_at at %d of %d texels" % [wrong, checked])


# --- The art ------------------------------------------------------------------------------

func _check_art(data: NelvarThicketData) -> void:
	var painter := NelvarThicketPainter.new()
	var giants := NelvarGiantPainter.new()
	var seen := {}
	var blank := 0
	for thing in data.things:
		var key := "%d:%d" % [thing.kind, thing.variant]
		if seen.has(key):
			continue
		seen[key] = true
		var art := painter.paint(thing)
		if art == null or art.image == null or art.image.is_invisible():
			blank += 1
	for kind in [Kind.ACORN, Kind.GIANT_MUSHROOM, Kind.GRASS_BLADES, Kind.CLOVER, Kind.GIANT_FLOWER, Kind.LEAF, Kind.TWIG,
			Kind.SHELL, Kind.FEATHER, Kind.DEW, Kind.AMBER, Kind.BONES, Kind.RIB]:
		var thing := NelvarThicketData.Item.new()
		thing.kind = kind
		thing.radius = 30.0
		thing.size = Vector2(160.0, 180.0)
		thing.appearance_seed = 7
		var art := painter.paint(thing)
		if art == null or art.image == null or art.image.is_invisible():
			blank += 1
	for species in 4:
		for giant in data.giants:
			if giant.species == species:
				var art := giants.paint_trunk(giant)
				if art.image == null or art.image.is_invisible():
					blank += 1
				break
	for trap: NelvarThicketData.Flytrap in data.flytraps.slice(0, 1):
		for state in 4:
			if painter.paint_flytrap(trap, state).image.is_invisible():
				blank += 1
	for puffball: NelvarThicketData.Puffball in data.puffballs.slice(0, 1):
		for burst in [false, true]:
			if painter.paint_puffball(puffball, burst).image.is_invisible():
				blank += 1
	for raft: NelvarThicketData.Raft in data.rafts.slice(0, 1):
		if painter.paint_raft(raft).image.is_invisible():
			blank += 1
	var fallen := giants.paint_fallen(data.fallen)
	var plate := giants.paint_plate(data.fallen)
	_check(blank == 0 and not fallen.is_empty() and plate != null, "%d things painted blank (or the fallen giant)" % blank)
	# A root's pieces fit together: no pixel painted twice, none of its line left out.
	var seams := 0
	for root: NelvarThicketData.Root in data.roots.slice(0, 4):
		var pieces := giants.paint_root(root, data.giants[root.giant].species)
		var taken := {}
		for piece in pieces:
			var corner := Vector2i(((piece.origin + piece.art.local_rect.position) / PIXEL).round())
			var image := piece.art.image
			for y in image.get_height():
				for x in image.get_width():
					if image.get_pixel(x, y).a > 0.0:
						var at := corner + Vector2i(x, y)
						if taken.has(at):
							seams += 1
						taken[at] = true
		for k in range(0, root.points.size(), 2):
			if root.parts[k] == Part.PASS:
				continue
			var top := root.points[k] / PIXEL - Vector2(0.0, root.heights[k] * 0.5)
			if not taken.has(Vector2i(top.floor())):
				seams += 1
	_check(seams == 0, "Roots' pieces overlap or leave gaps (%d pixels)" % seams)


# --- The start setting -------------------------------------------------------------------

## The start options exclude each other; «Играть» opens the forest when its option is on.
func _check_settings() -> void:
	var settings: Node = root.get_node("GameSettings")
	var path: String = settings.PATH
	var saved := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	var flags := ["start_in_void", "start_on_earth", "start_on_earth2", "start_in_fire", "start_on_ice", "start_in_fire2",
		"start_on_ice2"]
	var was := []
	for flag in flags:
		was.append(settings.get(flag))
	var clashes := 0
	for i in flags.size():
		settings.call("set_" + flags[i], true)
		for j in flags.size():
			if bool(settings.get(flags[j])) != (i == j):
				clashes += 1
	settings.set_start_on_earth2(true)
	settings.set_start_on_earth2(false)
	for flag in flags:
		if settings.get(flag):
			clashes += 1
	_check(clashes == 0, "The start options do not exclude each other (%d clashes)" % clashes)
	for i in flags.size():
		settings.set(flags[i], was[i])
	if saved.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	var menu := FileAccess.get_file_as_string("res://ui/main_menu/main_menu.gd")
	_check(menu.contains("res://scenes/earth2.tscn") and menu.contains("GameSettings.start_on_earth2"),
		"«Играть» does not open the giant forest")
	var panel: Node = load("res://ui/main_menu/settings_panel.tscn").instantiate()
	var check: Node = panel.get_node_or_null("Rows/Body/PageColumn/Scroll/Pages/DevPage/StartOnEarth2")
	var rows: Node = panel.get_node("Rows/Body/PageColumn/Scroll/Pages/DevPage")
	_check(check is CheckButton and (check as CheckButton).text == "Запускать игру на Земле"
		and check.get_index() == rows.get_node("StartOnIce2").get_index() + 1,
		"The developer menu has no Земля 2 start right under Лёд 2")
	panel.free()
	var hint := FileAccess.get_file_as_string("res://ui/main_menu/settings_panel.tscn")
	_check(hint.contains("«Играть» откроет исполинский лес (Земля 2)"), "The developer menu does not say «Играть» opens the forest")


# --- The scene -------------------------------------------------------------------------------

func _check_scene() -> void:
	var game = load("res://scenes/earth2.tscn").instantiate()
	game.set_meta("seed_override", SCENE_SEED)
	root.add_child(game)
	# The player's attacks join the current scene.
	current_scene = game
	_check(game.is_painting(), "The forest waited for all its art before the first frame")
	game.finish_painting()
	await physics_frame
	await physics_frame
	var data: NelvarThicketData = game.data
	var player: NelvarPlayer = game.player
	_check(data != null, "The forest scene did not generate")
	if data == null:
		return
	var misplaced := 0
	for enemy in get_nodes_in_group("enemies"):
		if not data.has_clearance(enemy.global_position, 18.0):
			misplaced += 1
		enemy.queue_free()
	_check(misplaced == 0, "%d enemies appeared in a trunk, a root, the water or a hazard" % misplaced)
	game.enemy_spawner.set_process(false)
	await physics_frame
	_check(game.thing_nodes.size() == data.things.size() and game.trunk_nodes.size() == data.giants.size()
		and game.root_pieces.size() >= data.roots.size() and not game.fallen_pieces.is_empty(),
		"Some things, trunks, roots or the fallen giant are missing")
	await _check_loose(game, data, player)
	await _check_water(game, data, player)
	await _check_resin(game, data, player)
	await _check_flytrap(game, data, player)
	await _check_puffball(game, data, player)
	await _check_acorn(game, data, player)
	await _check_hoppers(game, data, player)
	await _check_ants(game, player)
	await _check_fade(game, data, player)
	var key := InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	game._unhandled_input(key)
	_check(game.get("_outlines").visible, "F3 does not show the outlines")
	game.queue_free()
	await process_frame


## Loose earth: standing opens a pit and drops the player (back hurt); running over it holds.
func _check_loose(game: Node, data: NelvarThicketData, player: NelvarPlayer) -> void:
	var spot := Vector2.INF
	for patch in data.loose:
		for k in 24:
			var point := patch.point_at(TAU * k / 24.0, 40.0).lerp(patch.center, 0.5)
			if data.loose_depth(point) > 30.0 and not data.is_blocked(point, BODY):
				spot = point
				break
		if spot.is_finite():
			break
	if not spot.is_finite():
		return
	await _heal(player)
	await _place(player, data.spawn_position)
	await _place(player, spot)
	var health := player.health
	var falls: int = game.pit_falls
	for i in 75:
		await physics_frame
		player.velocity = Vector2.ZERO
	_check(game.pit_falls == falls + 1 and data.pit_at(spot, 10.0) != null, "Standing on loose earth did not open a pit")
	await create_timer(1.2).timeout
	_check(not player.is_falling() and player.health <= health - game.PIT_DAMAGE + 0.01
		and player.global_position.distance_to(spot) > 60.0, "The player did not come back hurt from the pit")
	# A run across stays up.
	await _heal(player)
	var patch: NelvarEarthData.Radial = null
	for candidate in data.loose:
		if candidate.center.distance_to(spot) > candidate.reach() + 100.0:
			patch = candidate
			break
	if patch != null:
		var from := patch.center + Vector2(-patch.axes.x - 60.0, 0.0)
		if not data.is_blocked(from, BODY) and not data.is_blocked(patch.center + Vector2(patch.axes.x + 60.0, 0.0), BODY):
			await _place(player, from)
			falls = game.pit_falls
			await _push(player, Vector2.RIGHT, 1.0, true, 60, func() -> bool: return false)
			_check(game.pit_falls == falls, "Running over loose earth made it give")
	data.pits.clear()


## The water drops the player; a lily pad holds; a big raft carries exactly its shift; a
## small one sinks under them.
func _check_water(game: Node, data: NelvarThicketData, player: NelvarPlayer) -> void:
	await _heal(player)
	var pond := data.ponds[0]
	var water := Vector2.INF
	for k in 64:
		var point := pond.point_at(TAU * k / 64.0, 60.0)
		if data.water_at(point, game.clock) and data.water_at(point, game.clock + 0.3):
			water = point
			break
	if water.is_finite():
		var plunges: int = game.plunges
		await _place(player, data.spawn_position)
		await _place(player, water)
		await create_timer(0.35).timeout
		_check(game.plunges == plunges + 1, "Stepping into the water did not drop the player")
		await create_timer(1.0).timeout
	if not data.lilies.is_empty():
		var lily := data.lilies[0]
		var plunges: int = game.plunges
		await _place(player, lily.center)
		await create_timer(0.6).timeout
		_check(game.plunges == plunges and not player.is_falling(), "A lily pad did not hold the player")
	var big: NelvarThicketData.Raft = null
	var small: NelvarThicketData.Raft = null
	for raft in data.rafts:
		if not raft.small() and big == null:
			big = raft
		if raft.small() and small == null:
			small = raft
	if big != null:
		await _heal(player)
		var at := big.position_at(game.clock)
		await _place(player, at)
		var from: Vector2 = player.global_position
		var raft_from: Vector2 = big.position_at(game.clock)
		for i in 40:
			await physics_frame
		var moved: Vector2 = player.global_position - from
		var shift: Vector2 = big.position_at(game.clock) - raft_from
		_check(moved.distance_to(shift) < 3.0 and shift.length() > 2.0,
			"A raft did not carry the player by its shift (%.1f moved, raft %.1f)" % [moved.length(), shift.length()])
	if small != null:
		await _heal(player)
		var plunges: int = game.plunges
		await _place(player, small.position_at(game.clock))
		for i in 150:
			await physics_frame
			if game.plunges > plunges:
				break
			if small.sink < 0.5 and data.carrier_at(player.global_position, game.clock) == small:
				player.global_position = small.position_at(game.clock)
		_check(small.sink > 0.0 or game.plunges > plunges, "A small raft did not sink under the player")
		await create_timer(1.2).timeout
	await _place(player, data.spawn_position)


## Resin halves the walking speed.
func _check_resin(game: Node, data: NelvarThicketData, player: NelvarPlayer) -> void:
	var spot := Vector2.INF
	for pool in data.resin:
		if pool.radius > 70.0 and not data.is_blocked(pool.center, BODY) and data.pit_at(pool.center) == null:
			spot = pool.center
			break
	if not spot.is_finite():
		return
	await _heal(player)
	await _place(player, spot)
	var fastest := [0.0]
	await _push(player, Vector2.RIGHT, 1.0, false, 30, func() -> bool:
		if data.resin_at(player.global_position):
			fastest[0] = maxf(fastest[0], player.velocity.length())
		return false)
	_check(fastest[0] > 0.35 * player.speed and fastest[0] < 0.6 * player.speed,
		"In resin the player walks at %.0f (not about half of %.0f)" % [fastest[0], player.speed])


## A flytrap snaps after its warning and bites; a flier does not set it off; a shot snaps it.
func _check_flytrap(game: Node, data: NelvarThicketData, player: NelvarPlayer) -> void:
	var traps: NelvarFlytraps = game.flytraps
	if traps.traps.is_empty():
		return
	var trap: NelvarFlytraps.Trap = traps.traps[0]
	for candidate in traps.traps:
		if not data.is_blocked(candidate.spec.center, BODY):
			trap = candidate
			break
	await _heal(player)
	await _place(player, trap.spec.center)
	var health := player.health
	await create_timer(0.3).timeout
	_check(trap.spec.state == State.TRIGGERED, "A flytrap did not tremble under the player")
	await create_timer(0.3).timeout
	_check(trap.spec.state == State.CLOSED and absf(health - player.health - NelvarFlytraps.DAMAGE) < 0.5,
		"A flytrap did not snap after its warning and bite for %d" % NelvarFlytraps.DAMAGE)
	# Open it again, then fly over it.
	trap.spec.state = State.OPEN
	trap.spec.timer = 0.0
	await _place(player, data.spawn_position)
	await create_timer(1.2).timeout
	player.call("_try_speed_boost")
	await _place(player, trap.spec.center)
	await create_timer(0.7).timeout
	_check(trap.spec.state == State.OPEN, "A flytrap snapped at a flier")
	await create_timer(3.2).timeout
	# A shot from afar snaps it.
	await _place(player, trap.spec.center + Vector2(0.0, 240.0))
	trap.spec.state = State.OPEN
	trap.spec.timer = 0.0
	trap.hit.collision_layer = 8
	trap.body.collision_layer = 0
	await physics_frame
	_shoot(game, player, trap.spec.center + Vector2(0.0, 240.0), Vector2.UP)
	for i in 30:
		await physics_frame
	_check(trap.spec.state == State.CLOSED, "A shot did not snap an open flytrap")


## A shot bursts a puffball into a cloud that hurts; the wave drives the cloud away.
func _check_puffball(game: Node, data: NelvarThicketData, player: NelvarPlayer) -> void:
	var balls: NelvarPuffballs = game.puffballs
	if balls.balls.is_empty():
		return
	var ball: NelvarPuffballs.Ball = balls.balls[0]
	var from := Vector2.INF
	for candidate in balls.balls:
		for direction: Vector2 in [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
			var point := candidate.spec.center + direction * (candidate.spec.radius + 200.0)
			if not data.is_blocked(point, BODY) and data.pond_depth(point) < -40.0:
				ball = candidate
				from = point
				break
		if from.is_finite():
			break
	if not from.is_finite():
		return
	await _heal(player)
	await _place(player, from)
	_shoot(game, player, from, from.direction_to(ball.spec.center))
	for i in 30:
		await physics_frame
	_check(not ball.spec.whole() and not balls.clouds.is_empty(), "A shot did not burst a puffball")
	if balls.clouds.is_empty():
		return
	var cloud: NelvarPuffballs.Cloud = balls.clouds[balls.clouds.size() - 1]
	await create_timer(0.7).timeout
	var health := player.health
	await _place(player, cloud.center)
	await create_timer(1.1).timeout
	_check(player.health < health, "The spore cloud did not hurt the player")
	var center := cloud.center
	await _place(player, center + Vector2(-220.0, 0.0))
	var wave: Node = player.wave_scene.instantiate()
	game.add_child(wave)
	wave.call("launch", player.global_position, Vector2.RIGHT)
	await create_timer(0.8).timeout
	_check(cloud.center.distance_to(center) > 60.0 and cloud.center.x > center.x, "The wave did not drive the spore cloud")


## An acorn strikes only in its circle and only after its shadow.
func _check_acorn(game: Node, data: NelvarThicketData, player: NelvarPlayer) -> void:
	await _heal(player)
	await create_timer(1.1).timeout
	var spot := data.spawn_position
	await _place(player, spot)
	var falling: NelvarFalling = game.falling
	var health := player.health
	var far := falling.add_drop(NelvarFalling.What.ACORN, spot + Vector2(120.0, 0.0), 42.0, game.clock)
	var near := falling.add_drop(NelvarFalling.What.ACORN, spot, 42.0, game.clock)
	await create_timer(0.8).timeout
	_check(player.health == health and not near.struck, "An acorn hurt before its shadow had grown")
	await create_timer(0.5).timeout
	_check(near.struck and far.struck and absf(health - player.health - NelvarFalling.PLAYER_DAMAGE) < 0.5,
		"An acorn did not strike in its circle (or one outside it struck too)")
	for item in falling.lying:
		item.queue_free()
	falling.lying.clear()


## Hoppers die in the water, a pit or a flytrap, and stick in resin.
func _check_hoppers(game: Node, data: NelvarThicketData, player: NelvarPlayer) -> void:
	var scene := load("res://enemies/hopper/hopper.tscn") as PackedScene
	await _place(player, data.spawn_position)
	var spots: Array[Vector2] = []
	var pond := data.ponds[0]
	for k in 32:
		var point := pond.point_at(TAU * k / 32.0, 70.0)
		if data.water_at(point, game.clock) and data.water_at(point, game.clock + 1.0):
			spots.append(point)
			break
	var pit: NelvarThicketData.Pit = game.call("open_pit", data.spawn_position + Vector2(600.0, 0.0))
	spots.append(pit.center)
	var hoppers := []
	for spot in spots:
		var hopper := scene.instantiate() as Node2D
		hopper.position = spot
		game.enemy_spawner.add_child(hopper)
		hoppers.append(hopper)
	var stuck: Node2D = null
	for pool in data.resin:
		var hopper := scene.instantiate() as Node2D
		hopper.position = pool.center
		game.enemy_spawner.add_child(hopper)
		stuck = hopper
		break
	for i in 6:
		await physics_frame
	var alive := 0
	for hopper in hoppers:
		if is_instance_valid(hopper) and not hopper.call("is_dead"):
			alive += 1
	_check(alive == 0, "%d hoppers survived the water or a pit" % alive)
	if stuck != null and is_instance_valid(stuck):
		_check(float(stuck.get("_hold_time_left")) > 0.0, "A hopper in resin did not stick")
		stuck.queue_free()
	data.pits.clear()
	# One thrown into an open trap is eaten.
	var traps: NelvarFlytraps = game.flytraps
	for trap in traps.traps:
		if trap.spec.state == State.OPEN:
			var hopper := scene.instantiate() as Node2D
			hopper.position = trap.spec.center
			game.enemy_spawner.add_child(hopper)
			hopper.set("_idle_time_left", 5.0)
			await create_timer(0.7).timeout
			_check(not is_instance_valid(hopper) or hopper.call("is_dead"), "A hopper in a flytrap was not eaten")
			break


## A trunk thins out while the player is behind it, and comes back.
## Ants do not step aside: the player standing on one squashes it and leaves a smear.
func _check_ants(game: Node, player: NelvarPlayer) -> void:
	var ants: NelvarAnts = game.ants
	var column: NelvarAnts.Column = null
	var index := -1
	for c in ants.columns:
		for i in c.count:
			if ants.is_walking(c, i):
				column = c
				index = i
				break
		if column != null:
			break
	_check(column != null, "No ant walks a trail")
	if column == null:
		return
	var splats := ants.splats.size()
	player.global_position = ants.ant_position(column, index)
	for i in 3:
		await process_frame
		player.global_position = ants.ant_position(column, index)
	_check(column.alive[index] == 0 and ants.splats.size() > splats, "The player stood on an ant and it was not squashed")


func _check_fade(game: Node, data: NelvarThicketData, player: NelvarPlayer) -> void:
	var trunk: NelvarGiantTrunk = game.trunk_nodes[0]
	var giant := trunk.giant
	var behind := giant.center + Vector2(0.0, -giant.radius - 60.0)
	if data.is_blocked(behind, BODY):
		return
	await _place(player, behind)
	await create_timer(0.4).timeout
	_check(trunk.fade > 0.95, "The trunk did not thin out with the player behind it")
	await _place(player, data.spawn_position)
	await create_timer(0.6).timeout
	_check(trunk.fade < 0.05, "The trunk did not come back")


# --- Helpers -----------------------------------------------------------------------------

func _shoot(game: Node, player: NelvarPlayer, from: Vector2, direction: Vector2) -> void:
	var shot: Node = player.projectile_scene.instantiate()
	game.add_child(shot)
	shot.call("launch", from + direction * 30.0, direction)


func _heal(player: NelvarPlayer) -> void:
	await create_timer(1.1).timeout
	player.health = player.get_max_health()


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


func _push(player: NelvarPlayer, direction: Vector2, strength: float, run: bool, frames: int, done: Callable) -> void:
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
