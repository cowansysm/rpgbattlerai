# Phase A7 — AI Opponent Specification

**Parent plan:** `alpha-implementation-plan.md` (Phase A7)
**Master spec:** `alpha-specs.md` (§11 AI Opponent)
**Builds on (Alpha):** `alpha-phaseA0-spec.md` (terrain effects the AI weighs), `alpha-phaseA5-spec.md` (band as opponent in quick battle)
**Builds on (MVP):** `phase4`/`phase5` (`TurnActions`, `RoundManager`, `MatchState`, `BattleController`), `phase3` (`Movement`, `RangeQuery`, `LineOfSight`, `HexGraph`)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-17

---

## 1. Purpose & Scope

Phase A7 adds the **tactical AI** that controls enemy units in single-player. The bar is **"basic but competent, with variance"**: the AI should use the map and its kit sensibly — threaten the player, prefer good positions, target the right enemies — yet remain beatable and visibly imperfect. It is the last system the roguelike run (A8) needs before the loop closes.

The defining architectural rule (master-spec §11.1): the AI is a **peer of the human `BattleController`** and acts **only through the same `TurnActions` backend**. It has no privileged powers — only the legal action surface and the shared `MatchState`. This keeps all combat rules in one place and guarantees the AI cannot do anything a player couldn't.

### In scope

- A **pure, testable `AIPlanner`** (in `src/core/ai/`) that, given a `MatchState` and the active unit, enumerates legal candidate plans, **scores** them with a utility heuristic, and **selects** one with controllable variance.
- A scene-level **`AIController`** that, on an AI team's activation, gets a plan and **executes it through `TurnActions`**, then ends the activation — paced for readability.
- A **utility scorer** weighing damage dealt/taken, positioning (cover/elevation/hazard from A0), target priority, ability value, and AP/WP economy.
- **Variance & difficulty**: sample among the top-N scored plans with a temperature parameter; difficulty presets; **seeded RNG** for reproducibility.
- Wiring the AI as the opponent in the A5 quick-battle-from-band, ready for A8 run battles.

### Out of scope

- **Multi-turn look-ahead, team coordination, learned/ML behavior** — designated extension points (master-spec §11.4). A7 is single-activation, greedy-with-variance.
- **The run / encounter generation** (Phase A8) — A7 makes the AI available; A8 fields enemy bands with it.
- **New abilities/content** (A9); the AI works with whatever kit a unit has.
- **Player-side automation** — the human `BattleController` is unchanged.

### Exit criteria

Phase A7 is complete when:

1. On an AI team's activation, the `AIController` plays a full activation — move and/or attack/ability/defend — **using only `TurnActions`** and then ends the turn.
2. The AI behaves sensibly: prefers cover/higher ground and avoids hazard tiles (A0), focuses vulnerable targets (low-HP, casters), heals/buffs when valuable, and doesn't waste AP/WP.
3. **Variance** is observable: the AI does not always pick the top-scored plan; difficulty presets visibly change its optimality; a fixed seed makes a battle reproducible.
4. A full battle plays **human vs AI** to a victory condition without the AI stalling or acting illegally.
5. The `AIPlanner` is covered by headless tests (deterministic under a fixed seed; only-legal actions); a manual human-vs-AI battle checklist passes.

---

