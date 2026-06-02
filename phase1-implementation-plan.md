# Phase 1 — Implementation Plan

**Source spec:** `phase1-spec.md`
**Builds on:** `phase0-implementation-plan.md` (pipeline skeleton)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Reference model:** Lazy lookup by ID · **Derived stats:** computed at load · **Validation:** runtime + GUT
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-05-29

---

## How to use this plan

Seven **work groups** (A–G). Within a group, tasks can be done in any order unless noted. Across groups: **A** (Resource types) unblocks everything; **B** (loader/registries) needs A; **C** (validation) needs A + B's registries; **D** (derivation) needs A + valid data from C; **E** (GameData API) surfaces B/D; **F** (content) can run in parallel once A's schemas exist; **G** (tests) trails the code/content it covers.

Each task lists a **done state**. Code stubs are Godot 4 / GDScript — drop-in starting points, not final implementations. They extend the Phase 0 skeleton (`JsonLoader`, `Validator`, `GameData`, `CharacterData`), generalizing it to the full data layer.

> **Carry-over from Phase 0:** the Phase 0 `CharacterData` was minimal and stored stats as flat fields. Phase 1 **refactors** it to a `base_stats` block and adds a computed final stat block (Group D). The Phase 0 character-only `Validator` is generalized in Group C.

---

## Group A — Resource Type Definitions

*Unblocks all other groups. Mirror the schemas in `phase1-spec.md` §3. References are stored as string IDs.*

### A1. `RaceData`
- **Done:** loads with `id`, `display_name`, `stat_modifiers` (keys validated against `StatKey`).

```gdscript
# src/core/data/race_data.gd
class_name RaceData
extends Resource

@export var id: String
@export var display_name: String
@export var stat_modifiers: Dictionary = {}   # e.g. {"spd":0,"hp":-1} — keys validated against StatKey
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
- **Done:** loads with type, ap_cost, range, optional area, structured effect (with `effect_type`), source.

```gdscript
# src/core/data/ability_data.gd
class_name AbilityData
extends Resource

@export var id: String
@export var display_name: String
@export var type: String              # "spell" | "skill" | "item" | "passive"
@export var ap_cost: int = 1
@export var range: int = 0
@export var area: Dictionary = {}     # {"shape":"burst","radius":1}
@export var effect: Dictionary = {}   # {"effect_type":"damage","value":7,"element":"fire"}
@export var effect_type: String = ""  # pulled from effect["effect_type"] at load for fast dispatch
@export var source: String = "class"  # "class" | "item"
```

### A4. `ItemData`
- **Done:** loads with slot, bp_value, optional passive, granted abilities; weapons carry attack profile fields.

```gdscript
# src/core/data/item_data.gd
class_name ItemData
extends Resource

@export var id: String
@export var display_name: String
@export var slot: String           # "weapon" | "armor" | "shield" | "accessory"
@export var bp_value: int = 0
@export var passive: Dictionary = {}        # {"accuracy":1}
@export var granted_abilities: Array[String] = []
# weapon-only (optional):
@export var weapon_power: int = 0
@export var weapon_range: int = 0
```

### A5. `CharacterData` (refactor from Phase 0)
- Replace flat stat fields with a `base_stats` dict; add a slot for the computed final block (filled by Group D).
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
    c.level = d.get("level", 1); c.bp = d.get("bp", 0)
    c.base_stats = d.get("base_stats", {})
    c.equipment = _to_str_array(d.get("equipment", []))
    c.abilities = _to_str_array(d.get("abilities", []))
    return c

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

# ... make_class, make_ability, make_item analogously

static func _to_str_array(v: Variant) -> Array[String]:
    var out: Array[String] = []
    for e in v: out.append(str(e))
    return out
```

### B2. Per-domain registries + `GameData` facade
- Each entity type has its own registry class with `load(dir, factory)`, `get(id)`, `all()`, and `validate_structural()`. `GameData` is a thin facade that orchestrates loading, validation, and derivation.
- **Done:** all six registries populate from `data/`; `GameData` delegates to them.

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
```

```gdscript
# src/autoload/game_data.gd  (facade — extends Phase 0 version)
extends Node

var _races := EntityRegistry.new()
var _classes := EntityRegistry.new()
var _abilities := EntityRegistry.new()
var _items := EntityRegistry.new()
var _characters := EntityRegistry.new()
var _maps := EntityRegistry.new()

