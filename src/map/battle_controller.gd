class_name BattleController
extends Node
## State-machine combat controller replacing Phase4Demo.
## Manages game flow, wires HUD signals to TurnActions, syncs PawnManager.
## Spec reference: phase8-spec.md §5

enum ControlState {
	DEPLOYMENT,
	AWAITING_ACTIVATION,
	ACTION_SELECT,
	TARGETING,
	ANIMATING,
	MATCH_OVER,
	# Speed-round states (A15)
	SR_AI_PLANNING,
	SR_PLAYER_SELECT,
	SR_PLANNING_ACTION,
	SR_PLANNING_TARGETING,
	SR_RESOLUTION,
	# Charge-time states (A20)
	CT_TICKING,
}

var _state: MatchState
var _builder: MapBuilder
var _overlay: OverlayController
var _pawn_manager: PawnManager
var _hud: BattleHUD
var _resolver: AbilityResolver
var _drag_handler: DragHandler

var _ai_controller: AIController = null
var _deployment_controller: DeploymentController = null

var _control_state: int = ControlState.AWAITING_ACTIVATION
var _pending_action: int = -1
var _pending_ability_id: String = ""
var _pending_item_id: String = ""
var _selected_tile: Vector2i = Vector2i(-999, -999)

# Cached ability/item lists for the current unit
var _current_abilities: Array = []
var _current_items: Array = []

# Pending activation (awaiting player confirm)
var _pending_activation_unit: BattleUnit = null

# Cycle index for N-key rotation through selectable units
var _cycle_index: int = -1

# Pending drag-move preview (not yet committed)
var _has_pending_move: bool = false
var _pending_move_coord: Vector2i = Vector2i(-999, -999)

# Speed-round state (A15)
var _sr_turn_system: SpeedRoundTurnSystem = null

# Charge-time state (A20)
var _ct_turn_system: ChargeTimeTurnSystem = null
var _ct_tick_timer: float = 0.0
const CT_TICK_INTERVAL: float = 0.05  # seconds between ticks (visual pacing)
var _player_plans: Dictionary = {}  # unit_id -> AIPlan
var _planning_unit: BattleUnit = null
var _planning_plan: AIPlan = null
var _planning_ap_left: int = 0
var _planning_moved: bool = false
var _planning_move_dest: Vector2i = Vector2i.MAX


func setup(builder: MapBuilder, map_data: MapData) -> void:
	_builder = builder

	# Create two parties (fallback demo — same as Phase4Demo)
	var party_a: Array[BattleUnit] = []
	var party_b: Array[BattleUnit] = []
	party_a.append(_make_unit("human_fighter"))
	party_a.append(_make_unit("human_rogue"))
	party_b.append(_make_unit("elf_black_mage"))
	party_b.append(_make_unit("halfling_white_mage"))

	_state = MatchSetup.create(party_a, party_b, map_data, GameData.get_terrain)
	_state.ai_teams = ["playerB"]

	_resolver = AbilityResolver.new(
		GameData.get_ability, GameData.get_job_class, GameData.get_item)
	_state.ability_provider = _resolver.resolve
	_state.item_provider = GameData.get_item

	# Interactive deployment (A12)
	_deployment_controller = DeploymentController.new()
	var errors := _deployment_controller.begin(
		_state, map_data.deployment_zones, _state.ai_teams)
	if not errors.is_empty():
		for e in errors:
			Log.error("BattleController", e)
		return

	_init_subsystems(builder)
	_enter_deployment()


func setup_from_state(
	builder: MapBuilder, state: MatchState,
	controller: DeploymentController = null,
) -> void:
	_builder = builder
	_state = state

	_resolver = AbilityResolver.new(
		GameData.get_ability, GameData.get_job_class, GameData.get_item)
	# Wire ability/item providers if not already set
	if not _state.ability_provider.is_valid():
		_state.ability_provider = _resolver.resolve
	if not _state.item_provider.is_valid():
		_state.item_provider = GameData.get_item

	# Wire speed-round turn system for roguelike run mode (A15)
	if MatchData.mode == "run" and _state.turn_system == null:
		_state.turn_system = SpeedRoundTurnSystem.new()
	if _state.turn_system is SpeedRoundTurnSystem:
		_sr_turn_system = _state.turn_system as SpeedRoundTurnSystem

	# Wire charge-time turn system for skirmish mode (A20)
	if MatchData.mode == "skirmish" and _state.turn_system == null:
		var ct_sys := ChargeTimeTurnSystem.new()
		var all_units: Array = []
		for team in _state.parties.keys():
			all_units.append_array(_state.parties[team])
		var seed_val: int = int(Time.get_ticks_msec())
		ct_sys.setup(all_units, seed_val)
		_state.turn_system = ct_sys
	if _state.turn_system is ChargeTimeTurnSystem:
		_ct_turn_system = _state.turn_system as ChargeTimeTurnSystem

	_init_subsystems(builder)

	# If still in deployment phase, drive interactive deployment
	if state.phase == MatchState.Phase.DEPLOYMENT:
		if controller:
			_deployment_controller = controller
			_enter_deployment()
		else:
			# Controller missing (e.g. lost during scene transition) — skip deployment
			Log.warn("BattleController",
				"Deployment phase active but no controller provided; skipping to round start")
			_skip_deployment_to_round_start()
	elif _is_speed_round():
		_start_new_round()
	elif _is_charge_time():
		_start_new_round()
	else:
		_enter_awaiting_activation()


func _init_subsystems(builder: MapBuilder) -> void:
	# Overlay controller
	_overlay = OverlayController.new()
	_overlay.graph = _state.graph
	_overlay.builder = builder
	add_child(_overlay)

	# Pawn manager
	_pawn_manager = PawnManager.new()
	_pawn_manager.setup(_state, _state.graph)
	add_child(_pawn_manager)

	# HUD — call setup() explicitly so UI nodes exist before update methods
	_hud = BattleHUD.new()
	_hud.setup()
	add_child(_hud)

	# Connect HUD signals
	_hud.action_selected.connect(_on_action_selected)
	_hud.ability_selected.connect(_on_ability_selected)
	_hud.item_selected.connect(_on_item_selected)
	_hud.finalize_move_pressed.connect(_on_finalize_move)
	_hud.cancel_move_pressed.connect(_on_cancel_move)
	_hud.unit_clicked.connect(_on_roster_unit_clicked)
	_hud.back_to_menu_pressed.connect(_on_back_to_menu)
	_hud.confirm_activation_pressed.connect(_on_confirm_activation)
	_hud.cancel_activation_pressed.connect(_on_cancel_activation)
	_hud.commit_round_pressed.connect(_on_commit_round)
	_hud.clear_plan_pressed.connect(_on_clear_plan)

	# AI controller
	_ai_controller = AIController.new()
	var ai_seed: int = int(Time.get_ticks_msec())
	var ai_diff: String = str(Constants.get_value("AI_DIFFICULTY", "normal"))
	_ai_controller.setup(_hud, _pawn_manager, _overlay, ai_seed, ai_diff)
	if _is_charge_time():
		_ai_controller.turn_complete.connect(_on_ai_turn_complete_ct)
	else:
		_ai_controller.turn_complete.connect(_on_ai_turn_complete)
	add_child(_ai_controller)

	# Initial HUD state
	_hud.update_roster(_state, null)
	_hud.update_turn_order(_state)
	if _state.phase == MatchState.Phase.DEPLOYMENT:
		_hud.append_log("--- Deploy your forces! ---")
	else:
		_hud.append_log("--- Battle begins! ---")

	# Dev combat panel (cheat controls)
	if Dev.enabled:
		var dev_panel := DevCombatPanel.new()
		dev_panel.setup(self)
		add_child(dev_panel)


# --- Deployment phase (A12) ---

func _enter_deployment() -> void:
	_control_state = ControlState.DEPLOYMENT
	_set_drag_enabled(false)
	_overlay.clear()
	_hud.set_targeting_mode(false)
	_hud.hide_action_panel()

	if not _deployment_controller:
		Log.error("BattleController", "_enter_deployment called with null controller")
		_skip_deployment_to_round_start()
		return

	if _deployment_controller.is_complete():
		_finish_deployment()
		return

	var team := _deployment_controller.current_team()
	var unit := _deployment_controller.next_unit(team)

	if team in _state.ai_teams:
		# AI places with pacing
		_hud.append_log("[Deploy] AI placing %s..." % unit.character.display_name, "deploy_ai")
		var delay: float = float(Constants.get_value("DEPLOY_PACE_DELAY", 0.4))
		var tree := get_tree()
		if not tree:
			Log.error("BattleController", "get_tree() null in _enter_deployment — node not in scene tree")
			return
		tree.create_timer(delay).timeout.connect(_do_ai_deploy_step)
	else:
		# Human places — highlight legal tiles
		var legal := _deployment_controller.legal_tiles(team)
		var positions: Array = []
		for t: Vector2i in legal:
			positions.append(t)
		_overlay.show_selectable(positions)
		_hud.show_unit_info(unit)
		_hud.append_log("[Deploy] Place %s (click a highlighted tile)" %
			unit.character.display_name, "deploy_player")


func _do_ai_deploy_step() -> void:
	if not _deployment_controller:
		Log.error("BattleController", "_do_ai_deploy_step called with null controller")
		_skip_deployment_to_round_start()
		return

	if _deployment_controller.is_complete():
		_finish_deployment()
		return

	var team := _deployment_controller.current_team()
	var unit := _deployment_controller.next_unit(team)
	if not unit:
		_finish_deployment()
		return

	var legal := _deployment_controller.legal_tiles(team)
	var enemy_team := "playerA" if team == "playerB" else "playerB"
	var enemy_z := _deployment_controller.zone_tiles(enemy_team)
	var weights: Dictionary = Constants.get_value("DEPLOY_WEIGHTS", {})
	var tile := DeploymentPlanner.choose(_state, team, unit, legal, enemy_z, weights)

	var errs := _deployment_controller.place_next(team, tile)
	if not errs.is_empty():
		Log.error("BattleController", "AI deploy error: %s" % str(errs))
		return

	# Spawn the pawn visually
	_pawn_manager.spawn_pawn(unit)
	_hud.append_log("[Deploy] %s placed at (%d,%d)" %
		[unit.character.display_name, tile.x, tile.y], "deploy_ai")

	_advance_deployment()


