class_name NelvarVoidMain
extends NelvarLocation
## The Void (developer setting "Запускать игру в Пустоте"): the player wakes on
## debris of the four realities and makes their way to the monolith.
##
## There are no walls here. Ground is wherever debris is (NelvarVoidData.support_at);
## off the ground the player keeps going for a moment (NelvarVoidData.COYOTE_TIME),
## longer is a fall: they sink into the Void and come back where they last stood
## firmly, a little worse for it. Flight carries them over anything. Threads of
## light (NelvarVoidThreads) mark the route, and a fall at a crossing that needs
## more than a step says what it takes.

const FALL_TIME := 0.75
const FALL_DAMAGE := 10.0
## A spot counts as firm footing this far from the edge of a still piece (the
## body radius plus a little: narrow logs count too).
const SAFE_CLEARANCE := 16.0
const MESSAGE_FADE := 1.6
const MESSAGE_HOLD := 3.6
const OPENING_LINES: Array[String] = [
	"Здесь нет ни земли, ни неба.",
	"Только то, что от них осталось.",
]
const ARENA_LINES: Array[String] = [
	"Здесь тебя ждали.",
]
const RETRY_LINES: Array[String] = [
	"Пустота помнит тебя.",
]
const VICTORY_LINES: Array[String] = [
	"Единственный распался.",
	"Пустота снова молчит.",
]
const DISTANT_DEBRIS := 46
## The boss bar darkens and burns paler as the Only One comes apart.
const PHASE_COLORS: Array[Color] = [Color(0.56, 0.36, 0.92), Color(0.5, 0.28, 0.9),
	Color(0.66, 0.3, 0.86), Color(0.86, 0.8, 1.0)]
## Said after a fall at a crossing that needs more than a step.
const HINT_LEAP := "Слишком далеко для шага. Разбегись: Ctrl на ходу."
const HINT_FLIGHT := "Шагом здесь не пройти. Взлети: Shift."
const HINT_FERRY := "Обломок плывёт. Дождись, пока он подойдёт."
const HINT_RIDE := "Дождись, пока обломок доплывёт до следующего."
const HINT_FLICKER := "Осколок то есть, то нет. Ступай, пока он виден."

var data: NelvarVoidData
var debris_nodes: Array[NelvarVoidDebris] = []
var monolith_node: NelvarVoidDebris

var _time := 0.0
var _air_time := 0.0
var _safe_position := Vector2.ZERO
var _falls := 0
## The route piece the player last stood on; a fall is explained by its crossing.
var _last_route_index := 0
var _message_tween: Tween
var _sky_material: ShaderMaterial
## Worker painting the monolith (it is big; the player is far from it at first);
## its result is picked up in _process once the task is done.
var _monolith_task := -1
var _monolith_result: NelvarDebrisPainter.Art
var _chip_tween: Tween
var _refill_tween: Tween
var _boss_pips: NelvarVoidBossPips
## A bright sliver riding the end of the bar while it fills up for a new phase.
var _boss_glint: ColorRect
## A soft highlight gliding along the boss bar, and how the bar shakes when hit.
var _boss_sheen: ColorRect
var _boss_shake := 0.0
var _boss_bar_home := Vector2.INF
var _boss_last_health := -1.0
var _boss_time := 0.0
var _title_tween: Tween
## Opened from the run's checkpoint (NelvarRunState.void_checkpoint): a lost boss fight
## comes back with the same seed, the player at the arena's door.
var _from_checkpoint := false

@onready var sky: NelvarCloudSea = $Sky
@onready var distant: Parallax2D = $Distant
@onready var world_layer: Node2D = $World
@onready var actors: Node2D = $Actors
@onready var arena: NelvarVoidArena = $Actors/Arena
@onready var motes: NelvarWindParticles = $Motes
@onready var shade: ColorRect = $Shade/Vignette
## The story's lines at the bottom of the screen (_say), the Void's own.
@onready var narration: Label = $BossHud/Message
@onready var boss_bar: Control = $BossHud/BossBar
@onready var boss_fill: ColorRect = $BossHud/BossBar/Bar/Fill
@onready var boss_chip: ColorRect = $BossHud/BossBar/Bar/Chip
@onready var boss_title: Control = $BossHud/BossTitle
@onready var boss_title_label: Label = $BossHud/BossTitle/Title
@onready var boss_subtitle: Label = $BossHud/BossTitle/Subtitle
@onready var boss_phase: Label = $BossHud/BossBar/Hint


