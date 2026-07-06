extends RefCounted
## Headless AI-vs-AI battle simulation driver for content validation (Phase 3 of
## the content redesign — see docs/content-redesign-phase3-plan.md).
##
## Pure core logic, no scene tree: MatchSetup + Deployment + RoundManager +
## AIPlanner + TurnActions, looped to victory or a round cap. Deterministic given
## a seed. Uses the GameData autoload (single shared content load) read-only.
##
## Preloaded by tests (no class_name) to avoid the headless global-class-cache
## dependency.


static func stub_terrain(_id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = _id
	p.move_cost = 1
	return p


## Flat grass map of the given radius with deployment columns on opposite sides.
static func flat_map(radius: int) -> MapData:
	var map := MapData.new()
	map.id = "sim_flat"
	var tiles: Array[TileRecord] = []
	var za: Array[String] = []
	var zb: Array[String] = []
	for c in Hex.hexes_in_range(Vector2i(0, 0), radius):
		tiles.append(TileRecord.new(c.x, c.y, 0, "grass"))
		if c.x <= -(radius - 1):
			za.append("%d,%d" % [c.x, c.y])
		elif c.x >= (radius - 1):
			zb.append("%d,%d" % [c.x, c.y])
	map.tiles = tiles
	map.deployment_zones = {"playerA": za, "playerB": zb}
	return map


## Build a BattleUnit from an authored template id (read-only shared data;
## from_character duplicates the StatBlock, so combat never dirties the template).
static func unit_from_template(template_id: String) -> BattleUnit:
	var c: CharacterData = GameData.get_character(template_id)
	var fs: StatBlock = GameData.get_final_stats(template_id)
	if c == null or fs == null:
		return null
	return BattleUnit.from_character(c, fs, GameData.get_ability)


## Build a synthetic caster with an explicit loadout (character.abilities), for
## controlled ability-cast / passive-hygiene checks. Does not touch shared data.
static func loadout_unit(id: String, abilities: Array) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.race = "human"
	c.classes = [] as Array[String]
	c.equipment = [] as Array[String]
	var t: Array[String] = []
	for a in abilities:
		t.append(str(a))
	c.abilities = t
	var sb := StatBlock.new()
	sb.set_base("hp", 30)
	sb.set_base("spd", 5)
	sb.set_base("atk", 8)
	sb.set_base("rng", 1)
	sb.set_base("def", 3)
	sb.set_base("mag", 8)
	sb.set_base("res", 3)
	sb.set_base("wp", 99)
	sb.set_base("jump", 2)
	return BattleUnit.from_character(c, sb)


# Keeps AbilityResolver instances alive for the lifetime of this sim: a Callable
# to a RefCounted method does not reliably keep the object from being freed, which
# would invalidate state.ability_provider mid-match (the real BattleController holds
# its resolver as a member for the same reason).
var _keepalive: Array = []


func _make_provider_state(party_a: Array[BattleUnit], party_b: Array[BattleUnit],
		map: MapData) -> MatchState:
	var state := MatchSetup.create(party_a, party_b, map, stub_terrain)
	var resolver := AbilityResolver.new(GameData.get_ability, GameData.get_job_class, GameData.get_item)
	_keepalive.append(resolver)
	state.ability_provider = resolver.resolve
	state.item_provider = GameData.get_item
	return state


## Minimal two-unit state with the caster adjacent to a target, ready for a single
## ability cast. current_unit is the caster with ample AP/WP.
func duel_state(caster: BattleUnit, target: BattleUnit) -> MatchState:
	var pa: Array[BattleUnit] = [caster]
	var pb: Array[BattleUnit] = [target]
	var state := _make_provider_state(pa, pb, flat_map(4))
	caster.position = Vector2i(0, 0)
	target.position = Vector2i(1, 0)
	state.occupancy[caster.position] = caster
	state.occupancy[target.position] = target
	caster.ap_remaining = 5
	caster.current_wp = 99
	state.current_unit = caster
	state.phase = MatchState.Phase.UNIT_TURN
	return state


## Run an AI-vs-AI match to a winner or a round cap. Returns a metrics dict.
func run(party_a: Array[BattleUnit], party_b: Array[BattleUnit],
		match_seed: int, max_rounds: int = 40) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed
	var map := flat_map(7)
	var state := _make_provider_state(party_a, party_b, map)
	state.ai_teams = ["playerA", "playerB"]
	Deployment.auto_deploy(state, map.deployment_zones)

	var res := {
		"winner": "", "capped": false, "rounds": 0, "activations": 0,
		"ability_ok": 0, "attack_ok": 0, "move_ok": 0,
		"executed_abilities": {}, "passive_executed": 0, "errors": [],
	}
	var diff: Dictionary = {}
	var guard := 0
	while true:
		guard += 1
		if guard > 200000:
			res["errors"].append("guard tripped (possible infinite loop)")
			break
		var w := state.check_winner()
		if w != "":
			res["winner"] = w
			break
		if state.round_number > max_rounds:
			res["capped"] = true
			break
		var team := RoundManager.current_team(state)
		if team.is_empty():
			RoundManager.start_round(state)
			continue
		var avail := state.activatable_units(team)
		if avail.is_empty():
			RoundManager.end_activation(state)
			continue
		var unit: BattleUnit = avail[0]
		var err := RoundManager.activate_unit(state, unit)
		if err != "":
			res["errors"].append("activate: " + err)
			RoundManager.end_activation(state)
			continue
		res["activations"] += 1
		if not unit.is_downed:
			var plan := AIPlanner.plan(state, unit, rng, diff)
			_execute_plan(state, unit, plan, res)
		RoundManager.end_activation(state)
	res["rounds"] = state.round_number
	return res


func _execute_plan(state: MatchState, _unit: BattleUnit, plan: AIPlan, res: Dictionary) -> void:
	for step in plan.steps:
		var kind := str(step.get("kind", ""))
		var result: Dictionary = {}
		match kind:
			"move":
				result = TurnActions.execute_move(state, step["target_pos"])
				if not result.has("error"):
					res["move_ok"] += 1
			"attack":
				result = TurnActions.execute_attack(state, step["target_pos"])
				if not result.has("error"):
					res["attack_ok"] += 1
			"ability":
				var aid := str(step.get("ability_id", ""))
				result = TurnActions.execute_ability(state, aid, step["target_pos"])
				if not result.has("error"):
					res["ability_ok"] += 1
					res["executed_abilities"][aid] = int(res["executed_abilities"].get(aid, 0)) + 1
					var ab: AbilityData = GameData.get_ability(aid)
					if ab != null and ab.passive_kind != "":
						res["passive_executed"] += 1
			"defend":
				result = TurnActions.execute_defend(state)
			_:
				result = TurnActions.execute_wait(state)
		# AIController aborts a plan on a hard step failure (except wait); mirror that.
		if result.has("error") and kind != "wait":
			break
