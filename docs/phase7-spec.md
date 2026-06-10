# Phase 7 — Party Building & Match Setup Specification

**Parent plan:** `rpg-implementation-plan.md` (Phase 7)
**Builds on:** `phase0-spec.md` (hex math), `phase1-spec.md` (data layer, validation), `phase2-spec.md` (rendered map), `phase3-spec.md` (movement, range, LoS), `phase4-spec.md` (activation loop, deployment, match setup), `phase5-spec.md` (combat resolution), `phase6-spec.md` (content authoring)
**Source spec:** `rpg-specs.md` (§5, §6, §7.2)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-09

---

## 1. Purpose & Scope

Phase 7 introduces the **player-facing entry point** to a match. Until now, parties were hardcoded in demo scripts and BattleUnits created programmatically. Phase 7 gives both players a UI to select a tier, draft a legal party from the shared character pool, and launch into battle on a randomly selected map.

This is the first phase with a real Godot UI scene. The logic layer (draft validation, map selection, match construction) is built as headless, testable GDScript classes. The UI scene consumes those classes and provides the visual flow.

### In scope

- **Tier selection UI**: player chooses Skirmish, Standard, or Large. Both players use the same tier.
- **Character drafting UI**: each player picks characters from the shared premade pool within the BP cap and size bounds. Both players draft independently on a shared screen (Player A drafts, confirms, then Player B drafts, confirms).
- **Draft validation**: enforce BP cap, character count min/max, no duplicate characters within a single party.
- **Mirror picks**: both players may draft the same character. No exclusion across parties.
- **Random map selection**: after both parties are confirmed, a map of the chosen tier is selected at random. No manual map choice.
- **Match construction**: create BattleUnits from both drafts, wire MatchSetup, auto-deploy, and hand off to the combat loop.
- **Headless logic classes**: `PartyDraft` (single-player draft state and validation) and `MatchBuilder` (orchestrates tier, drafts, map, and match creation) — fully testable without the UI.
- **GUT tests**: draft validation, party legality, map filtering, match construction.

### Out of scope

- Free-form character building or loadout editing (deferred; spec §10).
- Alternating/exclusive draft mode (both players pick independently).
- Manual map selection or map veto (random selection only for MVP).
- AI-controlled drafting or auto-party generation.
- Network/multiplayer drafting (shared screen only).
- Visual polish, animations, or transitions (Phase 11).
- Victory conditions and match-end flow (Phase 9).
- BP rebalancing (Phase 10).

### Exit criteria

Phase 7 is complete when:

1. A `PartyDraft` class validates character additions against tier BP cap, size bounds, and duplicate rules.
2. A `MatchBuilder` class orchestrates tier config lookup, map filtering by tier, random map selection, and full match construction (BattleUnits, MatchSetup, Deployment).
3. A Godot UI scene allows two human players to sequentially select a tier, draft parties, confirm, and start a match.
4. The UI displays available characters with BP cost, tracks remaining BP, enforces min/max character count, and disables illegal actions.
5. After both players confirm, a random map of the selected tier is chosen and the match begins (deployment + round 1).
6. GUT tests verify draft validation, party legality, map selection, and match construction headlessly.
7. The full flow — tier select → draft A → draft B → random map → deploy → combat — runs end to end without errors.
8. Git tag `phase-7-complete`.

---

