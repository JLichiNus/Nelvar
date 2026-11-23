class_name NelvarTheOneBody
extends Node2D
## The look of the Only One: one figure that the four phases bend out of shape
## instead of four models.
##
##   I   — a hunched humanoid with uneven arms and an empty face; it walks, now and
##         then freezing in a pose no body should take.
##   II  — the limbs come loose: an empty gap opens between shoulder and arm, the
##         arm moves on as if attached. The cracks burn brighter.
##   III — it stretches and squashes in jerks, parts blink out and come back, every
##         movement snaps instead of flowing.
##   IV  — only a humanoid silhouette is left, edges crawling, fragments of the old
##         form inside; it hardly touches the ground.
##
## Throughout, its contours lag behind it: each part leaves its outline where it
## was a moment ago, as if space could not keep up (see _draw_ghosts).
## The boss (NelvarTheOne) sets `pose`, `aim` and `phase`; the origin is the ground
## between its feet.

const FORM_SHADER := preload("res://scripts/void/boss/the_one_form.gdshader")
const WINDOW_SHADER := preload("res://scripts/void/boss/the_one_window.gdshader")
## Light it casts on the arena, per phase; sparks rising from its cracks, per phase.
const LIGHT_ENERGY: Array[float] = [0.85, 1.0, 1.15, 1.3]
## The glowing rim along its silhouette, per phase.
const RIM: Array[float] = [0.4, 0.5, 0.6, 0.0]
const SPARKS: Array[int] = [10, 18, 28, 40]
const LIGHT_HEIGHT := 80.0
const TEXEL := NelvarTheOnePainter.TEXEL
const PART_ORDER: Array[String] = ["leg_r", "leg_l", "arm_r", "torso", "head", "arm_l"]
## How far behind its part a contour lags, seconds, per phase.
const GHOST_DELAY: Array[float] = [0.09, 0.12, 0.16, 0.22]
const HISTORY_TIME := 0.7
const GLOW_STRENGTH: Array[float] = [0.3, 0.7, 0.85, 1.0]
## Phase II: the empty gap between torso and limbs, texels.
const LIMB_GAP := 5.0

## The current action; see _targets for the list.
var pose := &"idle"
## Direction to the player (world); the body faces it and aims the arms along it.
var aim := Vector2.DOWN
var phase := 0
## Stretch of the left arm (it grows longer when it strikes).
var reach := 1.0
## 1 = solid, 0 = gone (blinking across the arena, dying).
var presence := 1.0

