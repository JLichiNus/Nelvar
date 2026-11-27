class_name NelvarVolumeSlider
extends NelvarSlider
## A volume row in the settings (1% a step): reads and writes
## GameSettings.volumes[bus].

@export var bus: StringName = &"Master"


func _ready() -> void:
	super()
	set_value_no_signal(GameSettings.volume(bus))
	value_changed.connect(_on_value_changed)
	GameSettings.volume_changed.connect(_on_volume_changed)


func _on_value_changed(new_value: float) -> void:
	GameSettings.set_volume(bus, new_value)


func _on_volume_changed(changed_bus: StringName, new_value: float) -> void:
	if changed_bus == bus and not is_equal_approx(new_value, value()):
		set_value_no_signal(new_value)
