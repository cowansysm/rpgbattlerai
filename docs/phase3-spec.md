# Phase 3 — Movement, Range & Line of Sight Specification

**Parent plan:** `rpg-implementation-plan.md` (Phase 3)
**Builds on:** `phase0-spec.md` (hex math), `phase1-spec.md` (`MapData`, character `final_stats`), `phase2-spec.md` (rendered map, tiles, highlight)
**Source spec:** `rpg-specs.md` (§3 Maps, §4.3 derived stats, §7.4–7.5 combat)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Pathfinding:** Godot `AStar3D` graph · **Line of sight:** hybrid (hex-line sampling + raycast cross-check) · **Movement overlay:** two tiers (1 move / 2 moves)
**Date:** 2026-05-29

---

## 1. Purpose & Scope

Phase 3 makes the **spatial rules** real. On top of the rendered map from Phase 2, it computes where a unit can move (respecting move cost, impassable terrain, and the Jump/Climb elevation limit), what tiles are within a given range, and whether one tile has line of sight to another (with the "higher attacker sees over" rule). It renders these as overlays. It does **not** yet resolve combat, manage turns, or model multiple interacting units — those are Phases 4–5.

Phase 3 is validated against a single **placed character marker** (a stand-in, not the full unit system): given its position and `final_stats`, the map shows a correct reachable-tiles overlay and correctly flags valid attack targets given range and LoS.

### In scope

- A **terrain-properties** table (move cost, LoS blocking, cover, impassability) consumed by movement and LoS.
- A **hex connectivity graph** built on Godot `AStar3D` for the loaded `MapData`.
- **Pathfinding**: shortest path between tiles and a **reachable set** bounded by a move budget, honoring Jump/Climb and impassability.
- **Two-tier movement overlay**: single-move (SPD) reach and double-move (both AP) reach, visually distinct.
- **Range** queries: tiles within a weapon/ability range (hex distance).
- **Line of sight**: hybrid hex-line sampling with elevation rules, optionally cross-checked by a 3D raycast.
- A **target overlay** marking in-range tiles/targets with clear LoS.

### Out of scope

- Units as first-class entities, occupancy, facing, zones of control (Phase 4) — Phase 3 uses a single placed marker for testing and treats only **terrain** as blocking.
- Turn order, activation, AP spending mechanics (Phase 4).
- Damage, evasion, WP costs, status effects (Phase 5).
- AI movement decisions, animations, final UI (later phases).

### Exit criteria

Phase 3 is complete when:

1. Terrain properties load and drive move cost, impassability, and LoS blocking.
2. A reachable-tiles computation returns the correct set for a placed marker given its Move and Jump/Climb, shown as a **two-tier** overlay (1 move vs 2 moves).
3. A shortest path between two reachable tiles is returned with correct accumulated cost.
4. A range query returns the correct in-range tile set for a given range value.
5. Line of sight is correctly blocked by taller terrain/obstacles and correctly allowed when the attacker is high enough to "see over"; the target overlay reflects this.
6. Pure logic (graph, pathfinding, range, LoS) is unit-tested headless; overlays are verified by a documented manual checklist.

---

## 2. Design Decisions (Phase 3)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Pathfinding** | Build a hex connectivity graph on Godot **`AStar3D`** (one point per tile, edges to the six neighbors). Use it for point-to-point paths; compute the **reachable set** with a cost-bounded Dijkstra expansion over the same adjacency. | Leverages the built-in A* for paths while still producing the move-budget reachable set hexes need. Jump/Climb and impassability filter edges. |
| **Jump/Climb** | A move between adjacent tiles is allowed only if `abs(Δelevation) ≤ mover.jump_climb`. Mover-specific, so edge filtering is applied per query (graph reconnect or per-step check). | Matches spec §4.3; small MVP maps make per-mover handling cheap. |
| **Line of sight** | **Hybrid:** hex-line sampling between tiles applies the elevation/"higher sees over" rules deterministically; an optional 3D raycast against Phase 2 colliders cross-checks edge cases. | Rules-based core is testable and authoritative; raycast is a sanity check, not the source of truth. |
| **Terrain provider injection** | LoS and movement computations receive terrain properties through an **injected provider** (`Callable(String) -> TerrainProps`), not by directly accessing `GameData`. | Keeps spatial-rule functions pure and testable against stub terrain; allows future phases to inject modified terrain (destructible cover, spell-created obstacles) without altering the algorithms. |
| **Movement overlay** | **Two tiers:** single-move (cost ≤ SPD) and double-move (SPD < cost ≤ 2×SPD), drawn in distinct colors. | Mirrors the 2-AP action economy (spec §7.4): one move action vs spending both AP moving. |

