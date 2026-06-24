class_name DevOverridesPanel
extends PanelContainer
## Floating panel for toggling DevOverrides flags.
## Opened from the DevMenu. Dynamic UI, no scene file.

var _vbox: VBoxContainer

# Toggle references for reading state
var _chk_infinite_gold: CheckBox
var _chk_free_recruit: CheckBox
var _chk_infinite_ap: CheckBox
var _chk_infinite_wp: CheckBox
var _chk_invincible: CheckBox
var _chk_one_hit_kill: CheckBox
var _roster_cap_spin: SpinBox


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(PRESET_CENTER)
	offset_left = -160
	offset_right = 160
	offset_top = -200
	offset_bottom = 200

	_vbox = VBoxContainer.new()
	add_child(_vbox)

	var title := Label.new()
	title.text = "Dev Overrides"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	_vbox.add_child(title)

	_vbox.add_child(HSeparator.new())

	# --- Economy toggles ---
	var econ_label := Label.new()
	econ_label.text = "Economy"
	econ_label.add_theme_font_size_override("font_size", 14)
	_vbox.add_child(econ_label)

	_chk_infinite_gold = _add_checkbox("Infinite Gold", "DEV_INFINITE_GOLD")
	_chk_free_recruit = _add_checkbox("Free Recruits", "DEV_FREE_RECRUIT")

	var cap_row := HBoxContainer.new()
	_vbox.add_child(cap_row)
	var cap_label := Label.new()
	cap_label.text = "Roster Cap:"
	cap_label.size_flags_horizontal = SIZE_EXPAND_FILL
	cap_row.add_child(cap_label)
	_roster_cap_spin = SpinBox.new()
	_roster_cap_spin.min_value = 1
	_roster_cap_spin.max_value = 99
	_roster_cap_spin.value = Constants.get_value("ROSTER_CAP", 12)
	cap_row.add_child(_roster_cap_spin)
	var cap_btn := Button.new()
	cap_btn.text = "Set"
	cap_btn.pressed.connect(_on_roster_cap_set)
	cap_row.add_child(cap_btn)

	_vbox.add_child(HSeparator.new())

	# --- Combat toggles ---
	var combat_label := Label.new()
	combat_label.text = "Combat"
	combat_label.add_theme_font_size_override("font_size", 14)
	_vbox.add_child(combat_label)

	_chk_infinite_ap = _add_checkbox("Infinite AP", "DEV_INFINITE_AP")
	_chk_infinite_wp = _add_checkbox("Infinite WP", "DEV_INFINITE_WP")
	_chk_invincible = _add_checkbox("Invincible Player", "DEV_INVINCIBLE")
	_chk_one_hit_kill = _add_checkbox("One-Hit Kill", "DEV_ONE_HIT_KILL")

	_vbox.add_child(HSeparator.new())

	# --- Actions ---
	var clear_btn := Button.new()
	clear_btn.text = "Clear All Overrides"
	clear_btn.pressed.connect(_on_clear_all)
	_vbox.add_child(clear_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_on_close)
	_vbox.add_child(close_btn)


func _add_checkbox(label_text: String, override_key: String) -> CheckBox:
	var chk := CheckBox.new()
	chk.text = label_text
	chk.button_pressed = DevOverrides.get_flag(override_key, false)
	chk.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			DevOverrides.set_override(override_key, true)
		else:
			DevOverrides.clear_override(override_key))
	_vbox.add_child(chk)
	return chk


func _on_roster_cap_set() -> void:
	DevOverrides.set_override("DEV_ROSTER_CAP", int(_roster_cap_spin.value))


func _on_clear_all() -> void:
	DevOverrides.clear_all()
	_chk_infinite_gold.button_pressed = false
	_chk_free_recruit.button_pressed = false
	_chk_infinite_ap.button_pressed = false
	_chk_infinite_wp.button_pressed = false
	_chk_invincible.button_pressed = false
	_chk_one_hit_kill.button_pressed = false
	_roster_cap_spin.value = Constants.get_value("ROSTER_CAP", 12)


func _on_close() -> void:
	queue_free()
