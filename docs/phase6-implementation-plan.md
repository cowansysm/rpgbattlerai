# Phase 6 — Implementation Plan

**Source spec:** `phase6-spec.md`
**Builds on:** `phase0` (hex math), `phase1` (data layer, validation pipeline), `phase2` (map rendering), `phase3` (movement, range, LoS), `phase4` (activation, deployment), `phase5` (combat resolution)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed), JSON (data)
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-06-05

---

## How to use this plan

Five **work groups** (A--E). Within a group, tasks can be done in any order unless noted. Across groups: **A** (roster audit) is independent; **B** (deployment zone fixes) is independent of A; **C** (new maps) depends on the deployment sizing rules from the spec but not on A or B; **D** (validation & testing) depends on A + B + C; **E** (BP audit) is independent and can run in parallel with any group.

Phase 6 is primarily **data authoring** (JSON files) with minimal engine code changes. The only code changes are new GUT tests. All new content is validated by the existing boot-time pipeline (DataPipeline → structural validation → referential validation → stat derivation).

> **Carry-over:** consumes `DataPipeline`, `Validator`, `GameData`, `EntityRegistry`, `CharacterData`, `AbilityData`, `ItemData`, `MapData`, `ClassData`, `RaceData`, `TerrainProps`, `TileRecord`, `StatBlock`, `BattleUnit`, `HexGraph`, `MapBuilder`, `Deployment`, `MatchSetup`, `TurnActions`, `CombatResolver` from Phases 0--5.

---

## Group A — Roster Audit & Playability Verification

*Independent. Confirms all 8 characters work end-to-end with the Phase 5 combat system.*

### A1. Character instantiation audit

- For each of the 8 characters: load via `GameData.get_character()`, create a `BattleUnit` via `BattleUnit.from_character()`, and verify:
  - `final_stats` are computed correctly (base + race + class modifiers).
  - All equipment references resolve to valid `ItemData`.
  - All abilities (direct, class-granted, equipment-granted) resolve to valid `AbilityData`.
  - Weapon power is accessible via `CombatResolver.get_weapon_power()`.
- **Done:** all 8 characters instantiate without errors and have correct derived stats.

### A2. Ability resolution audit

- For each ability in the game (14 total), verify it resolves correctly when used in combat:
  - Damage abilities produce correct damage values.
  - Heal abilities restore HP correctly.
  - Buff abilities push the correct `StatModifier`.
  - Status abilities apply the correct status with correct duration.
  - AoE abilities (fire_2, inspire, smoke_bomb) affect multiple targets.
  - Self-target abilities (rage) target the caster.
- This is verified through GUT tests (Group D), not manual testing.
- **Done:** all 14 abilities resolve correctly via CombatResolver.

### A3. Equipment passive audit

- Verify equipment passives apply correctly at stat derivation time:
  - `light_armor` → DEF +1
  - `medium_armor` → DEF +2
  - `shield` → DEF +2
  - `bracer_of_accuracy` → accuracy +1 (recorded but not mechanically consumed in MVP)
- **Done:** effective stats reflect equipment passives.

---

## Group B — Deployment Zone Expansion

*Independent of A. Fixes the deployment zone sizing gap on existing maps.*

### B1. Expand `forest_clearing.json` deployment zones

- Current: 5 tiles per side. Required: 8 (standard tier, max 8 characters).
- Add 3 tiles to each deployment zone using adjacent edge hexes.
- Ensure new tiles are traversable (grass or road), exist in the tile array, and do not overlap with the other zone.
- **Selection criteria for new tiles:** prefer tiles adjacent to existing zone tiles, along the same map edge, at similar elevation.

**playerA zone** (southern edge, currently `"0,-4", "1,-4", "2,-4", "0,-3", "1,-3"`):
- Add 3 tiles from the southern/near-southern rows that are traversable and not already in the zone.

**playerB zone** (northern edge, currently `"-3,3", "-2,3", "-1,3", "0,3", "1,3"`):
- Add 3 tiles from the northern/near-northern rows.

