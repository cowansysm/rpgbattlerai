# Phase A1 — Map Editor (Dev Tool) Specification

**Parent plan:** `alpha-implementation-plan.md` (Phase A1)
**Master spec:** `alpha-specs.md` (§3 Map Editor)
**Builds on (Alpha):** `alpha-phaseA0-spec.md` (`Dev` flag + Dev Tools menu, `MapSerializer` condensed format, terrain effect schema)
**Builds on (MVP):** `phase2-spec.md` (`MapBuilder`, `HexTile`, `CameraRig`, `TilePicker`, `TerrainPalette`), `phase1` (`MapData`, `TileRecord`, `Validator`)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-17

---

## 1. Purpose & Scope

Phase A1 delivers the **map editor**: a GUI tool, reachable only in dev mode, for authoring maps visually instead of hand-editing JSON. It is the first consumer of A0's `Dev` flag (entry point) and `MapSerializer` (save format), and it reuses the MVP's entire map-rendering stack (`MapBuilder`, `HexTile`, `CameraRig`, `TilePicker`) rather than drawing anything new.

The editor is an **internal developer tool** in the Alpha (per the master-spec decision). The architecture is split so a player-facing editor later is a re-skin, not a rewrite: a **headless `MapEditorModel`** owns all editable state and mutation logic and is fully unit-testable; the **editor scene** is a thin controller that renders the model and routes input.

### In scope

- A headless **`MapEditorModel`**: editable map state, mutation operations (terrain, elevation, tile add/remove, deployment zones, metadata), bounded **undo/redo**, and conversion to/from `MapData`.
- An **editor scene** that renders the model via `MapBuilder`, drives the FFT `CameraRig`, selects/paints tiles via `TilePicker`/`DragHandler`, and refreshes on edits.
- Editor **UI**: terrain palette, elevation brush, deployment-zone tools, metadata fields, file operations (new/load/save), and inline validation feedback.
- **File I/O**: load any existing map (condensed or verbose), save as A0 condensed minified JSON after validation.
- **Access** wired into A0's Dev Tools menu.

### Out of scope

- A player-facing entry point, map sharing/distribution, in-editor playtesting (deferred per master spec §3.5).
- Prefab/decoration brushes beyond terrain (cosmetic markers are MVP `TerrainPalette` behavior; no new decoration authoring here).
- New terrain *types* or bulk map content (Phase A9) — the editor consumes whatever `terrain.json` defines.
- Per-tile effect overrides (`tile_effects` remains deferred from A0).

### Exit criteria

Phase A1 is complete when:

1. A developer opens the editor from the Dev Tools menu (and cannot reach it with the dev flag off).
2. They can create a new blank map of a chosen size, paint terrain, raise/lower elevation, mark deployment zones, and edit metadata, with the 3D view updating live.
3. Undo/redo correctly reverts and reapplies edits within a bounded history.
4. Saving validates the map and writes A0 condensed minified JSON; an invalid map surfaces a clear inline error instead of writing.
5. Loading an existing map (condensed or verbose) reproduces it exactly for editing, and `to_map_data(from_map_data(x)) == x` holds for the model.
6. `MapEditorModel` operations are covered by headless unit tests; the GUI is verified by a documented manual checklist.

---

## 2. Design Decisions (Phase A1)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Model / UI split** | All editable state and mutations live in a headless **`MapEditorModel`** (`RefCounted`, no scene-tree dependency); the editor scene is a thin controller. | Mirrors the MVP core/UI separation; makes the editor unit-testable and a future player-facing editor a re-skin (master spec §3.3). |
| **Rendering reuse** | Reuse `MapBuilder`/`HexTile` for display; **incremental refresh** for terrain/elevation edits (update the affected `HexTile`), **full rebuild** for structural edits (add/remove tile). | MVP maps are small (8–14 across); rebuild cost is negligible and keeps code simple. Incremental paths avoid flicker during painting. |
| **Undo/redo** | **Snapshot-based**: push a lightweight snapshot of the model's tile state before each mutation; bounded stack. | Maps are small, so whole-state snapshots are cheap and far simpler/safer than a command-diff system. |
| **Painting input** | Reuse `TilePicker` for single-tile selection and `DragHandler`-style drag for paint strokes; the active **tool** + **brush value** determine what a click/drag does. | Reuses proven raycast picking; one interaction model for select, paint, and zone-mark. |
| **Save-time validation** | Validate the **typed model/`MapData`**, not re-serialized JSON. | A0's condensed tiles are arrays; the boot `Validator.validate_map` assumes dict tiles. Validating the typed model (terrain ids exist, zones reference real tiles, no duplicate coords) is form-agnostic and testable. |
| **Save format** | Always write A0 **condensed minified JSON** via `MapSerializer`. | One on-disk format; the editor is the canonical producer of condensed maps. |
| **Access** | Launch only from the A0 **Dev Tools menu**; no route exists with `Dev.enabled == false`. | Keeps the tool internal; satisfies master-spec §3.2. |

