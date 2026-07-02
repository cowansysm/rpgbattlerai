class_name SkirmishScene
extends Control
## Skirmish container: squad-size selection -> draft (reusing existing draft flow)
## -> deployment -> CT battle. Supports vs-AI and local hot-seat.
## Sets MatchData.mode = "skirmish" which forces TELEGRAPH_MODE off and wires
## ChargeTimeTurnSystem in BattleController.
## Spec reference: alpha-phaseA20-spec.md §5

enum FlowState { SETUP, DRAFT_PLAYER_A, DRAFT_PLAYER_B, MATCH_READY, BATTLE }

var _flow_state: int = FlowState.SETUP
var _match_builder: MatchBuilder
var _squad_size: int = 3
var _opponent_type: String = "ai"  # "ai" or "hot_seat"
var _tier_id: String = "skirmish"
var _draft_a: PartyDraft
var _draft_b: PartyDraft
var _current_draft: PartyDraft
var _selected_map: MapData

# UI references
var _setup_panel: VBoxContainer
var _draft_panel: VBoxContainer
var _match_panel: VBoxContainer
var _player_label: Label
var _bp_label: Label
var _count_label: Label
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
	_show_setup()


func _build_ui() -> void:
	set_anchors_preset(PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	var root := VBoxContainer.new()
	margin.add_child(root)

	# --- Setup panel: squad size + opponent type ---
	_setup_panel = VBoxContainer.new()
	root.add_child(_setup_panel)

	var title := Label.new()
	title.text = "Skirmish Setup"
	title.add_theme_font_size_override("font_size", 28)
	_setup_panel.add_child(title)

	_setup_panel.add_child(_spacer(16))

	# Opponent type selection
	var opp_label := Label.new()
	opp_label.text = "Opponent Type"
	opp_label.add_theme_font_size_override("font_size", 18)
	_setup_panel.add_child(opp_label)

	var opp_row := HBoxContainer.new()
	opp_row.add_theme_constant_override("separation", 12)
	_setup_panel.add_child(opp_row)

	var btn_ai := Button.new()
	btn_ai.text = "vs AI"
	btn_ai.custom_minimum_size = Vector2(120, 40)
	btn_ai.toggle_mode = true
	btn_ai.button_pressed = true
	opp_row.add_child(btn_ai)

	var btn_hotseat := Button.new()
	btn_hotseat.text = "Hot Seat"
	btn_hotseat.custom_minimum_size = Vector2(120, 40)
	btn_hotseat.toggle_mode = true
	opp_row.add_child(btn_hotseat)

	# Wire toggle lambdas after both buttons are declared (avoids forward-reference parse error)
	btn_ai.pressed.connect(func() -> void:
		_opponent_type = "ai"
		if btn_ai: btn_ai.button_pressed = true
		if btn_hotseat: btn_hotseat.button_pressed = false)
	btn_hotseat.pressed.connect(func() -> void:
		_opponent_type = "hot_seat"
		if btn_ai: btn_ai.button_pressed = false
		if btn_hotseat: btn_hotseat.button_pressed = true)

	_setup_panel.add_child(_spacer(16))

	# Squad size selection
	var size_label := Label.new()
	size_label.text = "Squad Size"
	size_label.add_theme_font_size_override("font_size", 18)
	_setup_panel.add_child(size_label)

	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 12)
	_setup_panel.add_child(size_row)

	var squad_sizes: Array = Constants.get_value("SKIRMISH_SQUAD_SIZES", [2, 3, 4, 5])
	for sz in squad_sizes:
		var s: int = int(sz)
		var btn := Button.new()
		btn.text = "%d" % s
		btn.custom_minimum_size = Vector2(60, 40)
		btn.toggle_mode = true
		btn.button_pressed = (s == _squad_size)
		btn.pressed.connect(_on_squad_size_pressed.bind(s, size_row))
		size_row.add_child(btn)

	_setup_panel.add_child(_spacer(24))

	var begin_btn := Button.new()
	begin_btn.text = "Begin Draft"
	begin_btn.custom_minimum_size = Vector2(160, 50)
	begin_btn.pressed.connect(_on_begin_draft)
	_setup_panel.add_child(begin_btn)

	_setup_panel.add_child(_spacer(16))

	var back_btn := Button.new()
	back_btn.text = "Back to Main Menu"
	back_btn.custom_minimum_size = Vector2(160, 40)
	back_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/draft/draft_scene.tscn"))
	_setup_panel.add_child(back_btn)

	# --- Draft panel (reused flow) ---
	_draft_panel = VBoxContainer.new()
	_draft_panel.visible = false
	_draft_panel.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(_draft_panel)

	_player_label = Label.new()
	_player_label.add_theme_font_size_override("font_size", 24)
	_draft_panel.add_child(_player_label)

	_draft_panel.add_child(_spacer(8))

	var info_bar := HBoxContainer.new()
	_draft_panel.add_child(info_bar)

	_bp_label = Label.new()
	_bp_label.size_flags_horizontal = SIZE_EXPAND_FILL
	info_bar.add_child(_bp_label)

	_count_label = Label.new()
	_count_label.size_flags_horizontal = SIZE_EXPAND_FILL
	info_bar.add_child(_count_label)

	_draft_panel.add_child(_spacer(12))

	var roster_scroll := ScrollContainer.new()
	roster_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_draft_panel.add_child(roster_scroll)

	_roster_grid = GridContainer.new()
	_roster_grid.columns = 4
	_roster_grid.size_flags_horizontal = SIZE_EXPAND_FILL
	roster_scroll.add_child(_roster_grid)

	_draft_panel.add_child(_spacer(12))

	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm Party"
	_confirm_btn.custom_minimum_size.y = 40
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	_draft_panel.add_child(_confirm_btn)

	# --- Match ready panel ---
	_match_panel = VBoxContainer.new()
	_match_panel.visible = false
	root.add_child(_match_panel)

	var match_title := Label.new()
	match_title.text = "Skirmish Ready"
	match_title.add_theme_font_size_override("font_size", 28)
	_match_panel.add_child(match_title)

	_match_panel.add_child(_spacer(16))

	_map_label = Label.new()
	_map_label.add_theme_font_size_override("font_size", 20)
	_match_panel.add_child(_map_label)

	_match_panel.add_child(_spacer(12))

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
	_start_btn.text = "Start Skirmish"
	_start_btn.custom_minimum_size.y = 50
	_start_btn.pressed.connect(_on_start_battle_pressed)
	_match_panel.add_child(_start_btn)


