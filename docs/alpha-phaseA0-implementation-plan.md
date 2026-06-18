# Phase A0 — Implementation Plan

**Source spec:** `alpha-phaseA0-spec.md`
**Master spec:** `alpha-specs.md` (§3.2, §4, §4.4)
**Builds on (MVP):** `phase2-implementation-plan.md` (`HexGraph`, `MapData`, `MapBuilder`), `phase4`/`phase5` (turn flow, `TurnActions`, `CombatResolver`)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-06-17

---

## How to use this plan

Five **work groups** (A–E). Within a group, tasks can be done in any order unless noted. Across groups: **A** (terrain schema + data) unblocks everything terrain-related; **B** (effect integration) needs A; **C** (condensed map format) is independent of A/B and can proceed in parallel; **D** (dev flag + menu) is independent of all and can proceed in parallel; **E** (tests) trails the code it covers.

Each task lists a **done state**. Code stubs are Godot 4 / GDScript — drop-in starting points that extend the existing classes, not final implementations.

> **Carry-over:** A0 extends the MVP terrain spine — `TerrainProps`, `TerrainRegistry` (loads `data/terrain.json`), and the injected **`HexGraph`** provider (`terrain_props()`, `move_cost()`, `is_impassable()`, `effective_cover()`). Move cost, impassability, LoS, and cover are already wired; A0 adds the new effect data and the hazard/status/occupant-modifier hooks. The dev flag joins the existing autoloads (`Log`, `Constants`, `GameData`, `DebugReadout`, `MatchData`).

---

## Group A — Terrain Effect Schema & Data

*Unblocks B. Extends `TerrainProps` and `TerrainRegistry`; adds data.*

### A1. Extend `TerrainProps`
- Add the Alpha effect fields with neutral defaults so existing terrain stays valid.
- **Done:** `TerrainProps` compiles with the new fields; defaults are no-ops.

```gdscript
# src/core/data/terrain_props.gd  (additions)
@export var damage_on_enter: int = 0
@export var damage_per_turn: int = 0
@export var status_on_enter: Dictionary = {}     # {status_id: String, duration: int} or {}
@export var occupant_modifiers: Array = []       # [{key: String, value: int}, ...]
@export var is_water: bool = false
@export var terrain_tags: Array[String] = []     # type-level tags (e.g., "hazard", "forest")
```

### A2. Parse new fields in `TerrainRegistry`
- Read the new keys in `load_from`, defaulting when absent.
- **Done:** a terrain entry with new fields loads; one without them loads with defaults.

```gdscript
# src/core/data/terrain_registry.gd  (inside the per-entry loop)
p.damage_on_enter = int(d.get("damage_on_enter", 0))
p.damage_per_turn = int(d.get("damage_per_turn", 0))
p.status_on_enter = d.get("status_on_enter", {})
p.occupant_modifiers = d.get("occupant_modifiers", [])
p.is_water = bool(d.get("is_water", false))
p.terrain_tags = DataFactory._to_str_array(d.get("tags", []))
```

### A3. Author representative terrain
- Add a few hazard/water entries to `data/terrain.json` (e.g., `lava`, `spikes`, `bog`); leave existing entries intact.
- **Done:** `terrain.json` validates and loads; new and old entries coexist.

---

## Group B — Effect Integration (Combat & Movement)

*Depends on A. Adds `HexGraph` accessors and the three effect hooks.*

### B1. `HexGraph` accessors for new fields
- Surface the new properties through the existing `terrain_props()` indirection.
- **Done:** each accessor returns the provider's value (stub-testable).

```gdscript
# src/core/hex/hex_graph.gd  (additions)
func damage_on_enter(c: Vector2i) -> int:
    return terrain_props(c).damage_on_enter

func damage_per_turn(c: Vector2i) -> int:
    return terrain_props(c).damage_per_turn

func status_on_enter(c: Vector2i) -> Dictionary:
    return terrain_props(c).status_on_enter

func occupant_modifiers(c: Vector2i) -> Array:
    return terrain_props(c).occupant_modifiers

func is_water(c: Vector2i) -> bool:
    return terrain_props(c).is_water
```

### B2. Enter effects in `execute_move`
- After the move resolves and `position` updates, apply enter damage, enter status, and refresh occupant modifiers. Route damage through the existing downing path.
- **Done:** stepping onto a `damage_on_enter`/`status_on_enter` tile produces the expected outcome and can down a unit.

```gdscript
# src/core/combat/turn_actions.gd  (inside execute_move, after position set)
var g: HexGraph = state.graph
_apply_terrain_modifiers(unit, g, destination)        # B4
var outcomes: Array = []
var dmg: int = g.damage_on_enter(destination)
if dmg > 0:
    unit.current_hp -= dmg
    outcomes.append({"target": unit.id, "type": "terrain_damage", "amount": dmg})
    _handle_downing(state, unit)
var st: Dictionary = g.status_on_enter(destination)
if not st.is_empty() and unit.current_hp > 0:
    CombatResolver.resolve_status(unit, str(st["status_id"]), int(st["duration"]), "terrain")
    outcomes.append({"target": unit.id, "type": "terrain_status", "status_id": st["status_id"]})
# merge `outcomes` into the move result dictionary
```

