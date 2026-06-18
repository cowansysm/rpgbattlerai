# Phase A0 — Terrain Effects, Condensed Map Format & Dev Flag Specification

**Parent plan:** `alpha-implementation-plan.md` (Phase A0)
**Master spec:** `alpha-specs.md` (§3.2 dev flag, §4 terrain, §4.4 condensed maps)
**Builds on (MVP):** `phase2-spec.md` (`HexGraph`, `MapData`, `TerrainProps`, tile rendering), `phase4-spec.md` (turn lifecycle), `phase5-spec.md` (resolution & cover)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-17

---

## 1. Purpose & Scope

Phase A0 lays the three foundations the rest of the Alpha leans on: an **effectful, data-driven terrain model**, a **condensed map serialization format**, and a **dev-flag-gated dev tools** entry point. It is the Alpha analogue of Phase 0 — mostly infrastructure, little player-visible novelty — and it deliberately ships before the map editor (A1), AI (A7), and content authoring (A9), all of which depend on it.

The MVP already has a real terrain spine: `TerrainProps` (move cost, impassable, blocks_los, cover, los_height), loaded by `TerrainRegistry` from `data/terrain.json`, and surfaced to spatial rules through the **injected `HexGraph` provider** (`terrain_props()`, `move_cost()`, `is_impassable()`, `effective_cover()`). Phase A0 **extends** that spine rather than replacing it — adding hazard, water, and occupant-modifier effects and wiring the new ones into movement and the turn lifecycle.

### In scope

- Extend `TerrainProps` and `data/terrain.json` with the Alpha effect schema: `damage_on_enter`, `damage_per_turn`, `status_on_enter`, `occupant_modifiers`, `is_water`, and `tags` (alpha-specs §4.1).
- Wire the **new** effects into existing systems via the `HexGraph` provider and new turn-lifecycle hooks. (Move cost, impassability, LoS, and cover are already integrated in the MVP and only gain new data.)
- A **condensed, whitespace-minimal map format** (minified JSON, compact positional tile records, terrain by reference), a loader that accepts it, and a one-time migration of the existing maps.
- A **dev flag** (`Dev` autoload) sourced from build type, launch argument, and user config, plus a **Dev Tools menu** that gates internal tooling (the existing `DebugReadout`, and the A1 map editor entry point) behind it.

### Out of scope

- The map editor itself (Phase A1 — A0 only provides the dev-flag entry point and the save format it will write).
- The CSV content pipeline (Phase A2).
- New stats / magical resolution (Phase A3).
- Authoring large quantities of new terrain types or maps (Phase A9) — A0 adds the *schema* and a representative example or two, not the full library.
- Any swimming / deep-water traversal rules beyond the MVP's "deep water is impassable."

### Exit criteria

Phase A0 is complete when:

1. `TerrainProps` and `terrain.json` carry the new effect fields, and `TerrainRegistry` loads them with sensible defaults for terrain that omits them.
2. A unit entering a `damage_on_enter` tile takes damage; a unit starting its activation on a `damage_per_turn` tile takes damage; a `status_on_enter` tile applies its status; `occupant_modifiers` are applied while occupying and removed on leaving — all covered by unit tests.
3. Existing cover/move-cost/LoS behavior is unchanged (regression tests green).
4. Maps load from the condensed format with **identical geometry** to the pre-migration maps; the existing maps are migrated; a round-trip (`to_map_data(from_map_data(x)) == x`) holds.
5. Toggling the dev flag shows/hides the Dev Tools menu and the `DebugReadout` overlay; with the flag off, no dev entry point is reachable through normal navigation.

---

