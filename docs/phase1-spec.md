# Phase 1 — Data Layer & Content Schema Specification

**Parent plan:** `rpg-implementation-plan.md` (Phase 1)
**Builds on:** `phase0-spec.md` (pipeline skeleton)
**Source spec:** `rpg-specs.md`
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Content pipeline:** JSON authored → Godot Resources at runtime
**Reference model:** Lazy lookup by ID
**Derived stats:** Computed in the data layer at load
**Validation:** Runtime only (fail-loud at load) + GUT tests
**Date:** 2026-05-29

---

## 1. Purpose & Scope

Phase 0 delivered a pipeline *skeleton*: a loader, a character-only validator, one Resource type, and the `GameData` autoload proving a single JSON file loads. **Phase 1 turns that skeleton into the complete data layer.** Every game entity in `rpg-specs.md` §9 — Character, Class, Race, Ability/Spell, Item/Equipment, Map — exists as a typed, loadable Resource; all sample content loads and validates; cross-entity references resolve correctly; and each character produces a fully **computed final stat block** (race + class modifiers and derived stats) ready for later phases to consume.

No rendering, movement, combat, or UI — those remain in later phases. Phase 1's product is data: correct, validated, queryable, and complete enough that Phase 2 (map) and Phases 4–5 (combat) can be built against real content.

### In scope

- Resource type definitions for all six entity kinds, with full schemas.
- Expansion of the loader/validator to cover every type, including **referential integrity**.
- **Lazy, ID-based reference resolution** via `GameData` accessors.
- **Derived-stat computation** at load (final stat block from raw stats + race/class modifiers + derived values).
- Authoring of all sample content from the spec (§6 roster, sample classes/races/abilities/items, and the constants/tier data).
- GUT tests covering schemas, references, and derived-stat math.

### Out of scope

- Map rendering and geometry consumption (Phase 2).
- Movement, range, LoS resolution (Phase 3).
- Combat loop, action economy, damage resolution (Phases 4–5).
- In-app content authoring / builder (deferred per spec §10).
- Standalone validation CLI and schema-reference docs (not this phase; runtime validation + tests only).

### Exit criteria

Phase 1 is complete when:

1. All six Resource types compile and load from JSON.
2. The entire sample roster (spec §6) plus its referenced classes, races, abilities, and items load and pass validation.
3. Validation fails loud on missing fields, type errors, out-of-range values, **and dangling references** (e.g., a character citing a non-existent class or item), naming the offending file and field.
4. `GameData` exposes lazy lookup accessors for every entity type, returning the correct typed Resource by `id`.
5. Each character resolves to a **computed final stat block** combining base stats, race modifiers, and class modifiers, with derived stats (Move, Jump/Climb, etc.) per spec §4.3.
6. GUT tests for schema loading, referential integrity, and derived-stat computation pass; the suite runs headless.

---

## 2. Design Decisions (Phase 1)

| Area | Decision | Rationale |
|------|----------|-----------|
| **Reference model** | **Lazy lookup by ID.** Resources store reference *IDs* as strings; consumers resolve them through `GameData` accessors when needed. | Keeps loading simple and order-independent (no load-time link graph), avoids stale object references, and keeps Resources serialization-friendly. |
| **Derived stats** | **Computed in the data layer** at load into a `StatBlock` with a **modifier stack**. Base values (race + class) are set at load; equipment passives and runtime modifiers are pushed/popped at runtime. Derived stats recompute from effective values. | Base derivation lives in one place; combat and UI query `effective()` for current values; the modifier stack handles all runtime changes uniformly. |
| **Stat keys** | **Enforced via `StatKey` enum.** All stat-keyed dictionaries validate keys against `StatKey`; unknown keys are rejected. | Single point of expansion; eliminates silent typo bugs in stat references. |
| **Ability effects** | **Structured `effect_type` sub-schema.** Each ability effect declares its type (`damage`, `heal`, `status`, `buff`) and is validated per-type at load. | Phase 5 can dispatch on `effect_type` without parsing a schema-less blob; new effect types are added to one table. |
| **Runtime state** | **`BattleUnit` skeleton** separates immutable authored data from mutable per-battle state. Defined in Phase 1 (skeleton only), used in Phase 3 (marker), fully populated in Phase 4. | Phase 4 has a defined, tested pattern for mutable state instead of inventing one from scratch. |
| **GameData** | **Thin facade** over per-domain `EntityRegistry` objects. Each registry handles loading + structural validation + storage; `GameData` orchestrates and exposes the public API. | Each registry is independently testable; `GameData` stays thin as phases add more entity types. |
| **Validation** | **Runtime only**, fail-loud at load, plus GUT tests. Includes referential-integrity checks, `StatKey` validation, and `effect_type` validation. | Lean; no separate tooling to maintain. Loud failures surface bad content immediately in dev. |
| **Source of truth** | JSON content under `data/` is authoritative; Resource classes mirror the spec schemas (§9). | One contract; schema and Resource fields change together. |

