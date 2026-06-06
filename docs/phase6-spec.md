# Phase 6 — Content: Roster, Abilities & Maps Specification

**Parent plan:** `rpg-implementation-plan.md` (Phase 6)
**Builds on:** `phase0-spec.md` (hex math), `phase1-spec.md` (data layer, validation), `phase2-spec.md` (rendered map, terrain), `phase3-spec.md` (movement, range, LoS), `phase4-spec.md` (activation loop, action economy), `phase5-spec.md` (combat resolution)
**Source spec:** `rpg-specs.md` (§3.2, §5.2, §6, §9)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-05

---

## 1. Purpose & Scope

Phase 6 is the **content authoring phase**. Phases 0--5 built the engine: hex math, data layer, 3D map rendering, movement/range/LoS, the activation loop, and combat resolution. Phase 6 ensures there is enough authored content to make matches **varied and playable** across all three tiers. This phase is primarily data work (JSON), not engine code.

The master plan notes Phase 6 runs "in parallel with P4--P5 as soon as the schema (P1) is stable." Content was seeded during Phases 1--5 (8 characters, 14 abilities, 12 items, 3 maps). Phase 6 audits that content for completeness, fixes gaps, expands maps to support full tier party sizes, and adds additional maps for variety.

### In scope

- **Roster audit**: verify all 8 sample characters from §6 of the spec are fully playable with their loadouts end-to-end (deploy, move, attack, use abilities, take damage, get downed).
- **Deployment zone expansion**: existing maps have 5-tile deployment zones, which is insufficient for Standard tier (up to 8 characters) and Large tier (up to 12). Zones must be expanded to accommodate maximum party sizes.
- **Additional maps**: the spec calls for 2--3 maps per tier. Currently there is 1 per tier. Author at least 1 additional map per tier (target: 2 per tier, 6 total).
- **Content validation**: all new and existing content passes structural and referential validation at boot.
- **Balance review**: a first-pass audit of BP values against the heuristic formula from §7.6 of the spec. No rebalancing — just document discrepancies for Phase 9.

### Out of scope

- New character archetypes beyond the 8 in the spec roster (deferred to future content expansions).
- New ability effect types or combat mechanics (those are engine work, not content).
- New terrain types beyond the 8 already defined.
- New races or classes beyond the current 4 races and 8 classes.
- Party building UI or drafting flow (Phase 7).
- BP rebalancing or tuning (Phase 9).
- Visual polish, animations, or presentation improvements (Phase 10).

### Exit criteria

Phase 6 is complete when:

1. All 8 sample characters from §6 are playable with their full loadouts: abilities resolve correctly, items grant expected bonuses, equipment passives apply.
2. Deployment zones on all maps support the **maximum party size** for their tier: Skirmish ≤ 5, Standard ≤ 8, Large ≤ 12 tiles per side.
3. At least **2 maps per tier** exist (6 total minimum), each with correct terrain, elevation, and deployment zones.
4. All content passes structural and referential validation (boot completes with 0 errors).
5. A BP audit document records each character's computed BP against the heuristic and flags discrepancies for Phase 9.
6. GUT tests confirm all 8 characters can be instantiated as `BattleUnit`s with correct derived stats.
7. Git tag `phase-6-complete`.

---

