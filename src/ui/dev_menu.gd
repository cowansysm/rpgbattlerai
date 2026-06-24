class_name DevMenu
extends CanvasLayer
## Dev-only tools menu. Instantiated only when Dev.enabled.
## Provides entry points to internal tooling.

var _panel: PanelContainer
var _vbox: VBoxContainer
var _status_label: Label


func _ready() -> void:
	if not Dev.enabled:
		queue_free()
		return
	_build_ui()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.0
	_panel.anchor_right = 0.5
	_panel.offset_left = -120
	_panel.offset_right = 120
	_panel.offset_top = 10
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_panel.add_child(_vbox)

	var title := Label.new()
	title.text = "Dev Tools"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	_vbox.add_child(title)

	var sep := HSeparator.new()
	_vbox.add_child(sep)

	# Map Editor
	var map_editor_btn := Button.new()
	map_editor_btn.text = "Map Editor"
	map_editor_btn.pressed.connect(_on_map_editor_pressed)
	_vbox.add_child(map_editor_btn)

	# Band Management
	var band_btn := Button.new()
	band_btn.text = "Band Management"
	band_btn.pressed.connect(_on_band_management_pressed)
	_vbox.add_child(band_btn)

	# Dev Overrides
	var overrides_btn := Button.new()
	overrides_btn.text = "Dev Overrides"
	overrides_btn.pressed.connect(_on_overrides_pressed)
	_vbox.add_child(overrides_btn)

	# CSV Pipeline
	var csv_sep := HSeparator.new()
	_vbox.add_child(csv_sep)

	var csv_label := Label.new()
	csv_label.text = "CSV Pipeline"
	csv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(csv_label)

	var export_btn := Button.new()
	export_btn.text = "Export All → CSV"
	export_btn.pressed.connect(_on_csv_export_pressed)
	_vbox.add_child(export_btn)

	var import_btn := Button.new()
	import_btn.text = "Import All CSV → JSON"
	import_btn.pressed.connect(_on_csv_import_pressed)
	_vbox.add_child(import_btn)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 12)
	_vbox.add_child(_status_label)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_on_close)
	_vbox.add_child(close_btn)


func _on_map_editor_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/editor/map_editor.tscn")


func _on_csv_export_pressed() -> void:
	_status_label.text = "Exporting..."
	var errors := CsvExporter.export_all()
	if errors.is_empty():
		_status_label.text = "Export OK"
	else:
		_status_label.text = "%d error(s)" % errors.size()
		for e in errors:
			Log.error("DevMenu", e)


func _on_csv_import_pressed() -> void:
	_status_label.text = "Importing..."
	var errors := CsvImporter.import_all()
	if errors.is_empty():
		_status_label.text = "Import OK"
	else:
		_status_label.text = "%d error(s)" % errors.size()
		for e in errors:
			Log.error("DevMenu", e)


func _on_overrides_pressed() -> void:
	var panel := DevOverridesPanel.new()
	get_tree().root.add_child(panel)


func _on_band_management_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/band/band_scene.tscn")


func _on_close() -> void:
	_panel.visible = false


func show_menu() -> void:
	if _panel:
		_panel.visible = true
