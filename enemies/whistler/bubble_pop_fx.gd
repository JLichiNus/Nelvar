extends Node2D
## A bubble bursting: for a moment its skin flashes as a wider ring, then a few
## droplets fly out, fall a little and fade. Pixels on the world grid, like the
## bubble itself; frees itself when done.

const TEXEL := 3.0
const DURATION := 0.32
const RING_TIME := 0.06

var radius := 9.0
var height := 19.0
var rim := Color.WHITE
var outline := Color.BLACK
var droplets := 7

var _age := 0.0
var _drops: Array[Dictionary] = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for i in droplets:
		var angle := TAU * (i + randf() * 0.7) / droplets
		_drops.append({
			"pos": Vector2(0.0, -height),
			"vel": Vector2.from_angle(angle) * randf_range(70.0, 140.0),
			"size": 2.0 if i % 3 == 0 else 1.0,
		})


func _process(delta: float) -> void:
	_age += delta
	if _age >= DURATION:
		queue_free()
		return
	for drop in _drops:
		drop.vel *= exp(-delta * 5.0)
		drop.vel.y += 260.0 * delta
		drop.pos += drop.vel * delta
	queue_redraw()


func _draw() -> void:
	if _age < RING_TIME:
		var r := radius * 1.35 / TEXEL
		var center := Vector2(0.0, -height) / TEXEL
		for y in range(floori(-r) - 1, ceili(r) + 2):
			for x in range(floori(-r) - 1, ceili(r) + 2):
				var d := Vector2(x + 0.5, y + 0.5).length()
				if absf(d - r) < 0.6:
					var cell := (center + Vector2(x, y)).floor() * TEXEL
					draw_rect(Rect2(cell, Vector2(TEXEL, TEXEL)), rim)
		return
	var t := (_age - RING_TIME) / (DURATION - RING_TIME)
	var color := rim
	color.a = 1.0 - smoothstep(0.4, 1.0, t)
	for drop in _drops:
		var size: float = drop.size * TEXEL
		var cell: Vector2 = (drop.pos / TEXEL).floor() * TEXEL
		draw_rect(Rect2(cell, Vector2(size, size)), color)
