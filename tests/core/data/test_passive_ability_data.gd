extends GutTest
## A18: Tests for AbilityData passive fields and Validator passive descriptor rules.


# --- DataFactory populates passive fields ---

func test_make_ability_populates_passive_kind() -> void:
	var d := {
		"id": "counter",
		"name": "Counter",
		"type": "passive",
		"ap": 0, "wp": 0, "range": 0, "mag_scaling": 0.0,
		"source": "class",
		"passive_kind": "reaction",
		"trigger": {"event": "on_hit", "melee_only": true},
		"modifier": {},
	}
	var ab: AbilityData = DataFactory.make_ability(d)
	assert_eq(ab.passive_kind, "reaction")
	assert_eq(str(ab.trigger.get("event", "")), "on_hit")
	assert_true(bool(ab.trigger.get("melee_only", false)))
	assert_true(ab.modifier.is_empty())


func test_make_ability_populates_support_modifier() -> void:
	var d := {
		"id": "magic_up",
		"name": "Magic Up",
		"type": "passive",
		"ap": 0, "wp": 0, "range": 0, "mag_scaling": 0.0,
		"source": "class",
		"passive_kind": "support",
		"trigger": {},
		"modifier": {"kind": "stat", "stat": "mag", "value": 2},
	}
	var ab: AbilityData = DataFactory.make_ability(d)
	assert_eq(ab.passive_kind, "support")
	assert_eq(str(ab.modifier.get("kind", "")), "stat")
	assert_eq(str(ab.modifier.get("stat", "")), "mag")
	assert_eq(int(ab.modifier.get("value", 0)), 2)


func test_make_ability_defaults_passive_kind_to_empty() -> void:
	var d := {
		"id": "basic_strike",
		"name": "Basic Strike",
		"type": "skill",
		"ap": 1, "wp": 0, "range": 1, "mag_scaling": 0.0,
		"source": "class",
		"effect": {"effect_type": "damage", "value": 3},
	}
	var ab: AbilityData = DataFactory.make_ability(d)
	assert_eq(ab.passive_kind, "")
	assert_true(ab.trigger.is_empty())
	assert_true(ab.modifier.is_empty())


# --- Validator rejects malformed passives ---

func test_validator_accepts_valid_reaction_passive() -> void:
	var d := {
		"id": "counter",
		"type": "passive",
		"passive_kind": "reaction",
		"trigger": {"event": "on_hit"},
		"modifier": {},
	}
	var errs: Array[String] = Validator.validate_ability(d)
	assert_true(errs.is_empty(), "Valid reaction passive should pass: %s" % str(errs))


func test_validator_accepts_valid_support_passive() -> void:
	var d := {
		"id": "magic_up",
		"type": "passive",
		"passive_kind": "support",
		"trigger": {},
		"modifier": {"kind": "stat", "stat": "mag", "value": 2},
	}
	var errs: Array[String] = Validator.validate_ability(d)
	assert_true(errs.is_empty(), "Valid support passive should pass: %s" % str(errs))


func test_validator_accepts_valid_movement_passive() -> void:
	var d := {
		"id": "jump_plus_1",
		"type": "passive",
		"passive_kind": "movement",
		"trigger": {},
		"modifier": {"kind": "stat", "stat": "jump", "value": 1},
	}
	var errs: Array[String] = Validator.validate_ability(d)
	assert_true(errs.is_empty(), "Valid movement passive should pass: %s" % str(errs))


func test_validator_rejects_unknown_passive_kind() -> void:
	var d := {
		"id": "weird_passive",
		"type": "passive",
		"passive_kind": "invalid_kind",
		"trigger": {},
		"modifier": {"kind": "stat"},
	}
	var errs: Array[String] = Validator.validate_ability(d)
	assert_false(errs.is_empty(), "Unknown passive_kind should fail validation")
	assert_true(errs.any(func(e: String) -> bool: return "passive_kind" in e))


func test_validator_rejects_reaction_missing_trigger_event() -> void:
	var d := {
		"id": "bad_reaction",
		"type": "passive",
		"passive_kind": "reaction",
		"trigger": {},  # missing "event"
		"modifier": {},
	}
	var errs: Array[String] = Validator.validate_ability(d)
	assert_false(errs.is_empty(), "Reaction missing trigger.event should fail")
	assert_true(errs.any(func(e: String) -> bool: return "trigger.event" in e))


func test_validator_rejects_reaction_unknown_event() -> void:
	var d := {
		"id": "bad_reaction",
		"type": "passive",
		"passive_kind": "reaction",
		"trigger": {"event": "on_explode"},  # unknown event
		"modifier": {},
	}
	var errs: Array[String] = Validator.validate_ability(d)
	assert_false(errs.is_empty(), "Unknown trigger.event should fail")
	assert_true(errs.any(func(e: String) -> bool: return "trigger.event" in e))


func test_validator_rejects_support_missing_modifier_kind() -> void:
	var d := {
		"id": "bad_support",
		"type": "passive",
		"passive_kind": "support",
		"trigger": {},
		"modifier": {},  # missing "kind"
	}
	var errs: Array[String] = Validator.validate_ability(d)
	assert_false(errs.is_empty(), "Support missing modifier.kind should fail")
	assert_true(errs.any(func(e: String) -> bool: return "modifier.kind" in e))


func test_validator_rejects_movement_missing_modifier_kind() -> void:
	var d := {
		"id": "bad_movement",
		"type": "passive",
		"passive_kind": "movement",
		"trigger": {},
		"modifier": {},  # missing "kind"
	}
	var errs: Array[String] = Validator.validate_ability(d)
	assert_false(errs.is_empty(), "Movement missing modifier.kind should fail")
	assert_true(errs.any(func(e: String) -> bool: return "modifier.kind" in e))


func test_validator_accepts_passive_without_passive_kind() -> void:
	## Passives without a passive_kind are valid (un-categorised, future content).
	var d := {
		"id": "basic_passive",
		"type": "passive",
	}
	var errs: Array[String] = Validator.validate_ability(d)
	assert_true(errs.is_empty(), "Passive without passive_kind should be valid: %s" % str(errs))