func _load_all() -> void:
    _races.load_from("res://data/races", DataFactory.make_race)
    _classes.load_from("res://data/classes", DataFactory.make_class)
    _abilities.load_from("res://data/abilities", DataFactory.make_ability)
    _items.load_from("res://data/items", DataFactory.make_item)
    _characters.load_from("res://data/characters", DataFactory.make_character)
    _maps.load_from("res://data/maps", DataFactory.make_map)

# Public accessors delegate to registries
func get_race(id: String) -> RaceData:        return _races.get_entry(id)
func get_class(id: String) -> ClassData:      return _classes.get_entry(id)
func get_ability(id: String) -> AbilityData:  return _abilities.get_entry(id)
func get_item(id: String) -> ItemData:        return _items.get_entry(id)
func get_character(id: String) -> CharacterData: return _characters.get_entry(id)
func get_map(id: String) -> MapData:          return _maps.get_entry(id)
func all_characters() -> Array:               return _characters.all()
```

> Each registry is independently instantiable and testable. `GameData` stays thin and orchestrates the boot pipeline: load → validate (structural per registry, then cross-entity referential) → derive.

### B3. Boot sequence ordering
- `_ready`: load all → validate (Group C) → derive (Group D) → log summary. Abort loudly if validation fails.
- **Done:** `GameData._ready` runs the full pipeline in order.

---

## Group C — Validation (Structural + Referential)

*Depends on A + B. Generalizes the Phase 0 `Validator`. Two passes per spec §4.2.*

### C1. Structural validators (per type)
- One function per type returning `Array[String]` of errors (empty == valid): required fields, types, ranges, enums.
- **All stat-keyed dictionaries** (`base_stats`, `stat_modifiers`) are checked: every key must pass `StatKey.is_valid_key()`; unknown keys are rejected.
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
- After all registries load, confirm every referenced ID exists (spec §4.2 list). Operates on registries; pure/testable.
- **Done:** dangling refs (character→missing class/item/ability, class→missing ability/item, map zone→missing tile) produce precise errors.

```gdscript
static func validate_references(gd) -> Array[String]:
    var e: Array[String] = []
    for c in gd.characters.values():
        if not gd.races.has(c.race):
            e.append("character '%s' references unknown race '%s'" % [c.id, c.race])
        for cls in c.classes:
            if not gd.classes.has(cls):
                e.append("character '%s' references unknown class '%s'" % [c.id, cls])
        for it in c.equipment:
            if not gd.items.has(it):
                e.append("character '%s' references unknown item '%s'" % [c.id, it])
        for ab in c.abilities:
            if not gd.abilities.has(ab):
                e.append("character '%s' references unknown ability '%s'" % [c.id, ab])
    for cls in gd.classes.values():
        for ab in cls.granted_abilities:
            if not gd.abilities.has(ab):
                e.append("class '%s' references unknown ability '%s'" % [cls.id, ab])
        for it in cls.equipment_access:
            if not gd.items.has(it):
                e.append("class '%s' references unknown item '%s'" % [cls.id, it])
    # ... item.granted_abilities, map deployment zones ⊆ tiles
    return e
```

### C3. Wire validation into boot (fail-loud)
- Structural pass during/after load; referential pass after all loaded. On any error: `push_error` each and halt (e.g., assert or guarded abort) so dev sees it immediately.
- **Done:** clean content boots; injected bad content aborts with named errors.

---

## Group D — Derivation Pass (Final Stat Block)

*Depends on A + validated data (C). Implements spec §2.2 / §4.3. Single source of truth for stats.*

### D1. `StatModifier` and `StatBlock`
- `StatModifier`: a single additive modifier entry (key, value, source tag).
- `StatBlock`: stores base values (keyed by `StatKey` strings) + a modifier stack. Effective values are computed on demand. Derived stats (`move`, `jump_climb`) recompute from effective values. Supports `duplicate()` so each `BattleUnit` gets its own copy.
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
- After validation, for each character resolve `final_stats` (base values only, empty modifier stack) using the lazy `GameData` lookups for its race/classes; cache on the Resource.
- **Done:** `GameData.get_final_stats(id)` returns the cached block; computed once. Effective values equal base values at load (stack is empty).

```gdscript
# in GameData
func _derive_all() -> void:
    for c in characters.values():
        var race: RaceData = get_race(c.race)
        var cls_list: Array = []
        for cid in c.classes: cls_list.append(get_class(cid))
        c.final_stats = StatResolver.resolve(c, race, cls_list)
        # At load, modifier stack is empty — effective values == base values.
        # BattleUnit.from_character() will duplicate() this block for runtime use.