---

## 3. Architecture

### 3.1 `MapEditorModel` (headless)

A `RefCounted` holding the working map and all mutation logic — no `Node`, no rendering, no input. It is the single source of truth the scene renders.

**State**

- `id: String`, `tier: String`
- `tiles: Dictionary` — `Vector2i → {elevation: int, terrain: String, tags: Array[String]}`
- `zones: Dictionary` — `zone_name → Array[Vector2i]` (e.g., `playerA`, `playerB`, `enemy`, `player`)
- Undo/redo stacks of snapshots.

**Operations** (each pushes an undo snapshot, then mutates):

- `new_map(id, tier, shape, size)` — fill a region with grass at elevation 0.
- `set_terrain(coord, terrain)` / `set_elevation(coord, delta_or_value)`
- `add_tile(coord)` / `remove_tile(coord)`
- `set_zone(coord, zone_name, on)`
- `set_metadata(id, tier)`
- `undo()` / `redo()`
- `to_map_data() -> MapData` / `from_map_data(MapData)`
- `validate() -> Array[String]` — returns errors (empty == valid).

### 3.2 Editor scene (controller)

A scene (under `scenes/editor/`) that owns the rendering and UI nodes and translates user input into `MapEditorModel` calls, then refreshes the view. It holds no map state itself beyond a reference to the model and the current tool selection.

### 3.3 Separation contract

The model never imports scene/UI types; the scene never mutates map data except through model methods. `to_map_data`/`from_map_data` are the only bridge to the game's `MapData`. This contract is what makes the model unit-testable and the UI replaceable.

---

## 4. Editor Operations & Undo

### 4.1 Mutations

Every authoring action maps to one model operation (§3.1). Mutations validate their own preconditions cheaply (e.g., `set_terrain` on a non-existent tile is a no-op or implicitly adds, per tool semantics) and leave the model in a consistent state.

### 4.2 Undo/redo

Before each mutation the model snapshots its tile/zone state onto the undo stack (bounded depth, e.g., 50); a new mutation clears the redo stack. `undo`/`redo` swap snapshots. The scene refreshes fully after undo/redo since arbitrary tiles may change.

### 4.3 Round-trip

`from_map_data(to_map_data(model))` reproduces the model's logical content; combined with A0's `MapSerializer`, a saved-then-loaded map is identical for editing. This is a tested invariant.

---

## 5. Editor UI & Tools

A 2D overlay (`CanvasLayer`) over the 3D view. Functional, unstyled (polish is later), keyboard shortcuts alongside buttons.

| Panel / Tool | Function |
|--------------|----------|
| **Tool selector** | Choose the active tool: Paint Terrain, Raise/Lower Elevation, Add/Remove Tile, Zone Mark, Inspect. |
| **Terrain palette** | Buttons for each terrain id from `terrain.json` (data-driven, not hard-coded); selecting sets the paint value. Uses `TerrainPalette` colors for swatches. |
| **Elevation controls** | Raise/lower brush (±1) and a set-to-value option; clamped to the MVP elevation range. |
| **Zone tools** | Pick a zone (`playerA`/`playerB`/…); click/drag tiles to add/remove them from the zone; zone membership shown via the tile overlay layer. |
| **Metadata fields** | Edit map `id` and `tier`. |
| **File operations** | New (size/shape prompt), Load (pick from `data/maps/`), Save / Save As. |
| **Validation feedback** | A status line / list showing `model.validate()` results; Save is blocked while errors exist. |
| **Tile inspector** | Selecting a tile shows its `q,r`, elevation, terrain, tags, and zone membership (reuses the A0-gated `DebugReadout` conventions). |
| **Undo / redo** | Buttons + shortcuts (Ctrl+Z / Ctrl+Y). |

