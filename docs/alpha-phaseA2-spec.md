# Phase A2 — CSV ↔ JSON Content Pipeline Specification

**Parent plan:** `alpha-implementation-plan.md` (Phase A2)
**Master spec:** `alpha-specs.md` (§12 Content Expansion & Authoring Pipeline)
**Builds on (Alpha):** `alpha-phaseA0-spec.md` (`Dev` flag / Dev Tools menu for the optional in-app entry)
**Builds on (MVP):** `phase1-spec.md` (consolidated JSON, `DataFactory`, `Validator`, `DataPipeline`)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-17

---

## 1. Purpose & Scope

Phase A2 delivers the **content authoring pipeline**: a converter that exports the consolidated JSON content tables to **CSV** and re-imports edited CSV back to JSON, so the large Alpha content libraries (classes, abilities, items, character templates) can be authored in Google Sheets / Excel instead of hand-edited JSON. It is pure tooling — no gameplay change — and it unblocks the A9 content-expansion track.

The pipeline targets **human-authored content** only. The condensed, generated **map files** (A0) are produced by the map editor (A1), not this pipeline.

### In scope

- A **flattening convention** that maps the nested JSON entity schemas onto flat CSV columns losslessly.
- A declarative **per-entity column schema** describing how each field flattens (scalar / dotted-nested / JSON-encoded cell).
- A **JSON → CSV exporter** and a **CSV → JSON importer**, per entity type, runnable **headless**.
- **Validation on import** reusing the existing `Validator`; invalid content is rejected with precise errors and nothing is written.
- A tested **lossless round-trip** invariant.
- An optional in-app entry under the A0 Dev Tools menu.

### Out of scope

- Map files (condensed; owned by A1) — explicitly excluded from CSV.
- New content itself (Phase A9) — A2 provides the tool, not the library.
- New entity *types* or schema fields beyond what exists plus the Alpha-known additions (class archetype/growth/prereqs, ability `jp_cost`, item `price`); the schema table is the single point of extension.
- A spreadsheet-side plugin or live sync — the workflow is export → edit → import (file-based).

### Exit criteria

Phase A2 is complete when:

1. Each consolidated content table (`abilities`, `classes`, `items`, `characters`/templates, `races`, terrain) exports to a CSV with flattened columns.
2. Editing a CSV in a spreadsheet and importing it reproduces valid JSON the game loads unchanged.
3. The round-trip invariant holds per entity type: `csv→json(json→csv(x))` is semantically identical to `x` (order- and default-insensitive).
4. Import runs the existing `Validator`; a malformed row is reported with a precise, field-level error and **no file is written**.
5. The converter runs headless from a documented command; the optional Dev Tools entry invokes the same code.

---

## 2. Design Decisions (Phase A2)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **One CSV per entity type** | `abilities.csv`, `classes.csv`, `items.csv`, `characters.csv`, `races.csv`, `terrain.csv` — one row per entity. | Mirrors the consolidated-JSON-per-type layout; each sheet is independently editable. |
| **Declarative column schema** | A per-entity table declares each field's column(s) and flatten mode. The converter is schema-driven, not hand-coded per field. | New fields (Alpha class/ability/item additions) are added in one table; exporter and importer both read it. |
| **Three flatten modes** | **Scalar** (`key`), **dotted nested** (`effect.value`, `stats.atk`), **JSON cell** (arrays / open-keyed dicts encoded as a JSON snippet). | Fixed small nested objects stay human-friendly as columns; variable-length data stays lossless as JSON text. |
| **Stat dicts as dotted columns** | `stats.*` (and `growth.*`) get one column per `StatKey` value. | Bounded by the `StatKey` enum, so columns are stable and spreadsheet-friendly. |
| **Empty cell = absent** | A blank cell means the key is omitted (defaults apply on load); it is not written as `0`/`""`. | Preserves the JSON's "omit for default" semantics and round-trip fidelity. |
| **Validate before write** | Import builds row dicts, runs the matching `Validator.validate_*`, and writes the JSON array only if all rows pass. | Reuses the MVP validation layer; never produces broken content files. |
| **Source of truth stays JSON** | `res://data/*.json` remains what the game loads; CSV is an authoring convenience. | No runtime CSV dependency; the game is unaffected by the pipeline. |
| **Headless-first** | The converter is a GDScript runnable via `godot --headless -s`; the Dev Tools button calls the same functions. | Scriptable for batch/CI use; one implementation, two entry points. |

