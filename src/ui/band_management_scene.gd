class_name BandManagementScene
extends Control
## Full-screen band management UI: create/load bands, manage roster,
## inspect characters, field for battle.
## Spec reference: alpha-phaseA5-spec.md §8

enum PanelState { BAND_SELECT, ROSTER_VIEW, INSTANCE_INSPECT, FIELD_SELECT, SHOP }

var _state: int = PanelState.BAND_SELECT
var _band: BattleBand = null
var _inspected: CharacterInstance = null
var _name_gen: NameGenerator

# Provider callables
var _race_prov: Callable
var _class_prov: Callable
var _item_prov: Callable

# --- Panel containers ---
var _band_panel: VBoxContainer
var _roster_panel: VBoxContainer
var _inspect_panel: VBoxContainer
var _field_panel: VBoxContainer

# --- Band select widgets ---
var _band_list_box: VBoxContainer
var _new_band_input: LineEdit

# --- Roster view widgets ---
var _roster_title: Label
var _gold_label: Label
var _roster_list: VBoxContainer
var _recruit_list: VBoxContainer

# --- Instance inspect widgets ---
var _inspect_name: Label
var _inspect_stats: Label
var _inspect_class: Label
var _inspect_jp: Label
var _inspect_abilities: Label
var _inspect_equipment: Label
var _inspect_xp: Label
var _class_buttons: VBoxContainer
var _ability_buttons: VBoxContainer
var _equip_buttons: VBoxContainer
var _passive_buttons: VBoxContainer		## A18: passive slot equip/unequip buttons

# --- Field select widgets ---
var _field_checks: VBoxContainer
var _field_map_label: Label
var _field_start_btn: Button
var _selected_map: MapData
var _fielded_set: Dictionary = {}

# --- Shop widgets ---
var _shop_panel: VBoxContainer
var _shop_gold_label: Label
var _shop_buy_list: VBoxContainer
var _shop_sell_list: VBoxContainer
var _shop_feedback: Label

# --- Dev tools containers (gated by Dev.enabled) ---
var _dev_roster_box: VBoxContainer
var _dev_inspect_box: VBoxContainer


func _ready() -> void:
	_name_gen = NameGenerator.new()
	_name_gen.load_tables()
	_race_prov = func(id: String) -> RaceData: return GameData.get_race(id)
	_class_prov = func(id: String) -> ClassData: return GameData.get_job_class(id)
	_item_prov = func(id: String) -> ItemData: return GameData.get_item(id)
	SaveManager.load_game()
	_build_ui()
	_show_band_select()


# ============================================================
# UI CONSTRUCTION
# ============================================================

func _build_ui() -> void:
	set_anchors_preset(PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(root)

	_build_band_select_panel(root)
	_build_roster_panel(root)
	_build_inspect_panel(root)
	_build_field_panel(root)
	_build_shop_panel(root)


func _build_band_select_panel(root: VBoxContainer) -> void:
	_band_panel = VBoxContainer.new()
	root.add_child(_band_panel)

	var title := Label.new()
	title.text = "Battle Bands"
	title.add_theme_font_size_override("font_size", 28)
	_band_panel.add_child(title)
	_band_panel.add_child(_spacer(16))

	_band_list_box = VBoxContainer.new()
	_band_panel.add_child(_band_list_box)

	_band_panel.add_child(_spacer(16))

	var create_row := HBoxContainer.new()
	_band_panel.add_child(create_row)

	_new_band_input = LineEdit.new()
	_new_band_input.placeholder_text = "New band name..."
	_new_band_input.size_flags_horizontal = SIZE_EXPAND_FILL
	_new_band_input.custom_minimum_size.x = 200
	create_row.add_child(_new_band_input)

	var create_btn := Button.new()
	create_btn.text = "Create Band"
	create_btn.pressed.connect(_on_create_band)
	create_row.add_child(create_btn)

	_band_panel.add_child(_spacer(16))

	var back_btn := Button.new()
	back_btn.text = "Back to Menu"
	back_btn.custom_minimum_size.y = 40
	back_btn.pressed.connect(_on_back_to_menu)
	_band_panel.add_child(back_btn)


func _build_roster_panel(root: VBoxContainer) -> void:
	_roster_panel = VBoxContainer.new()
	_roster_panel.visible = false
	root.add_child(_roster_panel)

	_roster_title = Label.new()
	_roster_title.add_theme_font_size_override("font_size", 24)
	_roster_panel.add_child(_roster_title)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 16)
	_roster_panel.add_child(_gold_label)

	_roster_panel.add_child(_spacer(12))

	var roster_header := Label.new()
	roster_header.text = "Roster"
	roster_header.add_theme_font_size_override("font_size", 18)
	_roster_panel.add_child(roster_header)

	_roster_list = VBoxContainer.new()
	_roster_panel.add_child(_roster_list)

	_roster_panel.add_child(_spacer(12))

	# Recruit section
	var recruit_header := Label.new()
	recruit_header.text = "Recruit"
	recruit_header.add_theme_font_size_override("font_size", 18)
	_roster_panel.add_child(recruit_header)

	_recruit_list = VBoxContainer.new()
	_roster_panel.add_child(_recruit_list)

	_roster_panel.add_child(_spacer(12))

	# Action buttons
	var actions := HBoxContainer.new()
	_roster_panel.add_child(actions)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.custom_minimum_size.y = 40
	save_btn.pressed.connect(_on_save_band)
	actions.add_child(save_btn)

	var shop_btn := Button.new()
	shop_btn.text = "Shop"
	shop_btn.custom_minimum_size.y = 40
	shop_btn.pressed.connect(_on_show_shop)
	actions.add_child(shop_btn)

	var field_btn := Button.new()
	field_btn.text = "Field for Battle"
	field_btn.custom_minimum_size.y = 40
	field_btn.pressed.connect(_on_show_field_select)
	actions.add_child(field_btn)

	var embark_btn := Button.new()
	embark_btn.text = "Embark on Run"
	embark_btn.custom_minimum_size.y = 40
	embark_btn.pressed.connect(_on_embark_run)
	actions.add_child(embark_btn)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size.y = 40
	back_btn.pressed.connect(_on_roster_back)
	actions.add_child(back_btn)

	# Dev controls container (populated in _refresh_dev_roster)
	if Dev.enabled:
		_dev_roster_box = VBoxContainer.new()
		_roster_panel.add_child(_dev_roster_box)


