class_name NelvarWhistler
extends CharacterBody2D
## Свистун: a hollow sack of dry reed (straw-coloured, so it stands out from
## the green islands) rooted in the ground, with a tube for a mouth
## that turns after the player. It hardly moves. It draws air in — swells,
## quivers, the air streams into the tube and it whistles higher and higher:
## that is the warning — and blows slow soap bubbles: a fan of 3–5, or now and
## then a trill of three one after another, each aimed anew.
##
## The LMB shot bursts a bubble, the RMB wave sends it back (whistler_bubble),
## R compression breaks off the breath. Touching it hurts only a little.

const BUBBLE_SCENE := preload("res://enemies/whistler/whistler_bubble.tscn")
const TRAIL_SCRIPT := preload("res://attacks/wind_projectile/wind_projectile_trail.gd")
const DIRECTIONS := 16
## The art canvas, in texels; the sack's centre is the node origin.
const CANVAS := Vector2i(31, 37)
const SACK_CENTER := Vector2(15.5, 22.5)
const SACK_RADII := Vector2(7.6, 6.6)
const NOZZLE_BASE := Vector2(15.5, 21.5)
## The tube grows out of the sack this far from NOZZLE_BASE and ends (the
## mouth) at NOZZLE_LENGTH, so it never crosses the face.
const NOZZLE_START := 4.0
const NOZZLE_LENGTH := 10.0
const NOZZLE_HALF_WIDTH := 2.2
const MOUTH_RADIUS := 2.9
## Feet (and shadow) below the origin, world units.
const FEET := 16.0
## Height of the mouth above the ground: bubbles float at it.
const MOUTH_HEIGHT := 19.0

enum State { IDLE, INHALE, BLOW, RECOVER, DEAD }
enum Pattern { FAN, TRILL }
enum Eyes { LEFT, CENTER, RIGHT, CLOSED }

@export_category("Health")
@export var max_health: float = 45.0
@export var contact_damage: float = 6.0
@export var hit_flash_color := Color(2.0, 2.0, 2.0)
@export var hit_flash_duration: float = 0.1
@export var death_duration: float = 0.5

@export_category("Attack")
## The player must be this close (from the feet) for it to start a breath.
@export var aggro_range: float = 640.0
@export var first_delay := Vector2(1.2, 2.2)
@export var recover_time := Vector2(1.7, 2.6)
@export var inhale_duration: float = 0.9
## The tube stops following the player this long before the blow.
@export var aim_lock_time: float = 0.25
@export var turn_speed: float = 4.0
@export var fan_count_min: int = 3
@export var fan_count_max: int = 5
@export var fan_spread_degrees: float = 44.0
@export_range(0.0, 1.0) var trill_chance: float = 0.3
@export var trill_count: int = 3
@export var trill_interval: float = 0.17
@export var bubble_speed: float = 170.0
@export var trill_bubble_speed: float = 215.0
@export var bubble_damage: float = 10.0

@export_category("Knockback")
## Rooted: a wave only rocks it.
@export var knockback_scale: float = 0.3
@export var knockback_friction: float = 2400.0

@export_category("Visual")
@export_range(1, 8, 1) var pixel_size: int = 3
@export var outline_color := Color("4a2c1e")
@export var shade_color := Color("a8693a")
@export var base_color := Color("d59f58")
@export var light_color := Color("efcd86")
@export var highlight_color := Color("fff4d8")
@export var eye_color := Color("2a1a14")
@export var reed_color := Color("6f9e5e")
@export var reed_outline := Color("2c4a33")
@export var cattail_color := Color("a2794e")
@export var leaf_color := Color("5f9a5a")
@export var leaf_light := Color("8cc274")
@export var mouth_rim := Color("e46fa8")
@export var mouth_rim_light := Color("f7b3d2")
@export var mouth_hole := Color("3a1f3a")
@export var shadow_color := Color(0.0, 0.0, 0.0, 0.35)
## Swell at the end of a breath (x, y).
@export var inhale_swell := Vector2(0.22, 0.3)
@export var inhale_brightness: float = 1.15

