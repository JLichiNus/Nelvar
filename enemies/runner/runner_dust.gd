class_name NelvarRunnerDust
extends Node2D
## Little pixel puffs a Runner kicks up: dust from its feet, earth scratched up
## before a dash, a spray on a skid and the feathers it leaves when it dies.
## Positions are world ones (top_level), so the puffs stay where they were
## kicked up and are not flipped with the Runner. After release() the node
## frees itself once the last puff is gone.

const TEXEL := 3.0

var _puffs: Array[Dictionary] = []
var _released := false


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## `size` in texels; `rise` pulls it up (dust) or, negative, lets it fall;
## `sway` > 0 makes it rock from side to side as it falls (a feather).
func emit(at: Vector2, velocity: Vector2, color: Color, life: float,
		size: int = 1, rise: float = 18.0, sway: float = 0.0) -> void:
	_puffs.append({
		"pos": at, "vel": velocity, "color": color, "age": 0.0, "life": life,
		"size": size, "rise": rise, "sway": sway, "phase": randf() * TAU,
	})


func release() -> void:
	_released = true
	if _puffs.is_empty():
		queue_free()


func _process(delta: float) -> void:
	var alive: Array[Dictionary] = []
	for puff in _puffs:
		puff.age += delta
		if puff.age >= puff.life:
			continue
		puff.vel *= exp(-delta * 6.0)
		puff.vel.y -= puff.rise * delta
		var drift := Vector2.ZERO
		if puff.sway > 0.0:
			drift.x = sin(puff.age * 5.0 + puff.phase) * puff.sway
		puff.pos += (puff.vel + drift) * delta
		alive.append(puff)
	_puffs = alive
	if _puffs.is_empty() and _released:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	for puff in _puffs:
		var t: float = puff.age / puff.life
		var color: Color = puff.color
		color.a *= 1.0 - smoothstep(0.5, 1.0, t)
		# Dust shrinks as it thins out; feathers keep their size.
		var size: int = puff.size
		if puff.sway <= 0.0 and t > 0.6:
			size = maxi(size - 1, 1)
		var cell: Vector2 = (puff.pos / TEXEL).floor() * TEXEL
		draw_rect(Rect2(cell, Vector2(size, size) * TEXEL), color)
