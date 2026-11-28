class_name NelvarFireCritters
extends Node2D
## The little life of the fire forge. Ember moths flutter over the lava's edge, the ash
## flowers and the ember grass, glowing as they go, and scatter from the player.
## Salamanders bask on the lava shores; when the player comes close they run for the
## lava and dive in with a splash of sparks, to come out on another shore later.
## Drawn in whole art pixels of the world grid.

const STEP := NelvarFireData.PIXEL
const FLEE_DISTANCE := 110.0
const SCARE_DISTANCE := 150.0
const KEEP_DISTANCE := 1500.0
const MOTH_WINGS: Array[Color] = [Color8(255, 196, 96), Color8(246, 130, 52), Color8(255, 236, 160)]
const MOTH_DARK := Color8(150, 50, 30)
const LIZARD := Color8(26, 16, 18)
const LIZARD_BELLY := Color8(54, 30, 30)
const LIZARD_SPOTS := Color8(246, 132, 52)
const SHADOW := Color(0.02, 0.0, 0.02, 0.35)

enum State { FLY, REST, FLEE, BASK, RUN, GONE }


class Critter:
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var target := Vector2.ZERO
	var height := 20.0
	var state := State.FLY
	var timer := 0.0
	var phase := 0.0
	var facing := 1.0


@export var moth_count := 14
@export var salamander_count := 8

var player: Node2D
var data: NelvarFireData
## Salamanders that dived this session (for the tests).
var dives := 0

var _perches := PackedVector2Array()
var _shores := PackedVector2Array()
var _moths: Array[Critter] = []
var _lizards: Array[Critter] = []
var _embers: NelvarEmbers
var _rng := RandomNumberGenerator.new()


func setup(fire: NelvarFireData, watched: Node2D, embers: NelvarEmbers) -> void:
	data = fire
	player = watched
	_embers = embers
	_rng.seed = ("%d:critters" % fire.world_seed).hash()
	z_index = 15
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for thing in fire.things:
		if thing.kind in [NelvarFireData.Kind.ASH_FLOWER, NelvarFireData.Kind.EMBER_GRASS]:
			_perches.append(thing.position + Vector2(0, -thing.radius))
	# Basking spots: open ground just off the lava.
	for lake in fire.lakes:
		for i in 24:
			var point := lake.point_at(TAU * i / 24.0, -34.0)
			if fire.has_clearance(point, 10.0):
				_shores.append(point)
	for stream in fire.streams:
		var along := 60.0
		while along < stream.length():
			var side := stream.direction_at(along).orthogonal() * (stream.half_width + 30.0)
			for sign: float in [-1.0, 1.0]:
				var point := stream.point_at(along) + side * sign
				if fire.has_clearance(point, 10.0) and fire.lava_depth(point) > -60.0:
					_shores.append(point)
			along += 140.0
	_perches.append_array(_shores)
	if _perches.is_empty():
		_perches.append(fire.spawn_position)
	for i in moth_count:
		var moth := Critter.new()
		moth.phase = _rng.randf() * TAU
		_place_moth(moth, fire.spawn_position, Vector2(160.0, 800.0))
		_moths.append(moth)
	if not _shores.is_empty():
		for i in salamander_count:
			var lizard := Critter.new()
			_place_lizard(lizard, fire.spawn_position, 300.0)
			_lizards.append(lizard)


func _place_moth(moth: Critter, around: Vector2, distance: Vector2) -> void:
	var best := _perches[_rng.randi_range(0, _perches.size() - 1)]
	for attempt in 12:
		var perch := _perches[_rng.randi_range(0, _perches.size() - 1)]
		var d := perch.distance_to(around)
		if d >= distance.x and d <= distance.y:
			best = perch
			break
	moth.position = best + Vector2(_rng.randf_range(-50.0, 50.0), _rng.randf_range(-30.0, 30.0))
	moth.height = _rng.randf_range(16.0, 40.0)
	moth.state = State.FLY
	moth.target = _perches[_rng.randi_range(0, _perches.size() - 1)]


func _place_lizard(lizard: Critter, away_from: Vector2, distance: float) -> void:
	var spot := _shores[_rng.randi_range(0, _shores.size() - 1)]
	for attempt in 16:
		spot = _shores[_rng.randi_range(0, _shores.size() - 1)]
		if spot.distance_to(away_from) > distance:
			break
	lizard.position = spot
	lizard.state = State.BASK
	lizard.facing = -1.0 if _rng.randf() < 0.5 else 1.0
	lizard.timer = _rng.randf_range(1.0, 4.0)


func _process(delta: float) -> void:
	if data == null or not is_instance_valid(player):
		return
	var center := player.global_position
	for moth in _moths:
		_update_moth(moth, delta, center)
	for lizard in _lizards:
		_update_lizard(lizard, delta, center)
	queue_redraw()