var _form: CanvasGroup
var _rig: Node2D
var _pool: Node2D
var _light: PointLight2D
var _flare := 0.0
var _ash: CPUParticles2D
var _sparks: CPUParticles2D
var _window_material: ShaderMaterial
var _shown_phase := -1
var _ghosts: Node2D
var _material: ShaderMaterial
var _sprites := {}
var _glows := {}
var _contours := {}
var _rest := {}
var _time := 0.0
var _flip := 1.0
var _flash_tween: Tween
## Pose snapshot used in phase III: updated in jerks.
var _snap_time := 0.0
var _snapped := {}
## Recent global transforms of the parts: [[time, {part: Transform2D}, {part: visible}], ...]
var _history: Array = []
## Per part: extra lag while its contour "sticks" in place.
var _stutter := {}
var _next_stutter := 2.0
var _vanish := {}
var _next_vanish := 1.0
var _stretch := 1.0
var _next_stretch := 0.6
var _twitch := 0.0
var _twitch_left := 0.0
var _next_twitch := 2.5
var _glitch := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# A pool of the Void under its feet instead of a shadow.
	_pool = Node2D.new()
	_pool.name = "Pool"
	_pool.z_index = -1
	_pool.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pool.draw.connect(_draw_pool)
	add_child(_pool)
	_light = NelvarVoidFx.make_light(NelvarVoidFx.VIOLET, LIGHT_ENERGY[0], 400.0)
	_light.position = Vector2(0.0, -LIGHT_HEIGHT * 0.5)
	add_child(_light)
	# Dark ash drifting off the body, violet sparks rising from the cracks.
	_ash = NelvarVoidFx.spark_emitter(Color(0.04, 0.02, 0.08, 0.9), false)
	_sparks = NelvarVoidFx.spark_emitter(NelvarVoidFx.VIOLET)
	for emitter: CPUParticles2D in [_ash, _sparks]:
		emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		emitter.emission_rect_extents = Vector2(20.0, 52.0)
		emitter.position = Vector2(0.0, -72.0)
		emitter.direction = Vector2(0.0, -1.0)
		emitter.spread = 25.0
		emitter.gravity = Vector2(0.0, -30.0)
		emitter.initial_velocity_min = 10.0
		emitter.initial_velocity_max = 45.0
		emitter.lifetime = 1.6
		emitter.emitting = true
		add_child(emitter)
	_ash.amount = 26
	_sparks.amount = SPARKS[0]
	_sparks.lifetime = 1.1
	_form = CanvasGroup.new()
	_form.name = "Form"
	_form.fit_margin = 16.0
	_form.clear_margin = 16.0
	_material = ShaderMaterial.new()
	_material.shader = FORM_SHADER
	_form.material = _material
	add_child(_form)
	_rig = Node2D.new()
	_rig.name = "Rig"
	_form.add_child(_rig)
	var parts := NelvarTheOnePainter.parts()
	for name: String in PART_ORDER:
		var part: NelvarTheOnePainter.Part = parts[name]
		var sprite := Sprite2D.new()
		sprite.name = name
		sprite.texture = part.texture
		sprite.centered = false
		sprite.offset = -part.pivot
		sprite.scale = Vector2.ONE * TEXEL
		var glow := Sprite2D.new()
		glow.texture = part.glow
		glow.centered = false
		glow.offset = -part.pivot
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = add
		sprite.add_child(glow)
		if part.hole != null:
			# The hole in the chest looks into the Void, not at the floor behind it.
			var window := Sprite2D.new()
			window.name = "Window"
			window.texture = part.hole
			window.centered = false
			window.offset = -part.pivot
			_window_material = ShaderMaterial.new()
			_window_material.shader = WINDOW_SHADER
			window.material = _window_material
			sprite.add_child(window)
		_rig.add_child(sprite)
		_sprites[name] = sprite
		_glows[name] = glow
		_contours[name] = part.contour
		_rest[name] = {"rotation": 0.0, "offset": Vector2.ZERO, "scale": 1.0}
		_stutter[name] = 0.0
		_vanish[name] = 0.0
	_ghosts = Node2D.new()
	_ghosts.name = "Contours"
	_ghosts.top_level = true
	_ghosts.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ghosts.draw.connect(_draw_ghosts)
	add_child(_ghosts)
	_update(0.0)


func flash() -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	_material.set_shader_parameter("flash", 0.75)
	_flash_tween = create_tween()
	_flash_tween.tween_method(func(v: float) -> void: _material.set_shader_parameter("flash", v),
		0.75, 0.0, 0.14)


## Its light flares up for a moment (an attack, a hit, a phase change).
func flare(amount: float) -> void:
	_flare = maxf(_flare, amount)


## A full violet copy of the body where it stands now, fading out (dashes).
func afterimage() -> void:
	var image := Afterimage.new()
	image.top_level = true
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for name: String in PART_ORDER:
		var sprite: Sprite2D = _sprites[name]
		image.parts.append([sprite.texture, sprite.global_transform, sprite.offset])
	image.z_index = -1
	add_child(image)


class Afterimage:
	extends Node2D
	var parts: Array = []
	var age := 0.0
	const LIFE := 0.4

	func _process(delta: float) -> void:
		age += delta
		if age >= LIFE:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var fade := 1.0 - age / LIFE
		for part: Array in parts:
			draw_set_transform_matrix(part[1])
			draw_texture(part[0], part[2], Color(0.55, 0.3, 1.0, 0.55 * fade))
		draw_set_transform_matrix(Transform2D.IDENTITY)


## The body convulses for `duration`: everything jerks, contours lag far behind.
func glitch(duration: float) -> void:
	_glitch = maxf(_glitch, duration)


func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	_time += delta
	_glitch = maxf(0.0, _glitch - delta)
	if absf(aim.x) > 0.15:
		_flip = signf(aim.x)
	_update_quirks(delta)
	var targets := _targets()
	# Phase III and convulsions: the pose jumps in steps instead of flowing.
	var jerky := phase >= 2 or _glitch > 0.0
	if jerky:
		_snap_time -= delta
		if _snap_time <= 0.0 or _snapped.is_empty():
			_snapped = targets
			_snap_time = 0.11 if phase >= 2 else 0.06
		targets = _snapped
	var rate := 1.0 - exp(-(40.0 if jerky else 13.0) * delta)
	for name: String in PART_ORDER:
		var target: Dictionary = targets[name]
		var rest: Dictionary = _rest[name]
		rest["rotation"] = lerp_angle(rest["rotation"], target["rotation"], rate)
		rest["offset"] = (rest["offset"] as Vector2).lerp(target["offset"], rate)
		rest["scale"] = lerpf(rest["scale"], target["scale"], rate)
	_apply()
	_record()
	_ghosts.queue_redraw()


