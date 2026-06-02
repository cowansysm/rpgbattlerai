# Phase 0 — Implementation Plan

**Source spec:** `phase0-spec.md`
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Hex orientation:** **Flat-top** (committed)
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-05-29

---

## How to use this plan

Work is organized into six **work groups** (A–F). Within a group, tasks can be tackled in any order unless a dependency is noted. Across groups, follow the dependency notes: **A** unblocks everything; **B** (hex math) and **C** (data pipeline) are independent of each other and can run in parallel; **D** (autoloads) needs C's Resource types; **E** (boot) needs A and D; **F** (tests) trails B and C.

Each task lists a **done state**. Code stubs are Godot 4 / GDScript and meant as drop-in starting points, not final implementations.

> **Note on flat-top + axial coords:** the six axial neighbor vectors and hex distance are **orientation-independent** — flat-top vs pointy-top only changes pixel/layout math, which lands in Phase 2 (rendering). This plan records the flat-top decision and the layout constants now so nothing downstream has to revisit it.

---

## Group A — Project & Repository Setup

*Unblocks all other groups. Do this first.*

### A1. Create the Godot project
- Create a new Godot **4.6.3** project, renderer **Forward+**, name it (e.g., `tactics-sim`).
- Set the run/main scene to `res://scenes/main/main.tscn` (created in E1).
- **Done:** project opens in Godot 4.6.3 with no errors.

### A2. Initialize Git + `.gitignore`
- `git init` at the project root; add the Godot 4 ignore set.
- **Done:** first commit contains `project.godot` and source, excludes `.godot/`.

```gitignore
# Godot 4+
.godot/
/android/
# Builds
/build/
*.exe
*.pck
*.zip
# OS / editor
.DS_Store
Thumbs.db
.vscode/
.idea/
```

### A3. Create the folder structure
Create the directory tree from the spec (use `.gdignore`-free empty `.gdkeep` files to commit empty dirs if desired):

```
res://
├── addons/gut/
├── assets/
├── data/{characters,classes,races,abilities,items,maps}/
├── data/constants.json
├── src/core/{hex,data}/
├── src/autoload/
├── src/debug/
├── scenes/main/
└── tests/{core,data}/
```
- **Done:** tree exists and is committed.

### A4. README
- Document: pinned engine version (4.6.3), how to open, how to run tests (editor + headless CLI), folder conventions, and the **flat-top** hex decision.
- **Done:** `README.md` present and accurate.

### A5. Editor/style conventions
- Adopt typed GDScript, `snake_case` files, `PascalCase` `class_name`, `UPPER_SNAKE` constants. Optionally add an `.editorconfig`.
- **Done:** conventions noted in README; enforced by review.

---

## Group B — Hex Coordinate Math Module

*Independent of C/D. Depends only on A3. Pure logic, no scene tree — fully unit-testable.*

### B1. Define orientation & layout constants
- Commit **flat-top** layout constants for later rendering (kept here so the decision lives in code).
- **Done:** `HexLayout` constants exist; used by nothing yet but referenced in README.

```gdscript
# src/core/hex/hex_layout.gd
class_name HexLayout
extends RefCounted

# Flat-top orientation. Layout/pixel math is consumed in Phase 2 (rendering);
# defined here so the orientation decision is committed in Phase 0.
const ORIENTATION := "flat_top"

# Flat-top forward conversion matrix (size applied in Phase 2):
#   x = size * (3/2 * q)
#   y = size * (sqrt(3)/2 * q + sqrt(3) * r)
const F0 := 1.5
const F1 := 0.0
const F2 := 0.8660254037844386   # sqrt(3)/2
const F3 := 1.7320508075688772   # sqrt(3)
```

### B2. Coordinate conversions (axial ↔ cube)
- Axial `(q, r)` is canonical; cube `(x, y, z)` is derived for distance/rounding.
- **Done:** round-trip `axial → cube → axial` is identity (tested in F2).

```gdscript
# src/core/hex/hex.gd
class_name Hex
extends RefCounted

static func axial_to_cube(a: Vector2i) -> Vector3i:
    var x := a.x
    var z := a.y
    var y := -x - z
    return Vector3i(x, y, z)

static func cube_to_axial(c: Vector3i) -> Vector2i:
    return Vector2i(c.x, c.z)
```

