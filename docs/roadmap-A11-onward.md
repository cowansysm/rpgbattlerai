# RPG Battle Simulator — Roadmap (Phase A11 onward)

**Engine:** Godot 4.6.3 (do not auto-upgrade)
**Source specs:** `alpha-specs.md`, plus per-phase `alpha-phaseA<N>-spec.md` / `alpha-phaseA<N>-implementation-plan.md`
**Builds on:** the completed MVP (Phases 0–11) and Alpha **A0–A10** (implemented, tested, merged to `development`)
**Format:** High-level phased milestones (mirrors `alpha-implementation-plan.md`)
**Date:** 2026-06-30

This roadmap picks up where `alpha-implementation-plan.md` stops (A10). Phases **A11–A14**
already have detailed specs and implementation plans (currently *Draft*, not yet built);
they are sequenced here with their dependencies and exit criteria. Phases **A15+** are
**proposed** forward-looking milestones for planning — goals and provisional exit criteria,
to be expanded into full specs as they are scheduled.

As in the MVP and Alpha, each sub-phase ends in a demonstrable state with tests, and content
authoring layers on continuously rather than waiting for a single phase.

---

## Status snapshot

- **Done & merged:** MVP Phases 0–11; Alpha A0–A10.
- **Specced, not built (this roadmap):** A11–A14 (*Draft* specs + implementation plans) and A15–A20 (*Draft* specs) — A15 commits enemy-intent telegraphing as the core mechanic; A16–A20 close the partial/absent combat baseline.
- **Authored, blocked on engine changes:** expanded content libraries in `data/csv/`
  (268 classes, 787 abilities, 160 characters, 32 races, 128 items) cannot be imported until
  the validator/schema changes land — folded into **A11** as a prerequisite (see below).
- **Pending code-change notes:** `class-tree-engine-changes.md` (n-tier class model),
  `content-pipeline-pending-changes.md` (`area.length` / `area.depth` schema columns).

---

## Phase A11 — Encounters, Level Scaling & Economy Refinement

**Goal:** The run is monster-heavy and level-appropriate, built on a single scaling curve, and
the early economy is re-tuned around a fixed starting purse.

Reinterpret authored character stats as **base (level-1) stats** and introduce a single
`LevelScaler` that projects any character — player or monster — to a target level via its class
`growth`, collapsing most balance into one curve. Add the **encounters dataset**
(`data/encounters.json`: named opposing bands with a `min_band_level` gate, an enemy roster, an
optional map id, and optional modifiers) and wire it into encounter generation so monster bands
fight at the **band level** (the average character level of the band). Define a character's level
as the **sum of its class levels**, with the level curve setting each next-level XP threshold.
Refine the economy: new bands start with **1 Human Vagabond (L1) + 500 gp**, recruit cost **50 gp**,
combat gold ≈ **50 × band level**, equipment prices rebalanced around the 500 gp start; split shops
into a **base shop** (band screen, all lower-tier gear) and **run-mode shops** (specialized/premium,
run-only). Restrict drafting to **Human / Dwarf / Elf / Halfling**, each starting as an L1 Vagabond.
Add dev-flag-gated test tools (set band/character level, grant gold/items, force-spawn encounters).

**Prerequisite folded into this phase — unblock the expanded content libraries.** A11's scaling and
encounters reference the larger class/ability/character/race/item libraries already authored in
`data/csv/`. Before (or as the first task of) A11, land the two pending engine changes so the CSVs
import and validate: (1) move the validator and class schema from the 4-tier model to the **n-tier
(0–9) class model** (`class-tree-engine-changes.md`), and (2) add the `area.length` / `area.depth`
columns to `entity_schema.gd` so `line` / `cone` abilities round-trip (`content-pipeline-pending-changes.md`).
Then import the expanded CSVs into the live JSON and confirm the full set passes validation at boot.

**Exit when:** the expanded content libraries import and validate at boot; character stats are base
stats and `LevelScaler.scale(character, level)` produces sensible stats at any level; `encounters.json`
loads and validates (real character/map refs, `min_band_level ≥ 1`); the system can select an eligible
encounter for a band level and field its enemies scaled to that level on the encounter's map; and
band level = average character level, with combat gold averaging ≈ 50 × band level.

---

## Phase A12 — Interactive Deployment Zones

**Goal:** Pre-battle placement becomes a meaningful, replayable decision instead of a hardcoded slotting.

