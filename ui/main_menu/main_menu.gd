extends Control
## Main menu: four buttons, four realities. Hovering or focusing a button sends a
## wave from that button across the landscape, turning it into the same place in
## that button's reality.

const GAME_SCENE := "res://scenes/main.tscn"
## Developer setting "Запускать игру в Пустоте" starts here instead.
const VOID_SCENE := "res://scenes/void.tscn"
## Developer setting "Запускать игру на Земле": the earth valley.
const EARTH_SCENE := "res://scenes/earth.tscn"
## Developer setting "Запускать игру в Огне": the fire forge.
const FIRE_SCENE := "res://scenes/fire.tscn"
## Developer setting "Запускать игру на Льду": the ice valley.
const ICE_SCENE := "res://scenes/ice.tscn"
const TRANSITION_TIME := 0.3
## Speed-up for a wave that is interrupted by another hover.
const HURRY_SPEED := 2.5
const PARTICLE_FADE := 0.6
## The pixel logo is drawn at this integer scale.
const LOGO_SCALE := 4
const PARTICLE_AMOUNT := 90
const IDLE_TEXT := Color(0.78, 0.78, 0.78)
## Text inset from the button's left edge; the highlighted text slides one art
## pixel further (the theme's button frames are drawn at 3x).
const TEXT_INSET := 24.0
const TEXT_SLIDE := 3.0
## The menu music (looped on import) fades in on entering the menu and fades
## out when the game starts.
const MUSIC_FADE_IN := 2.5
const MUSIC_FADE_OUT := 1.5

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
## Button -> Label drawing its text (separate node so a reality can put a shader
## on the text alone, without touching the button frame).
var _button_labels: Dictionary = {}
## Per reality: highlighted and pressed button styles tinted with its accent.
var _highlight_styles: Dictionary = {}
var _pressed_styles: Dictionary = {}
var _idle_style: StyleBox
var _particles: Dictionary = {}
var _particle_textures: Dictionary = {}
var _texel := 1.0
var _wind := 0.0
var _open_panel: NelvarMenuPanel
var _panel_owner: Button
var _menu_tween: Tween
var _music_tween: Tween

@onready var background: TextureRect = $Background
@onready var particle_root: Node2D = $Particles
@onready var menu_column: VBoxContainer = $Margin/Layout/Menu
@onready var logo: TextureRect = %Logo
@onready var logo_glow: TextureRect = %LogoGlow
@onready var play_button: Button = %Play
@onready var settings_button: Button = %Settings
@onready var about_button: Button = %About
@onready var quit_button: Button = %Quit
@onready var settings_panel: NelvarSettingsPanel = %SettingsPanel
@onready var about_panel: NelvarMenuPanel = %AboutPanel
@onready var about_back: Button = %AboutBack
@onready var music: AudioStreamPlayer = $Music
@onready var hover_sound: AudioStreamPlayer = $HoverSound
@onready var click_sound: AudioStreamPlayer = $ClickSound


func _ready() -> void:
	_material = background.material as ShaderMaterial
	logo.custom_minimum_size = logo.texture.get_size() * LOGO_SCALE
	_button_elements = {
		play_button: play_element,
		settings_button: settings_element,
		about_button: about_element,
		quit_button: quit_element,
	}
	_mutate_launch()
	# The theme's dark pixel frames; the highlight is tinted per reality.
	_idle_style = play_button.get_theme_stylebox("normal")
	var base_hover := play_button.get_theme_stylebox("hover") as StyleBoxTexture
	var base_pressed := play_button.get_theme_stylebox("pressed") as StyleBoxTexture
	for element: NelvarMenuElement in _button_elements.values():
		_particles[element] = _create_particles()
		var hover := base_hover.duplicate() as StyleBoxTexture
		hover.modulate_color = element.accent
		_highlight_styles[element] = hover
		var pressed := base_pressed.duplicate() as StyleBoxTexture
		pressed.modulate_color = element.accent.darkened(0.2)
		_pressed_styles[element] = pressed
	for button: Button in _button_elements:
		_button_labels[button] = _make_button_label(button, _button_elements[button])
		# The highlight below is drawn for mouse and keyboard alike.
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		_set_button_highlight(button, false)
		button.mouse_entered.connect(button.grab_focus)
		button.focus_entered.connect(_on_button_focus_entered.bind(button))
		button.focus_exited.connect(_on_button_focus_exited.bind(button))
	# Every button of the menu and its panels sounds on hover and press,
	# including ones added later. Hooked up before the buttons' own handlers so
	# the click is already playing when Play or Quit leaves the menu.
	for button in find_children("*", "BaseButton", true, false):
		_add_button_sounds(button)
	get_tree().node_added.connect(_on_node_added)
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_open.bind(settings_panel, settings_button, settings_panel.fullscreen_check))
	about_button.pressed.connect(_open.bind(about_panel, about_button, about_back))
	quit_button.pressed.connect(_quit)
	# Closing the window goes through _quit too, so the sounds stop first.
	get_tree().auto_accept_quit = false
	settings_panel.back_button.pressed.connect(_close_panel)
	settings_panel.dev_panel_toggled.connect(_on_dev_panel_toggled)
	about_back.pressed.connect(_close_panel)

	settings_panel.hide()
	about_panel.hide()
	settings_panel.accent = settings_element.accent
	about_panel.accent = about_element.accent

	resized.connect(_layout_particles)
	_layout_particles()
	# Every launch opens in a random reality until the player points at something.
	_show_instant(_button_elements.values().pick_random())
	_start_music()


