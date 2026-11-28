class_name NelvarPaintQueue
extends RefCounted
## A map's art painted on worker threads while it loads, and on after. The jobs the first
## frame needs (urgent ones: the floor's maps, and whatever lies within `reach` of the start)
## are painted first, with nothing else beside them: GDScript threads slow each other down,
## so the rest waits. Then the rest, nearest first, while the game runs.
##
## Usage: add() every job, start(), wait() in _ready(); lay_in() every frame; stop() when
## the map is left. `paint` (job) -> result runs on the painters, `lay` (job, result, late)
## on the main thread as the results come in (late: the first frame is out, so the art should
## fade in). A job laid in may queue another with then() (a big picture's finishing once its
## bands are in): it counts as urgent if the job that queued it did.

## Painters: one a physical core, more slow each other down (see NelvarEarthPainter).
static var threads := clampi(OS.get_processor_count() >> 1, 2, 12)

var _paint: Callable
var _lay: Callable
var _name: String
## [sort key, job] until start(): urgent ones key -1.
var _pending: Array = []
var _later: Array = []
var _later_started := false
## The group task running and its jobs (read by the painters, fixed while it runs).
var _group := -1
var _group_jobs: Array = []
var _group_urgent := false
var _group_left := 0
## Follow-ups running: token -> task id.
var _tasks := {}
var _token := 0
## Finished on the painters, not laid in yet: [job, result, urgent, token or -1].
var _done: Array = []
var _lock := Mutex.new()
## Not laid in yet: all, the urgent ones.
var _left := 0
var _wanted := 0
var _laying_urgent := false
var _stop := false


func _init(paint: Callable, lay: Callable, name: String) -> void:
	_paint = paint
	_lay = lay
	_name = name


## `distance`: how far from the start it shows (the nearest are painted first).
func add(job: Variant, distance: float, urgent: bool = false) -> void:
	_pending.append([-1.0 if urgent else maxf(distance, 0.0), job])


## Starts painting the urgent jobs and those within `reach` of the start.
func start(reach: float) -> void:
	_pending.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var now: Array = []
	for entry: Array in _pending:
		if entry[0] < reach:
			now.append(entry[1])
		else:
			_later.append(entry[1])
	_pending.clear()
	_left = now.size() + _later.size()
	_wanted = now.size()
	_run(now, true)
	_advance()


## Lays in results until the urgent jobs are all in (the rest goes on painting).
func wait() -> void:
	while _wanted > 0:
		lay_in()
		if _wanted > 0:
			OS.delay_usec(500)


## Lays in results until everything is in (the tests).
func finish() -> void:
	while _left > 0:
		lay_in()
		if _left > 0:
			OS.delay_usec(1000)


func busy() -> bool:
	return _left > 0


## On the main thread, from `lay`: one more job, painted as soon as a painter is free.
func then(job: Variant) -> void:
	_left += 1
	if _laying_urgent:
		_wanted += 1
	_token += 1
	_tasks[_token] = WorkerThreadPool.add_task(_follow.bind(job, _laying_urgent, _token), true, _name)


## Lays in what the painters have finished since the last call (main thread).
func lay_in() -> void:
	_lock.lock()
	var done := _done
	_done = []
	_lock.unlock()
	for entry: Array in done:
		_left -= 1
		if entry[2]:
			_wanted -= 1
		if entry[3] >= 0:
			WorkerThreadPool.wait_for_task_completion(_tasks[entry[3]])
			_tasks.erase(entry[3])
		else:
			_group_left -= 1
		_laying_urgent = entry[2]
		_lay.call(entry[0], entry[1], not entry[2])
	_laying_urgent = false
	_advance()


## Leaving: the painters drop what is left; returns once none of them runs.
func stop() -> void:
	_stop = true
	if _group >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_group)
		_group = -1
	for task: int in _tasks.values():
		WorkerThreadPool.wait_for_task_completion(task)
	_tasks.clear()
	_left = 0
	_wanted = 0


## The urgent group done: the rest starts.
func _advance() -> void:
	if _group >= 0 and _group_left == 0:
		WorkerThreadPool.wait_for_group_task_completion(_group)
		_group = -1
	if _group < 0 and _wanted == 0 and not _later_started:
		_later_started = true
		_run(_later, false)
		_later = []


func _run(jobs: Array, urgent: bool) -> void:
	if jobs.is_empty():
		return
	_group_jobs = jobs
	_group_urgent = urgent
	_group_left = jobs.size()
	_group = WorkerThreadPool.add_group_task(_paint_group, jobs.size(), threads, true, _name)


func _paint_group(index: int) -> void:
	if _stop:
		return
	var job: Variant = _group_jobs[index]
	var result: Variant = _paint.call(job)
	_lock.lock()
	_done.append([job, result, _group_urgent, -1])
	_lock.unlock()


func _follow(job: Variant, urgent: bool, token: int) -> void:
	if _stop:
		return
	var result: Variant = _paint.call(job)
	_lock.lock()
	_done.append([job, result, urgent, token])
	_lock.unlock()
