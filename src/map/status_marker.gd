class_name StatusMarker
extends MeshInstance3D
## Lightweight billboard quad displaying a status effect icon above a pawn.
## Uses SymbolAtlas for texture lookup and renders as a billboard so it
## always faces the camera.
## Spec reference: phase9-spec.md §7.9

var status_id: String


static func create(id: String) -> StatusMarker:
	var marker := StatusMarker.new()
	marker.status_id = id

	var quad := QuadMesh.new()
	quad.size = Vector2(0.1125, 0.1125)
	marker.mesh = quad

	var mat := SymbolAtlas.make_3d_material(id)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	marker.material_override = mat

	return marker
