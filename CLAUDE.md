# RPG Battle Simulator

Tactical battle simulator in the style of Final Fantasy Tactics, built with **Godot 4.6.3** (standard, non-.NET build) and **GDScript**.

**Do not auto-upgrade the engine version.** Hex orientation is **flat-top**, committed project-wide.

## Project Structure

```
res://
├── addons/gut/              # GUT v9.6.0 test framework (vendored)
├── assets/icons/            # Status effect and ability icons
├── data/
│   ├── abilities.json       # 82 abilities (39 skills, 36 spells, 7 item-bound)
│   ├── characters.json      # 141 character templates (playable roster + monster/NPC templates for encounters)
│   ├── classes.json         # 146 class/job definitions (Vagabond root → tier-1 → advanced → elite + monster classes)
│   ├── items.json           # 46 items (40 equipment + 6 consumables)
│   ├── races.json           # 32 race definitions (4 playable + monster races: bat, imp, kobold, slime, goblin, wolf, …)
│   ├── constants.json       # Game balance tuning (incl. AI presets, economy, affinity/crit, turn-system tunables)
│   ├── terrain.json         # 17 terrain type definitions
│   ├── loot_tables.json     # 2 loot tables (standard_battle, boss_battle)
│   ├── shop_pools.json      # 4 shop pools (tier1_weapons, tier1_armor, tier1_gear, starter_consumables)
│   ├── encounters.json      # 73 encounter definitions (A11: level-gated enemy compositions, map + scaling)
│   ├── events.json          # Run event definitions (A8 roguelike run)
│   ├── meta_unlocks.json    # Meta unlock rules + starting boons (A10)
│   ├── run_config.json      # Roguelike run tuning (A8)
│   ├── csv/                 # CSV working copies for the CSV↔JSON content pipeline (A2)
│   ├── maps/                # 6 map files (condensed format)
│   └── names/               # Per-race name tables (human, elf, dwarf, halfling; 20 given + 15 surname each)
├── scenes/
│   ├── band/                # Band management UI
│   ├── draft/               # Party draft UI (main scene)
│   ├── main/                # Entry point scene
│   └── map/                 # Battle map / combat scene
├── src/
│   ├── autoload/            # Singletons: Log, Constants, Dev, DevOverrides, GameData, MatchData, SaveManager
│   ├── core/
│   │   ├── ai/              # AI planner, scorer, plan model, telegraph & deployment planners
│   │   ├── combat/          # Match state, turns, resolution, deployment; turn systems, affinity, downed/revive
│   │   ├── data/            # Entity Resources, loader, validator, pipeline, stats, symbol atlas
│   │   ├── dev/             # Dev-mode flag support & dev override helpers
│   │   ├── economy/         # Pricing, LootRoller, ShopService, LevelScaler
│   │   ├── hex/             # Hex math, pathfinding, LOS, range queries
│   │   ├── progression/     # Character instances, name generation, stat resolver, profile/meta
│   │   └── run/             # Roguelike run container, encounters, events, death model
│   ├── debug/               # Debug readout
│   ├── map/                 # 3D map rendering, pawns, overlays, markers, camera, AI controller
│   ├── tools/               # Map editor model, CSV exporter/importer, entity schema, content pipeline
│   └── ui/                  # HUD, draft screen, dev menu, map editor UI
└── tests/
    ├── core/ai/             # AI planner & plan tests
    ├── core/combat/         # Combat unit + integration tests
    ├── core/data/           # Data layer tests
    ├── core/hex/            # Hex math tests
    ├── core/economy/        # Economy tests (pricing, shop, loot, validation, integration)
    ├── core/progression/    # Character instance & bridge tests
    ├── core/run/            # Run framework, encounter selector/generator tests
    ├── map/                 # Map/visual tests (incl. ability symbol pawns)
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
4. **DevOverrides** — `src/autoload/dev_overrides.gd` — dev cheat/override flags (A10; e.g. `DEV_SKIP_RECRUITMENT_GATE`, `DEV_ALL_CLASSES_UNLOCKED`)
5. **GameData** — `src/autoload/game_data.gd` — facade over `DataPipeline`
6. **DebugReadout** — `src/debug/debug_readout.gd` — debug overlay (gated by `Dev.enabled`)
7. **MatchData** — `src/autoload/match_data.gd` — per-match state transfer between scenes (incl. `mode` for turn-system selection)
8. **SaveManager** — `src/autoload/save_manager.gd` — versioned JSON persistence for bands, profile, runs

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
- **Job tree:** every character starts as **Vagabond** → unlocks **Thief/Soldier/Adept** at level 3 → advanced and elite classes branch out across all archetypes (the full tree is authored: 25 classes spanning physical, magical, control, and support — see `data/classes.json`)
- **`ClassData`** extended with: `archetype`, `branch`, `tier`, `growth`, `jp_costs`, `prerequisites`
- **`RaceData`** extended with: `base_stats` (StatKey→int)
- **`InstanceStatResolver`** computes base stats: race base_stats + active class modifiers + accumulated growth
- **`NameGenerator`** draws from `data/names/<race>.json` with seeded RNG
- **BattleUnit bridge:** `BattleUnit.from_instance()` synthesizes a CharacterData + derives StatBlock, feeding into the existing combat pipeline with no combat-layer changes

## Battle Bands & Save System (A5)

- **`BattleBand`** — persistent roster container: band_id, name, roster (`Array[CharacterInstance]`), inventory (`{equipment: [], consumables: []}`), gold
- **`SaveManager`** (autoload) — versioned JSON persistence at `user://saves/save.json`; atomic writes (`.tmp` + rename); band lifecycle (create/delete/get); version migration hook
- **`Recruiter`** — generates new instances from templates, deducts gold, scales recruits to band average level
- **`BpCalculator`** — `level × 3 + equipment_bp_sum + loadout_count × 2`; used for display and future encounter scaling
- **`BandPartyBuilder`** — converts fielded `CharacterInstance`s → `BattleUnit`s via `from_instance()`; generates throwaway opponent instances
- **`BandBattleLauncher`** — orchestrates band-to-battle transition: resolves fielded instances → builds parties → constructs match → sets MatchData (`ai_teams = ["playerB"]`) → scene change
- **`BandManagementScene`** — full-screen UI with 4-panel state machine: band select → roster view → instance inspect (stats, class switch, JP/abilities, equipment, dismiss) → field select → quick battle
- **MatchData** extended with: `active_band`, `fielded_ids`, `is_instance_battle`
- **CharacterInstance** extended with: `to_dict()`/`from_dict()` serialization (defensive defaults, type coercion for JSON)
- **Tunables** in `constants.json`: `ROSTER_CAP`, `RECRUIT_COST`, `RECRUIT_STARTING_GOLD`, `STARTING_INVENTORY`

