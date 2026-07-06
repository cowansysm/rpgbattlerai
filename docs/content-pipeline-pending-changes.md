# Content Pipeline — Pending Schema Change (abilities)

**Status:** ✅ OBSOLETE (2026-07-06). The AoE model was redesigned to `area.shape` + `area.radius` (both present in `entity_schema.gd`); the current `abilities.json`/`abilities.csv` use only `burst` shapes, so the proposed `area.length`/`area.depth` columns block nothing. Retained for historical context only.
**Owner:** needs a code change in `src/tools/entity_schema.gd` (planner cannot edit code).
**Date:** 2026-06-24 (superseded 2026-07-06)

## Why

`abilities.csv` now uses all four combat AOE shapes. The combat engine
(`src/core/combat/turn_actions.gd::_collect_affected_units`) reads:

| Shape   | Size key it reads | CSV column |
|---------|-------------------|------------|
| `burst` | `radius`          | `area.radius` ✅ already in schema |
| `ring`  | `radius`          | `area.radius` ✅ already in schema |
| `line`  | `length`          | `area.length` ⚠️ **not in schema yet** |
| `cone`  | `depth`           | `area.depth` ⚠️ **not in schema yet** |

The expanded `abilities.csv` adds two columns — `area.length` and `area.depth` —
and 14 `line` + 10 `cone` abilities use them. The CSV importer
(`csv_importer.gd::unflatten`) only reads columns that exist in
`EntitySchema.columns_for("abilities")`; any column **not** in the schema is
silently ignored. So until the schema is updated:

- Importing `abilities.csv` still succeeds (no errors).
- But `line`/`cone` abilities import with `area = {"shape": "..."}` and **no
  length/depth**, so at runtime they default to length/depth `1` (effectively a
  single-tile hit). Their `burst`/`ring` siblings are unaffected.

## The change

In `src/tools/entity_schema.gd`, function `_abilities()`, add the two columns
immediately after `area.radius`:

```gdscript
_col("area.shape", "area.shape", Mode.DOTTED, "str"),
_col("area.radius", "area.radius", Mode.DOTTED, "int"),
_col("area.length", "area.length", Mode.DOTTED, "int"),   # <-- add
_col("area.depth",  "area.depth",  Mode.DOTTED, "int"),   # <-- add
_col("effect.effect_type", "effect.effect_type", Mode.DOTTED, "str"),
```

No other code change is needed — the importer/exporter are both schema-driven, so
this makes `line`/`cone` round-trip correctly (export will also emit the two new
columns in this order).

## Verification after the change

1. `godot --headless -s res://src/tools/content_pipeline.gd -- import abilities`
   → expect "OK → data/abilities.json", 0 validation errors, 787 entries
     (768 base + 19 tier-7+ class capstones).
2. Re-export (`export abilities`) and confirm a clean round-trip
   (`area.length`/`area.depth` populated for line/cone rows).
3. Boot the game; `GameData` summary should report 787 abilities loaded.
