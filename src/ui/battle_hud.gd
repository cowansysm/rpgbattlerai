class_name BattleHUD
extends CanvasLayer
## Full combat HUD overlay: unit info, action panel, ability/item browsers,
## combat log, team roster sidebar, and turn order display.
## Built programmatically following the DraftScene._build_ui() pattern.
## Spec reference: phase8-spec.md §4

signal action_selected(action_type: int)
signal ability_selected(ability_id: String)
signal item_selected(item_id: String)
signal finalize_move_pressed()
signal cancel_move_pressed()
signal unit_clicked(character_id: String)

# Action type constants matching the controller's expectations
const ACTION_MOVE := 0
const ACTION_ATTACK := 1
const ACTION_ABILITY := 2
const ACTION_ITEM := 3
const ACTION_DEFEND := 4
const ACTION_WAIT := 5

const MAX_LOG_ENTRIES := 100
const PANEL_BG := Color(0.0, 0.0, 0.0, 0.6)
const SIDEBAR_WIDTH := 220
const LOG_WIDTH := 250
const BOTTOM_BAR_HEIGHT := 90

# UI node references
var _root: Control

# Top bar
var _round_label: Label
var _turn_order_container: HBoxContainer

# Left sidebar (team roster)
var _roster_container: VBoxContainer
var _team_a_list: VBoxContainer
var _team_b_list: VBoxContainer

# Right sidebar (combat log)
var _log_scroll: ScrollContainer
var _log_list: VBoxContainer
var _log_count: int = 0

# Bottom bar
var _unit_info_panel: HBoxContainer
var _unit_name_label: Label
var _hp_bar: ProgressBar
var _ap_pip_1: Label
var _ap_pip_2: Label
var _status_label: Label

# Action panel
var _action_panel: HBoxContainer
var _btn_attack: Button
var _btn_abilities: Button
var _btn_items: Button
var _btn_defend: Button
var _btn_wait: Button

# Sub-panels (floating popups above bottom bar)
var _ability_popup: PanelContainer
var _item_popup: PanelContainer
var _ability_panel: VBoxContainer
var _item_panel: VBoxContainer

# Movement finalize/cancel
var _finalize_panel: HBoxContainer
var _btn_finalize: Button
var _btn_cancel_move: Button

# Targeting mode indicator
var _targeting_label: Label


func setup() -> void:
	## Must be called explicitly before any update methods.
	## Builds the UI immediately (does not wait for _ready).
	layer = 1
	_build_ui()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_top_bar()
	_build_left_sidebar()
	_build_right_sidebar()
	_build_bottom_bar()
	_build_floating_panels()


# --- Top bar ---

func _build_top_bar() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.custom_minimum_size.y = 36
	_apply_panel_bg(panel)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	panel.add_child(hbox)

	_round_label = Label.new()
	_round_label.text = "Round 1"
	_round_label.add_theme_font_size_override("font_size", 16)
	hbox.add_child(_round_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var turn_label := Label.new()
	turn_label.text = "Pending:"
	turn_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(turn_label)

	_turn_order_container = HBoxContainer.new()
	_turn_order_container.add_theme_constant_override("separation", 8)
	hbox.add_child(_turn_order_container)


# --- Left sidebar (team roster) ---

func _build_left_sidebar() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_top = 40
	panel.offset_bottom = -BOTTOM_BAR_HEIGHT
	panel.custom_minimum_size.x = SIDEBAR_WIDTH
	_apply_panel_bg(panel)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(scroll)

	_roster_container = VBoxContainer.new()
	_roster_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_roster_container)

	# Team A header
	var header_a := Label.new()
	header_a.text = "Team A"
	header_a.add_theme_font_size_override("font_size", 14)
	header_a.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
	_roster_container.add_child(header_a)

	_team_a_list = VBoxContainer.new()
	_roster_container.add_child(_team_a_list)

	_roster_container.add_child(_spacer(8))

	# Team B header
	var header_b := Label.new()
	header_b.text = "Team B"
	header_b.add_theme_font_size_override("font_size", 14)
	header_b.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	_roster_container.add_child(header_b)

	_team_b_list = VBoxContainer.new()
	_roster_container.add_child(_team_b_list)