## 2. Design Decisions (Phase 6)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Deployment zone sizing** | Each map's deployment zones must have at least `tier.max` tiles per side (5 for skirmish, 8 for standard, 12 for large). Zones use edge hexes that are spread along the map boundary for tactical variety. | Current 5-tile zones work for skirmish but block standard (8-char) and large (12-char) parties. Expanding zones is a data-only change. |
| **Map variety** | New maps per tier emphasize different tactical challenges: chokepoints, elevation extremes, open fields, asymmetric terrain. Maps within a tier share the same approximate size range but differ in layout. | Variety ensures the game isn't solved by a single party composition; different maps reward different strategies. |
| **Map size ranges** | Skirmish: 30--50 tiles, elevation 0--6. Standard: 50--80 tiles, elevation 0--4. Large: 80--120 tiles, elevation 0--3. These are guidelines, not hard limits. | Smaller maps have more dramatic elevation to create tactical complexity with fewer tiles. Larger maps use gentler terrain to keep movement meaningful at scale. |
| **No new characters** | Phase 6 does not add characters beyond the spec's 8. Roster expansion is future content work. The 8 characters cover all 8 classes and 4 races, which is sufficient for varied matches. | Keeps scope bounded. Phase 9 balancing needs a stable roster. |
| **No new abilities/items** | Existing 14 abilities and 12 items cover all effect types (damage, heal, buff, status) and all delivery mechanisms (spell, skill, item). No gaps in mechanical coverage. | Adding content without gameplay need risks bloat. New abilities should come with new classes or as balance levers in Phase 9+. |
| **BP audit only** | Phase 6 documents BP discrepancies but does not change values. Actual rebalancing is Phase 9's job, after the full match loop (Phase 8) provides real playtest data. | Premature rebalancing without victory conditions and full match flow would be speculative. |
| **Terrain reuse** | New maps use the same 8 terrain types already defined. No new terrain types are needed for variety — combining existing terrains with different elevation profiles provides sufficient differentiation. | Avoids engine changes. The 8 terrains cover the spec's §3.2 requirements. |

---

## 3. Content Audit — Current State

### 3.1 Characters (8/8 from spec §6)

| Character | Race | Class(es) | BP | Status |
|-----------|------|-----------|-----|--------|
| Human Fighter | human | fighter | 18 | Playable |
| Human Archer | human | archer | 13 | Playable |
| Human Rogue | human | rogue | 16 | Playable |
| Human Bard | human | bard | 17 | Playable |
| Dwarf Barbarian | dwarf | barbarian | 20 | Playable |
| Elf Black Mage | elf | black_mage | 30 | Playable |
| Elf Red Mage | elf | red_mage | 26 | Playable |
| Halfling White Mage | halfling | white_mage | 24 | Playable |

All characters from §6 of the spec are authored with correct race, class, stats, equipment, and ability access. The data pipeline resolves final stats (base + race modifiers + class modifiers) and validates all references.

### 3.2 Abilities (14)

| Ability | Type | Effect | AP | Range | Area | Source class/item |
|---------|------|--------|----|-------|------|-------------------|
| fire_1 | spell | damage 4 (fire) | 1 | 3 | — | black_mage, red_mage |
| fire_2 | spell | damage 7 (fire) | 2 | 4 | burst r:1 | black_mage |
| ice_1 | spell | damage 4 (ice) | 1 | 3 | — | black_mage |
| thunder_1 | spell | damage 5 (lightning) | 1 | 3 | — | black_mage |
| cure_1 | spell | heal 4 | 1 | 3 | — | white_mage, red_mage |
| cure_2 | spell | heal 8 | 2 | 4 | — | white_mage |
| shield_1 | spell | buff def +2 (3 rds) | 1 | 3 | — | white_mage |
| power_strike | skill | damage 4 | 1 | 1 | — | fighter |
| reckless_swing | skill | damage 6 | 1 | 1 | — | barbarian |
| rage | skill | buff atk +3 (3 rds) | 1 | 0 | — | barbarian (self) |
| backstab | skill | damage 5 | 1 | 1 | — | rogue |
| inspire | skill | buff atk +2 (3 rds) | 1 | 3 | burst r:1 | bard |
| lullaby | skill | status sleep (2 rds) | 1 | 3 | — | bard |
| smoke_bomb | item | status blind (2 rds) | 1 | 2 | burst r:1 | smoke_bomb_pouch |

Coverage: damage (spell, skill), heal, buff, status (sleep, blind), AoE burst, self-target, item-granted. All effect types from §9.3.1 are exercised.

### 3.3 Items (12)

7 weapons, 3 armor/shield, 2 accessories. All equipment referenced by characters exists and is valid.

### 3.4 Maps (3 — gap identified)

| Map | Tier | Tiles | Elev range | Deploy tiles/side | Tier max party | Gap |
|-----|------|-------|------------|-------------------|----------------|-----|
| mountain_pass | skirmish | 33 | 0--6 | 5 | 5 | None |
| forest_clearing | standard | 59 | 0--3 | 5 | 8 | **Need 8 deploy tiles** |
| river_crossing | large | 95 | 0--2 | 5 | 12 | **Need 12 deploy tiles** |

