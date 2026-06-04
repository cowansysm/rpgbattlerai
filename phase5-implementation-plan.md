# Phase 5 — Implementation Plan

**Source spec:** `phase5-spec.md`
**Builds on:** `phase0` (hex math), `phase1` (data layer, `BattleUnit`, `StatBlock`, `StatModifier`), `phase2` (rendered map), `phase3` (movement, range, LoS, elevation), `phase4` (activation loop, action economy, `TurnActions`, `RoundManager`)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-06-04

---

## How to use this plan

Six **work groups** (A–F). Within a group, tasks can be done in any order unless noted. Across groups: **A** (CombatResolver core) is the foundation; **B** (duration tracking, status effects) needs A; **C** (TurnActions integration) needs A + B; **D** (round-start cleanup) needs B; **E** (demo update) ties it together; **F** (tests) trails the logic.

Each task lists a **done state**. Code stubs are Godot 4 / GDScript — drop-in starting points. All resolution logic is unit-testable without a running scene. Phase 5 extends Phase 4's action system: validation is unchanged, resolution is added after validation passes.

> **Carry-over:** consumes `MatchState`, `TurnActions`, `RoundManager`, `AbilityResolver` from Phase 4; `HexGraph.elevation()`, `HexGraph.terrain_props()`, `TerrainProps.cover` from Phase 3; `BattleUnit`, `StatBlock`, `StatModifier`, `AbilityData`, `ItemData`, `CharacterData` from Phase 1; `Constants` autoload; `Hex.distance()`, `Hex.hexes_in_range()` from Phase 0.

---

## Group A — Combat Resolver Core

*Foundation for all resolution. No dependencies beyond Phase 1 data types and Phase 3 spatial queries.*

### A1. `CombatResolver` — centralized resolution logic

- Static class with methods for each resolution path.
- Accepts explicit `elev_bonus` and `cover_def` parameters (defaulting to Constants values) for testability.
- Each method returns a result Dictionary with outcome fields.
- **Done:** can resolve physical attack damage, spell damage, healing, buff application, and status application.

