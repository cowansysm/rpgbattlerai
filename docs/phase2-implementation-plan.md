# Phase 2 — Implementation Plan

**Source spec:** `phase2-spec.md`
**Builds on:** `phase0-implementation-plan.md` (hex math, `HexLayout`), `phase1-implementation-plan.md` (`MapData` loading)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Orientation:** Flat-top · **Tiles:** per-tile `MeshInstance3D` · **Elevation:** single tile at raised Y · **Picking:** raycast · **Camera:** FFT fixed angles
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-05-29

---

## How to use this plan

Seven **work groups** (A–G). Within a group, tasks can be done in any order unless noted. Across groups: **A** (hex→world math) unblocks placement; **B** (mesh + materials) is independent; **C** (tile node + builder) needs A and B; **D** (camera) is independent of C and can be built against a stub map; **E** (picking) needs C's colliders and D's camera; **F** (sample map + scene wiring) ties it together; **G** (tests) trails A and the manual checklist trails C–F.

Each task lists a **done state**. Code stubs are Godot 4 / GDScript — drop-in starting points, not final implementations. Rendering, camera, and picking are validated by a **manual screenshot checklist** (G2); only the math is unit-testable.

> **Carry-over:** Phase 2 activates the flat-top `HexLayout` constants (`F0`, `F2`, `F3`) defined but unused in Phase 0, and consumes the `MapData` resources loaded in Phase 1 via `GameData.get_map(id)`.

---

## Group A — Hex → World Mapping

*Unblocks tile placement. Extends the Phase 0 hex module. Pure, unit-testable.*

### A1. World layout constants + conversion
- Add `HEX_SIZE` and `ELEV_UNIT`, and a flat-top `hex_to_world` using the Phase 0 `HexLayout` constants.
- **Done:** known coordinates map to expected world positions (tested in G1).

```gdscript
# src/core/hex/hex_world.gd
class_name HexWorld
extends RefCounted

const HEX_SIZE := 1.0     # center-to-corner, world units
const ELEV_UNIT := 0.5    # world height per elevation step

# Flat-top axial (q, r) + elevation -> world position.
# Grid lies on X/Z; elevation maps to Y.
static func hex_to_world(q: int, r: int, elevation: int) -> Vector3:
    var x := HEX_SIZE * (HexLayout.F0 * q)                       # 3/2 * q
    var z := HEX_SIZE * (HexLayout.F2 * q + HexLayout.F3 * r)    # (sqrt3/2)*q + sqrt3*r
    var y := float(elevation) * ELEV_UNIT
    return Vector3(x, y, z)
```

### A2. (Optional) world → hex fallback
- Not needed for picking (raycast carries coords). If wanted later, project to the ground plane and use the Phase 0 `Hex.cube_round`.
- **Done:** documented as deferred; no blocker for Phase 2.

---

## Group B — Hex Tile Mesh & Terrain Materials

*Independent. Provides the shared mesh and material palette.*

### B1. Shared hex mesh
- Use a 6-segment `CylinderMesh` as a flat hex prism; tiles rotate 30° to present **flat-top**.
- **Done:** one reusable `Mesh` resource exists.

```gdscript
# src/map/tile_mesh.gd
class_name TileMesh
extends RefCounted

static func make_hex_mesh() -> Mesh:
    var m := CylinderMesh.new()
    m.radial_segments = 6
    m.top_radius = HexWorld.HEX_SIZE
    m.bottom_radius = HexWorld.HEX_SIZE
    m.height = 0.1
    return m
# NOTE: a 6-sided cylinder is pointy-top by default; rotate the tile node
# by 30° about Y (see C1) to align flat edges to the camera (flat-top).
```

### B2. Terrain material palette
- Map each `rpg-specs.md` §3.2 terrain to a distinct material (flat colors for MVP; water is translucent).
- **Done:** `material_for(terrain)` returns a material for every known terrain; unknown → magenta (visible error).

