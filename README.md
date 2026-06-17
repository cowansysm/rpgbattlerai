# RPG Battle Simulator

A tactical battle simulator in the style of Final Fantasy Tactics, built with Godot and GDScript. All MVP phases (0–11) are complete: draft a party, deploy, and play a full tactical battle to a victory screen.

## Engine Version

**Godot 4.6.3** (standard, non-.NET build). Do not auto-upgrade the engine version.

## Hex Orientation

**Flat-top** hexes. This decision is committed project-wide. Layout constants are in `src/core/hex/hex_layout.gd`.

## Running the Game

Open the project in Godot 4.6.3 and run. The main scene is `res://scenes/draft/draft_scene.tscn`, which flows through party draft → deployment → combat. The full match loop (draft → deploy → rounds → victory → result) is playable end to end through the visual UI, with keyboard shortcuts available as alternatives.

## Project Structure

```
res://
├── project.godot
├── addons/gut/              # GUT test framework (vendored, v9.6.0)
├── assets/icons/            # status effect and ability icons
├── data/                    # authored JSON content (consolidated arrays)
│   ├── characters.json      # 8 premade roster characters
│   ├── classes.json         # 8 class/job definitions
│   ├── races.json           # 4 race definitions
│   ├── abilities.json       # 14 abilities (spells, skills, item-bound)
│   ├── items.json           # 12 equipment items
│   ├── constants.json       # game balance tuning
│   ├── terrain.json         # terrain type definitions
│   └── maps/                # 6 map files (forest_clearing, mountain_pass,
│                            #   open_plains, river_crossing,
│                            #   ruined_watchtower, sunken_courtyard)
├── src/
│   ├── autoload/            # singletons (Log, Constants, GameData, MatchData)
│   ├── core/
│   │   ├── combat/          # match state, turns, resolution, abilities, deployment, draft
│   │   ├── data/            # Resource definitions, loader, validator, pipeline, stats, atlas
│   │   └── hex/             # hex math, pathfinding, LOS, range queries
│   ├── debug/               # debug readout overlay
│   ├── map/                 # 3D map rendering, pawns, overlays, markers, camera
│   └── ui/                  # combat HUD, draft screen
├── scenes/
│   ├── draft/               # party draft UI (main scene)
│   ├── main/                # entry point scene
│   └── map/                 # battle map / combat scene
└── tests/                   # GUT test scripts (mirrors src/ layout)
    ├── core/combat/         # combat unit + integration tests
    ├── core/data/           # data layer tests
    ├── core/hex/            # hex math tests
    ├── map/                 # map/visual tests
    └── fixtures/            # test fixture sets (valid_set, dangling_ref, bad_effect)
```

## Conventions

- **Files/directories:** `snake_case`
- **Classes:** `PascalCase` via `class_name` (one per file)
- **Constants/enums:** `UPPER_SNAKE_CASE`
- **Private members:** leading underscore (`_base`, `_entries`)
- **Typing:** explicit type hints throughout; typed arrays (`Array[BattleUnit]`)
- **Test file naming:** `test_<module>.gd`, mirrors source layout
- **Test method naming:** `test_<behavior_description>`

## Architecture

### Separation of concerns

- **`src/core/`** — Pure business logic. No scene-tree dependency. Classes extend `RefCounted` or `Resource`. Fully unit-testable.
- **`src/map/`, `src/ui/`** — Scene-tree controllers wiring core services together. Extend `Node`/`Node3D`/`CanvasLayer`.

### Dependency injection

Services receive `Callable` references to data getters rather than direct class references, enabling testing with stubs (e.g., spatial-rule functions receive terrain properties through an injected provider rather than accessing `GameData` directly).

### Reference model

Resources hold **string IDs** as references, not object links. Consumers resolve references via `GameData` accessors at runtime (lazy lookup). This keeps JSON simple and avoids circular-dependency issues during loading.

### Consolidated JSON format

Each entity type is a single JSON file containing an array of objects:

