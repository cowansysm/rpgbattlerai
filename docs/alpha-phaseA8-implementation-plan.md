# Phase A8 — Implementation Plan

**Source spec:** `alpha-phaseA8-spec.md`
**Master spec:** `alpha-specs.md` (§8)
**Builds on (Alpha):** A4 (instances/`downs_this_run`), A5 (`BattleBand`, `SaveManager.active_run`, `BandPartyBuilder`, `MatchData`), A6 (`LootRoller`/`ShopService`/`grant_rewards`), A7 (`AIController`)
**Builds on (MVP):** `phase7` (`MatchBuilder`/`MatchSetup`), `phase4`/`phase5` (`MatchState`, `RoundManager`)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-06-17

---

## How to use this plan

Seven **work groups** (A–G). Across groups: **A** (graph generation) is pure and unblocks the map UI; **B** (run state/persistence) underpins traversal; **C** (node resolution) composes A4–A7; **D** (encounter generation) feeds Battle nodes; **E** (death model) is consumed by C; **F** (run map UI + flow) ties it together; **G** (tunables + tests) trails.

Each task lists a **done state**. Code stubs are Godot 4 / GDScript — orchestration reusing A4–A7. All run randomness flows from the **run seed**.

> **Carry-over:** A8 is composition. Battles reuse `BandPartyBuilder` (A5) → `MatchSetup`/`RoundManager`, with `AIController` (A7) driving the enemy and `grant_rewards`/`LootRoller` (A6) paying out. The run persists via `SaveManager.active_run` (A5 reserved slot). `MatchData` already carries band/fielded refs (A5) — A8 adds the run ref and routes match-end back to the run controller.

---

## Group A — Run Graph & Generation

*Pure core. Unblocks the map UI.*

### A1. `RunGraph` model
- Nodes `{id, column, row, kind}` and directed edges `{from, to}`; helpers `next_nodes(id)`, `node(id)`.
- **Done:** a hand-built graph answers traversal queries.

```gdscript
# src/core/run/run_graph.gd
class_name RunGraph
extends RefCounted

var nodes: Dictionary = {}      # id -> {id, column, row, kind}
var edges: Array = []           # [{from, to}]

func next_nodes(id: String) -> Array:
    var out: Array = []
    for e in edges:
        if e["from"] == id: out.append(e["to"])
    return out
```

### A2. Seeded generator (width cap + cross-links)
- Generate columns `0..RUN_LENGTH`; interior width in `[1, MAX_PARALLEL]` (3); 1–2 outgoing edges per node biased to nearest row; sporadic cross-links/merges via `CROSS_LINK_CHANCE`.
- **Done:** width never exceeds 3; cross-links appear; (reachability ensured in A3).

```gdscript
# src/core/run/run_graph_generator.gd
class_name RunGraphGenerator
extends RefCounted

static func generate(rng: RandomNumberGenerator, cfg: Dictionary) -> RunGraph:
    var g := RunGraph.new()
    var L: int = int(cfg.get("run_length", 12))
    var maxw: int = int(cfg.get("max_parallel", 3))
    var widths: Array = [1]
    for c in range(1, L): widths.append(rng.randi_range(1, maxw))
    widths.append(1)                                  # boss column width 1
    _place_nodes(g, widths)
    _connect_columns(g, widths, rng, float(cfg.get("cross_link_chance", 0.25)))
    return g
```

### A3. Reachability repair
- Ensure every non-start node has an incoming edge and every non-boss node has an outgoing edge.
- **Done:** no orphans; every route leads Start→Boss (tested in G).

### A4. Node-kind assignment
- Column 0 = Start, column L = Boss; assign interior kinds by `NODE_WEIGHTS` with Shop/Rest spacing and a not-all-battles guarantee.
- **Done:** kinds are assigned within the rules; deterministic per seed.

---

## Group B — Run State & Persistence

*Depends on A. Uses the A5 save slot.*

### B1. `RunState` + (de)serialization
- Fields: run_id, band_id, seed, graph, position, depth, down_limit; `to_dict`/`from_dict` (graph serializes to nodes/edges).
- **Done:** `from_dict(to_dict(x))` round-trips, including the graph (G).

