# Phase 10 — Action Drop-In Markers Specification

**Parent plan:** `rpg-implementation-plan.md` (Phase 10)
**Builds on:** `phase8-spec.md` (BattleController, PawnManager, BattleHUD, UnitPawn), `phase9-spec.md` (SymbolAtlas, StatusMarker, icon system)
**Source spec:** `rpg-specs.md` (§7.7)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-14

---

## 1. Purpose & Scope

Phase 9 added a comprehensive icon system covering all game entities. Icons appear in the HUD (buttons, popups, combat log) and as persistent status markers above pawns. However, when a character uses an ability, spell, item, or attack, the only visual feedback is a combat log text entry — there is no in-world 3D animation communicating what was used or who was targeted.

Phase 10 adds **action drop-in markers**: animated 3D billboard icons that appear above each affected target whenever a combat action resolves. The marker drops in from above, holds briefly so the player can read it, then fades out and self-destructs. This provides immediate spatial feedback — the player sees *what* was used and *where* it landed — complementing the textual combat log.

### In scope

- **ActionMarker**: a new fire-and-forget 3D billboard node that animates a drop → hold → fade → self-destruct lifecycle.
- **Ability markers**: when an ability resolves, each affected target gets a marker showing the ability's icon (e.g., `fire_1`, `cure_1`, `backstab`).
- **Attack markers**: when a basic attack resolves, the target gets a marker showing the `action_attack` icon.
- **Item markers**: when an item is used, each affected target gets a marker showing the item's icon (e.g., `potion`, `smoke_bomb_pouch`).
- **Multi-target support**: burst abilities that affect multiple units spawn one marker per affected target simultaneously.
- **PawnManager integration**: a new `show_action_marker(unit, icon_id)` method handles positioning and lifecycle.
- **BattleController integration**: marker spawning calls added after action resolution in `_do_attack()`, `_do_ability()`, and `_do_use_item()`.

### Out of scope

- Animated particle effects, hit numbers, or damage floaters (future phase).
- Markers for defend or wait actions (no spatial target — these are self-actions communicated via log only).
- Markers for movement (movement already has its own tween animation).
- Audio feedback tied to markers.
- AI-controlled units or victory/rout detection.

### Exit criteria

1. When a unit attacks a target, an `action_attack` icon drops in above the target pawn, holds briefly, fades out, and self-destructs.
2. When a unit uses an ability, the ability's icon (e.g., `fire_1`) drops in above each affected target.
3. When a unit uses an item, the item's icon drops in above each affected target.
4. For burst abilities affecting multiple targets, each target gets its own independent marker simultaneously.
5. Markers use billboard rendering (always face the camera) and are readable at all camera angles.
6. Markers do not block game flow — the controller proceeds immediately after spawning markers (fire-and-forget).
7. Markers self-clean via `queue_free()` after the animation completes (~0.9s lifetime).
8. Markers are visually distinct from persistent status markers (larger size, animated lifecycle, temporary).
9. GUT tests verify ActionMarker construction properties (mesh type, material settings, sizing).
10. Manual visual verification confirms markers appear correctly during combat.

---

## 2. Design Decisions

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Fire-and-forget** | Markers are non-blocking. The controller spawns them and proceeds immediately. | Game state has already resolved before markers appear. Blocking would add dead time where the player just watches a cosmetic icon float. Keeps BattleController changes minimal — no new state transitions or signal wiring. |
| **Separate class** | New `ActionMarker` class rather than extending `StatusMarker`. | StatusMarker is persistent (managed by PawnManager lifecycle). ActionMarker is transient (self-destructing). Different transparency modes (alpha blend vs. alpha scissor). Different sizing. Conflating them would add complexity for no reuse. |
| **World-space parenting** | Markers are children of PawnManager, not UnitPawn. | UnitPawn rotation changes when downed (180° X flip). A child marker would flip with it. World-space parenting keeps the drop animation independent of pawn rotation. |
| **Size: 0.3 × 0.3** | Double the status marker size (0.15 × 0.15). | Large enough to be a clear momentary callout. Small enough not to obscure the pawn beneath. Visually distinct from persistent status markers. |
| **Alpha blend** | Uses `TRANSPARENCY_ALPHA` instead of `TRANSPARENCY_ALPHA_SCISSOR`. | Alpha scissor gives hard-edge cutoff — fine for persistent markers. ActionMarker needs smooth fade-out during its animation, which requires alpha blending. |
| **Icon selection** | Uses the existing SymbolAtlas icon ID directly (ability ID, item ID, or `"action_attack"`). | All IDs are already in `SymbolAtlas.ICON_MAP`. Unknown IDs gracefully fall back to `"_fallback"`. No new icon mapping needed. |
| **No defend/wait markers** | Defend and wait actions do not spawn markers. | These are self-targeted actions with no spatial target to mark. The combat log already communicates them. |

