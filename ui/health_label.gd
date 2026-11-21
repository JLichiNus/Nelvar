extends Label


@export var player: Node


func _ready() -> void:
	if player == null or not player.has_signal("health_changed"):
		push_warning("Индикатору HP не назначен игрок.")
		return
	player.connect("health_changed", _on_health_changed)
	_on_health_changed(player.get("health"), player.get("max_health"))


func _on_health_changed(current: float, maximum: float) -> void:
	text = "HP: %d / %d" % [ceili(current), roundi(maximum)]