## 2. Design Decisions (Phase A0)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Terrain provider** | Keep the existing **`HexGraph` injected-provider** seam; add new accessors there rather than giving combat code direct `GameData` access. | Preserves the MVP's testability-with-stubs contract; spatial and combat rules stay decoupled from content loading. |
| **Effect data location** | Effects live **once per terrain type** in `terrain.json`, referenced by tiles — not duplicated per tile. | Keeps maps small (reinforced by §5) and tuning centralized. Per-tile overrides remain a deferred optional (`tile_effects`). |
| **Hazard timing** | `damage_on_enter` resolves **during move resolution**; `damage_per_turn` resolves at the **start of the occupant's activation**. | Matches player intuition (stepping on spikes hurts immediately; standing in lava hurts each turn) and slots into existing `TurnActions`/`RoundManager` flow. |
| **Occupant modifiers** | Applied via the existing **`StatModifier` stack** with `source = "terrain"`, recomputed on each move and at deployment. | Reuses the MVP three-layer stat model; no special-casing per source. |
| **Map format** | **Minified JSON with compact positional tile records** `[q, r, elevation, terrain]`; loader accepts both condensed and the MVP verbose form. | Maps are generated by the editor (A1), not hand-edited; compactness shrinks files and diffs. Backward-compatible loading avoids a hard cutover. |
| **Dev flag** | A single **`Dev` autoload** (`enabled: bool`) sourced from `OS.is_debug_build()`, a `--dev` / `--no-dev` launch arg, and a `user://` config override. | One coherent on/off switch for all dev tooling; player builds default off; developers can flip without code edits. |

---

## 3. Terrain Effect Schema

### 3.1 Extended `TerrainProps`

`TerrainProps` (a `Resource`) gains the Alpha effect fields alongside the existing ones. All new fields are optional with neutral defaults, so existing terrain entries remain valid.

| Field | Type | Default | Meaning | Status |
|-------|------|---------|---------|--------|
| `move_cost` | `int` | `1` | AP-movement cost to enter (`"impassable"` → `impassable=true`). | MVP (unchanged) |
| `impassable` | `bool` | `false` | Blocks ground movement entirely. | MVP |
| `blocks_los` | `bool` | `false` | Blocks line of sight (subject to elevation). | MVP |
| `cover` | `int` | `0` | Soft-cover ranged-DEF bonus for an occupant. | MVP |
| `los_height` | `int` | `0` | Visual/LoS height of the terrain feature. | MVP |
| `damage_on_enter` | `int` | `0` | Damage dealt when a unit enters the tile. | **A0 new** |
| `damage_per_turn` | `int` | `0` | Damage dealt at the start of an occupant's activation. | **A0 new** |
| `status_on_enter` | `{status_id: String, duration: int}` or `null` | `null` | Status applied on entry. | **A0 new** |
| `occupant_modifiers` | `Array` of `{key, value}` | `[]` | Stat modifiers applied while occupying (`key` is a valid `StatKey`). | **A0 new** |
| `is_water` | `bool` | `false` | Tags the tile as water for ability/movement interactions. | **A0 new** |
| `tags` | `Array[String]` | `[]` | Free-form terrain classification for content and AI heuristics. | **A0 new** |

> The existing per-tile `tags` on `TileRecord` and the `HexGraph.TAG_EFFECTS` table continue to function; terrain-level `tags` are a separate, type-level classification (e.g., `"hazard"`, `"forest"`) consumed by AI heuristics in A7.

### 3.2 `terrain.json` (extended example)

`data/terrain.json` remains the same keyed-dict file `TerrainRegistry` already loads; entries simply gain fields. Example additions:

```json
{
  "grass":  { "move_cost": 1, "cover": 0 },
  "brush":  { "move_cost": 2, "cover": 1, "tags": ["forest"] },
  "lava":   { "move_cost": 2, "damage_per_turn": 4, "tags": ["hazard"] },
  "spikes": { "move_cost": 1, "damage_on_enter": 3, "tags": ["hazard"] },
  "bog":    { "move_cost": 2, "status_on_enter": { "status_id": "slowed", "duration": 1 },
              "occupant_modifiers": [{ "key": "spd", "value": -1 }], "tags": ["hazard"] },
  "shallow_water": { "move_cost": 2, "is_water": true },
  "deep_water":    { "move_cost": 0, "impassable": true, "is_water": true }
}
```

