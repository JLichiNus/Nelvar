class_name NelvarIceHazards
extends RefCounted
## The hazards of the ice maps, shared by the valley (NelvarIceMain) and the cave
## (NelvarCaveMain). A step over a fall — a crevasse, an open hole or open water, the
## cave's chasms — holds for a moment (COYOTE_TIME: narrow ones are crossed at a run,
## wide ones by flight), then the player drops and comes back where they last stood
## safely, hurt; the first fall of each kind says what to do. Thin ice holds a running
## player, not a standing one: standing a moment in one spot cracks it, the crack breaks
## into a hole of open water unless the player gets away, and the hole freezes over
## again. Hoppers blown into a fall die; a hopper landing on snow leaves a dent.
##
## The map's data (NelvarIceData or a map built on it) says what lies where:
## fall_kind(point, margin), is_safe_spot(point), ice_at(point), grip_at(point).

const Fall = NelvarIceData.Fall
const COYOTE_TIME := 0.09
const FALL_TIME := 0.6
const FALL_DAMAGE := 12.0
const CREVASSE_TINT := Color(0.16, 0.26, 0.62, 0.0)
const WATER_TINT := Color(0.2, 0.72, 0.78, 0.0)
const CHASM_TINT := Color(0.06, 0.1, 0.3, 0.0)
## Thin ice: standing this long within CRACK_REACH of a spot cracks it; the crack
## breaks after CRACK_TIME unless the player gets further than CRACK_REACH from it
## (then it holds for CRACK_LINGER, and a step on it breaks it at once).
const HOLD_TIME := 0.35
const CRACK_TIME := 0.8
const CRACK_REACH := 40.0
const CRACK_LINGER := 10.0
const HOLE_RADIUS := 40.0
## Seconds for a hole to freeze over again (open water, slush, thin ice).
const FREEZE_TIME := 25.0
const MAX_CRACKS := 8
const MAX_HOLES := 16
const HINT_WIDE := "Слишком широко. Разбегись (Ctrl) или взлети (Shift)"
const HINT_THIN := "Тонкий лёд: по нему можно бежать, стоять нельзя"


## A crack spreading under the player on thin ice, or one that held.
class Crack:
	var center := Vector2.ZERO
	var age := 0.0
	var held := false
	var held_time := 0.0


## The player fell (`kind`: NelvarIceData.Fall); the map updates its status line.
signal fell(kind: int)

var data: NelvarIceData
var player: NelvarPlayer
## Where the puffs go and whose say() shows the hints.
var host: Node
## Hoppers landing on snow leave dents here (optional).
var marks: NelvarSnowMarks
## Falls into crevasses (and chasms), plunges into water, cracks and holes so far.
var falls := 0
var plunges := 0
var cracks_made := 0
var holes_broken := 0
var cracks: Array[Crack] = []
var safe_position := Vector2.ZERO
## True from a fall until the player is back on their feet.
var falling := false
## The hint after the first fall of each kind (none for kinds left out).
var hints := {Fall.CREVASSE: HINT_WIDE, Fall.WATER: HINT_THIN}
## Shown after the next fall instead of the usual hint (the cave's melting ice says why).
var next_hint := ""

var _over_time := 0.0
var _stand_anchor := Vector2.INF
var _stand_time := 0.0
var _hinted := {}
## Enemies in the air last frame (a hopper's landing leaves a dent).
var _airborne_enemies := {}


func _init(map_data: NelvarIceData, the_player: NelvarPlayer, the_host: Node, snow_marks: NelvarSnowMarks = null) -> void:
	data = map_data
	player = the_player
	host = the_host
	marks = snow_marks
	safe_position = data.spawn_position


## The player's ground this physics frame: falls, thin ice, the safe spot. Call it after
## update_holes(), update_cracks() and enemies().
func step(delta: float) -> void:
	if falling or player.is_falling() or player.health <= 0.0:
		return
	var point := player.global_position
	if player.is_airborne():
		# The flight passes over everything and leaves the ice alone.
		player.traction = 1.0
		_over_time = 0.0
		_stand_anchor = Vector2.INF
		return
	player.traction = data.grip_at(point)
	var kind := data.fall_kind(point)
	if kind != Fall.NONE:
		_over_time += delta
		if _over_time > COYOTE_TIME:
			_over_time = 0.0
			fall(kind)
		return
	_over_time = 0.0
	_thin_ice(point, delta)
	if data.is_safe_spot(point):
		safe_position = point


