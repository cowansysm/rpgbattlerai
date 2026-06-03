# RPG Battle Simulator

A tactical battle simulator in the style of Final Fantasy Tactics, built with Godot and GDScript.

## Engine Version

**Godot 4.6.3** (standard, non-.NET build). Do not auto-upgrade the engine mid-phase.

## Hex Orientation

**Flat-top** hexes. This decision is committed project-wide. Layout constants are in `src/core/hex/hex_layout.gd`.

## Project Structure

```
res://
├── project.godot
├── addons/gut/          # GUT test framework (vendored, v9.6.0)
├── assets/              # art, audio, fonts (placeholder)
├── data/                # authored JSON content
│   ├── characters/      # 8 premade roster characters
│   ├── classes/         # 8 class/job definitions
│   ├── races/           # 4 race definitions
│   ├── abilities/       # 14 abilities (spells, skills, item-bound)
│   ├── items/           # 12 equipment items
│   ├── maps/            # 3 maps (one per tier)
│   └── constants.json
├── src/
│   ├── core/hex/        # hex coordinate & math module
│   ├── core/data/       # loader, validator, Resource definitions, pipeline
│   ├── autoload/        # singletons (Log, Constants, GameData)
│   └── debug/           # debug harness
├── scenes/main/         # entry point scene
└── tests/               # GUT test scripts (mirrors src/ layout)
    ├── core/hex/
    ├── core/data/
    └── fixtures/        # test fixture directories (valid_set, dangling_ref, etc.)
```

## Conventions

- **Files/directories:** `snake_case`
- **Classes:** `PascalCase` via `class_name`
- **Constants:** `UPPER_SNAKE`
- **Typing:** Explicit type hints throughout (typed GDScript)
- **Stats:** Stored as `Dictionary` validated against `StatKey` enum
- **Test paths:** Mirror source layout (e.g., `tests/core/hex/test_hex.gd` for `src/core/hex/hex.gd`)

## Data Architecture (Phase 1)

### Reference model

Resources hold **string IDs** as references, not object links. Consumers resolve references via `GameData` accessors at runtime (lazy lookup). This keeps JSON simple and avoids circular-dependency issues during loading.

### Multiclass stacking

Stat modifiers from multiple classes stack **additively** (MVP rule). A character with two classes sums both sets of stat modifiers onto the base stats.

### Read-only contract

All authored data (`CharacterData`, `RaceData`, etc.) is immutable post-load. The `GameData` facade and `DataPipeline` expose data but never mutate content. All per-battle mutable state lives on `BattleUnit` instances, which duplicate the `StatBlock` at creation for independent runtime modification.

### Boot pipeline

`GameData._ready()` → `DataPipeline.run()` → load all entities → structural validate → referential validate → derive final stats → log summary. The pipeline aborts loudly on any validation error.

## Running Tests

### From the Godot editor

1. Open the project in Godot 4.6.3
2. The GUT panel appears at the bottom
3. Click **Run All**

### Headless (command line)

```bash
godot -d -s --path . addons/gut/gut_cmdln.gd
```

The `.gutconfig.json` at the project root configures test directories and exit behavior.

## Autoloads (load order)

1. **Log** — `src/autoload/logger.gd` — log levels DEBUG/INFO/WARN/ERROR
2. **Constants** — `src/autoload/constants.gd` — loads `data/constants.json`
3. **GameData** — `src/autoload/game_data.gd` — facade delegating to `DataPipeline`

## Phase Status

- [x] Phase 0 — Project Foundation
- [x] Phase 1 — Data Layer & Content Schema
- [ ] Phase 2 — Hex Map & 3D Representation
- [ ] Phase 3 — Movement, Range & Line of Sight