```gdscript
# src/map/terrain_palette.gd
class_name TerrainPalette
extends RefCounted

const COLORS := {
    "grass": Color(0.30, 0.60, 0.25),
    "road": Color(0.50, 0.50, 0.50),
    "brush": Color(0.45, 0.70, 0.35),
    "trees": Color(0.20, 0.45, 0.20),
    "rocks": Color(0.35, 0.35, 0.38),
    "shallow_water": Color(0.40, 0.70, 0.90, 0.70),
    "deep_water": Color(0.15, 0.35, 0.70, 0.85),
    "cliff": Color(0.40, 0.36, 0.32),
}

static func material_for(terrain: String) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    var c: Color = COLORS.get(terrain, Color.MAGENTA)
    mat.albedo_color = c
    if c.a < 1.0:
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    return mat
```

### B3. Highlight material
- A shared highlight material assigned to the **selection layer** mesh (not as an override on the terrain mesh). Independent of overlay materials.
- **Done:** a distinct, obvious highlight (e.g., bright emissive) is available.

```gdscript
# src/map/highlight_material.gd
class_name HighlightMaterial
extends RefCounted

static func make() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(1.0, 0.95, 0.3)
    mat.emission_enabled = true
    mat.emission = Color(0.8, 0.7, 0.1)
    return mat
```

### B4. (Optional) decoration markers
- Simple tree/boulder marker meshes placed atop `trees`/`rocks` tiles. Cosmetic only — no gameplay semantics.
- **Done:** markers render; deferred if time-constrained.

---

## Group C — Tile Node & Map Builder

*Depends on A (placement) + B (mesh/materials). Consumes `MapData`.*

### C1. `HexTile` node (multi-layer)
- A `Node3D` placed at hex→world, rotated to flat-top, with **three mesh children** (base, overlay, selection) and a collider for picking; stores its coords/elevation/terrain.
- Layers are independent: base always shows terrain, overlay is for movement/range painting, selection is for click highlight. Each can be shown/hidden without affecting the others.
- **Done:** a single tile instantiates at the correct position, is clickable, and supports independent overlay + selection states.

```gdscript
# src/map/hex_tile.gd
class_name HexTile
extends Node3D

var q: int
var r: int
var elevation: int
var terrain: String

var _base_mesh: MeshInstance3D      # always visible; terrain material
var _overlay_mesh: MeshInstance3D   # hidden by default; movement/range/target painting
var _selection_mesh: MeshInstance3D # hidden by default; click/hover highlight

const OVERLAY_Y_OFFSET := 0.02     # slight Y offset to stack above base
const SELECTION_Y_OFFSET := 0.04   # slight Y offset to stack above overlay

func setup(tq: int, tr: int, te: int, tt: String, mesh: Mesh, mat: StandardMaterial3D, highlight: StandardMaterial3D) -> void:
    q = tq; r = tr; elevation = te; terrain = tt
    position = HexWorld.hex_to_world(q, r, elevation)
    rotation.y = deg_to_rad(30.0)                       # align flat-top

    # Base layer — always visible, never overridden
    _base_mesh = MeshInstance3D.new()
    _base_mesh.mesh = mesh
    _base_mesh.material_override = mat
    add_child(_base_mesh)

    # Overlay layer — hidden by default; set_overlay() shows it
    _overlay_mesh = MeshInstance3D.new()
    _overlay_mesh.mesh = mesh
    _overlay_mesh.position.y = OVERLAY_Y_OFFSET
    _overlay_mesh.visible = false
    add_child(_overlay_mesh)

    # Selection layer — hidden by default; set_highlighted() shows it
    _selection_mesh = MeshInstance3D.new()
    _selection_mesh.mesh = mesh
    _selection_mesh.material_override = highlight
    _selection_mesh.position.y = SELECTION_Y_OFFSET
    _selection_mesh.visible = false
    add_child(_selection_mesh)

    # Collider for raycast picking
    var body := StaticBody3D.new()
    var shape := CollisionShape3D.new()
    var cyl := CylinderShape3D.new()
    cyl.radius = HexWorld.HEX_SIZE
    cyl.height = 0.1
    shape.shape = cyl
    body.add_child(shape)
    add_child(body)

    set_meta("hex", Vector2i(q, r))

func set_highlighted(on: bool) -> void:
    _selection_mesh.visible = on

func set_overlay(mat: StandardMaterial3D) -> void:
    _overlay_mesh.material_override = mat
    _overlay_mesh.visible = true

func clear_overlay() -> void:
    _overlay_mesh.visible = false
```