func _advance_deployment() -> void:
	if not _deployment_controller:
		_skip_deployment_to_round_start()
		return
	if _deployment_controller.is_complete():
		_finish_deployment()
		return
	_enter_deployment()


func _finish_deployment() -> void:
	if _deployment_controller:
		# finish() asserts completion; it also calls RoundManager.start_round()
		# which handles the legacy (alternating) path. For CT/SR modes the turn
		# system begin_round was already triggered by that start_round call, so we
		# enter the correct phase directly without calling _start_new_round() again
		# (which would double-increment the round counter).
		_deployment_controller.finish()
	else:
		RoundManager.start_round(_state)
	_hud.append_log("--- Deployment complete! ---")
	_overlay.clear()
	# Refresh status markers for all surviving units
	for team in _state.parties.keys():
		for unit: BattleUnit in _state.parties[team]:
			if unit.current_hp > 0 or unit.is_downed:
				_pawn_manager.update_status_markers(unit)
	_hud.append_log("--- Round %d begins ---" % _state.round_number)
	_hud.show_round_banner(_state.round_number)
	if _is_charge_time():
		# Initialize CT system with deployed units if not already set up
		if _ct_turn_system and not _ct_turn_system.get_scheduler():
			var all_units: Array = []
			for team in _state.parties.keys():
				all_units.append_array(_state.parties[team])
			var seed_val: int = int(Time.get_ticks_msec())
			_ct_turn_system.setup(all_units, seed_val)
		_enter_ct_ticking()
	elif _is_speed_round():
		_enter_ai_planning()
	else:
		_enter_awaiting_activation()


func _skip_deployment_to_round_start() -> void:
	## Fallback when deployment cannot proceed (null controller). Starts round 1 directly.
	_hud.append_log("--- Deployment skipped (fallback) ---")
	_overlay.clear()
	if _is_charge_time() and _ct_turn_system and not _ct_turn_system.get_scheduler():
		var all_units: Array = []
		for team in _state.parties.keys():
			all_units.append_array(_state.parties[team])
		var seed_val: int = int(Time.get_ticks_msec())
		_ct_turn_system.setup(all_units, seed_val)
	_start_new_round()


func _handle_deployment_click(coord: Vector2i) -> void:
	if not _deployment_controller:
		return
	var team := _deployment_controller.current_team()
	if team.is_empty() or team in _state.ai_teams:
		return  # Not the human's turn during deployment

	var unit := _deployment_controller.next_unit(team)
	if not unit:
		return

	var errs := _deployment_controller.place_next(team, coord)
	if not errs.is_empty():
		_hud.append_log("[Deploy] Invalid tile", "deploy_error")
		return

	# Spawn the pawn visually
	_pawn_manager.spawn_pawn(unit)
	_hud.append_log("[Deploy] %s placed at (%d,%d)" %
		[unit.character.display_name, coord.x, coord.y], "deploy_player")
	_hud.hide_unit_info()

	_advance_deployment()


## Public getters for dev tools access.
func get_match_state() -> MatchState:
	return _state

func get_hud() -> BattleHUD:
	return _hud

func get_pawn_manager() -> PawnManager:
	return _pawn_manager

## Triggers match-over check (used by DevCombatPanel after force-killing units).
func check_match_over_now() -> bool:
	return _check_match_over()


func setup_drag(camera: Camera3D, builder: MapBuilder) -> void:
	_drag_handler = DragHandler.new()
	_drag_handler.setup(camera, _state, _pawn_manager)
	_drag_handler.drag_move_requested.connect(_on_drag_move)
	_drag_handler.drag_cancelled.connect(_on_drag_cancelled)
	_drag_handler.set_enabled(_control_state == ControlState.ACTION_SELECT)
	add_child(_drag_handler)


func get_drag_handler() -> DragHandler:
	return _drag_handler


# --- State transitions ---

func _enter_awaiting_activation() -> void:
	_control_state = ControlState.AWAITING_ACTIVATION
	_pending_activation_unit = null
	_cycle_index = -1
	_set_drag_enabled(false)
	_overlay.clear()
	_hud.set_targeting_mode(false)
	_hud.hide_action_panel()
	_hud.hide_unit_info()
	_pawn_manager.clear_highlight()

	if _check_match_over():
		return

	var team := RoundManager.current_team(_state)
	if team.is_empty():
		_enter_round_end()
		return

	# Get all eligible units (living + downed, not yet activated)
	var all_eligible := _state.activatable_units(team)

	# If no eligible units at all, skip this activation slot
	if all_eligible.is_empty():
		_state.current_index += 1
		_enter_awaiting_activation()
		return

	# Auto-skip sleeping units for this team's activation slot
	var selectable := all_eligible.filter(
		func(u: BattleUnit) -> bool: return not RoundManager.is_sleeping(u))

	if selectable.is_empty() and not all_eligible.is_empty():
		# All remaining living units on this team are sleeping — skip one
		var sleeping_unit: BattleUnit = all_eligible[0]
		var err := RoundManager.activate_unit(_state, sleeping_unit)
		if not err.is_empty():
			Log.error("BattleController", err)
			return
		TurnActions.execute_wait(_state)
		_hud.append_log("%s is asleep -- skipped" % sleeping_unit.character.display_name, "sleep")
		RoundManager.end_activation(_state)
		_enter_awaiting_activation()
		return

	# AI team routing — hand off to AIController instead of human input
	if team in _state.ai_teams:
		_handle_ai_activation(team, selectable)
		return

	# Highlight selectable units on the map
	_pawn_manager.highlight_selectable(selectable)
	var selectable_positions: Array = []
	for u: BattleUnit in selectable:
		selectable_positions.append(u.position)
	_overlay.show_selectable(selectable_positions)

	# Build list of selectable character IDs for roster click support
	var selectable_ids: Array = []
	for u: BattleUnit in selectable:
		selectable_ids.append(u.character.id)

	_hud.show_awaiting_activation(team)
	_hud.update_round_info(_state.round_number, team)
	_hud.update_turn_order(_state)
	_hud.update_roster(_state, null, selectable_ids)


func _enter_action_select() -> void:
	# Cancel any pending move preview if still active
	if _has_pending_move:
		_clear_pending_move()

	_control_state = ControlState.ACTION_SELECT
	var unit: BattleUnit = _state.current_unit
	if not unit:
		return

	# Cache abilities and usable items for this unit
	_current_abilities = _resolver.all_abilities(unit)
	_current_items = _get_usable_items(unit)

	# Compute WP costs for usable items (resolve granted abilities)
	var item_wp_costs := {}
	for item in _current_items:
		if item is ItemData and not item.granted_abilities.is_empty():
			var ability: AbilityData = _resolver.resolve(unit, item.granted_abilities[0])
			if ability:
				item_wp_costs[item.id] = ability.wp_cost

	_hud.show_unit_info(unit)
	_hud.show_action_panel(unit, _current_abilities, _current_items, _must_reserve_move(), item_wp_costs)
	_hud.set_targeting_mode(false)
	_hud.set_finalize_enabled(false)
	_hud.update_roster(_state, unit)
	_pawn_manager.highlight_active(unit)

	# When AP is depleted or unit is downed, skip movement overlay and disable drag
	if unit.ap_remaining <= 0 or unit.is_downed:
		_set_drag_enabled(false)
		_overlay.clear()
	else:
		_set_drag_enabled(true)
		# Show movement overlay by default
		_overlay.show_movement(
			unit.position,
			unit.stats.effective_move(),
			unit.stats.effective("jump"))


func _enter_targeting(action: int, ability_id: String = "", item_id: String = "") -> void:
	_control_state = ControlState.TARGETING
	_set_drag_enabled(false)
	_pending_action = action
	_pending_ability_id = ability_id
	_pending_item_id = item_id

	var unit: BattleUnit = _state.current_unit
	if not unit:
		return

	_hud.set_targeting_mode(true)
	_overlay.clear()

	match action:
		BattleHUD.ACTION_MOVE:
			_overlay.show_movement(
				unit.position,
				unit.stats.effective_move(),
				unit.stats.effective("jump"))
		BattleHUD.ACTION_ATTACK:
			var rng: int = unit.stats.effective("rng")
			var min_rng: int = 2 if rng > 1 else 1
			_overlay.show_targets(unit.position, rng, min_rng)
		BattleHUD.ACTION_ABILITY:
			var ability := _find_ability(ability_id)
			if ability:
				if str(ability.effect.get("effect_type", "")) == "revive":
					_overlay.show_revive_targets(
						unit.position, ability.ability_range, _state, unit.team)
				else:
					_show_ability_overlay(unit, ability)
		BattleHUD.ACTION_ITEM:
			var item: ItemData = GameData.get_item(item_id)
			if item and not item.granted_abilities.is_empty():
				var ability := _find_ability(item.granted_abilities[0])
				if ability:
					_show_ability_overlay(unit, ability)


func _enter_animating() -> void:
	_control_state = ControlState.ANIMATING
	_set_drag_enabled(false)
	_hud.set_targeting_mode(false)


func _enter_round_end() -> void:
	## Round complete — auto-advance to the next round.
	_hud.append_log("--- Round %d complete ---" % _state.round_number)
	_start_new_round()


