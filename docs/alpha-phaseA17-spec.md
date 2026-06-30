# Phase A17 — Knockout & Revive Lifecycle Specification

**Parent plan:** `roadmap-A11-onward.md` (sub-phase A17)
**Master spec:** `alpha-specs.md` (combat resolution, run death model)
**Builds on (MVP):** `phase5` (`CombatResolver.resolve_revive`), `phase8` (`BattleController`, `PawnManager`, HUD, event log)
**Builds on (Alpha):** A8 (`DeathModel`/down-limit permadeath), A5 (`CharacterInstance.downs_this_run`)
**Coordinates with:** A15 (downed state and revive targets are telegraphed), A16 (lethal-blow flagging)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-30
**Status:** Draft v0.1

---

## 1. Purpose & Scope

The pieces of a knockout/revive lifecycle exist but are **not fully wired into one coherent, visible flow**. `CombatResolver.resolve_revive` and a `revive`-type effect exist; `BattleUnit` tracks `current_hp` and a downed condition; the run layer (`DeathModel`, `downs_this_run`, `DOWN_LIMIT`) tracks permadeath. A17 connects these into a single, legible **down → (revive | stay down) → run-level permadeath** lifecycle with the matching in-battle UX, so the player can clearly see who is down, revive them, and understand the permadeath stakes.

### In scope

- A precise **downed-unit state machine** on `BattleUnit`: `ACTIVE → DOWNED` at HP ≤ 0 (removed from the activation queue, not removed from the board), `DOWNED → ACTIVE` on revive at a defined HP fraction, and a clear distinction between **downed (revivable this battle)** and **dead/removed**.
- **Revive integration**: `resolve_revive` restores a downed unit to `REVIVE_HP_FRACTION` of max HP, returns it to the activation order, and is a legal ability/item target only on downed allies.
- **Victory/queue correctness**: downed units do not act and do not count as living for victory; reviving a unit reverses that.
- **Run-level permadeath wiring**: a unit still downed at battle end increments `downs_this_run`; exceeding `DOWN_LIMIT` triggers permanent removal via `DeathModel`. The battle-end → run handoff applies this consistently.
- **UX**: downed pawn visual (knocked/greyed), a HUD roster indicator, revive-target highlighting (telegraphed via A15), and event-log entries for down / revive / permadeath.

### Out of scope

- Crystals/loot-on-death à la FFT (forward note only).
- Auto-revive *passives* (A18) and revive-on-element-absorb (A16) — they hook this lifecycle later.
- Changing the `DOWN_LIMIT` value or run-loss conditions (A8/A10 tuning).

### Exit criteria

1. A unit reaching HP ≤ 0 enters **DOWNED**: it leaves the activation queue, stays on the board with a downed visual, does not act, and does not count toward its team's living count.
2. A revive ability/item targets **only downed allies** and returns the unit to **ACTIVE** at `REVIVE_HP_FRACTION` HP and back into the activation order at the correct position.
3. Victory detection counts a revived unit as living again; a team with all units downed loses immediately (revive can avert this only before the check resolves).
4. At battle end, units still downed increment `downs_this_run`; crossing `DOWN_LIMIT` removes the `CharacterInstance` permanently through `DeathModel`, reflected in the band roster.
5. The HUD shows downed status per unit; the event log records down, revive, and permadeath events; A15 telegraphs revive targets and any enemy intent to revive.
6. Headless tests cover the full lifecycle without visuals; combat/run outcomes are deterministic.
7. Existing combat and run tests pass with the formalized state machine.

---

## 2. Design Decisions

- **Downed ≠ removed.** Downed units remain on the board (occupying their tile) so revive has a location and the board reads correctly; only run-level permadeath removes the instance.
- **Single source of truth for "living."** Victory and queue logic query one predicate (`is_active()` / `is_living()`); revive flips it. No scattered HP checks.
- **Battle/run seam.** The battle reports per-unit downed status; the run layer (`RunController` + `DeathModel`) owns the permadeath decision so battles stay run-agnostic and testable in isolation.
- **Tunables** in `constants.json`: `REVIVE_HP_FRACTION`, and reuse existing `DOWN_LIMIT`.

---

## 3. Files

**Modified:**
- `src/core/data/battle_unit.gd` — downed state machine + `is_active()`/`is_living()` predicates.
- `src/core/combat/match_state.gd` / `round_manager.gd` — queue removal/reinsertion; victory predicate via the single source of truth.
- `src/core/combat/combat_resolver.gd` (`resolve_revive`) + `turn_actions.gd` — revive legality (downed allies only), HP restore, requeue.
- `src/core/run/{run_controller,death_model}.gd` — battle-end downed → `downs_this_run` → permadeath.
- `src/map/pawn_manager.gd` / `src/ui/battle_hud.gd` — downed visual, roster indicator, revive highlight, log entries.
- `data/constants.json` — `REVIVE_HP_FRACTION`.

---

## 4. Test Plan

- HP ≤ 0 → DOWNED: unit leaves queue, not counted living, stays on board.
- Revive: only valid on downed allies; restores HP fraction; re-enters queue; counts living again.
- All-downed team → immediate loss; revive before the check averts it.
- Battle end with a still-downed unit increments `downs_this_run`; `DOWN_LIMIT+1` removes the instance from the band.
- Regression: prior combat/run suites green with the new predicates.
