# Phase 11 — Polish & Future Hooks Specification

**Parent plan:** `rpg-implementation-plan.md` (Phase 11)
**Builds on:** `phase10-spec.md` (ActionMarker, dice markers, HP rebalance), `phase8-spec.md` (BattleController, BattleHUD, PawnManager), `phase9-spec.md` (SymbolAtlas, StatusMarker)
**Source spec:** `rpg-specs.md` (§10, §7.4, §7.5, §5)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-16

---

## 1. Purpose & Scope

Phase 11 is the final MVP phase. Prior phases built the full combat loop from data through resolution and visual feedback. Phase 11 addresses gameplay polish, UX friction, and mechanical refinements that emerged during playtesting. It also introduces the **Willpower (WP)** resource system, adds **victory/rout detection**, and improves the activation flow with a **confirmation step**.

### In scope

- **Willpower (WP) system**: new resource stat gating ability usage, with per-ability WP costs, per-character WP pools, and full HUD integration.
- **Victory detection**: `MatchState.check_winner()` with match-over overlay and back-to-menu flow.
- **Activation confirmation**: click-to-preview then confirm/cancel before committing a unit's activation.
- **Defend duration fix**: defense die persists until the defender's next activation (cross-round), not just until round start.
- **Minimum range for ranged attacks**: ranged weapons and ranged abilities (range > 1) cannot target adjacent hexes (minimum range 2).
- **Status effects in sidebar**: status effect icons and defend indicator shown in the team roster sidebar cards.
- **Status billboard enlargement**: 50% larger status marker quads for better visibility.
- **Draft screen cleanup**: removed "Your Party" list to prevent the confirm button being pushed offscreen; selected characters indicated by green highlight on cards.
- **Round banner**: floating center-screen "Round N" text with fade animation at each round start.
- **Downed unit activation**: downed units participate in the activation queue and are permanently removed at end of their activation turn (replacing the old grace-period removal at round start).
- **Delayed down animation**: pawn flip-to-downed visual deferred until dice animation completes.
- **Auto-round-advance**: rounds automatically transition without requiring a keypress at round end.
- **Mouse pan**: middle-mouse-button drag panning for the camera rig.
- **Data layer additions**: `wp_cost` field on abilities, `wp` stat on characters/classes/races, `DiceMarker.TOTAL_DURATION` constant.

### Out of scope

- AI opponents (deferred).
- Multiplayer/networking (deferred).
- In-app character builder and free-form multiclassing (deferred).
- Floating damage numbers and particle effects (deferred).
- Audio feedback (deferred).
- Undo within an activation (deferred — evaluated and deprioritized for MVP).
- Rout threshold percentage (MVP uses full elimination only).

### Exit criteria

1. Abilities with `wp_cost > 0` deduct WP on use; abilities are disabled in the HUD when WP is insufficient (shown in red).
2. WP is displayed in the bottom bar unit info, in ability/item popups, and as a purple bar in the sidebar.
3. A match ends immediately when one team has no living or downed units; a match-over overlay displays the winner with a back-to-menu button.
4. Clicking a unit during AWAITING_ACTIVATION previews the selection; a confirm/cancel panel appears. Activation only commits on confirm.
5. The Defend action's +2 DEF modifier and defense die eligibility persist through round boundaries until the unit is next activated.
6. Ranged attacks (RNG > 1) and ranged abilities (range > 1) reject targets at hex distance 1; target overlays exclude adjacent hexes for these actions.
7. Status effect icons appear in the team roster sidebar cards alongside duration labels; the defend state shows a blue "Defending" indicator.
8. Status billboard markers are 50% larger (0.225 quad) with proportionally increased spacing (0.27).
9. The draft screen's "Your Party" section is removed; the confirm button remains always visible; selected characters are indicated by green card tinting.
10. A "Round N" banner fades in and out at center screen when each round begins.
11. Downed units appear in the activation queue; selecting a downed unit activates it and permanently removes it at end of activation.
12. The pawn down-flip animation is deferred until after dice markers finish (~3.3s).
13. Rounds auto-advance without requiring a keypress; the ROUND_END controller state is replaced by MATCH_OVER.
14. Middle-mouse-button drag pans the camera relative to yaw.
15. All existing GUT tests pass with updated assertions reflecting new mechanics.