- **Done:** both zones have 8 tiles; all tiles exist on the map and are traversable.

### B2. Expand `river_crossing.json` deployment zones

- Current: 5 tiles per side. Required: 12 (large tier, max 12 characters).
- Add 7 tiles to each deployment zone using adjacent edge hexes.
- The large map has more room; spread the zone across 2--3 rows of edge tiles for width.

**playerA zone** (southern edge, currently `"-2,-5", "-1,-5", "0,-5", "1,-5", "2,-5"`):
- Add tiles from rows r=-4 and r=-5 that are traversable.

**playerB zone** (northern edge, currently `"-2,4", "-1,4", "0,4", "1,4", "2,4"`):
- Add tiles from rows r=3 and r=4 that are traversable.

- **Done:** both zones have 12 tiles; all tiles exist on the map and are traversable.

### B3. Verify `mountain_pass.json` deployment zones

- Current: 5 tiles per side. Required: 5 (skirmish tier, max 5 characters).
- No changes needed. Verify existing zones are correct.
- **Done:** zones confirmed valid; no changes.

---

## Group C — New Maps

*Independent of A and B. Authors 3 new maps (1 per tier).*

All new maps follow these conventions:
- Axial hex coordinates (q, r), flat-top orientation.
- JSON structure matches existing maps: `{id, tier, tiles: [{q, r, elevation, terrain}, ...], deployment_zones: {playerA: [...], playerB: [...]}}`.
- Terrain types drawn from: grass, road, brush, trees, rocks, shallow_water, deep_water, cliff.
- Validated by the existing `Validator` pipeline at boot.

### C1. `ruined_watchtower.json` — Skirmish tier

- **Design brief:** crumbled tower on a hilltop. Elevation is the star.
- **Target:** ~35--45 tiles, elevation 0--5.
- **Terrain mix:** grass (base), road (paths up), rocks (rubble/walls), brush (overgrowth). No water.
- **Layout concept:**
  - Central plateau at elevation 4--5 (the tower ruin, ~5--7 tiles, mostly rocks with 1--2 accessible road tiles).
  - Mid-level ring at elevation 2--3 (~10--12 tiles, grass/brush).
  - Lower ground at elevation 0--1 (~18--22 tiles, grass/road).
  - Two approach paths (road) wind up from opposite sides.
- **Deployment zones:** 5+ tiles per side, on opposite low-ground edges.
- **Tactical character:** controlling the high ground provides elevation bonus; limited approaches create chokepoint decisions; rocks block LoS, forcing flanking.
- **Done:** JSON file authored, boots without validation errors, renders correctly.

### C2. `sunken_courtyard.json` — Standard tier

- **Design brief:** partially flooded ancient ruin. Water divides; bridges connect.
- **Target:** ~55--75 tiles, elevation 0--3.
- **Terrain mix:** road (walkways/bridges), shallow_water, deep_water (channels), grass, brush, rocks (pillars/walls).
- **Layout concept:**
  - Raised perimeter at elevation 2--3 (road/grass, deployment areas).
  - Sunken center at elevation 0 with shallow_water and deep_water channels.
  - 2--3 narrow bridges (road tiles at elevation 1) crossing the water.
  - Scattered rock pillars providing LoS-blocking cover.
  - Brush patches on the perimeter for soft cover.
- **Deployment zones:** 8+ tiles per side, on opposite perimeter edges.
- **Tactical character:** bridge control determines engagement timing; ranged units fire across water but melee must cross bridges; rock pillars break sightlines.
- **Done:** JSON file authored, boots without validation errors, renders correctly.

### C3. `open_plains.json` — Large tier

