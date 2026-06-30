# Phase A14 — Ability Symbol Pawns (Physics Drop Feedback) Specification

**Parent plan:** `alpha-implementation-plan.md` (new sub-phase A14)
**Master spec:** `alpha-specs.md` (combat substrate); `rpg-specs.md` (MVP visuals)
**Builds on (MVP):** `phase2` (3D map rendering), `phase8` (`BattleController`, `PawnManager`, `ActionMarker`), `phase9` (`SymbolAtlas`), `phase10` (`DiceMarker` animation precedent)
**Coordinates with (Alpha):** A7 (`AIController` step pacing)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-24
**Status:** Draft v0.1

---

## 1. Purpose & Scope

When an ability (or attack) resolves, spawn a small **3D "symbol pawn"** bearing that ability's icon, **drop it next to each target with real physics (gravity)**, let it **rest on screen for a few seconds**, then **sink out of sight** and despawn. This communicates, at a glance, *what* was used, on *whom*, and draws the eye to the corresponding **event-log** entry.

This **replaces** the existing billboard `ActionMarker` (which tween-drops an icon *above* a target and fades) for ability/attack feedback, upgrading it to a physics-dropped token beside the target(s).

### In scope

- An **`AbilitySymbolPawn`** (`RigidBody3D`) that falls under **true Godot physics**, collides with a landing surface, settles, dwells, then **sinks** (descends through the floor / fades) and frees itself.
- **Placement beside each target** — one symbol pawn per affected target, offset next to the target's tile (elevation-aware), for single- and multi-target (AoE) abilities.
- A **symbol resolver** mapping an ability to an atlas icon, with a **fallback chain** (ability id → element → effect type → generic) so any of the 700+ abilities yields a sensible symbol.
- A **brief blocking beat**: the acting turn/step waits until the pawn(s) **land** (capped by a max-wait) before continuing, focusing attention on the result + log.
- **Replacement** of the `ActionMarker` billboard for ability/attack feedback (dice/status markers unchanged).

### Out of scope

- New art beyond a small set of **generic fallback symbols** in the atlas (asset task, minimal).
- Dice markers, status markers, movement feedback (unchanged).
- Non-combat uses of the symbol pawn (reusable, but only combat feedback is wired here).
- Deterministic physics — the drop is **cosmetic** and does not affect game logic or the seeded outcome (A8); per-drop tumble may vary.

### Exit criteria

1. Resolving an ability spawns a symbol pawn **beside each target**, bearing the ability's icon (or a sensible fallback).
2. The pawn **falls under RigidBody3D physics**, lands on the target tile's surface (elevation-aware), and settles.
3. It **dwells** a few seconds, then **sinks** out of sight and frees (no leaks).
4. The turn/step **pauses briefly until landing** (capped), then continues; multi-target abilities drop all pawns and resume after the last lands (or the cap).
5. The billboard `ActionMarker` is **retired** for ability/attack feedback, replaced by the symbol pawn; dice/status markers still work.
6. Symbol resolution yields an icon for **every** ability via the fallback chain.
7. Headless contexts skip the visual entirely (no physics nodes), and the change does not alter combat outcomes.

---

## 2. Design Decisions (Phase A14)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **True physics** | The pawn is a **`RigidBody3D`** that falls, collides, can bounce/tumble, and settles. | Matches the requested "physics-based gravity simulation"; lively, tactile feedback. Cosmetic only — never affects game logic. |
| **Brief blocking beat** | The acting turn/step **waits until the pawn lands** (capped by `SYMBOL_PAWN_MAX_LAND_WAIT`) before continuing. | Forces a beat of attention on the target + log entry; bounded so combat never stalls. |
| **Replace `ActionMarker`** | The symbol pawn becomes the ability/attack on-target feedback; the billboard marker is retired for that purpose. | One unified, stronger visual; less marker clutter. Dice/status markers untouched. |
| **One pawn per target, beside it** | Each affected target gets its own pawn, offset next to its tile (not on top of the unit). | Reads clearly for AoE; doesn't occlude the target pawn. |
| **Symbol fallback chain** | ability id → element → effect type → generic icon, via `SymbolAtlas`. | The MVP atlas only maps a handful of abilities; the 700+ new ones need graceful fallback. |
| **Cosmetic, headless-safe** | Physics/visuals live in the scene layer only; headless/tests skip them. | Determinism (A8) and test speed preserved; logic is unchanged. |

---

## 3. Lifecycle

```
ability resolves → for each target: spawn AbilitySymbolPawn(symbol, beside(target))
  state SPAWN:  positioned above the target tile at SYMBOL_PAWN_SPAWN_HEIGHT, physics enabled
  state FALL:   RigidBody3D falls under gravity, collides with the landing surface, settles
  → emit `landed` (on sleep / low-velocity, or after a max-fall timeout)
  [controller resumes the turn/step once all pawns for this action have landed, capped]
  state DWELL:  rest for SYMBOL_PAWN_DWELL seconds
  state SINK:   disable physics; tween position down through the floor over SYMBOL_PAWN_SINK_DURATION (optional fade)
  → queue_free
```

## 4. Placement

- **Beside each target:** spawn at a small horizontal offset from the target unit's tile center (toward the caster, or a free adjacent direction) so the pawn doesn't occlude the unit. One pawn per affected target.
- **Elevation-aware landing:** the landing surface height = the target tile's top (tile elevation). The pawn spawns `SYMBOL_PAWN_SPAWN_HEIGHT` above that and falls to rest on it.
- **Multi-target / AoE:** iterate the action's affected targets; spawn one pawn each (slightly staggered start is optional for visual variety).

## 5. Physics