## 2. Design Decisions (Phase A7)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Planner / controller split** | A pure `AIPlanner` (core, no scene tree) returns an `AIPlan`; a scene-level `AIController` executes it via `TurnActions`. | Mirrors the MVP core/UI split and the A1 editor model/scene split; the planner is unit-testable, the controller handles timing. |
| **Legal surface only** | The AI calls `TurnActions.execute_*` exactly as the player does; it reads shared `MatchState` but gets no hidden info or special powers. | Keeps combat rules single-sourced; the AI is provably "fair." |
| **Greedy with variance** | Single-activation planning: enumerate candidate plans for this turn's 2 AP, score, sample among the top-N. No multi-turn search. | Meets the "basic but competent" bar cheaply; the scorer/enumerator are the seams for smarter AI later. |
| **Bounded enumeration** | Prune the candidate space (cap considered move destinations, target sets) for tractability on MVP-size maps. | Keeps per-activation cost low and deterministic; avoids combinatorial blowup. |
| **Utility scoring** | A weighted sum over expected damage, exposure/positioning, target value, ability value, and resource economy. | Transparent, tunable, and good enough to read as competent play. |
| **Variance via top-N + temperature** | Select from the N best plans weighted by a temperature/ε; difficulty presets set N/temperature/breadth. | Delivers the requested "variance in optimality" and a difficulty dial. |
| **Seeded RNG** | The planner takes an injected RNG (seeded from the run in A8; fixed in tests). | Reproducible battles for debugging and deterministic tests. |
| **Reuse spatial systems** | Candidate enumeration uses `Movement.reachable`, `RangeQuery`, `LineOfSight`, and the A0 `HexGraph` effects. | No new spatial code; the AI "sees" exactly what the rules expose. |

---

## 3. The AI Plan & Action Model

### 3.1 `AIPlan`

An ordered list of **steps** the controller will execute this activation, each a legal `TurnActions` call:

```
AIStep := { kind: "move"|"attack"|"ability"|"defend"|"wait"|"use_item",
            target_pos: Vector2i,        # for move/attack/ability/item
            ability_id: String,          # for ability
            item_id: String }            # for item
AIPlan := Array[AIStep]                  # fits within the unit's 2 AP
```

A plan respects AP/WP exactly as `TurnActions` would validate it; the controller still checks each call's result and stops gracefully on any rejection.

### 3.2 Candidate enumeration

For the active unit (2 AP), the planner enumerates a **bounded** set of candidate plans, e.g.:

- **Reachable tiles** via `Movement.reachable` (optionally capped to the most promising by proximity to enemies / cover).
- For each (origin or reachable tile), the **legal attacks/abilities** against valid targets (`RangeQuery` + `LineOfSight`, min-range and friendly-fire rules already enforced by `TurnActions`).
- Composite 2-AP plans: `move→attack`, `attack→move`, `attack→attack`, `move→ability`, `ability(2AP)`, plus `defend` and `wait` as fallbacks.

Enumeration only produces **legal** candidates (it pre-checks with the same range/LoS/AP rules), so execution should never be rejected except on benign races.

---

## 4. Utility Scoring

Each candidate plan is scored by a weighted utility function over its **predicted end state**:

| Factor | Intent |
|--------|--------|
| **Damage dealt / kills** | Reward expected damage; weight kills (removing a unit) higher. Uses the resolution model (incl. A3 magic) for expected values. |
| **Damage taken / exposure** | Penalize ending in the open, in enemy range, or on hazard terrain; reward **cover** and **higher elevation** (A0 `HexGraph` cover/elevation, hazard `damage_*`). |
| **Target priority** | Prefer low-HP enemies (finish them) and high-value targets (casters/support). |
| **Ability value** | Reward heals when allies are hurt, buffs when impactful, AoE on clusters; avoid overhealing/wasted casts. |
| **Resource economy** | Penalize spending WP/AP for little gain; value `Defend` when threatened with no good offense. |

Weights are tunable constants. The scorer is deterministic given a state and plan (expected-value based; the dice randomness lives in resolution, not the score).

---

## 5. Selection & Variance

To avoid robotic optimality (master-spec §11.3):

- Rank candidates by score; take the **top-N** (`AI_TOP_N`).
- Select among them by a **temperature/ε** weighting (`AI_TEMPERATURE`) using the injected RNG — higher temperature flattens toward random, lower sharpens toward optimal.
- **Difficulty presets** (`AI_DIFFICULTY`) set `top_n`, `temperature`, and optionally enumeration breadth: e.g., *easy* (wide N, high temperature, narrow search), *normal*, *hard* (small N, low temperature, broader search).
- The RNG is **seeded** (from the run seed in A8), so a battle replays identically for debugging.

---

## 6. The `AIController` (Driver)

A scene-level peer to `BattleController`:

