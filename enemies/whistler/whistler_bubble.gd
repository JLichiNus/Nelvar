class_name NelvarWhistlerBubble
extends Area2D
## A soap bubble blown by the Whistler. It drifts slowly in a straight line
## and wobbles like jelly. The collider is its shadow on the ground (like the
## feet of the player and enemies), the bubble itself floats above it.
##
## - On a player who is not protected by flight it bursts and hurts.
## - A trunk or a rock bursts it; shores and bridge rails do not — it drifts
##   out over the clouds and bursts there at the end of its way.
## - The LMB shot bursts it (take_damage, like an enemy on the Enemies layer).
## - The RMB wave turns it around (deflect): the bubble takes the colours of
##   the player's wind, flies back faster, towards an enemy close to where the
##   wave was heading, and hurts enemies instead of the player.

const POP_FX := preload("res://enemies/whistler/bubble_pop_fx.gd")
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_PLAYER_ATTACKS := 4
const LAYER_ENEMIES := 8
const WOBBLE_FRAMES := 3

@export_category("Flight")
@export var speed: float = 170.0
@export var max_distance: float = 950.0
@export var damage: float = 10.0
@export var float_height: float = 19.0
@export var grow_duration: float = 0.14

@export_category("Deflected")
@export var deflected_speed_scale: float = 2.2
@export var deflected_damage: float = 30.0
@export var deflected_knockback: float = 220.0
## An enemy within this angle of the wave's direction draws the bubble to it.
@export var deflect_aim_angle: float = 28.0
@export var deflect_aim_range: float = 900.0

@export_category("Visual")
## Collider radius; the drawn bubble is a little bigger (visual_radius),
## so a graze that looks like a miss is a miss.
@export var radius: float = 9.0
@export var visual_radius: float = 12.0
@export_range(1, 8, 1) var pixel_size: int = 3
@export var wobble_rate: float = 7.0
@export var bob_height: float = 2.0
@export var bob_rate: float = 2.4
@export var enemy_outline := Color("4a2350")
@export var enemy_rim := Color("e46fa8")
@export var enemy_rim_light := Color("f7b3d2")
@export var enemy_fill := Color(0.96, 0.55, 0.78, 0.28)
@export var wind_outline := Color("2c4a6b")
@export var wind_rim := Color("9fd3ea")
@export var wind_rim_light := Color("eefaff")
@export var wind_fill := Color(0.78, 0.92, 1.0, 0.28)
@export var highlight_color := Color.WHITE
@export var shadow_color := Color(0.0, 0.0, 0.0, 0.22)

@export_category("Sound")
@export var pop_stream: AudioStream
@export var deflect_stream: AudioStream
@export var pop_volume_db: float = -4.0
## The quiet burst at the end of its way, out over the clouds.
@export var fade_pop_volume_db: float = -14.0

static var _texture_cache := {}

var direction := Vector2.RIGHT
var _deflected := false
var _popped := false
var _travelled := 0.0
var _age := 0.0
var _phase := 0.0

@onready var visual: Node2D = $Visual
@onready var sprite: Sprite2D = $Visual/Sprite
@onready var shadow_sprite: Sprite2D = $Shadow
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	_phase = randf() * TAU
	# The shape is shared by every bubble of the scene: a different radius
	# gets a copy of its own.
	var circle := collision_shape.shape as CircleShape2D
	if not is_equal_approx(circle.radius, radius):
		circle = circle.duplicate() as CircleShape2D
		circle.radius = radius
		collision_shape.shape = circle
	sprite.scale = Vector2.ONE * pixel_size
	shadow_sprite.texture = _cached_texture("shadow", 0, _paint_shadow.bind())
	shadow_sprite.scale = Vector2.ONE * pixel_size
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	_update_visual()


## `origin` is the point on the ground under the Whistler's mouth.
func launch(origin: Vector2, launch_direction: Vector2) -> void:
	global_position = origin
	if launch_direction.length_squared() > 0.0001:
		direction = launch_direction.normalized()


func is_deflected() -> bool:
	return _deflected


func _physics_process(delta: float) -> void:
	if _popped:
		return
	_age += delta
	var step := direction * speed * delta
	global_position += step
	_travelled += step.length()
	if _travelled >= max_distance:
		_pop(false)
		return
	if not _deflected:
		_check_player()
	_update_visual()


# Polled every frame, not on body_entered: a player who flies into the bubble
# and lands inside it must still be hit.
func _check_player() -> void:
	for body in get_overlapping_bodies():
		if not body.is_in_group(&"player"):
			continue
		if body.has_method("is_dead") and body.call("is_dead"):
			continue
		if body.has_method("is_flight_protected") and body.call("is_flight_protected"):
			continue
		if body.has_method("take_damage"):
			body.call("take_damage", damage, global_position)
		_pop(true)
		return


## LMB shot: the bubble bursts (a deflected one is no longer on its layer).
func take_damage(_amount: float) -> void:
	if not _deflected:
		_pop(true)


## RMB wave: turned back the way the wave goes.
func deflect(wave_direction: Vector2) -> void:
	if _popped or _deflected:
		return
	_deflected = true
	direction = _deflect_direction(wave_direction.normalized())
	speed *= deflected_speed_scale
	_travelled = 0.0
	# Called from a physics signal: layers only deferred.
	set_deferred("collision_layer", LAYER_PLAYER_ATTACKS)
	set_deferred("collision_mask", LAYER_WORLD | LAYER_ENEMIES)
	NelvarOneShotSound.play(get_parent(), deflect_stream, global_position, -3.0)
	_update_visual()


