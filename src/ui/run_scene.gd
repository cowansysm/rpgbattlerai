class_name RunScene
extends Control
## Main scene for the roguelike run. Displays the run map, dispatches node
## resolution, handles battle hand-off and return, and manages overlays for
## events, shop, rest, and run outcomes.

enum OverlayState { NONE, NODE_PREVIEW, EVENT_OUTCOME, SHOP, REST_OUTCOME,
	PERMADEATH, RUN_OUTCOME, BATTLE_REWARDS }

const PANEL_BG := Color(0.12, 0.12, 0.16, 0.92)

var _overlay_state: int = OverlayState.NONE
var _run_controller: RunController
var _run: RunState
var _band: BattleBand
var _pending_node_id: String = ""
var _name_gen: NameGenerator

# UI elements
var _map_display: RunMapDisplay
var _sidebar: VBoxContainer
var _band_info_label: Label
var _roster_list: VBoxContainer
var _node_preview: VBoxContainer
var _node_preview_label: Label
var _advance_btn: Button
var _overlay_container: PanelContainer
var _overlay_label: Label
var _overlay_effects_label: Label
var _overlay_dismiss_btn: Button
var _outcome_overlay: PanelContainer
var _outcome_label: Label
var _outcome_details: Label
var _outcome_btn: Button
var _shop_overlay: PanelContainer
var _shop_gold_label: Label
var _shop_item_list: VBoxContainer


func _ready() -> void:
	_run_controller = RunController.new()
	_run_controller.set_meta_unlocks_provider(GameData.get_meta_unlocks)
	_name_gen = NameGenerator.new()
	_name_gen.load_tables()
	_build_ui()
	_initialize_run()
	_update_display()


func _initialize_run() -> void:
	# Check for battle result return first
	if MatchData.battle_result != null:
		_band = MatchData.active_band
		if MatchData.active_run is RunState:
			_run = MatchData.active_run as RunState
		elif SaveManager.active_run is RunState:
			_run = SaveManager.active_run as RunState
		_process_battle_return(MatchData.battle_result as Dictionary)
		MatchData.battle_result = null
		MatchData.active_run = null
		MatchData.run_node_id = ""
		return

	# Resume existing run or embark new
	_band = MatchData.active_band
	if _band == null and SaveManager.active_run is RunState:
		var saved_run: RunState = SaveManager.active_run as RunState
		_band = SaveManager.get_band(saved_run.band_id)

	if SaveManager.active_run is RunState:
		_run = SaveManager.active_run as RunState
		Log.info("RunScene", "Resumed run %s at node %s" % [_run.run_id, _run.position])
	elif _band != null:
		var seed_val: int = Time.get_ticks_usec()
		var cfg: Dictionary = GameData.get_run_config()
		# Resolve eligible starting boons from profile and auto-apply
		var boons: Array[Dictionary] = MetaUnlockEngine.resolve_boons(
			SaveManager.profile, GameData.get_meta_unlocks())
		_run = _run_controller.embark(_band, seed_val, cfg, boons)
		Log.info("RunScene", "Embarked on new run %s (boons: %d)" % [_run.run_id, boons.size()])
	else:
		Log.error("RunScene", "No band available for run")


