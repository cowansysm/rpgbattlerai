# Staged CSV Content — Import Findings & Follow-up

**Date:** 2026-07-06
**Status:** import mechanically solved; **full adoption deferred pending a gameplay-model decision.**

## Summary

`data/csv/` holds a larger content library than what ships in `data/*.json`:

| Entity | Live JSON | Staged CSV |
|--------|-----------|------------|
| abilities | 91 | 91 (see below) |
| classes | 146 | 268 |
| items | 46 | 128 |
| characters | 141 | 160 |
| races / terrain | 32 / 17 | 32 / 17 |

The staged classes/items/characters were authored against a **787-ability** library that was
reduced to 91 during A18 (`abilities.csv` shrank from 788→92 lines between commits `3cc9c9d`
and `c3c92a1`). As shipped, importing the surplus fails with ~1959 dangling-reference errors.

## What was solved (the mechanical import)

A scoped spike confirmed the surplus **can** be made to import and boot cleanly:

1. **Restore the ability library.** Merge the historical 787-ability CSV
   (`git show 3cc9c9d:data/csv/abilities.csv`) with the live 91 — keep the live versions where
   IDs overlap (they carry A16/A18/A19 tuning), append the ~699 historical-only rows. Result:
   ~790 abilities covering all 649 previously-dangling references.
2. **Extend the element set.** The historical content uses 6 elements A16 trimmed away:
   `poison, arcane, steam, alchemical, aether, sonic`. These were re-added to
   `Affinity.ELEMENTS` (`src/core/combat/affinity.gd`). Nothing declares affinity for them, so
   they resolve NEUTRAL (×1.0) — backward-compatible. **This change is retained** as a
   forward-enabler even though current content doesn't use it.

With those two changes, `import abilities/classes/items/characters` all pass with **0 errors**
and the boot pipeline loads `790 abilities / 268 classes / 128 items / 160 characters` clean.

The old engine blockers are **not** the issue: the n-tier class model already landed
(`class_data.gd tier:int`), and the `area.length`/`area.depth` question is moot (the schema
imports `area.shape`/`area.radius`; line/cone/ring shapes import without error).

## Why full adoption was deferred

The staged content encodes a **different ability-acquisition model** than the current game:

- The 128 player classes have **empty `granted_abilities`**; every ability (including
  `basic_strike`) lives in `jp_costs` — i.e. learn-via-JP. Monster classes keep fixed granted kits.
- `CharacterInstance.generate()` starts `learned_abilities = []` and `to_character_data()` sets
  `abilities = ability_loadout` (a subset of learned). So under the new content a **freshly
  generated player character has no baseline attack** until JP is spent — a gameplay regression.
- Stat modifiers / kits differ from the old classes (e.g. Fighter ATK/DEF/WP, vagabond/soldier/thief signatures).

Consequently 148 tests fail — all pinned to the old 146-class content. Making them green would
mean either masking the no-baseline-attack regression or adopting the new model wholesale.

## Remaining work to adopt the content (separate task)

1. **Decide the ability-acquisition model.** Either (a) adopt learn-via-JP and add code so fresh
   characters auto-learn a baseline attack (e.g. seed `learned_abilities`/loadout from the
   starting class's cheapest/`basic_strike` on `generate()`), or (b) populate `granted_abilities`
   for player classes in `classes.csv` to preserve current behavior.
2. **Re-run the import** (restore 787 abilities + keep the element change) and confirm 0 errors.
3. **Reconcile ~148 tests** (`tests/core/data/test_full_library.gd`,
   `tests/core/data/test_roster.gd`, `tests/core/combat/test_ability_resolver_all.gd`,
   `tests/core/ai/test_ai_planner.gd`) to the new canonical content.
4. **Balance pass** on the expanded library (790 abilities / 268 classes) — out of scope for the import.

## Reproduce the import spike

```bash
git show 3cc9c9d:data/csv/abilities.csv > /tmp/abilities_old.csv
# merge live 91 + historical-only rows into data/csv/abilities.csv (see PR notes),
# then import in the GUT runtime (autoloads available; the -s pipeline script fails to
# compile standalone because it references the Constants autoload at parse time):
#   CsvImporter.import_entity("abilities" | "classes" | "items" | "characters")
```
