class_name IconAtlasGenerator
extends RefCounted
## Generates the symbol_atlas.png by drawing all icons procedurally.
## Reuses drawing patterns from PawnFactory adapted for 64×64 atlas cells.
## Spec reference: phase9-spec.md §6

const CELL := 64
const ATLAS_SIZE := 512
const HALF := CELL / 2  # 32 — cell center offset

# Fill colors for each category
const SPELL_FILL := Color(0.6, 0.3, 0.8, 0.8)
const SKILL_FILL := Color(0.8, 0.6, 0.2, 0.8)
const WEAPON_FILL := Color(0.5, 0.5, 0.55, 0.8)
const EQUIP_FILL := Color(0.55, 0.4, 0.25, 0.8)
const STATUS_FILL := Color(0.7, 0.2, 0.2, 0.8)
const NEUTRAL_FILL := Color(0.6, 0.6, 0.6, 0.8)  # Race+class identity
const ACTION_FILL := Color(0.35, 0.35, 0.4, 0.8)

# Element tint overrides for spells
const ELEMENT_TINTS := {
	"fire": Color(0.85, 0.35, 0.15, 0.8),
	"ice": Color(0.2, 0.55, 0.85, 0.8),
	"lightning": Color(0.85, 0.8, 0.2, 0.8),
	"healing": Color(0.25, 0.7, 0.35, 0.8),
}

# Icon-to-element mapping for spell tinting
const SPELL_ELEMENTS := {
	"fire_1": "fire", "fire_2": "fire",
	"ice_1": "ice", "thunder_1": "lightning",
	"cure_1": "healing", "cure_2": "healing",
	"shield_1": "",  # Base purple
}

# Layout: icon_id → {col, row, category, draw_func}
# Row 0: Spells, Row 1: Skills, Row 2: Weapons, Row 3: Equipment
# Row 4: Status, Row 5: Actions+fallback, Row 6: Race+class
const LAYOUT := {
	# Spells (row 0)
	"fire_1":          {"col": 0, "row": 0, "cat": "spell", "icon": "flame_small"},
	"fire_2":          {"col": 1, "row": 0, "cat": "spell", "icon": "flame_large"},
	"ice_1":           {"col": 2, "row": 0, "cat": "spell", "icon": "snowflake"},
	"thunder_1":       {"col": 3, "row": 0, "cat": "spell", "icon": "bolt"},
	"cure_1":          {"col": 4, "row": 0, "cat": "spell", "icon": "cross"},
	"cure_2":          {"col": 5, "row": 0, "cat": "spell", "icon": "cross_thick"},
	"shield_1":        {"col": 6, "row": 0, "cat": "spell", "icon": "chevron"},
	# Skills (row 1)
	"power_strike":    {"col": 0, "row": 1, "cat": "skill", "icon": "slash_impact"},
	"backstab":        {"col": 1, "row": 1, "cat": "skill", "icon": "dagger_thrust"},
	"reckless_swing":  {"col": 2, "row": 1, "cat": "skill", "icon": "wide_arc"},
	"rage":            {"col": 3, "row": 1, "cat": "skill", "icon": "fist"},
	"inspire":         {"col": 4, "row": 1, "cat": "skill", "icon": "horn"},
	"lullaby":         {"col": 5, "row": 1, "cat": "skill", "icon": "crescent_zz"},
	# Weapons (row 2)
	"sword":           {"col": 0, "row": 2, "cat": "weapon", "icon": "sword"},
	"daggers":         {"col": 1, "row": 2, "cat": "weapon", "icon": "crossed_daggers"},
	"bow":             {"col": 2, "row": 2, "cat": "weapon", "icon": "bow"},
	"staff":           {"col": 3, "row": 2, "cat": "weapon", "icon": "staff"},
	"rapier":          {"col": 4, "row": 2, "cat": "weapon", "icon": "rapier"},
	"greataxe":        {"col": 5, "row": 2, "cat": "weapon", "icon": "axe"},
	"sling":           {"col": 6, "row": 2, "cat": "weapon", "icon": "sling"},
	# Equipment (row 3)
	"light_armor":     {"col": 0, "row": 3, "cat": "equip", "icon": "chain"},
	"medium_armor":    {"col": 1, "row": 3, "cat": "equip", "icon": "breastplate"},
	"shield":          {"col": 2, "row": 3, "cat": "equip", "icon": "shield_front"},
	"bracer_of_accuracy": {"col": 3, "row": 3, "cat": "equip", "icon": "wristguard"},
	"smoke_bomb_pouch":{"col": 4, "row": 3, "cat": "equip", "icon": "pouch"},
	# Status effects (row 4)
	"sleep":           {"col": 0, "row": 4, "cat": "status", "icon": "crescent_zz"},
	"blind":           {"col": 1, "row": 4, "cat": "status", "icon": "eye_crossed"},
	"defend":          {"col": 2, "row": 4, "cat": "status", "icon": "shield_up"},
	# Action buttons (row 5)
	"action_move":     {"col": 0, "row": 5, "cat": "action", "icon": "boot"},
	"action_attack":   {"col": 1, "row": 5, "cat": "action", "icon": "sword_strike"},
	"action_ability":  {"col": 2, "row": 5, "cat": "action", "icon": "starburst"},
	"action_item":     {"col": 3, "row": 5, "cat": "action", "icon": "pouch"},
	"action_defend":   {"col": 4, "row": 5, "cat": "action", "icon": "shield_front"},
	"action_wait":     {"col": 5, "row": 5, "cat": "action", "icon": "hourglass"},
	"_fallback":       {"col": 6, "row": 5, "cat": "action", "icon": "question"},
}

