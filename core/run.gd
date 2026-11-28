class_name NelvarRun
extends RefCounted
## The run: everything about the Wanderer that lasts from «Играть» until death or the
## main menu, whichever location they are in (NelvarRunState). Locations come and go;
## the player and the mutation director in each of them take the run's state when they
## appear and change it in place, so leaving a location loses nothing.
##
## A location opened on its own (F6 in the editor, a test) has no run going: its player
## gets a state of its own that ends with the scene. The first death there starts a
## run, so the Void's checkpoint works the same way.
##
## A static holder rather than an autoload: player.tscn is preloaded by tests before
## autoloads exist, and the run needs no node of its own.

static var _active: NelvarRunState


## «Играть»: a new run, whatever was going before.
static func begin() -> NelvarRunState:
	_active = NelvarRunState.new()
	return _active


## The main menu: no run is going any more.
static func end() -> void:
	_active = null


static func is_active() -> bool:
	return _active != null


## The run going now; null when there is none.
static func current() -> NelvarRunState:
	return _active


## The state a new player takes: the run's, or a fresh one of its own when no run is
## going (see the class comment).
static func attach() -> NelvarRunState:
	return _active if _active != null else NelvarRunState.new()


## Death or /restart: the run starts over and the location reloads. Only the Void's
## checkpoint outlives it (`from`, the state that is over: the player's). Does nothing
## without a scene to reload (tests that add scenes by hand).
static func restart(tree: SceneTree, from: NelvarRunState = null) -> void:
	if tree.current_scene == null:
		return
	start_over(from)
	tree.reload_current_scene()


## The run after `from` (null: the one going) is over: a new one keeping only the
## Void's checkpoint. restart() without the reload.
static func start_over(from: NelvarRunState = null) -> NelvarRunState:
	var over := from if from != null else _active
	_active = NelvarRunState.new()
	if over != null:
		_active.void_checkpoint = over.void_checkpoint
	return _active
