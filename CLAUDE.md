# RPG Battle Simulator

Tactical battle simulator in the style of Final Fantasy Tactics, built with **Godot 4.6.3** (standard, non-.NET build) and **GDScript**.

**Do not auto-upgrade the engine version.** Hex orientation is **flat-top**, committed project-wide.

## Project Structure

```
res://
├── addons/gut/              # GUT v9.6.0 test framework (vendored)
├── assets/icons/            # Status effect and ability icons
├── data/
│   ├── abilities.json       # All abilities (consolidated array)
│   ├── characters.json      # 8 premade roster characters
│   ├── classes.json         # 8 class/job definitions
│   ├── items.json           # 12 equipment items
│   ├── races.json           # 4 race definitions
│   ├── constants.json       # Game balance tuning
│   ├── terrain.json         # Terrain type definitions
│   └── maps/                # Map JSON files (one per map)
├── scenes/
│   ├── draft/               # Party draft UI (main scene)
│   ├── main/                # Entry point scene
│   └── map/                 # Battle map / combat scene
├── src/
│   ├── autoload/            # Singletons: Log, Constants, GameData, MatchData
│   ├── core/
│   │   ├── combat/          # Match state, turns, resolution, abilities, deployment
│   │   ├── data/            # Entity Resources, loader, validator, pipeline, stats
│   │   └── hex/             # Hex math, pathfinding, LOS, range queries
│   ├── debug/               # Debug readout
│   ├── map/                 # 3D map rendering, pawns, overlays, markers, camera
│   └── ui/                  # HUD, draft screen
└── tests/
    ├── core/combat/         # Combat unit + integration tests
    ├── core/data/           # Data layer tests
    ├── core/hex/            # Hex math tests
    ├── map/                 # Map/visual tests
    └── fixtures/            # Test data sets (valid_set, dangling_ref, bad_effect)
```

## Conventions

- **Files/directories:** `snake_case`
- **Classes:** `PascalCase` via `class_name` (one per file)
- **Constants/enums:** `UPPER_SNAKE_CASE`
- **Private members:** leading underscore (`_base`, `_entries`)
- **Type hints:** explicit on all function signatures and variables; use typed arrays (`Array[BattleUnit]`)
- **Test file naming:** `test_<module>.gd`, mirrors source layout
- **Test method naming:** `test_<behavior_description>`

## Architecture

### Separation of concerns

- **`src/core/`** — Pure business logic. No scene-tree dependency. All classes extend `RefCounted` or `Resource`. Fully unit-testable.
- **`src/map/`, `src/ui/`** — Scene-tree controllers that wire core services together. Extend `Node`/`Node3D`/`CanvasLayer`.

### Dependency injection
Services receive `Callable` references to data getters rather than direct class references. This enables testing with stubs:
```gdscript
func _init(ability_getter: Callable, class_getter: Callable) -> void
```

### Key patterns

- **Factory:** `DataFactory` has static `make_race()`, `make_class()`, etc. that convert raw JSON dicts to typed Resources
- **Registry:** `EntityRegistry` is a generic key-value store for loaded entities with validation
- **Pipeline:** `DataPipeline` orchestrates: load → structural validate → referential validate → derive final stats
- **State machine:** `MatchState.Phase` enum (SETUP, DEPLOYMENT, ROUND_START, AWAITING_ACTIVATION, UNIT_TURN, MATCH_OVER) + `BattleController.ControlState` for UI

### Immutability contract
All authored data (`CharacterData`, `RaceData`, etc.) is immutable post-load. Per-battle mutable state lives on `BattleUnit` instances, which duplicate the `StatBlock` at creation.

## Data Architecture

### Reference model
Resources hold **string IDs** as references, not object links. Consumers resolve via `GameData` accessors at runtime (lazy lookup).

### Consolidated JSON format
Each entity type is a single JSON file containing an array of objects:
```json
[{"id": "fire_1", "type": "offensive", "ap": 1, ...}, ...]
```

### Stat system

- `StatKey` enum: canonical keys (SPD, ATK, RNG, DEF, HP, JUMP, WP)
- `StatBlock`: base + modifiers stack. `effective(key)` = base + sum(modifiers)
- Multiclass stats stack additively

### Boot pipeline
`GameData._ready()` → `DataPipeline.run()` → load all entities → structural validate → referential validate → derive final stats → log summary. Aborts on validation errors.

## Autoloads (load order)

1. **Log** — `src/autoload/logger.gd` — levels: DEBUG, INFO, WARN, ERROR
2. **Constants** — `src/autoload/constants.gd` — loads `data/constants.json`
3. **GameData** — `src/autoload/game_data.gd` — facade over `DataPipeline`
4. **DebugReadout** — `src/debug/debug_readout.gd` — debug overlay
5. **MatchData** — `src/autoload/match_data.gd` — per-match state transfer between scenes

## Combat System

- **Alternating activation** turn structure (not full-team turns)
- **2 AP per activation:** Move (1 AP), Attack/Ability (1-2 AP), Defend/Wait/Item (1 AP)
- **Willpower (WP):** resource gating spell usage (per-ability costs, per-character pools)
- **Status effects** with duration tracking, stat modifiers, and special rules
- **Victory:** immediate win when opposing team has no living units
- **Minimum range 2** for ranged attacks (cannot target adjacent hexes)

## Hex System

- **Flat-top** orientation, axial coordinates (q, r)
- Layout constants in `src/core/hex/hex_layout.gd`
- Pure static math in `src/core/hex/hex.gd`
- Elevation-aware pathfinding with jump/climb limits
- LOS blocked by terrain; higher attacker can see over obstacles

## Running Tests

### Godot editor
Open project → GUT panel at bottom → **Run All**

### Headless (command line)
```bash
godot -d -s --path . addons/gut/gut_cmdln.gd
```

Config: `.gutconfig.json` (test dirs: `res://tests/`, prefix: `test_`, exit on complete)

## Error Handling

- Validation returns `Array[String]` of errors (empty = success)
- Errors accumulated before failing (not fail-fast)
- Logging via `Log.info("Tag", "message")`, `Log.warn(...)`, `Log.error(...)`

## Phase Progress

All MVP phases complete:

- Phase 0: Project foundation
- Phase 1: Data layer & content schema
- Phase 2: Hex map & 3D representation
- Phase 3: Movement, range & line of sight
- Phase 4: Combat activation & action economy
- Phase 5: Combat resolution
- Phase 6: Content — roster, abilities & maps
- Phase 7: Party building & match setup
- Phase 8: Combat UI & unit visuals
- Phase 9: Symbol atlas & icon system
- Phase 10: Dice/action markers, HP rebalance
- Phase 11: Polish — WP system, victory detection, defend duration, min range, status sidebar

Main scene: `res://scenes/draft/draft_scene.tscn` (party draft → deploy → combat)

## Documentation

Phase specs and implementation plans live in `docs/`:
- `rpg-specs.md` — master MVP specification
- `rpg-implementation-plan.md` — high-level phase roadmap
- `phase<N>-spec.md` / `phase<N>-implementation-plan.md` — per-phase details (0-11)