## Places the parts: torso on the hips, head and arms on the torso, legs below.
func _apply() -> void:
	var hover := 0.0
	if phase >= 3:
		hover = -14.0 + 3.0 * sin(_time * 2.1)
	_rig.scale = Vector2(_flip / sqrt(_stretch), _stretch)
	_rig.position = Vector2(0.0, hover)
	if _glitch > 0.0:
		_rig.position += Vector2(randf_range(-4.0, 4.0), randf_range(-3.0, 3.0)).round()
	var torso: Sprite2D = _sprites["torso"]
	var torso_rest: Dictionary = _rest["torso"]
	torso.position = Vector2(0.0, -NelvarTheOnePainter.HIP_HEIGHT) + torso_rest["offset"]
	torso.rotation = torso_rest["rotation"]
	torso.scale = Vector2.ONE * TEXEL * Vector2(1.0, torso_rest["scale"])
	var gap := Vector2.ZERO
	if phase >= 1:
		gap = Vector2(LIMB_GAP, -1.5) * TEXEL
	var anchors := {
		"head": NelvarTheOnePainter.NECK,
		"arm_l": NelvarTheOnePainter.SHOULDER_L + gap,
		"arm_r": NelvarTheOnePainter.SHOULDER_R + Vector2(-gap.x, gap.y),
	}
	for name: String in anchors:
		var sprite: Sprite2D = _sprites[name]
		var rest: Dictionary = _rest[name]
		var anchor: Vector2 = anchors[name]
		anchor.y *= torso_rest["scale"]
		sprite.position = torso.position + anchor.rotated(torso.rotation) + rest["offset"]
		sprite.rotation = torso.rotation + rest["rotation"]
		var length: float = rest["scale"] * (reach if name == "arm_l" else 1.0)
		sprite.scale = Vector2.ONE * TEXEL * Vector2(1.0, length)
	for name: String in ["leg_l", "leg_r"]:
		var sprite: Sprite2D = _sprites[name]
		var rest: Dictionary = _rest[name]
		var hip := NelvarTheOnePainter.HIP_L if name == "leg_l" else NelvarTheOnePainter.HIP_R
		if phase >= 1:
			hip.y += 1.5 * TEXEL
		sprite.position = Vector2(0.0, -NelvarTheOnePainter.HIP_HEIGHT) + hip + rest["offset"]
		sprite.rotation = rest["rotation"]
		sprite.scale = Vector2.ONE * TEXEL * Vector2(1.0, rest["scale"])
	# Visibility: parts blinking out (III), dangling legs and the silhouette (IV).
	for name: String in PART_ORDER:
		var sprite: Sprite2D = _sprites[name]
		var alpha := 0.0 if _vanish[name] > 0.0 else 1.0
		if phase >= 3 and name.begins_with("leg"):
			alpha *= 0.4
		sprite.self_modulate.a = alpha
		var glow: Sprite2D = _glows[name]
		var strength: float = GLOW_STRENGTH[phase]
		glow.modulate.a = alpha * strength * (0.75 + 0.25 * sin(_time * 3.0 + name.length()))
	_form.modulate.a = presence
	_pool.queue_redraw()
	_flare = maxf(0.0, _flare - get_process_delta_time() * 2.5)
	_light.energy = (LIGHT_ENERGY[phase] * (0.85 + 0.15 * sin(_time * 2.3)) + _flare) * presence
	_light.position.y = _rig.position.y - LIGHT_HEIGHT
	if _shown_phase != phase:
		_shown_phase = phase
		_sparks.amount = SPARKS[phase]
		_sparks.color = NelvarVoidFx.PALE if phase >= 3 else NelvarVoidFx.VIOLET
	_ash.emitting = presence > 0.3
	_sparks.emitting = presence > 0.3
	if _window_material != null:
		_window_material.set_shader_parameter("time", _time)
		_window_material.set_shader_parameter("intensity", 0.6 + GLOW_STRENGTH[phase] * 0.6)
	_material.set_shader_parameter("time", _time)
	_material.set_shader_parameter("void_amount", 1.0 if phase >= 3 else 0.0)
	_material.set_shader_parameter("rim_amount", clampf(RIM[phase] * (0.8 + 0.2 * sin(_time * 3.0)) + _flare * 0.3, 0.0, 1.0))
	var crawl := 0.0
	if phase >= 3:
		crawl = 3.0
	elif phase >= 2:
		crawl = 0.8
	if _glitch > 0.0:
		crawl = maxf(crawl, 4.0)
	_material.set_shader_parameter("distort", crawl)