### B3. Per-turn damage at activation start
- Add an activation-start hook in the turn flow that applies `damage_per_turn` to the unit becoming active, before control is handed off.
- **Done:** a unit beginning its activation on a hazard tile takes damage once; downing/victory still resolve.

```gdscript
# src/core/combat/round_manager.gd  (new static, called when a unit is activated)
static func on_activation_start(state: MatchState, unit: BattleUnit) -> Array:
    var outcomes: Array = []
    if unit.current_hp <= 0:
        return outcomes
    var dmg: int = state.graph.damage_per_turn(unit.position)
    if dmg > 0:
        unit.current_hp -= dmg
        outcomes.append({"target": unit.id, "type": "terrain_damage", "amount": dmg})
        TurnActions._handle_downing(state, unit)
    return outcomes
```

> Wire `on_activation_start` into the same place the active unit is set (`RoundManager` advance / `BattleController`); surface its outcomes to the HUD/log like other actions.

### B4. Occupant modifiers (clear-then-reapply)
- A helper that strips `source = "terrain"` modifiers and applies the destination tile's `occupant_modifiers`; call it on move (B2) and at deployment.
- **Done:** occupying a `-SPD` bog reduces effective move; leaving restores it; no accumulation across moves.

```gdscript
# src/core/combat/turn_actions.gd  (helper)
static func _apply_terrain_modifiers(unit: BattleUnit, g: HexGraph, c: Vector2i) -> void:
    unit.stats.remove_modifiers_by_source("terrain")
    for m in g.occupant_modifiers(c):
        unit.stats.add_modifier(str(m["key"]), int(m["value"]), "terrain")
```

### B5. Regression guard (cover / move cost / LoS)
- Confirm no behavioral change to existing systems; only data widened.
- **Done:** the Phase 2/3/5 spatial and resolution suites pass unchanged.

---

## Group C — Condensed Map Format

*Independent of A/B. Touches `DataFactory` (load) and a new writer.*

### C1. Accept condensed tiles in `make_map`
- Read array-form tiles positionally; keep dict-form support for MVP maps.
- **Done:** both forms parse to identical `TileRecord`s.

```gdscript
# src/core/data/data_factory.gd  (inside make_map tile loop)
for t in d.get("tiles", []):
    if typeof(t) == TYPE_ARRAY:                       # condensed [q, r, elev, terrain, (tags)]
        var tags_c: Array[String] = _to_str_array(t[4]) if t.size() > 4 else [] as Array[String]
        tiles.append(TileRecord.new(int(t[0]), int(t[1]), int(t[2]), str(t[3]), tags_c))
    else:                                             # verbose MVP dict form
        var tags_v: Array[String] = _to_str_array(t.get("tags", []))
        tiles.append(TileRecord.new(int(t["q"]), int(t["r"]),
            int(t.get("elevation", 0)), str(t.get("terrain", "grass")), tags_v))
```

### C2. Condensed map writer
- Serialize a `MapData` to minified JSON with compact tile records. This is the format the A1 editor will write.
- **Done:** writing then loading reproduces the same tile set (round-trip).

```gdscript
# src/core/data/map_serializer.gd
class_name MapSerializer
extends RefCounted

static func to_json(map: MapData) -> String:
    var tiles: Array = []
    for t: TileRecord in map.tiles:
        var rec: Array = [t.q, t.r, t.elevation, t.terrain]
        if not t.tags.is_empty():
            rec.append(t.tags)
        tiles.append(rec)
    var obj := {"id": map.id, "tier": map.tier, "tiles": tiles,
        "deployment_zones": map.deployment_zones}
    return JSON.stringify(obj)        # no indent → minified
```

### C3. Migrate existing maps
- One-time pass converting `data/maps/*.json` to condensed via load → `MapSerializer.to_json` → overwrite. Assert geometry equality (coords/elevation/terrain/tags) before/after.
- **Done:** all shipped maps are condensed and load with identical geometry.

---

## Group D — Dev Flag & Dev Tools Menu

*Independent. Adds the `Dev` autoload, a menu, and gates `DebugReadout`.*

### D1. `Dev` autoload
- Resolve `enabled` once from launch arg → user config → `OS.is_debug_build()`.
- **Done:** `--dev`/`--no-dev` and a release build resolve as specified; `Dev.enabled` readable everywhere.

```gdscript
# src/autoload/dev.gd   (Autoload: Dev, after Constants)
extends Node

var enabled: bool = false

func _ready() -> void:
    var args := OS.get_cmdline_args()
    if args.has("--dev"):
        enabled = true
    elif args.has("--no-dev"):
        enabled = false
    elif FileAccess.file_exists("user://dev.cfg"):
        enabled = FileAccess.get_file_as_string("user://dev.cfg").strip_edges() == "1"
    else:
        enabled = OS.is_debug_build()
    Log.info("Dev", "dev mode = %s" % enabled)
```