```gdscript
# src/core/combat/combat_resolver.gd
class_name CombatResolver
extends RefCounted

## Resolve a physical (basic weapon) attack.
## Returns {damage: int, target_hp_after: int, is_downed: bool}
static func resolve_attack(
    attacker: BattleUnit,
    target: BattleUnit,
    weapon_power: int,
    attacker_elev: int,
    target_elev: int,
    target_cover: int,
    is_ranged: bool,
    elev_bonus: int = -1,
    cover_def: int = -1,
) -> Dictionary:
    if elev_bonus < 0:
        elev_bonus = Constants.get_value("ELEV_BONUS", 1)
    if cover_def < 0:
        cover_def = Constants.get_value("COVER_DEF", 1)

    var atk: int = attacker.stats.effective("atk")
    var e_bonus: int = elev_bonus if attacker_elev > target_elev else 0
    var c_bonus: int = cover_def * target_cover if is_ranged else 0
    var target_def: int = target.stats.effective("def")
    var damage: int = max(1, atk + weapon_power + e_bonus - target_def - c_bonus)

    target.current_hp = max(0, target.current_hp - damage)
    var is_downed: bool = target.current_hp <= 0

    return {
        "damage": damage,
        "target_hp_after": target.current_hp,
        "is_downed": is_downed,
    }


## Resolve a damage ability effect (spell or skill).
## type == "skill": reduced by DEF (physical). type == "spell": ignores DEF.
static func resolve_damage(
    attacker: BattleUnit,
    target: BattleUnit,
    effect_value: int,
    ability_type: String,
    attacker_elev: int,
    target_elev: int,
    elev_bonus: int = -1,
) -> Dictionary:
    if elev_bonus < 0:
        elev_bonus = Constants.get_value("ELEV_BONUS", 1)

    var e_bonus: int = elev_bonus if attacker_elev > target_elev else 0
    var damage: int

    if ability_type == "skill":
        # Physical skill: reduced by DEF
        var target_def: int = target.stats.effective("def")
        damage = max(1, effect_value + e_bonus - target_def)
    else:
        # Spell: ignores DEF
        damage = effect_value + e_bonus

    target.current_hp = max(0, target.current_hp - damage)
    var is_downed: bool = target.current_hp <= 0

    return {
        "damage": damage,
        "target_hp_after": target.current_hp,
        "is_downed": is_downed,
    }


## Resolve a healing effect.
static func resolve_heal(
    target: BattleUnit,
    effect_value: int,
) -> Dictionary:
    var max_hp: int = target.stats.effective("hp")
    var healing: int = min(effect_value, max_hp - target.current_hp)
    target.current_hp = min(target.current_hp + healing, max_hp)

    return {
        "healing": healing,
        "target_hp_after": target.current_hp,
    }


## Resolve a buff effect. Pushes a StatModifier with a tracked source tag.
## Returns the source tag for duration registration.
static func resolve_buff(
    target: BattleUnit,
    stat: String,
    value: int,
    ability_id: String,
) -> Dictionary:
    var source_tag: String = "buff:%s" % ability_id
    target.stats.push_modifier(StatModifier.new(stat, value, source_tag))

    return {
        "buff_stat": stat,
        "buff_value": value,
        "source_tag": source_tag,
    }


## Resolve a status effect. Adds or refreshes on the target.
static func resolve_status(
    target: BattleUnit,
    status_id: String,
    duration: int,
    source: String,
) -> Dictionary:
    # Refresh if already present
    for s in target.status_effects:
        if s["id"] == status_id:
            s["duration"] = duration
            s["source"] = source
            return {
                "status_id": status_id,
                "status_duration": duration,
                "refreshed": true,
            }

    # Add new status
    target.status_effects.append({
        "id": status_id,
        "duration": duration,
        "source": source,
    })

    return {
        "status_id": status_id,
        "status_duration": duration,
        "refreshed": false,
    }
```

### A2. Weapon power lookup helper

- Static function to find the weapon_power for a unit.
- Uses the `item_provider` callable from MatchState.
- **Done:** returns weapon_power from the unit's first weapon slot item, or 0 if none.

```gdscript
## Look up weapon power for a unit via item_provider.
## Returns 0 if no weapon equipped or provider unavailable.
static func get_weapon_power(unit: BattleUnit, item_provider: Callable) -> int:
    if not item_provider.is_valid():
        return 0
    for eq_id in unit.character.equipment:
        var item: ItemData = item_provider.call(eq_id)
        if item and item.slot == "weapon":
            return item.weapon_power
    return 0
```

> This can live as a static method on `CombatResolver` or as a standalone helper.

---

## Group B — Duration Tracking & Status Effects

*Depends on A. Extends BattleUnit and MatchState for buff/status duration management.*

### B1. `BattleUnit` extension — status_effects field

- Add `status_effects: Array` to `BattleUnit` (Array of Dictionaries: `{id, duration, source}`).
- Initialize as empty in `from_character()`.
- Add helper methods: `has_status(id) -> bool`, `remove_status(id)`.
- **Done:** BattleUnit can store and query active status effects.

```gdscript
# Additions to src/core/data/battle_unit.gd
var status_effects: Array = []    # [{id: String, duration: int, source: String}, ...]

func has_status(status_id: String) -> bool:
    for s in status_effects:
        if s["id"] == status_id:
            return true
    return false

func remove_status(status_id: String) -> void:
    status_effects = status_effects.filter(
        func(s: Dictionary) -> bool: return s["id"] != status_id)
```

### B2. `MatchState` extension — item_provider and buff_durations

- Add `item_provider: Callable` (parallel to existing `ability_provider`).
- Add `buff_durations: Array` — each entry: `{source_tag: String, unit: BattleUnit, remaining: int}`.
- **Done:** MatchState can track buff lifetimes for round-start cleanup.