func _handle_ai_activation(team: String, selectable: Array) -> void:
	## Activate the first selectable AI unit and hand off to AIController.
	if selectable.is_empty():
		return

	var unit: BattleUnit = selectable[0]
	_pawn_manager.highlight_active(unit)
	_hud.update_round_info(_state.round_number, team)
	_hud.update_turn_order(_state)

	var err := RoundManager.activate_unit(_state, unit)
	if not err.is_empty():
		Log.error("BattleController", "AI activation failed: %s" % err)
		return

	var race_class_id := "%s_%s" % [unit.character.race,
		unit.character.classes[0] if not unit.character.classes.is_empty() else ""]
	_hud.append_log("[AI] %s activated (%s)" % [unit.character.display_name, team], race_class_id)

	# Apply per-turn terrain damage at activation start
	var was_downed_before := unit.is_downed
	var terrain_outcomes := RoundManager.on_activation_start(_state, unit)
	for outcome in terrain_outcomes:
		var dmg: int = int(outcome.get("amount", 0))
		var hp_after: int = int(outcome.get("target_hp_after", 0))
		_hud.append_log("[AI] %s takes %d terrain damage (%d HP)" % [
			unit.character.display_name, dmg, hp_after], "terrain_damage")
		if unit.current_hp <= 0:
			_pawn_manager.down_pawn(unit)
			_hud.append_log("[AI] %s DOWNED by terrain!" % unit.character.display_name)
	_pawn_manager.update_status_markers(unit)

	if _check_match_over():
		return

	# If downed by terrain THIS activation, end immediately
	if unit.is_downed and not was_downed_before:
		var removed := RoundManager.end_activation(_state)
		if removed:
			_pawn_manager.remove_pawn(removed)
			_hud.append_log("[AI] %s has been permanently removed" % removed.character.display_name)
		if _check_match_over():
			return
		_enter_awaiting_activation()
		return

	# Hand off to AI controller
	_control_state = ControlState.ANIMATING
	_ai_controller.take_turn(_state)


func _on_ai_turn_complete() -> void:
	## Called when AIController finishes an activation.
	if _check_match_over():
		return
	_enter_awaiting_activation()


func _check_match_over() -> bool:
	## Check if the match is over. Returns true if a winner was found.
	var winner := _state.check_winner()
	if not winner.is_empty():
		_enter_match_over(winner)
		return true
	return false


func _enter_match_over(winner: String) -> void:
	_control_state = ControlState.MATCH_OVER
	_set_drag_enabled(false)
	_overlay.clear()
	_hud.set_targeting_mode(false)
	_hud.hide_action_panel()
	_hud.hide_unit_info()
	_pawn_manager.clear_highlight()
	var display_name := "Player A" if winner == "playerA" else "Player B"
	_hud.show_match_over(display_name)
	_hud.append_log("--- %s wins! ---" % display_name)
	if MatchData.active_run != null:
		_hud.set_back_button_text("Return to Run")


func _on_back_to_menu() -> void:
	if MatchData.active_run != null:
		_complete_run_battle()
	elif MatchData.mode == "skirmish":
		MatchData.clear()
		get_tree().change_scene_to_file("res://scenes/skirmish/skirmish_scene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/draft/draft_scene.tscn")


func _complete_run_battle() -> void:
	var winner: String = _state.check_winner()
	var downed_ids: Array[String] = DeathModel.extract_downed_ids(_state, "playerA")
	MatchData.battle_result = {
		"winner": winner,
		"player_won": winner == "playerA",
		"downed_instance_ids": downed_ids,
		"node_id": MatchData.run_node_id,
	}
	get_tree().change_scene_to_file("res://scenes/run/run_scene.tscn")


# --- Input handling ---

func on_tile_selected(coord: Vector2i) -> void:
	if _control_state == ControlState.MATCH_OVER:
		return
	_selected_tile = coord

	if _control_state == ControlState.DEPLOYMENT:
		_handle_deployment_click(coord)
		return

	if _control_state == ControlState.AWAITING_ACTIVATION:
		# If there's a pending activation, clear it and try selecting the new tile
		if _pending_activation_unit:
			_clear_pending_activation()
		_try_select_unit(coord)
	elif _control_state == ControlState.TARGETING:
		_execute_targeting(coord)
	# Speed-round planning states
	elif _control_state == ControlState.SR_PLAYER_SELECT:
		_sr_try_select_plan_unit(coord)
	elif _control_state == ControlState.SR_PLANNING_ACTION:
		_sr_try_click_move(coord)
	elif _control_state == ControlState.SR_PLANNING_TARGETING:
		_sr_execute_plan_targeting(coord)


func _unhandled_input(event: InputEvent) -> void:
	if not _state:
		return
	if _control_state == ControlState.MATCH_OVER:
		return

	if event.is_action_pressed("p4_next"):
		if _control_state == ControlState.AWAITING_ACTIVATION:
			_activate_next()
	elif event.is_action_pressed("p4_move"):
		if _control_state == ControlState.ACTION_SELECT:
			_enter_targeting(BattleHUD.ACTION_MOVE)
		elif _control_state == ControlState.SR_PLANNING_ACTION:
			_sr_enter_plan_targeting(BattleHUD.ACTION_MOVE)
	elif event.is_action_pressed("p4_attack"):
		if _control_state == ControlState.ACTION_SELECT and not _must_reserve_move():
			_enter_targeting(BattleHUD.ACTION_ATTACK)
		elif _control_state == ControlState.SR_PLANNING_ACTION and _planning_ap_left >= 1:
			_sr_enter_plan_targeting(BattleHUD.ACTION_ATTACK)
	elif event.is_action_pressed("p4_defend"):
		if _control_state == ControlState.ACTION_SELECT and not _must_reserve_move():
			_do_defend()
		elif _control_state == ControlState.SR_PLANNING_ACTION and _planning_ap_left >= 1:
			_sr_plan_defend()
	elif event.is_action_pressed("p4_wait"):
		if _control_state == ControlState.ACTION_SELECT:
			_do_wait()
		elif _control_state == ControlState.SR_PLANNING_ACTION:
			_sr_plan_wait()
	elif event.is_action_pressed("ui_cancel"):
		if _control_state == ControlState.AWAITING_ACTIVATION and _pending_activation_unit:
			_clear_pending_activation()
		elif _control_state == ControlState.TARGETING:
			_cancel_targeting()
		elif _control_state == ControlState.SR_PLANNING_TARGETING:
			_enter_sr_plan_action()
		elif _control_state == ControlState.SR_PLANNING_ACTION:
			_enter_sr_player_select()
	elif event.is_action_pressed("demo_clear"):
		if _overlay:
			_overlay.clear()


# --- HUD signal handlers ---

func _on_action_selected(action_type: int) -> void:
	# Speed-round planning mode
	if _control_state == ControlState.SR_PLANNING_ACTION:
		match action_type:
			BattleHUD.ACTION_MOVE:
				_sr_enter_plan_targeting(BattleHUD.ACTION_MOVE)
			BattleHUD.ACTION_ATTACK:
				_sr_enter_plan_targeting(BattleHUD.ACTION_ATTACK)
			BattleHUD.ACTION_DEFEND:
				_sr_plan_defend()
			BattleHUD.ACTION_WAIT:
				_sr_plan_wait()
		return

	if _control_state != ControlState.ACTION_SELECT:
		return

	match action_type:
		BattleHUD.ACTION_MOVE:
			_enter_targeting(BattleHUD.ACTION_MOVE)
		BattleHUD.ACTION_ATTACK:
			_enter_targeting(BattleHUD.ACTION_ATTACK)
		BattleHUD.ACTION_DEFEND:
			_do_defend()
		BattleHUD.ACTION_WAIT:
			_do_wait()


func _on_ability_selected(ability_id: String) -> void:
	# Speed-round planning mode
	if _control_state == ControlState.SR_PLANNING_ACTION:
		var ability := _find_ability(ability_id)
		if ability and ability.ability_range == 0 and _planning_unit:
			_sr_plan_ability(_planning_unit.position, ability_id)
			return
		_sr_enter_plan_targeting(BattleHUD.ACTION_ABILITY, ability_id)
		return

	if _control_state != ControlState.ACTION_SELECT:
		return
	# Self-targeted abilities (range 0): auto-execute on caster's tile
	var ability := _find_ability(ability_id)
	if ability and ability.ability_range == 0 and _state.current_unit:
		_pending_ability_id = ability_id
		_do_ability(_state.current_unit.position)
		return
	_enter_targeting(BattleHUD.ACTION_ABILITY, ability_id)


func _on_item_selected(item_id: String) -> void:
	# Speed-round planning mode
	if _control_state == ControlState.SR_PLANNING_ACTION:
		_sr_enter_plan_targeting(BattleHUD.ACTION_ITEM, "", item_id)
		return

	if _control_state != ControlState.ACTION_SELECT:
		return
	_enter_targeting(BattleHUD.ACTION_ITEM, "", item_id)


# --- Action execution ---

func _activate_next() -> void:
	## Convenience shortcut (N key): cycles through selectable (non-sleeping) units.
	## Each press advances to the next unit and shows the activation dialog.
	var team := RoundManager.current_team(_state)
	var selectable: Array[BattleUnit] = []
	for u: BattleUnit in _state.activatable_units(team):
		if not RoundManager.is_sleeping(u):
			selectable.append(u)
	if selectable.is_empty():
		return
	_cycle_index = (_cycle_index + 1) % selectable.size()
	_set_pending_activation(selectable[_cycle_index])


func _set_pending_activation(unit: BattleUnit) -> void:
	## Set a unit as pending activation (preview before confirm).
	_pending_activation_unit = unit
	_pawn_manager.highlight_active(unit)
	_hud.show_unit_info(unit)
	_hud.set_confirm_activation_enabled(true, unit.character.display_name)
	_hud.update_roster(_state, unit)


func _clear_pending_activation() -> void:
	## Clear pending activation and return to normal awaiting state.
	_pending_activation_unit = null
	_hud.set_confirm_activation_enabled(false)
	_hud.hide_unit_info()

	# Re-highlight all selectable units
	var team := RoundManager.current_team(_state)
	if not team.is_empty():
		var selectable := _state.activatable_units(team).filter(
			func(u: BattleUnit) -> bool:
				return not RoundManager.is_sleeping(u))
		_pawn_manager.highlight_selectable(selectable)
		_hud.update_roster(_state, null,
			selectable.map(func(u: BattleUnit) -> String: return u.character.id))


