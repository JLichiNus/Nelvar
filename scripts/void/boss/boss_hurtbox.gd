class_name NelvarBossHurtbox
extends Area2D
## The tall body of a boss, on the enemy layer: player attacks hit it here and the
## damage goes to the boss (whose own collider is only its feet).

var boss: Node


func take_damage(amount: float) -> void:
	if is_instance_valid(boss):
		boss.take_damage(amount)