@export_category("Sound")
@export var inhale_stream: AudioStream
@export var blow_stream: AudioStream
@export var toot_stream: AudioStream
@export var hurt_stream: AudioStream
@export var death_stream: AudioStream
@export var hurt_gap: float = 0.07

static var _texture_cache := {}

var health: float
var _state := State.IDLE
var _pattern := Pattern.FAN
var _state_time := 0.0
var _shots_left := 0
var _shot_time := 0.0
var _aim_angle := PI * 0.5
var _nozzle_index := -1
var _nozzle_in_front := true
var _eyes := Eyes.CENTER
var _blink_left := 0.0
var _next_blink := 0.0
var _hold_left := 0.0
var _knockback_velocity := Vector2.ZERO
var _swell := 0.0
var _pulse := Vector2.ZERO
var _pulse_velocity := Vector2.ZERO
var _appear := 1.0
var _breath_phase := 0.0
var _quiver := Vector2.ZERO
var _quiver_time := 0.0
var _air_carry := 0.0
var _last_hurt_sound := -INF
var _flash_tween: Tween
var _air: WindProjectileTrail
var _player: Node2D
var _idle_target := 0.0

@onready var shadow: Node2D = $Shadow
@onready var shadow_sprite: Sprite2D = $Shadow/Sprite
@onready var visual: Node2D = $Visual
@onready var body: Sprite2D = $Visual/Body
@onready var nozzle: Sprite2D = $Visual/Nozzle
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var inhale_sound: AudioStreamPlayer2D = $InhaleSound
@onready var hurt_sound: AudioStreamPlayer2D = $HurtSound


func _ready() -> void:
	health = max_health
	_breath_phase = randf() * TAU
	_next_blink = randf_range(1.5, 4.0)
	var texel_scale := Vector2.ONE * pixel_size
	# Canvas centre vs. sack centre: the sprites sit so the sack is at the origin.
	var offset := Vector2(CANVAS) * 0.5 - SACK_CENTER
	for sprite in [body, nozzle]:
		sprite.scale = texel_scale
		sprite.offset = offset
		sprite.position = Vector2(0.0, -FEET)
	visual.position = Vector2(0.0, FEET)
	shadow.position = Vector2(0.0, FEET)
	shadow_sprite.texture = _cached_texture("shadow", 0, _paint_shadow)
	shadow_sprite.scale = texel_scale
	inhale_sound.stream = inhale_stream
	hurt_sound.stream = hurt_stream
	_air = TRAIL_SCRIPT.new()
	_air.lifetime = Vector2(0.28, 0.4)
	_air.curl_radius = 2.2
	add_child(_air)
	_player = get_tree().get_first_node_in_group(&"player") as Node2D
	if _player != null:
		_aim_angle = (_player.global_position - _feet()).angle()
	_set_nozzle(_aim_angle)
	_set_eyes(Eyes.CENTER)
	_enter(State.RECOVER, randf_range(first_delay.x, first_delay.y))


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node2D

	if _hold_left > 0.0:
		_update_hold(delta)
	else:
		_state_time -= delta
		match _state:
			State.IDLE:
				_update_idle(delta)
			State.INHALE:
				_update_inhale(delta)
			State.BLOW:
				_update_blow(delta)
			State.RECOVER:
				_update_recover(delta)

	velocity = _knockback_velocity
	move_and_slide()
	for i in get_slide_collision_count():
		var normal := get_slide_collision(i).get_normal()
		if _knockback_velocity.dot(normal) < 0.0:
			_knockback_velocity = _knockback_velocity.bounce(normal) * 0.5
	_knockback_velocity = _knockback_velocity.move_toward(
		Vector2.ZERO, knockback_friction * delta)


func _process(delta: float) -> void:
	if _state == State.DEAD:
		return
	_update_blink(delta)
	_update_body(delta)


# --- public: what attacks and the spawner call --------------------------------

