extends GutTest
## Integration test for Phase A5: full pipeline from band creation
## through serialization to battle unit construction.


var _name_gen: NameGenerator


func before_all() -> void:
	_name_gen = NameGenerator.new()
	_name_gen.load_tables()


func _gen_name(race: String) -> String:
	return _name_gen.generate_name(race)


func _class_provider(id: String) -> ClassData:
	return GameData.get_job_class(id)


func _race_provider(id: String) -> RaceData:
	return GameData.get_race(id)


func _item_provider(id: String) -> ItemData:
	return GameData.get_item(id)


func test_create_band_recruit_serialize_deserialize() -> void:
	# Create a band
	var band := BattleBand.create("Integration Band")
	band.gold = 500
	# Add starting inventory
	band.add_to_inventory("sword")
	band.add_to_inventory("light_armor")

	# Recruit from templates
	var templates: Array = GameData.all_characters()
	assert_true(templates.size() > 0, "Need at least one character template")

	var template: CharacterData = templates[0] as CharacterData
	var result := Recruiter.recruit(band, template, _gen_name)
	assert_eq(result["error"], "")
	var ci: CharacterInstance = result["instance"]
	assert_not_null(ci)
	assert_eq(band.roster_size(), 1)
	assert_eq(band.gold, 450)  # 500 - 50 recruit cost

	# Serialize to dict and back
	var band_dict := band.to_dict()
	var json_str := JSON.stringify(band_dict)
	var parsed: Variant = JSON.parse_string(json_str)
	assert_true(parsed is Dictionary)
	var restored := BattleBand.from_dict(parsed as Dictionary)

	assert_eq(restored.band_id, band.band_id)
	assert_eq(restored.name, "Integration Band")
	assert_eq(restored.gold, 450)
	assert_eq(restored.roster_size(), 1)
	assert_eq(restored.roster[0].instance_id, ci.instance_id)
	assert_eq(restored.roster[0].race, ci.race)


func test_band_to_battle_units() -> void:
	# Create band with a recruit
	var band := BattleBand.create("Battle Test Band")
	band.gold = 500
	var templates: Array = GameData.all_characters()
	if templates.is_empty():
		pass_test("No templates available — skipping")
		return
	var template: CharacterData = templates[0] as CharacterData
	var result := Recruiter.recruit(band, template, _gen_name)
	assert_eq(result["error"], "")

	# Build party from fielded instances
	var fielded: Array[CharacterInstance] = []
	fielded.append(band.roster[0])
	var party: Array[BattleUnit] = BandPartyBuilder.build_party(
		fielded, _race_provider, _class_provider)

	assert_eq(party.size(), 1)
	var unit: BattleUnit = party[0]
	assert_eq(unit.character.display_name, band.roster[0].name)
	assert_true(unit.stats.effective("hp") > 0, "Unit should have positive HP")


func test_bp_calculator_with_real_data() -> void:
	var ci := CharacterInstance.new()
	ci.class_levels = {"vagabond": 5}
	ci.equipment = {}
	ci.ability_loadout = []
	# Base BP: 5 * 3 = 15
	var bp: int = BpCalculator.compute(ci, _item_provider)
	assert_eq(bp, 15)

	# With equipment
	ci.equipment = {"weapon": "sword"}
	bp = BpCalculator.compute(ci, _item_provider)
	# 15 + item bp_value for sword
	var sword: ItemData = GameData.get_item("sword")
	if sword != null:
		assert_eq(bp, 15 + sword.bp_value)


func test_save_manager_round_trip_with_real_band() -> void:
	# Use a temp path to avoid clobbering real saves
	var tmp_path: String = "user://test_integration_a5_save.json"
	SaveManager.set_save_path(tmp_path)

	# Clean slate
	SaveManager.bands.clear()
	SaveManager.save_game()
	SaveManager.load_game()
	assert_eq(SaveManager.bands.size(), 0)

	# Create a band via SaveManager
	var band := SaveManager.create_band("SM Integration")
	assert_true(band.gold > 0, "Band should have starting gold")

	# Recruit
	var templates: Array = GameData.all_characters()
	if not templates.is_empty():
		var template: CharacterData = templates[0] as CharacterData
		Recruiter.recruit(band, template, _gen_name)

	SaveManager.save_game()

	# Reload
	SaveManager.bands.clear()
	SaveManager.load_game()
	assert_eq(SaveManager.bands.size(), 1)
	var restored: BattleBand = SaveManager.bands[0]
	assert_eq(restored.name, "SM Integration")
	assert_eq(restored.roster_size(), band.roster_size())

	# Cleanup
	DirAccess.remove_absolute(tmp_path)
	SaveManager.set_save_path(SaveManager.SAVE_PATH)


func test_recruiter_scale_to_band_average() -> void:
	var band := BattleBand.create("Scale Test")
	band.gold = 1000
	# Add a high-level member manually
	var veteran := CharacterInstance.new()
	veteran.instance_id = "vet_1"
	veteran.class_levels = {"vagabond": 10}
	veteran.active_class = "vagabond"
	veteran.unlocked_classes = ["vagabond"] as Array[String]
	band.add_instance(veteran)

	var avg: int = Recruiter.average_band_level(band)
	assert_eq(avg, 10)

	# Recruit and scale
	var templates: Array = GameData.all_characters()
	if templates.is_empty():
		pass_test("No templates — skipping")
		return
	var template: CharacterData = templates[0] as CharacterData
	var result := Recruiter.recruit(band, template, _gen_name)
	assert_eq(result["error"], "")
	var recruit: CharacterInstance = result["instance"]
	Recruiter.scale_to_level(recruit, avg, _class_provider)
	assert_true(recruit.character_level() >= 10, "Recruit should be scaled to band average")


func test_full_pipeline_create_recruit_field_build() -> void:
	# End-to-end: create band → recruit → field → build party → verify units
	var band := BattleBand.create("Full Pipeline")
	band.gold = 1000

	var templates: Array = GameData.all_characters()
	if templates.size() < 2:
		pass_test("Need at least 2 templates — skipping")
		return

	# Recruit 2 members
	for i in range(2):
		var t: CharacterData = templates[i] as CharacterData
		var r := Recruiter.recruit(band, t, _gen_name)
		assert_eq(r["error"], "")
	assert_eq(band.roster_size(), 2)

	# Field both
	var fielded: Array[CharacterInstance] = []
	for ci in band.roster:
		fielded.append(ci)

	# Build party
	var party: Array[BattleUnit] = BandPartyBuilder.build_party(
		fielded, _race_provider, _class_provider)
	assert_eq(party.size(), 2)

	# Generate opponents
	var opp_instances := BandPartyBuilder.generate_opponent_instances(
		templates, _gen_name, 2)
	assert_eq(opp_instances.size(), 2)
	var opp_party: Array[BattleUnit] = BandPartyBuilder.build_party(
		opp_instances, _race_provider, _class_provider)
	assert_eq(opp_party.size(), 2)

	# Verify all units have valid stats
	for unit in party:
		assert_true(unit.stats.effective("hp") > 0)
		assert_false(unit.character.display_name.is_empty())
	for unit in opp_party:
		assert_true(unit.stats.effective("hp") > 0)