# --- Right sidebar (combat log) ---

func _build_right_sidebar() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -LOG_WIDTH
	panel.offset_top = 40
	panel.offset_bottom = -BOTTOM_BAR_HEIGHT
	_apply_panel_bg(panel)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "Combat Log"
	header.add_theme_font_size_override("font_size", 14)
	vbox.add_child(header)

	_log_scroll = ScrollContainer.new()
	_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_log_scroll)

	_log_list = VBoxContainer.new()
	_log_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_scroll.add_child(_log_list)


# --- Bottom bar ---

func _build_bottom_bar() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -BOTTOM_BAR_HEIGHT
	panel.offset_left = SIDEBAR_WIDTH
	panel.offset_right = -LOG_WIDTH
	_apply_panel_bg(panel)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Unit info row
	_unit_info_panel = HBoxContainer.new()
	_unit_info_panel.add_theme_constant_override("separation", 12)
	_unit_info_panel.visible = false
	vbox.add_child(_unit_info_panel)

	_unit_name_label = Label.new()
	_unit_name_label.add_theme_font_size_override("font_size", 16)
	_unit_info_panel.add_child(_unit_name_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(120, 20)
	_hp_bar.show_percentage = false
	_unit_info_panel.add_child(_hp_bar)

	var hp_label := Label.new()
	hp_label.text = "HP"
	hp_label.add_theme_font_size_override("font_size", 12)
	_unit_info_panel.add_child(hp_label)

	var ap_box := HBoxContainer.new()
	ap_box.add_theme_constant_override("separation", 4)
	_unit_info_panel.add_child(ap_box)

	var ap_label := Label.new()
	ap_label.text = "AP:"
	ap_label.add_theme_font_size_override("font_size", 12)
	ap_box.add_child(ap_label)

	_ap_pip_1 = Label.new()
	_ap_pip_1.add_theme_font_size_override("font_size", 14)
	ap_box.add_child(_ap_pip_1)

	_ap_pip_2 = Label.new()
	_ap_pip_2.add_theme_font_size_override("font_size", 14)
	ap_box.add_child(_ap_pip_2)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	_unit_info_panel.add_child(_status_label)

	# Action buttons row
	_action_panel = HBoxContainer.new()
	_action_panel.add_theme_constant_override("separation", 8)
	_action_panel.visible = false
	vbox.add_child(_action_panel)

	_btn_attack = _make_action_btn("Attack [F]", ACTION_ATTACK)
	_btn_abilities = Button.new()
	_btn_abilities.text = "Abilities"
	_btn_abilities.custom_minimum_size = Vector2(90, 36)
	_btn_abilities.pressed.connect(_toggle_ability_panel)
	_action_panel.add_child(_btn_abilities)
	_btn_items = Button.new()
	_btn_items.text = "Items"
	_btn_items.custom_minimum_size = Vector2(70, 36)
	_btn_items.pressed.connect(_toggle_item_panel)
	_action_panel.add_child(_btn_items)
	_btn_defend = _make_action_btn("Defend [G]", ACTION_DEFEND)
	_btn_wait = _make_action_btn("Wait [X]", ACTION_WAIT)

	# Finalize/Cancel movement buttons
	_finalize_panel = HBoxContainer.new()
	_finalize_panel.add_theme_constant_override("separation", 8)
	_finalize_panel.visible = false
	vbox.add_child(_finalize_panel)

	_btn_finalize = Button.new()
	_btn_finalize.text = "Finalize Movement"
	_btn_finalize.custom_minimum_size = Vector2(160, 36)
	_btn_finalize.disabled = true
	_btn_finalize.pressed.connect(func() -> void: finalize_move_pressed.emit())
	_finalize_panel.add_child(_btn_finalize)

	_btn_cancel_move = Button.new()
	_btn_cancel_move.text = "Cancel"
	_btn_cancel_move.custom_minimum_size = Vector2(70, 36)
	_btn_cancel_move.disabled = true
	_btn_cancel_move.pressed.connect(func() -> void: cancel_move_pressed.emit())
	_finalize_panel.add_child(_btn_cancel_move)

	# Targeting mode label
	_targeting_label = Label.new()
	_targeting_label.text = "Select target (Escape to cancel)"
	_targeting_label.add_theme_font_size_override("font_size", 14)
	_targeting_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5))
	_targeting_label.visible = false
	vbox.add_child(_targeting_label)


