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
│   ├── characters.json      # 8 character templates
│   ├── classes.json         # Class/job definitions (Vagabond + tier-1 branches)
│   ├── items.json           # 12 equipment items
│   ├── races.json           # 4 race definitions (with base_stats)
│   ├── constants.json       # Game balance tuning (incl. AI presets)
│   ├── terrain.json         # Terrain type definitions
│   ├── maps/                # Map JSON files (condensed format)
│   └── names/               # Per-race name tables (human, elf, dwarf, halfling)
├── scenes/
│   ├── draft/               # Party draft UI (main scene)
│   ├── main/                # Entry point scene
│   └── map/                 # Battle map / combat scene
├── src/
│   ├── autoload/            # Singletons: Log, Constants, Dev, GameData, MatchData
│   ├── core/
│   │   ├── ai/              # AI planner, scorer, plan model
│   │   ├── combat/          # Match state, turns, resolution, abilities, deployment
│   │   ├── data/            # Entity Resources, loader, validator, pipeline, stats
│   │   ├── hex/             # Hex math, pathfinding, LOS, range queries
│   │   └── progression/     # Character instances, name generation, stat resolver
│   ├── debug/               # Debug readout
│   ├── map/                 # 3D map rendering, pawns, overlays, markers, camera, AI controller
│   ├── tools/               # Map editor model, CSV exporter/importer, entity schema, content pipeline
│   └── ui/                  # HUD, draft screen, dev menu, map editor UI
└── tests/
    ├── core/ai/             # AI planner & plan tests
    ├── core/combat/         # Combat unit + integration tests
    ├── core/data/           # Data layer tests
    ├── core/hex/            # Hex math tests
    ├── core/progression/    # Character instance & bridge tests
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

- `StatKey` enum: canonical keys (SPD, ATK, RNG, DEF, HP, JUMP, WP, MAG, RES)
- `StatBlock`: base + modifiers stack. `effective(key)` = base + sum(modifiers)
- Multiclass stats stack additively
- Magical resolution: `roll + value + round(mag_scaling × MAG) − RES` (min 1); Defend die reduces magical damage

### Boot pipeline
`GameData._ready()` → `DataPipeline.run()` → load all entities → structural validate → referential validate → derive final stats → log summary. Aborts on validation errors.

## Autoloads (load order)

1. **Log** — `src/autoload/logger.gd` — levels: DEBUG, INFO, WARN, ERROR
2. **Constants** — `src/autoload/constants.gd` — loads `data/constants.json`
3. **Dev** — `src/autoload/dev.gd` — dev mode flag (`--dev`/`--no-dev`/`user://dev.cfg`/`OS.is_debug_build()`)
4. **GameData** — `src/autoload/game_data.gd` — facade over `DataPipeline`
5. **DebugReadout** — `src/debug/debug_readout.gd` — debug overlay (gated by `Dev.enabled`)
6. **MatchData** — `src/autoload/match_data.gd` — per-match state transfer between scenes

## Combat System

- **Alternating activation** turn structure (not full-team turns)
- **2 AP per activation:** Move (1 AP), Attack/Ability (1-2 AP), Defend/Wait/Item (1 AP)
- **Willpower (WP):** resource gating spell usage (per-ability costs, per-character pools)
- **Status effects** with duration tracking, stat modifiers, and special rules
- **Victory:** immediate win when opposing team has no living units
- **Minimum range 2** for ranged attacks (cannot target adjacent hexes)
- **Terrain effects:** damage-on-enter (spikes), damage-per-turn (lava), status-on-enter (bog), occupant stat modifiers, water tagging
- **Condensed map format:** minified JSON with positional tile arrays `[q, r, elev, terrain]`

## Hex System

- **Flat-top** orientation, axial coordinates (q, r)
- Layout constants in `src/core/hex/hex_layout.gd`
- Pure static math in `src/core/hex/hex.gd`
- Elevation-aware pathfinding with jump/climb limits
- LOS blocked by terrain; higher attacker can see over obstacles

## Progression System (A4)

- **`CharacterInstance`** — persistent character with generated identity (name from race tables), level/XP, JP per class, unlocked classes, learned abilities, equipment loadout
- **Job tree:** every character starts as **Vagabond** → unlocks **Thief/Soldier/Adept** at level 3 (archetype branches planned for later tiers)
- **`ClassData`** extended with: `archetype`, `branch`, `tier`, `growth`, `jp_costs`, `prerequisites`
- **`RaceData`** extended with: `base_stats` (StatKey→int)
- **`InstanceStatResolver`** computes base stats: race base_stats + active class modifiers + accumulated growth
- **`NameGenerator`** draws from `data/names/<race>.json` with seeded RNG
- **BattleUnit bridge:** `BattleUnit.from_instance()` synthesizes a CharacterData + derives StatBlock, feeding into the existing combat pipeline with no combat-layer changes

## AI System (A7)

- **`AIPlan`** — plan model with step kinds (move, attack, ability, defend, wait) and AP cost tracking
- **`AIPlanner`** — enumerates legal candidates: reachable tiles, valid attack/ability targets per range/LoS/min-range, composite 2-AP plans, fallback plans; bounded to max 12 tiles for tractability
- **`AIScorer`** — utility heuristic weighing expected damage, kills, exposure, cover, elevation, hazards (A0), target priority, ability value, resource economy; terrain- and magic-aware (A3)
- **`AIController`** (`src/map/ai_controller.gd`) — scene-level driver executing plans via `TurnActions` (same action backend as the human player, no privileged access); includes pacing delays and visual feedback
- **Selection:** top-N sampling with temperature parameter; difficulty presets in `constants.json`

