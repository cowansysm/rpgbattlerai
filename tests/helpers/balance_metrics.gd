extends RefCounted
## Balance-metrics harness for the content redesign (Phase 6).
##
## Extends the Phase-3 AI-vs-AI sim (tests/helpers/battle_sim.gd) into an
## aggregating sweep: run many seeded matches and collect distribution metrics
## (rounds-to-resolution, per-side win rate, AI ability-usage rate, max single-hit
## damage, one-shot frequency, capped/stalemate rate). Also builds a "progressed"
## player party from the 20 playable-race templates (loadouts drawn from each
## unit's recommended-path class jp_costs) and runs it against level-matched
## authored encounters.
##
## Pure core logic, no scene tree. Preloaded (NO class_name) so the headless
## global-class cache does not need to see it. Deterministic given seeds.
##
## Entry points (see docs/content-redesign-phase6-balance-report.md for repro):
##   var bm := preload("res://tests/helpers/balance_metrics.gd").new()
##   bm.sweep_monster_vs_monster(base_seed, n)     -> Dictionary (aggregate)
##   bm.sweep_player_vs_encounters(base_seed, band) -> Dictionary (aggregate)

const BattleSim = preload("res://tests/helpers/battle_sim.gd")

# The 20 playable-race templates (the "roster"), grouped by recommended path.
const PLAYABLE_TEMPLATES: Array[String] = [
	"human_fighter", "human_archer", "human_rogue", "human_bard",
	"dwarf_barbarian", "elf_black_mage", "elf_red_mage", "halfling_white_mage",
	"dwarf_guardian", "dwarf_cleric", "elf_ranger", "elf_enchanter",
	"halfling_scout", "halfling_herbalist", "human_knight", "human_mage",
	"human_healer", "elf_assassin", "dwarf_berserker", "halfling_trickster",
]

# recommended_path -> tier-1 class to progress into (vagabond -> this at L3+).
const PATH_TO_CLASS: Dictionary = {
	"physical": "squire",
	"magical": "apprentice",
	"control": "cutpurse",
	"support": "page",
}


# ---------------------------------------------------------------------------
# Progressed-party construction
# ---------------------------------------------------------------------------

## Build a "progressed" BattleUnit from a playable template: unlock and level the
## recommended-path tier-1 class, grant ample JP, learn a seeded handful of that
## class's ACTIVE abilities (skipping passives), set a loadout, then bridge to a
## BattleUnit. Falls back to a plain template unit if progression is unavailable.
func progressed_unit(template_id: String, target_level: int, rng: RandomNumberGenerator) -> BattleUnit:
	var template: CharacterData = GameData.get_character(template_id)
	if template == null:
		return null
	var name_gen := func(_r: String) -> String: return template_id
	var ci: CharacterInstance = CharacterInstance.generate(template, name_gen)

	# Level the base vagabond a few times so prerequisites (vagabond L3) are met.
	var vagabond_levels: int = clampi(3, 1, target_level)
	for _i in range(vagabond_levels - 1):
		ci.increment_active_class_level(GameData.get_job_class)

	# Unlock + progress the recommended-path tier-1 class.
	var path: String = str(template.recommended_path)
	var target_class: String = str(PATH_TO_CLASS.get(path, "squire"))
	if ci.unlock_class(target_class, GameData.get_job_class):
		ci.set_active_class(target_class)
		var advanced_levels: int = maxi(1, target_level - vagabond_levels)
		for _i in range(advanced_levels):
			ci.increment_active_class_level(GameData.get_job_class)

	# Grant generous JP and learn a seeded selection of ACTIVE abilities.
	_learn_seeded_abilities(ci, target_class, rng)
	_learn_seeded_abilities(ci, "vagabond", rng)

	var u: BattleUnit = BattleUnit.from_instance(
		ci, GameData.get_race, GameData.get_job_class, GameData.get_ability)
	if u != null:
		u.team = "playerA"
	return u