Existing terrain keeps its current values; only new categories declare the new effects.

---

## 4. Combat & Movement Integration

The MVP already routes terrain through `HexGraph`. Phase A0 adds accessors for the new fields and three new effect hooks. **Move cost, impassability, LoS, and cover require no behavioral change** — they already read `TerrainProps` via the graph and only see richer data.

### 4.1 `HexGraph` accessors (new)

`HexGraph` exposes the new fields through the same `terrain_props()` indirection it already uses:

- `damage_on_enter(c) -> int`
- `damage_per_turn(c) -> int`
- `status_on_enter(c) -> Dictionary` (`{}` when none)
- `occupant_modifiers(c) -> Array`
- `is_water(c) -> bool`

These are pure reads off the injected provider, keeping the graph stub-testable.

### 4.2 Hazard & status hooks

| Effect | When it fires | Where it hooks |
|--------|---------------|----------------|
| `damage_on_enter` | The moment a unit's move resolves onto the tile. | `TurnActions.execute_move` — after the unit's `position` updates, apply damage and route through the existing downing path (`_handle_downing`). |
| `status_on_enter` | Same moment as enter damage. | `TurnActions.execute_move` — apply via the existing status mechanism used by abilities. |
| `damage_per_turn` | The start of the unit's activation. | A new **activation-start hook** invoked from the turn flow (`RoundManager` activation advance / `BattleController`), before the player/AI is handed control. |

Both damage paths produce combat-log outcomes consistent with the MVP's `outcomes` array so the HUD and AI can read them, and both respect victory/downing detection.

### 4.3 Occupant modifiers

While a unit occupies a tile, that terrain's `occupant_modifiers` are present on the unit's `StatBlock` modifier stack with `source = "terrain"`:

- On move (and at deployment), the unit clears any `source = "terrain"` modifiers and re-applies the destination tile's `occupant_modifiers`.
- Effective stats (and derived `move`/`jump_climb`) recompute automatically through the existing `effective()` path.
- This reuses the MVP push/pop mechanism with no new modifier semantics.

### 4.4 Cover (already integrated — confirmation only)

`CombatResolver` already applies `target_cover` × `COVER_DEF` for ranged attacks, sourced from `HexGraph.effective_cover()`. A0 changes nothing here except that more terrain types now carry `cover` values. This is called out so it is **not** re-implemented.

---

## 5. Condensed Map Serialization

### 5.1 Format

Map files become **machine-generated, whitespace-minimal** artifacts:

- **Minified JSON** — no indentation or superfluous newlines; the file is effectively one line.
- **Compact tile records** — each tile is a positional array `[q, r, elevation, terrain]` rather than an object with repeated keys. (`tags`, when present, append as a 5th element: `[q, r, elevation, terrain, [tags...]]`.)
- **Terrain by reference** — `terrain` is the short string id already used in `terrain.json`; effects are never inlined per tile.
- **Metadata stays keyed** — top-level `id`, `tier`, and `deployment_zones` remain named keys for clarity; only the large `tiles` array is compacted.

Condensed example (single line in practice, shown wrapped here):

```json
{"id":"forest_clearing","tier":"standard","tiles":[[0,-4,2,"trees"],[1,-4,2,"trees"],[0,-3,1,"brush"]],"deployment_zones":{"playerA":["0,0"],"playerB":["2,0"]}}
```

### 5.2 Loader contract

- `DataFactory.make_map` accepts **both forms**: a tile that is an `Array` is read positionally (condensed); a tile that is a `Dictionary` is read by key (the MVP verbose form). Both produce identical `TileRecord`s.
- The condensed records expand into the same typed `Array[TileRecord]` on `MapData`; **no downstream consumer changes** (`HexGraph`, `MapBuilder`, etc. are untouched).
- A serializer (`to_map_data` / map-writer) produces the condensed form and is the format the A1 editor will write. Round-trip fidelity holds: `to_map_data(from_map_data(x)) == x` for any valid map.

### 5.3 Migration

