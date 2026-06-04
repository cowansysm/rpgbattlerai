# Phase 5 — Combat Resolution Specification

**Parent plan:** `rpg-implementation-plan.md` (Phase 5)
**Builds on:** `phase0-spec.md` (hex math), `phase1-spec.md` (data layer, `BattleUnit`, `StatBlock`), `phase2-spec.md` (rendered map), `phase3-spec.md` (movement, range, LoS), `phase4-spec.md` (activation loop, action economy, action records)
**Source spec:** `rpg-specs.md` (§7.5, §9.3.1, §9.7)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-04

---

## 1. Purpose & Scope

Phase 5 makes actions **produce outcomes**. Phase 4 validated actions structurally (range, LoS, AP) and logged "would hit" records. Phase 5 resolves those actions: physical attacks deal damage, spells deal damage or heal, buffs push stat modifiers, status effects alter unit behavior, and units are downed when HP reaches zero. The tunable constants (`ELEV_BONUS`, `COVER_DEF`) are applied, and a combat log provides human-readable output for verification.

Phase 5 is validated by running the same 2v2 demo from Phase 4 and observing correct HP changes, downing, buff/status duration tracking, and AoE resolution in the console log.

### In scope

- **Physical damage resolution**: `max(1, ATK + weapon_power + elevation_bonus - target_DEF)`.
- **Spell/ability damage**: ability `effect.value`, modified by elevation bonus where applicable.
- **Healing**: ability `effect.value` restores HP, clamped to max HP.
- **Buff effects**: push a `StatModifier` onto the target's stat block with a tracked duration; expire at round start after `duration` rounds.
- **Status effects**: `sleep` and `blind` with duration tracking; status-specific behavioral rules (sleep = skip activation, blind = attacks auto-miss).
- **Area-of-effect (AoE)**: abilities with `area.shape == "burst"` affect all units within `area.radius` of the target tile.
- **Elevation bonus**: attacking from higher ground grants `+ELEV_BONUS` to physical damage.
- **Cover defense**: target on a tile with `cover > 0` gains `+COVER_DEF` to effective DEF against ranged attacks.
- **Downing**: unit at HP <= 0 is removed from play; occupancy cleared, excluded from activation queue.
- **Weapon power integration**: physical attacks use `weapon_power` from the attacker's weapon item.
- **Combat log**: structured records enriched with outcome fields (damage dealt, HP remaining, effects applied).

### Out of scope

- Victory conditions, rout detection, match-end logic (Phase 8).
- Accuracy/hit rolls (MVP is auto-hit for melee; cover reduces damage, not hit chance).
- Elemental resistances and weaknesses (deferred; element is recorded but has no mechanical effect yet).
- Reaction/overwatch triggers (deferred).
- Visual feedback, hit/heal animations (Phase 10).
- AI decision-making (later phases).

### Exit criteria

Phase 5 is complete when:

1. Physical attacks resolve damage using the formula `max(1, ATK + weapon_power + elevation_bonus - target_DEF)`, respecting cover.
2. Spell/ability damage effects deal their authored `value`, modified by elevation bonus.
3. Healing abilities restore HP clamped to max HP.
4. Buff abilities push a `StatModifier` with duration; expired buffs are removed at round start.
5. Status effects (`sleep`, `blind`) are tracked with duration; sleep skips activation, blind causes attack failure.
6. AoE abilities (burst) affect all units within the burst radius of the target tile.
7. Units at HP <= 0 are downed: removed from occupancy, skipped in activation, excluded from `living_units()`.
8. Elevation bonus and cover defense are applied correctly per the constants.
9. Action records include outcome fields: `damage`, `healing`, `target_hp_after`, `effects_applied`, `is_downed`.
10. All resolution logic is unit-tested headlessly; the Phase 4 demo shows HP changes and downing in console output.

---

