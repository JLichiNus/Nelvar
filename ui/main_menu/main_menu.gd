extends Control
## Main menu: four buttons, four realities. Hovering or focusing a button sends a
## wave from that button across the landscape, turning it into the same place in
## that button's reality.

const GAME_SCENE := "res://scenes/main.tscn"
const TRANSITION_TIME := 0.8
## Speed-up for a wave that is interrupted by another hover.
const HURRY_SPEED := 2.5
const PARTICLE_FADE := 0.6
const PARTICLE_AMOUNT := 90
const IDLE_BUTTON_BG := Color(0.05, 0.08, 0.1, 0.72)
const IDLE_FONT := Color(0.93, 0.9, 0.8)
const PANEL_BG := Color(0.06, 0.09, 0.12, 0.92)

@export var play_element: NelvarMenuElement
@export var settings_element: NelvarMenuElement
@export var about_element: NelvarMenuElement
@export var quit_element: NelvarMenuElement

var _material: ShaderMaterial
## Reality fully on screen.
var _shown: NelvarMenuElement
## Reality the running wave is revealing; null when no wave is running.
var _incoming: NelvarMenuElement
## Reality requested while a wave was running; starts right after it.
var _pending: NelvarMenuElement
var _pending_origin := Vector2.ZERO
var _transition: Tween
var _accent_tween: Tween
var _particle_tween: Tween
var _button_elements: Dictionary = {}
var _button_tweens: Dictionary = {}
var _particles: Dictionary = {}
var _particle_textures: Dictionary = {}
var _texel := 1.0
var _wind := 0.0
var _open_panel: Control
var _panel_owner: Button

@onready var background: TextureRect = $Background
@onready var particle_root: Node2D = $Particles
@onready var title_label: Label = %Title
@onready var reality_label: Label = %Reality
@onready var play_button: Button = %Play
@onready var settings_button: Button = %Settings
@onready var about_button: Button = %About
@onready var quit_button: Button = %Quit
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var about_panel: PanelContainer = %AboutPanel
@onready var fullscreen_check: CheckButton = %Fullscreen
@onready var settings_back: Button = %SettingsBack
@onready var about_back: Button = %AboutBack


func _ready() -> void:
	_material = background.material as ShaderMaterial
	_button_elements = {
		play_button: play_element,
		settings_button: settings_element,
		about_button: about_element,
		quit_button: quit_element,
	}
	_mutate_launch()
	for element: NelvarMenuElement in _button_elements.values():
		_particles[element] = _create_particles()
	for button: Button in _button_elements:
		_set_button_highlight(button, false)
		button.mouse_entered.connect(button.grab_focus)
		button.focus_entered.connect(_on_button_focus_entered.bind(button))
		button.focus_exited.connect(_on_button_focus_exited.bind(button))
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_open.bind(settings_panel, settings_button, fullscreen_check))
	about_button.pressed.connect(_open.bind(about_panel, about_button, about_back))
	quit_button.pressed.connect(get_tree().quit)
	settings_back.pressed.connect(_close_panel)
	about_back.pressed.connect(_close_panel)

	fullscreen_check.set_pressed_no_signal(FullscreenToggle.is_fullscreen())
	fullscreen_check.toggled.connect(FullscreenToggle.set_fullscreen)
	FullscreenToggle.fullscreen_changed.connect(fullscreen_check.set_pressed_no_signal)

	_style_panel(settings_panel, settings_element)
	_style_panel(about_panel, about_element)
	settings_panel.hide()
	about_panel.hide()

	resized.connect(_layout_particles)
	_layout_particles()
	# Every launch opens in a random reality until the player points at something.
	_show_instant(_button_elements.values().pick_random())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _open_panel != null:
		_close_panel()
		get_viewport().set_input_as_handled()
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	for action in ["ui_down", "ui_up", "ui_focus_next", "ui_focus_prev", "ui_accept"]:
		if event.is_action_pressed(action):
			play_button.grab_focus()
			get_viewport().set_input_as_handled()
			return


## Small per-launch differences: the menu mutates too.
func _mutate_launch() -> void:
	_material.set_shader_parameter("hue_shift", randf_range(-0.025, 0.025))
	_material.set_shader_parameter("tint", Color.WHITE.lerp(Color.from_hsv(randf(), 0.3, 1.0), 0.1))
	_material.set_shader_parameter("breath_phase",
		Vector4(randf() * TAU, randf() * TAU, randf() * TAU, randf() * TAU))
	_material.set_shader_parameter("breath_speed",
		Vector4(randf_range(0.5, 1.0), randf_range(0.5, 1.0), randf_range(0.5, 1.0), randf_range(0.5, 1.0)))
	_wind = randf_range(-8.0, 8.0)