### 2.1 Lazy reference model — implications

- A `CharacterData` stores `classes: Array[String]`, `equipment: Array[String]`, `abilities: Array[String]` as **IDs**, not object references.
- Resolution happens on demand: `GameData.get_class(id)`, `GameData.get_item(id)`, `GameData.get_ability(id)`.
- **Referential integrity is still validated at load** even though references aren't linked: after all entities load, a validation pass confirms every referenced ID exists. Dangling references abort the load with a precise error. (Validating existence ≠ eagerly linking objects.)
- Load order does not matter: validation runs once everything is in the registry.

### 2.2 Derived-stat computation — model

At load, for each character:

1. Start from authored **base stats** (SPD, ATK, RNG, DEF, HP — iterated via `StatKey.KEYS`, not a hardcoded list).
2. Apply **race** modifiers (additive per `RaceData`).
3. Apply **class** modifiers (per each `ClassData` in `classes`; multiclass = sum/stack per a documented rule).
4. Produce the **base final stats** — these are the load-time derived values before any runtime modifiers.
5. Compute **derived stats** from the base final block per spec §4.3:
   - `Move = final SPD`
   - `Jump/Climb = floor(final SPD / 2) + 1` (+ class bonuses, e.g., Rogue)
   - Magic Power / Magic Defense folded into ability values / DEF for the MVP (no separate stat yet).

The computed base values are stored in a `StatBlock` that supports a **modifier stack** (see §5.1). At load the stack is empty, so effective values equal base values. Equipment passives and temporary modifiers (buffs, debuffs, situational bonuses) are applied at runtime through the modifier stack on `BattleUnit.stats` (see §5.1); they are not baked into the load-time derivation.

> **Multiclass stacking rule (MVP):** class modifiers are **additive** across all of a character's classes. Document this in the README; revisit when free-form multiclassing arrives (spec §10).

---

## 3. Entity Schemas

All schemas mirror `rpg-specs.md` §9 and extend it where Phase 1 needs more fields. JSON is authoritative; Resource classes are the typed mirror. References are stored as **string IDs**.

### 3.1 RaceData

```json
{
  "id": "elf",
  "display_name": "Elf",
  "stat_modifiers": { "spd": 0, "atk": 0, "rng": 0, "def": 0, "hp": -1, "magic_affinity": 1 },
  "flavor": "Nimble and attuned to magic."
}
```

Fields: `id`, `display_name`, `stat_modifiers` (per-stat additive ints, **keys validated against `StatKey`**), optional `flavor`.

### 3.2 ClassData

```json
{
  "id": "black_mage",
  "display_name": "Black Mage",
  "abbr": "B.Mage",
  "stat_modifiers": { "atk": 0, "def": 0 },
  "derived_bonuses": { "jump_climb": 0 },
  "equipment_access": ["staff", "robe"],
  "granted_abilities": ["fire_1", "ice_1", "thunder_1"]
}
```