### B3. Neighbors & directions
- Six axial direction vectors (orientation-independent).
- **Done:** `neighbors()` returns 6 unique hexes; tested in F2.

```gdscript
const DIRECTIONS: Array[Vector2i] = [
    Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
    Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

static func neighbor(a: Vector2i, dir: int) -> Vector2i:
    return a + DIRECTIONS[dir]

static func neighbors(a: Vector2i) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for d in DIRECTIONS:
        out.append(a + d)
    return out
```

### B4. Distance
- Cube/Manhattan-over-2 distance.
- **Done:** symmetric, zero to self, 1 to each neighbor; tested in F2.

```gdscript
static func distance(a: Vector2i, b: Vector2i) -> int:
    var ac := axial_to_cube(a)
    var bc := axial_to_cube(b)
    return (abs(ac.x - bc.x) + abs(ac.y - bc.y) + abs(ac.z - bc.z)) / 2
```

### B5. Range query
- All hexes within radius N.
- **Done:** cardinality `3*N*(N+1)+1`; tested in F2.

```gdscript
static func hexes_in_range(center: Vector2i, n: int) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for dq in range(-n, n + 1):
        for dr in range(max(-n, -dq - n), min(n, -dq + n) + 1):
            out.append(center + Vector2i(dq, dr))
    return out
```

### B6. Cube rounding (for future pixel→hex)
- Needed later for input; stub now with a test.
- **Done:** rounds a fractional cube to a valid integer cube; tested in F2.

```gdscript
static func cube_round(fx: float, fy: float, fz: float) -> Vector3i:
    var rx := roundi(fx)
    var ry := roundi(fy)
    var rz := roundi(fz)
    var dx := absf(rx - fx)
    var dy := absf(ry - fy)
    var dz := absf(rz - fz)
    if dx > dy and dx > dz:
        rx = -ry - rz
    elif dy > dz:
        ry = -rx - rz
    else:
        rz = -rx - ry
    return Vector3i(rx, ry, rz)
```

### B7. Elevation helpers (stubs for later phases)
- Elevation is a separate int, **not** part of hex distance. Provide a helper used by Jump/Climb later.
- **Done:** helper exists and is tested for sign/magnitude.

```gdscript
static func elevation_step(from_elev: int, to_elev: int) -> int:
    return absi(to_elev - from_elev)
```

---

## Group C — Data Pipeline (JSON → Resources)

*Independent of B. Depends on A3. Provides Resource types that Group D consumes.*

### C1. `StatKey` enum
- The canonical stat-key enum per `rpg-specs.md` §4.2.1. All stat-keyed dictionaries across the project validate against this enum.
- **Done:** enum compiles; `to_string()`/`from_string()` round-trip tested in F3.

```gdscript
# src/core/data/stat_key.gd
class_name StatKey
extends RefCounted

enum Key { SPD, ATK, RNG, DEF, HP }

const KEYS: Array[Key] = [Key.SPD, Key.ATK, Key.RNG, Key.DEF, Key.HP]

const _STRINGS: Dictionary = {
    Key.SPD: "spd", Key.ATK: "atk", Key.RNG: "rng", Key.DEF: "def", Key.HP: "hp"
}

static func to_string_key(k: Key) -> String:
    return _STRINGS[k]

static func from_string(s: String) -> Key:
    for k in _STRINGS.keys():
        if _STRINGS[k] == s:
            return k as Key
    push_error("StatKey: unknown key '%s'" % s)
    return Key.SPD

static func all_strings() -> Array[String]:
    var out: Array[String] = []
    for k in KEYS:
        out.append(_STRINGS[k])
    return out

static func is_valid_key(s: String) -> bool:
    return s in _STRINGS.values()
```

### C1b. `TileRecord` typed class
- A typed container for individual map tile data, replacing raw dictionaries in `MapData.tiles`.
- **Done:** class compiles; fields accessible by type.