---

## 3. Flattening Convention

### 3.1 Modes

For each field, the column schema selects one mode:

- **Scalar** → a single column named for the key (`id`, `name`, `type`, `ap`, `wp`, `range`, `source`, `bp`, `power`, `slot`, `level`, …). Typed per schema (string / int / bool).
- **Dotted nested** → one column per known sub-key of a fixed nested object. Examples:
  - `effect.effect_type`, `effect.value`, `effect.element`, `effect.status_id`, `effect.duration`, `effect.stat`
  - `area.shape`, `area.radius`
  - `stats.spd`, `stats.atk`, `stats.rng`, `stats.def`, `stats.hp`, `stats.jump`, `stats.wp` (plus `stats.mag`, `stats.res` once A3 lands)
- **JSON cell** → a single column whose cell holds a JSON snippet, for variable-length arrays and open-keyed dicts:
  - arrays: `equipment_access`, `granted_abilities`, `classes`, `equipment`, `abilities`, `required_classes`, `prerequisites`, `tags`
  - open dicts: `jp_costs` (keyed by ability id), `derived_bonuses`, `passive`

### 3.2 Empty-cell semantics

A blank cell means **the key is absent** from the produced JSON object (so the loader's default applies). Exporting an absent key produces a blank cell. This makes export/import symmetric and avoids polluting JSON with explicit zeros/defaults.

### 3.3 Worked example — abilities

`fire_2` as JSON:

```json
{ "id": "fire_2", "name": "Fire 2", "type": "spell", "ap": 2, "wp": 5, "range": 4,
  "area": { "shape": "burst", "radius": 1 },
  "effect": { "effect_type": "damage", "value": 17, "element": "fire" }, "source": "class" }
```

flattens to a CSV row (header shown above it):

```
id,name,type,ap,wp,range,area.shape,area.radius,effect.effect_type,effect.value,effect.element,effect.status_id,effect.duration,source
fire_2,Fire 2,spell,2,5,4,burst,1,damage,17,fire,,,class
```

`fire_1` (no `area`) leaves `area.shape`/`area.radius` blank. A `status`-effect ability leaves `effect.value`/`effect.element` blank and fills `effect.status_id`/`effect.duration`.

### 3.4 Round-trip normalization

Equality is **semantic**, not byte-wise: key order is irrelevant, absent keys equal blank cells, and numbers compare by value. The importer emits JSON via a stable key order so committed files have clean diffs.

---

## 4. Per-Entity Column Schemas

Each entity has a schema entry listing its columns and modes. Indicative coverage (the schema table is authoritative and extended as fields are added):

| Entity | Scalar columns | Dotted columns | JSON-cell columns |
|--------|----------------|----------------|-------------------|
| **ability** | id, name, type, ap, wp, range, source, *(A3)* jp_cost | effect.*, area.*, *(A3)* mag_scaling.* | — |
| **class** | id, name, abbr, level_max, *(A4)* archetype, branch, tier | stats.*, *(A4)* growth.* | equipment_access, granted_abilities, required_classes, derived_bonuses, *(A4)* prerequisites, jp_costs |
| **item** | id, name, slot, bp, power, range, *(A6)* price | — | passive, granted_abilities |
| **character/template** | id, name, race, level, bp, *(A4)* recommended_path | stats.* | classes, equipment, abilities, *(A4)* name_tables |
| **race** | id, name, flavor | stats.* | — |
| **terrain** | id, move_cost, impassable, blocks_los, cover, los_height, damage_on_enter, damage_per_turn, is_water | status_on_enter.* | occupant_modifiers, tags |

> `terrain.json` is a keyed dict (id → props), not an array; the converter handles it as "key becomes the `id` column." All others are arrays of objects.

---

## 5. Converter Tooling

### 5.1 Components

- **`EntitySchema`** — the declarative column definitions (§4): for each entity, the ordered list of columns with `{name, path, mode, type}`.
- **`CsvExporter`** — reads a consolidated JSON file, flattens each object per the schema, writes a CSV (header + one row per entity) using Godot's `FileAccess.store_csv_line`.
- **`CsvImporter`** — reads a CSV (`FileAccess.get_csv_line`), unflattens each row into an entity dict (typed per schema), validates, and writes the consolidated JSON array (stable key order).
- **`PipelineRunner`** — the headless entry: dispatches `export <entity>` / `import <entity>` (or `all`).

### 5.2 Invocation

Headless, from the project root:

```bash
# export every content table to data/csv/*.csv
godot --headless -s res://src/tools/content_pipeline.gd -- export all
# import an edited sheet back to JSON (validated)
godot --headless -s res://src/tools/content_pipeline.gd -- import abilities
```

The optional **Dev Tools** entry (A0) exposes the same export/import actions as buttons; it is dev-only and shares the converter code.

### 5.3 File locations

CSVs live under `data/csv/` (a working area), separate from the authoritative `data/*.json`. CSVs may be committed for history or treated as transient — a project convention, not a runtime dependency.

---

## 6. Validation on Import

Import is **fail-closed**:

1. Unflatten each CSV row into an entity dict.
2. Run the matching `Validator.validate_*` (e.g., `validate_ability`, `validate_class`, `validate_item`, `validate_character`, `validate_race`, `validate_map`-style for terrain), including `validate_stat_keys` for stat columns.
3. Optionally run referential validation via `DataPipeline` against the full set (e.g., class `granted_abilities` resolve).
4. If **any** row fails, report every error with its entity id / column and write **nothing**.
5. Only on a fully clean set is the JSON file written.

This guarantees the importer never produces content that would fail at boot.

---

## 7. Workflow

```
export JSON → CSV  →  edit in Google Sheets / Excel  →  import CSV → JSON  →  validate  →  commit
```

The authored `data/*.json` remains the source of truth the game loads. CSV is the editing surface. Bulk authoring (A9) follows this loop; the map editor (A1) follows its own JSON path.

---

## 8. Risks & Notes

- **Lossy flattening.** The danger is a field that silently doesn't round-trip. Every entity type must have a round-trip test (§A2 exit #3); add a field → add it to the schema and the test.
- **CSV quoting.** Cells containing commas, quotes, or newlines (JSON-cell columns especially) must be quoted/escaped correctly. Use Godot's CSV helpers consistently for read and write.
- **Empty vs zero.** Treat blank as absent, not `0`/`false`; a stat genuinely set to `0` is rare but must be representable (decide a convention, e.g., explicit `0` is allowed and round-trips, blank means omitted).
- **Schema drift.** The CSV schema and the JSON/Resource/Validator schemas must stay in sync; treat the column-schema table as part of the data contract and update it with any field change.
- **terrain.json shape.** It is a keyed dict, not an array; the converter special-cases the id↔key mapping.
- **Validator form coverage.** Reuse the per-entity validators; if terrain validation is needed, ensure it covers the A0 effect fields.
- **Scope creep.** No maps, no live sync, no new content here — just a lossless, validated converter.

---

## 9. Phase A2 Deliverables Checklist

- [ ] `EntitySchema` declarative column definitions for ability, class, item, character/template, race, terrain (§4).
- [ ] Flattening convention implemented: scalar, dotted-nested, JSON-cell; stat dicts as `stats.*`; blank = absent (§3).
- [ ] `CsvExporter`: consolidated JSON → CSV (header + rows) per entity (§5).
- [ ] `CsvImporter`: CSV → unflattened dicts → validated consolidated JSON (stable key order) (§5, §6).
- [ ] Fail-closed validation reusing `Validator` (+ optional referential pass); precise per-row errors; nothing written on failure (§6).
- [ ] Headless `PipelineRunner` (`export`/`import` `<entity>`/`all`); optional Dev Tools entry sharing the code (§5.2).
- [ ] Per-entity round-trip tests proving `csv→json(json→csv(x))` semantic equality; malformed-CSV rejection test (§3.4, §6).
- [ ] A documented authoring workflow; a real edit made in a spreadsheet imports and loads in-game (§7).
- [ ] Git tag `alpha-phaseA2-complete`.