func _on_confirm_activation() -> void:
	if _pending_activation_unit:
		var unit := _pending_activation_unit
		_pending_activation_unit = null
		_hud.set_confirm_activation_enabled(false)
		_activate_chosen_unit(unit)


func _on_cancel_activation() -> void:
	_clear_pending_activation()


func _activate_chosen_unit(unit: BattleUnit) -> void:
	## Activate a specific unit chosen by the player (or auto-picked).
	var err := RoundManager.activate_unit(_state, unit)
	if not err.is_empty():
		Log.error("BattleController", err)
		return

	var race_class_id := "%s_%s" % [unit.character.race,
		unit.character.classes[0] if not unit.character.classes.is_empty() else ""]
	_hud.append_log("%s activated (%s)" % [unit.character.display_name, unit.team], race_class_id)

	# Alpha A0: apply per-turn terrain damage at activation start
	var was_downed_before := unit.is_downed
	var terrain_outcomes := RoundManager.on_activation_start(_state, unit)
	for outcome in terrain_outcomes:
		var dmg: int = int(outcome.get("amount", 0))
		var hp_after: int = int(outcome.get("target_hp_after", 0))
		_hud.append_log("%s takes %d terrain damage (%d HP)" % [
			unit.character.display_name, dmg, hp_after], "terrain_damage")
		if unit.current_hp <= 0:
			_pawn_manager.down_pawn(unit)
			_hud.append_log("%s DOWNED by terrain!" % unit.character.display_name)
	_pawn_manager.update_status_markers(unit)

	if _check_match_over():
		return

	# If the unit was downed by terrain damage THIS activation, end immediately
	if unit.is_downed and not was_downed_before:
		var removed := RoundManager.end_activation(_state)
		if removed:
			_pawn_manager.remove_pawn(removed)
			_hud.append_log("%s has been permanently removed" % removed.character.display_name)
		if _check_match_over():
			return
		_enter_awaiting_activation()
		return

	_enter_action_select()


func _try_select_unit(coord: Vector2i) -> void:
	## Handle tile click during AWAITING_ACTIVATION — set as pending activation.
	var team := RoundManager.current_team(_state)
	if team.is_empty():
		return
	var unit: BattleUnit = _state.unit_at(coord)
	if not unit or unit.team != team or unit.is_activated:
		return
	if unit.current_hp <= 0 and not unit.is_downed:
		return
	if RoundManager.is_sleeping(unit):
		return
	_set_pending_activation(unit)


func _on_roster_unit_clicked(character_id: String) -> void:
	## Handle roster sidebar click — set as pending activation or select for planning.
	if _control_state == ControlState.SR_PLAYER_SELECT:
		_sr_select_plan_unit_by_id(character_id)
		return
	if _control_state != ControlState.AWAITING_ACTIVATION:
		return
	var team := RoundManager.current_team(_state)
	if team.is_empty():
		return
	for u: BattleUnit in _state.activatable_units(team):
		if u.character.id == character_id and not RoundManager.is_sleeping(u):
			_set_pending_activation(u)
			return


func _execute_targeting(coord: Vector2i) -> void:
	var unit: BattleUnit = _state.current_unit
	if not unit:
		return

	match _pending_action:
		BattleHUD.ACTION_MOVE:
			_do_move(coord)
		BattleHUD.ACTION_ATTACK:
			_do_attack(coord)
		BattleHUD.ACTION_ABILITY:
			_do_ability(coord)
		BattleHUD.ACTION_ITEM:
			_do_use_item(coord)


func _do_move(destination: Vector2i) -> void:
	var result := TurnActions.execute_move(_state, destination)
	if result.has("error"):
		_hud.append_log("Move failed: %s" % str(result["error"]))
		return

	var unit: BattleUnit = _state.current_unit
	_hud.append_log("%s moves to (%d,%d)" % [
		unit.character.display_name, destination.x, destination.y], "action_move")

	# Alpha A0: log terrain enter effects
	for outcome in result.get("terrain_effects", []):
		if outcome.get("type") == "terrain_damage":
			_hud.append_log("%s takes %d terrain damage (%d HP)" % [
				unit.character.display_name, int(outcome["amount"]),
				int(outcome["target_hp_after"])], "terrain_damage")
		elif outcome.get("type") == "terrain_status":
			_hud.append_log("%s afflicted by %s" % [
				unit.character.display_name, str(outcome["status_id"])], "terrain_status")
	if unit:
		_pawn_manager.update_status_markers(unit)
		_pawn_manager.update_facing(unit)

	# Animate pawn movement
	_enter_animating()
	var tw := _pawn_manager.move_pawn(unit, destination)
	if tw:
		tw.finished.connect(_on_move_tween_finished)
	else:
		_on_move_tween_finished()


func _on_move_tween_finished() -> void:
	_overlay.clear()
	_check_end_activation_or_continue()


func _do_attack(target_pos: Vector2i) -> void:
	# Capture target unit before execute (downing erases from occupancy)
	var target_unit_pre: BattleUnit = _state.unit_at(target_pos)

	var result := TurnActions.execute_attack(_state, target_pos)
	if result.has("error"):
		_hud.append_log("Attack failed: %s" % str(result["error"]))
		return

	_log_attack_result(result)

	# Show symbol pawn beside target (awaitable landing beat)
	if target_unit_pre:
		await _pawn_manager.show_ability_pawns([target_unit_pre], "action_attack")

	# Show dice roll animations above attacker and target
	var attacker: BattleUnit = _state.current_unit
	if attacker and result.has("atk_roll"):
		_pawn_manager.show_dice_roll(attacker, int(result["atk_roll"]), true)
	var atk_def_roll: int = int(result.get("def_roll", 0))
	if target_unit_pre and atk_def_roll > 0:
		_pawn_manager.show_dice_roll(target_unit_pre, atk_def_roll, false)

	if result.get("is_downed", false) and target_unit_pre:
		_delay_down_pawn(target_unit_pre)

	# Update status markers for attacker and target
	if target_unit_pre:
		_pawn_manager.update_status_markers(target_unit_pre)
	if attacker:
		_pawn_manager.update_status_markers(attacker)
		_pawn_manager.update_facing(attacker)

	_overlay.clear()
	_check_end_activation_or_continue()


func _do_ability(target_pos: Vector2i) -> void:
	# Snapshot units at affected positions before execute (for pawn removal)
	var units_before := _snapshot_affected_units(target_pos)

	var ability_id := _pending_ability_id
	var result := TurnActions.execute_ability(_state, ability_id, target_pos)
	if result.has("error"):
		_hud.append_log("Ability failed: %s" % str(result["error"]))
		return

	_log_ability_result(result, ability_id)

	# Show symbol pawn beside each affected target (awaitable landing beat)
	var caster: BattleUnit = _state.current_unit
	var outcomes: Array = result.get("outcomes", [])
	var affected: Array = []
	for outcome in outcomes:
		var target_unit: BattleUnit = units_before.get(str(outcome.get("target", "")))
		if target_unit and target_unit not in affected:
			affected.append(target_unit)
	if not affected.is_empty():
		var ability: AbilityData = GameData.get_ability(ability_id)
		var icon: String = SymbolAtlas.symbol_for_ability(ability)
		await _pawn_manager.show_ability_pawns(affected, icon)

	# Show dice roll animations for damage outcomes
	for outcome in outcomes:
		if outcome.has("atk_roll"):
			if caster:
				_pawn_manager.show_dice_roll(caster, int(outcome["atk_roll"]), true)
			var def_val: int = int(outcome.get("def_roll", 0))
			if def_val > 0:
				var target_unit_dr: BattleUnit = units_before.get(str(outcome.get("target", "")))
				if target_unit_dr:
					_pawn_manager.show_dice_roll(target_unit_dr, def_val, false)

	# Handle downing and revive from ability outcomes
	for outcome in outcomes:
		if outcome.get("is_downed", false):
			var downed_unit: BattleUnit = units_before.get(str(outcome["target"]))
			if downed_unit:
				_delay_down_pawn(downed_unit)
		elif outcome.get("revived", false):
			var revived_unit: BattleUnit = units_before.get(str(outcome["target"]))
			if revived_unit:
				_pawn_manager.revive_pawn(revived_unit)

	# Update status markers for caster and all affected units
	if caster:
		_pawn_manager.update_status_markers(caster)
		_pawn_manager.update_facing(caster)
	for key in units_before:
		var u: BattleUnit = units_before[key]
		_pawn_manager.update_status_markers(u)

	_overlay.clear()
	_check_end_activation_or_continue()


func _do_use_item(target_pos: Vector2i) -> void:
	var units_before := _snapshot_affected_units(target_pos)

	var item_id := _pending_item_id
	var result := TurnActions.execute_use_item(_state, item_id, target_pos)
	if result.has("error"):
		_hud.append_log("Item failed: %s" % str(result["error"]))
		return

	_hud.append_log("%s uses %s" % [
		str(result.get("actor", "")),
		str(result.get("item", ""))], item_id)

	# Show symbol pawn beside each affected target (awaitable landing beat)
	var user: BattleUnit = _state.current_unit
	var outcomes: Array = result.get("outcomes", [])
	var affected: Array = []
	for outcome in outcomes:
		var target_unit: BattleUnit = units_before.get(str(outcome.get("target", "")))
		if target_unit and target_unit not in affected:
			affected.append(target_unit)
	if not affected.is_empty():
		# Resolve icon from item's granted ability, or use item_id directly
		var icon: String = item_id
		var item: ItemData = GameData.get_item(item_id)
		if item and not item.granted_abilities.is_empty():
			var ability: AbilityData = GameData.get_ability(item.granted_abilities[0])
			icon = SymbolAtlas.symbol_for_ability(ability)
		await _pawn_manager.show_ability_pawns(affected, icon)

	# Show dice roll animations for damage outcomes
	for outcome in outcomes:
		if outcome.has("atk_roll"):
			if user:
				_pawn_manager.show_dice_roll(user, int(outcome["atk_roll"]), true)
			var def_val: int = int(outcome.get("def_roll", 0))
			if def_val > 0:
				var target_unit_dr: BattleUnit = units_before.get(str(outcome.get("target", "")))
				if target_unit_dr:
					_pawn_manager.show_dice_roll(target_unit_dr, def_val, false)

	for outcome in outcomes:
		if outcome.get("is_downed", false):
			var downed_unit: BattleUnit = units_before.get(str(outcome["target"]))
			if downed_unit:
				_delay_down_pawn(downed_unit)
		elif outcome.get("revived", false):
			var revived_unit: BattleUnit = units_before.get(str(outcome["target"]))
			if revived_unit:
				_pawn_manager.revive_pawn(revived_unit)

	# Update status markers for user and affected units
	if user:
		_pawn_manager.update_status_markers(user)
	for key in units_before:
		var u: BattleUnit = units_before[key]
		_pawn_manager.update_status_markers(u)

	_overlay.clear()
	_check_end_activation_or_continue()


