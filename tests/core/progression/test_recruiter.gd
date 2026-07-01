extends GutTest
## Tests for Recruiter: recruitment logic, gold deduction, scaling.


var _template: CharacterData


func before_each() -> void:
	_template = CharacterData.new()
	_template.id = "human_fighter"
	_template.display_name = "Human Fighter"
	_template.race = "human"


func _name_gen(race: String) -> String:
	return "Test " + race.capitalize()


func _class_provider(id: String) -> ClassData:
	var cls := ClassData.new()
	cls.id = id
	cls.growth = {"hp": 1.0, "atk": 0.5}
	cls.stat_modifiers = {}
	cls.jp_costs = {}
	cls.prerequisites = {}
	cls.equipment_access = []
	return cls


func test_recruit_creates_vagabond_instance() -> void:
	var band := BattleBand.create("Test")
	band.gold = 100
	var result := Recruiter.recruit(band, _template, _name_gen, 50, 12)
	assert_eq(result["error"], "")
	var ci: CharacterInstance = result["instance"]
	assert_not_null(ci)
	assert_eq(ci.character_level(), 1)
	assert_eq(ci.active_class, "vagabond")
	assert_eq(ci.race, "human")
	assert_false(ci.instance_id.is_empty())


func test_recruit_deducts_gold() -> void:
	var band := BattleBand.create("Test")
	band.gold = 200
	Recruiter.recruit(band, _template, _name_gen, 50, 12)
	assert_eq(band.gold, 150)


func test_recruit_rejects_insufficient_gold() -> void:
	var band := BattleBand.create("Test")
	band.gold = 10
	var result := Recruiter.recruit(band, _template, _name_gen, 50, 12)
	assert_null(result["instance"])
	assert_true((result["error"] as String).begins_with("Not enough gold"))
	assert_eq(band.gold, 10)  # Gold unchanged


func test_recruit_rejects_full_roster() -> void:
	var band := BattleBand.create("Test")
	band.gold = 1000
	# Fill roster (cap=2)
	Recruiter.recruit(band, _template, _name_gen, 0, 2)
	Recruiter.recruit(band, _template, _name_gen, 0, 2)
	var result := Recruiter.recruit(band, _template, _name_gen, 0, 2)
	assert_null(result["instance"])
	assert_eq(result["error"], "Roster is full")


func test_scale_to_level() -> void:
	var ci := CharacterInstance.new()
	ci.class_levels = {"vagabond": 1}
	ci.xp = 0
	ci.active_class = "vagabond"
	ci.unlocked_classes = ["vagabond"] as Array[String]
	Recruiter.scale_to_level(ci, 3, _class_provider)
	assert_true(ci.character_level() >= 3, "Expected level >= 3, got %d" % ci.character_level())


func test_scale_does_nothing_if_already_at_target() -> void:
	var ci := CharacterInstance.new()
	ci.class_levels = {"vagabond": 5}
	ci.xp = 999
	ci.active_class = "vagabond"
	Recruiter.scale_to_level(ci, 3, _class_provider)
	assert_eq(ci.character_level(), 5)  # Unchanged


func test_average_band_level() -> void:
	var band := BattleBand.create("Test")
	assert_eq(Recruiter.average_band_level(band), 1)  # Empty
	var ci1 := CharacterInstance.new()
	ci1.instance_id = "ci_1"
	ci1.class_levels = {"vagabond": 4}
	var ci2 := CharacterInstance.new()
	ci2.instance_id = "ci_2"
	ci2.class_levels = {"vagabond": 6}
	band.add_instance(ci1, 12)
	band.add_instance(ci2, 12)
	assert_eq(Recruiter.average_band_level(band), 5)
