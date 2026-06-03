# Phase 1 — Implementation Plan

**Source spec:** `phase1-spec.md`
**Builds on:** `phase0-implementation-plan.md` (pipeline skeleton)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Reference model:** Lazy lookup by ID · **Derived stats:** computed at load · **Validation:** runtime + GUT
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-05-29
**Revised:** 2026-06-02 — integration-test gaps patched; Phase 0 carry-over corrected; clarified decisions applied.

---

## How to use this plan

Seven **work groups** (A–G). Within a group, tasks can be done in any order unless noted. Across groups: **A** (Resource types) unblocks everything; **B** (loader/registries/pipeline) needs A; **C** (validation) needs A + B's registries; **D** (derivation) needs A + valid data from C; **E** (GameData API) surfaces B/D; **F** (content + test fixtures) can run in parallel once A's schemas exist; **G** (tests) trails the code/content it covers.

Each task lists a **done state**. Code stubs are Godot 4 / GDScript — drop-in starting points, not final implementations. They extend the Phase 0 skeleton (`JsonLoader`, `Validator`, `GameData`, `CharacterData`), generalizing it to the full data layer.

> **Carry-over from Phase 0:** Phase 0's `CharacterData` already stores stats as a `base_stats: Dictionary` (not flat fields) — no refactoring needed there. Phase 1 adds only `var final_stats: StatBlock = null`. The Phase 0 character-only `Validator` is generalized in Group C. The Phase 0 decision to use `ability_range` (not `range`) on `AbilityData` is preserved.

---

## Resolved Design Decisions

These decisions were finalized during Phase 1 preparation and apply throughout the plan:

| Area | Decision | Rationale |
|------|----------|-----------|
| **`magic_affinity`** | **Dropped.** Not added to `StatKey`. The Elf race example in `phase1-spec.md` §3.1 is illustrative only. | §4.3 defers magic stats for MVP: "folded into per-ability values and DEF." |
| **Item `passive` validation** | **Free-form keys.** `passive` dictionaries are not validated against `StatKey`. Only value types are checked (numeric). | Passives include non-stat effects (e.g., `"accuracy": 1`). Combat code (Phase 5) interprets them. |
| **`ability_range` naming** | **Keep `ability_range`.** Phase 0's decision preserved. JSON `"range"` maps to `ability_range` in `DataFactory`. | Avoids shadowing GDScript's `range()` builtin. |
| **Content seed values** | **Inferred from spec flavor.** Race/class modifiers, ability stats, item values derived from §6 roster and flavor text. | Phase 9 handles balancing; Phase 1 only requires load + validate + derive correctly. |

---

## Group A — Resource Type Definitions

*Unblocks all other groups. Mirror the schemas in `phase1-spec.md` §3. References are stored as string IDs.*

### A1. `RaceData`
- **Done:** loads with `id`, `display_name`, `stat_modifiers` (keys validated against `StatKey`), optional `flavor`.

```gdscript
# src/core/data/race_data.gd
class_name RaceData
extends Resource

@export var id: String
@export var display_name: String
@export var stat_modifiers: Dictionary = {}   # e.g. {"spd":1,"hp":-1} — keys validated against StatKey
@export var flavor: String = ""
```

### A2. `ClassData`
- **Done:** loads with modifiers (keys validated against `StatKey`), derived bonuses, equipment access, granted abilities (all IDs).

```gdscript
# src/core/data/class_data.gd
class_name ClassData
extends Resource

@export var id: String
@export var display_name: String
@export var abbr: String = ""
@export var stat_modifiers: Dictionary = {}       # keys validated against StatKey
@export var derived_bonuses: Dictionary = {}      # e.g. {"jump_climb":1}
@export var equipment_access: Array[String] = []  # ItemData ids
@export var granted_abilities: Array[String] = [] # AbilityData ids
```

### A3. `AbilityData`
- **Done:** loads with type, ap_cost, ability_range (JSON `"range"` → `ability_range`), optional area, structured effect (with `effect_type`), source.
- **Note:** field is `ability_range` not `range` to avoid shadowing GDScript's `range()` builtin. The factory maps `d["range"]` → `ability_data.ability_range`.

```gdscript
# src/core/data/ability_data.gd
class_name AbilityData
extends Resource

@export var id: String
@export var display_name: String
@export var type: String              # "spell" | "skill" | "item" | "passive"
@export var ap_cost: int = 1
@export var ability_range: int = 0    # JSON key "range" — renamed to avoid GDScript builtin shadow
@export var area: Dictionary = {}     # {"shape":"burst","radius":1}
@export var effect: Dictionary = {}   # {"effect_type":"damage","value":7,"element":"fire"}
@export var effect_type: String = ""  # pulled from effect["effect_type"] at load for fast dispatch
@export var source: String = "class"  # "class" | "item"
```

### A4. `ItemData`
- **Done:** loads with slot, bp_value, optional passive (free-form keys, not StatKey-validated), granted abilities; weapons carry attack profile fields.

```gdscript
# src/core/data/item_data.gd
class_name ItemData
extends Resource

@export var id: String
@export var display_name: String
@export var slot: String           # "weapon" | "armor" | "shield" | "accessory"
@export var bp_value: int = 0
@export var passive: Dictionary = {}        # free-form keys (e.g. {"accuracy":1}) — NOT validated against StatKey
@export var granted_abilities: Array[String] = []
# weapon-only (optional):
@export var weapon_power: int = 0
@export var weapon_range: int = 0
```

### A5. `CharacterData` (extend Phase 0)
- Phase 0 already has `base_stats: Dictionary`. Phase 1 adds `var final_stats: StatBlock = null` for the computed derivation.
- **Done:** loads §6 schema; `final_stats` starts null until derivation runs.