```gdscript
# Additions to src/core/combat/match_state.gd
var item_provider: Callable = Callable()    # (String) -> ItemData or null
var buff_durations: Array = []              # [{source_tag, unit, remaining}, ...]
```

### B3. Buff duration registration

- After `CombatResolver.resolve_buff()`, register the buff in `state.buff_durations`.
- **Done:** buffs have tracked durations tied to their source tag and target unit.

---

## Group C — TurnActions Integration

*Depends on A + B. Extends TurnActions to call CombatResolver after validation.*

### C1. `execute_attack` — add damage resolution

- After existing validation passes (range, LoS, AP, target validity), look up weapon power and resolve.
- Check for blind status: if attacker has "blind", return error.
- Enrich action record with outcome fields.
- Handle downing: if target is downed, clear from occupancy.
- **Done:** attack actions produce HP changes and downing.

```gdscript
# Modified execute_attack in turn_actions.gd (after validation block)

    # Check blind status
    if unit.has_status("blind"):
        unit.ap_remaining -= 1
        var record := {
            "action": "attack",
            "actor": unit.character.id,
            "target": target.character.id,
            "target_pos": target_pos,
            "missed": true,
            "reason": "blind",
        }
        state.turn_log.append(record)
        return record

    var weapon_power: int = CombatResolver.get_weapon_power(unit, state.item_provider)
    var attacker_elev: int = state.graph.elevation(unit.position)
    var target_elev: int = state.graph.elevation(target_pos)
    var target_cover: int = state.graph.terrain_props(target_pos).cover
    var is_ranged: bool = unit.stats.effective("rng") > 1
    unit.ap_remaining -= 1

    var result := CombatResolver.resolve_attack(
        unit, target, weapon_power,
        attacker_elev, target_elev, target_cover, is_ranged)

    var record := {
        "action": "attack",
        "actor": unit.character.id,
        "target": target.character.id,
        "target_pos": target_pos,
        "damage": result["damage"],
        "target_hp_after": result["target_hp_after"],
        "is_downed": result["is_downed"],
    }

    if result["is_downed"]:
        _handle_downing(state, target, target_pos)

    state.turn_log.append(record)
    return record
```

### C2. `execute_ability` — add effect resolution

- After existing validation, dispatch based on `ability.effect.effect_type`.
- For AoE abilities (burst), collect all units in radius and resolve per-unit.
- For single-target abilities, resolve against the target unit.
- Self-targeted abilities (range 0) resolve against the caster.
- Remove sleep on damage to sleeping target.
- Enrich action record with per-target outcome fields.
- **Done:** ability actions produce damage, healing, buff, or status effects.

```gdscript
# Modified execute_ability — after validation, before return:

    var effect: Dictionary = ability.effect
    var effect_type: String = str(effect.get("effect_type", ""))

    # Collect affected units (AoE or single target)
    var affected: Array = _collect_affected_units(state, target_pos, ability.area)

    var outcomes: Array = []
    for affected_unit: BattleUnit in affected:
        var outcome := _resolve_effect(
            state, unit, affected_unit, effect, effect_type, ability)
        outcomes.append(outcome)

    # Build record with outcomes
    var record := {
        "action": "ability",
        "actor": unit.character.id,
        "ability": ability_id,
        "target_pos": target_pos,
        "ap_spent": ability.ap_cost,
        "outcomes": outcomes,
    }
    state.turn_log.append(record)
    return record
```

### C3. `execute_use_item` — delegate to ability resolution

- After existing validation, look up the item's granted ability.
- Resolve using the same effect dispatch as `execute_ability`.
- **Done:** item actions resolve their granted ability effect.

### C4. Downing helper

- Static helper `_handle_downing(state, unit, pos)` clears occupancy and logs.
- **Done:** downed units are cleanly removed from the map.

```gdscript
static func _handle_downing(state: MatchState, unit: BattleUnit, pos: Vector2i) -> void:
    state.occupancy.erase(pos)
```