**Deployment zone gaps**: forest_clearing and river_crossing cannot host full-size parties for their tier. This is the primary content fix required.

**Map count gap**: 1 map per tier exists; spec calls for 2--3 per tier. At least 3 additional maps are needed.

### 3.5 Classes, Races, Terrain

All complete. 8 classes, 4 races, 8 terrain types — matching the spec.

---

## 4. Deployment Zone Requirements

### 4.1 Sizing rules

Each deployment zone must have **at least** as many tiles as the tier's maximum party size:

| Tier | Max party | Required deploy tiles per side |
|------|-----------|-------------------------------|
| Skirmish | 5 | ≥ 5 |
| Standard | 8 | ≥ 8 |
| Large | 12 | ≥ 12 |

### 4.2 Placement guidelines

- Deployment tiles should be along the **map edge**, forming a contiguous or near-contiguous row/cluster.
- The two deployment zones should be on **opposite sides** of the map.
- Zones should span enough width that players have meaningful placement choices (not a single-file line for large parties).
- Deployment tiles must be **traversable** (not rocks, deep water, or cliff terrain). Grass, road, and shallow_water are preferred.

### 4.3 Existing map fixes

- **forest_clearing** (standard): expand both zones from 5 to 8 tiles by adding 3 adjacent edge tiles per side.
- **river_crossing** (large): expand both zones from 5 to 12 tiles by adding 7 adjacent edge tiles per side.
- **mountain_pass** (skirmish): no change needed (5 tiles = tier max).

---

## 5. New Map Requirements

### 5.1 Target: 2 maps per tier (6 total)

| Tier | Existing | New | Total |
|------|----------|-----|-------|
| Skirmish | mountain_pass | +1 | 2 |
| Standard | forest_clearing | +1 | 2 |
| Large | river_crossing | +1 | 2 |

### 5.2 New map design briefs

Each new map should offer a **distinct tactical challenge** compared to its tier-mate:

#### Skirmish — "Ruined Watchtower" (`ruined_watchtower`)
- **Theme**: a crumbled stone tower on a hilltop with surrounding rubble. Elevation is the star.
- **Size**: ~35--45 tiles.
- **Elevation**: 0--5, with a high central plateau (the tower ruin) and lower approaches.
- **Terrain**: road, rocks (rubble), grass, brush. No water.
- **Tactical hook**: control the high ground for elevation bonus; limited approaches force chokepoint decisions.
- **Deploy zones**: 5+ tiles per side on opposite low-ground edges.

#### Standard — "Sunken Courtyard" (`sunken_courtyard`)
- **Theme**: a partially flooded courtyard of an ancient ruin. Water divides the map; bridges/shallows create crossing points.
- **Size**: ~55--75 tiles.
- **Elevation**: 0--3, with raised stone walkways and a sunken center.
- **Terrain**: road (walkways), shallow_water, deep_water (center channels), grass, brush, rocks (pillars).
- **Tactical hook**: controlling the bridges/shallows determines how quickly melee units engage. Ranged units can fire across water but can't easily cross.
- **Deploy zones**: 8+ tiles per side.

#### Large — "Open Plains" (`open_plains`)
- **Theme**: rolling grasslands with scattered brush and a road running through. Minimal elevation, emphasis on positioning and range.
- **Size**: ~90--110 tiles.
- **Elevation**: 0--2, gentle rolling hills.
- **Terrain**: grass (dominant), brush, road, shallow_water (a stream).
- **Tactical hook**: wide-open sightlines favor ranged units and AoE. Little cover forces aggressive positioning. The stream creates a soft division without blocking movement.
- **Deploy zones**: 12+ tiles per side.

### 5.3 Map authoring constraints

All new maps must:

1. Use only existing terrain types (grass, road, brush, trees, rocks, shallow_water, deep_water, cliff).
2. Use axial hex coordinates (q, r) with flat-top orientation.
3. Form a **contiguous** tile set (every tile reachable from every other tile via traversable adjacency, ignoring impassable terrain).
4. Include valid deployment zones per §4.
5. Pass structural and referential validation at boot.

---

## 6. BP Audit

### 6.1 Heuristic formula (from spec §7.6)

```
BP ~ w1*HP + w2*ATK + w3*DEF + w4*SPD + w5*(RNG value)
   + sum(ability_value) + sum(equipment_value)
```