func _deflect_direction(wave_direction: Vector2) -> Vector2:
	var best := wave_direction
	var best_distance := deflect_aim_range
	var max_angle := deg_to_rad(deflect_aim_angle)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Node2D
		if enemy == null:
			continue
		var to_enemy := enemy.global_position - global_position
		var distance := to_enemy.length()
		if distance < 1.0 or distance >= best_distance:
			continue
		if absf(wave_direction.angle_to(to_enemy)) > max_angle:
			continue
		best_distance = distance
		best = to_enemy / distance
	return best


func _on_body_entered(body: Node) -> void:
	if _popped:
		return
	if body.is_in_group(&"player"):
		return  # _check_player
	var collision_object := body as CollisionObject2D
	if collision_object == null:
		return
	if collision_object.collision_layer & LAYER_ENEMIES != 0:
		if _deflected and body.has_method("take_damage"):
			body.call("take_damage", deflected_damage)
			if body.has_method("apply_knockback"):
				body.call("apply_knockback", direction * deflected_knockback)
			_pop(true)
		return
	if collision_object.collision_layer & LAYER_WORLD != 0 and _blocks(body):
		_pop(true)


func _on_area_entered(area: Area2D) -> void:
	# A deflected bubble bursts the enemy bubbles it meets, and itself.
	if _popped or not _deflected:
		return
	var other := area as NelvarWhistlerBubble
	if other != null and not other.is_deflected():
		other.take_damage(0.0)
		_pop(true)


# Trunks and rocks stop bubbles; island shores and bridge rails are low
# borders the bubble floats over.
func _blocks(body: Node) -> bool:
	return not (body.get_parent() is NelvarWorldChunk)


func _pop(loud: bool) -> void:
	if _popped:
		return
	_popped = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	var parent := get_parent()
	if parent != null:
		var fx := POP_FX.new()
		fx.radius = visual_radius
		fx.height = float_height
		fx.rim = wind_rim_light if _deflected else enemy_rim_light
		fx.droplets = 7 if loud else 4
		parent.add_child(fx)
		fx.global_position = global_position
		NelvarOneShotSound.play(parent, pop_stream, global_position,
			pop_volume_db if loud else fade_pop_volume_db)
	queue_free()


func _update_visual() -> void:
	if visual == null:
		return
	var grow := clampf(_age / maxf(grow_duration, 0.01), 0.0, 1.0)
	grow = 1.0 - (1.0 - grow) * (1.0 - grow)
	var frame := int(_age * wobble_rate + _phase) % WOBBLE_FRAMES
	var kind := "wind" if _deflected else "enemy"
	sprite.texture = _cached_texture(kind, frame, _paint_bubble.bind(_deflected, frame))
	visual.scale = Vector2.ONE * lerpf(0.25, 1.0, grow)
	# The bob snaps to whole texels: the bubble stays on the pixel grid.
	var bob := roundf(sin(_age * bob_rate * TAU / 2.0 + _phase) * bob_height / pixel_size) * pixel_size
	visual.position = Vector2(0.0, -float_height + bob)
	shadow_sprite.scale = Vector2.ONE * pixel_size * lerpf(0.4, 1.0, grow)


func _cached_texture(kind: String, frame: int, painter: Callable) -> ImageTexture:
	var key := "%s|%d|%s|%s|%d|%s" % [kind, frame, radius, visual_radius, pixel_size, [
		enemy_outline, enemy_rim, enemy_rim_light, enemy_fill,
		wind_outline, wind_rim, wind_rim_light, wind_fill, highlight_color]]
	if not _texture_cache.has(key):
		_texture_cache[key] = ImageTexture.create_from_image(painter.call())
	return _texture_cache[key]


# A ring with a dark outline (readable on pale grass), a lighter top-left arc,
# a faint tinted inside and a highlight. Frames 1 and 2 are squashed wide and
# tall: played in turn they make the bubble quiver.
func _paint_bubble(deflected: bool, frame: int) -> Image:
	var outline := wind_outline if deflected else enemy_outline
	var rim := wind_rim if deflected else enemy_rim
	var rim_light := wind_rim_light if deflected else enemy_rim_light
	var fill := wind_fill if deflected else enemy_fill
	var r := visual_radius / pixel_size
	var squash := [Vector2.ONE, Vector2(1.12, 0.9), Vector2(0.9, 1.12)][frame] as Vector2
	var radii := Vector2(r, r) * squash + Vector2(0.5, 0.5)
	var half := ceili(maxf(radii.x, radii.y)) + 1
	var size := half * 2 + 1
	var center := Vector2(half + 0.5, half + 0.5)
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := (Vector2(x + 0.5, y + 0.5) - center) / radii
			var dist := d.length()
			if dist > 1.0:
				continue
			var edge := 1.0 - 1.0 / minf(radii.x, radii.y)
			var color := fill
			if dist > edge:
				color = outline
			elif dist > edge - 1.1 / minf(radii.x, radii.y):
				color = rim_light if d.x + d.y < -0.35 else rim
			image.set_pixel(x, y, color)
	# A glint on the inner edge of the rim, upper left.
	var spot := Vector2i((center - radii * Vector2(0.5, 0.5)).floor())
	image.set_pixelv(spot, highlight_color)
	image.set_pixelv(spot + Vector2i.RIGHT, highlight_color)
	image.set_pixelv(spot + Vector2i.DOWN, highlight_color)
	return image


func _paint_shadow() -> Image:
	var radii := Vector2(radius * 0.8, radius * 0.32) / pixel_size
	var half := Vector2i(radii.ceil())
	var size := half * 2 + Vector2i.ONE
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			var d := (Vector2(x, y) - Vector2(half)) / (radii + Vector2(0.5, 0.5))
			if d.length_squared() <= 1.0:
				image.set_pixel(x, y, shadow_color)
	return image
