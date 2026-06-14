# Phase 9 — Symbology Expansion Specification

**Parent plan:** `rpg-implementation-plan.md` (Phase 9)
**Builds on:** `phase1-spec.md` (data layer: abilities, items, status effects), `phase2-spec.md` (3D map, hex tiles), `phase7-spec.md` (draft UI, character cards), `phase8-spec.md` (NATO symbology, PawnFactory, BattleHUD, PawnManager, BattleController)
**Source spec:** `rpg-specs.md` (§7.7)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-13

---

## 1. Purpose & Scope

Phase 8 introduced a NATO-inspired symbology system rendered procedurally on 3D unit pawn tokens — race encoded as frame shape, class encoded as interior icon. This system covers only unit identity (race + class) and appears only on the map's 3D token faces.

Phase 9 extends the symbology to cover **all game entities**: abilities (spells and skills), items (weapons and equipment), and status effects. It replaces per-entity procedural drawing with a **sprite atlas** — a single PNG texture containing all icons in a grid, looked up by ID at runtime. The atlas also incorporates race+class identity symbols (previously drawn procedurally by PawnFactory), unifying all game symbology into one texture. Icons are integrated into every UI surface: HUD action/ability/item panels, Draft UI character cards, 3D map status markers, and combat log entries. Any atlas sprite can also be rendered as a 3D world object using the same approach UnitPawn uses for its symbol face.