### C2. `MapBuilder`
- Iterates a `MapData`'s tiles, instances a `HexTile` for each, registers it by axial coord, and computes a focus center for the camera.
- **Done:** building `forest_clearing` produces the full tile set at correct positions/elevations.

```gdscript
# src/map/map_builder.gd
class_name MapBuilder
extends Node3D

var tiles: Dictionary = {}   # Vector2i -> HexTile

func build(map: MapData) -> void:
    var mesh := TileMesh.make_hex_mesh()
    var highlight := HighlightMaterial.make()
    for t: TileRecord in map.tiles:          # typed TileRecord — no dict key parsing
        var tile := HexTile.new()
        tile.setup(t.q, t.r, t.elevation, t.terrain, mesh,
            TerrainPalette.material_for(t.terrain), highlight)
        add_child(tile)
        tiles[t.coord()] = tile
    Logger.log_msg(Logger.Level.INFO, "MapBuilder", "built %d tiles" % tiles.size())

func focus_center() -> Vector3:
    if tiles.is_empty():
        return Vector3.ZERO
    var sum := Vector3.ZERO
    for tile in tiles.values():
        sum += tile.position
    return sum / float(tiles.size())
```

### C3. Get the tile from a collider hit
- Helper to resolve a raycast `collider` back to its `HexTile` (the collider is a child of the tile node).
- **Done:** a hit collider reliably yields its `HexTile`.

```gdscript
# in tile_picker.gd (Group E) or a shared util
static func tile_from_collider(node: Node) -> HexTile:
    var n := node
    while n != null and not (n is HexTile):
        n = n.get_parent()
    return n as HexTile
```

---

## Group D — FFT-Style Camera Rig

*Independent of C; can be built against a placeholder. Implements spec §6.*

### D1. Camera rig (pivot + orthographic camera)
- A pivot `Node3D` with a child `Camera3D` at fixed pitch; orthographic for the FFT look.
- **Done:** the map is visible from a fixed top-down-ish angle.

```gdscript
# src/map/camera_rig.gd
class_name CameraRig
extends Node3D   # this node is the pivot/focus

@export var pitch_deg: float = 40.0
@export var distance: float = 14.0
@export var zoom: float = 10.0
@export var zoom_min: float = 4.0
@export var zoom_max: float = 20.0
@export var pan_speed: float = 8.0

var _yaw_index: int = 0          # 0..3 → 0/90/180/270
var _camera: Camera3D

func _ready() -> void:
    _camera = Camera3D.new()
    _camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    _camera.size = zoom
    add_child(_camera)
    _apply_transform()

func _apply_transform() -> void:
    rotation.y = deg_to_rad(_yaw_index * 90.0)
    var pitch := deg_to_rad(pitch_deg)
    _camera.position = Vector3(0.0, sin(pitch) * distance, cos(pitch) * distance)
    _camera.look_at(global_position, Vector3.UP)
```

### D2. Rotate (four snap views), zoom, pan
- Rotate steps `_yaw_index` by ±1 and animates to the snap angle; zoom clamps `_camera.size`; pan moves the pivot on X/Z.
- **Done:** all three controls work and stay within sensible bounds.

