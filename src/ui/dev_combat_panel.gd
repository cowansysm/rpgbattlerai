class_name DevCombatPanel
extends CanvasLayer
## In-combat cheat panel. Provides HP/WP/AP manipulation, kill/revive,
## match control, and combat toggle overrides.
## Instantiated by BattleController when Dev.enabled is true.

var _controller: Node  # BattleController
var _panel: PanelContainer
var _vbox: VBoxContainer
var _visible: bool = false

# Current unit widgets
var _unit_label: Label
var _hp_spin: SpinBox
var _wp_spin: SpinBox
var _ap_spin: SpinBox

# Unit selector (all units)
var _unit_selector: OptionButton
var _unit_refs: Array = []  # Parallel array of BattleUnit refs

# Toggle state (tracked locally, synced to DevOverrides)
var _chk_infinite_ap: CheckBox
var _chk_infinite_wp: CheckBox
var _chk_invincible: CheckBox
var _chk_one_hit_kill: CheckBox

# AP/WP tracking for toggle enforcement
var _last_ap: int = -1
var _last_wp: int = -1


func setup(controller: Node) -> void:
	_controller = controller


func _ready() -> void:
	_build_ui()
	_panel.visible = false


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -260
	_panel.offset_right = -10
	_panel.offset_top = 10
	_panel.offset_bottom = 600

	# Semi-transparent background
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.85)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.5, 0.5, 0.6, 0.8)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_vbox)

	var title := Label.new()
	title.text = "Combat Cheats"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color.ORANGE_RED)
	_vbox.add_child(title)

	_vbox.add_child(HSeparator.new())

	# --- Current Unit Section ---
	_unit_label = Label.new()
	_unit_label.text = "No active unit"
	_unit_label.add_theme_font_size_override("font_size", 13)
	_vbox.add_child(_unit_label)

	_hp_spin = _add_stat_row("HP", 0, 999, _on_set_hp)
	_wp_spin = _add_stat_row("WP", 0, 999, _on_set_wp)
	_ap_spin = _add_stat_row("AP", 0, 10, _on_set_ap)

	var heal_btn := Button.new()
	heal_btn.text = "Full Heal Current"
	heal_btn.pressed.connect(_on_full_heal_current)
	_vbox.add_child(heal_btn)

	var kill_current_btn := Button.new()
	kill_current_btn.text = "Kill Current Unit"
	kill_current_btn.pressed.connect(_on_kill_current)
	_vbox.add_child(kill_current_btn)

	_vbox.add_child(HSeparator.new())

	# --- All Units Section ---
	var sel_label := Label.new()
	sel_label.text = "Target Unit:"
	sel_label.add_theme_font_size_override("font_size", 13)
	_vbox.add_child(sel_label)

	_unit_selector = OptionButton.new()
	_unit_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_child(_unit_selector)

	var btn_row1 := HBoxContainer.new()
	_vbox.add_child(btn_row1)

	var kill_btn := Button.new()
	kill_btn.text = "Kill"
	kill_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kill_btn.pressed.connect(_on_kill_selected)
	btn_row1.add_child(kill_btn)

	var revive_btn := Button.new()
	revive_btn.text = "Revive"
	revive_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	revive_btn.pressed.connect(_on_revive_selected)
	btn_row1.add_child(revive_btn)

	var heal_sel_btn := Button.new()
	heal_sel_btn.text = "Heal"
	heal_sel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heal_sel_btn.pressed.connect(_on_heal_selected)
	btn_row1.add_child(heal_sel_btn)

	_vbox.add_child(HSeparator.new())

	# --- Match Control ---
	var match_label := Label.new()
	match_label.text = "Match Control"
	match_label.add_theme_font_size_override("font_size", 13)
	_vbox.add_child(match_label)

	var win_row := HBoxContainer.new()
	_vbox.add_child(win_row)

	var win_a_btn := Button.new()
	win_a_btn.text = "Player A Wins"
	win_a_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	win_a_btn.pressed.connect(_on_force_win_a)
	win_row.add_child(win_a_btn)

	var win_b_btn := Button.new()
	win_b_btn.text = "Player B Wins"
	win_b_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	win_b_btn.pressed.connect(_on_force_win_b)
	win_row.add_child(win_b_btn)

	_vbox.add_child(HSeparator.new())

	# --- Toggles ---
	var toggle_label := Label.new()
	toggle_label.text = "Toggles"
	toggle_label.add_theme_font_size_override("font_size", 13)
	_vbox.add_child(toggle_label)

	_chk_infinite_ap = _add_toggle("Infinite AP", "DEV_INFINITE_AP")
	_chk_infinite_wp = _add_toggle("Infinite WP", "DEV_INFINITE_WP")
	_chk_invincible = _add_toggle("Invincible Player", "DEV_INVINCIBLE")
	_chk_one_hit_kill = _add_toggle("One-Hit Kill", "DEV_ONE_HIT_KILL")

	_vbox.add_child(HSeparator.new())

	# --- Close ---
	var close_btn := Button.new()
	close_btn.text = "Close [F11]"
	close_btn.pressed.connect(_toggle_visible)
	_vbox.add_child(close_btn)


