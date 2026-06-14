# Phase 9 — Implementation Plan

**Source spec:** `phase9-spec.md`
**Builds on:** `phase1` (data layer: AbilityData, ItemData, BattleUnit), `phase2` (3D map, HexWorld), `phase7` (DraftScene UI), `phase8` (PawnFactory drawing primitives, BattleHUD, PawnManager, BattleController)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages with dependency order. Cross-group dependencies noted.
**Date:** 2026-06-13

---

## How to use this plan

Eight **work groups** (A–H). Group A (atlas generator) is the foundation — it produces the PNG that all other groups consume. Group B (SymbolAtlas lookup) depends on A. Groups C, D, E, and F depend on B and can be done in parallel. Group G (tests) trails the logic. Group H is manual verification.

Phase 9 spans three layers: **asset generation** (A — procedural atlas PNG), **data lookup** (B — SymbolAtlas class), and **UI integration** (C–F — HUD, Draft UI, 3D map, combat log).

> **Carry-over:** consumes `PawnFactory` drawing primitives from Phase 8; `BattleHUD` UI panels and `append_log()` from Phase 8; `PawnManager` pawn tracking from Phase 8; `BattleController` action flow from Phase 8; `DraftScene._build_character_card()` from Phase 7; `AbilityData`, `ItemData`, `BattleUnit.status_effects` from Phase 1; `HexWorld.hex_to_world()` from Phase 2.

---

## Group A — Atlas Generator (Foundation)

*No dependencies on other new code. Reuses PawnFactory drawing primitives.*

### A1. Extract or expose drawing primitives

The following PawnFactory static methods are needed by `IconAtlasGenerator`. Since they are static and accessible despite the `_` prefix in GDScript, they can be called directly. Alternatively, extract to a shared `DrawPrimitives` class.

**Decision:** Call `PawnFactory._safe_pixel()`, `PawnFactory._draw_thick_line()`, etc. directly. This avoids creating a new class and keeps changes minimal. If the `_` prefix causes issues, extract later.

**Reference:** `src/map/pawn_factory.gd` lines 230–298 — all drawing primitives.

### A2. `IconAtlasGenerator` — procedural atlas rendering

Static class that generates the full 512×512 sprite atlas by drawing all icons into a single `Image`.

```
# src/map/icon_atlas_generator.gd
class_name IconAtlasGenerator
extends RefCounted

const CELL := 64
const ATLAS_SIZE := 512

static func generate() -> Image
static func save(path: String) -> void

# 5 category frame functions
static func _draw_starburst_frame(img: Image, ox: int, oy: int, fill: Color, outline: Color) -> void
static func _draw_pentagon_frame(img: Image, ox: int, oy: int, fill: Color, outline: Color) -> void
static func _draw_kite_frame(img: Image, ox: int, oy: int, fill: Color, outline: Color) -> void
static func _draw_rounded_rect_frame(img: Image, ox: int, oy: int, fill: Color, outline: Color) -> void
static func _draw_inverted_triangle_frame(img: Image, ox: int, oy: int, fill: Color, outline: Color) -> void

# Interior icon functions (~28)
static func _draw_icon_flame(img: Image, ox: int, oy: int, color: Color, large: bool) -> void
static func _draw_icon_snowflake(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_bolt(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_cross(img: Image, ox: int, oy: int, color: Color, thick: bool) -> void
static func _draw_icon_chevron(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_slash(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_dagger(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_arc(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_fist(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_horn(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_moon(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_sword(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_crossed_daggers(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_bow(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_staff(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_rapier(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_axe(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_sling(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_chain(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_breastplate(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_shield(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_wristguard(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_pouch(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_eye_crossed(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_shield_up(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_boot(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_hourglass(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_question(img: Image, ox: int, oy: int, color: Color) -> void
```

**Reference patterns:**
- `src/map/pawn_factory.gd` — `_draw_race_frame()` and `_draw_class_icon()` for the drawing approach
- `src/map/pawn_factory.gd` lines 80–226 — existing frame and icon implementations to follow as patterns

**Frame drawing details:**