### D2. Gate `DebugReadout`
- Show the overlay only in dev mode.
- **Done:** the readout is hidden with the flag off, visible with it on.

```gdscript
# src/debug/debug_readout.gd  (in _ready, after building the label)
visible = Dev.enabled
```

### D3. Dev Tools menu entry
- A dev-only menu/overlay reachable from the entry scene, listing dev tools. In A0 it is the seam; the Map Editor button arrives in A1 (stub it as disabled/"coming in A1").
- **Done:** with the flag on, a Dev Tools entry appears; with it off, there is no route to it.

```gdscript
# src/ui/dev_menu.gd  (instantiated only when Dev.enabled)
extends CanvasLayer

func _ready() -> void:
    if not Dev.enabled:
        queue_free()
        return
    # build a simple panel with buttons; Map Editor button added in A1
```

### D4. Register autoload
- Add `Dev="*res://src/autoload/dev.gd"` to `project.godot` autoloads after `Constants`.
- **Done:** boots without error; load order correct.

---

## Group E — Tests & Verification

*Math/logic unit-tested; the dev menu is checklist-verified.*

### E1. Terrain effect tests (GUT)
- Enter damage, per-turn damage, enter status, and occupant modifiers, using a stub terrain provider on `HexGraph`.
- **Done:** green, headless.

```gdscript
# tests/core/combat/test_terrain_effects.gd
extends GutTest

func test_enter_damage_reduces_hp() -> void:
    # build a 2-tile graph: start grass, destination "spikes" (damage_on_enter=3)
    # execute_move; assert unit.current_hp dropped by 3 and an outcome was logged
    pass

func test_per_turn_damage_on_activation() -> void:
    # unit on "lava" (damage_per_turn=4); RoundManager.on_activation_start
    # assert hp dropped by 4 once
    pass

func test_occupant_modifier_applies_and_clears() -> void:
    # move onto "bog" (-1 spd) → effective_move reduced; move off → restored
    pass
```

### E2. Serialization round-trip tests (GUT)
- Condensed write→load equals the original tile set; verbose and condensed forms parse identically.
- **Done:** green, headless.

```gdscript
# tests/core/data/test_map_serializer.gd
extends GutTest

func test_round_trip_preserves_tiles() -> void:
    var map := GameData.get_map("forest_clearing")
    var json := MapSerializer.to_json(map)
    var reparsed := DataFactory.make_map(JSON.parse_string(json))
    assert_eq(reparsed.tiles.size(), map.tiles.size())
    # assert each TileRecord equal (q, r, elevation, terrain, tags)

func test_condensed_and_verbose_parse_equal() -> void:
    var verbose := {"id":"t","tier":"standard",
        "tiles":[{"q":1,"r":2,"elevation":3,"terrain":"grass"}],"deployment_zones":{}}
    var condensed := {"id":"t","tier":"standard",
        "tiles":[[1,2,3,"grass"]],"deployment_zones":{}}
    assert_eq(DataFactory.make_map(verbose).tiles[0].coord(),
              DataFactory.make_map(condensed).tiles[0].coord())
```

### E3. Regression suite
- Run the existing Phase 2/3/5 suites unchanged.
- **Done:** all green; no behavioral drift in move cost, LoS, or cover.

### E4. Dev-flag manual checklist
- [ ] Launch with `--dev`: Dev Tools menu and `DebugReadout` visible.
- [ ] Launch with `--no-dev` (or release build): no Dev Tools route; readout hidden.
- [ ] `user://dev.cfg` override respected when no launch arg given.
- **Done:** checklist passes.

---

## Dependency Map

```
A (terrain schema + data) ──> B (effect integration) ──┐
                                                        ├──> E (tests)
C (condensed map format) ──────────────────────────────┤
D (dev flag + menu) ───────────────────────────────────┘
```

**Suggested first pass:** A1–A3 → B1–B5 → C1–C3 (parallel) and D1–D4 (parallel) → E1–E4. Build C and D alongside B since they share no code.

---

## Phase A0 Definition of Done

- [ ] `TerrainProps` + `TerrainRegistry` carry and load the new effect fields with defaults (A1–A2).
- [ ] `terrain.json` includes representative hazard/water terrain; existing entries intact (A3).
- [ ] `HexGraph` exposes new-field accessors via the injected provider (B1).
- [ ] Enter damage/status and occupant modifiers applied in `execute_move`; per-turn damage at activation start; all routed through downing/log (B2–B4).
- [ ] Cover/move-cost/LoS behavior unchanged; regression suites green (B5, E3).
- [ ] `DataFactory.make_map` accepts condensed and verbose tiles; `MapSerializer` writes minified condensed maps; round-trip holds (C1–C2, E2).
- [ ] Existing maps migrated to condensed with verified identical geometry (C3).
- [ ] `Dev` autoload resolves the flag (arg/config/build); `DebugReadout` and the Dev Tools menu gated by it; autoload registered (D1–D4).
- [ ] Terrain-effect and serialization GUT tests green; dev-flag manual checklist passed (E1–E4).
- [ ] Git tag `alpha-phaseA0-complete`.