## 2. Design Decisions (Phase 5)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Damage formula** | `max(1, ATK + weapon_power + elev_bonus - target_DEF - cover_bonus)`. Minimum 1 damage guarantees progress. | Matches spec §7.5. Simple, deterministic, tunable via constants. No hit roll in MVP. |
| **Spell damage** | Spell damage uses `effect.value` directly; not reduced by DEF. Elevation bonus applies if attacker is higher. | Spells bypass physical armor (spec §7.5 implies spell values are self-contained). DEF reduces physical attacks only. |
| **Healing** | `min(effect.value, max_hp - current_hp)`. Cannot overheal. | Standard RPG healing behavior. Max HP is `stats.effective("hp")`. |
| **Buff duration** | Buffs last `duration` rounds, decremented at round start. Duration 3 means the buff persists through the current round plus 2 more round starts before expiring. | Consistent with the existing Defend modifier pattern (push/pop by source). Buffs use a `"buff:{ability_id}"` source tag for targeted removal. |
| **Status effects** | Statuses are tracked on a new `status_effects` array on `BattleUnit`. Each entry: `{id, duration, source}`. Decremented at round start; removed when duration reaches 0. | Lightweight extension to BattleUnit. No new class needed — a Dictionary suffices for MVP's two statuses. |
| **Sleep behavior** | A sleeping unit's activation is automatically skipped (Wait with 0 AP). Sleep is removed if the unit takes damage. | Standard RPG sleep: damage wakes the target. Skipping activation is handled in RoundManager or the demo loop. |
| **Blind behavior** | A blinded unit's attacks automatically fail (return error "Unit is blinded"). Does not affect movement or abilities. | Simple MVP behavior. Blind affects basic attacks only, not spells. |
| **AoE resolution** | Burst abilities iterate all units within `area.radius` of the target tile. Each affected unit is resolved independently (damage/heal/buff/status applied per unit). Friendly fire applies — AoE hits allies too. | Faithful to FFT-style AoE. The ability targets a tile, not a unit; all units in the burst are affected. |
| **Cover** | Cover reduces incoming ranged physical damage. Target on a `cover > 0` terrain tile gains `+COVER_DEF` effective DEF against ranged attacks (RNG > 1). Melee attacks ignore cover. | Spec §7.5. Uses the existing `TerrainProps.cover` field and `COVER_DEF` constant. |
| **Elevation bonus** | Attacker elevation > target elevation grants `+ELEV_BONUS` to physical damage. For spells, elevation bonus applies to damage spells only. | Spec §7.5. Read from `HexGraph.elevation()`. Applied additively before DEF subtraction. |
| **Weapon power** | Physical attacks add `weapon_power` from the attacker's equipped weapon. Looked up via `ItemData.weapon_power` for the first `slot == "weapon"` item in `character.equipment`. | Spec §7.5 formula includes weapon_power. Items are loaded via the injectable item provider. |
| **Downing** | When `current_hp <= 0`: set `current_hp = 0`, clear from occupancy, unit is excluded from `living_units()`. Downed units remain in the parties array but are filtered out of all queries. | MVP: no revive, no death animation. The existing `living_units()` filter (`current_hp > 0`) already handles this. |
| **CombatResolver** | A new static class `CombatResolver` centralizes all resolution logic. `TurnActions` calls `CombatResolver` after validation passes. This separates "can I do this?" (TurnActions) from "what happens?" (CombatResolver). | Clean separation. Phase 4 TurnActions validation is unchanged; resolution is injected at the point where Phase 4 logged structural records. |
| **Item provider** | Resolution needs item data (weapon_power) at runtime. An `item_provider: Callable` on MatchState (parallel to `ability_provider`) allows injectable item lookup for testability. | Same pattern as ability_provider. Tests use stubs; the demo wires GameData. |
| **No accuracy roll** | MVP is deterministic: attacks always hit (unless blinded or no LoS). Cover reduces damage, not hit chance. | Simplifies Phase 5. Accuracy rolls are a future tuning knob (spec §7.5 notes "may start auto-hit"). |

---

## 3. Resolution Formulas

### 3.1 Physical attack damage

```
weapon_power = attacker's weapon ItemData.weapon_power (0 if no weapon)
elev_bonus   = ELEV_BONUS if attacker_elevation > target_elevation, else 0
cover_bonus  = COVER_DEF if target tile has cover > 0 AND attack is ranged (RNG > 1), else 0
raw_damage   = ATK + weapon_power + elev_bonus
effective_def = target_DEF + cover_bonus
damage       = max(1, raw_damage - effective_def)
```

