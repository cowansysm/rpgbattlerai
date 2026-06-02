# Phase 3 — Implementation Plan

**Source spec:** `phase3-spec.md`
**Builds on:** `phase0` (hex math), `phase1` (`MapData`, `final_stats`), `phase2` (rendered tiles, highlight)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Pathfinding:** `AStar3D` graph · **LoS:** hybrid (hex-line + raycast cross-check) · **Move overlay:** two tiers
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-05-29

---

## How to use this plan

Eight **work groups** (A–H). Within a group, tasks can be done in any order unless noted. Across groups: **A** (terrain data) unblocks movement + LoS; **B** (graph) needs A; **C** (movement) needs B; **D** (range) needs only the Phase 0 hex math; **E** (LoS) needs A + the graph's tile data; **F** (overlays) needs C/D/E + a small Phase 2 `HexTile` extension; **G** (marker + demo) ties it together; **H** (tests) trails the logic, manual checklist trails F/G.

Each task lists a **done state**. Code stubs are Godot 4 / GDScript — drop-in starting points. The graph/pathfinding/range/LoS are unit-testable; overlays are checklist-verified.

> **Carry-over:** consumes `MapData` + character `final_stats` (Move, Jump/Climb) from Phase 1, the Phase 0 hex helpers (`neighbors`, `distance`, `hexes_in_range`, `cube_round`), and the Phase 2 `MapBuilder`/`HexTile`/`HexWorld`. Only **terrain** blocks movement/LoS this phase; unit occupancy is Phase 4.

---

## Group A — Terrain Properties Data

*Unblocks movement (B/C) and LoS (E). Extends the Phase 1 data layer.*

### A1. Author `terrain.json`
- Properties for every `rpg-specs.md` §3.2 terrain: `move_cost`, `impassable`, `blocks_los`, `cover`, `los_height`.
- **Done:** file loads; covers all terrains used by maps.

```json
// data/terrain.json
{
  "grass":         { "move_cost": 1, "impassable": false, "blocks_los": false, "cover": 0, "los_height": 0 },
  "road":          { "move_cost": 1, "impassable": false, "blocks_los": false, "cover": 0, "los_height": 0 },
  "brush":         { "move_cost": 2, "impassable": false, "blocks_los": false, "cover": 1, "los_height": 0 },
  "trees":         { "move_cost": 2, "impassable": false, "blocks_los": true,  "cover": 1, "los_height": 2 },
  "rocks":         { "move_cost": 0, "impassable": true,  "blocks_los": true,  "cover": 0, "los_height": 3 },
  "shallow_water": { "move_cost": 2, "impassable": false, "blocks_los": false, "cover": 0, "los_height": 0 },
  "deep_water":    { "move_cost": 0, "impassable": true,  "blocks_los": false, "cover": 0, "los_height": 0 },
  "cliff":         { "move_cost": 0, "impassable": true,  "blocks_los": true,  "cover": 0, "los_height": 3 }
}
```

### A2. `TerrainProps` + loader
- A typed resource and a `GameData` registry + accessor; validate every map terrain has properties.
- **Done:** `GameData.get_terrain("trees").move_cost == 2`.

```gdscript
# src/core/data/terrain_props.gd
class_name TerrainProps
extends Resource

@export var id: String
@export var move_cost: int = 1
@export var impassable: bool = false
@export var blocks_los: bool = false
@export var cover: int = 0
@export var los_height: int = 0
```

```gdscript
# src/core/data/terrain_registry.gd
class_name TerrainRegistry
extends RefCounted

var _entries: Dictionary = {}   # id -> TerrainProps

func load_from(path: String) -> void:
    var text := FileAccess.get_file_as_string(path)
    var data: Variant = JSON.parse_string(text)
    for id in data.keys():
        var d: Dictionary = data[id]
        var p := TerrainProps.new()
        p.id = id; p.move_cost = int(d.get("move_cost", 1))
        p.impassable = bool(d.get("impassable", false))
        p.blocks_los = bool(d.get("blocks_los", false))
        p.cover = int(d.get("cover", 0)); p.los_height = int(d.get("los_height", 0))
        _entries[id] = p

func get_entry(id: String) -> TerrainProps:
    return _entries.get(id, _entries.get("grass"))

func has(id: String) -> bool:
    return _entries.has(id)
```