```gdscript
func rotate_view(dir: int) -> void:           # dir = -1 or +1
    _yaw_index = wrapi(_yaw_index + dir, 0, 4)
    var target := deg_to_rad(_yaw_index * 90.0)
    create_tween().tween_property(self, "rotation:y", target, 0.2)

func zoom_by(delta: float) -> void:
    zoom = clampf(zoom + delta, zoom_min, zoom_max)
    _camera.size = zoom

func pan(input: Vector2, dt: float) -> void:   # screen-relative pan on ground plane
    var basis_xz := Basis(Vector3.UP, rotation.y)
    var move := basis_xz * Vector3(input.x, 0.0, input.y) * pan_speed * dt
    global_position += move
```

### D3. Input wiring
- Map keys/mouse to `rotate_view` (e.g., Q/E), `zoom_by` (wheel), and `pan` (WASD/edge/middle-drag). Define input actions in Project Settings.
- **Done:** controls respond; pitch stays fixed.

---

## Group E — Tile Picking, Highlight & Debug Readout

*Depends on C (colliders) + D (camera). Implements spec §7.*

### E1. Raycast picker
- On click, raycast from the camera through the cursor; resolve the hit to a `HexTile`; select + highlight it.
- **Done:** clicking any tile selects exactly that tile.

```gdscript
# src/map/tile_picker.gd
extends Node

@export var camera_path: NodePath
var _selected: HexTile = null

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        _pick(event.position)

func _pick(screen_pos: Vector2) -> void:
    var cam := get_node(camera_path) as Camera3D
    if cam == null:
        return
    var from := cam.project_ray_origin(screen_pos)
    var to := from + cam.project_ray_normal(screen_pos) * 1000.0
    var space := get_viewport().world_3d.direct_space_state
    var query := PhysicsRayQueryParameters3D.create(from, to)
    var hit := space.intersect_ray(query)
    if hit.is_empty():
        return
    var tile := HexTile.tile_from_collider(hit["collider"])  # see C3
    if tile:
        _select(tile)

func _select(tile: HexTile) -> void:
    if _selected:
        _selected.set_highlighted(false)
    _selected = tile
    tile.set_highlighted(true)
    DebugReadout.show_tile(tile)   # E2
```

### E2. Debug coordinate readout
- A minimal `CanvasLayer` label (dev-only) showing the selected tile's `q, r`, elevation, terrain. Routes through the Phase 0 `Logger` too.
- **Done:** selecting a tile updates the on-screen label.

```gdscript
# src/debug/debug_readout.gd  (Autoload: DebugReadout)
extends CanvasLayer

@onready var _label: Label = $Label

func show_tile(tile) -> void:
    _label.text = "(%d, %d)  elev %d  %s" % [tile.q, tile.r, tile.elevation, tile.terrain]
    Logger.log_msg(Logger.Level.INFO, "Picker",
        "Tile (%d,%d) elev %d %s" % [tile.q, tile.r, tile.elevation, tile.terrain])
```

---

## Group F — Sample Map & Scene Wiring

*Ties A–E together. Depends on Phase 1 map loading.*

### F1. Author `forest_clearing` map data
- A small varied map (mixed elevation + terrain) under `data/maps/`, valid per the Phase 1 `MapData` schema/validator.
- **Done:** the map loads clean via `GameData.get_map("forest_clearing")`.

```json
// data/maps/forest_clearing.json (excerpt — author a full small grid)
{
  "id": "forest_clearing",
  "tier": "standard",
  "tiles": [
    { "q": 0, "r": 0, "elevation": 0, "terrain": "grass" },
    { "q": 1, "r": 0, "elevation": 1, "terrain": "brush" },
    { "q": 2, "r": 0, "elevation": 2, "terrain": "trees" },
    { "q": 0, "r": 1, "elevation": 0, "terrain": "shallow_water" },
    { "q": 1, "r": 1, "elevation": 3, "terrain": "rocks" }
  ],
  "deployment_zones": { "playerA": ["0,0"], "playerB": ["2,0"] }
}
```

### F2. Map scene
- A `MapScene` that, on ready, gets the `MapData`, builds it (`MapBuilder`), centers the `CameraRig` on `focus_center()`, and wires the `TilePicker` to the rig's camera.
- **Done:** running the scene shows the map with working camera + selection.