func _do_defend() -> void:
	var result := TurnActions.execute_defend(_state)
	if result.has("error"):
		_hud.append_log("Defend failed: %s" % str(result["error"]))
		return

	var unit: BattleUnit = _state.current_unit
	_hud.append_log("%s defends (+2 DEF)" % unit.character.display_name, "action_defend")
	if unit:
		_pawn_manager.update_status_markers(unit)
	_overlay.clear()
	_check_end_activation_or_continue()


func _do_wait() -> void:
	var unit: BattleUnit = _state.current_unit
	if not unit:
		return

	var result := TurnActions.execute_wait(_state)
	_hud.append_log("%s waits" % unit.character.display_name, "action_wait")
	_overlay.clear()

	if _is_charge_time():
		_ct_end_activation(true)
		return

	var removed := RoundManager.end_activation(_state)
	if removed:
		_pawn_manager.remove_pawn(removed)
		_hud.append_log("%s has been permanently removed" % removed.character.display_name)
	if _check_match_over():
		return
	_enter_awaiting_activation()


func _cancel_targeting() -> void:
	_pending_action = -1
	_pending_ability_id = ""
	_pending_item_id = ""
	_enter_action_select()


func _start_new_round() -> void:
	if _is_charge_time():
		_ct_turn_system.begin_round(_state)
		# Refresh status markers for all surviving units
		for team in _state.parties.keys():
			for unit: BattleUnit in _state.parties[team]:
				if unit.current_hp > 0 or unit.is_downed:
					_pawn_manager.update_status_markers(unit)
		_hud.append_log("--- Round %d begins ---" % _state.round_number)
		_hud.show_round_banner(_state.round_number)
		_enter_ct_ticking()
		return

	RoundManager.start_round(_state)
	# Refresh status markers for all surviving units (durations may have expired)
	for team in _state.parties.keys():
		for unit: BattleUnit in _state.parties[team]:
			if unit.current_hp > 0 or unit.is_downed:
				_pawn_manager.update_status_markers(unit)
	_hud.append_log("--- Round %d begins ---" % _state.round_number)
	_hud.show_round_banner(_state.round_number)
	if _is_speed_round():
		_enter_ai_planning()
	else:
		_enter_awaiting_activation()


func _check_end_activation_or_continue() -> void:
	var unit: BattleUnit = _state.current_unit
	if not unit:
		if _is_charge_time():
			_ct_end_activation(false)
			return
		var removed := RoundManager.end_activation(_state)
		if removed:
			_pawn_manager.remove_pawn(removed)
			_hud.append_log("%s has been permanently removed" % removed.character.display_name)
		_enter_awaiting_activation()
	else:
		_enter_action_select()


# --- Log formatting ---

func _log_attack_result(result: Dictionary) -> void:
	var actor: String = str(result.get("actor", ""))
	var target: String = str(result.get("target", ""))

	if result.get("missed", false):
		_hud.append_log("%s attacks %s -- MISSED (%s)" % [
			actor, target, str(result.get("reason", ""))], "action_attack")
	else:
		var dmg: int = int(result.get("damage", 0))
		var hp_after: int = int(result.get("target_hp_after", 0))
		var downed: String = " DOWNED!" if result.get("is_downed", false) else ""
		_hud.append_log("%s attacks %s for %d damage (%d HP)%s" % [
			actor, target, dmg, hp_after, downed], "action_attack")


func _log_ability_result(result: Dictionary, ability_id: String = "") -> void:
	var actor: String = str(result.get("actor", ""))
	var ability_name: String = str(result.get("ability", ""))

	for outcome in result.get("outcomes", []):
		var target_name: String = str(outcome.get("target", ""))
		if outcome.has("damage"):
			var dmg: int = int(outcome.get("damage", 0))
			var hp_after: int = int(outcome.get("target_hp_after", 0))
			var downed: String = " DOWNED!" if outcome.get("is_downed", false) else ""
			var element: String = str(outcome.get("element", ""))
			var elem_str := " %s" % element if not element.is_empty() else ""
			_hud.append_log("%s casts %s on %s -- %d%s damage (%d HP)%s" % [
				actor, ability_name, target_name, dmg, elem_str, hp_after, downed], ability_id)
		elif outcome.has("healing"):
			var heal: int = int(outcome.get("healing", 0))
			var hp_after: int = int(outcome.get("target_hp_after", 0))
			_hud.append_log("%s casts %s on %s -- heals %d HP (%d HP)" % [
				actor, ability_name, target_name, heal, hp_after], ability_id)
		elif outcome.has("buff_stat"):
			var stat: String = str(outcome.get("buff_stat", ""))
			var val: int = int(outcome.get("buff_value", 0))
			var dur: int = int(outcome.get("buff_duration", 1))
			_hud.append_log("%s casts %s on %s -- +%d %s for %d rounds" % [
				actor, ability_name, target_name, val, stat.to_upper(), dur], ability_id)
		elif outcome.get("revived", false):
			var hp_after: int = int(outcome.get("target_hp_after", 0))
			_hud.append_log("%s casts %s on %s -- REVIVED! (%d HP)" % [
				actor, ability_name, target_name, hp_after], ability_id)
		elif outcome.has("status_id"):
			var status_id: String = str(outcome.get("status_id", ""))
			var dur: int = int(outcome.get("status_duration", 1))
			_hud.append_log("%s casts %s on %s -- %s for %d rounds" % [
				actor, ability_name, target_name, status_id, dur], ability_id)


# --- Helpers ---

func _delay_down_pawn(unit: BattleUnit) -> void:
	## Delay the visual flip animation until after dice have fully animated.
	## Game state (HP, is_downed) is already updated; only the visual flip is deferred.
	get_tree().create_timer(DiceMarker.TOTAL_DURATION).timeout.connect(
		func() -> void:
			if is_instance_valid(_pawn_manager) and _pawn_manager.has_pawn(unit):
				_pawn_manager.down_pawn(unit))


func _make_unit(char_id: String) -> BattleUnit:
	var c := GameData.get_character(char_id)
	var fs := GameData.get_final_stats(char_id)
	if not c or not fs:
		Log.error("BattleController", "Character '%s' not found" % char_id)
		return null
	return BattleUnit.from_character(c, fs)


func _snapshot_affected_units(target_pos: Vector2i) -> Dictionary:
	## Snapshot unit references keyed by character.id at and around target_pos.
	## Used to reliably map outcome["target"] back to BattleUnit after state mutation.
	## Includes both alive and downed units (for revive outcome mapping).
	var result: Dictionary = {}
	for team in _state.parties.keys():
		for unit: BattleUnit in _state.parties[team]:
			if unit.current_hp > 0 or unit.is_downed:
				result[unit.character.id + ":" + str(unit.position)] = unit
				# Also key by just character.id for simple lookup (last wins if dupes)
				result[unit.character.id] = unit
	return result


## A19: Returns a human-readable arc label for display in the forecast panel.
func _arc_label(arc: int) -> String:
	match arc:
		Hex.Arc.FLANK:
			var bonus: int = int(Constants.get_value("FLANK_HIT", 1))
			return " (FLANK +%d)" % bonus
		Hex.Arc.REAR:
			var bonus: int = int(Constants.get_value("REAR_HIT", 2))
			return " (REAR +%d)" % bonus
	return ""


func _find_ability(ability_id: String) -> AbilityData:
	for a in _current_abilities:
		if a is AbilityData and a.id == ability_id:
			return a
	return GameData.get_ability(ability_id)


func _get_usable_items(unit: BattleUnit) -> Array:
	var items: Array = []
	for eq_id in unit.character.equipment:
		var item: ItemData = GameData.get_item(eq_id)
		if item and not item.granted_abilities.is_empty():
			items.append(item)
	return items


func _show_ability_overlay(unit: BattleUnit, ability: AbilityData) -> void:
	if ability.ability_range == 0:
		# Self-targeted — no overlay needed
		return
	# Ranged abilities (range > 1) cannot target adjacent hexes
	var min_rng: int = 2 if ability.ability_range > 1 else 1
	_overlay.show_targets(unit.position, ability.ability_range, min_rng)


# --- Drag-and-drop movement ---

func _set_drag_enabled(on: bool) -> void:
	if _drag_handler:
		_drag_handler.set_enabled(on)


func _on_drag_move(destination: Vector2i) -> void:
	## Store the drag destination as a pending preview (not yet committed).
	var unit: BattleUnit = _state.current_unit
	if not unit:
		return

	# Pawn is already visually at destination from drag — store as pending
	_has_pending_move = true
	_pending_move_coord = destination
	_pawn_manager.sync_pawn_position(unit, destination)
	_hud.hide_action_panel()
	_hud.set_finalize_enabled(true)
	_set_drag_enabled(false)


func _on_drag_cancelled() -> void:
	# Pawn already snapped back by DragHandler — nothing to do
	pass