Where:
- `ATK` = `attacker.stats.effective("atk")`
- `target_DEF` = `target.stats.effective("def")` (includes buffs, defend modifier, equipment passives)
- `ELEV_BONUS` and `COVER_DEF` are tunable constants from `constants.json`

### 3.2 Spell/ability damage

```
elev_bonus = ELEV_BONUS if attacker_elevation > target_elevation, else 0
damage     = effect.value + elev_bonus
```

Spell damage is **not** reduced by DEF. The `effect.value` is the authored damage on the ability. Elevation bonus applies to damage spells.

### 3.3 Healing

```
healing = min(effect.value, max_hp - current_hp)
```

Where `max_hp = target.stats.effective("hp")`. Healing cannot exceed max HP. Healing can target allies (and self for self-targeted abilities like range-0 heals).

### 3.4 Buff application

Push a `StatModifier(effect.stat, effect.value, "buff:{ability_id}")` onto the target's stat block. Track the buff in a duration registry (see §5) with `effect.duration` rounds remaining.

### 3.5 Status application

Add an entry `{id: effect.status_id, duration: effect.duration, source: ability_id}` to the target's `status_effects` array. If the target already has the same status, refresh the duration to the new value.

---

## 4. Effect Type Resolution

Each ability's `effect.effect_type` selects a resolution path:

| `effect_type` | Resolution | Action record fields added |
|---------------|------------|---------------------------|
| `"damage"` | Compute damage (§3.1 for skills, §3.2 for spells). Subtract from `target.current_hp`. Check downing. | `damage: int`, `target_hp_after: int`, `is_downed: bool`, `element: String` |
| `"heal"` | Compute healing (§3.3). Add to `target.current_hp`. | `healing: int`, `target_hp_after: int` |
| `"buff"` | Push stat modifier (§3.4). Register duration. | `buff_stat: String`, `buff_value: int`, `buff_duration: int` |
| `"status"` | Apply status (§3.5). Register duration. | `status_id: String`, `status_duration: int` |

For **physical attacks** (basic weapon attack, not ability), resolution uses the §3.1 formula with the attacker's weapon stats. No `effect_type` dispatch — it's a direct damage calculation.

For **ability-based damage** (skills and spells), the distinction between physical and magical is determined by `ability.type`:
- `type == "skill"`: damage is `max(1, effect.value + elev_bonus - target_DEF)` (physical, reduced by DEF).
- `type == "spell"`: damage is `effect.value + elev_bonus` (magical, ignores DEF).

---

## 5. Duration Tracking

### 5.1 Buff durations

Buffs are tracked alongside the `StatModifier` they push. A parallel data structure on `MatchState` (or `BattleUnit`) maps `source_tag -> {rounds_remaining, unit}`. At each round start, decrement all buff durations. When a buff reaches 0, call `unit.stats.remove_modifiers_by_source(source_tag)`.

The source tag format is `"buff:{ability_id}"` (e.g., `"buff:shield_1"`, `"buff:rage"`). This ensures targeted removal without affecting Defend modifiers (source `"defend"`) or equipment passives.

### 5.2 Status durations

Status effects are tracked per-unit in `BattleUnit.status_effects: Array[Dictionary]`. Each entry: `{id: String, duration: int, source: String}`. At round start:

1. Decrement `duration` for all active statuses on all living units.
2. Remove entries where `duration <= 0`.
3. Sleep is additionally removed when the unit takes damage (immediate removal, mid-resolution).

### 5.3 Round-start cleanup order

At each `RoundManager.start_round()`:

1. **Remove Defend modifiers** (existing behavior from Phase 4).
2. **Decrement and expire buff durations** — remove expired StatModifiers.
3. **Decrement and expire status durations** — remove expired statuses.
4. **Reset units** (is_activated, ap_remaining) — existing behavior.
5. **Build activation queue** — skipping downed units (already filtered by `living_units()`).

---

## 6. Area-of-Effect Resolution

### 6.1 Burst abilities

Abilities with `area: {"shape": "burst", "radius": N}` target a tile and affect all units within `N` hexes of that tile (inclusive of the tile itself).

Resolution steps:

