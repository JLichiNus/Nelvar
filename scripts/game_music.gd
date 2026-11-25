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
## Game scenes call start() when they open, the main menu calls stop().

## Tracks to pick from; add new ones here.
const PLAYLIST: Array[AudioStream] = [
	preload("res://assets/audio/music/game/odd_meter_arpeggio.mp3"),
]
const FADE_IN := 4.0
const FADE_OUT := 6.0
## Seconds of silence between two tracks.
const SILENCE := 30.0
## Fade when the run is left for the menu.
const STOP_FADE := 1.5
## Volume of a track at full level. The music sits under the sound effects;
## the player sets the overall music volume in the settings (bus "Music").
const VOLUME_DB := -19.0

var _player: AudioStreamPlayer
var _running := false
var _silence_left := 0.0
var _last := -1
var _stop_tween: Tween


func _ready() -> void:
	# Keeps playing in the pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	_player.volume_db = -80.0
	add_child(_player)
	_player.finished.connect(_on_track_finished)


## A run began: play music unless it already plays (a restart after death).
## Headless runs (the tests) have no sound, so they get no music either.
func start() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _stop_tween != null:
		_stop_tween.kill()
		_stop_tween = null
	if _running:
		return
	_running = true
	_play_next()


## The run is over (back to the menu): fade the music out and stay silent.
func stop() -> void:
	if not _running:
		return
	_running = false
	_silence_left = 0.0
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
	if not _running:
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
	if PLAYLIST.is_empty():
		return
	var index := randi_range(0, PLAYLIST.size() - 1)
	if PLAYLIST.size() > 1 and index == _last:
		index = (index + randi_range(1, PLAYLIST.size() - 1)) % PLAYLIST.size()
	_last = index
	_player.stream = PLAYLIST[index]
	_player.volume_db = -80.0
	_player.play()


func _on_track_finished() -> void:
	if _running:
		_silence_left = SILENCE
