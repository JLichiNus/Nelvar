class_name NelvarPuffballs
extends Node
## The puffballs of the giant forest and their clouds of spores. A puffball bursts from the
## player's shot or wind wave, from a falling acorn, and when the player walks into it; it
## shrivels, a jet of spores shoots from its top and a cloud rises round it (CLOUD_RADIUS):
## it swells for SWELL seconds, then thins out over LINGER. Inside, the player (not in
## flight) loses PLAYER_DAMAGE every TICK seconds, enemies ENEMY_DAMAGE. The wind wave drives
## the whole cloud its way at PUSH_SPEED (it stops in PUSH_TIME); the shot blows a hole in it
## (the puffs nearest it are blown away, NelvarSmoke does that). The skin lies for REGROW
## seconds, then swells back in SWELL_BACK. A cloud never bursts another puffball.
##
## The clouds are logical circles (centre, radius, drift) for the damage; NelvarSmoke draws
## their puffs in the spores' palette.

signal burst(puffball: NelvarThicketData.Puffball)

const STEP := NelvarEarthData.PIXEL
const CLOUD_RADIUS := Vector2(120.0, 170.0)
const SWELL := 0.6
const LINGER := 5.0
const TICK := 0.5
const PLAYER_DAMAGE := 3.0
const ENEMY_DAMAGE := 8.0
const PUSH_SPEED := 300.0
const PUSH_TIME := 1.2
const REGROW := 20.0
const SWELL_BACK := 3.0
## Walking into one bursts it (faster than this, towards it).
const BUMP_SPEED := 40.0
const SPORES: Array[Color] = [Color8(112, 112, 52), Color8(150, 148, 70), Color8(186, 180, 96), Color8(220, 212, 136)]
const POP := preload("res://assets/audio/sfx/puffball_pop.tres")
const JET: Array[Color] = [Color8(132, 110, 52), Color8(170, 146, 70), Color8(204, 180, 98), Color8(232, 214, 140)]


## A cloud of spores.
class Cloud:
	var center := Vector2.ZERO
	var radius := 140.0
	var velocity := Vector2.ZERO
	var age := 0.0
	var tick := 0.0
	var emit := 0.0

	func size() -> float:
		return radius * minf(1.0, 0.3 + 0.7 * age / SWELL)

	func alive() -> bool:
		return age < SWELL + LINGER

	func covers(point: Vector2) -> bool:
		return point.distance_to(center) < size()


## One puffball on screen: its collision (low or solid by its size) while whole.
class Ball extends StaticBody2D:
	var spec: NelvarThicketData.Puffball
	var whole: NelvarEarthArt
	var skin: NelvarEarthArt
	var hit: Hit
	var layer := 0
	var show_collision := false

	func _draw() -> void:
		var art := whole if spec.whole() else skin
		if spec.regrow > 0.0 and spec.regrow < SWELL_BACK and int(spec.regrow * 6.0) % 2 == 0:
			art = whole
		if art != null and art.texture != null:
			draw_texture_rect(art.texture, art.local_rect, false)
		if show_collision and spec.whole():
			draw_arc(Vector2.ZERO, spec.radius, 0.0, TAU, 24, NelvarEarthThing.DEBUG_COLOR, 2.0)


## What the player's shot and wind wave hit.
class Hit extends Area2D:
	var ball: Ball
	var owner_balls: NelvarPuffballs

	func take_damage(_amount: float) -> void:
		owner_balls.burst_ball(ball)


var data: NelvarThicketData
var player: NelvarPlayer
var smoke: NelvarSmoke
var balls: Array[Ball] = []
var clouds: Array[Cloud] = []
## Bursts so far.
var bursts := 0
## Wind attacks this frame (NelvarEmbers.gusts_in).
var gusts: Array = []

var _rng := RandomNumberGenerator.new()


## `arts`: [whole, burst] per puffball in data.puffballs order.
func setup(thicket: NelvarThicketData, arts: Array, the_player: NelvarPlayer, parent: Node, spores: NelvarSmoke) -> void:
	data = thicket
	player = the_player
	smoke = spores
	_rng.seed = ("%d:spores" % thicket.world_seed).hash()
	for i in data.puffballs.size():
		var spec := data.puffballs[i]
		var ball := Ball.new()
		ball.name = "Puffball_%d" % spec.id
		ball.spec = spec
		ball.position = spec.center
		ball.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ball.whole = arts[i][0]
		ball.skin = arts[i][1]
		ball.whole.bake()
		ball.skin.bake()
		ball.layer = NelvarProp.WORLD_LAYER if spec.solid() else NelvarProp.LOW_OBSTACLE_LAYER
		ball.collision_layer = ball.layer
		ball.collision_mask = 0
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = spec.radius
		shape.shape = circle
		ball.add_child(shape)
		ball.hit = Hit.new()
		ball.hit.name = "Hit"
		ball.hit.ball = ball
		ball.hit.owner_balls = self
		ball.hit.collision_layer = 8
		ball.hit.collision_mask = 0
		ball.hit.monitoring = false
		var hit_shape := CollisionShape2D.new()
		var hit_circle := CircleShape2D.new()
		hit_circle.radius = spec.radius + 12.0
		hit_shape.shape = hit_circle
		ball.hit.add_child(hit_shape)
		ball.add_child(ball.hit)
		parent.add_child(ball)
		balls.append(ball)