Each frame function draws within a 64×64 cell at offset `(ox, oy)`. The center of the cell is `(ox + 32, oy + 32)`. Frame radius/size is approximately 26px (leaving 6px margin on each side). Outline is 2px stroke.

- **Starburst (spells):** 8-pointed star polygon. Compute 16 vertices alternating between outer radius (26) and inner radius (14), connect with Bresenham lines, scanline fill the interior.
- **Pentagon (skills):** 5 vertices at 72° intervals starting from top center. Polygon fill + outline.
- **Kite shield (weapons):** 4-vertex polygon: top-center, left-center, right-center, and pointed bottom. Wider at the top, narrows to a point below center.
- **Rounded rectangle (equipment):** Rectangle with corner radius ~6px. Fill the interior, then outline. Corner rounding achieved by drawing quarter-circles at each corner.
- **Inverted triangle (status):** 3 vertices: top-left, top-right, bottom-center. Polygon fill + outline.

**`generate()` flow:**
1. Create `Image.create(512, 512, false, Image.FORMAT_RGBA8)`.
2. Fill with transparent (`Color(0, 0, 0, 0)`).
3. For each entry in the icon map (see spec §4.3), compute `ox = col * 64`, `oy = row * 64`.
4. Draw the appropriate category frame with category fill color (element-tinted for spells).
5. Draw the interior icon in white.
6. Return the `Image`.

**`save()` flow:**
1. Call `generate()`.
2. Ensure the output directory exists (`DirAccess.make_dir_recursive_absolute()`).
3. Call `img.save_png(path)`.

---

## Group B — SymbolAtlas Lookup

*Depends on: Group A (the atlas PNG must exist for runtime loading).*

### B1. `SymbolAtlas` — static icon lookup class

```
# src/core/data/symbol_atlas.gd
class_name SymbolAtlas
extends RefCounted

const CELL_SIZE := 64
const ATLAS_PATH := "res://assets/icons/symbol_atlas.png"

const ICON_MAP := { ... }  # Full mapping from spec §4.3

static var _atlas: Texture2D = null
static var _cache: Dictionary = {}

static func get_icon(id: String) -> AtlasTexture
static func _ensure_loaded() -> void
static func _make_region(col: int, row: int) -> AtlasTexture
```

**Reference pattern:** `src/map/pawn_factory.gd` — `_symbol_cache` and `make_symbol_texture()` for the static caching pattern.

**Implementation details:**

- `_ensure_loaded()`: Checks `_atlas != null`. If null, loads via `load(ATLAS_PATH)` or `Image.load_from_file()` + `ImageTexture.create_from_image()`. The latter works in headless tests; `load()` requires the resource system.
- `get_icon(id)`: If `id` not in `ICON_MAP`, recurse with `"_fallback"`. If in `_cache`, return cached. Otherwise, get `Vector2i(col, row)` from `ICON_MAP`, call `_make_region(col, row)`, cache, return.
- `_make_region(col, row)`: Creates an `AtlasTexture`, sets `atlas = _atlas`, sets `region = Rect2(col * CELL_SIZE, row * CELL_SIZE, CELL_SIZE, CELL_SIZE)`, returns it.

---

## Group C — HUD Integration

*Depends on: Group B (SymbolAtlas lookup).*

### C1. Action button icons

Modify `BattleHUD._build_bottom_bar()` and `_make_action_btn()` to add a 24×24 `TextureRect` icon before each button's text.

**Approach:** Use `Button.icon` property (Godot 4 supports setting an icon on a Button directly). Set `btn.icon = SymbolAtlas.get_icon("action_attack")` etc.

**Modified method:** `_make_action_btn()` in `src/ui/battle_hud.gd` line 507.

```gdscript
func _make_action_btn(text: String, action_type: int, icon_id: String = "") -> Button:
    var btn := Button.new()
    btn.text = text
    btn.custom_minimum_size = Vector2(90, 36)
    if not icon_id.is_empty():
        btn.icon = SymbolAtlas.get_icon(icon_id)
    btn.pressed.connect(func() -> void: action_selected.emit(action_type))
    _action_panel.add_child(btn)
    return btn
```

