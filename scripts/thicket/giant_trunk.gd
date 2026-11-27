class_name NelvarGiantTrunk
extends StaticBody2D
## A giant's trunk on screen: sorted by the middle of its base (whoever stands north of the
## base is behind it), the base circle its collision (World). While the player is behind
## it, everything above its foot thins out (giant_trunk.gdshader) in FADE_IN seconds and
## comes back in FADE_OUT; NelvarThicketMain decides when. Now and then two eyes glint in
## its hollow; a few beetles crawl slowly up the bark into the dark of the crown.

const SHADER := preload("res://scripts/thicket/giant_trunk.gdshader")
const STEP := NelvarEarthData.PIXEL
const FADE_IN := 0.25
const FADE_OUT := 0.4
const EYE := Color8(250, 226, 120)
const BEETLE := Color8(28, 22, 26)
const BEETLE_SHINE := Color8(92, 110, 120)
## Beetles crawl up this fast (world units per second).
const CRAWL := 9.0

var giant: NelvarThicketData.Giant
var art: NelvarEarthArt
var show_collision := false
## 0 solid .. 1 thinned out.
var fade := 0.0

var _material: ShaderMaterial
var _behind := false
var _eye_time := 0.0
var _eyes_open := false
## Beetles on the bark: (x across the trunk −1..1, how far up 0..1, speed factor).
var _beetles: Array[Vector3] = []


## A piece of something long lying on the ground (a root, the fallen giant), sorted by its
## own lowest point. Pieces of the fallen giant share one material and thin out together.
class Piece extends Node2D:
	var art: NelvarEarthArt
	var along := 0.0

	func setup(piece: NelvarGiantPainter.Piece, shared: Material = null) -> void:
		art = piece.art
		along = piece.along
		position = piece.origin
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if shared != null:
			material = shared

	func _draw() -> void:
		if art != null and art.texture != null:
			draw_texture_rect(art.texture, art.local_rect, false)


func setup(spec: NelvarThicketData.Giant, artwork: NelvarEarthArt) -> void:
	giant = spec
	art = artwork
	name = "Giant_%d" % spec.id
	position = spec.center
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	collision_layer = NelvarProp.WORLD_LAYER
	collision_mask = 0
	var collider := CollisionShape2D.new()
	collider.name = "Collision"
	var circle := CircleShape2D.new()
	circle.radius = spec.radius
	collider.shape = circle
	add_child(collider)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material = _material
	_eye_time = randf_range(2.0, 9.0)
	set_process(art.eye.is_finite())
	var rng := RandomNumberGenerator.new()
	rng.seed = spec.appearance_seed + 3
	for i in rng.randi_range(1, 3) if not spec.ring else 0:
		_beetles.append(Vector3(rng.randf_range(-0.8, 0.8), rng.randf(), rng.randf_range(0.7, 1.3)))


## True when the point is behind the trunk on screen: north of its base and within its
## silhouette (its seen height).
func hides(point: Vector2, margin: float = 0.0) -> bool:
	var offset := point - giant.center
	if absf(offset.x) > giant.radius * 1.1 + margin:
		return false
	var base := giant.radius * sqrt(maxf(0.0, 1.0 - pow(offset.x / (giant.radius * 1.16), 2.0)))
	return offset.y < base and offset.y > -giant.height - margin


## Moves the beetles up the bark (called while the trunk is near the screen).
func crawl(delta: float) -> void:
	if _beetles.is_empty():
		return
	var before := []
	for i in _beetles.size():
		var b := _beetles[i]
		before.append(_beetle_pixel(b))
		b.y += CRAWL * b.z * delta / (giant.height * 0.6)
		if b.y > 1.0:
			b = Vector3(randf_range(-0.8, 0.8), 0.0, b.z)
		_beetles[i] = b
	for i in _beetles.size():
		if _beetle_pixel(_beetles[i]) != before[i]:
			queue_redraw()
			return


func _beetle_pixel(beetle: Vector3) -> Vector2:
	var r := giant.radius / STEP
	var base := r * sqrt(maxf(0.0, 1.0 - beetle.x * beetle.x))
	return Vector2(roundf(beetle.x * r * 0.9), roundf(base - 12.0 - beetle.y * giant.height / STEP * 0.6))


## Called every frame with whether the player is behind it.
func update_fade(behind: bool, delta: float) -> void:
	_behind = behind
	var target := 1.0 if behind else 0.0
	if is_equal_approx(fade, target):
		return
	fade = move_toward(fade, target, delta / (FADE_IN if behind else FADE_OUT))
	_material.set_shader_parameter("fade", fade)


func _process(delta: float) -> void:
	_eye_time -= delta
	if _eye_time <= 0.0:
		_eyes_open = not _eyes_open
		_eye_time = randf_range(0.6, 1.6) if _eyes_open else randf_range(5.0, 14.0)
		queue_redraw()


func _draw() -> void:
	if art == null or art.texture == null:
		return
	draw_texture_rect(art.texture, art.local_rect, false)
	var cell := Vector2.ONE * STEP
	for beetle in _beetles:
		var at := _beetle_pixel(beetle)
		draw_rect(Rect2(at * STEP, Vector2(STEP * 2.0, STEP * 3.0)), BEETLE)
		draw_rect(Rect2((at + Vector2(1.0, 0.0)) * STEP, cell), BEETLE_SHINE)
	if _eyes_open and art.eye.is_finite():
		for dx: float in [-2.0, 1.0]:
			draw_rect(Rect2((art.eye + Vector2(dx, 1.0)) * STEP, cell), EYE)
	if show_collision:
		draw_circle(Vector2.ZERO, giant.radius, NelvarEarthThing.DEBUG_COLOR, false, 3.0)