## Economy System (A6)

- **`Pricing`** — static buy/sell price computation: authored `price` field (≥ 0) takes precedence; fallback derives from `bp_value × PRICE_PER_BP`; sell value = `round(buy_price × SELL_RATIO)`
- **`ShopService`** — transactional buy/sell on `BattleBand`: deducts/adds gold, routes equipment to `add_to_inventory()` and consumables (empty slot) to `add_consumable()`; returns `""` on success or error string
- **`LootRoller`** — rolls loot from authored `loot_tables.json` with depth scaling (`1.0 + LOOT_DEPTH_SCALE × depth`); injectable `RandomNumberGenerator` for deterministic testing; `grant_rewards()` applies rolled gold/equipment/consumables to a band
- **`ItemData`** extended with: `price: int = -1` (-1 = derive from bp_value)
- **Consumables:** items with empty `slot` are consumables; stacked in `inventory.consumables` as `{id, qty}` dicts; `BattleBand` has `add_consumable()`, `remove_consumable()`, `has_consumable()`, `consumable_qty()` helpers
- **Data files:** `data/loot_tables.json` (keyed dict of table definitions with gold ranges, weighted drops, roll counts); `data/shop_pools.json` (keyed dict of item ID arrays per pool)
- **DataPipeline** loads loot tables and shop pools as plain dictionaries (not `EntityRegistry`); validates pool item refs and loot table structure via `Validator`
- **Shop UI** integrated into `BandManagementScene` as `SHOP` panel state: buy list (from merged shop pools with prices), sell list (equipment + consumables with sell values), transaction feedback
- **Tunables** in `constants.json`: `SELL_RATIO` (0.5), `LOOT_DEPTH_SCALE` (0.1), `PRICE_PER_BP` (5)

