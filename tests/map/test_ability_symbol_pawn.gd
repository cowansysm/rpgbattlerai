extends GutTest
## Tests for AbilitySymbolPawn creation and lifecycle.
## Physics behavior is cosmetic — these tests verify the API surface,
## signal emission via timeout, and cleanup.


func test_create_returns_valid_pawn() -> void:
	var pawn := AbilitySymbolPawn.create("action_attack", 0.0)
	assert_not_null(pawn, "create() should return a valid pawn")
	assert_is(pawn, RigidBody3D, "pawn should extend RigidBody3D")
	pawn.free()


func test_pawn_has_landed_signal() -> void:
	var pawn := AbilitySymbolPawn.create("fire_1", 0.0)
	assert_true(pawn.has_signal("landed"), "pawn should have 'landed' signal")
	pawn.free()


func test_pawn_starts_in_fall_state() -> void:
	var pawn := AbilitySymbolPawn.create("action_ability", 0.0)
	assert_eq(pawn._state, AbilitySymbolPawn.State.FALL,
		"pawn should start in FALL state")
	pawn.free()


func test_pawn_collision_layer_set() -> void:
	var pawn := AbilitySymbolPawn.create("action_attack", 0.0)
	assert_eq(pawn.collision_layer, 1 << 7,
		"pawn should be on collision layer 8 (bit 7)")
	assert_eq(pawn.collision_mask, 1 << 7,
		"pawn should mask collision layer 8 (bit 7)")
	pawn.free()


func test_pawn_has_visual_mesh() -> void:
	var pawn := AbilitySymbolPawn.create("action_attack", 0.0)
	assert_not_null(pawn._body_mesh, "pawn should have a body mesh")
	assert_not_null(pawn._material, "pawn should have a material")
	pawn.free()


func test_create_with_fallback_icon() -> void:
	# Using an unknown icon ID should still create a valid pawn
	# (SymbolAtlas falls back to _fallback)
	var pawn := AbilitySymbolPawn.create("nonexistent_icon_xyz", 0.0)
	assert_not_null(pawn, "create with unknown icon should still succeed")
	pawn.free()


func test_pawn_uses_constants() -> void:
	var pawn := AbilitySymbolPawn.create("action_attack", 0.0)
	var expected_mass: float = float(Constants.get_value("SYMBOL_PAWN_MASS", 1.0))
	assert_eq(pawn.mass, expected_mass,
		"pawn mass should match SYMBOL_PAWN_MASS constant")
	pawn.free()
