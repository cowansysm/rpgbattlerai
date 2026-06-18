# Phase A2 — Implementation Plan

**Source spec:** `alpha-phaseA2-spec.md`
**Master spec:** `alpha-specs.md` (§12)
**Builds on (Alpha):** `alpha-phaseA0-implementation-plan.md` (`Dev` autoload / `DevMenu` for the optional entry)
**Builds on (MVP):** `phase1-implementation-plan.md` (consolidated JSON, `DataFactory`, `Validator`, `DataPipeline`)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-06-17

---

## How to use this plan

Six **work groups** (A–F). Across groups: **A** (`EntitySchema`) unblocks everything; **B** (exporter) and **C** (importer) both need A and can be built in parallel; **D** (validation) hooks into C; **E** (runner + Dev Tools entry) wraps B–D; **F** (tests) trails B–E.

Each task lists a **done state**. Code stubs are Godot 4 / GDScript — drop-in starting points reusing existing classes (`Validator.*`, `DataFactory`, consolidated `data/*.json`).

> **Carry-over:** A2 reads/writes the same consolidated `data/*.json` the MVP loads, reuses the per-entity `Validator.validate_*` functions, and (optionally) `DataPipeline` for referential checks. The optional in-app entry hangs off A0's `DevMenu`.

---

## Group A — Entity Column Schemas

*Pure data/declaration. Unblocks B–D.*

### A1. `EntitySchema` definitions
- A declarative table per entity: ordered columns with `{name, path, mode, type}` where mode ∈ `SCALAR | DOTTED | JSON`.
- **Done:** every current field of each entity is covered by exactly one column rule.

```gdscript
# src/tools/entity_schema.gd
class_name EntitySchema
extends RefCounted

enum Mode { SCALAR, DOTTED, JSON }

# Column := {name: String, path: String, mode: Mode, type: String}  # type: "str"|"int"|"bool"
const STAT_KEYS := ["spd", "atk", "rng", "def", "hp", "jump", "wp"]   # + "mag","res" after A3

static func columns_for(entity: String) -> Array:
    match entity:
        "abilities": return _abilities()
        "classes":   return _classes()
        "items":     return _items()
        "characters":return _characters()
        "races":     return _races()
        "terrain":   return _terrain()
    return []

static func _abilities() -> Array:
    var cols: Array = [
        {"name":"id","path":"id","mode":Mode.SCALAR,"type":"str"},
        {"name":"name","path":"name","mode":Mode.SCALAR,"type":"str"},
        {"name":"type","path":"type","mode":Mode.SCALAR,"type":"str"},
        {"name":"ap","path":"ap","mode":Mode.SCALAR,"type":"int"},
        {"name":"wp","path":"wp","mode":Mode.SCALAR,"type":"int"},
        {"name":"range","path":"range","mode":Mode.SCALAR,"type":"int"},
        {"name":"area.shape","path":"area.shape","mode":Mode.DOTTED,"type":"str"},
        {"name":"area.radius","path":"area.radius","mode":Mode.DOTTED,"type":"int"},
        {"name":"effect.effect_type","path":"effect.effect_type","mode":Mode.DOTTED,"type":"str"},
        {"name":"effect.value","path":"effect.value","mode":Mode.DOTTED,"type":"int"},
        {"name":"effect.element","path":"effect.element","mode":Mode.DOTTED,"type":"str"},
        {"name":"effect.status_id","path":"effect.status_id","mode":Mode.DOTTED,"type":"str"},
        {"name":"effect.duration","path":"effect.duration","mode":Mode.DOTTED,"type":"int"},
        {"name":"effect.stat","path":"effect.stat","mode":Mode.DOTTED,"type":"str"},
        {"name":"source","path":"source","mode":Mode.SCALAR,"type":"str"},
    ]
    return cols
# _classes/_items/_characters/_races/_terrain follow the same shape (see spec §4).
```

### A2. Stat-dict column helper
- Generate `stats.<key>` (and later `growth.<key>`) DOTTED columns from `STAT_KEYS`.
- **Done:** stat columns are produced for every `StatKey`; adding a key adds a column.

### A3. Header ordering
- A stable column order per entity for clean diffs.
- **Done:** export header is deterministic.

---

## Group B — JSON → CSV Exporter

*Depends on A.*

