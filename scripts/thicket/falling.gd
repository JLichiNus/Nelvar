class_name NelvarFalling
extends Node2D
## What falls from the oaks' crowns (only under an oak, never over a clearing). While the
## player is under an oak an acorn falls every few seconds (INTERVAL): 40% aimed where the
## player will be (their place and half a second of their speed), the others somewhere in
## the oak's reach 150–600 from them; no more than MAX_SHADOWS at once. Its shadow grows on
## the ground from a point to its full size for WARN seconds (darker in the last 0.2) while a
## couple of leaves flutter down ahead of it; then it strikes within HIT_RADIUS: the player
## loses PLAYER_DAMAGE and is pushed a little, enemies ENEMY_DAMAGE, puffballs nearby burst.
## It lies LIE seconds as a low obstacle and crumbles (MAX_LYING at most). Now and then a
## branch falls instead (a long shadow, BRANCH_WARN, BRANCH_DAMAGE, lying BRANCH_LIE as solid
## cover); never across a trail. The order is drawn from the map's seed.
##
## This node draws the shadows on the floor; the falling things and the leaves ahead of them
## are drawn above everything by its child.

signal struck(drop: Drop)

const STEP := NelvarEarthData.PIXEL
const INTERVAL := Vector2(3.0, 6.0)
const RANGE := Vector2(150.0, 600.0)
const AIMED := 0.4
const LEAD := 0.5
const WARN := 1.1
const DARKEN := 0.2
const SHADOW := Vector2(38.0, 46.0)
const HIT_RADIUS := 46.0
const PLAYER_DAMAGE := 14.0
const ENEMY_DAMAGE := 30.0
const PUSH := 180.0
const LIE := 25.0
const MAX_LYING := 10
const MAX_SHADOWS := 3
const BRANCH_INTERVAL := Vector2(25.0, 45.0)
const BRANCH_WARN := 1.6
const BRANCH_LENGTH := Vector2(180.0, 260.0)
const BRANCH_WIDTH := 40.0
const BRANCH_DAMAGE := 20.0
const BRANCH_LIE := 40.0
## How high up things start falling (world units), and for how long they are seen falling.
const DROP_HEIGHT := 420.0
const FALL_SEEN := 0.32
const SHADE := Color(0.05, 0.04, 0.02, 0.42)
const RUSTLE := preload("res://assets/audio/sfx/acorn_rustle.tres")
const THUD := preload("res://assets/audio/sfx/acorn_thud.tres")
const CRACK := preload("res://assets/audio/sfx/branch_crack.wav")

enum What { ACORN, BRANCH }


class Drop:
	var what := What.ACORN
	var center := Vector2.ZERO
	## Acorns: the shadow's full radius; branches: half length.
	var size := 42.0
	var start := 0.0
	var warn := WARN
	var struck := false

	func age(time: float) -> float:
		return time - start

	## True for a point within its blow.
	func hits(point: Vector2, margin: float = 0.0) -> bool:
		if what == What.ACORN:
			return point.distance_to(center) < HIT_RADIUS + margin
		var local := point - center
		return absf(local.x) < size + margin and absf(local.y) < BRANCH_WIDTH * 0.5 + margin


## Something lying where it fell: an acorn (a low obstacle) or a branch (solid cover).
class Lying extends StaticBody2D:
	var art: NelvarEarthArt
	var age := 0.0
	var life := LIE

	func _draw() -> void:
		if art == null or art.texture == null:
			return
		var left := life - age
		if left < 2.0 and int(left * 8.0) % 2 == 0:
			return
		draw_texture_rect(art.texture, art.local_rect, false)


var data: NelvarThicketData
var player: NelvarPlayer
var puffballs: NelvarPuffballs
var drops: Array[Drop] = []
var lying: Array[Lying] = []
## Acorns and branches fallen so far.
var acorns := 0
var branches := 0

var _rng := RandomNumberGenerator.new()
var _next := 0.0
var _next_branch := 0.0
var _acorn_art: NelvarEarthArt
var _branch_art: NelvarEarthArt
var _above: Node2D
var _actors: Node2D
var _time := 0.0


func setup(thicket: NelvarThicketData, the_player: NelvarPlayer, actors: Node2D, balls: NelvarPuffballs) -> void:
	data = thicket
	player = the_player
	puffballs = balls
	_actors = actors
	_rng.seed = ("%d:falling" % thicket.world_seed).hash()
	_next = _rng.randf_range(INTERVAL.x, INTERVAL.y)
	_next_branch = _rng.randf_range(BRANCH_INTERVAL.x, BRANCH_INTERVAL.y)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = -1
	_above = Node2D.new()
	_above.name = "Above"
	_above.z_index = 40
	_above.z_as_relative = false
	_above.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_above.draw.connect(_draw_above)
	add_child(_above)
	var painter := NelvarThicketPainter.new()
	var acorn := NelvarThicketData.Item.new()
	acorn.kind = NelvarEarthData.Kind.ACORN
	acorn.radius = 34.0
	acorn.appearance_seed = thicket.world_seed + 5
	_acorn_art = painter.paint(acorn)
	_acorn_art.bake()
	var twig := NelvarThicketData.Item.new()
	twig.kind = NelvarEarthData.Kind.TWIG
	twig.radius = 18.0
	twig.size = Vector2(220.0, 0.0)
	twig.appearance_seed = thicket.world_seed + 9
	_branch_art = painter.paint(twig)
	_branch_art.bake()


