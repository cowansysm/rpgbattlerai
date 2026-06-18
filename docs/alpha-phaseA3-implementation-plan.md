# Phase A3 — Implementation Plan

**Source spec:** `alpha-phaseA3-spec.md`
**Master spec:** `alpha-specs.md` (§5.6)
**Builds on (Alpha):** `alpha-phaseA2-implementation-plan.md` (`EntitySchema.STAT_KEYS`, ability columns)
**Builds on (MVP):** `phase1` (`StatKey`, `StatBlock`, `StatResolver`, `Validator`), `phase5-implementation-plan.md` (`CombatResolver`, `TurnActions`)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-06-17

---

## How to use this plan

Five **work groups** (A–E). Across groups: **A** (`StatKey` extension) unblocks everything; **B** (resolution math) needs A; **C** (data wiring + re-tune) needs A and is validated by B's tests; **D** (display + A2 sync) needs A; **E** (tests) trails B–C.

Each task lists a **done state**. Code stubs are Godot 4 / GDScript — drop-in edits to existing classes. The change is small in code, large in data; treat the re-tune (C) as first-class work.

> **Carry-over:** A3 edits the existing `StatKey`, `CombatResolver`, `TurnActions`, `AbilityData`, and content JSON. `StatResolver` already iterates `StatKey.all_strings()` and `StatBlock` is string-keyed, so adding enum entries flows through derivation and validation with no further code. If A2 has shipped, also update its `STAT_KEYS`.

---

## Group A — `StatKey` Extension

*Pure enum change. Unblocks all.*

### A1. Add `MAG`/`RES`
- Extend `enum Key`, `KEYS`, and `_STRINGS`.
- **Done:** `StatKey.all_strings()` includes `"mag"`/`"res"`; `from_string`/`to_string_key` round-trip them.

```gdscript
# src/core/data/stat_key.gd
enum Key { SPD, ATK, RNG, DEF, HP, JUMP, WP, MAG, RES }

const KEYS := [Key.SPD, Key.ATK, Key.RNG, Key.DEF, Key.HP, Key.JUMP, Key.WP, Key.MAG, Key.RES]

const _STRINGS: Dictionary = {
    Key.SPD: "spd", Key.ATK: "atk", Key.RNG: "rng", Key.DEF: "def",
    Key.HP: "hp", Key.JUMP: "jump", Key.WP: "wp",
    Key.MAG: "mag", Key.RES: "res",
}
```

### A2. Audit for hardcoded stat lists
- Grep for hand-listed stats (HUD rows, BP heuristic) that don't iterate `StatKey`; note any that must include the new keys.
- **Done:** every stat consumer either iterates `StatKey` or is listed for the D-group display update.

---

## Group B — Magical Resolution

*Depends on A. The core math change.*

### B1. Spell branch of `resolve_damage`
- Replace the `else` (spell) branch to scale with `MAG` and subtract `RES`; keep skill, Defend die, elevation, wake-on-damage.
- **Done:** spell damage rises with caster MAG and falls with target RES; floors at 1 (tested in E1).

```gdscript
# src/core/combat/combat_resolver.gd  (resolve_damage; add mag_scaling param)
static func resolve_damage(
    attacker: BattleUnit, target: BattleUnit, effect_value: int, ability_type: String,
    attacker_elev: int, target_elev: int, elev_bonus: int = -1, mag_scaling: float = 1.0
) -> Dictionary:
    if elev_bonus < 0:
        elev_bonus = Constants.get_value("ELEV_BONUS", 1)
    var e_bonus: int = elev_bonus if attacker_elev > target_elev else 0
    var atk_roll: int = roll_die()
    var damage: int
    if ability_type == "skill":
        damage = max(1, atk_roll + effect_value + e_bonus - target.stats.effective("def"))
    else:
        var mag_bonus: int = int(round(mag_scaling * attacker.stats.effective("mag")))
        damage = max(1, atk_roll + effect_value + mag_bonus + e_bonus - target.stats.effective("res"))
    var def_roll: int = 0
    if target.stats.has_modifier_from_source("defend"):
        def_roll = roll_die()
        damage = max(1, damage - def_roll)
    _wake_on_damage(target)
    target.current_hp = max(0, target.current_hp - damage)
    return {"damage": damage, "atk_roll": atk_roll, "def_roll": def_roll,
        "target_hp_after": target.current_hp, "is_downed": target.current_hp <= 0}
```

### B2. `MAG`-scaled healing
- Extend `resolve_heal` with optional caster + `mag_scaling`; default flat.
- **Done:** divine heals scale with MAG; item/basic heals (no caster) stay flat.

```gdscript
static func resolve_heal(target: BattleUnit, effect_value: int,
        caster: BattleUnit = null, mag_scaling: float = 0.0) -> Dictionary:
    var bonus: int = int(round(mag_scaling * caster.stats.effective("mag"))) if caster else 0
    var max_hp: int = target.stats.effective("hp")
    var healing: int = max(0, min(effect_value + bonus, max_hp - target.current_hp))
    target.current_hp = min(target.current_hp + healing, max_hp)
    return {"healing": healing, "target_hp_after": target.current_hp}
```

### B3. `mag_scaling` on `AbilityData` + thread through `TurnActions`
- Add the field (default per spec §4.3) and pass it (and `caster`) at the call sites.
- **Done:** abilities carry `mag_scaling`; `turn_actions` resolve_damage/heal calls supply it.