func _build_floating_panels() -> void:
	var popup_width := 300
	var ability_max_height := 200
	var item_max_height := 160

	# Ability popup — floats above the bottom bar, scrollable
	_ability_popup = PanelContainer.new()
	_ability_popup.visible = false
	_ability_popup.anchor_left = 0.0
	_ability_popup.anchor_right = 0.0
	_ability_popup.anchor_top = 1.0
	_ability_popup.anchor_bottom = 1.0
	_ability_popup.offset_left = SIDEBAR_WIDTH
	_ability_popup.offset_right = SIDEBAR_WIDTH + popup_width
	_ability_popup.offset_top = -BOTTOM_BAR_HEIGHT - ability_max_height
	_ability_popup.offset_bottom = -BOTTOM_BAR_HEIGHT
	_apply_panel_bg(_ability_popup)
	_ability_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_ability_popup)

	var ability_scroll := ScrollContainer.new()
	ability_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ability_popup.add_child(ability_scroll)

	_ability_panel = VBoxContainer.new()
	_ability_panel.add_theme_constant_override("separation", 2)
	_ability_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ability_scroll.add_child(_ability_panel)

	# Item popup — floats above the bottom bar, scrollable
	_item_popup = PanelContainer.new()
	_item_popup.visible = false
	_item_popup.anchor_left = 0.0
	_item_popup.anchor_right = 0.0
	_item_popup.anchor_top = 1.0
	_item_popup.anchor_bottom = 1.0
	_item_popup.offset_left = SIDEBAR_WIDTH
	_item_popup.offset_right = SIDEBAR_WIDTH + popup_width
	_item_popup.offset_top = -BOTTOM_BAR_HEIGHT - item_max_height
	_item_popup.offset_bottom = -BOTTOM_BAR_HEIGHT
	_apply_panel_bg(_item_popup)
	_item_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_item_popup)

	var item_scroll := ScrollContainer.new()
	item_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_item_popup.add_child(item_scroll)

	_item_panel = VBoxContainer.new()
	_item_panel.add_theme_constant_override("separation", 2)
	_item_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_scroll.add_child(_item_panel)


# --- Public update methods ---

func show_unit_info(unit: BattleUnit) -> void:
	_unit_info_panel.visible = true
	var class_name_str := unit.character.classes[0].capitalize() if not unit.character.classes.is_empty() else ""
	_unit_name_label.text = "%s (%s)" % [unit.character.display_name, class_name_str]

	var max_hp: int = unit.stats.effective("hp")
	_hp_bar.max_value = max_hp
	_hp_bar.value = unit.current_hp

	_update_ap_pips(unit.ap_remaining)
	_update_status_display(unit)


func hide_unit_info() -> void:
	_unit_info_panel.visible = false


