class_name MapEditorHUD
extends CanvasLayer
## 2D overlay for the map editor. Functional, unstyled.
## Programmatically built following the BattleHUD pattern.

signal tool_selected(tool_id: int)
signal terrain_selected(terrain_id: String)
signal zone_selected(zone_name: String)
signal metadata_changed(new_id: String, new_tier: String)
signal new_map_requested(new_id: String, new_tier: String, shape: String, size: int)
signal load_map_requested(filename: String)
signal save_requested()
signal undo_requested()
signal redo_requested()
signal exit_requested()

# Tool enum must match MapEditor controller
enum Tool { PAINT_TERRAIN, RAISE_ELEVATION, LOWER_ELEVATION, ADD_TILE, REMOVE_TILE, ZONE_MARK, INSPECT }

const TOOL_NAMES: Array[String] = ["Paint", "Raise", "Lower", "Add Tile", "Remove Tile", "Zone", "Inspect"]
const ZONE_NAMES: Array[String] = ["playerA", "playerB", "enemy", "player"]
const TIER_OPTIONS: Array[String] = ["skirmish", "standard", "large"]

var _tool_buttons: Array[Button] = []
var _terrain_buttons: Dictionary = {}   # String -> Button
var _zone_buttons: Array[Button] = []
var _undo_btn: Button
var _redo_btn: Button
var _id_field: LineEdit
var _tier_option: OptionButton
var _status_label: Label
var _validation_label: RichTextLabel
var _tile_info_label: Label
var _zone_panel: VBoxContainer
var _new_dialog: PanelContainer
var _load_dialog: PanelContainer
var _load_list: VBoxContainer
var _new_id_field: LineEdit
var _new_tier_option: OptionButton
var _new_shape_option: OptionButton
var _new_size_spin: SpinBox
var _hover_panel: PanelContainer
var _hover_label: Label
var _active_tool: int = Tool.PAINT_TERRAIN
var _active_terrain: String = "grass"
var _active_zone: String = "playerA"


func setup() -> void:
	layer = 10
	_build_ui()


func _build_ui() -> void:
	_build_left_toolbar()
	_build_top_bar()
	_build_hover_readout()
	_build_bottom_bar()
	_build_right_panel()
	_build_new_dialog()
	_build_load_dialog()


# --- Left toolbar: tools + terrain palette ---

func _build_left_toolbar() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_right = 150
	panel.offset_top = 50
	panel.offset_bottom = -40
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Tool buttons
	var tools_label := Label.new()
	tools_label.text = "Tools"
	tools_label.add_theme_font_size_override("font_size", 14)
	tools_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tools_label)

	for i in range(TOOL_NAMES.size()):
		var btn := Button.new()
		btn.text = TOOL_NAMES[i]
		btn.toggle_mode = true
		btn.button_pressed = (i == _active_tool)
		var tool_id := i
		btn.pressed.connect(func() -> void: _on_tool_pressed(tool_id))
		vbox.add_child(btn)
		_tool_buttons.append(btn)

	vbox.add_child(HSeparator.new())

	# Zone selector (visible when zone tool active)
	_zone_panel = VBoxContainer.new()
	_zone_panel.visible = (_active_tool == Tool.ZONE_MARK)
	vbox.add_child(_zone_panel)

	var zone_label := Label.new()
	zone_label.text = "Zones"
	zone_label.add_theme_font_size_override("font_size", 12)
	zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone_panel.add_child(zone_label)

	for zn: String in ZONE_NAMES:
		var btn := Button.new()
		btn.text = zn
		btn.toggle_mode = true
		btn.button_pressed = (zn == _active_zone)
		var zone_name := zn
		btn.pressed.connect(func() -> void: _on_zone_pressed(zone_name))
		_zone_panel.add_child(btn)
		_zone_buttons.append(btn)

	_zone_panel.add_child(HSeparator.new())

	# Terrain palette
	var terrain_label := Label.new()
	terrain_label.text = "Terrain"
	terrain_label.add_theme_font_size_override("font_size", 14)
	terrain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(terrain_label)

	for terrain_id: String in GameData.all_terrain_ids():
		var hbox := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.color = TerrainPalette.COLORS.get(terrain_id, Color.MAGENTA)
		hbox.add_child(swatch)
		var btn := Button.new()
		btn.text = terrain_id
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.toggle_mode = true
		btn.button_pressed = (terrain_id == _active_terrain)
		var tid := terrain_id
		btn.pressed.connect(func() -> void: _on_terrain_pressed(tid))
		hbox.add_child(btn)
		vbox.add_child(hbox)
		_terrain_buttons[terrain_id] = btn


