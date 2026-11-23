class_name NelvarVoidArena
extends Node2D
## The arena on the monolith: broken obelisks ring the sigil, and stepping inside
## starts the fight with the Only One (NelvarTheOne). The monolith's edge is sealed
## so there is no way back, the sigil and the sky wake up, and the boss forms out
## of the sigil. Defeating it lifts the seal.

signal fight_started
signal fight_won

const SEAL_TIME := 1.4
const OBELISK_WIDTH := 14
const OBELISK_HEIGHT := 46
const OBELISK_FOOTPRINT := Vector2(28.0, 14.0)
const STONE: Array[Color] = [Color("15151d"), Color("1f1f29"), Color("2b2b37"), Color("393946"),
	Color("4a4a59")]
const STONE_RIM := Color("6a6a80")

var data: NelvarVoidData
var player: NelvarPlayer
var monolith_node: NelvarVoidDebris
var started := false
var boss: NelvarTheOne
var boss_defeated := false
var _world_layer: Node2D
var _barrier_tween: Tween

var _seal: StaticBody2D
var _barrier: Line2D
var _rune_glows: Array[Sprite2D] = []


func setup(void_data: NelvarVoidData, player_node: NelvarPlayer, monolith: NelvarVoidDebris,
		world_layer: Node2D) -> void:
	data = void_data
	player = player_node
	monolith_node = monolith
	_world_layer = world_layer
	y_sort_enabled = true
	var obelisks := NelvarVoidData.obelisk_positions()
	for i in obelisks.size():
		_add_obelisk(obelisks[i], NelvarVoidData.OBELISKS[i].y, i)
	var outline := data.monolith.world_polygon()
	# The seal: walls along the whole edge, switched on when the fight starts.
	_seal = StaticBody2D.new()
	_seal.name = "Seal"
	_seal.collision_layer = 0
	_seal.collision_mask = 2
	add_child(_seal)
	for i in outline.size():
		var segment := SegmentShape2D.new()
		segment.a = outline[i]
		segment.b = outline[(i + 1) % outline.size()]
		var collider := CollisionShape2D.new()
		collider.shape = segment
		_seal.add_child(collider)
	# A thin wall of light along the edge, shown with the seal.
	_barrier = Line2D.new()
	_barrier.name = "Barrier"
	_barrier.closed = true
	_barrier.width = 4.0
	_barrier.default_color = Color(0.62, 0.38, 1.0)
	_barrier.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_barrier.joint_mode = Line2D.LINE_JOINT_SHARP
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_barrier.material = add
	_barrier.z_index = 3
	_barrier.modulate.a = 0.0
	for point in outline:
		_barrier.add_point(point + (data.arena_center - point).normalized() * 6.0)
	world_layer.add_child(_barrier)


func boss_spawn_position() -> Vector2:
	return data.arena_center


func _physics_process(_delta: float) -> void:
	if started or player == null or player.is_falling():
		return
	if player.global_position.distance_to(data.arena_center) < NelvarVoidData.ARENA_TRIGGER_RADIUS:
		start_fight()


func start_fight() -> void:
	if started:
		return
	started = true
	_seal.collision_layer = 1
	var tween := create_tween()
	tween.tween_property(_barrier, "modulate:a", 1.0, SEAL_TIME) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_pulse_barrier)
	create_tween().tween_property(monolith_node, "glow_boost", 0.45, SEAL_TIME * 2.0)
	for glow in _rune_glows:
		create_tween().tween_property(glow, "modulate:a", 1.0, SEAL_TIME)
	boss = NelvarTheOne.new()
	boss.position = data.arena_center
	add_child(boss)
	boss.defeated.connect(_on_boss_defeated)
	fight_started.emit()
	boss.begin(player, data.arena_center, _world_layer)


func _pulse_barrier() -> void:
	if boss_defeated:
		return
	_barrier_tween = create_tween().set_loops()
	_barrier_tween.tween_property(_barrier, "modulate:a", 0.45, 1.6).set_trans(Tween.TRANS_SINE)
	_barrier_tween.tween_property(_barrier, "modulate:a", 1.0, 1.6).set_trans(Tween.TRANS_SINE)


## The seal lifts and the sigil quiets down.
func _on_boss_defeated() -> void:
	boss_defeated = true
	boss = null
	_seal.collision_layer = 0
	if _barrier_tween != null:
		_barrier_tween.kill()
	create_tween().tween_property(_barrier, "modulate:a", 0.0, SEAL_TIME * 2.0)
	create_tween().tween_property(monolith_node, "glow_boost", 0.0, SEAL_TIME * 3.0)
	for glow in _rune_glows:
		create_tween().tween_property(glow, "modulate:a", 0.35, SEAL_TIME * 3.0)
	fight_won.emit()


