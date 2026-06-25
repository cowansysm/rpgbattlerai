# Phase A11 — Implementation Plan

**Source spec:** `alpha-phaseA11-spec.md`
**Master spec:** `alpha-specs.md` (§5–§8)
**Builds on (Alpha):** A4 (`InstanceStatResolver`, `growth`, levels), A5 (`BattleBand`, `Recruiter`, `BandPartyBuilder`, `SaveManager`, band screen), A6 (`Pricing`, `ShopService`, `LootRoller`), A8 (`EncounterGenerator` — consumes A11)
**Prerequisite:** `docs/class-tree-engine-changes.md` (numeric tiers / 6 archetypes / monster classes must load before encounter content resolves)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-06-24

---

## How to use this plan

Seven **work groups** (A–G):

- **A — Level scaling, base stats & leveling** is the foundation (incl. the Σ-class-levels level model); everything else assumes it.
- **B — Encounter data + selection** defines and validates encounters and picks/instantiates them at level.
- **C — Band start & economy** re-tunes starting gold, recruiting, and rewards.
- **D — Drafting** restricts recruitment to Human/Dwarf/Elf/Halfling L1 Vagabonds.
- **E — Shops (base vs run)** splits stock into base-shop and run-only premium.
- **F — Tunables, validation & tests** trails and locks the curves.
- **G — Dev & test tools** (dev-flag gated) make the changes accessible and cheatable for testing.

Each task lists a **done state**. A and B are the load-bearing pieces; C/D/E are largely data + service tweaks on A5/A6. A11 is a *feature*, not a rewrite — most code is new services plus targeted edits at the A4/A6/A8 seams.

> **Carry-over:** scaling reuses A4 `growth`; encounters are consumed by A8's `EncounterGenerator`; shops reuse A6 `ShopService`; recruiting reuses A5 `Recruiter`. If A8 isn't built yet, exercise B via a test harness / quick-battle (the data + services stand alone).

---

## Group A — Level Scaling & Base Stats

*Pure core. Unblocks B and the economy curve.*

### A1. `LevelScaler`
- Project a base stat block to a target level via class `growth`.
- **Done:** scaling a known base + growth to L1 returns the base; to L_n adds `round(growth × (n−1))` per stat.

```gdscript
# src/core/progression/level_scaler.gd
class_name LevelScaler
extends RefCounted

static func scale(base_stats: Dictionary, growth: Dictionary, level: int) -> Dictionary:
    var out: Dictionary = {}
    var n: int = max(0, level - 1)
    for k in StatKey.all_strings():
        out[k] = int(base_stats.get(k, 0)) + int(round(float(growth.get(k, 0.0)) * n))
    return out
```

### A2. Reinterpret character stats as base
- Treat `CharacterData` stats as the **L1 base**; document the semantics (no value change needed for L1 parity).
- Route `BattleUnit.from_character` (and monster spawns) through `LevelScaler` using the character's class `growth` and its `level`.
- **Done:** a legacy character at L1 has unchanged combat stats; the same character at L5 is scaled up.

### A3. Share the math with instances (A4)
- Refactor `InstanceStatResolver` to obtain its per-level projection from `LevelScaler` so instances and monsters scale identically.
- **Done:** an instance and a monster of equal base/growth/level resolve to equal scaled bases.

### A4. Band-level helper
- `BattleBand.band_level()` = `round(mean(character_level))`; `character_level` = sum of class levels.
- **Done:** a mixed-level band reports the correct average; updates on roster/level change.

```gdscript
# on BattleBand
func band_level() -> int:
    if roster.is_empty(): return 1
    var total := 0
    for ci in roster: total += ci.character_level()   # sum of class levels
    return int(round(float(total) / roster.size()))
```