```gdscript
# src/core/data/character_data.gd
class_name CharacterData
extends Resource

@export var id: String
@export var display_name: String
@export var race: String                    # RaceData id
@export var classes: Array[String] = []     # ClassData ids
@export var level: int = 1
@export var bp: int = 0
@export var base_stats: Dictionary = {}     # {"spd":3,"atk":2,...} — keys validated against StatKey
@export var equipment: Array[String] = []   # ItemData ids
@export var abilities: Array[String] = []   # extra AbilityData ids

var final_stats: StatBlock = null           # computed in Group D (not serialized); base values only
```

### A6. `MapData` (schema only)
- **Done:** loads tiles as `Array[TileRecord]` (converted from JSON dicts at load) and deployment zones; not consumed geometrically this phase.

```gdscript
# src/core/data/map_data.gd
class_name MapData
extends Resource

@export var id: String
@export var tier: String
var tiles: Array[TileRecord] = []              # populated by factory from JSON tile dicts
@export var deployment_zones: Dictionary = {}   # {"playerA":["0,0"], "playerB":["8,0"]}
```

### A7. `BattleUnit` (skeleton)
- The runtime wrapper separating immutable authored data from mutable per-battle state (spec §9.6, phase1-spec §5.1).
- No combat logic — only the class definition with mutable fields and initialization from a loaded character.
- **Done:** class compiles; a test instantiates it from a loaded character and verifies field defaults.

```gdscript
# src/core/data/battle_unit.gd
class_name BattleUnit
extends RefCounted

var character: CharacterData        # immutable authored data
var stats: StatBlock                # initialized from load-time derivation; modifier stack for runtime
var position: Vector2i = Vector2i.ZERO
var current_hp: int = 0
var ap_remaining: int = 2
var is_activated: bool = false
var team: String = ""

static func from_character(c: CharacterData, final_stats: StatBlock) -> BattleUnit:
    var u := BattleUnit.new()
    u.character = c
    u.stats = final_stats.duplicate()  # own copy for runtime modifiers
    u.current_hp = u.stats.effective(StatKey.to_string_key(StatKey.Key.HP))
    return u
```

---

## Group B — Loader Generalization & Registries

*Depends on A. Extends the Phase 0 `JsonLoader`/`GameData`.*

### B1. Per-type factories
- One factory `Callable(Dictionary) -> Resource` per type, mapping JSON onto the Resource. Centralize in a `DataFactory` to keep `GameData` thin.
- `make_ability` maps JSON `d["range"]` → `ability_data.ability_range` and pulls `effect_type` from `d["effect"]["effect_type"]`.
- **Done:** each factory produces a populated Resource from a valid dict.

```gdscript
# src/core/data/data_factory.gd
class_name DataFactory
extends RefCounted

static func make_race(d: Dictionary) -> RaceData:
    var r := RaceData.new()
    r.id = d["id"]; r.display_name = d.get("display_name", d["id"])
    r.stat_modifiers = d.get("stat_modifiers", {}); r.flavor = d.get("flavor", "")
    return r

static func make_character(d: Dictionary) -> CharacterData:
    var c := CharacterData.new()
    c.id = d["id"]; c.display_name = d.get("display_name", d["id"])
    c.race = d["race"]; c.classes = _to_str_array(d.get("classes", []))
    c.level = int(d.get("level", 1)); c.bp = int(d.get("bp", 0))
    c.base_stats = d.get("base_stats", {})
    c.equipment = _to_str_array(d.get("equipment", []))
    c.abilities = _to_str_array(d.get("abilities", []))
    return c

static func make_ability(d: Dictionary) -> AbilityData:
    var a := AbilityData.new()
    a.id = d["id"]; a.display_name = d.get("display_name", d["id"])
    a.type = d.get("type", ""); a.ap_cost = int(d.get("ap_cost", 1))
    a.ability_range = int(d.get("range", 0))   # JSON "range" → ability_range
    a.area = d.get("area", {}); a.effect = d.get("effect", {})
    a.effect_type = str(d.get("effect", {}).get("effect_type", ""))
    a.source = d.get("source", "class")
    return a

static func make_map(d: Dictionary) -> MapData:
    var m := MapData.new()
    m.id = d["id"]; m.tier = d.get("tier", "standard")
    m.deployment_zones = d.get("deployment_zones", {})
    var tiles: Array[TileRecord] = []
    for t in d.get("tiles", []):
        tiles.append(TileRecord.new(int(t["q"]), int(t["r"]),
            int(t.get("elevation", 0)), str(t.get("terrain", "grass"))))
    m.tiles = tiles
    return m

# ... make_class, make_item analogously

static func _to_str_array(v: Variant) -> Array[String]:
    var out: Array[String] = []
    for e in v: out.append(str(e))
    return out
```

### B2. Per-domain registries
- Each entity type has its own `EntityRegistry` with `load_from(dir, factory)`, `get_entry(id)`, `all()`, `has(id)`, `size()`.
- **Done:** each registry is independently instantiable and testable.

```gdscript
# src/core/data/entity_registry.gd
class_name EntityRegistry
extends RefCounted

var _entries: Dictionary = {}   # id -> Resource

func load_from(dir_path: String, factory: Callable) -> void:
    _entries = JsonLoader.load_dir(dir_path, factory)

func get_entry(id: String) -> Resource:
    return _entries.get(id)

func all() -> Array:
    return _entries.values()

func has(id: String) -> bool:
    return _entries.has(id)

func size() -> int:
    return _entries.size()

func ids() -> Array:
    return _entries.keys()
```

