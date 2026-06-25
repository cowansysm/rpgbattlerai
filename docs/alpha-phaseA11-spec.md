# Phase A11 — Encounters, Level Scaling & Economy Refinement Specification

**Parent plan:** `alpha-implementation-plan.md` (new sub-phase A11)
**Master spec:** `alpha-specs.md` (§5 progression, §6 bands, §7 economy, §8 run)
**Builds on (Alpha):** A4 (instances, levels, `growth`, `InstanceStatResolver`), A5 (`BattleBand`, `Recruiter`, `BandPartyBuilder`, `SaveManager`), A6 (`Pricing`, `ShopService`, `LootRoller`), A8 (run/`EncounterGenerator` — consumes A11's encounter data)
**Builds on (content):** the 32-race / 268-class / 160-character / 768-ability libraries and `docs/class-tree-engine-changes.md`
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-24
**Status:** Draft v0.2 (refinements: Halfling draftable; level = Σ class levels with curve-based thresholds; dev/test tools in scope)

---

## 1. Purpose & Scope

Phase A11 introduces the **encounter** data layer and the **level-scaling** model that together make the single-player run "monster-heavy and level-appropriate," and it **re-tunes the early economy and shops** around a fixed starting purse. It is a **distinct Alpha feature** that plugs into the existing pipeline at well-defined seams (it revises A4 stats, A6 economy, and feeds A8's encounter generation) but does **not** require rebuilding those phases.

The keystone idea: **characters store base stats, not absolute stats**, and a single **`LevelScaler`** projects any character (player or monster) to a target level using its class `growth`. This lets the run pit **groups of monsters scaled to the player's band level**, collapsing most balance into one curve.

### In scope

- An **encounters dataset** (`data/encounters.json`): named opposing bands with a **`min_band_level`** gate, an enemy roster, an **optional map id**, and optional condition/alteration modifiers.
- **Base-stat conversion**: `characters.csv` stats reinterpreted as **base stats** (level-1 baseline); a `LevelScaler` that scales to any target level via class `growth`.
- **Level scaling** wired into encounter generation so monster bands fight at the **band level** (§3, point 3).
- **Band level** defined as the **average character level** of the band (point 8).
- **Economy refinement**: new bands start with **1 Human Vagabond (L1) + 500 gp**; recruit cost **50 gp**; combat gold ≈ **50 × band level**; equipment prices re-balanced around the 500 gp start.
- **Drafting restriction**: the player may only create the four ancestries **Human / Dwarf / Elf / Halfling**, each starting as a **Level 1 Vagabond** (point 7).
- **Level model**: a character's level is the **sum of its class levels**; the level curve sets each next-level XP threshold from that total (so it stays consistent for every downstream consumer).
- **Two-tier shops**: a **base shop** (band screen) stocking all lower-tier equipment, and **run-mode shops** (node map) with limited but specialized/expensive stock (premium gear is run-only).
- **Development/test tools** (dev-flag gated): cheats to set band/character level, grant gold and items, and force-spawn encounters so the feature can be fully tested.

### Out of scope

- The run framework itself (A8) — A11 supplies the encounter *data* and scaling *service* A8 consumes; A8 builds the node map and traversal.
- New combat mechanics, ability/class/item authoring beyond what re-tuning prices requires.
- Rich encounter scripting (multi-wave, scripted dialogue) — A11 keeps modifiers minimal and data-driven.
- Meta-progression / unlock economy (A10).

### Exit criteria

A11 is complete when:

1. `characters.csv` stats are **base stats**, and `LevelScaler.scale(character, level)` reproduces sensible combat stats at any level (L1 ≈ old authored values for legacy chars; monsters scale up with level).
2. `data/encounters.json` loads and validates: each encounter references real characters, an optional real map, and a `min_band_level ≥ 1`.
3. Given a band level, the system can **select an eligible encounter** (`min_band_level ≤ band_level`) and **field its enemies scaled to the band level**, on the encounter's map when specified.
4. **Band level = average of band character levels**; combat gold reward averages **≈ 50 × band level**.
5. A new band is created with **1 Human Vagabond (L1) + 500 gp**; recruiting a character costs **50 gp** and yields a **L1 Vagabond** of a chosen **Human/Dwarf/Elf/Halfling**.
6. The **base shop** offers all lower-tier equipment; **run shops** offer a limited specialized stock (with premium items unavailable in the base shop).
7. Headless tests cover scaling, encounter validation/selection, band-level math, reward math, and shop stock partitioning; the full suite is green.

---

## 2. Design Decisions (Phase A11)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Base stats over absolute** | `characters.csv` stats become **level-1 base stats**; combat stats are derived by `LevelScaler`. | One source of truth; enables level-matched monsters and removes hand-tuned absolute blocks (points 2, 4). |
| **Scale via existing `growth`** | `LevelScaler` reuses class `growth` rates: `scaled = base + round(growth × (level − 1))`. | No new curve; consistent with A4 `InstanceStatResolver`; monsters and instances scale the same way. |
| **Monsters fight at band level** | Encounter enemies are scaled to the **band level** (optionally offset per encounter). | "Equivalent level to the player's band" (point 3); difficulty tracks the player automatically (point 4). |
| **Band level = mean level** | `band_level = round(mean(character_level))` over the band roster. | Simple, legible (point 8). Character level = sum of class levels (class-tree model). |
| **Encounters are data** | `data/encounters.json` defines enemy bands, gate, optional map, modifiers. | Designers add fights without code; A8 selects/instantiates them (points 1, 5). |
| **Fixed starting purse** | New band = 1 Human Vagabond (L1) + **500 gp**, empty inventory. | Clear economic baseline to balance against (point 9). |
| **Reward = 50 × band level** | Average combat gold ≈ `GOLD_PER_BAND_LEVEL (50) × band_level`. | Predictable income curve to price gear against (point 10). |
| **Draft = the four ancestries, L1 Vagabond** | Recruitment offers Human/Dwarf/Elf/**Halfling**; all start as L1 Vagabond. | Player builds characters via the job tree, not via premades (point 7). Only monster races are non-draftable. |
| **Two shop tiers** | Base shop = all lower-tier gear; run shops = limited + specialized/premium (run-only). | Home base covers basics cheaply; runs are where rare gear is found (points 11, 12). |
| **Level = Σ class levels, one curve** | Character level is the sum of class levels; the level curve sets next-level thresholds from that total. | A single, consistent level definition for scaling, band level, rewards, and AI — multiclassing can't farm cheap thresholds (refinement 2). |
| **Dev/test tools in phase** | Dev-flag-gated cheats + encounter harness ship with A11. | The scaling/economy/encounter changes are hard to test by normal play; cheats make them verifiable (refinement 3). |
| **Separate feature, shared seams** | A11 revises A4 stats + A6 economy and feeds A8; it is built as its own work but lands those touch-points. | Honors "part of Alpha, separate from the current pipeline" (point 6). |

---

## 3. Level Scaling & Base Stats (points 2, 3, 4, 8)

### 3.1 Base stats

A character template's `stats` block is reinterpreted as the **base stat block at level 1** (the floor before growth). Authored monster characters (A-monster pass) already carry archetype-shaped blocks; these become their L1 base. Legacy MVP characters keep their values as L1 base (so L1 scaling ≈ today's behavior).

### 3.2 The scaler

```
LevelScaler.scale(base_stats, growth, level) -> StatBlock
  for each StatKey k:
    out[k] = base_stats[k] + round(growth.get(k, 0.0) × (level - 1))
```

- `growth` is the active class's per-level growth (monster classes carry it; player instances accumulate it already via A4).
- For **monsters**, `level` is the **target level** chosen at encounter time (§3.4); the monster's single class supplies `growth`.
- For **player instances**, A4's `InstanceStatResolver` already does the equivalent (`base_stats + class mods + accumulated growth`); A11 factors the per-level projection into the shared `LevelScaler` so both paths agree.
- Race modifiers and equipment passives apply **after** scaling, unchanged.

> **[ASSUMPTION]** Linear growth (`base + growth × (level−1)`) matches A4's `per_class_rate` model. If A10 balancing wants diminishing returns, the scaler is the single point to change.

### 3.3 Band level

```
band_level = round( mean( character_level for c in band.roster ) )      # point 8
character_level = sum( class_levels )                                    # class-tree model
```

Band level is recomputed on roster/level change. The **fielded** subset is used for encounter scaling at battle start; the **roster** average is the displayed band level. (A single definition — roster mean — is acceptable for Alpha; note the choice in code.)

### 3.4 Monster level matching

When an encounter is instantiated:

```
target_level = clamp(band_level + encounter.level_offset, 1, MAX_LEVEL)
for each enemy entry: spawn character scaled via LevelScaler to target_level
```

This delivers "groups of monsters at the player's level" (point 3) and folds difficulty tuning into the band-level curve (point 4).

### 3.5 Level model & XP thresholds (refinement 2)

- **Character level = Σ class levels.** A character's level is the sum of the levels it holds across **every class it knows** (each class caps at `level_max = 10`). This is the single definition consumed by band level (§3.3), monster scaling (§3.4), rewards (§5.3), and display.
- **One curve, keyed by character level.** The level curve (`XP_CURVE`, seeded by `XP_CURVE_BASE`) defines the XP required for the **next** level as a function of the character's **current total level** — not per-class. Gaining the next level *in whichever class is currently earning XP* costs `xp_threshold(character_level)`. Advancement cost therefore rises with overall power, and multiclassing cannot farm cheap low thresholds by hopping into a fresh class.
- **Leveling-algorithm contract.** Any XP/leveling code must: (a) compute the threshold from `character_level = Σ class_levels`; (b) on a threshold crossing, increment the **active class's** level (respecting its `level_max = 10`; overflow XP is discarded per the A4 class-switch rule); and (c) **recompute derived values** (character level, band level, scaled stats) immediately after. Downstream consumers read the recomputed character/band level — never a stale per-class figure. This contract is stated explicitly so the dependency survives any future leveling refactor.
- **Two distinct curves.** `LevelScaler` (§3.2) projects *stats* by level (single-class path for monsters; A4 accumulates per-class growth for players); `XP_CURVE` governs *when* a level is gained. Both key off the same character-level definition so they never disagree.

---

## 4. Encounter Dataset (points 1, 5)

### 4.1 Purpose

An **encounter** defines an opposing band and the conditions of a fight. The run's `EncounterGenerator` (A8) selects an eligible encounter for the current node and instantiates it at band level.

### 4.2 Schema (`data/encounters.json`)

```json
{
  "id": "goblin_warband",
  "name": "Goblin Warband",
  "min_band_level": 1,
  "enemies": [
    { "character": "goblin_soldier",  "count": 2 },
    { "character": "goblin_skirmisher","count": 2 },
    { "character": "goblin_shaman",   "count": 1 }
  ],
  "map": "forest_clearing",
  "level_offset": 0,
  "tags": ["goblinoid", "early"],
  "modifiers": {},
  "weight": 1.0
}
```

| Field | Type | Meaning |
|-------|------|---------|
| `id` / `name` | String | Identity. |
| `min_band_level` | int ≥ 1 | **Gate**: encounter is only eligible when `band_level ≥ min_band_level` (keeps advanced monsters out of early fights — point 1). |
| `enemies` | array of `{character, count}` | The opposing band; `character` references a real character template (typically a monster NPC). `count` ≥ 1. |
| `map` | String (optional) | A specific map id to fight on; absent → A8 picks from the pool (point 5). |
| `level_offset` | int (optional, default 0) | Adjusts enemy target level relative to band level (e.g., `+2` for an "elite" fight). |
| `tags` | [String] (optional) | Classification for selection/weighting (`boss`, `goblinoid`, `undead`, …). |
| `modifiers` | dict (optional) | Conditions/alterations to the combat (§4.3). Minimal in Alpha. |
| `weight` | float (optional, default 1.0) | Relative selection weight among eligible encounters. |

### 4.3 Modifiers (minimal, extensible)

`modifiers` is a free-form, data-driven dict; A11 implements a **small starter set** and leaves room for more:

- `level_offset` (also top-level) — enemy level bump.
- `enemy_buff` — a `{stat: value}` applied to all enemies (e.g., a "frenzied" pack).
- `victory` — alternate win condition tag (`defeat_all` default; `survive_n_rounds`, `defeat_leader` reserved).
- `forced_weather`/`hazard_on` — toggle terrain hazards (uses A0 terrain effects).

> Anything not recognized is ignored, so the framework is forward-compatible (richer scripting is post-Alpha).

### 4.4 Validation

Extend the validator/referential pass to cover encounters: `enemies[].character` resolves to a real character; `map` (if present) resolves to a real map; `min_band_level` and `count` are positive ints; `weight ≥ 0`. Invalid encounters fail load (boot) and CSV/JSON import.

### 4.5 Selection (consumed by A8)

```
eligible = [e for e in encounters if e.min_band_level <= band_level]
pick = weighted_choice(eligible, by e.weight, rng=run_seed)
enemies = [scale(spawn(entry.character), target_level) for entry in pick.enemies for _ in count]
map = pick.map or pool_pick(depth)
```

A8 remains responsible for *when* a Battle node fires; A11 supplies the *what* (eligible, level-matched band + map).

---

## 5. Band Start & Economy Refinement (points 9, 10)

### 5.1 New band

- Roster: **1 Human Vagabond at Level 1**.
- Gold: **500 gp**.
- Inventory: **empty** (gold funds starter gear via the base shop).

Replaces `RECRUIT_STARTING_GOLD = 200` + `STARTING_INVENTORY = [...]` with `STARTING_GOLD = 500` and an empty starting inventory plus a seeded L1 Human Vagabond.

### 5.2 Recruitment

- **Cost: 50 gp** (`RECRUIT_COST` unchanged) per new character.
- A recruit is a **Level 1 Vagabond** of a chosen ancestry (Human/Dwarf/Elf/Halfling — §6), generated identity per A4.

### 5.3 Rewards

- **Average combat gold ≈ `GOLD_PER_BAND_LEVEL (50) × band_level`** (point 10): L1 band ≈ 50, L2 ≈ 100, L3 ≈ 150, …
- Implemented by making `LootRoller` gold ranges a function of **band level** (replacing/augmenting the depth-only scale), centered on `50 × band_level` with variance.
- "Capital" (loot/items) scales similarly; the gold figure is the average, not a floor/cap.

### 5.4 Equipment cost balance (point 10)

Prices are tuned so the **500 gp start buys a reasonable starter kit** and income (`50 × band_level`/fight) gates progression:

- **Lower-tier gear** (the base-shop set, bp ≤ 2) priced **~20–160 gp** (already the case in the 128-item set) so a fresh band can equip its Vagabond and a recruit or two.
- **Mid/premium gear** (bp 3–4) **~180–650 gp**; **artifacts** (bp 5–6) **~700–1200 gp** — multi-fight investments, run-only (§7).
- A balance pass (with A10) validates: a L1 band can afford a weapon + light armor at start; premium gear takes several fights' income.

> **[ASSUMPTION]** Existing authored prices already approximate these bands; A11 audits and nudges values in `items.csv`, not the `Pricing` formula.

---

## 6. Character Drafting / Recruitment (point 7)

- The recruit/draft UI exposes the four ancestries: **Human, Dwarf, Elf, Halfling**.
- Regardless of choice, the new character is a **Level 1 Vagabond**; the player then trains it through the job tree (A4) and equips it (A5/shops).
- **Only monster races are non-draftable** (they back NPCs). All four player ancestries are selectable.
- This reshapes A5's `Recruiter`: race-gated to `DRAFTABLE_RACES`, fixed starting class = `vagabond`, fixed starting level = 1.

---

## 7. Shops: Base vs Run (points 11, 12)

### 7.1 Item availability tiers

Classify equipment by tier for shop stock:

- **Basic / lower-tier** — `bp ≤ 2` (≈ price ≤ 160). Available **everywhere**.
- **Premium / specialized** — `bp ≥ 3`. Available **only in run mode**.

> **[ASSUMPTION]** `bp` is the tier signal (no schema change). If finer control is wanted, add an optional `shop_tier` field to items later.

### 7.2 Base shop (band screen)

- Part of the **band management screen** (A5), always available between runs.
- Stocks **all lower-tier equipment** (every basic weapon/armor/shield/accessory) plus basic consumables.
- Uses A6 `ShopService` for buy/sell; sell value via `SELL_RATIO`.

### 7.3 Run-mode shops (node map)

- **Limited stock**: a small rotating selection per Shop node (seeded by the run), **not** the full catalogue.
- Carries **basic items** *and* **premium/specialized gear** — and premium gear is **only obtainable here** (point 12).
- Depth/band-level influences which premium items appear (more potent gear deeper in).

### 7.4 `shop_pools.json` restructure

Replace the current tier-named pools with a clearer split:

```json
{
  "base_shop":      ["iron_sword", "leather_armor", "buckler", "ring_of_protection", "tonic", "..."],
  "run_common":     ["steel_sword", "scale_mail", "kite_shield", "..."],
  "run_premium":    ["flametongue", "mythril_mail", "aegis_shield", "genji_gloves", "..."],
  "run_artifact":   ["excalibur", "dragon_plate", "zodiac_stone", "..."]
}
```

- `base_shop` = the basic set (auto-derivable as `bp ≤ 2`, or curated).
- Run Shop nodes draw a small sample: mostly `run_common`, a chance of `run_premium`, rare `run_artifact`, plus a few basics.

---

## 8. Data Model & Touch Points

- **New data:** `data/encounters.json` (array of encounter defs, §4.2).
- **New core:** `src/core/progression/level_scaler.gd` (`LevelScaler`); `src/core/run/encounter_data.gd` + loader (typed `EncounterData`); `src/core/run/encounter_selector.gd` (eligibility + weighted pick + instantiate at level).
- **New core:** `src/core/progression/leveling.gd` (`Leveling` — XP thresholds + level-up keyed on `character_level`, §3.5); `src/debug/dev_cheats.gd` (A11 dev tools, §8.5).
- **Modified core:** `Recruiter` (A5) — race-gated to `DRAFTABLE_RACES`, L1 Vagabond; `CharacterInstance` (A4) — expose `character_level()` = Σ class levels; `LootRoller` (A6) — gold ≈ `50 × band_level`; `BandPartyBuilder`/`EncounterGenerator` (A5/A8) — spawn enemies from encounter entries scaled by `LevelScaler`; `ShopService`/shop pools (A6) — base vs run stock; band-level helper on `BattleBand`.
- **Modified data:** `characters.csv` — stats reinterpreted as base (no value change required for L1 parity; document the semantics); `constants.json` — see §9; `shop_pools.json` — restructured (§7.4); `items.csv` — price audit (§5.4).
- **Validation:** add encounter referential checks; extend the CSV pipeline (`entity_schema`) only if encounters are authored via CSV (otherwise hand-authored/validated JSON like loot/shop pools).
- **Docs:** this spec + the A11 implementation plan; cross-reference `class-tree-engine-changes.md` (encounters depend on monster classes/characters which depend on that engine pass).

### 8.5 Development & Test Tools (dev-flag gated, refinement 3)

The A11 systems (scaling, level math, economy curve, encounter gating) are hard to exercise through normal play, so A11 ships **dev/test tooling** under the existing A0 **dev flag** (off in player builds, reachable from the Dev Tools menu):

- **State cheats:** set band gold; grant any item by id; set a character's per-class levels (→ recompute character/band level); grant XP/levels to a character or whole band; unlock all ancestries/classes for draft.
- **Encounter harness:** force-spawn a chosen encounter by id (or a random eligible one) at a chosen band level, on its map, straight into a quick battle — bypassing the run node map.
- **Scaling inspector:** a `DebugReadout` panel showing a selected character's base stats, growth, level, scaled stats at the current level, and the next-level XP threshold.

No dev path affects the shipped player experience when the flag is off (A0 contract).

---

## 9. Tunables (`constants.json`)

```
STARTING_GOLD          = 500     // replaces RECRUIT_STARTING_GOLD (200)
RECRUIT_COST           = 50      // unchanged
STARTING_INVENTORY     = []      // empty; gold funds the base shop
GOLD_PER_BAND_LEVEL    = 50      // avg combat gold ≈ this × band_level
DRAFTABLE_RACES        = ["human", "dwarf", "elf", "halfling"]
STARTING_CLASS         = "vagabond"
STARTING_LEVEL         = 1
BASE_SHOP_MAX_BP       = 2       // bp ≤ this is "basic" (base shop + run)
RUN_SHOP_SLOTS         = 6       // items stocked per run Shop node
RUN_PREMIUM_CHANCE     = ...     // odds a run-shop slot is premium/artifact (depth-scaled)
ENCOUNTER_LEVEL_OFFSET = 0       // global default offset for monster scaling
```

(Existing economy tunables — `SELL_RATIO`, `PRICE_PER_BP`, `LOOT_DEPTH_SCALE` — are retained; `LOOT_DEPTH_SCALE` becomes secondary to the band-level gold curve.)

---

## 10. Relationship to Existing Phases (point 6)

A11 is a **self-contained feature** that lands at three seams:

- **A4 (progression):** reinterpret stats as base; centralize per-level projection in `LevelScaler` (instances already scale — this just shares the math).
- **A6 (economy):** starting gold, reward curve, base-vs-run shop split, price audit.
- **A8 (run):** `EncounterGenerator` consumes `encounters.json` + `LevelScaler` + `EncounterSelector`. If A8 is not yet built, A11's encounter data and services stand alone and are exercised by a "quick battle" / test harness; A8 wires them into the node map.

It does **not** require reworking A1/A2 tooling, A3 combat math, or A7 AI. The class-tree engine changes (`class-tree-engine-changes.md`) remain a prerequisite for loading the monster classes/characters that encounters reference.

---

## 11. Out of Scope / Future Work

- Multi-wave / scripted / dialogue encounters (modifiers stay minimal).
- Non-combat encounter kinds beyond the reserved hooks (Event/Boon/Hazard remain A8's `events.json`).
- Per-item `shop_tier` field (bp-derived for now).
- Diminishing-returns scaling curves (linear for Alpha; `LevelScaler` is the seam).
- Meta-progression effects on starting gold/recruits (A10).

---

## 12. Requirements Traceability

| # | Requirement | Where addressed |
|---|-------------|-----------------|
| 1 | Encounter dataset; enemy band; `min_band_level` gate | §4, §4.2 |
| 2 | Character stats become **base stats** | §3.1, §8 |
| 3 | Level scaling: monster groups at player's level | §3.2, §3.4, §4.5 |
| 4 | Scaling simplifies balance | §3 (decision), §2 |
| 5 | Encounters define bands + conditions + optional map id | §4.2, §4.3 |
| 6 | Part of Alpha, separate from current pipeline | §1, §10 |
| 7 | Draft Human/Dwarf/Elf/**Halfling**; all start L1 Vagabond | §6 (refinement 1) |
| 8 | Band level = average of character levels | §3.3 |
| 9 | New band: 1 Human Vagabond L1 + 500 gp; recruit 50 gp | §5.1, §5.2, §9 |
| 10 | Reward ≈ 50 × band level; price balance vs 500 gp start | §5.3, §5.4, §9 |
| 11 | Band-screen base shop with all lower-tier equipment | §7.2, §7.4 |
| 12 | Run shops: limited, specialized, expensive; premium run-only | §7.3, §7.4 |
| R1 | Halfling re-included as draftable | §6, §9 |
| R2 | Level = Σ class levels; curve sets next-level thresholds (downstream-safe) | §3.5 |
| R3 | Dev/test tools to access & cheat the changes | §8.5 |
