# Phase A13 — Coin Flip & Opening Initiative Specification

**Parent plan:** `alpha-implementation-plan.md` (new sub-phase A13)
**Master spec:** `alpha-specs.md` (combat substrate); `rpg-specs.md` (MVP initiative)
**Builds on (MVP):** `phase4` (`MatchState`, `RoundManager`, `initiative`), `phase7` (`MatchSetup`), `phase8` (`BattleController`, HUD/markers)
**Coordinates with (Alpha):** A12 (interactive deployment — the flip runs at the deployment→round-1 seam), A8 (run seed feeds determinism)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-24
**Status:** Draft v0.1

---

## 1. Purpose & Scope

Add a **coin-flip mechanic** to the game: a fair, seeded, two-sided flip with a clear **visual reveal**. Its **first use is opening initiative** — at the start of a battle (after deployment), the coin is flipped: **Heads → the player acts first**, **Tails → the AI acts first**. The mechanic is built **generic and reusable** so later systems (event nodes, tie-breaks, gambles) can flip a coin with the same service and visual.

Today the opening initiative is decided silently by total team SPD (`MatchSetup._determine_initiative`, tie → `randi()`). A13 replaces that opening determination with a coin flip that is **shown to the player**, and leaves the existing per-round initiative flip (`RoundManager`) untouched.

### In scope

- A **generic `CoinFlip` service**: `flip(rng) -> CoinSide {HEADS, TAILS}`, fair 50/50, **seeded** by an injected `RandomNumberGenerator` (reproducible).
- A **reusable coin-flip visual/animation** that *illustrates a pre-computed result* (core decides; the animation lands on that side), emits a "finished" signal, and is skippable.
- **Opening-initiative integration**: after deployment, flip → set `state.initiative` (Heads = player/`playerA`, Tails = AI/`playerB`) → start round 1. Replaces the SPD-based opening determination.
- **Determinism**: the flip derives from the match/run seed (A8 reproducibility).

### Out of scope

- Changing the **per-round** initiative flip (`RoundManager` keeps alternating each round after round 1).
- Other consumers of the coin flip (events/gambles) — A13 only proves the reusable seam with initiative.
- Weighted/loaded coins, multi-coin flips, stat-influenced odds (fair 50/50 only).
- Networked/PvP-specific reveal beyond the generic mapping (PvP maps Heads→`playerA`, Tails→`playerB`).

### Exit criteria

1. A `CoinFlip` service returns `HEADS`/`TAILS` fairly and **deterministically** for a given seeded RNG.
2. At battle start (**after deployment, before round 1**) the coin is flipped and the **result is animated** on screen.
3. **Heads sets `playerA` (player) initiative; Tails sets `playerB` (AI)**; round 1 then begins with that team acting first.
4. The animation **lands on the computed side** (never contradicts the logical result) and the round does not start until the reveal completes (skippable).
5. Headless/test contexts perform the flip + start round **without** animation, deterministically by seed.
6. The old SPD-based opening determination no longer sets initiative; per-round flipping is unchanged.
7. Tests cover seeded determinism, Heads/Tails→team mapping, and the deployment→flip→round-1 sequencing.

---

## 2. Design Decisions (Phase A13)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Timing** | Flip **after deployment, before round 1**; A12 deployment order is **unchanged**. | The opening formation is set first; the flip is the dramatic "who strikes first" beat before combat. |
| **Reusable mechanic** | A generic `CoinFlip` core + a reusable coin-flip view; **initiative is the first consumer**. | Future systems flip with the same service/visual; the caller supplies the meaning of each side. |
| **Seeded** | Result derives from the match/run **seed** via an injected RNG. | Reproducible battles (A8 determinism); "same seed → same flip." |
| **Fair 50/50** | Unweighted coin; no stat influence. | Heads/Tails are a clean binary; SPD no longer gates the opening. |
| **Result first, animation second** | Core computes the side; the view animates *to* that side and signals completion. | The visual can never disagree with game logic; headless skips the view. |
| **Mapping** | **Heads → `playerA` (player) first; Tails → `playerB` (AI) first.** | Per the feature request; generalizes to PvP as playerA/playerB. |

---

## 3. Flow & Sequencing

```
build match → DEPLOYMENT (A12 interactive; AI-first)            # unchanged by A13
deployment completes
  → InitiativeFlip: side = CoinFlip.flip(seeded_rng)            # core, deterministic
  → state.initiative = "playerA" if side == HEADS else "playerB"
  → (scene) play coin-flip reveal animation landing on `side`   # await finished / skippable
  → RoundManager.start_round(state)                             # round 1 begins
```

- A12's `DeploymentController.finish()` previously called `RoundManager.start_round`. A13 **inserts the flip between them**: deployment completion triggers the initiative flip + reveal, and `start_round` is called only after the reveal resolves.
- If A12 is not present, the same insertion happens at the match-start → round-1 transition (the flip simply follows auto/initial placement). A13 is therefore **independent of A12** but shares this seam.

