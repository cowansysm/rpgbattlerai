extends GutTest
## Tests for StatusMarker — 3D billboard icon for status effects.
## Spec reference: phase9-spec.md §7.9


func before_all() -> void:
	# Ensure atlas is available
	SymbolAtlas._atlas = null
	SymbolAtlas._cache = {}


func test_create_returns_mesh_instance() -> void:
	var marker := StatusMarker.create("sleep")
	assert_not_null(marker)
	assert_true(marker is MeshInstance3D, "marker should be a MeshInstance3D")
	marker.free()


func test_marker_stores_status_id() -> void:
	var marker := StatusMarker.create("blind")
	assert_eq(marker.status_id, "blind")
	marker.free()


func test_marker_has_billboard_material() -> void:
	var marker := StatusMarker.create("sleep")
	var mat: StandardMaterial3D = marker.material_override
	assert_not_null(mat)
	assert_eq(mat.billboard_mode, BaseMaterial3D.BILLBOARD_ENABLED,
		"status marker should use billboard mode")
	marker.free()


func test_marker_is_unshaded() -> void:
	var marker := StatusMarker.create("defend")
	var mat: StandardMaterial3D = marker.material_override
	assert_eq(mat.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED,
		"status marker should be unshaded")
	marker.free()


func test_marker_has_alpha_scissor() -> void:
	var marker := StatusMarker.create("sleep")
	var mat: StandardMaterial3D = marker.material_override
	assert_eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,
		"status marker should use alpha scissor transparency")
	marker.free()


func test_marker_has_quad_mesh() -> void:
	var marker := StatusMarker.create("blind")
	assert_true(marker.mesh is QuadMesh, "marker should use a QuadMesh")
	marker.free()
