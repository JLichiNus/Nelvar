class_name NelvarTheOne
extends CharacterBody2D
## Единственный — the Only One, the boss of the Void's arena. One body that the
## fight bends out of shape (NelvarTheOneBody), four phases by remaining health:
##
##   I   Единственный — dash, pull around itself, a rift towards the player.
##   II  Искажение    — two dashes (aimed anew), a pull next to the player, three
##                      rifts in a fan.
##   III Отторжение   — three dashes (the last trail stays long), two pulls tearing
##                      the player both ways, rifts crossing the arena one after
##                      another, and the collapse: rotating sectors from the centre.
##   IV  Поглощённый  — hardly moves: rings of shards that fly out and return, and
##                      a closing ring of the Void with a single gap. Short and tense.
##
## Attacks are coroutines guarded by a token: a phase change or death bumps it and
## whatever was running stops at its next wait. Hazards are NelvarVoidHazards.

signal health_changed(current: float, maximum: float)
signal phase_changed(phase: int)
signal defeated
signal _dash_finished

const DISPLAY_NAME := "Единственный"
const PHASE_TITLES: Array[String] = ["Единственный", "Искажение", "Отторжение", "Поглощённый"]
const PHASE_NUMERALS: Array[String] = ["I", "II", "III", "IV"]
## Share of health at which phases II, III and IV begin.
const PHASE_AT: Array[float] = [0.7, 0.42, 0.14]
const MAX_HEALTH := 3200.0
const WALK_SPEED := 95.0
const DASH_SPEED := 1150.0
const DASH_REACH := 950.0
const FOOT_RADIUS := 22.0
const CONTACT_RADIUS := 38.0
const CONTACT_DAMAGE := 12.0
const DASH_DAMAGE := 22.0
const INTRO_TIME := 2.6
const SHIFT_TIME := 1.6
const DEATH_TIME := 2.8
## Where it keeps itself from the player between attacks, and how far from the centre.
const KEEP_DISTANCE := 230.0
const ROAM_RADIUS := 600.0

const DAMAGE := {
	"trail": 12.0, "pull": 24.0, "rift": 24.0, "sectors": 26.0, "shard": 14.0, "squeeze": 28.0,
}

var max_health := MAX_HEALTH
var health := MAX_HEALTH
var phase := 0
var player: NelvarPlayer
var arena_center := Vector2.ZERO
## Where ground hazards go (the world layer: under the actors, over the floor).
var hazard_layer: Node2D
var active := false
var dead := false

var body: NelvarTheOneBody
var _token := 0
var _invulnerable := true
var _walking := false
var _walk_target := Vector2.ZERO
var _dashing := false
var _dash_direction := Vector2.ZERO
var _dash_left := 0.0
var _dash_start := Vector2.ZERO
var _trail_life := 0.7
var _trail_width := 30.0
var _last_attack := &""
var _rng := RandomNumberGenerator.new()
var _aim: NelvarVoidHazards.Aim
var _aim_age := 0.0
var _aim_total := 1.0
var _afterimage_left := 0.0
var _spark_left := 0.0


func _ready() -> void:
	name = "TheOne"
	add_to_group("enemies")
	# Its feet stop at walls (the seal, obelisks); attacks hit the hurtbox instead.
	collision_layer = 0
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var feet := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = FOOT_RADIUS
	feet.shape = circle
	add_child(feet)
	var hurtbox := NelvarBossHurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.boss = self
	hurtbox.collision_layer = 8
	hurtbox.collision_mask = 0
	hurtbox.monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(56.0, 140.0)
	shape.shape = rect
	shape.position = Vector2(0.0, -74.0)
	hurtbox.add_child(shape)
	add_child(hurtbox)
	body = NelvarTheOneBody.new()
	body.name = "Body"
	add_child(body)
	body.presence = 0.0
	_rng.randomize()