```gdscript
# in GameData (facade — extends Phase 1)
var _terrain := TerrainRegistry.new()

func _load_terrain() -> void:
    _terrain.load_from("res://data/terrain.json")

func get_terrain(id: String) -> TerrainProps:
    return _terrain.get_entry(id)
```

> Add a validation check: every terrain referenced by a loaded `MapData` exists in `terrain` (extend the Phase 1 referential pass).

---

## Group B — Hex Connectivity Graph (`AStar3D`)

*Depends on A. One point per tile; edges to valid neighbors.*

### B1. `HexGraph` (AStar3D subclass)
- Build points from `MapData`; track coord↔id, elevation, terrain. Terrain properties are accessed through an **injected provider** (`Callable(String) -> TerrainProps`) passed at build time — not by calling `GameData` directly. This keeps the graph pure/testable and supports future terrain mutation.
- **Done:** graph has a point per tile; cost overrides return terrain move cost / hex-distance estimate. Tests pass with a stub terrain provider.

```gdscript
# src/core/hex/hex_graph.gd
class_name HexGraph
extends AStar3D

var _id_of: Dictionary = {}     # Vector2i -> int
var _coord_of: Dictionary = {}  # int -> Vector2i
var _elev: Dictionary = {}      # Vector2i -> int
var _terrain: Dictionary = {}   # Vector2i -> String
var _mover_jump: int = 99
var _terrain_provider: Callable  # (String) -> TerrainProps — injected at build

func build(map: MapData, terrain_provider: Callable) -> void:
    clear(); _id_of.clear(); _coord_of.clear(); _elev.clear(); _terrain.clear()
    _terrain_provider = terrain_provider
    var next_id := 0
    for t: TileRecord in map.tiles:
        var c := t.coord()
        add_point(next_id, Vector3(c.x, t.elevation, c.y))
        _id_of[c] = next_id; _coord_of[next_id] = c
        _elev[c] = t.elevation; _terrain[c] = t.terrain
        next_id += 1

func elevation(c: Vector2i) -> int: return int(_elev.get(c, 0))
func terrain_id(c: Vector2i) -> String: return str(_terrain.get(c, "grass"))
func terrain_props(c: Vector2i) -> TerrainProps: return _terrain_provider.call(terrain_id(c))
func has_tile(c: Vector2i) -> bool: return _id_of.has(c)
func id_of(c: Vector2i) -> int: return int(_id_of.get(c, -1))
func coord_of(id: int) -> Vector2i: return _coord_of.get(id, Vector2i.ZERO)
func is_impassable(c: Vector2i) -> bool: return terrain_props(c).impassable
func move_cost(c: Vector2i) -> int: return terrain_props(c).move_cost

# AStar cost overrides (used by point-to-point pathing)
func _compute_cost(from_id: int, to_id: int) -> float:
    return float(move_cost(_coord_of[to_id]))
func _estimate_cost(from_id: int, to_id: int) -> float:
    return float(Hex.distance(_coord_of[from_id], _coord_of[to_id]))
```

> Production code passes `GameData.get_terrain` as the provider; tests pass a stub lambda.

### B2. Per-mover edge connection (cached)
- Jump/Climb is mover-specific; edge sets are **cached per distinct `jump_climb` value**. `set_mover(jump)` checks the cache before reconnecting, avoiding redundant teardown/rebuild across activations.
- **Done:** after `set_mover(jump)`, edges exist only where passable and `abs(Δelev) ≤ jump`. Repeated calls with the same jump value are free. `invalidate_cache()` exists for future destructible-terrain support.

