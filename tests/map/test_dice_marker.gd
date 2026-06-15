extends GutTest
## Tests for DiceMarker — animated 3D D6 cube for dice roll feedback.


func test_create_returns_node3d() -> void:
	var marker := DiceMarker.create(4, true)
	assert_not_null(marker)
	assert_true(marker is Node3D, "marker should be a Node3D")
	marker.free()


func test_create_stores_value() -> void:
	var marker := DiceMarker.create(3, true)
	assert_eq(marker._value, 3)
	marker.free()


func test_create_stores_is_attack() -> void:
	var atk := DiceMarker.create(4, true)
	assert_true(atk._is_attack)
	atk.free()
	var def_m := DiceMarker.create(4, false)
	assert_false(def_m._is_attack)
	def_m.free()


func test_cube_has_body_mesh() -> void:
	var marker := DiceMarker.create(5, true)
	assert_not_null(marker._body, "marker should have a body MeshInstance3D")
	assert_true(marker._body.mesh is BoxMesh, "body should use BoxMesh")
	marker.free()


func test_cube_has_six_faces() -> void:
	var marker := DiceMarker.create(2, true)
	assert_eq(marker._faces.size(), 6, "cube should have 6 face quads")
	marker.free()


func test_faces_use_quad_mesh() -> void:
	var marker := DiceMarker.create(1, false)
	for face in marker._faces:
		assert_true(face.mesh is QuadMesh, "each face should use QuadMesh")
	marker.free()


func test_attack_color_tint() -> void:
	var marker := DiceMarker.create(3, true)
	for mat in marker._face_materials:
		assert_almost_eq(mat.albedo_color.r, DiceMarker.ATK_COLOR.r, 0.01)
		assert_almost_eq(mat.albedo_color.g, DiceMarker.ATK_COLOR.g, 0.01)
		assert_almost_eq(mat.albedo_color.b, DiceMarker.ATK_COLOR.b, 0.01)
	marker.free()


func test_defense_color_tint() -> void:
	var marker := DiceMarker.create(3, false)
	for mat in marker._face_materials:
		assert_almost_eq(mat.albedo_color.r, DiceMarker.DEF_COLOR.r, 0.01)
		assert_almost_eq(mat.albedo_color.g, DiceMarker.DEF_COLOR.g, 0.01)
		assert_almost_eq(mat.albedo_color.b, DiceMarker.DEF_COLOR.b, 0.01)
	marker.free()


func test_faces_are_unshaded() -> void:
	var marker := DiceMarker.create(1, true)
	for mat in marker._face_materials:
		assert_eq(mat.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	marker.free()


func test_faces_have_alpha_transparency() -> void:
	var marker := DiceMarker.create(4, true)
	for mat in marker._face_materials:
		assert_eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	marker.free()


func test_pip_textures_cached() -> void:
	var marker := DiceMarker.create(1, true)
	assert_eq(DiceMarker._pip_textures.size(), 6,
		"should cache 6 pip textures")
	marker.free()


func test_all_values_1_through_6() -> void:
	for v in [1, 2, 3, 4, 5, 6]:
		var marker := DiceMarker.create(v, true)
		assert_eq(marker._value, v)
		assert_eq(marker._faces.size(), 6)
		marker.free()


func test_value_clamped_to_valid_range() -> void:
	var low := DiceMarker.create(0, true)
	assert_eq(low._value, 1, "value below 1 should clamp to 1")
	low.free()
	var high := DiceMarker.create(9, true)
	assert_eq(high._value, 6, "value above 6 should clamp to 6")
	high.free()


func test_result_rotations_defined_for_all_values() -> void:
	for v in [1, 2, 3, 4, 5, 6]:
		assert_true(DiceMarker._RESULT_ROTATIONS.has(v),
			"rotation should be defined for value %d" % v)