## The run's checkpoint brings back the Void of a lost fight (the tests' seed_override
## still wins: they pick a seed with the crossings they need).
func _pick_seed() -> int:
	if not has_meta("seed_override") and player.run.void_checkpoint >= 0:
		_from_checkpoint = true
		return player.run.void_checkpoint
	return super()


func _build() -> void:
	player.run.void_checkpoint = -1
	data = NelvarVoidGenerator.new().generate(world_seed)
	if data == null:
		fail("Пустота не сложилась")
		return
	var screen := NelvarVoidScreen.new()
	screen.name = "Screen"
	add_child(screen)
	_build_world()
	var threads := NelvarVoidThreads.new()
	threads.name = "Threads"
	threads.setup(data)
	world_layer.add_child(threads)
	_build_distant()
	_sky_material = sky.backdrop_material()
	sky.set_world_seed(world_seed)
	motes.color = Color(0.66, 0.52, 1.0, 0.5)
	arena.setup(data, player, monolith_node, world_layer)
	arena.fight_started.connect(_on_fight_started)
	arena.fight_won.connect(_on_fight_won)
	player.died.connect(_on_player_died)
	player.position = data.spawn_position
	if _from_checkpoint:
		# The causeway in front of the monolith.
		player.position = data.debris[data.route[data.route.size() - 1]].position
	_safe_position = player.position
	_last_route_index = data.route.find(data.support_at(player.position, 0.0).id) \
		if data.support_at(player.position, 0.0) != null else 0
	player.camera.reset_smoothing()
	narration.modulate.a = 0.0
	boss_bar.hide()
	show_seed()
	status_label.text = "%d обломков на пути · %d всего · %d разбегов · %d перелётов" % [
		data.route.size(), data.debris.size(), data.count_gaps(NelvarVoidData.Gap.LEAP),
		data.count_gaps(NelvarVoidData.Gap.FLIGHT)]
	print("Nelvar Void seed: %d | route: %d | debris: %d | leaps: %d | flights: %d | ferries: %d | flickers: %d" % [
		data.world_seed, data.route.size(), data.debris.size(), data.count_gaps(NelvarVoidData.Gap.LEAP),
		data.count_gaps(NelvarVoidData.Gap.FLIGHT), data.count_motion(NelvarVoidData.Motion.FERRY),
		data.count_motion(NelvarVoidData.Motion.FLICKER)])
	if _from_checkpoint:
		_say(RETRY_LINES, 0.6)
	else:
		_say(OPENING_LINES, 1.2)


func _build_world() -> void:
	var painter := NelvarDebrisPainter.new()
	monolith_node = NelvarVoidDebris.new()
	monolith_node.setup(data.monolith, NelvarDebrisPainter.cached_monolith())
	world_layer.add_child(monolith_node)
	if monolith_node.art == null:
		_monolith_task = WorkerThreadPool.add_task(_paint_monolith, false, "Void monolith")
	for piece in data.debris:
		var node := NelvarVoidDebris.new()
		node.setup(piece, painter.paint(piece))
		world_layer.add_child(node)
		debris_nodes.append(node)


## Runs on a worker thread: pixels only, textures are made on the main thread.
func _paint_monolith() -> void:
	_monolith_result = NelvarDebrisPainter.new().paint_images(data.monolith)


func _process(delta: float) -> void:
	_animate_boss_bar(delta)
	if _monolith_task >= 0 and WorkerThreadPool.is_task_completed(_monolith_task):
		WorkerThreadPool.wait_for_task_completion(_monolith_task)
		_monolith_task = -1
		var art := _monolith_result.bake()
		NelvarDebrisPainter.remember_monolith(art)
		monolith_node.set_art(art)


func _exit_tree() -> void:
	if _monolith_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_monolith_task)
		_monolith_task = -1


## Lost the fight: the run's next Void (the scene reloads) starts at the arena.
func _on_player_died() -> void:
	if arena.started and not arena.boss_defeated:
		player.run.void_checkpoint = data.world_seed


## Far-off debris drifting deep in the Void: dim silhouettes on a slow parallax layer.
func _build_distant() -> void:
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
	if support != null and support.on_route:
		_last_route_index = data.route.find(support.id)
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
	var hint := _fall_hint()
	if not hint.is_empty():
		_say([hint], 0.2, 2.6)