- **Design brief:** rolling grasslands with a stream and scattered brush. Open and expansive.
- **Target:** ~90--110 tiles, elevation 0--2.
- **Terrain mix:** grass (dominant, ~60--70%), brush (~15%), road (~10%), shallow_water (stream, ~5--10%).
- **Layout concept:**
  - Wide, roughly rectangular footprint.
  - Gentle elevation changes (0--2) across rolling hills.
  - A shallow_water stream running roughly perpendicular to the deployment axis, creating a soft dividing line.
  - Road crossing the stream at one or two fords.
  - Brush clusters providing scattered soft cover, more concentrated near the stream.
  - No impassable terrain (no rocks, deep_water, or cliff) — everything is traversable.
- **Deployment zones:** 12+ tiles per side, spread across 2 rows of edge tiles for width.
- **Tactical character:** wide-open sightlines favor ranged units and AoE. Little hard cover forces aggressive use of terrain elevation. The stream slows but doesn't stop crossing. Many valid strategies.
- **Done:** JSON file authored, boots without validation errors, renders correctly.

### C4. Map authoring validation

- After authoring each map, run the game to trigger boot-time validation.
- Verify: all tile coordinates are unique, all terrains reference valid terrain types, deployment zone tiles exist in the tile array, tile set is contiguous.
- Load each map in the map scene to confirm 3D rendering is correct.
- **Done:** all 3 new maps pass validation and render correctly.

---

## Group D — Testing & Validation

*Depends on A + B + C. Verifies all content through automated and manual tests.*

### D1. Character instantiation tests (GUT)

- Test: for each of the 8 character IDs, load via `GameData.get_character()`, create `BattleUnit` via `BattleUnit.from_character()`, assert non-null.
- Test: final stats match expected values (base + race mods + class mods).
- Test: weapon power lookup via `CombatResolver.get_weapon_power()` returns expected values for each character.
- Test: all abilities for each character are accessible via `AbilityResolver`.
- **Done:** green, headless.

```gdscript
# tests/core/data/test_roster.gd
extends GutTest

## Verify all 8 spec characters instantiate correctly.

var _character_ids: Array[String] = [
    "human_fighter", "human_archer", "human_rogue", "human_bard",
    "dwarf_barbarian", "elf_black_mage", "elf_red_mage", "halfling_white_mage"
]

func test_all_characters_load() -> void:
    for id in _character_ids:
        var c := GameData.get_character(id)
        assert_not_null(c, "Character '%s' should load" % id)

func test_all_characters_have_final_stats() -> void:
    for id in _character_ids:
        var fs := GameData.get_final_stats(id)
        assert_not_null(fs, "Character '%s' should have final stats" % id)
        assert_gt(fs.effective("hp"), 0, "'%s' HP should be > 0" % id)

func test_all_characters_create_battle_units() -> void:
    for id in _character_ids:
        var c := GameData.get_character(id)
        var fs := GameData.get_final_stats(id)
        var u := BattleUnit.from_character(c, fs)
        assert_not_null(u, "BattleUnit for '%s' should create" % id)
        assert_eq(u.character.id, id)
        assert_gt(u.current_hp, 0)

func test_weapon_power_for_armed_characters() -> void:
    # Characters with weapons and their expected weapon power
    var expected: Dictionary = {
        "human_fighter": 3,    # sword
        "human_archer": 2,     # bow
        "human_rogue": 2,      # daggers
        "human_bard": 1,       # sling
        "dwarf_barbarian": 5,  # greataxe
        "elf_red_mage": 3,     # rapier
    }
    for id in expected.keys():
        var c := GameData.get_character(id)
        var fs := GameData.get_final_stats(id)
        var u := BattleUnit.from_character(c, fs)
        var wp: int = CombatResolver.get_weapon_power(u, GameData.get_item)
        assert_eq(wp, int(expected[id]),
            "'%s' weapon power should be %d, got %d" % [id, expected[id], wp])

func test_casters_have_zero_weapon_power() -> void:
    # Staff has weapon_power=1, so these should be 1 not 0
    for id in ["elf_black_mage", "halfling_white_mage"]:
        var c := GameData.get_character(id)
        var fs := GameData.get_final_stats(id)
        var u := BattleUnit.from_character(c, fs)
        var wp: int = CombatResolver.get_weapon_power(u, GameData.get_item)
        assert_eq(wp, 1, "'%s' weapon power (staff) should be 1" % id)
```