# --- Top bar: metadata, file ops, undo/redo ---

func _build_top_bar() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.offset_left = 155
	panel.offset_bottom = 45
	add_child(panel)

	var hbox := HBoxContainer.new()
	panel.add_child(hbox)

	# Map ID
	var id_label := Label.new()
	id_label.text = "ID:"
	hbox.add_child(id_label)

	_id_field = LineEdit.new()
	_id_field.text = "untitled"
	_id_field.custom_minimum_size.x = 120
	_id_field.text_changed.connect(func(new_text: String) -> void:
		metadata_changed.emit(new_text, TIER_OPTIONS[_tier_option.selected]))
	hbox.add_child(_id_field)

	# Tier
	var tier_label := Label.new()
	tier_label.text = "Tier:"
	hbox.add_child(tier_label)

	_tier_option = OptionButton.new()
	for t: String in TIER_OPTIONS:
		_tier_option.add_item(t)
	_tier_option.selected = 1  # standard
	_tier_option.item_selected.connect(func(_idx: int) -> void:
		metadata_changed.emit(_id_field.text, TIER_OPTIONS[_tier_option.selected]))
	hbox.add_child(_tier_option)

	hbox.add_child(VSeparator.new())

	# File operations
	var new_btn := Button.new()
	new_btn.text = "New"
	new_btn.pressed.connect(func() -> void: _show_new_dialog())
	hbox.add_child(new_btn)

	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.pressed.connect(func() -> void: _show_load_dialog())
	hbox.add_child(load_btn)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(func() -> void: save_requested.emit())
	hbox.add_child(save_btn)

	hbox.add_child(VSeparator.new())

	# Undo / Redo
	_undo_btn = Button.new()
	_undo_btn.text = "Undo"
	_undo_btn.disabled = true
	_undo_btn.pressed.connect(func() -> void: undo_requested.emit())
	hbox.add_child(_undo_btn)

	_redo_btn = Button.new()
	_redo_btn.text = "Redo"
	_redo_btn.disabled = true
	_redo_btn.pressed.connect(func() -> void: redo_requested.emit())
	hbox.add_child(_redo_btn)

	hbox.add_child(VSeparator.new())

	# Exit
	var exit_btn := Button.new()
	exit_btn.text = "Exit"
	exit_btn.pressed.connect(func() -> void: exit_requested.emit())
	hbox.add_child(exit_btn)


# --- Hover readout: terrain info on mouse hover ---

func _build_hover_readout() -> void:
	_hover_panel = PanelContainer.new()
	_hover_panel.anchor_left = 0.0
	_hover_panel.anchor_top = 0.0
	_hover_panel.offset_left = 155
	_hover_panel.offset_top = 48
	_hover_panel.offset_right = 520
	_hover_panel.offset_bottom = 90
	_hover_panel.visible = false
	add_child(_hover_panel)

	_hover_label = Label.new()
	_hover_label.add_theme_font_size_override("font_size", 12)
	_hover_panel.add_child(_hover_label)


# --- Bottom bar: status + validation ---

func _build_bottom_bar() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 155
	panel.offset_top = -35
	add_child(panel)

	var hbox := HBoxContainer.new()
	panel.add_child(hbox)

	_status_label = Label.new()
	_status_label.text = "Ready"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_status_label)

	_validation_label = RichTextLabel.new()
	_validation_label.bbcode_enabled = false
	_validation_label.scroll_active = true
	_validation_label.custom_minimum_size = Vector2(400, 30)
	_validation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_validation_label)


# --- Right panel: tile inspector ---

func _build_right_panel() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.offset_left = -200
	panel.offset_top = 50
	panel.offset_bottom = 250
	add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Tile Inspector"
	title.add_theme_font_size_override("font_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	_tile_info_label = Label.new()
	_tile_info_label.text = "Click a tile to inspect"
	_tile_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_tile_info_label)


# --- New map dialog ---

