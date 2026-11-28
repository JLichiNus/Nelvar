extends SceneTree
## Developer console: the hints follow the command trees, bad input is
## reported instead of run, and the commands really change mutations, health,
## level, abilities and enemies on the test arena.
## Run: godot --headless --path . --script tests/test_console.gd

# Loaded at run time: the arena's scripts use autoloads, which a preload
# here would compile before they exist.
const ARENA := "res://test_world.tscn"

var _failures: Array[String] = []
var _checks := 0
var _tree: NelvarCommandTree
var _errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arena := (load(ARENA) as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	await process_frame
	await process_frame
	_tree = NelvarCommandTree.new()
	_tree.printed.connect(func(text: String, kind: int) -> void:
		if kind == NelvarCommandTree.Output.ERROR:
			_errors.append(text))
	NelvarConsoleCommands.new(_tree, self).register()

	_check_hints()
	_check_errors()
	var player := get_first_node_in_group(&"player") as NelvarPlayer
	_check(player != null, "No player on the arena")
	if player != null:
		_check_mutations(player)
		_check_player(player)
		await _check_enemies(player)
	Engine.time_scale = 1.0
	_tree.clear()
	arena.queue_free()
	await process_frame
	if _failures.is_empty():
		print("PASS: %d console checks; hints, errors, mutations, health, level, enemies." % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _check_hints() -> void:
	var all := _texts(_tree.suggest("/"))
	for word in ["help", "mutation", "hp", "spawn", "kill", "god"]:
		_check(all.has(word), "/ does not suggest %s" % word)
	_check(_texts(_tree.suggest("/mu")) == ["mutation"], "/mu does not narrow to mutation")
	_check(_texts(_tree.suggest("/mutation up")) == ["upgrade"], "Subcommand prefix")
	var by_title := _texts(_tree.suggest("/mutation give лёг"))
	_check(by_title.has("light_body"), "A mutation is not found by its Russian title")
	var hp := _tree.suggest("/hp add ")
	_check(hp["expected"] == PackedStringArray(["<amount>"]), "Number argument not hinted")
	_check(hp["start"] == "/hp add ".length(), "Word start is off")
	_check(not _tree.suggest("/nothing ")["error"].is_empty(), "Unknown command not flagged in hints")
	var spawn := _tree.suggest("/spawn ")
	_check(_texts(spawn).has("runner") and spawn["candidates"][0]["more"], "Enemy kinds not suggested")


func _check_errors() -> void:
	_check(not _tree.execute("/nothing").is_empty(), "Unknown command ran")
	_check(not _tree.execute("/hp add abc").is_empty(), "A word passed as a number")
	_check(not _tree.execute("/hp add").is_empty(), "A missing argument ran")
	_check(not _tree.execute("/mutation give nope").is_empty(), "An unknown mutation was given")
	_check(not _tree.execute("/timescale 500").is_empty(), "A value out of range ran")
	_check(not _tree.execute("/god on off").is_empty(), "An extra word ran")


func _check_mutations(player: NelvarPlayer) -> void:
	var director: NelvarMutationDirector = player.get_node("Mutations")
	var base_speed := player.stats.base(&"move_speed")
	_run_ok("mutation give light_body")
	_check(director.stage_of(&"light_body") == 1, "give did not give stage I")
	_check(player.stats.value(&"move_speed") > base_speed, "A given mutation does not change stats")
	_run_ok("mutation upgrade light_body")
	_check(director.stage_of(&"light_body") == 2, "upgrade did not raise the stage")
	_errors.clear()
	_tree.execute("/mutation upgrade light_body")
	_check(director.stage_of(&"light_body") == 2 and not _errors.is_empty(), "upgrade went past the last stage")
	_run_ok("mutation give fury 2 fire")
	var fury := director.owned().filter(func(e: Dictionary) -> bool: return e["mutation"].id == &"fury")
	_check(fury.size() == 1 and fury[0]["owners"] == [NelvarMutation.Version.FIRE, NelvarMutation.Version.FIRE],
		"give with a stage and owner")
	_check(director.mutation_count == 4, "Mutation count off after give: %d" % director.mutation_count)
	_run_ok("mutation give split_shot ice")
	_check(director.owned().back()["owners"] == [NelvarMutation.Version.ICE], "give with an owner only")
	_run_ok("mutation upgrade all")
	_check(director.stage_of(&"split_shot") == 2, "upgrade all")
	_run_ok("mutation remove light_body")
	_check(director.stage_of(&"light_body") == 0 and is_equal_approx(player.stats.value(&"move_speed"), base_speed),
		"remove left the mutation or its stats")
	_run_ok("mutation remove all")
	_check(director.owned().is_empty() and director.mutation_count == 0, "remove all")
	_run_ok("mutation ripen air")
	_check(director.has_pending(), "ripen air did not give the player a choice")
	director.choose(0)
	_run_ok("mutation ripen fire")
	_check(director.owned().back()["owners"] == [NelvarMutation.Version.FIRE], "ripen fire")
	_run_ok("mutation adapt 5")
	_run_ok("mutation list")
	_run_ok("mutation remove all")


func _check_player(player: NelvarPlayer) -> void:
	_run_ok("hp set 40")
	_check(is_equal_approx(player.health, 40.0), "hp set")
	_run_ok("hp add 15")
	_check(is_equal_approx(player.health, 55.0), "hp add")
	_run_ok("hp remove 5")
	_check(is_equal_approx(player.health, 50.0), "hp remove")
	_run_ok("hp max 250")
	_run_ok("hp full")
	_check(is_equal_approx(player.health, 250.0) and is_equal_approx(player.get_max_health(), 250.0), "hp max / full")
	_run_ok("god on")
	player.take_damage(30.0)
	_check(is_equal_approx(player.health, 250.0), "God mode still takes damage")
	_run_ok("god")
	_check(not player.god_mode, "god does not toggle")
	_run_ok("level set 6")
	_check(player.level == 6, "level set")
	_run_ok("level add 2")
	_check(player.level == 8, "level add")
	_run_ok("cooldowns off")
	_check(player.no_cooldowns, "cooldowns off")
	_run_ok("cooldowns on")
	_run_ok("tp 300 200")
	_check(player.global_position.is_equal_approx(Vector2(300, 200)), "tp to a point")
	_run_ok("timescale 2")
	_check(is_equal_approx(Engine.time_scale, 2.0), "timescale")
	_run_ok("stats all")
	_run_ok("help")
	_run_ok("help mutation")


func _check_enemies(_player: NelvarPlayer) -> void:
	_run_ok("spawner off")
	_run_ok("kill")
	var before := get_nodes_in_group(&"enemies").size()
	_run_ok("spawn hopper 3")
	_run_ok("spawn runner")
	await process_frame
	_check(get_nodes_in_group(&"enemies").size() == before + 4, "spawn did not bring 4 enemies")
	_run_ok("kill hopper")
	await process_frame
	var left := get_nodes_in_group(&"enemies")
	_check(left.size() == before + 1 and left.all(func(e: Node) -> bool:
		return e.scene_file_path.ends_with("runner.tscn")), "kill hopper killed the wrong ones")
	_run_ok("kill")
	await process_frame
	_check(get_nodes_in_group(&"enemies").is_empty(), "kill left enemies")


func _run_ok(line: String) -> void:
	_errors.clear()
	var error := _tree.execute("/" + line)
	_check(error.is_empty() and _errors.is_empty(), "/%s failed: %s %s" % [line, error, _errors])


func _texts(hint: Dictionary) -> Array:
	return hint["candidates"].map(func(c: Dictionary) -> String: return c["text"])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