# --- UI Construction ---

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	add_child(margin)

	var split := HSplitContainer.new()
	split.dragger_visibility = SplitContainer.DRAGGER_HIDDEN
	margin.add_child(split)

	# Left: map area
	var map_panel := PanelContainer.new()
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_stretch_ratio = 3.0
	_apply_panel_bg(map_panel)
	split.add_child(map_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	map_panel.add_child(scroll)

	_map_display = RunMapDisplay.new()
	_map_display.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.add_child(_map_display)
	_map_display.node_clicked.connect(_on_node_clicked)
	_map_display.node_hovered.connect(_on_node_hovered)

	# Right: sidebar
	var sidebar_panel := PanelContainer.new()
	sidebar_panel.custom_minimum_size.x = 260
	sidebar_panel.size_flags_horizontal = Control.SIZE_FILL
	_apply_panel_bg(sidebar_panel)
	split.add_child(sidebar_panel)

	var sidebar_margin := MarginContainer.new()
	sidebar_margin.add_theme_constant_override("margin_left", 10)
	sidebar_margin.add_theme_constant_override("margin_right", 10)
	sidebar_margin.add_theme_constant_override("margin_top", 10)
	sidebar_margin.add_theme_constant_override("margin_bottom", 10)
	sidebar_panel.add_child(sidebar_margin)

	_sidebar = VBoxContainer.new()
	sidebar_margin.add_child(_sidebar)

	# Band info header
	_band_info_label = Label.new()
	_band_info_label.add_theme_font_size_override("font_size", 16)
	_sidebar.add_child(_band_info_label)

	_sidebar.add_child(_make_separator())

	# Roster list
	var roster_header := Label.new()
	roster_header.text = "Roster"
	roster_header.add_theme_font_size_override("font_size", 14)
	_sidebar.add_child(roster_header)

	var roster_scroll := ScrollContainer.new()
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_sidebar.add_child(roster_scroll)

	_roster_list = VBoxContainer.new()
	roster_scroll.add_child(_roster_list)

	_sidebar.add_child(_make_separator())

	# Node preview
	_node_preview = VBoxContainer.new()
	_node_preview.visible = false
	_sidebar.add_child(_node_preview)

	_node_preview_label = Label.new()
	_node_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_node_preview.add_child(_node_preview_label)

	_advance_btn = Button.new()
	_advance_btn.text = "Advance"
	_advance_btn.custom_minimum_size.y = 36
	_advance_btn.pressed.connect(_on_advance_confirmed)
	_node_preview.add_child(_advance_btn)

	_sidebar.add_child(_make_separator())

	# Abandon run button
	var abandon_btn := Button.new()
	abandon_btn.text = "Abandon Run"
	abandon_btn.custom_minimum_size.y = 32
	abandon_btn.pressed.connect(_on_abandon_run)
	_sidebar.add_child(abandon_btn)

	# Dev tools (only when dev flag is on)
	if Dev.enabled:
		_build_dev_panel()

	# Overlays (initially hidden)
	_build_overlay()
	_build_outcome_overlay()
	_build_shop_overlay()


func _build_overlay() -> void:
	_overlay_container = PanelContainer.new()
	_overlay_container.set_anchors_and_offsets_preset(PRESET_CENTER)
	_overlay_container.custom_minimum_size = Vector2(400, 250)
	_overlay_container.visible = false
	_apply_panel_bg(_overlay_container)
	add_child(_overlay_container)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_overlay_container.add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	_overlay_label = Label.new()
	_overlay_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_overlay_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_overlay_label)

	vbox.add_child(_make_spacer(10))

	_overlay_effects_label = Label.new()
	_overlay_effects_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_overlay_effects_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6))
	vbox.add_child(_overlay_effects_label)

	vbox.add_child(_make_spacer(15))

	_overlay_dismiss_btn = Button.new()
	_overlay_dismiss_btn.text = "Continue"
	_overlay_dismiss_btn.custom_minimum_size.y = 36
	_overlay_dismiss_btn.pressed.connect(_on_overlay_dismissed)
	vbox.add_child(_overlay_dismiss_btn)


func _build_outcome_overlay() -> void:
	_outcome_overlay = PanelContainer.new()
	_outcome_overlay.set_anchors_and_offsets_preset(PRESET_CENTER)
	_outcome_overlay.custom_minimum_size = Vector2(450, 300)
	_outcome_overlay.visible = false
	_apply_panel_bg(_outcome_overlay)
	add_child(_outcome_overlay)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 25)
	margin.add_theme_constant_override("margin_right", 25)
	margin.add_theme_constant_override("margin_top", 25)
	margin.add_theme_constant_override("margin_bottom", 25)
	_outcome_overlay.add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	_outcome_label = Label.new()
	_outcome_label.add_theme_font_size_override("font_size", 24)
	_outcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_outcome_label)

	vbox.add_child(_make_spacer(15))

	_outcome_details = Label.new()
	_outcome_details.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_outcome_details)

	vbox.add_child(_make_spacer(20))

	_outcome_btn = Button.new()
	_outcome_btn.text = "Return to Menu"
	_outcome_btn.custom_minimum_size.y = 40
	_outcome_btn.pressed.connect(_on_run_finished)
	vbox.add_child(_outcome_btn)


