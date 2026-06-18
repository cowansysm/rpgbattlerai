# Phase A4 — Character Instances, Classes & Job Tree Specification

**Parent plan:** `alpha-implementation-plan.md` (Phase A4)
**Master spec:** `alpha-specs.md` (§5 Character Instances & Progression, §6 templates)
**Builds on (Alpha):** `alpha-phaseA3-spec.md` (`MAG`/`RES` stats), `alpha-phaseA2-spec.md` (CSV columns for new class fields)
**Builds on (MVP):** `phase1-spec.md` (`CharacterData`, `ClassData`, `RaceData`, `StatResolver`, `Validator`), `phase4`/`phase5` (`BattleUnit`, deployment)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-17

---

## 1. Purpose & Scope

Phase A4 is the **core data shift** of the Alpha: combatants stop being static premades and become **persistent, unique instances** that level up, learn abilities by job, climb an **archetype-based job tree** rooted at **Vagabond**, and carry an equipment loadout — in the spirit of *Final Fantasy Tactics*. It turns the MVP `CharacterData` into a **template** (a recruitment seed) and introduces the mutable **`CharacterInstance`** that the player will own.

Crucially, A4 keeps the combat layer untouched. An instance produces a **synthesized, read-only `CharacterData` snapshot** plus a derived `StatBlock`, so the existing `BattleUnit.from_character(...)` path and everything below it (`CombatResolver`, `TurnActions`, deployment) consume instances with no changes.

### In scope

- A **`CharacterInstance`** runtime model with generated identity, level/XP, per-class JP, unlocked classes, learned abilities, a free-form ability loadout, accumulated growth, and equipment slots.
- **Leveling & class-driven stat growth**; **JP earn/spend** to learn abilities; **class unlock/upgrade** along a job tree.
- The **archetype paradigm** (Support / Control / Physical Might·Melee·Ranged / Magical Might·Arcane·Divine) and the **foundational tree**: Vagabond → (level 3) Thief / Soldier / Adept → branches.
- Extensions to `ClassData` (archetype, branch, tier, growth, prerequisites, jp_costs) and `RaceData` (base stat profile); `CharacterData`-as-template additions.
- The **instance → `BattleUnit` bridge** via a synthesized `CharacterData` + an `InstanceStatResolver`.
- Authoring the **root of the tree** (Vagabond, Thief, Soldier, Adept) and their starter abilities, enough to be demonstrable; per-race **name tables**.

### Out of scope

- **Persistence / save system** (Phase A5) — A4 instances live in memory and are exercised by tests/dev harness; saving to `user://` is A5.
- **Battle Bands and the management UI** (A5); **economy/shop/recruitment flow** (A6/A8).
- The **full class/ability libraries** (~20+ classes, ~80+ abilities) — Phase A9. A4 seeds only the root tree to prove the mechanics.
- AI (A7) and the run (A8).
- Rich in-battle loadout UI (a dev/inspector view suffices; full UI is A5).

### Exit criteria

Phase A4 is complete when:

1. A `CharacterInstance` is generated from a template with a unique id and a race-appropriate generated name, starting as **Vagabond at level 1**.
2. Gaining XP levels the instance and applies **class-driven growth** to its stats (capped at `MAX_LEVEL`).
3. Earning JP and spending it **learns abilities** per `jp_costs`; **class unlocks** are gated by prerequisites, and Vagabond unlocks **Thief / Soldier / Adept** at `TIER1_UNLOCK_LEVEL` (default 3).
4. The instance fields with one **active class** and a **free-form ability loadout** (≤ `ABILITY_SLOTS`) drawn from learned abilities of any unlocked class; equipment assignment respects the active class's access.
5. The instance produces a `BattleUnit` (synthesized `CharacterData` + derived `StatBlock`) that the **existing combat layer consumes unchanged**.
6. All of the above is covered by headless unit tests; authored root-tree content validates clean.

---