```gdscript
var _edge_cache: Dictionary = {}    # int (jump_climb) -> Array of [id_a, id_b] pairs

func set_mover(jump_climb: int) -> void:
    if _mover_jump == jump_climb:
        return                      # already set — no work
    _mover_jump = jump_climb
    if _edge_cache.has(jump_climb):
        _apply_cached_edges(jump_climb)
    else:
        _reconnect()
        _cache_current_edges(jump_climb)

func _reconnect() -> void:
    for id in _coord_of.keys():
        for nb_id in get_point_connections(id):
            disconnect_points(id, nb_id)
    for c in _id_of.keys():
        for nb in Hex.neighbors(c):
            if _id_of.has(nb) and _edge_valid(c, nb):
                connect_points(_id_of[c], _id_of[nb], true)

func _cache_current_edges(jump: int) -> void:
    var edges: Array = []
    for id in _coord_of.keys():
        for nb_id in get_point_connections(id):
            if nb_id > id:          # avoid duplicates
                edges.append([id, nb_id])
    _edge_cache[jump] = edges

func _apply_cached_edges(jump: int) -> void:
    for id in _coord_of.keys():
        for nb_id in get_point_connections(id):
            disconnect_points(id, nb_id)
    for pair in _edge_cache[jump]:
        connect_points(pair[0], pair[1], true)

func invalidate_cache() -> void:
    _edge_cache.clear()

func _edge_valid(from_c: Vector2i, to_c: Vector2i) -> bool:
    if is_impassable(to_c): return false
    return abs(elevation(to_c) - elevation(from_c)) <= _mover_jump
```

---

## Group C — Movement & Pathfinding

*Depends on B. Reachable set (bounded Dijkstra) + path + two-tier.*

### C1. Reachable set
- Cost-bounded Dijkstra over neighbors honoring Jump/Climb + impassability; returns `{tile: min_cost}`.
- **Done:** correct set for a known start/budget.

```gdscript
# src/core/hex/movement.gd
class_name Movement
extends RefCounted

const INF_COST := 1 << 30

static func reachable(graph: HexGraph, start: Vector2i, max_cost: int, jump: int) -> Dictionary:
    var dist := { start: 0 }
    var frontier: Array = [[0, start]]
    while not frontier.is_empty():
        frontier.sort_custom(func(a, b): return a[0] < b[0])
        var top: Array = frontier.pop_front()
        var cost: int = top[0]
        var cur: Vector2i = top[1]
        if cost > int(dist.get(cur, INF_COST)): continue
        for nb in Hex.neighbors(cur):
            if not graph.has_tile(nb) or graph.is_impassable(nb): continue
            if abs(graph.elevation(nb) - graph.elevation(cur)) > jump: continue
            var nc: int = cost + graph.move_cost(nb)
            if nc <= max_cost and nc < int(dist.get(nb, INF_COST)):
                dist[nb] = nc
                frontier.append([nc, nb])
    return dist
```

### C2. Two-tier reach (action economy)
- Tier 1 = budget `move`; Tier 2 = budget `2*move` minus Tier 1.
- **Done:** the two sets are disjoint and partition the full double-move reach.

```gdscript
static func two_tier(graph: HexGraph, start: Vector2i, move: int, jump: int) -> Dictionary:
    var t1 := reachable(graph, start, move, jump)
    var t2_full := reachable(graph, start, move * 2, jump)
    var t2_only := {}
    for c in t2_full.keys():
        if not t1.has(c):
            t2_only[c] = t2_full[c]
    return { "tier1": t1, "tier2": t2_only }
```

### C3. Shortest path (AStar)
- Reconnect edges for the mover, then `get_id_path`; map ids back to coords.
- **Done:** returns the ordered tile path between two reachable tiles.

```gdscript
static func path(graph: HexGraph, start: Vector2i, goal: Vector2i, jump: int) -> Array:
    graph.set_mover(jump)
    var ids := graph.get_id_path(graph.id_of(start), graph.id_of(goal))
    var out: Array = []
    for id in ids:
        out.append(graph.coord_of(int(id)))
    return out
```

---

## Group D — Range

*Depends only on Phase 0 hex math.*

### D1. In-range query via `effective_range`
- All on-map tiles where `effective_range(origin, target, graph) ≤ radius`.
- `effective_range` is the **designated extension point** for adding a vertical-distance term. Currently returns 2D hex distance.
- All range consumers use `effective_range`, not `Hex.distance` directly.
- **Done:** correct set; cardinality matches hex range math intersected with the map.