### B3. `DataPipeline` — testable boot pipeline
- Owns the six registries and the full load → structural validate → referential validate → derive sequence. Extracted from `GameData` so the entire pipeline is testable without the scene tree or autoload registration.
- Accepts a base path (default `"res://data"`) so tests can point it at fixture directories.
- Returns an `Array[String]` of errors from each stage; callers decide how to handle failures.
- **Done:** `DataPipeline` runs the full pipeline; independently testable from GUT with no Node/scene-tree dependency.

```gdscript
# src/core/data/data_pipeline.gd
class_name DataPipeline
extends RefCounted

var races := EntityRegistry.new()
var classes := EntityRegistry.new()
var abilities := EntityRegistry.new()
var items := EntityRegistry.new()
var characters := EntityRegistry.new()
var maps := EntityRegistry.new()

## Runs the full pipeline: load → structural validate → referential validate → derive.
## Returns Array[String] of all errors (empty == success).
func run(base_path: String = "res://data") -> Array[String]:
    _load_all(base_path)
    var errors: Array[String] = []
    errors.append_array(_validate_structural())
    if not errors.is_empty():
        return errors
    errors.append_array(_validate_references())
    if not errors.is_empty():
        return errors
    _derive_all()
    return errors

func _load_all(base_path: String) -> void:
    races.load_from(base_path.path_join("races"), DataFactory.make_race)
    classes.load_from(base_path.path_join("classes"), DataFactory.make_class)
    abilities.load_from(base_path.path_join("abilities"), DataFactory.make_ability)
    items.load_from(base_path.path_join("items"), DataFactory.make_item)
    characters.load_from(base_path.path_join("characters"), DataFactory.make_character)
    maps.load_from(base_path.path_join("maps"), DataFactory.make_map)

func _validate_structural() -> Array[String]:
    var errors: Array[String] = []
    # Per-type structural validation on each loaded entry
    # ... delegates to Validator.validate_race(), validate_class(), etc.
    return errors

func _validate_references() -> Array[String]:
    # Cross-entity referential integrity — uses registries dict
    return Validator.validate_references({
        "races": races, "classes": classes, "abilities": abilities,
        "items": items, "characters": characters, "maps": maps,
    })

func _derive_all() -> void:
    for c in characters.all():
        var race: RaceData = races.get_entry(c.race)
        var cls_list: Array = []
        for cid in c.classes:
            cls_list.append(classes.get_entry(cid))
        c.final_stats = StatResolver.resolve(c, race, cls_list)

# Convenience accessors (same signatures as GameData for delegation)
func get_race(id: String) -> RaceData:        return races.get_entry(id)
func get_class(id: String) -> ClassData:      return classes.get_entry(id)
func get_ability(id: String) -> AbilityData:  return abilities.get_entry(id)
func get_item(id: String) -> ItemData:        return items.get_entry(id)
func get_character(id: String) -> CharacterData: return characters.get_entry(id)
func get_map(id: String) -> MapData:          return maps.get_entry(id)
func get_final_stats(id: String) -> StatBlock:
    var c := get_character(id)
    return c.final_stats if c else null
```

### B4. `GameData` facade (thin delegation)
- `GameData` (autoload Node) delegates entirely to `DataPipeline`. Its `_ready()` is a three-line boot: instantiate pipeline, run, abort on errors.
- Public accessors delegate to the pipeline.
- **Done:** `GameData._ready` runs the full pipeline; all accessors work.

```gdscript
# src/autoload/game_data.gd  (facade — thin delegation to DataPipeline)
extends Node

var _pipeline := DataPipeline.new()

func _ready() -> void:
    var errors := _pipeline.run()
    if not errors.is_empty():
        for err in errors:
            push_error("GameData: %s" % err)
        Logger.error("GameData", "Data pipeline failed with %d error(s)" % errors.size())
        return
    Logger.info("GameData", "Loaded %d race(s), %d class(es), %d ability(ies), %d item(s), %d character(s), %d map(s)" % [
        _pipeline.races.size(), _pipeline.classes.size(),
        _pipeline.abilities.size(), _pipeline.items.size(),
        _pipeline.characters.size(), _pipeline.maps.size()])

# Public accessors delegate to pipeline
func get_race(id: String) -> RaceData:           return _pipeline.get_race(id)
func get_class(id: String) -> ClassData:         return _pipeline.get_class(id)
func get_ability(id: String) -> AbilityData:     return _pipeline.get_ability(id)
func get_item(id: String) -> ItemData:           return _pipeline.get_item(id)
func get_character(id: String) -> CharacterData: return _pipeline.get_character(id)
func get_map(id: String) -> MapData:             return _pipeline.get_map(id)
func get_final_stats(id: String) -> StatBlock:   return _pipeline.get_final_stats(id)
func all_characters() -> Array:                  return _pipeline.characters.all()
```

### B5. Boot sequence ordering
- `GameData._ready` → `DataPipeline.run()` → load all → structural validate → referential validate → derive → log summary. Abort loudly if any validation pass fails.
- **Done:** clean content boots with summary; bad content aborts with named errors.

---

## Group C — Validation (Structural + Referential)

*Depends on A + B. Generalizes the Phase 0 `Validator`. Two passes per spec §4.2.*

### C1. Structural validators (per type)
- One function per type returning `Array[String]` of errors (empty == valid): required fields, types, ranges, enums.
- **All stat-keyed dictionaries** (`base_stats`, `stat_modifiers`) are checked: every key must pass `StatKey.is_valid_key()`; unknown keys are rejected.
- **Item `passive`** dictionaries are **not** validated against `StatKey` — free-form keys are allowed; only value types are checked (must be numeric).
- **Done:** each catches missing/bad fields with precise messages; unknown stat keys are flagged.

