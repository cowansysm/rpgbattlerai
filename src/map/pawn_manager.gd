class_name PawnManager
extends Node
## Manages the set of all UnitPawns on the map. Provides a clean interface
## for the controller to spawn, move, remove, and highlight pawns.
## Pull-based sync — controller calls methods explicitly after TurnActions.
## Spec reference: phase8-spec.md §3.3

var _pawns: Dictionary = {}   # BattleUnit -> UnitPawn
var _markers: Dictionary = {}  # BattleUnit -> Array[StatusMarker]
var _graph: HexGraph


func setup(state: MatchState, graph: HexGraph) -> void:
	_graph = graph
	# Skip spawning if in deployment phase (pawns will be spawned individually)
	if state.phase != MatchState.Phase.DEPLOYMENT:
		spawn_all(state)


func spawn_all(state: MatchState) -> void:
	for team in state.parties.keys():
		for unit: BattleUnit in state.parties[team]:
			if unit.current_hp > 0 or unit.is_downed:
				spawn_pawn(unit)


func spawn_pawn(unit: BattleUnit) -> void:
	if _pawns.has(unit):
		return  # Already spawned
	var pawn := UnitPawn.new()
	pawn.setup(unit, _graph)
	if unit.is_downed:
		pawn.rotation_degrees.x = 180.0
	add_child(pawn)
	_pawns[unit] = pawn


func move_pawn(unit: BattleUnit, to: Vector2i) -> Tween:
	var pawn: UnitPawn = _pawns.get(unit)
	if not pawn:
		return null
	return pawn.move_to(to, _graph)


func remove_pawn(unit: BattleUnit) -> void:
	var pawn: UnitPawn = _pawns.get(unit)
	if pawn:
		pawn.remove()
		_pawns.erase(unit)


func down_pawn(unit: BattleUnit) -> Tween:
	var pawn: UnitPawn = _pawns.get(unit)
	if pawn:
		return pawn.set_downed(true)
	return null


func revive_pawn(unit: BattleUnit) -> Tween:
	var pawn: UnitPawn = _pawns.get(unit)
	if pawn:
		return pawn.set_downed(false)
	return null


func highlight_active(unit: BattleUnit) -> void:
	for u in _pawns.keys():
		var p: UnitPawn = _pawns[u]
		p.set_active(u == unit)


func clear_highlight() -> void:
	for pawn: UnitPawn in _pawns.values():
		pawn.set_active(false)


func highlight_selectable(units: Array) -> void:
	for u in _pawns.keys():
		var p: UnitPawn = _pawns[u]
		p.set_active(u in units)


func get_pawn(unit: BattleUnit) -> UnitPawn:
	return _pawns.get(unit)


func has_pawn(unit: BattleUnit) -> bool:
	return _pawns.has(unit)


func sync_pawn_position(unit: BattleUnit, coord: Vector2i) -> void:
	## Snap pawn to precise hex position after a drag-move.
	## The pawn is already visually close; this ensures pixel-perfect alignment.
	var pawn: UnitPawn = _pawns.get(unit)
	if pawn:
		pawn.place(coord, _graph)


## A19: Update the facing chevron on a unit's pawn to match unit.facing.
func update_facing(unit: BattleUnit) -> void:
	var pawn: UnitPawn = _pawns.get(unit)
	if pawn:
		pawn.set_facing(unit.facing)


func update_status_markers(unit: BattleUnit) -> void:
	## Refresh status effect billboard markers above a unit's pawn.
	## Called by the controller after any action that may change statuses.
	_clear_markers(unit)
	var pawn: UnitPawn = _pawns.get(unit)
	if not pawn:
		return
	var markers: Array = []
	for i in range(unit.status_effects.size()):
		var s: Dictionary = unit.status_effects[i]
		var marker := StatusMarker.create(s["id"])
		marker.position = Vector3(float(i) * 0.135, 0.125, 0.0)
		pawn.add_child(marker)
		markers.append(marker)
	if not markers.is_empty():
		_markers[unit] = markers


func show_ability_pawns(targets: Array, icon_id: String) -> void:
	## Spawn physics-dropped symbol pawns beside each target and await landing.
	## Blocks until all pawns land or the max-wait timeout expires.
	## Skips silently in headless/test contexts (no scene tree).
	if targets.is_empty():
		return
	if not is_inside_tree():
		return

	var offset_dist: float = float(Constants.get_value("SYMBOL_PAWN_OFFSET", 0.5))
	var spawn_height: float = float(Constants.get_value("SYMBOL_PAWN_SPAWN_HEIGHT", 4.0))
	var max_wait: float = float(Constants.get_value("SYMBOL_PAWN_MAX_LAND_WAIT", 0.8))

	var pending_count: int = 0
	var all_landed: bool = false

	for target in targets:
		if not target is BattleUnit:
			continue
		var unit: BattleUnit = target as BattleUnit
		if not has_pawn(unit):
			continue

		# Compute world position of target's tile
		var elev: int = _graph.elevation(unit.position)
		var world_pos := HexWorld.hex_to_world(unit.position.x, unit.position.y, elev)
		var surface_y: float = world_pos.y + TileMesh.TILE_HEIGHT * 0.5

		# Offset beside the target (consistent +X direction)
		var spawn_pos := Vector3(
			world_pos.x + offset_dist,
			surface_y + spawn_height,
			world_pos.z)

		var pawn := AbilitySymbolPawn.create(icon_id, surface_y)
		pawn.position = spawn_pos
		add_child(pawn)
		pawn.setup_landing_collider(self, world_pos)

		pending_count += 1
		pawn.landed.connect(func() -> void:
			pending_count -= 1
			if pending_count <= 0:
				all_landed = true)

	if pending_count <= 0:
		return

	# Wait for all pawns to land or timeout
	var elapsed: float = 0.0
	while not all_landed and elapsed < max_wait:
		await get_tree().create_timer(0.05).timeout
		elapsed += 0.05


func show_dice_roll(unit: BattleUnit, value: int, is_attack: bool) -> void:
	## Spawn a drop-in dice above the unit's pawn. Fire-and-forget.
	## Positioned above the symbol pawn drop area (y=0.55) so dice are
	## not obscured. Attack rolls slightly left, defense rolls slightly right.
	var pawn: UnitPawn = _pawns.get(unit)
	if not pawn:
		return
	var marker := DiceMarker.create(value, is_attack)
	var x_offset := -0.06 if is_attack else 0.06
	marker.position = pawn.position + Vector3(x_offset, 0.275, 0.0)
	add_child(marker)
	marker.play()


func _clear_markers(unit: BattleUnit) -> void:
	if _markers.has(unit):
		for marker in _markers[unit]:
			if is_instance_valid(marker):
				marker.queue_free()
		_markers.erase(unit)


func pawn_count() -> int:
	return _pawns.size()