## 2. Design Decisions (Phase A4)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Template vs instance** | `CharacterData` becomes the **template** (authored seed); a new **`CharacterInstance`** (`RefCounted`) holds all mutable, persistent state. | Separates authored content from owned state; instances are what A5 saves. |
| **Bridge via synthesized `CharacterData`** | An instance produces a transient, read-only `CharacterData` snapshot (classes = active class, equipment = loadout, abilities = ability loadout) consumed by `BattleUnit.from_character`. | The entire combat layer reads `unit.character.*` today; synthesizing a snapshot means **zero combat-layer changes**. |
| **Stat derivation** | `InstanceStatResolver` computes base stats = **race base profile + active-class modifiers + accumulated growth**; runtime modifiers (equipment/buffs/terrain) stack on top as today. | Mirrors `StatResolver` but sourced from instance state; keeps the three-layer stat model. |
| **Everyone starts Vagabond** | Instances begin as Vagabond L1 regardless of template; the template's `recommended_path` is guidance only. | Master-spec requirement; a single, shared starting class roots the job tree. |
| **Archetype job tree** | `ClassData` gains `archetype`, `branch`, `tier`, `growth`, `prerequisites`, `jp_costs`; prerequisites generalize the existing `required_classes`. | Encodes the MMORPG role model and the Vagabond→Thief/Soldier/Adept→branches structure as data. |
| **Free-form loadout** | One active (primary) class for stats/equipment access + innate kit, plus an ability loadout of any learned abilities up to `ABILITY_SLOTS`. | Honors "no hard two-job cap" while keeping battle UI/balance tractable (master-spec assumption). |
| **Growth model** | Per-class growth rates accumulated and floored on level-up (`GROWTH_MODEL = "per_class_rate"`). | FFT-style: the class you level in shapes the stat curve; simple and tunable. |
| **Persistence deferred** | Instances are in-memory in A4; A5 adds `SaveManager`/`user://`. | Keeps A4 focused on the model and progression rules. |

---

## 3. Templates & Generated Identity

### 3.1 Character template

`CharacterData` is repurposed as the **template** — a recruitment seed, not a fielded character:

- Existing fields stay (`id`, `display_name`, `race`, …) but `classes`/`level`/`base_stats` describe a *suggested* build, not the instance's actual state.
- New fields: `recommended_path` (target archetype/class for flavor and recruit suggestion) and `name_tables` (or a reference into per-race name data).
- The MVP premades become templates; instances generated from them start as Vagabond L1.

### 3.2 Identity generation

On creation an instance gets:

- A **unique `instance_id`** (generated, stable for life).
- A **generated `name`** from race-appropriate **name tables** (`data/names/<race>.json` or a `names` block), e.g., given-name + optional surname.
- An optional cosmetic appearance seed (color/symbol variant) — cosmetic only in A4.

---

## 4. The `CharacterInstance` Model

A `RefCounted` holding persistent, mutable state (aligns with master-spec §9.2):

```
instance_id: String          # generated
template_id: String          # source template
name: String                 # generated identity
race: String
level: int                   # starts 1
xp: int
active_class: String         # starts "vagabond"
unlocked_classes: Array[String]   # always includes "vagabond"
jp: Dictionary               # class_id -> int
learned_abilities: Array[String]
ability_loadout: Array[String]    # <= ABILITY_SLOTS, subset of learned
equipment: Dictionary        # slot -> item_id ("weapon"/"armor"/"shield"/"accessory")
growth_accumulated: Dictionary    # StatKey -> int
downs_this_run: int          # run-scoped (A8); reset per run
```

The instance owns no rendering and no combat logic — it is data plus the progression operations in §5–§6.

---

## 5. Progression

### 5.1 Leveling & growth

- XP is gained from battles/nodes (awarded in A8); crossing an `XP_CURVE` threshold raises `level` (capped at `MAX_LEVEL`).
- On level-up, the **active class's `growth`** rates are accumulated into `growth_accumulated` (per `StatKey`, floored per `GROWTH_MODEL`).
- Effective base stats are derived (§7) from race base + active-class modifiers + `growth_accumulated`.

