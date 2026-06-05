# Phase 0 — Project Foundation Specification

**Parent plan:** `rpg-implementation-plan.md` (Phase 0)
**Source spec:** `rpg-specs.md`
**Engine:** Godot **4.6.3** (current stable, May 2026)
**Language:** GDScript
**Content pipeline:** JSON authored → Godot Resources at runtime
**Testing:** GUT (Godot Unit Test), local
**Date:** 2026-05-29

---

## 1. Purpose & Scope

Phase 0 establishes the technical foundation every later phase builds on. It produces **no gameplay** — instead it delivers a running Godot project with version control, a defined folder and scene structure, the content-loading pipeline (JSON → Resources), the hex coordinate system and math module, and a local unit-test harness.

**In scope:** engine setup, project settings, repo conventions, directory layout, autoloads, the data pipeline skeleton, the hex math library, and the test harness.

**Out of scope:** rendering the map, characters, combat, UI, party building, content authoring — all later phases.

### Exit criteria

Phase 0 is complete when:

1. The project opens in Godot 4.6.3 and runs to an empty main scene without errors.
2. The repository is initialized with a correct `.gitignore` and the agreed folder structure.
3. The hex math module exists and its GUT unit tests pass (distance, neighbors, coordinate conversions, elevation helpers).
4. The JSON-to-Resource loader can load a trivial sample data file into a typed Resource and is covered by a passing test.
5. A documented command/process runs the full test suite locally.

---

## 2. Engine & Tooling

| Item | Decision |
|------|----------|
| Engine | Godot **4.6.3** stable (standard, non-.NET build) |
| Language | **GDScript** (typed style — explicit type hints throughout) |
| Editor | Godot built-in editor; external editor optional via `editor_settings` |
| Test framework | **GUT** (Godot Unit Test) addon, run locally from the editor and CLI |
| Version control | Git |
| Min. target platform | Desktop (Windows/macOS/Linux); rendering method **Forward+** by default |

**Why these choices.** GDScript gives the fastest iteration and tightest engine integration for this scope. Authoring content as JSON keeps it engine-agnostic, diffable, and bulk-editable, while converting to typed Resources at load time preserves Godot's inspector and type-safety benefits downstream. GUT run locally is enough safety for a small team without CI overhead.

**Pinning the version.** Record the exact Godot version (4.6.3) in the README and avoid auto-upgrading mid-phase; the engine version is part of the project's reproducibility contract.

---

## 3. Repository & Version Control

### 3.1 Git setup

Initialize a Git repo at the project root. Commit the Godot project files; never commit the import cache or per-user editor state.

### 3.2 `.gitignore`

Use the official Godot 4 ignore set as the baseline:

```gitignore
# Godot 4+ specific ignores
.godot/
/android/

# Exported builds
/build/
*.exe
*.pck
*.zip

# OS / editor cruft
.DS_Store
Thumbs.db
.vscode/
.idea/
```

> `.godot/` (the import/cache directory) must be ignored; it is regenerated on open. `project.godot`, `*.tres`, `*.gd`, `*.import`, and content JSON **are** tracked.

### 3.3 Branching & commits

Trunk-based with short-lived feature branches is sufficient at this scale. Keep commits scoped and message-clear. Tag the end of each implementation phase (e.g., `phase-0-complete`).

---

## 4. Project Structure

A feature/system-oriented layout, with code, scenes, and data separated:

```
res://
├── project.godot
├── README.md
├── addons/
│   └── gut/                  # GUT test framework (vendored)
├── assets/                   # art, audio, fonts (placeholder in P0)
├── data/                     # authored JSON content (schemas from spec §9)
│   ├── characters/
│   ├── classes/
│   ├── races/
│   ├── abilities/
│   ├── items/
│   ├── maps/
│   └── constants.json        # tunable constants (ELEV_BONUS, etc.)
├── src/
│   ├── core/                 # engine-agnostic systems
│   │   ├── hex/              # hex coordinate + math module (§6)
│   │   └── data/             # loader, validator, Resource definitions (§5)
│   ├── autoload/             # singletons registered as autoloads (§4.2)
│   └── debug/                # debug harness, dev console (§7)
├── scenes/
│   └── main/                 # empty Main scene (entry point)
└── tests/                    # GUT test scripts (mirror src/ layout)
    ├── core/
    └── data/
```