## Advances to `time` (the map's clock) with the player where they are.
func step(time: float, delta: float) -> void:
	_time = time
	var oak := data.oak_over(player.global_position) if is_instance_valid(player) and not player.is_dead() else null
	if oak != null:
		_next -= delta
		_next_branch -= delta
		if _next <= 0.0:
			_next = _rng.randf_range(INTERVAL.x, INTERVAL.y)
			if _shadows() < MAX_SHADOWS:
				_drop_acorn(time)
		if _next_branch <= 0.0:
			_next_branch = _rng.randf_range(BRANCH_INTERVAL.x, BRANCH_INTERVAL.y)
			_drop_branch(time)
	for drop: Drop in drops.duplicate():
		var age := drop.age(time)
		if not drop.struck and age >= drop.warn:
			drop.struck = true
			_strike(drop)
		if age > drop.warn + 0.4:
			drops.erase(drop)
	for item: Lying in lying.duplicate():
		item.age += delta
		if item.age >= item.life:
			lying.erase(item)
			item.queue_free()
		elif item.life - item.age < 2.0:
			item.queue_redraw()
	queue_redraw()
	_above.queue_redraw()


func _shadows() -> int:
	var count := 0
	for drop in drops:
		if not drop.struck:
			count += 1
	return count


## An acorn: aimed where the player will be, or somewhere near them under the oak.
func _drop_acorn(time: float) -> void:
	var at := Vector2.INF
	if _rng.randf() < AIMED:
		var aim := player.global_position + player.velocity * LEAD
		if data.oak_over(aim) != null and data.pond_depth(aim) < -20.0:
			at = aim
	if not at.is_finite():
		for attempt in 12:
			var point := player.global_position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(RANGE.x, RANGE.y)
			if data.oak_over(point) != null and data.pond_depth(point) < -20.0 and data.valley.signed_distance(point) > 40.0 \
					and data.giant_at(point, 20.0) == null:
				at = point
				break
	if not at.is_finite():
		return
	add_drop(What.ACORN, at, _rng.randf_range(SHADOW.x, SHADOW.y), time)


## A branch: a long shadow somewhere near the player, never across a trail.
func _drop_branch(time: float) -> void:
	for attempt in 16:
		var point := player.global_position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(RANGE.x, RANGE.y * 0.8)
		var half := _rng.randf_range(BRANCH_LENGTH.x, BRANCH_LENGTH.y) * 0.5
		if not branch_fits(point, half):
			continue
		add_drop(What.BRANCH, point, half, time)
		return


## Room for a branch lying across `point`: under an oak, on the floor, off the trails, the
## water, the trunks and the roots' walls.
func branch_fits(point: Vector2, half: float) -> bool:
	for k in 5:
		var at := point + Vector2(lerpf(-half, half, k / 4.0), 0.0)
		if data.oak_over(at) == null or data.valley.signed_distance(at) < 60.0 or data.pond_depth(at) > -30.0:
			return false
		if data.trail_clearance(at) < BRANCH_WIDTH or data.giant_at(at, 30.0) != null:
			return false
		if data.root_clearance(at, [NelvarThicketData.Part.HIGH]) < 30.0:
			return false
	return true


func add_drop(what: What, center: Vector2, size: float, time: float) -> Drop:
	var drop := Drop.new()
	drop.what = what
	drop.center = center
	drop.size = size
	drop.start = time
	drop.warn = WARN if what == What.ACORN else BRANCH_WARN
	drops.append(drop)
	if is_inside_tree():
		NelvarOneShotSound.play(self, RUSTLE if what == What.ACORN else CRACK, center, -2.0 if what == What.ACORN else 0.0, 1.0, 0.0)
	return drop


## The blow: the player and enemies under it are hurt, puffballs burst; it lies there.
func _strike(drop: Drop) -> void:
	if drop.what == What.ACORN:
		acorns += 1
	else:
		branches += 1
	if is_instance_valid(player) and not player.is_airborne() and not player.is_falling() and drop.hits(player.global_position):
		player.take_damage(PLAYER_DAMAGE if drop.what == What.ACORN else BRANCH_DAMAGE, drop.center)
		var away := drop.center.direction_to(player.global_position)
		player.velocity += (away if away != Vector2.ZERO else Vector2.DOWN) * PUSH
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node2D
		if body == null or (enemy.has_method("is_airborne") and enemy.call("is_airborne")):
			continue
		if drop.hits(body.global_position, 10.0):
			enemy.call("take_damage", ENEMY_DAMAGE)
	if puffballs != null:
		puffballs.burst_near(drop.center, HIT_RADIUS if drop.what == What.ACORN else drop.size)
	_dust(drop.center, 10 if drop.what == What.ACORN else 18)
	NelvarOneShotSound.play(self, THUD, drop.center, 0.0 if drop.what == What.ACORN else 3.0, 1.0 if drop.what == What.ACORN else 0.8)
	_lie(drop)
	struck.emit(drop)