**Callers updated:**
- `_btn_attack = _make_action_btn("Attack [F]", ACTION_ATTACK, "action_attack")`
- `_btn_defend = _make_action_btn("Defend [G]", ACTION_DEFEND, "action_defend")`
- `_btn_wait = _make_action_btn("Wait [X]", ACTION_WAIT, "action_wait")`

The Abilities and Items buttons (not created via `_make_action_btn`) are updated directly:
- `_btn_abilities.icon = SymbolAtlas.get_icon("action_ability")`
- `_btn_items.icon = SymbolAtlas.get_icon("action_item")`

### C2. Ability popup icons

Modify `BattleHUD._populate_ability_panel()` to add icons to each ability button.

**Modified method:** `_populate_ability_panel()` in `src/ui/battle_hud.gd` line 526.

```gdscript
# Add after creating btn:
btn.icon = SymbolAtlas.get_icon(ability.id)
```

**Reference:** Existing `_populate_ability_panel()` at line 526 creates `Button` nodes per ability.

### C3. Item popup icons

Modify `BattleHUD._populate_item_panel()` to add icons to each item button.

**Modified method:** `_populate_item_panel()` in `src/ui/battle_hud.gd` line 566.

```gdscript
# Add after creating btn:
btn.icon = SymbolAtlas.get_icon(item.id)
```

### C4. Status effect display icons

Replace `BattleHUD._status_label` (plain `Label`) with an `HBoxContainer` of `[TextureRect + Label]` pairs.

**Modified method:** `_update_status_display()` in `src/ui/battle_hud.gd` line 615.

```gdscript
func _update_status_display(unit: BattleUnit) -> void:
    # Clear existing children from _status_container
    for child in _status_container.get_children():
        child.queue_free()
    if unit.status_effects.is_empty():
        return
    for s in unit.status_effects:
        var icon := TextureRect.new()
        icon.texture = SymbolAtlas.get_icon(s["id"])
        icon.custom_minimum_size = Vector2(16, 16)
        icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        _status_container.add_child(icon)
        var lbl := Label.new()
        lbl.text = "%s(%d)" % [s["id"], s["duration"]]
        lbl.add_theme_font_size_override("font_size", 12)
        _status_container.add_child(lbl)
```

**Prerequisite:** Change `_status_label: Label` to `_status_container: HBoxContainer` in `_build_bottom_bar()`. The container replaces the single Label in the unit info panel.

### C5. Roster sidebar weapon icons

Modify `BattleHUD._update_team_list()` to show the unit's equipped weapon icon (16×16) beside the unit name.

**Modified method:** `_update_team_list()` in `src/ui/battle_hud.gd` line 625.

Add after `name_lbl`:
```gdscript
# Show weapon icon if unit has equipment
if not unit.character.equipment.is_empty():
    var weapon_id: String = unit.character.equipment[0]
    var weapon_icon := TextureRect.new()
    weapon_icon.texture = SymbolAtlas.get_icon(weapon_id)
    weapon_icon.custom_minimum_size = Vector2(16, 16)
    weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    name_row.add_child(weapon_icon)
```

---

## Group D — Draft UI Integration

*Depends on: Group B (SymbolAtlas lookup).*

### D1. Character card equipment and ability icons

Modify `DraftScene._build_character_card()` (or equivalent) to add icon rows for equipment and abilities below the existing character info.

**Modified file:** `src/ui/draft_scene.gd`

**Implementation:**
1. After existing character info (name, class, stats), add an equipment row:
   - `HBoxContainer` with 16×16 `TextureRect` nodes for each item in `character.equipment`.
2. Add an abilities row:
   - `HBoxContainer` with 16×16 `TextureRect` nodes for each ability in `character.abilities`.
3. Icons loaded via `SymbolAtlas.get_icon(id)`.

**Reference:** Existing `DraftScene._build_character_card()` builds character cards programmatically.

---

## Group E — Map Status Markers

*Depends on: Group B (SymbolAtlas lookup).*

### E1. `StatusMarker` — 3D billboard marker

A lightweight Node3D that displays a status effect icon as a billboard quad above a pawn.

```
# src/map/status_marker.gd
class_name StatusMarker
extends MeshInstance3D

var status_id: String

static func create(id: String) -> StatusMarker
    # Creates a StatusMarker with a QuadMesh (0.15 × 0.15)
    # Material: unshaded, billboard, alpha_scissor
    # Texture: SymbolAtlas.get_icon(id)
```