---

## 2. Design Decisions

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Willpower as gating resource** | New `wp` stat with per-ability `wp_cost`. Zero-cost abilities remain ungated. | Prevents spell spam without introducing cooldowns. Adds a strategic dimension — casters must manage WP across the match. WP is a base stat like HP, derived from character + class + race. |
| **WP not recovered** | No WP recovery mechanic in MVP. | Simplifies balance. Casters are powerful early, weaken over time. Recovery items/abilities can be added in future phases. |
| **Defend persists until next activation** | Moved defend removal from `start_round()` to `activate_unit()`. | Original behavior (clear at round start) meant defending on the last activation of a round gave nearly zero benefit. New behavior rewards the tactical choice regardless of activation order. |
| **Minimum range 2 for ranged** | Enforced in `TurnActions` validation and `OverlayController` visuals. | Prevents ranged characters from being equally effective in melee, creating a positioning incentive. Melee abilities (range 1) are unaffected. |
| **Activation confirmation** | Two-step flow: click → preview → confirm/cancel. | Prevents misclicks from committing to the wrong unit's activation. Especially important since activation order is tactically significant. |
| **Downed removal at activation** | Downed units enter the queue and are removed when their turn comes (via `end_activation`). | More predictable than the old grace-period system. Players see exactly when a downed unit will be removed. Creates tactical tension — the opponent's activation order affects when downed allies are lost. |
| **Auto-round-advance** | `_enter_round_end()` calls `_start_new_round()` directly; removed `ROUND_END` state and `p4_round` input. | Eliminates a dead keypress step. The round banner provides visual feedback. |
| **Match-over overlay** | Inline overlay with winner text and back-to-menu button. | Simple, effective. No new scene needed. The overlay blocks input to prevent further actions. |
| **Draft "Your Party" removal** | Removed the growing list; rely on green card highlighting. | The growing list pushed the confirm button offscreen with enough selections. Card highlighting already communicates selection state. |
| **Delayed down animation** | `DiceMarker.TOTAL_DURATION` timer before calling `down_pawn()`. | The dice roll animation needs to finish before the pawn flips, otherwise the visual sequence is confusing. Game state is already resolved; only the cosmetic flip is deferred. |

---

## 3. Willpower (WP) System

### 3.1 Data layer

- **StatKey**: `WP` added to the `Key` enum and string mapping (`"wp"`).
- **AbilityData**: new `wp_cost: int = 0` field.
- **DataFactory**: parses `wp_cost` from ability JSON.
- **Validator**: rejects negative `wp_cost`.
- **BattleUnit**: new `current_wp: int` field, initialized from `stats.effective("wp")` in `from_character()`.

### 3.2 Content updates

All 14 abilities gain a `wp_cost` field (0 for non-caster skills, 1–4 for spells).
All 8 characters gain `wp` in their `base_stats`.
Caster classes (black_mage, red_mage, white_mage, bard) gain positive `wp` modifiers.
Races with caster affinity (elf) gain `wp` bonus; dwarves take a `wp` penalty.

### 3.3 Combat enforcement

- **TurnActions.execute_ability()**: checks `current_wp >= ability.wp_cost` before allowing the ability. Deducts WP on success.
- **TurnActions.execute_use_item()**: resolves the item's granted ability and checks/deducts WP if the ability has a cost.

### 3.4 HUD integration

- **Bottom bar**: purple WP counter next to AP pips.
- **Ability popup**: each ability button shows WP cost; disabled with red text when WP insufficient but AP sufficient.
- **Item popup**: shows WP cost from the granted ability; same red-disabled treatment.
- **Sidebar**: purple WP bar with numeric label per unit card (hidden if max WP is 0).

---

## 4. Victory Detection & Match-Over

### 4.1 MatchState.check_winner()

Returns the winning team string when the opposing team has no living and no downed units. Returns empty string if the match continues.

### 4.2 BattleController integration

`_check_match_over()` is called:
- At the start of `_enter_awaiting_activation()` (catches eliminations from combat).
- After `_do_wait()` completes and `end_activation()` removes a downed unit.

### 4.3 Match-over overlay