func _exit_tree() -> void:
	NelvarLocationCursor.apply(null)
	get_tree().auto_accept_quit = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()


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
	logo_glow.modulate = element.accent
	_set_cursor(element)
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
	_set_cursor(element)
	if _accent_tween != null:
		_accent_tween.kill()
	_accent_tween = create_tween()
	_accent_tween.tween_property(logo_glow, "modulate", element.accent, TRANSITION_TIME * 0.6)
	if _particle_tween != null:
		_particle_tween.kill()
	_particle_tween = create_tween().set_parallel()
	for other: NelvarMenuElement in _particles:
		var target := 1.0 if other == element else 0.0
		_particle_tween.tween_property(_particles[other], "modulate:a", target, PARTICLE_FADE)


## The cursor changes together with the reality behind the menu.
func _set_cursor(element: NelvarMenuElement) -> void:
	NelvarLocationCursor.apply(element.cursor)


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
	var tween := create_tween()
	tween.tween_property(button, "modulate", Color.WHITE, 0.15)
	_button_tweens[button] = tween


## Buttons are the theme's dark pixel frames; the focused one is tinted with its
## reality's accent and its text slides one art pixel right. Only the focused
## button is highlighted (hovering grabs focus), so two buttons never light up.
func _set_button_highlight(button: Button, highlighted: bool) -> void:
	var element: NelvarMenuElement = _button_elements[button]
	var look: StyleBox = _highlight_styles[element] if highlighted else _idle_style
	button.add_theme_stylebox_override("normal", look)
	button.add_theme_stylebox_override("hover", look)
	button.add_theme_stylebox_override("pressed", _pressed_styles[element])
	button.add_theme_stylebox_override("hover_pressed", _pressed_styles[element])
	var label: Label = _button_labels[button]
	label.add_theme_color_override("font_color", Color.WHITE if highlighted else IDLE_TEXT)
	label.offset_left = TEXT_INSET + (TEXT_SLIDE if highlighted else 0.0)


## Moves the button's text into a Label in the reality's stylized pixel font,
## with the reality's optional text material (e.g. wind for air).
func _make_button_label(button: Button, element: NelvarMenuElement) -> Label:
	var label := Label.new()
	label.text = button.text
	label.add_theme_font_override("font", element.font)
	label.add_theme_font_size_override("font_size", button.get_theme_font_size("font_size"))
	# The stylized fonts have their own outline; no extra shadow.
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.material = element.text_material
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = TEXT_INSET
	button.text = ""
	button.add_child(label)
	# Keep the button as tall as the text plus the frame's vertical padding
	# (measured once the label is in the tree and its font is resolved).
	var padding := button.get_theme_stylebox("normal").get_minimum_size().y
	button.custom_minimum_size.y = label.get_combined_minimum_size().y + padding
	return label


