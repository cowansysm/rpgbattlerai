# Phase A3 — Stat Additions & Magical Resolution Specification

**Parent plan:** `alpha-implementation-plan.md` (Phase A3)
**Master spec:** `alpha-specs.md` (§5.6 Stat additions)
**Builds on (Alpha):** `alpha-phaseA2-spec.md` (CSV `stats.*` columns will gain the new keys)
**Builds on (MVP):** `phase1-spec.md` (`StatKey`, `StatBlock`, `StatResolver`, `Validator`), `phase5-spec.md` (`CombatResolver`)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-17

---

## 1. Purpose & Scope

Phase A3 adds two canonical stats — **`MAG`** (magic power) and **`RES`** (magic defense) — and rebuilds spell resolution around them, replacing the MVP simplification in which "magic is folded into per-ability values and DEF" and spells ignore defense entirely. After A3, spell damage **scales with the caster's `MAG`** and is **mitigated by the target's `RES`**, giving the deeper casting jobs (A4 job tree) and the larger ability library (A9) a real stat to build around.

This is the **most invasive Alpha change to combat math**, so it is sequenced early — before mass ability authoring — so that all new spells are authored against the final model. It is small in surface area (the stat enum and one resolver) but high in blast radius (every spell number), so it includes a contained re-tune of the existing ~14 abilities.

### In scope

- Add `MAG` and `RES` to the `StatKey` enum (and the A2 stat-column list).
- A **magical resolution branch** in `CombatResolver`: spell damage uses `MAG`/`RES`; optional `MAG`-scaled healing for divine magic.
- An optional per-ability **`mag_scaling`** coefficient (alpha-specs §10.1).
- Wire the new stats into authored data (races, classes, characters/templates, item passives) and **re-tune the existing spell/heal values** to the new formula.
- Display `MAG`/`RES` wherever stats are shown (HUD/inspector).

### Out of scope

- The job tree / class archetypes that *use* `MAG` heavily (Phase A4) — A3 provides the stat and math; A4 and A9 provide the casters and spells.
- New abilities/elemental affinity/resistance systems (A9 / post-Alpha).
- Changing physical attacks or `skill`-type damage (they remain ATK/DEF-based).
- A separate magic-evasion or spell-accuracy system (the existing attack-die + Defend mechanics carry over).

### Exit criteria

Phase A3 is complete when:

1. `MAG` and `RES` exist in `StatKey`; derivation and validation pick them up automatically (no hardcoded key lists changed elsewhere).
2. A spell's damage increases with caster `MAG` and decreases with target `RES`, flooring at 1, with the **attack die** and elevation bonus still applying.
3. The **Defend die applies to magical damage** the same as physical/skill, and persists until the defender's next activation; a test proves a Defended target takes reduced spell damage.
4. Divine/holy heals optionally scale with caster `MAG` via `mag_scaling`.
5. Physical attacks and `skill`-type damage are unchanged (regression green).
6. The existing abilities are re-tuned so their effective output is sane under the new model; the full suite passes.
7. `MAG`/`RES` appear in the unit info display; the A2 pipeline round-trips them as `stats.mag` / `stats.res`.

---

## 2. Design Decisions (Phase A3)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Single point of expansion** | Add `MAG`/`RES` to the `StatKey` enum, `KEYS`, and `_STRINGS` only. | `StatResolver` iterates `StatKey.all_strings()` and `StatBlock` is string-keyed, so derivation flows automatically; `Validator` accepts them via `StatKey.is_valid_key`. No other key list exists to update. |
| **Spells become magical** | `type == "spell"` damage = `atk_roll + value + round(mag_scaling × caster.MAG) + elev − target.RES`, floored at 1. | Replaces the MVP "spells ignore DEF" rule; gives casters a scaling stat and gives `RES` a job. Mirrors the physical formula's structure for consistency. |
| **Skills stay physical** | `type == "skill"` damage is unchanged (ATK-flavored value, reduced by `DEF`). | Skills are martial; keeping them physical preserves the melee/ranged identity and avoids re-tuning non-spells. |
| **Optional `mag_scaling`** | Abilities carry an optional `mag_scaling` float (default **1.0** for spell damage / heals; `0.0` means "flat, no MAG"). | Lets content tune how hard each spell leans on `MAG`; default-on keeps casters relevant without per-ability boilerplate. |
| **Divine heals scale** | `resolve_heal` gains an optional caster + `mag_scaling` so holy magic scales with `MAG`; basic/item heals can pass `0.0`. | Supports the Support/Divine archetype (A4) without a separate heal stat. |
| **Re-tune, don't rewrite** | A3 re-tunes the existing ~14 ability values to the new model in this phase. | Small, contained; keeps the game balanced through the transition. Bulk authoring stays in A9. |
| **`RES` defaults low** | Most units start with low/zero `RES`; casters and certain races/armors grant it. | Keeps early balance close to MVP while making `RES` a meaningful investment. |

