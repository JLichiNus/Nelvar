class_name NelvarVoidScreen
extends CanvasLayer
## Screen effects of the Void fight: shockwaves from a point in the world, the
## picture tearing (glitch), a flash, and slow motion. The full-screen pass is only
## drawn while one of them runs. Found by others through the group "void_screen"
## (see NelvarVoidFx).

const SHADER := preload("res://scripts/void/void_screen.gdshader")
const SHOCK_TIME := 0.75

var _rect: ColorRect
var _material: ShaderMaterial
var _time := 0.0
var _shock_at := Vector2.ZERO
var _shock_age := 99.0
var _shock_power := 0.0
var _glitch_left := 0.0
var _glitch_power := 0.0
var _flash_tween: Tween
var _flash := 0.0
var _slow_until := 0.0
var _base_time_scale := 1.0


func _ready() -> void:
	add_to_group("void_screen")
	layer = 1
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect.material = _material
	_rect.visible = false
	add_child(_rect)


func shock(at: Vector2, strength: float) -> void:
	# A stronger or newer wave replaces a fading one.
	if _shock_age < SHOCK_TIME * 0.5 and strength < _shock_power:
		return
	_shock_at = at
	_shock_age = 0.0
	_shock_power = clampf(strength, 0.0, 1.5)
	if strength > 0.7:
		glitch(0.18, strength * 0.4)


func glitch(duration: float, strength: float) -> void:
	_glitch_left = maxf(_glitch_left, duration)
	_glitch_power = maxf(_glitch_power if _glitch_left > 0.0 else 0.0, strength)


func flash(color: Color, amount: float, duration: float) -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	_material.set_shader_parameter("flash_color", color)
	_flash = amount
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "_flash", 0.0, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


## Slows the game to `scale` for `duration` real seconds.
func slow_motion(scale: float, duration: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _slow_until:
		_base_time_scale = Engine.time_scale
	_slow_until = maxf(_slow_until, now + duration)
	Engine.time_scale = _base_time_scale * scale


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.001)
	_time += real
	if _slow_until > 0.0 and Time.get_ticks_msec() / 1000.0 >= _slow_until:
		_slow_until = 0.0
		Engine.time_scale = _base_time_scale
	_shock_age += real
	_glitch_left = maxf(0.0, _glitch_left - real)
	var shock_on := _shock_age < SHOCK_TIME
	var active := shock_on or _glitch_left > 0.0 or _flash > 0.005
	_rect.visible = active
	if not active:
		return
	var viewport := get_viewport()
	var size := viewport.get_visible_rect().size
	var on_screen := viewport.get_canvas_transform() * _shock_at
	var k := clampf(_shock_age / SHOCK_TIME, 0.0, 1.0)
	_material.set_shader_parameter("shock_center", on_screen / size)
	_material.set_shader_parameter("shock_radius", 0.08 + k * 0.7)
	_material.set_shader_parameter("shock_strength", _shock_power * (1.0 - k) if shock_on else 0.0)
	_material.set_shader_parameter("glitch", _glitch_power * clampf(_glitch_left * 4.0, 0.0, 1.0))
	_material.set_shader_parameter("time", _time)
	_material.set_shader_parameter("flash_amount", _flash)


func _exit_tree() -> void:
	# Never leave the game slowed down.
	if _slow_until > 0.0:
		Engine.time_scale = _base_time_scale
		_slow_until = 0.0
