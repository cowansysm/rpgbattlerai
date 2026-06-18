# Phase A8 — Roguelike Run Framework Specification

**Parent plan:** `alpha-implementation-plan.md` (Phase A8)
**Master spec:** `alpha-specs.md` (§8 Single-Player: The Roguelike Run)
**Builds on (Alpha):** A4 (instances, `downs_this_run`), A5 (`BattleBand`, `SaveManager.active_run`, party-from-instances, `MatchData`), A6 (`LootRoller`, `ShopService`, `grant_rewards`), A7 (`AIController` opponent)
**Builds on (MVP):** `phase7` (`MatchBuilder`), `phase4`/`phase5` (`MatchState`, `RoundManager`), `phase9`-style match-flow
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-17

---

## 1. Purpose & Scope

Phase A8 is where the Alpha becomes a **game you can play solo, start to finish**. It composes A4–A7 into the **roguelike run**: a band embarks, traverses a **branching graph of nodes** of escalating difficulty, fights AI-controlled enemy bands, resolves events, and either completes the run (boss) or is defeated. It is the keystone phase — it wires the persistent characters (A4), bands/saves (A5), economy (A6), and AI (A7) into one loop.

### In scope

- A **run graph**: a generated, branching directed graph of nodes the player traverses, with a **visible run map**, **at most 3 parallel paths** at any node index, and **sporadic cross-connections** for interesting choices (see §4 — per the phase note).
- **Node kinds** and their resolution: Battle, Boss, Event, Boon, Hazard, Shop, Rest (Event/Boon/Hazard may be simple, data-driven outcome tables).
- **Encounter generation**: select a map (from the pool, by tier/size for depth) and compose an AI-controlled **enemy band** scaled to a target BP for the current depth.
- The **down-limit death model**: per-run down counter, permadeath past `DOWN_LIMIT`, run-loss when the band can't field a legal party.
- **Run state & persistence**: a `RunState` saved in `SaveManager.active_run`, resumable mid-run; a **run seed** making graph, encounters, loot, and AI variance reproducible.
- **Rewards** wired to A6; **light meta-progression** scaffolding on run completion.

### Out of scope

- **Rich narrative events / story campaign** — A8 events are intentionally minimal (master-spec §8.2); deep events are post-Alpha.
- **Full meta-progression depth** (unlock economy, multiple acts) — A8 scaffolds the profile; tuning/expansion is A10.
- **New content libraries** (A9), **balance tuning** (A10).
- **Networked or co-op runs** (deferred).

### Exit criteria

Phase A8 is complete when:

1. Starting a run generates a **branching node graph** with a start, a terminal boss, **≤ 3 parallel nodes per index**, and **sporadic cross-links**, rendered on a **run map** that shows traversed, current, and selectable-next nodes.
2. The player advances by choosing among the current node's outgoing edges; each **node kind resolves** (battles via A5 party builder + A7 AI + A6 rewards; Event/Boon/Hazard via simple tables; Shop/Rest functional).
3. **Encounters scale with depth** (enemy band target BP follows the depth curve) on maps drawn from the pool.
4. The **down-limit death model** works: characters survive up to `DOWN_LIMIT` downs per run, die on the next, and the run is lost when no legal party can be fielded.
5. A run is **persisted and resumable**, and a fixed **run seed** reproduces the same graph/encounters/loot/AI.
6. A full run plays **embark → traverse → victory or defeat**; graph generation and node/death logic are covered by headless tests; the run map by a manual checklist.

---

## 2. Design Decisions (Phase A8)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Branching graph, capped width** | A column-indexed DAG: each node index has **1–3 nodes** (`MAX_PARALLEL = 3`); edges connect adjacent indices with **sporadic cross-links** and occasional merges. | Per the phase note — bounded width prevents explosive difficulty/branching; cross-links create meaningful route choices (Slay-the-Spire-like). |
| **Single seed drives everything** | One **run seed** feeds graph generation, encounter generation, loot (A6), and AI variance (A7). | Whole-run reproducibility for debugging and fair "same seed, same run." |
| **Composition, not new combat** | Battles reuse A5's party-from-instances + the existing `MatchSetup`/`RoundManager`, with A7 driving the enemy and A6 paying out. | No new combat code; A8 is orchestration. |
| **Simple events** | Event/Boon/Hazard nodes are **data-driven outcome tables** (`data/events.json`) with text + basic effects; the node framework is extensible. | Master-spec allows feature-incomplete events; keeps A8 focused on the loop. |
| **Down-limit death** | Per-run `downs_this_run` (A4) vs `DOWN_LIMIT` (default 2); 3rd down = permadeath; tunable. | The agreed death model (master-spec §8.4); a single tunable for difficulty. |
| **Resumable run** | `RunState` lives in `SaveManager.active_run`; saved on node transitions. | Players can quit mid-run; aligns with A5's reserved slot. |
| **Light meta now** | Run completion writes minimal profile progress; full meta-progression is A10. | Keeps the profile slot live without over-building. |