### 4.1 Naming conventions

- Files/dirs: `snake_case`. Classes: `PascalCase` via `class_name`. Constants: `UPPER_SNAKE`.
- One primary class per script; name the file after the class.
- Use typed GDScript everywhere (`var x: int`, typed function signatures, typed arrays where practical).

### 4.2 Autoloads (singletons)

Register the minimum needed in Phase 0:

| Autoload | Responsibility |
|----------|----------------|
| `GameData` | Thin facade over per-domain registry objects. Orchestrates loading, cross-entity validation, and exposes typed lookup-by-id accessors. Read-only access for the rest of the game. |
| `Constants` | Loads `constants.json` and exposes tunable values (ELEV_BONUS, COVER_DEF, ROUT_THRESHOLD, tier definitions). |
| `Logger` | Lightweight logging with levels; used by the debug harness. |

Keep autoloads thin and stateless beyond loaded data; gameplay state lives in scenes and runtime state objects (e.g., `BattleUnit`) added in later phases.

### 4.3 Entry point

A single `Main` scene set as the project's run scene. In Phase 0 it boots, triggers `GameData` to load, logs success/failure, and otherwise renders nothing.

---

## 5. Content Pipeline (JSON → Resources)

### 5.1 Approach

Content is **authored as JSON** under `data/` following the schemas in `rpg-specs.md` §9. At load time the pipeline parses each JSON file, **validates** it, and instantiates a strongly-typed Godot **Resource** that the rest of the game consumes. The game logic never touches raw JSON — only the typed Resources.

### 5.2 Components