func _update_moth(moth: Critter, delta: float, center: Vector2) -> void:
	var to_player := moth.position - center
	if to_player.length() > KEEP_DISTANCE:
		_place_moth(moth, center, Vector2(380.0, 900.0))
		return
	if to_player.length() < FLEE_DISTANCE and moth.state != State.FLEE:
		moth.state = State.FLEE
		moth.timer = _rng.randf_range(1.0, 1.8)
		moth.velocity = to_player.normalized().rotated(_rng.randf_range(-0.6, 0.6)) * 160.0
	match moth.state:
		State.REST:
			moth.phase += delta * 1.5
			moth.height = move_toward(moth.height, 3.0, delta * 30.0)
			moth.timer -= delta
			if moth.timer <= 0.0:
				moth.state = State.FLY
				moth.target = _perches[_rng.randi_range(0, _perches.size() - 1)]
		State.FLEE:
			moth.phase += delta * 26.0
			moth.position += moth.velocity * delta
			moth.height = move_toward(moth.height, 60.0, delta * 50.0)
			moth.timer -= delta
			if moth.timer <= 0.0:
				moth.state = State.FLY
				moth.target = _perches[_rng.randi_range(0, _perches.size() - 1)]
		_:
			moth.phase += delta * 16.0
			var heading := moth.position.direction_to(moth.target).rotated(sin(moth.phase * 0.17) * 1.2)
			moth.velocity = moth.velocity.lerp(heading * 58.0, minf(1.0, delta * 3.0))
			moth.position += moth.velocity * delta
			moth.height = clampf(moth.height + sin(moth.phase * 0.21) * delta * 30.0, 10.0, 50.0)
			if moth.position.distance_to(moth.target) < 12.0:
				moth.state = State.REST
				moth.timer = _rng.randf_range(1.5, 5.0)


func _update_lizard(lizard: Critter, delta: float, center: Vector2) -> void:
	match lizard.state:
		State.BASK:
			lizard.timer -= delta
			if lizard.timer <= 0.0:
				lizard.timer = _rng.randf_range(1.5, 4.0)
				lizard.phase = 0.6
			lizard.phase = maxf(0.0, lizard.phase - delta)
			if lizard.position.distance_to(center) < SCARE_DISTANCE:
				# Run for the lava: downhill of the lava's depth.
				var here := data.lava_depth(lizard.position)
				var best := Vector2.ZERO
				for i in 8:
					var direction := Vector2.from_angle(TAU * i / 8.0)
					var gain := data.lava_depth(lizard.position + direction * 20.0) - here
					if best == Vector2.ZERO or gain > data.lava_depth(lizard.position + best * 20.0) - here:
						best = direction
				lizard.velocity = best * 200.0
				lizard.facing = signf(best.x) if absf(best.x) > 0.1 else lizard.facing
				lizard.state = State.RUN
				lizard.timer = 1.5
		State.RUN:
			lizard.phase += delta * 20.0
			lizard.position += lizard.velocity * delta
			lizard.timer -= delta
			if data.lava_depth(lizard.position) > 4.0 or lizard.timer <= 0.0:
				if _embers != null:
					_embers.burst(lizard.position, 8, 0.6)
				dives += 1
				lizard.state = State.GONE
				lizard.timer = _rng.randf_range(8.0, 15.0)
		State.GONE:
			lizard.timer -= delta
			if lizard.timer <= 0.0:
				_place_lizard(lizard, center, 600.0)


func _draw() -> void:
	var cell := Vector2.ONE * STEP
	for moth in _moths:
		var ground := (moth.position / STEP).floor()
		var body := ground - Vector2(0, roundf(moth.height / STEP))
		if moth.height > 6.0:
			draw_rect(Rect2(ground * STEP, Vector2(STEP * 2.0, STEP)), SHADOW)
		var light := MOTH_WINGS[int(moth.phase * 0.3) % 3 if moth.state == State.FLEE else 0]
		var open := moth.state != State.REST and int(moth.phase) % 2 == 0
		if open:
			for side in [-1, 1]:
				draw_rect(Rect2((body + Vector2(side, -1)) * STEP, cell), light)
				draw_rect(Rect2((body + Vector2(side, 0)) * STEP, cell), MOTH_DARK)
		else:
			draw_rect(Rect2((body + Vector2(1, -1)) * STEP, cell), light)
		draw_rect(Rect2(body * STEP, cell), MOTH_DARK)
	for lizard in _lizards:
		if lizard.state == State.GONE:
			continue
		var at := (lizard.position / STEP).floor()
		var f := lizard.facing
		draw_rect(Rect2((at + Vector2(-2 * f, 1)) * STEP, Vector2(STEP * 4.0, STEP)), SHADOW)
		# Head, body, tail along the facing; spots on the back; legs that move as it runs.
		for k in range(-3, 3):
			var color := LIZARD if k != 0 else LIZARD_BELLY
			draw_rect(Rect2((at + Vector2(k * f, 0)) * STEP, cell), color)
		var wag := 1 if lizard.phase > 0.3 and int(lizard.phase * 10.0) % 2 == 0 else 0
		draw_rect(Rect2((at + Vector2(-4 * f, -wag)) * STEP, cell), LIZARD)
		draw_rect(Rect2((at + Vector2(-1 * f, -1)) * STEP, cell), LIZARD_SPOTS)
		draw_rect(Rect2((at + Vector2(1 * f, -1)) * STEP, cell), LIZARD_SPOTS)
		var step := int(lizard.phase) % 2 if lizard.state == State.RUN else 0
		for leg in [-2, 1]:
			draw_rect(Rect2((at + Vector2(leg * f + step * f, 1)) * STEP, cell), LIZARD)
		draw_rect(Rect2((at + Vector2(2 * f, -1)) * STEP, cell), LIZARD)