## Grant JP to a class and learn up to `max_learn` active abilities from its
## jp_costs (seeded pick, passives excluded), then push them onto the loadout.
func _learn_seeded_abilities(ci: CharacterInstance, class_id: String,
		rng: RandomNumberGenerator, max_learn: int = 3) -> void:
	var cls: ClassData = GameData.get_job_class(class_id)
	if cls == null:
		return
	if not ci.unlocked_classes.has(class_id):
		return
	ci.gain_jp(class_id, 10000)  # ample; costs are ~20-130
	var candidates: Array[String] = []
	for aid in cls.jp_costs.keys():
		var ab: AbilityData = GameData.get_ability(aid)
		if ab != null and ab.is_active():
			candidates.append(str(aid))
	candidates.sort()  # stable order before seeded shuffle
	_seeded_shuffle(candidates, rng)
	var learned_now: Array[String] = []
	for aid in candidates:
		if learned_now.size() >= max_learn:
			break
		if ci.learn_ability(aid, class_id, GameData.get_job_class):
			learned_now.append(aid)
	# Merge into loadout (cap 6), keeping any already-set abilities.
	var load: Array[String] = []
	for aid in ci.ability_loadout:
		load.append(str(aid))
	for aid in learned_now:
		if not load.has(aid) and load.size() < 6:
			load.append(aid)
	ci.set_loadout(load)


func _seeded_shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func build_player_party(size: int, target_level: int, rng: RandomNumberGenerator) -> Array[BattleUnit]:
	var pool: Array[String] = PLAYABLE_TEMPLATES.duplicate()
	_seeded_shuffle(pool, rng)
	var party: Array[BattleUnit] = []
	for i in range(mini(size, pool.size())):
		var u: BattleUnit = progressed_unit(pool[i], target_level, rng)
		if u != null:
			party.append(u)
	return party


# ---------------------------------------------------------------------------
# Enemy / encounter construction
# ---------------------------------------------------------------------------

## All authored encounters at a given min_band_level, as parsed dicts.
static func encounters_at_band(band: int) -> Array:
	var raw: Variant = _load_json("res://data/encounters.json")
	var out: Array = []
	if raw is Array:
		for e in raw:
			if e is Dictionary and int((e as Dictionary).get("min_band_level", -1)) == band:
				out.append(e)
	return out


## Build the enemy squad for an authored encounter (template units, optionally
## scaled to the encounter's effective level via LevelScaler).
func enemy_squad_from_encounter(enc: Dictionary, scale_level: int = 0) -> Array[BattleUnit]:
	var squad: Array[BattleUnit] = []
	for entry in enc.get("enemies", []):
		var tid: String = str((entry as Dictionary).get("character", ""))
		var count: int = int((entry as Dictionary).get("count", 1))
		for _i in range(count):
			var u: BattleUnit = _enemy_unit(tid, scale_level)
			if u != null:
				u.team = "playerB"
				squad.append(u)
	return squad


## Build a monster/NPC BattleUnit from a template. If scale_level > 0, project the
## authored base stats to that level via the template's class growth (LevelScaler).
func _enemy_unit(template_id: String, scale_level: int) -> BattleUnit:
	var c: CharacterData = GameData.get_character(template_id)
	var fs: StatBlock = GameData.get_final_stats(template_id)
	if c == null or fs == null:
		return null
	if scale_level > 1 and not c.classes.is_empty():
		var cls: ClassData = GameData.get_job_class(c.classes[0])
		if cls != null and not cls.growth.is_empty():
			var base: Dictionary = {}
			for k in StatKey.all_strings():
				base[k] = fs.effective(k)
			var scaled: Dictionary = LevelScaler.scale(base, cls.growth, scale_level)
			var sb := StatBlock.new()
			for k in scaled.keys():
				sb.set_base(k, int(scaled[k]))
			return BattleUnit.from_character(c, sb, GameData.get_ability)
	return BattleUnit.from_character(c, fs, GameData.get_ability)


# ---------------------------------------------------------------------------
# Instrumented match run (adds damage metrics on top of BattleSim.run)
# ---------------------------------------------------------------------------

