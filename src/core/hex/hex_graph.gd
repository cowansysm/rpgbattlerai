class_name HexGraph
extends AStar3D
## Hex connectivity graph built on Godot AStar3D.
## One point per map tile; edges filtered by impassability and Jump/Climb.
## Terrain properties accessed through an injected provider (Callable),
## keeping the graph pure and testable with stubs.

var _id_of: Dictionary = {}       ## Vector2i -> int (AStar point id)
var _coord_of: Dictionary = {}    ## int -> Vector2i
var _elev: Dictionary = {}        ## Vector2i -> int
var _terrain: Dictionary = {}     ## Vector2i -> String (terrain id)
var _mover_jump: int = -1         ## Current Jump/Climb value for edges (-1 = unset)
var _terrain_provider: Callable   ## (String) -> TerrainProps — injected at build
var _edge_cache: Dictionary = {}  ## int (jump_climb) -> Array of [id_a, id_b] pairs


func build(map: MapData, terrain_provider: Callable) -> void:
	clear()
	_id_of.clear()
	_coord_of.clear()
	_elev.clear()
	_terrain.clear()
	_edge_cache.clear()
	_mover_jump = -1
	_terrain_provider = terrain_provider
	var next_id := 0
	for t: TileRecord in map.tiles:
		var c := t.coord()
		add_point(next_id, Vector3(c.x, t.elevation, c.y))
		_id_of[c] = next_id
		_coord_of[next_id] = c
		_elev[c] = t.elevation
		_terrain[c] = t.terrain
		next_id += 1


# --- Accessors ---

func elevation(c: Vector2i) -> int:
	return int(_elev.get(c, 0))


func terrain_id(c: Vector2i) -> String:
	return str(_terrain.get(c, "grass"))


func terrain_props(c: Vector2i) -> TerrainProps:
	return _terrain_provider.call(terrain_id(c))


func has_tile(c: Vector2i) -> bool:
	return _id_of.has(c)


func id_of(c: Vector2i) -> int:
	return int(_id_of.get(c, -1))


func coord_of(id: int) -> Vector2i:
	return _coord_of.get(id, Vector2i.ZERO)


func is_impassable(c: Vector2i) -> bool:
	return terrain_props(c).impassable


func move_cost(c: Vector2i) -> int:
	return terrain_props(c).move_cost


func tile_count() -> int:
	return _id_of.size()


# --- Per-mover edge connection (cached) ---

func set_mover(jump_climb: int) -> void:
	if _mover_jump == jump_climb:
		return
	_mover_jump = jump_climb
	if _edge_cache.has(jump_climb):
		_apply_cached_edges(jump_climb)
	else:
		_reconnect()
		_cache_current_edges(jump_climb)


func invalidate_cache() -> void:
	_edge_cache.clear()


func _reconnect() -> void:
	_disconnect_all()
	# Reconnect valid edges.
	for c in _id_of.keys():
		for nb in Hex.neighbors(c):
			if not _id_of.has(nb):
				continue
			if _edge_valid(c, nb):
				connect_points(_id_of[c], _id_of[nb], false)


func _edge_valid(from_c: Vector2i, to_c: Vector2i) -> bool:
	if is_impassable(to_c):
		return false
	return absi(elevation(to_c) - elevation(from_c)) <= _mover_jump


func _cache_current_edges(jump: int) -> void:
	var edges: Array = []
	for id in _coord_of.keys():
		for nb_id in get_point_connections(id):
			edges.append([id, nb_id])
	_edge_cache[jump] = edges


func _apply_cached_edges(jump: int) -> void:
	_disconnect_all()
	for pair in _edge_cache[jump]:
		connect_points(pair[0], pair[1], false)


func _disconnect_all() -> void:
	for id in _coord_of.keys():
		for nb_id in get_point_connections(id):
			disconnect_points(id, nb_id, false)


# --- AStar3D cost overrides ---

func _compute_cost(from_id: int, to_id: int) -> float:
	return float(move_cost(_coord_of[to_id]))


func _estimate_cost(from_id: int, to_id: int) -> float:
	return float(Hex.distance(_coord_of[from_id], _coord_of[to_id]))