---

## 3. Run Structure & Lifecycle

1. **Embark** — pick a band (A5) and start a run with a seed. Generate the graph (§4) and a fresh `RunState` (position at the start node; per-instance `downs_this_run` reset to 0).
2. **Traverse** — at the current node, the player chooses one of its **outgoing edges** to advance; the destination node **resolves** by kind (§5).
3. **Progress** — depth increases; encounters and rewards scale (§6). The run persists after each transition.
4. **End** — **victory** on clearing the **Boss** node; **defeat** when the band can no longer field a legal party (§7). The run map shows the outcome and returns to the band/menu.

---

## 4. Run Map & Graph Generation

The run is a **column-indexed directed acyclic graph** generated from the run seed and displayed to the player.

### 4.1 Structure & invariants

- **Columns (indices) `0..L`** where `L = RUN_LENGTH`. Column `0` is a single **Start** node; column `L` is a single **Boss** node.
- **Width per interior column ∈ [1, `MAX_PARALLEL` = 3]** — never more than three parallel nodes at any index (the cap from the phase note that prevents explosive branching).
- **Edges connect adjacent columns** (index `c → c+1`). A node has 1–2 outgoing edges, biased toward the nearest row, with **sporadic cross-links** (edges that shift rows) and occasional **merges** (two nodes → one), tuned by `CROSS_LINK_CHANCE`.
- **Reachability is guaranteed:** every non-start node has ≥ 1 incoming edge and every non-boss node has ≥ 1 outgoing edge (a repair pass fixes orphans), so any chosen route leads from Start to Boss.

### 4.2 Generation algorithm (seeded)

1. Choose interior column widths in `[1, 3]` from the run RNG.
2. Place nodes at `(column, row)`.
3. For each node in column `c`, add 1–2 edges to column `c+1`, preferring the same/adjacent row; with probability `CROSS_LINK_CHANCE`, add a cross-row edge or allow a merge.
4. **Repair:** ensure every column-`c+1` node has an incoming edge and every column-`c` node has an outgoing edge.
5. **Assign node kinds** (§5) by `NODE_WEIGHTS` with rules: column `0` = Start, column `L` = Boss, periodic Shop/Rest spacing, and a guarantee that the path is not all-battles.

The result is a weaving, bounded graph with real route decisions ("take the Shop path or the extra Battle for loot?").

### 4.3 Run map UI

