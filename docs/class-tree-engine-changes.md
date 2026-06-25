# Class Tree — Required Engine Changes (n-tier model)

**Status:** required before `import classes` will validate/import the new 128-class `classes.csv`.
**Owner:** code changes in `validator.gd`, `entity_schema.gd`, `class_data.gd`, and the progression/unlock layer (planner cannot edit code).
**Date:** 2026-06-24

The new `data/csv/classes.csv` authors **128 classes** under a redesigned model that the
current A4/A9 validator does **not** accept. Importing it today will fail validation. The
changes below make it valid. (The CSV itself is structurally self-consistent: 0 dangling
ability/item/class references, 7 abilities per class, prerequisites strictly lower-tier.)

## Model summary (what the data now expresses)

- **Numeric, n-determinant tiers.** `tier(C)` = the number of classes in C's *transitive
  prerequisite closure* (all ancestors). Tier 0 = the single root (`vagabond`). The authored
  data spans tiers **0–9**. Tiers grant no inherent bonus; they only measure unlock depth.
- **6 archetypes:** `physical_attack`, `physical_defense`, `magical_attack`,
  `magical_defense`, `support`, `control`.
- **Prerequisites are class-LEVELS in lower-tier classes.** `prerequisites.classes` is a list
  of `[class_id, level]` where `level ∈ 1..10`. No prerequisite ever references an equal- or
  higher-tier class (guaranteed by the closure definition).
- **`level_max = 10`** for every class. (Character level = sum of class levels — engine-side.)
- **7 learnable abilities per class** via `jp_costs`; cost scales with tier
  (~`30 + tier*25`, spread ×0.6–1.6). `granted_abilities` is empty for all (field unused).

## 1. `src/core/data/validator.gd`

- **`TIERS` const** — currently `["starting","tier1","advanced","elite"]`. Replace the tier
  check (`validate_class`, ~line 71) with: tier must be a **non-negative integer**.
- **`ARCHETYPES` const** (~line 16) — replace with the 6 values above (keep `""` allowed if
  desired for safety). Update the `validate_class` archetype check accordingly.
- **`validate_job_tree`** (~lines 350–458) — the tier-consistency section is hardcoded to the
  4-tier model (single `starting` root; `tier1` = level-only; `advanced` requires a `tier1`;
  `elite` requires an `advanced`). Replace with the n-tier rule:
  - The root set = classes with **no** `prerequisites.classes` (the player root `vagabond`
    **plus all 140 monster classes** — see "Monster classes" below). Allow multiple roots;
    do not require a single starting class.
  - For every class, **each prerequisite class must have a strictly smaller tier**.
  - Recommended: have the validator **derive** `tier` as the closure size and assert the
    authored `tier` matches (catches authoring drift).
  - Keep cycle detection and reachability (all classes remain reachable since prereqs are
    level-based — a character can always level a prerequisite class).

## 2. `src/core/data/class_data.gd`

- `@export var tier: String = "starting"` → `@export var tier: int = 0`.

## 3. `src/tools/entity_schema.gd`

- In `_classes()`, change the `tier` column type from `"str"` to `"int"`:
  `_col("tier", "tier", Mode.SCALAR, "int")`. (No new columns — `prerequisites` and
  `jp_costs` already round-trip as JSON cells.)

## Monster classes (140) — `granted_abilities` paradigm

`classes.csv` now contains **268** classes: the **128 player classes** plus **140 monster
classes** (5 per monster race × 28 races, ids like `goblin_soldier`, `minotaur_berserker`).
Monster classes differ from player classes:

- **Standalone roots:** `tier = 0`, `prerequisites = {}`, `required_classes = []`. They are not
  part of the Vagabond job tree; a monster character simply *is* its monster class.
- **Innate kit via `granted_abilities`:** each monster class lists **5** abilities in
  `granted_abilities` (its known kit) and has **empty `jp_costs`** — the opposite of player
  classes (which use `jp_costs` and leave `granted_abilities` empty). The combat/instance
  layer should treat a class's `granted_abilities` as abilities the unit knows innately
  (no JP spend required), in addition to anything learned via `jp_costs`.
- **No equipment:** `equipment_access = []` (monsters fight with innate abilities).
- They carry archetype stat_modifiers + growth like player classes, so a monster's combat
  profile = race `base_stats` + monster-class modifiers + growth.

Validation impact: the job-tree validator must (a) allow many tier-0 roots, and (b) **not** flag
`granted_abilities` on monster classes as an error (granted abilities still reference-check
against the ability registry, which they pass).

## 4. Progression / unlock layer (CharacterInstance & class-switching)

The prerequisite semantics changed from the A4 model (JP thresholds + character level) to
**per-class levels**. Wherever class-unlock eligibility is evaluated:

- Interpret `prerequisites.classes` `[class_id, level]` as "needs ≥ `level` **levels** in
  `class_id`" (not JP).
- Enforce `level_max = 10` per class; **XP gained at class level 10 is discarded** until the
  character switches active class.
- Character level = **sum of class levels** (display/derived only).

## Verification after the changes

1. `godot --headless -s res://src/tools/content_pipeline.gd -- import classes`
   → expect "OK → data/classes.json", 0 validation errors, 128 entries.
2. Boot: `GameData` summary reports 128 classes; job-tree validation passes (acyclic, all
   prereqs lower-tier, single root `vagabond`).
3. Re-export and confirm clean round-trip.
