extends Node3D
## Map editor scene controller. Owns the MapEditorModel and wires it to
## the rendering stack (MapBuilder/HexTile/CameraRig/TilePicker) and UI.
## Dev-only; launched from DevMenu.

enum Tool { PAINT_TERRAIN, RAISE_ELEVATION, LOWER_ELEVATION, ADD_TILE, REMOVE_TILE, ZONE_MARK, INSPECT }

const ZONE_COLORS: Dictionary = {
	"playerA": Color(0.3, 0.5, 1.0, 0.4),
	"playerB": Color(1.0, 0.3, 0.3, 0.4),
	"enemy":   Color(0.8, 0.8, 0.0, 0.4),
	"player":  Color(0.3, 1.0, 0.3, 0.4),
}

var model := MapEditorModel.new()
var _builder: MapBuilder
var _rig: CameraRig
var _picker: TilePicker
var _paint_drag: EditorPaintDrag
var _hud: MapEditorHUD
var _current_tool: int = Tool.PAINT_TERRAIN
var _brush_terrain: String = "grass"
var _active_zone: String = "playerA"
var _selected_coord: Vector2i = Vector2i(-999, -999)
var _current_file_path: String = ""
var _hovered_coord: Vector2i = Vector2i(-999, -999)


func _ready() -> void:
	# Start with a default blank map
	model.new_map("untitled", "standard", "rect", 8)
	_rebuild()

	# Camera rig
	_rig = CameraRig.new()
	_rig.position = _builder.focus_center()
	add_child(_rig)

	# Tile picker (fires on click release)
	_picker = TilePicker.new()
	_picker.setup(_rig.get_camera())
	_picker.tile_selected.connect(_on_tile_selected)
	add_child(_picker)

	# Paint-drag handler
	_paint_drag = EditorPaintDrag.new()
	_paint_drag.setup(_rig.get_camera())
	_paint_drag.drag_started.connect(_on_drag_started)
	_paint_drag.tile_painted.connect(_on_tile_painted)
	_paint_drag.drag_ended.connect(_on_drag_ended)
	add_child(_paint_drag)

	# Editor HUD
	_hud = MapEditorHUD.new()
	_hud.setup()
	_hud.tool_selected.connect(_on_tool_selected)
	_hud.terrain_selected.connect(_on_terrain_selected)
	_hud.zone_selected.connect(_on_zone_selected)
	_hud.metadata_changed.connect(_on_metadata_changed)
	_hud.new_map_requested.connect(_on_new_map)
	_hud.load_map_requested.connect(_on_load_map)
	_hud.save_requested.connect(_on_save_map)
	_hud.undo_requested.connect(_on_undo)
	_hud.redo_requested.connect(_on_redo)
	_hud.exit_requested.connect(_on_exit_editor)
	add_child(_hud)

	# Lighting (same as map_scene.gd)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	light.light_energy = 1.0
	light.shadow_enabled = true
	add_child(light)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.70, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.5)
	env.ambient_light_energy = 0.5
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	_hud.update_validation(model.validate())
	Log.info("MapEditor", "Editor ready with %d tiles" % model.tile_count())


# --- Rebuild / Refresh ---

func _rebuild() -> void:
	if _builder:
		_builder.free()
	_builder = MapBuilder.new()
	add_child(_builder)
	_builder.build(model.to_map_data())
	if _rig:
		_rig.position = _builder.focus_center()
	_update_zone_overlays()


func _refresh_tile(coord: Vector2i) -> void:
	var tile: HexTile = _builder.get_tile(coord)
	if not tile:
		return
	var data: Dictionary = model.tiles[coord]
	var new_terrain: String = data["terrain"]
	var elevation: int = data["elevation"]
	tile._base_mesh.material_override = TerrainPalette.material_for(new_terrain, elevation)
	tile.hex_terrain = new_terrain