func _on_finalize_move() -> void:
	## Commit the pending drag-move preview.
	if not _has_pending_move:
		return
	var unit: BattleUnit = _state.current_unit
	if not unit:
		return

	var destination := _pending_move_coord
	_has_pending_move = false
	_pending_move_coord = Vector2i(-999, -999)

	var result := TurnActions.execute_move(_state, destination)
	if result.has("error"):
		_hud.append_log("Move failed: %s" % str(result["error"]))
		# Snap pawn back to its actual position in state
		if _drag_handler:
			_drag_handler.cancel_preview()
		_pawn_manager.sync_pawn_position(unit, unit.position)
		_hud.set_finalize_enabled(false)
		_enter_action_select()
		return

	_hud.append_log("%s moves to (%d,%d)" % [
		unit.character.display_name, destination.x, destination.y], "action_move")

	# Alpha A0: log terrain enter effects from drag-move
	for outcome in result.get("terrain_effects", []):
		if outcome.get("type") == "terrain_damage":
			_hud.append_log("%s takes %d terrain damage (%d HP)" % [
				unit.character.display_name, int(outcome["amount"]),
				int(outcome["target_hp_after"])], "terrain_damage")
		elif outcome.get("type") == "terrain_status":
			_hud.append_log("%s afflicted by %s" % [
				unit.character.display_name, str(outcome["status_id"])], "terrain_status")
	if unit:
		_pawn_manager.update_status_markers(unit)
		_pawn_manager.update_facing(unit)

	if _drag_handler:
		_drag_handler.confirm_preview()

	_pawn_manager.sync_pawn_position(unit, destination)
	_overlay.clear()
	_hud.set_finalize_enabled(false)
	_check_end_activation_or_continue()


func _on_cancel_move() -> void:
	## Cancel the pending drag-move preview and snap pawn back.
	if not _has_pending_move:
		return

	_has_pending_move = false
	_pending_move_coord = Vector2i(-999, -999)

	if _drag_handler:
		_drag_handler.cancel_preview()

	var unit: BattleUnit = _state.current_unit
	if unit:
		_pawn_manager.sync_pawn_position(unit, unit.position)

	_hud.set_finalize_enabled(false)
	_enter_action_select()


func _clear_pending_move() -> void:
	## Silently clear pending move state without snapping pawn (used when entering new state).
	_has_pending_move = false
	_pending_move_coord = Vector2i(-999, -999)


func _must_reserve_move() -> bool:
	## Returns true if the unit must spend its remaining AP on movement.
	## This enforces the rule: characters with base_ap >= 2 must move at least once.
	var unit := _state.current_unit
	if not unit:
		return false
	return unit.base_ap >= 2 and not unit.has_moved and unit.ap_remaining <= 1


# =======================================================================
# Charge-Time Flow (A20)
# =======================================================================

func _is_charge_time() -> bool:
	return _ct_turn_system != null


func _enter_ct_ticking() -> void:
	_control_state = ControlState.CT_TICKING
	_set_drag_enabled(false)
	_overlay.clear()
	_hud.hide_action_panel()
	_hud.hide_unit_info()
	_pawn_manager.clear_highlight()
	_hud.set_phase_label("Round %d - CT Clock" % _state.round_number)
	_ct_update_timeline()

	# Tick immediately to check for first activation
	_ct_do_tick()


func _ct_do_tick() -> void:
	## Tick the CT clock and check for an activation.
	if _control_state == ControlState.MATCH_OVER:
		return

	_ct_turn_system.advance(_state)
	var unit: BattleUnit = _ct_turn_system.activated_unit
	if unit:
		_ct_activate_unit(unit)
	else:
		# Continue ticking with visual pacing
		_ct_update_timeline()
		get_tree().create_timer(CT_TICK_INTERVAL).timeout.connect(_ct_do_tick)


func _ct_activate_unit(unit: BattleUnit) -> void:
	## A unit crossed the CT threshold — activate it.
	## CT mode bypasses RoundManager.activate_unit because that function
	## relies on the alternating activation_queue which CT mode does not use.
	_ct_update_timeline()

	# Validate unit can be activated
	if unit.current_hp <= 0 and not unit.is_downed:
		Log.error("BattleController", "CT activation failed: unit permanently removed")
		_ct_turn_system.on_activation_complete(_state, false)
		_ct_resume_after_activation()
		return

	# Direct CT activation (equivalent to RoundManager.activate_unit sans queue)
	unit.stats.remove_modifiers_by_source("defend")
	_state.current_unit = unit
	unit.has_moved = false
	_state.turn_log = []
	_state.phase = MatchState.Phase.UNIT_TURN

	var race_class_id := "%s_%s" % [unit.character.race,
		unit.character.classes[0] if not unit.character.classes.is_empty() else ""]
	_hud.append_log("%s activated (CT)" % unit.character.display_name, race_class_id)

	# Apply per-turn terrain damage at activation start
	var was_downed_before := unit.is_downed
	var terrain_outcomes := RoundManager.on_activation_start(_state, unit)
	for outcome in terrain_outcomes:
		var dmg: int = int(outcome.get("amount", 0))
		var hp_after: int = int(outcome.get("target_hp_after", 0))
		_hud.append_log("%s takes %d terrain damage (%d HP)" % [
			unit.character.display_name, dmg, hp_after], "terrain_damage")
		if unit.current_hp <= 0:
			_pawn_manager.down_pawn(unit)
			_hud.append_log("%s DOWNED by terrain!" % unit.character.display_name)
	_pawn_manager.update_status_markers(unit)

	if _check_match_over():
		return

	# If downed by terrain THIS activation, end immediately
	if unit.is_downed and not was_downed_before:
		_state.current_unit = null
		_ct_turn_system.on_activation_complete(_state, false)
		_ct_resume_after_activation()
		return

	# Route to AI or human
	if unit.team in _state.ai_teams:
		_control_state = ControlState.ANIMATING
		_pawn_manager.highlight_active(unit)
		_hud.update_round_info(_state.round_number, unit.team)
		_ai_controller.take_turn(_state)
	elif MatchData.opponent_type == "hot_seat" or unit.team not in _state.ai_teams:
		_pawn_manager.highlight_active(unit)
		_hud.update_round_info(_state.round_number, unit.team)
		_enter_action_select()


func _ct_end_activation(did_wait: bool) -> void:
	## End a CT activation and resume ticking.
	_state.current_unit = null
	_ct_turn_system.on_activation_complete(_state, did_wait)

	if _check_match_over():
		return

	_ct_resume_after_activation()


func _ct_resume_after_activation() -> void:
	## Resume the CT clock after an activation completes.
	if _ct_turn_system.is_round_complete(_state):
		_hud.append_log("--- Round %d complete ---" % _state.round_number)
		_start_new_round()
	else:
		_enter_ct_ticking()


func _ct_update_timeline() -> void:
	## Update the HUD timeline with upcoming activations.
	if not _ct_turn_system:
		return
	var timeline: Array = _ct_turn_system.get_timeline(6)
	_hud.update_ct_timeline(timeline)


func _on_ai_turn_complete_ct() -> void:
	## CT-mode version of AI turn completion.
	if _check_match_over():
		return
	_ct_end_activation(false)


# =======================================================================
# Speed-Round Flow (A15)
# =======================================================================

func _is_speed_round() -> bool:
	return _sr_turn_system != null


# --- Stage 1: AI Planning ---

func _enter_ai_planning() -> void:
	_control_state = ControlState.SR_AI_PLANNING
	_set_drag_enabled(false)
	_overlay.clear()
	_hud.hide_action_panel()
	_hud.hide_unit_info()
	_hud.hide_commit_round_panel()
	_pawn_manager.clear_highlight()
	_hud.set_phase_label("Round %d - AI Planning..." % _state.round_number)
	_hud.append_log("[Speed Round] AI is planning...")

	# Generate AI plans for all AI units
	var ai_plans: Dictionary = _ai_controller.plan_all_units(_state)

	# Collect AI units list
	var ai_units: Array = []
	for team in _state.ai_teams:
		for unit: BattleUnit in _state.living_units(team):
			ai_units.append(unit)

	# Commit AI plans to the turn system
	_sr_turn_system.commit_ai_plans(ai_plans, ai_units)

	# Build telegraph intents
	var telegraph_mode: String = str(Constants.get_value("TELEGRAPH_MODE", "full"))
	if telegraph_mode != "off":
		var intents: Array = TelegraphService.build_intents(_state, ai_plans, ai_units)
		_sr_turn_system.set_intents(intents)
		_overlay.show_telegraph_intents(intents, telegraph_mode)
		_hud.append_log("[Telegraph] AI intents revealed (%d units)" % intents.size())

	# Advance to player planning
	_sr_turn_system.advance(_state)
	_enter_sr_player_select()


# --- Stage 2: Player Planning ---

func _enter_sr_player_select() -> void:
	_control_state = ControlState.SR_PLAYER_SELECT
	_planning_unit = null
	_planning_plan = null
	_set_drag_enabled(false)
	_hud.set_targeting_mode(false)
	_hud.hide_action_panel()
	_hud.hide_forecast()

	# Determine which player units need plans
	var player_team := _state.other_team(_state.ai_teams[0]) if not _state.ai_teams.is_empty() else "playerA"
	var plannable: Array = []
	for unit: BattleUnit in _state.living_units(player_team):
		if not unit.is_downed:
			plannable.append(unit)

	# Check if all plannable units have plans
	var all_planned := true
	var planned_count := 0
	for unit: BattleUnit in plannable:
		if _player_plans.has(unit.character.id):
			planned_count += 1
		else:
			all_planned = false

	_hud.set_phase_label("Round %d - Plan Your Units (%d/%d)" % [
		_state.round_number, planned_count, plannable.size()])

	# Show commit button
	_hud.show_commit_round_panel(all_planned and not plannable.is_empty(), false)

	# Highlight plannable units and show their positions
	var selectable_positions: Array = []
	var selectable_ids: Array = []
	for unit: BattleUnit in plannable:
		selectable_positions.append(unit.position)
		selectable_ids.append(unit.character.id)
	_pawn_manager.highlight_selectable(plannable)

	# Keep telegraph overlay visible during planning (don't clear)
	# Show selectable unit tiles on top of telegraph
	var mat := OverlayMaterials.selectable()
	for pos in selectable_positions:
		if _builder.tiles.has(pos):
			_builder.tiles[pos].set_overlay(mat)

	# Build planned_ids for roster display
	var planned_ids: Array = []
	for uid in _player_plans.keys():
		planned_ids.append(uid)

	_hud.update_roster(_state, null, selectable_ids, planned_ids)