# --- Display Updates ---

func _update_display() -> void:
	if _run == null or _run.graph == null:
		return
	_map_display.set_state(_run.graph, _run.visited, _run.position,
		_run.graph.next_nodes(_run.position))
	_refresh_sidebar()
	_node_preview.visible = false
	_pending_node_id = ""


func _refresh_sidebar() -> void:
	if _band == null or _run == null:
		return
	_band_info_label.text = "%s\nDepth: %d  |  Gold: %d" % [
		_band.name, _run.depth, _band.gold]

	# Rebuild roster list
	for child in _roster_list.get_children():
		child.queue_free()
	for ci in _band.roster:
		var vbox := VBoxContainer.new()
		# Top row: name, level, class
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = "%s  Lv%d  %s" % [ci.name, ci.character_level(), ci.active_class.capitalize()]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		# Down indicator: "Lives: 2/3" style
		var remaining: int = maxi(0, _run.down_limit + 1 - ci.downs_this_run)
		var total_lives: int = _run.down_limit + 1
		var downs_label := Label.new()
		downs_label.text = "Lives: %d/%d" % [remaining, total_lives]
		if remaining <= 0:
			downs_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		elif ci.downs_this_run > 0:
			downs_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
		row.add_child(downs_label)
		vbox.add_child(row)
		_roster_list.add_child(vbox)


# --- Node Interaction ---

func _on_node_clicked(node_id: String) -> void:
	_pending_node_id = node_id
	var n: Dictionary = _run.graph.node(node_id)
	var kind: String = str(n.get("kind", "?"))
	_node_preview_label.text = "Node: %s\nKind: %s\nDepth: %d" % [
		node_id, kind.capitalize(), _run.depth + 1]
	_node_preview.visible = true


func _on_node_hovered(_node_id: String) -> void:
	pass  # Future: show tooltip


func _on_advance_confirmed() -> void:
	if _pending_node_id.is_empty() or _run == null or _band == null:
		return
	var ctx: Dictionary = _build_ctx()
	var result: Dictionary = _run_controller.advance_to(_run, _pending_node_id, _band, ctx)
	var kind: String = str(result.get("kind", "error"))

	match kind:
		"battle":
			_launch_battle(result)
		"event", "boon", "hazard":
			_show_event_outcome(result)
		"shop":
			_show_shop_overlay()
		"rest":
			_show_rest_outcome(result)
		"error":
			Log.warn("RunScene", "Advance error: %s" % str(result.get("error", "")))
		_:
			_update_display()


# --- Battle Hand-off ---

func _launch_battle(result: Dictionary) -> void:
	var encounter: Dictionary = result.get("encounter", {}) as Dictionary
	var map_data: Variant = encounter.get("map", null)
	var enemy_instances: Array = encounter.get("enemy_instances", []) as Array

	if map_data == null or not map_data is MapData:
		Log.error("RunScene", "No map for encounter")
		_update_display()
		return

	# Build player party from all roster instances
	var fielded: Array[CharacterInstance] = []
	var fielded_ids: Array[String] = []
	for ci in _band.roster:
		fielded.append(ci)
		fielded_ids.append(ci.instance_id)

	var race_prov := func(id: String) -> RaceData: return GameData.get_race(id)
	var class_prov := func(id: String) -> ClassData: return GameData.get_job_class(id)

	var player_party: Array[BattleUnit] = BandPartyBuilder.build_party(
		fielded, race_prov, class_prov)
	var enemy_typed: Array[CharacterInstance] = []
	for e in enemy_instances:
		if e is CharacterInstance:
			enemy_typed.append(e as CharacterInstance)
	var enemy_party: Array[BattleUnit] = BandPartyBuilder.build_party(
		enemy_typed, race_prov, class_prov)

	# Build match
	var builder := MatchBuilder.new(
		GameData.get_character, GameData.get_final_stats,
		GameData.all_maps, GameData.get_terrain,
		GameData.get_ability, GameData.get_job_class, GameData.get_item)
	var ai_teams: Array = ["playerB"]
	var match_result: Dictionary = builder.build_match_from_parties(
		player_party, enemy_party, map_data as MapData, ai_teams)

	if match_result.has("errors") and not (match_result["errors"] as Array).is_empty():
		Log.error("RunScene", "Match build errors: %s" % str(match_result["errors"]))
		_update_display()
		return

	var state: MatchState = match_result["state"] as MatchState

	# Populate MatchData
	MatchData.match_state = state
	MatchData.deployment_controller = match_result["controller"] as DeploymentController
	MatchData.map_id = (map_data as MapData).id
	MatchData.active_band = _band
	MatchData.fielded_ids = fielded_ids
	MatchData.is_instance_battle = true
	MatchData.active_run = _run
	MatchData.run_node_id = _pending_node_id

	get_tree().change_scene_to_file("res://scenes/map/map_scene.tscn")