func _spacer(height: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size.y = height
	return s


# --- Flow transitions ---

func _show_setup() -> void:
	_flow_state = FlowState.SETUP
	_setup_panel.visible = true
	_draft_panel.visible = false
	_match_panel.visible = false


func _show_draft(player_name: String, draft: PartyDraft) -> void:
	_current_draft = draft
	_setup_panel.visible = false
	_draft_panel.visible = true
	_match_panel.visible = false
	_player_label.text = "%s — Draft Your Squad (%d units)" % [player_name, _squad_size]
	_update_roster_grid()
	_update_info_bar()
	_confirm_btn.disabled = true


func _show_match_ready() -> void:
	_flow_state = FlowState.MATCH_READY
	_setup_panel.visible = false
	_draft_panel.visible = false
	_match_panel.visible = true
	_selected_map = _match_builder.select_random_map(_tier_id)
	if _selected_map:
		_map_label.text = "Map: %s" % _selected_map.id.replace("_", " ").capitalize()
	else:
		_map_label.text = "Error: No maps available"
		_start_btn.disabled = true

	_populate_summary(_summary_a, "Player A", _draft_a)
	_populate_summary(_summary_b, "Player B", _draft_b)


# --- Event handlers ---

func _on_squad_size_pressed(size: int, row: HBoxContainer) -> void:
	_squad_size = size
	for child in row.get_children():
		if child is Button:
			child.button_pressed = false
	# Re-press the selected one (deferred to avoid toggle conflicts)
	for child in row.get_children():
		if child is Button and child.text == "%d" % size:
			child.button_pressed = true


func _on_begin_draft() -> void:
	_draft_a = _match_builder.create_draft(_tier_id)
	_flow_state = FlowState.DRAFT_PLAYER_A
	_show_draft("Player A", _draft_a)


func _on_character_clicked(character_id: String) -> void:
	if not _current_draft:
		return
	if character_id in _current_draft.selected_ids():
		_current_draft.remove_character(character_id)
	else:
		if _current_draft.party_size() >= _squad_size:
			return
		var err := _current_draft.add_character(character_id)
		if not err.is_empty():
			Log.info("SkirmishScene", err)
			return
	_update_roster_grid()
	_update_info_bar()


func _on_confirm_pressed() -> void:
	if not _current_draft:
		return
	var err := _current_draft.confirm()
	if not err.is_empty():
		Log.info("SkirmishScene", err)
		return

	if _flow_state == FlowState.DRAFT_PLAYER_A:
		if _opponent_type == "ai":
			# Auto-draft for AI
			_draft_b = _match_builder.create_draft(_tier_id)
			_auto_draft_ai(_draft_b)
			_show_match_ready()
		else:
			_draft_b = _match_builder.create_draft(_tier_id)
			_flow_state = FlowState.DRAFT_PLAYER_B
			_show_draft("Player B", _draft_b)
	elif _flow_state == FlowState.DRAFT_PLAYER_B:
		_show_match_ready()


func _on_start_battle_pressed() -> void:
	if not _selected_map or not _draft_a or not _draft_b:
		return
	var ai_teams: Array = []
	if _opponent_type == "ai":
		ai_teams = ["playerB"]
	var result := _match_builder.build_match(_draft_a, _draft_b, _selected_map, ai_teams)
	if not result["errors"].is_empty():
		for e in result["errors"]:
			Log.error("SkirmishScene", e)
		return
	var state: MatchState = result["state"]
	var ctrl: DeploymentController = result["controller"]

	# Set MatchData for skirmish mode
	MatchData.match_state = state
	MatchData.deployment_controller = ctrl
	MatchData.map_id = _selected_map.id
	MatchData.mode = "skirmish"
	MatchData.opponent_type = _opponent_type
	MatchData.skirmish_squad_size = _squad_size

	Log.info("SkirmishScene", "Skirmish ready — %s vs %s on %s" % [
		_opponent_type, "%d units" % _squad_size, _selected_map.id])
	get_tree().change_scene_to_file("res://scenes/map/map_scene.tscn")


# --- AI auto-draft ---

func _auto_draft_ai(draft: PartyDraft) -> void:
	## Simple AI draft: pick random characters up to squad size.
	var characters := GameData.all_characters()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_msec())

	# Shuffle characters
	var shuffled: Array = characters.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp

	var added := 0
	for c in shuffled:
		if added >= _squad_size:
			break
		if not c is CharacterData:
			continue
		var char_data: CharacterData = c
		# Skip characters already in Player A's draft
		if char_data.id in _draft_a.confirmed_ids():
			continue
		if draft.can_add(char_data.id):
			var err := draft.add_character(char_data.id)
			if err.is_empty():
				added += 1

	draft.confirm()


