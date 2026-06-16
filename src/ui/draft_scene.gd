class_name DraftScene
extends Control
## Controls the party draft UI flow. Manages two PartyDraft instances
## (one per player) and a MatchBuilder for match construction.
## Spec reference: phase7-spec.md §6

enum FlowState { TIER_SELECT, DRAFT_PLAYER_A, DRAFT_PLAYER_B, MATCH_READY, BATTLE }

var _flow_state: int = FlowState.TIER_SELECT
var _match_builder: MatchBuilder
var _tier_id: String = ""
var _draft_a: PartyDraft
var _draft_b: PartyDraft
var _current_draft: PartyDraft
var _selected_map: MapData

# UI references (built in _ready)
var _tier_panel: VBoxContainer
var _draft_panel: VBoxContainer
var _match_panel: VBoxContainer
var _player_label: Label
var _bp_label: Label
var _count_label: Label
var _tier_info_label: Label
var _roster_grid: GridContainer
var _confirm_btn: Button
var _map_label: Label
var _summary_a: VBoxContainer
var _summary_b: VBoxContainer
var _start_btn: Button


func _ready() -> void:
	_match_builder = MatchBuilder.new(
		GameData.get_character,
		GameData.get_final_stats,
		GameData.all_maps,
		GameData.get_terrain,
		GameData.get_ability,
		GameData.get_job_class,
		GameData.get_item,
	)
	_build_ui()
	_show_tier_select()


# --- UI construction ---

func _build_ui() -> void:
	# Full-rect anchoring
	set_anchors_preset(PRESET_FULL_RECT)

	# Margin container for padding
	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	var root := VBoxContainer.new()
	margin.add_child(root)

	# --- Tier select panel ---
	_tier_panel = VBoxContainer.new()
	root.add_child(_tier_panel)

	var title := Label.new()
	title.text = "Select Match Tier"
	title.add_theme_font_size_override("font_size", 28)
	_tier_panel.add_child(title)

	_tier_panel.add_child(_spacer(16))

	var tier_buttons := VBoxContainer.new()
	_tier_panel.add_child(tier_buttons)

	for tier_id in _match_builder.get_tier_ids():
		var config := _match_builder.get_tier_config(tier_id)
		var btn := Button.new()
		btn.text = "%s  —  %d BP  ·  %d–%d characters" % [
			tier_id.capitalize(),
			int(config["bp_cap"]),
			int(config["min"]),
			int(config["max"])]
		btn.custom_minimum_size.y = 50
		btn.pressed.connect(_on_tier_selected.bind(tier_id))
		tier_buttons.add_child(btn)

	# --- Draft panel ---
	_draft_panel = VBoxContainer.new()
	_draft_panel.visible = false
	root.add_child(_draft_panel)

	_player_label = Label.new()
	_player_label.add_theme_font_size_override("font_size", 24)
	_draft_panel.add_child(_player_label)

	_draft_panel.add_child(_spacer(8))

	# Info bar
	var info_bar := HBoxContainer.new()
	_draft_panel.add_child(info_bar)

	_bp_label = Label.new()
	_bp_label.size_flags_horizontal = SIZE_EXPAND_FILL
	info_bar.add_child(_bp_label)

	_count_label = Label.new()
	_count_label.size_flags_horizontal = SIZE_EXPAND_FILL
	info_bar.add_child(_count_label)

	_tier_info_label = Label.new()
	info_bar.add_child(_tier_info_label)

	_draft_panel.add_child(_spacer(12))

	# Roster label
	var roster_label := Label.new()
	roster_label.text = "Available Characters"
	_draft_panel.add_child(roster_label)

	_draft_panel.add_child(_spacer(4))

	# Roster grid (4 columns)
	_roster_grid = GridContainer.new()
	_roster_grid.columns = 4
	_draft_panel.add_child(_roster_grid)

	_draft_panel.add_child(_spacer(12))

	# Confirm button
	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm Party"
	_confirm_btn.custom_minimum_size.y = 40
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	_draft_panel.add_child(_confirm_btn)

	# --- Match start panel ---
	_match_panel = VBoxContainer.new()
	_match_panel.visible = false
	root.add_child(_match_panel)

	var match_title := Label.new()
	match_title.text = "Match Ready"
	match_title.add_theme_font_size_override("font_size", 28)
	_match_panel.add_child(match_title)

	_match_panel.add_child(_spacer(16))

	_map_label = Label.new()
	_map_label.add_theme_font_size_override("font_size", 20)
	_match_panel.add_child(_map_label)

	_match_panel.add_child(_spacer(12))

	# Party summaries
	var summaries := HBoxContainer.new()
	_match_panel.add_child(summaries)

	_summary_a = VBoxContainer.new()
	_summary_a.size_flags_horizontal = SIZE_EXPAND_FILL
	summaries.add_child(_summary_a)

	_summary_b = VBoxContainer.new()
	_summary_b.size_flags_horizontal = SIZE_EXPAND_FILL
	summaries.add_child(_summary_b)

	_match_panel.add_child(_spacer(16))

	_start_btn = Button.new()
	_start_btn.text = "Start Battle"
	_start_btn.custom_minimum_size.y = 50
	_start_btn.pressed.connect(_on_start_battle_pressed)
	_match_panel.add_child(_start_btn)


