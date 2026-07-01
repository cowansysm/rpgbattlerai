extends GutTest

# --- Helpers ---

func _seeded(s: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	return rng


func _make_instance(id: String, downs: int = 0) -> CharacterInstance:
	var ci := CharacterInstance.new()
	ci.instance_id = id
	ci.template_id = "tmpl_human"
	ci.name = "Hero " + id
	ci.race = "human"
	ci.class_levels = {"vagabond": 3}
	ci.active_class = "vagabond"
	ci.unlocked_classes = ["vagabond"] as Array[String]
	ci.downs_this_run = downs
	ci.xp = 0
	return ci


func _make_band(instances: Array[CharacterInstance], gold: int = 100) -> BattleBand:
	var band := BattleBand.create("Test Band")
	band.gold = gold
	for ci in instances:
		band.add_instance(ci)
	return band


func _sample_events_data() -> Dictionary:
	return {
		"events": [
			{
				"id": "test_event",
				"kind": "event",
				"text": "A test event.",
				"choices": [
					{"label": "Choice A", "effects": [{"type": "gold", "value": -10}]},
					{"label": "Choice B", "effects": [{"type": "xp", "value": 5}]},
				]
			}
		],
		"boons": [
			{
				"id": "test_boon",
				"kind": "boon",
				"text": "A test boon.",
				"effects": [{"type": "gold", "value": 50}]
			}
		],
		"hazards": [
			{
				"id": "test_hazard",
				"kind": "hazard",
				"text": "A test hazard.",
				"effects": [{"type": "gold", "value": -30}]
			}
		],
	}


# --- Tests ---

func test_resolve_boon_grants_gold() -> void:
	var band: BattleBand = _make_band([_make_instance("ci_1")], 100)
	var result: Dictionary = EventResolver.resolve("boon", _seeded(1), band, _sample_events_data())
	assert_eq(band.gold, 150)
	assert_false((result["effects_applied"] as Array).is_empty())


func test_resolve_hazard_deducts_gold() -> void:
	var band: BattleBand = _make_band([_make_instance("ci_1")], 100)
	var result: Dictionary = EventResolver.resolve("hazard", _seeded(1), band, _sample_events_data())
	assert_eq(band.gold, 70)


func test_gold_floor_at_zero() -> void:
	var band: BattleBand = _make_band([_make_instance("ci_1")], 10)
	EventResolver.resolve("hazard", _seeded(1), band, _sample_events_data())
	assert_eq(band.gold, 0)  # -30 on 10 gold = 0, not -20


func test_resolve_returns_event_and_applied() -> void:
	var band: BattleBand = _make_band([_make_instance("ci_1")])
	var result: Dictionary = EventResolver.resolve("boon", _seeded(1), band, _sample_events_data())
	assert_true(result.has("event"))
	assert_true(result.has("effects_applied"))
	assert_false((result["event"] as Dictionary).is_empty())


func test_empty_pool_returns_empty() -> void:
	var band: BattleBand = _make_band([_make_instance("ci_1")])
	var result: Dictionary = EventResolver.resolve("boon", _seeded(1), band, {"boons": []})
	assert_true((result["event"] as Dictionary).is_empty())
	assert_true((result["effects_applied"] as Array).is_empty())


func test_missing_pool_returns_empty() -> void:
	var band: BattleBand = _make_band([_make_instance("ci_1")])
	var result: Dictionary = EventResolver.resolve("boon", _seeded(1), band, {})
	assert_true((result["event"] as Dictionary).is_empty())


func test_determinism() -> void:
	var band1: BattleBand = _make_band([_make_instance("ci_1")], 100)
	var band2: BattleBand = _make_band([_make_instance("ci_1")], 100)
	var data: Dictionary = _sample_events_data()
	EventResolver.resolve("boon", _seeded(42), band1, data)
	EventResolver.resolve("boon", _seeded(42), band2, data)
	assert_eq(band1.gold, band2.gold)


func test_heal_all_reduces_downs() -> void:
	var ci: CharacterInstance = _make_instance("ci_1", 2)
	var band: BattleBand = _make_band([ci])
	var data: Dictionary = {
		"boons": [{"id": "heal", "kind": "boon", "text": "Heal",
			"effects": [{"type": "heal_all", "value": 1}]}]
	}
	EventResolver.resolve("boon", _seeded(1), band, data)
	assert_eq(ci.downs_this_run, 1)  # reduced from 2 to 1


func test_damage_all_increments_downs() -> void:
	var ci1: CharacterInstance = _make_instance("ci_1", 0)
	var ci2: CharacterInstance = _make_instance("ci_2", 1)
	var band: BattleBand = _make_band([ci1, ci2])
	var data: Dictionary = {
		"hazards": [{"id": "dmg", "kind": "hazard", "text": "Damage",
			"effects": [{"type": "damage_all", "value": 1}]}]
	}
	EventResolver.resolve("hazard", _seeded(1), band, data)
	assert_eq(ci1.downs_this_run, 1)
	assert_eq(ci2.downs_this_run, 2)


func test_item_effect_adds_consumable() -> void:
	var band: BattleBand = _make_band([_make_instance("ci_1")])
	var data: Dictionary = {
		"boons": [{"id": "gift", "kind": "boon", "text": "Gift",
			"effects": [{"type": "item", "item_id": "potion", "qty": 2}]}]
	}
	EventResolver.resolve("boon", _seeded(1), band, data)
	assert_eq(band.consumable_qty("potion"), 2)


func test_xp_effect_adds_xp() -> void:
	var ci: CharacterInstance = _make_instance("ci_1")
	var band: BattleBand = _make_band([ci])
	var data: Dictionary = {
		"boons": [{"id": "xp", "kind": "boon", "text": "XP",
			"effects": [{"type": "xp", "value": 15}]}]
	}
	EventResolver.resolve("boon", _seeded(1), band, data)
	assert_eq(ci.xp, 15)


func test_resolve_choice() -> void:
	var band: BattleBand = _make_band([_make_instance("ci_1")], 100)
	var event: Dictionary = (_sample_events_data()["events"] as Array)[0]
	# Choice B grants 5 XP
	var applied: Array[String] = EventResolver.resolve_choice(event, 1, band, _seeded(1))
	assert_false(applied.is_empty())
	assert_eq(band.roster[0].xp, 5)
