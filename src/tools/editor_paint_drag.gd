class_name EditorPaintDrag
extends Node
## Lightweight drag handler for editor paint strokes.
## Detects click-drag across hex tiles and emits tile_painted for each
## new tile entered. Uses _input() for priority over TilePicker.

signal drag_started()
signal tile_painted(coord: Vector2i)
signal drag_ended()

var _camera: Camera3D
var _enabled := true
var _pressing := false
var _drag_started := false
var _press_screen_pos: Vector2 = Vector2.ZERO
var _last_painted: Vector2i = Vector2i(-999, -999)
const DRAG_THRESHOLD_PX := 4.0
const INVALID_COORD := Vector2i(-999, -999)


func setup(camera: Camera3D) -> void:
	_camera = camera


func set_enabled(on: bool) -> void:
	_enabled = on
	if not on:
		_pressing = false
		_drag_started = false


func is_dragging() -> bool:
	return _drag_started


func _input(event: InputEvent) -> void:
	if not _enabled or not _camera:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressing = true
				_drag_started = false
				_press_screen_pos = mb.position
				_last_painted = INVALID_COORD
			else:
				if _drag_started:
					drag_ended.emit()
				_pressing = false
				_drag_started = false
	elif event is InputEventMouseMotion and _pressing:
		if not _drag_started:
			if event.position.distance_to(_press_screen_pos) < DRAG_THRESHOLD_PX:
				return
			_drag_started = true
			drag_started.emit()
			# Paint the initial press position too
			var first_coord := _raycast_tile(_press_screen_pos)
			if first_coord != INVALID_COORD:
				_last_painted = first_coord
				tile_painted.emit(first_coord)
				get_viewport().set_input_as_handled()
		# Paint current position if it's a new tile
		var coord := _raycast_tile(event.position)
		if coord != INVALID_COORD and coord != _last_painted:
			_last_painted = coord
			tile_painted.emit(coord)
			get_viewport().set_input_as_handled()


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
