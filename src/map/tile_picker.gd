class_name TilePicker
extends Node
## Picks hex tiles via physics raycast from camera through cursor.
## Fires tile_selected on mouse RELEASE (not press) for drag compatibility.

signal tile_selected(coord: Vector2i)

var _camera: Camera3D
var _selected: HexTile = null
var _drag_handler: DragHandler = null


func setup(camera: Camera3D) -> void:
	_camera = camera


func set_drag_handler(handler: DragHandler) -> void:
	_drag_handler = handler


func _unhandled_input(event: InputEvent) -> void:
	if not _camera:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			# Fire on release; skip if DragHandler consumed this as a drag
			if _drag_handler and _drag_handler.is_dragging():
				return
			_pick(mb.position)


func _pick(screen_pos: Vector2) -> void:
	var space := _camera.get_world_3d().direct_space_state
	if not space:
		return
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var to := from + dir * 100.0

	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := space.intersect_ray(query)
	if result.is_empty():
		_deselect()
		return

	var collider: Node = result["collider"]
	var tile := HexTile.tile_from_collider(collider)
	if tile:
		_select(tile)
	else:
		_deselect()


func _select(tile: HexTile) -> void:
	if _selected != tile:
		_deselect()
		_selected = tile
		_selected.set_highlighted(true)
	tile_selected.emit(tile.coord())
	DebugReadout.show_tile(tile)


func _deselect() -> void:
	if _selected:
		_selected.set_highlighted(false)
		_selected = null
