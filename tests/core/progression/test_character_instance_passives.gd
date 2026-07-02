extends GutTest
## A18: Tests for CharacterInstance passive slot learn/equip/unequip/serialisation.


func _make_ability(id: String, passive_kind: String) -> AbilityData:
	var ab := AbilityData.new()
	ab.id = id
	ab.type = "passive"
	ab.passive_kind = passive_kind
	ab.trigger = {}
	ab.modifier = {}
	return ab


func _ability_provider(id: String) -> AbilityData:
	match id:
		"counter":
			return _make_ability("counter", "reaction")
		"magic_up":
			return _make_ability("magic_up", "support")
		"move_plus_1":
			return _make_ability("move_plus_1", "movement")
		"attack_up":
			return _make_ability("attack_up", "support")
		"some_active":
			var ab := AbilityData.new()
			ab.id = "some_active"
			ab.type = "skill"
			ab.passive_kind = ""
			return ab
	return null


func _make_ci() -> CharacterInstance:
	var ci := CharacterInstance.new()
	ci.instance_id = "test_id"
	ci.race = "human"
	ci.name = "Tester"
	ci.active_class = "vagabond"
	ci.class_levels = {"vagabond": 1}
	return ci


# --- learn and equip routing ---

func test_equip_reaction_slot() -> void:
	var ci := _make_ci()
	ci.learned_abilities.append("counter")
	var ok: bool = ci.equip_passive("counter", _ability_provider)
	assert_true(ok)
	assert_eq(ci.reaction_slot, "counter")
	assert_eq(ci.support_slot, "")
	assert_eq(ci.movement_slot, "")


func test_equip_support_slot() -> void:
	var ci := _make_ci()
	ci.learned_abilities.append("magic_up")
	var ok: bool = ci.equip_passive("magic_up", _ability_provider)
	assert_true(ok)
	assert_eq(ci.support_slot, "magic_up")


func test_equip_movement_slot() -> void:
	var ci := _make_ci()
	ci.learned_abilities.append("move_plus_1")
	var ok: bool = ci.equip_passive("move_plus_1", _ability_provider)
	assert_true(ok)
	assert_eq(ci.movement_slot, "move_plus_1")


func test_equip_wrong_kind_rejected() -> void:
	## equip_passive routes by passive_kind; trying to put a skill ability into a slot is rejected.
	var ci := _make_ci()
	ci.learned_abilities.append("some_active")
	var ok: bool = ci.equip_passive("some_active", _ability_provider)
	assert_false(ok)
	assert_eq(ci.reaction_slot, "")
	assert_eq(ci.support_slot, "")
	assert_eq(ci.movement_slot, "")


func test_equip_not_learned_rejected() -> void:
	var ci := _make_ci()
	# counter is NOT in learned_abilities
	var ok: bool = ci.equip_passive("counter", _ability_provider)
	assert_false(ok)
	assert_eq(ci.reaction_slot, "")


func test_unequip_reaction() -> void:
	var ci := _make_ci()
	ci.learned_abilities.append("counter")
	ci.equip_passive("counter", _ability_provider)
	ci.unequip_passive("reaction")
	assert_eq(ci.reaction_slot, "")


func test_equip_replaces_existing_slot() -> void:
	var ci := _make_ci()
	ci.learned_abilities.append("magic_up")
	ci.learned_abilities.append("attack_up")
	ci.equip_passive("magic_up", _ability_provider)
	assert_eq(ci.support_slot, "magic_up")
	ci.equip_passive("attack_up", _ability_provider)
	assert_eq(ci.support_slot, "attack_up")


# --- to_dict / from_dict round-trip ---

func test_to_dict_includes_passive_slots() -> void:
	var ci := _make_ci()
	ci.learned_abilities.append("counter")
	ci.learned_abilities.append("magic_up")
	ci.learned_abilities.append("move_plus_1")
	ci.equip_passive("counter", _ability_provider)
	ci.equip_passive("magic_up", _ability_provider)
	ci.equip_passive("move_plus_1", _ability_provider)

	var d: Dictionary = ci.to_dict()
	assert_eq(str(d["reaction_slot"]), "counter")
	assert_eq(str(d["support_slot"]), "magic_up")
	assert_eq(str(d["movement_slot"]), "move_plus_1")


func test_from_dict_restores_passive_slots() -> void:
	var d: Dictionary = {
		"instance_id": "ci_test",
		"template_id": "tmpl",
		"name": "Hero",
		"race": "human",
		"active_class": "vagabond",
		"class_levels": {"vagabond": 1},
		"xp": 0,
		"unlocked_classes": ["vagabond"],
		"jp": {},
		"learned_abilities": ["counter", "magic_up", "move_plus_1"],
		"ability_loadout": [],
		"equipment": {},
		"growth_accumulated": {},
		"downs_this_run": 0,
		"reaction_slot": "counter",
		"support_slot": "magic_up",
		"movement_slot": "move_plus_1",
	}
	var ci: CharacterInstance = CharacterInstance.from_dict(d)
	assert_eq(ci.reaction_slot, "counter")
	assert_eq(ci.support_slot, "magic_up")
	assert_eq(ci.movement_slot, "move_plus_1")


func test_from_dict_missing_keys_defaults_to_empty() -> void:
	## Migration safety: old saves without passive slots should default to "".
	var d: Dictionary = {
		"instance_id": "ci_old",
		"template_id": "tmpl",
		"name": "Old Hero",
		"race": "human",
		"active_class": "vagabond",
		"class_levels": {"vagabond": 1},
		"xp": 0,
		"unlocked_classes": ["vagabond"],
		"jp": {},
		"learned_abilities": [],
		"ability_loadout": [],
		"equipment": {},
		"growth_accumulated": {},
		"downs_this_run": 0,
		# no reaction_slot / support_slot / movement_slot keys
	}
	var ci: CharacterInstance = CharacterInstance.from_dict(d)
	assert_eq(ci.reaction_slot, "")
	assert_eq(ci.support_slot, "")
	assert_eq(ci.movement_slot, "")


# --- to_character_data copies passive slots ---

func test_to_character_data_copies_passive_slots() -> void:
	var ci := _make_ci()
	ci.learned_abilities.append("counter")
	ci.learned_abilities.append("magic_up")
	ci.learned_abilities.append("move_plus_1")
	ci.equip_passive("counter", _ability_provider)
	ci.equip_passive("magic_up", _ability_provider)
	ci.equip_passive("move_plus_1", _ability_provider)

	var sb := StatBlock.new()
	sb.set_base("hp", 10)
	sb.set_base("spd", 3)
	sb.set_base("wp", 4)
	var cd: CharacterData = ci.to_character_data(sb)

	assert_eq(cd.reaction_passive, "counter")
	assert_eq(cd.support_passive, "magic_up")
	assert_eq(cd.movement_passive, "move_plus_1")