## What the crossing the player fell at takes, if more than a step.
func _fall_hint() -> String:
	if _last_route_index < 0 or _last_route_index >= data.route.size():
		return ""
	var here := data.debris[data.route[_last_route_index]]
	if here.motion == NelvarVoidData.Motion.FERRY:
		return HINT_RIDE
	if _last_route_index + 1 < data.route.size():
		var there := data.debris[data.route[_last_route_index + 1]]
		if there.motion == NelvarVoidData.Motion.FERRY:
			return HINT_FERRY
		if there.motion == NelvarVoidData.Motion.FLICKER:
			return HINT_FLICKER
	if here.gap == NelvarVoidData.Gap.LEAP:
		return HINT_LEAP
	if here.gap == NelvarVoidData.Gap.FLIGHT:
		return HINT_FLIGHT
	return ""


func _on_fight_started() -> void:
	_say(ARENA_LINES, 0.6)
	var boss := arena.boss
	boss.health_changed.connect(_on_boss_health)
	boss.phase_changed.connect(_on_boss_phase)
	boss_phase.text = boss.phase_title()
	_add_phase_pips()
	_show_title(NelvarTheOne.DISPLAY_NAME.to_upper(), "Пустота обрела форму", 1.4)
	boss_bar.modulate.a = 0.0
	boss_bar.show()
	var tween := create_tween().set_parallel()
	tween.tween_property(boss_bar, "modulate:a", 1.0, 1.5).set_delay(1.0)
	tween.tween_method(_set_dread, 0.0, 1.0, 6.0).set_trans(Tween.TRANS_SINE)
	tween.tween_property(shade, "modulate:a", 1.0, 3.0)
	_shake(0.7, 6.0)


func _on_boss_health(current: float, maximum: float) -> void:
	if current < _boss_last_health:
		_on_boss_hit(_boss_last_health - current)
	_boss_last_health = current
	# While the bar fills up for a new phase it runs on its own.
	if _refill_tween != null and _refill_tween.is_running():
		return
	# Whole pixels of the bar, not a smooth slide; the pale chip catches up later.
	var right := _bar_right(current / maxf(maximum, 1.0))
	boss_fill.offset_right = right
	if _chip_tween != null:
		_chip_tween.kill()
	_chip_tween = create_tween()
	_chip_tween.tween_interval(0.35)
	_chip_tween.tween_property(boss_chip, "offset_right", right, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## A hit: the bar jolts and its frame flashes pale, more for bigger hits.
func _on_boss_hit(amount: float) -> void:
	_boss_shake = clampf(0.08 + amount / 400.0, 0.08, 0.3)
	var edge := boss_fill.get_parent_control().get_node_or_null("Edge") as ReferenceRect
	if edge == null:
		return
	edge.border_color = Color(0.95, 0.9, 1.0)
	var tween := edge.create_tween()
	tween.tween_property(edge, "border_color", Color(0.5, 0.34, 0.82), 0.25)


## Shake and sheen of the boss bar, every frame while it is shown.
func _animate_boss_bar(delta: float) -> void:
	if not boss_bar.visible or _boss_sheen == null:
		return
	_boss_time += delta
	if _boss_bar_home == Vector2.INF:
		_boss_bar_home = boss_bar.position
	_boss_shake = maxf(_boss_shake - delta, 0.0)
	var jolt := Vector2.ZERO
	if _boss_shake > 0.0:
		jolt = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).round() * 3.0 * ceilf(_boss_shake * 10.0)
	boss_bar.position = _boss_bar_home + jolt
	var width := boss_fill.size.x
	var run := fmod(_boss_time * 420.0, width + 500.0) - 60.0
	_boss_sheen.position = Vector2(roundf(run / 3.0) * 3.0, 0.0)
	_boss_sheen.size = Vector2(36.0, boss_fill.size.y)


## The fill's right offset for `share` of the bar, snapped to whole art pixels.
func _bar_right(share: float) -> float:
	var width := boss_fill.get_parent_control().size.x - 6.0
	return -3.0 - roundf(width * (1.0 - clampf(share, 0.0, 1.0)) / 3.0) * 3.0