Painting: with a tool active, clicking a tile applies it; dragging paints a stroke. Add/Remove Tile lets the map grow beyond its initial region or carve non-rectangular shapes.

---

## 6. Rendering & Interaction

- **Display:** the scene builds the model via `MapEditorModel.to_map_data()` → `MapBuilder.build()`, reusing `HexTile` (including elevation walls) and `TerrainPalette`.
- **Camera:** the existing `CameraRig` (fixed pitch, four snap yaws, zoom, pan) is reused unchanged.
- **Picking:** `TilePicker` raycast resolves the clicked `HexTile`; the controller maps it to a `Vector2i` and applies the active tool. `DragHandler`-style drag enables paint strokes and zone sweeps.
- **Refresh strategy:** terrain/elevation edits update the affected `HexTile` in place (swap material / reposition + rebuild its wall); add/remove tile and undo/redo trigger a full `MapBuilder` rebuild. Both are cheap at MVP map sizes.
- **Overlays:** the `HexTile` overlay layer (already independent of selection) is used to visualize deployment zones while editing.

---

## 7. File Operations & Validation

### 7.1 Load

Load reads a map JSON from `data/maps/` through the existing `DataFactory.make_map` (which A0 made dual-form), producing a `MapData` the model imports via `from_map_data`. Both condensed and verbose maps load identically.

### 7.2 Save

Save runs `model.validate()` first:

- **Terrain references** resolve to ids present in `GameData`/`terrain.json`.
- **Deployment zones** reference existing tiles only.
- **No duplicate coordinates**; required metadata (`id`) present.

On success, the model serializes via A0's `MapSerializer.to_json` (condensed, minified) and writes to `data/maps/<id>.json`. On failure, nothing is written and errors appear in the validation panel. Validation operates on the typed model (per §2 decision), independent of on-disk JSON form.

---

## 8. Access (Dev Tools Menu)

The editor is launched only from A0's Dev Tools menu, which exists only when `Dev.enabled`. A0 left the Map Editor button stubbed/disabled ("coming in A1"); A1 enables it to open the editor scene. With the dev flag off there is no navigation path to the editor.

---

## 9. Risks & Notes

- **Validator form mismatch.** The boot `Validator.validate_map` assumes dict-form tiles; A1 deliberately validates the typed model instead of re-serialized JSON. If a future change routes editor saves back through `Validator`, extend it to accept condensed tiles first.
- **Refresh performance.** Full rebuilds on every keystroke would flicker; keep terrain/elevation edits incremental and reserve full rebuilds for structural changes and undo/redo.
- **Undo memory.** Snapshotting is simple but unbounded growth would leak; cap the stack depth.
- **Coordinate growth.** Add-tile lets maps grow arbitrarily; keep camera framing (`focus_center`) and bounds sensible as the tile set changes.
- **Zone/tile consistency.** Removing a tile must also drop it from any deployment zone to avoid dangling zone references (validation would otherwise block save).
- **Scope creep.** No playtesting, sharing, decorations, or new terrain types here — author maps from existing terrain only.

---

## 10. Phase A1 Deliverables Checklist

- [ ] `MapEditorModel` (headless): state, mutations, undo/redo, `to_map_data`/`from_map_data`, `validate()` (§3, §4).
- [ ] Editor scene reusing `MapBuilder`/`HexTile`/`CameraRig`/`TilePicker` with incremental + full refresh (§6).
- [ ] Tool set: paint terrain, elevation brush, add/remove tile, zone mark, inspect (§5).
- [ ] UI panels: terrain palette (data-driven), elevation, zones, metadata, file ops, validation feedback, undo/redo (§5).
- [ ] New map creation (size/shape) producing a blank grass field (§3.1).
- [ ] Load any existing map (condensed or verbose) for editing; round-trip preserved (§7.1, §4.3).
- [ ] Save: validate typed model → write A0 condensed minified JSON; block save on errors (§7.2).
- [ ] Launchable only from the A0 Dev Tools menu; unreachable with the dev flag off (§8).
- [ ] Headless unit tests for `MapEditorModel` (mutations, undo/redo, round-trip, validate); manual GUI checklist completed.
- [ ] Git tag `alpha-phaseA1-complete`.
