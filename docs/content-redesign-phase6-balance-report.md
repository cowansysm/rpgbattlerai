# Content Redesign — Phase 6: Balance Metrics & Report

**Date:** 2026-07-06
**Status:** ✅ Metrics + report delivered. **No subjective balance-value tuning applied** — that is left for human review. One clearly-correct data-hygiene fix was applied (see §5).
**Branch:** `feature/content-redesign-phase6-balance` (off the content tip `feature/content-redesign-phase5-docs`).
**Scope:** quantitative sweep over the rebalanced content (268 classes, 790 abilities, 160 character templates), a written report with flagged outliers, and a prioritized tuning-recommendation list. **This is not a retune.**

---

## 1. Harness

`tests/helpers/balance_metrics.gd` (preload-accessed, no `class_name`) extends the Phase-3
AI-vs-AI sim (`tests/helpers/battle_sim.gd`). It:

- runs many **seeded** matches and aggregates: rounds-to-resolution (min/median/max), per-side
  win rate, AI ability-usage rate, max single-hit damage, one-shot frequency (unit downed in a
  single hit from full HP), capped/stalemate rate, turn-1-wipe rate, hard-error count, and
  passive-executed-as-action count;
- builds a **progressed player party** from the 20 playable-race templates. Each unit is run
  through the real progression path (`CharacterInstance` → level the Vagabond root to L3 →
  unlock + level the recommended-path tier-1 class → grant JP → learn a seeded handful of that
  class's **active** abilities → `set_loadout` → `BattleUnit.from_instance`), then scaled to
  `band + 2`;
- builds enemy squads from authored `data/encounters.json` (optionally level-scaled via
  `LevelScaler`), and also pits authored monster squads against each other for a reference
  baseline.

### Reproduce

Class cache must exist first on a fresh checkout (`godot --headless --editor --quit --path .`).
Then, from a temporary GUT test (deleted before commit):

```gdscript
const BM = preload("res://tests/helpers/balance_metrics.gd")
var bm := BM.new()
var mvm := bm.sweep_monster_vs_monster(1000, [1, 2, 4, 5, 7, 8], 4)      # 100 matches
var pve := bm.sweep_player_vs_encounters(5000, [1, 4, 8], 4, 3)          # per-band summaries
```

Seeds are fixed: MVM base `1000`; PvE base `5000` (per-party RNG derives from `seed * 7919`).
The stability smoke test uses bases `9001` / `9101`. Round cap = 40 (a match reaching round 41
is counted `capped`).

---

## 2. Headline metrics

### 2.1 Monster-vs-monster (reference baseline) — 100 matches, seeds from 1000

| metric | value |
|---|---|
| rounds min / median / max | 4 / 9 / 41 |
| side-A win rate / side-B win rate | 0.57 / 0.38 |
| capped (stalemate) rate | **0.05** |
| turn-1 wipe rate | 0.00 |
| AI ability-usage rate (of all offensive actions) | 0.34 |
| max single hit | 60 |
| one-shots from full HP | 1 |
| hard errors / passive-executed-as-action | 0 / 0 |

**Read:** the authored monster roster fights well. Fights resolve (median 9 rounds), the AI uses
abilities a third of the time, one-shots are rare, and there are no runtime errors or passive
mis-use. The 5% capped rate is the only mild concern (see §4, F3).

### 2.2 Progressed player party vs level-matched authored encounters

Party size 4, party level = `band + 2`, 3 matches per encounter.

| band | matches | player (A) win rate | rounds med | AI abil-use | max hit | one-shots | capped | errors |
|---|---|---|---|---|---|---|---|---|
| 1 | 12 | **0.00** | 5 | 0.55 | 27 | 0 | 0.00 | 0 |
| 4 | 30 | **0.00** | 4 | 0.69 | 42 | 3 | 0.07 | 0 |
| 8 | 12 | **0.00** | 4 | 0.71 | 47 | 5 | 0.00 | 0 |

**Read:** the player party **loses 100% of level-matched fights across every band.** This is the
single biggest balance finding. It is *not* a harness artifact — see the stat probe in §3.

---

## 3. Root-cause probe: player vs monster stat gap

Progressed player units are dramatically under-statted versus same-band authored monsters:

| unit | HP | ATK | DEF | SPD | MAG |
|---|---|---|---|---|---|
| human_fighter (progressed L3) | 43 | 8 | 5 | 6 | 3 |
| human_fighter (progressed L6) | 45 | 8 | 5 | 6 | 3 |
| elf_black_mage (progressed L3/L6) | 27 | 3 | 4 | 6 | 9 |
| **bat_swarm** (band-1 monster) | **50** | **13** | **8** | **10** | 0 |
| **goblin_soldier** (band-1/2 monster) | **58** | **14** | **8** | **10** | 0 |
| **dire_beast_maw** (band-5 monster) | **70** | **15** | **8** | **10** | 0 |
| **gargoyle_sentinel** (band-5 monster) | **80** | **8** | **15** | **8** | 0 |

Three compounding problems:

1. **Absolute stat deficit.** Band-1 monsters out-HP the progressed fighter (~50 vs 43), out-ATK
   it by ~60% (13 vs 8), and out-DEF it (8 vs 5). Against a mage (HP 27) a single monster hit is
   near-lethal.
2. **Speed deficit.** Monsters sit at SPD 10 while progressed players are SPD 6–8. Under
   alternating activation the faster side effectively gets more turns and strikes first — a large
   swing this content does not account for.
3. **Growth barely accumulates.** From L3→L6 the fighter's HP moves 43→45 (+2 total); the mage's
   HP is flat at 27. Player class `growth` rates (e.g. vagabond `hp:1.0`, squire `hp:1.6`) are far
   too shallow relative to the flat authored monster stat lines, so "leveling up" the party does
   almost nothing to close the gap (win rate stays 0% at band 4 and 8 despite higher party level).

Monster templates carry **flat authored stat blocks tuned as a group** (they beat each other 57/38
in §2.1), whereas players are assembled from race base-stats + thin class modifiers + negligible
growth. The two stat economies were never reconciled.

---

## 4. Flagged outliers

- **F1 — Player party loses 100% of level-matched fights (all bands).** Highest priority. Root
  cause in §3: absolute stat, speed, and growth deficits vs authored monsters. Degenerate:
  a level-matched encounter is unwinnable.
- **F2 — Monster SPD is uniformly 10; players 6–8.** Systematic initiative advantage for enemies
  under alternating activation. Contributes to F1 and to rising one-shot counts at higher bands
  (0 → 3 → 5 one-shots as band climbs, §2.2).
- **F3 — 5% of monster-vs-monster fights hit the round cap** (`rounds_max` 41). A minority of
  authored comps stalemate (likely high-DEF / low-ATK matchups such as gargoyle mirror). Not
  broken, but worth a look — the AI may lack a closer against tanky mirrors.
- **F4 — 178 abilities authored `type:"passive"` with empty `passive_kind`** leaked through the
  Phase-3 active/passive filter (which only checked `passive_kind`). They were learnable, sat in
  loadouts, and were enumerated as usable **no-op actions** (most have `ap:0`, `effect:null`).
  This is a data-hygiene bug, fixed in §5. It was inflating "wasted" player turns; fixing it
  raised the AI ability-usage rate in PvE (band-1 0.51→0.55) but did **not** move win rate — F1
  is a genuine stat-balance problem, not a loadout artifact.
- **No** turn-1 team wipes and **no** never-resolving (guard-tripped) matches were observed. No
  archetype threw runtime errors.

---

## 5. Fix applied (clearly-safe, uncontroversial)

**Passive-ability filter now also excludes legacy `type == "passive"` abilities.**

The Phase-3 hygiene fix filtered only on the A18 `passive_kind` field. 178 abilities in the
rebalanced content are authored with `type:"passive"` (innate traits, resist/boost/absorb, equip
proficiencies, stat-boost passives) but `passive_kind == ""`, so they slipped through and were
treated as usable actions — no-op turns for anyone who learned them, and they polluted the AI's
candidate list. Only 9 abilities use the newer `passive_kind`.

Rather than re-author 178 abilities' `passive_kind` (that mapping to reaction/support/movement is
subjective design work — see R5), the minimal, unambiguous fix hardens the **filter**:

