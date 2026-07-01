class_name RunController
extends RefCounted
## Core orchestrator for roguelike run traversal and node resolution.
## Dispatches node resolution by kind, manages rewards, and persists state.
## Scene-level code (RunScene) calls this and handles UI/transitions.

var _meta_unlocks_provider: Variant = null  ## Callable returning meta_unlocks table
var _last_earned_unlocks: Array[Dictionary] = []


## Injects the meta-unlocks data provider (Callable -> Dictionary).
func set_meta_unlocks_provider(provider: Callable) -> void:
	_meta_unlocks_provider = provider


## Returns unlocks earned during the most recent run-end.
func get_last_earned_unlocks() -> Array[Dictionary]:
	return _last_earned_unlocks


## Creates a new run: resets downs, generates graph, applies boons, saves.
## Returns the new RunState.
func embark(band: BattleBand, seed_value: int, cfg: Dictionary,
		boons: Array[Dictionary] = []) -> RunState:
	DeathModel.reset_downs(band)
	var rs: RunState = RunState.create_new(band.band_id, seed_value, cfg)
	_apply_boons(band, rs, boons)
	SaveManager.active_run = rs
	SaveManager.save_game()
	return rs


## Advances to the given node. Returns a resolution dict by node kind.
## For battle/boss: {kind, encounter: {map, enemy_instances}, is_boss: bool}
## For event/boon/hazard: {kind, outcome: {event, effects_applied}}
## For shop: {kind: "shop"}
## For rest: {kind: "rest", healed: Array[String]}
## For invalid moves: {kind: "error", error: String}
func advance_to(run: RunState, node_id: String, band: BattleBand,
		ctx: Dictionary) -> Dictionary:
	if not run.is_valid_next(node_id):
		return {"kind": "error", "error": "Invalid move to %s" % node_id}

	var node: Dictionary = run.graph.node(node_id)
	var kind: String = str(node.get("kind", "battle"))

	# Advance position (updates depth and visited)
	run.advance_to(node_id)

	match kind:
		"battle":
			return _resolve_battle(run, ctx, false)
		"boss":
			return _resolve_battle(run, ctx, true)
		"event", "boon", "hazard":
			var result: Dictionary = _resolve_event(kind, run, band, ctx)
			_save_run(run)
			return result
		"shop":
			_save_run(run)
			return {"kind": "shop"}
		"rest":
			var result: Dictionary = _resolve_rest(run, band)
			_save_run(run)
			return result
		_:
			_save_run(run)
			return {"kind": kind}


## Processes battle results after a match completes.
## Returns {status: "continue"/"victory"/"defeat", deaths: Array[String],
##          rewards: {gold, equipment, consumables, xp, jp}}.
func on_battle_end(run: RunState, band: BattleBand,
		result: Dictionary, ctx: Dictionary) -> Dictionary:
	var player_won: bool = result.get("player_won", false) as bool
	var downed_ids: Array[String] = []
	var raw_downed: Variant = result.get("downed_instance_ids", [])
	if raw_downed is Array:
		for id in (raw_downed as Array):
			downed_ids.append(str(id))

	var rewards: Dictionary = {}
	var deaths: Array[String] = []

	if player_won:
		rewards = _award_battle_rewards(run, band, ctx)
		# Check if this was the boss
		var node: Dictionary = run.graph.node(run.position)
		if str(node.get("kind", "")) == "boss":
			_apply_downs(run, band, downed_ids)
			_end_run(run, band, "victory")
			return {"status": "victory", "deaths": deaths, "rewards": rewards,
				"earned_unlocks": _last_earned_unlocks}

	# Apply death model
	var death_result: Dictionary = _apply_downs(run, band, downed_ids)
	deaths = death_result.get("dead_ids", []) as Array[String]

	if not player_won or (death_result.get("run_lost", false) as bool):
		_end_run(run, band, "defeat")
		return {"status": "defeat", "deaths": deaths, "rewards": rewards,
			"earned_unlocks": _last_earned_unlocks}

	_save_run(run)
	return {"status": "continue", "deaths": deaths, "rewards": rewards}


