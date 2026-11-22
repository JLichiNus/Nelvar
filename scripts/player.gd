class_name NelvarPlayer
extends CharacterBody2D

const BODY_RADIUS := 24.0

@export var speed: float = 300.0

var facing := Vector2.DOWN
@onready var camera: Camera2D = $Camera2D
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_register_controls()


func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	move_and_slide()
	if direction != Vector2.ZERO:
		facing = direction
	if direction.x != 0.0:
		sprite.flip_h = direction.x < 0.0


func adjust_zoom(multiplier: float) -> void:
	var value := clampf(camera.zoom.x * multiplier, 0.18, 1.6)
	camera.zoom = Vector2.ONE * value


func _register_controls() -> void:
	var controls := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
	}
	for action: String in controls:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: int in controls[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