**Reference patterns:**
- `src/map/unit_pawn.gd` — symbol face `MeshInstance3D` setup (PlaneMesh, ALPHA_SCISSOR, unshaded)
- `src/map/pawn_factory.gd` — `symbol_material()` for material configuration

**Material setup:**
```gdscript
var mat := StandardMaterial3D.new()
mat.albedo_texture = SymbolAtlas.get_icon(status_id)
mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
mat.alpha_scissor_threshold = 0.1
mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
```

### E2. PawnManager status marker management

Add status marker tracking to `PawnManager`. The controller calls `update_status_markers(unit)` after any action that may change statuses.

**Modified file:** `src/map/pawn_manager.gd`

```gdscript
var _markers: Dictionary = {}  # BattleUnit → Array[StatusMarker]

func update_status_markers(unit: BattleUnit) -> void:
    # 1. Remove existing markers for this unit
    # 2. For each status in unit.status_effects:
    #    - Create StatusMarker.create(status["id"])
    #    - Position above the pawn with horizontal offset for stacking
    #    - Add as child of the UnitPawn
    # 3. Store in _markers

func _clear_markers(unit: BattleUnit) -> void:
    # Remove and free all markers for this unit
```

**Positioning:** First marker at `Vector3(0, 0.25, 0)` relative to pawn. Additional markers offset by `Vector3(0.18, 0, 0)` per index (horizontal stacking).

### E3. BattleController integration

Add `_pawn_manager.update_status_markers(unit)` calls in `BattleController` after:
- `TurnActions.execute_ability()` (status effects may be applied)
- `TurnActions.execute_use_item()` (e.g., smoke_bomb applies blind)
- `TurnActions.execute_defend()` (defend buff applied)
- `RoundManager.start_round()` (status durations tick, some may expire)

**Modified file:** `src/map/battle_controller.gd`

**Reference:** Existing controller pattern — controller already calls `_pawn_manager.highlight_active()` and `_pawn_manager.move_pawn()` after actions.

---

## Group F — Combat Log Icons

*Depends on: Group B (SymbolAtlas lookup).*

### F1. Update `append_log()` signature

Modify `BattleHUD.append_log()` to accept an optional icon ID.

**Modified method:** `append_log()` in `src/ui/battle_hud.gd` line 480.

```gdscript
func append_log(text: String, icon_id: String = "") -> void:
    if icon_id.is_empty():
        # Current behavior: plain Label
        var lbl := Label.new()
        lbl.text = text
        lbl.add_theme_font_size_override("font_size", 12)
        lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        lbl.custom_minimum_size.x = LOG_WIDTH - 20
        _log_list.add_child(lbl)
    else:
        # New: HBoxContainer with icon + label
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 4)
        var icon := TextureRect.new()
        icon.texture = SymbolAtlas.get_icon(icon_id)
        icon.custom_minimum_size = Vector2(12, 12)
        icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        row.add_child(icon)
        var lbl := Label.new()
        lbl.text = text
        lbl.add_theme_font_size_override("font_size", 12)
        lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        lbl.custom_minimum_size.x = LOG_WIDTH - 36
        lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(lbl)
        _log_list.add_child(row)
    _log_count += 1
    # ... trimming and auto-scroll unchanged
```

### F2. BattleController log calls

Update all `_hud.append_log()` calls in `BattleController` to pass the relevant icon ID.

**Modified file:** `src/map/battle_controller.gd`

Examples:
```gdscript
# Attack
_hud.append_log("%s attacks %s for %d damage" % [...], "action_attack")

# Ability
_hud.append_log("%s casts %s on %s — %d damage" % [...], ability_id)

# Item
_hud.append_log("%s uses %s on %s" % [...], item_id)

# Defend
_hud.append_log("%s defends (+2 DEF)" % [...], "action_defend")

# Wait
_hud.append_log("%s waits" % [...], "action_wait")

# Move
_hud.append_log("%s moves to (%d,%d)" % [...], "action_move")

# Round start
_hud.append_log("--- Round %d begins ---" % [...])  # No icon for round markers
```

