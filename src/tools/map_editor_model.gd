class_name MapEditorModel
extends RefCounted
## Headless map editor state and mutation logic.
## No scene-tree dependency. Fully unit-testable.
## The editor scene is a thin controller that renders this model.

var id: String = "untitled"
var tier: String = "standard"
var tiles: Dictionary = {}       # Vector2i -> {"elevation": int, "terrain": String, "tags": Array[String]}
var zones: Dictionary = {}       # String -> Array[Vector2i]

var _undo: Array = []
var _redo: Array = []
var _batch_active := false
const MAX_UNDO := 50
const MIN_ELEVATION := -5
const MAX_ELEVATION := 10
const MAX_TILES := 255


# --- Snapshot helpers ---

func _snapshot() -> void:
	if _batch_active:
		return
	_undo.push_back(_capture())
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()


func _capture() -> Dictionary:
	return {"id": id, "tier": tier, "tiles": tiles.duplicate(true), "zones": _deep_copy_zones()}


func _restore(s: Dictionary) -> void:
	id = s["id"]
	tier = s["tier"]
	tiles = s["tiles"]
	zones = s["zones"]


func _deep_copy_zones() -> Dictionary:
	var out: Dictionary = {}
	for z: String in zones.keys():
		out[z] = zones[z].duplicate()
	return out


# --- Mutations (each snapshots before mutating) ---

func set_terrain(coord: Vector2i, terrain: String) -> void:
	if not tiles.has(coord):
		return
	_snapshot()
	tiles[coord]["terrain"] = terrain


func set_elevation(coord: Vector2i, value: int) -> void:
	if not tiles.has(coord):
		return
	_snapshot()
	tiles[coord]["elevation"] = clampi(value, MIN_ELEVATION, MAX_ELEVATION)


func adjust_elevation(coord: Vector2i, delta: int) -> void:
	if not tiles.has(coord):
		return
	set_elevation(coord, int(tiles[coord]["elevation"]) + delta)


func add_tile(coord: Vector2i, terrain: String = "grass", elevation: int = 0) -> void:
	if tiles.has(coord):
		return
	if tiles.size() >= MAX_TILES:
		return
	_snapshot()
	var tags: Array[String] = []
	tiles[coord] = {"elevation": elevation, "terrain": terrain, "tags": tags}


func remove_tile(coord: Vector2i) -> void:
	if not tiles.has(coord):
		return
	_snapshot()
	tiles.erase(coord)
	for z: String in zones.keys():
		zones[z].erase(coord)


func set_zone(coord: Vector2i, zone_name: String, on: bool) -> void:
	if on and not tiles.has(coord):
		return
	_snapshot()
	if not zones.has(zone_name):
		var arr: Array[Vector2i] = []
		zones[zone_name] = arr
	if on and not zones[zone_name].has(coord):
		zones[zone_name].append(coord)
	elif not on:
		zones[zone_name].erase(coord)


func set_metadata(new_id: String, new_tier: String) -> void:
	_snapshot()
	id = new_id
	tier = new_tier


func clear_zone(zone_name: String) -> void:
	_snapshot()
	if zones.has(zone_name):
		zones[zone_name].clear()


# --- New map generation ---

func new_map(new_id: String, new_tier: String, shape: String, size: int) -> void:
	_undo.clear()
	_redo.clear()
	_batch_active = false
	id = new_id
	tier = new_tier
	tiles.clear()
	zones.clear()
	if shape == "hex":
		var radius := (size - 1) / 2
		for coord: Vector2i in Hex.hexes_in_range(Vector2i.ZERO, radius):
			var tags: Array[String] = []
			tiles[coord] = {"elevation": 0, "terrain": "grass", "tags": tags}
	else:
		# Rectangular grid: offset-to-axial for flat-top hexes
		for col in range(size):
			for row in range(size):
				var q := col
				var r := row - col / 2
				var coord := Vector2i(q, r)
				var tags: Array[String] = []
				tiles[coord] = {"elevation": 0, "terrain": "grass", "tags": tags}


# --- Undo / Redo ---

func undo() -> bool:
	if _undo.is_empty():
		return false
	_redo.push_back(_capture())
	_restore(_undo.pop_back())
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.push_back(_capture())
	_restore(_redo.pop_back())
	return true


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


# --- Batch (coalesce drag strokes into one undo entry) ---

func begin_batch() -> void:
	if not _batch_active:
		_undo.push_back(_capture())
		if _undo.size() > MAX_UNDO:
			_undo.pop_front()
		_redo.clear()
		_batch_active = true


func end_batch() -> void:
	_batch_active = false


# --- Conversion to/from MapData ---

func to_map_data() -> MapData:
	var m := MapData.new()
	m.id = id
	m.tier = tier
	var recs: Array[TileRecord] = []
	for c: Vector2i in tiles.keys():
		var t: Dictionary = tiles[c]
		var tags: Array[String] = []
		tags.assign(t.get("tags", []))
		recs.append(TileRecord.new(c.x, c.y, int(t["elevation"]), str(t["terrain"]), tags))
	m.tiles = recs
	var dz: Dictionary = {}
	for z: String in zones.keys():
		var arr: Array = []
		for c: Vector2i in zones[z]:
			arr.append("%d,%d" % [c.x, c.y])
		dz[z] = arr
	m.deployment_zones = dz
	return m


func from_map_data(m: MapData) -> void:
	_undo.clear()
	_redo.clear()
	_batch_active = false
	id = m.id
	tier = m.tier
	tiles.clear()
	zones.clear()
	for t: TileRecord in m.tiles:
		var tags: Array[String] = []
		tags.assign(t.tags)
		tiles[t.coord()] = {"elevation": t.elevation, "terrain": t.terrain, "tags": tags}
	for z: String in m.deployment_zones.keys():
		var arr: Array[Vector2i] = []
		for s in m.deployment_zones[z]:
			var parts := str(s).split(",")
			arr.append(Vector2i(int(parts[0]), int(parts[1])))
		zones[z] = arr


# --- Validation ---

func validate() -> Array[String]:
	var errors: Array[String] = []
	if id.strip_edges().is_empty():
		errors.append("Map id is required")
	if tiles.is_empty():
		errors.append("Map has no tiles")
	for c: Vector2i in tiles.keys():
		var terrain_id: String = str(tiles[c]["terrain"])
		if not GameData.has_terrain(terrain_id):
			errors.append("Tile (%d,%d): unknown terrain '%s'" % [c.x, c.y, terrain_id])
	for z: String in zones.keys():
		for c: Vector2i in zones[z]:
			if not tiles.has(c):
				errors.append("Zone '%s' references missing tile (%d,%d)" % [z, c.x, c.y])
	return errors


# --- Convenience getters ---

func get_tile(coord: Vector2i) -> Dictionary:
	return tiles.get(coord, {})


func has_tile(coord: Vector2i) -> bool:
	return tiles.has(coord)


func tile_count() -> int:
	return tiles.size()
