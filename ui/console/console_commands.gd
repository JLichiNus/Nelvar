class_name NelvarConsoleCommands
extends RefCounted
## The game's console commands: mutations, health, enemies, abilities, the
## player's place and the run itself. Every command looks the player up when
## it runs, so the same commands serve the air location, the Void and the
## test arena, and survive a restart.

const N := preload("res://ui/console/console_node.gd")
const ENEMIES := {
	"hopper": {"scene": "res://enemies/hopper/hopper.tscn", "title": "Прыгун"},
	"whistler": {"scene": "res://enemies/whistler/whistler.tscn", "title": "Свистун"},
	"runner": {"scene": "res://enemies/runner/runner.tscn", "title": "Бегунок"},
}
## Who picks a mutation, as typed in commands.
const OWNERS := {
	"air": NelvarMutation.Version.AIR,
	"earth": NelvarMutation.Version.EARTH,
	"fire": NelvarMutation.Version.FIRE,
	"ice": NelvarMutation.Version.ICE,
	"spontaneous": NelvarMutation.SPONTANEOUS,
}
const MAX_SPAWN := 50
## Several spawned enemies scatter this far around the cursor.
const SPAWN_SCATTER := 70.0
const APPEAR_DURATION := 0.3
## Damage that kills any ordinary enemy at once.
const KILL_DAMAGE := 1.0e9

var _tree: NelvarCommandTree
var _scene_tree: SceneTree


func _init(tree: NelvarCommandTree, scene_tree: SceneTree) -> void:
	_tree = tree
	_scene_tree = scene_tree


func register() -> void:
	_tree.add(_help())
	_tree.add(_mutation())
	_tree.add(_hp())
	_tree.add(_god())
	_tree.add(_cooldowns())
	_tree.add(_level())
	_tree.add(_spawn())
	_tree.add(_kill())
	_tree.add(_spawner())
	_tree.add(_tp())
	_tree.add(_timescale())
	_tree.add(_stats())
	_tree.add(_restart())


# --- help --------------------------------------------------------------------

func _help() -> NelvarConsoleNode:
	return N.literal("help", "список команд").runs(func(_a: Dictionary) -> void:
		for root in _tree.roots():
			_tree.info("/%s — %s" % [root.name, root.hint])
		_tree.info("Tab — дополнить, ↑↓ — подсказки и история.")
	).then(N.choice("command", _command_options).runs(func(a: Dictionary) -> void:
		var root := _tree.find_root(a["command"])
		for usage in _tree.usages(root):
			_tree.info("%s — %s" % [usage["usage"], usage["hint"]])))


func _command_options() -> Array:
	var result := []
	for root in _tree.roots():
		result.append({"text": root.name, "hint": root.hint})
	return result


# --- mutation ------------------------------------------------------------------

func _mutation() -> NelvarConsoleNode:
	# /mutation give <id> [stage] [owner]: the owner may also come right after the id.
	var give_stage := N.integer("stage", 1, NelvarMutation.STAGE_NAMES.size()) \
		.described("тир").runs(_give).then(N.choice("owner", _owner_options).runs(_give))
	var give_id := N.choice("id", _all_mutation_options).runs(_give) \
		.then(give_stage, [N.choice("owner", _owner_options).runs(_give)])
	return N.literal("mutation", "мутации: выдать, улучшить, убрать").then(
		N.literal("give", "выдать мутацию (следующий тир или указанный)").then(give_id), [
		N.literal("upgrade", "поднять мутацию на следующий тир").then(
			N.literal("all", "все полученные").runs(_upgrade_all), [
			N.choice("id", _upgradable_options).runs(_upgrade)]),
		N.literal("remove", "убрать мутацию").then(
			N.literal("all", "все полученные").runs(_remove_all), [
			N.choice("id", _owned_options).runs(_remove)]),
		N.literal("list", "полученные мутации").runs(_list_owned),
		N.literal("catalog", "все мутации игры").runs(_list_catalog),
		N.literal("ripen", "мутация созревает сейчас").runs(_ripen).then(
			N.choice("owner", _owner_options).runs(_ripen)),
		N.literal("adapt", "добавить адаптации").then(
			N.number("amount", 0.0).runs(_adapt)),
	])