## Bursts the whole puffballs within `reach` of the point (a falling acorn).
func burst_near(point: Vector2, reach: float) -> void:
	for ball in balls:
		if ball.spec.whole() and point.distance_to(ball.spec.center) < reach + ball.spec.radius:
			burst_ball(ball)


func burst_ball(ball: Ball) -> void:
	var spec := ball.spec
	if not spec.whole():
		return
	spec.regrow = REGROW + SWELL_BACK
	bursts += 1
	NelvarOneShotSound.play(ball, POP, spec.center, -3.0)
	ball.set_deferred("collision_layer", 0)
	ball.hit.set_deferred("collision_layer", 0)
	ball.queue_redraw()
	var cloud := Cloud.new()
	cloud.center = spec.center + Vector2(0.0, -spec.radius * 0.6)
	cloud.radius = _rng.randf_range(CLOUD_RADIUS.x, CLOUD_RADIUS.y)
	clouds.append(cloud)
	if smoke != null:
		# The jet from the top, then the cloud swelling round it.
		for i in 6:
			smoke.drift(spec.center + Vector2(_rng.randf_range(-4.0, 4.0), -spec.radius * 1.8),
				Vector2(_rng.randf_range(-20.0, 20.0), _rng.randf_range(-150.0, -80.0)), _rng.randf_range(3.0, 5.0),
				_rng.randf_range(0.8, 1.4), 0.9, true)
	burst.emit(spec)


func step(delta: float) -> void:
	_bump()
	for ball in balls:
		var spec := ball.spec
		if spec.regrow <= 0.0:
			continue
		var was := spec.regrow
		spec.regrow = maxf(0.0, spec.regrow - delta)
		if spec.regrow < SWELL_BACK or spec.regrow == 0.0:
			ball.queue_redraw()
		if spec.regrow == 0.0 and was > 0.0:
			ball.set_deferred("collision_layer", ball.layer)
			ball.hit.set_deferred("collision_layer", 8)
	for cloud: Cloud in clouds.duplicate():
		cloud.age += delta
		if not cloud.alive():
			clouds.erase(cloud)
			continue
		for gust: Array in gusts:
			var reach: float = gust[2]
			# The wave (not the shot) drives the whole cloud.
			if reach > 36.0 and (gust[0] as Vector2).distance_to(cloud.center) < cloud.size() + reach:
				cloud.velocity = (gust[1] as Vector2).normalized() * PUSH_SPEED
		cloud.velocity = cloud.velocity.move_toward(Vector2.ZERO, PUSH_SPEED / PUSH_TIME * delta)
		cloud.center += cloud.velocity * delta
		cloud.tick -= delta
		if cloud.tick <= 0.0:
			cloud.tick = TICK
			_hurt(cloud)
		cloud.emit -= delta
		if cloud.emit <= 0.0 and smoke != null:
			cloud.emit = 0.11
			var fade := 1.0 - maxf(0.0, cloud.age - SWELL) / LINGER
			for i in (3 if cloud.age < SWELL else 1):
				var at := cloud.center + Vector2.from_angle(_rng.randf() * TAU) * cloud.size() * sqrt(_rng.randf()) * Vector2(1.0, 0.7)
				smoke.drift(at, cloud.velocity * 0.8 + Vector2(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-10.0, 2.0)),
					_rng.randf_range(6.0, 10.0), _rng.randf_range(1.2, 2.0), 0.75 * fade, false)


## The player walking into a puffball bursts it.
func _bump() -> void:
	if not is_instance_valid(player) or player.is_airborne() or player.is_falling():
		return
	var speed := player.velocity.length()
	if speed < BUMP_SPEED:
		return
	for ball in balls:
		var spec := ball.spec
		if not spec.whole():
			continue
		var offset := spec.center - player.global_position
		if offset.length() < spec.radius + NelvarPlayer.BODY_RADIUS + 4.0 and player.velocity.dot(offset) > 0.0:
			burst_ball(ball)


func _hurt(cloud: Cloud) -> void:
	if is_instance_valid(player) and not player.is_airborne() and not player.is_falling() and cloud.covers(player.global_position):
		player.take_damage(PLAYER_DAMAGE, cloud.center)
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node2D
		if body == null or (enemy.has_method("is_airborne") and enemy.call("is_airborne")):
			continue
		if cloud.covers(body.global_position):
			enemy.call("take_damage", ENEMY_DAMAGE)


## The cloud over the point, if any (for the tests and the hints).
func cloud_at(point: Vector2) -> Cloud:
	for cloud in clouds:
		if cloud.covers(point):
			return cloud
	return null


func set_debug(shown: bool) -> void:
	for ball in balls:
		ball.show_collision = shown
		ball.queue_redraw()
