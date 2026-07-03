class_name MainMenu
extends Control
## Main menu screen. Provides entry points to:
## - New Band (creates a new band via BandManagementScene)
## - Load Band (loads existing bands via BandManagementScene)
## - Skirmish (CT-based battle via SkirmishScene)
## - Exit (quits the application)
## - Dev Tools (dev-only, opens DevMenu overlay)

var _title_label: Label
var _button_panel: PanelContainer
var _dev_tools_btn: Button


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(PRESET_FULL_RECT)

	# Outer margin for screen padding
	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = SIZE_EXPAND_FILL
	root.size_flags_vertical = SIZE_EXPAND_FILL
	margin.add_child(root)

	# --- Game Title (top area) ---
	var title_panel := PanelContainer.new()
	title_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var title_style := StyleBoxFlat.new()
	title_style.bg_color = Color(0.95, 0.95, 0.95, 1.0)
	title_style.border_color = Color(0.0, 0.0, 0.0, 1.0)
	title_style.set_border_width_all(2)
	title_style.set_content_margin_all(20)
	title_panel.add_theme_stylebox_override("panel", title_style)
	root.add_child(title_panel)

	_title_label = Label.new()
	_title_label.text = "RPG Battler AI"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 36)
	title_panel.add_child(_title_label)

	# --- Spacer to push button panel to center ---
	var top_spacer := Control.new()
	top_spacer.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(top_spacer)

	# --- Center button panel ---
	var center_container := CenterContainer.new()
	center_container.size_flags_horizontal = SIZE_EXPAND_FILL
	root.add_child(center_container)

	_button_panel = PanelContainer.new()
	_button_panel.custom_minimum_size = Vector2(300, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.92, 0.92, 0.92, 1.0)
	panel_style.border_color = Color(0.0, 0.0, 0.0, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.set_content_margin_all(20)
	_button_panel.add_theme_stylebox_override("panel", panel_style)
	center_container.add_child(_button_panel)

	var button_vbox := VBoxContainer.new()
	button_vbox.add_theme_constant_override("separation", 8)
	_button_panel.add_child(button_vbox)

	# New Band
	var new_band_btn := Button.new()
	new_band_btn.text = "New Band"
	new_band_btn.custom_minimum_size = Vector2(260, 50)
	new_band_btn.pressed.connect(_on_new_band_pressed)
	button_vbox.add_child(new_band_btn)

	# Load Band
	var load_band_btn := Button.new()
	load_band_btn.text = "Load Band"
	load_band_btn.custom_minimum_size = Vector2(260, 50)
	load_band_btn.pressed.connect(_on_load_band_pressed)
	button_vbox.add_child(load_band_btn)

	# Skirmish
	var skirmish_btn := Button.new()
	skirmish_btn.text = "Skirmish"
	skirmish_btn.custom_minimum_size = Vector2(260, 50)
	skirmish_btn.pressed.connect(_on_skirmish_pressed)
	button_vbox.add_child(skirmish_btn)

	# Exit
	var exit_btn := Button.new()
	exit_btn.text = "Exit"
	exit_btn.custom_minimum_size = Vector2(260, 50)
	exit_btn.pressed.connect(_on_exit_pressed)
	button_vbox.add_child(exit_btn)

	# --- Spacer to push Dev Tools to bottom ---
	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(bottom_spacer)

	# --- Dev Tools (bottom, only in dev mode) ---
	if Dev.enabled:
		var dev_center := CenterContainer.new()
		dev_center.size_flags_horizontal = SIZE_EXPAND_FILL
		root.add_child(dev_center)

		_dev_tools_btn = Button.new()
		_dev_tools_btn.text = "Dev Tools"
		_dev_tools_btn.custom_minimum_size = Vector2(160, 40)
		_dev_tools_btn.pressed.connect(_on_dev_tools_pressed)
		dev_center.add_child(_dev_tools_btn)


# --- Button handlers ---

func _on_new_band_pressed() -> void:
	# Navigate to band management — the band select panel has create-band UI
	MatchData.clear()
	get_tree().change_scene_to_file("res://scenes/band/band_scene.tscn")


func _on_load_band_pressed() -> void:
	# Navigate to band management in default (band select/load) mode
	MatchData.clear()
	get_tree().change_scene_to_file("res://scenes/band/band_scene.tscn")


func _on_skirmish_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/skirmish/skirmish_scene.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()


func _on_dev_tools_pressed() -> void:
	var dev_menu := DevMenu.new()
	add_child(dev_menu)