```gdscript
# src/core/run/run_state.gd
class_name RunState
extends RefCounted

var run_id: String
var band_id: String
var seed: int
var graph: RunGraph
var position: String        # current node id
var depth: int = 0
var down_limit: int = 2
```

### B2. Save/resume via `SaveManager`
- Put the active `RunState` in `SaveManager.active_run`; save on transitions; resume restores graph/position/band/downs.
- **Done:** quitting and reloading resumes the exact run.

---

## Group C — Node Resolution

*Depends on A,B,D,E + A4–A7.*

### C1. Run controller + dispatch
- Advance to a chosen next node; dispatch by kind; update position/depth; persist.
- **Done:** choosing an edge resolves the destination and moves the run forward.

```gdscript
# src/core/run/run_controller.gd
class_name RunController
extends RefCounted

func advance_to(run: RunState, node_id: String, ctx: Dictionary) -> void:
    if node_id not in RunGraph.new().next_nodes(run.position) and not _is_legal_next(run, node_id):
        return
    run.position = node_id; run.depth += 1
    match run.graph.nodes[node_id]["kind"]:
        "battle", "boss": _resolve_battle(run, node_id, ctx)
        "event", "boon", "hazard": EventResolver.resolve(run, node_id, ctx)
        "shop": _open_shop(run, ctx)
        "rest": _rest(run, ctx)
    SaveManager.active_run = run; SaveManager.save_game()
```

### C2. Battle nodes
- Generate the encounter (D), build the match (A5 `BandPartyBuilder` vs enemy band, A7 AI), run it; on win award XP/JP + `grant_rewards` (A6); on loss apply death model (E).
- **Done:** a Battle node plays to a result and updates the band.

### C3. Event/Boon/Hazard
- `EventResolver` reads `data/events.json`: present choices/outcomes; apply basic effects (gold/HP/item/XP/down).
- **Done:** a node applies a data-driven outcome to the band.

### C4. Shop & Rest
- Shop reuses the A6 panel against a depth-scaled pool; Rest recovers HP and reduces `downs_this_run`.
- **Done:** both mutate the band and persist.

---

## Group D — Encounter Generation

*Feeds C2.*

### D1. `EncounterGenerator`
- Seeded: pick a map from the pool (tier/size by depth) and compose an enemy band scaled to a target BP via `DEPTH_BP_CURVE`.
- **Done:** depth↑ → tougher enemy band; map fits the tier.

```gdscript
# src/core/run/encounter_generator.gd
class_name EncounterGenerator
extends RefCounted

static func generate(depth: int, rng: RandomNumberGenerator, providers: Dictionary) -> Dictionary:
    var target_bp: int = _depth_bp(depth)
    var enemy := _compose_enemy_band(target_bp, depth, rng, providers)   # generate instances to ~target_bp
    var map := _pick_map(depth, rng, providers)
    return {"map": map, "enemy_band": enemy}
```

---

## Group E — Death Model

*Consumed by C2.*

### E1. Down tracking & permadeath
- After a battle, increment `downs_this_run` for downed survivors; if it would exceed `down_limit`, mark the instance dead and remove from the band.
- **Done:** the 3rd down (default) permanently removes an instance.

### E2. Run-loss check
- The run is lost when the band can't field a legal party.
- **Done:** a wiped/insufficient band ends the run in defeat.

```gdscript
func apply_post_battle(run: RunState, band: BattleBand, downed: Array) -> void:
    for ci in downed:
        ci.downs_this_run += 1
        if ci.downs_this_run > run.down_limit:
            band.remove_instance(ci.instance_id)      # permadeath
    if not _can_field_legal_party(band):
        _end_run(run, "defeat")
```

---

## Group F — Run Map UI & Flow

*Depends on A–E.*

### F1. Run map screen
- Render nodes by column with kind icons and edges; mark visited/current; highlight selectable-next; dim unreachable.
- **Done:** the graph is readable; only outgoing-edge nodes are clickable.