Fields: `id`, `display_name`, `abbr`, `stat_modifiers` (**keys validated against `StatKey`**), optional `derived_bonuses` (e.g., Rogue's Jump/Climb bonus), `equipment_access` (item IDs), `granted_abilities` (ability IDs).

### 3.3 AbilityData

```json
{
  "id": "fire_2",
  "display_name": "Fire 2",
  "type": "spell",
  "ap_cost": 2,
  "range": 4,
  "area": { "shape": "burst", "radius": 1 },
  "effect": { "effect_type": "damage", "value": 7, "element": "fire" },
  "source": "class"
}
```

Fields: `id`, `display_name`, `type` (`spell` | `skill` | `item` | `passive`), `ap_cost`, `range`, optional `area` (`shape`, `radius`), `effect` (structured payload — see below), `source` (`class` | `item`). Phase 1 validates effect *structure*; combat (Phase 5) interprets *behavior*.

#### Effect sub-schema

The `effect` dictionary must contain an `effect_type` field selecting one of the known schemas defined in `rpg-specs.md` §9.3.1:

| `effect_type` | Required fields | Optional fields |
|---------------|----------------|-----------------|
| `"damage"` | `value: int` | `element: String` |
| `"heal"` | `value: int` | — |
| `"status"` | `status_id: String`, `duration: int` | `value: int` |
| `"buff"` | `stat: String` (valid `StatKey`), `value: int`, `duration: int` | — |

Validation rejects abilities with unknown `effect_type` values or missing required fields for the declared type. The `effect_type` is also exposed as a top-level field on `AbilityData` (`effect_type: String`) for fast dispatch without re-parsing the dictionary. New effect types are added to this table and the validation branch.

### 3.4 ItemData (equipment)

```json
{
  "id": "bracer_of_accuracy",
  "display_name": "Bracer of Accuracy",
  "slot": "accessory",
  "bp_value": 2,
  "passive": { "accuracy": 1 },
  "granted_abilities": []
}
```

Fields: `id`, `display_name`, `slot` (`weapon` | `armor` | `shield` | `accessory`), `bp_value`, optional `passive` (stat/effect bonuses), `granted_abilities` (item-bound ability IDs per spec §4.5). Weapons additionally carry a basic-attack profile (e.g., `weapon_power`, `range`).

### 3.5 CharacterData

```json
{
  "id": "human_archer",
  "display_name": "Human Archer",
  "race": "human",
  "classes": ["archer"],
  "level": 2,
  "bp": 13,
  "base_stats": { "spd": 3, "atk": 2, "rng": 2, "def": 1, "hp": 10 },
  "equipment": ["bow", "bracer_of_accuracy", "light_armor"],
  "abilities": []
}
```

Fields: `id`, `display_name`, `race` (RaceData ID), `classes` (ClassData IDs), `level`, `bp`, `base_stats` (**keys validated against `StatKey`**), `equipment` (ItemData IDs), `abilities` (extra AbilityData IDs beyond class/item-granted). The **final/derived** stat block is computed, not authored.

### 3.6 MapData (schema only this phase)

```json
{
  "id": "forest_clearing",
  "tier": "standard",
  "tiles": [
    { "q": 0, "r": 0, "elevation": 0, "terrain": "grass" },
    { "q": 1, "r": 0, "elevation": 2, "terrain": "trees" }
  ],
  "deployment_zones": { "playerA": ["0,0"], "playerB": ["8,0"] }
}
```

Phase 1 defines and loads/validates the `MapData` schema (axial `q,r`, `elevation`, `terrain`, deployment zones) but does **not** render or consume it geometrically — that's Phase 2. At load, each tile dictionary is converted into a typed `TileRecord` (defined in Phase 0) so all downstream consumers access tile properties through typed fields (`t.q`, `t.r`, `t.elevation`, `t.terrain`) rather than dictionary key parsing. `MapData.tiles` is `Array[TileRecord]`, not an array of raw dicts. Validation checks tile well-formedness, known terrain types, and that deployment-zone hexes exist in `tiles`.

### 3.7 Constants & tiers

`data/constants.json` (started in Phase 0) is finalized: `ELEV_BONUS`, `COVER_DEF`, `ROUT_THRESHOLD`, and the three tier definitions (Skirmish/Standard/Large with `bp_cap`/`min`/`max`). Exposed via the `Constants` autoload.

---

## 4. Loader & Validator (expanded)

### 4.1 Loader & Registries

Generalize the Phase 0 loader to load every content directory with a per-type factory that maps a JSON dict onto the matching Resource. Each entity type has its own **registry class** (e.g., `CharacterRegistry`, `ClassRegistry`, `RaceRegistry`) responsible for loading, structural validation, and storage. `GameData` is a thin **facade** that orchestrates: it instantiates registries, runs cross-entity referential validation after all registries load, then runs derivation. The public lookup-by-id API remains on `GameData` for consumer convenience, but each accessor delegates to the appropriate registry internally. This keeps each registry independently testable.

### 4.2 Validation passes

Validation runs in two passes so references can be checked after all entities exist:

1. **Per-entity (structural):** required fields present; correct types; values in range (e.g., HP > 0, `ap_cost` ≥ 0, BP ≥ 0); enums valid (`slot`, `terrain`, ability `type`/`source`); **all stat-keyed dictionaries** (`base_stats`, `stat_modifiers`) contain only keys present in `StatKey` — unknown keys are rejected with a precise error.
2. **Cross-entity (referential integrity):** every referenced ID resolves —
   - `character.race` → exists in `races`
   - each `character.classes[*]` → exists in `classes`
   - each `character.equipment[*]` → exists in `items`
   - each `character.abilities[*]` and `class.granted_abilities[*]` and `item.granted_abilities[*]` → exists in `abilities`
   - each `class.equipment_access[*]` → exists in `items`
   - each map `deployment_zones` hex → exists in that map's `tiles`

Any failure aborts the load (fail-loud) with a message naming the entity `id`, the field, and the offending value. Validation is pure/testable (operates on dictionaries + registries, no scene tree).

### 4.3 Derivation pass

After validation succeeds, a derivation pass computes each character's final stat block and derived stats (§2.2) and caches it for lookup.

---

## 5. GameData API (Phase 1 surface)

`GameData` exposes typed, lazy accessors. Indicative surface:

| Accessor | Returns |
|----------|---------|
| `get_race(id)` | `RaceData` |
| `get_class(id)` | `ClassData` |
| `get_ability(id)` | `AbilityData` |
| `get_item(id)` | `ItemData` |
| `get_character(id)` | `CharacterData` |
| `get_map(id)` | `MapData` |
| `get_final_stats(character_id)` | computed final stat block |
| `all_characters()` | collection for party-building/roster screens (Phase 7) |

Consumers resolve references themselves via these accessors (lazy model). `GameData` never mutates content after load.

### 5.1 Runtime state boundary: `BattleUnit` (skeleton)

Phase 1 defines a `BattleUnit` class as a **skeleton only** — no combat logic. This establishes the contract between authored data and runtime state early, before Phase 4 needs it:

- `character: CharacterData` — reference to the immutable authored data.
- `stats: StatBlock` — initialized from the character's load-time derived stats, with a modifier stack for runtime changes (equipment passives, buffs, debuffs). At load the stack is empty, so effective values equal base values.
- `position: Vector2i` — mutable; set at deployment.
- `current_hp: int` — mutable; initialized from `stats.effective(StatKey.HP)`.
- `ap_remaining: int` — mutable; reset each activation.
- `is_activated: bool` — mutable; tracks per-round activation.
- `team: String` — assignment at deployment.

**Contract:** Authored Resources (`CharacterData`, `ClassData`, etc.) are **never mutated** post-load. All per-battle mutable state lives on `BattleUnit`. Combat systems (Phases 4–5) operate on `BattleUnit` instances, not Resources.

Phase 3 uses `BattleUnit` for its placed marker demo, validating the pattern before Phase 4 depends on it.

---

## 6. Sample Content to Author

Phase 1 authors enough content to load the full §6 roster and everything it references:

- **Races:** Human, Elf, Halfling, Dwarf (modifiers per flavor).
- **Classes:** Archer, Black Mage, White Mage, Fighter, Barbarian, Rogue, Red Mage, Bard.
- **Abilities:** the spells/skills referenced (Fire 1/2, Ice 1, Thunder 1, Cure 1/2, Shield 1, Power Strike, Reckless Swing, Rage, Backstab, Inspire, Lullaby, etc.) plus item-bound ones (Smoke Bomb).
- **Items/equipment:** Bow, Bracer of Accuracy, Light/Medium Armor, Shield, Sword, Greataxe, Daggers, Rapier, Sling, Staff, etc., with `bp_value`s.
- **Characters:** all eight from §6, with `base_stats` matching the table.
- **Maps:** at least one valid `MapData` fixture per tier (geometry unused until Phase 2).
- **Constants:** finalized `constants.json`.

> Values are seeds from the spec; balancing them is Phase 9, not Phase 1. Phase 1 only requires that they load, validate, and derive correctly.

---

## 7. Testing (GUT, runtime validation)

Extend the Phase 0 suite:

- **Schema/load tests:** each entity type loads from a valid fixture into the correct Resource with expected field values.
- **Referential integrity tests:** a fixture with a dangling reference (e.g., character cites missing class/item) is rejected with a referential error; a clean set passes.
- **Structural validation tests:** missing required fields, bad enums, and out-of-range values each produce the expected error.
- **Derived-stat tests:** a known character's final stat block equals hand-computed expected values (base + race + class), and derived stats (Move, Jump/Climb, Rogue bonus) compute correctly; multiclass additive stacking verified.
- **Full-content smoke test:** loading the entire authored `data/` set succeeds with zero validation errors and the expected entity counts.

All tests run headless; suite green before Phase 1 is declared done.

---

## 8. Risks & Notes

- **Schema/Resource drift.** JSON schemas (spec §9 + §3 here) and Resource classes must move together; treat the spec as the contract.
- **Reference-existence vs linking.** Lazy model means references are validated for *existence* but not linked; consumers must go through `GameData`. Document this so later phases don't assume object links on the Resources.
- **Multiclass stacking ambiguity.** Additive stacking is the MVP rule; flag it for revisit when free-form multiclassing lands (spec §10).
- **Modifier stack complexity.** The MVP modifier stack is additive-only. Multiplicative modifiers, priority ordering, and stacking caps are deferred. Keep the `StatModifier` surface minimal; future complexity layers on top of the push/pop mechanism.
- **Map schema without consumption.** Loading/validating maps now (without rendering) risks schema assumptions that Phase 2 invalidates; keep `MapData` minimal and spec-aligned.
- **BattleUnit scope.** The `BattleUnit` skeleton in this phase has no combat logic — only the class definition and initialization. Resist adding turn management, damage, or AI behavior here.
- **Scope creep.** No combat/UI/rendering logic in Phase 1 — only data and the runtime-state pattern.

---

## 9. Phase 1 Deliverables Checklist

- [ ] Resource types defined for Race, Class, Ability, Item, Character, Map (§3).
- [ ] Loader generalized to all content directories with per-type factories (§4.1).
- [ ] Two-pass validation: structural + referential integrity, fail-loud with precise messages (§4.2).
- [ ] `StatKey` validation on all stat-keyed dictionaries; unknown keys rejected (§4.2).
- [ ] Ability `effect_type` validation against structured schemas (§3.3).
- [ ] Derivation pass producing each character's base final stat block + derived stats (§2.2, §4.3).
- [ ] `GameData` (facade) lazy accessors for every type + `get_final_stats` (§5).
- [ ] `BattleUnit` skeleton defined; instantiable from a loaded character (§5.1).
- [ ] Full sample content authored and loading clean (§6).
- [ ] `constants.json` finalized with tiers; exposed via `Constants`.
- [ ] GUT tests: schema, referential integrity, structural, derived-stat, effect-type, `BattleUnit`, full-content smoke (§7).
- [ ] Suite runs headless and is green.
- [ ] Git tag `phase-1-complete`.
