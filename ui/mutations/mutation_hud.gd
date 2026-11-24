class_name NelvarMutationHud
extends CanvasLayer
## Player-facing adaptation, mutation choices and applied effects.

const MutationText := preload("res://ui/mutations/mutation_text.gd")
const AdaptationWidget := preload("res://ui/mutations/adaptation_widget.gd")
const MutationChoice := preload("res://ui/mutations/mutation_choice.gd")
const MAX_TOASTS := 3
const TOAST_DURATION := 4.5
const TOAST_FADE := 0.6

## Player whose Mutations child this HUD displays.
@export var player: NelvarPlayer

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
	rows.add_child(MutationText.line(header, NelvarMutation.version_color(owner), 24))
	MutationText.add_effects(rows, mutation, stage)

	var fade := toast.create_tween()
	fade.tween_interval(TOAST_DURATION - TOAST_FADE)
	fade.tween_property(toast, "modulate:a", 0.0, TOAST_FADE)
	fade.tween_callback(_remove_toast.bind(toast))


func _remove_toast(toast: PanelContainer) -> void:
	_toasts.remove_child(toast)
	toast.queue_free()