### A5. Leveling & XP thresholds (refinement 2)
- `character_level()` = Σ class levels on `CharacterInstance`. `Leveling.next_threshold(character_level)` uses the level curve; `Leveling.grant_xp(ci, amount)` accrues to the **active class**, levels up on threshold crossings (respecting `level_max = 10`, discarding overflow per the class-switch rule), and recomputes derived values.
- **Done:** XP thresholds rise with total level; a level-up increments the active class; character/band level + scaled stats refresh afterward. (Contract enforced by tests in F2.)

```gdscript
# src/core/progression/leveling.gd
class_name Leveling
extends RefCounted

static func next_threshold(character_level: int) -> int:
    # one curve, keyed by Σ class levels (not per-class)
    return Constants.XP_CURVE_BASE * character_level * (character_level + 1)

static func grant_xp(ci, amount: int) -> void:
    ci.xp += amount
    while ci.active_class_level() < 10 and ci.xp >= next_threshold(ci.character_level()):
        ci.xp -= next_threshold(ci.character_level())
        ci.increment_active_class_level()             # → recompute level/stats downstream
    if ci.active_class_level() >= 10:
        ci.xp = 0                                      # overflow discarded until class switch
```

---

## Group B — Encounter Data & Selection

*Depends on A. Feeds A8.*

### B1. `EncounterData` + loader
- Typed resource for an encounter (`id, name, min_band_level, enemies[], map, level_offset, tags, modifiers, weight`); load `data/encounters.json` into a registry (plain dict like loot/shop pools, or `EntityRegistry`).
- **Done:** `encounters.json` loads into typed records.

```gdscript
# src/core/run/encounter_data.gd
class_name EncounterData
extends Resource

@export var id: String
@export var name: String
@export var min_band_level: int = 1
@export var enemies: Array = []        # [{character, count}]
@export var map_id: String = ""        # "" = pick from pool
@export var level_offset: int = 0
@export var tags: Array = []
@export var modifiers: Dictionary = {}
@export var weight: float = 1.0
```

### B2. Referential validation
- Extend the validator: `enemies[].character` resolves; `map_id` (if set) resolves; `min_band_level ≥ 1`; `count ≥ 1`; `weight ≥ 0`.
- **Done:** a dangling character/map id fails load and import (tested in F).

### B3. `EncounterSelector`
- Eligibility (`min_band_level ≤ band_level`), seeded weighted pick, instantiate enemies scaled to `clamp(band_level + level_offset, 1, MAX_LEVEL)`; resolve `map_id` or defer to the pool.
- **Done:** given a band level + seed, returns a deterministic enemy band (scaled) + map choice.

```gdscript
# src/core/run/encounter_selector.gd
static func select(band_level: int, rng: RandomNumberGenerator, reg, providers) -> Dictionary:
    var eligible := reg.all().filter(func(e): return e.min_band_level <= band_level)
    var pick := _weighted(eligible, rng)
    var lvl := clampi(band_level + pick.level_offset, 1, Constants.MAX_LEVEL)
    var enemies := []
    for entry in pick.enemies:
        for _i in range(int(entry["count"])):
            enemies.append(_spawn_scaled(entry["character"], lvl, providers))
    return {"enemies": enemies, "map_id": pick.map_id, "modifiers": pick.modifiers}
```

### B4. Modifier application (minimal)
- Apply the starter modifier set at battle setup: `enemy_buff` (stat block), `level_offset` (already in B3), `hazard_on`, reserved `victory`. Unknown keys ignored.
- **Done:** an encounter with `enemy_buff` produces buffed enemies; unknown modifiers are no-ops.

### B5. A8 hand-off (or harness)
- Wire `EncounterGenerator` (A8) to call `EncounterSelector`; if A8 is absent, add a dev/quick-battle entry that builds a match from a selected encounter.
- **Done:** a Battle resolves against an encounter-defined, level-scaled enemy band on the chosen map.

---

## Group C — Band Start & Economy

*Depends on A4 (band level). Data + A5/A6 tweaks.*

### C1. New-band seeding
- New band = roster `[Human Vagabond L1]`, gold `STARTING_GOLD (500)`, empty inventory.
- **Done:** creating a band yields exactly that state.