func _build_inspect_panel(root: VBoxContainer) -> void:
	_inspect_panel = VBoxContainer.new()
	_inspect_panel.visible = false
	root.add_child(_inspect_panel)

	_inspect_name = Label.new()
	_inspect_name.add_theme_font_size_override("font_size", 24)
	_inspect_panel.add_child(_inspect_name)

	_inspect_xp = Label.new()
	_inspect_panel.add_child(_inspect_xp)

	_inspect_stats = Label.new()
	_inspect_panel.add_child(_inspect_stats)

	_inspect_panel.add_child(_spacer(8))

	_inspect_class = Label.new()
	_inspect_class.add_theme_font_size_override("font_size", 16)
	_inspect_panel.add_child(_inspect_class)

	# Class switch / unlock buttons
	var class_header := Label.new()
	class_header.text = "Classes"
	class_header.add_theme_font_size_override("font_size", 18)
	_inspect_panel.add_child(class_header)

	_class_buttons = VBoxContainer.new()
	_inspect_panel.add_child(_class_buttons)

	_inspect_panel.add_child(_spacer(8))

	# JP / abilities
	_inspect_jp = Label.new()
	_inspect_panel.add_child(_inspect_jp)

	var ability_header := Label.new()
	ability_header.text = "Abilities"
	ability_header.add_theme_font_size_override("font_size", 18)
	_inspect_panel.add_child(ability_header)

	_inspect_abilities = Label.new()
	_inspect_panel.add_child(_inspect_abilities)

	_ability_buttons = VBoxContainer.new()
	_inspect_panel.add_child(_ability_buttons)

	# A18: passive slot section
	var passive_header := Label.new()
	passive_header.text = "Passive Slots"
	passive_header.add_theme_font_size_override("font_size", 16)
	_inspect_panel.add_child(passive_header)

	_passive_buttons = VBoxContainer.new()
	_inspect_panel.add_child(_passive_buttons)

	_inspect_panel.add_child(_spacer(8))

	# Equipment
	var equip_header := Label.new()
	equip_header.text = "Equipment"
	equip_header.add_theme_font_size_override("font_size", 18)
	_inspect_panel.add_child(equip_header)

	_inspect_equipment = Label.new()
	_inspect_panel.add_child(_inspect_equipment)

	_equip_buttons = VBoxContainer.new()
	_inspect_panel.add_child(_equip_buttons)

	_inspect_panel.add_child(_spacer(12))

	# Dev controls container (populated in _refresh_dev_inspect)
	if Dev.enabled:
		_dev_inspect_box = VBoxContainer.new()
		_inspect_panel.add_child(_dev_inspect_box)

	_inspect_panel.add_child(_spacer(12))

	# Bottom actions
	var actions := HBoxContainer.new()
	_inspect_panel.add_child(actions)

	var dismiss_btn := Button.new()
	dismiss_btn.text = "Dismiss"
	dismiss_btn.custom_minimum_size.y = 40
	dismiss_btn.pressed.connect(_on_dismiss_instance)
	actions.add_child(dismiss_btn)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size.y = 40
	back_btn.pressed.connect(_on_inspect_back)
	actions.add_child(back_btn)


func _build_field_panel(root: VBoxContainer) -> void:
	_field_panel = VBoxContainer.new()
	_field_panel.visible = false
	root.add_child(_field_panel)

	var title := Label.new()
	title.text = "Field Selection"
	title.add_theme_font_size_override("font_size", 24)
	_field_panel.add_child(title)

	_field_panel.add_child(_spacer(8))

	_field_map_label = Label.new()
	_field_map_label.add_theme_font_size_override("font_size", 18)
	_field_panel.add_child(_field_map_label)

	_field_panel.add_child(_spacer(12))

	_field_checks = VBoxContainer.new()
	_field_panel.add_child(_field_checks)

	_field_panel.add_child(_spacer(12))

	var actions := HBoxContainer.new()
	_field_panel.add_child(actions)

	_field_start_btn = Button.new()
	_field_start_btn.text = "Start Quick Battle"
	_field_start_btn.custom_minimum_size.y = 50
	_field_start_btn.pressed.connect(_on_start_battle)
	actions.add_child(_field_start_btn)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size.y = 40
	back_btn.pressed.connect(_on_field_back)
	actions.add_child(back_btn)


func _build_shop_panel(root: VBoxContainer) -> void:
	_shop_panel = VBoxContainer.new()
	_shop_panel.visible = false
	root.add_child(_shop_panel)

	var title := Label.new()
	title.text = "Shop"
	title.add_theme_font_size_override("font_size", 24)
	_shop_panel.add_child(title)

	_shop_gold_label = Label.new()
	_shop_gold_label.add_theme_font_size_override("font_size", 16)
	_shop_panel.add_child(_shop_gold_label)

	_shop_panel.add_child(_spacer(8))

	_shop_feedback = Label.new()
	_shop_feedback.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	_shop_panel.add_child(_shop_feedback)

	_shop_panel.add_child(_spacer(8))

	var buy_header := Label.new()
	buy_header.text = "Buy"
	buy_header.add_theme_font_size_override("font_size", 18)
	_shop_panel.add_child(buy_header)

	_shop_buy_list = VBoxContainer.new()
	_shop_panel.add_child(_shop_buy_list)

	_shop_panel.add_child(_spacer(12))

	var sell_header := Label.new()
	sell_header.text = "Sell"
	sell_header.add_theme_font_size_override("font_size", 18)
	_shop_panel.add_child(sell_header)

	_shop_sell_list = VBoxContainer.new()
	_shop_panel.add_child(_shop_sell_list)

	_shop_panel.add_child(_spacer(12))

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size.y = 40
	back_btn.pressed.connect(_on_shop_back)
	_shop_panel.add_child(back_btn)