---

## Group G — Tests

*Depends on: Groups A–F.*

### G1. `test_symbol_atlas.gd` — SymbolAtlas lookup tests

```
# tests/core/data/test_symbol_atlas.gd

- test_get_icon_returns_atlas_texture_for_known_ability
    # SymbolAtlas.get_icon("fire_1") is AtlasTexture, region matches (0*64, 0*64, 64, 64)

- test_get_icon_returns_atlas_texture_for_known_item
    # SymbolAtlas.get_icon("sword") is AtlasTexture, region matches (0*64, 2*64, 64, 64)

- test_get_icon_returns_atlas_texture_for_known_status
    # SymbolAtlas.get_icon("sleep") is AtlasTexture, region matches (0*64, 4*64, 64, 64)

- test_get_icon_fallback_for_unknown_id
    # SymbolAtlas.get_icon("nonexistent") returns a valid AtlasTexture (fallback icon)

- test_get_icon_caches_results
    # Two calls with same ID return the same AtlasTexture instance

- test_all_ability_ids_have_icons
    # For each ability in data/abilities/*.json, SymbolAtlas.get_icon(id) returns non-fallback

- test_all_item_ids_have_icons
    # For each item in data/items/*.json, SymbolAtlas.get_icon(id) returns non-fallback
```

**Note:** These tests require the atlas PNG to exist. Either generate it in `before_all()` via `IconAtlasGenerator.save()`, or ensure it exists as a committed asset.

### G2. `test_icon_atlas_generator.gd` — atlas generation tests

```
# tests/map/test_icon_atlas_generator.gd

- test_generate_returns_512x512_image
    # Image dimensions are 512×512

- test_generate_has_rgba8_format
    # Image.get_format() == Image.FORMAT_RGBA8

- test_cell_has_non_transparent_pixels
    # For each icon in ICON_MAP, the 64×64 cell at (col*64, row*64)
    # contains at least some non-transparent pixels

- test_reserved_cells_are_transparent
    # Cells in rows 6–7 are fully transparent

- test_save_creates_file
    # After save(), the file exists at the specified path
```

### G3. `test_status_marker.gd` — status marker tests

```
# tests/map/test_status_marker.gd

- test_create_returns_mesh_instance
    # StatusMarker.create("sleep") is MeshInstance3D

- test_marker_has_billboard_material
    # Material has billboard_mode == BILLBOARD_ENABLED

- test_marker_is_unshaded
    # Material has shading_mode == SHADING_MODE_UNSHADED
```

---

## Group H — Manual Verification

*Depends on: Groups A–G (all implementation and tests complete).*

### H1. Atlas visual inspection

1. Run `IconAtlasGenerator.save("res://assets/icons/symbol_atlas.png")`.
2. Open the PNG in an image viewer.
3. **Verify:** 8×8 grid visible. Each icon has a distinct frame shape and recognizable interior icon. Empty cells are transparent.
4. **Verify:** Spell row has starburst frames with element-tinted fills.
5. **Verify:** Skill row has pentagon frames with orange fills.
6. **Verify:** Weapon row has kite frames with grey fills.
7. **Verify:** Equipment row has rounded-rect frames with brown fills.
8. **Verify:** Status row has inverted-triangle frames with dark red fills.
9. **Verify:** Fallback icon shows "?" in a plain circle.

### H2. HUD icon verification

1. Launch game → Draft → Start battle.
2. Activate a unit.
3. **Verify:** Action buttons (Attack, Defend, Wait) show icons beside text.
4. **Verify:** Abilities and Items buttons show category icons.
5. Click Abilities ▼ → **Verify:** Each ability button shows the correct spell/skill icon.
6. Click Items ▼ → **Verify:** Each item button shows the correct item icon.
7. Apply a status effect (e.g., use Smoke Bomb to apply blind) → **Verify:** Unit info panel shows blind icon beside "blind(2)".

### H3. Map status marker verification

1. Apply a status effect to a unit.
2. **Verify:** A small billboard icon appears floating above the affected pawn token.
3. **Verify:** The icon faces the camera at all rotation angles.
4. Apply a second status effect → **Verify:** Two icons appear side by side.
5. Wait for status to expire → **Verify:** Icon disappears.

