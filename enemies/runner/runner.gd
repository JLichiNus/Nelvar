class_name NelvarRunner
extends CharacterBody2D
## Бегунок: a tiny fluffy bird on long legs that lives to run. It chases the
## player, coming round from the side rather than straight on, and — when the
## way is clear and the player close enough — dashes:
##
## 1. Windup (0.6 s): it crouches, scratches the ground, chirps, and a dashed
##    arrow grows along the ground the way it will go. The arrow follows the
##    player and turns light when the aim locks, just before the dash.
## 2. Dash: straight along the arrow, fast, hurting more than at a walk.
## 3. A miss ends in a skid and a moment out of breath — the time to hit it.
##    Running into a trunk or a rock stuns it (stars over its head), and so
##    does an RMB wave that catches it crouching or dashing.
##
## Slower than a walking player, so it can be kited, but it catches up when
## the player stops to fight.

const TRAIL_SCRIPT := preload("res://attacks/wind_projectile/wind_projectile_trail.gd")
const DUST_SCRIPT := preload("res://enemies/runner/runner_dust.gd")
## Art canvas in texels; ORIGIN is where the node origin sits on it (the lower
## body, so the collider covers the body and its y-sort is near the feet).
const CANVAS := Vector2i(24, 22)
const ORIGIN := Vector2(11.5, 14.5)
const GROUND_ROW := 20
## Angles tried, in turn, to get round a trunk when chasing (radians).
const STEER_ANGLES: Array[float] = [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.3, -2.3]

enum State { CHASE, WINDUP, DASH, SKID, RECOVER, STUNNED, DEAD }
enum Pose { STAND, RUN_0, RUN_1, RUN_2, RUN_3, CROUCH, DASH, DIZZY }
enum Eye { OPEN, BLINK, FOCUS, DIZZY }

@export_category("Health")
@export var max_health: float = 35.0
## Read by the player's hurtbox; the Runner changes it as it goes.
@export var contact_damage: float = 8.0
@export var walk_contact_damage: float = 8.0
@export var dash_contact_damage: float = 14.0
@export var hit_flash_color := Color(2.0, 2.0, 2.0)
@export var hit_flash_duration: float = 0.1
@export var death_duration: float = 0.35

@export_category("Chase")
@export var chase_speed: float = 250.0
@export var chase_acceleration: float = 1400.0
## It aims for a point this far from the player, turned off to one side.
@export var orbit_radius: float = 210.0
@export var orbit_angle: float = 0.65
@export var side_switch_time := Vector2(2.0, 4.0)
## Other Runners closer than this push it aside while chasing.
@export var separation_radius: float = 46.0
## Distance between footfalls (one frame of the run cycle).
@export var step_length: float = 20.0

@export_category("Dash")
@export var first_delay := Vector2(0.8, 1.6)
@export var dash_cooldown := Vector2(1.0, 2.0)
@export var dash_range_min: float = 160.0
@export var dash_range_max: float = 390.0
@export var windup_duration: float = 0.6
## The arrow stops following the player this long before the dash.
@export var aim_lock_time: float = 0.18
@export var aim_turn_speed: float = 6.0
@export var dash_speed: float = 760.0
@export var dash_duration: float = 0.42
@export var skid_duration: float = 0.3
@export var recover_duration: float = 0.55
## Stun after running into a trunk or rock, and after a wave knocks it over.
@export var bonk_stun: float = 1.4
@export var knock_stun: float = 0.9
@export var bonk_bounce: float = 220.0

@export_category("Knockback")
@export var knockback_friction: float = 1800.0

@export_category("Visual")
@export_range(1, 8, 1) var pixel_size: int = 3
@export var outline_color := Color("3b2a4f")
@export var shade_color := Color("a99ccc")
@export var base_color := Color("dcd6f0")
@export var light_color := Color("f8f6ff")
@export var wing_color := Color("8c7fb4")
@export var eye_white := Color("ffffff")
@export var eye_color := Color("1f1630")
@export var crest_color := Color("f08a3c")
@export var crest_dark := Color("a8481e")
@export var leg_color := Color("e07a34")
@export var leg_back_color := Color("9a4520")
@export var dust_color := Color(0.82, 0.74, 0.6, 0.85)
@export var telegraph_color := Color(1.0, 0.5, 0.15, 0.9)
@export var telegraph_lock_color := Color(1.0, 0.93, 0.78, 0.95)
@export var star_color := Color("ffe27a")
@export var shadow_color := Color(0.0, 0.0, 0.0, 0.33)