Replace `Deployment.auto_deploy()` (which slots `units[i] → zone_tiles[i]` and immediately advances to
`ROUND_START`) with a **deployment phase driver** (`DeploymentController`): per-team queues of undeployed
units, legal-tile computation within each zone, and **one-at-a-time alternating placement**. The
**AI-controlled team places first**, then the human, alternating one pawn each; the larger side places its
remainder at the end; placement is **locked on commit** (no undo/reposition). Add an AI **`DeploymentPlanner`**
heuristic (front/back by role, prefer cover and high ground, avoid hazard tiles, light anti-clustering) that
also serves the headless / AI-vs-AI / test path. Build the deployment **UI** in the map scene (zone
highlighting, next-pawn preview, click-to-place, AI pacing, live pawn spawning, auto-start on completion) and
a **zone-size pre-check** so a party larger than its zone fails clearly.

**Exit when:** starting a battle enters an interactive DEPLOYMENT phase; the AI deploys first and sides
alternate one pawn each with the larger party finishing its remainder; the human places by clicking legal
tiles in their own zone (illegal tiles rejected); the AI places sensibly via the role/terrain heuristic; all
units placed → `ROUND_START` and normal play; `auto_deploy` slotting is gone (AI/headless deploy via the
planner); and headless tests cover legal-tile rules, alternation/ordering, completion, and planner placement.

---

## Phase A13 — Coin Flip & Opening Initiative

**Goal:** A fair, seeded, visually revealed coin flip decides opening initiative — built as a reusable mechanic.

Add a generic **`CoinFlip` service** (`flip(rng) -> {HEADS, TAILS}`, fair 50/50, seeded by an injected RNG for
reproducibility) and a **reusable coin-flip visual** that illustrates a pre-computed result (core decides; the
animation lands on that side), emits a finished signal, and is skippable. Integrate it at the
**deployment → round-1 seam**: replace the silent SPD-based opening determination
(`MatchSetup._determine_initiative`) with a flip — **Heads → player (`playerA`) acts first, Tails → AI
(`playerB`)** — derived from the match/run seed. Leave the per-round initiative flip (`RoundManager`) untouched.
Build it generic so later systems (event nodes, tie-breaks, gambles) reuse the same service and visual.

**Exit when:** `CoinFlip` returns Heads/Tails fairly and deterministically for a seeded RNG; at battle start
(after deployment, before round 1) the coin is flipped and animated; Heads sets player initiative and Tails sets
AI, then round 1 begins with that team first; the animation always lands on the computed side and round 1 waits
for the (skippable) reveal; headless/test contexts flip and start deterministically without animation; the old
SPD-based opening determination no longer sets initiative; and tests cover seeded determinism, Heads/Tails→team
mapping, and the deployment→flip→round-1 sequence.

---

## Phase A14 — Ability Symbol Pawns (Physics Drop Feedback)

**Goal:** Ability/attack resolution gets clearer, more tactile feedback via physics-dropped symbol tokens.

When an ability or attack resolves, spawn a small 3D **`AbilitySymbolPawn`** (`RigidBody3D`) bearing the
ability's icon **beside each affected target** (elevation-aware, one per target for single- and multi-target/AoE),
let it **fall under real physics**, settle and **dwell** a few seconds, then **sink out of sight** and free itself
(no leaks). Add a **symbol resolver** with a fallback chain (ability id → element → effect type → generic) so any
of the 700+ abilities yields a sensible icon, plus a small set of generic fallback atlas cells. Add a **brief
blocking beat** so the acting step waits until the pawn(s) land (capped by a max-wait) before continuing, focusing
attention on the result and the event-log entry. This **replaces the billboard `ActionMarker`** for ability/attack
feedback; dice and status markers are unchanged.

**Exit when:** resolving an ability drops a symbol pawn beside each target with the right icon (or fallback); pawns
fall under physics, land on the target tile surface, dwell, then sink and free; the step pauses briefly until landing
(capped) and resumes after the last pawn lands; the billboard `ActionMarker` is retired for ability/attack feedback
while dice/status markers still work; symbol resolution yields an icon for every ability; and headless contexts skip
the visual with no effect on combat outcomes.

---

## Direction set: Two styles of play + combat-baseline completion (A15–A20)

This direction commits **two styles of play** behind one pluggable `TurnSystem` seam, plus the combat-math
features that make both styles whole:

- **A15** — single-player **telegraphed speed-round** (perfect information; the identity-defining SP mechanic) and
  the `TurnSystem` architecture.
- **A20** — multiplayer **continuous Charge-Time clock** + **skirmish container** (telegraph off; local play now,
  networking deferred to A26).
- **A16–A19** — close every **partial or absent combat baseline** piece surfaced by the code scan
  (`feature-scan-and-competitive-analysis.md`); these are **turn-system-agnostic** and resolve identically in both
  modes, with A15's telegraph surfacing them in single-player.