func _spacer(height: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size.y = height
	return s


# --- Flow state transitions ---

func _show_tier_select() -> void:
	_flow_state = FlowState.TIER_SELECT
	_tier_panel.visible = true
	_draft_panel.visible = false
	_match_panel.visible = false


func _show_draft(player_name: String, draft: PartyDraft) -> void:
	_current_draft = draft
	_tier_panel.visible = false
	_draft_panel.visible = true
	_match_panel.visible = false
	_player_label.text = "%s — Draft Your Party" % player_name
	_tier_info_label.text = _tier_id.capitalize()
	_update_roster_grid()
	_update_info_bar()
	_confirm_btn.disabled = true


func _show_match_ready() -> void:
	_flow_state = FlowState.MATCH_READY
	_tier_panel.visible = false
	_draft_panel.visible = false
	_match_panel.visible = true
	_selected_map = _match_builder.select_random_map(_tier_id)
	if _selected_map:
		_map_label.text = "Map: %s" % _selected_map.id.replace("_", " ").capitalize()
	else:
		_map_label.text = "Error: No maps available for this tier"
		_start_btn.disabled = true

	_populate_summary(_summary_a, "Player A", _draft_a)
	_populate_summary(_summary_b, "Player B", _draft_b)


func _populate_summary(container: VBoxContainer, title: String, draft: PartyDraft) -> void:
	for child in container.get_children():
		child.queue_free()

	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 18)
	container.add_child(header)

	var total_bp := 0
	for id in draft.confirmed_ids():
		var c: CharacterData = GameData.get_character(id)
		if not c:
			continue
		var entry := Label.new()
		entry.text = "  %s (%d BP)" % [c.display_name, c.bp]
		container.add_child(entry)
		total_bp += c.bp

	var bp_total := Label.new()
	bp_total.text = "  Total: %d BP" % total_bp
	container.add_child(bp_total)


# --- Tier selection ---

func _on_tier_selected(tier_id: String) -> void:
	_tier_id = tier_id
	_draft_a = _match_builder.create_draft(tier_id)
	_flow_state = FlowState.DRAFT_PLAYER_A
	_show_draft("Player A", _draft_a)


# --- Character selection ---

func _on_character_clicked(character_id: String) -> void:
	if not _current_draft:
		return
	if character_id in _current_draft.selected_ids():
		_current_draft.remove_character(character_id)
	else:
		var err := _current_draft.add_character(character_id)
		if not err.is_empty():
			Log.info("DraftScene", err)
			return
	_update_roster_grid()
	_update_info_bar()