### C2. Reward curve
- `LootRoller` gold centered on `GOLD_PER_BAND_LEVEL × band_level` with variance; capital/loot scales similarly.
- **Done:** averaged over many rolls, L1≈50, L2≈100, L3≈150 gp.

```gdscript
# LootRoller (A6) — band-level gold
func roll_gold(band_level: int, rng: RandomNumberGenerator) -> int:
    var center := Constants.GOLD_PER_BAND_LEVEL * band_level
    return int(round(center * rng.randf_range(0.7, 1.3)))
```

### C3. Price audit
- Verify lower-tier gear (`bp ≤ 2`) sits ~20–160 gp; mid/premium ~180–650; artifacts ~700–1200 (audit `items.csv`, nudge values — not the `Pricing` formula).
- **Done:** a 500 gp start can buy a weapon + light armor + a recruit; premium gear costs several fights' income.

---

## Group D — Drafting (Human / Dwarf / Elf / Halfling, L1 Vagabond)

*Depends on A5's `Recruiter`.*

### D1. Race-gated recruit
- `Recruiter` offers only `DRAFTABLE_RACES` (Human/Dwarf/Elf/Halfling); produces a `STARTING_CLASS` (`vagabond`) instance at `STARTING_LEVEL` (1) of the chosen race for `RECRUIT_COST` (50) gp.
- **Done:** recruiting deducts 50 gp and adds a L1 Vagabond of a chosen ancestry.

### D2. Draft UI
- The recruit panel (band screen) lists the four ancestries; no class/level choice at recruit time.
- **Done:** the four ancestry options appear; the result is always a L1 Vagabond.

---

## Group E — Shops (Base vs Run)

*Depends on A6 `ShopService`.*

### E1. Stock partition
- Classify equipment: basic (`bp ≤ BASE_SHOP_MAX_BP`) vs premium (`bp ≥ 3`); restructure `shop_pools.json` into `base_shop` / `run_common` / `run_premium` / `run_artifact`.
- **Done:** pools load; base/premium partition is deterministic.

### E2. Base shop (band screen)
- Band-screen shop offers the full `base_shop` set + basic consumables via `ShopService`.
- **Done:** all lower-tier gear is buyable at base; no premium gear appears.

### E3. Run shop (node map)
- Run Shop nodes stock `RUN_SHOP_SLOTS` items: mostly `run_common`, `RUN_PREMIUM_CHANCE` (depth-scaled) of `run_premium`/`run_artifact`, plus a few basics; seeded by the run.
- **Done:** premium/artifact gear is only purchasable in run mode; stock is limited and varies by node.

---

## Group F — Tunables, Validation & Tests

### F1. Constants & data
- Add the §9 tunables to `constants.json`; author `data/encounters.json`; restructure `shop_pools.json`; price-audit `items.csv`.
- **Done:** data loads and validates at boot.

### F2. Scaling & band-level tests (GUT)
- `LevelScaler` parity at L1, correct projection at L_n; `band_level()` average; instance↔monster scaling agreement.
- **Done:** green.

```gdscript
# tests/core/progression/test_level_scaler.gd
func test_l1_parity():
    var base := {"atk": 10, "hp": 50}
    assert_eq(LevelScaler.scale(base, {"atk":0.6,"hp":1.6}, 1), {"atk":10,"hp":50, ...})

func test_scale_up():
    assert_eq(LevelScaler.scale({"atk":10}, {"atk":1.0}, 5)["atk"], 14)  # 10 + 4
```

### F3. Encounter tests (GUT)
- Validation rejects dangling character/map; selection respects `min_band_level`; enemies instantiate at the target level; determinism by seed.
- **Done:** green.

### F4. Economy tests (GUT)
- New-band state (1 Human Vagabond L1 + 500 gp, empty inventory); recruit costs 50 gp → L1 Vagabond; reward gold averages ≈ `50 × band_level`; base vs run stock partition.
- **Done:** green.