# --- Battle Return ---

func _process_battle_return(result: Dictionary) -> void:
	var ctx: Dictionary = _build_ctx()
	var ctrl_result: Dictionary = _run_controller.on_battle_end(_run, _band, result, ctx)
	var status: String = str(ctrl_result.get("status", "continue"))
	var deaths: Array = ctrl_result.get("deaths", []) as Array

	match status:
		"victory":
			_show_run_outcome("VICTORY", ctrl_result)
		"defeat":
			_show_run_outcome("DEFEAT", ctrl_result)
		_:
			# Show rewards/deaths, then continue
			if not deaths.is_empty():
				_show_permadeath_and_rewards(ctrl_result)
			elif ctrl_result.has("rewards"):
				_show_battle_rewards(ctrl_result.get("rewards", {}))
			else:
				_update_display()


func _show_permadeath_and_rewards(ctrl_result: Dictionary) -> void:
	var deaths: Array = ctrl_result.get("deaths", []) as Array
	var rewards: Dictionary = ctrl_result.get("rewards", {}) as Dictionary
	var text: String = "Battle Complete"
	var details: String = ""
	if not deaths.is_empty():
		details += "Fallen:\n"
		for death_id in deaths:
			details += "  - %s (permadeath)\n" % str(death_id)
	if rewards.get("gold", 0) > 0:
		details += "\nGold: +%d" % int(rewards.get("gold", 0))
	if rewards.get("xp", 0) > 0:
		details += "\nXP: +%d  JP: +%d" % [int(rewards.get("xp", 0)), int(rewards.get("jp", 0))]
	_overlay_label.text = text
	_overlay_effects_label.text = details
	_overlay_state = OverlayState.BATTLE_REWARDS
	_overlay_container.visible = true


func _show_battle_rewards(rewards: Dictionary) -> void:
	var details: String = ""
	if rewards.get("gold", 0) > 0:
		details += "Gold: +%d\n" % int(rewards.get("gold", 0))
	if rewards.get("xp", 0) > 0:
		details += "XP: +%d  JP: +%d\n" % [int(rewards.get("xp", 0)), int(rewards.get("jp", 0))]
	var equip: Array = rewards.get("equipment", []) as Array
	if not equip.is_empty():
		details += "Equipment: %s\n" % ", ".join(equip)
	if details.is_empty():
		_update_display()
		return
	_overlay_label.text = "Battle Victory!"
	_overlay_effects_label.text = details
	_overlay_state = OverlayState.BATTLE_REWARDS
	_overlay_container.visible = true


# --- Event/Boon/Hazard ---

func _show_event_outcome(result: Dictionary) -> void:
	var outcome: Dictionary = result.get("outcome", {}) as Dictionary
	var event: Dictionary = outcome.get("event", {}) as Dictionary
	var effects: Array = outcome.get("effects_applied", []) as Array
	_overlay_label.text = str(event.get("text", "Something happened..."))
	_overlay_effects_label.text = "\n".join(effects)
	_overlay_state = OverlayState.EVENT_OUTCOME
	_overlay_container.visible = true


# --- Shop ---

func _show_shop_overlay() -> void:
	_refresh_shop_items()
	_overlay_state = OverlayState.SHOP
	_shop_overlay.visible = true


# --- Rest ---