func _update_zone_overlays() -> void:
	for tile: HexTile in _builder.tiles.values():
		tile.clear_overlay()
	for zone_name: String in model.zones.keys():
		var color: Color = ZONE_COLORS.get(zone_name, Color(1.0, 1.0, 1.0, 0.3))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for coord: Vector2i in model.zones[zone_name]:
			var tile: HexTile = _builder.get_tile(coord)
			if tile:
				tile.set_overlay(mat)


# --- Tool application ---

func _apply_tool(coord: Vector2i) -> void:
	match _current_tool:
		Tool.PAINT_TERRAIN:
			model.set_terrain(coord, _brush_terrain)
			_refresh_tile(coord)
		Tool.RAISE_ELEVATION:
			if model.has_tile(coord):
				model.adjust_elevation(coord, 1)
				_rebuild()
		Tool.LOWER_ELEVATION:
			if model.has_tile(coord):
				model.adjust_elevation(coord, -1)
				_rebuild()
		Tool.ADD_TILE:
			model.add_tile(coord, _brush_terrain)
			_rebuild()
		Tool.REMOVE_TILE:
			model.remove_tile(coord)
			_rebuild()
		Tool.ZONE_MARK:
			if model.has_tile(coord):
				var currently_in := _coord_in_zone(coord, _active_zone)
				model.set_zone(coord, _active_zone, not currently_in)
				_update_zone_overlays()
		Tool.INSPECT:
			_selected_coord = coord
			_hud.show_tile_info(coord, model.get_tile(coord), _get_zones_for_coord(coord))
	_hud.update_undo_redo(model.can_undo(), model.can_redo())
	_hud.update_validation(model.validate())


func _coord_in_zone(coord: Vector2i, zone_name: String) -> bool:
	if not model.zones.has(zone_name):
		return false
	return model.zones[zone_name].has(coord)


func _get_zones_for_coord(coord: Vector2i) -> Array[String]:
	var result: Array[String] = []
	for z: String in model.zones.keys():
		if model.zones[z].has(coord):
			result.append(z)
	return result


# --- Input signal handlers ---

func _on_tile_selected(coord: Vector2i) -> void:
	if _paint_drag.is_dragging():
		return
	_apply_tool(coord)


func _on_drag_started() -> void:
	model.begin_batch()


func _on_tile_painted(coord: Vector2i) -> void:
	_apply_tool(coord)


func _on_drag_ended() -> void:
	model.end_batch()
	_hud.update_undo_redo(model.can_undo(), model.can_redo())
	_hud.update_validation(model.validate())


# --- HUD signal handlers ---

func _on_tool_selected(tool_id: int) -> void:
	_current_tool = tool_id


func _on_terrain_selected(terrain_id: String) -> void:
	_brush_terrain = terrain_id


func _on_zone_selected(zone_name: String) -> void:
	_active_zone = zone_name


func _on_metadata_changed(new_id: String, new_tier: String) -> void:
	model.set_metadata(new_id, new_tier)
	_hud.update_undo_redo(model.can_undo(), model.can_redo())
	_hud.update_validation(model.validate())


func _on_new_map(new_id: String, new_tier: String, shape: String, size: int) -> void:
	model.new_map(new_id, new_tier, shape, size)
	_current_file_path = ""
	_rebuild()
	_hud.update_file_info(model.id, "")
	_hud.update_validation(model.validate())
	_hud.update_undo_redo(false, false)
	_hud.show_status("Created new %s map '%s' (%d tiles)" % [shape, new_id, model.tile_count()])
	Log.info("MapEditor", "New map '%s' (%s, %d tiles)" % [new_id, shape, model.tile_count()])


func _on_load_map(filename: String) -> void:
	var path := "res://data/maps/%s" % filename
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		_hud.show_status("Failed to load: file empty or missing")
		return
	var raw: Variant = JSON.parse_string(text)
	if raw == null:
		_hud.show_status("Failed to load: invalid JSON")
		return
	var map_data: MapData = DataFactory.make_map(raw)
	model.from_map_data(map_data)
	_current_file_path = path
	_rebuild()
	_hud.update_file_info(model.id, _current_file_path)
	_hud.update_validation(model.validate())
	_hud.update_undo_redo(false, false)
	_hud.show_status("Loaded '%s'" % model.id)
	Log.info("MapEditor", "Loaded map '%s' from %s" % [model.id, path])