### 5.2 Job Points & learning abilities

- JP accrues **per class** (`jp[class_id]`), earned for the active class in battle (`JP_PER_BATTLE`, optional `JP_SHARE` to others).
- Spending JP **learns an ability** if the ability belongs to an unlocked class and the class's `jp_costs[ability]` is affordable; learned abilities persist permanently.

### 5.3 Class unlock & upgrade

- A class **unlocks** when its `prerequisites` are met (character level and/or JP/level in prerequisite classes) and any `CLASS_UNLOCK_COST` is paid.
- **Vagabond** is unlocked from the start; at `TIER1_UNLOCK_LEVEL` (default 3) its prerequisites are satisfied for **Thief**, **Soldier**, and **Adept**.
- **Upgrading** is unlocking an advanced class and switching `active_class` to it; everything learned in prior classes is retained.

### 5.4 Active class & ability loadout

- `active_class` sets stat-growth context, equipment access, and innate kit.
- The **ability loadout** is any subset of `learned_abilities` (from any unlocked class) up to `ABILITY_SLOTS`; this is the kit the instance fields with.

### 5.5 Equipment

- The instance holds an `equipment` slot map (`weapon`/`armor`/`shield`/`accessory`) referencing item ids.
- Assignment is gated by the **active class's `equipment_access`**. (Inventory ownership and reassignment UI are A5; A4 supports equip/unequip on the instance.)

---

## 6. Classes, Archetypes & the Job Tree

### 6.1 Archetypes

Every class declares an `archetype` (and optional `branch`):

| Archetype | Branch | Role |
|-----------|--------|------|
| Support | — | Healing-adjacent utility, buffs, sustain. |
| Control | — | Debuffs, status, zoning. |
| Physical Might | Melee / Ranged | Front-line / skirmish physical damage. |
| Magical Might | Arcane / Divine | Offensive arcane / healing-holy casting. |

### 6.2 Foundational tree (authored in A4)

- **Vagabond** — `tier: starting`, basic kit (a basic attack skill + a basic utility); the root.
- **Thief** — `tier: tier1`, opens **Control/Support**; prereq: Vagabond + character level 3.
- **Soldier** — `tier: tier1`, opens **Physical Might**; prereq: Vagabond + character level 3.
- **Adept** — `tier: tier1`, opens **Magical Might**; prereq: Vagabond + character level 3.

A4 authors these four classes (with `growth`, `jp_costs`, prerequisites, archetype/branch) and a small set of starter abilities for each, enough to demonstrate leveling, learning, unlocking, and branching. The deeper/advanced classes are A9.

### 6.3 `ClassData` extensions

`ClassData` gains: `archetype: String`, `branch: String`, `tier: String` (`starting`/`tier1`/`advanced`/`elite`), `growth: Dictionary` (StatKey → rate), `jp_costs: Dictionary` (ability_id → int), and `prerequisites` (character level + prerequisite-class thresholds — generalizing the existing `required_classes` `[id, level]` pairs). The new stat keys from A3 (`mag`/`res`) are valid in `stat_modifiers` and `growth`.

---

## 7. Instance → BattleUnit Bridge

### 7.1 Derived stats

`InstanceStatResolver.resolve(instance, providers) -> StatBlock` computes the base block (mirroring `StatResolver` but instance-sourced):

```
base(key) = race.base_stats[key] + active_class.stat_modifiers[key] + growth_accumulated[key]   (for each StatKey)
```

Runtime modifiers (equipment passives, buffs, terrain from A0) stack on top via the existing `StatBlock` mechanism, unchanged.

### 7.2 Synthesized snapshot

`instance.to_character_data() -> CharacterData` builds a transient, read-only `CharacterData` so downstream code that reads `unit.character.*` keeps working:

- `classes = [active_class]`, `equipment = [slot items...]`, `abilities = ability_loadout`, `race`, `display_name = name`, `level`, `base_stats` = derived base.

### 7.3 Fielding