1. Determine affected tiles: all tiles within `Hex.distance(target_tile, tile) <= area.radius`.
2. Collect all units on affected tiles (from `state.occupancy`).
3. Resolve the ability's effect against each affected unit independently.
4. Friendly fire: AoE damage/status affects all units, not just enemies. Healing/buff AoE affects all units including enemies (player must aim carefully).

### 6.2 Single-target abilities

Abilities without an `area` field (or `area == {}`) target a single unit on the target tile. If the effect is `"heal"` or `"buff"`, the target may be an ally or self. If the effect is `"damage"`, the target must be an enemy (enforced at validation in TurnActions).

### 6.3 Self-targeted abilities

Abilities with `range == 0` target the caster. The `target_pos` must equal the caster's position. This covers abilities like Rage (self-buff).

---

## 7. Weapon Power Lookup

Physical attacks require the attacker's weapon power. Resolution flow:

1. Iterate `unit.character.equipment` array.
2. For each equipment ID, look up the `ItemData` via the injected `item_provider`.
3. The first item with `slot == "weapon"` provides `weapon_power`.
4. If no weapon is found, `weapon_power = 0` (unarmed/caster).

This lookup happens once per physical attack resolution. An `item_provider: Callable` on `MatchState` (similar to `ability_provider`) provides injectable item access for testability.

---

## 8. Downing & Removal

### 8.1 Downing trigger

When `unit.current_hp` is set to 0 or below during resolution:

1. Set `current_hp = 0`.
2. Remove unit from `state.occupancy` (clear the tile).
3. The unit remains in `state.parties` but is filtered out by `living_units()` (already implemented).
4. If the unit is the current active unit (downed by an AoE reaction — unlikely in MVP but possible), end its activation.

### 8.2 Activation queue impact

Downed units are never placed in the activation queue (the queue is built from `unactivated_units()` which calls `living_units()`). If a unit is downed mid-round, it simply isn't available for future activations that round.

### 8.3 Sleep + downing interaction

If a sleeping unit takes damage, sleep is removed **before** checking if the unit is downed. This is a cosmetic distinction in MVP (the unit wakes up and then might die), but it ensures correct status tracking.

---

## 9. Integration with Phase 4

### 9.1 TurnActions modifications

Phase 4's `TurnActions` methods are extended, not replaced:

- **`execute_attack`**: After existing validation, call `CombatResolver.resolve_attack()`. Enrich the action record with `damage`, `target_hp_after`, `is_downed`.
- **`execute_ability`**: After existing validation, call `CombatResolver.resolve_ability()`. Enrich the record with effect-specific outcome fields.
- **`execute_use_item`**: After existing validation, call `CombatResolver.resolve_ability()` using the item's granted ability.
- **`execute_defend`**: Unchanged (already pushes +DEF modifier).
- **`execute_move`**: Unchanged.
- **`execute_wait`**: Unchanged.

### 9.2 Status checks in activation

Before a unit activates (in `RoundManager.activate_unit` or the demo loop):

- If the unit has `sleep` status: skip activation (auto-Wait), decrement sleep duration.
- If the unit has `blind` status: attacks fail with "Unit is blinded" error. Movement and abilities still work.

### 9.3 MatchState additions

- `item_provider: Callable` — `(String) -> ItemData`, for weapon power lookup.
- `buff_durations: Dictionary` — `source_tag -> {unit: BattleUnit, remaining: int}`, tracked globally for round-start cleanup.

### 9.4 BattleUnit additions

- `status_effects: Array[Dictionary]` — `[{id: String, duration: int, source: String}, ...]`, per-unit status tracking.
- `max_hp: int` — stored at creation time for heal clamping (or computed from `stats.effective("hp")`).

---

## 10. Data Flow & Integration

### 10.1 From prior phases

| Source | Data consumed |
|--------|---------------|
| Phase 0 | `Hex.distance()`, `Hex.hexes_in_range()` |
| Phase 1 | `CharacterData.equipment`, `AbilityData.effect`, `ItemData.weapon_power`, `StatBlock`, `StatModifier`, `BattleUnit.current_hp` |
| Phase 3 | `HexGraph.elevation()`, `HexGraph.terrain_props()`, `TerrainProps.cover`, `LineOfSight.has_los()`, `RangeQuery.effective_range()` |
| Phase 4 | `MatchState`, `TurnActions.*`, `RoundManager.start_round()`, action records, `ability_provider`, `AbilityResolver` |