## AI System (A7)

- **`AIPlan`** — plan model with step kinds (move, attack, ability, defend, wait) and AP cost tracking
- **`AIPlanner`** — enumerates legal candidates: reachable tiles, valid attack/ability targets per range/LoS/min-range, composite 2-AP plans, fallback plans; bounded to max 12 tiles for tractability
- **`AIScorer`** — utility heuristic weighing expected damage, kills, exposure, cover, elevation, hazards (A0), target priority, ability value, resource economy; terrain- and magic-aware (A3)
- **`AIController`** (`src/map/ai_controller.gd`) — scene-level driver executing plans via `TurnActions` (same action backend as the human player, no privileged access); includes pacing delays and visual feedback
- **Selection:** top-N sampling with temperature parameter; difficulty presets in `constants.json`

## Meta-Progression System (A10)

- **`Profile`** (`src/core/progression/profile.gd`) — persistent account-level state: `unlocked_templates`, `unlocked_classes`, `completed_runs`, `meta_unlocks`; `to_dict()`/`from_dict()` with safe defaults for backward compatibility
- **`MetaUnlockEngine`** (`src/core/progression/meta_unlock_engine.gd`) — evaluates data-driven unlock rules at run-end; trigger types: `run_complete`, `boss_kill`, `depth_reached`, `runs_completed`; `resolve_boons()` filters eligible starting boons by profile state
- **Data file:** `data/meta_unlocks.json` — rules array (trigger → grants to templates/classes/meta_unlocks) + starting_boons array (requires unlock → effect)
- **Recruitment gating:** `BandManagementScene` filters templates by `profile.unlocked_templates` (no gate when empty — fresh profiles see all templates)
- **Class seeding:** `CharacterInstance.generate()` accepts `bonus_classes` from profile; new recruits get profile-unlocked classes
- **Starting boons:** auto-applied at embark via `RunController.embark()` (gold bonus, down_limit_bonus)
- **Run shop:** buy-only shop overlay in `RunScene` using `ShopService.buy()` with all shop pools
- **SaveManager** stores `profile: Profile` (not Dictionary); loads via `Profile.from_dict()`
- **Dev tools:** profile cheats (grant templates/classes, reset, set completed_runs), DevOverrides flags (`DEV_SKIP_RECRUITMENT_GATE`, `DEV_ALL_CLASSES_UNLOCKED`), run dev panel (Win Run, Add Gold, Reset Downs)

## Encounters, Level Scaling & Economy Refinement (A11)

- **`EncounterData`** (`src/core/run/encounter_data.gd`) — resource: `id`, `min_band_level`, `enemies`, `map_id`, `level_offset`, `tags`, `modifiers`, `weight`
- **`EncounterSelector`** / **`EncounterGenerator`** (`src/core/run/`) — pick eligible encounters by band level and spawn level-scaled enemy instances into the run
- **`LevelScaler`** (`src/core/progression/level_scaler.gd`) — scales stats via `base_stats[k] + growth[k] × (level − 1)`
- **Data file:** `data/encounters.json` — 73 authored encounters, level-gated by `min_band_level`
- Band economy constants refined in `constants.json` (starting gold, recruit cost, gold-per-band-level)

## Interactive Deployment Zones (A12)

- **`DeploymentController`** (`src/core/combat/deployment_controller.gd`) — replaces hardcoded auto-deploy: AI deploys first, teams alternate placing one pawn each into legal deployment tiles; player clicks to place; completion advances to `ROUND_START`
- **`DeploymentPlanner`** (`src/core/ai/deployment_planner.gd`) — role/terrain heuristic: front/back by range, cover, elevation, hazard avoidance, anti-clustering

## Ability Symbol Pawns (A14)