func _give(a: Dictionary) -> void:
	var director := _director()
	if director == null:
		return
	var mutation := director.find(StringName(a["id"]))
	var stage: int = a.get("stage", director.next_stage(mutation))
	if stage > mutation.max_stage:
		_tree.error("%s: тир %s — уже последний." % [mutation.title,
			NelvarMutation.stage_name(mutation.max_stage)])
		return
	var owner: int = OWNERS.get(a.get("owner", ""), director.player_version)
	director.grant(mutation.id, stage, owner)
	_tree.good("Выдана мутация %s %s." % [mutation.title, NelvarMutation.stage_name(stage)])


func _upgrade(a: Dictionary) -> void:
	var director := _director()
	if director == null:
		return
	var mutation := director.find(StringName(a["id"]))
	var stage := director.stage_of(mutation.id)
	if stage == 0:
		_tree.error("%s ещё не получена: /mutation give %s" % [mutation.title, mutation.id])
	elif stage >= mutation.max_stage:
		_tree.error("%s: тир %s — уже последний." % [mutation.title, NelvarMutation.stage_name(stage)])
	else:
		director.grant(mutation.id, stage + 1)
		_tree.good("%s: тир %s." % [mutation.title, NelvarMutation.stage_name(stage + 1)])


func _upgrade_all(_a: Dictionary) -> void:
	var director := _director()
	if director == null:
		return
	var count := 0
	for entry in director.owned():
		var mutation: NelvarMutation = entry["mutation"]
		if entry["stage"] < mutation.max_stage:
			director.grant(mutation.id, entry["stage"] + 1)
			count += 1
	if count == 0:
		_tree.error("Улучшать нечего.")
	else:
		_tree.good("Улучшено мутаций: %d." % count)


func _remove(a: Dictionary) -> void:
	var director := _director()
	if director == null:
		return
	var mutation := director.find(StringName(a["id"]))
	director.remove(mutation.id)
	_tree.good("Убрана мутация %s." % mutation.title)


func _remove_all(_a: Dictionary) -> void:
	var director := _director()
	if director == null:
		return
	var owned := director.owned()
	for entry in owned:
		director.remove((entry["mutation"] as NelvarMutation).id)
	if owned.is_empty():
		_tree.error("Мутаций нет.")
	else:
		_tree.good("Убрано мутаций: %d." % owned.size())


func _list_owned(_a: Dictionary) -> void:
	var director := _director()
	if director == null:
		return
	var owned := director.owned()
	if owned.is_empty():
		_tree.info("Мутаций нет.")
	for entry in owned:
		var mutation: NelvarMutation = entry["mutation"]
		var owners := PackedStringArray()
		for owner: int in entry["owners"]:
			owners.append(NelvarMutation.version_name(owner))
		_tree.info("%s — %s %s/%s (%s)" % [mutation.id, mutation.title,
			NelvarMutation.stage_name(entry["stage"]), NelvarMutation.stage_name(mutation.max_stage),
			", ".join(owners)])


func _list_catalog(_a: Dictionary) -> void:
	var director := _director()
	if director == null:
		return
	for mutation in director.catalog():
		var stage := director.stage_of(mutation.id)
		var reached := " · есть %s" % NelvarMutation.stage_name(stage) if stage > 0 else ""
		_tree.info("%s — %s, тиров: %d%s" % [mutation.id, mutation.title, mutation.max_stage, reached])


func _ripen(a: Dictionary) -> void:
	var director := _director()
	if director == null:
		return
	var owner: int = OWNERS.get(a.get("owner", ""), -2)
	if director.ripen_now(owner):
		_tree.good("Мутация созрела.")
	else:
		_tree.error("Твоя мутация уже ждёт выбора.")


