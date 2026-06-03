extends GutTest
## Tests for TileRecord typed container.

func test_fields_assigned_correctly() -> void:
	var t := TileRecord.new(3, -1, 2, "trees")
	assert_eq(t.q, 3)
	assert_eq(t.r, -1)
	assert_eq(t.elevation, 2)
	assert_eq(t.terrain, "trees")


func test_coord_returns_vector2i() -> void:
	var t := TileRecord.new(3, -1, 2, "trees")
	assert_eq(t.coord(), Vector2i(3, -1))


func test_default_values() -> void:
	var t := TileRecord.new()
	assert_eq(t.q, 0)
	assert_eq(t.r, 0)
	assert_eq(t.elevation, 0)
	assert_eq(t.terrain, "grass")