- Added `AbilityData.is_active()` → `passive_kind == "" and type != "passive"`.
- Routed all four active/passive gate sites through it:
  - `AbilityResolver.resolve()` (gates `execute_ability` + the HUD ability menu),
  - `AbilityResolver.all_abilities()` — including the class-granted and equipment-granted loops,
    which previously had **no** passive filter at all (a second latent leak),
  - `AIPlanner._get_unit_abilities()` (all three source loops).

No behavior change for genuine active abilities. Regression-guarded by
`test_balance_smoke.test_progressed_units_build_with_active_loadouts` and covered by the existing
Phase-3 passive-hygiene test. Full `tests/core/combat` (438) and `tests/core/ai` (39) suites pass.

---

## 6. Prioritized tuning recommendations (for human review — NOT applied)

> All of the following are subjective balance-value changes and are intentionally left unapplied.

1. **R1 (highest) — Reconcile the player vs monster stat economy.** Level-matched fights must be
   winnable. Options, in rough order of surgical-ness:
   - Raise player class `base` stat modifiers and (especially) `growth` rates so a party at
     `band + 2` reaches parity. Target: HP/ATK/DEF within ~10% of same-band monsters, not ~40%
     behind. The near-flat growth (fighter +2 HP over 3 levels) is the clearest lever.
   - **Or** lower authored monster stat lines toward the player curve (bigger blast radius — the
     monster set is internally balanced at 57/38, so scaling it down uniformly preserves that).
   - Recommend re-running the §2.2 sweep after any change; target player win rate ≈ 0.5–0.65 at
     level-match, not 0.0.