- `AbilitySymbolPawn extends RigidBody3D` — a small token mesh (quad/coin/cube) textured with the symbol material (`SymbolAtlas.make_3d_material`), or a billboard sprite child for the icon face.
- A **landing surface** is required for collisions: either a shared `StaticBody3D` ground plane at the play area's base, or a thin collider placed at the target tile's top elevation per drop. `[ASSUMPTION]` a per-drop landing collider at the tile-top height is simplest and elevation-correct.
- Tunable physics params (`constants.json`): mass, gravity scale, bounce (restitution), linear/angular damping, initial spin. The body **sleeps** when settled → triggers `landed`.
- Pawns collide with the ground/each other but **not** with game pawns or combat state (separate physics layer); purely visual.

## 6. Pacing (Brief Blocking Beat)

- After spawning the action's symbol pawn(s), the controller **awaits** their `landed` signal(s), or `SYMBOL_PAWN_MAX_LAND_WAIT` seconds, whichever comes first, before proceeding to the next step / ending the turn.
- This supersedes/co-exists with the A7 `AI_PACE_DELAY` for the ability step (the landing wait *is* the pace beat). The cap guarantees combat never hangs on stuck physics.
- Dwell + sink happen **after** the beat and are **non-blocking** (the pawn lives out its rest/sink while combat continues).

## 7. Symbol Resolution

A `symbol_for_ability(ability) -> String` resolver (extending `SymbolAtlas`) returns an atlas icon id via a fallback chain:

1. **Exact**: `ability.id` present in `ICON_MAP` (e.g., `fire_1`).
2. **Element**: a per-element generic icon (fire/ice/lightning/holy/dark/…) when the ability has an `element`.
3. **Effect type**: a generic icon for `damage` / `heal` / `buff` / `status` / `revive`.
4. **Default**: a catch-all "ability" icon.

`[ASSUMPTION]` A small set of **generic fallback symbols** (per element + per effect type) is added to the atlas (`SymbolAtlas`/`icon_atlas_generator`). This is a minor asset/content task; until then the effect-type/default tier still renders *something*.

## 8. Integration & Replacement of `ActionMarker`

- `PawnManager.show_action_marker(target, ability_id)` (called today by `BattleController` and `AIController` for attack/ability feedback) is reworked to spawn an **`AbilitySymbolPawn`** beside the target instead of a billboard `ActionMarker`.
- The controllers' ability/attack steps **await** the landing beat (§6) before continuing. Multi-target abilities pass the full affected-target set so one pawn drops per target.
- `ActionMarker` is retired for ability/attack use (the file may be removed or repurposed); `DiceMarker`, status markers, and log-only icons (defend/wait) are unchanged.
- Spawning coincides with the existing `append_log` result entry; `[optional]` briefly emphasize the matching log line to reinforce the link.

## 9. Data Model & Touch Points

- **New scene/code:** `src/map/ability_symbol_pawn.gd` (+ optional scene) — `RigidBody3D` token: `spawn(symbol_id, world_pos, surface_y)`, `landed` signal, dwell + sink + free; a landing-collider helper.
- **Modified core (tiny):** `SymbolAtlas` — add `symbol_for_ability(ability)` resolver + generic fallback icon ids; `icon_atlas_generator` — generate the generic fallback cells.
- **Modified scene:** `PawnManager` — replace `show_action_marker` internals with the symbol-pawn spawner; expose a multi-target spawn + a `await`-able landing beat. `BattleController` / `AIController` — pass affected targets and await the beat on ability/attack steps.
- **Retired:** `ActionMarker` (for ability/attack feedback).
- **Tunables:** `constants.json` (§10). No data-schema change; no validator change.

## 10. Tunables (`constants.json`)

```
SYMBOL_PAWN_SPAWN_HEIGHT   = 4.0    // drop height above the target tile top
SYMBOL_PAWN_DWELL          = 2.5    // seconds resting on screen before sinking
SYMBOL_PAWN_SINK_DURATION  = 1.0    // seconds to sink out of sight
SYMBOL_PAWN_MAX_LAND_WAIT  = 0.8    // cap (s) on the blocking landing beat
SYMBOL_PAWN_OFFSET         = 0.5    // horizontal offset beside the target
SYMBOL_PAWN_PHYSICS = {
  "mass": 1.0, "gravity_scale": 1.4, "bounce": 0.25, "linear_damp": 0.2, "angular_damp": 0.2
}
```

## 11. Relationship to Phases / Prerequisites

- **Required (MVP, complete):** Phase 2 (3D map), Phase 8 (`BattleController`/`PawnManager`/`ActionMarker`), Phase 9 (`SymbolAtlas`).
- **Coordinates with A7:** the landing beat integrates with `AIController` step pacing.
- **Independent of** the content libraries, the pending class-tree engine changes, A8/A11/A12/A13 — this is a presentation-layer feature on the existing combat scene.

## 12. Out of Scope / Future

- Rich VFX (particles, impact bursts), sound — placeholder visuals continue.
- Reusing the symbol pawn for non-combat events.
- Bespoke per-ability symbols beyond the atlas + generic fallbacks.

## 13. Requirements Traceability

| # | Requirement | Where addressed |
|---|-------------|-----------------|
| 1 | Pawn with the ability's matching symbol | §7, §8 |
| 2 | Dropped next to the target(s) | §4 |
| 3 | Rests a few seconds, then sinks out of sight | §3, §10 |
| 4 | Communicates skill/targets/result (event log) | §1, §6, §8 |
| 5 | Animations + physics-based gravity drop | §5, §2 |
| D1 | RigidBody3D true physics | §5, §2 |
| D2 | Brief blocking beat | §6, §2 |
| D3 | Replace the billboard ActionMarker | §8, §2 |