- **`StatKey` enum** (`src/core/data/stat_key.gd`): The canonical list of stat keys (`SPD`, `ATK`, `RNG`, `DEF`, `HP`) as defined in `rpg-specs.md` §4.2.1. All Resource definitions that carry stat dictionaries validate keys against `StatKey` at load. This enum is the single point of expansion when future stats are added.
- **`TileRecord`** (`src/core/data/tile_record.gd`): A typed container (`RefCounted`) for map tile data — `q: int`, `r: int`, `elevation: int`, `terrain: String` — replacing raw dictionaries in `MapData.tiles`. All consumers access tile properties through typed fields rather than dictionary key parsing.
- **Resource definitions** (`src/core/data/`): GDScript `Resource` subclasses with `class_name` for each entity — `CharacterData`, `ClassData`, `RaceData`, `AbilityData`, `ItemData`, `MapData`. Fields mirror the spec schemas.
- **Loader**: reads a directory of JSON files (`FileAccess` + `JSON.parse_string`), maps each object onto its Resource type, and returns a typed collection keyed by `id`.
- **Validator**: checks required fields, types, value ranges, and referential integrity (e.g., a character's `classes`/`equipment`/`abilities` IDs resolve to existing entries). Stat-keyed dictionaries are validated against `StatKey`. On failure it logs a clear, file-and-field-specific error and aborts the load (fail loud in dev).
- **Registry**: `GameData` is a thin facade that delegates to per-domain registry objects (e.g., `CharacterRegistry`, `ClassRegistry`). Each registry handles loading, structural validation, and storage for its entity type. `GameData` orchestrates loading order, cross-entity referential validation, and exposes the public lookup-by-id API.

### 5.3 Phase 0 deliverable

A minimal but real end-to-end slice: one sample JSON file (e.g., a single `CharacterData`), the matching Resource class, loader, and validator — plus a test proving a valid file loads and an invalid one is rejected. The `StatKey` enum and `TileRecord` class are defined and tested (compilation + round-trip). Full content authoring is Phase 6; Phase 0 only proves the pipeline works.

### 5.4 Error handling philosophy

- **Development:** validation failures are loud and fatal — surface the offending file and field immediately.
- **Design:** the loader is deterministic and side-effect free apart from populating the registry, so it is unit-testable without the full engine running.

---

## 6. Hex Coordinate System & Math Module

### 6.1 Coordinate system

Use **axial coordinates `(q, r)`** as the canonical 2D hex address (matching the `MapData` schema in the spec), with **cube coordinates** `(x, y, z)` derived internally for distance and rounding math. **Elevation** is a separate integer dimension layered on top of the 2D hex address; it is not part of the hex distance computation but feeds range/LoS/movement rules in later phases.

Pick and document a single orientation (pointy-top or flat-top) and stick with it project-wide.

### 6.2 Module responsibilities (`src/core/hex/`)

The hex module is pure, engine-light GDScript (no scene-tree dependency) so it is fully unit-testable:

- Axial ↔ cube conversion.
- **Distance** between two hexes.
- **Neighbors** (the six adjacent hexes) and direction vectors.
- **Range** queries (all hexes within N).
- Cube **rounding** (for any future pixel→hex needs).
- Optional helpers stubbed for later: line-drawing between hexes (LoS support), and elevation-difference helpers used by Jump/Climb.

> Pathfinding, LoS resolution, and rendering are **not** in this module yet — Phase 0 provides only the coordinate math primitives those systems will call.

### 6.3 Correctness

This module is the geometric backbone of the whole game; bugs here propagate everywhere. It must ship with thorough unit tests (§7) covering distance symmetry, neighbor counts and uniqueness, range cardinality, and conversion round-trips.

---

## 7. Debug & Test Harness

### 7.1 Unit testing — GUT

- Vendor the **GUT** addon under `addons/gut/` and enable it.
- Tests live in `tests/`, mirroring the `src/` layout, named `test_*.gd`.
- Phase 0 test coverage: the **hex math module** (§6) and the **data loader/validator** (§5).
- Tests run locally both from the GUT panel in the editor and headless from the command line so they can be invoked in one step (documented in the README). No CI in this phase.

### 7.2 Debug harness (`src/debug/`)

A lightweight in-editor debug aid: a `Logger` autoload with log levels and a simple toggleable on-screen/console output for development. Optionally a minimal dev command to dump the loaded `GameData` registry for inspection. This is a developer tool, not a player feature.

### 7.3 Definition of "tested" for Phase 0

Every public function in the hex module and the loader/validator has at least one positive and, where meaningful, one negative test. The suite passes green before Phase 0 is declared complete.

---

## 8. Risks & Notes

- **Hex orientation drift.** Choosing pointy- vs flat-top late causes rework in rendering and input. Decide and document in Phase 0.
- **Schema/Resource divergence.** The JSON schemas (spec §9) and the Resource classes must stay in sync; treat the spec as the contract and update both together.
- **Engine version creep.** Pin Godot 4.6.3 for the phase; revisit upgrades deliberately, not incidentally.
- **Scope leakage.** Resist adding rendering or gameplay here — Phase 0's value is a clean, tested foundation.

---

## 9. Phase 0 Deliverables Checklist

- [ ] Godot 4.6.3 project boots to an empty `Main` scene, no errors.
- [ ] Git repo initialized with Godot 4 `.gitignore`; README documents engine version and how to run tests.
- [ ] Folder structure and naming conventions in place (§4).
- [ ] `GameData`, `Constants`, `Logger` autoloads registered (§4.2).
- [ ] `StatKey` enum defined with `SPD`/`ATK`/`RNG`/`DEF`/`HP` + string conversion helpers (§5.2).
- [ ] `TileRecord` typed class defined with `q`/`r`/`elevation`/`terrain` fields (§5.2).
- [ ] JSON → Resource loader + validator with one sample entity, fail-loud on invalid input (§5).
- [ ] Hex math module: conversions, distance, neighbors, range, rounding (§6).
- [ ] GUT installed; passing tests for hex math, `StatKey`, `TileRecord`, and the data loader/validator (§7).
- [ ] Phase tagged in Git (`phase-0-complete`).