---

## 3. New Stat Keys

`MAG` and `RES` join the canonical enum:

| Enum value | String key | Meaning | Used by |
|------------|------------|---------|---------|
| `MAG` | `"mag"` | Magic power — scales spell damage and `MAG`-scaled healing. | base_stats, stat_modifiers, StatBlock, resolution |
| `RES` | `"res"` | Magic defense — mitigates magical damage. | base_stats, stat_modifiers, StatBlock, resolution |

Because the codebase already centralizes stats:

- **`StatKey`** — add to `enum Key`, `KEYS`, and `_STRINGS`. This is the only definition change.
- **`StatResolver`** — already iterates `StatKey.all_strings()`; new keys derive automatically from race/class/character contributions.
- **`StatBlock`** — string-keyed; `effective("mag")` / `effective("res")` work with no change.
- **`Validator.validate_stat_keys`** — uses `StatKey.is_valid_key`, so `mag`/`res` become valid stat keys automatically; unknown keys still rejected.
- **A2 pipeline** — extend the exporter's `STAT_KEYS` list so `stats.mag` / `stats.res` columns appear and round-trip.

---

## 4. Magical Resolution Model

### 4.1 Spell damage (changed)

`CombatResolver.resolve_damage` keeps its `skill` branch and replaces its `spell` branch:

```
e_bonus  = ELEV_BONUS if attacker_elev > target_elev else 0
mag_bonus = round(mag_scaling * attacker.effective("mag"))

# skill (unchanged): physical, reduced by DEF
damage = max(1, atk_roll + value + e_bonus - target.effective("def"))

# spell (A3): magical, reduced by RES
damage = max(1, atk_roll + value + mag_bonus + e_bonus - target.effective("res"))
```

The **Defend die** (`has_modifier_from_source("defend")`) and the **wake-on-damage** behavior still apply to both branches, exactly as today.

### 4.2 Healing (extended)

`resolve_heal` optionally scales with the caster's `MAG`:

```
heal_bonus = round(mag_scaling * caster.effective("mag"))   # 0 if no caster / mag_scaling 0
healing    = clamp(effect_value + heal_bonus, 0, max_hp - current_hp)
```

Basic and item heals may pass `mag_scaling = 0.0` for flat healing; class spells (White/Divine) pass their authored coefficient.

### 4.3 `mag_scaling`

An optional float on the ability (alpha-specs §10.1):

- Absent → defaults to **1.0** for `spell`-type damage effects and for heal effects authored on caster classes; **0.0** otherwise.
- `0.0` → pure flat value (no `MAG` contribution), useful for item-bound or utility effects.
- Higher values → spells that lean harder on `MAG`.

### 4.4 Dice & the Defend die (preserved across A3) — required

The MVP's randomized combat rolls and the Defend mechanic are **load-bearing and must survive A3 unchanged**. This is an explicit requirement, not an incidental detail:

- **Attack die.** Every damage resolution — physical attack, `skill`, **and `spell`** — still rolls the injectable `atk_roll = roll_die()` (1d6 by default) and adds it to the total. The magical branch keeps this exactly as the physical branch does; A3 does not make spells deterministic.
- **Defense die.** When a unit takes the **Defend** action it gains a defense die that is rolled against **all incoming damage — physical, skill, and magical alike** — and subtracted from the damage (floored at 1). The magical (`spell`) branch evaluates `target.stats.has_modifier_from_source("defend")` and rolls the defense die identically to the physical and skill branches. There is no "magic ignores Defend" carve-out.
- **Duration.** The defense die (and the Defend `+DEF` modifier) persists from the Defend action **until the defender's next activation**, including across round boundaries, exactly as established in Phase 11. A3 changes none of this duration logic — it lives on the `"defend"` modifier source, which the spell branch already reads.

In short: adding `MAG`/`RES` widens the damage formula but leaves the dice pipeline (`roll_die`, the injectable `dice_roller`, and the Defend die) intact for all attack types. The B1 stub in the implementation plan reflects this, and a dedicated test (plan E1) asserts the defense die reduces **spell** damage.

### 4.5 What else does not change

Physical basic attacks (`resolve_attack`), `skill`-type ability damage, buffs, statuses, revives, ranged cover, range/LoS, and the action economy are all unchanged. `RES` only enters the spell branch; `MAG` only enters spell damage and scaled heals.

---

## 5. Data Wiring & Re-tune

### 5.1 Authored stats