func _resolve_battle(run: RunState, ctx: Dictionary, is_boss: bool) -> Dictionary:
	var rng: RandomNumberGenerator = _make_run_rng(run)
	var providers: Dictionary = ctx.get("providers", {}) as Dictionary
	var encounter: Dictionary = EncounterGenerator.generate(
		run.depth, rng, providers, is_boss)
	# Don't save yet — save happens after battle completes
	return {"kind": "battle", "encounter": encounter, "is_boss": is_boss}


func _resolve_event(kind: String, run: RunState, band: BattleBand,
		ctx: Dictionary) -> Dictionary:
	var rng: RandomNumberGenerator = _make_run_rng(run)
	var events_data: Dictionary = ctx.get("events_data", {}) as Dictionary
	var outcome: Dictionary = EventResolver.resolve(kind, rng, band, events_data)
	return {"kind": kind, "outcome": outcome}


func _resolve_rest(run: RunState, band: BattleBand) -> Dictionary:
	var healed: Array[String] = []
	for ci in band.roster:
		if ci.downs_this_run > 0:
			ci.downs_this_run = maxi(0, ci.downs_this_run - 1)
			healed.append(ci.instance_id)
	return {"kind": "rest", "healed": healed}


func _award_battle_rewards(run: RunState, band: BattleBand,
		ctx: Dictionary) -> Dictionary:
	var providers: Dictionary = ctx.get("providers", {}) as Dictionary
	var run_cfg: Dictionary = providers.get("run_config", {}) as Dictionary

	# XP and JP
	var xp_amount: int = int(run_cfg.get("xp_per_battle", 30))
	var jp_amount: int = int(run_cfg.get("jp_per_battle", 20))
	var class_prov: Variant = providers.get("class_provider", null)

	var fielded_ids: Array = ctx.get("fielded_ids", []) as Array
	for ci in band.roster:
		if fielded_ids.is_empty() or fielded_ids.has(ci.instance_id):
			if class_prov is Callable:
				Leveling.grant_xp(ci, xp_amount, class_prov as Callable)
			else:
				ci.xp += xp_amount
			ci.gain_jp(ci.active_class, jp_amount)

	# Loot
	var node: Dictionary = run.graph.node(run.position)
	var node_kind: String = str(node.get("kind", "battle"))
	var loot_table_key: String = str(run_cfg.get("loot_table_by_kind", {}).get(node_kind, "standard_battle"))
	var loot_table_fn: Variant = providers.get("loot_table_provider", null)
	var pool_fn: Variant = providers.get("shop_pool_provider", null)
	var rolled: Dictionary = {"gold": 0, "equipment": [], "consumables": []}

	if loot_table_fn is Callable and pool_fn is Callable:
		var table: Dictionary = (loot_table_fn as Callable).call(loot_table_key)
		if not table.is_empty():
			var rng: RandomNumberGenerator = _make_run_rng(run)
			rolled = LootRoller.roll(table, run.depth, rng, pool_fn as Callable,
				band.band_level())
			LootRoller.grant_rewards(band, rolled)

	rolled["xp"] = xp_amount
	rolled["jp"] = jp_amount
	return rolled


func _apply_downs(run: RunState, band: BattleBand,
		downed_ids: Array[String]) -> Dictionary:
	return DeathModel.apply_post_battle(run, band, downed_ids)


func _end_run(run: RunState, band: BattleBand, outcome: String) -> void:
	# Evaluate meta-unlock rules and apply grants to the profile
	var unlocks_table: Dictionary = {}
	if _meta_unlocks_provider is Callable:
		unlocks_table = (_meta_unlocks_provider as Callable).call()
	_last_earned_unlocks = MetaUnlockEngine.evaluate_run_end(
		SaveManager.profile, outcome, run, unlocks_table)
	# Clear active run
	SaveManager.active_run = null
	SaveManager.save_game()


func _save_run(run: RunState) -> void:
	SaveManager.active_run = run
	SaveManager.save_game()


func _apply_boons(band: BattleBand, run: RunState,
		boons: Array[Dictionary]) -> void:
	for boon in boons:
		var effect: Dictionary = boon.get("effect", {}) as Dictionary
		if effect.has("gold"):
			band.gold += int(effect["gold"])
		if effect.has("down_limit_bonus"):
			run.down_limit += int(effect["down_limit_bonus"])


func _make_run_rng(run: RunState) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	# Combine seed with depth for per-node variance while remaining deterministic
	rng.seed = run.seed_value + run.depth * 31
	return rng
