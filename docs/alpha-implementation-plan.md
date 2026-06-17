# RPG Battle Simulator — Alpha Implementation Plan (Milestones)

**Engine:** Godot 4.6.3 (do not auto-upgrade)
**Source spec:** `alpha-specs.md` (Alpha / progression, content & single-player)
**Builds on:** the completed MVP (Phases 0–11) and `rpg-implementation-plan.md`
**Format:** High-level phased milestones
**Date:** 2026-06-17

Each sub-phase ends in a demonstrable state with tests, exactly as the MVP phases did. The detailed per-sub-phase specs and task breakdowns will live in `alpha-phase<N>-spec.md` / `alpha-phase<N>-implementation-plan.md` (where `<N>` is `A0`–`A10`), mirroring the MVP documentation layout.

Build order favors **foundations and tooling first** (so content and combat can be authored at scale), then the **persistent character and economy layer**, then the **AI and the roguelike run that ties everything together**, and finally **content and polish**. Content authoring (A9) runs in parallel once the pipeline and schema are stable.

---

## Phase A0 — Terrain Effects, Condensed Map Format & Dev Flag

**Goal:** The foundations every later sub-phase leans on are in place.

Extend `terrain.json` to the structured effect schema (move cost, LoS, cover, damage-on-enter, damage-per-turn, status-on-enter, occupant modifiers, water/tags) and wire those effects into the existing systems through their injected providers: pathfinding/LoS read movement and sight fields, resolution reads cover, and new turn-lifecycle hooks apply enter/per-turn damage and status as units move and activate. Switch map serialization to the condensed, whitespace-minimal format (minified JSON, compact positional tile records, terrain by reference) with a loader that expands records back into typed `TileRecord`s and a one-time migration for the existing MVP maps. Introduce the `dev_mode` flag (config + launch-arg override, off by default) and a Dev Tools entry point that gates internal tooling and the existing debug overlay behind one switch. Exit when terrain effects measurably alter movement and combat in tests, all existing maps load from the condensed format with identical geometry, and toggling the dev flag shows/hides the Dev Tools menu.

---

## Phase A1 — Map Editor (Dev Tool)

**Goal:** Maps can be authored visually instead of by hand-editing JSON.

Build the map editor scene behind the A0 dev flag, reusing the existing 3D rendering and tile-picking. Implement the headless `MapEditorModel` (new/load/save, grid sizing and reshaping, terrain painting, elevation brush, deployment-zone marking, metadata, tile inspector, undo/redo) with the editor scene as a thin controller over it. Saving runs the standard validator and writes the condensed map format from A0; loading round-trips any existing map without loss. Keep editor logic fully separate from editor UI so a player-facing editor is a later re-skin. Exit when a developer can create, paint, save, and reload a playable map end to end through the GUI, and `from_map_data(to_map_data(x)) == x` holds for every existing map.

---

## Phase A2 — CSV ↔ JSON Content Pipeline

**Goal:** Content can be authored in spreadsheets at volume.

Build the converter that exports each consolidated JSON content table to CSV and re-imports CSV back to JSON, per entity type, runnable headless (and/or as a dev-tools utility). Define and implement the flattening convention for nested fields (dotted headers for fixed nested keys, JSON-encoded cells for variable-length/complex fields). Import reuses the existing validator and rejects malformed content with precise errors. The pipeline targets human-authored content (classes, abilities, items, templates, terrain), not the generated map files. Exit when a content table round-trips losslessly (`csv→json(json→csv(x))` is semantically identical to `x`) as a tested invariant, and an edit made in a spreadsheet imports cleanly and loads in-game.

---

## Phase A3 — Stat Additions & Magical Resolution

**Goal:** The combat model supports deep casters.

Add `MAG` and `RES` to the `StatKey` enum and let the single-point-of-expansion design carry them through validation, derivation, and the modifier stack. Extend the resolution math with a magical branch parallel to the physical one — spell/heal values scale with `MAG` and are mitigated by `RES` — replacing the MVP's "magic folded into per-ability values and DEF" simplification. Add the optional `mag_scaling` field to abilities and the new stat keys to class/race/item modifiers. This is the most invasive change to combat math and is sequenced before mass content authoring so spells are authored against the final model. Exit when magical and physical attacks resolve through their respective formulas in tested scenarios and all existing combat tests pass against the extended stat set.

---

## Phase A4 — Character Instances, Classes & Job Tree

**Goal:** Characters are persistent individuals who level and change jobs.

Introduce `CharacterInstance` (generated from a `CharacterTemplate`) with generated identity, level/XP, class-driven stat growth, per-class JP, unlocked classes, learned abilities, and a free-form ability loadout. Implement the archetype-based job tree: every instance starts as **Vagabond**, unlocks **Thief / Soldier / Adept** at `TIER1_UNLOCK_LEVEL` (default 3), and branches outward across the Support / Control / Physical / Magical archetypes via JP/level prerequisites. Add the authored class fields (archetype, branch, growth, prerequisites, jp_costs, tier). Wire instance → `BattleUnit` so a fielded instance produces the same runtime wrapper the MVP combat layer already consumes, sourced from derived effective stats and the loadout. Exit when an instance can earn XP/JP, level up with correct growth, unlock and switch classes along the tree, learn abilities, and deploy into a battle with its loadout.

