extends GutTest
## Tests for CharacterInstance.to_dict / from_dict round-trip.


func _make_populated_instance() -> CharacterInstance:
	var ci := CharacterInstance.new()
	ci.instance_id = "ci_test_abc"
	ci.template_id = "human_fighter"
	ci.name = "Aldric the Brave"
	ci.race = "human"
	ci.level = 5
	ci.xp = 120
	ci.active_class = "soldier"
	ci.unlocked_classes = ["vagabond", "soldier"] as Array[String]
	ci.jp = {"vagabond": 10, "soldier": 45}
	ci.learned_abilities = ["first_aid", "power_strike"] as Array[String]
	ci.ability_loadout = ["power_strike"] as Array[String]
	ci.equipment = {"weapon": "sword", "armor": "medium_armor"}
	ci.growth_accumulated = {"hp": 4, "atk": 2, "def": 1}
	ci.downs_this_run = 1
	return ci


func test_round_trip_preserves_all_fields() -> void:
	var original := _make_populated_instance()
	var d := original.to_dict()
	var restored := CharacterInstance.from_dict(d)
	assert_eq(restored.instance_id, original.instance_id)
	assert_eq(restored.template_id, original.template_id)
	assert_eq(restored.name, original.name)
	assert_eq(restored.race, original.race)
	assert_eq(restored.level, original.level)
	assert_eq(restored.xp, original.xp)
	assert_eq(restored.active_class, original.active_class)
	assert_eq(restored.unlocked_classes, original.unlocked_classes)
	assert_eq(restored.jp, original.jp)
	assert_eq(restored.learned_abilities, original.learned_abilities)
	assert_eq(restored.ability_loadout, original.ability_loadout)
	assert_eq(restored.equipment, original.equipment)
	assert_eq(restored.growth_accumulated, original.growth_accumulated)
	assert_eq(restored.downs_this_run, original.downs_this_run)


func test_from_dict_defaults_on_empty() -> void:
	var ci := CharacterInstance.from_dict({})
	assert_eq(ci.instance_id, "")
	assert_eq(ci.level, 1)
	assert_eq(ci.xp, 0)
	assert_eq(ci.active_class, "vagabond")
	assert_eq(ci.unlocked_classes.size(), 1)
	assert_eq(ci.unlocked_classes[0], "vagabond")
	assert_eq(ci.jp.size(), 0)
	assert_eq(ci.learned_abilities.size(), 0)
	assert_eq(ci.ability_loadout.size(), 0)
	assert_eq(ci.equipment.size(), 0)
	assert_eq(ci.growth_accumulated.size(), 0)
	assert_eq(ci.downs_this_run, 0)


func test_to_dict_is_json_serializable() -> void:
	var original := _make_populated_instance()
	var d := original.to_dict()
	var json_str := JSON.stringify(d)
	assert_false(json_str.is_empty())
	var parsed: Variant = JSON.parse_string(json_str)
	assert_true(parsed is Dictionary)
	var restored := CharacterInstance.from_dict(parsed as Dictionary)
	assert_eq(restored.instance_id, original.instance_id)
	assert_eq(restored.level, original.level)
	assert_eq(restored.jp, original.jp)
	assert_eq(restored.equipment, original.equipment)
	assert_eq(restored.growth_accumulated, original.growth_accumulated)


func test_to_dict_does_not_share_references() -> void:
	var original := _make_populated_instance()
	var d := original.to_dict()
	# Mutate the dict — should not affect the original instance
	(d["unlocked_classes"] as Array).append("thief")
	(d["jp"] as Dictionary)["thief"] = 99
	assert_eq(original.unlocked_classes.size(), 2)
	assert_false(original.jp.has("thief"))
