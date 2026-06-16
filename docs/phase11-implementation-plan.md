# Phase 11 — Implementation Plan

**Source spec:** `phase11-spec.md`
**Builds on:** `phase10` (ActionMarker, DiceMarker, HP rebalance), `phase8` (BattleController, BattleHUD, PawnManager), `phase9` (SymbolAtlas, StatusMarker)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages with dependency order. Cross-group dependencies noted.
**Date:** 2026-06-16

---

## How to use this plan

Seven **work groups** (A–G). Group A (WP data layer) is the foundation. Group B (combat enforcement) depends on A. Group C (HUD integration) depends on A and B. Group D (controller polish) depends on C. Group E (visual polish) is independent. Group F (draft/overlay fixes) is independent. Group G (tests) depends on all.

Phase 11 is a broad polish phase touching many files across the codebase. The changes are individually small but collectively bring the MVP to a coherent first-playable state.

> **Carry-over:** consumes `StatKey` enum, `AbilityData`, `BattleUnit`, `DataFactory`, `Validator` from Phase 1; `TurnActions`, `RoundManager`, `MatchState` from Phases 4–5; `CombatResolver.has_modifier_from_source()` from Phase 5; `BattleController`, `BattleHUD`, `PawnManager`, `UnitPawn` from Phase 8; `SymbolAtlas.get_icon()` from Phase 9; `DiceMarker`, `ActionMarker` from Phase 10.

---

## Group A — WP Data Layer (Foundation)

*No dependencies on other new code. Extends existing data pipeline.*

### A1. Add WP to StatKey enum

**Modified file:** `src/core/data/stat_key.gd`

Add `WP` to the `Key` enum, `KEYS` array, and `_STRINGS` mapping with string value `"wp"`.

### A2. Add `wp_cost` to AbilityData

**Modified file:** `src/core/data/ability_data.gd`

New `@export var wp_cost: int = 0` field.

### A3. Parse `wp_cost` in DataFactory

**Modified file:** `src/core/data/data_factory.gd`

Add `a.wp_cost = int(d.get("wp_cost", 0))` in `make_ability()`.

### A4. Validate `wp_cost` in Validator

**Modified file:** `src/core/data/validator.gd`

Add negative `wp_cost` check in `validate_ability()`.

### A5. Add `current_wp` to BattleUnit

**Modified file:** `src/core/data/battle_unit.gd`

New `var current_wp: int = 0` field. Initialize from `stats.effective("wp")` in `from_character()`.

### A6. Update all content JSON files

**Modified files:** All 14 `data/abilities/*.json`, all 8 `data/characters/*.json`, 4 `data/classes/*.json`, 3 `data/races/*.json`.

- Abilities: add `"wp_cost"` field (0 for martial skills, 1–4 for spells).
- Characters: add `"wp"` to `base_stats` dictionaries.
- Classes: add `"wp"` modifier to caster classes (black_mage, red_mage, white_mage, bard).
- Races: add `"wp"` modifier (elf positive, dwarf negative, halfling positive).

---

## Group B — Combat Enforcement

*Depends on: Group A (WP fields must exist).*

### B1. WP checks in TurnActions.execute_ability()

**Modified file:** `src/core/combat/turn_actions.gd`

After the AP check, add:
```gdscript
if ability.wp_cost > 0 and unit.current_wp < ability.wp_cost:
    return { "error": "Not enough WP (need %d, have %d)" % [ability.wp_cost, unit.current_wp] }
```

After deducting AP, add: `unit.current_wp -= ability.wp_cost`.

### B2. WP checks in TurnActions.execute_use_item()

**Modified file:** `src/core/combat/turn_actions.gd`

Resolve the item's granted ability, check WP before deducting AP, then deduct WP after AP.

### B3. Minimum range for ranged attacks

**Modified file:** `src/core/combat/turn_actions.gd`

In `execute_attack()`: compute distance, check `rng > 1 and dist < 2` → error "Target too close for ranged attack".

In `execute_ability()`: compute distance, check `ability.ability_range > 1 and ability_dist < 2` → error "Target too close for ranged ability".

### B4. Defend modifier timing change

**Modified file:** `src/core/combat/round_manager.gd`

- **Remove** the defend modifier removal loop from `start_round()`.
- **Add** `unit.stats.remove_modifiers_by_source("defend")` at the start of `activate_unit()`.

### B5. Victory detection

**Modified file:** `src/core/combat/match_state.gd`