1. The battle flow detects that the **current activation's team is AI-controlled** (e.g., the opponent band in single-player).
2. The controller calls `AIPlanner.plan(state, unit, rng, difficulty)` to get an `AIPlan`.
3. It **executes each step** via the matching `TurnActions.execute_*`, checking the returned dict for `error` and stopping gracefully if a step becomes illegal.
4. It paces steps for readability (reusing the existing animation/marker timing the human path uses) and surfaces outcomes to the HUD/combat log identically.
5. It calls `RoundManager.end_activation(state)` to pass the turn.

The controller holds **no game logic** beyond sequencing the plan — all rules stay in `TurnActions`/`CombatResolver`. Which teams are AI-controlled is a match-level flag (set by quick-battle and, later, the run).

---

## 7. Integration & Reproducibility

- **Quick battle (A5):** the opponent band is marked AI-controlled; the `AIController` drives its activations. This is the A7 proving ground and the path A8 reuses for run battles.
- **Turn routing:** when the active team is AI, control routes to `AIController` instead of waiting for human input; when it's the human team, `BattleController` behaves exactly as today.
- **Reproducibility:** the planner's RNG is injected; with a fixed seed and identical state, plans are deterministic, enabling replay and tests.

---

## 8. Data Model & Touch Points

- **New (core):** `src/core/ai/ai_planner.gd` (enumerate/score/select), `ai_scorer.gd` (utility), `ai_plan.gd` (step types) — pure, scene-tree-free.
- **New (scene):** `src/map/ai_controller.gd` — executes plans via `TurnActions`, paces, ends activation.
- **Modified:** the battle flow (`BattleController`/match scene) routes AI teams to `AIController`; `MatchState`/match setup carries an "AI teams" flag.
- **Reused:** `Movement`, `RangeQuery`, `LineOfSight`, `HexGraph` (incl. A0 effects), `CombatResolver` expected-value helpers.
- **Tunables:** `AI_TOP_N`, `AI_TEMPERATURE`, `AI_DIFFICULTY` (+ scorer weights) (alpha-specs §11.5).

---

## 9. Risks & Notes

- **Enumeration cost.** Unbounded move×target enumeration can blow up; cap candidate tiles/targets and profile on the largest maps.
- **Stalling/loops.** The plan must always make progress or end the turn; guarantee a `wait`/`defend` fallback so the AI never hangs an activation.
- **Illegal-step races.** Even pre-checked plans can be invalidated by an earlier step; always inspect each `TurnActions` result and abort the plan cleanly.
- **Determinism leaks.** Any global `randi()` in the planner breaks reproducibility — route all randomness through the injected RNG.
- **Heuristic myopia.** Greedy scoring can make locally good, globally poor moves; acceptable for A7, and the scorer/enumerator are the documented seams for lookahead later.
- **Difficulty legibility.** Presets must produce a felt difference; validate by playing each preset.
- **Scope creep.** No lookahead, coordination, learning, run wiring beyond quick battle, or new content.

---

## 10. Phase A7 Deliverables Checklist

- [ ] `AIPlan`/`AIStep` model; `AIPlanner` enumerates bounded, **legal-only** candidate plans for the active unit (§3).
- [ ] `AIScorer` utility over damage, exposure/positioning (cover/elevation/hazard from A0), target priority, ability value, economy (§4).
- [ ] Selection with top-N + temperature; difficulty presets; injected seeded RNG (§5).
- [ ] `AIController` executes plans via `TurnActions` only, paced and logged like the human path, then `end_activation` (§6).
- [ ] Battle flow routes AI teams to `AIController`; quick-battle-from-band fields an AI opponent (§7).
- [ ] Tunables (`AI_TOP_N`, `AI_TEMPERATURE`, `AI_DIFFICULTY`, scorer weights) in `constants.json` (§8).
- [ ] Headless planner tests (deterministic under fixed seed; only-legal actions; sensible target/positioning choices); manual human-vs-AI battle checklist.
- [ ] Git tag `alpha-phaseA7-complete`.