```gdscript
# src/core/data/validator.gd  (extends Phase 0 version)
class_name Validator
extends RefCounted

const TERRAINS := ["grass","road","brush","trees","rocks","shallow_water","deep_water","cliff"]
const SLOTS := ["weapon","armor","shield","accessory"]
const ABILITY_TYPES := ["spell","skill","item","passive"]
const EFFECT_TYPES := ["damage","heal","status","buff"]

static func validate_stat_keys(d: Dictionary, entity_id: String, field_name: String) -> Array[String]:
    var e: Array[String] = []
    for k in d.keys():
        if not StatKey.is_valid_key(str(k)):
            e.append("%s '%s' has unknown stat key '%s' in %s" % ["entity", entity_id, k, field_name])
    return e

static func validate_item(d: Dictionary) -> Array[String]:
    var e: Array[String] = []
    for k in ["id","slot","bp_value"]:
        if not d.has(k): e.append("item missing '%s'" % k)
    if d.has("slot") and not SLOTS.has(d["slot"]):
        e.append("item '%s' bad slot '%s'" % [d.get("id","?"), d["slot"]])
    # passive dict: free-form keys, but values must be numeric
    if d.has("passive") and typeof(d["passive"]) == TYPE_DICTIONARY:
        for pk in d["passive"].keys():
            var pv = d["passive"][pk]
            if typeof(pv) != TYPE_INT and typeof(pv) != TYPE_FLOAT:
                e.append("item '%s' passive key '%s' has non-numeric value" % [d.get("id","?"), pk])
    return e

# ... validate_race, validate_class, validate_ability, validate_character, validate_map
# Each validator for types with stat_modifiers / base_stats calls validate_stat_keys().

static func validate_ability_effect(effect: Dictionary, ability_id: String) -> Array[String]:
    var e: Array[String] = []
    if not effect.has("effect_type"):
        e.append("ability '%s' effect missing 'effect_type'" % ability_id)
        return e
    var et: String = str(effect["effect_type"])
    if not EFFECT_TYPES.has(et):
        e.append("ability '%s' has unknown effect_type '%s'" % [ability_id, et])
        return e
    # Per-type required fields
    match et:
        "damage":
            if not effect.has("value"): e.append("ability '%s' damage effect missing 'value'" % ability_id)
        "heal":
            if not effect.has("value"): e.append("ability '%s' heal effect missing 'value'" % ability_id)
        "status":
            for k in ["status_id", "duration"]:
                if not effect.has(k): e.append("ability '%s' status effect missing '%s'" % [ability_id, k])
        "buff":
            for k in ["stat", "value", "duration"]:
                if not effect.has(k): e.append("ability '%s' buff effect missing '%s'" % [ability_id, k])
            if effect.has("stat") and not StatKey.is_valid_key(str(effect["stat"])):
                e.append("ability '%s' buff targets unknown stat '%s'" % [ability_id, effect["stat"]])
    return e
```

### C2. Referential-integrity pass
- After all registries load, confirm every referenced ID exists (spec §4.2 list).
- Accepts a **Dictionary of registries** (not a GameData node) for testability without scene tree.
- **Done:** dangling refs (character→missing class/item/ability, class→missing ability/item, map zone→missing tile) produce precise errors.

```gdscript
## registries: Dictionary with keys "races","classes","abilities","items","characters","maps"
## each value is an EntityRegistry instance.
static func validate_references(registries: Dictionary) -> Array[String]:
    var e: Array[String] = []
    for c in registries["characters"].all():
        if not registries["races"].has(c.race):
            e.append("character '%s' references unknown race '%s'" % [c.id, c.race])
        for cls in c.classes:
            if not registries["classes"].has(cls):
                e.append("character '%s' references unknown class '%s'" % [c.id, cls])
        for it in c.equipment:
            if not registries["items"].has(it):
                e.append("character '%s' references unknown item '%s'" % [c.id, it])
        for ab in c.abilities:
            if not registries["abilities"].has(ab):
                e.append("character '%s' references unknown ability '%s'" % [c.id, ab])
    for cls in registries["classes"].all():
        for ab in cls.granted_abilities:
            if not registries["abilities"].has(ab):
                e.append("class '%s' references unknown ability '%s'" % [cls.id, ab])
        for it in cls.equipment_access:
            if not registries["items"].has(it):
                e.append("class '%s' references unknown item '%s'" % [cls.id, it])
    for it in registries["items"].all():
        for ab in it.granted_abilities:
            if not registries["abilities"].has(ab):
                e.append("item '%s' references unknown ability '%s'" % [it.id, ab])
    for m in registries["maps"].all():
        var tile_coords := {}
        for t in m.tiles:
            tile_coords["%d,%d" % [t.q, t.r]] = true
        for zone_name in m.deployment_zones.keys():
            for coord_str in m.deployment_zones[zone_name]:
                if not tile_coords.has(coord_str):
                    e.append("map '%s' deployment zone '%s' references non-existent tile '%s'" % [m.id, zone_name, coord_str])
    return e
```

### C3. Wire validation into boot (fail-loud)
- Structural pass runs during `DataPipeline._validate_structural()`; referential pass runs in `DataPipeline._validate_references()`. On any error: pipeline returns the error array; `GameData` logs each with `push_error` and aborts loading.
- **Done:** clean content boots; bad content aborts with named errors.

---

## Group D — Derivation Pass (Final Stat Block)

*Depends on A + validated data (C). Implements spec §2.2 / §4.3. Single source of truth for stats.*

