class_name NelvarDamageVignette
extends ColorRect
## Red vignette over the screen when the player is hurt; fades out on its own.
## Strength and "only the side facing the hit" come from GameSettings.

const SHADER := preload("res://ui/damage_vignette.gdshader")

@export var player: NelvarPlayer
@export var fade_time: float = 0.7

var _material := ShaderMaterial.new()
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color.WHITE
	_material.shader = SHADER
	material = _material
	hide()
	resized.connect(_on_resized)
	_on_resized()
	if player == null:
		push_warning("Виньетке урона не назначен игрок.")
		return
	player.damaged.connect(_on_damaged)


func _on_damaged(_amount: float, from: Vector2) -> void:
	var strength := GameSettings.damage_vignette_strength()
	if strength <= 0.0:
		return
	var direction := Vector2.ZERO
	if GameSettings.damage_vignette_directional and from.is_finite():
		var offset := from - player.global_position
		# Too close to tell a side (a blast right under the player): whole edge.
		if offset.length() > 4.0:
			direction = offset.normalized()
	# The camera does not rotate: a world direction is the same on screen.
	_material.set_shader_parameter("direction", direction)
	_material.set_shader_parameter("strength", strength)
	show()
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_strength, strength, 0.0, fade_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(hide)


func _on_resized() -> void:
	_material.set_shader_parameter("rect_size", size)


func _set_strength(value: float) -> void:
	_material.set_shader_parameter("strength", value)
