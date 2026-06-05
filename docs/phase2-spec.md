# Phase 2 — Hex Map & 3D Representation Specification

**Parent plan:** `rpg-implementation-plan.md` (Phase 2)
**Builds on:** `phase0-spec.md` (hex math, `HexLayout`), `phase1-spec.md` (`MapData` loading)
**Source spec:** `rpg-specs.md` (§3 Maps)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Hex orientation:** Flat-top
**Tile rendering:** Per-tile `MeshInstance3D` nodes · **Elevation:** single tile placed at raised Y
**Tile picking:** Physics raycast · **Camera:** FFT-style fixed angles
**Date:** 2026-05-29

---

## 1. Purpose & Scope

Phase 2 is the first phase that produces something **visible**: a 3D hex map rendered from data, with terrain and elevation, an FFT-style camera, and tile selection. It is the first consumer of the `MapData` that Phase 1 loads and validates but deliberately does not render, and the first use of the flat-top `HexLayout` constants stubbed in Phase 0.

No movement, range, line of sight, units, or combat — Phase 2 draws the board and lets the player look at it and click tiles. Spatial *rules* begin in Phase 3.

### In scope

- A flat-top **hex → world** coordinate mapping built on the Phase 0 `HexLayout` constants.
- A reusable **hex tile mesh** and a **terrain material palette** for the §3.2 terrain types.
- A **map builder** that turns a `MapData` resource into a scene of per-tile `MeshInstance3D` nodes, each placed at its elevation (raised Y) with a collider for picking.
- An **FFT-style camera rig**: fixed pitch, four snap-rotated yaw views, zoom, and pan.
- **Tile selection** via physics raycast, with highlight feedback and a debug coordinate readout.
- A hand-authored sample map (`forest_clearing`) that loads and displays correctly.

### Out of scope

- Pathfinding, reachable-tile overlays, range, and line of sight (Phase 3).
- Characters/units, deployment, combat, UI beyond debug readouts (Phases 4+).
- Animated terrain, water shaders, lighting polish, final art (Phase 10 polish).
- Map editing/authoring tools (content is authored as JSON per Phase 1).

### Exit criteria

Phase 2 is complete when:

1. The flat-top hex → world mapping is implemented and unit-tested for known coordinates.
2. A `MapData` resource (e.g., `forest_clearing`) builds into a 3D scene of per-tile meshes at correct positions and elevations.
3. Each terrain type renders with a visually distinct material; elevation differences are visible.
4. The FFT-style camera pans, zooms, and snap-rotates between four fixed views without disorientation.
5. Clicking a tile selects it via raycast, highlights it, and prints its axial coordinates + elevation + terrain to a debug readout.
6. Hex → world conversion tests pass headless; rendering/camera/picking are verified by a documented manual checklist (screenshots).

---

## 2. Design Decisions (Phase 2)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Tile rendering** | **Per-tile `MeshInstance3D` nodes**, each sharing a single hex-prism (or hex-disc) mesh resource. | Simplest path for small MVP maps (8–14 hexes); per-tile nodes make selection, highlighting, and metadata trivial. Revisit MultiMesh only if tile counts grow. |
| **Elevation** | **Single flat tile placed at raised Y** = `elevation × ELEV_UNIT`. No extruded column under the tile. | Chosen for simplicity. Trade-off: a raised tile can read as "floating" with nothing beneath it (see §5 and Risks). An optional visual skirt/support is deferred and can be added without changing the data model. |
| **Tile picking** | **Physics raycast** from the camera through the cursor against per-tile colliders. | Robust with elevation and overlapping tiles; the hit collider carries the tile's axial coords as metadata, so picking returns coordinates directly without inverse math. |
| **Camera** | **FFT-style fixed angles:** a fixed pitch with four yaw views snapped at 90°, plus pan and zoom. | Faithful to FFT's feel; constrains the view to readable angles and simplifies elevation/LoS reasoning later. |

---

## 3. Coordinate → World Mapping

Phase 2 turns axial hex coordinates into 3D world positions using the **flat-top** layout committed in Phase 0 (`HexLayout`).

### 3.1 Axes

- The hex grid lies on the world **X/Z ground plane**.
- **Elevation** maps to world **Y** (up), scaled by a constant `ELEV_UNIT` (world units per elevation step).