# --- Reality transitions -----------------------------------------------------

func _show_instant(element: NelvarMenuElement) -> void:
	_shown = element
	_set_from(element)
	_set_to(element)
	_material.set_shader_parameter("progress", 0.0)
	reality_label.text = element.title
	title_label.modulate = element.accent
	reality_label.modulate = element.accent
	for other: NelvarMenuElement in _particles:
		_particles[other].modulate.a = 1.0 if other == element else 0.0


func _request_element(element: NelvarMenuElement, origin: Vector2) -> void:
	_show_labels_and_particles(element)
	if _incoming != null:
		if element == _incoming:
			_pending = null
			return
		# Let the running wave finish quickly, then send the next one.
		_pending = element
		_pending_origin = origin
		_transition.set_speed_scale(HURRY_SPEED)
		return
	if element != _shown:
		_start_wave(element, origin)


func _start_wave(element: NelvarMenuElement, origin: Vector2) -> void:
	_incoming = element
	_set_to(element)
	_material.set_shader_parameter("origin", origin)
	_material.set_shader_parameter("progress", 0.0)
	_transition = create_tween()
	_transition.tween_method(_set_progress, 0.0, 1.0, TRANSITION_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_transition.tween_callback(_finish_wave)


func _finish_wave() -> void:
	_shown = _incoming
	_incoming = null
	_set_from(_shown)
	_material.set_shader_parameter("progress", 0.0)
	var next := _pending
	_pending = null
	if next != null and next != _shown:
		_start_wave(next, _pending_origin)


func _set_progress(value: float) -> void:
	_material.set_shader_parameter("progress", value)


func _set_from(element: NelvarMenuElement) -> void:
	background.texture = element.background
	_material.set_shader_parameter("from_tex", element.background)
	_material.set_shader_parameter("from_fx", element.fx_mask)
	_material.set_shader_parameter("from_glow", element.glow_color)


func _set_to(element: NelvarMenuElement) -> void:
	_material.set_shader_parameter("to_tex", element.background)
	_material.set_shader_parameter("to_fx", element.fx_mask)
	_material.set_shader_parameter("to_glow", element.glow_color)
	_material.set_shader_parameter("edge_color", element.accent)
	_material.set_shader_parameter("breath_points", element.breath_points)


func _show_labels_and_particles(element: NelvarMenuElement) -> void:
	reality_label.text = element.title
	if _accent_tween != null:
		_accent_tween.kill()
	_accent_tween = create_tween().set_parallel()
	_accent_tween.tween_property(title_label, "modulate", element.accent, TRANSITION_TIME * 0.6)
	_accent_tween.tween_property(reality_label, "modulate", element.accent, TRANSITION_TIME * 0.6)
	if _particle_tween != null:
		_particle_tween.kill()
	_particle_tween = create_tween().set_parallel()
	for other: NelvarMenuElement in _particles:
		var target := 1.0 if other == element else 0.0
		_particle_tween.tween_property(_particles[other], "modulate:a", target, PARTICLE_FADE)


## Converts a point on screen to background texture UV (the background is drawn "cover").
func _screen_to_uv(point: Vector2) -> Vector2:
	var texture_size := background.texture.get_size()
	var scale_factor := maxf(background.size.x / texture_size.x, background.size.y / texture_size.y)
	var drawn := texture_size * scale_factor
	var offset := (drawn - background.size) / 2.0
	return (point - background.global_position + offset) / drawn


# --- Buttons -----------------------------------------------------------------

func _on_button_focus_entered(button: Button) -> void:
	var element: NelvarMenuElement = _button_elements[button]
	_request_element(element, _screen_to_uv(button.get_global_rect().get_center()))
	_set_button_highlight(button, true)
	_animate_button(button, element.id)


func _on_button_focus_exited(button: Button) -> void:
	_kill_button_tween(button)
	_set_button_highlight(button, false)
	var tween := create_tween().set_parallel()
	tween.tween_property(button, "scale", Vector2.ONE, 0.15)
	tween.tween_property(button, "rotation_degrees", 0.0, 0.15)
	tween.tween_property(button, "modulate", Color.WHITE, 0.15)
	_button_tweens[button] = tween


func _set_button_highlight(button: Button, highlighted: bool) -> void:
	var element: NelvarMenuElement = _button_elements[button]
	var style := StyleBoxFlat.new()
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.border_width_left = 6 if highlighted else 3
	style.bg_color = element.button_color if highlighted else IDLE_BUTTON_BG
	style.border_color = element.accent if highlighted else element.accent.darkened(0.35)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, style)
	# Highlight is drawn by the styles above for mouse and keyboard alike.
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var font := Color.WHITE if highlighted else IDLE_FONT
	for state in ["font_color", "font_hover_color", "font_focus_color",
			"font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, font)


## Each reality moves its button in its own way.
func _animate_button(button: Button, id: StringName) -> void:
	_kill_button_tween(button)
	button.pivot_offset = button.size / 2.0
	var tween := create_tween()
	_button_tweens[button] = tween
	var raised := Vector2(1.04, 1.04)
	match id:
		&"air":
			tween.set_trans(Tween.TRANS_SINE)
			tween.tween_property(button, "scale", raised, 0.1)
			tween.tween_property(button, "rotation_degrees", -2.0, 0.12)
			tween.tween_property(button, "rotation_degrees", 1.5, 0.2)
			tween.tween_property(button, "rotation_degrees", 0.0, 0.18)
		&"ice":
			tween.tween_property(button, "scale", Vector2(1.09, 1.09), 0.06)
			tween.parallel().tween_property(button, "modulate", Color(1.5, 1.55, 1.6), 0.06)
			tween.tween_property(button, "scale", raised, 0.25) \
				.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			tween.parallel().tween_property(button, "modulate", Color.WHITE, 0.35)
		&"earth":
			tween.tween_property(button, "scale", Vector2(1.08, 0.88), 0.07)
			tween.tween_property(button, "scale", raised, 0.35) \
				.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		&"fire":
			tween.set_loops()
			tween.tween_property(button, "scale", raised, 0.08)
			tween.tween_property(button, "modulate", Color(1.3, 1.1, 0.92), 0.09)
			tween.tween_property(button, "modulate", Color(1.05, 0.98, 0.95), 0.13)
			tween.tween_property(button, "modulate", Color(1.35, 1.12, 0.95), 0.07)
			tween.tween_property(button, "modulate", Color.WHITE, 0.16)
		_:
			tween.tween_property(button, "scale", raised, 0.1)


func _kill_button_tween(button: Button) -> void:
	var tween: Tween = _button_tweens.get(button)
	if tween != null:
		tween.kill()
	_button_tweens.erase(button)


# --- Particles ---------------------------------------------------------------
# One always-running system per reality; switching realities cross-fades them.

func _create_particles() -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.amount = PARTICLE_AMOUNT
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.particle_flag_align_y = true
	particles.lifetime = 7.0
	particles.preprocess = 7.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.8, 1.0])
	ramp.colors = PackedColorArray([
		Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	particles.color_ramp = ramp
	particles.modulate.a = 0.0
	particle_root.add_child(particles)
	return particles


func _layout_particles() -> void:
	var texture_size := play_element.background.get_size()
	# Background is drawn "cover": one background texel is this many UI units.
	_texel = maxf(size.x / texture_size.x, size.y / texture_size.y)
	for element: NelvarMenuElement in _particles:
		_configure_particles(_particles[element], element)


## Particle settings are in background texels so they match the art's pixel grid.
func _configure_particles(particles: CPUParticles2D, element: NelvarMenuElement) -> void:
	particles.position = size / 2.0
	particles.emission_rect_extents = size / 2.0 + Vector2(40.0, 40.0)
	particles.scale_amount_min = _texel
	particles.scale_amount_max = _texel
	particles.texture = _particle_texture(element.particle_size)
	particles.color = element.particle_color
	particles.direction = element.particle_direction
	particles.spread = element.particle_spread
	particles.initial_velocity_min = element.particle_velocity.x * _texel
	particles.initial_velocity_max = element.particle_velocity.y * _texel
	particles.gravity = (element.particle_gravity + Vector2(_wind, 0.0)) * _texel


func _particle_texture(texture_size: Vector2i) -> Texture2D:
	if not _particle_textures.has(texture_size):
		var image := Image.create(maxi(1, texture_size.x), maxi(1, texture_size.y), false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_particle_textures[texture_size] = ImageTexture.create_from_image(image)
	return _particle_textures[texture_size]


# --- Panels ------------------------------------------------------------------

func _style_panel(panel: PanelContainer, element: NelvarMenuElement) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_width_left = 3
	style.border_color = element.accent
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)


func _open(panel: Control, owner_button: Button, first_focus: Control) -> void:
	if _open_panel != null and _open_panel != panel:
		_open_panel.hide()
	_open_panel = panel
	_panel_owner = owner_button
	panel.show()
	first_focus.grab_focus.call_deferred()


func _close_panel() -> void:
	if _open_panel == null:
		return
	_open_panel.hide()
	_open_panel = null
	if _panel_owner != null:
		_panel_owner.grab_focus()


func _on_play_pressed() -> void:
	for button: Button in _button_elements:
		button.disabled = true
	get_tree().change_scene_to_file(GAME_SCENE)