## 2. Design Decisions (Phase 7)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Draft model** | Independent drafting. Both players see the full 8-character pool. Mirror picks allowed. No exclusion across parties. | Simplest MVP model. Matches spec §5.3 ("each player privately drafts"). Exclusion drafts add strategic depth but require alternating-turn UI — deferred. |
| **Player flow** | Shared screen, sequential. Player A drafts and confirms, then Player B drafts and confirms. Player B does not see Player A's picks until both are done. | Supports two-player local play without networking. Player A's draft is hidden during Player B's turn to preserve the "privately drafts" spec intent. |
| **Map selection** | Random from all maps matching the selected tier. No player choice or veto. | Saves time on map selection UI. The 2 maps per tier from Phase 6 provide variety. Manual selection can be added as Phase 11 polish. |
| **Duplicate characters** | A single player cannot draft the same character twice. Across players, duplicates (mirror picks) are allowed. | Spec §5.1 says "the same character may be available to both players (mirror picks allowed unless a tier rules otherwise)." No tier currently restricts mirrors. |
| **Validation timing** | Validation is continuous: the UI disables adding characters that would violate BP cap or max count. The confirm button is disabled until the party meets min count. | Prevents invalid states entirely rather than validating at submission. Better UX. |
| **Logic/UI separation** | `PartyDraft` and `MatchBuilder` are pure logic classes (RefCounted, no Node dependency). The UI scene instantiates and queries them. | Testable headlessly. UI can be replaced or redesigned without touching validation logic. Consistent with Phase 4/5 pattern (e.g., TurnActions is pure logic). |
| **File organization** | Logic in `src/core/combat/` (alongside match_setup.gd, deployment.gd). UI in `src/ui/` (new directory). Scene in `scenes/draft/`. | `src/core/combat/` is the natural home for match-adjacent logic. `src/ui/` establishes a convention for future UI scenes (Phase 9 result screen, Phase 11 polish). |
| **Tier config source** | Read from `Constants.get_value("tiers")` at runtime. No hardcoded tier values in logic classes. | Tier definitions already exist in `data/constants.json`. Single source of truth. |
| **Match handoff** | After deployment, the system transitions to the Phase 4 combat loop. Phase 7 does not modify combat logic — it constructs the inputs that MatchSetup and Deployment consume. | Clean phase boundary. Phase 7's output is a deployed MatchState; Phases 4/5 take over from there. |
| **No auto-draft / AI** | Both players are human. No AI opponent drafting logic. Both sides must be manually drafted. | AI drafting is a distinct feature with its own heuristics. Out of scope for the match setup phase. |

---

## 3. Draft Flow

### 3.1 High-level sequence

```
1. Tier Selection
   - Player chooses Skirmish / Standard / Large.
   - Tier config (BP cap, min/max chars) loaded from Constants.

2. Player A Draft
   - Shared character pool displayed (all 8 characters).
   - Player A adds/removes characters.
   - UI shows: selected characters, total BP, remaining BP, character count vs. bounds.
   - Confirm button enabled when party meets min character count and BP ≤ cap.
   - On confirm: draft locked, state preserved.

3. Player B Draft
   - Same pool displayed (independent — Player A's picks are not excluded).
   - Player B drafts independently with the same rules.
   - On confirm: draft locked.

4. Match Start
   - Random map selected from the tier's available maps.
   - BattleUnits created from both drafts.
   - MatchSetup.create() builds the MatchState.
   - Deployment.auto_deploy() places units.
   - RoundManager.start_round() begins combat.
```

### 3.2 Draft validation rules

A party draft is **valid** when all of the following hold:

| Rule | Check |
|------|-------|
| BP cap | `total_bp <= tier.bp_cap` |
| Min characters | `party_size >= tier.min` |
| Max characters | `party_size <= tier.max` |
| No self-duplicates | Each character ID appears at most once in the party |

A character **can be added** to a draft when:

| Rule | Check |
|------|-------|
| Not already in party | `character_id not in selected_ids` |
| BP would not exceed cap | `total_bp + character.bp <= tier.bp_cap` |
| Party not at max size | `party_size < tier.max` |

### 3.3 Draft state transitions

```
EMPTY → DRAFTING (first character added)
DRAFTING → VALID (min count met AND BP ≤ cap)
VALID → DRAFTING (character removed, dropping below min)
VALID → CONFIRMED (player confirms)
CONFIRMED → (locked, no further changes)
```

The `PartyDraft` class tracks the current state and exposes it for UI binding.

---

## 4. PartyDraft — Logic Class

### 4.1 Responsibilities

- Hold the list of selected character IDs for one player.
- Track total BP cost.
- Validate additions and removals against tier rules.
- Report draft state (empty, drafting, valid, confirmed).
- Provide the data needed to create BattleUnits after confirmation.

### 4.2 Interface