### 3.2 Flat-top hex → world

Given axial `(q, r)`, hex size `S` (`HEX_SIZE`), elevation `e`:

```
world.x = S * (3/2 * q)
world.z = S * (sqrt(3)/2 * q + sqrt(3) * r)
world.y = e * ELEV_UNIT
```

These use the `F0/F2/F3` flat-top constants from `HexLayout`. The tile's mesh is centered at this world position.

### 3.3 World → hex

Not required for picking (raycast carries coordinates). The Phase 0 `cube_round` helper remains available for any future cursor-to-ground projection, but is not the primary picking path in Phase 2.

### 3.4 New layout constants

| Constant | Meaning | Indicative MVP value |
|----------|---------|----------------------|
| `HEX_SIZE` | Hex "radius" (center to corner) in world units | `1.0` |
| `ELEV_UNIT` | World height per elevation step | `0.5` |

These belong with the other tunables and are documented alongside `HexLayout`.

---

## 4. Tile Rendering

### 4.1 Hex tile mesh

A single shared mesh resource for a flat-top hex tile — a thin hex prism or hex disc. All tiles instance this same mesh (one `Mesh`, many `MeshInstance3D`). Orientation matches flat-top (a flat edge facing the default camera).

### 4.2 Per-tile node (multi-layer)

Each tile in the scene carries **multiple visual layers** so that terrain, overlays, and selection can coexist independently:

```
Tile (Node3D)            # positioned at hex→world; holds q,r,elevation,terrain as metadata
├── MeshInstance3D       # BASE layer: shared hex mesh + terrain material (never overridden)
├── MeshInstance3D       # OVERLAY layer: hidden by default; shown for movement/range/target painting
├── MeshInstance3D       # SELECTION layer: hidden by default; shown when the tile is clicked/selected
└── StaticBody3D         # collider for raycast picking (§8)
    └── CollisionShape3D
```

Layers stack vertically (each slightly offset in Y above the previous) so they blend visually. Each layer is shown/hidden independently:

- **Base layer** always shows the terrain material. It is never swapped or overridden.
- **Overlay layer** is toggled by movement/range/target painting (Phase 3+). Future phases (deployment zones, AoE previews, status indicators) can add additional overlay meshes without conflicting.
- **Selection layer** is toggled by the tile picker. It is independent of the overlay layer — a tile can be both selected and within a movement overlay simultaneously.

The tile node stores its axial coordinates, elevation, and terrain type as metadata so selection can report them and later phases can query them.

### 4.3 Terrain material palette

Each terrain type from `rpg-specs.md` §3.2 maps to a distinct material (flat colors are sufficient for the MVP; textures/shaders are Phase 10):

| Terrain | Visual treatment (MVP) |
|---------|------------------------|
| Grass / dirt | Green base |
| Road / stone | Grey |
| Tall grass / brush | Lighter green, slightly raised tuft optional |
| Trees (forest) | Green base + a simple tree marker mesh on top |
| Rocks / boulders | Dark grey + a boulder marker mesh |
| Shallow water | Translucent light blue |
| Deep water | Darker blue |
| Cliff face | Bare rock material (used on raised edges) |

Decoration meshes (tree, boulder) are placeholders; impassability/cover semantics live in data and are consumed in Phase 3, not modeled physically here.

---

## 5. Elevation Representation

Per the chosen approach, a tile at elevation `e` is a **single flat tile placed at world Y = `e × ELEV_UNIT`** — there is no extruded column drawn beneath it.

- Cliffs and plateaus are conveyed purely by the height difference between neighboring tiles.
- **Known trade-off:** with nothing rendered below a raised tile, tall tiles can appear to float. This is accepted for the MVP. A later, optional **skirt/support** (a simple downward extrusion or a column mesh) can be added to ground raised tiles visually without changing `MapData` or the builder's placement logic. This is noted as a Risk (§10) and a candidate Phase 10 polish item.

---

## 6. Camera — FFT-Style Fixed Angles

The camera mimics *Final Fantasy Tactics*: a constrained, readable view rather than free orbit.

### 6.1 Rig

