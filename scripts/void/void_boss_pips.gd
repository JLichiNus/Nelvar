class_name NelvarVoidBossPips
extends Control
## The Only One's phases under its bar: one diamond per phase. Broken phases are
## dark hollow outlines, the current one burns and pulses, those to come wait dim.
## When a phase breaks its diamond shatters into pixels. Whole art pixels (3x UI).

const ART_PIXEL := 3.0
const SPACING := 11.0
const DIM := Color(0.36, 0.28, 0.5, 0.9)
const LIT := Color(0.9, 0.84, 1.0)
const BURN := Color(0.62, 0.4, 1.0)
const DARK := Color(0.12, 0.08, 0.2, 0.9)

var count := 4
var current := 0
var _age := 0.0
## Seconds since the last phase broke (shatter and the new one lighting up).
var _broke := 99.0
var _shards: Array[Vector4] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(0.0, 7.0 * ART_PIXEL)


func set_phase(phase: int) -> void:
	if phase > current:
		_broke = 0.0
		var rng := RandomNumberGenerator.new()
		rng.seed = phase * 7919
		_shards.clear()
		for i in 10:
			var angle := rng.randf() * TAU
			_shards.append(Vector4(0.0, 0.0, cos(angle) * rng.randf_range(20.0, 60.0),
				sin(angle) * rng.randf_range(20.0, 60.0)))
	current = phase
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_age += delta
	_broke += delta
	queue_redraw()


func _center(index: int) -> Vector2:
	var width := (count - 1) * SPACING * ART_PIXEL
	return Vector2(roundf((size.x - width) * 0.5 / ART_PIXEL) * ART_PIXEL + index * SPACING * ART_PIXEL,
		roundf(size.y * 0.5 / ART_PIXEL) * ART_PIXEL)


func _pixel(at: Vector2, color: Color) -> void:
	draw_rect(Rect2((at / ART_PIXEL).floor() * ART_PIXEL, Vector2.ONE * ART_PIXEL), color)


## A diamond of `radius` art pixels; filled or just the outline.
func _diamond(center: Vector2, radius: int, color: Color, filled: bool) -> void:
	for y in range(-radius, radius + 1):
		var span := radius - absi(y)
		for x in range(-span, span + 1):
			if filled or absi(x) == span:
				_pixel(center + Vector2(x, y) * ART_PIXEL, color)


func _draw() -> void:
	# A thin thread joining the diamonds.
	var thread := DARK
	var a := _center(0)
	var b := _center(count - 1)
	draw_rect(Rect2(a.x, a.y, b.x - a.x, ART_PIXEL), thread)
	for i in count:
		var center := _center(i)
		if i < current:
			_diamond(center, 2, DARK, true)
			_diamond(center, 2, DIM.darkened(0.3), false)
		elif i == current:
			var pulse := 0.5 + 0.5 * sin(_age * 4.0)
			var light := minf(_broke / 0.6, 1.0)
			var halo := BURN
			halo.a = (0.25 + 0.25 * pulse) * light
			_diamond(center, 3, halo, false)
			_diamond(center, 2, BURN.lerp(LIT, 0.3 + 0.4 * pulse) if light >= 1.0 else LIT, true)
			_diamond(center, 0, LIT, true)
		else:
			_diamond(center, 2, DARK, true)
			_diamond(center, 2, DIM, false)
	# The phase that just broke, flying apart.
	if _broke < 0.8 and current > 0:
		var origin := _center(current - 1)
		var fade := 1.0 - _broke / 0.8
		for shard in _shards:
			var color := LIT.lerp(BURN, 1.0 - fade)
			color.a = fade
			_pixel(origin + Vector2(shard.z, shard.w) * _broke * 1.6, color)
		var flash := LIT
		flash.a = fade
		_diamond(origin, int(2 + _broke * 6.0), flash, false)
