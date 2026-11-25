class_name NelvarOneShotSound
extends RefCounted
## A positional sound that outlives whoever made it: a popped bubble or a dead
## enemy is freed at once, its sound plays on by itself and then frees itself.
## The same stream again within `min_gap` seconds is skipped, so a burst of
## pops is heard as one event rather than a rattle.

const MAX_DISTANCE := 1600.0
const PANNING := 0.5

static var _last_played := {}


static func play(parent: Node, stream: AudioStream, at: Vector2,
		volume_db: float = 0.0, pitch: float = 1.0, min_gap: float = 0.04) -> void:
	if stream == null or parent == null or not parent.is_inside_tree():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var key := stream.get_instance_id()
	if now - float(_last_played.get(key, -INF)) < min_gap:
		return
	_last_played[key] = now
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = MAX_DISTANCE
	player.panning_strength = PANNING
	player.finished.connect(player.queue_free)
	parent.add_child(player)
	player.global_position = at
	player.play()
