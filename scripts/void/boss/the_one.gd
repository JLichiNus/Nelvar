class_name NelvarTheOne
extends CharacterBody2D
## Единственный — the Only One, the boss of the Void's arena. One body that the
## fight bends out of shape (NelvarTheOneBody), four phases of PHASE_HEALTH each:
## the bar empties, the body breaks into the next phase and the bar fills again.
##
##   I   Единственный — a dash that leads the player, a gravity well around
##                      itself, a rift towards the player.
##   II  Искажение    — two leading dashes, a well that creeps after the player,
##                      three parallel rifts cutting the floor into corridors.
##   III Отторжение   — three dashes whose tears all stay open, dividing the arena;
##                      twin wells circling one point, pulling in turn; a maze of
##                      crossing rifts; the collapse: rotating sectors.
##   IV  Поглощённый  — hardly moves: rings of shards that fly out and return, and
##                      a closing ring of the Void with a single gap. Short and tense.
##
## Principles: every attack is readable (it shows where and when), gets in the way
## of hitting the boss, and can be avoided at plain walking or running speed.
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
## Health of each phase; the bar shows the current phase only.
const PHASE_HEALTH := 3200.0
const PHASE_COUNT := 4
const MAX_HEALTH := PHASE_HEALTH
const WALK_SPEED := 95.0
const DASH_SPEED := 1150.0
const DASH_REACH := 950.0
const FOOT_RADIUS := 22.0
const CONTACT_RADIUS := 38.0
const CONTACT_DAMAGE := 12.0
const DASH_DAMAGE := 22.0
## The aim stops following the player this long before the dash goes.
const AIM_LOCK := 0.26
## How much of the player's motion a dash leads, and for how long at most.
const LEAD := 0.85
const LEAD_TIME := 0.75
## The maze of rifts (phase III): cell size, line length, steps and their pace.
const MAZE_CELL := 190.0
const MAZE_LENGTH := 1500.0
const MAZE_STEPS := 4
const MAZE_STEP_TIME := 1.05
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
var _trail_life := 1.9
var _trail_width := 30.0
var _locked_reach := Vector2.ZERO
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
	if health > 0.0:
		return
	if phase >= PHASE_COUNT - 1:
		_die()
	else:
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
		var left := _aim_total - _aim_age
		if left > AIM_LOCK:
			_locked_reach = _dash_target(left)
		elif not _aim.locked:
			_aim.locked = true
			body.flare(0.8)
		_aim.from = global_position
		_aim.to = global_position + _locked_reach
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
				await _attack_dashes(token, [0.75], 1.9, 30.0)
			&"double_dash":
				await _attack_dashes(token, [0.65, 0.55], 1.9, 30.0)
			&"dash_series":
				await _attack_dashes(token, [0.6, 0.5, 0.5], 1.9, 32.0, true)
			&"pull":
				await _attack_pull(token, 0)
			&"offset_pull":
				await _attack_pull(token, 1)
			&"double_pull":
				await _attack_pull(token, 2)
			&"rift":
				await _attack_rifts(token, 1, 0.0)
			&"triple_rift":
				await _attack_rifts(token, 3, 175.0)
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


## One or more dashes, each wound up for its time in `windups` and aimed anew at
## where the player is heading. With `all_stay`, every tear stays open until the
## series is over, so together they cut the arena into pieces.
func _attack_dashes(token: int, windups: Array, life: float, width: float, all_stay := false) -> void:
	for i in windups.size():
		if not await _wind_up(windups[i], token):
			return
		_trail_width = width
		_trail_life = life
		if all_stay:
			# Each tear lives until about 1.6 s after the last dash would end.
			var left := 0.0
			for j in range(i + 1, windups.size()):
				left += windups[j] + 0.75
			_trail_life = maxf(life, left + 2.6)
		var reach := _locked_reach
		if reach.length() < 1.0:
			reach = _dash_target(0.0)
		_start_dash(reach.normalized(), reach.length())
		await _dash_finished
		if token != _token or dead:
			return
		body.pose = &"idle"
		if not await _wait(0.25, token):
			return
	await _wait(0.45, token)


