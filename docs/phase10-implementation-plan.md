# Phase 10 — Implementation Plan

**Source spec:** `phase10-spec.md`
**Builds on:** `phase8` (BattleController action flow, PawnManager pawn tracking, UnitPawn positioning), `phase9` (SymbolAtlas icon lookup, StatusMarker pattern)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages with dependency order. Cross-group dependencies noted.
**Date:** 2026-06-14

---

## How to use this plan

Five **work groups** (A–E). Group A (ActionMarker class) is the foundation. Group B (PawnManager method) depends on A. Group C (BattleController calls) depends on B. Group D (tests) depends on A. Group E (manual verification) depends on all.

Phase 10 is a small, focused feature: **one new class** (ActionMarker), **one new method** (PawnManager.show_action_marker), **three call sites** (BattleController), and **one test file**.

> **Carry-over:** consumes `SymbolAtlas.make_3d_material()` from Phase 9; `PawnManager._pawns` dictionary and `get_pawn()` from Phase 8; `BattleController._do_attack/ability/item()` action flow from Phase 8; `UnitPawn.position` for world coordinates; `TurnActions` result dictionaries (`outcomes` array) from Phase 4.

---

## Group A — ActionMarker Class (Foundation)

*No dependencies on other new code. Reuses SymbolAtlas from Phase 9.*

### A1. `ActionMarker` — animated drop-in billboard marker

Self-contained 3D billboard icon that drops in, holds, fades out, and self-destructs. Follows `StatusMarker` structure (Phase 9) but adds animated lifecycle and uses alpha blend for smooth fade.

```
# src/map/action_marker.gd
class_name ActionMarker
extends MeshInstance3D
## Animated 3D billboard icon that drops in above a target, holds briefly,
## then fades out and removes itself. Fire-and-forget visual feedback for
## combat actions (abilities, attacks, items).
## Spec reference: phase10-spec.md §3

const QUAD_SIZE := Vector2(0.3, 0.3)
const DROP_HEIGHT := 0.5
const DROP_DURATION := 0.2
const HOLD_DURATION := 0.4
const FADE_DURATION := 0.3

static func create(icon_id: String) -> ActionMarker
    # 1. Create ActionMarker instance
    # 2. Create QuadMesh with QUAD_SIZE
    # 3. Get material from SymbolAtlas.make_3d_material(icon_id)
    # 4. Override: billboard_mode = BILLBOARD_ENABLED
    # 5. Override: transparency = TRANSPARENCY_ALPHA (for smooth fade)
    # 6. Set material_override
    # 7. Return marker

func play() -> void
    # 1. Offset position.y upward by DROP_HEIGHT
    # 2. Create tween
    # 3. Phase 1 — Drop: tween position:y back down (EASE_OUT, TRANS_CUBIC)
    # 4. Phase 2 — Hold: tween_interval(HOLD_DURATION)
    # 5. Phase 3 — Fade: tween_method _set_alpha from 1.0 to 0.0 (EASE_IN, TRANS_CUBIC)
    # 6. Phase 4 — Cleanup: tween_callback(queue_free)

func _set_alpha(alpha: float) -> void
    # Set material_override.albedo_color.a = alpha
```

**Reference patterns:**
- `src/map/status_marker.gd` — same structural pattern (static `create()` factory, QuadMesh, billboard material from SymbolAtlas)
- `src/map/unit_pawn.gd` lines 55–62 — `move_to()` tween pattern (EASE_OUT, TRANS_CUBIC, returns Tween)
- `src/map/unit_pawn.gd` lines 65–73 — `set_downed()` tween pattern (EASE_IN_OUT, sequential phases)

**Key divergence from StatusMarker:**
- `TRANSPARENCY_ALPHA` instead of `TRANSPARENCY_ALPHA_SCISSOR` — enables smooth alpha fade-out
- QuadMesh size `0.3` instead of `0.15` — larger for momentary callout visibility
- Self-driving animation lifecycle with `queue_free()` — StatusMarker is persistent

