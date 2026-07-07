# Content Redesign — Phase 3: Combat/AI Validation

**Date:** 2026-07-06
**Status:** ✅ COMPLETE (lean scope; balance-metrics sweep deferred to Phase 6 per decision).
**Branch:** `feature/content-redesign-phase3` (off `feature/content-redesign-phase1`).

## Objective
Confirm the adopted 10-tier content produces **functional, non-degenerate combat**: fights
resolve, the AI actually uses `jp_costs`/granted abilities (not just basic attacks), all ability
shapes/elements resolve without error, and passives are never mis-used as actions. Surface issues
as data for Phase 6 — not to tune balance here.

## Decisions (from Phase 0 / this phase)
- **Lean scope.** Termination + AI ability usage + passive hygiene + shape/element coverage. The
  full balance-metrics sweep (player-party vs level-matched, win-rate/damage tables) stays in Phase 6.
- **Fix passive bug here** (found during planning; see below).
- **New branch** off phase1, separate PR.

## Approach
A headless AI-vs-AI simulation in pure core logic (no scene tree), since all combat classes are
`RefCounted`: `MatchSetup` → `Deployment.auto_deploy` → loop `AIPlanner.plan` → `TurnActions.*`
→ `RoundManager.end_activation` until `MatchState.check_winner()` or a round cap. Deterministic
via a seeded RNG.

## Deliverables
- `tests/helpers/battle_sim.gd` — reusable headless sim driver (seeded, capped; returns a metrics
  dict: winner, rounds, activations, ability/attack/move counts, executed_abilities, passive_executed,
  errors). Also `duel_state()` + `loadout_unit()` for controlled single-ability casts.
- `tests/core/combat/test_encounter_sim.gd` — three GUT tests:
  1. **Termination + AI usage** — bat/demon/drake squads across low/mid/high bands resolve within
     the cap with 0 hard errors, `passive_executed == 0`, and the AI uses abilities; the sample
     exercises ≥1 new-element and ≥1 AoE-shape ability in real combat.
  2. **Shape/element coverage** — all 4 AoE shapes (`cleave`/`landslide`/`fissure`/`ring_of_fire`)
     and all 6 restored elements (`bio_1`/`flare`/`steam_dart`/`alchemical_dart`/`aether_dart`/
     `sonic_dart`) cast without error and produce an outcomes record.
  3. **Passive hygiene** — a passive (`counter`) in a loadout is excluded from `all_abilities()` and
     rejected by `resolve()`, while active abilities still resolve.

## Bug fixed (passive hygiene)
`AIPlanner._get_unit_abilities` and `AbilityResolver` had no `passive_kind` filter. The new content
teaches passive abilities via `jp_costs` (e.g. vagabond → `counter`, `auto_potion`), so a passive
sitting in a unit's loadout would be enumerated as a usable ability and "used" as an action —
silently fizzling (wasted AP). Fixed by filtering `passive_kind != ""` in:
- `AbilityResolver.resolve()` (gates `execute_ability` + the HUD ability menu),
- `AbilityResolver.all_abilities()`,
- `AIPlanner._get_unit_abilities()`.
Active abilities (`passive_kind == ""`) are unaffected.

## Findings confirmed
- **AoE**: all four shapes (burst/line/cone/ring) are handled in `TurnActions._collect_affected_units`;
  unsupported shapes degrade safely to single-target. Restored line/cone/ring abilities resolve.
- **Elements**: resolution is generic; the 6 re-added elements resolve as NEUTRAL (×1.0) with no
  special-casing.
- **Headless combat** is fully drivable without the scene tree.
- **Harness gotcha (documented in code):** a `Callable` to a `RefCounted` method (the ability
  resolver) must be kept alive by a held reference, or it invalidates mid-match. The sim holds its
  resolvers in `_keepalive`; the real `BattleController` holds one as a member.

## Results — all green
Run per-directory (see the whole-suite crash caveat in `content-redesign-spec.md`):
`tests/core/combat` **435/435** (incl. 3 new sim tests), `tests/core/ai` **39/39**, `tests/map`
**86/86** — 0 failures. Matches resolve within the cap; AI uses abilities; `passive_executed == 0`.

## Out of scope → Phase 6
Balance tuning and the quantitative metrics sweep (rounds-to-resolution distributions, win-rate
tables, damage bands, archetype balance).