func _build_new_dialog() -> void:
	_new_dialog = PanelContainer.new()
	_new_dialog.anchor_left = 0.5
	_new_dialog.anchor_top = 0.5
	_new_dialog.anchor_right = 0.5
	_new_dialog.anchor_bottom = 0.5
	_new_dialog.offset_left = -150
	_new_dialog.offset_right = 150
	_new_dialog.offset_top = -120
	_new_dialog.offset_bottom = 120
	_new_dialog.visible = false
	add_child(_new_dialog)

	var vbox := VBoxContainer.new()
	_new_dialog.add_child(vbox)

	var title := Label.new()
	title.text = "New Map"
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# ID
	var id_hbox := HBoxContainer.new()
	var id_lbl := Label.new()
	id_lbl.text = "ID:"
	id_hbox.add_child(id_lbl)
	_new_id_field = LineEdit.new()
	_new_id_field.text = "new_map"
	_new_id_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_hbox.add_child(_new_id_field)
	vbox.add_child(id_hbox)

	# Tier
	var tier_hbox := HBoxContainer.new()
	var tier_lbl := Label.new()
	tier_lbl.text = "Tier:"
	tier_hbox.add_child(tier_lbl)
	_new_tier_option = OptionButton.new()
	for t: String in TIER_OPTIONS:
		_new_tier_option.add_item(t)
	_new_tier_option.selected = 1
	_new_tier_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tier_hbox.add_child(_new_tier_option)
	vbox.add_child(tier_hbox)

	# Shape
	var shape_hbox := HBoxContainer.new()
	var shape_lbl := Label.new()
	shape_lbl.text = "Shape:"
	shape_hbox.add_child(shape_lbl)
	_new_shape_option = OptionButton.new()
	_new_shape_option.add_item("rect")
	_new_shape_option.add_item("hex")
	_new_shape_option.selected = 0
	_new_shape_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shape_hbox.add_child(_new_shape_option)
	vbox.add_child(shape_hbox)

	# Size
	var size_hbox := HBoxContainer.new()
	var size_lbl := Label.new()
	size_lbl.text = "Size:"
	size_hbox.add_child(size_lbl)
	_new_size_spin = SpinBox.new()
	_new_size_spin.min_value = 2
	_new_size_spin.max_value = 15
	_new_size_spin.value = 8
	_new_size_spin.step = 1
	_new_size_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_hbox.add_child(_new_size_spin)
	vbox.add_child(size_hbox)

	# Buttons
	var btn_hbox := HBoxContainer.new()
	var create_btn := Button.new()
	create_btn.text = "Create"
	create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_btn.pressed.connect(func() -> void:
		new_map_requested.emit(
			_new_id_field.text,
			TIER_OPTIONS[_new_tier_option.selected],
			_new_shape_option.get_item_text(_new_shape_option.selected),
			int(_new_size_spin.value))
		_new_dialog.visible = false)
	btn_hbox.add_child(create_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(func() -> void: _new_dialog.visible = false)
	btn_hbox.add_child(cancel_btn)
	vbox.add_child(btn_hbox)


# --- Load map dialog ---

func _build_load_dialog() -> void:
	_load_dialog = PanelContainer.new()
	_load_dialog.anchor_left = 0.5
	_load_dialog.anchor_top = 0.5
	_load_dialog.anchor_right = 0.5
	_load_dialog.anchor_bottom = 0.5
	_load_dialog.offset_left = -150
	_load_dialog.offset_right = 150
	_load_dialog.offset_top = -150
	_load_dialog.offset_bottom = 150
	_load_dialog.visible = false
	add_child(_load_dialog)

	var vbox := VBoxContainer.new()
	_load_dialog.add_child(vbox)

	var title := Label.new()
	title.text = "Load Map"
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_load_list = VBoxContainer.new()
	_load_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_load_list)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func() -> void: _load_dialog.visible = false)
	vbox.add_child(cancel_btn)


# --- Dialog show helpers ---

func _show_new_dialog() -> void:
	_load_dialog.visible = false
	_new_dialog.visible = true


func _show_load_dialog() -> void:
	_new_dialog.visible = false
	_populate_load_list()
	_load_dialog.visible = true