func _spacer(height: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size.y = height
	return s


# ============================================================
# PANEL TRANSITIONS
# ============================================================

func _show_band_select() -> void:
	_state = PanelState.BAND_SELECT
	_band_panel.visible = true
	_roster_panel.visible = false
	_inspect_panel.visible = false
	_field_panel.visible = false
	_shop_panel.visible = false
	_refresh_band_list()


func _show_roster_view() -> void:
	_state = PanelState.ROSTER_VIEW
	_band_panel.visible = false
	_roster_panel.visible = true
	_inspect_panel.visible = false
	_field_panel.visible = false
	_shop_panel.visible = false
	_refresh_roster()


func _show_inspect(ci: CharacterInstance) -> void:
	_inspected = ci
	_state = PanelState.INSTANCE_INSPECT
	_band_panel.visible = false
	_roster_panel.visible = false
	_inspect_panel.visible = true
	_field_panel.visible = false
	_shop_panel.visible = false
	_refresh_inspect()


func _show_field_select() -> void:
	_state = PanelState.FIELD_SELECT
	_band_panel.visible = false
	_roster_panel.visible = false
	_inspect_panel.visible = false
	_field_panel.visible = true
	_shop_panel.visible = false
	_fielded_set.clear()
	_refresh_field_select()


func _show_shop() -> void:
	_state = PanelState.SHOP
	_band_panel.visible = false
	_roster_panel.visible = false
	_inspect_panel.visible = false
	_field_panel.visible = false
	_shop_panel.visible = true
	_shop_feedback.text = ""
	_refresh_shop()


# ============================================================
# BAND SELECT
# ============================================================

func _refresh_band_list() -> void:
	for child in _band_list_box.get_children():
		child.queue_free()
	if SaveManager.bands.is_empty():
		var empty := Label.new()
		empty.text = "No bands yet. Create one below."
		_band_list_box.add_child(empty)
		return
	for band in SaveManager.bands:
		var row := HBoxContainer.new()
		var btn := Button.new()
		btn.text = "%s  (%d members, %d gold)" % [band.name, band.roster_size(), band.gold]
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		btn.custom_minimum_size.y = 40
		var bid: String = band.band_id
		btn.pressed.connect(_on_band_selected.bind(bid))
		row.add_child(btn)

		var del_btn := Button.new()
		del_btn.text = "X"
		del_btn.custom_minimum_size = Vector2(40, 40)
		del_btn.pressed.connect(_on_delete_band.bind(bid))
		row.add_child(del_btn)

		_band_list_box.add_child(row)


func _on_create_band() -> void:
	var band_name: String = _new_band_input.text.strip_edges()
	if band_name.is_empty():
		band_name = "New Band"
	_band = SaveManager.create_band(band_name)
	SaveManager.save_game()
	_new_band_input.text = ""
	_show_roster_view()


func _on_band_selected(band_id: String) -> void:
	_band = SaveManager.get_band(band_id)
	if _band != null:
		_show_roster_view()


func _on_delete_band(band_id: String) -> void:
	SaveManager.delete_band(band_id)
	SaveManager.save_game()
	_refresh_band_list()


func _on_back_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


# ============================================================
# ROSTER VIEW
# ============================================================

func _refresh_roster() -> void:
	if _band == null:
		return
	_roster_title.text = _band.name
	_gold_label.text = "Gold: %d" % _band.gold

	# Roster entries
	for child in _roster_list.get_children():
		child.queue_free()
	if _band.roster.is_empty():
		var empty := Label.new()
		empty.text = "No members. Recruit below."
		_roster_list.add_child(empty)
	else:
		for ci in _band.roster:
			var bp: int = BpCalculator.compute(ci, _item_prov)
			var btn := Button.new()
			btn.text = "%s  —  Lv%d %s  (%d BP)" % [
				ci.name, ci.character_level(), ci.active_class.capitalize(), bp]
			btn.size_flags_horizontal = SIZE_EXPAND_FILL
			btn.custom_minimum_size.y = 36
			var iid: String = ci.instance_id
			btn.pressed.connect(_on_inspect_instance.bind(iid))
			_roster_list.add_child(btn)

	# Recruit buttons (one per draftable race — each produces L1 Vagabond)
	for child in _recruit_list.get_children():
		child.queue_free()
	var cost: int = Constants.get_value("RECRUIT_COST", 50)
	var draftable: Array = Constants.get_value("DRAFTABLE_RACES",
		["human", "dwarf", "elf", "halfling"]) as Array
	for race_id in draftable:
		var race_name: String = str(race_id).capitalize()
		var btn := Button.new()
		btn.text = "Recruit %s Vagabond — %d gold" % [race_name, cost]
		btn.custom_minimum_size.y = 32
		btn.disabled = _band.gold < cost or _band.is_roster_full()
		var rid: String = str(race_id)
		btn.pressed.connect(_on_recruit_race.bind(rid))
		_recruit_list.add_child(btn)

	# Inventory summary
	var equip_list: Array = _band.inventory["equipment"] as Array
	if not equip_list.is_empty():
		var inv_label := Label.new()
		var items_str: Array[String] = []
		for eid in equip_list:
			var item: ItemData = GameData.get_item(str(eid))
			if item != null:
				items_str.append(item.display_name)
			else:
				items_str.append(str(eid))
		inv_label.text = "Inventory: %s" % ", ".join(items_str)
		_roster_list.add_child(inv_label)

	if Dev.enabled:
		_refresh_dev_roster()


func _on_inspect_instance(instance_id: String) -> void:
	var ci := _band.get_instance(instance_id)
	if ci != null:
		_show_inspect(ci)


func _on_recruit_race(race_id: String) -> void:
	# A11: Race-based recruitment — builds a synthetic L1 Vagabond template
	var starting_class: String = str(Constants.get_value("STARTING_CLASS", "vagabond"))
	var template := CharacterData.new()
	template.id = "%s_%s" % [race_id, starting_class]
	template.display_name = "%s %s" % [race_id.capitalize(), starting_class.capitalize()]
	template.race = race_id
	template.classes = [starting_class] as Array[String]
	template.level = 1
	template.bp = 0
	template.base_stats = {}
	var race_data: RaceData = GameData.get_race(race_id)
	if race_data != null:
		template.base_stats = race_data.base_stats.duplicate()
	var gen_name := func(race: String) -> String: return _name_gen.generate_name(race)
	var bonus: Array[String] = []
	if Dev.enabled and DevOverrides.get_flag("DEV_ALL_CLASSES_UNLOCKED", false):
		for cid in GameData.all_classes():
			bonus.append(str(cid))
	else:
		bonus = SaveManager.profile.unlocked_classes.duplicate()
	var result := Recruiter.recruit(_band, template, gen_name, -1, -1, bonus)
	if result["error"] != "":
		Log.info("BandManagement", result["error"])
		return
	# Scale recruit to band average
	var ci: CharacterInstance = result["instance"]
	var avg: int = Recruiter.average_band_level(_band)
	if avg > 1:
		Recruiter.scale_to_level(ci, avg, _class_prov)
	_refresh_roster()


func _on_save_band() -> void:
	SaveManager.save_game()
	Log.info("BandManagement", "Band saved")


func _on_roster_back() -> void:
	SaveManager.save_game()
	_band = null
	_show_band_select()


# ============================================================
# INSTANCE INSPECT
# ============================================================

func _refresh_inspect() -> void:
	if _inspected == null:
		return

	_inspect_name.text = "%s  (Lv%d %s)" % [
		_inspected.name, _inspected.character_level(), _inspected.race.capitalize()]
	var down_limit: int = Constants.get_value("DOWN_LIMIT", 2)
	var remaining_lives: int = maxi(0, down_limit + 1 - _inspected.downs_this_run)
	var total_lives: int = down_limit + 1
	_inspect_xp.text = "XP: %d / %d  |  Lives: %d/%d" % [
		_inspected.xp, Leveling.next_threshold(_inspected.character_level()), remaining_lives, total_lives]

	# Compute stats
	var sb: StatBlock = InstanceStatResolver.resolve(_inspected, _race_prov, _class_prov)
	var stat_parts: Array[String] = []
	for k in ["hp", "atk", "def", "mag", "res", "spd", "rng", "jump"]:
		stat_parts.append("%s %d" % [k.to_upper(), sb.effective(k)])
	_inspect_stats.text = "Stats: " + "  ".join(stat_parts)

	_inspect_class.text = "Active class: %s" % _inspected.active_class.capitalize()

	# JP display
	var jp_parts: Array[String] = []
	for cls_id in _inspected.unlocked_classes:
		jp_parts.append("%s: %d JP" % [cls_id.capitalize(), int(_inspected.jp.get(cls_id, 0))])
	_inspect_jp.text = "JP: " + ", ".join(jp_parts) if not jp_parts.is_empty() else "JP: —"

	# Learned abilities display
	if _inspected.learned_abilities.is_empty():
		_inspect_abilities.text = "Learned: none"
	else:
		_inspect_abilities.text = "Learned: " + ", ".join(_inspected.learned_abilities)

	# Equipment display
	if _inspected.equipment.is_empty():
		_inspect_equipment.text = "Equipped: none"
	else:
		var eq_parts: Array[String] = []
		for slot in _inspected.equipment.keys():
			var item_id: String = str(_inspected.equipment[slot])
			var item: ItemData = GameData.get_item(item_id)
			var item_name: String = item.display_name if item != null else item_id
			eq_parts.append("%s: %s" % [slot.capitalize(), item_name])
		_inspect_equipment.text = "Equipped: " + ", ".join(eq_parts)

	_refresh_class_buttons()
	_refresh_ability_buttons()
	_refresh_passive_buttons()
	_refresh_equip_buttons()

	if Dev.enabled:
		_refresh_dev_inspect()


func _refresh_class_buttons() -> void:
	for child in _class_buttons.get_children():
		child.queue_free()
	# Switch to unlocked class
	for cls_id in _inspected.unlocked_classes:
		var btn := Button.new()
		if cls_id == _inspected.active_class:
			btn.text = "%s (active)" % cls_id.capitalize()
			btn.disabled = true
		else:
			btn.text = "Switch to %s" % cls_id.capitalize()
			var cid: String = cls_id
			btn.pressed.connect(_on_switch_class.bind(cid))
		btn.custom_minimum_size.y = 30
		_class_buttons.add_child(btn)
	# Unlock / locked classes — show all known classes with status
	for cls_id in GameData.all_classes():
		var cid: String = str(cls_id)
		if _inspected.unlocked_classes.has(cid):
			continue
		var cls: ClassData = GameData.get_job_class(cid)
		if cls == null:
			continue
		if _inspected.can_unlock(cid, _class_prov):
			var btn := Button.new()
			btn.text = "Unlock %s" % cls.display_name
			btn.custom_minimum_size.y = 30
			btn.pressed.connect(_on_unlock_class.bind(cid))
			_class_buttons.add_child(btn)
		else:
			# Show locked class with prerequisite info
			var prereq_text: String = _format_prerequisites(cls)
			var label := Label.new()
			label.text = "[LOCKED] %s — %s" % [cls.display_name, prereq_text]
			label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			_class_buttons.add_child(label)


func _refresh_ability_buttons() -> void:
	for child in _ability_buttons.get_children():
		child.queue_free()
	# Show learnable abilities from active class
	var cls: ClassData = GameData.get_job_class(_inspected.active_class)
	if cls == null:
		return
	var current_jp: int = int(_inspected.jp.get(_inspected.active_class, 0))
	for ability_id in cls.jp_costs.keys():
		var cost: int = int(cls.jp_costs[ability_id])
		var btn := Button.new()
		if _inspected.learned_abilities.has(ability_id):
			btn.text = "%s (learned)" % ability_id
			btn.disabled = true
		elif current_jp >= cost:
			btn.text = "Learn %s (%d JP)" % [ability_id, cost]
			var aid: String = ability_id
			btn.pressed.connect(_on_learn_ability.bind(aid))
		else:
			btn.text = "%s (%d JP — need %d)" % [ability_id, cost, cost - current_jp]
			btn.disabled = true
		btn.custom_minimum_size.y = 30
		_ability_buttons.add_child(btn)

	# Loadout toggle: show learned abilities as toggleable
	if not _inspected.learned_abilities.is_empty():
		var loadout_label := Label.new()
		loadout_label.text = "Loadout (toggle to equip/unequip):"
		_ability_buttons.add_child(loadout_label)
		for ab_id in _inspected.learned_abilities:
			var btn := Button.new()
			var in_loadout: bool = _inspected.ability_loadout.has(ab_id)
			btn.text = "[X] %s" % ab_id if in_loadout else "[ ] %s" % ab_id
			var aid: String = ab_id
			btn.pressed.connect(_on_toggle_loadout.bind(aid))
			btn.custom_minimum_size.y = 28
			_ability_buttons.add_child(btn)


func _refresh_passive_buttons() -> void:
	## A18: Show equipped passive slots and allow equip/unequip of learned passives.
	for child in _passive_buttons.get_children():
		child.queue_free()

	var ab_prov: Callable = func(ab_id: String) -> AbilityData: return GameData.get_ability(ab_id)

	# Show current slots with unequip buttons
	for kind in ["reaction", "support", "movement"]:
		var equipped_id: String = str(_inspected.get(kind + "_slot") if _inspected.get(kind + "_slot") != null else "")
		var row := HBoxContainer.new()
		var slot_label := Label.new()
		slot_label.text = kind.capitalize() + ": " + (equipped_id if not equipped_id.is_empty() else "(none)")
		slot_label.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(slot_label)
		if not equipped_id.is_empty():
			var unequip_btn := Button.new()
			unequip_btn.text = "Unequip"
			unequip_btn.custom_minimum_size.y = 28
			var k: String = kind
			unequip_btn.pressed.connect(_on_unequip_passive.bind(k))
			row.add_child(unequip_btn)
		_passive_buttons.add_child(row)

	# List learned passives that can be equipped
	var has_passives: bool = false
	for ab_id: String in _inspected.learned_abilities:
		var ab: AbilityData = GameData.get_ability(ab_id)
		if ab == null or ab.type != "passive":
			continue
		if not has_passives:
			var equip_label := Label.new()
			equip_label.text = "Equip passive:"
			_passive_buttons.add_child(equip_label)
			has_passives = true
		var btn := Button.new()
		btn.text = "Equip %s (%s)" % [ab_id, ab.passive_kind]
		btn.custom_minimum_size.y = 28
		var aid: String = ab_id
		btn.pressed.connect(_on_equip_passive.bind(aid))
		_passive_buttons.add_child(btn)


func _on_equip_passive(ability_id: String) -> void:
	var ab_prov: Callable = func(ab_id: String) -> AbilityData: return GameData.get_ability(ab_id)
	_inspected.equip_passive(ability_id, ab_prov)
	SaveManager.save_game()
	_refresh_inspect()


func _on_unequip_passive(kind: String) -> void:
	_inspected.unequip_passive(kind)
	SaveManager.save_game()
	_refresh_inspect()


func _refresh_equip_buttons() -> void:
	for child in _equip_buttons.get_children():
		child.queue_free()
	# Unequip current equipment
	for slot in _inspected.equipment.keys():
		var item_id: String = str(_inspected.equipment[slot])
		var item: ItemData = GameData.get_item(item_id)
		var item_name: String = item.display_name if item != null else item_id
		var btn := Button.new()
		btn.text = "Unequip %s (%s)" % [item_name, slot.capitalize()]
		btn.custom_minimum_size.y = 30
		var s: String = slot
		btn.pressed.connect(_on_unequip.bind(s))
		_equip_buttons.add_child(btn)
	# Equip from inventory
	var equip_list: Array = _band.inventory["equipment"] as Array
	if not equip_list.is_empty():
		var equip_label := Label.new()
		equip_label.text = "Equip from inventory:"
		_equip_buttons.add_child(equip_label)
		for i in range(equip_list.size()):
			var item_id: String = str(equip_list[i])
			var item: ItemData = GameData.get_item(item_id)
			if item == null:
				continue
			var btn := Button.new()
			btn.text = "%s → %s slot" % [item.display_name, item.slot.capitalize()]
			btn.custom_minimum_size.y = 28
			var eid: String = item_id
			var eslot: String = item.slot
			btn.pressed.connect(_on_equip_from_inventory.bind(eid, eslot))
			_equip_buttons.add_child(btn)


func _on_switch_class(class_id: String) -> void:
	_inspected.set_active_class(class_id)
	_refresh_inspect()


func _on_unlock_class(class_id: String) -> void:
	_inspected.unlock_class(class_id, _class_prov)
	_refresh_inspect()


func _on_learn_ability(ability_id: String) -> void:
	_inspected.learn_ability(ability_id, _inspected.active_class, _class_prov)
	_refresh_inspect()


func _on_toggle_loadout(ability_id: String) -> void:
	var new_loadout: Array[String] = _inspected.ability_loadout.duplicate()
	if new_loadout.has(ability_id):
		new_loadout.erase(ability_id)
	else:
		new_loadout.append(ability_id)
	_inspected.set_loadout(new_loadout)
	_refresh_inspect()


func _on_unequip(slot: String) -> void:
	_band.unassign_equipment(_inspected, slot)
	_refresh_inspect()


func _on_equip_from_inventory(item_id: String, slot: String) -> void:
	_band.assign_equipment(_inspected, slot, item_id, _class_prov, _item_prov)
	_refresh_inspect()


func _on_dismiss_instance() -> void:
	if _inspected == null or _band == null:
		return
	_band.remove_instance(_inspected.instance_id)
	_inspected = null
	_show_roster_view()


func _on_inspect_back() -> void:
	_inspected = null
	_show_roster_view()


func _format_prerequisites(cls: ClassData) -> String:
	var parts: Array[String] = []
	var pre: Dictionary = cls.prerequisites
	if pre.is_empty():
		return "no prerequisites"
	var req_level: int = int(pre.get("level", 0))
	if req_level > 0:
		parts.append("Lv%d" % req_level)
	var req_classes: Array = pre.get("classes", []) as Array
	for pair in req_classes:
		if pair is Array and (pair as Array).size() >= 1:
			parts.append(str(pair[0]).capitalize())
	if parts.is_empty():
		return "requirements not met"
	return "needs " + ", ".join(parts)


# ============================================================
# FIELD SELECT
# ============================================================

func _on_show_field_select() -> void:
	if _band == null or _band.roster.is_empty():
		return
	_show_field_select()


func _refresh_field_select() -> void:
	for child in _field_checks.get_children():
		child.queue_free()
	_fielded_set.clear()

	# Pick a random map for the quick battle
	var maps: Array = GameData.all_maps()
	if not maps.is_empty():
		_selected_map = maps[randi() % maps.size()] as MapData
		_field_map_label.text = "Map: %s" % _selected_map.id.replace("_", " ").capitalize()
	else:
		_selected_map = null
		_field_map_label.text = "No maps available"

	for ci in _band.roster:
		var row := HBoxContainer.new()
		var check := CheckBox.new()
		var bp: int = BpCalculator.compute(ci, _item_prov)
		check.text = "%s  Lv%d %s  (%d BP)" % [
			ci.name, ci.character_level(), ci.active_class.capitalize(), bp]
		var iid: String = ci.instance_id
		check.toggled.connect(_on_field_toggled.bind(iid))
		row.add_child(check)
		_field_checks.add_child(row)

	_field_start_btn.disabled = true


func _on_field_toggled(toggled: bool, instance_id: String) -> void:
	if toggled:
		_fielded_set[instance_id] = true
	else:
		_fielded_set.erase(instance_id)
	_field_start_btn.disabled = _fielded_set.is_empty()


func _on_start_battle() -> void:
	if _band == null or _selected_map == null or _fielded_set.is_empty():
		return
	SaveManager.save_game()
	var fielded_ids: Array[String] = []
	for iid in _fielded_set.keys():
		fielded_ids.append(str(iid))
	var gen_name := func(race: String) -> String: return _name_gen.generate_name(race)
	var err: String = BandBattleLauncher.launch_quick_battle(
		_band, fielded_ids, _selected_map, gen_name, get_tree())
	if not err.is_empty():
		Log.error("BandManagement", "Battle launch failed: %s" % err)


func _on_field_back() -> void:
	_show_roster_view()


# ============================================================
# SHOP
# ============================================================

func _on_show_shop() -> void:
	if _band == null:
		return
	_show_shop()


func _refresh_shop() -> void:
	if _band == null:
		return
	_shop_gold_label.text = "Gold: %d" % _band.gold

	# --- Buy list ---
	for child in _shop_buy_list.get_children():
		child.queue_free()
	var pool_prov := func(id: String) -> Array:
		return GameData.get_shop_pool(id)
	# A11: Base shop only shows the base_shop pool (bp <= 2 items)
	var pool_ids: Array[String] = ["base_shop"]
	var buyable: Array[String] = ShopService.available_items(pool_ids, pool_prov)
	if buyable.is_empty():
		var empty := Label.new()
		empty.text = "Nothing available."
		_shop_buy_list.add_child(empty)
	else:
		for item_id in buyable:
			var item: ItemData = GameData.get_item(item_id)
			if item == null:
				continue
			var price: int = Pricing.buy_price(item)
			var after_gold: int = _band.gold - price
			var btn := Button.new()
			btn.text = "Buy %s — %d gold (after: %d)" % [item.display_name, price, maxi(after_gold, 0)]
			btn.custom_minimum_size.y = 30
			btn.disabled = _band.gold < price
			var iid: String = item_id
			btn.pressed.connect(_on_shop_buy.bind(iid))
			_shop_buy_list.add_child(btn)

	# --- Sell list ---
	for child in _shop_sell_list.get_children():
		child.queue_free()
	var equip_list: Array = _band.inventory["equipment"] as Array
	var has_sellable: bool = false
	for eid in equip_list:
		var item: ItemData = GameData.get_item(str(eid))
		if item == null:
			continue
		has_sellable = true
		var sell_val: int = Pricing.sell_value(item)
		var after_gold: int = _band.gold + sell_val
		var btn := Button.new()
		btn.text = "Sell %s — +%d gold (after: %d)" % [item.display_name, sell_val, after_gold]
		btn.custom_minimum_size.y = 30
		var sid: String = str(eid)
		btn.pressed.connect(_on_shop_sell_confirm.bind(btn, sid))
		_shop_sell_list.add_child(btn)
	# Consumables
	var consumables: Array = _band.inventory.get("consumables", []) as Array
	for entry in consumables:
		if not entry is Dictionary:
			continue
		var cid: String = str(entry.get("id", ""))
		var qty: int = int(entry.get("qty", 0))
		if cid.is_empty() or qty <= 0:
			continue
		var item: ItemData = GameData.get_item(cid)
		if item == null:
			continue
		has_sellable = true
		var sell_val: int = Pricing.sell_value(item)
		var after_gold: int = _band.gold + sell_val
		var btn := Button.new()
		btn.text = "Sell %s (x%d) — +%d gold each (after: %d)" % [item.display_name, qty, sell_val, after_gold]
		btn.custom_minimum_size.y = 30
		var scid: String = cid
		btn.pressed.connect(_on_shop_sell_confirm.bind(btn, scid))
		_shop_sell_list.add_child(btn)
	if not has_sellable:
		var empty := Label.new()
		empty.text = "Nothing to sell."
		_shop_sell_list.add_child(empty)


func _on_shop_buy(item_id: String) -> void:
	var err := ShopService.buy(_band, item_id, _item_prov)
	if err.is_empty():
		var item: ItemData = GameData.get_item(item_id)
		var name_str: String = item.display_name if item != null else item_id
		_shop_feedback.text = "Bought %s" % name_str
	else:
		_shop_feedback.text = err
	_refresh_shop()


func _on_shop_sell_confirm(btn: Button, item_id: String) -> void:
	# Two-step sell: first click shows "Confirm?", second click sells
	if btn.has_meta("sell_confirmed"):
		var err := ShopService.sell(_band, item_id, _item_prov)
		if err.is_empty():
			var item: ItemData = GameData.get_item(item_id)
			var name_str: String = item.display_name if item != null else item_id
			_shop_feedback.text = "Sold %s" % name_str
		else:
			_shop_feedback.text = err
		_refresh_shop()
	else:
		btn.set_meta("sell_confirmed", true)
		btn.text = "Confirm sell?"
		btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))