- **`AbilitySymbolPawn`** (`src/map/ability_symbol_pawn.gd`) — `RigidBody3D` token that spawns, falls under real physics, lands on the target tile, dwells (~2.5s), then sinks; one per affected target. Replaces the old billboard action marker
- **`SymbolAtlas`** (`src/core/data/symbol_atlas.gd`) — resolves a symbol via fallback chain: ability id → element → effect type → default
- Brief blocking beat (max ~0.8s) before resolution continues

## Turn Systems & Telegraphed Speed-Round (A15)

- **`TurnSystem`** (`src/core/combat/turn_system.gd`) — abstract seam so combat can swap turn models; `MatchData.mode` selects the concrete system
- **`SpeedRoundTurnSystem`** (`src/core/combat/speed_round_turn_system.gd`) — single-player four-stage round: AI_PLANNING → PLAYER_PLANNING → RESOLUTION → ROUND_RESET; plans lock at commit, resolve in SPD order (seeded tie-break) with a validity policy (moves stop short, single-target fizzles, ground AoE hits current occupants)
- **`TelegraphService`** / **`IntentPlan`** (`src/core/ai/`) — build a telegraph of the AI's committed `AIPlan`; disclosure dial via `TELEGRAPH_MODE`
- **`RoundPlan`** (`src/core/combat/round_plan.gd`) — merges committed plans, SPD-sorted iteration
- **`OutcomeProjection`** (`src/core/combat/outcome_projection.gd`) — min/mid/max outcome ranges from `CombatResolver`

## Elemental Affinities & Critical Hits (A16)

- **`Affinity`** (`src/core/combat/affinity.gd`) — tier enum (ABSORB / IMMUNE / RESIST / NEUTRAL / WEAK), multiplier lookup, additive stacking across sources (race/class/item/terrain)
- **`CombatResolver`** applies element/affinity scaling post-formula and rolls crits; absorb routes to a heal; crit flagged in the result
- Abilities carry `effect.element` (fire/ice/lightning/dark/holy/earth/wind/water); `BattleUnit.effective_affinity(element)` resolves the stack
- Tunables in `constants.json`: `AFFINITY_MULT` table, `CRIT_CHANCE`, `CRIT_MULT`; neutral-default keeps pre-A16 content backward compatible

## Knockout & Revive Lifecycle (A17)

- **`BattleUnit`** gains `is_downed` / `downed_round` state and `is_active()` / `is_living()` predicates; a unit at HP ≤ 0 enters DOWNED, leaves the activation queue, and stays on the board
- **`CombatResolver.resolve_revive`** restores a downed ally to `REVIVE_HP_FRACTION` and re-enters the queue; revive is legal only on downed allies
- Victory is decided by living count; a still-downed unit at battle-end increments `downs_this_run`, and reaching `DOWN_LIMIT+1` permadeaths the character (`src/core/run/death_model.gd`)

## Multiplayer / Skirmish Charge-Time Clock (A20)

- **`ChargeTimeTurnSystem`** (`src/core/combat/charge_time_turn_system.gd`) — continuous clock: units accrue `ct += effective_SPD` per tick and act at threshold; acting resets CT with a surcharge (full action costs more than Wait); faster units act more often; seeded tie-break
- **`TurnScheduler`** (`src/core/combat/turn_scheduler.gd`) — per-unit CT bookkeeping, next-actor query, timeline
- Slowed/Haste statuses shift CT frequency; **skirmish container** (`scenes/skirmish/`, `src/ui/skirmish_setup.gd`) provides squad-size selection with vs-AI and local hot-seat play (no networking); telegraph is forced off in skirmish

## Specified but NOT yet implemented

These phases have spec docs in `docs/` but no implementation in `src/` yet — do not assume they exist:

- **A18: Reaction / Support / Movement Passives** — only a foundation exists (`passive: Dictionary` field on ability data + a validator exemption); no passive dispatch bus, slots, or seed passive abilities
- **A19: Facing & Flanking** — no facing state on `BattleUnit`, no arc classification, no flanking bonuses

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