---

## 3. Terrain Properties

Movement and LoS need per-terrain attributes. These are defined in a **terrain-properties table** (data-authored; see §8) covering every terrain type from `rpg-specs.md` §3.2:

| Terrain | move_cost | impassable | blocks_los | cover |
|---------|-----------|------------|------------|-------|
| grass / dirt | 1 | no | no | 0 |
| road / stone | 1 | no | no | 0 |
| brush (tall grass) | 2 | no | no | 1 (soft) |
| trees (forest) | 2 | no* | yes | 1 (soft) |
| rocks / boulders | — | yes | yes | — |
| shallow water | 2 | no | no | 0 |
| deep water | — | yes | no | — |
| cliff face | — | yes | yes | — |

\* "Dense" trees may be authored impassable; "sparse" passable at cost 2. The data table is authoritative; this is a readable view.

- **move_cost**: cost to *enter* the tile (destination-based; entering rough terrain costs more).
- **impassable**: the tile cannot be entered (no graph edges into it).
- **blocks_los**: the tile's contents block line of sight up to its blocking height (see §6).
- **cover**: soft-cover value applied later in combat (spec §7.5); carried here for completeness, consumed in Phase 5.

---

## 4. Movement & Pathfinding

### 4.1 The connectivity graph

For a loaded `MapData`, build a graph with one node per tile and undirected adjacency to each of the six hex neighbors that exist on the map. An edge `A→B` is **valid** when:

- `B` is on the map and **not impassable**, and
- `abs(elevation(B) − elevation(A)) ≤ mover.jump_climb`.

Edge **cost** entering `B` = `terrain.move_cost(B)`. Because cost is destination-based, the A→B and B→A costs may differ; the graph's cost function accounts for direction.

**Edge caching:** Edge sets are cached per distinct `jump_climb` value. On small MVP maps the number of distinct Jump/Climb values is small (typically 2–4), so caching all variants at graph-build time or on first use is practical. `set_mover(jump)` checks the cache before reconnecting. The cache is invalidated only if the map changes (e.g., destructible terrain in a future phase).

### 4.2 Shortest path

Given a start and a reachable goal tile, return the ordered tile path and its total accumulated move cost, via `AStar3D`.

### 4.3 Reachable set (move budget)

Given a start tile and a **move budget**, return every tile reachable with accumulated cost ≤ budget (cost-bounded Dijkstra over the adjacency, honoring Jump/Climb + impassability). The result maps each reachable tile to its minimal cost.

### 4.4 Two-tier reach (action economy)

Per spec §7.4 a character can move once (up to SPD) or spend both AP moving (up to 2×SPD):

- **Tier 1 (single move):** reachable with budget = `Move` (= final SPD).
- **Tier 2 (double move):** reachable with budget = `2 × Move`, minus the tier-1 set.

Both tiers come from the same reachable computation at two budgets.

---

## 5. Range

Range for an attack or ability is defined by the **weapon/ability** (spec §4.2), not a character stat. Phase 3 provides the geometric query:

- **In-range set** = all tiles where `effective_range(origin, target, graph) ≤ radius`.
- **`effective_range`** is a dedicated function that currently returns **2D hex distance** (via `Hex.distance`). This is the **designated extension point** for adding a vertical-distance term in a future phase. All range consumers (overlays, target validation, AI) call `effective_range`, not `Hex.distance` directly.
- **MVP elevation note:** range uses 2D hex distance; verticality is handled by **line of sight** (§6) and the elevation combat bonus (spec §7.5), not by inflating distance. When vertical range rules are needed, only `effective_range` changes — not every consumer.

A tile is a **valid target** when it is in range **and** has clear line of sight from the origin.

---

## 6. Line of Sight

### 6.1 Hex-line sampling (authoritative)

To test LoS from tile `A` (attacker, eye height `Ha`) to tile `B` (target, eye height `Hb`):

1. Compute the line of hexes between `A` and `B` (cube interpolation + `cube_round` from Phase 0).
2. For each **intervening** hex `H` (excluding the endpoints), compute its **blocking height** = `elevation(H)` plus an obstacle contribution if `H`'s terrain `blocks_los` (trees/rocks/cliff add height).
3. Interpolate the **sightline height** at `H`'s position along the line between `Ha` and `Hb`.
4. If any intervening hex's blocking height **exceeds** the sightline height there, LoS is **blocked**.

Eye height = tile elevation (plus a small unit-height constant). Because the sightline is interpolated between the two eye heights, a **higher attacker** produces a sightline that clears lower intervening obstacles automatically — implementing the "higher sees over lower" rule without special-casing.

### 6.2 Raycast cross-check (optional, hybrid)