func _show_rest_outcome(result: Dictionary) -> void:
	var healed: Array = result.get("healed", []) as Array
	var text: String = "Your band rests and recovers."
	var details: String = ""
	if healed.is_empty():
		details = "Everyone is already in good health."
	else:
		details = "Downs reduced for:\n"
		for cid in healed:
			var ci: CharacterInstance = _band.get_instance(str(cid))
			if ci:
				details += "  - %s\n" % ci.name
	_overlay_label.text = text
	_overlay_effects_label.text = details
	_overlay_state = OverlayState.REST_OUTCOME
	_overlay_container.visible = true


# --- Run Outcome ---

func _show_run_outcome(title: String, ctrl_result: Dictionary) -> void:
	_outcome_label.text = title
	var details: String = "Depth reached: %d\n" % _run.depth
	details += "Gold: %d\n" % _band.gold
	var rewards: Dictionary = ctrl_result.get("rewards", {}) as Dictionary
	if not rewards.is_empty():
		details += "\nFinal battle rewards:\n"
		if rewards.get("gold", 0) > 0:
			details += "  Gold: +%d\n" % int(rewards.get("gold", 0))
	var deaths: Array = ctrl_result.get("deaths", []) as Array
	if not deaths.is_empty():
		details += "\nFallen:\n"
		for d in deaths:
			details += "  - %s\n" % str(d)
	# Display earned meta-progression unlocks
	var earned: Array = ctrl_result.get("earned_unlocks", []) as Array
	if not earned.is_empty():
		details += "\nUnlocks earned:\n"
		for unlock in earned:
			details += "  - %s\n" % str(unlock.get("rule_id", ""))
	details += "\nRuns completed: %d" % SaveManager.profile.completed_runs
	if title == "VICTORY":
		_outcome_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	else:
		_outcome_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_outcome_details.text = details
	_overlay_state = OverlayState.RUN_OUTCOME
	_outcome_overlay.visible = true


# --- Overlay Dismiss ---

func _on_overlay_dismissed() -> void:
	_overlay_container.visible = false
	_overlay_state = OverlayState.NONE
	_update_display()


func _on_run_finished() -> void:
	_outcome_overlay.visible = false
	MatchData.clear()
	get_tree().change_scene_to_file("res://scenes/band/band_scene.tscn")


func _on_abandon_run() -> void:
	SaveManager.active_run = null
	SaveManager.save_game()
	MatchData.clear()
	get_tree().change_scene_to_file("res://scenes/band/band_scene.tscn")


# --- Context Builder ---

func _build_ctx() -> Dictionary:
	return {
		"events_data": GameData.get_events_data(),
		"providers": {
			"all_maps": GameData.all_maps,
			"all_characters": GameData.all_characters,
			"class_provider": GameData.get_job_class,
			"character_provider": GameData.get_character,
			"map_provider": GameData.get_map,
			"name_gen": func(race: String) -> String:
				return _name_gen.generate_name(race),
			"run_config": GameData.get_run_config(),
			"loot_table_provider": GameData.get_loot_table,
			"shop_pool_provider": GameData.get_shop_pool,
			"encounters": GameData.all_encounters(),
			"band_level": _band.band_level() if _band else 0,
		},
		"fielded_ids": [],  # all roster members are fielded in runs
	}


# --- Shop Overlay ---

func _build_shop_overlay() -> void:
	_shop_overlay = PanelContainer.new()
	_shop_overlay.set_anchors_and_offsets_preset(PRESET_CENTER)
	_shop_overlay.custom_minimum_size = Vector2(420, 350)
	_shop_overlay.visible = false
	_apply_panel_bg(_shop_overlay)
	add_child(_shop_overlay)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_shop_overlay.add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Shop"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_shop_gold_label = Label.new()
	_shop_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vbox.add_child(_shop_gold_label)

	vbox.add_child(_make_spacer(8))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.custom_minimum_size.y = 180
	vbox.add_child(scroll)

	_shop_item_list = VBoxContainer.new()
	scroll.add_child(_shop_item_list)

	vbox.add_child(_make_spacer(10))

	var leave_btn := Button.new()
	leave_btn.text = "Leave Shop"
	leave_btn.custom_minimum_size.y = 36
	leave_btn.pressed.connect(_on_shop_leave)
	vbox.add_child(leave_btn)


