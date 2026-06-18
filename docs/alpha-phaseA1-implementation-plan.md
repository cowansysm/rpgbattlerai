# Phase A1 — Implementation Plan

**Source spec:** `alpha-phaseA1-spec.md`
**Master spec:** `alpha-specs.md` (§3)
**Builds on (Alpha):** `alpha-phaseA0-implementation-plan.md` (`Dev` autoload + `DevMenu`, `MapSerializer`, dual-form `make_map`)
**Builds on (MVP):** `phase2-implementation-plan.md` (`MapBuilder`, `HexTile`, `CameraRig`, `TilePicker`, `TerrainPalette`), `phase1` (`MapData`, `TileRecord`, `Validator`)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-06-17

---

## How to use this plan

Six **work groups** (A–F). Across groups: **A** (`MapEditorModel`) is pure and unblocks everything; **B** (rendering/interaction) needs A and the MVP map stack; **C** (UI) needs A and drives B; **D** (file I/O + validation) needs A and A0's `MapSerializer`; **E** (dev-menu wiring) needs A0's `DevMenu` and the editor scene from B/C; **F** (tests) trails A–E.

Each task lists a **done state**. Code stubs are Godot 4 / GDScript — drop-in starting points that reuse existing classes, not final implementations.

> **Carry-over:** A1 reuses the MVP rendering stack unchanged — `MapBuilder.build(map_data)`, `HexTile.setup(...)`, `CameraRig` (`rotate_view`/`zoom_by`/`pan`/`get_camera`), `TilePicker` (emits `tile_selected(coord)`), and `TerrainPalette.material_for(terrain, elevation)`. It consumes A0's `Dev` flag, `DevMenu`, dual-form `DataFactory.make_map`, and `MapSerializer.to_json`.

---

## Group A — `MapEditorModel` (Headless)

*Pure `RefCounted`; no scene tree. Unblocks all other groups.*

### A1. Model state + `to/from MapData`
- Hold `id`, `tier`, `tiles` (`Vector2i → {elevation, terrain, tags}`), `zones`; convert to/from `MapData`.
- **Done:** `from_map_data(to_map_data(m))` reproduces the model's content (tested in F1).

```gdscript
# src/tools/map_editor_model.gd
class_name MapEditorModel
extends RefCounted

var id: String = "untitled"
var tier: String = "standard"
var tiles: Dictionary = {}     # Vector2i -> {"elevation": int, "terrain": String, "tags": Array[String]}
var zones: Dictionary = {}     # String -> Array[Vector2i]

var _undo: Array = []
var _redo: Array = []
const MAX_UNDO := 50

func to_map_data() -> MapData:
    var m := MapData.new()
    m.id = id; m.tier = tier
    var recs: Array[TileRecord] = []
    for c in tiles.keys():
        var t: Dictionary = tiles[c]
        recs.append(TileRecord.new(c.x, c.y, int(t["elevation"]), str(t["terrain"]), t.get("tags", [])))
    m.tiles = recs
    var dz := {}
    for z in zones.keys():
        dz[z] = zones[z].map(func(c: Vector2i) -> String: return "%d,%d" % [c.x, c.y])
    m.deployment_zones = dz
    return m

func from_map_data(m: MapData) -> void:
    id = m.id; tier = m.tier
    tiles.clear(); zones.clear()
    for t: TileRecord in m.tiles:
        tiles[t.coord()] = {"elevation": t.elevation, "terrain": t.terrain, "tags": t.tags}
    for z in m.deployment_zones.keys():
        var arr: Array[Vector2i] = []
        for s in m.deployment_zones[z]:
            var p := str(s).split(",")
            arr.append(Vector2i(int(p[0]), int(p[1])))
        zones[z] = arr
```

### A2. Mutations
- `new_map`, `set_terrain`, `set_elevation`, `add_tile`, `remove_tile`, `set_zone`, `set_metadata` — each snapshots before mutating.
- **Done:** each operation changes state as expected; removing a tile also drops it from all zones.

