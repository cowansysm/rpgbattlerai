class_name BattleController
extends Node
## State-machine combat controller replacing Phase4Demo.
## Manages game flow, wires HUD signals to TurnActions, syncs PawnManager.
## Spec reference: phase8-spec.md §5

enum ControlState {
	AWAITING_ACTIVATION,
	ACTION_SELECT,
	TARGETING,
	ANIMATING,
	MATCH_OVER,
}

var _state: MatchState
var _builder: MapBuilder
var _overlay: OverlayController
var _pawn_manager: PawnManager
var _hud: BattleHUD
var _resolver: AbilityResolver
var _drag_handler: DragHandler

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

	_resolver = AbilityResolver.new(
		GameData.get_ability, GameData.get_job_class, GameData.get_item)
	_state.ability_provider = _resolver.resolve
	_state.item_provider = GameData.get_item

	var errors := Deployment.auto_deploy(_state, map_data.deployment_zones)
	if not errors.is_empty():
		for e in errors:
			Log.error("BattleController", e)
		return

	_init_subsystems(builder)
	RoundManager.start_round(_state)
	_enter_awaiting_activation()


func setup_from_state(builder: MapBuilder, state: MatchState) -> void:
	_builder = builder
	_state = state

	_resolver = AbilityResolver.new(
		GameData.get_ability, GameData.get_job_class, GameData.get_item)
	# Wire ability/item providers if not already set
	if not _state.ability_provider.is_valid():
		_state.ability_provider = _resolver.resolve
	if not _state.item_provider.is_valid():
		_state.item_provider = GameData.get_item

	_init_subsystems(builder)
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

	# Initial HUD state
	_hud.update_roster(_state, null)
	_hud.update_turn_order(_state)
	_hud.append_log("--- Battle begins! ---")


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


func _on_back_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/draft/draft_scene.tscn")


# --- Input handling ---

func on_tile_selected(coord: Vector2i) -> void:
	if _control_state == ControlState.MATCH_OVER:
		return
	_selected_tile = coord

	if _control_state == ControlState.AWAITING_ACTIVATION:
		# If there's a pending activation, clear it and try selecting the new tile
		if _pending_activation_unit:
			_clear_pending_activation()
		_try_select_unit(coord)
	elif _control_state == ControlState.TARGETING:
		_execute_targeting(coord)


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
	elif event.is_action_pressed("p4_attack"):
		if _control_state == ControlState.ACTION_SELECT and not _must_reserve_move():
			_enter_targeting(BattleHUD.ACTION_ATTACK)
	elif event.is_action_pressed("p4_defend"):
		if _control_state == ControlState.ACTION_SELECT and not _must_reserve_move():
			_do_defend()
	elif event.is_action_pressed("p4_wait"):
		if _control_state == ControlState.ACTION_SELECT:
			_do_wait()
	elif event.is_action_pressed("ui_cancel"):
		if _control_state == ControlState.AWAITING_ACTIVATION and _pending_activation_unit:
			_clear_pending_activation()
		elif _control_state == ControlState.TARGETING:
			_cancel_targeting()
	elif event.is_action_pressed("demo_clear"):
		if _overlay:
			_overlay.clear()


# --- HUD signal handlers ---

func _on_action_selected(action_type: int) -> void:
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

	# If the unit was downed by terrain damage, end activation immediately
	if unit.is_downed:
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
	## Handle roster sidebar click — set as pending activation.
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

	# Show action icon on target
	if target_unit_pre:
		_pawn_manager.show_action_marker(target_unit_pre, "action_attack")

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

	# Show ability icon on each affected target
	var caster: BattleUnit = _state.current_unit
	var outcomes: Array = result.get("outcomes", [])
	for outcome in outcomes:
		var target_unit: BattleUnit = units_before.get(str(outcome.get("target", "")))
		if target_unit:
			_pawn_manager.show_action_marker(target_unit, ability_id)

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

	# Show item icon on each affected target
	var user: BattleUnit = _state.current_unit
	var outcomes: Array = result.get("outcomes", [])
	for outcome in outcomes:
		var target_unit: BattleUnit = units_before.get(str(outcome.get("target", "")))
		if target_unit:
			_pawn_manager.show_action_marker(target_unit, item_id)

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
	RoundManager.start_round(_state)
	# Refresh status markers for all surviving units (durations may have expired)
	for team in _state.parties.keys():
		for unit: BattleUnit in _state.parties[team]:
			if unit.current_hp > 0 or unit.is_downed:
				_pawn_manager.update_status_markers(unit)
	_hud.append_log("--- Round %d begins ---" % _state.round_number)
	_hud.show_round_banner(_state.round_number)
	_enter_awaiting_activation()


func _check_end_activation_or_continue() -> void:
	var unit: BattleUnit = _state.current_unit
	if not unit:
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