2. **R2 — Address the SPD gap (F2).** Either lower monster SPD from the uniform 10 toward 7–9, or
   raise player SPD growth. The uniform monster SPD 10 is the most obvious single outlier and
   likely the cheapest high-impact change.
3. **R3 — Curb one-shots at higher bands (F1/F2 downstream).** One-shots climb 0→3→5 with band.
   Once R1/R2 land, re-measure; if still high, consider a per-hit damage cap as a fraction of
   target max-HP, or a small floor on player HP growth.
4. **R4 — Investigate the 5% monster stalemate (F3).** Identify which comps cap out (suspected
   high-DEF mirrors) and either tune those matchups or give the AI a tie-breaking closer (e.g.
   prefer chip damage / repositioning when no lethal line exists) so no fight relies on the cap.
5. **R5 — Author `passive_kind` on the 178 legacy `type:"passive"` abilities.** The §5 filter fix
   makes them safe (they no longer act), but they are also currently **inert** — a unit that
   "learns" `stoneskin` or `resist_fire` gets no benefit, because only `passive_kind`-tagged
   passives are wired into `PassiveDispatch` / `BattleUnit._apply_passive_modifiers`. To make this
   large passive library actually function, classify each into reaction/support/movement (or a new
   innate category) and give it a `trigger`/`modifier`. This is substantial design work, not a
   hygiene fix — hence a recommendation, not applied here.
6. **R6 — AI ability-usage in low bands.** Usage is ~0.34 in MVM and ~0.55–0.71 in PvE; healthy,
   but low-band monsters lean on basic attacks. Not a defect; monitor after R1/R2.

---

## 7. Test artifacts

- `tests/helpers/balance_metrics.gd` — the sweep harness (preload, no `class_name`).
- `tests/core/combat/test_balance_smoke.gd` — 3 **stability-only** invariant tests (matches
  terminate within cap, zero hard errors, zero passive-as-action, progressed loadouts are
  active-only). No balance thresholds asserted. Fast (small seeded sweeps).

Run per-directory (whole-suite teardown SIGABRT is a known engine issue, fires after the summary):

```bash
printf '{"dirs":["res://tests/core/combat/"],"include_subdirs":false,"prefix":"test_","suffix":".gd","should_exit":true,"log_level":1}' > gutcfg.json
godot --headless -s --path . addons/gut/gut_cmdln.gd -gconfig=res://gutcfg.json -gexit
rm -f gutcfg.json
```

Judge success by "Passing Tests == Tests" / "0 failures" in the summary, not the exit code.