## 4. The `CoinFlip` Service (generic)

```gdscript
# src/core/combat/coin_flip.gd
class_name CoinFlip
extends RefCounted

enum Side { HEADS, TAILS }

static func flip(rng: RandomNumberGenerator) -> int:
    return Side.HEADS if rng.randi() % 2 == 0 else Side.TAILS

static func side_name(side: int) -> String:
    return "heads" if side == Side.HEADS else "tails"
```

- Pure and deterministic for a given seeded `rng`. No global `randi()`.
- Callers map sides to meaning; A13's initiative consumer maps Heads→`playerA`, Tails→`playerB`.

## 5. Opening-Initiative Integration

- A small `InitiativeFlip.resolve(state, rng) -> int` (or a method on `MatchSetup`) calls `CoinFlip.flip`, sets `state.initiative` per the mapping, and returns the side (so the scene can animate it).
- **Replaces** `MatchSetup._determine_initiative` for the opening round: the SPD-sum determination is removed (or demoted to an unused helper); `MatchSetup.create` no longer pre-sets `initiative` from SPD.
- `RoundManager`'s per-round `initiative = other_team(initiative)` is **unchanged** — only the round-1 seed value comes from the coin now.

## 6. Visual & Animation

- A reusable view (e.g., `src/ui/coin_flip_overlay.gd` on a HUD `CanvasLayer`, or a small 3D coin in the map scene) that:
  - takes a **target side** + optional caption, plays a spin/flip animation that **lands on the target side**, then emits `flip_finished`.
  - shows a clear result caption — e.g., **"Heads — You go first!"** / **"Tails — Enemy goes first."** (caption supplied by the initiative consumer; the view itself is content-agnostic).
  - is **skippable** (click/confirm fast-forwards to the result) and has a tunable duration.
- The battle controller awaits `flip_finished` before `start_round`. Headless contexts bypass the view entirely.

## 7. Determinism & Seeding

- The flip uses a `RandomNumberGenerator` seeded from the **match/run seed**. In a run (A8), thread the run seed (offset per battle/event so successive flips differ yet reproduce). For standalone battles, derive a match seed (stored on `MatchState`/`MatchData`).
- "Same seed → same flip → same opening initiative," consistent with A8's determinism rule. The animation is cosmetic and never alters the seeded outcome.

## 8. Data Model & Touch Points

- **New core:** `src/core/combat/coin_flip.gd` (`CoinFlip`); a thin `InitiativeFlip` resolver (own file or a `MatchSetup` static).
- **New UI:** `src/ui/coin_flip_overlay.gd` (+ scene) — reusable reveal animation with a `flip_finished` signal.
- **Modified core:** `MatchSetup` — stop setting opening `initiative` from SPD (remove/retire `_determine_initiative`); ensure a seed/RNG is available to the flip. `MatchState` — carry a `seed`/rng if not already present.
- **Modified scene:** `BattleController` — at the deployment→round-1 seam, resolve the flip (core), play the reveal (await), then `RoundManager.start_round`; headless path flips + starts without the view. Coordinates with A12's `DeploymentController.finish()` hand-off.
- **Data/tunables:** `constants.json` — see §9. No new authored content; no schema change.

## 9. Tunables (`constants.json`)

```
COIN_HEADS_TEAM   = "playerA"   // team that Heads favors for initiative (player); Tails → the other team
COIN_FLIP_FAIR    = true        // fair 50/50 (reserved hook for future weighting)
COIN_FLIP_DURATION = 1.2        // reveal animation seconds (skippable)
```

## 10. Relationship to Phases / Prerequisites

- **Required (MVP, complete):** Phase 4 (`MatchState`/`RoundManager`/`initiative`), Phase 7 (`MatchSetup`), Phase 8 (`BattleController`, HUD).
- **Coordinates with A12:** the flip slots into the deployment→round-1 hand-off; if A12 ships first, A13 hooks `DeploymentController.finish()`. A13 does **not** require A12 — without it, the flip runs at match start before round 1.
- **Coordinates with A8:** uses the run seed when in a run for reproducibility; standalone battles use a match seed. Not blocking.
- Independent of the content libraries and the pending class-tree engine changes.

## 11. Out of Scope / Future

- Additional coin-flip consumers (events, gambles, tie-breaks) — the service/visual are designed for reuse.
- Loaded/weighted coins or stat-influenced odds.
- Per-round or mid-battle flips; multi-coin or dice mechanics.

## 12. Requirements Traceability

| # | Requirement | Where addressed |
|---|-------------|-----------------|
| 1 | Coin-flip mechanic | §4 |
| 2 | First used for first initiative | §5 |
| 3 | Heads → player first; Tails → AI first | §5, §2 |
| 4 | Visual element + animation of the result | §6 |
| D1 | After deployment, before round 1 | §3, §2 |
| D2 | Generic reusable mechanic | §4, §6, §11 |
| D3 | Seeded by match/run RNG | §7 |
