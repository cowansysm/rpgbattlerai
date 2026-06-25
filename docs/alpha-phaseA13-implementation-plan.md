# Phase A13 — Implementation Plan

**Source spec:** `alpha-phaseA13-spec.md`
**Builds on (MVP):** `phase4` (`MatchState`, `RoundManager`, `initiative`), `phase7` (`MatchSetup`), `phase8` (`BattleController`, HUD/markers)
**Coordinates with (Alpha):** A12 (deployment→round-1 seam), A8 (run seed)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-06-24

---

## How to use this plan

Five **work groups** (A–E):

- **A — Coin flip core** is the generic, seeded service (pure; unblocks all).
- **B — Initiative integration** wires the flip into opening initiative and the deployment→round-1 seam.
- **C — Coin flip visual** is the reusable reveal animation that lands on the computed side.
- **D — Scene wiring** sequences deployment → flip → reveal → round 1 (and a headless path).
- **E — Tests & verification** locks determinism, mapping, and sequencing.

Each task lists a **done state**. A is `RefCounted` core (no scene tree); C is a reusable UI scene. Decision recap: **after deployment, before round 1**; **generic reusable**; **seeded**; **Heads → player (`playerA`), Tails → AI (`playerB`)**; fair 50/50; the **animation illustrates a pre-computed result**.

> **Carry-over:** reuses `MatchState.initiative` + `RoundManager.start_round` (round 1), the match/run **seed** (A8), and the HUD/`CanvasLayer` from phase 8. Coordinates with A12's `DeploymentController.finish()` hand-off (the flip is inserted between deployment completion and `start_round`).

---

## Group A — Coin Flip Core

*Pure `RefCounted`. Unblocks B–E.*

### A1. `CoinFlip` service
- `flip(rng) -> Side {HEADS, TAILS}`, fair 50/50 from an injected seeded RNG; `side_name(side)` helper. No global `randi()`.
- **Done:** repeated flips on a fixed-seed RNG reproduce the same sequence; ~50/50 over many flips.

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

### A2. Seed access
- Ensure a seeded `RandomNumberGenerator` is reachable at match start: thread the run seed (A8) when in a run, else derive/store a match seed on `MatchState`/`MatchData`.
- **Done:** the flip can be performed deterministically given the match/run seed.

---

## Group B — Initiative Integration

*Depends on A.*

### B1. `InitiativeFlip` resolver
- `resolve(state, rng) -> int`: `side = CoinFlip.flip(rng)`; set `state.initiative = COIN_HEADS_TEAM ("playerA")` if HEADS else the other team; return `side` for the view.
- **Done:** Heads → `playerA` initiative, Tails → `playerB`; returns the side.

```gdscript
# src/core/combat/initiative_flip.gd
class_name InitiativeFlip
extends RefCounted

static func resolve(state: MatchState, rng: RandomNumberGenerator) -> int:
    var side := CoinFlip.flip(rng)
    var heads_team := Constants.COIN_HEADS_TEAM            # "playerA"
    state.initiative = heads_team if side == CoinFlip.Side.HEADS else state.other_team(heads_team)
    return side
```

### B2. Retire SPD-based opening determination
- `MatchSetup`: stop pre-setting `initiative` from team SPD (remove/retire `_determine_initiative`); `MatchSetup.create` leaves `initiative` unset until the flip resolves.
- **Done:** opening initiative is set only by `InitiativeFlip`; the per-round `RoundManager` flip is unchanged.

---

## Group C — Coin Flip Visual

*Depends on A (Side enum). Reusable.*

### C1. Reveal overlay
- `coin_flip_overlay` (HUD `CanvasLayer` scene): `play(side, caption)` spins/flips and **lands on `side`**, shows the caption, emits `flip_finished`; tunable `COIN_FLIP_DURATION`.
- **Done:** calling `play(HEADS, "...")` always settles on heads and signals when done.

```gdscript
# src/ui/coin_flip_overlay.gd
extends CanvasLayer
signal flip_finished
func play(side: int, caption: String) -> void:
    # animate spin; force final frame/orientation to `side`; show caption; then:
    # await anim; emit_signal("flip_finished")
    ...
```

### C2. Skip + result caption
- Click/confirm fast-forwards to the settled result; caption text supplied by the caller (initiative passes "Heads — You go first!" / "Tails — Enemy goes first.").
- **Done:** the reveal is skippable and content-agnostic (reusable by future consumers).

---

## Group D — Scene Wiring

*Depends on A–C. Coordinates with A12.*

### D1. Deployment → flip → round-1 sequence
- At the deployment-complete seam (A12 `DeploymentController.finish()` or match-start without A12): call `InitiativeFlip.resolve(state, rng)`; play the overlay with the matching caption; on `flip_finished`, call `RoundManager.start_round(state)`.
- **Done:** the battle pauses on the reveal, then round 1 begins with the flipped team acting first.

### D2. Headless / test path
- A non-visual path resolves the flip and starts the round immediately (no overlay), used by AI-vs-AI/headless/tests.
- **Done:** headless battles set initiative by seed and proceed without UI.

---

## Group E — Tests & Verification

### E1. Core tests (GUT)
- `CoinFlip.flip` is deterministic per seeded RNG; distribution ~50/50 over N; `side_name` mapping.
- **Done:** green.

```gdscript
# tests/core/combat/test_coin_flip.gd
func test_determinism():
    var a := _seeded(7); var b := _seeded(7)
    for _i in range(20): assert_eq(CoinFlip.flip(a), CoinFlip.flip(b))
```

### E2. Initiative tests (GUT)
- `InitiativeFlip.resolve`: HEADS → `playerA`, TAILS → `playerB`; same seed → same initiative; SPD no longer influences the opening; per-round flip still alternates afterward.
- **Done:** green.

### E3. Sequencing test (GUT)
- Deployment completion resolves the flip before `start_round`; headless path sets initiative and starts round 1 without the overlay.
- **Done:** green.

### E4. Manual checklist
- [ ] After deployment, a coin-flip animation plays and lands on the result.
- [ ] Heads → player acts first; Tails → AI acts first in round 1.
- [ ] The reveal is skippable; round 1 doesn't start until it resolves.
- [ ] Same seed reproduces the same flip/initiative.
- **Done:** checklist passes.

---

## Dependency Map

```
A (coin flip core + seed) ──┬──> B (initiative integration) ──┐
                            └──> C (reveal visual) ───────────┼──> D (scene wiring) ──> E (tests)
                                                              │   (A12 finish() seam)
B ────────────────────────────────────────────────────────────┘
```

**Suggested first pass:** A1–A2 → E1 → B1–B2 → E2 → C1–C2 → D1–D2 → E3–E4. Lock the seeded core + initiative mapping (with tests) before the visual and scene wiring.

---

## Phase A13 Definition of Done

- [ ] `CoinFlip` generic service: fair, seeded, deterministic `HEADS`/`TAILS` (A).
- [ ] `InitiativeFlip` sets opening initiative — **Heads → playerA, Tails → playerB**; SPD-based opening determination retired; per-round flip unchanged (B).
- [ ] Reusable coin-flip overlay animates to the computed side, shows a caption, is skippable, signals completion (C).
- [ ] Sequence wired: deployment-complete → flip → reveal → `start_round`; headless path flips + starts without UI (D).
- [ ] `COIN_*` tunables in `constants.json`; core/initiative/sequencing tests green; manual checklist passed (E).
- [ ] Git tag `alpha-phaseA13-complete`.