func _lie(drop: Drop) -> void:
	var acorn := drop.what == What.ACORN
	if acorn:
		var count := 0
		for item in lying:
			if item.life == LIE:
				count += 1
		if count >= MAX_LYING:
			for item in lying:
				if item.life == LIE:
					lying.erase(item)
					item.queue_free()
					break
	var item := Lying.new()
	item.name = "Fallen_%d" % (acorns + branches)
	item.art = _acorn_art if acorn else _branch_art
	item.life = LIE if acorn else BRANCH_LIE
	item.position = drop.center
	item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	item.collision_layer = NelvarProp.LOW_OBSTACLE_LAYER if acorn else NelvarProp.WORLD_LAYER
	item.collision_mask = 0
	var shape := CollisionShape2D.new()
	if acorn:
		var circle := CircleShape2D.new()
		circle.radius = 26.0
		shape.shape = circle
	else:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(drop.size * 2.0, BRANCH_WIDTH * 0.6)
		shape.shape = rect
	item.add_child(shape)
	_actors.add_child.call_deferred(item)
	lying.append(item)


func _dust(at: Vector2, count: int) -> void:
	for colors: Array in [[Color(0.42, 0.34, 0.24), count], [Color(0.74, 0.6, 0.38), count / 2]]:
		var particles := CPUParticles2D.new()
		particles.one_shot = true
		particles.explosiveness = 0.9
		particles.amount = colors[1]
		particles.lifetime = 0.7
		particles.direction = Vector2.UP
		particles.spread = 80.0
		particles.initial_velocity_min = 50.0
		particles.initial_velocity_max = 150.0
		particles.gravity = Vector2(0.0, 300.0)
		particles.scale_amount_min = STEP
		particles.scale_amount_max = STEP
		particles.color = colors[0]
		particles.position = at
		particles.z_index = 20
		particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		particles.finished.connect(particles.queue_free)
		add_child(particles)
		particles.emitting = true


## The shadows on the floor: growing from a point to their size, darker just before.
func _draw() -> void:
	for drop in drops:
		if drop.struck:
			continue
		var t := clampf(drop.age(_time) / drop.warn, 0.0, 1.0)
		var color := SHADE
		if drop.warn - drop.age(_time) < DARKEN:
			color.a = 0.65
		if drop.what == What.ACORN:
			_dithered_ellipse(drop.center, Vector2(drop.size, drop.size * 0.6) * t, color)
		else:
			_dithered_ellipse(drop.center, Vector2(drop.size, BRANCH_WIDTH * 0.5) * maxf(t, 0.15), color)


func _dithered_ellipse(center: Vector2, axes: Vector2, color: Color) -> void:
	if axes.x < STEP * 0.5:
		return
	var from := ((center - axes) / STEP).floor()
	var to := ((center + axes) / STEP).ceil()
	for y in range(int(from.y), int(to.y) + 1):
		for x in range(int(from.x), int(to.x) + 1):
			var point := (Vector2(x, y) + Vector2(0.5, 0.5)) * STEP
			var d := ((point - center) / axes).length_squared()
			if d > 1.0:
				continue
			if d > 0.6 and (1.0 - (d - 0.6) / 0.4) * 16.0 <= NelvarPixelArt.bayer(Vector2i(x, y)) + 0.5:
				continue
			draw_rect(Rect2(Vector2(x, y) * STEP, Vector2.ONE * STEP), color)


## The falling things in their last moments, and the leaves fluttering down ahead of them.
func _draw_above() -> void:
	for drop in drops:
		var age := drop.age(_time)
		var left := drop.warn - age
		if left < FALL_SEEN and left > 0.0:
			var height := DROP_HEIGHT * left / FALL_SEEN
			var art := _acorn_art if drop.what == What.ACORN else _branch_art
			var at := ((drop.center - Vector2(0.0, height)) / STEP).round() * STEP
			_above.draw_texture_rect(art.texture, Rect2(at + art.local_rect.position, art.local_rect.size), false)
		elif age < drop.warn and not drop.struck:
			# Two leaves ahead of it, spiralling down.
			for k in 2:
				var fall := clampf(age / drop.warn + k * 0.25, 0.0, 1.0)
				var sway := sin(age * 5.0 + k * 2.0) * 22.0
				var at := ((drop.center + Vector2(sway + (k - 0.5) * 30.0, -DROP_HEIGHT * (1.0 - fall))) / STEP).floor() * STEP
				var color := Color8(176, 120, 52) if k == 0 else Color8(120, 140, 56)
				_above.draw_rect(Rect2(at, Vector2(STEP * 2.0, STEP)), color)
				_above.draw_rect(Rect2(at + Vector2(STEP, -STEP), Vector2(STEP, STEP)), color.darkened(0.3))
