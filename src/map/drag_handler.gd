class_name DragHandler
extends Node
## Handles drag-and-drop movement for the active unit's pawn.
## Uses _input() (not _unhandled_input) to guarantee mouse-release capture
## even when the cursor is over HUD panels.
## Enabled only during BattleController.ACTION_SELECT state.
##
## Dropping a pawn on a valid tile creates a *preview* — the move is not
## committed until the controller calls confirm_preview(). The controller
## may also call cancel_preview() to snap the pawn back.

signal drag_move_requested(destination: Vector2i)
signal drag_cancelled()

const DRAG_THRESHOLD_PX := 8.0
const INVALID_COORD := Vector2i(-999, -999)

var _camera: Camera3D
var _state: MatchState
var _pawn_manager: PawnManager

# Drag tracking
var _enabled := false
var _pressing := false
var _drag_started := false
var _press_screen_pos: Vector2 = Vector2.ZERO
var _drag_unit: BattleUnit = null
var _drag_pawn: UnitPawn = null
var _original_coord: Vector2i = INVALID_COORD
var _original_world_pos: Vector3 = Vector3.ZERO
var _current_hover: Vector2i = INVALID_COORD
var _reachable: Dictionary = {}

# Preview persistence — retained after a valid drop so cancel/confirm can act
var _preview_active := false
var _preview_coord: Vector2i = INVALID_COORD
var _preview_original_coord: Vector2i = INVALID_COORD
var _preview_original_world_pos: Vector3 = Vector3.ZERO
var _preview_pawn: UnitPawn = null


func setup(camera: Camera3D, state: MatchState, pawn_mgr: PawnManager) -> void:
	_camera = camera
	_state = state
	_pawn_manager = pawn_mgr


func set_enabled(on: bool) -> void:
	_enabled = on
	if not on and _pressing:
		_cancel_drag()
		_reset()


func is_dragging() -> bool:
	return _drag_started


func has_pending_preview() -> bool:
	return _preview_active


func cancel_preview() -> void:
	## Snap pawn back to original position and clear preview state.
	if _preview_active and _preview_pawn:
		_preview_pawn.position = _preview_original_world_pos
	_clear_preview()


func confirm_preview() -> void:
	## Clear preview state without moving pawn (it's already at destination).
	_clear_preview()


func _input(event: InputEvent) -> void:
	if not _enabled or not _camera:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_press(mb.position)
			else:
				_on_release(mb.position)

	elif event is InputEventMouseMotion and _pressing:
		_on_motion(event.position)


func _on_press(screen_pos: Vector2) -> void:
	var unit := _state.current_unit
	if not unit or unit.ap_remaining < 1:
		return

	var hit_coord := _raycast_tile(screen_pos)

	# If a preview is active and the player clicks on the preview tile or
	# original tile, cancel the preview and allow a fresh re-drag.
	if _preview_active:
		if hit_coord == _preview_coord or hit_coord == _preview_original_coord:
			cancel_preview()
			# After cancelling, the pawn is back at unit.position
		else:
			return  # Clicked elsewhere — not starting a drag

	if hit_coord != unit.position:
		return

	var pawn := _pawn_manager.get_pawn(unit)
	if not pawn:
		return

	_pressing = true
	_drag_started = false
	_press_screen_pos = screen_pos
	_drag_unit = unit
	_drag_pawn = pawn
	_original_coord = unit.position
	_original_world_pos = pawn.position
	_current_hover = INVALID_COORD

	# Precompute valid move destinations (tier1 only, filtered for occupancy)
	var move: int = unit.stats.effective_move()
	var jump: int = unit.stats.effective("jump")
	_reachable = Movement.reachable(_state.graph, unit.position, move, jump)
	for pos in _state.occupancy.keys():
		if pos != unit.position and _reachable.has(pos):
			_reachable.erase(pos)


func _on_motion(screen_pos: Vector2) -> void:
	if not _pressing or not _drag_pawn:
		return

	if not _drag_started:
		if screen_pos.distance_to(_press_screen_pos) < DRAG_THRESHOLD_PX:
			return
		_drag_started = true

	# Consume event so TilePicker and other handlers don't see it
	get_viewport().set_input_as_handled()

	var hover_coord := _raycast_tile(screen_pos)
	if hover_coord == _current_hover:
		return
	_current_hover = hover_coord

	if _reachable.has(hover_coord):
		_drag_pawn.place(hover_coord, _state.graph)
	else:
		_snap_to_cursor(screen_pos)


func _on_release(screen_pos: Vector2) -> void:
	if not _pressing:
		return

	if _drag_started:
		get_viewport().set_input_as_handled()
		var drop_coord := _raycast_tile(screen_pos)
		if _reachable.has(drop_coord) and drop_coord != _original_coord:
			# Store preview state before resetting drag tracking
			_preview_active = true
			_preview_coord = drop_coord
			_preview_original_coord = _original_coord
			_preview_original_world_pos = _original_world_pos
			_preview_pawn = _drag_pawn
			# Reset drag state BEFORE emitting so the signal handler's
			# set_enabled(false) won't see _pressing==true and call _cancel_drag().
			_reset()
			drag_move_requested.emit(drop_coord)
			return
		else:
			_cancel_drag()
			drag_cancelled.emit()

	_reset()


func _raycast_tile(screen_pos: Vector2) -> Vector2i:
	var space := _camera.get_world_3d().direct_space_state
	if not space:
		return INVALID_COORD
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var to := from + dir * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := space.intersect_ray(query)
	if result.is_empty():
		return INVALID_COORD
	var tile := HexTile.tile_from_collider(result["collider"])
	if tile:
		return tile.coord()
	return INVALID_COORD


func _snap_to_cursor(screen_pos: Vector2) -> void:
	## Project cursor onto the Y-plane at the pawn's original height,
	## giving a "floating along with cursor" feel over invalid tiles.
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var plane_y := _original_world_pos.y
	if absf(dir.y) < 0.001:
		return
	var t := (plane_y - from.y) / dir.y
	if t < 0.0:
		return
	var world_pos := from + dir * t
	_drag_pawn.position = Vector3(world_pos.x, plane_y, world_pos.z)


func _cancel_drag() -> void:
	if _drag_pawn:
		_drag_pawn.position = _original_world_pos


func _reset() -> void:
	_pressing = false
	_drag_started = false
	_drag_unit = null
	_drag_pawn = null
	_original_coord = INVALID_COORD
	_original_world_pos = Vector3.ZERO
	_current_hover = INVALID_COORD
	_reachable = {}


func _clear_preview() -> void:
	_preview_active = false
	_preview_coord = INVALID_COORD
	_preview_original_coord = INVALID_COORD
	_preview_original_world_pos = Vector3.ZERO
	_preview_pawn = null
