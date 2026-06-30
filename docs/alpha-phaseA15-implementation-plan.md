# Phase A15 — Implementation Plan: Single-Player Telegraphed Speed-Round + Turn-System Architecture

**Spec:** `alpha-phaseA15-spec.md`
**Branch:** `feature/alpha-a15` · **Merge target:** `development`
**Engine:** Godot 4.6.3 (do not auto-upgrade) · GDScript (typed)
**Depends on:** A7 (`AIPlanner`/`AIScorer`/`AIController`). Coordinates with A12/A13 (deployment→round seam) and A20 (second `TurnSystem`).
**Scope guard:** A15 owns the **turn-system seam** + the **single-player speed-round** + **telegraph**. It does **not** add combat math (A16–A19) or the Charge-Time system / skirmish (A20). It *consumes* whatever resolution math exists.

---

## Group A — TurnSystem seam (foundation)

- [ ] `src/core/combat/turn_system.gd` — abstract `TurnSystem` (`RefCounted`): `begin_round(state)`, `is_round_complete(state)`, `advance(state)`; optional `wants_telegraph() -> bool`.
- [ ] `src/autoload/match_data.gd` — add `mode: String` (`"run"` | `"skirmish"`) with safe default `"run"`.
- [ ] `src/core/combat/round_manager.gd` — delegate round flow to the active `TurnSystem`; keep MVP behavior behind the seam until the speed-round lands.
- [ ] `BandBattleLauncher` / match build — instantiate `SpeedRoundTurnSystem` when `mode == "run"`.
- [ ] Tests: seam selection by mode; `RoundManager` delegates.

## Group B — Round-plan model

- [ ] `src/core/combat/round_plan.gd` (`RoundPlan`) — holds committed per-unit plans for **both** teams; reuse the A7 `AIPlan` step model; `sorted_by_speed(state) -> Array` (descending effective `SPD`, seeded tie-break; round-1 tie respects A13 flip if present).
- [ ] Player plans are produced as the same `AIPlan` structure via the UI (Group E).
- [ ] Tests: SPD ordering, seeded ties, round-1 flip seed.

## Group C — SpeedRoundTurnSystem (the four stages)

- [ ] `src/core/combat/speed_round_turn_system.gd` — stage machine: `AI_PLANNING → PLAYER_PLANNING → RESOLUTION → reset`.
- [ ] `src/core/combat/match_state.gd` — add `Phase` values `AI_PLANNING`, `PLAYER_PLANNING`, `RESOLUTION`; hold the active `TurnSystem`.
- [ ] **AI_PLANNING:** ask `AIController`/`AIPlanner` for a committed plan per AI unit (full round); store as `IntentPlan`s (Group D) + into the `RoundPlan`.
- [ ] **PLAYER_PLANNING:** accept the player's committed plans for all his units (Group E) into the `RoundPlan`.
- [ ] **RESOLUTION:** iterate `RoundPlan.sorted_by_speed`; feed each step to `TurnActions`; apply the **validity policy** (Group F) per step.
- [ ] **reset:** clear plans, tick status durations, apply per-turn terrain (existing hooks), victory check, next round.
- [ ] Tests: stage sequencing; full deterministic headless round.

## Group D — Telegraph & projection (logic)

- [ ] `src/core/combat/outcome_projection.gd` (`OutcomeProjection`, static) — pure `min/mid/max` over `CombatResolver` math (rolls 1 / 3.5 / 6, incl. Defend die + elevation/cover). No mutation.
- [ ] `src/core/ai/intent_plan.gd` (`IntentPlan`) — serializable: `unit_id`, `move_to`, `path`, `action_kind`, `ability_id`, `targets`, `aoe_footprint`, `projection`, `committed`.
- [ ] `src/core/ai/telegraph_service.gd` (`TelegraphService`) — build `IntentPlan`s from the AI's committed `RoundPlan` (single plan source — no parallel logic).
- [ ] Tests: telegraph plan == executed plan (pre-invalidation); projection matches `resolve_damage` at fixed rolls.

## Group E — Player batch-planning UI

- [ ] `src/ui/battle_hud.gd` / `src/map/battle_controller.gd` — planning flow: select unit → plan move (path preview) + action (target/forecast) → repeat for all units → **Commit round** button; free re-plan before commit.
- [ ] Player action **forecast**: render `OutcomeProjection` on prospective targets on hover/selection.
- [ ] Tests (headless-friendly where possible): plan capture per unit; commit gating (cannot resolve before commit; cannot act before AI commits).

## Group F — Resolution-time validity policy

- [ ] In `SpeedRoundTurnSystem` resolution: **move** advances along path, stops on last free tile if blocked; **single-target action** fizzles if target dead/out-of-range/LoS (AP/WP **spent** — confirm with design); **ground AoE** resolves on the tile (hits current occupants).
- [ ] Emit clear log + telegraph annotation for fizzle/interrupt.
- [ ] Tests: stop-short on newly occupied tile; single-target fizzle; ground-AoE hits occupant; **interrupt** (fast unit kills telegraphed attacker → its strike fizzles).

## Group G — Telegraph overlay & disclosure dial

- [ ] `src/map/overlay_controller.gd` — intent layers (ghost pawn, dashed path, target/AoE highlight, range label); whole AI side shown as committed.
- [ ] Resolution playback uses existing A14 symbol pawns + dice/status markers.
- [ ] `data/constants.json` — `TELEGRAPH_MODE` (`full`/`targets`/`off`, default `full`) + styling/policy tunables; wire to difficulty presets.
- [ ] Tests: disclosure gating; **parity** — `off` yields identical combat logs to a telegraph-disabled baseline.

---

## Exit gate

- [ ] Run container selects the speed-round; four stages sequence correctly.
- [ ] AI commits + telegraphs full round; player plans all units; resolution is `SPD`-ordered; validity/interrupt policy holds.
- [ ] Single-plan contract + range projection verified; disclosure dial + parity verified.
- [ ] Headless suite deterministic and green: `godot -d -s --path . addons/gut/gut_cmdln.gd`.
- [ ] Git tag `alpha-phaseA15-complete`; PR into `development`.

## Notes for the implementing agent

- Keep `CombatResolver`/`TurnActions` untouched except where projection needs a pure extraction — the goal is a new *driver*, not new resolution rules.
- Design the seam so A20's `ChargeTimeTurnSystem` drops in without touching `SpeedRoundTurnSystem`.
- One open design decision to confirm with the planner/user: fizzled actions **spend** vs **refund** AP/WP (plan assumes **spend**).
