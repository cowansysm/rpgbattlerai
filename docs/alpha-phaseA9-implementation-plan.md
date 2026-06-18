# Phase A9 — Implementation Plan

**Source spec:** `alpha-phaseA9-spec.md`
**Master spec:** `alpha-specs.md` (§12)
**Builds on (Alpha):** A1 (map editor), A2 (CSV pipeline + validator), A3 (`MAG`/`RES`), A4 (job tree fields), A0 (terrain effects), A6 (item price, loot/shop)
**Builds on (MVP):** `phase6-implementation-plan.md` (content authoring), `phase1` (`Validator`, `DataPipeline`)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed) — *primarily authoring; code is limited to validator referential extensions and authoring helpers*
**Structure:** Authoring work groups, highly parallel; cross-group dependencies noted.
**Date:** 2026-06-17

---

## How to use this plan

Seven **work groups** (A–G). This phase is mostly **content authoring** through the A2 pipeline and A1 editor, so groups are batches of authored data plus one code group (F, validator). Across groups: **A** (classes/tree) anchors the structure; **B** (abilities) is referenced by A's `granted_abilities`/`jp_costs`; **C** (items), **D** (templates/names), **E** (maps/terrain) are largely independent; **F** (validation at scale) gates all authored data; **G** (integration) verifies the whole library.

Each task lists a **done state**. "Stubs" here are mostly **JSON shape examples** plus the one validator extension; the bulk of the work is authoring volume in spreadsheets/editor.

> **Carry-over:** author non-map content via A2 (`export → edit in Sheets → import → validate`), maps via the A1 editor (condensed save). All spells use the A3 model (`mag_scaling`/`MAG`/`RES`). The blueprint in spec §3 is the authoring map. Balance is **A10**, not here.

---

## Group A — Class Job Tree

*Anchors the content. Authored to spec §3 blueprint.*

### A1. Author tier-0/1 finalization + advanced classes
- Confirm Vagabond/Thief/Soldier/Adept (from A4) and author advanced classes per branch (Knight, Berserker, Archer, Ranger, Black/White Mage, Elementalist, Acolyte, Rogue, Trickster, Bard, Herald, …), folding in MVP classes.
- **Done:** advanced classes load with `archetype`/`branch`/`tier`/`growth`/`equipment_access`/`granted_abilities`/`jp_costs`/`prerequisites`.

```json
// data/classes.json — advanced class example
{ "id": "black_mage", "name": "Black Mage", "abbr": "BLM",
  "archetype": "magical", "branch": "arcane", "tier": "advanced",
  "stat_modifiers": { "mag": 4, "wp": 2 },
  "growth": { "mag": 1.4, "hp": 0.8, "wp": 1.0 },
  "equipment_access": ["staff", "robe"],
  "granted_abilities": ["fire_1", "fire_2", "ice_1", "thunder_1"],
  "jp_costs": { "fire_1": 100, "fire_2": 300, "ice_1": 100, "thunder_1": 100 },
  "prerequisites": { "level": 6, "classes": [["adept", 200]] } }
```

### A2. Author elite classes
- Tier-3 capstones per archetype (Templar, Warlord, Sharpshooter, Sage, Necromancer, Priest, Oracle, Assassin, Minstrel, …) with deeper prereqs.
- **Done:** elites load and gate on advanced-class prerequisites.

### A3. Tree coherence pass
- Verify the blueprint is fully realized: every archetype/branch covered, no orphan/duplicate roles, all rooted at Vagabond.
- **Done:** the authored tree matches the blueprint (or a consciously re-scoped version).

---

## Group B — Ability & Spell Library

*Referenced by A. Authored to the A3 model.*

### B1. Physical & control/support skills
- Author `skill`-type physical abilities and `status`/`buff` control/support abilities for the relevant classes.
- **Done:** skills/effects load and validate; no MAG on physical skills.

### B2. Arcane & divine spells (A3 model)
- Author `spell`-type abilities with `mag_scaling`, reduced flat `value`, RES-mitigation; divine heals scale with `MAG` where authored.
- **Done:** spells load; a spot-check confirms MAG/RES scaling (not MVP flat values).

```json
// data/abilities.json — A3-model spell
{ "id": "fire_3", "name": "Fire 3", "type": "spell", "ap": 2, "wp": 7, "range": 4,
  "area": { "shape": "burst", "radius": 1 },
  "effect": { "effect_type": "damage", "value": 6, "element": "fire" },
  "mag_scaling": 1.0, "source": "class" }
```

### B3. Coverage pass
- Ensure each class's `granted_abilities` exist and each ability has a `jp_cost` on its owning class; reach the ability target.
- **Done:** no class references a missing ability; counts meet/re-scope the target.

---

## Group C — Items & Equipment

*Independent.*

### C1. Weapons/armor/shields/accessories
- Author equipment per slot with `bp_value`, `price` (A6), and weapon fields; align with class `equipment_access`.
- **Done:** equipment loads; prices present; access references resolve.