```gdscript
func _snapshot() -> void:
    _undo.push_back(_capture())
    if _undo.size() > MAX_UNDO: _undo.pop_front()
    _redo.clear()

func _capture() -> Dictionary:
    return {"id": id, "tier": tier, "tiles": tiles.duplicate(true), "zones": zones.duplicate(true)}

func set_terrain(c: Vector2i, terrain: String) -> void:
    if not tiles.has(c): return
    _snapshot(); tiles[c]["terrain"] = terrain

func set_elevation(c: Vector2i, value: int) -> void:
    if not tiles.has(c): return
    _snapshot(); tiles[c]["elevation"] = value

func add_tile(c: Vector2i, terrain: String = "grass", elevation: int = 0) -> void:
    if tiles.has(c): return
    _snapshot(); tiles[c] = {"elevation": elevation, "terrain": terrain, "tags": [] as Array[String]}

func remove_tile(c: Vector2i) -> void:
    if not tiles.has(c): return
    _snapshot(); tiles.erase(c)
    for z in zones.keys(): zones[z].erase(c)

func set_zone(c: Vector2i, zone: String, on: bool) -> void:
    _snapshot()
    if not zones.has(zone): zones[zone] = [] as Array[Vector2i]
    if on and not zones[zone].has(c): zones[zone].append(c)
    elif not on: zones[zone].erase(c)
```

### A3. New-map fill
- `new_map(id, tier, shape, size)` fills a rectangular or hex region with grass at elevation 0.
- **Done:** a fresh model has the expected tile count and all-grass terrain.

### A4. Undo/redo
- Swap snapshots between the undo/redo stacks; bounded depth.
- **Done:** undo reverts the last mutation; redo reapplies it; depth capped.

```gdscript
func undo() -> void:
    if _undo.is_empty(): return
    _redo.push_back(_capture()); _restore(_undo.pop_back())

func redo() -> void:
    if _redo.is_empty(): return
    _undo.push_back(_capture()); _restore(_redo.pop_back())

func _restore(s: Dictionary) -> void:
    id = s["id"]; tier = s["tier"]; tiles = s["tiles"]; zones = s["zones"]
```

### A5. `validate()`
- Return errors for unknown terrain ids, zones referencing missing tiles, and missing `id`.
- **Done:** a clean model returns `[]`; seeded faults return precise messages.

```gdscript
func validate() -> Array[String]:
    var e: Array[String] = []
    if id.strip_edges().is_empty(): e.append("map missing 'id'")
    for c in tiles.keys():
        if not GameData.get_terrain(tiles[c]["terrain"]):   # falls back to grass if unknown
            e.append("tile (%d,%d) unknown terrain '%s'" % [c.x, c.y, tiles[c]["terrain"]])
    for z in zones.keys():
        for c in zones[z]:
            if not tiles.has(c): e.append("zone '%s' references missing tile (%d,%d)" % [z, c.x, c.y])
    return e
```

---

## Group B — Rendering & Interaction

*Depends on A + MVP map stack. The editor scene's 3D side.*

### B1. Editor scene scaffold
- A `scenes/editor/map_editor.tscn` + controller that owns a `MapEditorModel`, a `MapBuilder`, a `CameraRig`, and a `TilePicker`.
- **Done:** opening the scene renders the current model with working camera + tile selection.

```gdscript
# src/ui/map_editor.gd
extends Node3D

var model := MapEditorModel.new()
var _builder: MapBuilder
var _rig: CameraRig
var _picker: TilePicker
var _tool: String = "paint_terrain"
var _brush_terrain: String = "grass"

func _ready() -> void:
    model.new_map("untitled", "standard", "rect", 8)
    _rebuild()
    _rig = CameraRig.new(); add_child(_rig); _rig.global_position = _builder.focus_center()
    _picker = TilePicker.new(); add_child(_picker)
    _picker.setup(_rig.get_camera())
    _picker.tile_selected.connect(_on_tile_selected)

func _rebuild() -> void:
    if _builder: _builder.queue_free()
    _builder = MapBuilder.new(); add_child(_builder)
    _builder.build(model.to_map_data())
```