### D1. `StatModifier` and `StatBlock`
- `StatModifier`: a single additive modifier entry (key, value, source tag).
- `StatBlock`: stores base values (keyed by `StatKey` strings) + a modifier stack. Effective values are computed on demand. Derived stats (`move`, `jump_climb`) recompute from effective values. Supports `duplicate()` (deep-copies modifier stack) so each `BattleUnit` gets its own copy.
- **Done:** holds base + modifiers; `effective()`, `effective_move()`, `effective_jump_climb()` return correct values; push/pop modifiers work.

```gdscript
# src/core/data/stat_modifier.gd
class_name StatModifier
extends RefCounted

var key: String       # a valid StatKey string (e.g., "spd")
var value: int        # additive
var source: String    # e.g., "equipment", "buff", "elevation"

func _init(k: String = "", v: int = 0, s: String = "") -> void:
    key = k; value = v; source = s
```

```gdscript
# src/core/data/stat_block.gd
class_name StatBlock
extends RefCounted

var _base: Dictionary = {}                   # StatKey string -> int
var _modifiers: Array[StatModifier] = []
var _jump_climb_bonus: int = 0               # class-derived (e.g., Rogue)

func set_base(key: String, value: int) -> void:
    _base[key] = value

func base(key: String) -> int:
    return int(_base.get(key, 0))

func effective(key: String) -> int:
    var v: int = base(key)
    for m in _modifiers:
        if m.key == key:
            v += m.value
    return v

func push_modifier(m: StatModifier) -> void:
    _modifiers.append(m)

func remove_modifiers_by_source(source: String) -> void:
    _modifiers = _modifiers.filter(func(m): return m.source != source)

func set_jump_climb_bonus(bonus: int) -> void:
    _jump_climb_bonus = bonus

# Derived stats — recompute from effective values
func effective_move() -> int:
    return effective("spd")

func effective_jump_climb() -> int:
    return int(floor(effective("spd") / 2.0)) + 1 + _jump_climb_bonus

func duplicate() -> StatBlock:
    var sb := StatBlock.new()
    sb._base = _base.duplicate()
    sb._jump_climb_bonus = _jump_climb_bonus
    for m in _modifiers:
        sb._modifiers.append(StatModifier.new(m.key, m.value, m.source))
    return sb
```

### D2. `StatResolver`
- Combine base + race modifiers + each class modifier (**additive** multiclass rule), then populate `StatBlock` base values. Derived stats are computed via `StatBlock` helpers.
- Iterates `StatKey.all_strings()` — no hardcoded key list.
- **Done:** returns a correct `StatBlock` for a character; matches hand-computed expectations.

```gdscript
# src/core/data/stat_resolver.gd
class_name StatResolver
extends RefCounted

static func resolve(c: CharacterData, race: RaceData, classes: Array) -> StatBlock:
    var sb := StatBlock.new()
    for k in StatKey.all_strings():                  # iterate enum, not a hardcoded list
        var v: int = int(c.base_stats.get(k, 0))
        v += int(race.stat_modifiers.get(k, 0))
        for cls in classes:
            v += int(cls.stat_modifiers.get(k, 0))   # additive multiclass stacking
        sb.set_base(k, v)
    # derived bonuses
    var jump_bonus := 0
    for cls in classes:
        jump_bonus += int(cls.derived_bonuses.get("jump_climb", 0))
    sb.set_jump_climb_bonus(jump_bonus)
    return sb
```

### D3. Run derivation in boot & cache
- After validation, `DataPipeline._derive_all()` resolves each character's `final_stats` using the pipeline's own registries.
- **Done:** `get_final_stats(id)` returns the cached block; computed once. Effective values equal base values at load (stack is empty).

---

## Group E — GameData API (Lazy Accessors)

*Depends on B (pipeline) + D (derived cache). The public surface other phases consume.*

### E1. Typed accessors (on facade)
- Defined on `GameData` (B4), delegating to `DataPipeline`. Includes `get_final_stats`:
- **Done:** each returns the correct typed Resource by id, or null.

```gdscript
# in GameData (delegates to _pipeline — see B4)
func get_final_stats(id: String) -> StatBlock:
    return _pipeline.get_final_stats(id)
```

### E2. Read-only guarantee
- `GameData` (facade), `DataPipeline`, and all registries expose data but never mutate content post-load. All per-battle mutable state lives on `BattleUnit` instances (§A7), not on Resources. Document that consumers resolve references via `GameData` accessors (lazy model — Resources hold IDs, not object links).
- **Done:** convention documented in README; no setters on the public surface.

---

## Group F — Content Authoring & Test Fixtures

*Depends on A (schemas). Runs in parallel with B–E. Values are seeds; balancing is Phase 9.*

### F1. Races
- Author Human, Elf, Halfling, Dwarf under `data/races/`.
- **Done:** four races load.

### F2. Classes
- Archer, Black Mage, White Mage, Fighter, Barbarian, Rogue, Red Mage, Bard under `data/classes/` with modifiers, equipment access, granted abilities.
- **Done:** eight classes load; their ability/item refs exist (or are authored in F3/F4).

### F3. Abilities
- Fire 1/2, Ice 1, Thunder 1, Cure 1/2, Shield 1, Power Strike, Reckless Swing, Rage, Backstab, Smoke Bomb (item-bound), Inspire, Lullaby.
- **Done:** all referenced abilities load.

### F4. Items / equipment
- Bow, Bracer of Accuracy, Light/Medium Armor, Shield, Sword, Greataxe, Daggers, Rapier, Sling, Staff, etc., with `bp_value` and (weapons) attack profile.
- **Done:** all referenced items load.