func _on_shop_back() -> void:
	_show_roster_view()


# ============================================================
# DEV TOOLS (gated by Dev.enabled)
# ============================================================

func _refresh_dev_roster() -> void:
	if _dev_roster_box == null or _band == null:
		return
	for child in _dev_roster_box.get_children():
		child.queue_free()

	_dev_roster_box.add_child(HSeparator.new())

	var header := Label.new()
	header.text = "DEV TOOLS"
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color.ORANGE_RED)
	_dev_roster_box.add_child(header)

	# Gold controls
	var gold_row := HBoxContainer.new()
	_dev_roster_box.add_child(gold_row)
	var gold_label := Label.new()
	gold_label.text = "Gold:"
	gold_row.add_child(gold_label)
	var gold_spin := SpinBox.new()
	gold_spin.min_value = 0
	gold_spin.max_value = 999999
	gold_spin.value = _band.gold
	gold_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	gold_row.add_child(gold_spin)
	var gold_set_btn := Button.new()
	gold_set_btn.text = "Set"
	gold_set_btn.pressed.connect(func() -> void:
		DevCheatService.set_gold(_band, int(gold_spin.value))
		_refresh_roster())
	gold_row.add_child(gold_set_btn)

	var add_gold_btn := Button.new()
	add_gold_btn.text = "Add 10000 Gold"
	add_gold_btn.pressed.connect(func() -> void:
		DevCheatService.add_gold(_band, 10000)
		_refresh_roster())
	_dev_roster_box.add_child(add_gold_btn)

	# Toggle buttons
	var toggle_inf_gold := CheckBox.new()
	toggle_inf_gold.text = "Infinite Gold"
	toggle_inf_gold.button_pressed = DevOverrides.get_flag("DEV_INFINITE_GOLD", false)
	toggle_inf_gold.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			DevOverrides.set_override("DEV_INFINITE_GOLD", true)
		else:
			DevOverrides.clear_override("DEV_INFINITE_GOLD"))
	_dev_roster_box.add_child(toggle_inf_gold)

	var toggle_free_recruit := CheckBox.new()
	toggle_free_recruit.text = "Free Recruits"
	toggle_free_recruit.button_pressed = DevOverrides.get_flag("DEV_FREE_RECRUIT", false)
	toggle_free_recruit.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			DevOverrides.set_override("DEV_FREE_RECRUIT", true)
		else:
			DevOverrides.clear_override("DEV_FREE_RECRUIT")
		_refresh_roster())
	_dev_roster_box.add_child(toggle_free_recruit)

	# Add all items
	var add_items_btn := Button.new()
	add_items_btn.text = "Add All Equipment Items"
	add_items_btn.pressed.connect(func() -> void:
		DevCheatService.add_all_items(_band)
		_refresh_roster())
	_dev_roster_box.add_child(add_items_btn)

	# --- META / PROFILE section ---
	_dev_roster_box.add_child(HSeparator.new())

	var meta_header := Label.new()
	meta_header.text = "META / PROFILE"
	meta_header.add_theme_font_size_override("font_size", 14)
	meta_header.add_theme_color_override("font_color", Color.ORANGE_RED)
	_dev_roster_box.add_child(meta_header)

	var profile_info := Label.new()
	profile_info.text = "Completed runs: %d | Unlocks: %d" % [
		SaveManager.profile.completed_runs, SaveManager.profile.meta_unlocks.size()]
	_dev_roster_box.add_child(profile_info)

	var grant_templates_btn := Button.new()
	grant_templates_btn.text = "Grant All Templates"
	grant_templates_btn.pressed.connect(func() -> void:
		for t in GameData.all_characters():
			if t is CharacterData:
				DevCheatService.grant_profile_template(SaveManager.profile, (t as CharacterData).id)
		SaveManager.save_game()
		_refresh_roster())
	_dev_roster_box.add_child(grant_templates_btn)

	var grant_classes_btn := Button.new()
	grant_classes_btn.text = "Grant All Classes (Profile)"
	grant_classes_btn.pressed.connect(func() -> void:
		for cid in GameData.all_classes():
			DevCheatService.grant_profile_class(SaveManager.profile, str(cid))
		SaveManager.save_game()
		_refresh_roster())
	_dev_roster_box.add_child(grant_classes_btn)

	var reset_profile_btn := Button.new()
	reset_profile_btn.text = "Reset Profile"
	reset_profile_btn.pressed.connect(func() -> void:
		DevCheatService.reset_profile(SaveManager.profile)
		SaveManager.save_game()
		_refresh_roster())
	_dev_roster_box.add_child(reset_profile_btn)

	var runs_row := HBoxContainer.new()
	_dev_roster_box.add_child(runs_row)
	var runs_label := Label.new()
	runs_label.text = "Runs:"
	runs_row.add_child(runs_label)
	var runs_spin := SpinBox.new()
	runs_spin.min_value = 0
	runs_spin.max_value = 999
	runs_spin.value = SaveManager.profile.completed_runs
	runs_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	runs_row.add_child(runs_spin)
	var runs_set_btn := Button.new()
	runs_set_btn.text = "Set"
	runs_set_btn.pressed.connect(func() -> void:
		DevCheatService.set_completed_runs(SaveManager.profile, int(runs_spin.value))
		SaveManager.save_game()
		_refresh_roster())
	runs_row.add_child(runs_set_btn)

	var toggle_skip_gate := CheckBox.new()
	toggle_skip_gate.text = "Skip Recruit Gate"
	toggle_skip_gate.button_pressed = DevOverrides.get_flag("DEV_SKIP_RECRUITMENT_GATE", false)
	toggle_skip_gate.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			DevOverrides.set_override("DEV_SKIP_RECRUITMENT_GATE", true)
		else:
			DevOverrides.clear_override("DEV_SKIP_RECRUITMENT_GATE")
		_refresh_roster())
	_dev_roster_box.add_child(toggle_skip_gate)

	var toggle_all_classes := CheckBox.new()
	toggle_all_classes.text = "All Classes Unlocked"
	toggle_all_classes.button_pressed = DevOverrides.get_flag("DEV_ALL_CLASSES_UNLOCKED", false)
	toggle_all_classes.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			DevOverrides.set_override("DEV_ALL_CLASSES_UNLOCKED", true)
		else:
			DevOverrides.clear_override("DEV_ALL_CLASSES_UNLOCKED"))
	_dev_roster_box.add_child(toggle_all_classes)