func _refresh_shop_items() -> void:
	_shop_gold_label.text = "Gold: %d" % _band.gold

	for child in _shop_item_list.get_children():
		child.queue_free()

	# A11: Sample limited stock from run pools using seeded RNG
	var slots: int = int(Constants.get_value("RUN_SHOP_SLOTS", 6))
	var premium_chance: float = float(Constants.get_value("RUN_PREMIUM_CHANCE", 0.25))
	var rng := RandomNumberGenerator.new()
	rng.seed = _run.seed_value + _run.depth * 97 if _run else 0
	var common_pool: Array = GameData.get_shop_pool("run_common")
	var premium_pool: Array = GameData.get_shop_pool("run_premium")
	var item_ids: Array[String] = []
	for _i in range(slots):
		var pool: Array = common_pool
		if rng.randf() < premium_chance and not premium_pool.is_empty():
			pool = premium_pool
		if pool.is_empty():
			continue
		var pick: String = str(pool[rng.randi_range(0, pool.size() - 1)])
		if not item_ids.has(pick):
			item_ids.append(pick)

	if item_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No items available."
		_shop_item_list.add_child(empty_label)
		return

	for item_id in item_ids:
		var item: ItemData = GameData.get_item(item_id)
		if item == null:
			continue
		var price: int = Pricing.buy_price(item)
		var after_gold: int = _band.gold - price
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s — %d gp (after: %d)" % [item.display_name, price, maxi(after_gold, 0)]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var buy_btn := Button.new()
		buy_btn.text = "Buy"
		buy_btn.custom_minimum_size.x = 60
		buy_btn.disabled = _band.gold < price
		var captured_id: String = item_id
		buy_btn.pressed.connect(func() -> void:
			var err: String = ShopService.buy(_band, captured_id, GameData.get_item)
			if err.is_empty():
				Log.info("RunShop", "Bought %s" % captured_id)
			else:
				Log.info("RunShop", "Buy failed: %s" % err)
			_refresh_shop_items())
		row.add_child(buy_btn)
		_shop_item_list.add_child(row)


func _on_shop_leave() -> void:
	_shop_overlay.visible = false
	_overlay_state = OverlayState.NONE
	_update_display()


# --- Dev Panel ---

func _build_dev_panel() -> void:
	_sidebar.add_child(_make_separator())

	var header := Label.new()
	header.text = "DEV TOOLS"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color.ORANGE_RED)
	_sidebar.add_child(header)

	var profile_label := Label.new()
	profile_label.text = "Runs: %d | Unlocks: %d" % [
		SaveManager.profile.completed_runs, SaveManager.profile.meta_unlocks.size()]
	_sidebar.add_child(profile_label)

	var win_btn := Button.new()
	win_btn.text = "Win Current Run"
	win_btn.custom_minimum_size.y = 28
	win_btn.pressed.connect(func() -> void:
		if _run != null and _band != null:
			_run_controller._end_run(_run, _band, "victory")
			_show_run_outcome("VICTORY (DEV)", {"earned_unlocks": _run_controller.get_last_earned_unlocks()}))
	_sidebar.add_child(win_btn)

	var gold_btn := Button.new()
	gold_btn.text = "Add 1000 Gold"
	gold_btn.custom_minimum_size.y = 28
	gold_btn.pressed.connect(func() -> void:
		if _band != null:
			DevCheatService.add_gold(_band, 1000)
			_update_display())
	_sidebar.add_child(gold_btn)

	var reset_downs_btn := Button.new()
	reset_downs_btn.text = "Reset All Downs"
	reset_downs_btn.custom_minimum_size.y = 28
	reset_downs_btn.pressed.connect(func() -> void:
		if _band != null:
			for ci in _band.roster:
				DevCheatService.reset_downs(ci)
			_update_display())
	_sidebar.add_child(reset_downs_btn)


# --- Utilities ---

func _apply_panel_bg(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_content_margin_all(8)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)


func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	return sep


func _make_spacer(height: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size.y = height
	return s
