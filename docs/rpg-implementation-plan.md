# RPG Battle Simulator — Implementation Plan (Milestones)

**Engine:** Godot
**Source spec:** `rpg-specs.md` (MVP / core systems)
**Format:** High-level phased milestones
**Date:** 2026-05-29

Each phase ends in a demonstrable state. Build the data and map foundations first, then combat, then the player-facing flow, then balance and polish. Phases are roughly sequential, but content authoring (P6) runs in parallel once the data layer exists.

---

## Phase 0 — Project Foundation

**Goal:** A running Godot project with the scaffolding to build everything else.

Set up the Godot project, version control, and folder structure. Establish core conventions: scene organization, a simple resource-loading pipeline (Godot `Resource`/JSON for game data), and a debug/test harness. Define the axial hex coordinate system (q, r) and a shared math module for hex distance, neighbors, and elevation. Define the `StatKey` enum (canonical stat keys) and `TileRecord` typed class (replacing raw dict tiles). Exit when the project boots to an empty scene, the hex math has unit tests passing, and `StatKey`/`TileRecord` compile and are tested.

---

## Phase 1 — Data Layer & Content Schema

**Goal:** All game entities exist as loadable data, matching the spec's schemas; the authored-data vs. runtime-state boundary is established.

Implement the data models for Character, Class, Race, Ability/Spell, Item/Equipment, Map, and the tunable constants block (§9 of the spec). Use Godot custom `Resource` types (or JSON loaded into typed objects) so content is authored without code changes. Wire a content loader and a validator that rejects malformed entries. Define the `StatKey` enum (§4.2.1) and validate all stat-keyed dictionaries against it. Validate ability effects against their structured `effect_type` schemas (§9.3.1). Define the `BattleUnit` skeleton class (§9.6) — the runtime wrapper that separates immutable authored data from mutable per-battle state — with no combat logic yet. Exit when the eight sample characters from §6 load from data, pass validation, and a `BattleUnit` can be instantiated from a loaded character.

---

## Phase 2 — Hex Map & 3D Representation

**Goal:** A 3D hex map renders on screen with terrain and elevation, using multi-layer tiles.

Build the map scene: a grid of hex tiles (consuming `TileRecord` from Phase 1) with per-tile elevation and terrain type, rendered in 3D. Each tile node carries three visual layers (base terrain, overlay, selection) that can be shown independently — no single-material-override conflicts. Implement an FFT-style camera (pan, rotate, zoom). Render terrain visually (grass, brush, trees, rocks, water, cliffs) and stacked elevation. Add tile selection/highlighting via the selection layer and a coordinate readout for debugging. Exit when a hand-authored sample map (e.g., `forest_clearing`) loads from data and displays correctly with selectable tiles.

---

## Phase 3 — Movement, Range & Line of Sight

**Goal:** Spatial rules from the spec work on the map.

Implement pathfinding over the hex grid respecting move cost, impassable terrain, and the Jump/Climb elevation limit (§3.2, §4.3). Implement range calculation via an `effective_range` function (hex distance; designated extension point for vertical range) and line-of-sight checks blocked by tall terrain/obstacles, including the "higher attacker sees over" rule. Spatial-rule functions receive terrain properties through an injected provider (not direct `GameData` access) for testability and future terrain mutation. Add movement-range and target-range overlays. The placed marker uses a `BattleUnit` instance (from Phase 1's skeleton) to validate the runtime-state pattern. Exit when a placed character shows a correct reachable-tiles overlay and valid attack targets given LoS and elevation.

---

## Phase 4 — Combat Core: Activation & Action Economy

**Goal:** The turn structure plays out end to end.

Implement match setup and deployment zones, first-activation determination, and the **alternating activation** round loop with the spent/reset cycle (§7.2–7.3). Implement the **2 AP** action economy and the action catalog: Move, Attack, Ability/Spell, Use Item, Defend/Overwatch, Wait (§7.4), including per-ability AP restrictions. Exit when two manually controlled parties can alternate activations and spend AP on moves and basic actions for a full round.

---

## Phase 5 — Combat Resolution

**Goal:** Actions produce correct outcomes.

Implement the resolution math (§7.5): physical damage formula, spell/heal values, accuracy with cover and elevation bonuses, area/burst effects, HP and downing, and item-bound exceptions (e.g., revive). Apply the tunable constants (ELEV_BONUS, COVER_DEF). Add combat log output for verification. Exit when each sample ability resolves with correct damage/healing, range, area, and elevation/cover modifiers in tested scenarios.

---

## Phase 6 — Content: Roster, Abilities & Maps

**Goal:** Enough authored content to make matches varied.

Author the full sample roster (§6) as data, each ability and item with its values, and 2–3 maps per tier scaled to size (§5.2). This phase runs in parallel with P4–P5 as soon as the schema (P1) is stable. Exit when all sample characters are playable with their loadouts and at least one map per tier exists.

---

## Phase 7 — Party Building & Match Setup

**Goal:** Players can draft legal parties and start a match.

Implement tier selection (Skirmish / Standard / Large), the shared premade pool, and the drafting flow with BP-cap and character-count validation (§5). Build the screen to assemble a party, see remaining BP, and confirm a legal list, then hand off to deployment. Exit when both players can draft valid parties of a chosen tier and proceed into a live battle.

---

## Phase 8 — Combat UI & Unit Visuals

**Goal:** Players can see their units on the map and control all combat actions through a visual interface.

Add 3D pawn meshes representing deployed characters on the hex map, with team coloring, active-unit highlighting, and smooth movement animation (§7.7). Build a full combat HUD: action panel with buttons for all six action types (including ability and item browsers), unit info display, combat log, turn order tracker, and team roster sidebar. Replace the keyboard-only Phase4Demo controller with a BattleController that wires the HUD to the existing TurnActions backend. Keep keyboard shortcuts as alternatives. Exit when a complete match can be played using the visual UI with all actions accessible, pawns visible and animated, and combat state readable at a glance.

---

## Phase 9 — Victory Conditions & Match Flow

**Goal:** Matches reach a defined end.

Implement the rout/last-party-standing logic (§8): elimination, the rout threshold (ROUT_THRESHOLD), simultaneous-loss draw handling, and the end-of-match state with a result screen. Connect the full loop: draft → deploy → rounds → victory → result. Exit when a complete match can be played start to finish and ends correctly.

---

## Phase 10 — Balancing & Tuning

**Goal:** BP values and constants feel fair.

Validate the BP derivation heuristic (§7.6) against playtests, expose the tunable constants for quick iteration, and adjust ability/equipment point values. Add tooling to run or replay scenarios and inspect outcomes. Exit when the sample roster shows no dominant or dead picks in informal playtesting.

---

## Phase 11 — Polish & Future Hooks

**Goal:** First playable feels finished and is extensible.

Add UI polish, basic feedback (hit/heal/move cues), and quality-of-life (undo within an activation, clear turn indicators). Confirm the architecture leaves clean seams for deferred features (§10): in-app character builder and free-form multiclassing, larger content libraries, additional victory modes, status/elemental systems, AI, and networking. Exit when the MVP is a coherent, demonstrable first playable.

---

## Dependency Summary

```
P0 → P1 → P2 → P3 → P4 → P5 → P8 → P9 → P10 → P11
            P1 → P6 (parallel, feeds P5–P9)
            P3 + P5 → P7 (party building needs combat to be meaningful)
```

The critical path runs through the combat and presentation systems (P3–P5, P8–P9). Content authoring (P6) is the main parallel track. Party building (P7) and balancing (P10) layer on once combat resolves correctly.