```gdscript
# src/core/data/tile_record.gd
class_name TileRecord
extends RefCounted

var q: int
var r: int
var elevation: int
var terrain: String

func _init(tq: int = 0, tr: int = 0, te: int = 0, tt: String = "grass") -> void:
    q = tq; r = tr; elevation = te; terrain = tt

func coord() -> Vector2i:
    return Vector2i(q, r)
```

### C1c. Define Resource classes
- One typed `Resource` per entity, mirroring `rpg-specs.md` §9. Start minimal; expand fields as later phases need them.
- **Done:** classes compile and appear with `class_name`.

```gdscript
# src/core/data/character_data.gd
class_name CharacterData
extends Resource

@export var id: String
@export var display_name: String
@export var race: String
@export var classes: Array[String] = []
@export var level: int
@export var bp: int
@export var spd: int
@export var atk: int
@export var rng: int
@export var def: int
@export var hp: int
@export var equipment: Array[String] = []
@export var abilities: Array[String] = []
```

> Create sibling classes the same way: `ClassData`, `RaceData`, `AbilityData`, `ItemData`, `MapData` — fields per spec §9. Keep them thin in Phase 0.

### C2. JSON loader
- Read a directory of `.json` files, parse, and map onto a Resource type via a factory callback. Engine-light so it's testable.
- **Done:** loads a directory into a `{ id: Resource }` dictionary.

```gdscript
# src/core/data/json_loader.gd
class_name JsonLoader
extends RefCounted

# factory: Callable(dict) -> Resource
static func load_dir(dir_path: String, factory: Callable) -> Dictionary:
    var out := {}
    var dir := DirAccess.open(dir_path)
    if dir == null:
        push_error("JsonLoader: cannot open dir %s" % dir_path)
        return out
    for file_name in dir.get_files():
        if not file_name.ends_with(".json"):
            continue
        var path := dir_path.path_join(file_name)
        var text := FileAccess.get_file_as_string(path)
        var parsed: Variant = JSON.parse_string(text)
        if typeof(parsed) != TYPE_DICTIONARY:
            push_error("JsonLoader: %s is not a JSON object" % path)
            continue
        var res: Resource = factory.call(parsed)
        if res != null and res.get("id") != null:
            out[res.id] = res
    return out
```

### C3. Validator
- Required-field, type, range, and referential-integrity checks. **Fail loud** in dev (return errors; caller aborts load).
- **Done:** a valid sample passes; a malformed sample yields a precise error.

```gdscript
# src/core/data/validator.gd
class_name Validator
extends RefCounted

# Returns an Array[String] of error messages (empty == valid).
static func validate_character(d: Dictionary) -> Array[String]:
    var errors: Array[String] = []
    for key in ["id", "race", "classes", "level", "bp", "hp"]:
        if not d.has(key):
            errors.append("character missing required field '%s'" % key)
    if d.has("hp") and typeof(d["hp"]) == TYPE_FLOAT and d["hp"] <= 0:
        errors.append("character '%s' has non-positive hp" % d.get("id", "?"))
    return errors
```

### C4. Sample data files
- Author one valid `data/characters/human_archer.json` (from spec §6) and a deliberately broken fixture under `tests/` for negative testing. Add `data/constants.json` with the spec's tunable values.
- **Done:** files parse; the valid one loads, the broken one is rejected.

```json
// data/characters/human_archer.json
{
  "id": "human_archer",
  "display_name": "Human Archer",
  "race": "human",
  "classes": ["archer"],
  "level": 2, "bp": 13,
  "spd": 3, "atk": 2, "rng": 2, "def": 1, "hp": 10,
  "equipment": ["bow", "bracer_of_accuracy", "light_armor"],
  "abilities": []
}
```

```json
// data/constants.json
{
  "ELEV_BONUS": 1,
  "COVER_DEF": 1,
  "ROUT_THRESHOLD": 0.25,
  "tiers": {
    "skirmish": { "bp_cap": 100, "min": 3, "max": 5 },
    "standard": { "bp_cap": 150, "min": 4, "max": 8 },
    "large":    { "bp_cap": 250, "min": 6, "max": 12 }
  }
}
```

---

## Group D — Autoloads (Singletons)

*Depends on C1–C3. Register after the data layer exists.*

