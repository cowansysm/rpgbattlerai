# Phase A14 — Implementation Plan

**Source spec:** `alpha-phaseA14-spec.md`
**Builds on (MVP):** `phase2` (3D map), `phase8` (`BattleController`, `PawnManager`, `ActionMarker`), `phase9` (`SymbolAtlas`), `phase10` (`DiceMarker`)
**Coordinates with (Alpha):** A7 (`AIController` pacing)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-06-24

---

## How to use this plan

Five **work groups** (A–E):

- **A — Symbol resolution** maps any ability to an atlas icon with a fallback chain (pure; unblocks the visual).
- **B — Symbol pawn physics body** is the `RigidBody3D` token with its drop → land → dwell → sink lifecycle.
- **C — Placement & landing** positions pawns beside targets (elevation-aware) and provides a landing surface.
- **D — Integration** rewires `PawnManager`/controllers to spawn the pawn (replacing `ActionMarker`) and await the brief landing beat.
- **E — Tunables, retirement & tests** finishes off.

Each task lists a **done state**. A is core (`SymbolAtlas` extension); B/C are scene-layer physics; D wires combat. Decision recap: **RigidBody3D true physics**, **brief blocking beat** (capped), **replace the ActionMarker** for ability/attack feedback, one pawn **beside each target**. All of it is **cosmetic** — game logic/seed unaffected; headless skips it.

> **Carry-over:** reuses `SymbolAtlas.make_3d_material`, the `DiceMarker` tween/lifecycle pattern, `PawnManager.show_action_marker` call sites in `BattleController`/`AIController`, and per-tile elevation from the map graph. No combat-logic or data-schema change.

---

## Group A — Symbol Resolution

*Pure-ish. Unblocks B/D.*

### A1. `symbol_for_ability` fallback chain
- Extend `SymbolAtlas`: `symbol_for_ability(ability) -> String` returns ability-id → element → effect-type → default icon id (first hit in `ICON_MAP`/generics).
- **Done:** every ability returns a renderable icon id; mapped abilities return their exact icon.

```gdscript
# src/core/data/symbol_atlas.gd (addition)
static func symbol_for_ability(ab) -> String:
    if ICON_MAP.has(ab.id): return ab.id
    var el := str(ab.effect.get("element", ""))
    if el != "" and ICON_MAP.has("elem_" + el): return "elem_" + el
    var et := str(ab.effect.get("effect_type", ""))
    if ICON_MAP.has("fx_" + et): return "fx_" + et
    return "fx_ability"     # default
```

### A2. Generic fallback icons
- Add generic atlas cells (`elem_fire`/`elem_ice`/…, `fx_damage`/`fx_heal`/`fx_buff`/`fx_status`/`fx_revive`, `fx_ability`) in `icon_atlas_generator`; register them in `ICON_MAP`.
- **Done:** the fallback ids resolve to real atlas regions/materials.

---

## Group B — Symbol Pawn Physics Body

*Scene layer. Depends on A (material).*

### B1. `AbilitySymbolPawn` body + drop
- `RigidBody3D` token (small mesh + symbol material/billboard face); `spawn(symbol_id, world_pos, surface_y)` places it at `world_pos.y = surface_y + SPAWN_HEIGHT`, enables physics, applies `SYMBOL_PAWN_PHYSICS` + a little spin.
- **Done:** the pawn falls and collides; settles on the surface.

```gdscript
# src/map/ability_symbol_pawn.gd
class_name AbilitySymbolPawn
extends RigidBody3D
signal landed

func spawn(symbol_id: String, world_pos: Vector3, surface_y: float) -> void:
    # build mesh + SymbolAtlas.make_3d_material(symbol_id); set physics params
    global_position = Vector3(world_pos.x, surface_y + Constants.SYMBOL_PAWN_SPAWN_HEIGHT, world_pos.z)
    sleeping = false
    _watch_for_landing()        # emit `landed` on sleep / low-velocity, or max-fall timeout
```

### B2. Land → dwell → sink → free
- On `landed`: wait `SYMBOL_PAWN_DWELL`; then **freeze** physics and tween position down (through the floor) over `SYMBOL_PAWN_SINK_DURATION` (optional alpha fade); `queue_free`.
- **Done:** the pawn rests, sinks out of sight, and is freed (no leaks).