### F5. Characters
- All eight from spec §6 with `base_stats` matching the table.
- **Done:** roster loads and validates.

```json
// data/characters/elf_black_mage.json
{
  "id": "elf_black_mage", "display_name": "Elf Black Mage",
  "race": "elf", "classes": ["black_mage"], "level": 5, "bp": 30,
  "base_stats": { "spd": 3, "atk": 0, "rng": 0, "def": 0, "hp": 12 },
  "equipment": ["staff"],
  "abilities": ["fire_1","fire_2","ice_1","thunder_1"]
}
```

### F6. Maps & constants
- At least one valid `MapData` fixture per tier under `data/maps/`; finalize `data/constants.json` (ELEV_BONUS, COVER_DEF, ROUT_THRESHOLD, tiers).
- **Done:** maps load/validate (geometry unused); constants exposed via `Constants`.

### F7. Integration test fixtures
- Dedicated fixture directories under `tests/fixtures/` with small, self-consistent content sets that integration tests control independently of the live `data/` directory. These are stable inputs for repeatable testing.
- **Done:** three fixture sets exist and are used by G6–G8.

| Fixture directory | Contents | Purpose |
|---|---|---|
| `tests/fixtures/valid_set/` | Minimal complete set: 1 race, 1 class, 1 ability, 1 item, 1 character, 1 map — all references resolve. | Positive integration tests (pipeline, wiring, BattleUnit). |
| `tests/fixtures/dangling_ref/` | Same as `valid_set` but character references a non-existent class. | Referential-integrity integration test (negative). |
| `tests/fixtures/bad_effect/` | Same as `valid_set` but ability has malformed effect dict (missing `effect_type`). | Effect-type validation integration test (negative). |

---

## Group G — Tests (GUT)

*Trails the code/content it covers. Extend the Phase 0 suite. All test files live under `tests/core/data/` (mirroring `src/core/data/`).*

### G1. Schema/load unit tests
- Each entity type loaded from a hand-built dict via `DataFactory` into the right Resource with expected field values.
- **Done:** green.

### G2. Structural validation unit tests
- Missing required field, bad enum (`slot`/`terrain`/ability `type`), out-of-range value, non-numeric passive value, unknown stat key — each yields the expected error.
- **Done:** green.

### G3. Referential-integrity unit tests
- Hand-populated `EntityRegistry` instances with a dangling reference are rejected; a clean set passes.
- Uses `Validator.validate_references()` with a hand-built registries dictionary (no file I/O).
- **Done:** positive + negative cases pass.

```gdscript
# tests/core/data/test_references.gd
extends GutTest

func test_dangling_class_ref_detected() -> void:
    var characters := EntityRegistry.new()
    # ... manually add a CharacterData citing a non-existent class
    var registries := {
        "races": _stub_registry(["human"]),
        "classes": EntityRegistry.new(),  # empty — no classes loaded
        "abilities": EntityRegistry.new(),
        "items": EntityRegistry.new(),
        "characters": characters,
        "maps": EntityRegistry.new(),
    }
    var errors := Validator.validate_references(registries)
    assert_true(errors.size() > 0, "should detect dangling class ref")

func test_clean_set_passes() -> void:
    # ... fully consistent registries
    var errors := Validator.validate_references(registries)
    assert_eq(errors.size(), 0, "clean set should have no ref errors")
```

### G4. Derived-stat unit tests
- A known character's `final_stats` equals hand-computed base + race + class values; Move and Jump/Climb (incl. Rogue bonus) correct; multiclass additive stacking verified.
- **Done:** green.

```gdscript
# tests/core/data/test_stat_resolver.gd
extends GutTest

func test_archer_derived_stats() -> void:
    var c := CharacterData.new()
    c.base_stats = {"spd":3,"atk":2,"rng":2,"def":1,"hp":10}
    var human := RaceData.new()        # no modifiers
    var archer := ClassData.new()      # no modifiers
    var sb := StatResolver.resolve(c, human, [archer])
    assert_eq(sb.effective("spd"), 3)
    assert_eq(sb.effective_move(), 3)
    assert_eq(sb.effective_jump_climb(), 2)  # floor(3/2)+1

func test_modifier_stack() -> void:
    var c := CharacterData.new()
    c.base_stats = {"spd":3,"atk":2,"rng":2,"def":1,"hp":10}
    var sb := StatResolver.resolve(c, RaceData.new(), [])
    assert_eq(sb.effective("def"), 1)
    sb.push_modifier(StatModifier.new("def", 2, "equipment"))
    assert_eq(sb.effective("def"), 3)
    sb.remove_modifiers_by_source("equipment")
    assert_eq(sb.effective("def"), 1)
```

### G5. JsonLoader integration test
- Calls `JsonLoader.load_dir()` against a real fixture directory (`tests/fixtures/valid_set/characters/`) with `DataFactory.make_character` and asserts:
  - Correct number of entries returned.
  - Each entry has the expected `id`.
  - Fields populated from JSON match expected values.
- Also tests error handling: a directory containing a malformed file (non-JSON, empty, missing id) skips bad entries without crashing.
- **Done:** green.

```gdscript
# tests/core/data/test_json_loader.gd
extends GutTest

func test_load_dir_returns_correct_entries() -> void:
    var result := JsonLoader.load_dir("res://tests/fixtures/valid_set/characters", DataFactory.make_character)
    assert_eq(result.size(), 1, "fixture has one character")
    assert_true(result.has("test_fighter"), "loaded character has expected id")
    var c: CharacterData = result["test_fighter"]
    assert_eq(c.race, "test_race")
    assert_eq(c.bp, 10)

func test_load_dir_skips_malformed_files() -> void:
    var result := JsonLoader.load_dir("res://tests/fixtures/bad_files", DataFactory.make_character)
    # bad_files/ contains a non-JSON file and an empty file — both should be skipped
    assert_eq(result.size(), 0, "malformed files should be skipped")
```

