# Phase A5 — Implementation Plan

**Source spec:** `alpha-phaseA5-spec.md`
**Master spec:** `alpha-specs.md` (§7, §9.2/§9.4)
**Builds on (Alpha):** `alpha-phaseA4-implementation-plan.md` (`CharacterInstance`, `BattleUnit.from_instance`, `InstanceStatResolver`)
**Builds on (MVP):** `phase7-implementation-plan.md` (`MatchBuilder`, `DraftScene`, `MatchData`), `phase1` (`GameData`)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-06-17

---

## How to use this plan

Six **work groups** (A–F). Across groups: **A** (`BattleBand` + serialization) unblocks persistence and UI; **B** (`SaveManager`) needs A; **C** (band → battle) needs A and the A4 bridge; **D** (management UI) needs A+B+C and the A4 ops; **E** (recruitment + tunables) supports A/D; **F** (tests) trails A–E.

Each task lists a **done state**. Code stubs are Godot 4 / GDScript — drop-in starting points reusing A4 (`CharacterInstance`, `BattleUnit.from_instance`) and the MVP match pipeline.

> **Carry-over:** A5 builds parties from instances via `BattleUnit.from_instance` (A4) and feeds the existing `MatchSetup`/`Deployment`/`RoundManager`. `DraftScene` already sets `MatchData.match_state`/`map_id` and changes scene — the instance path mirrors that. No `user://` save code exists yet; `SaveManager` is new. New autoload registered after `GameData`.

---

## Group A — Battle Band Model & Serialization

*Unblocks B–D. Pure data.*

### A1. `BattleBand` model
- Roster, inventory (equipment + consumables), gold; add/remove/equipment-move ops; `ROSTER_CAP`.
- **Done:** band ops mutate state correctly; roster bounded.

```gdscript
# src/core/progression/battle_band.gd
class_name BattleBand
extends RefCounted

var band_id: String
var name: String = "New Band"
var roster: Array[CharacterInstance] = []
var inventory: Dictionary = {"equipment": [], "consumables": []}   # equipment: [id], consumables: [{id, qty}]
var gold: int = 0

func add_instance(ci: CharacterInstance) -> bool:
    if roster.size() >= Constants.get_value("ROSTER_CAP", 12): return false
    roster.append(ci); return true

func remove_instance(instance_id: String) -> void:
    roster = roster.filter(func(c): return c.instance_id != instance_id)

func assign_equipment(ci: CharacterInstance, slot: String, item_id: String) -> void:
    # move from inventory to slot; return the displaced item to inventory
    pass
```

### A2. Instance & band (de)serialization
- `CharacterInstance.to_dict/from_dict` and `BattleBand.to_dict/from_dict`; ids reference `GameData` content.
- **Done:** `from_dict(to_dict(x))` round-trips (tested in F1).

```gdscript
# character_instance.gd  (additions)
func to_dict() -> Dictionary:
    return {"instance_id": instance_id, "template_id": template_id, "name": name, "race": race,
        "level": level, "xp": xp, "active_class": active_class,
        "unlocked_classes": unlocked_classes, "jp": jp,
        "learned_abilities": learned_abilities, "ability_loadout": ability_loadout,
        "equipment": equipment, "growth_accumulated": growth_accumulated,
        "downs_this_run": downs_this_run}

static func from_dict(d: Dictionary) -> CharacterInstance:
    var ci := CharacterInstance.new()
    ci.instance_id = str(d.get("instance_id", ""))
    ci.template_id = str(d.get("template_id", ""))
    ci.name = str(d.get("name", ""))
    ci.race = str(d.get("race", ""))
    ci.level = int(d.get("level", 1))
    ci.xp = int(d.get("xp", 0))
    ci.active_class = str(d.get("active_class", "vagabond"))
    ci.unlocked_classes = _to_str_array(d.get("unlocked_classes", ["vagabond"]))
    ci.jp = d.get("jp", {})
    ci.learned_abilities = _to_str_array(d.get("learned_abilities", []))
    ci.ability_loadout = _to_str_array(d.get("ability_loadout", []))
    ci.equipment = d.get("equipment", {})
    ci.growth_accumulated = d.get("growth_accumulated", {})
    ci.downs_this_run = int(d.get("downs_this_run", 0))
    return ci
```