---

## Group B — PawnManager Integration

*Depends on: Group A (ActionMarker class must exist).*

### B1. Add `show_action_marker()` method

Add one new public method to `PawnManager` for spawning action markers in world space.

**Modified file:** `src/map/pawn_manager.gd`

**Insert after `update_status_markers()` (line 103):**

```gdscript
func show_action_marker(unit: BattleUnit, icon_id: String) -> void:
    ## Spawn a drop-in icon above the unit's pawn. Fire-and-forget.
    var pawn: UnitPawn = _pawns.get(unit)
    if not pawn:
        return
    var marker := ActionMarker.create(icon_id)
    marker.position = pawn.position + Vector3(0.0, 0.35, 0.0)
    add_child(marker)
    marker.play()
```

**Design notes:**
- Parented to PawnManager (world space), not UnitPawn (local space). Prevents the drop animation from being affected by pawn rotation (e.g., 180° X flip when downed).
- Y offset `0.35` places the resting point above the pawn top (token half-height 0.0525 + tile half-height 0.05 = ~0.1) and above status markers (at pawn-local y=0.25). The marker starts at `0.35 + 0.5 = 0.85` above the hex and drops to `0.35`.
- Silent no-op if pawn not found (e.g., unit already removed).

---

## Group C — BattleController Integration

*Depends on: Group B (PawnManager.show_action_marker must exist).*

### C1. Attack marker

**Modified file:** `src/map/battle_controller.gd`

**Insert after line 446** (`_log_attack_result(result)`), before the downed check:

```gdscript
    # Show attack icon on target
    if target_unit_pre:
        _pawn_manager.show_action_marker(target_unit_pre, "action_attack")
```

Uses `target_unit_pre` (captured at line 439 before execute, already exists for downing logic).

### C2. Ability marker

**Modified file:** `src/map/battle_controller.gd`

**Insert after line 472** (`_log_ability_result(result, ability_id)`), before the existing outcomes loop at line 475:

```gdscript
    # Show ability icon on each affected target
    for outcome in outcomes:
        var target_unit: BattleUnit = units_before.get(str(outcome.get("target", "")))
        if target_unit:
            _pawn_manager.show_action_marker(target_unit, ability_id)
```

**Note:** The `outcomes` variable is declared at line 475 in the existing code. The marker loop needs to use the same `outcomes` array. Two approaches:
1. Move the `var outcomes` declaration above the marker loop (before line 473).
2. Inline the outcomes extraction in the marker loop.

**Recommended:** Move `var outcomes: Array = result.get("outcomes", [])` to just after line 472, before the marker loop. The existing loop at line 476 then uses the same variable without re-declaring it.

### C3. Item marker

**Modified file:** `src/map/battle_controller.gd`

**Insert after line 509** (`_hud.append_log(...)` for item use), before the existing outcomes loop at line 511:

```gdscript
    # Show item icon on each affected target
    for outcome in outcomes:
        var target_unit: BattleUnit = units_before.get(str(outcome.get("target", "")))
        if target_unit:
            _pawn_manager.show_action_marker(target_unit, item_id)
```

**Same note as C2:** Move `var outcomes` declaration above the marker loop.

---

## Group D — Tests

*Depends on: Group A (ActionMarker class).*

### D1. `test_action_marker.gd` — ActionMarker construction tests

Following the pattern of `tests/map/test_status_marker.gd` (54 lines, 6 test functions).

```
# tests/map/test_action_marker.gd
extends GutTest
## Tests for ActionMarker — animated 3D billboard icon for action feedback.
## Spec reference: phase10-spec.md §3

func before_all() -> void:
    SymbolAtlas._atlas = null
    SymbolAtlas._cache = {}

- test_create_returns_mesh_instance
    # ActionMarker.create("fire_1") is MeshInstance3D

- test_marker_has_quad_mesh
    # marker.mesh is QuadMesh

- test_marker_quad_size
    # (marker.mesh as QuadMesh).size == Vector2(0.3, 0.3)

- test_marker_has_billboard_material
    # material_override.billboard_mode == BILLBOARD_ENABLED

- test_marker_uses_alpha_blend
    # material_override.transparency == TRANSPARENCY_ALPHA (not ALPHA_SCISSOR)

- test_marker_is_unshaded
    # material_override.shading_mode == SHADING_MODE_UNSHADED

- test_fallback_for_unknown_icon
    # ActionMarker.create("nonexistent_xyz") produces valid marker (SymbolAtlas falls back)
```