```gdscript
# src/core/hex/range_query.gd
class_name RangeQuery
extends RefCounted

# Extension point for vertical range: currently returns 2D hex distance.
# When elevation-adjusted range is needed, only this function changes.
static func effective_range(a: Vector2i, b: Vector2i, graph: HexGraph) -> int:
    return Hex.distance(a, b)

static func in_range(origin: Vector2i, radius: int, graph: HexGraph) -> Array:
    var out: Array = []
    for c in Hex.hexes_in_range(origin, radius):
        if graph.has_tile(c) and effective_range(origin, c, graph) <= radius:
            out.append(c)
    return out
```

> Range uses 2D hex distance (spec §5); elevation is handled by LoS + the combat elevation bonus, not by inflating distance. The `effective_range` indirection ensures all consumers update if vertical range rules are added later.

---

## Group E — Line of Sight (hybrid)

*Depends on A (terrain `blocks_los`/`los_height`) + graph tile data.*

### E1. Hex-line LoS (authoritative)
- Sample intervening hexes; block if blocking height exceeds the interpolated sightline. Higher attacker "sees over" automatically.
- Receives terrain properties through the **graph's injected terrain provider** (via `graph.terrain_props()`), not by calling `GameData` directly. This keeps LoS pure and testable against stub terrain.
- **Done:** blocked by tall terrain; allowed when attacker is high enough. Tests pass with a stub terrain provider.

```gdscript
# src/core/hex/line_of_sight.gd
class_name LineOfSight
extends RefCounted

const UNIT_EYE := 1.0   # eye height above the tile surface

static func has_los(graph: HexGraph, a: Vector2i, b: Vector2i) -> bool:
    var line := _hex_line(a, b)
    var n := line.size() - 1
    if n <= 1:
        return true
    var ha := float(graph.elevation(a)) + UNIT_EYE
    var hb := float(graph.elevation(b)) + UNIT_EYE
    for i in range(1, n):                       # intervening hexes only
        var h: Vector2i = line[i]
        if not graph.has_tile(h): continue
        var sight_h: float = lerp(ha, hb, float(i) / float(n))
        if _block_height(graph, h) > sight_h:
            return false
    return true

static func _block_height(graph: HexGraph, c: Vector2i) -> float:
    var props: TerrainProps = graph.terrain_props(c)  # via injected provider
    var h := float(graph.elevation(c))
    if props.blocks_los:
        h += float(props.los_height)
    return h

static func _hex_line(a: Vector2i, b: Vector2i) -> Array:
    var n := Hex.distance(a, b)
    if n == 0:
        return [a]
    var ac := Hex.axial_to_cube(a)
    var bc := Hex.axial_to_cube(b)
    var out: Array = []
    for i in range(n + 1):
        var t := float(i) / float(n)
        out.append(Hex.cube_to_axial(Hex.cube_round(
            lerp(float(ac.x), float(bc.x), t),
            lerp(float(ac.y), float(bc.y), t),
            lerp(float(ac.z), float(bc.z), t))))
    return out
```

### E2. Raycast cross-check (optional, debug)
- Cast a 3D ray between eye-points (via `HexWorld`) against Phase 2 colliders; log disagreements with E1. Hex-line stays authoritative.
- **Done:** diagnostic available behind a debug flag; not used for gameplay decisions.

```gdscript
static func raycast_clear(space: PhysicsDirectSpaceState3D, from_w: Vector3, to_w: Vector3) -> bool:
    var query := PhysicsRayQueryParameters3D.create(from_w, to_w)
    return space.intersect_ray(query).is_empty()
```

---

## Group F — Overlays

*Depends on C/D/E + a small Phase 2 `HexTile` extension. Reuses the rendered tiles.*

### F1. Consume Phase 2 multi-layer `HexTile`
- Phase 2's `HexTile` already provides `set_overlay(mat)` / `clear_overlay()` on the overlay layer, independent of the selection layer. No extension needed in Phase 3.
- **Done:** the overlay controller can paint tiles without conflicting with selection highlighting.

### F2. Overlay materials
- Distinct materials: move tier-1, move tier-2, target-valid, target-blocked.
- **Done:** four visually distinct overlay materials.

