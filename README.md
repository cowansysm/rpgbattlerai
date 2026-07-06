# RPG Battle Simulator

A tactical battle simulator in the style of Final Fantasy Tactics, built with Godot and GDScript. All MVP phases (0–11) are complete: draft a party, deploy, and play a full tactical battle to a victory screen. **Alpha** development is well advanced — sub-phases A0–A20 are implemented and tested (the only exceptions: A13 was dropped, and A9 content authoring has maps still below target). This spans effectful terrain, tooling, MAG/RES magic, the job tree, Battle Bands/saves, economy, AI, the roguelike run, meta-progression, encounters & level scaling, interactive deployment, multiple turn systems (speed-round, charge-time), elemental affinities & crits, knockout/revive, passives, facing/flanking, and a local skirmish mode.

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
│   ├── characters.json      # 20 character templates (7 human, 5 elf, 4 dwarf, 4 halfling)
│   ├── classes.json         # 25 class/job definitions (1 starting, 3 tier-1, 12 advanced, 9 elite)
│   ├── races.json           # 4 race definitions (with base_stats)
│   ├── abilities.json       # 82 abilities (39 skills, 36 spells, 7 item-bound)
│   ├── items.json           # 46 items (40 equipment + 6 consumables)
│   ├── constants.json       # game balance tuning (incl. AI presets, economy tunables)
│   ├── terrain.json         # 17 terrain type definitions
│   ├── loot_tables.json     # 2 loot tables (standard_battle, boss_battle)
│   ├── shop_pools.json      # 4 shop pools (tier1_weapons/armor/gear, starter_consumables)
│   ├── names/               # per-race name tables (human, elf, dwarf, halfling)
│   ├── csv/                 # CSV mirrors for the CSV↔JSON authoring pipeline
│   └── maps/                # 6 map files (forest_clearing, mountain_pass,
│                            #   open_plains, river_crossing,
│                            #   ruined_watchtower, sunken_courtyard)
├── src/
│   ├── autoload/            # singletons (Log, Constants, Dev, GameData, MatchData, SaveManager)
│   ├── core/
│   │   ├── ai/              # AI planner, scorer, plan model
│   │   ├── combat/          # match state, turns, resolution, abilities, deployment, draft
│   │   ├── data/            # Resource definitions, loader, validator, pipeline, stats, atlas
│   │   ├── economy/         # pricing, loot roller, shop service
│   │   ├── hex/             # hex math, pathfinding, LOS, range queries
│   │   └── progression/     # character instances, name generation, stat resolver
│   ├── debug/               # debug readout overlay
│   ├── map/                 # 3D map rendering, pawns, overlays, markers, camera, AI controller
│   ├── tools/               # map editor model, CSV exporter/importer, content pipeline
│   └── ui/                  # combat HUD, draft screen, dev menu, map editor UI
├── scenes/
│   ├── band/                # band management UI
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
- **Magical resolution (A3):** spells scale with `MAG` and are mitigated by `RES` (`roll + value + round(mag_scaling × MAG) − RES`, min 1); the Defend die reduces magical damage too.
- **Terrain effects (A0):** damage-on-enter, damage-per-turn, status-on-enter, occupant stat modifiers, cover, and water tagging.
- **Status effects** with duration tracking, stat modifiers, and special rules.
- **Minimum range 2** for ranged attacks (cannot target adjacent hexes).
- **Victory:** immediate win when the opposing team has no living units, with a match-over result screen.

## Hex System

- **Flat-top** orientation, axial coordinates (q, r).
- Pure static math in `src/core/hex/hex.gd`; layout constants in `src/core/hex/hex_layout.gd`.
- Elevation-aware pathfinding with jump/climb limits.
- Line of sight blocked by terrain; a higher attacker can see over obstacles.

## Stat System

- `StatKey` enum: canonical keys (SPD, ATK, RNG, DEF, HP, JUMP, WP, MAG, RES).
- `StatBlock`: base + modifiers stack; `effective(key)` = base + sum(modifiers).
- Multiclass stats stack additively.

