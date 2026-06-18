# Phase A4 — Implementation Plan

**Source spec:** `alpha-phaseA4-spec.md`
**Master spec:** `alpha-specs.md` (§5, §6)
**Builds on (Alpha):** `alpha-phaseA3-implementation-plan.md` (`MAG`/`RES`), `alpha-phaseA2` (CSV class columns)
**Builds on (MVP):** `phase1-implementation-plan.md` (`CharacterData`, `ClassData`, `RaceData`, `StatResolver`, `DataFactory`, `Validator`), `phase4`/`phase5` (`BattleUnit`)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-06-17

---

## How to use this plan

Six **work groups** (A–F). Across groups: **A** (authored-data extensions) unblocks the tree and stats; **B** (`CharacterInstance` model) is the spine; **C** (progression ops) needs A+B; **D** (stat derivation + bridge) needs A+B and reuses the MVP combat path; **E** (tunables + accessors) is small and supports C/D; **F** (tests) trails B–E.

Each task lists a **done state**. Code stubs are Godot 4 / GDScript — drop-in starting points reusing existing classes (`StatBlock`, `BattleUnit.from_character`, `StatResolver`, `Validator`).

> **Carry-over:** A4 keeps the combat layer unchanged. The bridge produces a synthesized read-only `CharacterData` + a derived `StatBlock`, then calls the existing `BattleUnit.from_character`. `ClassData` already has `required_classes` (`[id, level]` pairs) which generalizes into `prerequisites`. A3's `MAG`/`RES` are valid in `stat_modifiers`/`growth`.

---

## Group A — Authored Data Extensions

*Unblocks the tree, stats, and content. Extends Resources + factory + validator; authors the root tree.*

### A1. `ClassData` + `RaceData` + template fields
- Add `archetype`, `branch`, `tier`, `growth`, `jp_costs`, `prerequisites` to `ClassData`; a `base_stats` profile to `RaceData`; `recommended_path`/`name_tables` to `CharacterData`.
- **Done:** Resources compile; defaults are neutral.

```gdscript
# src/core/data/class_data.gd  (additions)
@export var archetype: String = ""          # support|control|physical|magical
@export var branch: String = ""             # melee|ranged|arcane|divine|""
@export var tier: String = "starting"       # starting|tier1|advanced|elite
@export var growth: Dictionary = {}          # StatKey -> float rate
@export var jp_costs: Dictionary = {}        # ability_id -> int
@export var prerequisites: Dictionary = {}   # {"level": int, "classes": [[id, threshold], ...]}

# src/core/data/race_data.gd  (addition)
@export var base_stats: Dictionary = {}      # StatKey -> int baseline
```

### A2. `DataFactory` parsing
- Parse the new class/race/template fields; fold legacy `required_classes` into `prerequisites.classes`.
- **Done:** authored JSON populates the new fields; legacy maps still load.

### A3. `Validator` extensions
- Validate `archetype`/`tier` enums, `growth`/`jp_costs` stat/ability keys, and that `prerequisites` resolve and the tree is rooted at Vagabond (no cycles).
- **Done:** bad archetype/tier/prereq yields a precise error; clean content passes.

### A4. Author the root tree + names
- `vagabond`, `thief`, `soldier`, `adept` classes (archetype/branch/tier/growth/jp_costs/prereqs) + a few starter abilities each; `data/names/<race>.json` name tables; set race `base_stats`.
- **Done:** content loads and validates; Vagabond is `tier: starting`, the other three require Vagabond + level 3.

---

## Group B — `CharacterInstance` Model

*The spine. Pure `RefCounted`.*

### B1. Instance state + identity generation
- Fields per spec §4; a factory that generates id + name from a template's race name tables, starting Vagabond L1.
- **Done:** `generate(template)` yields a named Vagabond instance (tested in F1).

```gdscript
# src/core/progression/character_instance.gd
class_name CharacterInstance
extends RefCounted

var instance_id: String
var template_id: String
var name: String
var race: String
var level: int = 1
var xp: int = 0
var active_class: String = "vagabond"
var unlocked_classes: Array[String] = ["vagabond"]
var jp: Dictionary = {}                 # class_id -> int
var learned_abilities: Array[String] = []
var ability_loadout: Array[String] = []
var equipment: Dictionary = {}          # slot -> item_id
var growth_accumulated: Dictionary = {} # StatKey -> int
var downs_this_run: int = 0

static func generate(template: CharacterData, name_gen: Callable) -> CharacterInstance:
    var ci := CharacterInstance.new()
    ci.instance_id = "ci_%d" % (Time.get_ticks_usec())   # replace with a UUID helper
    ci.template_id = template.id
    ci.race = template.race
    ci.name = name_gen.call(template.race)
    ci.unlocked_classes = ["vagabond"]
    ci.active_class = "vagabond"
    return ci
```