New `check_winner() -> String` method: iterates teams, returns the winning team when the opponent has no living and no downed units.

### B6. Downed unit activation and removal

**Modified file:** `src/core/combat/round_manager.gd`

- Change `_build_queue()` to use `activatable_units()` (living + downed, not activated) instead of `unactivated_units()`.
- Change `activate_unit()` to allow downed units (reject only permanently removed units with `current_hp <= 0 and not is_downed`).
- Change `end_activation()` to return `BattleUnit`: if current unit is downed, remove it from occupancy and clear `is_downed` flag.
- Remove the old grace-period permanent removal code from `start_round()`.

### B7. Activatable units query

**Modified file:** `src/core/combat/match_state.gd`

New `activatable_units(team) -> Array` method: returns units with `(current_hp > 0 or is_downed) and not is_activated`.

---

## Group C — HUD Integration

*Depends on: Groups A and B (WP fields and enforcement must exist).*

### C1. WP display in bottom bar

**Modified file:** `src/ui/battle_hud.gd`

Add purple WP counter (`_wp_label`) below AP pips in `_build_bottom_bar()`. Update in `show_unit_info()`.

### C2. WP in ability popup

**Modified file:** `src/ui/battle_hud.gd`

Modify `_populate_ability_panel()` to accept `current_wp` parameter. Show WP cost on buttons. Disable when WP insufficient; red text when WP is the limiting factor.

### C3. WP in item popup

**Modified file:** `src/ui/battle_hud.gd`

Modify `_populate_item_panel()` to accept `current_wp` and `item_wp_costs` parameters. Show WP cost from granted abilities. Same red-disabled treatment.

### C4. WP bar in sidebar

**Modified file:** `src/ui/battle_hud.gd`

In `_update_team_list()`, add a purple WP progress bar row (hidden when max WP is 0) after the AP row.

### C5. Status effects in sidebar

**Modified file:** `src/ui/battle_hud.gd`

In `_update_team_list()`, after the WP row, add:
- Status effect icon + label row (`SymbolAtlas.get_icon()`, amber text, `id(duration)` format).
- Defend indicator row (blue text, "Defending (+2 DEF, defense die)").

### C6. Activation confirmation panel

**Modified file:** `src/ui/battle_hud.gd`

New `_activation_panel` with confirm/cancel buttons. New signals: `confirm_activation_pressed`, `cancel_activation_pressed`. New method: `set_confirm_activation_enabled(enabled, unit_name)`.

### C7. Round banner

**Modified file:** `src/ui/battle_hud.gd`

New centered `_round_banner` label. `show_round_banner(round_number)` method with tween: hold 1.5s, fade 0.5s, hide.

### C8. Match-over overlay

**Modified file:** `src/ui/battle_hud.gd`

New `_match_over_overlay` panel with `_winner_label` and `_btn_back_to_menu`. New signal: `back_to_menu_pressed`. `show_match_over(winning_team_display)` method.

---

## Group D — BattleController Polish

*Depends on: Group C (HUD signals and panels must exist).*

### D1. Activation confirmation flow

**Modified file:** `src/map/battle_controller.gd`

- New `_pending_activation_unit` field.
- `_set_pending_activation(unit)`: preview the unit, show confirm panel.
- `_clear_pending_activation()`: reset to selectable display.
- `_on_confirm_activation()` / `_on_cancel_activation()`: commit or cancel.
- `_try_select_unit()` and `_on_roster_unit_clicked()` call `_set_pending_activation()` instead of `_activate_chosen_unit()`.
- `_activate_next()` (N key) prefers living non-sleeping units, falls back to downed.

### D2. Match-over integration

**Modified file:** `src/map/battle_controller.gd`

- `_check_match_over() -> bool`: calls `_state.check_winner()`, enters match-over state if winner found.
- `_enter_match_over(winner)`: sets `MATCH_OVER` state, shows overlay, logs result.
- Called from `_enter_awaiting_activation()` and `_do_wait()`.
- `_on_back_to_menu()`: scene change to `draft_scene.tscn`.
- Input handlers early-return when `_control_state == MATCH_OVER`.

### D3. Auto-round-advance

**Modified file:** `src/map/battle_controller.gd`

- `_enter_round_end()` calls `_start_new_round()` directly.
- Remove `ROUND_END` enum value (replaced by `MATCH_OVER`).
- Remove `p4_round` input handling.
- `_start_new_round()` calls `_hud.show_round_banner()`.

### D4. Downed unit handling in controller