```

---

## Group E — GameData API (Lazy Accessors)

*Depends on B (registries) + D (derived cache). The public surface other phases consume.*

### E1. Typed accessors (on facade)
- Already defined in B2 on the `GameData` facade. Add `get_final_stats`:
- **Done:** each returns the correct typed Resource by id, or null; delegates to registries.

```gdscript
# in GameData (already has get_race, get_class, etc. from B2)
func get_final_stats(id: String) -> StatBlock:
    var c := get_character(id)
    return c.final_stats if c else null
```

### E2. Read-only guarantee
- `GameData` (facade) and all registries expose data but never mutate content post-load. All per-battle mutable state lives on `BattleUnit` instances (§A7), not on Resources. Document that consumers resolve references via `GameData` accessors (lazy model — Resources hold IDs, not object links).
- **Done:** convention documented in README; no setters on the public surface.

---

## Group F — Content Authoring

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

---

## Group G — Tests (GUT)

*Trails the code/content it covers. Extend the Phase 0 suite.*

### G1. Schema/load tests
- Each entity type loads from a valid fixture into the right Resource with expected values.
- **Done:** green.

### G2. Structural validation tests
- Missing required field, bad enum (`slot`/`terrain`/ability `type`), out-of-range value each yield the expected error.
- **Done:** green.

### G3. Referential-integrity tests
- A fixture set with a dangling reference is rejected with a referential error; a clean set passes.
- **Done:** positive + negative cases pass.

```gdscript
# tests/data/test_references.gd
extends GutTest

func test_dangling_class_ref_detected() -> void:
    var gd := _StubGameData.new()  # registries with a character citing missing class
    var errors := Validator.validate_references(gd)
    assert_true(errors.size() > 0)
```

### G4. Derived-stat tests
- A known character's `final_stats` equals hand-computed base + race + class values; Move and Jump/Climb (incl. Rogue bonus) correct; multiclass additive stacking verified.
- **Done:** green.

```gdscript
# tests/data/test_stat_resolver.gd
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

### G5. Full-content smoke test
- Loading the entire authored `data/` set succeeds with zero validation errors and the expected entity counts per type.
- **Done:** green; suite runs headless.

---

## Dependency Map

```
A (Resource types + StatKey + TileRecord + BattleUnit skeleton)
  ├──> B (loader/registries/facade) ──> C (validation + StatKey + effect_type) ──> D (derivation + StatBlock) ──> E (GameData API)
  └──> F (content authoring, parallel)
A7 (BattleUnit) needs D1 (StatBlock)
B,C,D,F ──> G (tests)
```

**Suggested first pass:** A1–A6 → A7 (after D1) → B1–B3 → (C1–C3 ∥ F1–F6) → D1–D3 → E1–E2 → G. Author content (F) alongside the loader/validator so the smoke test has real data to run against.

---

## Phase 1 Definition of Done

- [ ] Resource types for Race, Class, Ability, Item, Character, Map (A).
- [ ] `CharacterData` refactored to `base_stats` + computed `final_stats` (A5).
- [ ] `BattleUnit` skeleton defined with mutable state fields; instantiable from a loaded character (A7).
- [ ] Loader generalized with per-type factories; six registries populate (B).
- [ ] Two-pass validation — structural + referential integrity — fail-loud with precise messages (C).
- [ ] `StatKey` validation on all stat-keyed dictionaries; unknown keys rejected (C1).
- [ ] Ability `effect_type` validation against structured schemas (C1).
- [ ] Derivation pass: base final stat block + derived stats, additive multiclass stacking, cached (D).
- [ ] `GameData` (facade) lazy accessors for every type + `get_final_stats` + `all_characters`; read-only (E).
- [ ] Full sample content authored and loading clean (F).
- [ ] `constants.json` finalized with tiers; exposed via `Constants` (F6).
- [ ] GUT tests: schema, structural, referential, derived-stat, effect-type, `BattleUnit`, full-content smoke — all green, headless (G).
- [ ] Git tag `phase-1-complete`.
```

