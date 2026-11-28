class_name NelvarFlytraps
extends Node
## The flytraps of the giant forest. Open, a trap lies flat on the ground and waits; when the
## player (not in flight) or a hopper stands with its middle inside it (its radius less
## TRIGGER_INSET), it trembles and clicks for TRIGGER_TIME (its hairs stand up), then snaps
## shut: the player inside loses DAMAGE and is thrown out; an enemy inside is eaten (the kill
## is the player's). Shut, it digests for CLOSED_TIME (swollen if it ate) and stands as a low
## obstacle; then it opens again in OPEN_TIME. A shot of the player's (LMB) snaps an open trap
## at once: a trap can be spent from afar; the wind wave does not touch it (it throws hoppers
## in).

signal snapped(trap: NelvarThicketData.Flytrap, eaten: int, hurt: bool)

const State = NelvarThicketData.TrapState
const STEP := NelvarEarthData.PIXEL
const TRIGGER_INSET := 10.0
const TRIGGER_TIME := 0.45
const SNAP_TIME := 0.08
const CLOSED_TIME := 5.0
const OPEN_TIME := 1.0
const DAMAGE := 18.0
const PUSH := 380.0
const CLICK := preload("res://assets/audio/sfx/flytrap_click.tres")
const SNAP := preload("res://assets/audio/sfx/flytrap_snap.tres")


## One trap on screen; sorted with the others while it stands shut, flat under everyone
## while open.
class Trap extends Node2D:
	var spec: NelvarThicketData.Flytrap
	## Open, trembling, shut, shut over prey.
	var arts: Array[NelvarEarthArt] = []
	var body: StaticBody2D
	var hit: Hit
	var snap_left := 0.0
	var show_collision := false

	func _draw() -> void:
		var frame := 0
		var shake := Vector2.ZERO
		match spec.state:
			State.TRIGGERED:
				frame = 1
				shake = Vector2((1 if int(Time.get_ticks_msec() / 40) % 2 == 0 else -1) * STEP, 0.0)
			State.CLOSED:
				frame = 3 if spec.fed else 2
				if snap_left > 0.0:
					frame = 1
			State.OPENING:
				frame = 2 if spec.timer > OPEN_TIME * 0.5 else 1
		var art := arts[frame]
		if art != null and art.texture != null:
			draw_texture_rect(art.texture, Rect2(art.local_rect.position + shake, art.local_rect.size), false)
		if show_collision:
			draw_arc(Vector2.ZERO, spec.radius, 0.0, TAU, 32, Color.RED if spec.is_open() else Color.ORANGE, 2.0)
			draw_arc(Vector2.ZERO, spec.radius - TRIGGER_INSET, 0.0, TAU, 32, Color(1, 0.4, 0.4, 0.5), 1.0)


## What the player's shot hits (on the enemies' layer, so the shot reaches it).
class Hit extends Area2D:
	var trap: Trap
	var owner_traps: NelvarFlytraps

	func take_damage(_amount: float) -> void:
		owner_traps.shoot(trap)

	## The wind wave passes it by (it throws hoppers in instead).
	func deflect(_direction: Vector2) -> void:
		pass


var data: NelvarThicketData
var player: NelvarPlayer
var traps: Array[Trap] = []
## Snaps so far, and enemies eaten.
var snaps := 0
var eaten := 0


## `arts`: four arts per trap (open, trembling, shut, shut over prey), in data.flytraps order.
func setup(thicket: NelvarThicketData, arts: Array, the_player: NelvarPlayer, parent: Node) -> void:
	data = thicket
	player = the_player
	for i in data.flytraps.size():
		var spec := data.flytraps[i]
		var trap := Trap.new()
		trap.name = "Flytrap_%d" % spec.id
		trap.spec = spec
		trap.position = spec.center
		trap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		for art: NelvarEarthArt in arts[i]:
			art.bake()
			trap.arts.append(art)
		trap.z_index = -1
		trap.body = StaticBody2D.new()
		trap.body.name = "Shut"
		trap.body.collision_layer = 0
		trap.body.collision_mask = 0
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = spec.radius * 0.7
		shape.shape = circle
		trap.body.add_child(shape)
		trap.add_child(trap.body)
		trap.hit = Hit.new()
		trap.hit.name = "Hit"
		trap.hit.trap = trap
		trap.hit.owner_traps = self
		trap.hit.collision_layer = 8
		trap.hit.collision_mask = 0
		trap.hit.monitoring = false
		var hit_shape := CollisionShape2D.new()
		var hit_circle := CircleShape2D.new()
		hit_circle.radius = spec.radius * 0.6
		hit_shape.shape = hit_circle
		trap.hit.add_child(hit_shape)
		trap.add_child(trap.hit)
		parent.add_child(trap)
		traps.append(trap)