### B2. Name generator
- Draw given/surname from `data/names/<race>.json`.
- **Done:** names vary by race; deterministic with a seeded RNG for tests.

---

## Group C — Progression Operations

*Depends on A+B. Leveling, JP, unlocks, loadout, equip.*

### C1. XP & leveling with growth
- `gain_xp`; on threshold, level up and accumulate the active class's `growth`.
- **Done:** crossing a threshold raises level and updates `growth_accumulated`; caps at `MAX_LEVEL`.

```gdscript
func gain_xp(amount: int, class_provider: Callable) -> void:
    xp += amount
    while level < Constants.get_value("MAX_LEVEL", 50) and xp >= xp_for_next(level):
        level += 1
        var cls: ClassData = class_provider.call(active_class)
        for k in cls.growth.keys():
            growth_accumulated[k] = int(floor(float(growth_accumulated.get(k, 0)) + float(cls.growth[k])))
```

### C2. JP earn & learn
- `gain_jp(class_id, n)`; `learn_ability(ability_id, class_provider)` checks unlocked class + `jp_costs` and deducts.
- **Done:** affordable abilities learn and persist; unaffordable/locked are rejected.

```gdscript
func learn_ability(ability_id: String, class_id: String, class_provider: Callable) -> bool:
    if not unlocked_classes.has(class_id): return false
    var cost: int = int(class_provider.call(class_id).jp_costs.get(ability_id, -1))
    if cost < 0 or int(jp.get(class_id, 0)) < cost: return false
    jp[class_id] = int(jp.get(class_id, 0)) - cost
    if not learned_abilities.has(ability_id): learned_abilities.append(ability_id)
    return true
```

### C3. Class unlock & upgrade
- `can_unlock(class_id)` checks `prerequisites` (level + per-class thresholds); `unlock_class` pays cost and adds; `set_active_class` switches among unlocked.
- **Done:** Vagabond unlocks Thief/Soldier/Adept at level 3; deeper classes gate on their prereqs.

```gdscript
func can_unlock(class_id: String, class_provider: Callable) -> bool:
    var pre: Dictionary = class_provider.call(class_id).prerequisites
    if level < int(pre.get("level", 0)): return false
    for pair in pre.get("classes", []):
        if not unlocked_classes.has(pair[0]): return false
        if int(jp.get(pair[0], 0)) < int(pair[1]) and level < int(pair[1]):
            return false   # threshold interpreted per design (JP or level)
    return true
```

### C4. Loadout & equipment
- `set_loadout(abilities)` enforces subset-of-learned and `ABILITY_SLOTS`; `equip(slot, item_id)` checks active-class `equipment_access`.
- **Done:** loadout/equip reject invalid entries; valid ones stick.

---

## Group D — Stat Derivation & BattleUnit Bridge

*Depends on A+B. Reuses the MVP combat path.*

### D1. `InstanceStatResolver`
- Compute base `StatBlock` = race base + active-class modifiers + accumulated growth, iterating `StatKey`.
- **Done:** derived stats match hand-computed values for a sample instance (F-tested).

```gdscript
# src/core/progression/instance_stat_resolver.gd
class_name InstanceStatResolver
extends RefCounted

static func resolve(ci: CharacterInstance, race_provider: Callable, class_provider: Callable) -> StatBlock:
    var sb := StatBlock.new()
    var race: RaceData = race_provider.call(ci.race)
    var cls: ClassData = class_provider.call(ci.active_class)
    for k in StatKey.all_strings():
        var v: int = int(race.base_stats.get(k, 0))
        v += int(cls.stat_modifiers.get(k, 0))
        v += int(ci.growth_accumulated.get(k, 0))
        sb.set_base(k, v)
    return sb
```

### D2. Synthesized `CharacterData` snapshot
- `to_character_data()` builds a transient read-only `CharacterData` exposing classes/equipment/abilities the combat layer reads.
- **Done:** snapshot carries active class, loadout, equipment, race, name, derived base.

```gdscript
# character_instance.gd
func to_character_data(stat_block: StatBlock) -> CharacterData:
    var c := CharacterData.new()
    c.id = instance_id; c.display_name = name; c.race = race
    c.classes = [active_class]
    c.level = level
    c.equipment = _equipment_array()
    c.abilities = ability_loadout.duplicate()
    c.base_stats = {}                       # snapshot already-derived effective base
    for k in StatKey.all_strings(): c.base_stats[k] = stat_block.base(k)
    return c
```