func _adapt(a: Dictionary) -> void:
	var director := _director()
	if director == null:
		return
	if director.has_pending():
		_tree.error("Твоя мутация ждёт выбора: шкала стоит.")
		return
	director.add_adaptation(a["amount"])
	_tree.good("Адаптация: %s/%s." % [_num(director.adaptation), _num(director.threshold)])


func _all_mutation_options() -> Array:
	var director := _director(false)
	var result := []
	if director == null:
		return result
	for mutation in director.catalog():
		result.append({"text": String(mutation.id), "hint": _mutation_hint(director, mutation)})
	return result


func _upgradable_options() -> Array:
	var director := _director(false)
	var result := []
	if director == null:
		return result
	for entry in director.owned():
		var mutation: NelvarMutation = entry["mutation"]
		if entry["stage"] < mutation.max_stage:
			result.append({"text": String(mutation.id), "hint": _mutation_hint(director, mutation)})
	return result


func _owned_options() -> Array:
	var director := _director(false)
	var result := []
	if director == null:
		return result
	for entry in director.owned():
		var mutation: NelvarMutation = entry["mutation"]
		result.append({"text": String(mutation.id), "hint": _mutation_hint(director, mutation)})
	return result


func _mutation_hint(director: NelvarMutationDirector, mutation: NelvarMutation) -> String:
	var stage := director.stage_of(mutation.id)
	if stage == 0:
		return mutation.title
	return "%s %s/%s" % [mutation.title, NelvarMutation.stage_name(stage),
		NelvarMutation.stage_name(mutation.max_stage)]


func _owner_options() -> Array:
	var result := []
	for key: String in OWNERS:
		result.append({"text": key, "hint": NelvarMutation.version_name(OWNERS[key])})
	return result


# --- hp, god, cooldowns, level -------------------------------------------------

func _hp() -> NelvarConsoleNode:
	return N.literal("hp", "здоровье игрока").then(
		N.literal("add", "вылечить").then(N.number("amount", 0.0).runs(func(a: Dictionary) -> void:
			_change_health(func(p: NelvarPlayer) -> float: return p.health + a["amount"]))), [
		N.literal("remove", "отнять (мимо брони и неуязвимости)").then(
			N.number("amount", 0.0).runs(func(a: Dictionary) -> void:
				_change_health(func(p: NelvarPlayer) -> float: return p.health - a["amount"]))),
		N.literal("set", "задать здоровье").then(N.number("amount", 0.0).runs(func(a: Dictionary) -> void:
			_change_health(func(_p: NelvarPlayer) -> float: return a["amount"]))),
		N.literal("full", "полное здоровье").runs(func(_a: Dictionary) -> void:
			_change_health(func(p: NelvarPlayer) -> float: return p.get_max_health())),
		N.literal("max", "базовый максимум здоровья").then(
			N.number("amount", 1.0).runs(func(a: Dictionary) -> void:
				var player := _player()
				if player == null:
					return
				player.stats.set_base(&"max_health", a["amount"])
				_report_health(player))),
	])


func _change_health(target: Callable) -> void:
	var player := _player()
	if player == null:
		return
	if player.is_dead():
		_tree.error("Игрок мёртв.")
		return
	player.set_health(target.call(player))
	_report_health(player)


func _report_health(player: NelvarPlayer) -> void:
	_tree.good("Здоровье: %s/%s." % [_num(player.health), _num(player.get_max_health())])


func _god() -> NelvarConsoleNode:
	var set_god := func(on: bool) -> void:
		var player := _player()
		if player == null:
			return
		player.god_mode = on
		_tree.good("Бессмертие %s." % ("включено" if on else "выключено"))
	return N.literal("god", "бессмертие: переключить").runs(func(_a: Dictionary) -> void:
		var player := _player()
		if player != null:
			set_god.call(not player.god_mode)
	).then(N.literal("on").runs(func(_a: Dictionary) -> void: set_god.call(true)), [
		N.literal("off").runs(func(_a: Dictionary) -> void: set_god.call(false))])


