extends ColorRect
## A glow along the screen edges in a version's colour when a mutation takes
## hold. The same blocky vignette as the damage one, flaring up and fading.

const SHADER := preload("res://ui/damage_vignette.gdshader")
const RISE := 0.08
const FADE := 1.1

var _material := ShaderMaterial.new()
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color.WHITE
	_material.shader = SHADER
	_material.set_shader_parameter("inner", 0.5)
	material = _material
	hide()
	resized.connect(func() -> void: _material.set_shader_parameter("rect_size", size))
	_material.set_shader_parameter("rect_size", size)


## `pulses`: how many times it flares (an intercepted mutation flares twice).
func play(tint: Color, strength: float = 1.0, pulses: int = 1) -> void:
	# A deeper tone of the colour: the pale accents vanish against the sky.
	_material.set_shader_parameter("color", Color(tint.darkened(0.35), 0.65))
	show()
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	for i in pulses:
		_tween.tween_method(_set_strength, 0.0, strength, RISE)
		var fade := FADE if i == pulses - 1 else FADE * 0.3
		_tween.tween_method(_set_strength, strength, 0.0, fade) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(hide)


func _set_strength(value: float) -> void:
	_material.set_shader_parameter("strength", value)