### D2. Map loading and deployment zone tests (GUT)

- Test: all 6 maps load via `GameData.get_map()`.
- Test: each map's deployment zones have at least `tier.max` tiles per side.
- Test: all deployment zone tile coordinates exist in the map's tile array.
- Test: deployment zone tiles are traversable (not impassable terrain).
- **Done:** green, headless.

```gdscript
# tests/core/data/test_maps.gd
extends GutTest

## Verify all maps load, have correct deployment zones, and meet tier sizing.

var _tier_max: Dictionary = {
    "skirmish": 5,
    "standard": 8,
    "large": 12,
}

var _map_ids: Array[String] = [
    "mountain_pass", "ruined_watchtower",
    "forest_clearing", "sunken_courtyard",
    "open_plains", "river_crossing",
]

func test_all_maps_load() -> void:
    for id in _map_ids:
        var m := GameData.get_map(id)
        assert_not_null(m, "Map '%s' should load" % id)

func test_deployment_zones_meet_tier_max() -> void:
    for id in _map_ids:
        var m := GameData.get_map(id)
        if not m:
            continue
        var required: int = _tier_max.get(m.tier, 0)
        for team in ["playerA", "playerB"]:
            var zone: Array = m.deployment_zones.get(team, [])
            assert_gte(zone.size(), required,
                "Map '%s' (%s) %s zone should have >= %d tiles, has %d" % [
                    id, m.tier, team, required, zone.size()])

func test_deployment_zone_tiles_exist_on_map() -> void:
    for id in _map_ids:
        var m := GameData.get_map(id)
        if not m:
            continue
        var tile_coords: Dictionary = {}
        for t: TileRecord in m.tiles:
            tile_coords[Vector2i(t.q, t.r)] = true
        for team in ["playerA", "playerB"]:
            var zone: Array = m.deployment_zones.get(team, [])
            for s in zone:
                var parts := str(s).split(",")
                var coord := Vector2i(int(parts[0]), int(parts[1]))
                assert_true(tile_coords.has(coord),
                    "Map '%s' %s zone tile %s should exist in tile array" % [
                        id, team, str(coord)])

func test_deployment_zone_tiles_are_traversable() -> void:
    for id in _map_ids:
        var m := GameData.get_map(id)
        if not m:
            continue
        var tile_terrain: Dictionary = {}
        for t: TileRecord in m.tiles:
            tile_terrain[Vector2i(t.q, t.r)] = t.terrain
        for team in ["playerA", "playerB"]:
            var zone: Array = m.deployment_zones.get(team, [])
            for s in zone:
                var parts := str(s).split(",")
                var coord := Vector2i(int(parts[0]), int(parts[1]))
                var terrain_id: String = tile_terrain.get(coord, "")
                var tp: TerrainProps = GameData.get_terrain(terrain_id)
                if tp:
                    assert_false(tp.impassable,
                        "Map '%s' %s zone tile %s terrain '%s' should be traversable" % [
                            id, team, str(coord), terrain_id])
```

### D3. Boot validation test

- Run the game to trigger the DataPipeline boot sequence.
- Verify: 0 validation errors logged, all entity counts match expectations (8 characters, 14 abilities, 12 items, 8 classes, 4 races, 6 maps, 8 terrains).
- **Done:** boot completes cleanly.

### D4. Manual map rendering check

- Load each of the 6 maps in the map scene (change `map_id` export).
- Visually confirm: tiles render at correct elevations, terrain colors/materials are distinct, deployment zones are in sensible edge positions, the camera can view the full map.
- **Done:** all 6 maps render correctly.

### D5. End-to-end combat test on new maps