All six have full specs (`alpha-phaseA15-spec.md` … `alpha-phaseA20-spec.md`).

> **Numbering note:** these concrete phases supersede the earlier *placeholder* A15–A20 proposals
> (player-facing editor, richer events, audio, deeper AI, save robustness, multiplayer). Those remain
> valid future work and are renumbered to the **Deferred backlog (A21+)** below.

> **Baseline already covered elsewhere:** multi-tile **AoE application** is *already implemented* in
> `turn_actions._collect_affected_units` (burst/line/cone/ring); its only gap is the import schema
> (`area.length`/`area.depth`), owned by **A11**. So AoE gets no phase of its own — A16 only adds a
> verification test. A minor **equipment stat-bonus** resolution test gap is folded into A16's regression
> suite.

### Mode-dependent turn activation (decided)

Turn activation now depends on **game mode**, and the two modes are the game's two styles of play:

- **Single-player → roguelike run (A8 container):** a **telegraphed speed-round** (WeGo). The AI commits and
  telegraphs all its actions → the player plans all of his units against that full information → every action
  resolves in **`SPD` order** → the round resets. Telegraphing is the core single-player mechanic. **(A15)**
- **Multiplayer → skirmish (squad-size pick + draft):** a **continuous Charge-Time clock**, telegraph **off** —
  units act when their `SPD`-driven CT crosses threshold. The dynamic, reactive style. **(A20)** *No networking is
  built yet — skirmish is playable locally (vs-AI / hot-seat); networked play is deferred to A26.*

A **`TurnSystem` seam** (introduced in A15) makes the activation model pluggable; `MatchData.mode` selects it.
The combat-math phases **A16–A19 are turn-system-agnostic** — they resolve identically under either mode.

### Phase A15 — Single-Player Combat: Telegraphed Speed-Round + Turn-System Architecture *(specced)*

**Goal:** Build the pluggable `TurnSystem` seam and the single-player **telegraphed speed-round**: (1) AI commits
+ telegraphs every unit's intended move/action/target with projected outcome ranges (d6 stays, so outcomes are
ranges, intent is exact); (2) the player plans **all** his units against full information; (3) all actions resolve
**one unit at a time in `SPD` order**, so a fast unit can interrupt a telegraphed-but-slower enemy; (4) round
resets. Single plan source (`AIPlanner`/`AIScorer`) so telegraph == execution; a resolution-time validity policy
governs plans whose target/path changed (fizzle / stop-short / ground-AoE-hits-occupant).
**Exit:** see `alpha-phaseA15-spec.md` — turn-system selection by mode, four-stage sequencing, `SPD` resolution
order, validity/interrupt policy, range projection, Full/Targets-only/Off disclosure dial, deterministic headless round.

### Phase A16 — Elemental Affinities & Critical Hits *(specced)*

**Goal:** Add the two missing damage-math features — element weakness/resistance/immunity/absorb (abilities
already carry `effect.element`, but `resolve_damage` ignores it) and critical hits — feeding A15's ranges.
**Exit:** affinity scales element damage and stacks across sources; crits apply and flag; neutral/no-crit
defaults reproduce current numbers; A15 projection reflects both. (`alpha-phaseA16-spec.md`)

### Phase A17 — Knockout & Revive Lifecycle *(specced)*

**Goal:** Wire the scattered KO/revive pieces (`resolve_revive`, downed HP, `DeathModel`/`DOWN_LIMIT`) into one
coherent **down → revive → run-permadeath** flow with the matching battle UX. **Exit:** formal downed state
(leaves queue, stays on board, not counted living), revive only on downed allies, correct victory/permadeath
handoff, HUD + log + telegraphed revive targets. (`alpha-phaseA17-spec.md`)

### Phase A18 — Reaction / Support / Movement Passives *(specced)*

**Goal:** Add FFT-style passive slots (one each: reaction / support / movement) learned via JP — Counter,
Auto-Potion, +1 Jump, Half WP, etc. — through one typed trigger-dispatch seam, with AI/telegraph awareness of
known reactions. **Exit:** learn/equip/persist passives; each seed passive triggers correctly; no-passive
baseline unchanged; AI avoids known Counters. (`alpha-phaseA18-spec.md`)

### Phase A19 — Facing & Flanking *(specced)*

**Goal:** Add 6-direction unit facing and front/flank/rear attack bonuses (hit/damage/crit), set on deploy and
updated on move; feeds A15 projection and AI positioning. **Exit:** deterministic arc classification, arc
bonuses applied, front-attack regression baseline, facing indicators, AI flank-seeking. (`alpha-phaseA19-spec.md`)

