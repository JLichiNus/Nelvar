extends Node2D

@export var world_config: NelvarWorldConfig
@export var forest_config: NelvarForestConfig = preload("res://resources/earth_forest_config.tres")
@export var prop_config: NelvarPropConfig = preload("res://resources/earth_prop_config.tres")

var world_data: NelvarWorldData
var forest_data: NelvarForestData
var prop_data: NelvarPropData
var tree_nodes: Array[NelvarTree] = []
var prop_nodes: Array[NelvarProp] = []
@onready var cloud_sea: NelvarCloudSea = $CloudSea
@onready var wind: NelvarWindParticles = $Wind
@onready var world_view: NelvarWorldView = $World
@onready var actors: Node2D = $Actors
@onready var player: NelvarPlayer = $Actors/Player
@onready var enemy_spawner: Node2D = $Actors/EnemySpawner
@onready var info_panel: Control = $HUD/Margin/Stack/Panel
@onready var seed_label: Label = $HUD/Margin/Stack/Panel/Padding/Rows/Seed
@onready var status_label: Label = $HUD/Margin/Stack/Panel/Padding/Rows/Status


func _ready() -> void:
	GameMusic.start(&"air")
	# Seed, world stats and controls: hidden unless enabled in settings or with F12.
	info_panel.visible = GameSettings.show_info_panel
	GameSettings.info_panel_changed.connect(info_panel.set_visible)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var world_seed := int(rng.randi())
	# An optional command-line override makes reported maps reproducible.
	# Ordinary editor/game launches always use a fresh random seed.
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			var value := argument.trim_prefix("--seed=")
			if value.is_valid_int():
				world_seed = value.to_int()
	world_data = NelvarWorldGenerator.new().generate(world_config, world_seed)
	if world_data == null:
		seed_label.text = "Не удалось построить карту · сид %d" % world_seed
		status_label.text = "Ошибка генерации. Подробности в Output."
		info_panel.show()  # the error must be visible even if the panel is off
		player.set_physics_process(false)
		player.set_process(false)
		return
	world_view.build(world_data)
	cloud_sea.texel_size = world_view.terrain_style.pixel_size
	cloud_sea.set_world_seed(world_data.world_seed)
	wind.texel_size = world_view.terrain_style.pixel_size
	forest_data = NelvarForestGenerator.new().generate(world_data, forest_config)
	var tree_painter := NelvarTreePainter.new()
	for tree in forest_data.trees:
		var node := NelvarTree.new()
		node.setup(tree, tree_painter.paint(tree, world_view.terrain_style))
		actors.add_child(node)
		tree_nodes.append(node)
	prop_data = NelvarPropGenerator.new().generate(world_data, forest_data, forest_config, prop_config)
	var prop_painter := NelvarPropPainter.new()
	for prop in prop_data.props:
		var node := NelvarProp.new()
		node.setup(prop, prop_painter.paint(prop, world_view.terrain_style))
		actors.add_child(node)
		prop_nodes.append(node)
	player.position = world_data.spawn_position
	player.camera.reset_smoothing()
	enemy_spawner.call("start", world_data, forest_data, prop_data)
	seed_label.text = "ЗЕМЛЯ · СИД %d" % world_data.world_seed
	var large := 0
	for island in world_data.islands:
		if island.large:
			large += 1
	var rocks := prop_data.count(NelvarPropData.Kind.ROCK)
	var bushes := prop_data.count(NelvarPropData.Kind.BUSH)
	status_label.text = "%d крупных · %d малых · %d мостов · %d деревьев · %d камней · %d кустов" % [
		large, world_data.islands.size() - large, world_data.bridges.size(), tree_nodes.size(),
		rocks, bushes]
	print("Nelvar seed: %d | islands: %d | bridges: %d | chunks: %d | trees: %d | groves: %d | rocks: %d | bushes: %d" % [
		world_data.world_seed, world_data.islands.size(), world_data.bridges.size(),
		world_data.leaves.size(), tree_nodes.size(), forest_data.clusters.size(), rocks, bushes])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			var show_debug := world_view.toggle_chunks()
			for tree in tree_nodes:
				tree.show_collision = show_debug
				tree.queue_redraw()
			for prop in prop_nodes:
				prop.show_collision = show_debug
				prop.queue_redraw()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			player.adjust_zoom(1.15)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			player.adjust_zoom(1.0 / 1.15)
			get_viewport().set_input_as_handled()