### D1. `Logger`
- Levels (DEBUG/INFO/WARN/ERROR), simple console output; used by everything else.
- **Done:** registered as autoload; messages print with level + tag.

```gdscript
# src/autoload/logger.gd  (Autoload name: Logger)
extends Node

enum Level { DEBUG, INFO, WARN, ERROR }
var min_level: Level = Level.DEBUG

func log_msg(level: Level, tag: String, msg: String) -> void:
    if level < min_level:
        return
    print("[%s][%s] %s" % [Level.keys()[level], tag, msg])
```

### D2. `Constants`
- Loads `data/constants.json` on `_ready`; exposes typed getters (tiers, ELEV_BONUS, etc.).
- **Done:** values readable from any script after boot.

```gdscript
# src/autoload/constants.gd  (Autoload name: Constants)
extends Node

var values: Dictionary = {}

func _ready() -> void:
    var text := FileAccess.get_file_as_string("res://data/constants.json")
    values = JSON.parse_string(text) if text != "" else {}

func get_value(key: String, default_value: Variant = null) -> Variant:
    return values.get(key, default_value)
```

### D3. `GameData` (facade)
- A thin facade that delegates to per-domain registry objects. In Phase 0, only a character registry exists. On `_ready`, loads content via `JsonLoader` (validating first), exposes lookups. Aborts loudly on validation failure.
- Phase 1 generalizes this with `EntityRegistry` per type (see Phase 1 Group B).
- **Done:** `GameData.get_character("human_archer")` returns a `CharacterData`.

```gdscript
# src/autoload/game_data.gd  (Autoload name: GameData)
extends Node

var _characters: Dictionary = {}   # id -> CharacterData (Phase 1 replaces with EntityRegistry)

func _ready() -> void:
    _load_characters()
    Logger.log_msg(Logger.Level.INFO, "GameData",
        "loaded %d characters" % _characters.size())

func _load_characters() -> void:
    _characters = JsonLoader.load_dir("res://data/characters",
        func(d: Dictionary) -> Resource:
            var errors := Validator.validate_character(d)
            if not errors.is_empty():
                push_error("Invalid character: %s" % ", ".join(errors))
                return null
            var c := CharacterData.new()
            c.id = d["id"]; c.display_name = d.get("display_name", d["id"])
            c.race = d["race"]; c.level = d["level"]; c.bp = d["bp"]
            c.spd = d.get("spd", 0); c.atk = d.get("atk", 0)
            c.rng = d.get("rng", 0); c.def = d.get("def", 0); c.hp = d["hp"]
            return c)

func get_character(id: String) -> CharacterData:
    return _characters.get(id)
```

### D4. Register autoloads
- Add `Logger`, `Constants`, `GameData` in Project Settings → Autoload **in that order** (Logger first; GameData last, since it uses both).
- **Done:** autoloads listed and load without error.

---

## Group E — Boot / Entry Point

*Depends on A (project) and D (autoloads).*

### E1. `Main` scene
- A minimal scene set as the run scene. On ready, log that data loaded and otherwise render nothing.
- **Done:** running the project prints the GameData load summary, no errors.

```gdscript
# scenes/main/main.gd  (attached to scenes/main/main.tscn root Node)
extends Node

func _ready() -> void:
    Logger.log_msg(Logger.Level.INFO, "Main", "Boot OK")
    var archer := GameData.get_character("human_archer")
    if archer:
        Logger.log_msg(Logger.Level.INFO, "Main",
            "Sample character: %s (BP %d)" % [archer.display_name, archer.bp])
```

### E2. Debug dump (optional)
- A `src/debug/` helper to dump the loaded registries on a keypress for inspection.
- **Done:** dev-only; not wired into player flow.

---

## Group F — Test Harness (GUT)

*Trails B and C; finalize before declaring Phase 0 done.*

### F1. Install GUT
- Vendor GUT under `addons/gut/`, enable the plugin, configure a `.gutconfig.json` so tests can run headless from CLI.
- **Done:** GUT panel appears; `godot --headless -s addons/gut/gut_cmdln.gd` runs.