### Phase A20 — Multiplayer Combat: Continuous Charge-Time Clock + Skirmish Container *(specced)*

**Goal:** Deliver the **second** turn system and its container. A `ChargeTimeTurnSystem` (behind the A15 seam):
units accrue CT from `SPD` and act on threshold (`Slowed`/`Haste` change frequency), with the **telegraph off** —
the dynamic, hidden-intent style. The container is **skirmish mode**: pick a squad size, draft characters, deploy
(A12), and fight under the clock. **No networking is built here** — skirmish runs locally (vs-AI / hot-seat) as
future-proofing for two styles of play; networked transport/lobby/authoritative server is **deferred to A26**,
reusing the deterministic `TurnActions` log + `TurnSystem` seam this phase establishes.
**Exit:** CT accrual/ordering, haste/slow, mode→system selection (skirmish = CT + telegraph off; run = A15
speed-round), full skirmish setup→deploy→battle loop vs-AI and hot-seat, A16–A19 math identical across modes,
seeded determinism. See `alpha-phaseA20-spec.md`.

---

## Deferred backlog (A21+) — forward-looking, not yet specced

Renumbered from the earlier placeholders; each attaches to an audited seam (`seam-audit.md`) and can be
scheduled independently once the A15–A20 combat work lands.

- **A21 — Player-Facing Map Editor:** re-skin the UI over the unchanged headless `MapEditorModel`; save under `user://`.
- **A22 — Richer Narrative Events & Coin-Flip Gambles:** event chaining, more effect types, gamble/tie-break nodes reusing the A13 `CoinFlip`.
- **A23 — Audio, Music & Game Feel:** SFX/music tied to A14 symbol pawns and A15 telegraph beats; mixer + options.
- **A24 — Deeper AI & Difficulty:** multi-unit coordination / lookahead beyond per-activation scoring (and tempo-aware if A20 ships).
- **A25 — Save Robustness, Options & Onboarding:** migration/corruption tests, save slots, options menu, first-run guidance.
- **A26 — Networked Multiplayer *(stretch / Beta)*:** add transport/lobby/authoritative validation to the **skirmish** container and `ChargeTimeTurnSystem` built in A20; remote players reuse the deterministic `TurnActions` log and the `TurnSystem`/`AIController` interfaces. A20 ships skirmish playable locally (vs-AI / hot-seat); A26 only adds the network layer.

**Larger signature/replayability ideas** noted in the competitive analysis but not yet phased: build-defining
run **relics**, a Disgaea-style **Item World** (reusing the A8 run graph), **capture/persuade** recruitment,
character **reincarnation/prestige**, and **daily seeded** runs. Promote into the A21+ sequence as desired.

---

## Dependency Summary

```
A10 (done) ─> A11 (content import + scaling + encounters + economy)
                 │
                 ├─> A12 (interactive deployment) ─> A13 (coin-flip opening initiative)
                 │
                 └─> A14 (ability symbol pawns; independent visual layer)

Two turn systems behind one TurnSystem seam (introduced in A15):
  A7 (AIPlanner/Scorer) ──> A15  Single-player: telegraphed SPEED-ROUND (run container)  ◄── core SP mechanic
  A13 + A15 seam ───────> A20  Multiplayer: continuous CHARGE-TIME clock + SKIRMISH (telegraph off, local only)
                                 └─ networking deferred ──> A26

Mode-agnostic combat math (resolve identically under both turn systems; A15 telegraph surfaces them in SP):
  A11 schema + A3 magic ─> A16 (elemental affinities & crits)
  A5/A8 death ──────────> A17 (KO/revive lifecycle)
  A4 JP/abilities ──────> A18 (reaction/support/movement passives)
  A12 deploy ───────────> A19 (facing & flanking)

Deferred backlog: A21 editor · A22 events · A23 audio · A24 deeper AI · A25 save/options · A26 net-multiplayer
```

**Critical path:** **A11 → A12 → A13** (as before), then **A15 first** — it introduces the `TurnSystem` seam and
the single-player telegraphed speed-round (the core SP mechanic). **A16–A19** follow in parallel behind it: each is
an independent, turn-system-agnostic combat-math/positioning addition that A15's projection surfaces in
single-player and that resolves unchanged under A20's clock. Sequence them by value — A16 (elements/crits) and A19
(facing) give the most immediate texture; A17 (KO/revive) and A18 (passives) add depth. **A20** can be built any
time after the A15 seam exists; it adds the multiplayer Charge-Time system and the skirmish container (local play
now, networking at A26). The A21+ backlog attaches to existing seams and can follow in any order.