### D3. `BattleUnit.from_instance`
- Convenience that derives stats, builds the snapshot, and delegates to `BattleUnit.from_character`.
- **Done:** the produced `BattleUnit` runs through existing combat with no other changes.

```gdscript
# src/core/data/battle_unit.gd  (addition)
static func from_instance(ci: CharacterInstance, race_provider: Callable, class_provider: Callable) -> BattleUnit:
    var sb := InstanceStatResolver.resolve(ci, race_provider, class_provider)
    return BattleUnit.from_character(ci.to_character_data(sb), sb)
```

---

## Group E — Tunables & Accessors

### E1. Constants
- Add `MAX_LEVEL`, `TIER1_UNLOCK_LEVEL`, `XP_CURVE` (table/formula), `JP_PER_BATTLE`, `JP_SHARE`, `ABILITY_SLOTS`, `CLASS_UNLOCK_COST`, `GROWTH_MODEL` to `constants.json`.
- **Done:** readable via `Constants.get_value`.

### E2. Template/name accessors
- `GameData` helpers to list templates and load name tables; class accessor already exists (`get_job_class`).
- **Done:** templates and name tables are queryable.

---

## Group F — Tests & Verification

### F1. Instance & identity (GUT)
- `generate` yields Vagabond L1 with a race-appropriate name and a stable id.
- **Done:** green.

### F2. Progression (GUT)
- Leveling applies growth and caps; JP learn respects cost/unlock; unlock gates on prerequisites (Vagabond→tier1 at level 3); loadout enforces slots/subset.
- **Done:** green.

```gdscript
# tests/core/progression/test_progression.gd
extends GutTest

func test_tier1_unlocks_at_level_3() -> void:
    var ci := _vagabond()
    assert_false(ci.can_unlock("soldier", _class_provider))   # level 1
    _level_to(ci, 3)
    assert_true(ci.can_unlock("soldier", _class_provider))

func test_learn_respects_jp_cost() -> void:
    var ci := _vagabond()
    assert_false(ci.learn_ability("power_strike", "vagabond", _class_provider))  # no JP
    ci.gain_jp("vagabond", 100)
    assert_true(ci.learn_ability("power_strike", "vagabond", _class_provider))

func test_loadout_caps_at_ability_slots() -> void:
    var ci := _vagabond()
    ci.learned_abilities = ["a","b","c","d","e","f","g"]
    ci.set_loadout(["a","b","c","d","e","f","g"])
    assert_lte(ci.ability_loadout.size(), Constants.get_value("ABILITY_SLOTS", 6))
```

### F3. Stat derivation & bridge (GUT)
- `InstanceStatResolver` matches hand-computed base; `BattleUnit.from_instance` yields a unit with correct HP/WP and a usable kit; a resolved attack/spell runs through `CombatResolver` unchanged.
- **Done:** green.

### F4. Content validation
- Boot the pipeline with the root tree + name tables; assert clean load and a valid Vagabond-rooted tree.
- **Done:** `GameData` loads with no validation errors.

---

## Dependency Map

```
A (data ext + root tree) ──┬──> C (progression) ──┐
B (CharacterInstance) ─────┤                       ├──> F (tests)
A + B ─────────────────────┴──> D (stat + bridge) ─┤
E (tunables/accessors) ─────────────────────────────┘
```

**Suggested first pass:** A1–A4 → B1–B2 → E1 → C1–C4 → D1–D3 → F1–F4. Author the four root classes early so progression and bridge tests have real data.

---

## Phase A4 Definition of Done

- [ ] `CharacterInstance` model + identity generation; starts Vagabond L1 (B).
- [ ] Leveling with class-driven growth (cap `MAX_LEVEL`); JP earn/spend learning; class unlock/upgrade via prerequisites (C).
- [ ] Vagabond unlocks Thief/Soldier/Adept at `TIER1_UNLOCK_LEVEL`; free-form loadout (≤ `ABILITY_SLOTS`); equipment gated by active class (C).
- [ ] `ClassData`/`RaceData`/template extensions + `DataFactory`/`Validator`; root tree + name tables authored and validating (A).
- [ ] `InstanceStatResolver` + `to_character_data` + `BattleUnit.from_instance` producing a combat-ready unit with no combat-layer changes (D).
- [ ] Progression tunables in `constants.json` (E).
- [ ] Unit tests for identity, progression, derivation, and the bridge green; content validates (F).
- [ ] Git tag `alpha-phaseA4-complete`.