```gdscript
class_name PartyDraft
extends RefCounted

enum State { EMPTY, DRAFTING, VALID, CONFIRMED }

# Construction
func _init(tier_config: Dictionary, character_provider: Callable) -> void
    ## tier_config: {bp_cap: int, min: int, max: int}
    ## character_provider: (String) -> CharacterData

# Queries
func state() -> State
func selected_ids() -> Array[String]
func party_size() -> int
func total_bp() -> int
func remaining_bp() -> int
func can_add(character_id: String) -> bool
func is_valid() -> bool           # meets min count and BP ≤ cap

# Mutations
func add_character(character_id: String) -> String    # "" on success, error message on failure
func remove_character(character_id: String) -> String  # "" on success, error message on failure
func confirm() -> String                               # "" on success, error if not valid

# Data output (post-confirm)
func confirmed_ids() -> Array[String]  # same as selected_ids, but only after confirm
```

### 4.3 Tier config format

Consumed from `Constants.get_value("tiers")[tier_id]`:

```json
{ "bp_cap": 150, "min": 4, "max": 8 }
```

### 4.4 Character provider

The `character_provider: Callable` takes a character ID string and returns a `CharacterData`. In production this is `GameData.get_character`. In tests this can be a stub that returns mock CharacterData with controlled BP values.

---

## 5. MatchBuilder — Orchestration Class

### 5.1 Responsibilities

- Load tier config from Constants.
- Filter maps by tier.
- Select a random map from the tier's available maps.
- Create BattleUnit arrays from confirmed drafts.
- Wire MatchSetup, Deployment, and RoundManager to produce a ready-to-play MatchState.

### 5.2 Interface

```gdscript
class_name MatchBuilder
extends RefCounted

# Construction
func _init(
    character_provider: Callable,   # (String) -> CharacterData
    stats_provider: Callable,       # (String) -> StatBlock
    map_provider: Callable,         # (String) -> MapData
    terrain_provider: Callable,     # (String) -> TerrainProps
    ability_provider: Callable,     # (BattleUnit, String) -> AbilityData or null
    item_provider: Callable,        # (String) -> ItemData or null
) -> void

# Tier
func get_tier_config(tier_id: String) -> Dictionary    # {bp_cap, min, max}
func get_tier_ids() -> Array[String]                   # ["skirmish", "standard", "large"]

# Map
func get_maps_for_tier(tier_id: String) -> Array[MapData]
func select_random_map(tier_id: String) -> MapData

# Match construction
func build_match(
    draft_a: PartyDraft,
    draft_b: PartyDraft,
    map_data: MapData,
) -> Dictionary    # {state: MatchState, errors: Array[String]}
```

### 5.3 Build match sequence

`build_match()` performs these steps:

1. **Validate** both drafts are in `CONFIRMED` state.
2. **Create BattleUnits** from each draft's confirmed IDs:
   - `GameData.get_character(id)` → `CharacterData`
   - `GameData.get_final_stats(id)` → `StatBlock`
   - `BattleUnit.from_character(char_data, final_stats)` → `BattleUnit`
3. **Call MatchSetup.create()** with the two party arrays, the selected map, and the terrain provider. This builds the HexGraph and determines initiative.
4. **Wire providers** on the MatchState: `ability_provider`, `item_provider`.
5. **Call Deployment.auto_deploy()** with the map's deployment zones. Returns errors if zones are insufficient (should not happen with Phase 6's validated zones).
6. **Call RoundManager.start_round()** to begin the first round.
7. **Return** `{state: MatchState, errors: []}` on success, or `{state: null, errors: [...]}` on failure.

### 5.4 Map filtering

Maps are filtered by matching `MapData.tier` to the selected tier ID. The `map_provider` callable is used to look up maps; the full list of map IDs is iterated to find matches. `GameData.all_maps()` may need to be exposed if not already available — alternatively, map IDs can be provided externally.

---

## 6. UI Scene — Draft Flow

### 6.1 Scene structure