func _sr_try_select_plan_unit(coord: Vector2i) -> void:
	## Handle tile click during SR_PLAYER_SELECT — select a unit for planning.
	var player_team := _state.other_team(_state.ai_teams[0]) if not _state.ai_teams.is_empty() else "playerA"
	var unit: BattleUnit = _state.unit_at(coord)
	if not unit or unit.team != player_team:
		return
	if unit.current_hp <= 0 or unit.is_downed:
		return
	_sr_begin_plan_unit(unit)


func _sr_select_plan_unit_by_id(character_id: String) -> void:
	## Handle roster click during SR_PLAYER_SELECT.
	var player_team := _state.other_team(_state.ai_teams[0]) if not _state.ai_teams.is_empty() else "playerA"
	for unit: BattleUnit in _state.living_units(player_team):
		if unit.character.id == character_id and not unit.is_downed:
			_sr_begin_plan_unit(unit)
			return


func _sr_begin_plan_unit(unit: BattleUnit) -> void:
	## Start planning for a specific player unit.
	_planning_unit = unit
	_planning_plan = AIPlan.new()
	_planning_ap_left = unit.base_ap
	_planning_moved = false
	_planning_move_dest = unit.position

	# If already had a plan, clear it (revision)
	_player_plans.erase(unit.character.id)

	_hud.append_log("Planning: %s" % unit.character.display_name)
	_pawn_manager.highlight_active(unit)
	_hud.show_unit_info(unit)
	_enter_sr_plan_action()


func _enter_sr_plan_action() -> void:
	## Show the action panel for the planning unit with simulated AP.
	_control_state = ControlState.SR_PLANNING_ACTION
	var unit := _planning_unit
	if not unit:
		_enter_sr_player_select()
		return

	# Cache abilities and items for this unit
	_current_abilities = _resolver.all_abilities(unit)
	_current_items = _get_usable_items(unit)

	# Compute WP costs for usable items
	var item_wp_costs := {}
	for item in _current_items:
		if item is ItemData and not item.granted_abilities.is_empty():
			var ability: AbilityData = _resolver.resolve(unit, item.granted_abilities[0])
			if ability:
				item_wp_costs[item.id] = ability.wp_cost

	# Temporarily set simulated AP for the action panel display
	var original_ap := unit.ap_remaining
	var original_moved := unit.has_moved
	unit.ap_remaining = _planning_ap_left
	unit.has_moved = _planning_moved
	_hud.show_unit_info(unit)
	_hud.show_action_panel(unit, _current_abilities, _current_items, false, item_wp_costs)
	unit.ap_remaining = original_ap
	unit.has_moved = original_moved

	_hud.set_targeting_mode(false)
	_hud.show_commit_round_panel(false, _player_plans.has(unit.character.id))

	# Show movement overlay from the planned position
	var origin := _planning_move_dest if _planning_moved else unit.position
	if _planning_ap_left > 0 and not _planning_moved:
		_overlay.clear_telegraph()
		_overlay.show_movement(origin, unit.stats.effective_move(), unit.stats.effective("jump"))
	else:
		_overlay.clear()


func _sr_try_click_move(coord: Vector2i) -> void:
	## Handle tile click during SR_PLANNING_ACTION — direct click-to-move.
	## If the clicked tile is within movement range, record a move plan step.
	var unit := _planning_unit
	if not unit:
		return
	if _planning_ap_left < 1 or _planning_moved:
		return
	if coord == unit.position:
		return

	# Validate tile is reachable (matches the displayed movement overlay)
	var reach := Movement.reachable(
		_state.graph, unit.position, unit.stats.effective_move(), unit.stats.effective("jump"))
	if not reach.has(coord):
		return

	_sr_plan_move(coord)


func _sr_enter_plan_targeting(action: int, ability_id: String = "", item_id: String = "") -> void:
	## Enter targeting mode for planning.
	_control_state = ControlState.SR_PLANNING_TARGETING
	_pending_action = action
	_pending_ability_id = ability_id
	_pending_item_id = item_id
	_set_drag_enabled(false)

	var unit := _planning_unit
	if not unit:
		return

	_hud.set_targeting_mode(true)
	_hud.hide_commit_round_panel()
	_overlay.clear()

	# Compute overlay from the planned position (after move)
	var origin := _planning_move_dest if _planning_moved else unit.position

	match action:
		BattleHUD.ACTION_MOVE:
			_overlay.show_movement(
				unit.position, unit.stats.effective_move(), unit.stats.effective("jump"))
		BattleHUD.ACTION_ATTACK:
			var rng: int = unit.stats.effective("rng")
			var min_rng: int = 2 if rng > 1 else 1
			_overlay.show_targets(origin, rng, min_rng)
		BattleHUD.ACTION_ABILITY:
			var ability := _find_ability(ability_id)
			if ability:
				if str(ability.effect.get("effect_type", "")) == "revive":
					_overlay.show_revive_targets(origin, ability.ability_range, _state, unit.team)
				else:
					var min_rng: int = 2 if ability.ability_range > 1 else 1
					_overlay.show_targets(origin, ability.ability_range, min_rng)
		BattleHUD.ACTION_ITEM:
			var item: ItemData = GameData.get_item(item_id)
			if item and not item.granted_abilities.is_empty():
				var ability := _find_ability(item.granted_abilities[0])
				if ability:
					var min_rng: int = 2 if ability.ability_range > 1 else 1
					_overlay.show_targets(origin, ability.ability_range, min_rng)


func _sr_execute_plan_targeting(coord: Vector2i) -> void:
	## Handle tile click during SR_PLANNING_TARGETING.
	match _pending_action:
		BattleHUD.ACTION_MOVE:
			_sr_plan_move(coord)
		BattleHUD.ACTION_ATTACK:
			_sr_plan_attack(coord)
		BattleHUD.ACTION_ABILITY:
			_sr_plan_ability(coord, _pending_ability_id)
		BattleHUD.ACTION_ITEM:
			_sr_plan_use_item(coord, _pending_item_id)


func _sr_plan_move(dest: Vector2i) -> void:
	## Record a move step in the planning plan.
	if _planning_ap_left < 1:
		return
	_planning_plan.add_step({"kind": "move", "target_pos": dest})
	_planning_ap_left -= 1
	_planning_moved = true
	_planning_move_dest = dest
	_hud.append_log("  Plan: Move to (%d,%d)" % [dest.x, dest.y], "action_move")

	# If AP remains, show remaining actions from new position
	if _planning_ap_left > 0:
		_enter_sr_plan_action()
	else:
		_sr_finalize_unit_plan()


func _sr_plan_attack(target_pos: Vector2i) -> void:
	## Record an attack step in the planning plan.
	if _planning_ap_left < 1:
		return
	_planning_plan.add_step({"kind": "attack", "target_pos": target_pos})
	_planning_ap_left -= 1
	var target: BattleUnit = _state.unit_at(target_pos)
	var target_name := target.character.display_name if target else "(%d,%d)" % [target_pos.x, target_pos.y]

	# Show damage forecast
	if target and _planning_unit:
		var origin := _planning_move_dest if _planning_moved else _planning_unit.position
		var weapon_power: int = CombatResolver.get_weapon_power(_planning_unit, _state.item_provider)
		var atk_elev: int = _state.graph.elevation(origin)
		var tgt_elev: int = _state.graph.elevation(target_pos)
		var tgt_cover: int = _state.graph.effective_cover(target_pos)
		var is_ranged: bool = _planning_unit.stats.effective("rng") > 1
		# A19: compute arc for forecast display
		var plan_arc: int = Hex.arc_between(origin, target_pos, target.facing)
		var proj: Dictionary = OutcomeProjection.project_attack(
			_planning_unit, target, weapon_power, atk_elev, tgt_elev, tgt_cover, is_ranged, plan_arc)
		var arc_label: String = _arc_label(plan_arc)
		_hud.append_log("  Plan: Attack %s [%d-%d dmg]%s" % [
			target_name, proj["min"], proj["max"], arc_label], "action_attack")
		_hud.show_forecast(proj, "Damage", arc_label)
	else:
		_hud.append_log("  Plan: Attack %s" % target_name, "action_attack")

	_sr_finalize_unit_plan()


func _sr_plan_ability(target_pos: Vector2i, ability_id: String) -> void:
	## Record an ability step in the planning plan.
	var ability := _find_ability(ability_id)
	var ap_cost: int = ability.ap_cost if ability else 1
	if _planning_ap_left < ap_cost:
		return
	_planning_plan.add_step({
		"kind": "ability",
		"ability_id": ability_id,
		"target_pos": target_pos,
		"ap_cost": ap_cost
	})
	_planning_ap_left -= ap_cost
	var ability_name := ability.display_name if ability else ability_id

	# Show damage/healing forecast
	if ability and _planning_unit:
		var effect_type: String = str(ability.effect.get("effect_type", ""))
		var effect_value: int = int(ability.effect.get("value", 0))
		var origin := _planning_move_dest if _planning_moved else _planning_unit.position
		var caster_elev: int = _state.graph.elevation(origin)
		var tgt_elev: int = _state.graph.elevation(target_pos)
		var target: BattleUnit = _state.unit_at(target_pos)

		if effect_type == "damage" and target:
			var proj: Dictionary = OutcomeProjection.project_ability_damage(
				_planning_unit, target, effect_value, ability.type,
				caster_elev, tgt_elev, ability.mag_scaling)
			_hud.append_log("  Plan: %s [%d-%d dmg]" % [
				ability_name, proj["min"], proj["max"]], ability_id)
			_hud.show_forecast(proj)
		elif effect_type == "heal" and target:
			var proj: Dictionary = OutcomeProjection.project_heal(
				target, effect_value, _planning_unit, ability.mag_scaling)
			_hud.append_log("  Plan: %s [%d heal]" % [
				ability_name, proj["mid"]], ability_id)
			_hud.show_forecast(proj, "Healing")
		else:
			_hud.append_log("  Plan: %s" % ability_name, ability_id)
	else:
		_hud.append_log("  Plan: %s" % ability_name, ability_id)

	_sr_finalize_unit_plan()