A centered `PanelContainer` with winner text and "Back to Main Menu" button. Blocks all input. Button triggers scene change back to `draft_scene.tscn`.

---

## 5. Activation Confirmation Flow

### 5.1 State changes

- New `_pending_activation_unit: BattleUnit` field on `BattleController`.
- `_set_pending_activation(unit)`: highlights the unit, shows info, displays confirm/cancel panel.
- `_clear_pending_activation()`: resets to selectable-units display.
- `_on_confirm_activation()`: commits the activation via `_activate_chosen_unit()`.
- Tile clicks and roster clicks during `AWAITING_ACTIVATION` now call `_set_pending_activation()` instead of directly activating.

### 5.2 HUD elements

- New `_activation_panel: PanelContainer` floating above the bottom bar.
- "Activate: [Name]" confirm button and "Cancel" button.
- New signals: `confirm_activation_pressed`, `cancel_activation_pressed`.

---

## 6. Defend Duration Fix

### 6.1 Change

- **Removed**: bulk defend modifier removal from `RoundManager.start_round()`.
- **Added**: `unit.stats.remove_modifiers_by_source("defend")` in `RoundManager.activate_unit()`.

### 6.2 Behavior

A unit that defends keeps the +2 DEF modifier and defense die eligibility through any number of opponent activations and across round boundaries. The modifier is removed only when that specific unit begins its next activation.

---

## 7. Minimum Range for Ranged Attacks

### 7.1 Validation

- **TurnActions.execute_attack()**: if `rng > 1` and distance to target < 2, returns error "Target too close for ranged attack".
- **TurnActions.execute_ability()**: if `ability_range > 1` and distance to target < 2, returns error "Target too close for ranged ability".

### 7.2 Overlay

- **OverlayController.show_targets()**: new `min_range: int = 1` parameter. Hexes closer than `min_range` are excluded from the overlay.
- **BattleController**: passes `min_range = 2` when showing attack overlays for ranged weapons (`rng > 1`) and ability overlays for ranged abilities (`ability_range > 1`).

---

## 8. Status Effects in Sidebar

### 8.1 Unit cards

After the WP bar row, each sidebar unit card now shows:
- A row of status effect icons with `SymbolAtlas.get_icon()` textures, labeled with `id(duration)` in amber text.
- A "Defending (+2 DEF, defense die)" indicator in blue text when the unit has the defend modifier.

---

## 9. Additional Polish

### 9.1 Status billboard size

`StatusMarker` quad size increased from `Vector2(0.15, 0.15)` to `Vector2(0.225, 0.225)` (50% larger). Marker horizontal spacing in `PawnManager` increased from `0.18` to `0.27`.

### 9.2 Draft screen

"Your Party" label, `_selected_list` container, and `_update_selected_list()` method removed. The `_confirm_btn` is now placed directly after the roster grid, keeping it always visible.

### 9.3 Round banner

A large centered label ("Round N") fades in at round start, holds for 1.5s, then fades out over 0.5s. Uses shadow text for readability. `MOUSE_FILTER_IGNORE` to avoid intercepting clicks.

### 9.4 Downed unit handling

- Downed units are included in `activatable_units()` and the activation queue.
- When a downed unit's activation comes, it is activated (no AP), then `end_activation()` permanently removes it and frees its hex.
- The old `start_round()` grace-period removal code is removed.

### 9.5 Delayed down animation

`_delay_down_pawn()` uses `get_tree().create_timer(DiceMarker.TOTAL_DURATION)` to defer the visual pawn flip until dice animations complete. `DiceMarker.TOTAL_DURATION` is a new constant (`ROLL_DURATION + HOLD_DURATION + FADE_DURATION = 3.3s`).

### 9.6 Auto-round-advance

`_enter_round_end()` calls `_start_new_round()` directly. The `ROUND_END` controller state is replaced by `MATCH_OVER`. The `p4_round` input action is removed.

### 9.7 Mouse panning

`CameraRig` gains middle-mouse-button drag support. `_mmb_dragging` and `_mmb_last_pos` track state. `_apply_pan()` extracted from `pan()` for reuse. `mouse_pan_speed` export (default 0.02).

---

## 10. Data Flow