## One diamond per phase under the bar, and the glint for refilling.
func _add_phase_pips() -> void:
	var bar := boss_fill.get_parent_control()
	if _boss_pips == null:
		_boss_pips = NelvarVoidBossPips.new()
		_boss_pips.name = "Phases"
		_boss_pips.count = NelvarTheOne.PHASE_COUNT
		boss_bar.add_child(_boss_pips)
		boss_bar.move_child(_boss_pips, bar.get_index() + 1)
		_boss_glint = ColorRect.new()
		_boss_glint.color = Color(1.0, 0.97, 1.0)
		_boss_glint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_boss_glint.anchor_bottom = 1.0
		_boss_glint.offset_top = -3.0
		_boss_glint.offset_bottom = 3.0
		_boss_glint.hide()
		bar.add_child(_boss_glint)
		boss_fill.clip_contents = true
		_boss_sheen = ColorRect.new()
		_boss_sheen.color = Color(1.0, 0.95, 1.0, 0.22)
		_boss_sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		boss_fill.add_child(_boss_sheen)
	_boss_pips.set_phase(0)


## The bar of the broken phase is empty; it fills again in the new phase's colour,
## the pale chip racing ahead and a glint riding the end of the fill.
func _refill_boss_bar(color: Color) -> void:
	if _chip_tween != null:
		_chip_tween.kill()
	if _refill_tween != null:
		_refill_tween.kill()
	boss_fill.color = color
	boss_fill.offset_right = _bar_right(0.0)
	boss_chip.offset_right = _bar_right(0.0)
	_refill_tween = create_tween()
	_refill_tween.tween_interval(0.25)
	_refill_tween.tween_callback(_boss_glint.show)
	_refill_tween.tween_method(_set_refill, 0.0, 1.0, 0.95).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_refill_tween.tween_callback(_boss_glint.hide)


func _set_refill(share: float) -> void:
	boss_fill.offset_right = _bar_right(share)
	boss_chip.offset_right = _bar_right(minf(share * 1.25, 1.0))
	var width := boss_fill.get_parent_control().size.x
	var at := width + boss_fill.offset_right
	_boss_glint.offset_left = at - 3.0
	_boss_glint.offset_right = at + 3.0
	_boss_glint.modulate.a = 0.6 + 0.4 * sin(share * 40.0)


## A big title in the middle of the screen: letters appear, hold, fade.
func _show_title(title: String, subtitle: String, hold: float) -> void:
	if _title_tween != null:
		_title_tween.kill()
	boss_title_label.text = title
	boss_subtitle.text = subtitle
	boss_title_label.visible_ratio = 0.0
	boss_title.modulate.a = 1.0
	boss_subtitle.modulate.a = 0.0
	boss_title.show()
	_title_tween = create_tween()
	_title_tween.tween_property(boss_title_label, "visible_ratio", 1.0, 0.6)
	_title_tween.tween_property(boss_subtitle, "modulate:a", 1.0, 0.4)
	_title_tween.tween_interval(hold)
	_title_tween.tween_property(boss_title, "modulate:a", 0.0, 0.8)
	_title_tween.tween_callback(boss_title.hide)


func _on_boss_phase(phase: int) -> void:
	boss_phase.text = arena.boss.phase_title()
	_show_title(NelvarTheOne.PHASE_TITLES[phase].to_upper(), NelvarTheOne.PHASE_NUMERALS[phase], 0.9)
	_refill_boss_bar(PHASE_COLORS[phase])
	_boss_pips.set_phase(phase)
	_shake(0.9, 9.0)
	# The Void flinches with it.
	var tween := create_tween()
	tween.tween_method(_set_dread, 1.0, 1.6, 0.4)
	tween.tween_method(_set_dread, 1.6, 1.0, 1.2)


func _on_fight_won() -> void:
	_say(VICTORY_LINES, 2.6)
	_show_title("ЕДИНСТВЕННЫЙ РАСПАЛСЯ", "", 1.4)
	var tween := create_tween().set_parallel()
	tween.tween_property(boss_bar, "modulate:a", 0.0, 2.0)
	tween.tween_method(_set_dread, 1.0, 0.0, 5.0)
	tween.tween_property(shade, "modulate:a", 0.75, 4.0)
	_shake(1.0, 7.0)


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
func _say(lines: Array[String], delay: float, hold: float = MESSAGE_HOLD) -> void:
	if _message_tween != null:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(delay)
	for line in lines:
		_message_tween.tween_callback(narration.set_text.bind(line))
		_message_tween.tween_property(narration, "modulate:a", 1.0, MESSAGE_FADE)
		_message_tween.tween_interval(hold)
		_message_tween.tween_property(narration, "modulate:a", 0.0, MESSAGE_FADE)
		_message_tween.tween_interval(0.4)

