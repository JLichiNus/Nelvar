extends CharacterBody2D


enum State { IDLE, JUMPING, DEAD }

@export_category("Health")
@export var max_health: float = 40.0
@export var contact_damage: float = 10.0
@export var hit_flash_color := Color(2.0, 2.0, 2.0)
@export var hit_flash_duration: float = 0.1
@export var death_scale: float = 1.4
@export var death_duration: float = 0.2

@export_category("Jumping")
@export var idle_time_min: float = 0.8
@export var idle_time_max: float = 1.8
@export var windup_duration: float = 0.12
@export var windup_scale := Vector2(1.2, 0.8)
@export var jump_distance_min: float = 120.0
@export var jump_distance_max: float = 200.0
@export var jump_duration: float = 0.45
@export var jump_height: float = 28.0
@export var jump_shadow_scale: float = 0.6
@export var landing_scale := Vector2(1.25, 0.75)
@export var landing_recovery: float = 0.15

@export_category("Knockback")
@export var knockback_friction: float = 1800.0

@export_category("Visual")
## Радиус тела в мировых пикселях; рисуется пиксель-артом по сетке pixel_size.
@export var body_radius: float = 22.0
@export_range(1, 8, 1) var pixel_size: int = 3
@export var outline_color := Color("4a182c")
@export var shade_color := Color("992e4a")
@export var base_color := Color("d64f5e")
@export var light_color := Color("ee8382")
@export var highlight_color := Color("ffe0d6")
@export var eye_color := Color("3a1222")
@export var shadow_color := Color(0.0, 0.0, 0.0, 0.35)

# Текстуры одинаковы у всех прыгунов с одинаковыми параметрами — печём один раз.
static var _texture_cache := {}

var health: float
var _state := State.IDLE
var _idle_time_left := 0.0
var _is_winding_up := false
var _jump_time := 0.0
var _jump_velocity := Vector2.ZERO
var _knockback_velocity := Vector2.ZERO
var _hold_time_left := 0.0
var _visual_tween: Tween
var _flash_tween: Tween

@onready var shadow: Node2D = $Shadow
@onready var shadow_sprite: Sprite2D = $Shadow/Sprite
@onready var visual: Node2D = $Visual
@onready var body: Sprite2D = $Visual/Body
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	health = max_health
	var texel_scale := Vector2.ONE * pixel_size
	body.texture = _cached_texture("body", _paint_body)
	body.scale = texel_scale
	shadow_sprite.texture = _cached_texture("shadow", _paint_shadow)
	shadow_sprite.scale = texel_scale
	_enter_idle()


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return

	if _hold_time_left > 0.0:
		_update_hold(delta)
	else:
		match _state:
			State.IDLE:
				_update_idle(delta)
			State.JUMPING:
				_update_jump(delta)

	velocity = _jump_velocity + _knockback_velocity
	move_and_slide()
	_bounce_off_walls()
	_knockback_velocity = _knockback_velocity.move_toward(
		Vector2.ZERO,
		knockback_friction * delta
	)


func take_damage(amount: float) -> void:
	if _state == State.DEAD:
		return
	health -= amount
	_flash()
	if health <= 0.0:
		_die()


func apply_knockback(force: Vector2) -> void:
	if _state == State.DEAD or _hold_time_left > 0.0:
		return
	_knockback_velocity += force


# Удержание (R-сжатие): враг замирает сплющенным, не прыгает и не отлетает.
func apply_hold(duration: float) -> void:
	if _state == State.DEAD or duration <= 0.0:
		return
	if _state == State.JUMPING:
		_land()
	# Замах прерывается: после удержания он проиграется заново.
	_is_winding_up = false
	_jump_velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	_hold_time_left = maxf(_hold_time_left, duration)
	_restart_visual_tween().tween_property(
		visual,
		"scale",
		windup_scale,
		0.08
	)