## The dash as it would go `delay` seconds from now: towards where the player will
## be when it gets there if they keep going (most of the way: LEAD), and on past.
func _dash_target(delay: float) -> Vector2:
	var at := player.global_position
	var motion := player.velocity * LEAD
	var point := at
	for i in 2:
		var time := minf(delay + global_position.distance_to(point) / DASH_SPEED, LEAD_TIME)
		point = at + motion * time
	var to_point := point - global_position
	if to_point.length() < 1.0:
		to_point = global_position.direction_to(at) * 1.0
	return to_point.normalized() * clampf(to_point.length() + 140.0, 260.0, DASH_REACH)


## Crouches, gathers the Void into itself and shows where it is about to go.
func _wind_up(time: float, token: int) -> bool:
	body.pose = &"windup"
	body.flare(0.6)
	NelvarVoidFx.burst(hazard_layer, global_position + Vector2(0.0, -70.0), 22, NelvarVoidFx.VIOLET,
		-220.0, minf(time, 0.6), 110.0)
	_aim = NelvarVoidHazards.Aim.new()
	_aim_age = 0.0
	_aim_total = time
	_locked_reach = _dash_target(time)
	_spawn(_aim, Vector2.ZERO, 0.0)
	var alive := await _wait(time, token)
	_drop_aim()
	return alive


func _drop_aim() -> void:
	if is_instance_valid(_aim):
		_aim.queue_free()
	_aim = null


## 0: a well around itself; 1: one next to the player that creeps after them and
## stops before it bursts; 2: twins circling a point between the boss and the
## player, pulling in turn, bursting one after the other.
func _attack_pull(token: int, mode: int) -> void:
	body.pose = &"cast"
	body.flare(1.2)
	NelvarVoidFx.burst(hazard_layer, global_position + Vector2(0.0, -110.0), 20, NelvarVoidFx.PALE, 200.0, 0.5)
	if not await _wait(0.3, token):
		return
	var wait := 2.6
	match mode:
		0:
			var pull := NelvarVoidHazards.Pull.new()
			pull.start_radius = 130.0
			pull.radius = 270.0
			pull.duration = 2.3
			pull.strength = 175.0
			_spawn(pull, global_position, DAMAGE["pull"])
		1:
			var pull := NelvarVoidHazards.Pull.new()
			pull.start_radius = 100.0
			pull.radius = 235.0
			pull.duration = 2.7
			pull.strength = 165.0
			pull.follow = player
			pull.follow_speed = 75.0
			pull.lock_time = 0.7
			_spawn(pull, player.global_position + Vector2.from_angle(_rng.randf() * TAU) * 90.0, DAMAGE["pull"])
			wait = 3.0
		_:
			var pivot := global_position.lerp(player.global_position, 0.6)
			var start := _rng.randf() * TAU
			var turn := 0.55 * (1.0 if _rng.randf() < 0.5 else -1.0)
			var twins: Array[NelvarVoidHazards.Pull] = []
			for i in 2:
				var pull := NelvarVoidHazards.Pull.new()
				pull.start_radius = 90.0
				pull.radius = 195.0
				pull.duration = 2.6 + i * 0.9
				pull.strength = 150.0
				pull.orbit_center = pivot
				pull.orbit_radius = 215.0
				pull.orbit_angle = start + i * PI
				pull.orbit_speed = turn
				pull.lock_time = 0.55
				pull.pulse_period = 1.5
				pull.pulse_offset = i * PI
				twins.append(pull)
			twins[0].twin = twins[1]
			for pull in twins:
				_spawn(pull, pivot, DAMAGE["pull"])
			wait = 3.8
	if not await _wait(wait, token):
		return
	body.pose = &"idle"
	await _wait(0.4, token)


