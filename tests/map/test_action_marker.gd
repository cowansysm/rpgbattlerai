extends GutTest
## Tests for ActionMarker — animated 3D billboard icon for action feedback.
## Spec reference: phase10-spec.md §3


func before_all() -> void:
	SymbolAtlas._atlas = null
	SymbolAtlas._cache = {}


func test_create_returns_mesh_instance() -> void:
	var marker := ActionMarker.create("fire_1")
	assert_not_null(marker)
	assert_true(marker is MeshInstance3D, "marker should be a MeshInstance3D")
	marker.free()


func test_marker_has_quad_mesh() -> void:
	var marker := ActionMarker.create("fire_1")
	assert_true(marker.mesh is QuadMesh, "marker should use a QuadMesh")
	marker.free()


func test_marker_quad_size() -> void:
	var marker := ActionMarker.create("fire_1")
	var quad: QuadMesh = marker.mesh as QuadMesh
	assert_eq(quad.size, Vector2(0.3, 0.3), "quad size should be 0.3x0.3")
	marker.free()


func test_marker_has_billboard_material() -> void:
	var marker := ActionMarker.create("action_attack")
	var mat: StandardMaterial3D = marker.material_override
	assert_not_null(mat)
	assert_eq(mat.billboard_mode, BaseMaterial3D.BILLBOARD_ENABLED,
		"action marker should use billboard mode")
	marker.free()


func test_marker_uses_alpha_blend() -> void:
	var marker := ActionMarker.create("fire_1")
	var mat: StandardMaterial3D = marker.material_override
	assert_eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA,
		"action marker should use TRANSPARENCY_ALPHA for smooth fade")
	marker.free()


func test_marker_is_unshaded() -> void:
	var marker := ActionMarker.create("cure_1")
	var mat: StandardMaterial3D = marker.material_override
	assert_eq(mat.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED,
		"action marker should be unshaded")
	marker.free()


func test_fallback_for_unknown_icon() -> void:
	var marker := ActionMarker.create("nonexistent_xyz")
	assert_not_null(marker, "unknown icon should still produce a valid marker")
	assert_true(marker.mesh is QuadMesh)
	assert_not_null(marker.material_override)
	marker.free()