func show_action_panel(unit: BattleUnit, abilities: Array, items: Array,
		must_reserve_move: bool = false) -> void:
	_action_panel.visible = true
	_finalize_panel.visible = true

	var ap := unit.ap_remaining
	var rng: int = unit.stats.effective("rng")

	if must_reserve_move:
		# Only Move and Wait allowed; 1-AP combat actions disabled
		_btn_attack.disabled = true
		_btn_items.disabled = true
		_btn_defend.disabled = true
		_btn_wait.disabled = false
		# Abilities: keep enabled only if any ability costs >= base_ap (exempt)
		var has_exempt := false
		for a in abilities:
			if a is AbilityData and a.ap_cost >= unit.base_ap:
				has_exempt = true
				break
		_btn_abilities.disabled = not has_exempt or abilities.is_empty()
	else:
		_btn_attack.disabled = ap < 1 or rng <= 0
		_btn_abilities.disabled = ap < 1 or abilities.is_empty()
		_btn_items.disabled = ap < 1 or items.is_empty()
		_btn_defend.disabled = ap < 1
		_btn_wait.disabled = false

	_populate_ability_panel(abilities, ap, unit.base_ap, unit.has_moved)
	_populate_item_panel(items, ap)


func hide_action_panel() -> void:
	_action_panel.visible = false
	_ability_popup.visible = false
	_item_popup.visible = false
	_finalize_panel.visible = false


func set_targeting_mode(active: bool) -> void:
	_targeting_label.visible = active
	_action_panel.visible = not active
	_finalize_panel.visible = not active
	_ability_popup.visible = false
	_item_popup.visible = false


func set_finalize_enabled(enabled: bool) -> void:
	_finalize_panel.visible = true
	_btn_finalize.disabled = not enabled
	_btn_cancel_move.disabled = not enabled


func update_roster(state: MatchState, active_unit: BattleUnit,
		selectable_ids: Array = []) -> void:
	_update_team_list(_team_a_list, state.parties.get("playerA", []),
		active_unit, selectable_ids)
	_update_team_list(_team_b_list, state.parties.get("playerB", []),
		active_unit, selectable_ids)


func update_turn_order(state: MatchState) -> void:
	for child in _turn_order_container.get_children():
		child.queue_free()

	for team in state.parties.keys():
		for unit: BattleUnit in state.unactivated_units(team):
			var lbl := Label.new()
			lbl.text = unit.character.display_name.left(8)
			lbl.add_theme_font_size_override("font_size", 12)
			if unit.team == "playerA":
				lbl.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
			else:
				lbl.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
			_turn_order_container.add_child(lbl)


func update_round_info(round_number: int, team: String) -> void:
	var team_display := "Player A" if team == "playerA" else "Player B"
	_round_label.text = "Round %d - %s's Turn" % [round_number, team_display]


func show_round_end_info(round_number: int) -> void:
	_round_label.text = "Round %d Complete - Press R for next round" % round_number


func show_awaiting_activation(team: String) -> void:
	var team_display := "Player A" if team == "playerA" else "Player B"
	_round_label.text = "%s: Select a unit to activate" % team_display