A 3D physics raycast between the two eye-points against the Phase 2 obstacle colliders can be run as a secondary check (e.g., in debug builds) to catch geometry the hex sampling misses. The hex-line result remains authoritative for gameplay; disagreements are logged for tuning.

### 6.3 Symmetry

LoS is treated as symmetric for the MVP except where the elevation interpolation differs by direction (a higher attacker may see a target that cannot see back at the same clarity). This is acceptable and consistent with the higher-ground rule.

---

## 7. Overlays

Overlays use the Phase 2 per-tile **overlay layer** (independent of the selection layer) with distinct overlay materials:

- **Movement overlay (two tiers):** tier-1 (single move) and tier-2 (double move) tiles in distinct colors; the start tile marked.
- **Path preview (optional):** highlight the path to a hovered reachable tile.
- **Target overlay:** in-range tiles with clear LoS marked as valid targets; in-range-but-no-LoS optionally shown in a muted/blocked color.

Overlays use the overlay layer; selection uses the selection layer. Both may be visible simultaneously (e.g., a selected tile within a movement overlay). Future phases (deployment zones, AoE previews, status indicators) can add additional overlay meshes to the tile node without displacing existing layers. Overlays are presentation over the authoritative computations; they hold no rules state.

---

## 8. Inputs & Data Flow

- **Terrain properties**: authored as a data table (e.g., `data/terrain.json`) loaded by `GameData` (extends the Phase 1 data layer). Validation ensures every terrain type used by maps has properties.
- **Map**: `MapData` (Phase 1) supplies tiles, elevation, terrain.
- **Mover**: a placed marker uses a `BattleUnit` instance (from Phase 1's skeleton) initialized from a character, providing position, Move, and Jump/Climb through the stat block's effective values. This validates the runtime-state pattern before Phase 4 depends on it.
- **Range**: supplied per query from a weapon/ability range value (a literal in Phase 3 tests; sourced from item/ability data in later phases).

All computations are read-only over loaded data; results (reachable sets, paths, LoS booleans) are returned to callers/overlays without mutating content.

---

## 9. Risks & Notes

- **Per-mover edge filtering.** Jump/Climb is mover-specific, so the graph's valid edges depend on who's moving. Mitigated by **caching edge sets per distinct `jump_climb` value** (§4.1); cache invalidation needed if destructible terrain is added later.
- **LoS height tuning.** The obstacle blocking-height contribution (how "tall" trees/rocks/cliffs are for LoS) needs tuning so the higher-sees-over rule feels right; expose as constants.
- **Range vs elevation.** Keeping range as 2D hex distance is a deliberate MVP simplification; the `effective_range` function (§5) is the designated extension point. Document it so combat (Phase 5) and balancing don't assume otherwise.
- **No unit occupancy yet.** Only terrain blocks movement/LoS in Phase 3; other units blocking tiles/sight arrives in Phase 4. The placed marker uses a `BattleUnit` instance (from Phase 1), which is the carrier for future occupancy tracking. Don't bake unit-blocking assumptions into the graph here.
- **Hybrid LoS disagreements.** Treat the hex-line rule as authoritative; use raycast only as a diagnostic to avoid two competing sources of truth.
- **Terrain provider contract.** Spatial-rule functions receive terrain through an injected provider. Ensure the provider contract is documented so future terrain mutation (destructible cover) passes a modified provider, not a patched global.
- **Scope creep.** No turns, AP spending, or damage in Phase 3 — only movement/range/LoS computation and overlays.

---

## 10. Phase 3 Deliverables Checklist

- [ ] Terrain-properties table authored and loaded via `TerrainRegistry`; validated against map terrain usage (§3, §8).
- [ ] Hex connectivity graph on `AStar3D` with Jump/Climb + impassability edge rules and **per-jump-climb edge caching** (§4.1).
- [ ] Graph and LoS receive terrain via **injected provider**, not direct `GameData` access (§2).
- [ ] Shortest-path query with accumulated cost (§4.2).
- [ ] Reachable-set computation bounded by move budget (§4.3) and the **two-tier** derivation (§4.4).
- [ ] Range via `effective_range` function (extension point for vertical range) (§5).
- [ ] Hybrid line of sight: hex-line sampling with higher-sees-over + optional raycast cross-check (§6).
- [ ] Two-tier movement overlay + target overlay using Phase 2 multi-layer tiles (§7).
- [ ] Validation: placed marker uses a `BattleUnit` instance and shows correct reachable overlay and valid targets (§1 exit).
- [ ] GUT tests for graph, pathfinding, range, LoS green (headless, with stub terrain providers); manual overlay checklist with screenshots.
- [ ] Git tag `phase-3-complete`.
