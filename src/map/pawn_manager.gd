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
	spawn_all(state)


func spawn_all(state: MatchState) -> void:
	for team in state.parties.keys():
		for unit: BattleUnit in state.parties[team]:
			if unit.current_hp > 0 or unit.is_downed:
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


func sync_pawn_position(unit: BattleUnit, coord: Vector2i) -> void:
	## Snap pawn to precise hex position after a drag-move.
	## The pawn is already visually close; this ensures pixel-perfect alignment.
	var pawn: UnitPawn = _pawns.get(unit)
	if pawn:
		pawn.place(coord, _graph)


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
		marker.position = Vector3(float(i) * 0.18, 0.25, 0.0)
		pawn.add_child(marker)
		markers.append(marker)
	if not markers.is_empty():
		_markers[unit] = markers


func _clear_markers(unit: BattleUnit) -> void:
	if _markers.has(unit):
		for marker in _markers[unit]:
			if is_instance_valid(marker):
				marker.queue_free()
		_markers.erase(unit)


func pawn_count() -> int:
	return _pawns.size()
