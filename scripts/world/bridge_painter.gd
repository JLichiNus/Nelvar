class_name NelvarBridgePainter
extends RefCounted
## Builds plank, rail and post shapes in bridge coordinates, then samples them
## at world pixel centers. The baked image is never rotated when drawn.

const PLANK_LENGTH := 16.0
const POST_SPACING := 64.0
## Sun-bleached planks of the air reality.
const WOOD_PALETTE: Array[Color] = [
	Color("b49c84"), Color("bca48a"), Color("c4ac90"),
	Color("b09880"), Color("c8b094"), Color("b8a086"),
]
const BOARD_GAP := Color("6a5a5a")
const BOARD_GRAIN := Color("a48c76")
const BOARD_LIGHT := Color("d4c2a6")
const RAIL_LIGHT := Color("e6d6b8")
const RAIL_BODY := Color("ccb898")
const RAIL_SHADE := Color("a08a74")
const POST_OUTLINE := Color("5a4c56")
const POST_LIGHT := Color("d8c6a8")


func paint(data: NelvarWorldData, style: NelvarTerrainStyle) -> Array[NelvarBridgeArt]:
	var result: Array[NelvarBridgeArt] = []
	for bridge in data.bridges:
		result.append(_paint_bridge(bridge, data.world_seed, maxi(1, style.pixel_size)))
	return result


func _paint_bridge(bridge: NelvarWorldData.Bridge, world_seed: int,
		pixel_size: int) -> NelvarBridgeArt:
	var art := NelvarBridgeArt.new()
	art.pixel_size = pixel_size
	var step := float(pixel_size)
	var rail_width := maxf(5.0, step * 1.5)
	var post_radius := maxf(4.5, step * 1.3)
	var bounds := bridge.bounds.grow(post_radius + step)
	var origin := (bounds.position / step).floor() * step
	var size := ((bounds.end - origin) / step).ceil()
	art.world_rect = Rect2(origin, size * step)
	art.image = Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGBA8)
	var direction := bridge.start.direction_to(bridge.finish)
	var side := direction.orthogonal()
	var length := bridge.start.distance_to(bridge.finish)
	var half_width := bridge.width * 0.5
	var cap_width := minf(rail_width, length * 0.2)
	var deck_length := maxf(0.01, length - cap_width * 2.0)
	var plank_count := maxi(1, roundi(deck_length / maxf(PLANK_LENGTH, step * 3.0)))
	var plank_step := deck_length / plank_count
	# A seam must span at least a terrain pixel to stay continuous after sampling.
	var gap_width := minf(plank_step * 0.4, maxf(2.0, step * 1.05))
	var post_count := maxi(1, roundi(length / POST_SPACING))
	var post_step := length / post_count
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:bridge:%d:%d" % [world_seed, bridge.island_a, bridge.island_b]).hash()
	var boards: Array[Color] = []
	var grain_offsets: Array[float] = []
	for i in plank_count:
		boards.append(WOOD_PALETTE[rng.randi_range(0, WOOD_PALETTE.size() - 1)])
		grain_offsets.append(rng.randf_range(-half_width * 0.6, half_width * 0.3))
	for y in int(size.y):
		for x in int(size.x):
			var point := origin + Vector2(x + 0.5, y + 0.5) * step
			var local := point - bridge.start
			var along := local.dot(direction)
			var across := local.dot(side)
			var across_abs := absf(across)
			var color := Color.TRANSPARENT
			if along >= 0.0 and along <= length and across_abs <= half_width:
				var plank := clampi(floori((along - cap_width) / plank_step), 0, plank_count - 1)
				var phase := along - cap_width - plank * plank_step
				color = boards[plank]
				if phase >= plank_step - gap_width:
					color = BOARD_GAP
				elif phase < step * 0.55:
					color = BOARD_LIGHT
				elif plank % 3 == 0 and absf(phase - plank_step * 0.5) < step * 0.4 \
						and across > grain_offsets[plank] and across < grain_offsets[plank] + 16.0:
					color = BOARD_GRAIN
				if across_abs >= half_width - rail_width:
					color = RAIL_LIGHT if across < 0.0 else RAIL_BODY
					if across_abs < half_width - rail_width * 0.75:
						color = RAIL_SHADE
				if along < cap_width or along > length - cap_width:
					color = RAIL_BODY
			# Posts sit at both landings and at regular intervals on either rail.
			if across_abs >= half_width - post_radius and across_abs <= half_width + post_radius:
				var post_along := clampf(roundf(along / post_step) * post_step, 0.0, length)
				var post_offset := Vector2(along - post_along, across_abs - half_width)
				if post_offset.length_squared() <= post_radius * post_radius:
					color = POST_OUTLINE
					if post_offset.length_squared() < post_radius * post_radius * 0.35:
						color = POST_LIGHT
			if color.a > 0.0:
				art.image.set_pixel(x, y, color)
	art.texture = ImageTexture.create_from_image(art.image)
	return art