**Modified file:** `src/map/battle_controller.gd`

- `_enter_awaiting_activation()` uses `activatable_units()`.
- `_enter_action_select()` handles downed units (no drag, no overlay, only End Turn).
- `_do_wait()` handles `end_activation()` return value for removed units.
- `_check_end_activation_or_continue()` handles removal.

### D5. Delayed down animation

**Modified file:** `src/map/battle_controller.gd`

New `_delay_down_pawn(unit)` method: uses `get_tree().create_timer(DiceMarker.TOTAL_DURATION)` to defer `down_pawn()`. Replace direct `_pawn_manager.down_pawn()` calls in `_do_attack()`, `_do_ability()`, `_do_use_item()`.

### D6. WP cost forwarding

**Modified file:** `src/map/battle_controller.gd`

In `_enter_action_select()`, compute `item_wp_costs` dictionary by resolving granted abilities for usable items. Pass to `_hud.show_action_panel()`.

---

## Group E — Visual Polish (Independent)

*No dependencies on Groups A–D.*

### E1. Status billboard size increase

**Modified file:** `src/map/status_marker.gd`

Change quad size from `Vector2(0.15, 0.15)` to `Vector2(0.225, 0.225)`.

### E2. Status marker spacing

**Modified file:** `src/map/pawn_manager.gd`

Change horizontal marker spacing from `0.18` to `0.27`.

### E3. DiceMarker TOTAL_DURATION constant

**Modified file:** `src/map/dice_marker.gd`

Add `const TOTAL_DURATION := ROLL_DURATION + HOLD_DURATION + FADE_DURATION` for use by delayed down animation.

### E4. Mouse pan support

**Modified file:** `src/map/camera_rig.gd`

- New `mouse_pan_speed` export (default 0.02).
- New `_mmb_dragging` and `_mmb_last_pos` state fields.
- Extract `_apply_pan(world_dir)` from `pan()`.
- Handle `MOUSE_BUTTON_MIDDLE` press/release and `InputEventMouseMotion` for drag panning.

---

## Group F — Draft & Overlay Fixes (Independent)

*No dependencies on Groups A–E.*

### F1. Remove "Your Party" from draft screen

**Modified file:** `src/ui/draft_scene.gd`

- Remove `_selected_list` variable.
- Remove "Your Party" label and `_selected_list` container from `_build_ui()`.
- Remove `_update_selected_list()` method.
- Remove calls to `_update_selected_list()` from `_show_draft()` and `_on_character_clicked()`.

### F2. Minimum range in overlay controller

**Modified file:** `src/map/overlay_controller.gd`

Add `min_range: int = 1` parameter to `show_targets()`. Skip hexes where `Hex.distance(origin, c) < min_range`.

### F3. Minimum range in battle controller overlays

**Modified file:** `src/map/battle_controller.gd`

In `_enter_targeting()` ACTION_ATTACK branch: compute `min_rng = 2 if rng > 1 else 1`, pass to `show_targets()`.
In `_show_ability_overlay()`: compute `min_rng = 2 if ability.ability_range > 1 else 1`, pass to `show_targets()`.

---

## Group G — Tests

*Depends on: All implementation groups.*

### G1. Update round manager tests

**Modified file:** `tests/core/combat/test_round_manager.gd`

- Replace `test_start_round_removes_defend_modifiers` with:
  - `test_defend_persists_through_round_start`: verify defend survives `start_round()`.
  - `test_defend_removed_on_activation`: verify defend cleared in `activate_unit()`.

### G2. Update resolution integration tests

**Modified file:** `tests/core/combat/test_resolution_integration.gd`

- Replace `test_defend_still_removed_at_round_start` with `test_defend_persists_until_next_activation`: verify defend survives round boundary and clears on activation.

### G3. Update turn actions tests

**Modified file:** `tests/core/combat/test_turn_actions.gd`

- Add WP tests: `test_ability_deducts_wp`, `test_ability_insufficient_wp_fails`, `test_attack_does_not_cost_wp`, `test_use_item_deducts_wp`.
- Existing ranged attack tests remain valid (no existing test had ranged attacking adjacent).

### G4. Update downed/revive tests

**Modified file:** `tests/core/combat/test_downed_revive.gd`

Update tests to account for downed units being activated and removed via `end_activation()` instead of grace-period removal at round start.

### G5. Update battle controller tests

**Modified file:** `tests/map/test_battle_controller.gd`

Update tests for activation confirmation flow, match-over detection, auto-round-advance, and downed unit handling.

