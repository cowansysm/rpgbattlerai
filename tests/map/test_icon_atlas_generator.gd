extends GutTest
## Tests for IconAtlasGenerator — procedural atlas rendering.
## Validates image dimensions, format, cell content, and file output.
## Spec reference: phase9-spec.md §6

var _img: Image


func before_all() -> void:
	_img = IconAtlasGenerator.generate()


# --- Image properties ---

func test_generate_returns_512x512_image() -> void:
	assert_eq(_img.get_width(), 512, "atlas width should be 512")
	assert_eq(_img.get_height(), 512, "atlas height should be 512")


func test_generate_has_rgba8_format() -> void:
	assert_eq(_img.get_format(), Image.FORMAT_RGBA8, "atlas should use RGBA8 format")


# --- Cell content checks ---

func test_cell_has_non_transparent_pixels() -> void:
	for icon_id in IconAtlasGenerator.LAYOUT:
		var info: Dictionary = IconAtlasGenerator.LAYOUT[icon_id]
		var has_content := _cell_has_content(info["col"], info["row"])
		assert_true(has_content, "cell for '%s' at (%d,%d) should have non-transparent pixels" % [
			icon_id, info["col"], info["row"]])


func test_race_class_cells_have_content() -> void:
	for char_id in IconAtlasGenerator.RACE_CLASS_LAYOUT:
		var info: Dictionary = IconAtlasGenerator.RACE_CLASS_LAYOUT[char_id]
		var has_content := _cell_has_content(info["col"], info["row"])
		assert_true(has_content, "race+class cell for '%s' should have content" % char_id)


func test_unoccupied_cells_are_transparent() -> void:
	# Cells not referenced by any LAYOUT or RACE_CLASS_LAYOUT entry should be transparent
	var occupied: Dictionary = {}  # "col,row" -> true
	for icon_id in IconAtlasGenerator.LAYOUT:
		var info: Dictionary = IconAtlasGenerator.LAYOUT[icon_id]
		occupied["%d,%d" % [info["col"], info["row"]]] = true
	for char_id in IconAtlasGenerator.RACE_CLASS_LAYOUT:
		var info: Dictionary = IconAtlasGenerator.RACE_CLASS_LAYOUT[char_id]
		occupied["%d,%d" % [info["col"], info["row"]]] = true
	var checked := 0
	for row in range(8):
		for col in range(8):
			var key := "%d,%d" % [col, row]
			if key in occupied:
				continue
			var has_content := _cell_has_content(col, row)
			assert_false(has_content, "unoccupied cell at (%d,%d) should be transparent" % [col, row])
			checked += 1
	assert_true(checked > 0, "should have at least one unoccupied cell to verify")


# --- File output ---

func test_save_creates_file() -> void:
	var path := "user://test_symbol_atlas.png"
	IconAtlasGenerator.save(path)
	var exists := FileAccess.file_exists(path)
	assert_true(exists, "save() should create the atlas PNG file")
	# Clean up
	if exists:
		DirAccess.remove_absolute(path)


# --- Helpers ---

func _cell_has_content(col: int, row: int) -> bool:
	var ox := col * 64
	var oy := row * 64
	for y in range(oy, oy + 64):
		for x in range(ox, ox + 64):
			if x < _img.get_width() and y < _img.get_height():
				if _img.get_pixel(x, y).a > 0.0:
					return true
	return false