func _cooldowns() -> NelvarConsoleNode:
	var set_free := func(free: bool) -> void:
		var player := _player()
		if player == null:
			return
		player.no_cooldowns = free
		player.reset_cooldowns()
		_tree.good("Перезарядка %s." % ("выключена" if free else "включена"))
	return N.literal("cooldowns", "перезарядка способностей").then(
		N.literal("reset", "всё готово сейчас").runs(func(_a: Dictionary) -> void:
			var player := _player()
			if player != null:
				player.reset_cooldowns()
				_tree.good("Способности готовы.")), [
		N.literal("off", "без перезарядки").runs(func(_a: Dictionary) -> void: set_free.call(true)),
		N.literal("on", "обычная перезарядка").runs(func(_a: Dictionary) -> void: set_free.call(false)),
	])


func _level() -> NelvarConsoleNode:
	var set_level := func(value: int) -> void:
		var player := _player()
		if player == null:
			return
		player.set_level(value)
		_tree.good("Уровень %d." % player.level)
	return N.literal("level", "уровень игрока").then(
		N.literal("set", "задать уровень").then(N.integer("level", 1).runs(func(a: Dictionary) -> void:
			set_level.call(a["level"]))), [
		N.literal("add", "добавить уровней").then(N.integer("levels").runs(func(a: Dictionary) -> void:
			var player := _player()
			if player != null:
				set_level.call(player.level + int(a["levels"])))),
	])


# --- enemies -------------------------------------------------------------------

func _spawn() -> NelvarConsoleNode:
	return N.literal("spawn", "призвать врагов к курсору").then(
		N.choice("enemy", _enemy_options).runs(_spawn_enemies).then(
			N.integer("count", 1, MAX_SPAWN).runs(_spawn_enemies)))


func _spawn_enemies(a: Dictionary) -> void:
	var player := _player()
	if player == null:
		return
	var kind: Dictionary = ENEMIES[a["enemy"]]
	var scene := load(kind["scene"]) as PackedScene
	var count: int = a.get("count", 1)
	var spawner := _spawner_node()
	var parent: Node2D = spawner if spawner != null else player.get_parent() as Node2D
	var center := player.get_global_mouse_position()
	for i in count:
		var enemy := scene.instantiate() as Node2D
		var offset := Vector2.ZERO
		if i > 0:
			offset = Vector2.from_angle(randf() * TAU) * randf_range(SPAWN_SCATTER * 0.3, SPAWN_SCATTER)
		enemy.position = parent.to_local(center + offset)
		parent.add_child(enemy)
		if enemy.has_method("play_spawn_animation"):
			enemy.call("play_spawn_animation", APPEAR_DURATION)
	_tree.good("Призвано: %s × %d." % [kind["title"], count])


func _kill() -> NelvarConsoleNode:
	var options := func() -> Array:
		var result := _enemy_options()
		result.append({"text": "boss", "hint": "Единственный: удар на всю полосу фазы"})
		return result
	return N.literal("kill", "убить врагов (без аргумента — всех, кроме босса)").runs(_kill_enemies).then(
		N.choice("enemy", options).runs(_kill_enemies))


func _kill_enemies(a: Dictionary) -> void:
	var which: String = a.get("enemy", "")
	var count := 0
	for node in _scene_tree.get_nodes_in_group(&"enemies"):
		if not node.has_method("take_damage"):
			continue
		if node is NelvarTheOne:
			if which == "boss":
				var boss := node as NelvarTheOne
				boss.take_damage(maxf(boss.health, 1.0))
				count += 1
			continue
		if which.is_empty() or _kind_of(node) == which:
			node.call("take_damage", KILL_DAMAGE)
			count += 1
	if count == 0:
		_tree.error("Некого убивать.")
	else:
		_tree.good("Убито: %d." % count)


func _spawner() -> NelvarConsoleNode:
	var set_spawning := func(on: bool) -> void:
		var spawner := _spawner_node()
		if spawner == null:
			_tree.error("Здесь враги не появляются сами.")
			return
		spawner.set_process(on)
		_tree.good("Враги %s." % ("появляются" if on else "больше не появляются"))
	return N.literal("spawner", "враги появляются сами или нет").then(
		N.literal("on").runs(func(_a: Dictionary) -> void: set_spawning.call(true)), [
		N.literal("off").runs(func(_a: Dictionary) -> void: set_spawning.call(false))])