```gdscript
# scenes/map/map_scene.gd
extends Node3D

@export var map_id: String = "forest_clearing"

func _ready() -> void:
    var map: MapData = GameData.get_map(map_id)
    var builder := MapBuilder.new()
    add_child(builder)
    builder.build(map)

    var rig := CameraRig.new()
    rig.global_position = builder.focus_center()
    add_child(rig)

    var picker = preload("res://src/map/tile_picker.gd").new()
    picker.camera_path = rig.get_node("Camera3D").get_path()
    add_child(picker)
```

### F3. Make it runnable
- Set `MapScene` as the run scene (or reachable from `Main`). Confirm boot → render → interact with no errors.
- **Done:** the project runs straight into the rendered map.

---

## Group G — Verification

*Math is unit-tested; visuals are checklist-verified.*

### G1. Hex → world unit tests (GUT)
- Verify `hex_to_world` for known coordinates and elevation scaling.
- **Done:** green, headless.

```gdscript
# tests/core/test_hex_world.gd
extends GutTest

func test_origin() -> void:
    assert_eq(HexWorld.hex_to_world(0, 0, 0), Vector3(0, 0, 0))

func test_q_axis() -> void:
    var w := HexWorld.hex_to_world(1, 0, 0)
    assert_almost_eq(w.x, 1.5, 0.0001)                 # HEX_SIZE * 3/2
    assert_almost_eq(w.z, 0.8660254, 0.0001)           # HEX_SIZE * sqrt3/2
    assert_eq(w.y, 0.0)

func test_elevation_scales_y() -> void:
    assert_almost_eq(HexWorld.hex_to_world(0, 0, 4).y, 2.0, 0.0001)  # 4 * ELEV_UNIT(0.5)
```

### G2. Manual render/camera/picking checklist (with screenshots)
- [ ] `forest_clearing` renders all tiles at correct relative positions.
- [ ] Each terrain type is visually distinct; water is translucent.
- [ ] Elevation differences are visible (note the accepted "floating tile" look).
- [ ] Camera pans, zooms, and snap-rotates through all four views; pitch stays fixed.
- [ ] Tiles are readable (not occluded confusingly) from every view on a varied-elevation map.
- [ ] Clicking each tile highlights it and the debug readout shows correct `q,r`/elevation/terrain.
- **Done:** checklist passes; screenshots captured for the four camera views.

---

## Dependency Map

```
A (hex→world) ──┐
                ├──> C (tile node + builder) ──┐
B (mesh+mats) ──┘                              ├──> E (picking + readout) ──> F (scene wiring)
D (camera rig) ────────────────────────────────┘
A ──> G1 (math tests);  C–F ──> G2 (manual checklist)
```

**Suggested first pass:** A1 → B1–B3 → C1–C3 → D1–D3 → E1–E2 → F1–F3 → G. Build D against a placeholder tile early so the camera can be tuned in parallel with C.

---

## Phase 2 Definition of Done

- [ ] `HexWorld.hex_to_world` (flat-top) with `HEX_SIZE`/`ELEV_UNIT`; math tests green (A, G1).
- [ ] Shared hex mesh + terrain material palette + highlight material (B).
- [ ] Multi-layer `HexTile` node (base/overlay/selection meshes + collider + metadata) and `MapBuilder` from `MapData` using `TileRecord` (C).
- [ ] Overlay and selection layers are independent — a tile can be both highlighted and overlaid simultaneously (C1).
- [ ] FFT-style `CameraRig`: fixed pitch, four snap views, zoom, pan, input wired (D).
- [ ] Raycast `TilePicker` with selection-layer highlight and debug readout (E).
- [ ] `forest_clearing` authored, loads clean, and renders in a runnable `MapScene` (F).
- [ ] Manual render/camera/picking checklist passed with screenshots (G2).
- [ ] Git tag `phase-2-complete`.
