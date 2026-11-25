class_name NelvarBossSound
extends RefCounted
## Sounds of the fight with the Only One (`assets/audio/sfx/boss/`, made by
## `tools/gen_boss_sfx.py`).
##
## Every sound is positional (AudioStreamPlayer2D on the SFX bus): a rift on the
## left is heard on the left, a far one is quieter. One-shots are left where
## they were played and free themselves when done, so a hazard that frees
## itself never cuts its own sound off. Loops (`hold`) hang on a node, move
## with it and die with it; their owner sets their level every frame.
##
## Sounds that may fire many times at once (hits, many rifts of the maze) have
## a shortest gap between two plays and a voice limit, so a burst of them is
## heard as one event, not a wall of noise.

const FOLDER := "res://assets/audio/sfx/boss/"
## Beyond this the sound is gone; the arena is about 2000 across.
const MAX_DISTANCE := 3200.0
const ATTENUATION := 0.7
## Level of each sound at full volume, in dB, against the rest of the game
## (the player's own sounds sit around -20 dB).
const VOLUME := {
	&"boss_intro": -8.0, &"boss_presence": -20.0, &"boss_hit": -14.0,
	&"phase_shift": -6.0, &"death": -5.0,
	&"dash_aim": -12.0, &"dash_lock": -10.0, &"dash_rush": -9.0,
	&"trail_charge": -12.0, &"trail_burst": -10.0, &"trail_crackle": -18.0,
	&"pull_spawn": -12.0, &"pull_charge": -12.0, &"pull_lock": -10.0, &"pull_burst": -8.0,
	&"rift_crack": -14.0, &"rift_open": -11.0, &"rift_hum": -24.0,
	&"blink": -12.0, &"collapse_tick": -15.0, &"collapse_strike": -9.0, &"collapse_reverse": -9.0,
	&"shard_charge": -11.0, &"shard_launch": -9.0, &"shard_turn": -11.0, &"shard_hit": -9.0,
	&"squeeze_start": -9.0, &"squeeze_rise": -10.0, &"squeeze_beacon": -14.0, &"squeeze_final": -7.0,
}
## Shortest time between two plays of a sound, in seconds.
const GAP := {
	&"boss_hit": 0.09, &"shard_hit": 0.12, &"rift_crack": 0.08, &"rift_open": 0.1,
	&"trail_burst": 0.15, &"collapse_tick": 0.05,
}
## Most voices of a sound playing at the same time.
const VOICES := {
	&"boss_hit": 3, &"rift_crack": 3, &"rift_open": 3, &"rift_hum": 3, &"trail_crackle": 3,
	&"shard_hit": 2, &"pull_charge": 2,
}
## Sounds that loop seamlessly (see `hold`).
const LOOPS: Array[StringName] = [&"boss_presence", &"trail_crackle", &"rift_hum", &"squeeze_beacon"]

static var _streams := {}
static var _last := {}


## A one-shot at `at` (global), parented to `host` (any node that outlives the
## sound: the hazard layer). Returns null when it is skipped (too soon after the
## last one, or too many already playing).
static func play(name: StringName, host: Node, at: Vector2, volume := 0.0,
		pitch := 1.0) -> AudioStreamPlayer2D:
	if host == null or not host.is_inside_tree() or not _may_play(name, host):
		return null
	var sound := _player(name, volume, pitch)
	host.add_child(sound)
	sound.global_position = at
	sound.finished.connect(sound.queue_free)
	sound.play()
	return sound


## A loop hanging on `owner` (at `offset` from it), silent at first: the owner
## raises it with `set_level`. Null when there are too many voices already.
static func hold(name: StringName, owner: Node2D, offset := Vector2.ZERO, pitch := 1.0) -> AudioStreamPlayer2D:
	if owner == null or not owner.is_inside_tree() or not _may_play(name, owner):
		return null
	var sound := _player(name, 0.0, pitch)
	sound.volume_db = -80.0
	sound.position = offset
	owner.add_child(sound)
	sound.play()
	return sound


## 0..1 level of a playing loop (or one-shot) against its full volume.
static func set_level(sound: AudioStreamPlayer2D, level: float) -> void:
	if not is_instance_valid(sound):
		return
	var full: float = sound.get_meta(&"full_db", 0.0)
	sound.volume_db = full + linear_to_db(maxf(level, 0.0001)) if level > 0.001 else -80.0


## Fades a sound out over `time` and frees it.
static func fade_out(sound: AudioStreamPlayer2D, time := 0.3) -> void:
	if not is_instance_valid(sound) or not sound.is_inside_tree():
		return
	var tween := sound.create_tween()
	tween.tween_property(sound, "volume_db", -60.0, time).set_ease(Tween.EASE_IN)
	tween.tween_callback(sound.queue_free)


static func stream(name: StringName) -> AudioStream:
	if not _streams.has(name):
		_streams[name] = load(FOLDER + String(name) + ".wav")
	return _streams[name]


static func _player(name: StringName, volume: float, pitch: float) -> AudioStreamPlayer2D:
	var sound := AudioStreamPlayer2D.new()
	sound.stream = stream(name)
	sound.bus = &"SFX"
	sound.max_distance = MAX_DISTANCE
	sound.attenuation = ATTENUATION
	sound.pitch_scale = pitch
	var full: float = VOLUME.get(name, -12.0) + volume
	sound.volume_db = full
	sound.set_meta(&"full_db", full)
	sound.add_to_group(_group(name))
	return sound


static func _may_play(name: StringName, host: Node) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if GAP.has(name) and now - float(_last.get(name, -1000.0)) < float(GAP[name]):
		return false
	if VOICES.has(name) and host.get_tree().get_nodes_in_group(_group(name)).size() >= int(VOICES[name]):
		return false
	_last[name] = now
	return true


static func _group(name: StringName) -> StringName:
	return StringName("boss_sound_" + String(name))