- **Races** (`races.json`): add `mag`/`res` modifiers where flavor warrants (e.g., Elf +MAG; Dwarf +RES).
- **Classes** (`classes.json`): caster classes grant `MAG`; some grant `RES`. (The full archetype set arrives in A4; A3 seeds the existing classes.)
- **Characters/templates** (`characters.json`): include `mag`/`res` in `base_stats` so existing premades have sensible values (casters > 0 MAG; others low).
- **Items** (`items.json`): armor/accessories may grant `RES` via passives.

### 5.2 Ability re-tune

Each existing damage spell gets a `mag_scaling` (typically `1.0`) and a **reduced flat `value`**, so that `value + mag_scaling × MAG` lands near the old single-number damage for a representative caster. Heal spells likewise. The goal is parity at the current power band, with headroom for `MAG` growth. This re-tune is part of A3 (≈14 abilities), not A9.

### 5.3 Worked example

`fire_1` today: `effect.value = 10`, spell, ignores DEF. After A3 with an Elf Black Mage at, say, `MAG 6`:

```
value 4 + mag_scaling 1.0 × MAG 6 = 10 base, then + atk_roll + elev − target.RES
```

i.e. lower the authored `value` to ~4 so a typical caster reproduces the prior ~10 before the die/elevation, while a high-`MAG` caster hits harder and a high-`RES` target takes less.

---

## 6. Touch Points (Call Sites)

The change is contained to a few well-known spots:

| Location | Change |
|----------|--------|
| `src/core/data/stat_key.gd` | Add `MAG`/`RES` to `enum Key`, `KEYS`, `_STRINGS`. |
| `src/core/combat/combat_resolver.gd` | Rewrite the `spell` branch of `resolve_damage`; extend `resolve_heal` with optional caster + `mag_scaling`. |
| `src/core/combat/turn_actions.gd` | Pass `ability.mag_scaling` and `caster` into `resolve_damage` / `resolve_heal` (lines ~341, ~362). |
| `src/core/data/ability_data.gd` | Add optional `mag_scaling: float` field (default per §4.3). |
| `data/*.json` | Add `mag`/`res` stats and `mag_scaling`; re-tune spell/heal values (§5). |
| `src/tools/entity_schema.gd` (A2) | Add `mag`/`res` to `STAT_KEYS`; add `mag_scaling` column to abilities. |
| HUD / unit info (`src/ui/`) | Show `MAG`/`RES` rows where stats are displayed. |

---

## 7. Risks & Notes

- **Balance swing.** Switching spells from "flat, ignore DEF" to "MAG-scaled, minus RES" changes every spell's output. Re-tune in the same phase and verify with representative caster/target pairs.
- **Heal signature ripple.** Extending `resolve_heal` changes its callers; keep a default (`caster = null`, `mag_scaling = 0.0`) so item/basic heals stay flat without edits.
- **Hidden key assumptions.** Confirm nothing outside `StatKey` enumerates stats by hand (UI rows, BP heuristic). `StatResolver` and `StatBlock` are safe; audit the HUD and any BP calc.
- **RES making spells too weak.** With the floor at 1 and low default `RES`, early balance should hold; watch high-`RES` targets trivializing casters — tune `RES` grants conservatively.
- **A2 sync.** If A2 already shipped, update its `STAT_KEYS` and re-export, or `stats.mag`/`stats.res` will be dropped on round-trip.
- **Scope creep.** No elemental resist tables, no spell accuracy/evasion, no new abilities — just the two stats and the magical branch.

---

## 8. Phase A3 Deliverables Checklist

- [ ] `MAG`/`RES` added to `StatKey` (`enum`, `KEYS`, `_STRINGS`); derivation/validation pick them up (§3).
- [ ] `resolve_damage` spell branch uses `MAG`/`RES` with floor, **attack die, and Defend die**, and elevation (§4.1).
- [ ] Attack dice and the Defend die are preserved for spells: the defense die reduces magical damage and persists until the defender's next activation; physical/skill dice behavior unchanged (§4.4).
- [ ] `resolve_heal` optionally scales with caster `MAG` via `mag_scaling`; flat heals preserved (§4.2).
- [ ] `mag_scaling` field on `AbilityData` with the §4.3 defaults; threaded through `turn_actions` call sites (§6).
- [ ] Physical attacks and `skill` damage unchanged (regression green) (§4.4).
- [ ] `mag`/`res` wired into races/classes/characters/items; existing spells/heals re-tuned to the new model (§5).
- [ ] HUD/unit info shows `MAG`/`RES`; A2 `STAT_KEYS` extended so they round-trip (§3, §6).
- [ ] Resolution unit tests (magical formula, MAG/RES scaling, heal scaling) + physical/skill regression green.
- [ ] Git tag `alpha-phaseA3-complete`.