### C5. AoE target collection helper

- Static helper `_collect_affected_units(state, target_pos, area)` returns all units in the burst radius.
- If area is empty or missing, returns the single unit at target_pos.
- **Done:** AoE abilities correctly enumerate affected targets.

```gdscript
static func _collect_affected_units(
    state: MatchState, target_pos: Vector2i, area: Dictionary
) -> Array:
    if area.is_empty() or not area.has("shape"):
        # Single target
        var u := state.unit_at(target_pos)
        return [u] if u else []

    if str(area.get("shape", "")) == "burst":
        var radius: int = int(area.get("radius", 0))
        var units: Array = []
        for hex in Hex.hexes_in_range(target_pos, radius):
            var u := state.unit_at(hex)
            if u:
                units.append(u)
        return units

    # Unknown shape — fall back to single target
    var u := state.unit_at(target_pos)
    return [u] if u else []
```

---

## Group D — Round-Start Cleanup

*Depends on B. Extends RoundManager.start_round() with buff/status expiry.*

### D1. Buff duration expiry

- At round start, iterate `state.buff_durations`.
- Decrement `remaining` for each entry.
- When `remaining <= 0`, call `unit.stats.remove_modifiers_by_source(source_tag)` and remove the entry.
- **Done:** buffs expire after their authored duration in rounds.

```gdscript
# Addition to RoundManager.start_round(), after defend removal:

    # Expire buffs
    var expired_buffs: Array = []
    for entry in state.buff_durations:
        entry["remaining"] -= 1
        if entry["remaining"] <= 0:
            var u: BattleUnit = entry["unit"]
            u.stats.remove_modifiers_by_source(str(entry["source_tag"]))
            expired_buffs.append(entry)
    for e in expired_buffs:
        state.buff_durations.erase(e)
```

### D2. Status duration expiry

- At round start, iterate all living units.
- Decrement `duration` for each status in `unit.status_effects`.
- Remove entries where `duration <= 0`.
- **Done:** statuses expire after their authored duration in rounds.

```gdscript
# Addition to RoundManager.start_round(), after buff expiry:

    # Expire statuses
    for team in state.parties.keys():
        for u: BattleUnit in state.living_units(team):
            for s in u.status_effects:
                s["duration"] -= 1
            u.status_effects = u.status_effects.filter(
                func(s: Dictionary) -> bool: return s["duration"] > 0)
```

### D3. Sleep activation skip

- When a unit is about to activate, check for sleep status.
- If sleeping: auto-Wait (set AP to 0), decrement sleep duration or remove if expired, advance the activation queue.
- This is handled at the activation level — either in `RoundManager.activate_unit()` (returns a special error/flag) or in the demo loop that calls `activate_unit`.
- **Done:** sleeping units skip their turn.

---

## Group E — Demo Update

*Ties A–D together. Updates Phase4Demo to show resolution results.*

### E1. Wire item_provider on MatchState

- In `Phase4Demo.setup()`, set `_state.item_provider = GameData.get_item`.
- **Done:** CombatResolver can look up weapon power via the injected provider.

### E2. Update demo log output

- Update `_do_attack()` to print damage, target HP, and downing status.
- Update console output for ability effects.
- Show status effects and buffs in unit status log.
- **Done:** demo console output shows full resolution results.

```gdscript
# Updated _do_attack() log:
Log.info("Phase4Demo", "Attack: %s -> %s | damage=%d HP=%d%s — AP=%d" % [
    str(result["actor"]), str(result["target"]),
    int(result.get("damage", 0)),
    int(result.get("target_hp_after", 0)),
    " DOWNED!" if result.get("is_downed", false) else "",
    _state.current_unit.ap_remaining])
```

### E3. Handle sleep skip in demo loop

- In `_activate_next()`, after activating a unit, check for sleep. If sleeping, auto-wait and advance.
- **Done:** sleeping units are visibly skipped in the demo.