@export_category("Sound")
@export var step_stream: AudioStream
@export var chirp_stream: AudioStream
@export var dash_stream: AudioStream
@export var skid_stream: AudioStream
@export var bonk_stream: AudioStream
@export var hurt_stream: AudioStream
@export var death_stream: AudioStream
@export var step_volume_db: float = -13.0
@export var hurt_gap: float = 0.07

static var _texture_cache := {}

var health: float
var _state := State.CHASE
var _state_time := 0.0
var _dash_cooldown_left := 0.0
var _dash_dir := Vector2.RIGHT
var _move_velocity := Vector2.ZERO
var _knockback_velocity := Vector2.ZERO
var _hold_left := 0.0
var _facing := 1.0
var _side := 1.0
var _side_time := 0.0
var _step_distance := 0.0
var _run_frame := 0
var _scratch_time := 0.0
var _pulse := Vector2.ZERO
var _pulse_velocity := Vector2.ZERO
var _appear := 1.0
var _hop := 0.0
var _blink_left := 0.0
var _next_blink := 0.0
var _anim_time := 0.0
var _pose := -1
var _eye := -1
var _last_hurt_sound := -INF
var _flash_tween: Tween
var _trail: WindProjectileTrail
var _dust: NelvarRunnerDust
var _player: Node2D

@onready var shadow: Node2D = $Shadow
@onready var shadow_sprite: Sprite2D = $Shadow/Sprite
@onready var visual: Node2D = $Visual
@onready var legs: Sprite2D = $Visual/Legs
@onready var body: Sprite2D = $Visual/Body
@onready var stars: Node2D = $Stars
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var chirp_sound: AudioStreamPlayer2D = $ChirpSound
@onready var hurt_sound: AudioStreamPlayer2D = $HurtSound


func _ready() -> void:
	health = max_health
	contact_damage = walk_contact_damage
	_side = 1.0 if randf() < 0.5 else -1.0
	_side_time = randf_range(side_switch_time.x, side_switch_time.y)
	_next_blink = randf_range(1.5, 4.0)
	_dash_cooldown_left = randf_range(first_delay.x, first_delay.y)
	var offset := Vector2(CANVAS) * 0.5 - ORIGIN
	for sprite in [legs, body]:
		sprite.scale = Vector2.ONE * pixel_size
		sprite.offset = offset
		sprite.position = Vector2(0.0, -_feet_height())
	visual.position = Vector2(0.0, _feet_height())
	shadow.position = Vector2(0.0, _feet_height())
	shadow_sprite.texture = _cached_texture("shadow", 0, _paint_shadow)
	shadow_sprite.scale = Vector2.ONE * pixel_size
	chirp_sound.stream = chirp_stream
	hurt_sound.stream = hurt_stream
	stars.draw.connect(_draw_stars)
	_dust = DUST_SCRIPT.new()
	add_child(_dust)
	_player = get_tree().get_first_node_in_group(&"player") as Node2D
	_set_look(Pose.STAND, Eye.OPEN)


# Freed by someone else mid-dash (a restart, the spawner): the wind trail lives
# with the parent and must be let go.
func _exit_tree() -> void:
	_release_trail()


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node2D

	if _hold_left > 0.0:
		_update_hold(delta)
	else:
		_state_time -= delta
		_dash_cooldown_left -= delta
		match _state:
			State.CHASE:
				_update_chase(delta)
			State.WINDUP:
				_update_windup(delta)
			State.DASH:
				_update_dash(delta)
			State.SKID:
				_update_skid(delta)
			State.RECOVER, State.STUNNED:
				_move_velocity = _move_velocity.move_toward(Vector2.ZERO, chase_acceleration * delta)
				if _state_time <= 0.0:
					_end_pause()

	velocity = _move_velocity + _knockback_velocity
	move_and_slide()
	_check_collisions()
	_knockback_velocity = _knockback_velocity.move_toward(
		Vector2.ZERO, knockback_friction * delta)
	_count_steps(delta)


func _process(delta: float) -> void:
	if _state == State.DEAD:
		return
	_anim_time += delta
	_update_look(delta)
	if _state == State.WINDUP:
		queue_redraw()
	if _state == State.STUNNED:
		stars.queue_redraw()