### B1. Flatten one object
- Walk the schema; pull scalar/dotted values; JSON-encode JSON-mode fields; absent → blank.
- **Done:** a known entity flattens to the expected cells (tested in F1).

```gdscript
# src/tools/csv_exporter.gd
class_name CsvExporter
extends RefCounted

static func flatten(obj: Dictionary, cols: Array) -> PackedStringArray:
    var row := PackedStringArray()
    for col in cols:
        var v: Variant = _dig(obj, col["path"])
        if v == null:
            row.append("")                                  # absent → blank
        elif col["mode"] == EntitySchema.Mode.JSON:
            row.append(JSON.stringify(v))
        else:
            row.append(str(v))
    return row

static func _dig(obj: Dictionary, path: String) -> Variant:
    var cur: Variant = obj
    for part in path.split("."):
        if typeof(cur) != TYPE_DICTIONARY or not cur.has(part):
            return null
        cur = cur[part]
    return cur
```

### B2. Write the CSV file
- Header row from `cols`, then one flattened row per entity; use `FileAccess.store_csv_line`.
- **Done:** `data/csv/<entity>.csv` is produced for each table (terrain handled via id-from-key).

```gdscript
static func export_entity(entity: String, json_path: String, csv_path: String) -> void:
    var cols := EntitySchema.columns_for(entity)
    var arr := _load_as_array(entity, json_path)            # terrain: dict→array w/ id
    var f := FileAccess.open(csv_path, FileAccess.WRITE)
    var header := PackedStringArray()
    for c in cols: header.append(c["name"])
    f.store_csv_line(header)
    for obj in arr:
        f.store_csv_line(flatten(obj, cols))
```

---

## Group C — CSV → JSON Importer

*Depends on A. Parallel with B.*

### C1. Unflatten one row
- Rebuild the nested dict from cells per the schema; coerce types; blank → omit key; parse JSON cells.
- **Done:** a CSV row reconstructs the original object (tested in F1).

```gdscript
# src/tools/csv_importer.gd
class_name CsvImporter
extends RefCounted

static func unflatten(header: PackedStringArray, row: PackedStringArray, cols: Array) -> Dictionary:
    var obj: Dictionary = {}
    for col in cols:
        var idx := header.find(col["name"])
        if idx < 0: continue
        var cell := row[idx]
        if cell == "":                                       # blank → omit
            continue
        var val: Variant = _coerce(cell, col)
        _put(obj, col["path"], val)
    return obj

static func _coerce(cell: String, col: Dictionary) -> Variant:
    match col["mode"]:
        EntitySchema.Mode.JSON: return JSON.parse_string(cell)
        _:
            match col["type"]:
                "int":  return int(cell)
                "bool": return cell.to_lower() in ["1","true","yes"]
                _:      return cell

static func _put(obj: Dictionary, path: String, val: Variant) -> void:
    var parts := path.split(".")
    var cur := obj
    for i in range(parts.size() - 1):
        if not cur.has(parts[i]): cur[parts[i]] = {}
        cur = cur[parts[i]]
    cur[parts[parts.size() - 1]] = val
```

### C2. Read the CSV file
- Read header + rows via `FileAccess.get_csv_line`; unflatten each into an entity dict array.
- **Done:** a CSV parses into an array of entity dicts.

### C3. Write consolidated JSON (stable order)
- Emit the JSON array (or terrain keyed dict) with deterministic key order for clean diffs.
- **Done:** importing then exporting yields a byte-stable CSV (modulo intended edits).

---

## Group D — Validation Integration

*Hooks into C. Fail-closed.*

### D1. Per-row validation
- Run the matching `Validator.validate_*` on each unflattened dict; collect all errors with entity id/column context.
- **Done:** a malformed row yields a precise error; a clean set yields none.

```gdscript
static func validate_rows(entity: String, rows: Array) -> Array[String]:
    var errs: Array[String] = []
    for d in rows:
        match entity:
            "abilities":  errs.append_array(Validator.validate_ability(d))
            "classes":    errs.append_array(Validator.validate_class(d))
            "items":      errs.append_array(Validator.validate_item(d))
            "characters": errs.append_array(Validator.validate_character(d))
            "races":      errs.append_array(Validator.validate_race(d))
            # terrain: structural check of effect fields
    return errs
```

### D2. Atomic write
- Write the JSON only if `validate_rows` is empty; otherwise print errors and leave the file untouched.
- **Done:** invalid imports never modify `data/*.json`.