---

## 3. ActionMarker

### 3.1 Class definition

```
class_name ActionMarker
extends MeshInstance3D
## Animated 3D billboard icon that drops in above a target, holds briefly,
## then fades out and removes itself. Fire-and-forget visual feedback for
## combat actions (abilities, attacks, items).
## Spec reference: phase10-spec.md §3
```

### 3.2 Mesh and material

- **Mesh**: `QuadMesh` with size `Vector2(0.3, 0.3)`.
- **Material**: `StandardMaterial3D` from `SymbolAtlas.make_3d_material(icon_id)` with overrides:
  - `billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED` — always faces camera.
  - `transparency = BaseMaterial3D.TRANSPARENCY_ALPHA` — enables smooth fade-out (overrides the default `ALPHA_SCISSOR` from `make_3d_material`).
  - `shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED` — consistent visibility (inherited from `make_3d_material`).

### 3.3 Animation lifecycle

The marker runs a self-contained tween sequence when `play()` is called:

| Phase | Duration | Effect |
|-------|----------|--------|
| **Drop** | 0.2s | Position Y tweens from `+0.5` above resting point down to resting point. `EASE_OUT` / `TRANS_CUBIC`. |
| **Hold** | 0.4s | Marker sits at resting position. Player reads the icon. |
| **Fade** | 0.3s | Material `albedo_color.a` tweens from 1.0 to 0.0. `EASE_IN` / `TRANS_CUBIC`. |
| **Cleanup** | — | `queue_free()` called via tween callback. |

**Total lifetime: ~0.9 seconds.**

Animation constants:

| Constant | Value | Rationale |
|----------|-------|-----------|
| `QUAD_SIZE` | `Vector2(0.3, 0.3)` | 2× status marker size for visibility |
| `DROP_HEIGHT` | `0.5` | 2× elevation unit (0.25). Noticeable arc without being excessive. |
| `DROP_DURATION` | `0.2` | Fast and snappy. Slightly faster than movement tween (0.3) since it's purely cosmetic. |
| `HOLD_DURATION` | `0.4` | Long enough to register the icon. Not so long that it drags. |
| `FADE_DURATION` | `0.3` | Gentle fade matching existing tween durations in the project. |

### 3.4 API

```gdscript
static func create(icon_id: String) -> ActionMarker
    ## Factory method. Creates a marker with the given icon.
    ## Caller must add to scene tree and call play().

func play() -> void
    ## Starts the drop-hold-fade-cleanup animation.
    ## Must be called after adding to the scene tree.
```

---

## 4. PawnManager Integration

### 4.1 New method

```gdscript
func show_action_marker(unit: BattleUnit, icon_id: String) -> void
    ## Spawns a drop-in icon above the unit's pawn. Fire-and-forget.
    ## The marker is added as a child of PawnManager (world space)
    ## and self-destructs after its animation completes.
```

### 4.2 Positioning

The marker's world position is computed from the target pawn's current position:

```
marker.position = pawn.position + Vector3(0.0, 0.35, 0.0)
```

- `pawn.position.y` already accounts for hex elevation + tile height + token height.
- The `+0.35` offset places the marker's resting point above the pawn top and above any existing status markers (which sit at `y = 0.25` relative to the pawn in local space).
- The marker starts 0.5 units higher than this (due to `DROP_HEIGHT`) and drops into the resting position.

### 4.3 Error handling

If `unit` has no associated pawn (e.g., already removed), the method returns silently. No crash, no error.

---

## 5. BattleController Integration

### 5.1 Insertion points