A pivot `Node3D` at a focus point on the map, with a `Camera3D` child offset at a **fixed pitch** (e.g., ~30–45° looking down). The camera looks at the pivot. An **orthographic** projection is recommended for the clean isometric-ish FFT look; perspective is an alternative.

### 6.2 Controls

- **Rotate:** yaw snaps between **four fixed views** 90° apart (e.g., keys to rotate left/right). Rotation animates smoothly to the next snap angle.
- **Zoom:** adjusts orthographic `size` (or camera distance in perspective) between clamped min/max.
- **Pan:** moves the pivot across the X/Z ground plane within map bounds.

### 6.3 Behavior

Pitch is fixed (not user-controlled). The four snap angles keep elevation and tile relationships readable from every view, which matters for the LoS/height rules added in Phase 3.

---

## 7. Tile Selection & Highlighting

### 7.1 Picking — physics raycast

On cursor click, cast a ray from the camera through the cursor (`project_ray_origin` / `project_ray_normal`) and intersect the physics space against tile colliders (§4.2). The first hit identifies the tile; its metadata yields axial coords, elevation, and terrain.

### 7.2 Highlight

The selected tile's **selection layer** mesh is shown with a highlight material. This layer is independent of the overlay layer, so a tile can be both selected and overlaid simultaneously. Hovering may optionally show the selection layer under the cursor. Only one selection at a time in the MVP.

### 7.3 Debug readout

A minimal on-screen label (debug-only, via the Phase 0 `Logger`/debug harness conventions) shows the selected tile's `q, r`, elevation, and terrain. This is a developer aid, not player UI.

---

## 8. Map Scene Composition & Data Flow

1. The map scene is handed a `MapData` id (from `GameData`, loaded in Phase 1).
2. A **map builder** iterates the map's `TileRecord` entries (typed, not raw dicts), computes each world position (§3.2), instances a multi-layer tile node (§4.2), assigns the terrain material (§4.3), positions it at raised Y (§5), and registers its collider.
3. The camera rig is centered on the map's bounds.
4. Selection and the debug readout are wired in.

The builder consumes `MapData` read-only via `GameData`; it does not mutate content. Deployment zones present in `MapData` are ignored visually in Phase 2 (consumed in Phase 4).

---

## 9. Risks & Notes

- **Floating tiles.** The chosen single-tile-at-raised-Y elevation can look like floating tiles where height differences are large. Accepted for MVP; mitigation (optional skirt/support mesh) is deferred and non-breaking.
- **Flat-top correctness.** The hex→world mapping must match the flat-top `HexLayout` constants exactly; a mismatch misaligns the whole grid. Lock with unit tests on known coordinates.
- **Picking vs elevation.** Raycast picking is robust, but ensure colliders sit at the tile's raised Y so hits register at the visible surface.
- **Camera readability.** Fixed pitch + four snaps must keep tall terrain from occluding tiles confusingly; validate by screenshot at each of the four views with a varied-elevation map.
- **Multi-layer tile cost.** Each tile now has three `MeshInstance3D` children (base, overlay, selection) instead of one. On MVP maps (8–14 tiles) this is negligible. If tile counts grow significantly, consider using visibility toggling efficiently or merging overlay/selection into a single switchable mesh.
- **Scope creep.** No movement/LoS/units here — only rendering, camera, and selection. Defer everything spatial-rules-related to Phase 3.
- **Mesh placeholders.** Tree/boulder markers are placeholder art; do not encode gameplay (cover/impassability) in the meshes — that stays in data.

---

## 10. Phase 2 Deliverables Checklist

- [ ] Flat-top hex → world mapping using `HexLayout`, with `HEX_SIZE` / `ELEV_UNIT` constants (§3).
- [ ] Shared hex tile mesh + terrain material palette for all §3.2 terrains (§4).
- [ ] Per-tile node (mesh + collider + metadata) (§4.2).
- [ ] Map builder: `MapData` → positioned tiles at raised Y (§5, §8).
- [ ] FFT-style camera rig: fixed pitch, four snap views, zoom, pan (§6).
- [ ] Raycast tile selection with highlight + debug coordinate readout (§7).
- [ ] Sample map `forest_clearing` loads from data and renders correctly (§8).
- [ ] Hex → world unit tests green (headless); manual render/camera/picking checklist with screenshots completed.
- [ ] Git tag `phase-2-complete`.