### H4. Combat log icon verification

1. Execute an attack → **Verify:** Log entry has a sword icon before the text.
2. Cast a spell → **Verify:** Log entry has the spell's icon.
3. Defend → **Verify:** Log entry has a shield icon.
4. Wait → **Verify:** Log entry has an hourglass icon.

### H5. Draft UI icon verification

1. Open Draft scene.
2. **Verify:** Character cards show equipment icons (weapon, armor) below character info.
3. **Verify:** Character cards show ability icons (spells, skills) below equipment.

### H6. Readability at display sizes

1. **64×64** (atlas native): icons are clear and detailed.
2. **24×24** (HUD buttons): frame shape recognizable, interior icon distinguishable.
3. **16×16** (roster, status): frame shape recognizable, interior may be simplified.
4. **12×12** (combat log): frame shape still provides category identification.

---

## Suggested implementation order

```
A (IconAtlasGenerator) ─→ B (SymbolAtlas) ─┬─→ C (HUD integration)
                                             ├─→ D (Draft UI integration)
                                             ├─→ E (Map status markers)
                                             └─→ F (Combat log icons)
                                                        │
                                             G (Tests) ←┘
                                                        │
                                             H (Manual verification) ←┘
```

A → B is the critical path. Once B is complete, C, D, E, and F can be done in parallel.

---

## File manifest

### New files

| File | Class | Group | Description |
|------|-------|-------|-------------|
| `src/map/icon_atlas_generator.gd` | `IconAtlasGenerator` | A | Procedural sprite atlas generation |
| `src/core/data/symbol_atlas.gd` | `SymbolAtlas` | B | Static icon lookup by entity ID |
| `src/map/status_marker.gd` | `StatusMarker` | E | 3D billboard marker for status effects |
| `assets/icons/symbol_atlas.png` | — | A | Generated sprite atlas (512×512) |
| `tests/core/data/test_symbol_atlas.gd` | — | G | SymbolAtlas GUT tests |
| `tests/map/test_icon_atlas_generator.gd` | — | G | Atlas generator GUT tests |
| `tests/map/test_status_marker.gd` | — | G | StatusMarker GUT tests |

### Modified files

| File | Group | Changes |
|------|-------|---------|
| `src/ui/battle_hud.gd` | C, F | Add icons to action buttons, ability/item popups, status display, roster sidebar; update `append_log()` with optional icon |
| `src/ui/draft_scene.gd` | D | Add equipment and ability icon rows to character cards |
| `src/map/pawn_manager.gd` | E | Add `_markers` dictionary, `update_status_markers()`, `_clear_markers()` |
| `src/map/battle_controller.gd` | E, F | Add `update_status_markers()` calls after actions; pass icon IDs to `append_log()` |

---

## Definition of Done

- [ ] `IconAtlasGenerator.generate()` produces a 512×512 Image with all icon cells populated
- [ ] `IconAtlasGenerator.save()` writes `assets/icons/symbol_atlas.png` to disk
- [ ] `SymbolAtlas.get_icon(id)` returns correct `AtlasTexture` for all 14 ability IDs
- [ ] `SymbolAtlas.get_icon(id)` returns correct `AtlasTexture` for all 12 item IDs
- [ ] `SymbolAtlas.get_icon(id)` returns correct `AtlasTexture` for all 3 status effect IDs
- [ ] `SymbolAtlas.get_icon("unknown")` returns fallback icon (not null)
- [ ] HUD action buttons display icons
- [ ] HUD ability popup buttons display spell/skill icons
- [ ] HUD item popup buttons display item icons
- [ ] HUD status display shows status effect icons
- [ ] HUD roster sidebar shows weapon icons
- [ ] Draft UI character cards show equipment and ability icons
- [ ] Combat log entries show inline action icons
- [ ] Status markers appear as 3D billboards above affected pawns
- [ ] Status markers appear/disappear correctly with status effect lifecycle
- [ ] All GUT tests pass
- [ ] Manual visual verification confirms readability at all display sizes
- [ ] Git tag `phase-9-complete`