func _add_stat_row(label_text: String, min_val: int, max_val: int, on_set: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	_vbox.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.custom_minimum_size.x = 30
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	var btn := Button.new()
	btn.text = "Set"
	btn.pressed.connect(on_set)
	row.add_child(btn)
	return spin


func _add_toggle(label_text: String, override_key: String) -> CheckBox:
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


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		_toggle_visible()
		get_viewport().set_input_as_handled()


func _toggle_visible() -> void:
	_visible = not _visible
	_panel.visible = _visible
	if _visible:
		_refresh()


func _process(_delta: float) -> void:
	if not _visible:
		return
	var state := _get_state()
	if state == null:
		return
	var unit: BattleUnit = state.current_unit
	if unit == null:
		return
	# Enforce combat toggles via polling
	if DevOverrides.get_flag("DEV_INFINITE_AP", false):
		if unit.ap_remaining < unit.base_ap and unit.team != _get_ai_team(state):
			unit.ap_remaining = unit.base_ap
	if DevOverrides.get_flag("DEV_INFINITE_WP", false):
		if unit.team != _get_ai_team(state):
			var max_wp: int = unit.stats.effective("wp")
			unit.current_wp = max_wp


func _get_state() -> MatchState:
	if _controller and _controller.has_method("get_match_state"):
		return _controller.get_match_state()
	return null


func _get_hud() -> Node:
	if _controller and _controller.has_method("get_hud"):
		return _controller.get_hud()
	return null


func _get_pawn_manager() -> Node:
	if _controller and _controller.has_method("get_pawn_manager"):
		return _controller.get_pawn_manager()
	return null


func _get_ai_team(state: MatchState) -> String:
	if not state.ai_teams.is_empty():
		return str(state.ai_teams[0])
	return ""


func _refresh() -> void:
	var state := _get_state()
	if state == null:
		return
	_refresh_current_unit(state)
	_refresh_unit_selector(state)


func _refresh_current_unit(state: MatchState) -> void:
	var unit: BattleUnit = state.current_unit
	if unit == null:
		_unit_label.text = "No active unit"
		return
	_unit_label.text = "%s (%s) [%s]" % [unit.character.display_name, unit.team,
		"alive" if unit.is_alive() else "downed"]
	_hp_spin.max_value = unit.stats.effective("hp")
	_hp_spin.value = unit.current_hp
	_wp_spin.max_value = unit.stats.effective("wp")
	_wp_spin.value = unit.current_wp
	_ap_spin.value = unit.ap_remaining


func _refresh_unit_selector(state: MatchState) -> void:
	_unit_selector.clear()
	_unit_refs.clear()
	for team in state.parties.keys():
		for unit: BattleUnit in state.parties[team]:
			var status := "alive" if unit.is_alive() else ("downed" if unit.is_downed else "dead")
			_unit_selector.add_item("%s [%s] (%s)" % [unit.character.display_name, team, status])
			_unit_refs.append(unit)


func _get_selected_unit() -> BattleUnit:
	var idx: int = _unit_selector.selected
	if idx >= 0 and idx < _unit_refs.size():
		return _unit_refs[idx] as BattleUnit
	return null


func _refresh_hud() -> void:
	var state := _get_state()
	var hud := _get_hud()
	if state and hud:
		hud.update_roster(state, state.current_unit)
		if state.current_unit:
			hud.show_unit_info(state.current_unit)


# --- Current unit handlers ---

func _on_set_hp() -> void:
	var state := _get_state()
	if state == null or state.current_unit == null:
		return
	DevCheatService.set_unit_hp(state.current_unit, int(_hp_spin.value))
	_refresh_hud()
	_refresh()


func _on_set_wp() -> void:
	var state := _get_state()
	if state == null or state.current_unit == null:
		return
	DevCheatService.set_unit_wp(state.current_unit, int(_wp_spin.value))
	_refresh_hud()
	_refresh()


func _on_set_ap() -> void:
	var state := _get_state()
	if state == null or state.current_unit == null:
		return
	DevCheatService.set_unit_ap(state.current_unit, int(_ap_spin.value))
	_refresh_hud()
	_refresh()


func _on_full_heal_current() -> void:
	var state := _get_state()
	if state == null or state.current_unit == null:
		return
	DevCheatService.heal_unit_full(state.current_unit)
	_refresh_hud()
	_refresh()


func _on_kill_current() -> void:
	var state := _get_state()
	if state == null or state.current_unit == null:
		return
	DevCheatService.kill_unit(state.current_unit, state.round_number)
	_refresh_hud()
	_refresh()
	_try_check_match_over()


# --- Selected unit handlers ---

func _on_kill_selected() -> void:
	var unit := _get_selected_unit()
	if unit == null:
		return
	var state := _get_state()
	if state == null:
		return
	DevCheatService.kill_unit(unit, state.round_number)
	_refresh_hud()
	_refresh()
	_try_check_match_over()


func _on_revive_selected() -> void:
	var unit := _get_selected_unit()
	if unit == null:
		return
	DevCheatService.revive_unit(unit)
	_refresh_hud()
	_refresh()


func _on_heal_selected() -> void:
	var unit := _get_selected_unit()
	if unit == null:
		return
	DevCheatService.heal_unit_full(unit)
	_refresh_hud()
	_refresh()


# --- Match control ---

func _on_force_win_a() -> void:
	var state := _get_state()
	if state == null:
		return
	DevCheatService.force_win(state, "playerA")
	_refresh_hud()
	_try_check_match_over()


func _on_force_win_b() -> void:
	var state := _get_state()
	if state == null:
		return
	DevCheatService.force_win(state, "playerB")
	_refresh_hud()
	_try_check_match_over()


func _try_check_match_over() -> void:
	if _controller and _controller.has_method("check_match_over_now"):
		_controller.check_match_over_now()