A one-time migration converts the existing `data/maps/*.json` from the verbose MVP form to condensed. The migration is verified by asserting tile-set equality (same coords, elevations, terrains, tags) before and after — geometry must be identical.

---

## 6. Dev Mode & Dev Tools Access

### 6.1 The dev flag

A new **`Dev` autoload** exposes `Dev.enabled: bool`, resolved once at boot in priority order:

1. Explicit launch argument: `--dev` forces on, `--no-dev` forces off (via `OS.get_cmdline_args()`).
2. User config override (`user://dev.cfg`), if present.
3. Default: `OS.is_debug_build()` (on in editor/debug builds, off in exported release builds).

`Dev` is registered after `Log`/`Constants` and before scene-level controllers so any scene can query it at `_ready`.

### 6.2 Dev Tools menu

When `Dev.enabled` is true, a **Dev Tools** entry point is exposed (a menu item on the main/entry scene and/or a debug hotkey overlay). It is the single launch point for internal tooling:

- **Map Editor** (added in Phase A1).
- Future content/scenario utilities.

When `Dev.enabled` is false, the Dev Tools entry and all its routes are absent — the editor scene is unreachable through normal navigation.

### 6.3 Gating existing dev affordances

The existing `DebugReadout` overlay is brought under the same switch: it renders only when `Dev.enabled`. This makes "dev tools" one coherent concept and keeps debug UI out of player builds. No dev-only code path affects gameplay when the flag is off.

---

## 7. Risks & Notes

- **Regression surface.** Extending `TerrainProps` and `HexGraph` touches the most-used spatial paths. Lock existing move-cost/LoS/cover behavior with regression tests before adding hooks.
- **Activation-start hook placement.** `damage_per_turn` must fire exactly once, at the right moment, for the right unit (including downed-unit edge cases from Phase 11). Verify it interacts correctly with the existing reset/queue logic in `RoundManager`.
- **Downing via terrain.** Hazard damage can down a unit outside of an attack; ensure it routes through `_handle_downing` and victory detection just like ability/attack damage.
- **Occupant-modifier leakage.** Failing to clear `source = "terrain"` modifiers on leave would let bonuses/penalties accumulate. Always clear-then-reapply on move and deployment.
- **Format cutover.** The loader must accept both forms during and after migration; do not remove verbose-form support until all maps are migrated and tested.
- **Flag misconfiguration.** A release build must default the flag off; add a test/assert that exported builds without `--dev` resolve `Dev.enabled == false`.
- **Scope creep.** No editor UI, no new stats, no content library here — A0 is schema, hooks, format, and the flag.

---

## 8. Phase A0 Deliverables Checklist

- [ ] `TerrainProps` extended with `damage_on_enter`, `damage_per_turn`, `status_on_enter`, `occupant_modifiers`, `is_water`, `tags`; `TerrainRegistry` loads them with defaults (§3).
- [ ] `data/terrain.json` updated; representative hazard/water terrain added (§3.2).
- [ ] `HexGraph` accessors for the new fields, off the injected provider (§4.1).
- [ ] `damage_on_enter` + `status_on_enter` applied in `TurnActions.execute_move`, routed through downing/log (§4.2).
- [ ] `damage_per_turn` applied at activation start via the turn-flow hook (§4.2).
- [ ] `occupant_modifiers` applied/cleared via the `StatModifier` stack on move and deployment (§4.3).
- [ ] Existing cover/move-cost/LoS behavior unchanged (regression tests green) (§4.4).
- [ ] Condensed map format: compact tile records + minified writer; `DataFactory.make_map` accepts both forms (§5.1–5.2).
- [ ] Existing maps migrated to condensed; geometry-equality verified; round-trip test green (§5.2–5.3).
- [ ] `Dev` autoload (build/arg/config resolution) and Dev Tools menu; `DebugReadout` gated by the flag (§6).
- [ ] GUT tests for terrain effects and serialization round-trip; manual checklist for the dev menu toggle.
- [ ] Git tag `alpha-phaseA0-complete`.
