class_name HexTile
extends Node3D
## A single hex tile in the 3D scene. Multi-layer: base + overlay + selection.
## Stores axial coords/elevation/terrain as metadata for picking.

const OVERLAY_Y_OFFSET := 0.02
const SELECTION_Y_OFFSET := 0.04
const FLAT_TOP_ROTATION := deg_to_rad(30.0)

var hex_q: int
var hex_r: int
var hex_elevation: int
var hex_terrain: String

var _base_mesh: MeshInstance3D
var _overlay_mesh: MeshInstance3D
var _selection_mesh: MeshInstance3D


func setup(tq: int, tr: int, te: int, tt: String,
		mesh: Mesh, mat: Material, highlight_mat: Material,
		floor_elev: int = 0) -> void:
	hex_q = tq
	hex_r = tr
	hex_elevation = te
	hex_terrain = tt

	position = HexWorld.hex_to_world(tq, tr, te)
	rotation.y = FLAT_TOP_ROTATION

	# Base layer — always visible, terrain material.
	_base_mesh = MeshInstance3D.new()
	_base_mesh.mesh = mesh
	_base_mesh.material_override = mat
	add_child(_base_mesh)

	# Side wall — opaque vertical face extending from tile bottom to floor.
	var wall_height: float = (te - floor_elev) * HexWorld.ELEV_UNIT
	if wall_height > 0.001:
		var wall_mesh := TileMesh.make_wall_mesh(wall_height)
		var wall := MeshInstance3D.new()
		wall.mesh = wall_mesh
		# Top of wall cylinder at tile bottom (-TILE_HEIGHT/2)
		wall.position.y = -TileMesh.TILE_HEIGHT * 0.5 - wall_height * 0.5
		var wall_mat := TerrainPalette.wall_material(tt, te)
		wall.material_override = wall_mat
		add_child(wall)

	# Overlay layer — hidden by default, Phase 3+ movement/range painting.
	_overlay_mesh = MeshInstance3D.new()
	_overlay_mesh.mesh = mesh
	_overlay_mesh.position.y = OVERLAY_Y_OFFSET
	_overlay_mesh.visible = false
	add_child(_overlay_mesh)

	# Selection layer — hidden by default, shown on click/select.
	_selection_mesh = MeshInstance3D.new()
	_selection_mesh.mesh = mesh
	_selection_mesh.material_override = highlight_mat
	_selection_mesh.position.y = SELECTION_Y_OFFSET
	_selection_mesh.visible = false
	add_child(_selection_mesh)

	# Collider for raycast picking.
	var body := StaticBody3D.new()
	var col_shape := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = HexWorld.HEX_SIZE * 0.9
	shape.height = TileMesh.TILE_HEIGHT + 0.05
	col_shape.shape = shape
	body.add_child(col_shape)
	add_child(body)

	# Decoration marker (tree/boulder) if applicable.
	var deco_mesh: Mesh = DecorationFactory.decoration_for(tt)
	if deco_mesh:
		var deco := MeshInstance3D.new()
		deco.mesh = deco_mesh
		deco.position = Vector3(0.14, TileMesh.TILE_HEIGHT * 0.5 + 0.03, 0.0)
		var deco_mat := StandardMaterial3D.new()
		if tt == "trees":
			deco_mat.albedo_color = Color(0.15, 0.50, 0.15)
		elif tt == "rocks":
			deco_mat.albedo_color = Color(0.30, 0.30, 0.32)
		deco.material_override = deco_mat
		add_child(deco)


func set_highlighted(on: bool) -> void:
	_selection_mesh.visible = on


func set_overlay(mat: Material) -> void:
	_overlay_mesh.material_override = mat
	_overlay_mesh.visible = true


func clear_overlay() -> void:
	_overlay_mesh.visible = false


func coord() -> Vector2i:
	return Vector2i(hex_q, hex_r)


static func tile_from_collider(node: Node) -> HexTile:
	var current := node
	while current:
		if current is HexTile:
			return current as HexTile
		current = current.get_parent()
	return null