```gdscript
# src/map/overlay_materials.gd
class_name OverlayMaterials
extends RefCounted

static func _mat(c: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new(); m.albedo_color = c
    if c.a < 1.0: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    return m

static func move_tier1() -> StandardMaterial3D: return _mat(Color(0.3, 0.5, 1.0, 0.7))
static func move_tier2() -> StandardMaterial3D: return _mat(Color(0.5, 0.8, 1.0, 0.5))
static func target_valid() -> StandardMaterial3D: return _mat(Color(1.0, 0.3, 0.3, 0.7))
static func target_blocked() -> StandardMaterial3D: return _mat(Color(0.5, 0.5, 0.5, 0.5))
```

### F3. Overlay controller
- Paint movement (two tiers) or targets (in-range + LoS) over the builder's tiles.
- **Done:** `show_movement` and `show_targets` render correctly; `clear` resets.

```gdscript
# src/map/overlay_controller.gd
class_name OverlayController
extends Node

var graph: HexGraph
var builder: MapBuilder

func show_movement(start: Vector2i, move: int, jump: int) -> void:
    clear()
    var tiers := Movement.two_tier(graph, start, move, jump)
    for c in tiers["tier1"].keys(): _paint(c, OverlayMaterials.move_tier1())
    for c in tiers["tier2"].keys(): _paint(c, OverlayMaterials.move_tier2())

func show_targets(origin: Vector2i, radius: int) -> void:
    clear()
    for c in RangeQuery.in_range(origin, radius, graph):
        if c == origin: continue
        var mat := OverlayMaterials.target_valid() if LineOfSight.has_los(graph, origin, c) else OverlayMaterials.target_blocked()
        _paint(c, mat)

func _paint(c: Vector2i, mat: StandardMaterial3D) -> void:
    if builder.tiles.has(c): builder.tiles[c].set_overlay(mat)

func clear() -> void:
    for t in builder.tiles.values(): t.clear_overlay()
```

---

## Group G — Marker & Demo Wiring

*Ties A–F together for the exit-criteria demo. No full unit system yet.*

### G1. Placed marker (via `BattleUnit`)
- A `BattleUnit` instantiated from a loaded character (via `BattleUnit.from_character()`), placed on a start tile. Move and Jump/Climb are read from `unit.stats.effective_move()` and `unit.stats.effective_jump_climb()`. A sample weapon range is provided as a literal.
- This validates the Phase 1 runtime-state pattern: the marker is a `BattleUnit`, not raw stat values.
- **Done:** marker sits on a tile; its stats drive overlays.

### G2. Demo controls
- Build the graph from the current map; keys to toggle **movement overlay** vs **target overlay** from the marker's tile; clicking moves the marker (visual only) to a reachable tile and re-renders.
- **Done:** the exit-criteria behaviors are demonstrable interactively.

```gdscript
# src/map/phase3_demo.gd  (attached in the map scene for testing)
extends Node

@export var map_id := "forest_clearing"
@export var character_id := "human_rogue"
@export var start := Vector2i(0, 0)
@export var weapon_range := 3

var _unit: BattleUnit
var _graph: HexGraph
var _overlay: OverlayController

func setup(builder: MapBuilder) -> void:
    # Create a BattleUnit from the loaded character — validates the runtime-state pattern
    var c := GameData.get_character(character_id)
    _unit = BattleUnit.from_character(c, GameData.get_final_stats(character_id))
    _unit.position = start

    _graph = HexGraph.new()
    _graph.build(GameData.get_map(map_id), GameData.get_terrain)  # injected terrain provider
    _overlay = OverlayController.new(); _overlay.graph = _graph; _overlay.builder = builder
    add_child(_overlay)

func show_move() -> void:
    var move: int = _unit.stats.effective_move()
    var jump: int = _unit.stats.effective_jump_climb()
    _overlay.show_movement(_unit.position, move, jump)

func show_targets() -> void:
    _overlay.show_targets(_unit.position, weapon_range)
```

---

## Group H — Verification

*Logic is unit-tested; overlays are checklist-verified.*

### H1. Movement tests (GUT)
- Reachable set on a tiny hand-built graph; Jump/Climb blocks a too-steep edge; impassable tile excluded; two-tier sets are disjoint and partition the double-move reach; path returns correct cost.
- Tests build graphs with a **stub terrain provider** (no `GameData` autoload required).
- **Done:** green, headless.