## The player goes down (into a crack, the water or a chasm) and comes back on the
## ground they last stood on safely, hurt. The first fall of a kind says what to do.
func fall(kind: int) -> void:
	falling = true
	if kind == Fall.WATER:
		plunges += 1
		splash(player.global_position, 18)
	else:
		falls += 1
	fell.emit(kind)
	var tint := WATER_TINT if kind == Fall.WATER else (CHASM_TINT if kind == Fall.CHASM else CREVASSE_TINT)
	player.fall_into_abyss(FALL_TIME, tint)
	var hint := next_hint
	next_hint = ""
	await host.get_tree().create_timer(FALL_TIME + 0.3, false).timeout
	falling = false
	if not is_instance_valid(player):
		return
	player.recover_at(safe_position)
	player.take_damage(FALL_DAMAGE)
	_stand_anchor = Vector2.INF
	if hint.is_empty() and not _hinted.has(kind):
		hint = hints.get(kind, "")
	_hinted[kind] = true
	if not hint.is_empty() and host.has_method("say"):
		host.call("say", hint)


## Thin ice holds a running player, not a standing one: standing a moment in one spot
## cracks it; a crack that held breaks at once under the next step.
func _thin_ice(point: Vector2, delta: float) -> void:
	if data.ice_at(point) != NelvarIceData.Surface.THIN:
		_stand_anchor = Vector2.INF
		return
	for crack in cracks:
		if crack.held and point.distance_to(crack.center) < CRACK_REACH * 0.8:
			_break(crack)
			return
	if not _stand_anchor.is_finite() or point.distance_to(_stand_anchor) > CRACK_REACH:
		_stand_anchor = point
		_stand_time = 0.0
		return
	_stand_time += delta
	if _stand_time < HOLD_TIME:
		return
	for crack in cracks:
		if crack.center.distance_to(_stand_anchor) < CRACK_REACH:
			return
	if cracks.size() >= MAX_CRACKS:
		cracks.remove_at(0)
	var crack := Crack.new()
	crack.center = _stand_anchor
	cracks.append(crack)
	cracks_made += 1
	_stand_time = -INF


## Spreading cracks break under a player who stays, or hold once they get away (or take
## off); held ones fade.
func update_cracks(delta: float) -> void:
	for crack in cracks.duplicate():
		if crack.held:
			crack.held_time += delta
			if crack.held_time > CRACK_LINGER:
				cracks.erase(crack)
			continue
		crack.age += delta
		var away := player.global_position.distance_to(crack.center) > CRACK_REACH
		if away or player.is_airborne() or player.is_falling():
			crack.held = true
			continue
		if crack.age >= CRACK_TIME:
			_break(crack)


## The ice gives: a hole of open water where the crack was.
func _break(crack: Crack) -> void:
	cracks.erase(crack)
	break_at(crack.center)


## A hole of open water breaks open at `point`.
func break_at(point: Vector2, radius: float = HOLE_RADIUS) -> void:
	if data.holes.size() >= MAX_HOLES:
		data.holes.remove_at(0)
	var hole := NelvarIceData.Hole.new()
	hole.center = point
	hole.radius = radius
	data.holes.append(hole)
	holes_broken += 1
	splash(point, 14)


## Holes freeze over: open water, slush, thin ice, then gone into the patch again.
func update_holes(delta: float) -> void:
	for hole in data.holes.duplicate():
		hole.freeze += delta / FREEZE_TIME
		if hole.freeze >= 1.0:
			data.holes.erase(hole)


## Hoppers blown into a crack or a chasm fall, into the water drown; a hopper landing on
## snow leaves a dent.
func enemies() -> void:
	var seen := {}
	for enemy in host.get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node2D
		if body == null:
			continue
		var id := body.get_instance_id()
		var airborne: bool = enemy.has_method("is_airborne") and enemy.call("is_airborne")
		seen[id] = airborne
		if airborne:
			continue
		if _airborne_enemies.get(id, false) and marks != null:
			marks.stamp_dent(body.global_position)
		var kind := data.fall_kind(body.global_position, 6.0)
		if kind == Fall.WATER:
			splash(body.global_position, 14)
			enemy.call("take_damage", 10000.0)
		elif kind != Fall.NONE:
			puff(body.global_position, Color(0.86, 0.92, 1.0), 12)
			enemy.call("take_damage", 10000.0)
	_airborne_enemies = seen


## Snow thrown up (a hopper falling into a crevasse).
func puff(point: Vector2, color: Color, count: int) -> void:
	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.amount = count
	particles.lifetime = 0.6
	particles.direction = Vector2.UP
	particles.spread = 70.0
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 160.0
	particles.gravity = Vector2(0.0, 320.0)
	particles.scale_amount_min = NelvarIceData.PIXEL
	particles.scale_amount_max = NelvarIceData.PIXEL
	particles.color = color
	particles.position = point
	particles.z_index = 20
	particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	particles.finished.connect(particles.queue_free)
	host.add_child(particles)
	particles.emitting = true


## Water and shards of ice thrown up where the ice breaks or someone goes in.
func splash(point: Vector2, count: int) -> void:
	puff(point, Color(0.62, 0.86, 0.92), count)
	puff(point, Color(0.95, 0.98, 1.0), count / 2)