### F5. Manual checklist
- [ ] Create band → 1 Human Vagabond L1 + 500 gp; buy a starter kit at the base shop.
- [ ] Recruit only Human/Dwarf/Elf/Halfling; each arrives L1 Vagabond for 50 gp.
- [ ] An eligible encounter spawns level-matched monsters on its map; an over-level encounter is gated out at low band level.
- [ ] Win a fight → ~`50 × band_level` gold on average.
- [ ] Run shop shows limited stock incl. premium gear absent from the base shop.
- **Done:** checklist passes.

---

## Group G — Dev & Test Tools (dev-flag gated)

*Extends the A0 dev flag / Dev Tools menu. Off in player builds; no shipped-path impact.*

### G1. State cheats
- Dev-menu actions: set band gold; grant any item by id; set a character's per-class levels (recomputes character/band level); unlock all ancestries/classes for draft.
- **Done:** each cheat mutates state and the UI reflects it immediately.

### G2. Level / XP fast-forward
- Grant XP or levels to a character or the whole band (drives `Leveling`), and grant a lump of gold — so reward/price/scaling curves can be exercised quickly.
- **Done:** a tester reaches any band level / gold amount in seconds.

### G3. Encounter harness
- Force-spawn a chosen encounter by id (or a random eligible one) at a chosen band level, on its map, straight into a quick battle — bypassing the run node map.
- **Done:** any encounter launches and plays directly.

### G4. Scaling inspector
- Reuse `DebugReadout` to show a selected character's base stats, growth, level, scaled stats at the current level, and next-level XP threshold.
- **Done:** the scaling/level math is visible and verifiable in-engine.

> All gated by `Dev.enabled` (A0). No dev path affects player builds.

---

## Dependency Map

```
A (scaling + base stats + band level + leveling) ──┬──> B (encounters: data, validate, select) ──> A8 hand-off
                                                    ├──> C (band start, rewards, price audit)
                                                    ├──> D (drafting)
                                                    └──> E (shops base/run)
                                                                └──> F (tunables, validation, tests)
G (dev & test tools) ── wraps A–E (used throughout to exercise them) ──> F (manual checklist)
```

**Suggested first pass:** A1–A5 → F2 → G1–G2 (cheats early, to test the rest) → B1–B3 → C1–C3 → D1–D2 → E1–E3 → G3–G4 → B4–B5 → F1/F3/F4/F5. Lock scaling + level model (with tests) before encounters and economy ride on them; build the cheats early so every later group is testable.

---

## Phase A11 Definition of Done

- [ ] `LevelScaler` projects base stats by level via class `growth`; instances and monsters scale identically; L1 parity for legacy characters (A).
- [ ] `BattleBand.band_level()` = average character level; recomputed on change (A4).
- [ ] `character_level()` = Σ class levels; `Leveling` sets next-level XP thresholds from total level, levels the active class (cap 10, overflow discarded), and recomputes derived values (A5).
- [ ] `data/encounters.json` schema loads + validates (characters/map resolve, `min_band_level ≥ 1`); `EncounterSelector` gates by band level, weighted-picks, and instantiates enemies scaled to band level on the chosen/optional map (B).
- [ ] New band = 1 Human Vagabond L1 + 500 gp, empty inventory; recruit = 50 gp → L1 Vagabond of Human/Dwarf/Elf/Halfling (C1, D).
- [ ] Combat gold averages ≈ `GOLD_PER_BAND_LEVEL × band_level`; lower-tier prices balanced to the 500 gp start (C2, C3).
- [ ] Base shop stocks all lower-tier gear; run shops are limited with run-only premium/artifact stock (E).
- [ ] §9 tunables in `constants.json`; scaling/encounter/economy tests green; manual checklist passed (F).
- [ ] Dev-flag-gated tools: state cheats, level/XP & gold fast-forward, encounter harness, scaling inspector — all off in player builds (G).
- [ ] Git tag `alpha-phaseA11-complete`.