## Each reality lights its button in its own way. Only colors change: moving or
## scaling pixel art by fractions of a pixel would smear it.
func _animate_button(button: Button, id: StringName) -> void:
	_kill_button_tween(button)
	var tween := create_tween()
	_button_tweens[button] = tween
	match id:
		&"air":
			# A gust: two quick cool flickers.
			tween.tween_property(button, "modulate", Color(1.3, 1.45, 1.5), 0.05)
			tween.tween_property(button, "modulate", Color.WHITE, 0.12)
			tween.tween_property(button, "modulate", Color(1.2, 1.3, 1.35), 0.05)
			tween.tween_property(button, "modulate", Color.WHITE, 0.2)
		&"ice":
			# Frost: a bright flash that slowly settles.
			tween.tween_property(button, "modulate", Color(1.6, 1.6, 1.65), 0.05)
			tween.tween_property(button, "modulate", Color.WHITE, 0.45) \
				.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		&"earth":
			# A heavy thud: darken, then a warm glow.
			tween.tween_property(button, "modulate", Color(0.65, 0.65, 0.6), 0.06)
			tween.tween_property(button, "modulate", Color(1.15, 1.12, 1.0), 0.12)
			tween.tween_property(button, "modulate", Color.WHITE, 0.25)
		&"fire":
			# Fire never settles: flicker while highlighted.
			tween.set_loops()
			tween.tween_property(button, "modulate", Color(1.3, 1.1, 0.92), 0.09)
			tween.tween_property(button, "modulate", Color(1.05, 0.98, 0.95), 0.13)
			tween.tween_property(button, "modulate", Color(1.35, 1.12, 0.95), 0.07)
			tween.tween_property(button, "modulate", Color.WHITE, 0.16)
		_:
			tween.tween_property(button, "modulate", Color.WHITE, 0.1)


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

func _open(panel: NelvarMenuPanel, owner_button: Button, first_focus: Control) -> void:
	if _open_panel != null and _open_panel != panel:
		_open_panel.close_now()
	_open_panel = panel
	_panel_owner = owner_button
	panel.play_open()
	first_focus.grab_focus.call_deferred()


func _close_panel() -> void:
	if _open_panel == null:
		return
	_open_panel.play_close()
	_open_panel = null
	if _panel_owner != null:
		_panel_owner.grab_focus()


## The developer panel opens left of the settings, over the menu column: the
## column fades out and stops taking input while the panel is open.
func _on_dev_panel_toggled(open: bool) -> void:
	if _menu_tween != null:
		_menu_tween.kill()
	_menu_tween = create_tween()
	_menu_tween.tween_property(menu_column, "modulate:a", 0.0 if open else 1.0, 0.15)
	for button: Button in _button_elements:
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE if open else Control.MOUSE_FILTER_STOP
		button.focus_mode = Control.FOCUS_NONE if open else Control.FOCUS_ALL


func _on_play_pressed() -> void:
	for button: Button in _button_elements:
		button.disabled = true
	_fade_out_music()
	_keep_click_sound()
	var scene := GAME_SCENE
	if GameSettings.start_in_void:
		scene = VOID_SCENE
	elif GameSettings.start_on_earth:
		scene = EARTH_SCENE
	elif GameSettings.start_in_fire:
		scene = FIRE_SCENE
	elif GameSettings.start_on_ice:
		scene = ICE_SCENE
	get_tree().change_scene_to_file(scene)


## Quitting with sounds still held by the audio server leaks them at exit:
## stop the players and let the audio thread release them first.
func _quit() -> void:
	for button: Button in _button_elements:
		button.disabled = true
	music.stop()
	hover_sound.stop()
	if click_sound.playing:
		await click_sound.finished
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()


# --- Sounds ------------------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node is BaseButton and is_ancestor_of(node):
		_add_button_sounds(node)


func _add_button_sounds(button: BaseButton) -> void:
	if button.has_meta(&"button_sounds"):
		return
	button.set_meta(&"button_sounds", true)
	button.mouse_entered.connect(_on_button_hovered.bind(button))
	button.pressed.connect(click_sound.play)


func _on_button_hovered(button: BaseButton) -> void:
	if not button.disabled:
		hover_sound.play()


## The game scene replaces the menu: the click moves to the tree root so it is
## not cut off, and frees itself once it has played.
func _keep_click_sound() -> void:
	var player := click_sound
	player.reparent(get_tree().root)
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(player.stream.get_length() + 0.1, true) \
		.timeout.connect(player.queue_free)


# --- Music -------------------------------------------------------------------

func _start_music() -> void:
	music.volume_linear = 0.0
	music.play()
	_music_tween = music.create_tween()
	_music_tween.tween_property(music, "volume_linear", 1.0, MUSIC_FADE_IN) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## The player moves to the tree root so the fade outlives the menu and plays
## over the game's first moments, then frees itself.
func _fade_out_music() -> void:
	if _music_tween != null:
		_music_tween.kill()
	var player := music
	player.reparent(get_tree().root)
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	var tween := player.create_tween()
	tween.tween_property(player, "volume_linear", 0.0, MUSIC_FADE_OUT) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(player.queue_free)
