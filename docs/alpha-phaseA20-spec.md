# Phase A20 — Multiplayer Combat: Continuous Charge-Time Clock + Skirmish Container Specification

**Parent plan:** `roadmap-A11-onward.md` (sub-phase A20)
**Master spec:** `alpha-specs.md` (combat substrate); `feature-scan-and-competitive-analysis.md` (Part 3, #4)
**Builds on (MVP):** `phase4` (`MatchState`, `RoundManager`), `phase7` (`MatchBuilder`/draft flow), `phase8` (`BattleController`, HUD)
**Builds on (Alpha):** A15 (the `TurnSystem` seam — A20 adds the second implementation), A12 (deployment), A13 (coin flip seeds opening CT ties), A7 (AI under the clock)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-30
**Status:** Draft v0.2 (revised: this is the *multiplayer* turn system + skirmish container, not an optional SP rework)

---

## 1. Purpose & Scope

Deliver the **second turn-activation model** and the container it belongs to. Where single-player uses the telegraphed speed-round (A15), the **multiplayer style of play** uses a **continuous Charge-Time (CT) clock** with **no telegraph**: units accrue CT each tick from their `SPD`, and whenever a unit's CT crosses the threshold it **acts immediately** (the controlling side plans and executes that single activation in the moment), then its CT resets. Fast units act more often; `Slowed`/`Haste` become powerful; turn order is a live, flowing resource rather than a batched round. This is the more dynamic, reactive style — and because each side reacts in real time to a hidden opponent, the perfect-information telegraph is intentionally **switched off** here.

The container for this style is **skirmish mode**: the player chooses a **squad size**, **drafts characters**, deploys (A12), and fights under the CT clock. Skirmish is the home of "two styles of play" alongside the roguelike run.

> **No networking is implemented in this phase.** A20 is **future-proofing**: it builds the CT turn system and the skirmish container so they are fully playable **locally** (vs. AI, and/or hot-seat). Actual networked multiplayer — transport, lobby, authoritative server — remains **deferred (roadmap A26)**, which will slot remote players into the same `TurnActions`/`TurnSystem` seams this phase establishes.

### In scope

- A **`ChargeTimeTurnSystem`** implementing the A15 `TurnSystem` seam: per-unit CT accrual by `SPD`, threshold activation, reset/surcharge on acting (a full action delays the next turn more than Wait), seeded tie-break (A13 flip at open).
- **Status integration**: `Slowed` reduces and `Haste` increases CT accrual; status/effect durations expressed consistently under the clock.
- **Telegraph disabled**: in skirmish/CT mode, `TelegraphService` is not engaged; opponents' intents are hidden; the AI simply acts on its activation. (`TELEGRAPH_MODE` is forced `off` for this mode.)
- **Skirmish container**: a mode entry that selects squad size, drafts characters (reuse/extend the existing draft scene), builds two parties, deploys via A12, and runs the match under `ChargeTimeTurnSystem`. Supports **vs-AI** and **local hot-seat** (both sides human on one device) now.
- **Mode plumbing**: `MatchData.mode = skirmish`; the launcher selects the CT system and the skirmish flow; the roguelike run continues to select the A15 speed-round.
- **HUD CT timeline**: an upcoming-activation forecast driven by the clock (no enemy *intent*, just *order*).
- **AI under the clock**: `AIController` plays a single activation when its unit's CT triggers; scoring accounts for tempo (when it next acts).

### Out of scope

- Network transport, matchmaking, lobbies, authoritative server, rollback — **all deferred to A26**. A20 ships local play only.
- The single-player speed-round and telegraph (A15).
- New combat math (A16–A19 apply unchanged under either turn system).
- Persistent skirmish progression/economy (skirmish uses drafted throwaway squads; the run owns persistence).

### Exit criteria

1. A match can run under **`ChargeTimeTurnSystem`**: units accrue CT from `SPD` and act on threshold; over a battle, faster units act measurably more often.
2. `Slowed`/`Haste` shift activation frequency in the expected direction; durations behave consistently under the clock.
3. **Skirmish mode** lets the player pick a squad size, draft characters, deploy, and fight a complete battle under the CT clock — **vs AI** and **hot-seat** — ending in a clear win/loss.
4. **Mode selection works end to end**: skirmish → CT system with telegraph **off**; roguelike run → A15 speed-round with telegraph **on**. The two are cleanly separated via the `TurnSystem` seam and `MatchData.mode`.
5. The HUD shows an accurate **upcoming-activation timeline** consistent with actual CT order; the A13 flip seeds round-1 ties.
6. The **AI plays competently** under the clock (legal plans, tempo-aware) with difficulty presets.
7. Headless/deterministic by seed; existing combat tests pass under both systems; no networking code is required for any of the above.
8. Tests cover CT accrual/ordering, `Slowed`/`Haste`, mode→system selection (incl. telegraph forced off), skirmish setup→deploy→battle→end, and seeded reproducibility.

---

## 2. Design Decisions

- **CT model:** `ct += effective_SPD` per tick; act when `ct ≥ CT_THRESHOLD`; on acting, `ct -= CT_THRESHOLD` plus an optional action-cost surcharge (full action > Wait), enabling deliberate tempo play. Threshold/surcharge/accrual are `constants.json` tunables.
- **Same backend, different driver.** `ChargeTimeTurnSystem` issues actions through `TurnActions` exactly as A15 does; only the *scheduling* differs. This keeps `CombatResolver` and all A16–A19 math identical across modes.
- **Telegraph off by construction.** The mode sets `TELEGRAPH_MODE = off` and never instantiates `TelegraphService`; intents are hidden, which is the whole point of the dynamic style.
- **Skirmish reuses the draft flow.** The existing draft/deploy pipeline (the MVP `draft_scene` → deploy → combat) is the natural skirmish container; A20 adds a squad-size selector and routes the built match through the CT system.
- **Determinism & the networking seam.** CT order, ticks, and ties are seeded; actions remain serializable `TurnActions` records. This is deliberately the shape A26 networking needs (authoritative state + replayable action log) without building any of it now.
- **Hot-seat as the stand-in for "multiplayer."** Until A26, "two players" means two humans on one device (or human vs AI). This proves the two-sided, no-telegraph experience end to end.

---

## 3. Architecture & Files

**New:**
- `src/core/combat/charge_time_turn_system.gd` (`ChargeTimeTurnSystem`) — CT accrual, ordering, reset/surcharge.
- `src/core/combat/turn_scheduler.gd` (`TurnScheduler`) — the CT bookkeeping the system uses (per-unit CT, next-actor query, timeline).
- `scenes/skirmish/` + `src/ui/skirmish_setup.gd` — squad-size selection and skirmish entry (wrapping the draft flow).

**Modified:**
- `src/core/combat/round_manager.gd` / `match_state.gd` — drive whichever `TurnSystem` is active (seam from A15).
- `src/autoload/match_data.gd` — `mode = skirmish`; opponent type (AI / hot-seat).
- `src/core/combat/status_*` — `Slowed`/`Haste` as CT modifiers; duration semantics under the clock.
- `src/map/ai_controller.gd` / `src/core/ai/ai_scorer.gd` — single-activation play; tempo-aware scoring.
- `src/ui/battle_hud.gd` — CT timeline widget; ensure no telegraph UI in this mode.
- `src/ui/draft_scene.gd` — squad-size parameter; route to skirmish match build.
- `data/constants.json` — `CT_THRESHOLD`, accrual/surcharge, status multipliers, skirmish squad-size bounds.

---

## 4. Implementation Outline

1. **`TurnScheduler` + `ChargeTimeTurnSystem`** behind the A15 seam; CT accrual/threshold/reset; seeded ties.
2. **Status hooks**: `Slowed`/`Haste` modify accrual; reconcile durations.
3. **Mode plumbing**: `MatchData.mode`; launcher selects CT system + forces telegraph off for skirmish.
4. **Skirmish container**: squad-size selector → draft → A12 deploy → CT battle; vs-AI and hot-seat.
5. **AI under the clock**: single-activation planning; tempo in scoring.
6. **HUD CT timeline.**
7. **Tests**: accrual/ordering, haste/slow, mode selection + telegraph-off, full skirmish loop, determinism.

---

## 5. Test Plan

- Higher `SPD` → more activations over a fixed tick window (deterministic).
- `Slowed`/`Haste` shift frequency correctly; durations consistent.
- Mode selection: skirmish → CT + telegraph forced off; run → A15 speed-round + telegraph on.
- Skirmish setup → deploy → battle → win/loss, both vs-AI and hot-seat.
- A13 flip seeds round-1 CT ties; timeline forecast matches actual order.
- A16–A19 resolution identical under CT and speed-round (mode-agnostic math regression).
- Seeded reproducibility; no networking dependencies.

---

## 6. Forward Hooks (deferred A26 — Networked Multiplayer)

A20 establishes everything networking will reuse: a single authoritative `MatchState`, serializable `TurnActions` records, a seeded deterministic clock, and the `TurnSystem` seam. **A26** will add transport/lobby/authoritative validation and slot remote players into the same interface `AIController` and the hot-seat human already use — no combat-core changes expected.
