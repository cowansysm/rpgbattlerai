class_name DevMenu
extends CanvasLayer
## Dev-only tools menu. Instantiated only when Dev.enabled.
## Provides entry points to internal tooling (map editor in A1, etc.).
## Alpha A0: the seam — Map Editor button is stubbed as disabled.

var _panel: PanelContainer
var _vbox: VBoxContainer


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

	# Map Editor — stubbed for A1
	var map_editor_btn := Button.new()
	map_editor_btn.text = "Map Editor (A1)"
	map_editor_btn.disabled = true
	map_editor_btn.tooltip_text = "Coming in Phase A1"
	_vbox.add_child(map_editor_btn)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_on_close)
	_vbox.add_child(close_btn)


func _on_close() -> void:
	_panel.visible = false


func show_menu() -> void:
	if _panel:
		_panel.visible = true