### G6. Update roster tests

**Modified file:** `tests/core/data/test_roster.gd`

Add validation for WP stat presence in character data.

---

## File manifest

### Modified files

| File | Group | Changes |
|------|-------|---------|
| `src/core/data/stat_key.gd` | A | Add `WP` to enum (+3 lines) |
| `src/core/data/ability_data.gd` | A | Add `wp_cost` field (+1 line) |
| `src/core/data/data_factory.gd` | A | Parse `wp_cost` (+1 line) |
| `src/core/data/validator.gd` | A | Validate `wp_cost` (+2 lines) |
| `src/core/data/battle_unit.gd` | A | Add `current_wp` field and init (+2 lines) |
| `data/abilities/*.json` (×14) | A | Add `"wp_cost"` field |
| `data/characters/*.json` (×8) | A | Add `"wp"` to base_stats |
| `data/classes/*.json` (×4) | A | Add `"wp"` modifier |
| `data/races/*.json` (×3) | A | Add `"wp"` modifier |
| `src/core/combat/turn_actions.gd` | B | WP checks, min range (+22 lines) |
| `src/core/combat/round_manager.gd` | B | Defend timing, downed activation, queue changes (+55/-55 lines) |
| `src/core/combat/match_state.gd` | B | `check_winner()`, `activatable_units()` (+21 lines) |
| `src/ui/battle_hud.gd` | C | WP displays, sidebar status, activation panel, round banner, match-over (+308 lines) |
| `src/map/battle_controller.gd` | D | Activation confirm, match-over, auto-advance, delayed down (+213/-60 lines) |
| `src/map/status_marker.gd` | E | Larger quad size (+1/-1 lines) |
| `src/map/pawn_manager.gd` | E | Wider marker spacing (+1/-1 lines) |
| `src/map/dice_marker.gd` | E | `TOTAL_DURATION` constant (+1 line) |
| `src/map/camera_rig.gd` | E | Mouse pan support (+22 lines) |
| `src/ui/draft_scene.gd` | F | Remove "Your Party" section (-35 lines) |
| `src/map/overlay_controller.gd` | F | `min_range` parameter (+5/-2 lines) |
| `tests/core/combat/test_round_manager.gd` | G | Defend timing tests (+20/-6 lines) |
| `tests/core/combat/test_resolution_integration.gd` | G | Defend persist test (+24/-18 lines) |
| `tests/core/combat/test_turn_actions.gd` | G | WP tests (+59 lines) |
| `tests/core/combat/test_downed_revive.gd` | G | Downed activation tests (+55/-40 lines) |
| `tests/map/test_battle_controller.gd` | G | Controller polish tests (+228/-30 lines) |
| `tests/core/data/test_roster.gd` | G | WP validation tests (+20 lines) |

**Total: 51 files changed, 938 insertions, 213 deletions.**

---

## Suggested implementation order

```
A (WP data layer) ─→ B (Combat enforcement) ─→ C (HUD integration) ─→ D (Controller polish)
                                                                              │
E (Visual polish) ─────────────────────────────────────────────────────────────┤
                                                                              │
F (Draft & overlay fixes) ─────────────────────────────────────────────────────┤
                                                                              │
                                                                     G (Tests) ←─┘
```

A → B → C → D is the critical path (WP requires data, then enforcement, then HUD, then controller wiring). E and F are independent tracks that can proceed in parallel at any time. G depends on all implementation being complete.

---

## Definition of Done

- [x] WP stat flows through the full pipeline: StatKey → JSON → DataFactory → BattleUnit → TurnActions → BattleHUD
- [x] Abilities with `wp_cost > 0` are gated by WP; zero-cost abilities are unaffected
- [x] WP is displayed in bottom bar, ability/item popups, and sidebar
- [x] `MatchState.check_winner()` correctly detects elimination
- [x] Match-over overlay displays winner and provides back-to-menu navigation
- [x] Activation confirmation prevents accidental unit activation
- [x] Defend modifier persists until the unit's next activation, not just until round start
- [x] Ranged attacks/abilities cannot target adjacent hexes
- [x] Status effects and defend state visible in sidebar
- [x] Status billboards are 50% larger
- [x] Draft screen confirm button always visible
- [x] Round banner displays at each round start
- [x] Downed units are removed at their activation turn
- [x] Down animation deferred until dice complete
- [x] Rounds auto-advance
- [x] Middle-mouse-button camera panning works
- [x] All GUT tests pass