```gdscript
# tests/core/test_movement.gd
extends GutTest

# Stub terrain provider for tests — returns grass by default
static func _stub_terrain(id: String) -> TerrainProps:
    var p := TerrainProps.new()
    p.id = id; p.move_cost = 1; p.impassable = (id == "rocks")
    return p

func test_jump_blocks_steep_edge() -> void:
    var g := _flat_graph_with_cliff()     # neighbor at elevation +3; built with _stub_terrain
    var reach := Movement.reachable(g, Vector2i(0,0), 10, 1)  # jump 1
    assert_false(reach.has(Vector2i(1,0)))                    # +3 step blocked

func test_two_tiers_disjoint() -> void:
    var g := _open_graph()                # built with _stub_terrain
    var tiers := Movement.two_tier(g, Vector2i(0,0), 2, 9)
    for c in tiers["tier1"].keys():
        assert_false(tiers["tier2"].has(c))
```

### H2. Range tests (GUT)
- In-range set equals hex-range math intersected with the map; origin excluded as appropriate.
- **Done:** green.

### H3. LoS tests (GUT)
- Tall terrain between two equal-elevation tiles blocks; raising the attacker above the obstacle restores LoS (higher-sees-over); clear ground always has LoS.
- Tests build graphs with a **stub terrain provider** that returns `blocks_los=true, los_height=2` for trees — no `GameData` required.
- **Done:** green.

```gdscript
# tests/core/test_los.gd
extends GutTest

static func _stub_terrain(id: String) -> TerrainProps:
    var p := TerrainProps.new()
    p.id = id
    if id == "trees":
        p.blocks_los = true; p.los_height = 2
    return p

func test_tall_terrain_blocks() -> void:
    var g := _graph_with_trees_between()   # built with _stub_terrain
    assert_false(LineOfSight.has_los(g, Vector2i(0,0), Vector2i(2,0)))

func test_higher_attacker_sees_over() -> void:
    var g := _graph_with_trees_between()   # built with _stub_terrain
    g.set_elevation(Vector2i(0,0), 4)
    assert_true(LineOfSight.has_los(g, Vector2i(0,0), Vector2i(2,0)))
```

### H4. Manual overlay checklist (screenshots)
- [ ] Movement overlay shows correct tier-1 (single move) and tier-2 (double move) tiles in distinct colors.
- [ ] Impassable/too-steep tiles are excluded from reach.
- [ ] Target overlay marks in-range tiles; LoS-blocked tiles show the blocked color.
- [ ] Raising terrain between marker and target blocks LoS; placing the marker on high ground restores it.
- **Done:** checklist passes; screenshots captured.

---

## Dependency Map

```
A (terrain data + TerrainRegistry) ──> B (graph + injected provider + edge cache) ──> C (movement) ──┐
A ──────────────────────────────────────────────> E (LoS via graph provider) ────────────────────────┤
(Phase 0 hex) ───────────────────────────────────> D (range via effective_range) ───────────────────┤
C,D,E + Phase 2 multi-layer tiles ──> F (overlays) ──> G (demo with BattleUnit)
A,B,C,D,E ──> H1–H3 (unit tests, stub providers);  F,G ──> H4 (manual)
```

**Suggested first pass:** A1–A2 → B1–B2 → C1–C3 → (D1 ∥ E1) → F1–F3 → G1–G2 → H. Build D and E in parallel; both feed the target overlay.

---

## Phase 3 Definition of Done

- [ ] Terrain properties authored + loaded via `TerrainRegistry` + validated against map terrains (A).
- [ ] `HexGraph` on `AStar3D` with injected terrain provider, per-mover Jump/Climb + impassability edges, and **per-jump-climb edge caching** (B).
- [ ] Reachable set, two-tier reach, and shortest path with cost (C).
- [ ] In-range query via `effective_range` function (D).
- [ ] Hybrid LoS: hex-line sampling (via injected terrain provider) with higher-sees-over + optional raycast cross-check (E).
- [ ] Two-tier movement overlay + target overlay using Phase 2 multi-layer tiles (F).
- [ ] Placed marker demo uses a `BattleUnit` instance and shows correct reachable overlay and valid targets (G).
- [ ] GUT tests for movement, range, LoS green (headless, with stub terrain providers); manual overlay checklist with screenshots (H).
- [ ] Git tag `phase-3-complete`.
