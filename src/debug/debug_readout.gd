extends CanvasLayer
## Debug overlay showing selected tile info. Registered as autoload "DebugReadout".

var _label: Label


func _ready() -> void:
	# Alpha A0: only show debug overlay in dev mode
	visible = Dev.enabled
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


## A11: Shows character scaling info (base stats, growth, level, next XP threshold).
func show_character_scaling(ci: CharacterInstance, class_prov: Callable) -> void:
	var cls: ClassData = class_prov.call(ci.active_class)
	var growth_str: String = ""
	if cls and not cls.growth.is_empty():
		var parts: Array[String] = []
		for k in cls.growth.keys():
			parts.append("%s:%.1f" % [k, cls.growth[k]])
		growth_str = " ".join(parts)
	var threshold: int = Leveling.next_threshold(ci.character_level())
	var lines: Array[String] = [
		"%s  Lv%d (%s Lv%d)" % [ci.name, ci.character_level(),
			ci.active_class, ci.active_class_level()],
		"XP: %d / %d" % [ci.xp, threshold],
		"Growth: %s" % growth_str,
		"Accumulated: %s" % str(ci.growth_accumulated),
	]
	_label.text = "\n".join(lines)