func append_log(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size.x = LOG_WIDTH - 20
	_log_list.add_child(lbl)
	_log_count += 1

	# Trim old entries
	while _log_count > MAX_LOG_ENTRIES:
		var first_child := _log_list.get_child(0)
		first_child.queue_free()
		_log_count -= 1

	# Auto-scroll to bottom (deferred to wait for layout)
	_log_scroll.call_deferred("set_v_scroll", 999999)


func disable_actions_below_ap(ap: int) -> void:
	_btn_attack.disabled = ap < 1
	_btn_abilities.disabled = ap < 1
	_btn_defend.disabled = ap < 1


# --- Internal helpers ---

func _make_action_btn(text: String, action_type: int) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(90, 36)
	btn.pressed.connect(func() -> void: action_selected.emit(action_type))
	_action_panel.add_child(btn)
	return btn


func _toggle_ability_panel() -> void:
	_ability_popup.visible = not _ability_popup.visible
	_item_popup.visible = false


func _toggle_item_panel() -> void:
	_item_popup.visible = not _item_popup.visible
	_ability_popup.visible = false


func _populate_ability_panel(abilities: Array, current_ap: int,
		base_ap: int = 2, has_moved: bool = true) -> void:
	for child in _ability_panel.get_children():
		child.queue_free()

	# When movement is required, only abilities costing >= base_ap are exempt
	var must_reserve := base_ap >= 2 and not has_moved

	for a in abilities:
		if not a is AbilityData:
			continue
		var ability: AbilityData = a
		var btn := Button.new()

		# Format: "Fire 2   2 AP - R4 - burst 1\n  7 fire damage"
		var line1 := ability.display_name
		line1 += "   %d AP" % ability.ap_cost
		if ability.ability_range > 0:
			line1 += " - R%d" % ability.ability_range
		if not ability.area.is_empty():
			var shape: String = str(ability.area.get("shape", ""))
			var radius: int = int(ability.area.get("radius", 0))
			if shape and radius > 0:
				line1 += " - %s %d" % [shape, radius]

		var line2 := _format_effect_summary(ability.effect)
		btn.text = line1 + ("\n  " + line2 if not line2.is_empty() else "")
		btn.custom_minimum_size = Vector2(200, 40)

		# Disable if not enough AP, or if movement reserve blocks non-exempt abilities
		var blocked_by_reserve := must_reserve and current_ap <= 1 and ability.ap_cost < base_ap
		btn.disabled = current_ap < ability.ap_cost or blocked_by_reserve

		var aid := ability.id
		btn.pressed.connect(func() -> void:
			ability_selected.emit(aid)
			_ability_popup.visible = false)
		_ability_panel.add_child(btn)


func _populate_item_panel(items: Array, current_ap: int) -> void:
	for child in _item_panel.get_children():
		child.queue_free()

	for item_data in items:
		if not item_data is ItemData:
			continue
		var item: ItemData = item_data
		var btn := Button.new()
		btn.text = "%s   1 AP" % item.display_name
		btn.custom_minimum_size = Vector2(200, 36)
		btn.disabled = current_ap < 1

		var iid := item.id
		btn.pressed.connect(func() -> void:
			item_selected.emit(iid)
			_item_popup.visible = false)
		_item_panel.add_child(btn)


func _format_effect_summary(effect: Dictionary) -> String:
	var etype: String = str(effect.get("effect_type", ""))
	match etype:
		"damage":
			var val: int = int(effect.get("value", 0))
			var element: String = str(effect.get("element", ""))
			if not element.is_empty():
				return "%d %s damage" % [val, element]
			return "%d damage" % val
		"heal":
			var val: int = int(effect.get("value", 0))
			return "heal %d HP" % val
		"buff":
			var stat: String = str(effect.get("stat", ""))
			var val: int = int(effect.get("value", 0))
			var dur: int = int(effect.get("duration", 1))
			return "+%d %s (%d rounds)" % [val, stat.to_upper(), dur]
		"status":
			var status_id: String = str(effect.get("status_id", ""))
			var dur: int = int(effect.get("duration", 1))
			return "%s (%d rounds)" % [status_id, dur]
	return ""


func _update_ap_pips(ap: int) -> void:
	_ap_pip_1.text = "[*]" if ap >= 1 else "[ ]"
	_ap_pip_2.text = "[*]" if ap >= 2 else "[ ]"


func _update_status_display(unit: BattleUnit) -> void:
	if unit.status_effects.is_empty():
		_status_label.text = ""
		return
	var parts: Array = []
	for s in unit.status_effects:
		parts.append("%s(%d)" % [s["id"], s["duration"]])
	_status_label.text = " ".join(parts)


func _update_team_list(container: VBoxContainer, units: Array,
		active_unit: BattleUnit, selectable_ids: Array = []) -> void:
	for child in container.get_children():
		child.queue_free()

	for unit: BattleUnit in units:
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 1)

		# Row 1: Name + activation indicator
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 4)
		card.add_child(name_row)

		var name_lbl := Label.new()
		name_lbl.text = unit.character.display_name
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_row.add_child(name_lbl)

		var indicator := Label.new()
		indicator.add_theme_font_size_override("font_size", 11)
		if unit.is_downed:
			indicator.text = "DOWN"
			indicator.add_theme_color_override("font_color", Color(1.0, 0.5, 0.1))
		elif unit.current_hp <= 0:
			indicator.text = "X"
			indicator.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))
		elif unit.is_activated:
			indicator.text = "done"
			indicator.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		else:
			indicator.text = "ready"
			indicator.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		name_row.add_child(indicator)

		# Row 2: HP bar with numbers
		var hp_row := HBoxContainer.new()
		hp_row.add_theme_constant_override("separation", 4)
		card.add_child(hp_row)

		var hp_label := Label.new()
		hp_label.text = "HP"
		hp_label.add_theme_font_size_override("font_size", 11)
		hp_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		hp_label.custom_minimum_size.x = 22
		hp_row.add_child(hp_label)

		var max_hp: int = unit.stats.effective("hp")
		var hp_bar := ProgressBar.new()
		hp_bar.custom_minimum_size = Vector2(0, 14)
		hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hp_bar.show_percentage = false
		hp_bar.max_value = max_hp
		hp_bar.value = unit.current_hp
		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = _hp_bar_color(unit.current_hp, max_hp)
		hp_bar.add_theme_stylebox_override("fill", fill_style)
		var bg_style := StyleBoxFlat.new()
		bg_style.bg_color = Color(0.15, 0.15, 0.15)
		hp_bar.add_theme_stylebox_override("background", bg_style)
		hp_row.add_child(hp_bar)

		var hp_num := Label.new()
		hp_num.text = "%d/%d" % [unit.current_hp, max_hp]
		hp_num.add_theme_font_size_override("font_size", 11)
		hp_num.custom_minimum_size.x = 42
		hp_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hp_row.add_child(hp_num)

		# Row 3: AP pips with numbers
		var ap_row := HBoxContainer.new()
		ap_row.add_theme_constant_override("separation", 4)
		card.add_child(ap_row)

		var ap_label := Label.new()
		ap_label.text = "AP"
		ap_label.add_theme_font_size_override("font_size", 11)
		ap_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		ap_label.custom_minimum_size.x = 22
		ap_row.add_child(ap_label)

		var pip_box := HBoxContainer.new()
		pip_box.add_theme_constant_override("separation", 2)
		ap_row.add_child(pip_box)

		for i in range(unit.base_ap):
			var pip := Label.new()
			pip.add_theme_font_size_override("font_size", 12)
			if unit.ap_remaining > i:
				pip.text = "■"
				pip.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
			else:
				pip.text = "□"
				pip.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
			pip_box.add_child(pip)

		var ap_num := Label.new()
		ap_num.text = "%d/%d" % [unit.ap_remaining, unit.base_ap]
		ap_num.add_theme_font_size_override("font_size", 11)
		ap_row.add_child(ap_num)

		# Separator between units
		var sep := HSeparator.new()
		sep.add_theme_constant_override("separation", 4)
		sep.modulate.a = 0.3
		card.add_child(sep)

		# Dim downed/removed units
		if unit.is_downed:
			card.modulate.a = 0.6
		elif unit.current_hp <= 0:
			card.modulate.a = 0.3

		# Highlight active unit
		if unit == active_unit:
			name_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5))

		# Clickable selection during AWAITING_ACTIVATION
		if unit.character.id in selectable_ids:
			card.mouse_filter = Control.MOUSE_FILTER_STOP
			card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			name_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
			var char_id := unit.character.id
			card.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					unit_clicked.emit(char_id))

		container.add_child(card)


func _hp_bar_color(current: int, maximum: int) -> Color:
	if maximum <= 0:
		return Color(0.3, 0.3, 0.3)
	var ratio := float(current) / float(maximum)
	if ratio > 0.5:
		return Color(0.2, 0.7, 0.2)
	elif ratio > 0.25:
		return Color(0.85, 0.7, 0.1)
	return Color(0.8, 0.15, 0.15)


func _apply_panel_bg(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)


func _spacer(height: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size.y = height
	return s