`BattleUnit.from_instance(instance, providers)` (a thin convenience) calls `InstanceStatResolver` and `to_character_data()`, then delegates to the existing `BattleUnit.from_character(snapshot, stat_block)`. The combat layer below is untouched. (Composing a *party/band* of instances into a match is wired in A5/A8; A4 delivers the single-instance bridge and its tests.)

---

## 8. Data Model Summary

- **CharacterInstance** (new, runtime/persistent) — §4.
- **CharacterData (template)** — adds `recommended_path`, `name_tables`.
- **ClassData** — adds `archetype`, `branch`, `tier`, `growth`, `jp_costs`, `prerequisites`.
- **RaceData** — adds a `base_stats` profile (the baseline an instance starts from; existing `stat_modifiers` are folded into or complement the baseline).
- **New authored data** — `data/names/<race>.json` (name tables); the four root classes and their starter abilities.
- **Validator** — extend class validation for `archetype`/`tier`/`prerequisites`/`jp_costs`; assert the job tree is rooted at Vagabond and prerequisites resolve.
- **A2 pipeline** — class CSV gains `archetype`, `branch`, `tier`, `growth.*`, `jp_costs`, `prerequisites` columns (forward-referenced in A2 §4).

---

## 9. Risks & Notes

- **Stat baseline source.** Moving from MVP absolute `base_stats` on characters to race-baseline + class + growth is a real remodel; keep early numbers close to the MVP by tuning race base profiles, and validate via the bridge tests.
- **Snapshot fidelity.** The synthesized `CharacterData` must expose everything downstream reads (`equipment` for weapon power, `classes` for access, `abilities` for kit). Audit `CombatResolver`/`TurnActions`/`AbilityResolver` reads of `unit.character.*`.
- **Prerequisite model.** Generalizing `required_classes` to character-level + per-class thresholds must stay data-driven and cycle-free (tree rooted at Vagabond); validate.
- **Loadout vs learned.** The loadout must be a subset of learned abilities and within `ABILITY_SLOTS`; enforce on set.
- **Growth rounding.** Per-level fractional growth accumulates; define floor/round consistently so levels are deterministic and testable.
- **Persistence boundary.** A4 instances are in-memory; do not bake save-format assumptions here — that contract is A5's.
- **Scope creep.** No bands, save, economy, full class library, or AI — only the instance model, progression, the root tree, and the bridge.

---

## 10. Phase A4 Deliverables Checklist

- [ ] `CharacterInstance` model with the §4 fields; generated id + race-appropriate name; starts Vagabond L1 (§3, §4).
- [ ] Leveling with class-driven growth (capped at `MAX_LEVEL`); `growth_accumulated` feeds derived base (§5.1, §7.1).
- [ ] JP earn/spend; `learn_ability` gated by unlocked class + `jp_costs` (§5.2).
- [ ] Class unlock/upgrade via `prerequisites`; Vagabond→Thief/Soldier/Adept at `TIER1_UNLOCK_LEVEL` (§5.3, §6.2).
- [ ] Active class + free-form ability loadout (≤ `ABILITY_SLOTS`); equipment gated by active-class access (§5.4–5.5).
- [ ] `ClassData`/`RaceData`/template extensions + `DataFactory`/`Validator` updates; root tree + name tables authored and validating (§6.3, §8).
- [ ] `InstanceStatResolver` + `to_character_data()` + `BattleUnit.from_instance` producing a unit the existing combat layer consumes unchanged (§7).
- [ ] Tunables added (`MAX_LEVEL`, `TIER1_UNLOCK_LEVEL`, `XP_CURVE`, `JP_PER_BATTLE`, `ABILITY_SLOTS`, `CLASS_UNLOCK_COST`, `GROWTH_MODEL`) (alpha-specs §5.7).
- [ ] Headless unit tests for identity, leveling/growth, JP/learning, unlock/tree, loadout, and the bridge; root content validates.
- [ ] Git tag `alpha-phaseA4-complete`.