## The pose to move towards: rotation, offset and length per part.
func _targets() -> Dictionary:
	var t := _time
	var local_aim := Vector2(aim.x * _flip, aim.y).normalized()
	var aim_angle := local_aim.angle() - PI / 2.0
	var result := {}
	for name: String in PART_ORDER:
		result[name] = {"rotation": 0.0, "offset": Vector2.ZERO, "scale": 1.0}
	# Hunched by default, the head hanging aside.
	result["torso"]["rotation"] = 0.14 + 0.03 * sin(t * 1.3)
	result["torso"]["offset"] = Vector2(0.0, roundf(sin(t * 1.7)) * TEXEL * 0.5)
	result["head"]["rotation"] = 0.42 + _twitch
	# Rotation > 0 swings a hanging limb backwards (away from the player it faces).
	result["arm_l"]["rotation"] = -0.08 + 0.05 * sin(t * 1.1)
	result["arm_r"]["rotation"] = 0.12 + 0.04 * sin(t * 1.4 + 1.0)
	result["leg_l"]["rotation"] = -0.14
	result["leg_r"]["rotation"] = 0.12
	match pose:
		&"walk":
			var swing := sin(t * 6.5)
			result["leg_l"]["rotation"] = 0.38 * swing
			result["leg_r"]["rotation"] = -0.38 * swing
			result["arm_l"]["rotation"] = -0.08 - 0.12 * swing
			result["arm_r"]["rotation"] = 0.12 + 0.2 * swing
			result["torso"]["offset"] = Vector2(0.0, -absf(swing) * TEXEL)
		&"windup":
			result["torso"]["rotation"] = -0.2
			result["torso"]["scale"] = 0.9
			result["arm_l"]["rotation"] = 1.0
			result["arm_r"]["rotation"] = 0.7
			result["leg_l"]["rotation"] = 0.3
			result["leg_r"]["rotation"] = -0.4
			result["head"]["rotation"] = 0.9
		&"dash":
			result["torso"]["rotation"] = 0.55
			result["arm_l"]["rotation"] = 1.35
			result["arm_r"]["rotation"] = 1.1
			result["leg_l"]["rotation"] = 0.7
			result["leg_r"]["rotation"] = 0.9
			result["head"]["rotation"] = 0.15
		&"cast":
			result["torso"]["rotation"] = -0.05
			result["arm_l"]["rotation"] = -2.6 + 0.1 * sin(t * 9.0)
			result["arm_r"]["rotation"] = 2.7 + 0.1 * sin(t * 8.0)
			result["head"]["rotation"] = -0.35
		&"swipe":
			result["torso"]["rotation"] = 0.35
			result["arm_l"]["rotation"] = aim_angle
			result["arm_r"]["rotation"] = 0.6
			result["head"]["rotation"] = 0.8
		&"spread":
			result["torso"]["rotation"] = 0.0
			result["arm_l"]["rotation"] = -1.55 + 0.08 * sin(t * 4.0)
			result["arm_r"]["rotation"] = 1.55 - 0.08 * sin(t * 4.0)
			result["head"]["rotation"] = 0.0
			result["leg_l"]["rotation"] = 0.2
			result["leg_r"]["rotation"] = -0.2
	# Phase II: loose limbs keep swaying on their own.
	if phase >= 1:
		result["arm_l"]["offset"] = Vector2(sin(t * 2.3), cos(t * 1.9)) * TEXEL
		result["arm_r"]["offset"] = Vector2(cos(t * 2.1), sin(t * 2.7)) * TEXEL
	if _glitch > 0.0:
		for name: String in PART_ORDER:
			result[name]["rotation"] += randf_range(-0.5, 0.5)
	return result


