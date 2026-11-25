class_name NelvarMutationBurst
extends Node2D
## A mutation taking hold, in the world around the player: the body flares in
## the colour of the version that picked it, a pillar of light and two pixel
## rings spread from it, and sparks fly out and drift upward. Follows the
## player as its child and frees itself when done.

const ART_PIXEL := 3.0
const LIFETIME := 1.1
const RING_TIME := 0.6
const RING_DELAY := 0.14
const PILLAR_TIME := 0.5
const SPARK_COUNT := 22
const FLASH_TIME := 0.55
## How far the body brightens at the flash's peak (modulate goes above 1).
const FLASH_BOOST := 2.4
const EDGE := Color(0.05, 0.06, 0.08, 0.75)

var _color := Color.WHITE
var _radius := 120.0
var _time := 0.0
## [angle, speed, size, delay].
var _sparks: Array[PackedFloat32Array] = []


## `strong`: a mutation that took effect; otherwise a softer burst (one only
## ripened and waits for the choice).
static func spawn(player: NelvarPlayer, color: Color, strong: bool = true) -> NelvarMutationBurst:
	var burst := NelvarMutationBurst.new()
	burst._color = color
	burst._radius = 150.0 if strong else 100.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in (SPARK_COUNT if strong else SPARK_COUNT / 2):
		burst._sparks.append(PackedFloat32Array([
			rng.randf() * TAU,
			rng.randf_range(90.0, 230.0) * (1.0 if strong else 0.7),
			ART_PIXEL * (3.0 if rng.randf() < 0.3 else 2.0),
			rng.randf() * 0.12,
		]))
	player.add_child(burst)
	burst._flash_body(player, strong)
	return burst


func _ready() -> void:
	z_index = 30
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	_time += delta
	if _time >= LIFETIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	_draw_pillar()
	_draw_ring(_time / RING_TIME, 3)
	_draw_ring((_time - RING_DELAY) / RING_TIME, 2)
	_draw_sparks()


func _draw_pillar() -> void:
	var t := _time / PILLAR_TIME
	if t >= 1.0:
		return
	var fade := 1.0 - t
	var half_width := snappedf(lerpf(8.0, 1.0, t) * ART_PIXEL, ART_PIXEL)
	var height := snappedf(_radius * 2.4 * (0.4 + 0.6 * ease(t, 0.3)), ART_PIXEL)
	var beam := Rect2(-half_width, -height, half_width * 2.0, height + ART_PIXEL * 4.0)
	draw_rect(beam.grow(ART_PIXEL), Color(EDGE, EDGE.a * fade))
	draw_rect(beam, Color(_color, 0.85 * fade))
	var core := maxf(snappedf(half_width * 0.4, ART_PIXEL), ART_PIXEL)
	draw_rect(Rect2(-core, beam.position.y, core * 2.0, beam.size.y), Color(Color.WHITE, fade))


# A circle of art pixels at `progress` (0..1) of its growth, `thickness` pixels wide.
func _draw_ring(progress: float, thickness: int) -> void:
	if progress <= 0.0 or progress >= 1.0:
		return
	var radius := _radius * ease(progress, 0.35)
	var color := Color.WHITE.lerp(_color, minf(progress * 2.5, 1.0))
	var alpha := 1.0 - progress * progress
	color.a = alpha
	var cells := {}
	var count := maxi(int(TAU * radius / ART_PIXEL), 8)
	for layer in thickness:
		var r := radius - layer * ART_PIXEL
		if r <= 0.0:
			continue
		for i in count:
			var angle := TAU * i / count
			# Flattened: the world is seen from above at an angle.
			var cell := (Vector2(cos(angle) * r, sin(angle) * r * 0.6) / ART_PIXEL).floor()
			cells[cell] = true
	_draw_cells(cells.keys(), Vector2.ONE * ART_PIXEL, color, alpha)


func _draw_sparks() -> void:
	for spark in _sparks:
		var t := (_time - spark[3]) / (LIFETIME - spark[3])
		if t <= 0.0 or t >= 1.0:
			continue
		var direction := Vector2(cos(spark[0]), sin(spark[0]) * 0.6)
		# Thrown out, slowing, then drifting upward.
		var travel := spark[1] * (1.0 - pow(1.0 - t, 3.0)) * 0.7
		var pos := direction * travel + Vector2.UP * (70.0 * t * t)
		var color := Color.WHITE.lerp(_color, minf(t * 3.0, 1.0))
		color.a = 1.0 - t
		_draw_cells([(pos / ART_PIXEL).floor()], Vector2.ONE * spark[2], color, color.a)


# Art-pixel cells with a dark outline, so the light colours still read on the
# pale sky and clouds. The outlines go first so they never cover a neighbour.
func _draw_cells(cells: Array, cell_size: Vector2, color: Color, alpha: float) -> void:
	var edge := Color(EDGE, EDGE.a * alpha)
	for cell: Vector2 in cells:
		draw_rect(Rect2(cell * ART_PIXEL, cell_size).grow(ART_PIXEL), edge)
	for cell: Vector2 in cells:
		draw_rect(Rect2(cell * ART_PIXEL, cell_size), color)


func _flash_body(player: NelvarPlayer, strong: bool) -> void:
	if player.is_dead():
		return
	var peak := Color.WHITE.lerp(_color, 0.5) * (FLASH_BOOST if strong else FLASH_BOOST * 0.7)
	peak.a = 1.0
	for sprite: CanvasItem in [player.vortex_sprite, player.torso_sprite]:
		if sprite.has_meta(&"mutation_flash"):
			var previous: Tween = sprite.get_meta(&"mutation_flash")
			if previous != null and previous.is_valid():
				previous.kill()
		sprite.modulate = peak
		var tween := sprite.create_tween()
		tween.tween_property(sprite, "modulate", Color.WHITE, FLASH_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		sprite.set_meta(&"mutation_flash", tween)