### F2. Run flow + battle hand-off
- Embark (pick band, seed, generate graph); selecting a node resolves it; Battle nodes hand off to the match scene via `MatchData` (run ref) and route results back to `RunController`.
- **Done:** a full run plays embark→traverse→win/lose.

### F3. Down/Run status display
- Show each instance's downs-remaining; show run outcome (victory/defeat) screen.
- **Done:** death stakes are legible; the run ends with a clear result.

---

## Group G — Tunables & Verification

### G1. Data & constants
- `data/run_config.json` (run_length, max_parallel=3, cross_link_chance, depth_bp_curve, node_weights) and `data/events.json`; mirror key tunables in `constants.json`.
- **Done:** authored data loads and validates.

### G2. Graph tests (GUT)
- Width ≤ 3 at every column; reachability (Start reaches Boss; no orphans); determinism (same seed → same graph); cross-links present.
- **Done:** green.

```gdscript
# tests/core/run/test_run_graph.gd
extends GutTest

func test_width_cap() -> void:
    var g := RunGraphGenerator.generate(_seeded(1), _cfg())
    var by_col := {}
    for n in g.nodes.values(): by_col[n["column"]] = int(by_col.get(n["column"], 0)) + 1
    for c in by_col: assert_lte(by_col[c], 3)

func test_reachability() -> void:
    var g := RunGraphGenerator.generate(_seeded(1), _cfg())
    assert_true(_start_reaches_boss(g))

func test_determinism() -> void:
    assert_eq(_signature(RunGraphGenerator.generate(_seeded(7), _cfg())),
              _signature(RunGraphGenerator.generate(_seeded(7), _cfg())))
```

### G3. Run logic tests (GUT)
- `RunState` round-trip (incl. graph); node dispatch routes correctly; death model permadeaths on the 3rd down; run-loss triggers on no legal party; encounter BP scales with depth.
- **Done:** green.

### G4. Manual run checklist
- [ ] Embark → branching map renders (≤3 wide, cross-links visible); only valid next nodes clickable.
- [ ] Battle/Boss/Event/Boon/Hazard/Shop/Rest each resolve and update the band.
- [ ] Enemies get tougher with depth; AI drives them (A7).
- [ ] A character permadies on its 3rd down; run lost when no party can field.
- [ ] Quit mid-run and resume identically; same seed → same run.
- [ ] A full run reaches victory or defeat.
- **Done:** checklist passes.

---

## Dependency Map

```
A (graph + gen) ──┬──> F (run map UI + flow) ──┐
B (run state/save)┤                             │
D (encounter) ────┼──> C (node resolution) ─────┼──> G (tests)
E (death model) ──┘                             │
A4–A7 systems ──────────────────────────────────┘
```

**Suggested first pass:** A1–A4 → G2 → B1–B2 → D1 → E1–E2 → C1–C4 → F1–F3 → G1/G3/G4. Lock the graph generator (with tests) before building traversal on top.

---

## Phase A8 Definition of Done

- [ ] Seeded `RunGraph` generator: ≤ `MAX_PARALLEL` (3) per column, sporadic cross-links/merges, reachability repair, node-kind assignment (A).
- [ ] `RunState` persisted in `SaveManager.active_run`; saved on transitions; resumable; seed reproduces the run (B, §8).
- [ ] Run controller dispatches all node kinds; battles via A5+A7+A6; Event/Boon/Hazard via `events.json`; Shop/Rest functional (C).
- [ ] `EncounterGenerator` scales enemy band BP with depth and picks tier-appropriate maps; enemies AI-controlled (D).
- [ ] Down-limit death model: per-run counter, permadeath past `DOWN_LIMIT`, run-loss on no legal party (E).
- [ ] Run map UI: visited/current/selectable rendering; advance via outgoing edges; down/outcome display (F).
- [ ] `run_config.json`/`events.json` + tunables; graph, run-logic, and `RunState` round-trip tests green; manual full-run checklist passed (G).
- [ ] Git tag `alpha-phaseA8-complete`.