### A3. Instance BP recompute
- A `BpCalculator.for_instance(ci, providers)` using the MVP heuristic over level/effective stats/loadout/equipment.
- **Done:** BP updates when level/loadout/equipment change.

---

## Group B — SaveManager (Persistence)

*Depends on A. New autoload after `GameData`.*

### B1. `SaveManager` load/save
- Read/write the versioned root document under `user://saves/save.json`; safe on first run; atomic write.
- **Done:** saving then loading reconstructs identical bands (F2).

```gdscript
# src/autoload/save_manager.gd   (Autoload: SaveManager, after GameData)
extends Node

const SAVE_PATH := "user://saves/save.json"
const SAVE_VERSION := 1

var bands: Array[BattleBand] = []
var profile: Dictionary = {}        # reserved (A8/A10)
var active_run: Variant = null      # reserved (A8)

func has_save() -> bool:
    return FileAccess.file_exists(SAVE_PATH)

func load_game() -> void:
    bands.clear()
    if not has_save(): return
    var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
    if typeof(raw) != TYPE_DICTIONARY: return
    raw = _migrate(raw)
    profile = raw.get("profile", {})
    active_run = raw.get("active_run", null)
    for bd in raw.get("bands", []):
        bands.append(BattleBand.from_dict(bd))

func save_game() -> void:
    DirAccess.make_dir_recursive_absolute("user://saves")
    var doc := {"save_version": SAVE_VERSION, "profile": profile,
        "active_run": active_run, "bands": bands.map(func(b): return b.to_dict())}
    var tmp := SAVE_PATH + ".tmp"
    var f := FileAccess.open(tmp, FileAccess.WRITE)
    f.store_string(JSON.stringify(doc)); f.close()
    DirAccess.rename_absolute(tmp, SAVE_PATH)   # atomic-ish swap
```

### B2. Migration + band lifecycle
- `_migrate(doc)` upgrades older `save_version`; `create_band/delete_band/active_band` helpers.
- **Done:** an older doc loads via migration; band create/delete work.

### B3. Register autoload
- Add `SaveManager="*res://src/autoload/save_manager.gd"` after `GameData` in `project.godot`.
- **Done:** boots clean; load order correct.

---

## Group C — Band → Battle Wiring

*Depends on A + A4 bridge.*

### C1. Party-from-instances builder
- Convert a fielded `Array[CharacterInstance]` to `Array[BattleUnit]` via `from_instance`.
- **Done:** a fielded selection yields a valid party (F3).

```gdscript
# src/core/progression/band_party_builder.gd
class_name BandPartyBuilder
extends RefCounted

static func build_party(fielded: Array, race_provider: Callable, class_provider: Callable) -> Array[BattleUnit]:
    var party: Array[BattleUnit] = []
    for ci in fielded:
        party.append(BattleUnit.from_instance(ci, race_provider, class_provider))
    return party
```

### C2. `MatchData` + match construction from bands
- Add active-band + fielded-selection refs to `MatchData`; a `MatchBuilder` entry (or `MatchSetup` call) that takes two instance parties.
- **Done:** a match builds from two instance parties and runs through `RoundManager`.

### C3. Quick-battle-from-band scene path
- Field a band subset vs a generated opponent band on a chosen map; hand off via `MatchData` like `DraftScene` does.
- **Done:** a battle plays end-to-end from a band (opponent manual/placeholder until A7).

### C4. Retain MVP hotseat
- Leave the premade-draft path intact; verify it still builds and plays.
- **Done:** MVP two-human draft → battle unchanged.

---

## Group D — Band Management UI

*Depends on A+B+C and A4 ops.*

### D1. Band overview + roster list
- Scene listing band name/gold and roster entries (name/level/class/BP); select an instance.
- **Done:** roster renders; selection drives the inspector.