### G6. DataPipeline integration test (cross-module wiring)
- Instantiates `DataPipeline`, points it at `tests/fixtures/valid_set/`, and exercises the **full chain**: JSON file → JsonLoader → DataFactory → Validator (structural) → EntityRegistry → Validator (referential) → StatResolver → StatBlock → BattleUnit.
- Asserts at each boundary:
  - Pipeline returns zero errors.
  - Each registry has the expected entry count.
  - A loaded character has correct field values from JSON.
  - Structural validation returned zero errors (implicit — pipeline succeeded).
  - Referential validation returned zero errors (implicit — pipeline succeeded).
  - Character's `final_stats` base values equal hand-computed (base + race modifier + class modifier).
  - Derived stats (move, jump_climb) are correct.
  - `BattleUnit.from_character()` produces a unit with `current_hp` equal to effective HP.
- **Done:** green. This is the single most valuable integration test — if it passes, the pipeline works end to end.

```gdscript
# tests/core/data/test_pipeline.gd
extends GutTest

func test_full_pipeline_on_valid_fixture() -> void:
    var pipeline := DataPipeline.new()
    var errors := pipeline.run("res://tests/fixtures/valid_set")
    assert_eq(errors.size(), 0, "valid fixture set should produce zero errors")

    # Registry counts
    assert_eq(pipeline.races.size(), 1)
    assert_eq(pipeline.classes.size(), 1)
    assert_eq(pipeline.characters.size(), 1)

    # Character loaded correctly
    var c := pipeline.get_character("test_fighter")
    assert_not_null(c, "test_fighter should exist")
    assert_eq(c.race, "test_race")

    # Derived stats correct (hand-computed: base + race + class)
    var sb := pipeline.get_final_stats("test_fighter")
    assert_not_null(sb, "final_stats should be computed")
    # ... assert_eq on specific stat values matching hand computation

    # Derived move/jump
    assert_eq(sb.effective_move(), sb.effective("spd"))
    assert_eq(sb.effective_jump_climb(), int(floor(sb.effective("spd") / 2.0)) + 1)

    # BattleUnit instantiation
    var unit := BattleUnit.from_character(c, sb)
    assert_eq(unit.current_hp, sb.effective("hp"))
    assert_eq(unit.ap_remaining, 2)
    assert_false(unit.is_activated)

func test_pipeline_rejects_dangling_refs() -> void:
    var pipeline := DataPipeline.new()
    var errors := pipeline.run("res://tests/fixtures/dangling_ref")
    assert_true(errors.size() > 0, "dangling ref fixture should produce errors")

func test_pipeline_rejects_bad_effect() -> void:
    var pipeline := DataPipeline.new()
    var errors := pipeline.run("res://tests/fixtures/bad_effect")
    assert_true(errors.size() > 0, "bad effect fixture should produce errors")
```

### G7. Referential-integrity integration test
- Companion to G3's unit test. Runs `Validator.validate_references()` on registries populated by `JsonLoader` from fixture directories (not hand-built).
- `tests/fixtures/valid_set/` → passes (zero errors).
- `tests/fixtures/dangling_ref/` → fails with a specific error message naming the dangling reference.
- **Done:** green.

```gdscript
# in tests/core/data/test_references.gd (alongside unit tests from G3)

func test_fixture_valid_set_passes_referential() -> void:
    var pipeline := DataPipeline.new()
    pipeline._load_all("res://tests/fixtures/valid_set")
    var errors := pipeline._validate_references()
    assert_eq(errors.size(), 0, "valid fixture set has no dangling refs")

func test_fixture_dangling_ref_caught() -> void:
    var pipeline := DataPipeline.new()
    pipeline._load_all("res://tests/fixtures/dangling_ref")
    var errors := pipeline._validate_references()
    assert_true(errors.size() > 0, "dangling ref should be caught")
    # Verify error message names the offending entity and field
    assert_true(errors[0].find("unknown class") >= 0, "error should name the dangling class ref")
```

### G8. Full-content smoke test (expanded)
- Loads the entire authored `data/` directory through `DataPipeline.run()` and verifies:
  - **Zero errors:** pipeline returns an empty error array.
  - **Expected entity counts:** 4 races, 8 classes, N abilities, N items, 8 characters, 3 maps.
  - **Accessor type correctness:** `get_race("human")` returns non-null with `id == "human"`; same for each entity type.
  - **Reference resolution:** at least one character's race, classes, equipment, and abilities all resolve through pipeline accessors without nulls.
  - **Derived stats computed:** `get_final_stats("human_archer")` is non-null and at least one stat matches a hand-computed expected value.
  - **BattleUnit instantiation:** `BattleUnit.from_character()` with a loaded character produces a unit with `current_hp > 0` and correct default state.
- **Done:** green; suite runs headless.