### 6.2 Audit approach

For each character, compute an **estimated BP** using the heuristic with reasonable weights, then compare to the authored BP. Flag any character where the discrepancy exceeds 15% as a Phase 9 review candidate.

This audit is **documentation only** — no BP values are changed in Phase 6. The audit output is recorded in the implementation plan's verification section.

### 6.3 Initial weight estimates

| Weight | Value | Rationale |
|--------|-------|-----------|
| w1 (HP) | 0.5 | Survivability is important but not dominant. |
| w2 (ATK) | 2.0 | Direct damage output. |
| w3 (DEF) | 1.5 | Damage reduction scales with match length. |
| w4 (SPD) | 1.5 | Movement is positioning advantage. |
| w5 (RNG) | 1.0 | Range provides safety but is offset by damage. |
| ability_value | per ability | Estimated from effect magnitude and versatility. |
| equipment_value | from item BP | Sum of `ItemData.bp_value`. |

These weights are starting points for the audit. They will be refined during Phase 9 playtesting.

---

## 7. Data Flow & Integration

### 7.1 From prior phases

| Source | Data consumed |
|--------|---------------|
| Phase 1 | Data pipeline, validation, entity registries, resource classes |
| Phase 2 | MapBuilder (rendering new maps), terrain visual mapping |
| Phase 3 | HexGraph (spatial queries over new maps), Movement/Range/LoS |
| Phase 4 | Deployment (auto-deploy into expanded zones), MatchState |
| Phase 5 | CombatResolver (validating ability resolution on all characters) |

### 7.2 New data authored

- Expanded deployment zones in `forest_clearing.json` and `river_crossing.json`.
- 3 new map JSON files: `ruined_watchtower.json`, `sunken_courtyard.json`, `open_plains.json`.
- No new characters, abilities, items, classes, races, or terrain types.

### 7.3 Outputs

- 6 validated, playable maps (2 per tier) with correctly sized deployment zones.
- 8 characters confirmed end-to-end playable.
- BP audit document (in implementation plan).
- Content ready for Phase 7 (party building) and Phase 8 (victory conditions / full match loop).

---

## 8. Risks & Notes

- **Hex coordinate authoring**. Manually writing hex tile arrays in JSON is error-prone. Use a systematic approach: define the map boundary shape, then fill tiles row by row. Validate coordinates against `Hex.neighbors()` to ensure contiguity.
- **Deployment zone balance**. Zones should be roughly symmetrical in terms of terrain quality (elevation, cover). An asymmetric map where one side deploys into trees and the other onto open grass would give a systematic advantage. First-activation initiative already provides an edge; deployment terrain should not compound it.
- **Map size vs. performance**. Large maps (100+ tiles) increase the number of 3D nodes. At MVP scale this should not be an issue (Godot handles thousands of simple meshes), but is worth noting if future maps grow beyond ~200 tiles.
- **No new effect types**. All 4 effect types (damage, heal, buff, status) are exercised by existing abilities. Phase 6 does not add new types, so no engine changes are needed.
- **Content validation as gate**. The boot-time validation pipeline (structural + referential) serves as the acceptance gate for all new content. If the game boots with 0 errors, the content is structurally sound.

---

## 9. Phase 6 Deliverables Checklist

- [ ] All 8 characters from §6 confirmed playable with full loadouts (§3.1).
- [ ] Deployment zones expanded: forest_clearing to 8/side, river_crossing to 12/side (§4.3).
- [ ] New map: `ruined_watchtower` (skirmish tier, ~35--45 tiles, elev 0--5) (§5.2).
- [ ] New map: `sunken_courtyard` (standard tier, ~55--75 tiles, elev 0--3) (§5.2).
- [ ] New map: `open_plains` (large tier, ~90--110 tiles, elev 0--2) (§5.2).
- [ ] All 6 maps pass validation, load correctly, and render in the map scene (§5.3).
- [ ] BP audit documented with per-character estimated vs. authored BP (§6).
- [ ] GUT tests for character instantiation and derived stats for all 8 characters.
- [ ] GUT tests for map loading and deployment zone sizing for all 6 maps.
- [ ] Boot-time validation passes with 0 errors across all content.
- [ ] Git tag `phase-6-complete`.
