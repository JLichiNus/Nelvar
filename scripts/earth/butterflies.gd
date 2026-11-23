class_name NelvarButterflies
extends Node2D
## Butterflies over the earth valley: they flutter from flower to flower, rest on one
## with their wings slowly opening and closing, and scatter when the player comes
## close. A small flock stays around the player: those left far behind reappear at
## flowers out of sight ahead. Drawn in whole art pixels of the world grid, with a
## faint shadow on the grass below each one.

const STEP := NelvarEarthData.PIXEL
const FLEE_DISTANCE := 110.0
const KEEP_DISTANCE := 1500.0
const SPAWN_DISTANCE := Vector2(380.0, 900.0)
## Wing colours, lit and shaded, of the five kinds; and the body.
const WING_LIGHT: Array[Color] = [Color8(250, 248, 236), Color8(250, 220, 90), Color8(150, 176, 244),
	Color8(246, 156, 70), Color8(240, 172, 206)]
const WING_DARK: Array[Color] = [Color8(206, 204, 188), Color8(214, 164, 42), Color8(96, 116, 206),
	Color8(196, 96, 44), Color8(198, 112, 156)]
const BODY := Color8(46, 34, 36)
const SHADOW := Color(0.05, 0.14, 0.08, 0.3)

enum State { FLY, REST, FLEE }


class Butterfly:
	var position := Vector2.ZERO
	var height := 24.0
	var velocity := Vector2.ZERO
	var target := Vector2.ZERO
	var state := State.FLY
	var timer := 0.0
	var phase := 0.0
	var palette := 0
	var wander := 0.0


@export var count := 16

var player: Node2D
var _flowers := PackedVector2Array()
var _flock: Array[Butterfly] = []
var _rng := RandomNumberGenerator.new()


func setup(data: NelvarEarthData, watched: Node2D) -> void:
	player = watched
	_rng.seed = ("%d:butterflies" % data.world_seed).hash()
	for thing in data.things:
		if thing.kind == NelvarEarthData.Kind.FLOWERS or thing.kind == NelvarEarthData.Kind.BUSH \
				and thing.variant == 2:
			_flowers.append(thing.position + Vector2(0, -thing.radius * 0.8))
	if _flowers.is_empty():
		_flowers.append(data.spawn_position)
	for i in count:
		var butterfly := Butterfly.new()
		butterfly.palette = _rng.randi_range(0, WING_LIGHT.size() - 1)
		butterfly.phase = _rng.randf() * TAU
		butterfly.wander = _rng.randf() * TAU
		_place(butterfly, data.spawn_position, Vector2(160.0, 700.0))
		_flock.append(butterfly)
	z_index = 15
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _place(butterfly: Butterfly, around: Vector2, distance: Vector2) -> void:
	var best := _flowers[_rng.randi_range(0, _flowers.size() - 1)]
	for attempt in 12:
		var flower := _flowers[_rng.randi_range(0, _flowers.size() - 1)]
		var d := flower.distance_to(around)
		if d >= distance.x and d <= distance.y:
			best = flower
			break
	butterfly.position = best + Vector2(_rng.randf_range(-60.0, 60.0), _rng.randf_range(-40.0, 40.0))
	butterfly.height = _rng.randf_range(16.0, 40.0)
	butterfly.state = State.FLY
	butterfly.target = _next_flower(butterfly.position)


func _next_flower(from: Vector2) -> Vector2:
	var best := _flowers[_rng.randi_range(0, _flowers.size() - 1)]
	for attempt in 8:
		var flower := _flowers[_rng.randi_range(0, _flowers.size() - 1)]
		if flower.distance_to(from) < best.distance_to(from) and flower.distance_to(from) > 40.0:
			best = flower
	return best


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var center := player.global_position
	for butterfly in _flock:
		_update(butterfly, delta, center)
	queue_redraw()


func _update(butterfly: Butterfly, delta: float, center: Vector2) -> void:
	var to_player := butterfly.position - center
	if to_player.length() > KEEP_DISTANCE:
		_place(butterfly, center, SPAWN_DISTANCE)
		return
	if to_player.length() < FLEE_DISTANCE and butterfly.state != State.FLEE:
		butterfly.state = State.FLEE
		butterfly.timer = _rng.randf_range(1.2, 2.0)
		butterfly.velocity = to_player.normalized().rotated(_rng.randf_range(-0.6, 0.6)) * 150.0
	match butterfly.state:
		State.REST:
			butterfly.phase += delta * 1.4
			butterfly.height = move_toward(butterfly.height, 2.0, delta * 30.0)
			butterfly.timer -= delta
			if butterfly.timer <= 0.0:
				butterfly.state = State.FLY
				butterfly.target = _next_flower(butterfly.position)
		State.FLEE:
			butterfly.phase += delta * 26.0
			butterfly.position += butterfly.velocity * delta
			butterfly.height = move_toward(butterfly.height, 56.0, delta * 50.0)
			butterfly.timer -= delta
			if butterfly.timer <= 0.0:
				butterfly.state = State.FLY
				butterfly.target = _next_flower(butterfly.position + butterfly.velocity)
		State.FLY:
			butterfly.phase += delta * 18.0
			butterfly.wander += delta * _rng.randf_range(1.0, 4.0)
			var heading := butterfly.position.direction_to(butterfly.target)
			var flutter := heading.rotated(sin(butterfly.wander) * 1.1)
			butterfly.velocity = butterfly.velocity.lerp(flutter * 52.0, minf(1.0, delta * 3.0))
			butterfly.position += butterfly.velocity * delta
			butterfly.height = clampf(butterfly.height + sin(butterfly.phase * 0.23) * delta * 30.0, 8.0, 48.0)
			if butterfly.position.distance_to(butterfly.target) < 10.0:
				butterfly.state = State.REST
				butterfly.timer = _rng.randf_range(2.0, 6.0)


func _draw() -> void:
	var cell := Vector2.ONE * STEP
	for butterfly in _flock:
		var ground := (butterfly.position / STEP).floor()
		var body := ground - Vector2(0, roundf(butterfly.height / STEP))
		if butterfly.height > 6.0:
			draw_rect(Rect2(ground * STEP, Vector2(STEP * 2.0, STEP)), SHADOW)
		var light := WING_LIGHT[butterfly.palette]
		var dark := WING_DARK[butterfly.palette]
		var frame := int(butterfly.phase) % 3 if butterfly.state != State.REST \
			else (0 if sin(butterfly.phase) > 0.3 else 2)
		match frame:
			0:
				# Wings spread: two pixels a side, the upper pixel lit.
				for side in [-1, 1]:
					draw_rect(Rect2((body + Vector2(side, -1)) * STEP, cell), light)
					draw_rect(Rect2((body + Vector2(side * 2, -1)) * STEP, cell), light)
					draw_rect(Rect2((body + Vector2(side, 0)) * STEP, cell), dark)
			1:
				for side in [-1, 1]:
					draw_rect(Rect2((body + Vector2(side, -1)) * STEP, cell), light)
					draw_rect(Rect2((body + Vector2(side, 0)) * STEP, cell), dark)
			2:
				# Folded up over the back.
				draw_rect(Rect2((body + Vector2(0, -2)) * STEP, cell), light)
				draw_rect(Rect2((body + Vector2(1, -2)) * STEP, cell), dark)
		draw_rect(Rect2((body + Vector2(0, -1)) * STEP, cell), BODY)
		draw_rect(Rect2(body * STEP, cell), BODY)
