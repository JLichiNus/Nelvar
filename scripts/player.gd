class_name NelvarPlayer
extends CharacterBody2D

const BODY_RADIUS := 12.0

@export var speed: float = 300.0

var facing := Vector2.DOWN
@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	_register_controls()


func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	move_and_slide()
	if direction != Vector2.ZERO and direction != facing:
		facing = direction
		queue_redraw()


func adjust_zoom(multiplier: float) -> void:
	var value := clampf(camera.zoom.x * multiplier, 0.18, 1.6)
	camera.zoom = Vector2.ONE * value


func _draw() -> void:
	draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 16.0, Color(0.08, 0.13, 0.14, 0.3))
	draw_set_transform(Vector2.ZERO)
	draw_circle(Vector2.ZERO, 14.0, Color("263942"), true, -1.0, true)
	draw_circle(Vector2.ZERO, 11.0, Color("f5d18b"), true, -1.0, true)
	var side := facing.orthogonal()
	draw_colored_polygon(PackedVector2Array([
		facing * 19.0, facing * 8.0 + side * 5.0, facing * 8.0 - side * 5.0,
	]), Color("fff2ce"))


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