### F2. Hex math tests
- Cover B2–B7: conversion round-trip, neighbor count/uniqueness, distance symmetry + neighbor distance == 1, range cardinality, cube rounding validity, elevation helper.
- **Done:** all green.

```gdscript
# tests/core/test_hex.gd
extends GutTest

func test_axial_cube_roundtrip() -> void:
    var a := Vector2i(2, -3)
    assert_eq(Hex.cube_to_axial(Hex.axial_to_cube(a)), a)

func test_neighbors_count() -> void:
    assert_eq(Hex.neighbors(Vector2i(0, 0)).size(), 6)

func test_distance_to_neighbor_is_one() -> void:
    for nb in Hex.neighbors(Vector2i(0, 0)):
        assert_eq(Hex.distance(Vector2i(0, 0), nb), 1)

func test_range_cardinality() -> void:
    var n := 2
    assert_eq(Hex.hexes_in_range(Vector2i(0, 0), n).size(), 3 * n * (n + 1) + 1)
```

### F3. Data pipeline tests
- Valid sample loads into a `CharacterData`; broken fixture produces validator errors and is excluded.
- `StatKey` round-trips through `to_string_key` / `from_string`; `is_valid_key` rejects unknown keys.
- `TileRecord` initializes with correct typed fields; `coord()` returns matching `Vector2i`.
- **Done:** positive and negative cases pass.

```gdscript
# tests/data/test_loader.gd
extends GutTest

func test_valid_character_passes_validation() -> void:
    var d := {"id": "x", "race": "human", "classes": ["archer"],
              "level": 1, "bp": 5, "hp": 10}
    assert_eq(Validator.validate_character(d).size(), 0)

func test_missing_field_fails_validation() -> void:
    var d := {"id": "x"}
    assert_true(Validator.validate_character(d).size() > 0)
```

```gdscript
# tests/data/test_stat_key.gd
extends GutTest

func test_roundtrip() -> void:
    for k in StatKey.KEYS:
        var s := StatKey.to_string_key(k)
        assert_eq(StatKey.from_string(s), k)

func test_invalid_key_rejected() -> void:
    assert_false(StatKey.is_valid_key("magic_power"))
    assert_true(StatKey.is_valid_key("spd"))
```

```gdscript
# tests/data/test_tile_record.gd
extends GutTest

func test_fields() -> void:
    var t := TileRecord.new(3, -1, 2, "trees")
    assert_eq(t.q, 3)
    assert_eq(t.r, -1)
    assert_eq(t.elevation, 2)
    assert_eq(t.terrain, "trees")
    assert_eq(t.coord(), Vector2i(3, -1))
```

### F4. Document the test command
- Add the editor + headless instructions to the README.
- **Done:** anyone can run the suite from a documented command.

---

## Dependency Map

```
A (setup) ──┬──> B (hex math) ─────────────┐
            ├──> C (data types/loader) ──> D (autoloads) ──> E (boot)
            └──> F1 (GUT install)
B ──> F2 (hex tests)
C ──> F3 (pipeline tests)
```

**Suggested first pass:** A1–A3 → (B2–B5 ∥ C1–C2) → C3–C4 → D → E1 → F. Everything else (A4–A5, B1/B6/B7, E2) slots in opportunistically.

---

## Phase 0 Definition of Done

- [ ] Project boots to `Main`, prints GameData load summary, no errors (E1).
- [ ] Git repo + `.gitignore` + README with engine version, test command, flat-top decision (A2, A4).
- [ ] Folder structure and conventions in place (A3, A5).
- [ ] Hex module complete: conversions, neighbors, distance, range, rounding, elevation helper (B2–B7).
- [ ] `StatKey` enum defined with all MVP keys + string conversion helpers; tested (C1).
- [ ] `TileRecord` typed class defined with `q`/`r`/`elevation`/`terrain` fields; tested (C1b).
- [ ] Data pipeline: Resource types, loader, validator, sample + constants, fail-loud on invalid (C1c–C4).
- [ ] Autoloads `Logger`/`Constants`/`GameData` (facade) registered and loading (D1–D4).
- [ ] GUT installed; hex + pipeline + StatKey + TileRecord tests green, runnable headless (F1–F4).
- [ ] Git tag `phase-0-complete`.
```