```gdscript
# tests/core/data/test_smoke.gd
extends GutTest

var _pipeline: DataPipeline

func before_all() -> void:
    _pipeline = DataPipeline.new()
    var errors := _pipeline.run("res://data")
    assert_eq(errors.size(), 0, "full content should load with zero errors")

func test_entity_counts() -> void:
    assert_eq(_pipeline.races.size(), 4, "4 races expected")
    assert_eq(_pipeline.classes.size(), 8, "8 classes expected")
    assert_eq(_pipeline.characters.size(), 8, "8 characters expected")
    assert_eq(_pipeline.maps.size(), 3, "3 maps expected")

func test_accessor_returns_correct_type() -> void:
    var human := _pipeline.get_race("human")
    assert_not_null(human); assert_eq(human.id, "human")
    var archer := _pipeline.get_class("archer")
    assert_not_null(archer); assert_eq(archer.id, "archer")
    var bow := _pipeline.get_item("bow")
    assert_not_null(bow); assert_eq(bow.id, "bow")

func test_reference_resolution() -> void:
    var c := _pipeline.get_character("human_archer")
    assert_not_null(c)
    assert_not_null(_pipeline.get_race(c.race), "race ref resolves")
    for cls_id in c.classes:
        assert_not_null(_pipeline.get_class(cls_id), "class ref '%s' resolves" % cls_id)
    for item_id in c.equipment:
        assert_not_null(_pipeline.get_item(item_id), "item ref '%s' resolves" % item_id)

func test_derived_stats_computed() -> void:
    var sb := _pipeline.get_final_stats("human_archer")
    assert_not_null(sb, "human_archer should have final_stats")
    assert_true(sb.effective("hp") > 0, "effective HP should be positive")
    assert_eq(sb.effective_move(), sb.effective("spd"), "move == spd")

func test_battle_unit_from_loaded_character() -> void:
    var c := _pipeline.get_character("human_archer")
    var sb := _pipeline.get_final_stats("human_archer")
    var unit := BattleUnit.from_character(c, sb)
    assert_true(unit.current_hp > 0, "BattleUnit HP should be positive")
    assert_eq(unit.ap_remaining, 2)
    assert_false(unit.is_activated)
    assert_eq(unit.character.id, "human_archer")
```

---

## Dependency Map

```
A (Resource types + StatKey + TileRecord + BattleUnit skeleton)
  ├──> B (loader/registries/DataPipeline/facade) ──> C (validation + StatKey + effect_type) ──> D (derivation + StatBlock) ──> E (GameData API)
  └──> F (content authoring + test fixtures, parallel)
A7 (BattleUnit) needs D1 (StatBlock)
B,C,D,F ──> G (tests: unit G1–G4, integration G5–G8)
```

**Suggested first pass:** A1–A6 → D1 (StatBlock/StatModifier) → A7 (BattleUnit) → B1–B5 → (C1–C3 ∥ F1–F7) → D2–D3 → E1–E2 → G. Author content (F) and test fixtures (F7) alongside the loader/validator so the integration tests have data to run against.

---

## Test Summary

| Test file | Type | # Tests (est.) | Covers |
|-----------|------|----------------|--------|
| `tests/core/data/test_data_factory.gd` | Unit | ~6 | G1: factory per type |
| `tests/core/data/test_validator_full.gd` | Unit | ~10 | G2: structural validation |
| `tests/core/data/test_references.gd` | Unit + Integration | ~4 | G3 + G7: referential integrity |
| `tests/core/data/test_stat_block.gd` | Unit | ~6 | D1: StatBlock base/effective/modifiers/derived |
| `tests/core/data/test_stat_resolver.gd` | Unit | ~4 | G4: derivation, multiclass, Rogue bonus |
| `tests/core/data/test_battle_unit.gd` | Unit | ~3 | A7: BattleUnit construction |
| `tests/core/data/test_json_loader.gd` | Integration | ~3 | G5: JsonLoader + real files |
| `tests/core/data/test_pipeline.gd` | Integration | ~3 | G6: full cross-module wiring |
| `tests/core/data/test_smoke.gd` | Integration | ~5 | G8: full content end-to-end |
| *(existing Phase 0 tests)* | Unit | ~30 | hex math, StatKey, TileRecord, character validation |
| **Total** | | **~74** | |

---

## Phase 1 Definition of Done

- [ ] Resource types for Race, Class, Ability, Item, Character, Map (A).
- [ ] `CharacterData` extended with computed `final_stats` (A5).
- [ ] `BattleUnit` skeleton defined with mutable state fields; instantiable from a loaded character (A7).
- [ ] Loader generalized with per-type factories in `DataFactory`; six `EntityRegistry` instances populate (B1–B2).
- [ ] `DataPipeline` extracts the full boot sequence (load → validate → derive) into a testable RefCounted class (B3).
- [ ] `GameData` is a thin facade delegating to `DataPipeline` (B4).
- [ ] Two-pass validation — structural + referential integrity — fail-loud with precise messages (C).
- [ ] `StatKey` validation on all stat-keyed dictionaries; unknown keys rejected (C1).
- [ ] Item `passive` dictionaries use free-form keys (not StatKey-validated); values checked numeric (C1).
- [ ] Ability `effect_type` validation against structured schemas (C1).
- [ ] Derivation pass: base final stat block + derived stats, additive multiclass stacking, cached (D).
- [ ] `GameData` (facade) lazy accessors for every type + `get_final_stats` + `all_characters`; read-only (E).
- [ ] Full sample content authored and loading clean (F1–F6).
- [ ] `constants.json` finalized with tiers; exposed via `Constants` (F6).
- [ ] Integration test fixtures authored: `valid_set`, `dangling_ref`, `bad_effect` (F7).
- [ ] Unit tests: factory, structural validation, referential integrity, derived-stat, effect-type, StatBlock, BattleUnit — all green (G1–G4).
- [ ] Integration tests: JsonLoader with real files, DataPipeline cross-module wiring, referential integrity on fixtures, full-content smoke — all green (G5–G8).
- [ ] Suite runs headless and is green.
- [ ] Git tag `phase-1-complete`.