### From prior phases

| Source | Data consumed |
|--------|------|
| Phase 1 | `CharacterData`, `StatBlock`, `BattleUnit`, `AbilityData`, `ItemData`, `DataFactory`, `Validator`, `StatKey` |
| Phase 4 | `TurnActions`, `RoundManager`, `MatchState`, action economy |
| Phase 5 | `CombatResolver` (defense die check via `has_modifier_from_source("defend")`) |
| Phase 8 | `BattleController` state machine, `BattleHUD` signals/panels, `PawnManager` pawn lifecycle |
| Phase 9 | `SymbolAtlas.get_icon()` for sidebar status icons |
| Phase 10 | `ActionMarker`, `DiceMarker.TOTAL_DURATION`, `PawnManager.show_action_marker()` |

### Outputs

- Modified `StatKey` — `WP` enum value and string mapping.
- Modified `AbilityData` — `wp_cost` field.
- Modified `BattleUnit` — `current_wp` field.
- Modified `MatchState` — `check_winner()`, `activatable_units()`.
- Modified `RoundManager` — defend removal on activation, downed unit removal in `end_activation()`, queue built from `activatable_units()`.
- Modified `TurnActions` — WP checks, minimum range enforcement.
- Modified `BattleController` — activation confirmation, match-over, auto-round-advance, delayed down animation, downed unit activation.
- Modified `BattleHUD` — WP displays, activation panel, round banner, match-over overlay, sidebar status/defend indicators.
- Modified `OverlayController` — `min_range` parameter on `show_targets()`.
- Modified `StatusMarker` — larger quad size.
- Modified `PawnManager` — wider status marker spacing.
- Modified `CameraRig` — mouse pan support.
- Modified `DiceMarker` — `TOTAL_DURATION` constant.
- Modified `DraftScene` — removed "Your Party" section.
- Updated all 14 ability JSONs — `wp_cost` field.
- Updated all 8 character JSONs — `wp` in base_stats.
- Updated 4 class JSONs — `wp` modifiers.
- Updated 3 race JSONs — `wp` modifiers.

---

## 11. Risks & Notes

- **WP balance untested at scale.** WP costs are initial estimates. Playtest iteration may require adjusting values. The system is designed for easy tuning (JSON-authored costs).
- **No WP recovery.** Casters become weaker over long matches. This is intentional for MVP but may need items or rest mechanics later.
- **Activation confirmation adds a click.** Experienced players may find it slow. A "quick activate" option could be added later.
- **Downed unit activation is a UI edge case.** The downed unit's turn shows only "End Turn" since they have 0 AP. This is intentional — it communicates the removal clearly.
- **Delayed down animation timing.** If dice animation timing changes, `TOTAL_DURATION` must be updated. The constant is centralized in `DiceMarker` for single-point maintenance.
- **Minimum range breaks some test setups.** Tests that had ranged units attacking adjacent targets needed updating. The new behavior is the desired gameplay rule.

---

## 12. Phase 11 Deliverables Checklist

- [x] WP stat added to `StatKey`, `AbilityData`, `BattleUnit`, data pipeline (§3.1)
- [x] All ability/character/class/race JSONs updated with WP values (§3.2)
- [x] WP enforcement in `TurnActions` for abilities and items (§3.3)
- [x] WP display in bottom bar, ability popup, item popup, sidebar (§3.4)
- [x] `MatchState.check_winner()` victory detection (§4.1)
- [x] Match-over overlay with winner display and back-to-menu (§4.2–4.3)
- [x] Activation confirmation flow with preview/confirm/cancel (§5)
- [x] Defend modifier persists until next activation (§6)
- [x] Minimum range 2 for ranged attacks and abilities (§7)
- [x] Status effect icons and defend indicator in sidebar (§8)
- [x] Status billboard 50% larger (§9.1)
- [x] Draft screen "Your Party" removed (§9.2)
- [x] Round banner with fade animation (§9.3)
- [x] Downed unit activation and removal in queue (§9.4)
- [x] Delayed down animation after dice (§9.5)
- [x] Auto-round-advance (§9.6)
- [x] Mouse pan via middle-click drag (§9.7)
- [x] All GUT tests updated and passing