func _on_save_map() -> void:
	var errors := model.validate()
	if not errors.is_empty():
		_hud.show_status("Cannot save: %d error(s)" % errors.size())
		_hud.update_validation(errors)
		return
	var map_data := model.to_map_data()
	var json_str := MapSerializer.to_json(map_data)
	var path := "res://data/maps/%s.json" % model.id
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		_hud.show_status("Failed to write: %s" % path)
		return
	f.store_string(json_str)
	f.close()
	_current_file_path = path
	_hud.update_file_info(model.id, _current_file_path)
	_hud.show_status("Saved '%s'" % model.id)
	Log.info("MapEditor", "Saved map '%s' to %s" % [model.id, path])


func _on_undo() -> void:
	if model.undo():
		_rebuild()
		_hud.update_undo_redo(model.can_undo(), model.can_redo())
		_hud.update_validation(model.validate())


func _on_redo() -> void:
	if model.redo():
		_rebuild()
		_hud.update_undo_redo(model.can_undo(), model.can_redo())
		_hud.update_validation(model.validate())


func _on_exit_editor() -> void:
	get_tree().change_scene_to_file("res://scenes/draft/draft_scene.tscn")


# --- Hover readout ---

func _update_hover(screen_pos: Vector2) -> void:
	var camera := _rig.get_camera()
	var space := camera.get_world_3d().direct_space_state
	if not space:
		_clear_hover()
		return
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var to := from + dir * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := space.intersect_ray(query)
	if result.is_empty():
		_clear_hover()
		return
	var collider: Node = result["collider"]
	var tile := HexTile.tile_from_collider(collider)
	if not tile:
		_clear_hover()
		return
	var coord := tile.coord()
	if coord == _hovered_coord:
		return
	_hovered_coord = coord
	var tile_data: Dictionary = model.tiles.get(coord, {})
	if tile_data.is_empty():
		_clear_hover()
		return
	var terrain_id: String = tile_data.get("terrain", "grass")
	var elevation: int = tile_data.get("elevation", 0)
	var props: TerrainProps = GameData.get_terrain(terrain_id)
	if props:
		_hud.update_hover(coord, elevation, terrain_id, props)
	else:
		_clear_hover()


func _clear_hover() -> void:
	if _hovered_coord != Vector2i(-999, -999):
		_hovered_coord = Vector2i(-999, -999)
		_hud.clear_hover()


# --- Ground-plane raycast for Add Tile on empty space ---

func _raycast_ground(screen_pos: Vector2) -> Vector2i:
	var camera := _rig.get_camera()
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	# Intersect with Y=0 plane
	if absf(dir.y) < 0.0001:
		return Vector2i(-999, -999)
	var t := -from.y / dir.y
	if t < 0.0:
		return Vector2i(-999, -999)
	var hit := from + dir * t
	return HexWorld.world_to_hex(hit)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover((event as InputEventMouseMotion).position)
	if event is InputEventKey and event.pressed:
		var key := event as InputEventKey
		if key.ctrl_pressed and key.keycode == KEY_Z:
			_on_undo()
			get_viewport().set_input_as_handled()
		elif key.ctrl_pressed and key.keycode == KEY_Y:
			_on_redo()
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_ESCAPE:
			_on_exit_editor()
			get_viewport().set_input_as_handled()
	# Add Tile on empty space: TilePicker won't fire if no collider was hit,
	# so we catch mouse release here and do a ground-plane raycast.
	if _current_tool == Tool.ADD_TILE and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if _paint_drag.is_dragging():
				return
			var coord := _raycast_ground(mb.position)
			if coord != Vector2i(-999, -999) and not model.has_tile(coord):
				_apply_tool(coord)