```gdscript
# src/core/data/ability_data.gd
@export var mag_scaling: float = 1.0   # 0.0 = flat; applies to spell damage / scaled heals

# src/core/combat/turn_actions.gd  (~line 341 / 362)
var result := CombatResolver.resolve_damage(
    caster, target, value, ability.type, caster_elev, target_elev, -1, ability.mag_scaling)
# ...
var result := CombatResolver.resolve_heal(target, value, caster, ability.mag_scaling)
```

---

## Group C — Content Data Wiring & Re-tune

*Depends on A; validated by B/E. The data half.*

### C1. Stats on races/classes/characters/items
- Add `mag`/`res` to race & class `stats`/modifiers, character `base_stats`, and item passives where appropriate.
- **Done:** loading content validates; casters have MAG > 0, others low; some RES sources exist.

### C2. Re-tune existing spells & heals
- For each damage spell, set `mag_scaling` and reduce flat `value` so a representative caster reproduces ~current output; do the same for heals.
- **Done:** representative caster/target pairs land near prior damage; high MAG/RES shift it as intended.

### C3. Validate the re-tuned set
- Boot the pipeline; confirm structural + referential validation passes with the new stats/fields.
- **Done:** `GameData` loads clean; no validation errors.

---

## Group D — Display & Pipeline Sync

*Depends on A.*

### D1. Show `MAG`/`RES` in unit info
- Add rows wherever stats are displayed (HUD/inspector, debug readout if it lists stats).
- **Done:** selecting/inspecting a unit shows MAG and RES.

### D2. A2 stat-column sync
- Add `"mag"`, `"res"` to `EntitySchema.STAT_KEYS`; ensure `stats.mag`/`stats.res` export and round-trip; add a `mag_scaling` column to the abilities schema.
- **Done:** A2 round-trip tests still pass with the new columns.

---

## Group E — Tests & Verification

### E1. Magical resolution tests (GUT)
- Fixed dice; assert spell damage = `atk_roll + value + round(scaling×MAG) + elev − RES` (floored), that MAG↑/RES↑ move it correctly, and that the **attack die still contributes** to spells.
- Assert the **Defend die reduces spell damage** (a Defended target takes less from a spell), confirming the defense die applies to magic, not just physical/skill.
- **Done:** green, headless.

```gdscript
# tests/core/combat/test_magical_resolution.gd
extends GutTest

func before_each() -> void:
    CombatResolver.dice_roller = func() -> int: return 3   # fixed

func test_spell_scales_with_mag_and_res() -> void:
    var caster := _unit({"mag": 6})
    var target := _unit({"res": 2, "hp": 50})
    var r := CombatResolver.resolve_damage(caster, target, 4, "spell", 0, 0, 0, 1.0)
    # 3(roll) + 4(value) + 6(mag) + 0(elev) - 2(res) = 11
    assert_eq(r["damage"], 11)

func test_skill_unchanged_uses_def() -> void:
    var a := _unit({}); var t := _unit({"def": 3, "hp": 50})
    var r := CombatResolver.resolve_damage(a, t, 5, "skill", 0, 0, 0)
    assert_eq(r["damage"], 5)   # 3 + 5 - 3

func test_defend_die_reduces_spell_damage() -> void:
    var caster := _unit({"mag": 6})
    var target := _unit({"res": 2, "hp": 50})
    target.stats.push_modifier(StatModifier.new("def", 2, "defend"))   # Defend action active
    var r := CombatResolver.resolve_damage(caster, target, 4, "spell", 0, 0, 0, 1.0)
    # base 3(roll) + 4 + 6(mag) - 2(res) = 11, minus defense die 3 → 8
    assert_eq(r["damage"], 8)
    assert_eq(r["def_roll"], 3)
```

### E2. Heal-scaling test (GUT)
- Assert `MAG`-scaled heal vs flat heal (no caster).
- **Done:** green.

### E3. Physical & regression suite
- Run the Phase 5 resolution suite; confirm basic attacks and skills are unchanged.
- **Done:** all green.

### E4. Balance sanity checklist
- [ ] Representative caster reproduces near-prior spell damage post-re-tune.
- [ ] High-MAG caster out-damages low-MAG; high-RES target takes less.
- [ ] No spell trivialized to the floor against default-RES targets.
- **Done:** checklist reviewed.

---

## Dependency Map

```
A (StatKey +MAG/RES) ──┬──> B (resolution math) ──┐
                       ├──> C (data wiring + re-tune) ──┤
                       └──> D (display + A2 sync) ───────┴──> E (tests)
```

**Suggested first pass:** A1–A2 → B1–B3 → C1–C3 → D1–D2 → E1–E4. Land the math with tests on stub units before re-tuning real content.

---

## Phase A3 Definition of Done

- [ ] `MAG`/`RES` in `StatKey` (`enum`/`KEYS`/`_STRINGS`); derivation & validation pick them up; no stray hardcoded lists (A).
- [ ] `resolve_damage` spell branch uses MAG/RES (floor, **attack die, Defend die**, elevation); skill branch unchanged (B1).
- [ ] Attack die and Defend die preserved for spells — defense die reduces magical damage and persists to the defender's next activation; verified by test (E1).
- [ ] `resolve_heal` MAG-scaling with safe defaults; `mag_scaling` on `AbilityData` threaded through `TurnActions` (B2–B3).
- [ ] `mag`/`res` wired into content; existing spells/heals re-tuned; content validates clean (C).
- [ ] HUD/unit info shows MAG/RES; A2 `STAT_KEYS` + `mag_scaling` column updated and round-tripping (D).
- [ ] Magical + heal-scaling tests and physical/skill regression suite green; balance checklist reviewed (E).
- [ ] Git tag `alpha-phaseA3-complete`.