```
DraftScene (Control)
├── TierSelectPanel (VBoxContainer)
│   ├── TierLabel ("Select Match Tier")
│   ├── SkirmishButton (Button)
│   ├── StandardButton (Button)
│   └── LargeButton (Button)
├── DraftPanel (VBoxContainer) [hidden until tier selected]
│   ├── PlayerLabel ("Player A — Draft Your Party")
│   ├── InfoBar (HBoxContainer)
│   │   ├── BPLabel ("BP: 0 / 150")
│   │   ├── CountLabel ("Characters: 0 / 4–8")
│   │   └── TierLabel ("Standard")
│   ├── RosterGrid (GridContainer) [available characters]
│   │   └── CharacterCard × 8 (Button or PanelContainer)
│   │       ├── NameLabel
│   │       ├── ClassLabel
│   │       └── BPLabel
│   ├── SelectedList (VBoxContainer) [current party]
│   │   └── SelectedEntry × N
│   │       ├── NameLabel
│   │       └── RemoveButton
│   └── ConfirmButton (Button) [disabled until valid]
└── MatchStartPanel (VBoxContainer) [hidden until both confirmed]
    ├── MapLabel ("Map: Forest Clearing")
    ├── PartySummaryA
    ├── PartySummaryB
    └── StartBattleButton (Button)
```

### 6.2 UI flow states

```
TIER_SELECT → DRAFT_PLAYER_A → DRAFT_PLAYER_B → MATCH_READY → BATTLE
```

| State | Visible panel | Behavior |
|-------|---------------|----------|
| `TIER_SELECT` | TierSelectPanel | Three tier buttons. Click selects tier, creates PartyDraft for Player A, transitions to DRAFT_PLAYER_A. |
| `DRAFT_PLAYER_A` | DraftPanel | Header says "Player A". Roster grid shows all characters. Player adds/removes. Confirm button active when draft is valid. On confirm: draft locked, transitions to DRAFT_PLAYER_B. |
| `DRAFT_PLAYER_B` | DraftPanel | Header says "Player B". Same roster (independent pool). New PartyDraft instance. On confirm: transitions to MATCH_READY. |
| `MATCH_READY` | MatchStartPanel | Shows selected map (random), both party summaries. Start Battle button builds the match and transitions to battle. |
| `BATTLE` | (scene change) | Match scene takes over with the constructed MatchState. |

### 6.3 Character card display

Each character card shows:

- **Name**: e.g., "Human Archer"
- **Class**: e.g., "Archer"
- **BP cost**: e.g., "13 BP"
- **Key stats**: SPD / ATK / RNG / DEF / HP (compact)

Cards are **clickable** to add the character to the party. A card is **visually disabled** (greyed out) when `can_add()` returns false (already in party, would exceed BP cap, or party at max size).

### 6.4 Privacy between players

When Player A confirms and the screen transitions to Player B's draft, Player A's selections are hidden. Player B sees a fresh draft panel with no indication of Player A's picks. After both confirm, the MatchStartPanel reveals both parties.

This is a shared-screen, honor-system approach. Sufficient for local two-player MVP.

---

## 7. Random Map Selection

### 7.1 Logic

After both players confirm their drafts:

1. Query all loaded maps via GameData.
2. Filter to maps where `map.tier == selected_tier`.
3. Select one at random (`maps[randi() % maps.size()]`).
4. Display the selected map name on the MatchStartPanel.

### 7.2 Edge cases

- **No maps for tier**: should not happen (Phase 6 guarantees 2 maps per tier). If it does, return an error and block match start.
- **Single map for tier**: that map is always selected. No randomness needed.

---

## 8. Match Construction Integration

### 8.1 From prior phases

| Source | Consumed by Phase 7 |
|--------|---------------------|
| Phase 1 | `CharacterData`, `StatBlock`, `BattleUnit.from_character()`, `GameData.*` accessors |
| Phase 4 | `MatchSetup.create()`, `Deployment.auto_deploy()`, `RoundManager.start_round()`, `MatchState` |
| Phase 5 | `MatchState.ability_provider`, `MatchState.item_provider` (wired during build) |
| Phase 6 | 8 characters, 6 maps (2 per tier), validated deployment zones |
| Constants | `tiers` config block |

### 8.2 Outputs

- A fully initialized `MatchState` with:
  - Two deployed parties (BattleUnits on map tiles).
  - HexGraph built from the selected map.
  - Initiative determined.
  - Providers wired (ability, item).
  - Round 1 started (activation queue built).
- The UI scene can then hand off to the combat scene / demo loop.

### 8.3 Scene transition