### D3. (Optional) referential pass
- After a successful structural import, run `DataPipeline` referential validation across the full set.
- **Done:** dangling references (e.g., class→missing ability) are reported.

---

## Group E — Runner & Dev Tools Entry

*Wraps B–D behind one interface.*

### E1. Headless `PipelineRunner`
- Parse `OS.get_cmdline_args()` after `--`; dispatch `export`/`import` for one entity or `all`.
- **Done:** the documented `godot --headless -s ... -- export all` / `import abilities` commands work.

```gdscript
# src/tools/content_pipeline.gd   (run via: godot --headless -s <this> -- <cmd> <entity>)
extends SceneTree

const ENTITIES := ["abilities","classes","items","characters","races","terrain"]

func _init() -> void:
    var args := OS.get_cmdline_args()
    var rest := args.slice(args.find("--") + 1) if args.has("--") else []
    var cmd := rest[0] if rest.size() > 0 else ""
    var who := rest[1] if rest.size() > 1 else "all"
    var targets := ENTITIES if who == "all" else [who]
    for e in targets:
        if cmd == "export": CsvExporter.export_entity(e, _json(e), _csv(e))
        elif cmd == "import": _import(e)
    quit()
```

### E2. Dev Tools buttons (optional)
- Add Export/Import actions to A0's `DevMenu`, calling the same exporter/importer.
- **Done:** dev users can run the pipeline in-app; hidden when the dev flag is off.

---

## Group F — Tests & Verification

*Round-trip is the core invariant.*

### F1. Per-entity round-trip tests (GUT)
- For each entity: load JSON → flatten all → unflatten all → assert semantic equality with the original.
- **Done:** green for abilities, classes, items, characters, races, terrain.

```gdscript
# tests/tools/test_csv_pipeline.gd
extends GutTest

func _round_trips(entity: String, json_path: String) -> bool:
    var original: Array = _load_array(entity, json_path)
    var cols := EntitySchema.columns_for(entity)
    var header := PackedStringArray()
    for c in cols: header.append(c["name"])
    for obj in original:
        var row := CsvExporter.flatten(obj, cols)
        var back := CsvImporter.unflatten(header, row, cols)
        if not _semantic_eq(obj, back):
            return false
    return true

func test_abilities_round_trip() -> void:
    assert_true(_round_trips("abilities", "res://data/abilities.json"))

func test_classes_round_trip() -> void:
    assert_true(_round_trips("classes", "res://data/classes.json"))
# items, characters, races, terrain ...
```

### F2. Malformed-import rejection (GUT)
- Feed a row with a bad stat key / missing required field; assert `validate_rows` returns errors and no file is written.
- **Done:** green.

### F3. Manual spreadsheet workflow check
- [ ] Export `abilities.csv`; open in Google Sheets; edit a value; re-export to CSV.
- [ ] Import the edited CSV; confirm the JSON updates and the game loads it.
- [ ] Import a deliberately broken CSV; confirm errors and that JSON is untouched.
- **Done:** checklist passes.

---

## Dependency Map

```
A (EntitySchema) ──┬──> B (exporter) ──┐
                   ├──> C (importer) ──> D (validation) ──┐
                   └───────────────────────────────────── ├──> E (runner + dev entry) ──> F (tests)
```

**Suggested first pass:** A1–A3 → B1–B2 and C1–C3 (parallel) → D1–D2 → E1 → F1–F2 → E2/D3/F3. Get a single entity (abilities) round-tripping end-to-end before generalizing.

---

## Phase A2 Definition of Done

- [ ] `EntitySchema` covers every field of all six content entities; stat columns generated from `StatKey` (A).
- [ ] `CsvExporter` flattens (scalar/dotted/JSON, blank=absent) and writes header+rows per entity (B).
- [ ] `CsvImporter` unflattens with type coercion and JSON-cell parsing into entity dicts (C).
- [ ] Consolidated JSON written with stable key order only after fail-closed validation (C3, D).
- [ ] Validation reuses `Validator.validate_*`; precise per-row errors; nothing written on failure (D).
- [ ] Headless `PipelineRunner` with `export`/`import` `<entity>`/`all`; optional Dev Tools entry (E).
- [ ] Per-entity round-trip tests + malformed-import rejection test green; manual spreadsheet workflow verified (F).
- [ ] Git tag `alpha-phaseA2-complete`.