### C2. Consumables
- Author consumable items (potions/ethers/antidotes/…) usable via the item path; priced for the shop.
- **Done:** consumables load and are buyable/sellable (A6).

---

## Group D — Templates & Name Tables

*Independent.*

### D1. Character templates
- Author ~target templates across races with `recommended_path` and recommended equipment (instances still start Vagabond).
- **Done:** templates load and validate; recruitment (A5) can generate from each.

### D2. Per-race name tables
- Author `data/names/<race>.json` with sufficient given/surnames.
- **Done:** generated instances get varied, race-appropriate names.

---

## Group E — Maps & Terrain

*Independent. Uses the A1 editor + A0 terrain.*

### E1. Expand terrain
- Add effectful terrain entries (lava/spikes/bog/deep+shallow water/dense forest/…) to `data/terrain.json` per the A0 schema.
- **Done:** terrain loads with effects; map editor palette shows them.

### E2. Author maps per tier
- Build maps in the A1 editor (varied terrain/elevation, valid zones), sized for Skirmish/Standard/Large, saved condensed; reach the map target.
- **Done:** maps load and render; the run map pool (A8) has tier-appropriate options.

---

## Group F — Validation at Scale

*The one real code group. Gates A–E.*

### F1. Extend referential validation
- Add checks: prerequisites resolve + tree rooted at Vagabond + acyclic; `granted_abilities`/`jp_costs` reference real abilities; equipment access/items resolve; loot/shop/event references resolve.
- **Done:** dangling/cyclic/orphan references produce precise errors; clean content passes.

```gdscript
# src/core/data/validator.gd  (referential additions, sketch)
static func validate_job_tree(classes: Dictionary) -> Array[String]:
    var e: Array[String] = []
    # every prerequisite class exists; "vagabond" is the only tier "starting"; no cycles
    for id in classes.keys():
        for pair in classes[id].prerequisites.get("classes", []):
            if not classes.has(pair[0]):
                e.append("class '%s' prereq references missing class '%s'" % [id, pair[0]])
    if _has_cycle(classes) or not classes.has("vagabond"):
        e.append("job tree must be acyclic and rooted at 'vagabond'")
    return e
```

### F2. Pipeline + boot integration
- Run the extended validation on CSV import (A2) and at boot (`DataPipeline`).
- **Done:** both paths enforce the new checks.

---

## Group G — Integration Verification

### G1. Full-library smoke test (GUT)
- Boot the pipeline with the entire authored library; assert clean load and target/structural invariants (tree rooted, counts within range).
- **Done:** green.

```gdscript
# tests/core/data/test_content_library.gd
extends GutTest

func test_library_loads_clean() -> void:
    var errors := DataPipeline.new().run("res://data")   # or the actual entry
    assert_eq(errors.size(), 0)

func test_tree_rooted_and_acyclic() -> void:
    assert_eq(Validator.validate_job_tree(_classes()).size(), 0)
```

### G2. Run variety check
- Play/simulate an A8 run; confirm varied maps/enemies and multiple viable build paths.
- **Done:** a run exercises diverse content without missing-reference errors.

### G3. Manual content review checklist
- [ ] Each archetype/branch has classes from tier-1 through elite; roles read distinctly.
- [ ] Spells use the A3 model; physical skills don't use MAG.
- [ ] Equipment access matches classes; consumables buyable.
- [ ] Templates cover races/paths; names vary.
- [ ] Maps span tiers with varied terrain; hazards/water/cover present.
- **Done:** review passes; balance concerns logged for A10.

---

## Dependency Map

```
A (classes/tree) ──┬─(refs)─> B (abilities) ──┐
C (items) ─────────┤                          │
D (templates/names)┤                          ├──> F (validation) ──> G (integration)
E (maps/terrain) ──┘                          │
(A1 editor + A2 pipeline enable all authoring) ┘
```

**Suggested first pass:** F1 (so authoring is validated as it lands) → A1 → B1–B2 → A2–A3/B3 in tandem → C, D, E in parallel → F2 → G. Author a vertical slice (one full archetype path + its gear/maps) end-to-end first to shake out the workflow.

---

## Phase A9 Definition of Done

- [ ] Job tree authored across all archetypes (Vagabond→tier-1→advanced/elite), MVP classes folded in (A).
- [ ] Ability library authored to the A3 model with `jp_cost`s; every class reference resolves (B).
- [ ] Equipment (priced, class-gated) + consumables to target (C).
- [ ] Templates + per-race name tables to target (D).
- [ ] Expanded effectful terrain + editor-built maps per tier to target; loot/shop/event tables authored (E, §7).
- [ ] Validator referential checks extended (tree rooted/acyclic, access, economy/run refs); enforced at boot and CSV import (F).
- [ ] Full-library smoke test green; an A8 run draws varied content with viable builds; manual content review passed (G).
- [ ] Git tag `alpha-phaseA9-complete`.