func take_damage(amount: float) -> void:
	if _state == State.DEAD:
		return
	health -= amount
	_flash()
	_kick(Vector2(0.1, -0.1))
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_hurt_sound >= hurt_gap and hurt_sound.stream != null:
		_last_hurt_sound = now
		hurt_sound.play()
	if health <= 0.0:
		_die()


func apply_knockback(force: Vector2) -> void:
	if _state == State.DEAD or _hold_left > 0.0:
		return
	_knockback_velocity += force * knockback_scale
	_kick(Vector2(-0.08, 0.08))


# R compression: held and squeezed, the breath it was drawing is lost.
func apply_hold(duration: float) -> void:
	if _state == State.DEAD or duration <= 0.0:
		return
	if _state == State.INHALE or _state == State.BLOW:
		_stop_inhale_sound()
		_enter(State.RECOVER, randf_range(recover_time.x, recover_time.y) * 0.6)
	_knockback_velocity = Vector2.ZERO
	_hold_left = maxf(_hold_left, duration)


func play_spawn_animation(duration: float) -> void:
	if _state == State.DEAD or duration <= 0.0:
		return
	_appear = 0.0
	create_tween().tween_property(self, "_appear", 1.0, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- states -------------------------------------------------------------------

func _enter(state: State, time: float = 0.0) -> void:
	_state = state
	_state_time = time


func _update_idle(delta: float) -> void:
	# Out of range: it looks about slowly, and starts a breath when the player
	# comes close enough.
	if _player_in_range():
		_turn_toward_player(delta, 0.5)
		_start_inhale()
	elif _state_time <= 0.0:
		_state_time = randf_range(1.5, 3.0)
		_idle_target = _aim_angle + randf_range(-1.2, 1.2)
	else:
		_aim_angle = rotate_toward(_aim_angle, _idle_target, turn_speed * 0.2 * delta)
		_set_nozzle(_aim_angle)


func _update_recover(delta: float) -> void:
	if _player_in_range():
		_turn_toward_player(delta, 0.7)
	_swell = move_toward(_swell, 0.0, delta * 3.0)
	if _state_time > 0.0:
		return
	if _player_in_range():
		_start_inhale()
	else:
		_enter(State.IDLE)


func _start_inhale() -> void:
	_pattern = Pattern.TRILL if randf() < trill_chance else Pattern.FAN
	_enter(State.INHALE, inhale_duration)
	_air_carry = 0.0
	if inhale_sound.stream != null:
		inhale_sound.volume_db = 0.0
		inhale_sound.play()


func _update_inhale(delta: float) -> void:
	var progress := 1.0 - clampf(_state_time / maxf(inhale_duration, 0.01), 0.0, 1.0)
	if _state_time > aim_lock_time:
		_turn_toward_player(delta, 1.0)
	# A trill swells less: the breath is spent on three small blows.
	var depth := 0.75 if _pattern == Pattern.TRILL else 1.0
	_swell = depth * progress * progress * (3.0 - 2.0 * progress)
	_emit_inhale_air(delta, progress)
	if _state_time <= 0.0:
		_start_blow()


func _start_blow() -> void:
	_enter(State.BLOW)
	if _pattern == Pattern.FAN:
		var count := randi_range(fan_count_min, maxi(fan_count_min, fan_count_max))
		var spread := deg_to_rad(fan_spread_degrees)
		for i in count:
			var t := 0.5 if count == 1 else float(i) / (count - 1)
			_shoot(_aim_angle + lerpf(-spread * 0.5, spread * 0.5, t), bubble_speed)
		NelvarOneShotSound.play(get_parent(), blow_stream, _mouth_position(), -2.0, 1.0, 0.0)
		_release_breath(1.0, 12)
		_state_time = 0.3
	else:
		_shots_left = trill_count
		_shot_time = 0.0
		_state_time = trill_count * trill_interval + 0.15


func _update_blow(delta: float) -> void:
	if _pattern == Pattern.TRILL:
		# Each blow of a trill aims anew, a little slower than it turns at rest.
		_turn_toward_player(delta, 0.6)
		_shot_time -= delta
		if _shots_left > 0 and _shot_time <= 0.0:
			_shots_left -= 1
			_shot_time = trill_interval
			_shoot(_aim_angle, trill_bubble_speed)
			NelvarOneShotSound.play(get_parent(), toot_stream, _mouth_position(), -3.0, 1.0, 0.0)
			_release_breath(0.3 if _shots_left > 0 else 1.0, 5)
	if _state_time <= 0.0:
		_enter(State.RECOVER, randf_range(recover_time.x, recover_time.y))


func _update_hold(delta: float) -> void:
	_hold_left -= delta
	_knockback_velocity = Vector2.ZERO
	_swell = move_toward(_swell, 0.0, delta * 4.0)
	if _hold_left <= 0.0:
		_hold_left = 0.0
		_kick(Vector2(-0.12, 0.15))


func _player_in_range() -> bool:
	if not is_instance_valid(_player):
		return false
	if _player.has_method("is_dead") and _player.call("is_dead"):
		return false
	return _feet().distance_to(_player.global_position) <= aggro_range


func _turn_toward_player(delta: float, speed_scale: float) -> void:
	if not is_instance_valid(_player):
		return
	var target := (_player.global_position - _feet()).angle()
	_aim_angle = rotate_toward(_aim_angle, target, turn_speed * speed_scale * delta)
	_set_nozzle(_aim_angle)


# --- bubbles and air ----------------------------------------------------------

func _shoot(angle: float, speed: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var direction := Vector2.from_angle(angle)
	var bubble := BUBBLE_SCENE.instantiate() as NelvarWhistlerBubble
	bubble.speed = speed
	bubble.damage = bubble_damage
	bubble.float_height = MOUTH_HEIGHT
	parent.add_child(bubble)
	bubble.launch(_feet() + direction * NOZZLE_LENGTH * pixel_size, direction)


# Where the mouth is drawn, in world coordinates.
func _mouth_position() -> Vector2:
	var direction := Vector2.from_angle(_aim_angle)
	return _feet() + direction * NOZZLE_LENGTH * pixel_size + Vector2(0.0, -MOUTH_HEIGHT)


func _feet() -> Vector2:
	return global_position + Vector2(0.0, FEET)


# Air streams into the tube from in front of it, more and more as the breath
# deepens; it starts farther out, so it is seen converging on the mouth.
func _emit_inhale_air(delta: float, progress: float) -> void:
	_air_carry += delta * lerpf(18.0, 60.0, progress)
	var mouth := _mouth_position()
	while _air_carry >= 1.0:
		_air_carry -= 1.0
		var angle := _aim_angle + randf_range(-1.0, 1.0)
		var at := mouth + Vector2.from_angle(angle) * randf_range(36.0, 64.0)
		_air.emit_puff(at, (mouth - at) * 4.5, (mouth - at).normalized())
	if progress > 0.6:
		# Strain: the sack quivers by whole texels.
		_quiver_time -= delta
		if _quiver_time <= 0.0:
			_quiver_time = 0.05
			_quiver = Vector2(randi_range(-1, 1), randi_range(-1, 0)) * pixel_size


# The blow: the swell collapses with a springy squash and air bursts out of the
# tube; `amount` 1.0 is a whole breath, less is one note of a trill.
func _release_breath(amount: float, puffs: int) -> void:
	_swell *= 1.0 - amount
	_quiver = Vector2.ZERO
	_kick(Vector2(-0.18, -0.24) * amount + Vector2(0.06, -0.04))
	var mouth := _mouth_position()
	var forward := Vector2.from_angle(_aim_angle)
	for _i in puffs:
		var side := forward.orthogonal() * randf_range(-70.0, 70.0)
		_air.emit_puff(mouth, forward * randf_range(90.0, 210.0) + side, forward)


func _stop_inhale_sound() -> void:
	if not inhale_sound.playing:
		return
	var tween := create_tween()
	tween.tween_property(inhale_sound, "volume_db", -40.0, 0.12)
	tween.tween_callback(inhale_sound.stop)


# --- look -----------------------------------------------------------------------

func _update_body(delta: float) -> void:
	# A springy pulse on top of a slow breath, the swell of a deep breath and the
	# squeeze of compression.
	_pulse_velocity += (-170.0 * _pulse - 11.0 * _pulse_velocity) * delta
	_pulse += _pulse_velocity * delta
	_breath_phase += delta * TAU * 0.55
	var breath := Vector2(1.0 - 0.02 * sin(_breath_phase), 1.0 + 0.035 * sin(_breath_phase))
	var swell := Vector2.ONE + inhale_swell * _swell
	if _hold_left > 0.0:
		swell *= Vector2(0.84, 0.9)
	visual.scale = breath * swell * (Vector2.ONE + _pulse) * _appear
	shadow.scale = Vector2.ONE * (1.0 + 0.2 * _swell) * _appear
	if _state != State.INHALE and _hold_left <= 0.0:
		_quiver = Vector2.ZERO
	elif _hold_left > 0.0:
		_quiver_time -= delta
		if _quiver_time <= 0.0:
			_quiver_time = 0.04
			_quiver = Vector2(randi_range(-1, 1), 0) * pixel_size
	visual.position = Vector2(0.0, FEET) + _quiver
	var bright := lerpf(1.0, inhale_brightness, _swell)
	body.self_modulate = Color(bright, bright, bright)


func _kick(amount: Vector2) -> void:
	_pulse += amount


func _update_blink(delta: float) -> void:
	var straining := _state == State.INHALE and _state_time < aim_lock_time
	if _blink_left > 0.0:
		_blink_left -= delta
	else:
		_next_blink -= delta
		if _next_blink <= 0.0:
			_next_blink = randf_range(2.0, 5.0)
			_blink_left = 0.12
	if straining or _blink_left > 0.0 or _hold_left > 0.0:
		_set_eyes(Eyes.CLOSED)
		return
	var x := cos(_aim_angle)
	_set_eyes(Eyes.RIGHT if x > 0.38 else (Eyes.LEFT if x < -0.38 else Eyes.CENTER))


func _set_eyes(eyes: Eyes) -> void:
	if eyes == _eyes and body.texture != null:
		return
	_eyes = eyes
	body.texture = _cached_texture("body", eyes, _paint_body.bind(eyes))


func _set_nozzle(angle: float) -> void:
	var index := posmod(roundi(angle / TAU * DIRECTIONS), DIRECTIONS)
	if index == _nozzle_index:
		return
	_nozzle_index = index
	nozzle.texture = _cached_texture("nozzle", index, _paint_nozzle.bind(index))
	# Pointing away from the viewer the tube is behind the sack.
	var in_front := Vector2.from_angle(index * TAU / DIRECTIONS).y > -0.2
	if in_front != _nozzle_in_front:
		_nozzle_in_front = in_front
		visual.move_child(nozzle, -1 if in_front else 0)


func _flash() -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	visual.modulate = hit_flash_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(visual, "modulate", Color.WHITE, hit_flash_duration)


# The sack deflates with a wheeze — flattening, air escaping from the tube —
# and fades.
func _die() -> void:
	_state = State.DEAD
	remove_from_group(&"enemies")
	get_tree().call_group(&"player", &"register_kill")
	collision_shape.set_deferred("disabled", true)
	_knockback_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	_stop_inhale_sound()
	NelvarOneShotSound.play(get_parent(), death_stream, global_position, -1.0, 1.0, 0.0)
	_set_eyes(Eyes.CLOSED)
	var start_scale := visual.scale
	var tween := create_tween()
	tween.tween_method(_deflate.bind(start_scale), 0.0, 1.0, death_duration)
	tween.tween_callback(_finish_death)


func _deflate(t: float, start_scale: Vector2) -> void:
	var flat := Vector2(lerpf(start_scale.x, 1.3, t), lerpf(start_scale.y, 0.3, t * t))
	visual.scale = flat
	var shake := float(randi_range(-1, 1) * pixel_size) if t < 0.7 else 0.0
	visual.position = Vector2(shake, FEET)
	visual.modulate.a = 1.0 - smoothstep(0.65, 1.0, t)
	shadow.modulate.a = visual.modulate.a
	if t < 0.75 and randf() < 0.7:
		var mouth := _mouth_position()
		var out := Vector2.from_angle(_aim_angle + randf_range(-0.8, 0.8))
		_air.emit_puff(mouth, out * randf_range(60.0, 160.0), out)


func _finish_death() -> void:
	# The air already let out drifts on after the body is gone.
	var parent := get_parent()
	if is_instance_valid(_air) and parent != null:
		remove_child(_air)
		parent.add_child(_air)
		_air.release(_mouth_position(), Vector2.UP, 6)
	queue_free()


# --- art ----------------------------------------------------------------------

func _cached_texture(kind: String, variant: int, painter: Callable) -> ImageTexture:
	var key := "%s|%d|%d|%s" % [kind, variant, pixel_size, [
		outline_color, shade_color, base_color, light_color, highlight_color,
		eye_color, reed_color, reed_outline, cattail_color, leaf_color,
		leaf_light, mouth_rim, mouth_rim_light, mouth_hole, shadow_color]]
	if not _texture_cache.has(key):
		_texture_cache[key] = ImageTexture.create_from_image(painter.call())
	return _texture_cache[key]


# Behind: reed stalks with cattail tips and two leaves at the base. Then the
# sack — outline, three tones lit from the upper left, two faint ribs like reed
# segments, a highlight — and two eyes looking the way the tube points.
func _paint_body(eyes: Eyes) -> Image:
	var image := Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	# Leaves: flat ellipses on both sides of the base.
	for leaf in [[Vector2(9.5, 28.2), -0.35], [Vector2(21.5, 28.2), 0.35]]:
		_paint_leaf(image, leaf[0], leaf[1])
	# Stalks: (x at the sack, top y, lean per texel up).
	for stalk in [[12.5, 9.0, -0.2], [16.0, 6.5, 0.05], [19.0, 10.0, 0.24]]:
		_paint_stalk(image, stalk[0], stalk[1], stalk[2])

	var light := Vector3(-0.45, -0.65, 0.61).normalized()
	for y in CANVAS.y:
		for x in CANVAS.x:
			var p := Vector2(x + 0.5, y + 0.5)
			if not _in_sack(p):
				continue
			var color := outline_color
			if _in_sack(p + Vector2.RIGHT) and _in_sack(p + Vector2.LEFT) \
					and _in_sack(p + Vector2.DOWN) and _in_sack(p + Vector2.UP):
				var d := (p - SACK_CENTER) / SACK_RADII
				var normal := Vector3(d.x, d.y, sqrt(maxf(0.0, 1.0 - d.length_squared())))
				var brightness := normal.dot(light)
				var tone := 0 if brightness < 0.3 else (1 if brightness < 0.82 else 2)
				# Ribs: a tone darker along two vertical lines.
				if absf(absf(p.x - SACK_CENTER.x) - 4.5) < 0.5 and absf(d.y) < 0.75:
					tone = maxi(tone - 1, 0)
				color = [shade_color, base_color, light_color][tone]
			image.set_pixel(x, y, color)

	var spot := Vector2i((SACK_CENTER - SACK_RADII * Vector2(0.45, 0.55)).floor())
	for offset in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN]:
		image.set_pixelv(spot + offset, highlight_color)

	var look := {Eyes.LEFT: -1, Eyes.CENTER: 0, Eyes.RIGHT: 1, Eyes.CLOSED: 0}[eyes] as int
	var eye_y := int(SACK_CENTER.y) - 4
	for eye_x in [int(SACK_CENTER.x) - 3 + look, int(SACK_CENTER.x) + 3 + look]:
		if eyes == Eyes.CLOSED:
			image.set_pixel(eye_x - 1, eye_y + 1, eye_color)
			image.set_pixel(eye_x, eye_y + 1, eye_color)
		else:
			image.set_pixel(eye_x, eye_y, eye_color)
			image.set_pixel(eye_x, eye_y + 1, eye_color)
	return image


func _paint_leaf(image: Image, center: Vector2, tilt: float) -> void:
	var radii := Vector2(5.2, 1.9)
	for y in CANVAS.y:
		for x in CANVAS.x:
			var p := Vector2(x + 0.5, y + 0.5) - center
			p = p.rotated(-tilt)
			var d := p / radii
			if d.length_squared() > 1.0:
				continue
			var inner := (p / (radii - Vector2(0.9, 0.9))).length_squared() <= 1.0
			var color := reed_outline
			if inner:
				color = leaf_light if p.y < -0.3 else leaf_color
			image.set_pixel(x, y, color)


func _paint_stalk(image: Image, base_x: float, top_y: float, lean: float) -> void:
	var bottom := int(SACK_CENTER.y)
	for y in range(int(top_y), bottom):
		var x := roundi(base_x + lean * (bottom - y))
		var is_tip := y < top_y + 3
		for dx in [-1, 0, 1]:
			var px: int = x + dx
			if px < 0 or px >= CANVAS.x:
				continue
			var color := reed_outline
			if dx == 0:
				color = cattail_color if is_tip else reed_color
			image.set_pixel(px, y, color)
		if is_tip:
			image.set_pixel(x + 1, y, cattail_color if y > top_y else reed_outline)
	var top_x := roundi(base_x + lean * (bottom - top_y))
	image.set_pixel(top_x, int(top_y) - 1, reed_outline)


func _in_sack(p: Vector2) -> bool:
	return ((p - SACK_CENTER) / SACK_RADII).length_squared() <= 1.0


# The tube from the sack toward `index` of 16 directions: outline, a lit side
# and a shaded one; at its end the mouth — a pink rim around a dark hole, seen
# only when it is turned toward the viewer or sideways.
func _paint_nozzle(index: int) -> Image:
	var image := Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	var dir := Vector2.from_angle(index * TAU / DIRECTIONS)
	var start := NOZZLE_BASE + dir * NOZZLE_START
	var tip := NOZZLE_BASE + dir * NOZZLE_LENGTH
	var tube := NOZZLE_LENGTH - NOZZLE_START
	var light_dir := Vector2(-0.6, -0.8)
	for y in CANVAS.y:
		for x in CANVAS.x:
			var p := Vector2(x + 0.5, y + 0.5)
			var s := clampf((p - start).dot(dir) / tube, 0.0, 1.0)
			var closest := start + dir * tube * s
			var off := p - closest
			var dist := off.length()
			var color := Color.TRANSPARENT
			if dist <= NOZZLE_HALF_WIDTH + 0.6:
				color = outline_color
				if dist <= NOZZLE_HALF_WIDTH - 0.4:
					var side := off.normalized().dot(light_dir) if dist > 0.01 else 0.0
					color = light_color if side > 0.45 else (shade_color if side < -0.45 else base_color)
			var to_tip := (p - tip).length()
			if to_tip <= MOUTH_RADIUS + 0.5:
				color = outline_color
				if to_tip <= MOUTH_RADIUS - 0.5:
					var lit := (p - tip).dot(light_dir) > 0.4
					color = mouth_rim_light if lit else mouth_rim
					if to_tip <= 1.3 and dir.y > -0.35:
						color = mouth_hole
			if color.a > 0.0:
				image.set_pixel(x, y, color)
	return image


func _paint_shadow() -> Image:
	var radii := Vector2(SACK_RADII.x * 1.15, SACK_RADII.x * 0.42)
	var half := Vector2i(radii.ceil())
	var size := half * 2 + Vector2i.ONE
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			var d := (Vector2(x, y) - Vector2(half)) / (radii + Vector2(0.5, 0.5))
			if d.length_squared() <= 1.0:
				image.set_pixel(x, y, shadow_color)
	return image