## Drags the long arm over the floor: rifts run out towards the player. With more
## than one they go side by side, `spacing` apart, cutting the floor into corridors;
## the middle one goes straight at the player, so they have to step into one.
func _attack_rifts(token: int, count: int, spacing: float) -> void:
	body.pose = &"swipe"
	var reach := create_tween()
	reach.tween_property(body, "reach", 1.7, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not await _wait(0.45, token):
		body.reach = 1.0
		return
	var direction := global_position.direction_to(player.global_position)
	var side := direction.orthogonal()
	body.flare(1.0)
	_burst(70.0, 0.4, global_position + direction * 60.0)
	for i in count:
		var offset := (i - (count - 1) * 0.5) * spacing
		var rift := NelvarVoidHazards.Rift.new()
		rift.direction = direction
		rift.length = 1050.0
		rift.telegraph = 0.8 + absf(offset) / maxf(spacing, 1.0) * 0.15
		rift.hold = 2.0 if count == 1 else 2.6
		_spawn(rift, global_position + direction * 30.0 + side * offset - direction * absf(offset) * 0.4,
			DAMAGE["rift"])
	create_tween().tween_property(body, "reach", 1.0, 0.5)
	if not await _wait(1.3, token):
		return
	body.pose = &"idle"
	await _wait(0.3, token)


## The maze: a grid of lines through the cells around the player. First two lanes
## either side of them, then lines across, one after another, each through the cell
## the player should be in, so they step from cell to cell. Every next line leaves
## a neighbouring cell free of every line open at the time: there is always a way.
func _attack_cross_rifts(token: int) -> void:
	body.pose = &"swipe"
	create_tween().tween_property(body, "reach", 1.8, 0.3)
	if not await _wait(0.4, token):
		body.reach = 1.0
		return
	body.flare(1.2)
	NelvarVoidFx.glitch(self, 0.2, 0.4)
	var plan := maze_plan(player.global_position, _rng.randf() * PI, _rng)
	var clock := 0.0
	for line: Dictionary in plan:
		if line["at"] > clock:
			if not await _wait(line["at"] - clock, token):
				body.reach = 1.0
				return
			clock = line["at"]
			body.flare(0.5)
		var rift := NelvarVoidHazards.Rift.new()
		rift.direction = line["direction"]
		rift.length = MAZE_LENGTH
		rift.width = 40.0
		rift.telegraph = line["telegraph"]
		rift.hold = line["hold"]
		_spawn(rift, line["from"], DAMAGE["rift"])
	create_tween().tween_property(body, "reach", 1.0, 0.6)
	if not await _wait(2.2, token):
		return
	body.pose = &"idle"
	await _wait(0.3, token)


## The lines of the maze around `center`, its grid turned by `angle`: each is
## {at, from, direction, telegraph, hold}, `at` seconds after the start. The cell
## the player is meant to stand in moves one step across each new line.
func maze_plan(center: Vector2, angle: float, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var u := Vector2.from_angle(angle)
	var v := u.orthogonal()
	# Lines as [axis (0: along u, through a row; 1: along v, through a column),
	# index, opens, closes].
	var lines: Array[Array] = []
	var plan: Array[Dictionary] = []
	var add := func(axis: int, index: int, at: float, telegraph: float, hold: float) -> void:
		var through := center + (v if axis == 0 else u) * index * MAZE_CELL
		var along := u if axis == 0 else v
		# Alternate the end each line tears from.
		if (plan.size() % 2) == 1:
			along = -along
		var travel := MAZE_LENGTH / 1300.0
		lines.append([axis, index, at + telegraph, at + telegraph + hold + travel + 0.3])
		plan.append({"at": at, "from": through - along * MAZE_LENGTH * 0.5, "direction": along,
			"telegraph": telegraph, "hold": hold})
	# Two lanes either side of the player.
	add.call(0, -1, 0.0, 0.9, 3.4)
	add.call(0, 1, 0.0, 0.9, 3.4)
	var cell := Vector2i.ZERO
	var last_axis := 0
	for step in MAZE_STEPS:
		var at := 0.55 + step * MAZE_STEP_TIME
		var opens := at + 1.0
		var options: Array[Array] = []
		for axis in 2:
			for way in [-1, 1]:
				# A line through the cell along `axis`; the way out is across it.
				var target: Vector2i = cell + (Vector2i(0, way) if axis == 0 else Vector2i(way, 0))
				var world := center + u * target.x * MAZE_CELL + v * target.y * MAZE_CELL
				if world.distance_to(arena_center) > NelvarVoidData.ARENA_REACH - 170.0:
					continue
				if _maze_cell_hit(lines, target, opens - 0.6, opens + MAZE_STEP_TIME + 0.6):
					continue
				options.append([axis, target])
		if options.is_empty():
			break
		# Prefer crossing the last line, so the maze turns.
		var crossing := options.filter(func(o: Array) -> bool: return o[0] != last_axis)
		var pick: Array = (crossing if not crossing.is_empty() else options)[
			rng.randi_range(0, (crossing if not crossing.is_empty() else options).size() - 1)]
		var axis: int = pick[0]
		add.call(axis, cell.y if axis == 0 else cell.x, at, 1.0, 2.2)
		cell = pick[1]
		last_axis = axis
	return plan


## Whether a line open at some moment between `from` and `to` runs through `cell`.
static func _maze_cell_hit(lines: Array[Array], cell: Vector2i, from: float, to: float) -> bool:
	for line in lines:
		if line[3] < from or line[2] > to:
			continue
		if (line[0] == 0 and line[1] == cell.y) or (line[0] == 1 and line[1] == cell.x):
			return true
	return false


## Collapse: to the centre, then sectors of the arena tear open and turn, again and again.
func _attack_collapse(token: int) -> void:
	body.pose = &"spread"
	body.flare(1.5)
	var sectors := NelvarVoidHazards.Sectors.new()
	sectors.start = arena_center.direction_to(player.global_position).angle()
	_spawn(sectors, arena_center, DAMAGE["sectors"])
	# A new phase takes the collapse away with it.
	phase_changed.connect(func(_phase: int) -> void:
		if is_instance_valid(sectors):
			sectors.queue_free(), CONNECT_ONE_SHOT)
	# Show the destination before the boss can make contact at the centre.
	if not await _wait(0.45, token):
		return
	if not await _blink_to(arena_center, token):
		return
	if not await _wait(sectors.duration() - sectors.age + 0.3, token):
		return
	body.pose = &"idle"


## The second outward spiral crosses the first as it curls back in.
func _attack_shards(token: int) -> void:
	body.pose = &"spread"
	var tell := NelvarVoidHazards.Shard.WARNING
	var spacing := NelvarVoidHazards.Shard.LAUNCH_SPACING
	_spawn_shard_ring(0.0)
	if not await _wait(tell, token):
		return
	body.flare(1.2)
	_burst(120.0, 0.35)
	if not await _wait(spacing - tell, token):
		return
	_spawn_shard_ring(NelvarVoidHazards.Shard.crossing_offset(spacing))
	if not await _wait(tell, token):
		return
	body.flare(1.2)
	_burst(120.0, 0.35)
	await _wait(NelvarVoidHazards.Shard.FLIGHT_TIME + NelvarVoidHazards.Shard.SPOKE_STAGGER + 0.3, token)


## The Void closes in from the edges of the arena; one gap in the ring lets the player out.
func _attack_squeeze(token: int) -> void:
	body.pose = &"cast"
	body.flare(1.5)
	NelvarVoidFx.glitch(self, 0.3, 0.6)
	var squeeze := NelvarVoidHazards.Squeeze.new()
	# The path is already in reach if the player starts at the arena's edge.
	squeeze.gap = global_position.direction_to(player.global_position).angle() - squeeze.gap_at(squeeze.warn)
	_spawn(squeeze, global_position, DAMAGE["squeeze"])
	if not await _wait(squeeze.duration + 0.4, token):
		return
	body.pose = &"spread"


func _spawn_shard_ring(heading: float) -> void:
	var count := NelvarVoidHazards.Shard.COUNT
	for i in count:
		var shard := NelvarVoidHazards.Shard.new()
		shard.heading = heading + TAU * i / count
		shard.telegraph += NelvarVoidHazards.Shard.SPOKE_STAGGER * (i % 2)
		_spawn(shard, global_position, DAMAGE["shard"])


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
	# Whole again for the next phase (the bar has filled up meanwhile).
	health = max_health
	health_changed.emit(health, max_health)
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