func play_spawn_animation(duration: float) -> void:
	if _state == State.DEAD or duration <= 0.0:
		return
	visual.scale = Vector2.ZERO
	shadow.scale = Vector2.ZERO
	var tween := _restart_visual_tween().set_parallel(true)
	tween.tween_property(visual, "scale", Vector2.ONE, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(shadow, "scale", Vector2.ONE, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _update_hold(delta: float) -> void:
	_jump_velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	_hold_time_left -= delta
	if _hold_time_left <= 0.0:
		_hold_time_left = 0.0
		_restart_visual_tween().tween_property(
			visual,
			"scale",
			Vector2.ONE,
			landing_recovery
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _enter_idle() -> void:
	_state = State.IDLE
	_is_winding_up = false
	_idle_time_left = randf_range(idle_time_min, idle_time_max)


func _update_idle(delta: float) -> void:
	_idle_time_left -= delta
	if not _is_winding_up and _idle_time_left <= windup_duration:
		_is_winding_up = true
		_restart_visual_tween().tween_property(
			visual,
			"scale",
			windup_scale,
			maxf(_idle_time_left, 0.01)
		)
	if _idle_time_left <= 0.0:
		_start_jump()


func _start_jump() -> void:
	_state = State.JUMPING
	_is_winding_up = false
	_jump_time = 0.0
	var direction := Vector2.from_angle(randf() * TAU)
	var distance := randf_range(jump_distance_min, jump_distance_max)
	_jump_velocity = direction * distance / maxf(jump_duration, 0.01)

	var tween := _restart_visual_tween()
	tween.tween_property(visual, "scale", Vector2(0.85, 1.15), 0.08)
	tween.tween_property(visual, "scale", Vector2.ONE, 0.15)


func _update_jump(delta: float) -> void:
	_jump_time += delta
	var progress := clampf(_jump_time / maxf(jump_duration, 0.01), 0.0, 1.0)
	var arc := sin(PI * progress)
	visual.position.y = -arc * jump_height
	shadow.scale = Vector2.ONE * lerpf(1.0, jump_shadow_scale, arc)
	if progress >= 1.0:
		_land()


func _land() -> void:
	_jump_velocity = Vector2.ZERO
	visual.position = Vector2.ZERO
	shadow.scale = Vector2.ONE
	visual.scale = landing_scale
	_restart_visual_tween().tween_property(
		visual,
		"scale",
		Vector2.ONE,
		landing_recovery
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_enter_idle()


func _bounce_off_walls() -> void:
	for i in get_slide_collision_count():
		var normal := get_slide_collision(i).get_normal()
		if _jump_velocity.dot(normal) < 0.0:
			_jump_velocity = _jump_velocity.bounce(normal)
		if _knockback_velocity.dot(normal) < 0.0:
			_knockback_velocity = _knockback_velocity.bounce(normal)


func _flash() -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	visual.modulate = hit_flash_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(
		visual,
		"modulate",
		Color.WHITE,
		hit_flash_duration
	)


func _die() -> void:
	_state = State.DEAD
	remove_from_group("enemies")
	get_tree().call_group(&"player", &"register_kill")
	# take_damage приходит из физического сигнала, поэтому только отложенно.
	collision_shape.set_deferred("disabled", true)
	_jump_velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	velocity = Vector2.ZERO

	var tween := _restart_visual_tween().set_parallel(true)
	tween.tween_property(
		visual,
		"scale",
		Vector2.ONE * death_scale,
		death_duration
	)
	tween.tween_property(self, "modulate:a", 0.0, death_duration)
	tween.chain().tween_callback(queue_free)


func _restart_visual_tween() -> Tween:
	if _visual_tween != null:
		_visual_tween.kill()
	_visual_tween = create_tween()
	return _visual_tween


func _cached_texture(kind: String, painter: Callable) -> ImageTexture:
	var key := "%s|%s|%d|%s" % [
		kind,
		body_radius,
		pixel_size,
		[outline_color, shade_color, base_color, light_color,
			highlight_color, eye_color, shadow_color],
	]
	if not _texture_cache.has(key):
		_texture_cache[key] = ImageTexture.create_from_image(painter.call())
	return _texture_cache[key]


# Шар чуть шире, чем выше: контур, три тона по свету сверху-слева, блик и глаза.
func _paint_body() -> Image:
	var r := maxi(3, roundi(body_radius / pixel_size))
	var size := 2 * r + 1
	var radii := Vector2(r + 0.5, r * 0.86 + 0.5)
	# Низ эллипса прижат к нижнему краю текстуры.
	var center := Vector2(r, r + (r - radii.y + 0.5))
	var light := Vector3(-0.45, -0.65, 0.61).normalized()
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			if not _in_ellipse(x, y, center, radii):
				continue
			var color := outline_color
			if _in_ellipse(x + 1, y, center, radii) \
					and _in_ellipse(x - 1, y, center, radii) \
					and _in_ellipse(x, y + 1, center, radii) \
					and _in_ellipse(x, y - 1, center, radii):
				var d := (Vector2(x, y) - center) / radii
				var normal := Vector3(d.x, d.y, sqrt(maxf(0.0, 1.0 - d.length_squared())))
				var brightness := normal.dot(light)
				if brightness < 0.3:
					color = shade_color
				elif brightness < 0.82:
					color = base_color
				else:
					color = light_color
			image.set_pixel(x, y, color)

	var spot := Vector2i(
		roundi(center.x - radii.x * 0.42),
		roundi(center.y - radii.y * 0.5)
	)
	for offset in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN]:
		image.set_pixelv(spot + offset, highlight_color)

	var eye_gap := maxi(1, floori(r / 3.0))
	var eye_y := roundi(center.y)
	for eye_x in [r - eye_gap, r + eye_gap]:
		image.set_pixel(eye_x, eye_y - 1, eye_color)
		image.set_pixel(eye_x, eye_y, eye_color)
	return image


func _paint_shadow() -> Image:
	var radii := Vector2(body_radius * 0.9, body_radius * 0.35) / pixel_size
	var half := Vector2i(radii.ceil())
	var size := half * 2 + Vector2i.ONE
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			if _in_ellipse(x, y, Vector2(half), radii + Vector2(0.5, 0.5)):
				image.set_pixel(x, y, shadow_color)
	return image


func _in_ellipse(x: int, y: int, center: Vector2, radii: Vector2) -> bool:
	var d := (Vector2(x, y) - center) / radii
	return d.length_squared() <= 1.0