```json
[{"id": "fire_1", "type": "offensive", "ap": 1, ...}, ...]
```

### Multiclass stacking

Stat modifiers from multiple classes stack **additively** (MVP rule). A character with two classes sums both sets of stat modifiers onto the base stats.

### Read-only contract

All authored data (`CharacterData`, `RaceData`, etc.) is immutable post-load. The `GameData` facade and `DataPipeline` expose data but never mutate content. All per-battle mutable state lives on `BattleUnit` instances, which duplicate the `StatBlock` at creation for independent runtime modification.

### Boot pipeline

`GameData._ready()` → `DataPipeline.run()` → load all entities → structural validate → referential validate → derive final stats → log summary. The pipeline aborts loudly on any validation error.

## Combat System

- **Alternating activation** turn structure (not full-team turns).
- **2 AP per activation:** Move (1 AP), Attack/Ability (1–2 AP), Defend/Wait/Item (1 AP).
- **Willpower (WP):** a resource gating spell usage, with per-ability costs and per-character pools.
- **Status effects** with duration tracking, stat modifiers, and special rules.
- **Minimum range 2** for ranged attacks (cannot target adjacent hexes).
- **Victory:** immediate win when the opposing team has no living units, with a match-over result screen.

## Hex System

- **Flat-top** orientation, axial coordinates (q, r).
- Pure static math in `src/core/hex/hex.gd`; layout constants in `src/core/hex/hex_layout.gd`.
- Elevation-aware pathfinding with jump/climb limits.
- Line of sight blocked by terrain; a higher attacker can see over obstacles.

## Stat System

- `StatKey` enum: canonical keys (SPD, ATK, RNG, DEF, HP, JUMP, WP).
- `StatBlock`: base + modifiers stack; `effective(key)` = base + sum(modifiers).
- Multiclass stats stack additively.

## Autoloads (load order)

1. **Log** — `src/autoload/logger.gd` — log levels DEBUG / INFO / WARN / ERROR
2. **Constants** — `src/autoload/constants.gd` — loads `data/constants.json`
3. **GameData** — `src/autoload/game_data.gd` — facade delegating to `DataPipeline`
4. **DebugReadout** — `src/debug/debug_readout.gd` — debug overlay
5. **MatchData** — `src/autoload/match_data.gd` — per-match state transfer between scenes

## Running Tests

### From the Godot editor

1. Open the project in Godot 4.6.3
2. The GUT panel appears at the bottom
3. Click **Run All**

### Headless (command line)

```bash
godot -d -s --path . addons/gut/gut_cmdln.gd
```

The `.gutconfig.json` at the project root configures test directories (`res://tests/`, prefix `test_`) and exit-on-complete behavior.

## Documentation

Phase specs and implementation plans live in `docs/`:

- `rpg-specs.md` — master MVP specification
- `rpg-implementation-plan.md` — high-level phase roadmap
- `phase<N>-spec.md` / `phase<N>-implementation-plan.md` — per-phase details (0–11)

## Phase Status

All MVP phases are complete:

- [x] Phase 0 — Project Foundation
- [x] Phase 1 — Data Layer & Content Schema
- [x] Phase 2 — Hex Map & 3D Representation
- [x] Phase 3 — Movement, Range & Line of Sight
- [x] Phase 4 — Combat Core: Activation & Action Economy
- [x] Phase 5 — Combat Resolution
- [x] Phase 6 — Content: Roster, Abilities & Maps
- [x] Phase 7 — Party Building & Match Setup
- [x] Phase 8 — Combat UI & Unit Visuals
- [x] Phase 9 — Symbol Atlas & Icon System
- [x] Phase 10 — Dice/Action Markers & HP Rebalance
- [x] Phase 11 — Polish: WP System, Victory Detection, Defend Duration, Min Range

### Deferred (post-MVP)

AI opponents, multiplayer/networking, in-app character builder and free-form multiclassing, floating damage numbers and particle effects, audio feedback, and undo-within-activation are intentionally deferred beyond the MVP.
