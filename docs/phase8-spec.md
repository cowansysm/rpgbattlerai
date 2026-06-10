# Phase 8 — Combat UI & Unit Visuals Specification

**Parent plan:** `rpg-implementation-plan.md` (Phase 8)
**Builds on:** `phase2-spec.md` (3D map, hex tiles, camera), `phase3-spec.md` (movement, range, LoS, overlays), `phase4-spec.md` (activation loop, match state, turn actions), `phase5-spec.md` (combat resolution), `phase7-spec.md` (draft UI, match builder, scene transition)
**Source spec:** `rpg-specs.md` (§7.4, §7.7)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-09

---

## 1. Purpose & Scope

Phase 8 bridges the gap between the fully functional combat backend (Phases 4–5) and a playable game. Until now, units exist only as data objects with no visual representation on the 3D map. The Phase4Demo controller exposes four of six action types via hardcoded keyboard shortcuts, leaving abilities and items inaccessible. There is no combat HUD — all feedback is console-only.

Phase 8 delivers three things: **visible unit pawns** on the hex map, a **full combat HUD** with action panels and state readouts, and a **BattleController** that wires them together with the existing TurnActions backend.

### In scope

- **3D unit tokens**: cylindrical game-piece tokens placed on hex tiles, team-colored (blue/red), with a **NATO-style symbology** rendered on the top face — race encoded as frame shape, class encoded as interior icon (§3.4).
- **Active-unit highlight**: emissive material variant for the active unit's token.
- **Pawn sync**: pawns reflect MatchState — deployed at match start, animated on move, removed on downing.
- **Smooth movement animation**: tween-based pawn movement from origin to destination tile.
- **Full combat HUD** (2D overlay):
  - Active unit info panel (name, class, HP bar, AP pips, status effects).
  - Action panel with buttons for all six action types (Move, Attack, Ability, Item, Defend, Wait).
  - Ability browser listing the unit's available abilities with AP cost, range, and effect summary.
  - Item browser listing usable equipment items.
  - Combat log panel (scrollable action history replacing console-only logging).
  - Turn order display (unactivated units this round, both teams).
  - Team roster sidebar (all units, mini HP bars, activation status, downed indicators).
- **Target selection flow**: select action → overlay shows valid range → click target tile → execute.
- **BattleController**: state-machine-based controller replacing Phase4Demo as the combat orchestrator.
- **Keyboard shortcuts**: preserved from Phase4Demo as alternative input method.

### Out of scope

- Victory/rout detection and match-end screen (Phase 9).
- Hit/heal floating numbers, particle effects, animations (Phase 11).
- Audio feedback (Phase 11).
- AI-controlled units (future work).
- Undo within an activation (Phase 11).
- Character-specific pawn models or sprites beyond the symbology system (future work).

### Exit criteria