Phase 7 does not dictate how the combat scene is structured (that's Phase 4's demo or a future combat scene). The `DraftScene` constructs the MatchState and either:
- Changes scene to the existing map/combat scene, passing the MatchState.
- Or emits a signal that the main scene handles.

The simplest approach for MVP: the `DraftScene` builds the MatchState and changes to a combat scene that receives it. The exact handoff mechanism (scene change, signal, autoload) is an implementation detail decided in the implementation plan.

---

## 9. Data Flow Summary

```
Constants.tiers ──> PartyDraft (validation rules)
GameData.all_characters() ──> UI (roster display)
GameData.get_character(id) ──> PartyDraft (BP lookup)
PartyDraft.confirmed_ids() ──> MatchBuilder (unit creation)
GameData.get_final_stats(id) ──> MatchBuilder (BattleUnit creation)
GameData.get_map(id) ──> MatchBuilder (map for match)
MatchBuilder.build_match() ──> MatchState (ready to play)
MatchState ──> Combat scene (Phase 4/5 loop)
```

---

## 10. Risks & Notes

- **First UI scene.** Phases 0--6 were headless logic and demo scripts. Phase 7 introduces Control nodes, scene files, and input handling for the first time. Keep the UI minimal — functional buttons and labels, no visual polish. Phase 11 handles presentation.
- **Scene transition pattern.** No established pattern exists for scene transitions in this project. Phase 7 establishes the convention. Keep it simple: direct scene change or autoload-based state passing.
- **GameData.all_maps() accessor.** The existing `GameData` autoload may not expose a method to list all maps. If not, one must be added (thin wrapper over DataPipeline). This is a minor extension, not a redesign.
- **RNG seeding.** Random map selection uses Godot's built-in `randi()`. For reproducible testing, tests should use seeded RNG or mock the selection. The production code does not need deterministic seeding.
- **Shared screen privacy.** Player A's draft is hidden during Player B's turn by UI state management (clearing the selected list, resetting the panel). There is no encryption or true privacy — this is honor-system for local play.
- **Character card layout.** The roster grid with 8 cards needs to be readable on various screen sizes. A 4×2 grid is a reasonable default. Exact layout is an implementation detail.
- **No undo after confirm.** Once a player confirms their draft, it is locked. There is no back button to re-draft. This is intentional for simplicity. A "Back" button could be added as Phase 11 polish.
- **AbilityResolver integration.** The MatchBuilder must wire `AbilityResolver.resolve` as the `ability_provider` on MatchState, matching the pattern from the Phase 4 demo. This is a wiring detail, not new logic.

---

## 11. Phase 7 Deliverables Checklist

- [ ] `PartyDraft` class with add/remove/validate/confirm logic, enforcing BP cap, size bounds, and no self-duplicates (§4).
- [ ] `MatchBuilder` class with tier config lookup, map filtering by tier, random map selection, and full match construction (§5).
- [ ] `GameData.all_maps()` accessor if not already present (§5.4).
- [ ] UI scene: tier selection panel with 3 tier buttons showing BP cap and size bounds (§6.1, §6.2).
- [ ] UI scene: draft panel with character roster grid, selected list, BP counter, character count, and confirm button (§6.1, §6.2).
- [ ] UI scene: match start panel showing selected map, both party summaries, and start battle button (§6.1, §6.2).
- [ ] Sequential draft flow: Player A drafts → confirms → Player B drafts → confirms (§6.2).
- [ ] Character cards display name, class, BP, and key stats; disabled when `can_add()` is false (§6.3).
- [ ] Privacy: Player A's selections hidden during Player B's draft (§6.4).
- [ ] Random map selection from tier-matching maps after both drafts confirmed (§7).
- [ ] Match construction: BattleUnits created, MatchSetup wired, Deployment run, Round 1 started (§8).
- [ ] Scene transition to combat after match construction (§8.3).
- [ ] GUT tests for PartyDraft: add/remove validation, BP cap enforcement, size bounds, duplicate rejection, state transitions (headless).
- [ ] GUT tests for MatchBuilder: tier config, map filtering, match construction with mock data (headless).
- [ ] End-to-end flow: tier select → draft A → draft B → random map → deploy → combat round 1 runs without errors.
- [ ] Git tag `phase-7-complete`.