**Note:** The `play()` method involves tweens and timing — deterministic unit testing is impractical. Animation behavior is verified visually in Group E.

---

## Group E — Manual Verification

*Depends on: Groups A–D (all implementation and tests complete).*

### E1. Attack marker verification

1. Launch game → Draft → Start battle.
2. Activate a unit adjacent to an enemy.
3. Click Attack → click enemy tile.
4. **Verify:** An `action_attack` icon drops in above the target, holds ~0.4s, fades out smoothly.
5. **Verify:** The marker faces the camera (billboard).
6. **Verify:** The game proceeds immediately — no pause during the animation.

### E2. Ability marker verification

1. Activate a unit with a ranged ability (e.g., Elf Black Mage with Fire 1).
2. Click Abilities → select Fire 1 → click target tile.
3. **Verify:** A `fire_1` icon drops in above the target.
4. Test a burst ability (e.g., Inspire with burst radius 1) hitting multiple units.
5. **Verify:** Each affected unit gets its own independent marker simultaneously.

### E3. Item marker verification

1. Activate a unit with a usable item.
2. Click Items → select item → click target tile.
3. **Verify:** The item's icon drops in above the target.

### E4. Edge cases

1. Use an ability that downs a target.
2. **Verify:** The marker appears at the target's position even as the pawn flips to downed state.
3. Use two abilities in quick succession on the same target (if AP allows).
4. **Verify:** Both markers animate independently without errors.

---

## File manifest

### New files

| File | Class | Group | Description |
|------|-------|-------|-------------|
| `src/map/action_marker.gd` | `ActionMarker` | A | Animated drop-in billboard marker |
| `tests/map/test_action_marker.gd` | — | D | ActionMarker GUT tests |

### Modified files

| File | Group | Changes |
|------|-------|---------|
| `src/map/pawn_manager.gd` | B | Add `show_action_marker()` method (+8 lines) |
| `src/map/battle_controller.gd` | C | Add marker spawn calls in `_do_attack()`, `_do_ability()`, `_do_use_item()` (+12 lines) |

### Auto-generated files

| File | Description |
|------|-------------|
| `src/map/action_marker.gd.uid` | Godot UID for new script |
| `tests/map/test_action_marker.gd.uid` | Godot UID for new test script |

---

## Suggested implementation order

```
A (ActionMarker class) ─→ B (PawnManager method) ─→ C (BattleController calls)
       │
       └─→ D (Tests)
                                                            │
                                              E (Manual verification) ←─┘
```

A is the foundation. B and D can proceed in parallel after A. C requires B. E requires all.

---

## Definition of Done

- [ ] `ActionMarker.create(icon_id)` returns a properly configured `MeshInstance3D` with billboard QuadMesh
- [ ] `ActionMarker.play()` runs the full drop-hold-fade-cleanup tween sequence
- [ ] `PawnManager.show_action_marker(unit, icon_id)` spawns a marker above the unit's pawn
- [ ] `BattleController._do_attack()` spawns `action_attack` marker on target
- [ ] `BattleController._do_ability()` spawns ability icon marker on each affected target
- [ ] `BattleController._do_use_item()` spawns item icon marker on each affected target
- [ ] Burst abilities spawn one marker per affected target simultaneously
- [ ] Markers are fire-and-forget — controller proceeds immediately
- [ ] Markers self-destruct after ~0.9s via `queue_free()`
- [ ] All GUT tests pass
- [ ] Manual visual verification confirms correct marker appearance and timing