func _sr_plan_use_item(target_pos: Vector2i, item_id: String) -> void:
	## Record a use_item step in the planning plan.
	if _planning_ap_left < 1:
		return
	_planning_plan.add_step({
		"kind": "use_item",
		"item_id": item_id,
		"target_pos": target_pos
	})
	_planning_ap_left -= 1
	_hud.append_log("  Plan: Use %s" % item_id, item_id)
	_sr_finalize_unit_plan()


func _sr_plan_defend() -> void:
	## Record a defend step.
	if _planning_ap_left < 1:
		return
	_planning_plan.add_step({"kind": "defend"})
	_planning_ap_left -= 1
	_hud.append_log("  Plan: Defend", "action_defend")
	_sr_finalize_unit_plan()


func _sr_plan_wait() -> void:
	## Record a wait step — immediately finalizes the plan.
	_planning_plan.add_step({"kind": "wait"})
	_hud.append_log("  Plan: Wait", "action_wait")
	_sr_finalize_unit_plan()


func _sr_finalize_unit_plan() -> void:
	## Store the completed plan and return to unit selection.
	if _planning_unit and _planning_plan and not _planning_plan.is_empty():
		_player_plans[_planning_unit.character.id] = _planning_plan
		_hud.append_log("Plan committed for %s" % _planning_unit.character.display_name)
	_planning_unit = null
	_planning_plan = null
	_enter_sr_player_select()


func _on_commit_round() -> void:
	## Player pressed "Commit Round" — commit all plans and start resolution.
	if _control_state != ControlState.SR_PLAYER_SELECT:
		return

	# Commit all player plans to the turn system
	var player_team := _state.other_team(_state.ai_teams[0]) if not _state.ai_teams.is_empty() else "playerA"
	for unit: BattleUnit in _state.living_units(player_team):
		if not unit.is_downed:
			var plan: AIPlan = _player_plans.get(unit.character.id)
			if plan:
				_sr_turn_system.commit_player_plan(unit, plan)

	# Advance to resolution
	_sr_turn_system.advance(_state)
	_hud.append_log("--- Plans committed, resolving... ---")
	_player_plans.clear()
	_enter_sr_resolution()


func _on_clear_plan() -> void:
	## Player pressed "Clear Plan" for the current planning unit.
	if _planning_unit:
		_player_plans.erase(_planning_unit.character.id)
		_hud.append_log("Plan cleared for %s" % _planning_unit.character.display_name)
	_planning_unit = null
	_planning_plan = null
	_enter_sr_player_select()


# --- Stage 3: Resolution ---

func _enter_sr_resolution() -> void:
	_control_state = ControlState.SR_RESOLUTION
	_set_drag_enabled(false)
	_overlay.clear_telegraph()
	_overlay.clear()
	_hud.hide_action_panel()
	_hud.hide_commit_round_panel()
	_hud.hide_forecast()
	_pawn_manager.clear_highlight()
	_hud.set_phase_label("Round %d - Resolving..." % _state.round_number)

	# Start the resolution loop
	_sr_resolve_loop()


func _sr_resolve_loop() -> void:
	## Async loop that resolves one unit at a time with animation.
	if not _sr_turn_system.has_next_resolution():
		_enter_sr_round_reset()
		return

	if _check_match_over():
		return

	var result: Dictionary = _sr_turn_system.resolve_next(_state)

	if result.get("done", false):
		_enter_sr_round_reset()
		return

	# Animate the resolution result, then continue
	await _sr_animate_resolution(result)
	_sr_resolve_loop()


func _sr_animate_resolution(result: Dictionary) -> void:
	## Animate one unit's resolution results.
	var unit_id: String = str(result.get("unit_id", ""))

	if result.get("fizzled", false):
		var reason: String = str(result.get("reason", ""))
		_hud.append_log("[Resolve] %s's plan fizzled (%s)" % [unit_id, reason])
		# Animate terrain effects even on fizzle
		for effect in result.get("terrain_effects", []):
			_sr_log_terrain_effect(unit_id, effect)
		await get_tree().create_timer(0.3).timeout
		return

	# Find the unit for visual updates
	var unit: BattleUnit = _find_unit_by_id(unit_id)
	if unit:
		_pawn_manager.highlight_active(unit)
		_hud.show_unit_info(unit)

	var results: Array = result.get("results", [])
	for step_result in results:
		if step_result is Dictionary:
			await _sr_animate_step(step_result, unit)

	if unit:
		_pawn_manager.update_status_markers(unit)

	# Brief pause between unit resolutions
	await get_tree().create_timer(0.4).timeout

	if _check_match_over():
		return


func _sr_animate_step(step_result: Dictionary, unit: BattleUnit) -> void:
	## Animate a single resolution step result.
	var action: String = str(step_result.get("action", ""))

	# Terrain damage results
	if step_result.get("type") == "terrain_damage":
		var target_id: String = str(step_result.get("target", ""))
		_sr_log_terrain_effect(target_id, step_result)
		if unit:
			_pawn_manager.update_status_markers(unit)
		return

	# Fizzled step
	if step_result.get("fizzled", false):
		var reason: String = str(step_result.get("reason", ""))
		var actor: String = str(step_result.get("actor", ""))
		_hud.append_log("[Resolve] %s's %s fizzled (%s)" % [actor, action, reason])
		await get_tree().create_timer(0.3).timeout
		return

	# Move
	if step_result.has("from") and step_result.has("to"):
		var to_pos: Vector2i = step_result["to"]
		var actor_name: String = str(step_result.get("actor", ""))
		_hud.append_log("[Resolve] %s moves to (%d,%d)" % [actor_name, to_pos.x, to_pos.y], "action_move")

		# Log terrain effects from movement
		for effect in step_result.get("terrain_effects", []):
			_sr_log_terrain_effect(actor_name, effect)

		# Animate pawn movement
		if unit:
			var tw := _pawn_manager.move_pawn(unit, to_pos)
			if tw:
				await tw.finished
			_pawn_manager.update_status_markers(unit)
		return

	# Attack
	if step_result.has("damage") or step_result.get("missed", false):
		_log_attack_result(step_result)
		var target_id: String = str(step_result.get("target", ""))
		var target_unit: BattleUnit = _find_unit_by_id(target_id)

		# Show dice rolls
		if unit and step_result.has("atk_roll"):
			_pawn_manager.show_dice_roll(unit, int(step_result["atk_roll"]), true)
		var def_roll: int = int(step_result.get("def_roll", 0))
		if target_unit and def_roll > 0:
			_pawn_manager.show_dice_roll(target_unit, def_roll, false)

		# Show action marker
		if target_unit:
			_pawn_manager.show_action_marker(target_unit, "action_attack")

		# Handle downing
		if step_result.get("is_downed", false) and target_unit:
			_delay_down_pawn(target_unit)
		if target_unit:
			_pawn_manager.update_status_markers(target_unit)

		await get_tree().create_timer(DiceMarker.TOTAL_DURATION).timeout
		return

	# Ability
	if step_result.has("outcomes"):
		_log_ability_result(step_result, str(step_result.get("ability", "")))
		var outcomes: Array = step_result.get("outcomes", [])

		for outcome in outcomes:
			var target_id: String = str(outcome.get("target", ""))
			var target_unit: BattleUnit = _find_unit_by_id(target_id)

			if outcome.has("atk_roll") and unit:
				_pawn_manager.show_dice_roll(unit, int(outcome["atk_roll"]), true)
			var dv: int = int(outcome.get("def_roll", 0))
			if target_unit and dv > 0:
				_pawn_manager.show_dice_roll(target_unit, dv, false)
			if target_unit:
				_pawn_manager.show_action_marker(target_unit, str(step_result.get("ability", "")))
			if outcome.get("is_downed", false) and target_unit:
				_delay_down_pawn(target_unit)
			elif outcome.get("revived", false) and target_unit:
				_pawn_manager.revive_pawn(target_unit)
			if target_unit:
				_pawn_manager.update_status_markers(target_unit)

		var has_dice := false
		for outcome in outcomes:
			if outcome.has("atk_roll"):
				has_dice = true
				break
		if has_dice:
			await get_tree().create_timer(DiceMarker.TOTAL_DURATION).timeout
		return

	# Defend
	if step_result.has("defended") or action == "defend":
		var actor: String = str(step_result.get("actor", ""))
		_hud.append_log("[Resolve] %s defends" % actor, "action_defend")
		if unit:
			_pawn_manager.update_status_markers(unit)
		await get_tree().create_timer(0.3).timeout
		return

	# Wait / other
	if action == "wait":
		var actor: String = str(step_result.get("actor", ""))
		_hud.append_log("[Resolve] %s waits" % actor, "action_wait")
		return


func _sr_log_terrain_effect(who: String, effect: Dictionary) -> void:
	if effect.get("type") == "terrain_damage":
		var dmg: int = int(effect.get("amount", 0))
		var hp: int = int(effect.get("target_hp_after", 0))
		_hud.append_log("[Resolve] %s takes %d terrain damage (%d HP)" % [who, dmg, hp], "terrain_damage")


# --- Stage 4: Round Reset ---

func _enter_sr_round_reset() -> void:
	_hud.append_log("--- Round %d complete ---" % _state.round_number)

	if _check_match_over():
		return

	# Start next round
	_start_new_round()


# --- Speed-round helpers ---

func _find_unit_by_id(unit_id: String) -> BattleUnit:
	for team in _state.parties.keys():
		for unit: BattleUnit in _state.parties[team]:
			if unit.character.id == unit_id:
				return unit
	return null