## Unnatural twitches (I+), contours sticking (all), stretching and parts blinking
## out (III+).
func _update_quirks(delta: float) -> void:
	_next_twitch -= delta
	_twitch_left -= delta
	if _twitch_left <= 0.0:
		_twitch = 0.0
	if _next_twitch <= 0.0:
		_twitch = [-1.1, 0.9, 1.4][randi() % 3]
		_twitch_left = randf_range(0.25, 0.5)
		_next_twitch = randf_range(2.0, 4.5)
	_next_stutter -= delta
	for name: String in PART_ORDER:
		_stutter[name] = maxf(0.0, _stutter[name] - delta)
		_vanish[name] = maxf(0.0, _vanish[name] - delta)
	if _next_stutter <= 0.0:
		_stutter[PART_ORDER.pick_random()] = randf_range(0.3, 0.5)
		_next_stutter = randf_range(0.8, 2.2) / (1.0 + phase * 0.6)
	if phase < 2:
		_stretch = 1.0
		return
	_next_vanish -= delta
	if _next_vanish <= 0.0:
		_vanish[PART_ORDER.pick_random()] = randf_range(0.1, 0.18)
		_next_vanish = randf_range(0.5, 1.1)
	_next_stretch -= delta
	if _next_stretch <= 0.0:
		_stretch = [0.8, 1.0, 1.0, 1.25][randi() % 4]
		_next_stretch = randf_range(0.35, 0.8)


func _record() -> void:
	var transforms := {}
	for name: String in PART_ORDER:
		transforms[name] = (_sprites[name] as Sprite2D).global_transform
	_history.push_front([_time, transforms])
	while _history.size() > 2 and _time - _history[_history.size() - 1][0] > HISTORY_TIME:
		_history.pop_back()


## Each part's contour, drawn where the part was `delay` seconds ago.
func _draw_ghosts() -> void:
	if _history.is_empty() or presence <= 0.01 and phase < 3:
		return
	for name: String in PART_ORDER:
		var delay: float = GHOST_DELAY[phase] + _stutter[name] + (0.15 if _glitch > 0.0 else 0.0)
		var then := _transform_at(name, delay)
		var now: Transform2D = _history[0][1][name]
		var drift := then.origin.distance_to(now.origin) + absf(then.get_rotation() - now.get_rotation()) * 40.0
		# Sitting on its part the contour is hidden; only where it trails does it show.
		var alpha := clampf((drift - 1.5) * 0.06, 0.0, 0.7)
		if phase >= 3:
			alpha = maxf(alpha, 0.4)
			then.origin += Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0)).round()
		alpha *= maxf(presence, 0.35)
		var sprite: Sprite2D = _sprites[name]
		_ghosts.draw_set_transform_matrix(then)
		_ghosts.draw_texture(_contours[name], sprite.offset, Color(1.0, 1.0, 1.0, alpha))
	_ghosts.draw_set_transform_matrix(Transform2D.IDENTITY)


func _transform_at(name: String, delay: float) -> Transform2D:
	var wanted := _time - delay
	for entry: Array in _history:
		if entry[0] <= wanted:
			return entry[1][name]
	return _history[_history.size() - 1][1][name]


## The pool of the Void under it: a dithered dark ellipse on the art grid with a
## cold rim and tendrils that crawl out and back. Smaller when it hovers (IV).
func _draw_pool() -> void:
	var size := Vector2(52.0, 18.0) * (0.75 if phase >= 3 else 1.0) * (0.6 + 0.4 * presence)
	if presence <= 0.01:
		return
	for y in range(-int(size.y), int(size.y) + 1, 3):
		for x in range(-int(size.x), int(size.x) + 1, 3):
			var d := Vector2(x / size.x, y / size.y).length_squared()
			if d > 1.0:
				continue
			var cell := Vector2i(x / 3, y / 3)
			if d > 0.6 and (1.0 - d) / 0.4 * 16.0 < NelvarPixelArt.bayer(cell) + 0.5:
				continue
			var color := NelvarVoidFx.DARK
			color.a = 0.8 * presence
			if d > 0.78:
				color = NelvarVoidFx.DEEP
				color.a = 0.55 * presence
			_pool.draw_rect(Rect2(x, y, 3.0, 3.0), color)
	# Tendrils: a few dotted strands that reach out and pull back.
	var tendril := NelvarVoidFx.DEEP
	for i in 6:
		var angle := TAU * i / 6.0 + 0.4 * sin(_time * 0.7 + i)
		var length := (0.4 + 0.6 * (0.5 + 0.5 * sin(_time * 1.3 + i * 1.7))) * size.x * 0.9
		for step in range(0, int(length), 4):
			var along := float(step)
			var wave := sin(along * 0.12 + _time * 3.0 + i) * 4.0
			var point := Vector2.from_angle(angle) * Vector2(1.0, 0.36) * (size.x * 0.8 + along)
			point += Vector2.from_angle(angle).orthogonal() * wave * 0.4
			tendril.a = (1.0 - along / maxf(length, 1.0)) * 0.7 * presence
			_pool.draw_rect(Rect2((point / 3.0).floor() * 3.0, Vector2(3.0, 3.0)), tendril)