### B3. Landing detection
- Emit `landed` when the body sleeps or |velocity| < ε for a few frames, **or** after a max-fall timeout (safety).
- **Done:** `landed` fires reliably even on odd bounces.

---

## Group C — Placement & Landing Surface

*Depends on B.*

### C1. Beside-target placement (elevation-aware)
- Compute a spawn position offset `SYMBOL_PAWN_OFFSET` from the target tile center (toward the caster or a free direction); `surface_y` = target tile top (from tile elevation / map graph).
- **Done:** pawns land beside the target on the correct tile height, not on top of the unit.

### C2. Landing collider
- Provide a collision surface at `surface_y` (per-drop thin `StaticBody3D`, or a shared ground plane); put symbol pawns on a dedicated physics layer that ignores game pawns/combat bodies.
- **Done:** pawns collide only with the ground, never with unit pawns or each other's gameplay.

---

## Group D — Integration & ActionMarker Replacement

*Depends on A–C. Coordinates with A7.*

### D1. PawnManager spawner
- Replace `PawnManager.show_action_marker(target, ability_id)` internals to spawn an `AbilitySymbolPawn` via `SymbolAtlas.symbol_for_ability`; add `show_ability_pawns(targets, ability)` → returns an `await`-able that resolves when all land (capped).
- **Done:** calling the spawner drops a symbol pawn beside each target.

### D2. Controller wiring + blocking beat
- `BattleController` and `AIController` ability/attack steps: gather affected targets, spawn the pawn(s), `await` the landing beat (or `SYMBOL_PAWN_MAX_LAND_WAIT`) before continuing; the dwell/sink runs non-blocking afterward.
- **Done:** the turn pauses briefly on landing, then proceeds; multi-target abilities drop one pawn per target.

### D3. Log linkage (optional)
- Spawn coincides with the existing `append_log` result; optionally emphasize the matching log line briefly.
- **Done:** the visual and the log entry land together.

---

## Group E — Tunables, Retirement & Tests

### E1. Constants + retire ActionMarker
- Add the `SYMBOL_PAWN_*` tunables to `constants.json`; remove/repurpose `ActionMarker` for ability/attack use (keep `DiceMarker`, status markers, log icons).
- **Done:** tunables drive the feel; no ability/attack path references `ActionMarker`.

### E2. Tests (GUT, headless-safe)
- `symbol_for_ability` fallback chain (exact/element/effect/default) for sampled abilities; headless contexts perform no physics spawns and combat outcomes are unchanged with/without the visual.
- **Done:** green.

### E3. Manual checklist
- [ ] Using an ability drops a symbol pawn beside each target with the right (or fallback) icon.
- [ ] The pawn falls with gravity, lands on the tile (correct elevation), can bounce/tumble, settles.
- [ ] The turn pauses briefly until landing (never hangs — capped), then continues.
- [ ] After a few seconds the pawn sinks out of sight and is freed; no leaks over many casts.
- [ ] AoE: one pawn per target. Dice/status markers still work; the billboard ActionMarker is gone.
- **Done:** checklist passes.

---

## Dependency Map

```
A (symbol resolution) ──┬──> B (pawn physics body) ──> C (placement & landing) ──> D (integration) ──> E (tunables/tests)
                        └────────────────────────────────────────────────────────┘
A7 pacing ── informs ─> D2 (blocking beat)
```

**Suggested first pass:** A1–A2 → B1–B3 → C1–C2 → D1–D2 → E1 → E2–E3 → D3. Get a single pawn dropping/landing/sinking beside one target before wiring multi-target and retiring the old marker.

---

## Phase A14 Definition of Done

- [ ] `SymbolAtlas.symbol_for_ability` resolves every ability via the fallback chain; generic fallback icons exist (A).
- [ ] `AbilitySymbolPawn` (`RigidBody3D`): physics drop, reliable `landed`, dwell, sink, free — no leaks (B).
- [ ] Beside-target, elevation-aware placement; symbol pawns collide only with the ground (C).
- [ ] `PawnManager`/controllers spawn the pawn (one per target) and await a **capped** landing beat; ActionMarker retired for ability/attack feedback (D).
- [ ] `SYMBOL_PAWN_*` tunables in `constants.json`; fallback + headless-safety tests green; manual checklist passed (E).
- [ ] Game logic/seed unaffected; dice/status markers intact.
- [ ] Git tag `alpha-phaseA14-complete`.
