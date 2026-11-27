extends Node
## Autoload: background music during a run (not in the main menu, which has
## its own).
##
## The tracks do not loop. Each one fades in at its start and fades out
## before its end, then the music is silent for SILENCE seconds and the next
## track is picked at random (never the same one twice in a row while there
## are others). It lives outside the scenes, so restarting after death or
## loading the Void does not restart the track.
##
## Each location has its own playlist (PLAYLISTS): the air plays only air
## music, the Void only Void music. Game scenes call start(<their playlist>)
## when they open, the main menu calls stop(). Opening a location with another
## playlist fades the current track out and starts one of the new playlist
## right away.
##
## set_muffled() puts the Music bus "under water" (a low-pass filter sliding
## down) while the pause menu is open, and lifts it again.

## Tracks to pick from, per location; add new ones here.
const PLAYLISTS := {
	&"air": [
		preload("res://assets/audio/music/game/odd_meter_arpeggio.mp3"),
	],
	&"void": [
		preload("res://assets/audio/music/void/fractured_orbits.mp3"),
	],
}
const FADE_IN := 4.0
const FADE_OUT := 6.0
## Seconds of silence between two tracks.
const SILENCE := 30.0
## Fade when the run is left for the menu.
const STOP_FADE := 1.5
## Fade of the old location's track when a location with another playlist opens.
const SWITCH_FADE := 1.0
## Volume of a track at full level. The music sits under the sound effects;
## the player sets the overall music volume in the settings (bus "Music").
const VOLUME_DB := -19.0

var _player: AudioStreamPlayer
var _running := false
var _playlist: StringName = &""
var _silence_left := 0.0
var _last := -1
var _stop_tween: Tween

## Low-pass on the Music bus while muffled; disabled (no cost) otherwise.
const MUFFLED_CUTOFF := 650.0
const OPEN_CUTOFF := 20000.0
const MUFFLE_TIME := 0.35
const UNMUFFLE_TIME := 0.45
var _muffle: AudioEffectLowPassFilter
var _muffle_index := -1
var _muffle_tween: Tween


func _ready() -> void:
	# Keeps playing in the pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	_player.volume_db = -80.0
	add_child(_player)
	_player.finished.connect(_on_track_finished)
	var bus := AudioServer.get_bus_index(&"Music")
	if bus >= 0:
		_muffle = AudioEffectLowPassFilter.new()
		_muffle.cutoff_hz = OPEN_CUTOFF
		AudioServer.add_bus_effect(bus, _muffle)
		_muffle_index = AudioServer.get_bus_effect_count(bus) - 1
		AudioServer.set_bus_effect_enabled(bus, _muffle_index, false)


## Muffles the music (the pause menu) or lifts it, sliding the filter;
## `instant` jumps there (the scene is going away).
func set_muffled(muffled: bool, instant := false) -> void:
	if _muffle == null:
		return
	if _muffle_tween != null:
		_muffle_tween.kill()
	var bus := AudioServer.get_bus_index(&"Music")
	var target := MUFFLED_CUTOFF if muffled else OPEN_CUTOFF
	if muffled:
		AudioServer.set_bus_effect_enabled(bus, _muffle_index, true)
	if instant:
		_set_cutoff(target)
		AudioServer.set_bus_effect_enabled(bus, _muffle_index, muffled)
		return
	# Exponential slide: equal steps in pitch, not in hertz, so it sounds even.
	_muffle_tween = create_tween()
	_muffle_tween.tween_method(_set_cutoff_log, log(_muffle.cutoff_hz), log(target),
		MUFFLE_TIME if muffled else UNMUFFLE_TIME).set_trans(Tween.TRANS_SINE)
	if not muffled:
		_muffle_tween.tween_callback(AudioServer.set_bus_effect_enabled.bind(bus, _muffle_index, false))


func _set_cutoff_log(log_hz: float) -> void:
	_set_cutoff(exp(log_hz))


func _set_cutoff(hz: float) -> void:
	_muffle.cutoff_hz = hz


## A location opened: play its playlist unless it already plays (a restart
## after death). A track of another playlist fades out first.
## Headless runs (the tests) have no sound, so they get no music either.
func start(playlist: StringName) -> void:
	if DisplayServer.get_name() == "headless":
		return
	assert(PLAYLISTS.has(playlist), "Unknown playlist %s" % playlist)
	var switching := playlist != _playlist
	if _running and not switching:
		return
	if _stop_tween != null:
		_stop_tween.kill()
		_stop_tween = null
	_playlist = playlist
	_running = true
	_silence_left = 0.0
	if switching:
		_last = -1
	if _player.playing and switching:
		# The other location's track fades out, then this one's begins.
		_stop_tween = create_tween()
		_stop_tween.tween_property(_player, "volume_db", -80.0, SWITCH_FADE) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_stop_tween.tween_callback(_player.stop)
		_stop_tween.tween_callback(_play_next)
	else:
		_play_next()


## The run is over (back to the menu): fade the music out and stay silent.
func stop() -> void:
	if not _running:
		return
	_running = false
	_silence_left = 0.0
	# A switch still fading must not start the next location's track.
	if _stop_tween != null:
		_stop_tween.kill()
	if not _player.playing:
		return
	_stop_tween = create_tween()
	_stop_tween.tween_property(_player, "volume_db", -80.0, STOP_FADE) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_stop_tween.tween_callback(_player.stop)


## Quitting with the track still held by the audio server leaks it at exit:
## stop it and give the audio thread a moment to let it go, then quit.
func quit_game() -> void:
	_running = false
	_player.stop()
	await get_tree().create_timer(0.1, true, false, true).timeout
	get_tree().quit()


func is_playing_track() -> bool:
	return _player.playing


func _process(delta: float) -> void:
	if not _running or _stop_tween != null and _stop_tween.is_running():
		return
	if _player.playing:
		_player.volume_db = VOLUME_DB + linear_to_db(_fade_level())
	elif _silence_left > 0.0:
		_silence_left -= delta
		if _silence_left <= 0.0:
			_play_next()


# 0..1: rising over FADE_IN from the start, falling over FADE_OUT to the end.
func _fade_level() -> float:
	var position := _player.get_playback_position()
	var length := _player.stream.get_length()
	var level := minf(position / FADE_IN, (length - position) / FADE_OUT)
	level = clampf(level, 0.0, 1.0)
	# Smooth at both ends of each fade.
	return level * level * (3.0 - 2.0 * level)


func _play_next() -> void:
	_stop_tween = null
	var tracks: Array = PLAYLISTS.get(_playlist, [])
	if tracks.is_empty():
		return
	var index := randi_range(0, tracks.size() - 1)
	if tracks.size() > 1 and index == _last:
		index = (index + randi_range(1, tracks.size() - 1)) % tracks.size()
	_last = index
	_player.stream = tracks[index]
	_player.volume_db = -80.0
	_player.play()


func _on_track_finished() -> void:
	if _running:
		_silence_left = SILENCE
