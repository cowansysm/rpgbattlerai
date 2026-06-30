# Phase A19 — Facing & Flanking Specification

**Parent plan:** `roadmap-A11-onward.md` (sub-phase A19)
**Master spec:** `alpha-specs.md` (combat resolution); `feature-scan-and-competitive-analysis.md` (Part 3, #3)
**Builds on (MVP):** `phase3` (hex math, directions), `phase5` (`CombatResolver`), `phase8` (pawns, HUD)
**Builds on (Alpha):** A12 (deployment sets initial facing), A16 (crit interacts with flanking), A7 (AI scoring)
**Coordinates with:** A15 (facing-adjusted projection in the telegraph), A18 (Counter only from defensible facings)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-30
**Status:** Draft v0.1

---

## 1. Purpose & Scope

Add **facing** to units and **flanking** to combat — a staple of FFT, Tactics Ogre, Fire Emblem, and XCOM that the hex grid is well-suited to. Each unit faces one of the six flat-top hex directions; attacks from the side or rear are more effective (higher hit and/or damage, higher crit), rewarding positioning and movement. Facing pairs naturally with the existing height bonus and feeds the telegraph (A15) and AI.

### In scope

- **Facing state** on `BattleUnit`: one of 6 hex directions; set on deployment (A12), updated on move (face along final step) and optionally on action (face the target).
- **Attack arc classification**: from attacker→target geometry relative to target facing, classify **front / flank (side) / rear**, using the existing `Hex` direction math.
- **Flanking bonuses**: tunable modifiers per arc — front (none), flank (e.g., +hit / +small damage / +crit), rear (larger) — applied in `resolve_attack`/`resolve_damage` and to `CRIT_CHANCE` (A16).
- **Telegraph & forecast**: A15 projection reflects the arc the pending attack would land in; the HUD shows the resulting bonus.
- **AI integration**: `AIScorer` values plans that achieve flank/rear positioning and avoids presenting its own rear.
- **Visual**: a facing indicator on pawns (chevron/arrow) and arc feedback on hover.

### Out of scope

- Per-attack manual "turn to face" as a separate AP action (facing follows move/action this phase; a dedicated face action is a forward note).
- Zone-of-control / opportunity attacks (separate future feature).
- Facing for AoE origin (AoE uses caster→target direction already; arc applies to single-target hits and the AoE's primary target).

### Exit criteria

1. Every unit has a **facing** (6 directions), initialized at deployment and updated after moving (and optionally after acting).
2. An attack is classified **front / flank / rear** from geometry and the target's facing, deterministically.
3. **Flank and rear attacks apply their tunable bonuses** (hit/damage/crit) in resolution; front attacks are unchanged from current numbers (regression guard).
4. The A15 telegraph and player forecast show the arc and its bonus before commit.
5. `AIScorer` accounts for facing — it seeks flanks and avoids exposing its rear — within the existing plan budget.
6. Pawns display a facing indicator; hover shows the prospective arc.
7. Tests cover arc classification for all six facings, bonus application per arc, the front-attack regression baseline, facing updates on move, and AI flank-seeking.

---

## 2. Design Decisions

- **Reuse hex direction math.** Arc = relation between the attacker's approach direction and the target's facing via `Hex` neighbor/direction helpers; no new geometry. Rear = directly opposite facing; flank = the side directions; front = facing ± adjacent.
- **Bonuses are tunable and additive** with elevation (A16/A19 stack): a high-ground rear strike is the strongest, by design.
- **Determinism preserved.** Facing is pure state; bonuses feed the same dice/affinity/crit path so seeds and A15 projections stay consistent.
- **Facing follows movement** (face the last step) and, if the unit acts without moving, faces its target — minimizing UX friction while keeping positioning meaningful. A manual face action can be added later without rework.
- **Backward compatibility:** with all arc bonuses set to zero, combat reproduces current numbers (guard test).

---

## 3. Files

**Modified:**
- `src/core/data/battle_unit.gd` — `facing` state + helpers.
- `src/core/hex/hex.gd` — arc classification helper (`arc_of(attacker_dir, target_facing)`), if not already derivable.
- `src/core/combat/combat_resolver.gd` — arc bonus in `resolve_attack`/`resolve_damage`; crit interaction with A16.
- `src/core/combat/turn_actions.gd` — update facing on move/action.
- `src/core/combat/deployment.gd` / A12 `DeploymentController` — initial facing.
- `src/core/ai/ai_scorer.gd` — facing-aware scoring; A15 `outcome_projection.gd` — arc-aware bounds.
- `src/map/pawn_manager.gd` / `src/ui/battle_hud.gd` — facing indicator + arc feedback.
- `data/constants.json` — `FLANK_*` / `REAR_*` bonus tunables.

---

## 4. Test Plan

- Arc classification correct for all six target facings × representative approach directions.
- Flank/rear bonuses apply; front unchanged (regression).
- Facing updates correctly after a move (faces final step) and after a no-move action (faces target).
- Crit-chance interaction with A16 applies on rear strikes.
- AI chooses a flanking plan when one scores higher within budget.
- A15 projection shows the correct arc bonus pre-commit.