### B2. Apply tool on selection
- Map a selected `Vector2i` to the active tool + brush; refresh the affected tile (incremental) or rebuild (structural).
- **Done:** clicking with each tool changes the model and the view matches.

```gdscript
func _on_tile_selected(c: Vector2i) -> void:
    match _tool:
        "paint_terrain": model.set_terrain(c, _brush_terrain); _refresh_tile(c)
        "raise":         model.set_elevation(c, _elev_of(c) + 1); _rebuild()
        "lower":         model.set_elevation(c, _elev_of(c) - 1); _rebuild()
        "add_tile":      model.add_tile(c, _brush_terrain); _rebuild()
        "remove_tile":   model.remove_tile(c); _rebuild()
        "zone":          model.set_zone(c, _active_zone, true); _refresh_zone_overlay()
```

### B3. Incremental tile refresh
- Update a single `HexTile`'s terrain material (and rebuild its wall on elevation change) without a full rebuild.
- **Done:** painting terrain updates instantly with no flicker; elevation/structural edits fall back to `_rebuild`.

### B4. Paint-drag
- Reuse a drag interaction so click-drag paints a stroke / sweeps a zone.
- **Done:** dragging across tiles applies the active tool to each.

---

## Group C — Editor UI

*Depends on A; drives B. The 2D overlay.*

### C1. Tool + terrain palette
- A `CanvasLayer` with tool buttons and a data-driven terrain palette built from `GameData` terrain ids, using `TerrainPalette` colors for swatches.
- **Done:** selecting a tool/terrain sets `_tool`/`_brush_terrain`.

### C2. Elevation, zone & metadata controls
- Raise/lower + set-value controls; zone picker; `id`/`tier` fields bound to `set_metadata`.
- **Done:** controls invoke the matching model mutations and refresh.

### C3. Validation panel + undo/redo buttons
- Show `model.validate()` output; wire Undo/Redo buttons and Ctrl+Z / Ctrl+Y.
- **Done:** errors list updates; Save disabled while non-empty; undo/redo work from the UI.

---

## Group D — File I/O & Validation

*Depends on A + A0 `MapSerializer`.*

### D1. Load
- A file picker over `data/maps/`; load via `DataFactory.make_map` → `model.from_map_data`.
- **Done:** selecting a map (condensed or verbose) loads it for editing.

```gdscript
func load_map(path: String) -> void:
    var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    model.from_map_data(DataFactory.make_map(raw))
    _rebuild()
```

### D2. Save (validate → serialize)
- Run `model.validate()`; on success write `MapSerializer.to_json(model.to_map_data())` to `data/maps/<id>.json`; on failure show errors, write nothing.
- **Done:** valid maps save as condensed minified JSON; invalid maps are blocked with messages.

```gdscript
func save_map() -> void:
    var errs := model.validate()
    if not errs.is_empty():
        _show_errors(errs); return
    var f := FileAccess.open("res://data/maps/%s.json" % model.id, FileAccess.WRITE)
    f.store_string(MapSerializer.to_json(model.to_map_data()))
    Log.info("MapEditor", "Saved map '%s'" % model.id)
```

---

## Group E — Dev Menu Wiring

*Depends on A0 `DevMenu` + the editor scene (B/C).*

### E1. Enable the Map Editor button
- In A0's `DevMenu`, replace the stubbed/disabled Map Editor entry with one that loads `map_editor.tscn`.
- **Done:** with `Dev.enabled`, the button opens the editor; with the flag off, the menu (and route) does not exist.

```gdscript
# src/ui/dev_menu.gd  (button handler)
func _on_map_editor_pressed() -> void:
    get_tree().change_scene_to_file("res://scenes/editor/map_editor.tscn")
```