### D2. Instance inspector + progression controls
- Show stats/level/XP/classes/learned/loadout/equipment/BP; buttons for learn (JP), unlock/switch class, set loadout.
- **Done:** controls invoke A4 `CharacterInstance` ops and refresh.

### D3. Equipment + recruit/dismiss
- Move gear between inventory and slots (gated by access); recruit from template; dismiss.
- **Done:** equip/recruit/dismiss mutate the band and persist on save.

### D4. Menu entry + save/load
- Reach management from the main menu (and A0 Dev Tools); Save writes via `SaveManager`; load on launch.
- **Done:** edits survive an app restart.

---

## Group E — Recruitment & Tunables

### E1. Recruitment generation
- Generate a scaled Vagabond instance from a template (A4 `generate`); optional `RECRUIT_COST` gold deduction.
- **Done:** a recruit joins the band at a sensible power level.

### E2. Constants
- Add `ROSTER_CAP`, `RECRUIT_COST`, and recruit power-scaling to `constants.json`.
- **Done:** readable via `Constants.get_value`.

---

## Group F — Tests & Verification

### F1. Serialization round-trip (GUT)
- `CharacterInstance` and `BattleBand` `from_dict(to_dict(x))` equality, including jp/growth/loadout/equipment.
- **Done:** green.

### F2. Save/load across simulated restart (GUT)
- Build bands, `save_game`, clear in-memory, `load_game`, assert identical; first-run (no file) yields empty state, no crash.
- **Done:** green.

```gdscript
# tests/core/progression/test_save_manager.gd
extends GutTest

func test_round_trip_save_load() -> void:
    var band := _band_with_two_instances()
    SaveManager.bands = [band]
    SaveManager.save_game()
    SaveManager.bands = []
    SaveManager.load_game()
    assert_eq(SaveManager.bands.size(), 1)
    assert_eq(SaveManager.bands[0].roster.size(), 2)

func test_first_run_is_empty_not_crash() -> void:
    # point SAVE_PATH at a nonexistent temp path; load_game yields empty
    SaveManager.load_game()
    assert_eq(SaveManager.bands.size(), 0)
```

### F3. Fielded party builds (GUT)
- `BandPartyBuilder.build_party` yields `BattleUnit`s with correct HP/kit; a built match runs a round.
- **Done:** green.

### F4. Manual UI checklist
- [ ] Create/name a band; recruit instances.
- [ ] Inspect; spend JP/learn; unlock/switch class; set loadout; equip from inventory.
- [ ] Save, restart, reload — band intact.
- [ ] Field a subset → quick battle plays.
- [ ] MVP hotseat draft still plays.
- **Done:** checklist passes.

---

## Dependency Map

```
A (band + serialize) ──┬──> B (SaveManager) ──┐
                       ├──> C (band→battle) ──┤
A + B + C + A4 ops ────┴──> D (management UI) ─┼──> F (tests)
E (recruit + tunables) ─────────────────────── ┘
```

**Suggested first pass:** A1–A3 → B1–B3 → C1–C2 → E1–E2 → D1–D4 → C3–C4 → F. Land serialization + save round-trip before building the UI on top.

---

## Phase A5 Definition of Done

- [ ] `BattleBand` model + ops + `ROSTER_CAP`; instance/band `to_dict`/`from_dict` round-trip (A, F1).
- [ ] `SaveManager` autoload: versioned `user://saves/save.json`, multiple bands, profile/run slots, migration, safe first-run, atomic write (B).
- [ ] Party-from-instances builder via `from_instance`; `MatchData` band/fielded refs; match builds from instance parties (C1–C2).
- [ ] Quick-battle-from-band plays; MVP hotseat retained (C3–C4).
- [ ] Management UI: inspect, JP/learn, unlock/switch, loadout, equip, recruit/dismiss, save/load (D).
- [ ] Recruitment generates scaled Vagabonds; tunables in `constants.json` (E).
- [ ] Instance BP recompute on change (A3).
- [ ] Serialization, save/load-restart, and fielded-party tests green; manual UI checklist passed (F).
- [ ] Git tag `alpha-phaseA5-complete`.