# --- UI helpers ---

func _update_roster_grid() -> void:
	for child in _roster_grid.get_children():
		child.queue_free()

	var characters := GameData.all_characters()
	for c in characters:
		if not c is CharacterData:
			continue
		var char_data: CharacterData = c

		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)

		var btn := Button.new()
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
		var at_max: bool = _current_draft.party_size() >= _squad_size and not is_selected
		btn.disabled = at_max and not is_selected

		if is_selected:
			card.modulate = Color(0.5, 1.0, 0.5)

		var char_id := char_data.id
		btn.pressed.connect(_on_character_clicked.bind(char_id))
		card.add_child(btn)

		_roster_grid.add_child(card)


func _update_info_bar() -> void:
	_bp_label.text = "BP: %d / %d" % [_current_draft.total_bp(), _current_draft.bp_cap()]
	_count_label.text = "Units: %d / %d" % [_current_draft.party_size(), _squad_size]
	_confirm_btn.disabled = _current_draft.party_size() < 1


func _populate_summary(container: VBoxContainer, title: String, draft: PartyDraft) -> void:
	for child in container.get_children():
		child.queue_free()

	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 18)
	container.add_child(header)

	for id in draft.confirmed_ids():
		var c: CharacterData = GameData.get_character(id)
		if not c:
			continue
		var entry := Label.new()
		entry.text = "  %s (%d BP)" % [c.display_name, c.bp]
		container.add_child(entry)
