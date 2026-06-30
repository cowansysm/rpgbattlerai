# Phase A15 — Single-Player Combat: Telegraphed Speed-Round + Turn-System Architecture Specification

**Parent plan:** `roadmap-A11-onward.md` (sub-phase A15)
**Master spec:** `alpha-specs.md` (combat substrate); `feature-scan-and-competitive-analysis.md` (Part 3, #7)
**Builds on (MVP):** `phase4` (`MatchState`, `RoundManager`, initiative), `phase8` (`BattleController`, `OverlayController`, `PawnManager`, HUD, tile picking)
**Builds on (Alpha):** A7 (`AIPlanner`, `AIScorer`, `AIController` — the plan source of truth), A0 (terrain effects feed projected outcomes), A14 (symbol pawns reused for intent/resolution feedback), A13 (coin flip seeds opening order ties)
**Coordinates with:** A16 (elemental/crit math feeds projected ranges), A17 (KO/revive at resolution), A18 (reactions in intent), A19 (facing affects projection); **A20 (the *other* turn system — multiplayer Charge-Time)**
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-30
**Status:** Draft v0.2 (revised for mode-dependent turn activation)

---

## 1. Purpose & Scope

Combat now has **two turn-activation models, selected by game mode**:

- **Single-player** (container: the **roguelike run**, A8) uses a **telegraphed speed-round** — a *plan-then-resolve* (WeGo) round built around perfect information. **This is A15** and it defines the game's signature single-player mechanic.
- **Multiplayer** (container: **skirmish**, squad-size + draft) uses a **continuous Charge-Time clock** with **no telegraph** — **that is A20**.

A15 delivers two things: (1) a **pluggable turn-system architecture** so a match can run under either model, and (2) the **single-player telegraphed speed-round** itself.

### The single-player round (the core loop)

Each round proceeds in four ordered stages:

1. **AI Commit & Telegraph.** The AI decides every one of its units' actions for the round (move + action + target, within AP/WP) and **locks them in**. All of it is **telegraphed** to the player: intended destination, action, target(s)/AoE footprint, and projected outcome range.
2. **Player Planning.** With the AI's full intent visible, the player **activates all of his characters** and plans each one's movement and action (up to its AP), freely revising until satisfied, then **commits the round**.
3. **Speed-Ordered Resolution.** Every committed action — both sides' — executes **one unit at a time in order of the `SPD` stat** (highest first; seeded tie-break), like a single Charge-Time pass for the round. A fast unit can therefore **act before** a slower enemy whose strike was telegraphed — landing a kill that makes the enemy's planned action fizzle (the interrupt dynamic that gives perfect information its bite).
4. **Round Reset.** Plans clear, status durations tick, terrain per-turn effects apply, victory is checked, and the next round returns to stage 1.

### Why this shape

The d6 stays, so outcomes are ranges, not certainties — but **intent is exact and fully disclosed for the whole round**. The tension is no longer "what will the enemy do?" (you know) but "can I out-tempo, block, or dodge what they've committed to, given who's faster?" That is a cleaner, more legible perfect-information puzzle than alternating activation allowed, and it makes `SPD` a first-class tactical resource in single-player.

### In scope

- A **`TurnSystem` seam** (strategy interface) over `MatchState`, with the **single-player** implementation here (`SpeedRoundTurnSystem`). A20 adds the multiplayer implementation. The match's mode (from `MatchData`) selects the system.
- The **four-stage round**: AI commit, telegraph, player batch-planning, `SPD`-ordered resolution, reset — with new `MatchState.Phase` states for planning and resolution.
- A **planning model**: per-unit committed plans (move path + action + target) for both teams, validated against AP/WP at commit time; the player may re-plan any of his units before committing the round; the AI's plan is locked once telegraphed.
- A **`TelegraphService`** producing an **`IntentPlan`** per AI unit from `AIPlanner`/`AIScorer` (single plan source — telegraph and execution cannot diverge), plus **`OutcomeProjection`** (min/mid/max ranges over `CombatResolver` math).
- A **resolution-time validity policy** (see §2.3) governing telegraphed/committed actions whose target or path changed before they resolve (fizzle / partial-move / stop-short) — the same rules for both teams.
- The **telegraph overlay** (ghost pawns, paths, target/AoE highlights, range labels) and a **player-side action forecast** during planning; a **disclosure dial** (Full / Targets-only / Off; Full default).
- **Headless/deterministic** execution: AI-plan + scripted player-plan + `SPD`-ordered resolve, reproducible by seed, no visual nodes.

### Out of scope

- The multiplayer Charge-Time system and the skirmish container (**A20**).
- Changing *how* the AI decides (A7 scoring unchanged; deeper AI later) — A15 reveals and batches the existing decision.
- The combat-math additions themselves (elements/crits A16, KO/revive A17, passives A18, facing A19) — A15 *consumes* whatever resolution math exists and renders/uses its results.
- Networked play (deferred, roadmap A26).

### Exit criteria

1. A match runs under a **selected `TurnSystem`**; the roguelike-run container selects the **single-player speed-round**.
2. Each round executes the four stages in order: AI commits all its units' actions → the player sees the **full AI intent** (move ghost + path + action + target(s)/AoE + projected range) → the player plans and commits **all** of his units → actions resolve.
3. **Resolution is ordered by `SPD`** (highest first, seeded tie-break), interleaving both teams; a faster unit acts before a slower one regardless of side.
4. A telegraphed/committed action whose target is gone or path is blocked at resolution follows the **validity policy** deterministically (fizzle / partial move / stop-short), identically for AI and player.
5. Telegraph and execution derive from the **same `AIPlanner`/`AIScorer`** plan; projected outcomes are **min–max ranges with the midpoint marked**, reflecting elevation, cover, and the Defend die (and A16/A19 when present).
6. The **disclosure dial** changes what is shown (Full default); with telegraph **Off**, combat logs are identical to a telegraph-disabled baseline.
7. Headless contexts run the full round deterministically by seed with no scene nodes; combat outcomes are independent of telegraph visibility.
8. Tests cover: turn-system selection by mode, four-stage sequencing, `SPD` resolution order + seeded ties, the validity policy (incl. the interrupt case), single-plan contract, projection math, and disclosure gating.

---

## 2. Design Decisions

### 2.1 Pluggable turn systems
A `TurnSystem` interface drives a match's flow over `MatchState`:
```
class_name TurnSystem            # abstract (RefCounted)
func begin_round(state) -> void
func is_round_complete(state) -> bool
func advance(state) -> void      # progress the current stage / next actor
```
`SpeedRoundTurnSystem` (this phase) implements the four-stage round; `ChargeTimeTurnSystem` (A20) implements continuous CT. `MatchData` carries a `mode` (`run` | `skirmish`); the launcher instantiates the matching system. `RoundManager` becomes a thin driver delegating to the active system, so existing combat code (`TurnActions`, `CombatResolver`) is untouched.

### 2.2 Plans are first-class, committed records
Both teams' actions are stored as committed **plans** (reuse the A7 `AIPlan` model; the player produces the same structure through the UI). The AI's plans are produced once at AI-Commit and locked; the player's are mutable until the round is committed. Resolution simply walks the merged plan list in `SPD` order and feeds each step to `TurnActions` — the same backend the AI and human already share (preserves the deterministic action log noted in `seam-audit.md`).

### 2.3 Resolution-time validity policy (the crux)
Because everything is planned before anything resolves, a plan can be invalidated by an earlier-resolving action. The policy (deterministic, symmetric for both teams):
- **Move step:** advance along the planned path as far as legal; if the destination (or an intermediate tile) is now occupied, **stop on the last free tile** before it.
- **Attack/ability on a specific unit:** if that unit is dead/downed or no longer in range/LoS after moving, the action **fizzles** (AP/WP spent or refunded — *decision: spent*, to keep commitment meaningful), with a clear "interrupted/whiffed" log + telegraph annotation.
- **Ground-targeted ability (AoE on a tile):** resolves on the tile regardless of occupancy (it hits whoever is there at resolution — rewards predicting movement).
This policy is the mechanical heart of the mode and must be covered by explicit tests (esp. the interrupt: a fast unit kills a telegraphed attacker → that attacker's strike fizzles).

### 2.4 SPD ordering
Resolution order = units sorted by effective `SPD` descending; ties broken by a seeded rule (and, at the very first round, by the A13 coin flip outcome → that team wins `SPD` ties). This finally gives `SPD` real weight in single-player without a continuous clock.

### 2.5 One plan, honest ranges, disclosure dial
As in v0.1: `TelegraphService` wraps `AIPlanner`/`AIScorer`; `OutcomeProjection` is a pure min/mid/max over `CombatResolver`; `Constants.TELEGRAPH_MODE` (`full`/`targets`/`off`, full default) gates disclosure; telegraph never changes outcomes (parity test with `off`).

### 2.6 Reuse visuals
Intent rendering reuses `OverlayController` (highlights/paths), the A14 icon atlas (action icons), and ghost pawn variants. Resolution feedback reuses A14 symbol pawns and existing dice/status markers.

---

## 3. Architecture & Files

**New (core):**
- `src/core/combat/turn_system.gd` (`TurnSystem`, abstract) — the mode seam.
- `src/core/combat/speed_round_turn_system.gd` (`SpeedRoundTurnSystem`) — the four-stage single-player round + `SPD` resolution + validity policy.
- `src/core/combat/round_plan.gd` (`RoundPlan`) — merged committed plans for a round (both teams), `SPD`-sorted iteration.
- `src/core/ai/telegraph_service.gd` (`TelegraphService`), `src/core/ai/intent_plan.gd` (`IntentPlan`), `src/core/combat/outcome_projection.gd` (`OutcomeProjection`).

**Modified:**
- `src/core/combat/match_state.gd` — add `Phase` states (`AI_PLANNING`, `PLAYER_PLANNING`, `RESOLUTION`); hold the active `TurnSystem`.
- `src/core/combat/round_manager.gd` — delegate to the active `TurnSystem`.
- `src/map/ai_controller.gd` — produce the AI's committed round plan at AI-Commit (cache `IntentPlan`s); no per-actor replanning.
- `src/map/battle_controller.gd` — drive the four stages; player batch-planning UI flow; resolution playback; telegraph overlay; gate by `TELEGRAPH_MODE`.
- `src/map/overlay_controller.gd` — intent layers (ghosts, paths, AoE, range labels); committed styling for the whole AI side.
- `src/ui/battle_hud.gd` — planning UI (per-unit plan, commit-round button), player action forecast, disclosure indicator.
- `src/autoload/match_data.gd` — `mode` field; `BandBattleLauncher` selects `SpeedRoundTurnSystem` for runs.
- `data/constants.json` — `TELEGRAPH_MODE` + defaults, validity-policy + styling tunables.

---

## 4. Implementation Outline

1. **`TurnSystem` seam** + `RoundManager` delegation; `MatchData.mode`; launcher selects the SP system.
2. **`OutcomeProjection`** extracted from `CombatResolver`; unit-tested at rolls {1, 3.5, 6}.
3. **`RoundPlan` + `SpeedRoundTurnSystem`**: stage machine (AI_PLANNING → PLAYER_PLANNING → RESOLUTION → reset), `SPD` ordering, validity policy.
4. **`TelegraphService`/`IntentPlan`** from `AIPlanner`/`AIScorer`; AI commits a full-round plan.
5. **Player batch-planning UI**: select unit → plan move + action → repeat → commit round; re-plan freely pre-commit; forecast on targets.
6. **Telegraph overlay** + resolution playback (A14 feedback); disclosure dial.
7. **Headless tests**: full deterministic round; validity/interrupt; ordering; projection; gating.

---

## 5. Test Plan

- **Mode selection:** run container → `SpeedRoundTurnSystem`; (A20 will assert skirmish → CT).
- **Sequencing:** stages fire in order; player cannot act before AI commits/telegraphs; resolution waits for player commit.
- **SPD order:** units resolve by descending `SPD`; seeded ties; round-1 tie respects the A13 flip.
- **Validity policy:** move stops short on a newly occupied tile; single-target action fizzles if target gone (AP/WP spent); ground AoE hits current occupants. **Interrupt:** fast unit kills a telegraphed attacker → that attack fizzles (explicit test).
- **Contract & projection:** telegraphed plan == executed plan (pre-invalidation); `OutcomeProjection` min/mid/max == `resolve_damage` at fixed rolls incl. Defend die/elevation.
- **Gating/parity:** `off` mode renders nothing and yields identical logs to a telegraph-disabled baseline.
- **Headless determinism:** whole round reproducible by seed, no scene nodes.

---

## 6. Forward Hooks

- **A20** implements `ChargeTimeTurnSystem` behind the same seam and the **skirmish** container; telegraph is disabled there.
- **A16/A19** extend `OutcomeProjection`; **A18** annotates reactions in `IntentPlan`; **A17** resolves KO/revive within `SPD`-ordered resolution.
- The deterministic merged `RoundPlan` / action log keeps the door open for replay and (deferred) networking (A26).
