class_name NelvarMutationHud
extends CanvasLayer
## Player-facing adaptation, mutation choices and applied effects.

const MutationText := preload("res://ui/mutations/mutation_text.gd")
const AdaptationWidget := preload("res://ui/mutations/adaptation_widget.gd")
const MutationChoice := preload("res://ui/mutations/mutation_choice.gd")
const MutationFlash := preload("res://ui/mutations/mutation_flash.gd")
const MAX_TOASTS := 3
const TOAST_DURATION := 4.5
const TOAST_FADE := 0.6
## A new toast pops in this much larger and brighter, then settles.
const TOAST_POP_SCALE := 1.18
const TOAST_POP_TIME := 0.35

## Player whose Mutations child this HUD displays.
@export var player: NelvarPlayer

## The "ripened" notice, gone once the mutation is chosen or seized.
var _ripe_toast: PanelContainer

@onready var _flash: MutationFlash = $Flash
@onready var _adaptation: AdaptationWidget = $Adaptation
@onready var _choice: MutationChoice = $Choice
@onready var _toasts: VBoxContainer = $Toasts
@onready var _strip: HBoxContainer = $Strip


func _ready() -> void:
	var director: NelvarMutationDirector
	if player != null:
		director = player.get_node_or_null("Mutations") as NelvarMutationDirector
	if director == null:
		push_warning("Интерфейс мутаций не нашёл узел Mutations у игрока.")
		hide()
		process_mode = Node.PROCESS_MODE_DISABLED
		_choice.set_process_input(false)
		return

	_adaptation.bind(director)
	_choice.bind(director)
	_strip.call("bind", director)
	director.mutation_applied.connect(_show_toast.bind(director))
	director.mutation_applied.connect(_celebrate)
	director.pending_changed.connect(_on_pending_changed.bind(director))


# A mutation took hold: the world around the player and the screen edges
# flare in the colour of the version that picked it.
func _celebrate(_mutation: NelvarMutation, _stage: int, owner: int, intercepted: bool) -> void:
	var color := NelvarMutation.version_color(owner)
	if is_instance_valid(player):
		NelvarMutationBurst.spawn(player, color, true)
	_flash.play(color, 1.0, 2 if intercepted else 1)


# The player's mutation ripened: a softer flare and a notice, so the choice
# is not missed and left to be seized.
func _on_pending_changed(pending: bool, director: NelvarMutationDirector) -> void:
	if not pending:
		if is_instance_valid(_ripe_toast):
			_remove_toast(_ripe_toast)
		return
	var color := NelvarMutation.version_color(director.player_version)
	if is_instance_valid(player):
		NelvarMutationBurst.spawn(player, color, false)
	_flash.play(color, 0.6)
	var key := _action_key_name(&"mutate")
	var rows := _add_toast([MutationText.line("Мутация созрела — %s, чтобы выбрать" % key, color, 24)])
	_ripe_toast = rows.get_parent() as PanelContainer


func _show_toast(mutation: NelvarMutation, stage: int, owner: int, intercepted: bool,
		director: NelvarMutationDirector) -> void:
	var version := NelvarMutation.version_name(owner)
	var title := mutation.title
	var header: String
	if intercepted:
		header = "%s перехватывает мутацию: %s" % [version, title]
	elif owner == NelvarMutation.SPONTANEOUS:
		header = "Спонтанная мутация: %s" % title
	elif owner == director.player_version:
		header = "Мутация: %s %s" % [title, NelvarMutation.stage_name(stage)]
	else:
		header = "%s выбирает за тебя: %s" % [version, title]

	var header_line := MutationText.line(header, NelvarMutation.version_color(owner), 24)
	var rows := _add_toast([header_line])
	MutationText.add_effects(rows, mutation, stage)


func _add_toast(lines: Array[Label]) -> VBoxContainer:
	if _toasts.get_child_count() >= MAX_TOASTS:
		var oldest := _toasts.get_child(0)
		_toasts.remove_child(oldest)
		oldest.queue_free()

	var toast := PanelContainer.new()
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_child(toast)

	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 3)
	toast.add_child(rows)
	for label in lines:
		rows.add_child(label)

	# Pops in from its centre; the container sets its size after this frame.
	toast.resized.connect(func() -> void: toast.pivot_offset = toast.size / 2.0)
	toast.scale = Vector2.ONE * TOAST_POP_SCALE
	toast.modulate = Color(1.8, 1.8, 1.8)
	var pop := toast.create_tween().set_parallel()
	pop.tween_property(toast, "scale", Vector2.ONE, TOAST_POP_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(toast, "modulate", Color.WHITE, TOAST_POP_TIME)

	var fade := toast.create_tween()
	fade.tween_interval(TOAST_DURATION - TOAST_FADE)
	fade.tween_property(toast, "modulate:a", 0.0, TOAST_FADE)
	fade.tween_callback(_remove_toast.bind(toast))
	return rows


func _action_key_name(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null:
			var code := key.physical_keycode if key.keycode == KEY_NONE else key.keycode
			return OS.get_keycode_string(code)
	return String(action)


func _remove_toast(toast: PanelContainer) -> void:
	if toast.get_parent() != _toasts:
		return
	_toasts.remove_child(toast)
	toast.queue_free()
