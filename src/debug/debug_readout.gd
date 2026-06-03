extends CanvasLayer
## Debug overlay showing selected tile info. Registered as autoload "DebugReadout".

var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.anchor_left = 0.0
	_label.anchor_top = 0.0
	_label.offset_left = 12.0
	_label.offset_top = 12.0
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.text = ""
	add_child(_label)


func show_tile(tile: HexTile) -> void:
	_label.text = "(%d, %d)  elev %d  %s" % [
		tile.hex_q, tile.hex_r, tile.hex_elevation, tile.hex_terrain]
	Log.info("Picker", "Selected tile (%d, %d) elev=%d terrain=%s" % [
		tile.hex_q, tile.hex_r, tile.hex_elevation, tile.hex_terrain])