---

## Phase A5 — Battle Bands & Save System

**Goal:** Players own and manage a persistent roster.

Implement the `BattleBand` (roster of instances, shared equipment inventory, consumables, gold) and the out-of-battle management UI (inspect, allocate JP, unlock/upgrade classes, set active class, assemble loadout, equip from inventory, recruit/dismiss). Build the `SaveManager` autoload persisting bands, instances, and an in-progress run as versioned JSON under `user://`, kept separate from authored `res://data/` content. Recruitment generates new Vagabond instances from available templates scaled to band power. Exit when a player can build a band, modify and equip its members, save and reload it intact across sessions, and take a fielded selection into a battle.

---

## Phase A6 — Economy: Gold, Shops & Loot

**Goal:** A reward-and-spend loop gives progression stakes.

Add band-level gold, authored loot tables scaled by run depth, and item prices (authored or derived from `bp_value`). Build the shop buy/sell interface (sell at a tunable fraction of price), usable at shop contexts and the management screen where permitted. Battles and nodes award gold, equipment, and consumables via the loot tables. Exit when completing a battle yields scaled loot, and a player can buy, sell, and equip purchased gear that persists on the band.

---

## Phase A7 — AI Opponent

**Goal:** Enemy units play competently, with variance.

Implement the `AIController` as a peer of the human `BattleController`, issuing actions through the same `TurnActions` backend with no privileged access. Per activation it enumerates legal candidate plans (move × action × target, pruned for tractability) and scores them with a utility heuristic that weighs expected damage dealt/taken, exposure and terrain (cover, elevation, hazards from A0), target priority, ability value, and AP/WP economy. Add variance by sampling among the top-N scored plans with a temperature/difficulty parameter, seeded for reproducibility. Exit when the AI can play a full battle against a human-controlled band — using terrain and abilities sensibly, threatening but beatable — with difficulty presets that visibly change its optimality.

---

## Phase A8 — Roguelike Run Framework

**Goal:** The single-player loop plays start to finish.

Build the run as a graph of nodes (Battle, Boss, Event, Boon, Hazard, Shop, Rest) with depth-based difficulty. Implement encounter generation (map selection plus an enemy band composed from templates scaled to a target BP for the depth), the down-limit death model (default 2 downs per run, permadeath on the next, counter reset per run, tunable), and run win/loss conditions. Event/Boon/Hazard nodes may be simple, data-driven outcome tables; the node framework must be extensible. This sub-phase composes A4–A7 into a playable session. Exit when a player can embark with a band, traverse a generated run node by node, fight AI battles that scale with depth, lose characters to the down limit, and reach a win or loss.

---

## Phase A9 — Content Expansion

**Goal:** Enough breadth that builds feel deep and meaningful.

Author the large content libraries through the A2 pipeline and A1 editor: the expanded class job tree across all archetypes (toward ~20+ classes), the ability/spell library (~80+, authored against the A3 magical model), equipment (~50+ with prices), character templates (~20+), expanded effectful terrain, and additional maps (~15+). Extend the validator's referential checks to the new cross-references (job-tree prerequisites form a valid tree rooted at Vagabond; loot/shop/event tables reference real entities). This track runs in parallel once A2–A4 are stable. Exit when the content targets are met (or consciously re-scoped), all content passes validation at boot, and runs draw varied maps, enemies, and loadouts.

---

## Phase A10 — Polish & Meta-Progression

**Goal:** The Alpha is a coherent, demonstrable single-player experience.

Add the account-level profile and meta-progression (unlocked templates/classes, completed-run tracking, optional starting boons) persisted via the save system. Tune the curves that span the whole loop — XP/JP gains, growth, depth→BP scaling, loot quality, economy, AI difficulty, and the down limit — against playtests. Add UX polish across the management, shop, run-map, and battle screens, and confirm the architecture leaves clean seams for deferred features (player-facing editor, networked multiplayer, richer events, deeper AI). Exit when a full run can be played from band-building through victory or defeat, meta-progression persists across runs, and the systems feel fair in informal playtesting.

---

## Dependency Summary

```
A0 ─┬─> A1 (editor)
    ├─> A7 (AI needs terrain awareness)
    └─> A3 ─> A4 ─> A5 ─> A6 ─┐
                               ├─> A8 ─> A10
                         A7 ──┘
A2 (pipeline) ─────────────────┐
A1 + A2 + A3 + A4 ─> A9 (content, parallel) ─> A10
```

The critical path runs **A0 → A3 → A4 → A5 → A6 → A8 → A10**: foundations, then the stat model, the persistent character layer, the economy, the run that composes them, and polish. **A7 (AI)** depends on A0 and joins at A8. **A1 (editor)** and **A2 (pipeline)** are tooling tracks that unblock the **A9 (content)** parallel track once the schema (A3–A4) is stable. As in the MVP, content authoring layers on continuously rather than waiting for a single phase.