# Race+class identity (row 6)
const RACE_CLASS_LAYOUT := {
	"human_fighter":       {"col": 0, "row": 6, "race": "human", "class": "fighter"},
	"human_archer":        {"col": 1, "row": 6, "race": "human", "class": "archer"},
	"human_rogue":         {"col": 2, "row": 6, "race": "human", "class": "rogue"},
	"human_bard":          {"col": 3, "row": 6, "race": "human", "class": "bard"},
	"elf_black_mage":      {"col": 4, "row": 6, "race": "elf", "class": "black_mage"},
	"elf_red_mage":        {"col": 5, "row": 6, "race": "elf", "class": "red_mage"},
	"halfling_white_mage": {"col": 6, "row": 6, "race": "halfling", "class": "white_mage"},
	"dwarf_barbarian":     {"col": 7, "row": 6, "race": "dwarf", "class": "barbarian"},
}


static func generate() -> Image:
	var img := Image.create(ATLAS_SIZE, ATLAS_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Draw category icons (rows 0-5)
	for icon_id in LAYOUT:
		var info: Dictionary = LAYOUT[icon_id]
		var ox: int = info["col"] * CELL
		var oy: int = info["row"] * CELL
		var cat: String = info["cat"]
		var icon_name: String = info["icon"]

		# Draw frame
		var fill := _get_fill_color(icon_id, cat)
		_draw_category_frame(img, ox, oy, cat, fill)

		# Draw interior icon
		_draw_interior_icon(img, ox, oy, icon_name, Color.WHITE)

	# Draw race+class identity icons (row 6)
	for char_id in RACE_CLASS_LAYOUT:
		var info: Dictionary = RACE_CLASS_LAYOUT[char_id]
		var ox: int = info["col"] * CELL
		var oy: int = info["row"] * CELL
		_draw_race_class_cell(img, ox, oy, info["race"], info["class"])

	return img


static func save(path: String) -> void:
	var img := generate()
	var dir := path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(path)


# --- Fill color helpers ---

static func _get_fill_color(icon_id: String, cat: String) -> Color:
	if cat == "spell":
		var element: String = SPELL_ELEMENTS.get(icon_id, "")
		if not element.is_empty() and element in ELEMENT_TINTS:
			return ELEMENT_TINTS[element]
		return SPELL_FILL
	match cat:
		"skill": return SKILL_FILL
		"weapon": return WEAPON_FILL
		"equip": return EQUIP_FILL
		"status": return STATUS_FILL
		"action": return ACTION_FILL
	return NEUTRAL_FILL


# --- Category frame dispatch ---

static func _draw_category_frame(img: Image, ox: int, oy: int,
		cat: String, fill: Color) -> void:
	match cat:
		"spell":  _draw_spell_frame(img, ox, oy, fill, Color.WHITE)
		"skill":  _draw_skill_frame(img, ox, oy, fill, Color.WHITE)
		"weapon": _draw_weapon_frame(img, ox, oy, fill, Color.WHITE)
		"equip":  _draw_equipment_frame(img, ox, oy, fill, Color.WHITE)
		"status": _draw_status_frame(img, ox, oy, fill, Color.WHITE)
		"action": _draw_action_frame(img, ox, oy, fill, Color.WHITE)


# --- Dual-overlapping-geometry category frames ---

static func _draw_spell_frame(img: Image, ox: int, oy: int,
		fill: Color, outline: Color) -> void:
	## Upward triangle + circle overlap
	var cx := ox + HALF
	var cy := oy + HALF
	# Triangle: top, bottom-left, bottom-right
	var tri: Array[Vector2i] = [
		Vector2i(cx, cy - 26),
		Vector2i(cx - 23, cy + 20),
		Vector2i(cx + 23, cy + 20),
	]
	_fill_polygon(img, tri, fill)
	_draw_circle_filled(img, cx, cy + 2, 15, fill)
	# Outlines
	_outline_polygon(img, tri, outline, 2)
	_outline_circle(img, cx, cy + 2, 15, outline, 2)


static func _draw_skill_frame(img: Image, ox: int, oy: int,
		fill: Color, outline: Color) -> void:
	## Pentagon + inverted pentagon overlap
	var cx := ox + HALF
	var cy := oy + HALF
	var pent_up := _regular_polygon(cx, cy, 22, 5, -PI / 2.0)
	var pent_dn := _regular_polygon(cx, cy, 16, 5, PI / 2.0)
	_fill_polygon(img, pent_up, fill)
	_fill_polygon(img, pent_dn, fill)
	_outline_polygon(img, pent_up, outline, 2)
	_outline_polygon(img, pent_dn, outline, 2)


static func _draw_weapon_frame(img: Image, ox: int, oy: int,
		fill: Color, outline: Color) -> void:
	## Hexagon + 90°-rotated square (diamond) overlap
	var cx := ox + HALF
	var cy := oy + HALF
	var hex := _regular_polygon(cx, cy, 22, 6, 0.0)
	# Diamond = square rotated 45°
	var diamond := _regular_polygon(cx, cy, 18, 4, PI / 4.0)
	_fill_polygon(img, hex, fill)
	_fill_polygon(img, diamond, fill)
	_outline_polygon(img, hex, outline, 2)
	_outline_polygon(img, diamond, outline, 2)


static func _draw_equipment_frame(img: Image, ox: int, oy: int,
		fill: Color, outline: Color) -> void:
	## Hexagon + circle overlap
	var cx := ox + HALF
	var cy := oy + HALF
	var hex := _regular_polygon(cx, cy, 22, 6, 0.0)
	_fill_polygon(img, hex, fill)
	_draw_circle_filled(img, cx, cy, 16, fill)
	_outline_polygon(img, hex, outline, 2)
	_outline_circle(img, cx, cy, 16, outline, 2)


static func _draw_status_frame(img: Image, ox: int, oy: int,
		fill: Color, outline: Color) -> void:
	## Inverted triangle + square overlap
	var cx := ox + HALF
	var cy := oy + HALF
	# Inverted triangle: top-left, top-right, bottom-center
	var tri: Array[Vector2i] = [
		Vector2i(cx - 23, cy - 18),
		Vector2i(cx + 23, cy - 18),
		Vector2i(cx, cy + 24),
	]
	# Square
	var sq_half := 14
	var sq: Array[Vector2i] = [
		Vector2i(cx - sq_half, cy - sq_half),
		Vector2i(cx + sq_half, cy - sq_half),
		Vector2i(cx + sq_half, cy + sq_half),
		Vector2i(cx - sq_half, cy + sq_half),
	]
	_fill_polygon(img, tri, fill)
	_fill_polygon(img, sq, fill)
	_outline_polygon(img, tri, outline, 2)
	_outline_polygon(img, sq, outline, 2)


static func _draw_action_frame(img: Image, ox: int, oy: int,
		fill: Color, outline: Color) -> void:
	## Simple circle frame for action buttons
	var cx := ox + HALF
	var cy := oy + HALF
	_draw_circle_filled(img, cx, cy, 26, fill)
	_outline_circle(img, cx, cy, 26, outline, 2)


# --- Race+class identity cells ---

static func _draw_race_class_cell(img: Image, ox: int, oy: int,
		race: String, job_class: String) -> void:
	## Draws race frame + class icon at 64×64 scale.
	## Uses neutral grey fill; team tinting applied at runtime.
	var cx := ox + HALF
	var cy := oy + HALF
	var fill := NEUTRAL_FILL
	var outline := Color.WHITE

	# Race frame (single geometry)
	match race:
		"human":
			_fill_rect(img, cx - 22, cy - 22, cx + 22, cy + 22, fill)
			_outline_rect(img, cx - 22, cy - 22, cx + 22, cy + 22, outline, 2)
		"elf":
			var diamond := _regular_polygon(cx, cy, 24, 4, PI / 4.0)
			_fill_polygon(img, diamond, fill)
			_outline_polygon(img, diamond, outline, 2)
		"halfling":
			_draw_circle_filled(img, cx, cy, 22, fill)
			_outline_circle(img, cx, cy, 22, outline, 2)
		"dwarf":
			var hex := _regular_polygon(cx, cy, 23, 6, 0.0)
			_fill_polygon(img, hex, fill)
			_outline_polygon(img, hex, outline, 2)
		_:
			_fill_rect(img, cx - 22, cy - 22, cx + 22, cy + 22, fill)
			_outline_rect(img, cx - 22, cy - 22, cx + 22, cy + 22, outline, 2)

	# Class icon (scaled down from PawnFactory's 128px to 64px — halved sizes)
	var s := 12  # icon half-size (was 24 at 128px)
	var icon_color := Color.WHITE
	match job_class:
		"fighter":
			_draw_thick_line(img, cx - s, cy - s, cx + s, cy + s, icon_color, 2)
			_draw_thick_line(img, cx + s, cy - s, cx - s, cy + s, icon_color, 2)
		"archer":
			_draw_thick_line(img, cx, cy - s, cx, cy + s, icon_color, 2)
			_draw_thick_line(img, cx - s / 2, cy - s / 2, cx, cy - s, icon_color, 2)
			_draw_thick_line(img, cx + s / 2, cy - s / 2, cx, cy - s, icon_color, 2)
		"rogue":
			_draw_thick_line(img, cx - s, cy + s, cx + s, cy - s, icon_color, 2)
		"barbarian":
			_draw_thick_line(img, cx, cy - s, cx, cy + s, icon_color, 2)
			_draw_thick_line(img, cx - s, cy - s / 3, cx + s, cy - s / 3, icon_color, 2)
			_draw_thick_line(img, cx - s, cy + s / 3, cx + s, cy + s / 3, icon_color, 2)
		"black_mage":
			_draw_thick_line(img, cx + s / 3, cy - s, cx - s / 4, cy - 1, icon_color, 2)
			_draw_thick_line(img, cx - s / 4, cy - 1, cx + s / 4, cy + 1, icon_color, 2)
			_draw_thick_line(img, cx + s / 4, cy + 1, cx - s / 3, cy + s, icon_color, 2)
		"white_mage":
			_draw_thick_line(img, cx - s, cy, cx + s, cy, icon_color, 2)
			_draw_thick_line(img, cx, cy - s, cx, cy + s, icon_color, 2)
		"red_mage":
			_draw_thick_line(img, cx - s, cy - s, cx + s, cy - s, icon_color, 2)
			_draw_thick_line(img, cx - s, cy - s, cx + s, cy + s, icon_color, 2)
			_draw_thick_line(img, cx + s, cy - s, cx - s, cy + s, icon_color, 2)
			_draw_thick_line(img, cx - s, cy + s, cx + s, cy + s, icon_color, 2)
		"bard":
			for x in range(cx - s, cx + s + 1):
				var t := float(x - cx) / float(s)
				var wave_y := int(round(sin(t * PI * 2.0) * float(s) * 0.4))
				_safe_pixel(img, x, cy + wave_y, icon_color)
				_safe_pixel(img, x, cy + wave_y + 1, icon_color)
		_:
			_draw_circle_filled(img, cx, cy, 4, icon_color)


# --- Interior icon dispatch ---

static func _draw_interior_icon(img: Image, ox: int, oy: int,
		icon_name: String, color: Color) -> void:
	var cx := ox + HALF
	var cy := oy + HALF
	match icon_name:
		"flame_small": _draw_icon_flame(img, cx, cy, color, false)
		"flame_large": _draw_icon_flame(img, cx, cy, color, true)
		"snowflake":   _draw_icon_snowflake(img, cx, cy, color)
		"bolt":        _draw_icon_bolt(img, cx, cy, color)
		"cross":       _draw_icon_cross(img, cx, cy, color, false)
		"cross_thick": _draw_icon_cross(img, cx, cy, color, true)
		"chevron":     _draw_icon_chevron(img, cx, cy, color)
		"slash_impact":_draw_icon_slash_impact(img, cx, cy, color)
		"dagger_thrust":_draw_icon_dagger(img, cx, cy, color)
		"wide_arc":    _draw_icon_arc(img, cx, cy, color)
		"fist":        _draw_icon_fist(img, cx, cy, color)
		"horn":        _draw_icon_horn(img, cx, cy, color)
		"crescent_zz": _draw_icon_moon_zz(img, cx, cy, color)
		"sword":       _draw_icon_sword(img, cx, cy, color)
		"crossed_daggers": _draw_icon_crossed_daggers(img, cx, cy, color)
		"bow":         _draw_icon_bow(img, cx, cy, color)
		"staff":       _draw_icon_staff(img, cx, cy, color)
		"rapier":      _draw_icon_rapier(img, cx, cy, color)
		"axe":         _draw_icon_axe(img, cx, cy, color)
		"sling":       _draw_icon_sling(img, cx, cy, color)
		"chain":       _draw_icon_chain(img, cx, cy, color)
		"breastplate": _draw_icon_breastplate(img, cx, cy, color)
		"shield_front":_draw_icon_shield(img, cx, cy, color)
		"wristguard":  _draw_icon_wristguard(img, cx, cy, color)
		"pouch":       _draw_icon_pouch(img, cx, cy, color)
		"eye_crossed": _draw_icon_eye_crossed(img, cx, cy, color)
		"shield_up":   _draw_icon_shield_up(img, cx, cy, color)
		"boot":        _draw_icon_boot(img, cx, cy, color)
		"sword_strike":_draw_icon_sword_strike(img, cx, cy, color)
		"starburst":   _draw_icon_starburst(img, cx, cy, color)
		"hourglass":   _draw_icon_hourglass(img, cx, cy, color)
		"question":    _draw_icon_question(img, cx, cy, color)


# --- Interior icon implementations ---

static func _draw_icon_flame(img: Image, cx: int, cy: int,
		color: Color, large: bool) -> void:
	var h := 14 if large else 10
	var w := 6 if large else 4
	# Teardrop flame shape
	_draw_thick_line(img, cx, cy - h, cx - w, cy + h / 2, color, 2)
	_draw_thick_line(img, cx, cy - h, cx + w, cy + h / 2, color, 2)
	_draw_thick_line(img, cx - w, cy + h / 2, cx, cy + h, color, 2)
	_draw_thick_line(img, cx + w, cy + h / 2, cx, cy + h, color, 2)
	# Inner flicker
	if large:
		_draw_thick_line(img, cx, cy - 6, cx - 2, cy + 2, color, 1)
		_draw_thick_line(img, cx, cy - 6, cx + 2, cy + 2, color, 1)


static func _draw_icon_snowflake(img: Image, cx: int, cy: int,
		color: Color) -> void:
	var r := 10
	# 3 crossing lines (6 arms)
	for i in range(3):
		var angle := PI / 3.0 * float(i)
		var dx := int(round(cos(angle) * r))
		var dy := int(round(sin(angle) * r))
		_draw_thick_line(img, cx - dx, cy - dy, cx + dx, cy + dy, color, 1)
		# Small ticks at ends
		var tx := int(round(cos(angle + PI / 6.0) * 3))
		var ty := int(round(sin(angle + PI / 6.0) * 3))
		_safe_pixel(img, cx + dx + tx, cy + dy + ty, color)
		_safe_pixel(img, cx - dx - tx, cy - dy - ty, color)


static func _draw_icon_bolt(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Zigzag lightning bolt
	_draw_thick_line(img, cx + 3, cy - 12, cx - 2, cy - 2, color, 2)
	_draw_thick_line(img, cx - 2, cy - 2, cx + 3, cy + 2, color, 2)
	_draw_thick_line(img, cx + 3, cy + 2, cx - 3, cy + 12, color, 2)


static func _draw_icon_cross(img: Image, cx: int, cy: int,
		color: Color, thick: bool) -> void:
	var s := 10
	var t := 3 if thick else 2
	_draw_thick_line(img, cx - s, cy, cx + s, cy, color, t)
	_draw_thick_line(img, cx, cy - s, cx, cy + s, color, t)
	if thick:
		# Radiating dots
		for i in range(4):
			var angle := PI / 4.0 + PI / 2.0 * float(i)
			var px := cx + int(round(cos(angle) * 7))
			var py := cy + int(round(sin(angle) * 7))
			_safe_pixel(img, px, py, color)


static func _draw_icon_chevron(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Upward chevron ^
	_draw_thick_line(img, cx - 10, cy + 4, cx, cy - 8, color, 2)
	_draw_thick_line(img, cx, cy - 8, cx + 10, cy + 4, color, 2)


static func _draw_icon_slash_impact(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Diagonal slash with impact arc
	_draw_thick_line(img, cx + 8, cy - 10, cx - 8, cy + 10, color, 2)
	# Impact arc at bottom
	for a in range(-30, 31):
		var angle := deg_to_rad(float(a) - 45.0)
		var px := cx - 6 + int(round(cos(angle) * 6))
		var py := cy + 8 + int(round(sin(angle) * 6))
		_safe_pixel(img, px, py, color)


static func _draw_icon_dagger(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Dagger pointing right with motion lines
	_draw_thick_line(img, cx - 8, cy, cx + 10, cy, color, 2)
	# Crossguard
	_draw_thick_line(img, cx - 2, cy - 4, cx - 2, cy + 4, color, 2)
	# Motion lines
	_draw_thick_line(img, cx - 12, cy - 3, cx - 8, cy - 3, color, 1)
	_draw_thick_line(img, cx - 12, cy + 3, cx - 8, cy + 3, color, 1)


static func _draw_icon_arc(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Wide quarter-circle sweep
	for a in range(45, 136):
		var angle := deg_to_rad(float(a))
		for t in range(2):
			var r := 10 + t
			var px := cx + int(round(cos(angle) * r))
			var py := cy - int(round(sin(angle) * r))
			_safe_pixel(img, px, py, color)


static func _draw_icon_fist(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Simple fist silhouette (filled rectangle with bumps on top)
	_fill_rect(img, cx - 6, cy - 4, cx + 6, cy + 8, color)
	# Finger bumps
	for i in range(4):
		var fx := cx - 5 + i * 3
		_fill_rect(img, fx, cy - 7, fx + 2, cy - 4, color)


static func _draw_icon_horn(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Horn/bugle pointing right
	_draw_thick_line(img, cx - 8, cy, cx + 4, cy - 4, color, 2)
	_draw_thick_line(img, cx + 4, cy - 4, cx + 10, cy, color, 2)
	_draw_thick_line(img, cx + 4, cy - 4, cx + 4, cy + 2, color, 2)
	# Bell
	_draw_thick_line(img, cx + 10, cy - 3, cx + 10, cy + 3, color, 2)
	# Sound lines
	_safe_pixel(img, cx + 13, cy - 2, color)
	_safe_pixel(img, cx + 14, cy, color)
	_safe_pixel(img, cx + 13, cy + 2, color)


static func _draw_icon_moon_zz(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Crescent moon with Zs
	for a in range(360):
		var angle := deg_to_rad(float(a))
		var r := 8
		var px := cx - 4 + int(round(cos(angle) * r))
		var py := cy + int(round(sin(angle) * r))
		_safe_pixel(img, px, py, color)
	# Cut out inner circle to make crescent
	# (just draw the crescent arc instead)
	_draw_circle_filled(img, cx - 1, cy, 5, Color(0, 0, 0, 0))
	# Z letters
	_draw_thick_line(img, cx + 6, cy - 8, cx + 12, cy - 8, color, 1)
	_draw_thick_line(img, cx + 12, cy - 8, cx + 6, cy - 3, color, 1)
	_draw_thick_line(img, cx + 6, cy - 3, cx + 12, cy - 3, color, 1)


static func _draw_icon_sword(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Vertical blade with crossguard
	_draw_thick_line(img, cx, cy - 12, cx, cy + 8, color, 2)
	# Crossguard
	_draw_thick_line(img, cx - 6, cy + 2, cx + 6, cy + 2, color, 2)
	# Pommel
	_draw_circle_filled(img, cx, cy + 10, 2, color)


static func _draw_icon_crossed_daggers(img: Image, cx: int, cy: int,
		color: Color) -> void:
	_draw_thick_line(img, cx - 8, cy - 8, cx + 8, cy + 8, color, 2)
	_draw_thick_line(img, cx + 8, cy - 8, cx - 8, cy + 8, color, 2)


static func _draw_icon_bow(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Curved bow
	for a in range(-60, 61):
		var angle := deg_to_rad(float(a) - 90.0)
		var px := cx - 4 + int(round(cos(angle) * 12))
		var py := cy + int(round(sin(angle) * 12))
		_safe_pixel(img, px, py, color)
		_safe_pixel(img, px + 1, py, color)
	# String
	_draw_thick_line(img, cx - 4, cy - 11, cx - 4, cy + 11, color, 1)
	# Arrow
	_draw_thick_line(img, cx - 4, cy, cx + 12, cy, color, 1)
	_draw_thick_line(img, cx + 8, cy - 3, cx + 12, cy, color, 1)
	_draw_thick_line(img, cx + 8, cy + 3, cx + 12, cy, color, 1)


static func _draw_icon_staff(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Vertical line with circle at top
	_draw_thick_line(img, cx, cy - 8, cx, cy + 12, color, 2)
	_outline_circle(img, cx, cy - 10, 4, color, 1)


static func _draw_icon_rapier(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Thin diagonal blade with circular guard
	_draw_thick_line(img, cx - 6, cy + 10, cx + 8, cy - 10, color, 1)
	_outline_circle(img, cx - 1, cy + 3, 4, color, 1)


static func _draw_icon_axe(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Vertical handle
	_draw_thick_line(img, cx, cy - 12, cx, cy + 10, color, 2)
	# Curved blade head
	for a in range(-60, 61):
		var angle := deg_to_rad(float(a))
		for t in range(2):
			var r := 8 + t
			var px := cx + int(round(cos(angle) * r))
			var py := cy - 6 + int(round(sin(angle) * r))
			_safe_pixel(img, px, py, color)


static func _draw_icon_sling(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Curved sling
	for a in range(-45, 46):
		var angle := deg_to_rad(float(a) + 90.0)
		var px := cx + int(round(cos(angle) * 10))
		var py := cy + int(round(sin(angle) * 10))
		_safe_pixel(img, px, py, color)
		_safe_pixel(img, px, py + 1, color)
	# Stone
	_draw_circle_filled(img, cx, cy - 10, 3, color)


static func _draw_icon_chain(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Three interlocking circles
	_outline_circle(img, cx - 6, cy, 5, color, 1)
	_outline_circle(img, cx + 6, cy, 5, color, 1)
	_outline_circle(img, cx, cy - 4, 5, color, 1)


static func _draw_icon_breastplate(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Trapezoid torso
	_draw_thick_line(img, cx - 8, cy - 8, cx + 8, cy - 8, color, 2)  # shoulders
	_draw_thick_line(img, cx - 8, cy - 8, cx - 6, cy + 8, color, 2)  # left side
	_draw_thick_line(img, cx + 8, cy - 8, cx + 6, cy + 8, color, 2)  # right side
	_draw_thick_line(img, cx - 6, cy + 8, cx + 6, cy + 8, color, 2)  # bottom


static func _draw_icon_shield(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Shield silhouette (rounded top, pointed bottom)
	_draw_thick_line(img, cx - 8, cy - 8, cx + 8, cy - 8, color, 2)  # top
	_draw_thick_line(img, cx - 8, cy - 8, cx - 8, cy + 2, color, 2)  # left
	_draw_thick_line(img, cx + 8, cy - 8, cx + 8, cy + 2, color, 2)  # right
	_draw_thick_line(img, cx - 8, cy + 2, cx, cy + 10, color, 2)    # bottom-left
	_draw_thick_line(img, cx + 8, cy + 2, cx, cy + 10, color, 2)    # bottom-right


static func _draw_icon_wristguard(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Rectangle band with crosshair dot
	_outline_rect(img, cx - 8, cy - 4, cx + 8, cy + 4, color, 2)
	_draw_circle_filled(img, cx, cy, 2, color)


static func _draw_icon_pouch(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Bag shape with drawstring top
	_draw_thick_line(img, cx - 6, cy - 4, cx + 6, cy - 4, color, 2)  # top
	_draw_thick_line(img, cx - 6, cy - 4, cx - 8, cy + 6, color, 2)  # left
	_draw_thick_line(img, cx + 6, cy - 4, cx + 8, cy + 6, color, 2)  # right
	_draw_thick_line(img, cx - 8, cy + 6, cx + 8, cy + 6, color, 2)  # bottom
	# Drawstring
	_draw_thick_line(img, cx - 3, cy - 4, cx, cy - 8, color, 1)
	_draw_thick_line(img, cx + 3, cy - 4, cx, cy - 8, color, 1)


static func _draw_icon_eye_crossed(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Eye oval
	_draw_thick_line(img, cx - 10, cy, cx - 4, cy - 5, color, 1)
	_draw_thick_line(img, cx - 4, cy - 5, cx + 4, cy - 5, color, 1)
	_draw_thick_line(img, cx + 4, cy - 5, cx + 10, cy, color, 1)
	_draw_thick_line(img, cx + 10, cy, cx + 4, cy + 5, color, 1)
	_draw_thick_line(img, cx + 4, cy + 5, cx - 4, cy + 5, color, 1)
	_draw_thick_line(img, cx - 4, cy + 5, cx - 10, cy, color, 1)
	# Pupil
	_draw_circle_filled(img, cx, cy, 2, color)
	# Diagonal cross-out line
	_draw_thick_line(img, cx - 10, cy + 6, cx + 10, cy - 6, color, 2)


static func _draw_icon_shield_up(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Small shield with upward arrow
	_draw_icon_shield(img, cx - 2, cy + 2, color)
	# Upward arrow
	_draw_thick_line(img, cx + 6, cy - 2, cx + 6, cy - 10, color, 1)
	_draw_thick_line(img, cx + 3, cy - 7, cx + 6, cy - 10, color, 1)
	_draw_thick_line(img, cx + 9, cy - 7, cx + 6, cy - 10, color, 1)


static func _draw_icon_boot(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Boot silhouette
	_draw_thick_line(img, cx - 2, cy - 10, cx - 2, cy + 4, color, 2)  # leg
	_draw_thick_line(img, cx - 2, cy + 4, cx + 8, cy + 4, color, 2)   # sole
	_draw_thick_line(img, cx + 8, cy + 4, cx + 8, cy, color, 2)       # toe
	_draw_thick_line(img, cx + 8, cy, cx + 2, cy, color, 2)           # top of toe


static func _draw_icon_sword_strike(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Sword with impact flash
	_draw_icon_sword(img, cx - 2, cy, color)
	# Impact lines
	_safe_pixel(img, cx + 6, cy - 4, color)
	_safe_pixel(img, cx + 8, cy - 6, color)
	_safe_pixel(img, cx + 7, cy - 2, color)
	_safe_pixel(img, cx + 9, cy - 3, color)


static func _draw_icon_starburst(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# 8-pointed starburst
	for i in range(8):
		var angle := PI / 4.0 * float(i)
		var dx := int(round(cos(angle) * 10))
		var dy := int(round(sin(angle) * 10))
		_draw_thick_line(img, cx, cy, cx + dx, cy + dy, color, 1)


static func _draw_icon_hourglass(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Hourglass
	_draw_thick_line(img, cx - 8, cy - 10, cx + 8, cy - 10, color, 2)  # top
	_draw_thick_line(img, cx - 8, cy - 10, cx + 8, cy + 10, color, 1)  # left diagonal
	_draw_thick_line(img, cx + 8, cy - 10, cx - 8, cy + 10, color, 1)  # right diagonal
	_draw_thick_line(img, cx - 8, cy + 10, cx + 8, cy + 10, color, 2)  # bottom


static func _draw_icon_question(img: Image, cx: int, cy: int,
		color: Color) -> void:
	# Question mark "?"
	# Top curve
	for a in range(-90, 91):
		var angle := deg_to_rad(float(a))
		var px := cx + int(round(cos(angle) * 6))
		var py := cy - 6 + int(round(sin(angle) * 6))
		_safe_pixel(img, px, py, color)
		_safe_pixel(img, px + 1, py, color)
	# Stem
	_draw_thick_line(img, cx, cy - 1, cx, cy + 4, color, 2)
	# Dot
	_draw_circle_filled(img, cx, cy + 8, 2, color)


# --- Drawing primitives ---

static func _safe_pixel(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, color)


static func _draw_thick_line(img: Image, x0: int, y0: int, x1: int, y1: int,
		color: Color, thickness: int) -> void:
	for t in range(thickness):
		var offset := t - thickness / 2
		_draw_line_bresenham(img, x0, y0 + offset, x1, y1 + offset, color)
		if thickness > 1:
			_draw_line_bresenham(img, x0 + offset, y0, x1 + offset, y1, color)


static func _draw_line_bresenham(img: Image, x0: int, y0: int,
		x1: int, y1: int, color: Color) -> void:
	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx - dy
	var x := x0
	var y := y0
	while true:
		_safe_pixel(img, x, y, color)
		if x == x1 and y == y1:
			break
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy


static func _draw_circle_filled(img: Image, cx: int, cy: int,
		radius: int, color: Color) -> void:
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius:
				_safe_pixel(img, x, y, color)


static func _outline_circle(img: Image, cx: int, cy: int, radius: int,
		color: Color, thickness: int) -> void:
	for a in range(360):
		var angle := deg_to_rad(float(a))
		for t in range(thickness):
			var r := radius + t
			var px := cx + int(round(cos(angle) * r))
			var py := cy + int(round(sin(angle) * r))
			_safe_pixel(img, px, py, color)


static func _fill_rect(img: Image, x0: int, y0: int, x1: int, y1: int,
		color: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_safe_pixel(img, x, y, color)


static func _outline_rect(img: Image, x0: int, y0: int, x1: int, y1: int,
		color: Color, thickness: int) -> void:
	for t in range(thickness):
		for x in range(x0 - t, x1 + t + 1):
			_safe_pixel(img, x, y0 - t, color)
			_safe_pixel(img, x, y1 + t, color)
		for y in range(y0 - t, y1 + t + 1):
			_safe_pixel(img, x0 - t, y, color)
			_safe_pixel(img, x1 + t, y, color)


static func _fill_polygon(img: Image, verts: Array[Vector2i], color: Color) -> void:
	if verts.is_empty():
		return
	var min_y := verts[0].y
	var max_y := verts[0].y
	var min_x := verts[0].x
	var max_x := verts[0].x
	for v in verts:
		min_y = mini(min_y, v.y)
		max_y = maxi(max_y, v.y)
		min_x = mini(min_x, v.x)
		max_x = maxi(max_x, v.x)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if _point_in_polygon(x, y, verts):
				_safe_pixel(img, x, y, color)


static func _outline_polygon(img: Image, verts: Array[Vector2i],
		color: Color, thickness: int) -> void:
	var n := verts.size()
	for i in range(n):
		var a := verts[i]
		var b := verts[(i + 1) % n]
		_draw_thick_line(img, a.x, a.y, b.x, b.y, color, thickness)


static func _point_in_polygon(px: int, py: int, verts: Array[Vector2i]) -> bool:
	var inside := false
	var n := verts.size()
	var j := n - 1
	for i in range(n):
		var vi := verts[i]
		var vj := verts[j]
		if ((vi.y > py) != (vj.y > py)) and \
			(px < (vj.x - vi.x) * (py - vi.y) / (vj.y - vi.y) + vi.x):
			inside = not inside
		j = i
	return inside


static func _regular_polygon(cx: int, cy: int, radius: int,
		sides: int, start_angle: float) -> Array[Vector2i]:
	var verts: Array[Vector2i] = []
	for i in range(sides):
		var angle := start_angle + TAU / float(sides) * float(i)
		verts.append(Vector2i(
			cx + int(round(cos(angle) * radius)),
			cy + int(round(sin(angle) * radius))))
	return verts