func _populate_load_list() -> void:
	for child in _load_list.get_children():
		child.queue_free()
	var dir := DirAccess.open("res://data/maps/")
	if not dir:
		return
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if filename.ends_with(".json"):
			var btn := Button.new()
			btn.text = filename.trim_suffix(".json")
			var fname := filename
			btn.pressed.connect(func() -> void:
				load_map_requested.emit(fname)
				_load_dialog.visible = false)
			_load_list.add_child(btn)
		filename = dir.get_next()


# --- Internal signal handlers ---

func _on_tool_pressed(tool_id: int) -> void:
	_active_tool = tool_id
	for i in range(_tool_buttons.size()):
		_tool_buttons[i].button_pressed = (i == tool_id)
	_zone_panel.visible = (tool_id == Tool.ZONE_MARK)
	tool_selected.emit(tool_id)


func _on_terrain_pressed(terrain_id: String) -> void:
	_active_terrain = terrain_id
	for tid: String in _terrain_buttons.keys():
		_terrain_buttons[tid].button_pressed = (tid == terrain_id)
	terrain_selected.emit(terrain_id)


func _on_zone_pressed(zone_name: String) -> void:
	_active_zone = zone_name
	for i in range(_zone_buttons.size()):
		_zone_buttons[i].button_pressed = (ZONE_NAMES[i] == zone_name)
	zone_selected.emit(zone_name)


# --- Public update methods ---

func update_undo_redo(can_undo: bool, can_redo: bool) -> void:
	_undo_btn.disabled = not can_undo
	_redo_btn.disabled = not can_redo


func update_validation(errors: Array[String]) -> void:
	if errors.is_empty():
		_validation_label.text = "No errors"
	else:
		_validation_label.text = "%d error(s): %s" % [errors.size(), "; ".join(errors)]


func show_tile_info(coord: Vector2i, tile_data: Dictionary, zone_names: Array[String]) -> void:
	if tile_data.is_empty():
		_tile_info_label.text = "No tile at (%d, %d)" % [coord.x, coord.y]
		return
	var info := "Coord: (%d, %d)\nElevation: %d\nTerrain: %s" % [
		coord.x, coord.y, tile_data.get("elevation", 0), tile_data.get("terrain", "?")]
	var tags: Array = tile_data.get("tags", [])
	if not tags.is_empty():
		info += "\nTags: %s" % ", ".join(tags)
	if not zone_names.is_empty():
		info += "\nZones: %s" % ", ".join(zone_names)
	_tile_info_label.text = info


func show_status(message: String) -> void:
	_status_label.text = message


func update_file_info(map_id: String, _file_path: String) -> void:
	_id_field.text = map_id


func set_active_tool(tool_id: int) -> void:
	_on_tool_pressed(tool_id)


func set_active_terrain(terrain_id: String) -> void:
	_on_terrain_pressed(terrain_id)


func set_active_zone(zone_name: String) -> void:
	_on_zone_pressed(zone_name)


func update_hover(coord: Vector2i, elevation: int, terrain_id: String,
		props: TerrainProps) -> void:
	var parts: Array[String] = []
	parts.append("(%d, %d)  H:%d  %s" % [coord.x, coord.y, elevation, terrain_id])
	var effects: Array[String] = []
	if props.move_cost != 1:
		effects.append("move:%d" % props.move_cost)
	if props.impassable:
		effects.append("impassable")
	if props.cover != 0:
		effects.append("cover:%+d" % props.cover)
	if props.blocks_los:
		effects.append("blocks LOS")
	if props.damage_on_enter != 0:
		effects.append("dmg enter:%d" % props.damage_on_enter)
	if props.damage_per_turn != 0:
		effects.append("dmg/turn:%d" % props.damage_per_turn)
	if not props.status_on_enter.is_empty():
		effects.append("status:%s" % props.status_on_enter.get("status_id", "?"))
	if not props.occupant_modifiers.is_empty():
		var mods: Array[String] = []
		for m: Dictionary in props.occupant_modifiers:
			mods.append("%s%+d" % [m.get("key", "?"), m.get("value", 0)])
		effects.append("mods:%s" % ",".join(mods))
	if props.is_water:
		effects.append("water")
	if not effects.is_empty():
		parts.append("  [%s]" % "  ".join(effects))
	_hover_label.text = "".join(parts)
	_hover_panel.visible = true


func clear_hover() -> void:
	_hover_panel.visible = false