The Alpha extends the MVP into a single-player game and, via A20, a local multiplayer/skirmish mode. Most sub-phases are **implemented and tested**; two (A18, A19) are **specified only** (see "Specified but NOT yet implemented" above), and A13 (coin flip & opening initiative) is **obsolete** — dropped, not to be implemented. Content has grown well past the original `alpha-specs.md` §12.2 targets: **82 abilities, 146 classes, 46 items, 141 character templates (incl. monster/NPC), 32 races (incl. monster races), 17 terrains, 73 encounters**; maps remain at 6.

Sub-phases (critical path A0→A3→A4→A5→A6→A8→A10; A1/A2 tooling and A9 content are parallel; A7 AI joins at A8; A11+ are post-A10 extensions):

- [x] A0: Terrain effects, condensed map format, dev flag & dev tools menu — **complete**
- [x] A1: Map editor (dev tool, gated by the dev flag) — **complete**
- [x] A2: CSV ↔ JSON content pipeline — **complete**
- [x] A3: `MAG`/`RES` stats & magical resolution — **complete**
- [x] A4: Character instances, classes & the Vagabond-rooted job tree — **complete**
- [x] A5: Battle Bands & save system (`user://`) — **complete**
- [x] A6: Economy — gold, shops & loot — **complete**
- [x] A7: AI opponent (`AIController` over `TurnActions`) — **complete**
- [x] A8: Roguelike run (branching node graph, ≤3 parallel paths, down-limit death) — **complete**
- [~] A9: Content expansion (authored via A1/A2) — **libraries well beyond target** (classes/abilities/items/characters/races/terrain/encounters); **maps (6) still below target**
- [x] A10: Polish & meta-progression (Profile, MetaUnlockEngine, recruitment gating, class seeding, starting boons, run shop, UX polish, seam audit) — **complete**
- [x] A11: Encounters, level scaling & economy refinement (`EncounterData`, `EncounterSelector`, `LevelScaler` in `progression/`, `data/encounters.json`) — **complete**
- [x] A12: Interactive deployment zones (`DeploymentController`, `DeploymentPlanner`) — **complete**
- [x] A14: Ability symbol pawns / physics drop feedback (`AbilitySymbolPawn`, `SymbolAtlas`) — **complete**
- [x] A15: Telegraphed speed-round + turn-system architecture (`TurnSystem`, `SpeedRoundTurnSystem`, `TelegraphService`) — **complete**
- [x] A16: Elemental affinities & critical hits (`Affinity`, resolver integration) — **complete**
- [x] A17: Knockout & revive lifecycle (downed state, `resolve_revive`, `DeathModel`) — **complete**
- [ ] A18: Reaction / support / movement passives — **spec only, foundation stub not wired**
- [ ] A19: Facing & flanking — **spec only, not implemented**
- [x] A20: Charge-time clock + skirmish container (`ChargeTimeTurnSystem`, `TurnScheduler`, skirmish scene) — **complete**

Key Alpha decisions: dev-tool map editor (player-facing later); CSV↔JSON authoring via spreadsheets; FFT-style progression (XP + JP + job tree + gold/shop + loot); roguelike single-player; every character starts **Vagabond** → unlocks **Thief/Soldier/Adept** at level 3 → archetype branches (support / control / physical·melee·ranged / magical·arcane·divine); characters permadie on the **3rd down** per run (tunable `DOWN_LIMIT`); the attack die and Defend die persist through the A3 magic change (Defend reduces magical damage too).

## Documentation

Phase specs and implementation plans live in `docs/`.

**MVP (implemented):**

- `rpg-specs.md` — master MVP specification
- `rpg-implementation-plan.md` — high-level phase roadmap
- `phase<N>-spec.md` / `phase<N>-implementation-plan.md` — per-phase details (0–11)

**Alpha (in progress — A0–A12, A14–A17, A20 implemented; A18/A19 spec only; A13 obsolete):**

- `alpha-specs.md` — master Alpha specification
- `alpha-implementation-plan.md` — Alpha milestone roadmap
- `alpha-phaseA<N>-spec.md` / `alpha-phaseA<N>-implementation-plan.md` — per-sub-phase details (A0–A20; A16–A20 are spec-only docs, no separate implementation-plan file)

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
