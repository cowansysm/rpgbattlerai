# Phase A17 — Implementation Plan: Knockout & Revive Lifecycle

**Spec:** `alpha-phaseA17-spec.md`
**Branch:** `feature/alpha-a17` · **Merge target:** `development`
**Engine:** Godot 4.6.3 (do not auto-upgrade) · GDScript (typed)
**Depends on:** A5 (`CharacterInstance.downs_this_run`), A8 (`DeathModel`, `DOWN_LIMIT`), existing `CombatResolver.resolve_revive`.
**Shared-file note:** touches `combat_resolver.gd`, `battle_unit.gd`, `turn_actions.gd`, `match_state.gd`, `round_manager.gd`, `battle_hud.gd` — shared with A18/A19. **A17 goes first in the follow-on wave** because its living/downed predicate is consumed everywhere. See the wave coordination plan.

---

## Group A — Downed state machine (single source of truth)

- [ ] `src/core/data/battle_unit.gd` — add explicit lifecycle: `ACTIVE → DOWNED` (HP ≤ 0) with `is_active()` / `is_living()` predicates; `DOWNED` unit stays on the board (keeps its tile) but is not "living."
- [ ] Replace scattered `current_hp <= 0` / `is_downed` checks with the predicate (grep the codebase; keep behavior identical where it already worked).
- [ ] Tests: HP ≤ 0 → DOWNED; predicate correctness; unit remains on board.

## Group B — Queue & victory correctness

- [ ] `src/core/combat/match_state.gd` / `round_manager.gd` — downed units removed from the activation order; **victory predicate** queries the single `is_living()` source.
- [ ] Works under **both** turn systems (A15 speed-round resolution order + A20 Charge-Time scheduler) — verify a downed unit is skipped in each.
- [ ] Tests: downed unit doesn't act; all-downed team → immediate loss.

## Group C — Revive integration

- [ ] `src/core/combat/combat_resolver.gd` (`resolve_revive`) + `turn_actions.gd` — revive legal **only** on downed allies; restores to `REVIVE_HP_FRACTION` of max HP; returns unit to `ACTIVE` and re-inserts into the activation order at the correct position (per active turn system).
- [ ] Tests: revive rejects non-downed / enemy targets; HP restored; requeued; counts living again; revive before the victory check averts a loss.

## Group D — Run-level permadeath handoff

- [ ] `src/core/run/run_controller.gd` + `death_model.gd` — at battle end, units still downed increment `downs_this_run`; crossing `DOWN_LIMIT` permanently removes the `CharacterInstance` via `DeathModel`, reflected in the band roster.
- [ ] Keep the battle run-agnostic: the battle reports per-unit downed status; the run layer owns the permadeath decision.
- [ ] Tests: still-downed at end → `downs_this_run++`; `DOWN_LIMIT+1` removes instance from band.

## Group E — UX & feedback

- [ ] `src/map/pawn_manager.gd` — downed pawn visual (knocked/greyed).
- [ ] `src/ui/battle_hud.gd` — per-unit downed indicator; revive-target highlight (surfaced by A15 telegraph where applicable).
- [ ] Event-log entries for down / revive / permadeath.
- [ ] `data/constants.json` — add `REVIVE_HP_FRACTION` (reuse existing `DOWN_LIMIT`).

---

## Exit gate

- [ ] Downed lifecycle formalized with one living/downed predicate; downed units leave the queue but stay on board.
- [ ] Revive targets only downed allies, restores HP fraction, requeues, counts living; correct victory/permadeath handoff.
- [ ] Works under both turn systems; HUD + log + telegraph reflect it.
- [ ] Headless GUT suite green: `godot -d -s --path . addons/gut/gut_cmdln.gd`.
- [ ] Git tag `alpha-phaseA17-complete`; PR into `development`.

## Notes for the implementing agent

- The goal is to *consolidate* existing pieces (`resolve_revive`, HP checks, `DeathModel`) into one coherent lifecycle — not to invent new death rules. Prefer one predicate over scattered checks.
- A18 (passives) will later hook auto-revive/auto-potion into this lifecycle, and A19 does not touch it — leave clean seams.