- For each new map, run the Phase 4/5 demo (or modify demo to load the map).
- Deploy a 2v2 party, play through at least one round of combat.
- Verify: movement respects terrain, attacks resolve damage, abilities work, no errors logged.
- **Done:** combat works on all new maps.

---

## Group E — BP Audit

*Independent. Can run in parallel with any other group.*

### E1. Compute estimated BP for each character

Using the heuristic weights from the spec (§6.2 of phase6-spec.md), compute estimated BP:

```
BP_est = w1*HP + w2*ATK + w3*DEF + w4*SPD + w5*RNG
       + sum(ability_values) + sum(equipment_bp)
```

**Weights used:**

| Weight | Value | Rationale |
|--------|-------|-----------|
| w1 (HP) | 0.3 | Survivability; lower weight because HP alone doesn't win fights. |
| w2 (ATK) | 1.0 | Direct damage output. |
| w3 (DEF) | 1.0 | Damage reduction scales with match length. |
| w4 (SPD) | 1.0 | Movement is positioning advantage; also determines initiative. |
| w5 (RNG) | 0.5 | Range provides safety but has diminishing returns. |

**Ability value estimates:**

| Ability | Type | Value Est. | Rationale |
|---------|------|-----------|-----------|
| fire_1 | spell dmg 4 | 3.0 | Solid ranged damage, ignores DEF |
| fire_2 | spell dmg 7 AoE | 6.0 | Premium: high damage, AoE burst, DEF bypass |
| ice_1 | spell dmg 4 | 3.0 | Same as fire_1 |
| thunder_1 | spell dmg 5 | 4.0 | Higher base damage than fire/ice |
| cure_1 | spell heal 4 | 2.5 | Solid ranged heal |
| cure_2 | spell heal 8 | 4.0 | Strong heal, costs 2 AP |
| shield_1 | spell buff def+2 | 3.0 | Good ranged defensive buff, 3-round duration |
| power_strike | skill dmg 4 | 2.0 | Melee, reduced by DEF |
| reckless_swing | skill dmg 6 | 3.0 | High melee damage, reduced by DEF |
| rage | skill buff atk+3 | 2.5 | Strong but self-only limits value |
| backstab | skill dmg 5 | 2.5 | Good melee damage |
| inspire | skill buff atk+2 AoE | 4.0 | AoE offensive buff, high team value |
| lullaby | skill status sleep | 3.5 | Powerful CC, skips target's turn |
| smoke_bomb | item status blind AoE | 3.5 | AoE CC, causes attack failure |

### E2. Per-character audit table

Final stats are computed as: base + race modifiers + class modifiers.

| Character | Authored BP | Final Stats (SPD/ATK/RNG/DEF/HP) | Stat Score | Equip BP | Ability Score | Est. BP | Delta | Flag |
|-----------|-------------|----------------------------------|------------|----------|---------------|---------|-------|------|
| human_fighter | 18 | 3/4/1/4/16 | 16.3 | 6 | 2.0 | 24.3 | +6.3 (+35%) | YES |
| human_archer | 13 | 3/2/3/1/10 | 10.5 | 5 | 0 | 15.5 | +2.5 (+19%) | YES |
| human_rogue | 16 | 5/3/1/0/11 | 11.8 | 4 | 6.0 | 21.8 | +5.8 (+36%) | YES |
| human_bard | 17 | 3/1/2/1/12 | 9.6 | 2 | 7.5 | 19.1 | +2.1 (+12%) | no |
| dwarf_barbarian | 20 | 2/5/1/2/22 | 16.1 | 4 | 5.5 | 25.6 | +5.6 (+28%) | YES |
| elf_black_mage | 30 | 4/0/0/0/11 | 7.3 | 1 | 16.0 | 24.3 | -5.7 (-19%) | YES |
| elf_red_mage | 26 | 4/3/1/1/12 | 12.1 | 3 | 5.5 | 20.6 | -5.4 (-21%) | YES |
| halfling_white_mage | 24 | 3/0/1/-1/13 | 6.4 | 1 | 9.5 | 16.9 | -7.1 (-30%) | YES |