func step(delta: float) -> void:
	for trap in traps:
		var spec := trap.spec
		match spec.state:
			State.OPEN:
				if _triggered(spec):
					spec.state = State.TRIGGERED
					spec.timer = TRIGGER_TIME
					trap.queue_redraw()
					NelvarOneShotSound.play(trap, CLICK, spec.center, -4.0)
			State.TRIGGERED:
				spec.timer -= delta
				trap.queue_redraw()
				if spec.timer <= 0.0:
					snap(trap)
			State.CLOSED:
				spec.timer -= delta
				if trap.snap_left > 0.0:
					trap.snap_left -= delta
					if trap.snap_left <= 0.0:
						trap.queue_redraw()
				if spec.timer <= 0.0:
					spec.state = State.OPENING
					spec.timer = OPEN_TIME
					trap.queue_redraw()
			State.OPENING:
				var before := spec.timer > OPEN_TIME * 0.5
				spec.timer -= delta
				if before != (spec.timer > OPEN_TIME * 0.5):
					trap.queue_redraw()
				if spec.timer <= 0.0:
					spec.state = State.OPEN
					spec.fed = false
					trap.z_index = -1
					trap.body.set_deferred("collision_layer", 0)
					trap.hit.set_deferred("collision_layer", 8)
					trap.queue_redraw()


## Something standing in an open trap: the player on foot, or an enemy on the ground.
func _triggered(spec: NelvarThicketData.Flytrap) -> bool:
	var reach := spec.radius - TRIGGER_INSET
	if _grounded(player) and player.global_position.distance_to(spec.center) < reach:
		return true
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node2D
		if body != null and _enemy_grounded(enemy) and body.global_position.distance_to(spec.center) < reach:
			return true
	return false


func _grounded(who: NelvarPlayer) -> bool:
	return is_instance_valid(who) and not who.is_airborne() and not who.is_falling() and not who.is_dead()


func _enemy_grounded(enemy: Node) -> bool:
	return not (enemy.has_method("is_airborne") and enemy.call("is_airborne")) \
		and not (enemy.has_method("is_dead") and enemy.call("is_dead"))


## A shot snaps an open trap at once.
func shoot(trap: Trap) -> void:
	if trap.spec.is_open():
		snap(trap)


## The trap shuts: whoever is in it is hurt and thrown out, or eaten.
func snap(trap: Trap) -> void:
	var spec := trap.spec
	spec.state = State.CLOSED
	spec.timer = CLOSED_TIME
	trap.snap_left = SNAP_TIME
	trap.z_index = 0
	trap.body.set_deferred("collision_layer", NelvarProp.LOW_OBSTACLE_LAYER)
	trap.hit.set_deferred("collision_layer", 0)
	snaps += 1
	NelvarOneShotSound.play(trap, SNAP, spec.center, -2.0)
	var hurt := false
	var count := 0
	if _grounded(player) and player.global_position.distance_to(spec.center) < spec.radius + NelvarPlayer.BODY_RADIUS * 0.5:
		var away := spec.center.direction_to(player.global_position)
		if away == Vector2.ZERO:
			away = Vector2.DOWN
		player.take_damage(DAMAGE, spec.center)
		player.velocity += away * PUSH
		hurt = true
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node2D
		if body == null or not _enemy_grounded(enemy):
			continue
		if body.global_position.distance_to(spec.center) < spec.radius:
			enemy.call("take_damage", 10000.0)
			count += 1
	if count > 0:
		spec.fed = true
		eaten += count
	trap.queue_redraw()
	snapped.emit(spec, count, hurt)


func set_debug(shown: bool) -> void:
	for trap in traps:
		trap.show_collision = shown
		trap.queue_redraw()