1. Each deployed unit has a visible token on its hex tile, positioned via `HexWorld.hex_to_world()`.
2. Team A and Team B tokens are visually distinct (blue vs. red body color).
3. Each token displays its race frame shape and class icon on the top face, readable at the default 40° camera pitch.
4. The active unit's token has a highlight/glow effect distinguishable from inactive tokens.
5. When a unit moves, its token tweens smoothly to the new tile (matching the project's tween conventions).
6. When a unit is downed (HP ≤ 0), its token is removed from the map.
7. An action panel shows all available actions for the active unit with appropriate disabled states.
8. The ability browser lists all abilities the active unit can use, showing AP cost and range.
9. Clicking an ability shows its range overlay; clicking a valid target tile executes it via `TurnActions.execute_ability()`.
10. The item browser lists usable items; selecting one and clicking a target triggers `TurnActions.execute_use_item()`.
11. A combat log panel displays action outcomes (damage, healing, buffs, status effects, downing).
12. A turn order display shows which units have not yet activated this round.
13. A team roster sidebar shows all units from both teams with HP and activation state.
14. The active unit's name, HP, AP, and status effects are displayed in an info panel.
15. All keyboard shortcuts from Phase4Demo (N, M, F, G, X, R) still work as alternatives.
16. Pure combat logic is unchanged — no modifications to TurnActions, CombatResolver, or RoundManager resolution behavior.

---

## 2. Design Decisions

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Token mesh** | Cylindrical `CylinderMesh` token (game-piece disc) via static `PawnFactory` (like `DecorationFactory`). | Flat token reads as a board-game piece. Top face provides a surface for the race/class symbol. |
| **NATO-style symbology** | Race encoded as frame shape (Rectangle/Diamond/Circle/Hexagon), class as interior icon (X, arrow, bolt, cross, etc.). Symbol rendered to texture via `SubViewport` + `_draw()`, applied to a `PlaneMesh` on the token's top face. | Communicates race + class at a glance without text. Inspired by NATO APP-6 layered symbology (frame = identity, icon = function). |
| **Team coloring** | `StandardMaterial3D` with team-specific albedo (blue for playerA, red for playerB) on the cylinder body. Symbol background tinted with team color. | Matches `OverlayMaterials` pattern. Immediately distinguishable. |
| **Active highlight** | Brighter emissive material variant swapped onto the active unit's token. | Clear at-a-glance identification. Simpler than adding outline shaders or pulsing scale. |
| **Token placement** | `UnitPawn` (Node3D) positioned via `HexWorld.hex_to_world()` + Y offset above tile surface. | Same coordinate transform used by `HexTile`. Tokens sit on top of tiles naturally. |
| **Movement animation** | Tween position (`EASE_OUT`, `TRANS_CUBIC`, 0.3s) matching `CameraRig` tween conventions. | Consistent tween style across project. Non-blocking — controller waits for tween completion before next action. |
| **PawnManager sync** | Pull-based — controller explicitly calls PawnManager methods after TurnActions completes. | Matches existing pattern where Phase4Demo explicitly reads from MatchState. MatchState remains signal-free (RefCounted with no signals). |
| **HUD construction** | Programmatic (`_ready()`, no `.tscn`) matching `DraftScene._build_ui()` pattern. | Consistent with Phase 7 UI approach. No scene-tree design dependency. All layout defined in code. |
| **BattleController** | New `Node` class replacing `Phase4Demo`, wired at same integration point in `map_scene.gd`. | Clean replacement. Phase4Demo preserved in codebase for backward compatibility but no longer the default controller. |
| **Action flow** | State machine: `AWAITING_ACTIVATION → ACTION_SELECT → TARGETING → ANIMATING` cycle. | Clear, testable flow for the ability/item target-selection interaction. Each state has well-defined inputs and transitions. |
| **AbilityResolver extension** | Add `all_abilities(unit)` method returning `Array[AbilityData]`. | Reuses existing 3-source resolution logic (character, class, equipment). Needed to populate the ability browser. |
| **Combat log** | Array of formatted strings in a `ScrollContainer` with `VBoxContainer` of `Label` nodes. | Simple, matches programmatic UI pattern. No rich text needed for MVP. Auto-scrolls to bottom. |
| **Symbol caching** | `PawnFactory` caches generated symbol textures keyed by `race + class` pair. Each unique combo generates one `SubViewport` render, then reuses the `ImageTexture`. | At most 32 textures (4 races × 8 classes). Avoids per-pawn SubViewport overhead. |
| **File organization** | Pawns in `src/map/` (visual, map-adjacent). HUD in `src/ui/`. Controller in `src/map/`. | Follows established directory conventions from prior phases. |

---

## 3. Unit Pawns

### 3.1 PawnFactory

A static factory class following the `DecorationFactory` pattern. Creates cylindrical token meshes, team materials, and NATO-style symbol textures.

```
class_name PawnFactory
extends RefCounted

# Token mesh
static func make_token_mesh() -> Mesh
    # CylinderMesh: radius ≈ 0.3, height ≈ 0.15, radial_segments = 16
    # Flat disc that reads as a board-game token

# Team materials (applied to the cylinder body)
static func team_material(team: String) -> StandardMaterial3D
    # playerA → blue (0.2, 0.4, 0.9), playerB → red (0.9, 0.2, 0.2)

static func active_material(team: String) -> StandardMaterial3D
    # Brighter variant with emission enabled

# Symbol texture (applied to PlaneMesh on top of token)
static func make_symbol_texture(race: String, job_class: String, team: String) -> ImageTexture
    # Renders the race frame + class icon into a 128×128 image
    # Cached by (race, job_class, team) key — at most 64 textures (4 races × 8 classes × 2 teams)

static func symbol_material(race: String, job_class: String, team: String) -> StandardMaterial3D
    # StandardMaterial3D with the symbol texture, ALPHA_SCISSOR for transparent background

# Internal drawing helpers (called by make_symbol_texture)
static func _draw_race_frame(img: Image, race: String, color: Color) -> void
static func _draw_class_icon(img: Image, job_class: String, color: Color) -> void
```

Team materials use `StandardMaterial3D` with `transparency = ALPHA_DISABLED` (fully opaque, unlike overlays). Active materials add `emission_enabled = true` with a glow matching the team color. Symbol materials use `ALPHA_SCISSOR` so the area outside the frame shape is transparent, showing the token body color beneath.

### 3.2 UnitPawn

A `Node3D` that represents one deployed character on the map. Each pawn has two visual layers: a team-colored cylinder body and a symbol face on top.

```
class_name UnitPawn
extends Node3D

var unit: BattleUnit             # Back-reference for lookup
var _body: MeshInstance3D        # Cylinder token mesh
var _symbol_face: MeshInstance3D # PlaneMesh on top with symbol texture
var _default_material: StandardMaterial3D
var _active_material: StandardMaterial3D

func setup(battle_unit: BattleUnit, graph: HexGraph) -> void
    # Create cylinder MeshInstance3D, assign team material
    # Create PlaneMesh child on top face, assign symbol material
    # Place at hex position

func place(coord: Vector2i, graph: HexGraph) -> void
    # Set position = HexWorld.hex_to_world(coord.x, coord.y, graph.elevation(coord))
    # Add Y offset: TileMesh.TILE_HEIGHT * 0.5 + token_half_height

func move_to(coord: Vector2i, graph: HexGraph) -> Tween
    # Tween global_position to target, EASE_OUT/TRANS_CUBIC, 0.3s
    # Returns the Tween so the controller can await completion

func set_active(active: bool) -> void
    # Swap body material between _default_material and _active_material

func remove() -> void
    # queue_free()
```

### 3.3 PawnManager

A `Node` that manages the set of all UnitPawns, providing a clean interface for the controller.

```
class_name PawnManager
extends Node

var _pawns: Dictionary = {}      # BattleUnit → UnitPawn
var _graph: HexGraph

func spawn_all(state: MatchState) -> void
    # For each living unit in state.parties, create a UnitPawn, call setup(), add_child()

func move_pawn(unit: BattleUnit, to: Vector2i) -> Tween
    # Look up UnitPawn, call move_to(), return Tween

func remove_pawn(unit: BattleUnit) -> void
    # Look up UnitPawn, call remove(), erase from dict

func highlight_active(unit: BattleUnit) -> void
    # set_active(false) on all pawns, set_active(true) on the specified one

func clear_highlight() -> void
    # set_active(false) on all pawns

func get_pawn(unit: BattleUnit) -> UnitPawn
    # Dictionary lookup
```

### 3.4 NATO-Style Symbology

Inspired by [NATO Joint Military Symbology (APP-6)](https://en.wikipedia.org/wiki/NATO_Joint_Military_Symbology), each pawn displays a layered symbol on its top face encoding race and class at a glance.

**Layer structure** (matching APP-6 frame + icon + fill convention):

| Layer | NATO equivalent | RPG mapping | Purpose |
|-------|----------------|-------------|---------|
| Frame shape | Affiliation frame | **Race** | Outer boundary shape identifies race |
| Interior icon | Function icon | **Class** | Centered symbol identifies combat role |
| Fill color | Friend/foe fill | **Team** | Background tint matches team color |

**Race → Frame shape:**

| Race | Frame | Visual description |
|------|-------|--------------------|
| Human | Rectangle | Upright rectangle — baseline, like NATO friendly frame |
| Elf | Diamond | 45°-rotated square — angular, elegant |
| Halfling | Circle | Round frame — compact, nimble |
| Dwarf | Hexagon | Six-sided frame — sturdy, geometric |

**Class → Interior icon:**

| Class | Abbr | Icon | Visual description | Inspiration |
|-------|------|------|--------------------|-------------|
| Fighter | FGT | ✕ | Saltire (diagonal cross) | NATO infantry crossed belts |
| Archer | Arc | ↑ | Upward arrow/chevron | Ranged fire direction |
| Rogue | ROG | / | Single diagonal slash | NATO cavalry sabre belt |
| Barbarian | BRB | ‡ | Double vertical cross | Heavy striking — doubled infantry |
| Black Mage | BLM | ⚡ | Zigzag bolt | Destructive elemental magic |
| White Mage | WHM | + | Upright cross | NATO medical — healing |
| Red Mage | RDM | ✳ | Six-point star | Hybrid — offense and healing |
| Bard | BRD | ∿ | Wave/tilde | Sound wave — support/influence |

**Rendering pipeline:**

1. `PawnFactory.make_symbol_texture(race, class, team)` creates a 128×128 `Image`.
2. Fill the image with transparent background.
3. `_draw_race_frame()` draws the frame outline in white/light color (2–3 px stroke) with a team-tinted fill interior.
4. `_draw_class_icon()` draws the class icon in white/contrasting color centered within the frame.
5. Convert to `ImageTexture`, cache by `(race, class, team)` key.
6. Apply to a `PlaneMesh` (size ≈ 0.5 × 0.5) positioned on top of the token cylinder, facing up (rotated -90° on X axis).

**Readability at camera pitch:** At the default 40° pitch, the top face of a 0.3-radius token is visible as an ellipse. The 128px symbol resolution and 2–3 px stroke width ensure the frame and icon remain legible at the default zoom range (4–20 orthographic size).

---

## 4. Combat HUD

### 4.1 BattleHUD layout

A `CanvasLayer` + `Control` node built programmatically in `_ready()`, following the `DraftScene._build_ui()` pattern. The HUD overlays the 3D map without blocking mouse events on the map (mouse filter set to `MOUSE_FILTER_IGNORE` on transparent areas).

Layout regions:

```
┌──────────────────────────────────────────────────────────────┐
│ Round 3 · Player A's Turn                     [Turn Order]   │
├──────────┬────────────────────────────────────┬──────────────┤
│          │                                    │              │
│  Team    │         3D Map View                │   Combat     │
│  Roster  │                                    │   Log        │
│          │                                    │              │
│          │                                    │              │
├──────────┴────────────────────────────────────┴──────────────┤
│ [Unit Info: Name HP AP Status] [Move][Atk][Ability▼][Item▼][Def][Wait] │
└──────────────────────────────────────────────────────────────┘
```

- **Top bar**: Round number, current team, turn phase.
- **Left sidebar**: Team roster (all units, both teams).
- **Right sidebar**: Combat log (scrollable).
- **Bottom bar**: Active unit info + action buttons.

All panels use semi-transparent backgrounds (`Color(0, 0, 0, 0.6)`) to avoid fully obscuring the map. Panels pass through mouse events in transparent areas.

### 4.2 Unit info panel (bottom-left region)

Displayed when a unit is activated:

- **Name & class**: `Label` showing `unit.character.display_name` and first class name.
- **HP bar**: `ProgressBar` or custom draw showing `current_hp / max_hp`. Color gradient (green → yellow → red).
- **AP pips**: two small indicators (filled = available, empty = spent).
- **Status effects**: row of labels showing active status IDs and remaining duration (e.g., "blind (1)", "sleep (2)").

### 4.3 Action panel (bottom-right region)

Row of `Button` nodes, one per action type:

| Button | Action | Enabled when | On click |
|--------|--------|-------------|----------|
| Move | `execute_move` | AP ≥ 1 | Enter TARGETING with movement overlay |
| Attack | `execute_attack` | AP ≥ 1, RNG > 0 | Enter TARGETING with target overlay |
| Abilities ▼ | Toggle ability list | AP ≥ 1, unit has abilities | Show/hide ability sub-panel |
| Items ▼ | Toggle item list | AP ≥ 1, unit has usable items | Show/hide item sub-panel |
| Defend | `execute_defend` | AP ≥ 1 | Execute immediately (no target needed) |
| Wait | `execute_wait` | Always (0 AP cost) | Execute immediately, end activation |

**Ability sub-panel**: `VBoxContainer` listing each ability the unit can use. Each entry shows:
- Ability display name
- AP cost (e.g., "2 AP")
- Range (e.g., "R3")
- Effect summary (e.g., "7 fire dmg, burst 1")
- Disabled if AP < ability.ap_cost

Clicking an ability entry enters TARGETING mode with the ability's range shown as an overlay.

**Item sub-panel**: `VBoxContainer` listing equipment items that have `granted_abilities`. Each entry shows item name and the ability it grants. Clicking enters TARGETING mode.

### 4.4 Combat log (right sidebar)

- `ScrollContainer` containing a `VBoxContainer` of `Label` nodes.
- Each action appends one or more formatted lines:
  - Move: `"[unit] moves to (q,r)"`
  - Attack: `"[unit] attacks [target] for X damage (Y HP remaining)"` or `"... DOWNED!"`
  - Ability: `"[unit] casts [ability] on [target] — X damage"` / `"... heals Y HP"` / `"... +2 DEF for 3 rounds"`
  - Status: `"[unit] applies [status] to [target] for N rounds"`
  - Defend: `"[unit] defends (+2 DEF)"`
  - Wait: `"[unit] waits"`
  - Round: `"--- Round N begins (initiative: [team]) ---"`
- Auto-scrolls to the latest entry.
- Maximum displayed entries: 100 (older entries removed to prevent unbounded growth).

### 4.5 Team roster sidebar (left sidebar)

- Two `VBoxContainer` sections (Team A, Team B), each with a header label.
- Per unit: `HBoxContainer` with:
  - Name label (truncated if needed).
  - Mini HP bar (`ProgressBar`, small).
  - Activation indicator: filled circle (pending) / checkmark (spent) / skull (downed).
- Downed units have dimmed text (`modulate.a = 0.4`).
- Active unit's entry has a subtle highlight background.

### 4.6 Turn order display (top-right region)

- Shows the remaining activation queue for the current round.
- Simple `HBoxContainer` of small labels with unit names and team colors.
- Updates after each activation completes.

---

## 5. BattleController

### 5.1 State machine

```
enum ControlState {
    AWAITING_ACTIVATION,   # Waiting for player to activate next unit (N key or auto)
    ACTION_SELECT,         # Unit activated, HUD shows action buttons
    TARGETING,             # Player chose a targeted action, overlay visible, awaiting tile click
    ANIMATING,             # Pawn movement or effect in progress, input blocked
    ROUND_END,             # All units activated, waiting for player to start next round (R key)
}
```

Additional state variables:
- `_pending_action: int` — which `ActionType` is being targeted (MOVE, ATTACK, ABILITY, USE_ITEM).
- `_pending_ability_id: String` — the specific ability ID when targeting an ability.
- `_pending_item_id: String` — the specific item ID when targeting an item use.

### 5.2 Integration with map_scene.gd

`BattleController` replaces `Phase4Demo` at the same integration point:

```gdscript
# In map_scene.gd _ready():
var controller := BattleController.new()
controller.setup(builder, state)     # or setup_from_state() for Phase 7 flow
add_child(controller)

picker.tile_selected.connect(controller.on_tile_selected)
```

The controller creates `PawnManager` and `BattleHUD` as children during setup.

### 5.3 Action flow

1. **AWAITING_ACTIVATION**: HUD shows round info and roster. Player presses N (or clicks an unactivated unit in roster) to activate the next unit. Sleeping units auto-wait (matching Phase4Demo behavior). Transitions to → ACTION_SELECT.

2. **ACTION_SELECT**: HUD shows action buttons and unit info. Movement overlay shown automatically. Player clicks a button:
   - **Move**: transitions to → TARGETING (pending_action = MOVE, movement overlay shown).
   - **Attack**: transitions to → TARGETING (pending_action = ATTACK, target overlay shown at weapon range).
   - **Ability**: player clicks ability in browser → TARGETING (pending_action = ABILITY, range overlay for ability).
   - **Item**: player clicks item in browser → TARGETING (pending_action = USE_ITEM, range overlay for item's ability).
   - **Defend**: executes immediately, updates HUD, checks AP → ACTION_SELECT or end activation.
   - **Wait**: executes immediately, ends activation → AWAITING_ACTIVATION or ROUND_END.

3. **TARGETING**: Overlay shows valid range. Player clicks a tile:
   - **Valid target**: execute action via TurnActions, transitions to → ANIMATING (if move) or back to ACTION_SELECT (if instant action). Update pawn, HUD, log.
   - **Invalid target / Escape**: cancel, return to → ACTION_SELECT. Clear overlay.

4. **ANIMATING**: Movement tween in progress. Input blocked. On tween completion: update HUD, check AP → ACTION_SELECT (if AP > 0) or end activation → AWAITING_ACTIVATION or ROUND_END.

5. **ROUND_END**: All units have activated. HUD shows "Press R to start next round". Player presses R → calls `RoundManager.start_round()` → AWAITING_ACTIVATION.

### 5.4 Keyboard shortcuts

All Phase4Demo shortcuts are preserved as alternatives:

| Key | Action | Controller response |
|-----|--------|-------------------|
| N | Activate next unit | If AWAITING_ACTIVATION: activate next unactivated unit |
| M | Move | If ACTION_SELECT: enter TARGETING for move |
| F | Attack | If ACTION_SELECT: enter TARGETING for attack |
| G | Defend | If ACTION_SELECT: execute defend |
| X | Wait | If ACTION_SELECT: execute wait |
| R | New round | If ROUND_END: start next round |
| Escape | Cancel | If TARGETING: return to ACTION_SELECT |

---

## 6. Ability & Item Browser

### 6.1 Populating the ability list

When a unit is activated, the controller queries `AbilityResolver.all_abilities(unit)` to get the full list of abilities the unit has access to. This new method iterates the same three sources as the existing `resolve()`:

1. Direct character abilities (`unit.character.abilities`).
2. Class-granted abilities (for each class in `unit.character.classes`).
3. Equipment-granted abilities (for each item in `unit.character.equipment`).

It returns deduplicated `Array[AbilityData]` (an ability appearing in multiple sources is listed once).

### 6.2 Ability display format

Each ability entry in the browser shows:

```
Fire 2          2 AP · R4 · burst 1
  7 fire damage
```

- Line 1: display name, AP cost, range, area (if any).
- Line 2: effect summary (damage value + element, heal value, buff stat/value/duration, or status id/duration).
- Entry disabled (grayed out) if `unit.ap_remaining < ability.ap_cost`.

### 6.3 Item display format

Items are shown only if they have `granted_abilities`. Each entry shows:

```
Smoke Bomb Pouch    1 AP
  Smoke Bomb — blind (2 rounds), burst 1
```

### 6.4 Targeting per effect type

| Effect type | Target selection | Overlay |
|-------------|-----------------|---------|
| Damage (enemy) | Click enemy-occupied tile in range + LoS | Target overlay (red = valid, gray = blocked) |
| Heal (friendly) | Click friendly-occupied tile in range + LoS | Heal overlay (green) |
| Buff (friendly) | Click friendly-occupied tile in range | Buff overlay (yellow) |
| Status (enemy) | Click enemy-occupied tile in range + LoS | Status overlay (purple) |
| Self (range 0) | Auto-targets caster's position | No overlay needed |

For area-of-effect abilities (burst), the overlay highlights the entire affected area when hovering over candidate center tiles.

---

## 7. Overlay Integration

The existing `OverlayController` (Phase 3) is reused for all overlay display:

- **Movement overlay**: `show_movement(pos, move, jump)` — already implemented.
- **Target overlay**: `show_targets(pos, range)` — already implemented (red = valid LoS, gray = blocked).
- **Ability range overlay**: reuse `show_targets()` with the ability's range. May need a variant for friendly-target abilities (green instead of red).

New overlay methods to consider:

```
func show_ability_range(origin: Vector2i, ability_range: int, friendly: bool) -> void
    # Like show_targets but uses green material for friendly abilities (heal/buff)

func show_area_preview(center: Vector2i, radius: int) -> void
    # Highlight hexes in burst radius around a candidate center tile
```

These extend `OverlayController` without modifying its existing behavior.

---

## 8. Data Flow & Integration

### From prior phases

| Source | Data consumed |
|--------|------|
| Phase 1 | `CharacterData`, `AbilityData`, `ItemData`, `ClassData`, `StatBlock` |
| Phase 2 | `MapBuilder`, `HexTile`, `HexWorld.hex_to_world()`, `TileMesh.TILE_HEIGHT` |
| Phase 3 | `Movement`, `RangeQuery`, `LineOfSight`, `OverlayController` |
| Phase 4 | `MatchState`, `RoundManager`, `TurnActions`, `ActionType` |
| Phase 5 | `CombatResolver` (damage, heal, buff, status resolution) |
| Phase 7 | `DraftScene` → `MatchData` autoload → `map_scene.gd` integration point |

### Outputs

- `PawnFactory`, `UnitPawn`, `PawnManager` — 3D unit representation system.
- `BattleHUD` — full combat UI overlay.
- `BattleController` — state-machine combat orchestrator replacing `Phase4Demo`.
- `AbilityResolver.all_abilities()` — ability enumeration for UI population.
- Extended `OverlayController` — friendly-target and area-preview overlays.
- A visually playable combat experience, ready for victory condition logic (Phase 9).

---

## 9. Risks & Notes

- **HUD obscuring the map.** Sidebars and bottom bar reduce the visible map area. Mitigation: use semi-transparent backgrounds, keep panels narrow, ensure the center map area remains unobstructed. Players can still pan/zoom/rotate the camera behind the HUD.
- **Pawn click selection not needed.** The existing `TilePicker` selects tiles by raycast. Since `MatchState.occupancy` maps tiles to units, clicking a tile implicitly selects its occupant. Adding a separate pawn click-detection layer is unnecessary for the MVP.
- **MatchState remains signal-free.** The controller follows the pull-based pattern: after calling a TurnActions method, it explicitly reads the result and updates PawnManager and HUD. No observer/signal infrastructure is added to MatchState.
- **Phase4Demo backward compatibility.** Phase4Demo is not deleted — it remains in the codebase. `map_scene.gd` switches to BattleController when `has_match` is true (Phase 7 flow) and can optionally fall back to Phase4Demo for developer testing. However, the default path through the game (DraftScene → map_scene) always uses BattleController.
- **Symbol readability.** At extreme zoom-out (orthographic size 20), symbols will be small. The 128px texture and high-contrast colors (white icon on team-colored fill) should remain legible, but playtest verification is needed. Fallback: increase texture resolution or add a Sprite3D billboard as a supplement.
- **No unit-specific pawn models.** All tokens use the same cylinder mesh and symbology system. Individual character identity (e.g., distinguishing two Human Fighters on the same team) is communicated through the HUD, not the pawn. Character-specific models are a future concern.
- **Tween blocking.** During the ANIMATING state, player input is blocked to prevent issuing actions mid-animation. The tween duration (0.3s) is short enough to feel responsive.

---

## 10. Phase 8 Deliverables Checklist

- [ ] `PawnFactory` with token mesh, team/active materials, and symbol texture generation (§3.1, §3.4)
- [ ] `UnitPawn` Node3D with cylinder body, symbol face, hex placement, movement tween, active highlight (§3.2)
- [ ] `PawnManager` syncing pawns with MatchState — spawn, move, remove, highlight (§3.3)
- [ ] `BattleHUD` with unit info panel, action buttons, combat log, roster sidebar (§4)
- [ ] Ability browser in action panel, populated via `AbilityResolver.all_abilities()` (§4.3, §6)
- [ ] Item browser in action panel (§4.3, §6.3)
- [ ] `BattleController` state machine replacing Phase4Demo (§5)
- [ ] Target selection flow with overlays (§5.3)
- [ ] `AbilityResolver.all_abilities(unit)` method (§6.1)
- [ ] Extended `OverlayController` for friendly-target and area-preview overlays (§7)
- [ ] `map_scene.gd` updated to use `BattleController` (§5.2)
- [ ] Keyboard shortcuts preserved from Phase4Demo (§5.4)
- [ ] GUT tests for `PawnManager` sync logic
- [ ] GUT tests for `BattleController` state transitions
- [ ] GUT tests for `AbilityResolver.all_abilities()`
- [ ] Git tag `phase-8-complete`