## Autoloads (load order)

1. **Log** — `src/autoload/logger.gd` — log levels DEBUG / INFO / WARN / ERROR
2. **Constants** — `src/autoload/constants.gd` — loads `data/constants.json`
3. **Dev** — `src/autoload/dev.gd` — dev-mode flag gating dev tools
4. **GameData** — `src/autoload/game_data.gd` — facade delegating to `DataPipeline`
5. **DebugReadout** — `src/debug/debug_readout.gd` — debug overlay (gated by `Dev.enabled`)
6. **MatchData** — `src/autoload/match_data.gd` — per-match state transfer between scenes
7. **SaveManager** — `src/autoload/save_manager.gd` — versioned JSON persistence for bands, profile, runs

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

Phase specs and implementation plans live in `docs/`.

**MVP (implemented):**

- `rpg-specs.md` — master MVP specification
- `rpg-implementation-plan.md` — high-level phase roadmap
- `phase<N>-spec.md` / `phase<N>-implementation-plan.md` — per-phase details (0–11)

**Alpha (in progress — A0–A20 implemented and tested except the dropped A13; A9 content authored, maps still below target):**

- `alpha-specs.md` — master Alpha specification
- `alpha-implementation-plan.md` — Alpha milestone roadmap (A0–A20)
- `alpha-phaseA<N>-spec.md` / `alpha-phaseA<N>-implementation-plan.md` — per-sub-phase details (A0–A20; A16–A20 are spec-only)

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

### Alpha (in progress)

The current milestone, **Alpha**, extends the MVP into a single-player game and, via A20, a local multiplayer/skirmish mode. All sub-phases are implemented and tested except A13, which was dropped. Status by sub-phase:

- [x] A0 — Terrain effects, condensed map format & dev flag
- [x] A1 — Map editor (dev tool)
- [x] A2 — CSV ↔ JSON content pipeline
- [x] A3 — `MAG`/`RES` stats & magical resolution
- [x] A4 — Character instances, classes & the Vagabond-rooted job tree
- [x] A5 — Battle Bands & save system (`user://`)
- [x] A6 — Economy: gold, shops & loot
- [x] A7 — AI opponent (`AIController` over `TurnActions`)
- [x] A8 — Roguelike run (branching node graph, down-limit death)
- [~] A9 — Content expansion: libraries well beyond target (91 abilities, 146 classes, 46 items, 141 characters, 32 races, 17 terrains, 73 encounters); **maps (6) still below target**
- [x] A10 — Polish & meta-progression (Profile, MetaUnlockEngine, recruitment gating, run shop)
- [x] A11 — Encounters, level scaling & economy refinement
- [x] A12 — Interactive deployment zones
- [ ] A13 — Coin flip & opening initiative — **dropped, not to be implemented**
- [x] A14 — Ability symbol pawns / physics drop feedback
- [x] A15 — Telegraphed speed-round + turn-system architecture
- [x] A16 — Elemental affinities & critical hits
- [x] A17 — Knockout & revive lifecycle
- [x] A18 — Reaction / support / movement passives
- [x] A19 — Facing & flanking
- [x] A20 — Charge-time clock + skirmish container

Only A9's maps remain below target; everything else on the Alpha path is shipped and green under the GUT suite. Each sub-phase has a spec (and, through A15, an implementation plan) in `docs/`.

> **Note on staged CSV content:** `data/csv/` holds a larger draft library (268 classes, 160 characters, 128 items). It is **not adopted yet**: it references a 787-ability set that was reduced to 91 during A18. A spike confirmed the surplus imports and boots clean once that ability library is restored (+6 elements re-added), but the content uses a learn-via-JP model that would leave fresh characters with no baseline attack and breaks 148 tests. Adoption is deferred pending a gameplay-model decision — see `docs/content-import-followup.md`.

### Deferred (beyond Alpha)

Networked multiplayer, final art/audio, and deeper systems (equipment crafting, coordinated/look-ahead AI, rich narrative campaigns) remain deferred. The Alpha architecture is designed to leave clean seams for them.