func _on_confirm_pressed() -> void:
	if not _current_draft:
		return
	var err := _current_draft.confirm()
	if not err.is_empty():
		Log.info("DraftScene", err)
		return

	if _flow_state == FlowState.DRAFT_PLAYER_A:
		_draft_b = _match_builder.create_draft(_tier_id)
		_flow_state = FlowState.DRAFT_PLAYER_B
		_show_draft("Player B", _draft_b)
	elif _flow_state == FlowState.DRAFT_PLAYER_B:
		_show_match_ready()


# --- Match start ---

func _on_start_battle_pressed() -> void:
	if not _selected_map or not _draft_a or not _draft_b:
		return
	var result := _match_builder.build_match(_draft_a, _draft_b, _selected_map)
	if not result["errors"].is_empty():
		for e in result["errors"]:
			Log.error("DraftScene", e)
		return
	var state: MatchState = result["state"]
	_start_battle(state)


func _start_battle(state: MatchState) -> void:
	MatchData.match_state = state
	MatchData.map_id = _selected_map.id
	Log.info("DraftScene", "Match ready — transitioning to battle on %s" % _selected_map.id)
	get_tree().change_scene_to_file("res://scenes/map/map_scene.tscn")


# --- UI update helpers ---

func _update_roster_grid() -> void:
	for child in _roster_grid.get_children():
		child.queue_free()

	var characters := GameData.all_characters()
	for c in characters:
		if not c is CharacterData:
			continue
		var char_data: CharacterData = c

		# Wrap each card in a VBoxContainer for button + icon rows
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)

		var btn := Button.new()

		# Show stats summary
		var fs: StatBlock = GameData.get_final_stats(char_data.id)
		var stats_line := ""
		if fs:
			stats_line = "\nSPD %d  ATK %d  DEF %d  HP %d" % [
				fs.effective("spd"), fs.effective("atk"),
				fs.effective("def"), fs.effective("hp")]

		btn.text = "%s\n%s · %d BP%s" % [
			char_data.display_name,
			char_data.classes[0].capitalize() if not char_data.classes.is_empty() else "",
			char_data.bp,
			stats_line]
		btn.custom_minimum_size = Vector2(180, 80)

		var is_selected: bool = char_data.id in _current_draft.selected_ids()
		var addable: bool = _current_draft.can_add(char_data.id)
		btn.disabled = not addable and not is_selected

		# Visual feedback for selected characters
		if is_selected:
			card.modulate = Color(0.5, 1.0, 0.5)

		var char_id := char_data.id
		btn.pressed.connect(_on_character_clicked.bind(char_id))
		card.add_child(btn)

		# Equipment icon row
		if not char_data.equipment.is_empty():
			var equip_row := HBoxContainer.new()
			equip_row.add_theme_constant_override("separation", 2)
			for eq_id in char_data.equipment:
				var icon := TextureRect.new()
				icon.texture = SymbolAtlas.get_icon(eq_id)
				icon.custom_minimum_size = Vector2(16, 16)
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				equip_row.add_child(icon)
			card.add_child(equip_row)

		# Ability icon row
		if not char_data.abilities.is_empty():
			var ability_row := HBoxContainer.new()
			ability_row.add_theme_constant_override("separation", 2)
			for ab_id in char_data.abilities:
				var icon := TextureRect.new()
				icon.texture = SymbolAtlas.get_icon(ab_id)
				icon.custom_minimum_size = Vector2(16, 16)
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				ability_row.add_child(icon)
			card.add_child(ability_row)

		_roster_grid.add_child(card)


func _update_info_bar() -> void:
	_bp_label.text = "BP: %d / %d" % [_current_draft.total_bp(), _current_draft.bp_cap()]
	_count_label.text = "Characters: %d / %d–%d" % [
		_current_draft.party_size(),
		_current_draft.min_characters(),
		_current_draft.max_characters()]
	_confirm_btn.disabled = not _current_draft.is_valid()