# --- Obelisks ----------------------------------------------------------------

func _add_obelisk(base: Vector2, remaining: float, index: int) -> void:
	var body := StaticBody2D.new()
	body.name = "Obelisk_%d" % index
	body.position = base
	body.collision_layer = 1
	body.collision_mask = 2
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shape := ConvexPolygonShape2D.new()
	shape.points = NelvarProp.footprint_polygon(OBELISK_FOOTPRINT)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	var images := _paint_obelisk(remaining, index)
	var pixel := float(NelvarDebrisPainter.PIXEL)
	var size := Vector2(images[0].get_size()) * pixel
	var rect := Rect2(Vector2(-size.x * 0.5, -size.y + 3.0 * pixel), size)
	var stone := Sprite2D.new()
	stone.texture = ImageTexture.create_from_image(images[0])
	stone.centered = false
	stone.position = rect.position
	stone.scale = Vector2.ONE * pixel
	body.add_child(stone)
	var glow := Sprite2D.new()
	glow.texture = ImageTexture.create_from_image(images[1])
	glow.centered = false
	glow.position = rect.position
	glow.scale = Vector2.ONE * pixel
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add
	glow.modulate.a = 0.35
	body.add_child(glow)
	_rune_glows.append(glow)
	add_child(body)
	NelvarOcclusionOutline.add_occluder(body, stone.texture, Rect2(base + rect.position, rect.size))
	body.tree_exiting.connect(NelvarOcclusionOutline.remove_occluder.bind(body))


## [stone, glow]: a tapering black pillar broken off at `remaining` of its height,
## lit from the upper right, a column of runes glowing down its face.
func _paint_obelisk(remaining: float, index: int) -> Array[Image]:
	var height := int(OBELISK_HEIGHT * remaining) + 8
	var width := OBELISK_WIDTH + 6
	var stone := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var glow := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var salt := 0x0BE115C + index * 977
	var base_y := height - 4
	# Ground shadow at the foot.
	for y in range(base_y - 2, height):
		for x in width:
			var d := Vector2((x + 0.5 - width * 0.5) / (width * 0.5), (y + 0.5 - base_y) / 3.0)
			if d.length_squared() < 1.0:
				stone.set_pixel(x, y, Color(0.0, 0.0, 0.02, 0.5))
	var top := 4
	for y in range(top, base_y):
		var rise := float(base_y - y) / float(base_y - top)
		var half := lerpf(OBELISK_WIDTH * 0.5, OBELISK_WIDTH * 0.32, rise)
		var center := width * 0.5
		for x in width:
			var offset := x + 0.5 - center
			if absf(offset) > half:
				continue
			# Broken top: a jagged line instead of a point.
			var jag := NelvarPixelArt.hash01(x, 0, salt) * 5.0
			if remaining < 0.99 and y < top + jag:
				continue
			if remaining >= 0.99 and float(y - top) < absf(offset) * 1.6:
				continue
			var cell := Vector2i(x, y)
			var color: Color
			if absf(offset) > half - 1.0:
				color = Color("060609")
			elif offset > half - 2.0 or (remaining < 0.99 and y < top + jag + 1.0):
				# Light from the upper right catches the edge and the broken top.
				color = STONE_RIM
			else:
				var lit := 0.2 + (0.45 if offset > 0.5 else 0.0) + (NelvarPixelArt.hash01(x, y, salt) - 0.5) * 0.15
				color = NelvarPixelArt.ramp(STONE, lit, cell)
			stone.set_pixel(x, y, color)
	# Runes down the face, one every few rows.
	var center_x := width / 2
	for row in range(top + 6, base_y - 4, 4):
		if NelvarPixelArt.hash01(row, 1, salt) < 0.3:
			continue
		var shape := int(NelvarPixelArt.hash01(row, 2, salt) * 4.0)
		var pixels: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]
		if shape == 1:
			pixels = [Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 2)]
		elif shape == 2:
			pixels = [Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 0)]
		elif shape == 3:
			pixels = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 2)]
		for p in pixels:
			var at := Vector2i(center_x, row) + p
			if stone.get_pixelv(at).a > 0.0:
				stone.set_pixelv(at, Color("0a0714"))
				glow.set_pixelv(at, Color(0.62, 0.36, 1.0, 0.9))
	return [stone, glow]