func _refresh_dev_inspect() -> void:
	if _dev_inspect_box == null or _inspected == null:
		return
	for child in _dev_inspect_box.get_children():
		child.queue_free()

	_dev_inspect_box.add_child(HSeparator.new())

	var header := Label.new()
	header.text = "DEV TOOLS"
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color.ORANGE_RED)
	_dev_inspect_box.add_child(header)

	# --- Level controls ---
	var level_row := HBoxContainer.new()
	_dev_inspect_box.add_child(level_row)
	var level_label := Label.new()
	level_label.text = "Level:"
	level_row.add_child(level_label)
	var level_spin := SpinBox.new()
	level_spin.min_value = 1
	level_spin.max_value = Constants.get_value("MAX_LEVEL", 50)
	level_spin.value = _inspected.character_level()
	level_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	level_row.add_child(level_spin)
	var level_set_btn := Button.new()
	level_set_btn.text = "Set"
	level_set_btn.pressed.connect(func() -> void:
		DevCheatService.set_level(_inspected, int(level_spin.value), _class_prov)
		_refresh_inspect())
	level_row.add_child(level_set_btn)

	var max_level_btn := Button.new()
	max_level_btn.text = "Max Level (%d)" % Constants.get_value("MAX_LEVEL", 50)
	max_level_btn.pressed.connect(func() -> void:
		DevCheatService.set_level(_inspected, Constants.get_value("MAX_LEVEL", 50), _class_prov)
		_refresh_inspect())
	_dev_inspect_box.add_child(max_level_btn)

	# --- XP controls ---
	var xp_row := HBoxContainer.new()
	_dev_inspect_box.add_child(xp_row)
	var xp_label := Label.new()
	xp_label.text = "XP:"
	xp_row.add_child(xp_label)
	var xp_spin := SpinBox.new()
	xp_spin.min_value = 0
	xp_spin.max_value = 999999
	xp_spin.value = _inspected.xp
	xp_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	xp_row.add_child(xp_spin)
	var xp_add_btn := Button.new()
	xp_add_btn.text = "Add"
	xp_add_btn.pressed.connect(func() -> void:
		DevCheatService.add_xp(_inspected, int(xp_spin.value), _class_prov)
		_refresh_inspect())
	xp_row.add_child(xp_add_btn)

	_dev_inspect_box.add_child(HSeparator.new())

	# --- JP controls ---
	var jp_label := Label.new()
	jp_label.text = "JP per class:"
	jp_label.add_theme_font_size_override("font_size", 14)
	_dev_inspect_box.add_child(jp_label)

	for cls_id in _inspected.unlocked_classes:
		var jp_row := HBoxContainer.new()
		_dev_inspect_box.add_child(jp_row)
		var cls_label := Label.new()
		cls_label.text = "%s:" % cls_id.capitalize()
		cls_label.custom_minimum_size.x = 80
		jp_row.add_child(cls_label)
		var jp_spin := SpinBox.new()
		jp_spin.min_value = 0
		jp_spin.max_value = 9999
		jp_spin.value = int(_inspected.jp.get(cls_id, 0))
		jp_spin.size_flags_horizontal = SIZE_EXPAND_FILL
		jp_row.add_child(jp_spin)
		var jp_set_btn := Button.new()
		jp_set_btn.text = "Set"
		var cid: String = cls_id
		jp_set_btn.pressed.connect(func() -> void:
			DevCheatService.set_jp(_inspected, cid, int(jp_spin.value))
			_refresh_inspect())
		jp_row.add_child(jp_set_btn)

	var grant_jp_btn := Button.new()
	grant_jp_btn.text = "Grant 999 JP to All Classes"
	grant_jp_btn.pressed.connect(func() -> void:
		DevCheatService.grant_all_jp(_inspected, 999)
		_refresh_inspect())
	_dev_inspect_box.add_child(grant_jp_btn)

	_dev_inspect_box.add_child(HSeparator.new())

	# --- Class cheats ---
	var unlock_all_btn := Button.new()
	unlock_all_btn.text = "Unlock All Classes"
	unlock_all_btn.pressed.connect(func() -> void:
		DevCheatService.force_unlock_all_classes(_inspected, _class_prov)
		_refresh_inspect())
	_dev_inspect_box.add_child(unlock_all_btn)

	var learn_all_btn := Button.new()
	learn_all_btn.text = "Learn All Abilities"
	learn_all_btn.pressed.connect(func() -> void:
		DevCheatService.force_learn_all_abilities(_inspected, _class_prov)
		_refresh_inspect())
	_dev_inspect_box.add_child(learn_all_btn)

	var reset_downs_btn := Button.new()
	reset_downs_btn.text = "Reset Downs (%d → 0)" % _inspected.downs_this_run
	reset_downs_btn.pressed.connect(func() -> void:
		DevCheatService.reset_downs(_inspected)
		_refresh_inspect())
	_dev_inspect_box.add_child(reset_downs_btn)

	_dev_inspect_box.add_child(HSeparator.new())

	# --- Force equip (bypass class restrictions) ---
	var force_equip_label := Label.new()
	force_equip_label.text = "Force Equip (ignores class):"
	force_equip_label.add_theme_font_size_override("font_size", 14)
	_dev_inspect_box.add_child(force_equip_label)

	var equip_row := HBoxContainer.new()
	_dev_inspect_box.add_child(equip_row)

	var item_option := OptionButton.new()
	item_option.size_flags_horizontal = SIZE_EXPAND_FILL
	var item_ids: Array[String] = []
	for item_id in GameData.all_items():
		var item: ItemData = GameData.get_item(item_id)
		if item != null and not item.slot.is_empty():
			item_option.add_item("%s (%s)" % [item.display_name, item.slot])
			item_ids.append(item_id)
	equip_row.add_child(item_option)

	var force_equip_btn := Button.new()
	force_equip_btn.text = "Force Equip"
	force_equip_btn.pressed.connect(func() -> void:
		var idx: int = item_option.selected
		if idx < 0 or idx >= item_ids.size():
			return
		var sel_item_id: String = item_ids[idx]
		var sel_item: ItemData = GameData.get_item(sel_item_id)
		if sel_item == null:
			return
		DevCheatService.force_equip(_inspected, sel_item.slot, sel_item_id)
		_refresh_inspect())
	equip_row.add_child(force_equip_btn)


# ============================================================
# EMBARK ON RUN
# ============================================================

func _on_embark_run() -> void:
	if _band == null or _band.roster.is_empty():
		return
	SaveManager.save_game()
	MatchData.clear()
	MatchData.active_band = _band
	# Field entire roster for the run
	var ids: Array[String] = []
	for ci in _band.roster:
		ids.append(ci.instance_id)
	MatchData.fielded_ids = ids
	get_tree().change_scene_to_file("res://scenes/run/run_scene.tscn")