**Stat Score** = `w1*HP + w2*ATK + w3*DEF + w4*SPD + w5*RNG`
**Est. BP** = Stat Score + Equip BP + Ability Score

### E3. Discrepancy analysis

**7 of 8 characters flagged** (>15% delta). The heuristic systematically:

1. **Overestimates physical characters** (Fighter +35%, Rogue +36%, Barbarian +28%): high base stats and equipment produce large stat scores, but the heuristic doesn't account for the fact that physical damage is reduced by target DEF — making raw ATK less valuable against armored targets.

2. **Underestimates casters** (Black Mage -19%, White Mage -30%, Red Mage -21%): the heuristic doesn't capture that spell damage **ignores DEF**, making it far more reliable than physical damage of equal value. Support abilities (healing, shields, buffs) provide compounding value over multiple rounds that a single-point estimate misses.

3. **Versatility premium not captured**: the Red Mage can melee, cast fire, and heal — this flexibility is worth more than the sum of individual ability values because it adapts to any tactical situation. The authored BP of 26 reflects this premium.

4. **Negative DEF penalty underweighted**: the White Mage's DEF of -1 means it takes MORE damage from every physical attack. The formula treats this as -1 to the stat score, but the actual combat impact is much larger (fragility compounds with low HP pool).

**Recommendations for Phase 9:**

- Revise weights to reduce stat contribution and increase ability contribution, especially for DEF-bypassing spells.
- Add a "survivability" composite factor (HP * DEF interaction) rather than treating them independently.
- Add a "versatility multiplier" for characters with abilities spanning multiple effect types.
- Consider separate "offensive threat" and "support utility" pricing tracks.
- Playtest with the full match loop (Phase 8) before adjusting any BP values — real match data is more informative than formula estimates.

> **This audit is informational input to Phase 9. No BP values are changed in Phase 6.**

---

## Dependency Map

```
Phase 1-5 (engine + data) ──> A (roster audit)
                           ──> B (deployment zone fixes)
                           ──> C (new maps)
                           ──> E (BP audit)
A + B + C ──> D (testing & validation)
```

Groups A, B, C, and E are **independent** and can be worked in parallel.
Group D is the final gate and depends on A, B, and C completing.

**Suggested order:** B (quick fixes) → C (map authoring, largest effort) → A (audit while maps settle) → D (validate everything) → E (BP audit, any time).

---

## Phase 6 Definition of Done

- [ ] All 8 characters from §6 load, instantiate as BattleUnits, and have correct derived stats (A).
- [ ] All 14 abilities resolve correctly through CombatResolver (A).
- [ ] Equipment passives apply correctly to effective stats (A).
- [ ] `forest_clearing.json` deployment zones expanded to 8 tiles per side (B).
- [ ] `river_crossing.json` deployment zones expanded to 12 tiles per side (B).
- [ ] `mountain_pass.json` deployment zones confirmed valid at 5 tiles per side (B).
- [ ] `ruined_watchtower.json` authored — skirmish tier, ~35--45 tiles, elev 0--5, 5+ deploy tiles/side (C).
- [ ] `sunken_courtyard.json` authored — standard tier, ~55--75 tiles, elev 0--3, 8+ deploy tiles/side (C).
- [ ] `open_plains.json` authored — large tier, ~90--110 tiles, elev 0--2, 12+ deploy tiles/side (C).
- [ ] All 6 maps pass structural and referential validation at boot (D).
- [ ] GUT tests for character instantiation and derived stats — green (D).
- [ ] GUT tests for map loading and deployment zone sizing — green (D).
- [ ] All 6 maps render correctly in the map scene (D).
- [ ] End-to-end combat demo runs on at least one new map without errors (D).
- [ ] BP audit table completed with estimated vs. authored values and flagged discrepancies (E).
- [ ] Git tag `phase-6-complete`.