---

## Group F — Verification

*Logic is unit-tested; the demo is checklist-verified.*

### F1. Physical attack resolution tests (GUT)

- Damage = `max(1, ATK + weapon_power + elev_bonus - DEF)`. Various stat combinations.
- Minimum damage is 1.
- Elevation bonus applied when attacker is higher.
- Cover reduces ranged damage, not melee.
- Target HP reduced correctly; downing at HP <= 0.
- **Done:** green, headless.

```gdscript
# tests/core/combat/test_combat_resolver.gd
extends GutTest

func test_physical_damage_basic() -> void:
    var attacker := _make_unit("a", 3, 10, 2)  # ATK=2
    var target := _make_unit("b", 3, 10, 1)    # DEF=1
    var result := CombatResolver.resolve_attack(
        attacker, target, 3,  # weapon_power=3
        0, 0, 0, false, 1, 1)  # flat ground, melee
    # damage = max(1, 2 + 3 + 0 - 1 - 0) = 4
    assert_eq(result["damage"], 4)
    assert_eq(target.current_hp, 6)

func test_minimum_damage_is_one() -> void:
    var attacker := _make_unit("a", 3, 10, 1)  # ATK=1
    var target := _make_unit("b", 3, 10, 10)   # DEF=10
    var result := CombatResolver.resolve_attack(
        attacker, target, 0, 0, 0, 0, false, 1, 1)
    assert_eq(result["damage"], 1)

func test_elevation_bonus_applied() -> void:
    var attacker := _make_unit("a", 3, 10, 2)
    var target := _make_unit("b", 3, 10, 1)
    var result := CombatResolver.resolve_attack(
        attacker, target, 3,
        3, 0, 0, false, 1, 1)  # attacker elev 3, target elev 0
    # damage = max(1, 2 + 3 + 1 - 1 - 0) = 5
    assert_eq(result["damage"], 5)

func test_cover_reduces_ranged_damage() -> void:
    var attacker := _make_unit("a", 3, 10, 2)
    var target := _make_unit("b", 3, 10, 1)
    var result := CombatResolver.resolve_attack(
        attacker, target, 3,
        0, 0, 1, true, 1, 1)  # cover=1, ranged
    # damage = max(1, 2 + 3 + 0 - 1 - 1) = 3
    assert_eq(result["damage"], 3)

func test_cover_ignored_for_melee() -> void:
    var attacker := _make_unit("a", 3, 10, 2)
    var target := _make_unit("b", 3, 10, 1)
    var result := CombatResolver.resolve_attack(
        attacker, target, 3,
        0, 0, 1, false, 1, 1)  # cover=1, but melee
    # damage = max(1, 2 + 3 + 0 - 1 - 0) = 4
    assert_eq(result["damage"], 4)

func test_downing_at_zero_hp() -> void:
    var attacker := _make_unit("a", 3, 10, 5)  # ATK=5
    var target := _make_unit("b", 3, 3, 0)     # HP=3, DEF=0
    var result := CombatResolver.resolve_attack(
        attacker, target, 3, 0, 0, 0, false, 1, 1)
    assert_true(result["is_downed"])
    assert_eq(target.current_hp, 0)
```

### F2. Spell and skill damage tests (GUT)

- Spell damage = `effect.value + elev_bonus`, ignores DEF.
- Skill damage = `max(1, effect.value + elev_bonus - target_DEF)`.
- Elevation bonus applied to both when attacker is higher.
- **Done:** green.

### F3. Healing tests (GUT)

- Healing restores HP up to max_hp. Cannot overheal.
- Healing on a full-HP unit results in 0 effective healing.
- **Done:** green.

### F4. Buff tests (GUT)

- Buff pushes StatModifier; effective stat increases.
- Buff expires after N round starts; modifier removed.
- Multiple buffs from different sources stack.
- **Done:** green.

### F5. Status effect tests (GUT)