A 2D map screen renders the graph: nodes as icons by kind, edges as connecting lines, laid out by column. It marks **visited** nodes, the **current** node, and the **selectable-next** nodes (the current node's outgoing edges) as the only clickable choices; unreachable nodes are dimmed. Selecting a next node travels to it and triggers resolution.

---

## 5. Node Kinds & Resolution

| Node | Resolution | Alpha completeness |
|------|------------|--------------------|
| **Start** | Entry; no resolution. | Full. |
| **Battle** | Generate an encounter (§6); build the match (A5 party-from-instances vs the enemy band) with A7 driving the enemy; on win, award XP/JP + roll loot (A6) to the band; on loss, apply the death model (§7). | Full. |
| **Boss** | A harder set-piece battle terminating the run; win = run victory. | Full (one boss suffices). |
| **Event** | A random encounter from `data/events.json`: text + one or more choices with basic outcomes (gold/HP/item/XP changes). | **Simple OK.** |
| **Boon** | A helpful outcome (heal, gold, item, XP/JP). | Simple. |
| **Hazard** | A harmful outcome (damage, gold loss, status, a down). | Simple. |
| **Shop** | Reuse the A6 shop panel against a depth-scaled shop pool. | Functional. |
| **Rest** | Recover HP and/or **reduce `downs_this_run`**; optionally spend to upgrade. | Functional. |

Node outcomes mutate the active **band** (A5) and its instances (A4), and persist with the `RunState`.

---

## 6. Encounter Generation & Difficulty

For a Battle/Boss node, the generator (seeded) selects:

- A **map** from the pool (`GameData` maps filtered by tier/size appropriate to the depth).
- An **enemy band** composed from templates and scaled to a **target BP** for the current depth via `DEPTH_BP_CURVE` (using A5's instance BP). Enemy instances are generated (A4) at a level/kit matching the target.

The enemy band is marked **AI-controlled** (A7). Composition rules, the depth→BP curve, and the map pool are authored/tunable data, not hard-coded.

---

## 7. Death Model

- Each instance carries a **run-scoped `downs_this_run`** (A4), reset to 0 at embark.
- A unit downed in a battle is removed from that battle (MVP). After the battle, **recoverable** survivors return (a Rest node or HP cost may be required); `downs_this_run` increments.
- On the **next down past `DOWN_LIMIT`** (default 2 → 3rd down) the instance **permanently dies** and is removed from the band.
- A **run is lost** when the band can no longer field a legal party (all fielded down with no reserves / objective failure).
- `DOWN_LIMIT` is the master-spec tunable (§8.7) for difficulty/progression.

---

## 8. Run State & Persistence

`RunState` (saved in `SaveManager.active_run`, A5):

```json
{ "run_id": "run_42", "band_id": "bb_1", "seed": 1234567,
  "graph": { "nodes": [...], "edges": [...] },
  "position": "node_12", "depth": 3, "down_limit": 2 }
```

- Saved on each node transition; a run can be **quit and resumed**.
- The **seed** makes graph, encounters, loot, and AI variance reproducible (the run RNG is threaded into A6's `LootRoller` and A7's planner).
- Completing or losing a run clears `active_run` (and writes light profile progress, §9).

---

## 9. Rewards & Light Meta-Progression

- **Within a run:** battles/nodes grant XP, JP, gold, and loot to the band via A4/A6.
- **Across runs:** on completion (and key milestones), write minimal **profile** progress (e.g., `completed_runs`, a few unlocks) into the A5 save profile slot. Full meta-progression breadth (unlock economy, starting boons) is **A10**; A8 only proves the data path exists.

---

## 10. Data Model & Touch Points

- **New (core):** `src/core/run/run_graph.gd` + `run_graph_generator.gd` (graph + generation), `run_state.gd` (`to_dict`/`from_dict`), `run_controller.gd` (traversal + node dispatch), `encounter_generator.gd`, `event_resolver.gd`.
- **New (data):** `data/events.json` (Event/Boon/Hazard tables), `data/run_config.json` (depth→BP curve, node weights, widths, cross-link chance). `data/shop_pools.json`/`loot_tables.json` already exist (A6).
- **New (scene):** run map UI + run flow scene; battle hand-off mirrors `DraftScene` via `MatchData` (band/fielded/run refs from A5).
- **Modified:** `SaveManager.active_run` populated; `MatchData` carries run context; match-end routes results back to the `run_controller`.
- **Reused:** A5 party builder, A6 `LootRoller`/`ShopService`/`grant_rewards`, A7 `AIController`, A4 instance ops.
- **Tunables (alpha-specs §8.7):** `RUN_LENGTH`, `MAX_PARALLEL` (3), `CROSS_LINK_CHANCE`, `DEPTH_BP_CURVE`, `DOWN_LIMIT`, `NODE_WEIGHTS`.

---

## 11. Risks & Notes

- **Graph validity.** A bad generator can orphan nodes or exceed the width cap; enforce the `≤ 3` width and run the reachability repair, and assert both in tests.
- **Difficulty curve.** The depth→BP curve drives fun and frustration; keep it data-tunable and validate that early nodes are winnable and late nodes are threatening.
- **Determinism.** All run randomness (graph, encounters, loot, AI) must flow from the run seed; a stray global `randi()` breaks reproducibility and resume integrity.
- **Resume correctness.** Saving/loading mid-run must restore the exact graph, position, band, and down counters; round-trip test `RunState`.
- **Death feel.** The down-limit must be legible to the player (UI shows downs remaining); avoid silent permadeath.
- **Event minimalism.** Keep events simple and data-driven; resist scope creep into narrative systems.
- **Scope creep.** No new content library, no deep meta-progression, no balance pass, no networking — orchestration of A4–A7 into the loop.

---

## 12. Phase A8 Deliverables Checklist

- [ ] `RunGraph` + seeded generator: columns, width ≤ `MAX_PARALLEL` (3), sporadic cross-links/merges, reachability repair, node-kind assignment (§4).
- [ ] Run map UI showing visited/current/selectable nodes; advance by choosing an outgoing edge (§4.3).
- [ ] Node resolution for all kinds; battles via A5 builder + A7 AI + A6 rewards; Event/Boon/Hazard via `events.json`; Shop/Rest functional (§5).
- [ ] Encounter generator: depth-scaled enemy band (`DEPTH_BP_CURVE`) + map from pool; enemy AI-controlled (§6).
- [ ] Down-limit death model: per-run counter, permadeath past `DOWN_LIMIT`, run-loss on no legal party (§7).
- [ ] `RunState` in `SaveManager.active_run`; saved on transitions; resumable; run seed reproduces graph/encounters/loot/AI (§8).
- [ ] Light meta-progression write on completion (profile slot) (§9).
- [ ] `events.json` / `run_config.json` authored + validated; tunables in `constants.json` (§10).
- [ ] Headless tests: graph invariants (width cap, reachability, determinism), node resolution, death model, `RunState` round-trip; manual run-map + full-run checklist.
- [ ] Git tag `alpha-phaseA8-complete`.
