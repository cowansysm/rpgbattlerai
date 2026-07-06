# Staged CSV Content — Import Findings & Follow-up

**Date:** 2026-07-06
**Status:** import mechanically solved. Adoption scoped as a design project —
see **`docs/content-redesign-spec.md`**.

> **Correction (2026-07-06):** an earlier revision of this doc claimed fresh characters would have
> "no basic attack" under the staged content. That is **wrong** — attack/move/defend/wait/use-item
> are intrinsic to the action economy (`TurnActions`), so an empty `granted_abilities` is fully
> combat-functional. The real reason adoption is non-trivial is that the staged content is a
> **wholesale redesign** (10-tier job tree, `adept` removed, full stat rebalance), not an expansion.
> The resolver analysis below remains accurate; treat the "no baseline attack" framing as superseded.

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

## Core issue (root cause)

Combat availability is computed by `AbilityResolver.all_abilities()`
(`src/core/combat/ability_resolver.gd`) from **three sources only**:

1. `unit.character.abilities` — for a `CharacterInstance` this equals its `ability_loadout`
   (`CharacterInstance.to_character_data()` sets `c.abilities = ability_loadout.duplicate()`).
2. the active class's `granted_abilities`.
3. equipped items' `granted_abilities`.

**The resolver never consults `jp_costs` or `learned_abilities`.** The sole progression→combat
bridge is: learn via JP → `learned_abilities` → manually slot (`set_loadout`) → `ability_loadout`.

Today this holds together because the baseline-ability contract implicitly lives in
`granted_abilities`: **all 146 current classes have non-empty `granted_abilities`** and **all 141
templates have an empty `abilities` field** — every unit's baseline (incl. `basic_strike`) comes
from its class. Fresh player instances work because their `vagabond` class grants a baseline.

The staged content **breaks this contract**: the 128 player classes have empty `granted_abilities`
(everything moved to `jp_costs`). Monsters keep their kit on `character.abilities` (140/160 staged
chars), so they still work — but the **20 playable templates** (all `vagabond`-rooted) have an
empty `abilities` field *and* a now-empty-granting class. With `generate()` seeding
`learned_abilities`/`ability_loadout` empty and **no auto-learn anywhere** (`learn_ability` /
`set_loadout` are only called from `band_management_scene.gd` and `dev_cheat_service.gd`), a freshly
recruited player character resolves to **zero usable abilities — not even a basic attack.**

Root cause: **there is no bridge for the starting/baseline state** between the JP-progression
model (`jp_costs`→learned→loadout) and the combat-availability model (`granted_abilities`). The
content moved the baseline out of `granted_abilities` without providing a replacement.

## Plan to resolve the underlying problems

**Phase 0 — Decide the baseline contract (design gate).** Pick the single source of truth for
"what a unit can do at any progression state." Three viable shapes:
- **(A) Content-only — keep a minimal `granted_abilities` baseline.** Populate each player class's
  `granted_abilities` with just the always-free baseline (e.g. `basic_strike`; class signature
  optional), leave the rest in `jp_costs`. **Zero engine change** — preserves the existing contract.
  *Recommended* as the lowest-risk fix; the learn-via-JP catalog still layers on top via loadout.
- **(B) Engine bridge — seed a starting loadout on generation.** Add a `starting_abilities` list to
  `ClassData` (or treat `jp_costs` entries with cost 0 as free) and have `CharacterInstance.generate()`
  seed `learned_abilities` + `ability_loadout` from it. Makes recruits battle-ready and gives a
  first-class "free/innate" concept, but touches progression + save migration + the band UI.
- **(C) Resolver bridge — surface free abilities innately.** Extend `AbilityResolver` to also include
  active-class `jp_costs` abilities whose cost is 0. Smallest resolver change, but blurs the
  granted-vs-learnable distinction and needs the content to mark free abilities with cost 0.

**Phase 1 — Implement the chosen baseline.** For (A): author baselines into `data/csv/classes.csv`
player rows. For (B)/(C): implement the engine change + `class_data.gd`/`data_factory.gd`/schema/
validator updates and save-migration defaults. Add a targeted unit test: a freshly generated
instance for every playable template resolves ≥1 offensive ability.

**Phase 2 — Battle-readiness for recruits (quality of life).** Regardless of Phase 0 choice, ensure
`Recruiter`/`generate()` produce a character that can act without manual band-UI setup: seed a
default `ability_loadout` from the available baseline. Guard the invariant in a test.

**Phase 3 — Re-run the import.** Restore the 787-ability library + keep the `Affinity.ELEMENTS`
addition (already landed), then `import abilities/classes/items/characters`; confirm 0 errors and a
clean boot (`~790 / 268 / 128 / 160`).

**Phase 4 — Reconcile the 148 tests** to the new canonical content:
`tests/core/data/test_full_library.gd` (128 — `test_every_class_has_granted_abilities` must accept
JP-only player classes), `tests/core/data/test_roster.gd` (14 — new stat mods / signatures),
`tests/core/combat/test_ability_resolver_all.gd` (5), `tests/core/ai/test_ai_planner.gd` (1). Where a
test encodes the old baseline contract, rewrite it against the Phase 0 decision rather than deleting.

**Phase 5 — Balance pass** on the expanded library (790 abilities / 268 classes): WP costs, JP costs,
tier gating, stat growth. Large, separate content effort — out of scope for making the import land.

**Exit criteria:** full suite green; every playable template yields a battle-ready unit with a basic
attack from a fresh recruit; boot loads the expanded content with 0 validation errors.

## Reproduce the import spike

```bash
git show 3cc9c9d:data/csv/abilities.csv > /tmp/abilities_old.csv
# merge live 91 + historical-only rows into data/csv/abilities.csv (see PR notes),
# then import in the GUT runtime (autoloads available; the -s pipeline script fails to
# compile standalone because it references the Constants autoload at parse time):
#   CsvImporter.import_entity("abilities" | "classes" | "items" | "characters")
```