- Sleep applied: unit has_status("sleep") returns true.
- Sleep skip: sleeping unit auto-waits.
- Sleep wake on damage: damage removes sleep.
- Sleep duration expiry: removed after N rounds.
- Blind: attacks return miss/error. Movement unaffected.
- Status refresh: reapplication resets duration.
- **Done:** green.

### F6. AoE tests (GUT)

- Burst radius 1: all units within 1 hex of target affected.
- Friendly fire: ally units in burst also affected.
- Empty burst: no targets → empty outcomes.
- **Done:** green.

### F7. Integration tests (GUT)

- Full attack → damage → downing → occupancy cleared.
- Ability (spell) → damage → HP change.
- Heal → HP restored, clamped.
- Buff → stat increase → round-start expiry.
- AoE ability → multiple targets affected.
- Sleep → skip activation → wake on damage.
- **Done:** green.

### F8. Manual demo checklist

- [ ] Physical attack shows damage and HP in console log.
- [ ] Target downed at HP <= 0: removed from occupancy, skipped in future activations.
- [ ] Spell damage ignores DEF (mage deals full damage to armored target).
- [ ] Skill damage reduced by DEF.
- [ ] Elevation bonus visible when attacking from higher ground.
- [ ] Cover reduces ranged damage (unit in brush takes less ranged damage).
- [ ] Defend (+2 DEF) visibly reduces incoming damage.
- [ ] Buff persists across turns within duration; removed after expiry.
- [ ] Status effect shown in unit log; sleeping unit skips turn.
- [ ] AoE hits multiple targets including allies.
- **Done:** checklist passes.

---

## Dependency Map

```
Phase 1 (BattleUnit, StatBlock, AbilityData, ItemData) ──> A (CombatResolver)
Phase 3 (HexGraph.elevation, terrain_props.cover) ─────────> A
Phase 4 (TurnActions, MatchState, RoundManager) ───────────> C (TurnActions integration)
A ──> B (BattleUnit status_effects, buff_durations)
A + B ──> C (TurnActions calls CombatResolver)
B ──> D (round-start buff/status expiry)
A + B + C + D ──> E (demo update)
A,B,C,D ──> F1–F7 (unit tests);  E ──> F8 (manual checklist)
```

**Suggested first pass:** A1–A2 → B1–B2 → C1–C5 → D1–D3 → E1–E3 → F. Group A is the core; B extends data model; C wires resolution into actions; D handles cleanup; E is demo; F verifies.

---

## Phase 5 Definition of Done

- [ ] `CombatResolver` with `resolve_attack()`, `resolve_damage()`, `resolve_heal()`, `resolve_buff()`, `resolve_status()`, `get_weapon_power()` (A).
- [ ] Physical damage formula with weapon power, elevation bonus, cover defense, minimum 1 (A).
- [ ] Spell damage ignores DEF; skill damage reduced by DEF (A).
- [ ] Healing clamped to max HP (A).
- [ ] `BattleUnit.status_effects` array with `has_status()`, `remove_status()` helpers (B).
- [ ] `MatchState.item_provider` and `MatchState.buff_durations` additions (B).
- [ ] `TurnActions.execute_attack` resolves damage, handles blind miss, handles downing (C).
- [ ] `TurnActions.execute_ability` dispatches to correct effect resolver, supports AoE burst (C).
- [ ] `TurnActions.execute_use_item` delegates to ability resolution for granted abilities (C).
- [ ] AoE target collection via `_collect_affected_units` (C).
- [ ] Downing clears occupancy (C).
- [ ] Round-start cleanup: defend → buff expiry → status expiry → unit reset (D).
- [ ] Sleep skip at activation (D).
- [ ] Demo wires `item_provider`, shows damage/HP/downing/effects in console log (E).
- [ ] GUT tests for all resolution paths: physical, spell, skill, heal, buff, status, AoE, elevation, cover, downing, durations, integration (F).
- [ ] Manual demo checklist verified (F).
- [ ] Git tag `phase-5-complete`.