Three existing action functions gain marker-spawning calls. No structural changes to the controller's state machine or signal flow.

#### Attack (`_do_attack`)

After `_log_attack_result(result)`, before downed/status logic:

```gdscript
if target_unit_pre:
    _pawn_manager.show_action_marker(target_unit_pre, "action_attack")
```

Uses the pre-captured `target_unit_pre` reference (already exists in the function for downing logic).

#### Ability (`_do_ability`)

After `_log_ability_result(result, ability_id)`, iterating over the existing `outcomes` array and `units_before` snapshot:

```gdscript
for outcome in outcomes:
    var target_unit: BattleUnit = units_before.get(str(outcome.get("target", "")))
    if target_unit:
        _pawn_manager.show_action_marker(target_unit, ability_id)
```

- `ability_id` (e.g., `"fire_1"`) is already a valid SymbolAtlas key.
- Multi-target burst abilities naturally spawn one marker per outcome entry.
- `units_before` snapshot ensures markers appear even for units that were just downed by the ability.

#### Item (`_do_use_item`)

After the `append_log()` call, iterating over outcomes and `units_before`:

```gdscript
for outcome in outcomes:
    var target_unit: BattleUnit = units_before.get(str(outcome.get("target", "")))
    if target_unit:
        _pawn_manager.show_action_marker(target_unit, item_id)
```

- `item_id` maps through SymbolAtlas, falling back to `"_fallback"` for unknown IDs.

### 5.2 No changes for defend/wait/move

- **Defend**: self-targeted buff, no spatial target to mark.
- **Wait**: forfeits AP, no spatial target.
- **Move**: already has its own tween animation via `PawnManager.move_pawn()`.

---

## 6. Data Flow

### From prior phases

| Source | Data consumed |
|--------|------|
| Phase 8 | `BattleController._do_attack/ability/item()` action flow, `PawnManager.get_pawn()` for positioning, `UnitPawn.position` for world coordinates |
| Phase 9 | `SymbolAtlas.make_3d_material()` for billboard material creation, `SymbolAtlas.ICON_MAP` for icon IDs |
| Phase 4 | `TurnActions` result dictionaries (`outcomes` array, `target` field) |
| Phase 1 | `BattleUnit` identity, `AbilityData.id`, `ItemData.id` |

### Outputs

- `ActionMarker` — self-contained animated 3D marker class.
- Modified `PawnManager` — `show_action_marker()` method.
- Modified `BattleController` — marker spawn calls in three action functions.

---

## 7. Risks & Notes

- **Alpha blend z-sorting.** Billboard alpha-blended quads can have z-sorting artifacts against other transparent objects (status markers, pawn symbol faces). Since markers are momentary (0.9s lifetime) and sit above other elements, this is unlikely to be visually problematic. If needed, `render_priority` can be set on the material.
- **Rapid action stacking.** If two actions resolve in quick succession targeting the same unit, two markers will overlap briefly. Since each is independent and self-destructs, this is harmless — the second marker drops in while the first is fading out.
- **Downed unit markers.** The `units_before` snapshot ensures markers can spawn even for a unit just downed by the action. The marker appears at the pawn's last position (the pawn may be flipping to downed state simultaneously). This is the desired behavior — the player sees the ability icon land and the pawn go down together.
- **`.gd.uid` files.** Godot 4.6.3 auto-generates `.uid` files for new scripts. The new `action_marker.gd` will get a companion `.gd.uid` file that should be committed.

---

## 8. Phase 10 Deliverables Checklist

- [ ] `ActionMarker` class with create/play API and drop-hold-fade-cleanup animation (§3)
- [ ] `PawnManager.show_action_marker()` method for world-space marker spawning (§4)
- [ ] `BattleController._do_attack()` spawns `action_attack` marker on target (§5.1)
- [ ] `BattleController._do_ability()` spawns ability icon marker on each affected target (§5.1)
- [ ] `BattleController._do_use_item()` spawns item icon marker on each affected target (§5.1)
- [ ] Multi-target abilities spawn one marker per affected target simultaneously (§5.1)
- [ ] GUT tests for ActionMarker construction properties (§3)
- [ ] Manual visual verification of markers during combat (§3.3)
- [ ] Git tag `phase-10-complete`