The atlas is procedurally generated (reusing PawnFactory's pixel-drawing primitives) but designed to be swappable with hand-drawn art later without code changes.

### In scope

- **Sprite atlas generation pipeline**: `IconAtlasGenerator` tool script that procedurally renders all icons into a 512×512 PNG grid, organized by category.
- **SymbolAtlas lookup class**: static class providing `get_icon(id) -> AtlasTexture` for any known ability, item, or status effect. Single texture in GPU memory; all icons are atlas sub-regions.
- **Five category frame shapes** using a dual-overlapping-geometry pattern (two geometric shapes drawn overlapping) with interior icons for each entity:
  - Spells (upward triangle + circle overlap)
  - Skills (pentagon + inverted pentagon overlap)
  - Weapons (hexagon + 90°-rotated square/diamond overlap)
  - Equipment (hexagon + circle overlap)
  - Status effects (inverted triangle + square overlap)
- **Race+class identity sprites (8 combinations)**: the existing procedural race-frame + class-icon pairs (`human_fighter`, `human_archer`, `human_rogue`, `human_bard`, `elf_black_mage`, `elf_red_mage`, `halfling_white_mage`, `dwarf_barbarian`) rendered into the atlas. `PawnFactory.make_symbol_texture()` and `symbol_material()` replaced with `SymbolAtlas` lookups.
- **All atlas sprites usable as 3D tokens**: any sprite in the atlas (items, spells, status effects, race+class identity) can be rendered as a 3D world object using the same PlaneMesh + StandardMaterial3D approach that UnitPawn uses for its symbol face. `SymbolAtlas.make_3d_material(id)` provides a ready-to-use material for any atlas icon.
- **HUD integration**: icons on ability popup buttons, item popup buttons, status effect display in unit info panel, and action buttons (Attack, Defend, Move, Wait, Abilities, Items).
- **Draft UI integration**: equipment and ability icons on character cards.
- **Map integration**: floating 3D status effect markers above affected pawns.
- **Combat log integration**: small inline icons before action text entries.

### Out of scope

- Animated icons, particle effects, or icon transitions.
- Hand-drawn replacement art (the atlas is procedurally generated; hand-drawn art can replace the PNG later without code changes).
- Icon tooltip system (hover for name/description) — deferred to a future phase.
- Victory/rout detection, AI, audio, or any non-symbology features.

### Exit criteria

1. A 512×512 sprite atlas PNG exists at `res://assets/icons/symbol_atlas.png` with all icons organized by category row.
2. `SymbolAtlas.get_icon(id)` returns a correctly-cropped `AtlasTexture` for every ability ID (`fire_1`, `fire_2`, `ice_1`, `thunder_1`, `cure_1`, `cure_2`, `shield_1`, `power_strike`, `backstab`, `reckless_swing`, `rage`, `inspire`, `lullaby`, `smoke_bomb`).
3. `SymbolAtlas.get_icon(id)` returns a correctly-cropped `AtlasTexture` for every item ID (`sword`, `daggers`, `bow`, `staff`, `rapier`, `greataxe`, `sling`, `light_armor`, `medium_armor`, `shield`, `bracer_of_accuracy`, `smoke_bomb_pouch`).
4. `SymbolAtlas.get_icon(id)` returns a correctly-cropped `AtlasTexture` for status effect IDs (`sleep`, `blind`, `defend`).
5. `SymbolAtlas.get_icon("unknown_id")` returns a fallback "?" icon rather than null.
6. `SymbolAtlas.get_icon(id)` returns a correctly-cropped `AtlasTexture` for all 8 race+class IDs (`human_fighter`, `human_archer`, `human_rogue`, `human_bard`, `elf_black_mage`, `elf_red_mage`, `halfling_white_mage`, `dwarf_barbarian`).
7. `PawnFactory.make_symbol_texture()` and `symbol_material()` delegate to `SymbolAtlas` instead of procedural drawing. Existing `UnitPawn.setup()` behavior is unchanged (same visual result, different source).
8. `SymbolAtlas.make_3d_material(id)` returns a `StandardMaterial3D` suitable for `MeshInstance3D` use, with correct alpha, unshaded mode, and the atlas sub-region as albedo texture. Any atlas icon can be placed on a 3D PlaneMesh/QuadMesh.
9. HUD ability popup buttons display the correct spell/skill icon beside the ability name.
10. HUD item popup buttons display the correct item icon beside the item name.
11. HUD unit info panel shows status effect icons beside each active status.
12. Draft UI character cards show equipment and ability icons.
13. Combat log entries include a small inline icon before action text.
14. Affected units on the 3D map display floating status effect markers above their pawn tokens.
15. All icons are legible at their displayed sizes (12–64px).
16. Adding a new ability, item, or status effect requires only adding one atlas cell + one mapping entry in the atlas dictionary.
17. GUT tests verify `SymbolAtlas` lookup returns correct textures for all IDs (including race+class) and the fallback for unknown IDs.

---

## 2. Design Decisions

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Icon technique** | Sprite atlas (single PNG sprite sheet) rather than per-icon procedural rendering. | One texture in GPU memory. Consistent resolution across all surfaces. Swappable with hand-drawn art later — only the PNG file changes, no code. |
| **Atlas generation** | Procedural generation via `IconAtlasGenerator` using PawnFactory's existing pixel-drawing primitives (`_draw_thick_line`, `_draw_circle_filled`, `_safe_pixel`, Bresenham lines). | Reuses proven drawing code from Phase 8. No external tool dependency. Atlas can be re-generated when new icons are added. |
| **Cell size** | 64×64 pixels per icon cell. | Large enough for visual clarity at 1:1. Downscales cleanly to 32, 16, and 12px display sizes needed by HUD, log, and status areas. |
| **Atlas dimensions** | 512×512 PNG (8 columns × 8 rows = 64 cells). | 35 entity icons + 8 race+class identity icons = 43 used, 21 reserved. Room for expansion without regenerating the atlas layout. |
| **Category frames** | Each non-character category gets a dual-overlapping-geometry frame (two shapes drawn overlapping) with category-specific fill color. Interior icon identifies the specific entity. Character identity sprites use single-shape frames (matching Phase 8 race encoding). | The dual vs. single pattern visually distinguishes entity-type icons from character-identity icons. Category is recognizable by composite shape even at small sizes. |
| **Race+class in atlas** | Move race+class identity sprites from PawnFactory procedural generation into the sprite atlas. Only the 8 currently-used combinations are added; future characters expand the atlas as needed. | Unifies all symbology into one texture. Eliminates the parallel PawnFactory procedural pipeline. PawnFactory retains drawing primitives for the atlas generator but no longer generates symbol textures at runtime. |
| **3D renderability** | `SymbolAtlas.make_3d_material(id)` creates a `StandardMaterial3D` from any atlas icon, suitable for PlaneMesh/QuadMesh faces. | Generalizes UnitPawn's existing pattern. Items, spells, status effects — any game entity — can be represented as a 3D world object. Enables future features (item pickups, spell markers, etc.) without new rendering code. |
| **Lookup class** | Static `SymbolAtlas` class (not autoload) with lazy-loaded atlas texture and `Dictionary` mapping IDs to grid coordinates. | Matches `PawnFactory` pattern (static, no scene-tree dependency). Lazy load avoids startup cost if icons aren't needed. |
| **HUD icon placement** | `TextureRect` nodes inserted into existing `HBoxContainer` / `Button` layouts in BattleHUD. | Minimal HUD restructuring — adds a child node to each button/label row. Existing layout spacing absorbs the icon. |
| **Map status markers** | `MeshInstance3D` with `QuadMesh` + billboard material floating above the pawn token. Managed by `PawnManager`. | Lightweight 3D node. Billboard ensures readability at any camera angle. PawnManager already tracks per-unit state. |
| **Combat log icons** | `HBoxContainer` per log entry containing a `TextureRect` + `Label`, replacing the current bare `Label`. | Minimal change to `append_log()`. Icon is optional — entries without icons render as before. |
| **Element tinting** | Spell frame fill color tinted by element (fire = red-orange, ice = cyan-blue, lightning = yellow, healing = green). Non-elemental spells use base purple. | Adds a second visual channel (shape + color) without needing separate frames per element. |
| **File organization** | Generator in `src/map/` (adjacent to PawnFactory). SymbolAtlas in `src/core/data/` (data lookup). StatusMarker in `src/map/` (3D visual). | Follows established directory conventions. |

---

## 3. Symbol Categories & Frame Shapes

### 3.1 Category frame definitions

Each non-character category uses a dual-overlapping-geometry frame drawn at 64×64 resolution with a 2px outline stroke. Two geometric shapes are drawn overlapping with the same fill color to create a distinctive composite silhouette. The interior icon is drawn in white, centered within the composite shape. Character identity sprites use single-shape frames (see §3.3).

| Category | Frame shape | Fill color | Outline | Use |
|----------|-------------|------------|---------|-----|
| **Spell** | Upward triangle + circle overlap | Purple (0.6, 0.3, 0.8, 0.8) | White | Magic abilities: `fire_1`, `fire_2`, `ice_1`, `thunder_1`, `cure_1`, `cure_2`, `shield_1` |
| **Skill** | Pentagon + inverted pentagon overlap | Orange/amber (0.8, 0.6, 0.2, 0.8) | White | Physical abilities: `power_strike`, `backstab`, `reckless_swing`, `rage`, `inspire`, `lullaby` |
| **Weapon** | Hexagon + 90°-rotated square (diamond) overlap | Steel grey (0.5, 0.5, 0.55, 0.8) | White | Weapons: `sword`, `daggers`, `bow`, `staff`, `rapier`, `greataxe`, `sling` |
| **Equipment** | Hexagon + circle overlap | Brown/leather (0.55, 0.4, 0.25, 0.8) | White | Armor and accessories: `light_armor`, `medium_armor`, `shield`, `bracer_of_accuracy`, `smoke_bomb_pouch` |
| **Status Effect** | Inverted triangle + square overlap | Dark red (0.7, 0.2, 0.2, 0.8) | White | Status effects: `sleep`, `blind`, `defend` |

**Dual-overlapping-geometry drawing approach:** Each frame function draws two geometric shapes at the same cell offset with the same fill color and outline. The shapes are drawn sequentially (first shape filled, then second shape filled on top), creating a composite silhouette. The overlap region is naturally filled. Outlines are drawn last for both shapes so they appear crisp at the edges.

- **Spell (triangle + circle):** Upward-pointing equilateral triangle (radius ~26px) with a filled circle (radius ~16px) centered on the triangle.
- **Skill (pentagon + inverted pentagon):** Regular pentagon point-up (radius ~24px) with an inverted pentagon point-down (radius ~18px) overlapping, creating a roughly decagonal composite.
- **Weapon (hexagon + diamond):** Regular flat-top hexagon (radius ~22px) with a square rotated 45° (diamond, side ~20px) centered on the hexagon.
- **Equipment (hexagon + circle):** Regular flat-top hexagon (radius ~22px) with a filled circle (radius ~18px) centered.
- **Status (inverted triangle + square):** Inverted triangle point-down (radius ~24px) with a filled square (~20px side) centered.

**Element tinting** (applied to spell frames only):

| Element | Fill color override |
|---------|-------------------|
| Fire | Red-orange (0.85, 0.35, 0.15, 0.8) |
| Ice | Cyan-blue (0.2, 0.55, 0.85, 0.8) |
| Lightning | Yellow (0.85, 0.8, 0.2, 0.8) |
| Healing | Green (0.25, 0.7, 0.35, 0.8) |

### 3.2 Interior icon catalog

**Spells (7 icons):**

| ID | Icon | Visual description | Element tint |
|----|------|--------------------|--------------|
| `fire_1` | Flame | Small flame silhouette (teardrop with flicker) | Fire |
| `fire_2` | Flame | Larger flame silhouette (taller, wider base) | Fire |
| `ice_1` | Snowflake | 6-armed snowflake (3 crossing lines with ticks) | Ice |
| `thunder_1` | Lightning bolt | Zigzag bolt (reuses black_mage icon pattern) | Lightning |
| `cure_1` | Healing cross | Upright cross (reuses white_mage icon pattern) | Healing |
| `cure_2` | Healing cross | Thicker upright cross with radiating dots | Healing |
| `shield_1` | Upward chevron | ^-shaped chevron pointing up | Purple (base) |

**Skills (6 icons):**

| ID | Icon | Visual description |
|----|------|--------------------|
| `power_strike` | Downward slash | Thick diagonal line top-right to bottom-left with impact arc |
| `backstab` | Dagger thrust | Single dagger pointing right with motion lines |
| `reckless_swing` | Wide arc | Curved arc from left to right (quarter-circle sweep) |
| `rage` | Clenched fist | Small fist silhouette (filled rectangle with finger bumps) |
| `inspire` | Horn | Horn/bugle silhouette pointing right with sound lines |
| `lullaby` | Crescent moon | Crescent moon with two small Z's |

**Weapons (7 icons):**

| ID | Icon | Visual description |
|----|------|--------------------|
| `sword` | Sword | Vertical blade with crossguard |
| `daggers` | Crossed daggers | Two diagonal blades crossed in an X |
| `bow` | Bow with arrow | Curved bow with arrow pointing up-right |
| `staff` | Vertical staff | Vertical line with circle at top |
| `rapier` | Thin blade | Thin diagonal line with circular guard |
| `greataxe` | Axe head | Vertical handle with large curved blade head |
| `sling` | Sling arc | Curved sling with small circle (stone) at end |

**Equipment (5 icons):**

| ID | Icon | Visual description |
|----|------|--------------------|
| `light_armor` | Chain links | Three interlocking circles (chain mail motif) |
| `medium_armor` | Breastplate | Trapezoid torso shape with shoulder line |
| `shield` | Shield front | Small shield silhouette (rounded top, pointed bottom) |
| `bracer_of_accuracy` | Wristguard | Rectangle band with crosshair dot |
| `smoke_bomb_pouch` | Pouch | Small bag shape with drawstring top |

**Status Effects (3 icons):**

| ID | Icon | Visual description |
|----|------|--------------------|
| `sleep` | Moon with Zs | Crescent moon with two small Z letters |
| `blind` | Crossed-out eye | Eye oval with diagonal line through it |
| `defend` | Shield up | Small shield with upward arrow |

**Action buttons (6 icons) — used on HUD action panel:**

| ID | Icon | Visual description |
|----|------|--------------------|
| `action_move` | Boot/footprint | Boot silhouette or directional arrow |
| `action_attack` | Sword strike | Sword with impact flash |
| `action_ability` | Starburst | Small 8-pointed starburst (matches spell category frame) |
| `action_item` | Pouch | Small bag (matches equipment frame style) |
| `action_defend` | Shield | Small shield (matches defend status icon) |
| `action_wait` | Hourglass | Hourglass silhouette |

**Fallback (1 icon):**

| ID | Icon | Visual description |
|----|------|--------------------|
| `_fallback` | Question mark | Centered "?" in a plain circle frame |

### 3.3 Race+class identity sprites

The 8 existing race+class combinations from Phase 8 are rendered into the atlas. Each uses the same single-shape frame and class interior icon as PawnFactory currently draws, but rendered at 64×64 into an atlas cell instead of 128×128 per-unit procedural textures. Single-shape frames (one geometric shape) visually distinguish character identity from entity categories (which use dual-overlapping shapes).

**Character frames** (single geometry — Phase 8 race encoding):

| Race | Frame shape |
|------|-------------|
| Human | Rectangle |
| Elf | Diamond |
| Halfling | Circle |
| Dwarf | Hexagon |

**Class interior icons** (Phase 8 class encoding):

| Class | Icon |
|-------|------|
| Fighter | Saltire (X) |
| Archer | Upward arrow |
| Rogue | Diagonal slash |
| Barbarian | Double-bar cross |
| Black Mage | Lightning bolt zigzag |
| White Mage | Upright cross (+) |
| Red Mage | Hourglass |
| Bard | Wave/tilde |

**Atlas entries (8 sprites):**

| ID | Race frame | Class icon |
|----|-----------|------------|
| `human_fighter` | Rectangle | Saltire (X) |
| `human_archer` | Rectangle | Upward arrow |
| `human_rogue` | Rectangle | Diagonal slash |
| `human_bard` | Rectangle | Wave/tilde |
| `elf_black_mage` | Diamond | Lightning bolt |
| `elf_red_mage` | Diamond | Hourglass |
| `halfling_white_mage` | Circle | Upright cross |
| `dwarf_barbarian` | Hexagon | Double-bar cross |

**Team coloring approach:** The atlas stores a neutral-colored version of each race+class sprite (grey fill: `Color(0.6, 0.6, 0.6, 0.8)`, white outline, white interior icon). At runtime, `PawnFactory.symbol_material()` loads the `AtlasTexture` via `SymbolAtlas.get_icon(character_id)` and sets `StandardMaterial3D.albedo_color` to the team color (lightened 0.3, alpha 0.8) as a multiplicative tint. White icon pixels remain white; neutral frame pixels become team-colored. This reproduces the existing Phase 8 visual with no per-unit procedural generation.

---

## 4. Sprite Atlas Layout

### 4.1 Atlas structure

- **Cell size:** 64×64 pixels
- **Atlas size:** 512×512 pixels (8 columns × 8 rows = 64 cells)
- **Format:** `Image.FORMAT_RGBA8` (same as PawnFactory symbol textures)
- **File path:** `res://assets/icons/symbol_atlas.png`

### 4.2 Grid layout

Each row is assigned to a category. Cells within a row are assigned left-to-right in the order listed below. Unused cells remain transparent.

```
     Col 0       Col 1       Col 2       Col 3       Col 4       Col 5       Col 6       Col 7
Row 0  fire_1      fire_2      ice_1       thunder_1   cure_1      cure_2      shield_1    (empty)
Row 1  power_str   backstab    reckless    rage        inspire     lullaby     (empty)     (empty)
Row 2  sword       daggers     bow         staff       rapier      greataxe    sling       (empty)
Row 3  light_armor medium_arm  shield      bracer_acc  smoke_pouch (empty)     (empty)     (empty)
Row 4  sleep       blind       defend      (empty)     (empty)     (empty)     (empty)     (empty)
Row 5  act_move    act_attack  act_ability act_item    act_defend  act_wait    _fallback   (empty)
Row 6  human_ftr   human_arc   human_rog   human_brd   elf_blk     elf_red     half_wht    dwarf_bar
Row 7  (reserved)
```

- **Row 0:** Spells (7 icons, element-tinted, upward-triangle+circle frames)
- **Row 1:** Skills (6 icons, orange/amber, pentagon+inverted-pentagon frames)
- **Row 2:** Weapons (7 icons, steel grey, hexagon+diamond frames)
- **Row 3:** Equipment (5 icons, brown, hexagon+circle frames)
- **Row 4:** Status effects (3 icons, dark red, inverted-triangle+square frames)
- **Row 5:** Action buttons + fallback (7 icons, plain circle frames)
- **Row 6:** Race+class identity (8 icons, neutral grey, single-shape race frames)
- **Row 7:** Reserved for future expansion

43 of 64 cells used. 21 reserved for expansion.

### 4.3 ID → grid coordinate mapping

Stored as a static `Dictionary` in `SymbolAtlas`:

```gdscript
const ICON_MAP := {
    # Spells (row 0)
    "fire_1":          Vector2i(0, 0),
    "fire_2":          Vector2i(1, 0),
    "ice_1":           Vector2i(2, 0),
    "thunder_1":       Vector2i(3, 0),
    "cure_1":          Vector2i(4, 0),
    "cure_2":          Vector2i(5, 0),
    "shield_1":        Vector2i(6, 0),
    # Skills (row 1)
    "power_strike":    Vector2i(0, 1),
    "backstab":        Vector2i(1, 1),
    "reckless_swing":  Vector2i(2, 1),
    "rage":            Vector2i(3, 1),
    "inspire":         Vector2i(4, 1),
    "lullaby":         Vector2i(5, 1),
    # Weapons (row 2)
    "sword":           Vector2i(0, 2),
    "daggers":         Vector2i(1, 2),
    "bow":             Vector2i(2, 2),
    "staff":           Vector2i(3, 2),
    "rapier":          Vector2i(4, 2),
    "greataxe":        Vector2i(5, 2),
    "sling":           Vector2i(6, 2),
    # Equipment (row 3)
    "light_armor":     Vector2i(0, 3),
    "medium_armor":    Vector2i(1, 3),
    "shield":          Vector2i(2, 3),
    "bracer_of_accuracy": Vector2i(3, 3),
    "smoke_bomb_pouch": Vector2i(4, 3),
    # Status effects (row 4)
    "sleep":           Vector2i(0, 4),
    "blind":           Vector2i(1, 4),
    "defend":          Vector2i(2, 4),
    # Action buttons (row 5)
    "action_move":     Vector2i(0, 5),
    "action_attack":   Vector2i(1, 5),
    "action_ability":  Vector2i(2, 5),
    "action_item":     Vector2i(3, 5),
    "action_defend":   Vector2i(4, 5),
    "action_wait":     Vector2i(5, 5),
    "_fallback":       Vector2i(6, 5),
    # Race+class identity (row 6)
    "human_fighter":       Vector2i(0, 6),
    "human_archer":        Vector2i(1, 6),
    "human_rogue":         Vector2i(2, 6),
    "human_bard":          Vector2i(3, 6),
    "elf_black_mage":      Vector2i(4, 6),
    "elf_red_mage":        Vector2i(5, 6),
    "halfling_white_mage": Vector2i(6, 6),
    "dwarf_barbarian":     Vector2i(7, 6),
}
```

---

## 5. SymbolAtlas Resource

### 5.1 Class signature

```
class_name SymbolAtlas
extends RefCounted
## Provides icon lookup by entity ID from a pre-generated sprite atlas PNG.
## All icons are AtlasTexture sub-regions of one shared Texture2D.
## Spec reference: phase9-spec.md §5

const CELL_SIZE := 64
const ATLAS_PATH := "res://assets/icons/symbol_atlas.png"

const ICON_MAP := { ... }  # See §4.3

static var _atlas: Texture2D = null
static var _cache: Dictionary = {}  # String → AtlasTexture

static func get_icon(id: String) -> AtlasTexture
    # Returns the AtlasTexture for the given ID.
    # Lazy-loads the atlas PNG on first call.
    # Returns the _fallback icon for unknown IDs.

static func make_3d_material(id: String, tint: Color = Color.WHITE) -> StandardMaterial3D
    # Returns a StandardMaterial3D configured for 3D mesh use:
    #   - albedo_texture = get_icon(id)
    #   - albedo_color = tint (for team-color modulation on race+class sprites)
    #   - transparency = TRANSPARENCY_ALPHA_SCISSOR
    #   - alpha_scissor_threshold = 0.1
    #   - shading_mode = SHADING_MODE_UNSHADED
    # Matches PawnFactory.symbol_material() configuration.
    # Callers can further configure the returned material (e.g., billboard_mode).

static func _ensure_loaded() -> void
    # Loads the atlas PNG into _atlas if not already loaded.

static func _make_region(col: int, row: int) -> AtlasTexture
    # Creates an AtlasTexture with region Rect2(col * 64, row * 64, 64, 64).
```

### 5.2 Lookup behavior

1. On first call to `get_icon()`, `_ensure_loaded()` loads `symbol_atlas.png` into `_atlas`.
2. If `id` is in `ICON_MAP`, look up `Vector2i(col, row)`.
3. Check `_cache` for a previously created `AtlasTexture`. If found, return it.
4. Otherwise, create a new `AtlasTexture` via `_make_region(col, row)`, store in `_cache`, return.
5. If `id` is **not** in `ICON_MAP`, return `get_icon("_fallback")`.

This ensures:
- One `Texture2D` in GPU memory for all icons.
- One `AtlasTexture` object per unique ID (cached).
- Unknown IDs gracefully fall back to a visible "?" icon.

**3D material creation:** `make_3d_material(id, tint)` calls `get_icon(id)` to obtain the `AtlasTexture`, then creates a `StandardMaterial3D` with the same configuration as `PawnFactory.symbol_material()`: unshaded, alpha-scissor transparency, albedo texture set to the icon. The optional `tint` parameter sets `albedo_color` for team-color modulation (used by race+class sprites where the atlas stores neutral grey and tint applies team color). Callers can further configure the material (e.g., setting `billboard_mode` for floating markers). Materials created by `make_3d_material` are not cached — each call returns a new instance, as materials are typically unique per mesh instance.

---

## 6. Atlas Generator

### 6.1 IconAtlasGenerator

A tool script that procedurally renders all icons into the atlas PNG. Can be run in the Godot editor or headless via command line.

```
class_name IconAtlasGenerator
extends RefCounted
## Generates the symbol_atlas.png by drawing all icons procedurally.
## Reuses PawnFactory's pixel-drawing primitives.
## Spec reference: phase9-spec.md §6

const CELL := 64
const ATLAS := 512

static func generate() -> Image
    # Creates a 512×512 Image, draws all icons, returns it.

static func save(path: String) -> void
    # Calls generate(), saves to disk as PNG.

# Frame drawing (5 dual-overlapping-geometry category frames)
static func _draw_spell_frame(img: Image, ox: int, oy: int, fill: Color, outline: Color) -> void
    # Upward triangle + circle overlap
static func _draw_skill_frame(img: Image, ox: int, oy: int, fill: Color, outline: Color) -> void
    # Pentagon + inverted pentagon overlap
static func _draw_weapon_frame(img: Image, ox: int, oy: int, fill: Color, outline: Color) -> void
    # Hexagon + 90°-rotated square (diamond) overlap
static func _draw_equipment_frame(img: Image, ox: int, oy: int, fill: Color, outline: Color) -> void
    # Hexagon + circle overlap
static func _draw_status_frame(img: Image, ox: int, oy: int, fill: Color, outline: Color) -> void
    # Inverted triangle + square overlap

# Race+class identity (single-shape frames, reusing PawnFactory patterns)
static func _draw_race_class_cell(img: Image, ox: int, oy: int, race: String, job_class: String) -> void
    # Draws the race frame + class icon at 64×64 scale (adapted from PawnFactory's 128×128)
    # Uses neutral grey fill; team tinting applied at runtime via material albedo_color

# Icon drawing (~28 interior icons)
static func _draw_icon_flame(img: Image, ox: int, oy: int, color: Color) -> void
static func _draw_icon_snowflake(img: Image, ox: int, oy: int, color: Color) -> void
# ... one function per interior icon
```

**Drawing approach:** Each icon is drawn into a 64×64 sub-region of the atlas `Image`. The `ox, oy` parameters specify the top-left corner of the cell. Frame and icon drawing functions operate within `[ox, ox+64) × [oy, oy+64)` using `PawnFactory._safe_pixel()`, `_draw_thick_line()`, `_draw_line_bresenham()`, and `_draw_circle_filled()`.

### 6.2 Reused PawnFactory primitives

The following PawnFactory drawing functions are reused directly (or extracted to a shared utility):

| Function | Purpose |
|----------|---------|
| `_safe_pixel(img, x, y, color)` | Bounds-checked single pixel set |
| `_draw_thick_line(img, x0, y0, x1, y1, color, thickness)` | Thick line via parallel Bresenham |
| `_draw_line_bresenham(img, x0, y0, x1, y1, color, offset)` | Single-pixel Bresenham line |
| `_draw_circle_filled(img, cx, cy, radius, color)` | Filled circle |
| `_draw_line_h(img, x0, x1, y, color)` | Horizontal line |
| `_draw_line_v(img, x, y0, y1, color)` | Vertical line |
| `_point_in_polygon(px, py, verts)` | Point-in-polygon test for scanline fill |

These may be extracted to a shared `DrawPrimitives` utility class if PawnFactory and IconAtlasGenerator both need them, or IconAtlasGenerator can call PawnFactory's static methods directly.

For race+class atlas cells (Row 6), `IconAtlasGenerator` reuses `PawnFactory._draw_race_frame()` and `_draw_class_icon()` logic, adapted from 128×128 to 64×64 coordinate space (all coordinates halved). Alternatively, it can call PawnFactory's methods directly on a 128×128 sub-image and then downscale to 64×64 before blitting into the atlas cell.

---

## 7. UI Integration Points

### 7.1 HUD — Action buttons

Each action button in `BattleHUD._action_panel` gains a small icon (24×24 `TextureRect`) placed before the text label. The button layout becomes `[icon] Attack [F]` instead of bare text.

| Button | Icon ID |
|--------|---------|
| Attack [F] | `action_attack` |
| Abilities | `action_ability` |
| Items | `action_item` |
| Defend [G] | `action_defend` |
| Wait [X] | `action_wait` |

The Move action is handled separately via drag-to-move (Phase 8), so it does not have a button, but `action_move` is available in the atlas for future use.

### 7.2 HUD — Ability popup

Each ability button in `BattleHUD._ability_panel` gains a 24×24 icon to the left of the text. The icon is loaded from `SymbolAtlas.get_icon(ability.id)`.

Current layout: `"Fire 2   2 AP - R4\n  7 fire damage"`
New layout: `[fire_2 icon] "Fire 2   2 AP - R4\n  7 fire damage"`

Implementation: wrap each ability button's content in an `HBoxContainer` containing a `TextureRect` + `Label` (or use `Button.icon` property).

### 7.3 HUD — Item popup

Same as §7.2 but for items. Each item button gains a 24×24 icon from `SymbolAtlas.get_icon(item.id)`.

Current: `"Smoke Bomb Pouch   1 AP"`
New: `[smoke_bomb_pouch icon] "Smoke Bomb Pouch   1 AP"`

### 7.4 HUD — Status effect display

The unit info panel's `_status_label` currently shows text like `"blind(1) sleep(2)"`. Replace with an `HBoxContainer` of `[icon] name(N)` pairs. Each status gets a 16×16 `TextureRect` from `SymbolAtlas.get_icon(status_id)`.

### 7.5 HUD — Roster sidebar

Each unit's roster card in `_update_team_list()` gains a row showing equipped weapon icon (16×16) beside the unit name. Status effects on the unit also show as small icons.

### 7.6 Draft UI — Character cards

`DraftScene` character cards gain two icon rows:
- **Equipment row**: weapon and armor icons (16×16) from `SymbolAtlas.get_icon(item.id)`.
- **Abilities row**: spell/skill icons (16×16) from `SymbolAtlas.get_icon(ability.id)`.

These appear below the existing character name and class info.

### 7.7 Combat log — Inline icons

`BattleHUD.append_log()` gains an optional `icon_id: String = ""` parameter. When provided, the log entry uses an `HBoxContainer` with a 12×12 `TextureRect` + `Label` instead of a bare `Label`.

Example log entries with icons:
- `[sword icon] Fighter attacks Elf Black Mage for 5 damage`
- `[fire_1 icon] Elf Black Mage casts Fire 1 on Human Fighter — 4 fire damage`
- `[shield icon] Human Fighter defends (+2 DEF)`

### 7.8 Map — Status effect markers

Floating 3D markers above pawn tokens showing active status effects. Managed by `PawnManager`.

**StatusMarker structure:**
- `MeshInstance3D` with `QuadMesh` (size 0.15 × 0.15).
- `StandardMaterial3D` with `AtlasTexture` from `SymbolAtlas.get_icon(status_id)`.
- `billboard_mode = BILLBOARD_ENABLED` so it always faces the camera.
- `shading_mode = SHADING_MODE_UNSHADED` for consistent visibility.
- `transparency = TRANSPARENCY_ALPHA_SCISSOR` (matching pawn symbol pattern).
- Positioned at `pawn.global_position + Vector3(0, 0.25, 0)` (above token top face).
- Multiple status markers stack horizontally with 0.15 spacing.

**Lifecycle:**
- Created when a status effect is applied (after `TurnActions.execute_ability()` or `execute_use_item()`).
- Removed when a status effect expires (after `RoundManager.start_round()` ticks durations).
- `PawnManager.update_status_markers(unit)` is called by the controller after any action that may change statuses.

### 7.9 Any atlas sprite as 3D world object

Any sprite in the atlas can be rendered as a 3D object in the world using `SymbolAtlas.make_3d_material(id)`. This generalizes the pattern already used by UnitPawn (PlaneMesh + StandardMaterial3D) and StatusMarker (QuadMesh + billboard material).

**Usage pattern:**

```gdscript
var mesh_instance := MeshInstance3D.new()
var quad := QuadMesh.new()
quad.size = Vector2(0.3, 0.3)
mesh_instance.mesh = quad
mesh_instance.material_override = SymbolAtlas.make_3d_material("sword")
# Optionally set billboard for camera-facing:
# mesh_instance.material_override.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
parent_node.add_child(mesh_instance)
```

This enables future features such as:
- Item pickups rendered on map tiles
- Spell effect markers at impact locations
- Floating ability icons during casting animations
- Equipment display on inspection panels

No additional code is needed beyond `SymbolAtlas.make_3d_material()`. The same material configuration (unshaded, alpha-scissor, atlas sub-region) applies to all sprites regardless of category.

### 7.10 PawnFactory race+class delegation

`PawnFactory.make_symbol_texture()` and `symbol_material()` are refactored to delegate to `SymbolAtlas` instead of procedural drawing.

**`PawnFactory.symbol_material()` change:**

```gdscript
const _RACE_CLASS_TO_ID := {
    "human:fighter": "human_fighter",
    "human:archer": "human_archer",
    "human:rogue": "human_rogue",
    "human:bard": "human_bard",
    "elf:black_mage": "elf_black_mage",
    "elf:red_mage": "elf_red_mage",
    "halfling:white_mage": "halfling_white_mage",
    "dwarf:barbarian": "dwarf_barbarian",
}

static func symbol_material(race: String, job_class: String, team: String) -> StandardMaterial3D:
    var char_id: String = _RACE_CLASS_TO_ID.get(
        "%s:%s" % [race, job_class], "_fallback")
    var team_color: Color = TEAM_COLORS.get(team, Color(0.5, 0.5, 0.5))
    var tint := team_color.lightened(0.3)
    tint.a = 0.8
    return SymbolAtlas.make_3d_material(char_id, tint)
```

**Impact on UnitPawn:** Zero code changes. `UnitPawn.setup()` calls `PawnFactory.symbol_material(race, job_class, team)` which returns the same type (`StandardMaterial3D`) with the same visual properties. The change is transparent.

PawnFactory's procedural drawing primitives (`_draw_race_frame`, `_draw_class_icon`, etc.) remain available for use by `IconAtlasGenerator` during atlas generation. The `_symbol_cache` and `make_symbol_texture()` method can be removed or deprecated since all symbol textures now come from the atlas.

---

## 8. Data Flow & Integration

### From prior phases

| Source | Data consumed |
|--------|------|
| Phase 1 | `AbilityData.id`, `AbilityData.type`, `AbilityData.effect` (element), `ItemData.id`, `ItemData.slot`, `BattleUnit.status_effects` |
| Phase 2 | `HexWorld.hex_to_world()` for status marker 3D positioning |
| Phase 7 | `DraftScene._build_character_card()` for icon integration into draft cards |
| Phase 8 | `PawnFactory` drawing primitives, `PawnManager` pawn tracking, `BattleHUD` UI panels and `append_log()`, `BattleController` action flow |

### Outputs

- `IconAtlasGenerator` — procedural atlas generation tool.
- `SymbolAtlas` — static lookup class for icon textures.
- `symbol_atlas.png` — sprite atlas asset.
- `StatusMarker` — 3D billboard marker for status effects on the map.
- Modified `BattleHUD` — icon-enhanced ability/item popups, status display, action buttons, combat log.
- Modified `DraftScene` — icon-enhanced character cards.
- Modified `PawnManager` — status marker management.
- Modified `PawnFactory` — `make_symbol_texture()` and `symbol_material()` delegate to `SymbolAtlas` instead of procedural drawing. Drawing primitives remain available for `IconAtlasGenerator`.
- Unchanged `UnitPawn` — `PawnFactory.symbol_material()` returns the same type (`StandardMaterial3D`). The refactor is transparent.
- A comprehensive visual symbology system covering all game entities, ready for future expansion.

---

## 9. Risks & Notes

- **Icon readability at small sizes.** At 12×12 (combat log) and 16×16 (roster, status), interior icon details may be lost. Mitigation: icons are designed as simple high-contrast silhouettes (white on colored fill). The category frame shape remains recognizable even when the interior is indistinct. Playtest verification is needed.
- **Atlas extensibility.** With 43 of 64 cells used, there is room for 21 more icons without increasing atlas size. If the game grows beyond 64 total icons, the atlas can be expanded to 1024×512 (128 cells) by changing `ATLAS` constant and adding rows. New race+class combinations in future phases add one cell each to row 6 (or overflow to row 7).
- **Shared drawing primitives.** PawnFactory's drawing helpers are currently private static methods. IconAtlasGenerator needs access. Options: (a) call PawnFactory's static methods directly (they're accessible even though prefixed with `_`), (b) extract to a shared `DrawPrimitives` class. Option (a) is simpler; option (b) is cleaner.
- **Item ID collision.** The item `shield` and the status effect `defend` are distinct entities with distinct IDs, so no collision. The ability `shield_1` and the item `shield` also have different IDs. However, if future content uses the same ID across categories, the flat `ICON_MAP` dictionary would need category-prefixed keys (e.g., `"item:shield"`, `"status:defend"`). Current data has no collisions.
- **MatchState remains signal-free.** Status marker updates follow the existing pull-based pattern: the controller calls `PawnManager.update_status_markers()` after each action, just as it already calls `highlight_active()` and `move_pawn()`.
- **Draft UI layout.** Adding equipment and ability icon rows to character cards increases card height. The existing scroll container in DraftScene accommodates this, but visual testing is needed to ensure cards remain readable.

---

## 10. Phase 9 Deliverables Checklist

- [ ] `IconAtlasGenerator` with 5 dual-overlapping-geometry category frame functions, 8 race+class cell functions, and ~28 interior icon functions (§6)
- [ ] Generated `symbol_atlas.png` at `res://assets/icons/` with 43 populated cells (§4)
- [ ] `SymbolAtlas` static lookup class with `get_icon(id)` and fallback (§5)
- [ ] `SymbolAtlas.make_3d_material(id, tint)` for 3D mesh use (§5, §7.9)
- [ ] Race+class identity sprites in atlas row 6 — 8 cells (§3.3, §4)
- [ ] `PawnFactory.symbol_material()` refactored to delegate to `SymbolAtlas` (§7.10)
- [ ] `StatusMarker` 3D billboard marker for status effects (§7.8)
- [ ] `BattleHUD` updated: ability popup icons, item popup icons, status icons, action button icons (§7.1–7.5)
- [ ] `BattleHUD.append_log()` updated with optional icon parameter (§7.7)
- [ ] `DraftScene` updated with equipment and ability icons on character cards (§7.6)
- [ ] `PawnManager` updated with status marker management (§7.8)
- [ ] GUT tests for `SymbolAtlas` lookup, fallback, and race+class IDs (§5)
- [ ] GUT tests for `SymbolAtlas.make_3d_material()` (§5)
- [ ] GUT tests for `PawnFactory.symbol_material()` atlas delegation (§7.10)
- [ ] GUT tests for `IconAtlasGenerator` output dimensions and cell contents (§6)
- [ ] Manual visual verification of all integration points (§7)
- [ ] Manual verification that 3D pawn token faces are visually unchanged from Phase 8 (§7.10)
- [ ] Git tag `phase-9-complete`
