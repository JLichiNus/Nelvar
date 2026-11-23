class_name NelvarVoidMain
extends Node2D
## The Void (developer setting "Запускать игру в Пустоте"): the player wakes on
## debris of the four realities and makes their way to the monolith.
##
## There are no walls here. Ground is wherever debris is (NelvarVoidData.support_at);
## off the ground the player keeps going for a moment (NelvarVoidData.COYOTE_TIME),
## longer is a fall: they sink into the Void and come back where they last stood
## firmly, a little worse for it. Flight carries them over anything.

const FALL_TIME := 0.75
const FALL_DAMAGE := 12.0
## A spot counts as firm footing this far from the edge of a still piece.
const SAFE_CLEARANCE := 26.0
const MESSAGE_FADE := 1.6
const MESSAGE_HOLD := 3.6
const OPENING_LINES: Array[String] = [
	"Здесь нет ни земли, ни неба.",
	"Только то, что от них осталось.",
]
const ARENA_LINES: Array[String] = [
	"Здесь кто-то должен был ждать.",
]
const DISTANT_DEBRIS := 46

var data: NelvarVoidData
var debris_nodes: Array[NelvarVoidDebris] = []
var monolith_node: NelvarVoidDebris

var _time := 0.0
var _air_time := 0.0
var _safe_position := Vector2.ZERO
var _falls := 0
var _message_tween: Tween
var _sky_material: ShaderMaterial

@onready var sky: NelvarCloudSea = $Sky
@onready var distant: Parallax2D = $Distant
@onready var world_layer: Node2D = $World
@onready var actors: Node2D = $Actors
@onready var player: NelvarPlayer = $Actors/Player
@onready var arena: NelvarVoidArena = $Actors/Arena
@onready var motes: NelvarWindParticles = $Motes
@onready var shade: ColorRect = $Shade/Vignette
@onready var info_panel: Control = $HUD/Margin/Stack/Panel
@onready var seed_label: Label = $HUD/Margin/Stack/Panel/Padding/Rows/Seed
@onready var status_label: Label = $HUD/Margin/Stack/Panel/Padding/Rows/Status
@onready var message: Label = $HUD/Message
@onready var boss_bar: Control = $HUD/BossBar


func _ready() -> void:
	info_panel.visible = GameSettings.show_info_panel
	GameSettings.info_panel_changed.connect(info_panel.set_visible)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var world_seed := int(rng.randi())
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			var value := argument.trim_prefix("--seed=")
			if value.is_valid_int():
				world_seed = value.to_int()
	# Tests pick a seed with the crossings they need.
	if has_meta("seed_override"):
		world_seed = get_meta("seed_override")
	data = NelvarVoidGenerator.new().generate(world_seed)
	if data == null:
		seed_label.text = "Пустота не сложилась · сид %d" % world_seed
		status_label.text = "Ошибка генерации. Подробности в Output."
		info_panel.show()
		player.set_physics_process(false)
		player.set_process(false)
		return
	_build_world()
	_build_distant(world_seed)
	_sky_material = sky.backdrop_material()
	sky.set_world_seed(world_seed)
	motes.color = Color(0.66, 0.52, 1.0, 0.5)
	arena.setup(data, player, monolith_node, world_layer)
	arena.fight_started.connect(_on_fight_started)
	player.position = data.spawn_position
	_safe_position = data.spawn_position
	player.camera.reset_smoothing()
	message.modulate.a = 0.0
	boss_bar.hide()
	seed_label.text = "ПУСТОТА · СИД %d" % data.world_seed
	status_label.text = "%d обломков на пути · %d всего · %d разбегов · %d перелётов" % [
		data.route.size(), data.debris.size(), data.count_gaps(NelvarVoidData.Gap.LEAP),
		data.count_gaps(NelvarVoidData.Gap.FLIGHT)]
	print("Nelvar Void seed: %d | route: %d | debris: %d | leaps: %d | flights: %d | ferries: %d | flickers: %d" % [
		data.world_seed, data.route.size(), data.debris.size(), data.count_gaps(NelvarVoidData.Gap.LEAP),
		data.count_gaps(NelvarVoidData.Gap.FLIGHT), data.count_motion(NelvarVoidData.Motion.FERRY),
		data.count_motion(NelvarVoidData.Motion.FLICKER)])
	_say(OPENING_LINES, 1.2)


func _build_world() -> void:
	var painter := NelvarDebrisPainter.new()
	monolith_node = NelvarVoidDebris.new()
	monolith_node.setup(data.monolith, painter.paint(data.monolith))
	world_layer.add_child(monolith_node)
	for piece in data.debris:
		var node := NelvarVoidDebris.new()
		node.setup(piece, painter.paint(piece))
		world_layer.add_child(node)
		debris_nodes.append(node)