### 10.2 Constants consumed

| Constant | Value | Used by |
|----------|-------|---------|
| `ELEV_BONUS` | 1 | Physical and spell damage elevation bonus |
| `COVER_DEF` | 1 | Ranged physical damage cover reduction |

### 10.3 Outputs

- Enriched action records with outcome data (damage, healing, effects, downing).
- Mutated `BattleUnit` state: `current_hp`, `status_effects`, stat modifiers from buffs.
- Console combat log showing resolution results.

---

## 11. Risks & Notes

- **No accuracy roll.** MVP is deterministic auto-hit. Cover reduces damage, not hit chance. This is intentionally simple; accuracy rolls are a future tuning lever (spec §7.5 note).
- **Elemental damage recorded but not consumed.** The `element` field is preserved in action records for future elemental resistance/weakness systems. Phase 5 does not grant bonuses or penalties based on element.
- **Friendly fire AoE.** Burst abilities affect all units in the area, including allies. This matches FFT behavior and adds tactical depth. Players must position carefully.
- **No revive.** Once downed, a unit is permanently removed for the match. The Phoenix Charm revive item is deferred (requires a revive effect_type and more complex resolution).
- **Sleep auto-skip.** A sleeping unit automatically waits on its activation turn. This is handled at the activation level (RoundManager or demo loop), not inside TurnActions. The choice to handle it outside TurnActions keeps the action system clean — TurnActions doesn't need to know about statuses beyond blind's attack block.
- **Buff stacking.** Multiple applications of the same buff from the same ability stack as separate modifiers (each with its own duration). A unit hit by Inspire twice gets +4 ATK from two separate modifiers. This is the simplest behavior; diminishing returns or "no stack" rules are deferred.
- **Status refresh.** Applying the same status to a unit that already has it refreshes the duration to the new value rather than adding a second entry. This prevents status duration accumulation from repeated application.
- **Constants injection.** `CombatResolver` reads `ELEV_BONUS` and `COVER_DEF` from the `Constants` autoload at runtime. For testability, the resolver accepts optional override parameters so tests can pass explicit values without autoload.
- **Spell DEF bypass.** Spells ignoring DEF is a deliberate design choice making mages strong against heavily armored targets. Physical skills (type "skill") are reduced by DEF, differentiating physical and magical damage.

---

## 12. Phase 5 Deliverables Checklist

- [ ] `CombatResolver` class with `resolve_attack()`, `resolve_ability()`, and helper methods for each effect type (§3, §4).
- [ ] Physical damage formula: `max(1, ATK + weapon_power + elev_bonus - target_DEF - cover_bonus)` (§3.1).
- [ ] Spell/ability damage: `effect.value + elev_bonus`, not reduced by DEF (§3.2).
- [ ] Healing: `min(effect.value, max_hp - current_hp)` (§3.3).
- [ ] Buff application: push StatModifier with duration tracking, expire at round start (§3.4, §5.1).
- [ ] Status effects: sleep (skip activation, wake on damage) and blind (attacks fail) with duration (§3.5, §5.2).
- [ ] AoE burst resolution: all units within radius affected independently (§6).
- [ ] Elevation bonus (`ELEV_BONUS`) applied to physical and spell damage (§3.1, §3.2).
- [ ] Cover defense (`COVER_DEF`) applied to ranged physical attacks (§3.1).
- [ ] Weapon power lookup via `item_provider` (§7).
- [ ] Downing: HP <= 0 clears occupancy, excludes from activation (§8).
- [ ] `TurnActions` enriched: attack/ability/item records include damage, HP, downed, effects (§9.1).
- [ ] `BattleUnit.status_effects` array for per-unit status tracking (§9.4).
- [ ] `MatchState.item_provider` and `MatchState.buff_durations` additions (§9.3).
- [ ] Round-start cleanup: Defend removal → buff expiry → status expiry → unit reset (§5.3).
- [ ] GUT tests for all resolution paths, elevation, cover, AoE, buff/status duration, downing (headless).
- [ ] Phase 4 demo updated to show HP changes and downing in console log.
- [ ] Git tag `phase-5-complete`.
