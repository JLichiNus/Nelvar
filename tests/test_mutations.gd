extends SceneTree
## Mutations: every one gains and costs, the meter ripens them, the player's
## own wait and get seized, the other versions pick by their element, and the
## stats really change the player and the HUD.
## Run: godot --headless --path . --script tests/test_mutations.gd

const PLAYER_SCENE := preload("res://player/player.tscn")
const HUD_SCENE := preload("res://ui/mutations/mutation_hud.tscn")

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_catalog()
	_check_stats()
	await _check_director()
	await _check_player_stats()
	await _check_hud()
	if _failures.is_empty():
		print("PASS: %d mutation checks; catalog, meter, choice, interception, versions, stats, HUD." % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


# VISION §3: no mutation is a pure gain or a pure loss, at any stage.
func _check_catalog() -> void:
	var ids := {}
	var mutations := NelvarMutationCatalog.all()
	_check(mutations.size() >= 15, "Too few mutations")
	var layers := {}
	for mutation in mutations:
		_check(not ids.has(mutation.id), "Duplicate mutation id %s" % mutation.id)
		ids[mutation.id] = true
		layers[mutation.layer] = true
		_check(not mutation.summary.is_empty() and mutation.summary.length() <= 60,
			"%s: summary missing or too long" % mutation.id)
		for stage in range(1, mutation.max_stage + 1):
			var text := mutation.describe(stage)
			_check(not text["gains"].is_empty(), "%s %d has no gain" % [mutation.id, stage])
			_check(not text["costs"].is_empty(), "%s %d has no cost" % [mutation.id, stage])
			for line: String in text["gains"] + text["costs"]:
				_check(line.length() <= 48, "%s: description line too long: %s" % [mutation.id, line])
		for modifier in mutation.modifiers:
			_check(NelvarStats.INFO.has(modifier["stat"]), "%s: unknown stat %s" % [mutation.id, modifier["stat"]])
	_check(layers.size() == NelvarMutation.Layer.size(), "Not every layer has mutations")
	# The same card must not be the best for every version: each version has
	# at least one mutation it likes most.
	var favored := {}
	for mutation in mutations:
		favored[mutation.favored_version()] = true
	_check(favored.size() == NelvarMutation.Version.size(), "Some version favours nothing")


func _check_stats() -> void:
	var stats := NelvarStats.new()
	stats.set_base(&"move_speed", 300.0)
	stats.set_source(&"a", [{"stat": &"move_speed", "percent": 20.0}])
	stats.set_source(&"b", [{"stat": &"move_speed", "percent": -10.0}, {"stat": &"move_speed", "flat": 10.0}])
	_check(is_equal_approx(stats.value(&"move_speed"), 310.0 * 1.1), "Percents and flats combine wrongly")
	stats.set_source(&"a", [{"stat": &"move_speed", "percent": 40.0}])
	_check(is_equal_approx(stats.value(&"move_speed"), 310.0 * 1.3), "Replacing a source stacks it")
	stats.set_source(&"a", [{"stat": &"move_speed", "percent": -500.0}])
	_check(stats.value(&"move_speed") >= 310.0 * NelvarStats.MIN_FACTOR - 0.01, "A stat fell below its floor")
	_check(is_equal_approx(stats.value(&"damage"), 1.0), "Multiplier stats do not start at 1")


func _check_director() -> void:
	var player := await _spawn_player()
	var director: NelvarMutationDirector = player.get_node("Mutations")
	director.set_seed(4242)
	director.spontaneous_chance = 0.0
	director.start_share = 1.0
	director.final_share = 1.0
	director.set_seed(4242)
	_check(director.upcoming_owners().size() == director.queue_length, "Queue is not filled")
	_check(director.upcoming_owners().all(func(o: int) -> bool: return o == director.player_version),
		"A full share still queues other versions")

	# Kills and lost health fill the meter.
	var before := director.adaptation
	player.register_kill()
	_check(director.adaptation > before, "A kill does not feed adaptation")
	before = director.adaptation
	player.take_damage(10.0)
	_check(director.adaptation > before + 10.0, "Lost health does not feed adaptation")

	# A full meter ripens the player's own mutation; it waits and freezes the meter.
	var applied: Array = []
	director.mutation_applied.connect(func(m, s, o, i) -> void: applied.append([m, s, o, i]))
	director.add_adaptation(director.threshold)
	_check(director.has_pending(), "A full meter did not ripen the player's mutation")
	_check(director.pending_offers().size() == director.offer_count, "Wrong number of cards")
	var frozen := director.adaptation
	director.add_adaptation(50.0)
	_check(is_equal_approx(director.adaptation, frozen), "The meter grows while a mutation waits")
	var card := director.pending_offers()[1]
	director.choose(1)
	_check(not director.has_pending(), "Choosing did not resolve the mutation")
	_check(applied.size() == 1 and applied[0][0] == card and applied[0][2] == director.player_version
		and not applied[0][3], "The chosen card was not applied as the player's")
	_check(director.stage_of(card.id) == 1, "Stage not recorded")
	var owned := director.owned()
	_check(owned.size() == 1 and owned[0]["owners"] == [director.player_version],
		"Owner of a stage not recorded")
	_check(player.stats.sources().has(StringName("mutation:%s" % card.id)), "Stats did not get the mutation")

	# Waiting too long: another version seizes it from the same cards.
	director.add_adaptation(director.threshold)
	var offers := director.pending_offers()
	await _wait_seconds(director, director.pending_duration + 0.5)
	_check(not director.has_pending(), "The waiting mutation was never seized")
	var seized: Array = applied[-1]
	_check(seized[3] and seized[2] != director.player_version, "Interception not reported as another version's")
	_check(offers.has(seized[0]), "The seizing version did not pick from the player's cards")

	# Another version picks what suits its element.
	director.start_share = 0.0
	director.final_share = 0.0
	director.set_seed(77)
	var fits := 0
	for i in 12:
		var owner: int = director.upcoming_owners()[0]
		director.add_adaptation(director.threshold)
		var last: Array = applied[-1]
		_check(last[2] == owner, "The queued owner is not who applied the mutation")
		var mutation: NelvarMutation = last[0]
		var own_score := mutation.score_for(owner, last[1])
		if own_score > 0.0:
			fits += 1
	_check(fits >= 10, "Other versions take mutations bad for themselves (%d/12 fit)" % fits)
	_check(director.mutation_count == 14, "Mutation count is off")
	player.queue_free()


func _check_player_stats() -> void:
	var player := await _spawn_player()
	var full := player.health
	player.stats.set_source(&"test", [{"stat": &"max_health", "percent": 50.0}])
	_check(is_equal_approx(player.get_max_health(), full * 1.5), "Max health stat not used")
	_check(is_equal_approx(player.health, full * 1.5), "A larger maximum did not add health")
	player.stats.set_source(&"test", [{"stat": &"max_health", "percent": -50.0}])
	_check(is_equal_approx(player.health, full * 0.5), "A smaller maximum did not cut health")

	player.stats.set_source(&"test", [{"stat": &"damage_taken", "percent": -50.0}])
	var health := player.health
	player.take_damage(10.0)
	_check(is_equal_approx(health - player.health, 5.0), "Damage taken stat not used")

	player.stats.set_source(&"test", [{"stat": &"regen", "flat": 5.0}])
	health = player.health
	await _wait_seconds(player, 1.0)
	_check(player.health > health + 3.0, "Regeneration does not heal")

	player.stats.set_source(&"test", [{"stat": &"kill_heal", "flat": 3.0}])
	player.health = 10.0
	player.register_kill()
	_check(is_equal_approx(player.health, 13.0), "Kill heal does not heal")

	player.stats.set_source(&"test", [{"stat": &"damage", "percent": 100.0},
		{"stat": &"wave_damage", "percent": 50.0}])
	var expected := player.base_damage() * player.wave_damage_percent / 100.0 * 3.0
	_check(is_equal_approx(player.call("_damage", player.wave_damage_percent, &"wave_damage"), expected),
		"Damage multipliers do not combine")

	player.stats.set_source(&"test", [{"stat": &"flight_unprotected", "flat": 1.0}])
	player.set("_speed_boost_state", NelvarPlayer.SpeedBoostState.ACTIVE)
	_check(player.is_airborne() and not player.is_flight_protected(), "Hollow vortex keeps flight protection")
	health = player.health
	player.set("_invulnerability_left", 0.0)
	player.take_damage(4.0)
	_check(player.health < health, "An unprotected flight takes no damage")
	player.queue_free()


# The HUD opens the choice on E, pauses, picks with 1/2/3 and unpauses.
func _check_hud() -> void:
	var player := await _spawn_player()
	var hud: NelvarMutationHud = HUD_SCENE.instantiate()
	hud.player = player
	root.add_child(hud)
	await process_frame
	var director: NelvarMutationDirector = player.get_node("Mutations")
	director.start_share = 1.0
	director.final_share = 1.0
	director.spontaneous_chance = 0.0
	director.set_seed(5)
	director.add_adaptation(director.threshold)
	_check(director.has_pending(), "HUD test: nothing ripened")
	var toasts: Node = hud.get_node("Toasts")
	_check(toasts.get_child_count() == 1, "No notice when the mutation ripened")
	_check(player.get_children().any(func(c: Node) -> bool: return c is NelvarMutationBurst),
		"No burst around the player when the mutation ripened")
	_press_action(&"mutate")
	await process_frame
	var choice: Control = hud.get_node("Choice")
	_check(choice.visible and paused, "E did not open the paused choice")
	_press_key(KEY_2)
	await process_frame
	_check(not choice.visible and not paused, "Choosing did not close the panel and unpause")
	_check(director.mutation_count == 1 and not director.has_pending(), "Key 2 did not choose")
	# The "ripened" notice gives way to the one about the chosen mutation.
	_check(toasts.get_child_count() == 1, "No notice after the mutation, or the ripened one stays")
	_check(hud.get_node("Flash").visible, "The screen edges do not flare on a mutation")
	await process_frame
	var strip: Node = hud.get_node("Strip")
	var icons := strip.get_children().filter(func(c: Node) -> bool: return c is NelvarMutationIcon)
	_check(icons.size() == 1, "The received mutation is not shown on top")
	if icons.size() == 1:
		# The hint shows at once on hover and hides when the mouse leaves.
		icons[0].mouse_entered.emit()
		_check(strip.call("hint_visible"), "Hovering a top tile shows no hint at once")
		icons[0].mouse_exited.emit()
		_check(not strip.call("hint_visible"), "The hint stays after the mouse left")
	var inventory := NelvarMutationInventory.new()
	root.add_child(inventory)
	inventory.refresh(director)
	await process_frame
	var list: Node = inventory.get("_list")
	_check(list.get_child_count() == 1, "The inventory does not list the mutation")
	inventory.queue_free()
	hud.queue_free()
	player.queue_free()
	await process_frame


func _spawn_player() -> NelvarPlayer:
	var player: NelvarPlayer = PLAYER_SCENE.instantiate()
	root.add_child(player)
	await process_frame
	return player


func _wait_seconds(node: Node, seconds: float) -> void:
	var timer := node.get_tree().create_timer(seconds)
	await timer.timeout


func _press_action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	root.push_input(event)


func _press_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	root.push_input(event)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
