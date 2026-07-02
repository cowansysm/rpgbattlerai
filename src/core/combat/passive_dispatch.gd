class_name PassiveDispatch
extends RefCounted
## Centralized passive ability trigger dispatch (A18).
## Fires typed events through the equipped reaction slot; support/movement
## passives are applied at BattleUnit construction time and do not use this bus.
##
## Rules:
## - A reaction fires at most once per triggering event.
## - reaction_locked prevents counter-of-counter infinite chains.
## - Downed/dead subjects do not react.
## - Auto-Potion / Defend Reflex only fire while current_hp > 0.
## - Resolution goes through CombatResolver roll seams (dice_roller/crit_roller)
##   so tests that swap callables remain reproducible.

## Typed event constants.
const ON_HIT := "on_hit"           ## Melee weapon attack landed on subject (rng <= 1 or adjacent)
const ON_DAMAGED := "on_damaged"   ## Any damage applied to subject
const ON_LOW_HP := "on_low_hp"     ## Subject HP crossed below the LOW_HP_PCT threshold
const ON_TURN_START := "on_turn_start"  ## Subject's activation begins
const ON_MOVE_QUERY := "on_move_query"  ## Query phase for movement-budget adjustment (unused in A18 runtime fire)
const ON_HAZARD_ENTER := "on_hazard_enter"  ## Subject enters a hazard tile (damage_on_enter)


## Fire a passive event for a subject unit.
## ctx keys: attacker (BattleUnit), state (MatchState), item_provider (Callable).
## Returns an Array of outcome Dictionaries describing what happened.
## Returns [] when no reaction fires (slot empty, wrong trigger, guards fail).
static func fire(event: String, subject: BattleUnit, ctx: Dictionary) -> Array:
	# Guard: dead or already reaction-locked units do not react
	if not subject.is_alive():
		return []
	if subject.reaction_locked:
		return []

	var ab_id: String = subject.equipped_passive("reaction")
	if ab_id.is_empty():
		return []

	var state: MatchState = ctx.get("state", null) as MatchState
	if state == null:
		return []

	var ability_provider: Callable = state.ability_provider
	if not ability_provider.is_valid():
		return []

	var ab: AbilityData = ability_provider.call(subject, ab_id)
	if ab == null or ab.passive_kind != "reaction":
		return []

	var trigger: Dictionary = ab.trigger
	if str(trigger.get("event", "")) != event:
		return []

	# Guard: melee_only — only fire if the attack was melee (attacker range <= 1)
	if bool(trigger.get("melee_only", false)):
		var attacker: BattleUnit = ctx.get("attacker", null) as BattleUnit
		if attacker == null:
			return []
		if attacker.stats.effective("rng") > 1:
			return []

	# Guard: hp_pct threshold — only fire if subject HP is at or below the fraction
	var hp_pct: float = float(trigger.get("hp_pct", 1.0))
	if hp_pct < 1.0:
		var max_hp: int = subject.stats.effective("hp")
		if max_hp <= 0:
			return []
		var current_ratio: float = float(subject.current_hp) / float(max_hp)
		if current_ratio > hp_pct:
			return []

	# Dispatch to the correct reaction handler
	match ab_id:
		"counter":
			return _fire_counter(subject, ctx, state)
		"auto_potion":
			return _fire_auto_potion(subject, ctx, state)
		"defend_reflex":
			return _fire_defend_reflex(subject, ctx, state)
		_:
			# Generic: attempt to dispatch by trigger kind if known
			return []


# --- Reaction handlers ---

## A19: Arc values from which a Counter can fire. Rear attacks are not defensible.
const COUNTER_DEFENSIBLE_ARCS: Array = [0, 1]  # Hex.Arc.FRONT, Hex.Arc.FLANK


static func _fire_counter(subject: BattleUnit, ctx: Dictionary, state: MatchState) -> Array:
	## Counter: subject retaliates against the attacker with a basic weapon attack.
	## A19: blocked from REAR arc — you cannot counter an attack you did not see coming.
	var attacker: BattleUnit = ctx.get("attacker", null) as BattleUnit
	if attacker == null or not attacker.is_alive():
		return []

	# A19: check arc; skip Counter if attack came from REAR
	var attack_arc: int = int(ctx.get("arc", Hex.Arc.FRONT))
	if not COUNTER_DEFENSIBLE_ARCS.has(attack_arc):
		return []

	# Lock to prevent counter-chains
	subject.reaction_locked = true

	var item_provider: Callable = state.item_provider
	var weapon_power: int = CombatResolver.get_weapon_power(subject, item_provider)
	var subj_elev: int = state.graph.elevation(subject.position)
	var atk_elev: int = state.graph.elevation(attacker.position)
	var cover: int = state.graph.effective_cover(attacker.position)

	var result: Dictionary = CombatResolver.resolve_attack(
		subject, attacker, weapon_power,
		subj_elev, atk_elev, cover, false)

	var outcome: Dictionary = {
		"reaction": "counter",
		"actor": subject.character.id,
		"target": attacker.character.id,
		"damage": result["damage"],
		"atk_roll": result["atk_roll"],
		"def_roll": result["def_roll"],
		"target_hp_after": result["target_hp_after"],
		"is_downed": result["is_downed"],
	}

	if result["is_downed"]:
		TurnActions._handle_downing(state, attacker)

	subject.reaction_locked = false
	return [outcome]


static func _fire_auto_potion(subject: BattleUnit, ctx: Dictionary, _state: MatchState) -> Array:
	## Auto-Potion: consumes a potion from the band's active inventory to heal.
	## Only heals; does not un-down (A17 compatibility).
	if subject.current_hp <= 0:
		return []

	# Check for potion in the state's active_band (if tracked in ctx or state)
	var potion_id: String = str(
		Constants.get_value("PASSIVE_AUTO_POTION_ITEM", "potion"))
	var heal_amount: int = int(
		Constants.get_value("PASSIVE_AUTO_POTION_HEAL", 8))

	# Consume the potion if available via active_band in ctx
	var consumed: bool = false
	var active_band: RefCounted = ctx.get("active_band", null) as RefCounted
	if active_band != null and active_band.has_consumable(potion_id):
		active_band.remove_consumable(potion_id, 1)
		consumed = true
	# Fallback: check unit's character equipment (for tests / authored units)
	elif potion_id in subject.character.equipment:
		consumed = true  # authored unit has the item, treat as available

	if not consumed:
		return [{"reaction": "auto_potion", "actor": subject.character.id, "no_item": true}]

	var max_hp: int = subject.stats.effective("hp")
	var actual_heal: int = mini(heal_amount, max_hp - subject.current_hp)
	subject.current_hp = mini(subject.current_hp + actual_heal, max_hp)

	return [{
		"reaction": "auto_potion",
		"actor": subject.character.id,
		"healing": actual_heal,
		"target_hp_after": subject.current_hp,
	}]


static func _fire_defend_reflex(subject: BattleUnit, _ctx: Dictionary, _state: MatchState) -> Array:
	## Defend Reflex: applies a Defend modifier at low HP (same as the Defend action).
	if subject.current_hp <= 0:
		return []

	var def_bonus: int = int(Constants.get_value("PASSIVE_DEFEND_REFLEX_DEF", 3))
	# Apply only if not already defending (avoid double-stacking)
	if not subject.stats.has_modifier_from_source("defend_reflex"):
		subject.stats.push_modifier(StatModifier.new("def", def_bonus, "defend_reflex"))

	return [{
		"reaction": "defend_reflex",
		"actor": subject.character.id,
		"def_bonus": def_bonus,
	}]