### E2. Return-to-menu
- A way back from the editor to the prior scene/menu.
- **Done:** the editor can be exited cleanly.

---

## Group F — Tests & Verification

*Model is unit-tested; the GUI is checklist-verified.*

### F1. `MapEditorModel` unit tests (GUT)
- Mutations, zone-cleanup on tile removal, undo/redo, `validate()`, and `to/from MapData` round-trip.
- **Done:** green, headless.

```gdscript
# tests/tools/test_map_editor_model.gd
extends GutTest

func test_round_trip() -> void:
    var m := MapEditorModel.new()
    m.new_map("t", "standard", "rect", 4)
    m.set_terrain(Vector2i(0,0), "brush")
    var copy := MapEditorModel.new()
    copy.from_map_data(m.to_map_data())
    assert_eq(copy.tiles[Vector2i(0,0)]["terrain"], "brush")

func test_remove_tile_clears_zone() -> void:
    var m := MapEditorModel.new(); m.new_map("t","standard","rect",2)
    m.set_zone(Vector2i(0,0), "playerA", true)
    m.remove_tile(Vector2i(0,0))
    assert_false(m.zones["playerA"].has(Vector2i(0,0)))

func test_undo_redo() -> void:
    var m := MapEditorModel.new(); m.new_map("t","standard","rect",2)
    m.set_terrain(Vector2i(0,0), "road"); m.undo()
    assert_eq(m.tiles[Vector2i(0,0)]["terrain"], "grass")
    m.redo(); assert_eq(m.tiles[Vector2i(0,0)]["terrain"], "road")

func test_validate_flags_bad_zone() -> void:
    var m := MapEditorModel.new(); m.new_map("t","standard","rect",1)
    m.zones["playerA"] = [Vector2i(9,9)]
    assert_gt(m.validate().size(), 0)
```

### F2. Save/load integration test (GUT)
- Save a model, reload via `DataFactory.make_map`, assert identical tiles/zones.
- **Done:** green, headless.

### F3. Manual GUI checklist
- [ ] Editor opens only from Dev Tools (flag on); no route with flag off.
- [ ] New map renders a blank grass field of the chosen size.
- [ ] Paint terrain, raise/lower elevation, add/remove tile, mark zones — view updates live.
- [ ] Undo/redo revert and reapply correctly.
- [ ] Save blocks on validation errors and writes condensed minified JSON when valid.
- [ ] Load an existing map (condensed and verbose) and edit it.
- **Done:** checklist passes; a sample map authored end-to-end.

---

## Dependency Map

```
A (MapEditorModel) ──┬──> B (render/interaction) ──┐
                     ├──> C (UI) ───────────────────┤
                     └──> D (file I/O + validate) ──┤
A0 DevMenu + B/C ────────────────> E (dev menu) ────┤
                                                     └──> F (tests)
```

**Suggested first pass:** A1–A5 → B1–B3 → C1–C3 → D1–D2 → E1–E2 → B4 → F. Build and unit-test the model fully before wiring the scene.

---

## Phase A1 Definition of Done

- [ ] `MapEditorModel`: state, mutations, undo/redo, `to/from MapData`, `validate()` — unit-tested (A, F1).
- [ ] Editor scene reuses `MapBuilder`/`HexTile`/`CameraRig`/`TilePicker`; incremental + full refresh (B).
- [ ] Tools: paint terrain, elevation, add/remove tile, zone mark, inspect; paint-drag (B, C).
- [ ] UI: data-driven terrain palette, elevation/zone/metadata controls, validation panel, undo/redo (C).
- [ ] New-map creation; load condensed or verbose maps; round-trip preserved (A3, D1, F1).
- [ ] Save validates the typed model and writes A0 condensed minified JSON; blocked on errors (D2).
- [ ] Launchable only from the A0 Dev Tools menu; unreachable with the dev flag off (E).
- [ ] Model unit tests + save/load integration test green; manual GUI checklist passed (F).
- [ ] Git tag `alpha-phaseA1-complete`.
