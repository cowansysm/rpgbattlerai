class_name EntitySchema
extends RefCounted
## Declarative column definitions for the CSV content pipeline.
## Each entity type has an ordered list of columns with {name, path, mode, type}.
## The exporter and importer are both driven by these schemas.

enum Mode { SCALAR, DOTTED, JSON }

## All known entity type keys.
const ENTITIES: Array[String] = [
	"abilities", "classes", "items", "characters", "races", "terrain",
]

## Returns the ordered column schema for the given entity type.
## Each column: {name: String, path: String, mode: Mode, type: String}
## type is "str", "int", or "bool".
static func columns_for(entity: String) -> Array[Dictionary]:
	match entity:
		"abilities":  return _abilities()
		"classes":    return _classes()
		"items":      return _items()
		"characters": return _characters()
		"races":      return _races()
		"terrain":    return _terrain()
	return []


## Whether this entity's JSON is a keyed dict (id → props) rather than an array.
static func is_keyed_dict(entity: String) -> bool:
	return entity == "terrain"


# ---------------------------------------------------------------------------
# Column helpers
# ---------------------------------------------------------------------------

static func _col(col_name: String, path: String, mode: Mode, type: String) -> Dictionary:
	return {"name": col_name, "path": path, "mode": mode, "type": type}


static func _stat_columns(prefix: String) -> Array[Dictionary]:
	var cols: Array[Dictionary] = []
	for key in StatKey.all_strings():
		cols.append(_col(prefix + "." + key, prefix + "." + key, Mode.DOTTED, "int"))
	return cols


# ---------------------------------------------------------------------------
# Per-entity schemas
# ---------------------------------------------------------------------------

static func _abilities() -> Array[Dictionary]:
	var cols: Array[Dictionary] = [
		_col("id", "id", Mode.SCALAR, "str"),
		_col("name", "name", Mode.SCALAR, "str"),
		_col("type", "type", Mode.SCALAR, "str"),
		_col("ap", "ap", Mode.SCALAR, "int"),
		_col("wp", "wp", Mode.SCALAR, "int"),
		_col("range", "range", Mode.SCALAR, "int"),
		_col("area.shape", "area.shape", Mode.DOTTED, "str"),
		_col("area.radius", "area.radius", Mode.DOTTED, "int"),
		_col("effect.effect_type", "effect.effect_type", Mode.DOTTED, "str"),
		_col("effect.value", "effect.value", Mode.DOTTED, "int"),
		_col("effect.element", "effect.element", Mode.DOTTED, "str"),
		_col("effect.status_id", "effect.status_id", Mode.DOTTED, "str"),
		_col("effect.duration", "effect.duration", Mode.DOTTED, "int"),
		_col("effect.stat", "effect.stat", Mode.DOTTED, "str"),
		_col("source", "source", Mode.SCALAR, "str"),
	]
	return cols


static func _classes() -> Array[Dictionary]:
	var cols: Array[Dictionary] = [
		_col("id", "id", Mode.SCALAR, "str"),
		_col("name", "name", Mode.SCALAR, "str"),
		_col("abbr", "abbr", Mode.SCALAR, "str"),
		_col("level_max", "level_max", Mode.SCALAR, "int"),
	]
	cols.append_array(_stat_columns("stats"))
	cols.append_array([
		_col("equipment_access", "equipment_access", Mode.JSON, "str"),
		_col("granted_abilities", "granted_abilities", Mode.JSON, "str"),
		_col("required_classes", "required_classes", Mode.JSON, "str"),
		_col("derived_bonuses", "derived_bonuses", Mode.JSON, "str"),
	])
	return cols


static func _items() -> Array[Dictionary]:
	var cols: Array[Dictionary] = [
		_col("id", "id", Mode.SCALAR, "str"),
		_col("name", "name", Mode.SCALAR, "str"),
		_col("slot", "slot", Mode.SCALAR, "str"),
		_col("bp", "bp", Mode.SCALAR, "int"),
		_col("power", "power", Mode.SCALAR, "int"),
		_col("range", "range", Mode.SCALAR, "int"),
		_col("passive", "passive", Mode.JSON, "str"),
		_col("granted_abilities", "granted_abilities", Mode.JSON, "str"),
	]
	return cols


static func _characters() -> Array[Dictionary]:
	var cols: Array[Dictionary] = [
		_col("id", "id", Mode.SCALAR, "str"),
		_col("name", "name", Mode.SCALAR, "str"),
		_col("race", "race", Mode.SCALAR, "str"),
		_col("level", "level", Mode.SCALAR, "int"),
		_col("bp", "bp", Mode.SCALAR, "int"),
	]
	cols.append_array(_stat_columns("stats"))
	cols.append_array([
		_col("classes", "classes", Mode.JSON, "str"),
		_col("equipment", "equipment", Mode.JSON, "str"),
		_col("abilities", "abilities", Mode.JSON, "str"),
	])
	return cols


static func _races() -> Array[Dictionary]:
	var cols: Array[Dictionary] = [
		_col("id", "id", Mode.SCALAR, "str"),
		_col("name", "name", Mode.SCALAR, "str"),
		_col("flavor", "flavor", Mode.SCALAR, "str"),
	]
	cols.append_array(_stat_columns("stats"))
	return cols


static func _terrain() -> Array[Dictionary]:
	var cols: Array[Dictionary] = [
		_col("id", "id", Mode.SCALAR, "str"),
		_col("move_cost", "move_cost", Mode.SCALAR, "int"),
		_col("impassable", "impassable", Mode.SCALAR, "bool"),
		_col("blocks_los", "blocks_los", Mode.SCALAR, "bool"),
		_col("cover", "cover", Mode.SCALAR, "int"),
		_col("los_height", "los_height", Mode.SCALAR, "int"),
		_col("damage_on_enter", "damage_on_enter", Mode.SCALAR, "int"),
		_col("damage_per_turn", "damage_per_turn", Mode.SCALAR, "int"),
		_col("is_water", "is_water", Mode.SCALAR, "bool"),
		_col("status_on_enter.status_id", "status_on_enter.status_id", Mode.DOTTED, "str"),
		_col("status_on_enter.duration", "status_on_enter.duration", Mode.DOTTED, "int"),
		_col("occupant_modifiers", "occupant_modifiers", Mode.JSON, "str"),
		_col("tags", "tags", Mode.JSON, "str"),
	]
	return cols