## Run a single instrumented match. Wraps BattleSim.run but captures per-hit
## damage by snapshotting HP before/after each activation is impractical in the
## step loop, so we re-derive one-shot / max-hit from the resolver outcomes by
## re-running with an outcome tap. Here we keep it simple and robust: use
## BattleSim.run for the primary metrics and compute damage metrics from a
## lightweight parallel pass on the same seed.
func run_match(party_a: Array[BattleUnit], party_b: Array[BattleUnit],
		match_seed: int, max_rounds: int = 40) -> Dictionary:
	# Record full-HP per unit for one-shot detection.
	var full_hp: Dictionary = {}
	for u in party_a + party_b:
		full_hp[u] = u.stats.effective(StatKey.to_string_key(StatKey.Key.HP))
	var sim := BattleSim.new()
	var r: Dictionary = _run_instrumented(sim, party_a, party_b, match_seed, max_rounds, full_hp)
	return r


## Copy of BattleSim.run's loop with damage instrumentation via HP deltas per
## resolved action. Reuses BattleSim helpers for setup so we don't fork behavior.
func _run_instrumented(sim: RefCounted, party_a: Array[BattleUnit], party_b: Array[BattleUnit],
		match_seed: int, max_rounds: int, full_hp: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed
	var map: MapData = BattleSim.flat_map(7)
	var state: MatchState = sim._make_provider_state(party_a, party_b, map)
	state.ai_teams = ["playerA", "playerB"]
	Deployment.auto_deploy(state, map.deployment_zones)

	var res := {
		"winner": "", "capped": false, "rounds": 0, "activations": 0,
		"ability_ok": 0, "attack_ok": 0, "move_ok": 0,
		"executed_abilities": {}, "passive_executed": 0, "errors": [],
		"max_hit": 0, "one_shots": 0,
	}
	var all_units: Array = party_a + party_b
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
			# HP snapshot for damage delta on this activation.
			var before: Dictionary = {}
			for u in all_units:
				before[u] = u.current_hp
			var plan := AIPlanner.plan(state, unit, rng, diff)
			sim._execute_plan(state, unit, plan, res)
			# Damage metrics: largest single-target drop this activation.
			for u in all_units:
				if u == unit:
					continue
				var dealt: int = int(before[u]) - u.current_hp
				if dealt > int(res["max_hit"]):
					res["max_hit"] = dealt
				if dealt > 0 and int(before[u]) >= int(full_hp.get(u, 999999)) and u.current_hp <= 0:
					res["one_shots"] += 1
		RoundManager.end_activation(state)
	res["rounds"] = state.round_number
	return res


# ---------------------------------------------------------------------------
# Aggregation
# ---------------------------------------------------------------------------

static func _new_agg() -> Dictionary:
	return {
		"n": 0, "rounds": [] as Array, "a_wins": 0, "b_wins": 0, "capped": 0,
		"errors": 0, "total_activations": 0, "total_ability_ok": 0,
		"total_attack_ok": 0, "passive_executed": 0, "max_hit": 0, "one_shots": 0,
		"turn1_wipes": 0, "error_samples": [] as Array,
	}


func _fold(agg: Dictionary, r: Dictionary) -> void:
	agg["n"] += 1
	(agg["rounds"] as Array).append(int(r["rounds"]))
	if str(r["winner"]) == "playerA":
		agg["a_wins"] += 1
	elif str(r["winner"]) == "playerB":
		agg["b_wins"] += 1
	if bool(r["capped"]):
		agg["capped"] += 1
	var errs: Array = r["errors"] as Array
	if not errs.is_empty():
		agg["errors"] += errs.size()
		if (agg["error_samples"] as Array).size() < 5:
			(agg["error_samples"] as Array).append_array(errs)
	agg["total_activations"] += int(r["activations"])
	agg["total_ability_ok"] += int(r["ability_ok"])
	agg["total_attack_ok"] += int(r["attack_ok"])
	agg["passive_executed"] += int(r["passive_executed"])
	agg["max_hit"] = maxi(int(agg["max_hit"]), int(r.get("max_hit", 0)))
	agg["one_shots"] += int(r.get("one_shots", 0))
	# A "turn-1 wipe" heuristic: resolved in round 1.
	if not bool(r["capped"]) and str(r["winner"]) != "" and int(r["rounds"]) <= 1:
		agg["turn1_wipes"] += 1


static func summarize(agg: Dictionary) -> Dictionary:
	var rounds: Array = (agg["rounds"] as Array).duplicate()
	rounds.sort()
	var n: int = agg["n"]
	var rmin: int = rounds[0] if n > 0 else 0
	var rmax: int = rounds[-1] if n > 0 else 0
	var rmed: int = rounds[n / 2] if n > 0 else 0
	var actions: int = int(agg["total_ability_ok"]) + int(agg["total_attack_ok"])
	var ability_rate: float = 0.0
	if actions > 0:
		ability_rate = float(agg["total_ability_ok"]) / float(actions)
	return {
		"matches": n,
		"rounds_min": rmin, "rounds_median": rmed, "rounds_max": rmax,
		"a_win_rate": (float(agg["a_wins"]) / n) if n > 0 else 0.0,
		"b_win_rate": (float(agg["b_wins"]) / n) if n > 0 else 0.0,
		"capped_rate": (float(agg["capped"]) / n) if n > 0 else 0.0,
		"turn1_wipe_rate": (float(agg["turn1_wipes"]) / n) if n > 0 else 0.0,
		"ai_ability_usage_rate": ability_rate,
		"total_errors": agg["errors"],
		"error_samples": agg["error_samples"],
		"passive_executed": agg["passive_executed"],
		"max_single_hit": agg["max_hit"],
		"one_shots": agg["one_shots"],
	}


# ---------------------------------------------------------------------------
# Sweeps
# ---------------------------------------------------------------------------

## Monster-vs-monster reference sweep: pit authored encounter squads from a band
## against each other, many seeds. Returns a summarized aggregate dict.
func sweep_monster_vs_monster(base_seed: int, bands: Array, matches_per_pair: int = 4,
		max_rounds: int = 40) -> Dictionary:
	var agg: Dictionary = _new_agg()
	var seed_ctr: int = base_seed
	for band in bands:
		var encs: Array = encounters_at_band(int(band))
		if encs.size() < 2:
			continue
		# Pair consecutive encounters (a vs b) within the band.
		for i in range(0, encs.size() - 1, 2):
			for s in range(matches_per_pair):
				seed_ctr += 1
				var pa: Array[BattleUnit] = enemy_squad_from_encounter(encs[i])
				var pb: Array[BattleUnit] = enemy_squad_from_encounter(encs[i + 1])
				for u in pa:
					u.team = "playerA"
				if pa.is_empty() or pb.is_empty():
					continue
				var r: Dictionary = run_match(pa, pb, seed_ctr, max_rounds)
				_fold(agg, r)
	return summarize(agg)


## Player-party vs level-matched authored encounters. For each band, build a
## progressed party (level ~ band+2) and run it against every encounter in that
## band across several seeds. Returns {band -> summary}.
func sweep_player_vs_encounters(base_seed: int, bands: Array, party_size: int = 4,
		matches_per_enc: int = 3, max_rounds: int = 40) -> Dictionary:
	var out: Dictionary = {}
	var seed_ctr: int = base_seed
	for band in bands:
		var band_i: int = int(band)
		var encs: Array = encounters_at_band(band_i)
		var agg: Dictionary = _new_agg()
		for enc in encs:
			for s in range(matches_per_enc):
				seed_ctr += 1
				var party_rng := RandomNumberGenerator.new()
				party_rng.seed = seed_ctr * 7919
				var pa: Array[BattleUnit] = build_player_party(party_size, band_i + 2, party_rng)
				var pb: Array[BattleUnit] = enemy_squad_from_encounter(enc as Dictionary)
				if pa.is_empty() or pb.is_empty():
					continue
				var r: Dictionary = run_match(pa, pb, seed_ctr, max_rounds)
				_fold(agg, r)
		out[band_i] = summarize(agg)
	return out


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

static func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	return parsed