func _enemy_options() -> Array:
	var result := []
	for key: String in ENEMIES:
		result.append({"text": key, "hint": ENEMIES[key]["title"]})
	return result


func _kind_of(enemy: Node) -> String:
	for key: String in ENEMIES:
		if enemy.scene_file_path == ENEMIES[key]["scene"]:
			return key
	return ""


func _spawner_node() -> NelvarEnemySpawner:
	var scene := _scene_tree.current_scene
	if scene == null:
		return null
	for node in scene.find_children("*", "Node2D", true, false):
		if node is NelvarEnemySpawner:
			return node
	return null


# --- place, time, stats, run ---------------------------------------------------

func _tp() -> NelvarConsoleNode:
	return N.literal("tp", "переместиться к курсору или в точку").runs(func(_a: Dictionary) -> void:
		var player := _player()
		if player != null:
			_teleport(player, player.get_global_mouse_position())
	).then(N.number("x").then(N.number("y").runs(func(a: Dictionary) -> void:
		var player := _player()
		if player != null:
			_teleport(player, Vector2(a["x"], a["y"])))))


func _teleport(player: NelvarPlayer, point: Vector2) -> void:
	player.teleport(point)
	_tree.good("Игрок в точке %s, %s." % [_num(point.x), _num(point.y)])


func _timescale() -> NelvarConsoleNode:
	return N.literal("timescale", "скорость времени (1 — обычная)").then(
		N.number("scale", 0.05, 10.0).runs(func(a: Dictionary) -> void:
			Engine.time_scale = a["scale"]
			_tree.good("Скорость времени ×%s." % _num(Engine.time_scale))))


func _stats() -> NelvarConsoleNode:
	return N.literal("stats", "характеристики, изменённые мутациями").runs(func(_a: Dictionary) -> void:
		_print_stats(false)
	).then(N.literal("all", "все характеристики").runs(func(_a: Dictionary) -> void:
		_print_stats(true)))


func _print_stats(everything: bool) -> void:
	var player := _player()
	if player == null:
		return
	var shown := 0
	for stat: StringName in NelvarStats.INFO:
		var base := player.stats.base(stat)
		var value := player.stats.value(stat)
		if not everything and is_equal_approx(base, value):
			continue
		var label: String = NelvarStats.INFO[stat]["label"]
		var line := String(stat) if label.is_empty() else "%s (%s)" % [stat, label]
		if is_equal_approx(base, value):
			line += ": %s" % _num(value)
		else:
			line += ": %s → %s" % [_num(base), _num(value)]
		_tree.info(line)
		shown += 1
	if shown == 0:
		_tree.info("Мутации ничего не изменили.")


func _restart() -> NelvarConsoleNode:
	return N.literal("restart", "начать забег заново").runs(func(_a: Dictionary) -> void:
		Engine.time_scale = 1.0
		_scene_tree.paused = false
		var player := _scene_tree.get_first_node_in_group(&"player") as NelvarPlayer
		NelvarRun.restart(_scene_tree, player.run if player != null else null))


# --- helpers -------------------------------------------------------------------

func _player() -> NelvarPlayer:
	var player := _scene_tree.get_first_node_in_group(&"player") as NelvarPlayer
	if player == null:
		_tree.error("Нет игрока: команда работает только в забеге.")
	return player


func _director(report: bool = true) -> NelvarMutationDirector:
	var player := _scene_tree.get_first_node_in_group(&"player") as NelvarPlayer
	var director: NelvarMutationDirector = null
	if player != null:
		director = player.get_node_or_null("Mutations") as NelvarMutationDirector
	if director == null and report:
		_tree.error("Нет мутаций: команда работает только в забеге.")
	return director


static func _num(value: float) -> String:
	return ("%.1f" % value).trim_suffix(".0")