## Far-off debris drifting deep in the Void: dim silhouettes on a slow parallax layer.
func _build_distant(world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:distant" % world_seed).hash()
	var painter := NelvarDebrisPainter.new()
	var size := distant.repeat_size
	for i in DISTANT_DEBRIS:
		var piece := NelvarVoidData.Debris.new()
		piece.kind = rng.randi_range(NelvarVoidData.Kind.EARTH, NelvarVoidData.Kind.SHARD) as NelvarVoidData.Kind
		piece.appearance_seed = rng.randi()
		var radius := rng.randf_range(14.0, 46.0)
		piece.polygon = PackedVector2Array()
		var corners := rng.randi_range(5, 9)
		for c in corners:
			piece.polygon.append(Vector2.from_angle(TAU * (c + rng.randf_range(-0.3, 0.3)) / corners)
				* radius * rng.randf_range(0.65, 1.0))
		piece.radius = radius
		var art := painter.paint(piece)
		var sprite := Sprite2D.new()
		sprite.texture = art.underside
		sprite.centered = false
		sprite.scale = Vector2.ONE * NelvarDebrisPainter.PIXEL
		var top := Sprite2D.new()
		top.texture = art.surface
		top.centered = false
		top.scale = sprite.scale
		var holder := Node2D.new()
		holder.position = Vector2(rng.randf() * size.x, rng.randf() * size.y)
		holder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# Deeper means darker and more violet.
		var depth := rng.randf()
		holder.modulate = Color(0.32, 0.27, 0.42).lerp(Color(0.14, 0.11, 0.2), depth)
		sprite.position = art.rect.position
		top.position = art.rect.position
		holder.add_child(sprite)
		holder.add_child(top)
		distant.add_child(holder)


func _physics_process(delta: float) -> void:
	if data == null:
		return
	# Ground under the player as it was during the move they just made.
	var support := data.support_at(player.global_position, _time)
	var next_time := _time + delta
	# A drifting piece carries whoever stands on it.
	if support != null and support.motion == NelvarVoidData.Motion.FERRY and not player.is_falling():
		player.global_position += support.offset_at(next_time) - support.offset_at(_time)
	_time = next_time
	monolith_node.sync(_time)
	for node in debris_nodes:
		node.sync(_time)
	if player.is_falling():
		return
	if support == null and not player.is_airborne():
		_air_time += delta
		if _air_time > NelvarVoidData.COYOTE_TIME:
			_fall()
		return
	_air_time = 0.0
	if support != null and support.motion == NelvarVoidData.Motion.STILL:
		var local := player.global_position - support.position
		if Geometry2D.is_point_in_polygon(local, support.polygon) \
				and NelvarVoidData.distance_to_outline(local, support.polygon) >= SAFE_CLEARANCE:
			_safe_position = player.global_position


func _fall() -> void:
	_falls += 1
	_air_time = 0.0
	player.fall_into_abyss(FALL_TIME)
	await get_tree().create_timer(FALL_TIME + 0.35, false).timeout
	if not is_instance_valid(player):
		return
	player.recover_at(_safe_position)
	player.take_damage(FALL_DAMAGE)


func _on_fight_started() -> void:
	_say(ARENA_LINES, 0.6)
	boss_bar.modulate.a = 0.0
	boss_bar.show()
	var tween := create_tween().set_parallel()
	tween.tween_property(boss_bar, "modulate:a", 1.0, 1.5).set_delay(1.0)
	tween.tween_method(_set_dread, 0.0, 1.0, 6.0).set_trans(Tween.TRANS_SINE)
	tween.tween_property(shade, "modulate:a", 1.0, 3.0)
	_shake(0.7, 6.0)


func _set_dread(value: float) -> void:
	_sky_material.set_shader_parameter("dread", value)


## A short quake of the camera; whole pixels only.
func _shake(duration: float, strength: float) -> void:
	var tween := create_tween()
	var steps := int(duration / 0.05)
	for i in steps:
		var fade := 1.0 - float(i) / steps
		var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength * fade
		tween.tween_property(player.camera, "offset", offset.round(), 0.05)
	tween.tween_property(player.camera, "offset", Vector2.ZERO, 0.05)


## Lines appear one after another at the bottom of the screen and fade away.
func _say(lines: Array[String], delay: float) -> void:
	if _message_tween != null:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(delay)
	for line in lines:
		_message_tween.tween_callback(message.set_text.bind(line))
		_message_tween.tween_property(message, "modulate:a", 1.0, MESSAGE_FADE)
		_message_tween.tween_interval(MESSAGE_HOLD)
		_message_tween.tween_property(message, "modulate:a", 0.0, MESSAGE_FADE)
		_message_tween.tween_interval(0.4)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			player.adjust_zoom(1.15)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			player.adjust_zoom(1.0 / 1.15)
			get_viewport().set_input_as_handled()
