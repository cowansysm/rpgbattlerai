class_name OverlayController
extends Node
## Paints movement (single-AP reach) and target (in-range + LoS) overlays
## on Phase 2 HexTile overlay layers. Pure presentation over authoritative
## spatial computations — holds no rules state.

var graph: HexGraph
var builder: MapBuilder

# Tiles currently painted by telegraph (tracked for selective clear)
var _telegraph_tiles: Array[Vector2i] = []
# 3D labels spawned for telegraph projections
var _telegraph_labels: Array[Node3D] = []


## Show single-AP movement overlay from start tile.
func show_movement(start: Vector2i, move: int, jump: int) -> void:
	clear()
	var reach := Movement.reachable(graph, start, move, jump)
	var mat1 := OverlayMaterials.move_tier1()
	for c in reach.keys():
		_paint(c, mat1)


## Show target overlay from origin with given range.
## min_range excludes hexes closer than the minimum (default 1 = no exclusion).
func show_targets(origin: Vector2i, radius: int, min_range: int = 1) -> void:
	clear()
	var mat_valid := OverlayMaterials.target_valid()
	var mat_blocked := OverlayMaterials.target_blocked()
	for c in RangeQuery.in_range(origin, radius, graph):
		if c == origin:
			continue
		if Hex.distance(origin, c) < min_range:
			continue
		if LineOfSight.has_los(graph, origin, c):
			_paint(c, mat_valid)
		else:
			_paint(c, mat_blocked)


## Show revive target overlay — highlights downed allies in range with LoS.
func show_revive_targets(origin: Vector2i, radius: int, state: MatchState, caster_team: String) -> void:
	clear()
	var mat := OverlayMaterials.revive_valid()
	for c in RangeQuery.in_range(origin, radius, graph):
		if c == origin:
			continue
		if not LineOfSight.has_los(graph, origin, c):
			continue
		var u: BattleUnit = state.unit_at(c)
		if u and u.is_downed and u.team == caster_team:
			_paint(c, mat)


## Show AoE shape preview from caster to target. Paints affected hexes.
func show_aoe_preview(caster_pos: Vector2i, target_pos: Vector2i, area: Dictionary) -> void:
	clear()
	var mat := OverlayMaterials.target_valid()
	var shape: String = str(area.get("shape", ""))
	var hexes: Array[Vector2i] = []

	match shape:
		"burst":
			var radius: int = int(area.get("radius", 0))
			hexes = Hex.hexes_in_range(target_pos, radius)
		"line":
			var length: int = int(area.get("length", 1))
			var direction: int = Hex.direction_toward(caster_pos, target_pos)
			hexes = Hex.line_in_direction(target_pos, direction, length)
		"cone":
			var depth: int = int(area.get("depth", 1))
			var direction: int = Hex.direction_toward(caster_pos, target_pos)
			hexes = Hex.cone_in_direction(target_pos, direction, depth)
		"ring":
			var radius: int = int(area.get("radius", 1))
			hexes = Hex.ring(target_pos, radius)

	for c in hexes:
		_paint(c, mat)


## Show selectable unit tiles (awaiting activation) — gold highlights.
func show_selectable(positions: Array) -> void:
	clear()
	var mat := OverlayMaterials.selectable()
	for pos in positions:
		_paint(pos, mat)


## Show telegraph intents on the map (A15 speed-round).
## Paints intent move destinations, paths, target tiles, and AoE footprints.
## mode: "full" — path + destination + target + AoE + projection labels
## mode: "targets" — target + AoE only
## mode: "off" — nothing rendered
func show_telegraph_intents(intents: Array, mode: String) -> void:
	clear_telegraph()
	if mode == "off":
		return

	var mat_path := OverlayMaterials.telegraph_path()
	var mat_dest := OverlayMaterials.telegraph_destination()
	var mat_target := OverlayMaterials.telegraph_target()
	var mat_aoe := OverlayMaterials.telegraph_aoe()

	for intent in intents:
		if not intent is IntentPlan:
			continue
		var ip: IntentPlan = intent

		# Full mode: show move path + destination
		if mode == "full" and ip.move_to != Vector2i.MAX:
			if ip.unit_ref and ip.move_to != ip.unit_ref.position:
				# Paint path tiles (skip current position)
				for tile in ip.path:
					if ip.unit_ref and tile != ip.unit_ref.position and tile != ip.move_to:
						_paint_telegraph(tile, mat_path)
				# Paint destination with distinct material
				_paint_telegraph(ip.move_to, mat_dest)

		# Both modes: show target hex
		if ip.target_pos != Vector2i.MAX:
			_paint_telegraph(ip.target_pos, mat_target)

		# Both modes: show AoE footprint
		for aoe_tile in ip.aoe_footprint:
			_paint_telegraph(aoe_tile, mat_aoe)

		# Full mode: show projection label at target position
		if mode == "full" and not ip.projection.is_empty() and ip.target_pos != Vector2i.MAX:
			_spawn_telegraph_label(ip.target_pos, ip.projection, ip.action_kind)


## Clear only telegraph-specific overlays and labels.
func clear_telegraph() -> void:
	for coord in _telegraph_tiles:
		if builder.tiles.has(coord):
			builder.tiles[coord].clear_overlay()
	_telegraph_tiles.clear()
	for label_node in _telegraph_labels:
		if is_instance_valid(label_node):
			label_node.queue_free()
	_telegraph_labels.clear()


## Clear all tile overlays (including telegraph).
func clear() -> void:
	for t in builder.tiles.values():
		t.clear_overlay()
	_telegraph_tiles.clear()
	for label_node in _telegraph_labels:
		if is_instance_valid(label_node):
			label_node.queue_free()
	_telegraph_labels.clear()


func _paint(c: Vector2i, mat: StandardMaterial3D) -> void:
	if builder.tiles.has(c):
		builder.tiles[c].set_overlay(mat)


func _paint_telegraph(c: Vector2i, mat: StandardMaterial3D) -> void:
	if builder.tiles.has(c):
		builder.tiles[c].set_overlay(mat)
		if c not in _telegraph_tiles:
			_telegraph_tiles.append(c)


func _spawn_telegraph_label(pos: Vector2i, projection: Dictionary, action_kind: String) -> void:
	## Spawn a floating 3D label above a tile showing the projection range.
	if not builder.tiles.has(pos):
		return
	var tile: HexTile = builder.tiles[pos]
	var label_3d := Label3D.new()
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.no_depth_test = true
	label_3d.font_size = 28
	label_3d.pixel_size = 0.005

	var min_v: int = int(projection.get("min", 0))
	var max_v: int = int(projection.get("max", 0))
	if action_kind == "ability":
		# Could be damage or heal — check if values suggest healing
		label_3d.text = "%d-%d" % [min_v, max_v]
	else:
		label_3d.text = "%d-%d" % [min_v, max_v]

	label_3d.modulate = Color(1.0, 0.85, 0.3, 0.9)
	label_3d.outline_modulate = Color(0, 0, 0, 0.8)
	label_3d.outline_size = 4

	# Position above the tile
	label_3d.position = tile.global_position + Vector3(0, 1.2, 0)
	add_child(label_3d)
	_telegraph_labels.append(label_3d)