## Dev Tooling

- **Dev flag** (`src/autoload/dev.gd`): resolved from CLI args (`--dev`/`--no-dev`) → `user://dev.cfg` → `OS.is_debug_build()`; gates all dev tools
- **Dev menu** (`src/ui/dev_menu.gd`): entry point to map editor and CSV tools
- **Map editor** (`src/tools/map_editor_model.gd` + `src/ui/map_editor.gd`): terrain painting, elevation editing, deployment zones, tile add/remove, undo/redo (50-step stack), save/load; reuses existing 3D rendering
- **CSV pipeline** (`src/tools/csv_exporter.gd`, `csv_importer.gd`, `entity_schema.gd`, `content_pipeline.gd`): round-trip CSV ↔ JSON for all 6 entity types; supports nested fields via dotted notation

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

## Alpha (in progress)

The Alpha extends the MVP into a single-player game. Its specs and implementation plans are complete (see Documentation). A0–A4 and A7 are **implemented and tested**; A5–A6, A8–A10 are **planned but not yet built** — treat their `alpha-*` docs as the plan of record, not as describing current code. Do not assume any A5+ system is built unless the source actually shows it.

Sub-phases (critical path A0→A3→A4→A5→A6→A8→A10; A1/A2 tooling and A9 content are parallel; A7 AI joins at A8):

- [x] A0: Terrain effects, condensed map format, dev flag & dev tools menu — **complete**
- [x] A1: Map editor (dev tool, gated by the dev flag) — **complete**
- [x] A2: CSV ↔ JSON content pipeline — **complete**
- [x] A3: `MAG`/`RES` stats & magical resolution — **complete**
- [x] A4: Character instances, classes & the Vagabond-rooted job tree — **complete**
- [ ] A5: Battle Bands & save system (`user://`)
- [ ] A6: Economy — gold, shops & loot
- [x] A7: AI opponent (`AIController` over `TurnActions`) — **complete**
- [ ] A8: Roguelike run (branching node graph, ≤3 parallel paths, down-limit death)
- [ ] A9: Content expansion (authored via A1/A2)
- [ ] A10: Polish & meta-progression

Key Alpha decisions: dev-tool map editor (player-facing later); CSV↔JSON authoring via spreadsheets; FFT-style progression (XP + JP + job tree + gold/shop + loot); roguelike single-player; every character starts **Vagabond** → unlocks **Thief/Soldier/Adept** at level 3 → archetype branches (support / control / physical·melee·ranged / magical·arcane·divine); characters permadie on the **3rd down** per run (tunable `DOWN_LIMIT`); the attack die and Defend die persist through the A3 magic change (Defend reduces magical damage too).

## Documentation

Phase specs and implementation plans live in `docs/`.

**MVP (implemented):**

- `rpg-specs.md` — master MVP specification
- `rpg-implementation-plan.md` — high-level phase roadmap
- `phase<N>-spec.md` / `phase<N>-implementation-plan.md` — per-phase details (0–11)

**Alpha (in progress — A0–A4 & A7 complete, A5–A6 & A8–A10 planned):**

- `alpha-specs.md` — master Alpha specification
- `alpha-implementation-plan.md` — Alpha milestone roadmap (A0–A10)
- `alpha-phaseA<N>-spec.md` / `alpha-phaseA<N>-implementation-plan.md` — per-sub-phase details (A0–A10)

## Development Workflow

### Worktree-based branching

All feature work happens in **git worktrees**, each with its own branch forked from `development`. This keeps the main checkout clean and allows parallel work on multiple phases or tasks.

**Directory layout:**

```
c:\development\
├── rpg-battle-ai/                    # Main checkout (development branch)
│   └── scripts/
│       ├── new-worktree.sh           # Create a new worktree + branch
│       └── remove-worktree.sh        # Clean up a worktree
└── rpg-battle-ai.worktrees/          # Sibling directory for worktrees
    ├── alpha-a5/                     # One worktree per task
    ├── alpha-a6/
    └── fix-pathfinding/
```

### Starting a new task

When beginning a new alpha phase or ad-hoc task, **always create a worktree first**:

```bash
# Alpha phase (auto-detects spec doc, extracts context):
./scripts/new-worktree.sh a5

# Ad-hoc task (provide a description):
./scripts/new-worktree.sh fix-pathfinding "Fix A* edge case with elevation 0 tiles"
```

The script creates a git worktree with a feature branch off `development`, copies `.claude/` config, and generates a `CLAUDE.local.md` with task-specific context (spec references, dependencies, scope). Launch Claude Code in the new worktree directory — it reads both `CLAUDE.md` (project context) and `CLAUDE.local.md` (task context) automatically.

### Branch naming

- Alpha phases: `feature/alpha-a5`, `feature/alpha-a6`, etc.
- Ad-hoc tasks: `feature/<kebab-case-slug>`, e.g. `feature/fix-pathfinding`

### Merge-back process

1. Complete work in the worktree, commit, and push the feature branch
2. Create a PR targeting `development`
3. After merge, clean up: `./scripts/remove-worktree.sh alpha-a5 --delete-branch`

### Task context via CLAUDE.local.md

Each worktree has a generated `CLAUDE.local.md` (gitignored) that tells Claude what task/phase is active, which spec and implementation plan to read, the branch name and merge target, and scope constraints. **When a user asks to start a new task or phase, suggest running the worktree setup script first** rather than working in the main checkout.
