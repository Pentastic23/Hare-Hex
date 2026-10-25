# preload.gd
class_name Preload

# Background loading, so starting a run doesn't wait on the disk. The main menu calls warm_run() once
# it is on screen: the run scene (and the scripts it compiles), every unit model, the portraits, item
# icons and tile textures are then loaded on worker threads while the player looks at the menu.
# scene() hands a scene over when it's needed (waiting for the rest only if it isn't done yet), and a
# plain load() of anything warmed here returns the cached copy at once. collect() picks up finished
# loads; the menu calls it every frame.

const RUN_SCENE := "res://scenes/main.tscn"
const DIRS := ["res://scenes/models", "res://textures/ui/portraits", "res://textures/ui/items"]
const TILE_DIR := "res://textures/tiles"

static var _pending := {}   # path -> true while a threaded load is in flight
static var _held := {}      # path -> resource: Godot's cache only keeps what is referenced, so this holds them

# Starts loading what a run needs. Safe to call again: it skips what's loaded or already on its way.
static func warm_run() -> void:
	request(RUN_SCENE)
	for dir in DIRS:
		for f in ResourceLoader.list_directory(dir):
			if f.ends_with(".tscn") or f.ends_with(".png"):
				request(dir.path_join(f))
	for theme in ResourceLoader.list_directory(TILE_DIR):
		if theme.ends_with("/"):
			for f in ResourceLoader.list_directory(TILE_DIR.path_join(theme)):
				if f.ends_with(".png"):
					request(TILE_DIR.path_join(theme).path_join(f))

static func request(path: String) -> void:
	if _pending.has(path) or _held.has(path) or not ResourceLoader.exists(path):
		return
	if ResourceLoader.has_cached(path):
		_held[path] = load(path)   # already loaded: just keep it
		return
	if ResourceLoader.load_threaded_request(path) == OK:
		_pending[path] = true

# A scene, from the background load when there is one (waiting for it if it isn't finished), else loaded now.
static func scene(path: String) -> PackedScene:
	if _pending.has(path):
		_pending.erase(path)
		var res := ResourceLoader.load_threaded_get(path)
		if res != null:
			_held[path] = res
		if res is PackedScene:
			return res
	return load(path) as PackedScene

# Hands finished loads to the cache (a threaded load is only released once it is fetched).
static func collect() -> void:
	for path in _pending.keys():
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_pending.erase(path)
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				_held[path] = ResourceLoader.load_threaded_get(path)

static func busy() -> bool:
	return not _pending.is_empty()

static func is_ready(path: String) -> bool:
	return ResourceLoader.has_cached(path) or (_pending.has(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED)
