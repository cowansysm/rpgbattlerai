# RPG Battle Simulator

Tactical battle simulator in the style of Final Fantasy Tactics, built with **Godot 4.6.3** (standard, non-.NET build) and **GDScript**.

**Do not auto-upgrade the engine version.** Hex orientation is **flat-top**, committed project-wide.

## Project Structure

```
res://
├── addons/gut/              # GUT v9.6.0 test framework (vendored)
├── assets/icons/            # Status effect and ability icons
├── data/
│   ├── abilities.json       # 790 abilities (learned via JP; skills, spells, item-bound, passives)
│   ├── characters.json      # 160 character templates (20 playable + monster/NPC templates for encounters)
│   ├── classes.json         # 268 class/job definitions (128 player + 140 monster; single vagabond root → 10-tier level-gated DAG)
│   ├── items.json           # 128 items (equipment + consumables)
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

## Progression System (A4, redesigned by the content overhaul)

> The content redesign (Phases 0–3, adopted) replaced the old 4-tier
> (starting/tier-1/advanced/elite) tree with a **10-tier** model. See
> `docs/content-redesign-spec.md` and `docs/content-redesign-phase3-plan.md` for the
> authoritative design.

- **`CharacterInstance`** — persistent character with generated identity (name from race tables), level/XP, JP per class, unlocked classes, learned abilities, equipment loadout
- **10-tier job tree:** `tier` is a **non-negative integer (0–9)** measuring unlock depth (the count of a class's transitive prerequisites); tiers grant no inherent bonus. A single root **`vagabond`** (tier 0) unlocks **8 tier-1 classes** at vagabond level 3: `squire, footman, apprentice, acolyte, page, cutpurse, tinker, slinger`. From there the tree chains through 10 tiers as a valid DAG (multi-parent merges allowed). `soldier`/`thief` are now **tier 2**; the old `adept` class is **removed**. The full authored tree spans **268 classes (128 player + 140 monster)** across 6 archetypes (`physical_attack`, `physical_defense`, `magical_attack`, `magical_defense`, `support`, `control`) — see `data/classes.json`.
- **Level-gated class unlocks:** `prerequisites: {"classes": [["<prereq_class>", <level>]]}` — reach the required level in a prerequisite class to unlock the next. No prerequisite references an equal- or higher-tier class.
- **Learn-via-JP:** player classes have **empty `granted_abilities`**; every skill/spell is learned by spending JP (`jp_costs`) and then equipped into the loadout. Passives are equipped into reaction/support/movement slots, not usable as actions. Core combat actions (move/attack/defend/wait/item) are intrinsic to the action economy, so a skill-less unit is still fully combat-functional.
- **Recruits start skill-less:** new recruits carry only intrinsic actions and receive a small random **starting-JP pool** on their starting class (tunables `RECRUIT_STARTING_JP_MIN=20` / `RECRUIT_STARTING_JP_MAX=50` in `constants.json`) so they can immediately buy 1–2 baseline skills.
- **`ClassData`** extended with: `archetype`, `branch`, `tier` (int), `growth`, `jp_costs`, `prerequisites`
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
- **Save version 3 (content redesign):** `SaveManager` bumped to v3 with a **clean-slate reset** — incompatible pre-v3 saves (which reference removed IDs like `adept`) are discarded/reset on load rather than migrated. Recruits now start **skill-less** with a small random starting-JP pool (see Progression System).
- **Tunables** in `constants.json`: `ROSTER_CAP`, `RECRUIT_COST`, `RECRUIT_STARTING_GOLD`, `STARTING_INVENTORY`, `RECRUIT_STARTING_JP_MIN`/`RECRUIT_STARTING_JP_MAX`

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
- Slowed/Haste statuses shift CT frequency; **skirmish container** (`scenes/skirmish/`, `src/ui/skirmish_scene.gd`) provides squad-size selection with vs-AI and local hot-seat play (no networking); telegraph is forced off in skirmish

## Reaction / Support / Movement Passives (A18)

- **Passive ability types:** `AbilityData` gains `passive_kind` (`reaction` | `support` | `movement` | `""` for active), plus `trigger` (reaction event + guards) and `modifier` (support/movement effect) descriptors; validated in `validator.gd`, round-tripped through the CSV schema
- **Slots:** `CharacterInstance` has one `reaction_slot` / `support_slot` / `movement_slot`, learned via JP and equipped via `equip_passive()`; save-migration-safe serialization. Slots are carried onto `CharacterData` (`reaction_passive`/`support_passive`/`movement_passive`) so **authored enemies** get passives too, not just player instances
- **`PassiveDispatch`** (`src/core/combat/passive_dispatch.gd`) — typed event bus: `ON_HIT`, `ON_DAMAGED`, `ON_LOW_HP`, `ON_TURN_START`, `ON_MOVE_QUERY`, `ON_HAZARD_ENTER`. Handles Counter / Auto-Potion / Defend-Reflex; `reaction_locked` prevents counter-of-counter chains; reactions route through `CombatResolver` roll seams for determinism and never un-down (respects A17)
- **Resolution seam:** `CombatResolver.resolve_attack`/`resolve_damage` take a single trailing `ctx: Dictionary` (shared with A19) that carries state so damage events can fire passives
- **Support/Movement** are modifiers, not events: support pushes `StatBlock` modifiers (Magic/Attack Boost) or flags (`wp_cost_mult` for Half-WP); movement uses stat mods (+1 Jump, Move +1) and an `ignores_hazards` flag
- **AI/telegraph:** `AIScorer` weighs `counter_risk` (avoid meleeing a known Counter unit); `TelegraphService` annotates likely reactions; passive-slot assignment UI in `band_management_scene.gd`
- **Tunables** in `constants.json`: `PASSIVE_LOW_HP_PCT`, `PASSIVE_AUTO_POTION_HEAL`, `PASSIVE_MAGIC_BOOST`, `PASSIVE_ATTACK_BOOST`, `PASSIVE_HALF_WP_MULT`, `PASSIVE_DEFEND_REFLEX_DEF`, `AI_WEIGHTS.counter_risk`

## Facing & Flanking (A19)

- **Facing state:** `BattleUnit.facing` is an index (0–5) into `Hex.DIRECTIONS`; **battle-scoped, not persisted** (reset on construction, set at deployment toward the enemy zone, updated to the final step on move and toward the target on a no-move action)
- **Arc classification:** `Hex.arc_of(attacker_dir, target_facing)` / `Hex.arc_between(...)` returns `Hex.Arc.FRONT` (facing ±1), `FLANK` (sides), or `REAR` (opposite), reusing existing flat-top direction math
- **Flanking bonuses:** `FacingBonus` (`src/core/combat/facing_bonus.gd`) reads `FLANK_HIT`/`FLANK_CRIT`/`REAR_HIT`/`REAR_CRIT`; applied additively (with elevation) in `resolve_attack`/`resolve_damage`. Front = zero (regression guard); the new basic-attack crit roll is gated behind `crit_bonus > 0` so front attacks consume no extra RNG and existing seeds hold. Only the **primary** AoE target gets an arc bonus (splash = front)
- **AI/telegraph/forecast:** `AIScorer` seeks flank/rear and penalizes `rear_exposure`; `OutcomeProjection` and the player forecast (`battle_hud.show_forecast`) show the arc bonus pre-commit; pawns show a facing chevron
- **A18 interaction:** Counter fires only from **defensible** arcs (front/flank), blocked from the rear; the AI's counter-risk penalty is suppressed for a rear approach
- **Tunables** in `constants.json`: `FLANK_HIT`, `FLANK_CRIT`, `REAR_HIT`, `REAR_CRIT`, `AI_WEIGHTS.rear_exposure`

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

The Alpha extends the MVP into a single-player game and, via A20, a local multiplayer/skirmish mode. All sub-phases except the obsolete A13 are **implemented and tested**; A13 (coin flip & opening initiative) is **dropped, not to be implemented**. Content has grown well past the original `alpha-specs.md` §12.2 targets and was further overhauled by the content redesign (Phases 0–3, adopted; see `docs/content-redesign-spec.md`): **790 abilities, 268 classes (128 player + 140 monster), 128 items, 160 character templates (20 playable + monster/NPC), 32 races (incl. monster races), 17 terrains, 73 encounters**; maps remain at 6.

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
- [x] A18: Reaction / support / movement passives (`PassiveDispatch`, passive slots, seed passives) — **complete**
- [x] A19: Facing & flanking (`Hex.arc_of`, `FacingBonus`, chevron visuals, Counter-vs-facing gate) — **complete**
- [x] A20: Charge-time clock + skirmish container (`ChargeTimeTurnSystem`, `TurnScheduler`, skirmish scene) — **complete**

Key Alpha decisions: dev-tool map editor (player-facing later); CSV↔JSON authoring via spreadsheets; FFT-style progression (XP + JP + job tree + gold/shop + loot); roguelike single-player; every character starts **`vagabond`** (tier 0) → at vagabond level 3 unlocks **8 tier-1 classes** (`squire, footman, apprentice, acolyte, page, cutpurse, tinker, slinger`) → a level-gated 10-tier class-unlock DAG across 6 archetypes (physical_attack/physical_defense, magical_attack/magical_defense, control, support); abilities are learned via JP (empty `granted_abilities`); characters permadie on the **3rd down** per run (tunable `DOWN_LIMIT`); the attack die and Defend die persist through the A3 magic change (Defend reduces magical damage too).

## Documentation

Phase specs and implementation plans live in `docs/`.

**MVP (implemented):**

- `rpg-specs.md` — master MVP specification
- `rpg-implementation-plan.md` — high-level phase roadmap
- `phase<N>-spec.md` / `phase<N>-implementation-plan.md` — per-phase details (0–11)

**Alpha (in progress — A0–A12, A14–A20 implemented; A13 obsolete):**

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
