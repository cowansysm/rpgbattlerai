extends RefCounted
## Shared, process-cached full-content DataPipeline for tests.
##
## WHY: loading `res://data` allocates well over a thousand Resource objects
## (790 abilities, 268 classes, 160 characters, 128 items, ...). Doing that
## fresh at ~16 call sites churns the native heap enough to surface a
## pre-existing engine heap-corruption abort at full-content scale. Loading
## ONCE per process removes that churn.
##
## READ-ONLY CONTRACT — how "clean starting state per test" is guaranteed:
##   Authored data is immutable post-load (RaceData/ClassData/AbilityData/
##   ItemData/CharacterData and the derived StatBlocks). Every test that touches
##   the shared pipeline treats it as read-only, so the data can never drift from
##   its loaded starting state — each test sees exactly the pristine content a
##   fresh `DataPipeline.run()` would have produced. Per-test mutable state lives
##   on objects the test owns: `BattleUnit.from_character()` duplicates the
##   StatBlock at creation, and tests that need custom characters/classes build
##   their own `*.new()` instances rather than mutating shared Resources.
##
##   DO NOT mutate any Resource returned by the shared pipeline (e.g. never assign
##   to `get_character(id).abilities`); that would leak state across tests. If a
##   test genuinely needs an isolated, mutable pipeline, call reset() in its
##   before_each to force a fresh load for that script.

static var _pipeline: DataPipeline = null
static var _load_errors: Array = []


## Returns the shared full-content pipeline, loading it once per process.
static func get_pipeline() -> DataPipeline:
	if _pipeline == null:
		_pipeline = DataPipeline.new()
		_load_errors = _pipeline.run("res://data")
		if not _load_errors.is_empty():
			push_error("SharedPipeline: full-content load errors: %s" % str(_load_errors))
	return _pipeline


## Errors from the (cached) full-content load; empty on a clean boot.
static func load_errors() -> Array:
	get_pipeline()
	return _load_errors


## Drops the cache so the next get_pipeline() reloads from disk. Use only when a
## test truly needs isolation from the shared instance.
static func reset() -> void:
	_pipeline = null
	_load_errors = []