# --- public: what attacks and the spawner call --------------------------------

func take_damage(amount: float) -> void:
	if _state == State.DEAD:
		return
	health -= amount
	_flash()
	_kick(Vector2(-0.12, 0.14))
	_hop = 2.0
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_hurt_sound >= hurt_gap and hurt_sound.stream != null:
		_last_hurt_sound = now
		hurt_sound.play()
	if health <= 0.0:
		_die()


func apply_knockback(force: Vector2) -> void:
	if _state == State.DEAD or _hold_left > 0.0:
		return
	_knockback_velocity += force
	# Caught crouching or mid-dash, it is knocked off its feet.
	if _state == State.WINDUP or _state == State.DASH:
		_stun(knock_stun, false)


# R compression: held still; a windup or a dash it was in is lost.
func apply_hold(duration: float) -> void:
	if _state == State.DEAD or duration <= 0.0:
		return
	if _state in [State.WINDUP, State.DASH, State.SKID]:
		_cancel_dash()
		_enter(State.RECOVER, 0.3)
	_move_velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	_hold_left = maxf(_hold_left, duration)


func play_spawn_animation(duration: float) -> void:
	if _state == State.DEAD or duration <= 0.0:
		return
	_appear = 0.0
	create_tween().tween_property(self, "_appear", 1.0, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func is_stunned() -> bool:
	return _state == State.STUNNED


# --- states -------------------------------------------------------------------

func _enter(state: State, time: float = 0.0) -> void:
	_state = state
	_state_time = time
	queue_redraw()
	stars.queue_redraw()


func _update_chase(delta: float) -> void:
	_side_time -= delta
	if _side_time <= 0.0:
		_side_time = randf_range(side_switch_time.x, side_switch_time.y)
		if randf() < 0.5:
			_side = -_side
	if not _player_alive():
		_move_velocity = _move_velocity.move_toward(Vector2.ZERO, chase_acceleration * delta)
		return
	var target := _chase_target()
	var to_target := target - _ground()
	var wanted := Vector2.ZERO
	if to_target.length() > 12.0:
		wanted = _steer(to_target.normalized()) * chase_speed
	wanted = (wanted + _separation() * chase_speed).limit_length(chase_speed)
	_move_velocity = _move_velocity.move_toward(wanted, chase_acceleration * delta)
	if absf(_move_velocity.x) > 25.0:
		_facing = signf(_move_velocity.x)
	if _can_dash():
		_start_windup()


# A point beside the player, off to this Runner's side: coming near, it curves
# round and closes in from the flank.
func _chase_target() -> Vector2:
	var player_at := _player.global_position
	var from_player := _ground() - player_at
	if from_player.length_squared() < 1.0:
		from_player = Vector2.RIGHT
	return player_at + from_player.normalized().rotated(_side * orbit_angle) * orbit_radius


# Runners keep a little apart, so a pack reads as several birds, not a heap.
func _separation() -> Vector2:
	var push := Vector2.ZERO
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var other := node as NelvarRunner
		if other == null or other == self:
			continue
		var away := global_position - other.global_position
		var distance := away.length()
		if distance > 0.01 and distance < separation_radius:
			push += away / distance * (1.0 - distance / separation_radius)
	return push


func _steer(direction: Vector2) -> Vector2:
	for angle in STEER_ANGLES:
		var candidate := direction.rotated(angle * _side)
		if not test_move(global_transform, candidate * 22.0):
			return candidate
	return direction


func _can_dash() -> bool:
	if _dash_cooldown_left > 0.0 or not _player_alive():
		return false
	var to_player := _player.global_position - _ground()
	var distance := to_player.length()
	if distance < dash_range_min or distance > dash_range_max:
		return false
	# Only with a clear run: no trunk or rock between it and the player.
	return not test_move(global_transform, to_player * 0.9)


func _start_windup() -> void:
	_enter(State.WINDUP, windup_duration)
	_dash_dir = (_player.global_position - _ground()).normalized()
	_facing = signf(_dash_dir.x) if absf(_dash_dir.x) > 0.05 else _facing
	_move_velocity = _move_velocity * 0.3
	_scratch_time = 0.0
	if chirp_sound.stream != null:
		chirp_sound.volume_db = -2.0
		chirp_sound.play()


func _update_windup(delta: float) -> void:
	_move_velocity = _move_velocity.move_toward(Vector2.ZERO, chase_acceleration * 2.0 * delta)
	if _state_time > aim_lock_time and _player_alive():
		var wanted := (_player.global_position - _ground()).angle()
		_dash_dir = Vector2.from_angle(rotate_toward(_dash_dir.angle(), wanted, aim_turn_speed * delta))
		if absf(_dash_dir.x) > 0.05:
			_facing = signf(_dash_dir.x)
	# Scratching the ground: earth flies back from under its feet.
	_scratch_time -= delta
	if _scratch_time <= 0.0:
		_scratch_time = 0.12
		var back := Vector2(-_facing, 0.0)
		for _i in 2:
			_dust.emit(_ground() + Vector2(randf_range(-4, 4), 0),
				back * randf_range(60, 130) + Vector2(0, randf_range(-90, -40)),
				dust_color, randf_range(0.25, 0.4), 1, -260.0)
	if _state_time <= 0.0:
		_start_dash()


func _start_dash() -> void:
	_enter(State.DASH, dash_duration)
	_move_velocity = _dash_dir * dash_speed
	contact_damage = dash_contact_damage
	_kick(Vector2(0.18, -0.12))
	NelvarOneShotSound.play(get_parent(), dash_stream, global_position, -3.0, 1.0, 0.0)
	_trail = TRAIL_SCRIPT.new()
	_trail.spacing = 7.0
	_trail.lifetime = Vector2(0.2, 0.36)
	var parent := get_parent()
	if parent != null:
		parent.add_child(_trail)
	for _i in 6:
		_dust.emit(_ground(), -_dash_dir * randf_range(40, 120) + Vector2(randf_range(-40, 40), -20),
			dust_color, randf_range(0.3, 0.45), 2)


func _update_dash(_delta: float) -> void:
	_move_velocity = _dash_dir * dash_speed
	if is_instance_valid(_trail):
		_trail.follow(global_position + Vector2(0.0, -6.0), _dash_dir)
	if _state_time <= 0.0:
		_start_skid()


func _start_skid() -> void:
	_release_trail()
	_enter(State.SKID, skid_duration)
	contact_damage = walk_contact_damage
	NelvarOneShotSound.play(get_parent(), skid_stream, global_position, -4.0, 1.0, 0.0)


func _update_skid(delta: float) -> void:
	_move_velocity = _move_velocity.move_toward(
		Vector2.ZERO, dash_speed / maxf(skid_duration, 0.01) * delta)
	# A spray of dust ahead of its braking feet.
	if randf() < 0.8:
		_dust.emit(_ground() + _dash_dir * 6.0,
			_dash_dir * randf_range(30, 90) + Vector2(randf_range(-30, 30), randf_range(-50, -10)),
			dust_color, randf_range(0.25, 0.4), 1 + int(randf() < 0.3))
	if _state_time <= 0.0:
		_enter(State.RECOVER, recover_duration)
		_dash_cooldown_left = randf_range(dash_cooldown.x, dash_cooldown.y)


func _end_pause() -> void:
	contact_damage = walk_contact_damage
	_enter(State.CHASE)


func _update_hold(delta: float) -> void:
	_hold_left -= delta
	_move_velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	if _hold_left <= 0.0:
		_hold_left = 0.0
		_kick(Vector2(-0.1, 0.12))


# A dash into a trunk or a rock: it bounces off and sits dazed.
func _check_collisions() -> void:
	if _state != State.DASH:
		return
	for i in get_slide_collision_count():
		var normal := get_slide_collision(i).get_normal()
		if normal.dot(_dash_dir) < -0.55:
			_knockback_velocity = normal * bonk_bounce
			_stun(bonk_stun, true)
			return


func _stun(time: float, bonk: bool) -> void:
	_cancel_dash()
	_move_velocity = Vector2.ZERO
	contact_damage = 0.0
	_enter(State.STUNNED, time)
	_dash_cooldown_left = maxf(_dash_cooldown_left, time + 0.6)
	_kick(Vector2(0.3, -0.35) if bonk else Vector2(0.15, -0.2))
	if bonk:
		NelvarOneShotSound.play(get_parent(), bonk_stream, global_position, -2.0, 1.0, 0.0)
		for _i in 8:
			var out := Vector2.from_angle(randf() * TAU)
			_dust.emit(_ground() + out * 6.0, out * randf_range(50, 110), dust_color,
				randf_range(0.3, 0.5), 2)


func _cancel_dash() -> void:
	_stop_chirp()
	_release_trail()
	contact_damage = walk_contact_damage


func _release_trail() -> void:
	if is_instance_valid(_trail):
		_trail.release(global_position + Vector2(0.0, -6.0), _dash_dir, 0)
	_trail = null


func _stop_chirp() -> void:
	if not chirp_sound.playing:
		return
	var tween := create_tween()
	tween.tween_property(chirp_sound, "volume_db", -40.0, 0.08)
	tween.tween_callback(chirp_sound.stop)


func _count_steps(delta: float) -> void:
	if _state != State.CHASE and _state != State.SKID:
		return
	var speed := velocity.length()
	if speed < 30.0:
		return
	_step_distance += speed * delta
	if _step_distance < step_length:
		return
	_step_distance -= step_length
	if _state == State.SKID:
		return
	_run_frame = (_run_frame + 1) % 4
	# Frames 0 and 2 are footfalls: a tap and a little dust behind.
	if _run_frame % 2 == 0:
		NelvarOneShotSound.play(get_parent(), step_stream, _ground(), step_volume_db, 1.0, 0.05)
		_dust.emit(_ground() + Vector2(-_facing * 4.0, 0.0),
			Vector2(-_facing * randf_range(20, 50), randf_range(-25, -5)),
			dust_color, randf_range(0.2, 0.32), 1)


func _player_alive() -> bool:
	if not is_instance_valid(_player):
		return false
	return not (_player.has_method("is_dead") and _player.call("is_dead"))


func _ground() -> Vector2:
	return global_position + Vector2(0.0, _feet_height())


func _feet_height() -> float:
	return (GROUND_ROW + 0.5 - ORIGIN.y) * pixel_size


# --- look -----------------------------------------------------------------------

func _update_look(delta: float) -> void:
	_pulse_velocity += (-180.0 * _pulse - 12.0 * _pulse_velocity) * delta
	_pulse += _pulse_velocity * delta
	_hop = move_toward(_hop, 0.0, delta * 14.0)

	var pose := Pose.STAND
	var eye := Eye.OPEN
	var bob := 0.0
	var shake := 0.0
	match _state:
		State.CHASE:
			if velocity.length() > 30.0:
				pose = [Pose.RUN_0, Pose.RUN_1, Pose.RUN_2, Pose.RUN_3][_run_frame]
				bob = 1.0 if _run_frame % 2 == 1 else 0.0
		State.WINDUP:
			pose = Pose.CROUCH
			eye = Eye.FOCUS
			if _state_time < windup_duration * 0.4:
				shake = 1.0 if int(_anim_time * 30.0) % 2 == 0 else -1.0
		State.DASH:
			pose = Pose.DASH
			eye = Eye.FOCUS
		State.SKID:
			pose = Pose.CROUCH
		State.RECOVER:
			# Out of breath: a quick heave of the body.
			bob = 1.0 if int(_anim_time * 10.0) % 2 == 0 else 0.0
		State.STUNNED:
			pose = Pose.DIZZY
			eye = Eye.DIZZY
	if _hold_left > 0.0:
		pose = Pose.CROUCH
		eye = Eye.BLINK
		shake = 1.0 if int(_anim_time * 25.0) % 2 == 0 else -1.0

	if eye == Eye.OPEN:
		if _blink_left > 0.0:
			_blink_left -= delta
			eye = Eye.BLINK
		else:
			_next_blink -= delta
			if _next_blink <= 0.0:
				_next_blink = randf_range(2.0, 5.0)
				_blink_left = 0.1
	_set_look(pose, eye)

	body.position = Vector2(0.0, -_feet_height() - bob * pixel_size)
	visual.position = Vector2(shake * pixel_size, _feet_height() - roundf(_hop) * pixel_size)
	visual.scale = Vector2(_facing, 1.0) * (Vector2.ONE + _pulse) * _appear
	shadow.scale = Vector2.ONE * _appear


func _set_look(pose: Pose, eye: Eye) -> void:
	var pose_changed := pose != _pose
	if pose_changed:
		_pose = pose
		legs.texture = _cached_texture("legs", pose, _paint_legs.bind(pose))
	if pose_changed or eye != _eye or body.texture == null:
		_eye = eye
		var variant := _body_variant(pose)
		body.texture = _cached_texture("body", variant * 8 + eye, _paint_body.bind(variant, eye))


func _kick(amount: Vector2) -> void:
	_pulse += amount


func _flash() -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	visual.modulate = hit_flash_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(visual, "modulate", Color.WHITE, hit_flash_duration)


# The dashed arrow on the ground, under the Runner (it is drawn before its
# children): it grows out during the windup, its dashes run forward, and it
# turns light once the aim is locked.
func _draw() -> void:
	if _state != State.WINDUP:
		return
	var progress := 1.0 - clampf(_state_time / maxf(windup_duration, 0.01), 0.0, 1.0)
	var locked := _state_time <= aim_lock_time
	var color := telegraph_lock_color if locked else telegraph_color
	color.a *= lerpf(0.35, 1.0, progress)
	var length := dash_speed * dash_duration * minf(1.0, progress * 1.6)
	var texel := float(pixel_size)
	var start := Vector2(0.0, _feet_height())
	var march := fmod(_anim_time * 90.0, 15.0)
	var d := 16.0 + march
	while d < length - 6.0:
		for k in 3:
			var at := start + _dash_dir * (d + k * texel)
			draw_rect(Rect2((at / texel).floor() * texel, Vector2(texel, texel)), color)
		d += 15.0
	if length > 30.0:
		# The head: a small chevron.
		var tip := start + _dash_dir * length
		var side := _dash_dir.orthogonal()
		for k in 3:
			for s in [-1.0, 1.0]:
				var at: Vector2 = tip - _dash_dir * k * texel + side * s * k * texel
				draw_rect(Rect2((at / texel).floor() * texel, Vector2(texel, texel)), color)


# Three little stars circling over its head while it is dazed.
func _draw_stars() -> void:
	if _state != State.STUNNED:
		return
	var texel := float(pixel_size)
	var center := Vector2(0.0, (1.0 - ORIGIN.y) * texel)
	for i in 3:
		var angle := _anim_time * 5.0 + i * TAU / 3.0
		var at := center + Vector2(cos(angle) * 15.0, sin(angle) * 5.0)
		var color := star_color
		if sin(angle) < 0.0:
			color = color.darkened(0.35)
		var cell := (at / texel).floor() * texel
		var cross := [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
		for offset in (cross if sin(angle) >= 0.0 else [Vector2.ZERO]):
			stars.draw_rect(Rect2(cell + offset * texel, Vector2(texel, texel)), color)


# A puff of feathers and a little jump, and it is gone.
func _die() -> void:
	_cancel_dash()
	_state = State.DEAD
	remove_from_group(&"enemies")
	get_tree().call_group(&"player", &"register_kill")
	collision_shape.set_deferred("disabled", true)
	_move_velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	queue_redraw()
	stars.queue_redraw()
	NelvarOneShotSound.play(get_parent(), death_stream, global_position, -1.0, 1.0, 0.0)
	var colors := [base_color, light_color, shade_color, crest_color]
	for i in 14:
		var out := Vector2.from_angle(randf() * TAU)
		_dust.emit(global_position + Vector2(0.0, -12.0) + out * 6.0,
			out * randf_range(60.0, 150.0) + Vector2(0.0, -40.0),
			colors[i % colors.size()], randf_range(0.7, 1.1), 1, -40.0, randf_range(12.0, 24.0))
	_set_look(Pose.DIZZY, Eye.DIZZY)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(visual, "position:y", visual.position.y - 12.0, death_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual, "scale", visual.scale * 1.25, death_duration)
	tween.tween_property(visual, "modulate:a", 0.0, death_duration)
	tween.tween_property(shadow, "modulate:a", 0.0, death_duration)
	tween.chain().tween_callback(_finish_death)


func _finish_death() -> void:
	# The dust and feathers already in the air drift on without it.
	var parent := get_parent()
	if is_instance_valid(_dust) and parent != null:
		remove_child(_dust)
		parent.add_child(_dust)
		_dust.release()
	queue_free()


# --- art ----------------------------------------------------------------------

func _body_variant(pose: Pose) -> int:
	match pose:
		Pose.CROUCH:
			return 1
		Pose.DASH:
			return 2
		Pose.DIZZY:
			return 3
	return 0


func _cached_texture(kind: String, variant: int, painter: Callable) -> ImageTexture:
	var key := "%s|%d|%d|%s" % [kind, variant, pixel_size, [
		outline_color, shade_color, base_color, light_color, wing_color, eye_white,
		eye_color, crest_color, crest_dark, leg_color, leg_back_color, shadow_color]]
	if not _texture_cache.has(key):
		_texture_cache[key] = ImageTexture.create_from_image(painter.call())
	return _texture_cache[key]


# Facing right (the sprite is flipped to face left). Tail feathers and crest
# behind, then the egg-shaped body lit from the upper left with a pale belly,
# a wing, the eye and a little beak. Variants: 0 upright, 1 crouched (lower,
# crest up, ready), 2 dashing (stretched, crest and tail flat back), 3 dazed
# (sat down, crest drooping).
func _paint_body(variant: int, eye: Eye) -> Image:
	var image := Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	var center := [Vector2(11.5, 10.0), Vector2(11.5, 12.0), Vector2(12.5, 11.0), Vector2(11.5, 12.0)][variant] as Vector2
	var radii := [Vector2(6.8, 5.6), Vector2(7.2, 5.0), Vector2(7.6, 4.8), Vector2(7.0, 5.2)][variant] as Vector2
	# Crest feathers: base offsets from the top of the body -> tip offsets.
	var crest_tips := [
		[Vector2(-3, -4), Vector2(-1, -5), Vector2(1, -4)],
		[Vector2(-1, -5), Vector2(1, -6), Vector2(3, -5)],
		[Vector2(-6, -1), Vector2(-6, -2), Vector2(-5, -3)],
		[Vector2(2, -2), Vector2(3, -1), Vector2(4, 0)],
	][variant] as Array
	var top := center + Vector2(0.5, -radii.y + 0.6)
	for i in 3:
		var base := top + Vector2(i - 1, 0)
		_line(image, base, base + crest_tips[i], crest_color, crest_dark)
	# Tail: two feathers at the back.
	var back := center + Vector2(-radii.x + 0.8, -0.5)
	var tail := [Vector2(-3, -2), Vector2(-3, 0)] if variant != 2 else [Vector2(-4, -1), Vector2(-4, 0)]
	for tip in tail:
		_line(image, back, back + tip, shade_color, outline_color)

	var light := Vector3(-0.45, -0.65, 0.61).normalized()
	for y in CANVAS.y:
		for x in CANVAS.x:
			var p := Vector2(x + 0.5, y + 0.5)
			if not _in_ellipse(p, center, radii):
				continue
			var color := outline_color
			if _in_ellipse(p + Vector2.RIGHT, center, radii) and _in_ellipse(p + Vector2.LEFT, center, radii) \
					and _in_ellipse(p + Vector2.DOWN, center, radii) and _in_ellipse(p + Vector2.UP, center, radii):
				var d := (p - center) / radii
				var normal := Vector3(d.x, d.y, sqrt(maxf(0.0, 1.0 - d.length_squared())))
				var brightness := normal.dot(light)
				color = shade_color if brightness < 0.25 else (base_color if brightness < 0.8 else light_color)
				# Pale belly, low at the front.
				if d.y > 0.25 and d.x > -0.2 and brightness >= 0.0:
					color = light_color
				# The wing: a darker feathered patch on the flank.
				var w := (p - (center + Vector2(-1.5, 0.8))) / Vector2(3.6, 2.3)
				if w.length_squared() <= 1.0:
					color = wing_color if w.length_squared() > 0.45 or w.x < -0.3 else shade_color
			image.set_pixel(x, y, color)

	# Beak at the front, a little below the eye.
	var eye_at := Vector2i((center + Vector2(radii.x * 0.45, -radii.y * 0.3)).floor())
	var beak := Vector2i(roundi(center.x + radii.x - 0.5), eye_at.y + 1)
	if variant == 3:
		beak.y += 1
	image.set_pixelv(beak, crest_color)
	image.set_pixelv(beak + Vector2i.RIGHT, crest_color)
	image.set_pixelv(beak + Vector2i(2, 0), crest_dark)
	image.set_pixelv(beak + Vector2i.DOWN, crest_dark)
	image.set_pixelv(beak + Vector2i(1, 1), crest_dark)

	match eye:
		Eye.OPEN:
			image.set_pixelv(eye_at + Vector2i(-1, -1), eye_white)
			image.set_pixelv(eye_at + Vector2i(-1, 0), eye_white)
			image.set_pixelv(eye_at + Vector2i(0, -1), eye_color)
			image.set_pixelv(eye_at, eye_color)
		Eye.BLINK:
			image.set_pixelv(eye_at + Vector2i(-1, 0), eye_color)
			image.set_pixelv(eye_at, eye_color)
		Eye.FOCUS:
			# Narrowed, with a brow pressed down over it.
			image.set_pixelv(eye_at + Vector2i(-1, -1), eye_color)
			image.set_pixelv(eye_at + Vector2i(-2, -2), eye_color)
			image.set_pixelv(eye_at + Vector2i(-1, 0), eye_white)
			image.set_pixelv(eye_at, eye_color)
		Eye.DIZZY:
			for offset in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
					Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
				image.set_pixelv(eye_at + offset, eye_color)
			image.set_pixelv(eye_at, eye_white)
	return image


# Two thin legs from the hips to the feet, the far one darker; each foot has
# a toe pointing forward (backward when the legs trail behind in a dash).
func _paint_legs(pose: Pose) -> Image:
	var image := Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	var g := float(GROUND_ROW)
	# Joints from the hip to the foot (a knee between when it is bent), for
	# the far leg, then the near one.
	var legs_of := {
		Pose.STAND: [[Vector2(10, 15), Vector2(9, g)], [Vector2(12, 15), Vector2(13, g)]],
		Pose.RUN_0: [[Vector2(10, 15), Vector2(7, g)], [Vector2(12, 15), Vector2(15, g)]],
		Pose.RUN_1: [[Vector2(10, 15), Vector2(10, g)], [Vector2(12, 15), Vector2(14, 17), Vector2(12, g - 2)]],
		Pose.RUN_2: [[Vector2(10, 15), Vector2(14, g)], [Vector2(12, 15), Vector2(8, g)]],
		Pose.RUN_3: [[Vector2(10, 15), Vector2(12, 17), Vector2(10, g - 2)], [Vector2(12, 15), Vector2(11, g)]],
		Pose.CROUCH: [[Vector2(10, 16), Vector2(12, 18), Vector2(10, g)], [Vector2(12, 16), Vector2(14, 18), Vector2(13, g)]],
		Pose.DASH: [[Vector2(10, 15), Vector2(4, 16)], [Vector2(11, 15), Vector2(5, 18)]],
		Pose.DIZZY: [[Vector2(10, 16), Vector2(7, g)], [Vector2(13, 16), Vector2(16, g)]],
	}
	var pair: Array = legs_of[pose]
	for i in 2:
		var leg: Array = pair[i]
		var color := leg_back_color if i == 0 else leg_color
		for j in leg.size() - 1:
			_line(image, leg[j], leg[j + 1], color, color)
		var foot: Vector2 = leg[leg.size() - 1]
		var toe := -1 if pose == Pose.DASH else 1
		_put(image, Vector2i(foot) + Vector2i(toe, 0), color)
	return image


func _line(image: Image, from: Vector2, to: Vector2, color: Color, tip_color: Color) -> void:
	var steps := maxi(int(maxf(absf(to.x - from.x), absf(to.y - from.y))), 1)
	for i in steps + 1:
		var at := Vector2i(from.lerp(to, float(i) / steps).round())
		_put(image, at, tip_color if i == steps else color)


func _put(image: Image, at: Vector2i, color: Color) -> void:
	if at.x >= 0 and at.y >= 0 and at.x < image.get_width() and at.y < image.get_height():
		image.set_pixelv(at, color)


func _in_ellipse(p: Vector2, center: Vector2, radii: Vector2) -> bool:
	return ((p - center) / radii).length_squared() <= 1.0


func _paint_shadow() -> Image:
	var radii := Vector2(6.5, 2.2)
	var half := Vector2i(radii.ceil())
	var size := half * 2 + Vector2i.ONE
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			var d := (Vector2(x, y) - Vector2(half)) / (radii + Vector2(0.5, 0.5))
			if d.length_squared() <= 1.0:
				image.set_pixel(x, y, shadow_color)
	return image