## Called by the arena once the fight starts: the Only One forms out of the sigil.
func begin(target: NelvarPlayer, center: Vector2, hazards: Node2D) -> void:
	player = target
	arena_center = center
	hazard_layer = hazards
	health_changed.emit(health, max_health)
	# A pillar of light out of the sigil, the Void streaming into it, then a body.
	var pillar := NelvarVoidHazards.Pillar.new()
	pillar.life = INTRO_TIME
	_spawn(pillar, global_position, 0.0)
	NelvarVoidFx.glitch(self, 0.4, 0.4)
	body.glitch(INTRO_TIME * 0.6)
	var tween := create_tween()
	tween.tween_property(body, "presence", 1.0, INTRO_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	await tween.finished
	if dead:
		return
	_burst(260.0, 1.1)
	NelvarVoidFx.flash(self, NelvarVoidFx.PALE, 0.35, 0.5)
	NelvarVoidFx.glitch(self, 0.35, 0.8)
	body.flare(1.5)
	_invulnerable = false
	active = true
	_brain(_token)


func take_damage(amount: float) -> void:
	if dead or _invulnerable or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	body.flash()
	body.flare(0.25)
	if _spark_left <= 0.0:
		_spark_left = 0.07
		var at := global_position + Vector2(_rng.randf_range(-18.0, 18.0), _rng.randf_range(-130.0, -30.0))
		NelvarVoidFx.burst(hazard_layer if hazard_layer != null else self, at, 7, NelvarVoidFx.PALE, 170.0, 0.3)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die()
	elif phase < PHASE_AT.size() and health / max_health <= PHASE_AT[phase]:
		_shift_phase()


## The wind cannot hold the Only One, nor push it.
func apply_hold(_duration: float) -> void:
	pass


func apply_knockback(_force: Vector2) -> void:
	pass


func phase_title() -> String:
	return "%s · %s" % [PHASE_NUMERALS[phase], PHASE_TITLES[phase]]


# --- Movement and contact ------------------------------------------------------

func _physics_process(delta: float) -> void:
	if dead or player == null:
		return
	body.aim = global_position.direction_to(player.global_position)
	_spark_left -= delta
	if is_instance_valid(_aim):
		_aim_age += delta
		var reach := _dash_target()
		_aim.from = global_position
		_aim.to = global_position + reach
		_aim.charge = clampf(_aim_age / _aim_total, 0.0, 1.0)
	if _dashing:
		_step_dash(delta)
		return
	velocity = Vector2.ZERO
	if _walking and phase < 3:
		var to_target := _walk_target - global_position
		if to_target.length() > 12.0:
			velocity = to_target.normalized() * WALK_SPEED * (1.35 if phase == 2 else 1.0)
	move_and_slide()
	if _walking:
		body.pose = &"walk" if velocity.length() > 1.0 else &"idle"
	if active:
		_touch(CONTACT_DAMAGE)


func _touch(damage: float) -> void:
	if player.is_flight_protected() or player.is_falling():
		return
	if player.global_position.distance_to(global_position) < CONTACT_RADIUS:
		player.take_damage(damage, global_position)


func _start_dash(direction: Vector2, distance: float) -> void:
	_dashing = true
	_dash_direction = direction
	_dash_left = distance
	_dash_start = global_position
	body.pose = &"dash"
	body.flare(1.0)
	_afterimage_left = 0.0
	NelvarVoidFx.shock(self, global_position, 0.3)
	NelvarVoidFx.burst(hazard_layer, global_position + Vector2(0.0, -40.0), 16, NelvarVoidFx.VIOLET, 240.0, 0.4)


func _step_dash(delta: float) -> void:
	var step := minf(DASH_SPEED * delta, _dash_left)
	var hit := move_and_collide(_dash_direction * step)
	_dash_left -= step
	_touch(DASH_DAMAGE)
	# Afterimages: the body leaves copies of itself as it tears through.
	_afterimage_left -= delta
	if _afterimage_left <= 0.0:
		_afterimage_left = 0.035
		body.afterimage()
	if hit != null or _dash_left <= 0.0:
		_end_dash()


func _end_dash() -> void:
	if not _dashing:
		return
	_dashing = false
	if not dead:
		_burst(90.0, 0.35)
	if _dash_start.distance_to(global_position) > 20.0 and not dead:
		var trail := NelvarVoidHazards.Trail.new()
		trail.from = _dash_start
		trail.to = global_position
		trail.life = _trail_life
		trail.width = _trail_width
		_spawn(trail, Vector2.ZERO, DAMAGE["trail"])
	_dash_finished.emit()


func _burst(radius: float, power: float, at := Vector2.INF) -> void:
	var burst := NelvarVoidHazards.Burst.new()
	burst.radius = radius
	burst.power = power
	_spawn(burst, global_position if at == Vector2.INF else at, 0.0)


func _spawn(hazard: NelvarVoidHazards.Hazard, at: Vector2, damage: float) -> NelvarVoidHazards.Hazard:
	hazard.player = player
	hazard.damage = damage
	hazard.position = at
	hazard_layer.add_child(hazard)
	return hazard


## Gone for a moment and back elsewhere; its contours stay behind a little longer.
func _blink_to(point: Vector2, token: int) -> bool:
	var out := create_tween()
	out.tween_property(body, "presence", 0.0, 0.22)
	await out.finished
	if token != _token or dead:
		body.presence = 1.0
		return false
	_burst(80.0, 0.0)
	global_position = point
	_burst(110.0, 0.4)
	var back := create_tween()
	back.tween_property(body, "presence", 1.0, 0.22)
	await back.finished
	return token == _token and not dead


# --- Brain -----------------------------------------------------------------

func _brain(token: int) -> void:
	while token == _token and not dead:
		if not await _between(token):
			return
		var attack := _pick_attack()
		_last_attack = attack
		match attack:
			&"dash":
				await _attack_dashes(token, [0.6], 0.7, 30.0)
			&"double_dash":
				await _attack_dashes(token, [0.5, 0.35], 0.7, 30.0)
			&"dash_series":
				await _attack_dashes(token, [0.34, 0.3, 0.3], 0.7, 30.0, true)
			&"pull":
				await _attack_pull(token, 0)
			&"offset_pull":
				await _attack_pull(token, 1)
			&"double_pull":
				await _attack_pull(token, 2)
			&"rift":
				await _attack_rifts(token, 1, 0.0)
			&"triple_rift":
				await _attack_rifts(token, 3, 0.38)
			&"cross_rifts":
				await _attack_cross_rifts(token)
			&"collapse":
				await _attack_collapse(token)
			&"shards":
				await _attack_shards(token)
			&"squeeze":
				await _attack_squeeze(token)


func _pick_attack() -> StringName:
	var options: Array[StringName] = []
	match phase:
		0:
			options = [&"dash", &"pull", &"rift"]
		1:
			options = [&"double_dash", &"offset_pull", &"triple_rift"]
		2:
			options = [&"dash_series", &"double_pull", &"cross_rifts", &"collapse"]
		_:
			options = [&"shards", &"squeeze"]
	options.erase(_last_attack)
	return options[_rng.randi_range(0, options.size() - 1)]


## Between attacks it stalks the player, keeping a little distance; in the last
## phase it only hangs in the centre.
func _between(token: int) -> bool:
	var pauses: Array[Vector2] = [Vector2(1.1, 1.8), Vector2(0.8, 1.4), Vector2(0.5, 1.0), Vector2(0.6, 0.9)]
	var time := _rng.randf_range(pauses[phase].x, pauses[phase].y)
	if phase >= 3:
		body.pose = &"spread"
		return await _wait(time, token)
	var away := player.global_position.direction_to(global_position)
	_walk_target = player.global_position + away * KEEP_DISTANCE
	var from_center := _walk_target - arena_center
	if from_center.length() > ROAM_RADIUS:
		_walk_target = arena_center + from_center.normalized() * ROAM_RADIUS
	_walking = true
	var alive := await _wait(time, token)
	_walking = false
	body.pose = &"idle"
	return alive


func _wait(seconds: float, token: int) -> bool:
	await get_tree().create_timer(seconds, false).timeout
	return token == _token and not dead


## One or more dashes, each wound up for its time in `windups` and aimed anew. With
## `long_last`, the final one leaves a trail that lingers.
func _attack_dashes(token: int, windups: Array, life: float, width: float, long_last := false) -> void:
	for i in windups.size():
		if not await _wind_up(windups[i], token):
			return
		var last := i == windups.size() - 1
		_trail_life = 3.0 if long_last and last else life
		_trail_width = 46.0 if long_last and last else width
		var reach := _dash_target()
		_start_dash(reach.normalized(), reach.length())
		await _dash_finished
		if token != _token or dead:
			return
		body.pose = &"idle"
		if not await _wait(0.25, token):
			return
	await _wait(0.45, token)


## The dash as it would go now: through the player and a little past them.
func _dash_target() -> Vector2:
	var to_player := player.global_position - global_position
	return to_player.normalized() * minf(to_player.length() + 140.0, DASH_REACH)


## Crouches, gathers the Void into itself and shows where it is about to go.
func _wind_up(time: float, token: int) -> bool:
	body.pose = &"windup"
	body.flare(0.6)
	NelvarVoidFx.burst(hazard_layer, global_position + Vector2(0.0, -70.0), 22, NelvarVoidFx.VIOLET,
		-220.0, minf(time, 0.6), 110.0)
	_aim = NelvarVoidHazards.Aim.new()
	_aim_age = 0.0
	_aim_total = time
	_spawn(_aim, Vector2.ZERO, 0.0)
	var alive := await _wait(time, token)
	_drop_aim()
	return alive


func _drop_aim() -> void:
	if is_instance_valid(_aim):
		_aim.queue_free()
	_aim = null


## 0: around itself; 1: next to the player; 2: two, on either side of the player.
func _attack_pull(token: int, mode: int) -> void:
	body.pose = &"cast"
	body.flare(1.2)
	NelvarVoidFx.burst(hazard_layer, global_position + Vector2(0.0, -110.0), 20, NelvarVoidFx.PALE, 200.0, 0.5)
	if not await _wait(0.3, token):
		return
	var centers: Array[Vector2] = [global_position]
	var radius := 260.0
	if mode == 1:
		centers = [player.global_position + Vector2.from_angle(_rng.randf() * TAU) * 70.0]
		radius = 230.0
	elif mode == 2:
		var across := global_position.direction_to(player.global_position).orthogonal()
		centers = [player.global_position + across * 250.0, player.global_position - across * 250.0]
		radius = 220.0
	for center in centers:
		var pull := NelvarVoidHazards.Pull.new()
		pull.radius = radius
		pull.strength = 135.0 if mode == 2 else 150.0
		_spawn(pull, center, DAMAGE["pull"])
	if not await _wait(2.2, token):
		return
	body.pose = &"idle"
	await _wait(0.4, token)


## Drags the long arm over the floor: rifts run out towards the player, fanned out.
func _attack_rifts(token: int, count: int, spread: float) -> void:
	body.pose = &"swipe"
	var reach := create_tween()
	reach.tween_property(body, "reach", 1.7, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not await _wait(0.45, token):
		body.reach = 1.0
		return
	var direction := global_position.direction_to(player.global_position)
	body.flare(1.0)
	_burst(70.0, 0.4, global_position + direction * 60.0)
	for i in count:
		var rift := NelvarVoidHazards.Rift.new()
		rift.direction = direction.rotated((i - (count - 1) * 0.5) * spread)
		rift.length = 1000.0
		rift.telegraph = 0.75
		_spawn(rift, global_position + rift.direction * 30.0, DAMAGE["rift"])
	create_tween().tween_property(body, "reach", 1.0, 0.5)
	if not await _wait(1.1, token):
		return
	body.pose = &"idle"
	await _wait(0.3, token)


## Rifts across the whole arena, crossing near the player, opening one by one.
func _attack_cross_rifts(token: int) -> void:
	body.pose = &"swipe"
	create_tween().tween_property(body, "reach", 1.8, 0.3)
	if not await _wait(0.4, token):
		body.reach = 1.0
		return
	body.flare(1.2)
	NelvarVoidFx.glitch(self, 0.2, 0.4)
	var count := 5
	for i in count:
		var through := player.global_position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 180.0)
		var direction := Vector2.from_angle(_rng.randf() * PI + i * PI / count)
		var rift := NelvarVoidHazards.Rift.new()
		rift.direction = direction
		rift.length = 1500.0
		rift.width = 40.0
		rift.telegraph = 1.0 + i * 0.3
		_spawn(rift, through - direction * 750.0, DAMAGE["rift"])
	create_tween().tween_property(body, "reach", 1.0, 0.6)
	if not await _wait(2.8, token):
		return
	body.pose = &"idle"
	await _wait(0.3, token)


## Collapse: to the centre, then sectors of the arena tear open and turn, again and again.
func _attack_collapse(token: int) -> void:
	if not await _blink_to(arena_center, token):
		return
	body.pose = &"spread"
	body.flare(1.5)
	var sectors := NelvarVoidHazards.Sectors.new()
	sectors.count = 6
	sectors.arc = 0.52
	# The first wave is aimed at the player.
	sectors.start = arena_center.direction_to(player.global_position).angle()
	sectors.turn = 0.36 * (1.0 if _rng.randf() < 0.5 else -1.0)
	sectors.cycles = 4
	sectors.telegraph = 0.85
	sectors.outer = NelvarVoidData.ARENA_REACH
	_spawn(sectors, arena_center, DAMAGE["sectors"])
	if not await _wait(sectors.cycles * (sectors.telegraph + sectors.fire_time) + 0.3, token):
		return
	body.pose = &"idle"


## A ring of shards flies out, stops and returns; a second ring between the first.
func _attack_shards(token: int) -> void:
	body.pose = &"spread"
	if not await _wait(0.35, token):
		return
	for ring in 2:
		body.flare(1.2)
		_burst(120.0, 0.45)
		var count := 18
		for i in count:
			var shard := NelvarVoidHazards.Shard.new()
			shard.direction = Vector2.from_angle(TAU * (i + ring * 0.5) / count)
			shard.boss = self
			_spawn(shard, global_position + Vector2(0.0, -14.0), DAMAGE["shard"])
		if not await _wait(1.2, token):
			return
	await _wait(2.0, token)


## The Void closes in from the edges of the arena; one gap in the ring lets the player out.
func _attack_squeeze(token: int) -> void:
	body.pose = &"cast"
	body.flare(1.5)
	NelvarVoidFx.glitch(self, 0.3, 0.6)
	var squeeze := NelvarVoidHazards.Squeeze.new()
	squeeze.gap = _rng.randf() * TAU
	squeeze.start_radius = NelvarVoidData.ARENA_REACH * 0.95
	_spawn(squeeze, global_position, DAMAGE["squeeze"])
	if not await _wait(squeeze.duration + 0.4, token):
		return
	body.pose = &"spread"


# --- Phases and death ----------------------------------------------------------

func _shift_phase() -> void:
	_token += 1
	var token := _token
	active = false
	_invulnerable = true
	_walking = false
	_end_dash()
	_drop_aim()
	body.reach = 1.0
	phase += 1
	body.phase = phase
	body.glitch(SHIFT_TIME)
	body.pose = &"spread"
	phase_changed.emit(phase)
	# The world stutters with it: slow motion, the picture tears, a flash, a wave.
	NelvarVoidFx.slow_motion(self, 0.35, 0.55)
	NelvarVoidFx.glitch(self, 0.7, 1.0)
	NelvarVoidFx.flash(self, NelvarVoidFx.PALE, 0.35, 0.45)
	body.flare(2.0)
	_burst(300.0, 1.2)
	if phase >= 3:
		await _blink_to(arena_center, token)
	await get_tree().create_timer(SHIFT_TIME, false).timeout
	if dead or token != _token:
		return
	_invulnerable = false
	active = true
	_brain(token)


func _die() -> void:
	dead = true
	get_tree().call_group(&"player", &"register_kill")
	_token += 1
	active = false
	_invulnerable = true
	_walking = false
	if _dashing:
		_dashing = false
		_dash_finished.emit()
	_drop_aim()
	for hazard in get_tree().get_nodes_in_group("void_hazards"):
		hazard.queue_free()
	body.pose = &"spread"
	body.glitch(DEATH_TIME)
	body.flare(2.5)
	# Everything slows; the Void it was made of is sucked back into it...
	NelvarVoidFx.slow_motion(self, 0.3, 1.3)
	NelvarVoidFx.glitch(self, 1.3, 0.9)
	var heart := global_position + Vector2(0.0, -70.0)
	NelvarVoidFx.burst(hazard_layer, heart, 70, NelvarVoidFx.PALE, -420.0, 1.0, 340.0)
	await get_tree().create_timer(DEATH_TIME * 0.5, false).timeout
	# ...and it comes apart in light.
	NelvarVoidFx.flash(self, NelvarVoidFx.PALE, 0.7, 1.2)
	_burst(520.0, 1.5)
	_burst(220.0, 0.0, heart)
	NelvarVoidFx.burst(hazard_layer, heart, 90, NelvarVoidFx.PALE, 700.0, 1.2)
	NelvarVoidFx.burst(hazard_layer, heart, 40, NelvarVoidFx.DARK, 420.0, 1.4, 0.0, false)
	var tween := create_tween()
	tween.tween_property(body, "presence", 0.0, DEATH_TIME * 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	await tween.finished
	defeated.emit()
	queue_free()
