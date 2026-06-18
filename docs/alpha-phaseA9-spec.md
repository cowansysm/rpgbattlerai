# Phase A9 — Content Expansion Specification

**Parent plan:** `alpha-implementation-plan.md` (Phase A9)
**Master spec:** `alpha-specs.md` (§12 Content Expansion & Authoring Pipeline)
**Builds on (Alpha):** A1 (map editor), A2 (CSV ↔ JSON pipeline + validation), A3 (`MAG`/`RES`, `mag_scaling`), A4 (job tree, `archetype`/`growth`/`jp_costs`/`prerequisites`), A0 (terrain effects), A6 (item `price`, loot/shop pools)
**Builds on (MVP):** `phase6` (content authoring), `phase1` (`Validator`, `DataPipeline`)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed) — *but this phase is primarily authoring, not engine code*
**Date:** 2026-06-17

---

## 1. Purpose & Scope

Phase A9 fills the Alpha with **enough content that builds feel deep and meaningful**: the full archetype **job tree** of classes, a broad **ability/spell** library, expanded **equipment** with prices, varied **character templates** and **name tables**, more **maps**, and a richer **terrain** set. It is the **parallel track** of the Alpha — it begins as soon as the pipeline (A2) and the schema (A3–A4) are stable and runs alongside A5–A8.

A9 is overwhelmingly **data authoring** done through the A2 CSV pipeline and the A1 map editor, plus a modest extension of the validator's referential checks to cover the larger graph of cross-references. **Balance tuning is A10** — A9 aims for breadth and structural correctness, with values as sane first drafts.

### In scope

- The **class job tree** across all archetypes (Support / Control / Physical·Melee·Ranged / Magical·Arcane·Divine), rooted at Vagabond, toward the §10 targets.
- The **ability/spell library** (physical skills, arcane/divine spells, control/support effects), authored against the A3 magical model (`mag_scaling`) with `jp_cost`s.
- **Equipment** expansion (weapons/armor/shields/accessories) with `bp_value` + `price` and class `equipment_access`; **consumables** for the economy.
- **Character templates** (race × recommended-path variety) and per-race **name tables**.
- **Maps** built in the A1 editor (varied terrain/elevation/size per tier) and an expanded **terrain** set using the A0 effect schema.
- **Loot/shop/event** content tables (the data A6/A8 systems consume).
- **Validation at scale**: extend referential checks so the larger content graph stays consistent.

### Out of scope

- **Balance tuning / playtest iteration** (Phase A10) — A9 sets first-draft values; A10 tunes them.
- **New engine systems** — A9 authors content for systems already built (A0–A8); the only code is validator referential extensions and any small authoring helpers.
- **New mechanics** (new effect types, new stats, new node kinds) beyond what A0–A8 defined; if content reveals a gap, it is scoped as a follow-up, not smuggled into A9.
- **Final art/audio** — placeholder visuals (procedural tokens/symbols) continue.

### Exit criteria

Phase A9 is complete when:

1. The **job tree** is authored end-to-end: Vagabond → tier-1 (Thief/Soldier/Adept) → advanced/elite classes across all archetypes, each with `archetype`/`branch`/`tier`/`growth`/`jp_costs`/`prerequisites`, meeting (or consciously re-scoping) the §10 class target.
2. The **ability library** covers each class's kit, authored against `MAG`/`RES`/`mag_scaling` and `jp_cost`, toward the ability target.
3. **Equipment** (with prices + class access) and **consumables**, **templates** + **name tables**, **maps** (per tier), and **terrain** entries meet their targets.
4. **Loot/shop/event** tables are authored and reference only real content.
5. The extended **validator passes** on the full set at boot and on CSV import — the job tree is rooted at Vagabond and acyclic, equipment access resolves, and loot/shop/event references resolve.
6. A run (A8) draws **varied** maps, enemies, and viable build options; an integration smoke test loads the whole library clean.

---

## 2. Design Decisions (Phase A9)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Author via the pipeline** | All non-map content is authored in spreadsheets through the A2 CSV ↔ JSON pipeline; maps via the A1 editor. | Volume authoring is the whole point of A1/A2; hand-editing JSON does not scale. |
| **Structure over balance** | A9 targets breadth and correct relationships (tree, access, references); numbers are sane drafts. | Balance is a dedicated pass (A10) against playtests; mixing the two stalls both. |
| **Blueprint-driven tree** | A documented job-tree blueprint (archetypes → classes → tier → prereqs) guides authoring; MVP classes fold in as advanced classes. | A shared map of the tree keeps authoring coherent and prevents orphan/duplicate jobs. |
| **Author to the A3 model** | Every spell carries `mag_scaling` and reduced flat values; heals scale where appropriate. | New content must use the post-A3 math, not the MVP "flat, ignore DEF" model. |
| **References validated** | The validator's referential pass is extended to the new cross-references; CSV import enforces it too. | Catches dangling ids early; the larger the library, the more this matters. |
| **Targets are tunable** | The §10 counts are goals, not contracts; re-scope consciously if needed. | Keeps A9 shippable; depth can grow post-Alpha. |

---

## 3. Class & Job-Tree Expansion

A9 authors the full tree rooted at Vagabond (A4 §6). The following is the **authoring blueprint** — an illustrative starting structure to be refined during authoring, not a fixed contract. MVP classes (Fighter, Archer, Barbarian, Rogue, Bard, Black/White/Red Mage) **fold in** as advanced classes.

| Archetype | Branch | Tier-1 root | Advanced (tier 2) | Elite (tier 3) |
|-----------|--------|-------------|-------------------|----------------|
| Physical Might | Melee | Soldier | Knight (tank), Berserker (← Barbarian) | Templar, Warlord |
| Physical Might | Ranged | Soldier | Archer, Ranger | Sharpshooter |
| Magical Might | Arcane | Adept | Black Mage, Elementalist | Sage, Necromancer |
| Magical Might | Divine | Adept | White Mage, Acolyte | Priest, Oracle |
| Control | — | Thief | Rogue, Trickster | Assassin |
| Support | — | Thief | Bard, Herald (← Red Mage hybrid) | Minstrel |

Each class declares `archetype`, `branch`, `tier` (`starting`/`tier1`/`advanced`/`elite`), `growth` (per-`StatKey` rates incl. `mag`/`res`), `equipment_access`, `granted_abilities`, `jp_costs` (per learnable ability), and `prerequisites` (character level and/or JP/level thresholds in predecessor classes). The tree must remain **rooted at Vagabond and acyclic**.

---

## 4. Ability & Spell Library

Authored to the §10 target, organized by archetype/class and built against the A3 model:

| Category | Examples | Notes |
|----------|----------|-------|
| **Physical skills** (`type: skill`) | Power Strike, Cleave, Aimed Shot, Backstab | ATK/DEF-based; no MAG. |
| **Arcane spells** (`type: spell`) | Fire/Ice/Thunder tiers, AoE bursts | `mag_scaling` ~1.0, reduced flat value, RES-mitigated (A3). |
| **Divine spells** (`type: spell`) | Cure tiers, Shield, Revive (item/ability) | Heals scale with `MAG` where authored; holy damage RES-mitigated. |
| **Control** (`effect_type: status`) | Sleep, Slow, Blind, Snare | Status + duration; debuff stacks. |
| **Support** (`effect_type: buff`) | Inspire, Haste, Guard | Stat buffs with duration. |

Every ability carries `ap`, optional `wp`/`wp_cost`, `range`, optional `area`, structured `effect`, `mag_scaling` (default per A3), and a `jp_cost` (referenced from the owning class). Effect types stay within the existing schema (damage/heal/status/buff); a genuinely new effect type is a scoped follow-up, not an A9 addition.

---

## 5. Items & Equipment

Expanded to the §10 target across slots, each with `bp_value` and `price` (A6) and gated by class `equipment_access`:

- **Weapons** — per branch (swords/axes/daggers for melee; bows/slings for ranged; staves/rods for casters), with `weapon_power`/`weapon_range`.
- **Armor** — Light/Medium/Heavy tiers (DEF, possible SPD trade-offs, `res` on some).
- **Shields** — DEF/block.
- **Accessories** — passive bonuses and item-bound abilities (e.g., Bracer of Accuracy, Phoenix Charm).
- **Consumables** — potions, ethers, antidotes, etc., as inventory items (A6) usable via the existing item path.

Prices are sane first drafts (A10 tunes); item-bound abilities reference real abilities.

---

## 6. Character Templates & Names

- **Templates** (~§10 target) spanning races (Human/Elf/Dwarf/Halfling) and recommended paths (a melee-leaning Human, an arcane-leaning Elf, etc.); all instances still start as **Vagabond** (A4) — `recommended_path` is flavor/guidance.
- **Name tables** (`data/names/<race>.json`) with enough given/surnames per race for varied generated identities.

---

## 7. Maps & Terrain

- **Maps** (~§10 target) authored in the **A1 editor**, saved in the A0 condensed format, varied in terrain/elevation and sized per tier (Skirmish/Standard/Large), with valid deployment zones.
- **Terrain** expanded using the A0 effect schema: more cover/slow/hazard/water variants (e.g., lava, spikes, bog, deep/shallow water, dense forest) with appropriate `move_cost`/`cover`/`blocks_los`/`damage_*`/`status_on_enter`/`occupant_modifiers`/`is_water`/`tags`.
- **Loot/shop pools** reference the expanded equipment/consumables; **events** (`data/events.json`) provide a small variety of Event/Boon/Hazard outcomes for A8.

---

## 8. Validation at Scale

The MVP/A2 validator is extended (referential layer) to keep the larger graph consistent:

- **Job tree:** prerequisites resolve to real classes; the tree is **rooted at Vagabond** and **acyclic**; `granted_abilities`/`jp_costs` reference real abilities.
- **Equipment access:** class `equipment_access` and template/instance equipment reference real items; weapon items have weapon fields.
- **Economy/run data:** loot pools, shop pools, and event outcomes reference real items/abilities/statuses.
- **Stats/effects:** stat keys (incl. `mag`/`res`) and effect types validate as before.

Validation runs at **boot** (`DataPipeline`) and on **CSV import** (A2), failing loud with precise, id-scoped errors.

---

## 9. Authoring Workflow

```
classes/abilities/items/templates/terrain : export CSV → edit in Sheets → import → validate → commit   (A2)
maps                                       : open the A1 editor → paint/save (condensed) → validate     (A1)
loot/shop/event tables                     : author JSON (or CSV where modelled) → validate             (A2/A6/A8)
```

The authored `data/*.json` remains the source of truth the game loads. A9 is iterative: author a slice, validate, load in-game, repeat. Numbers are first drafts; A10 owns balance.

---

## 10. Content Targets (from master spec §12.2)

Goals, not contracts — re-scope consciously:

| Content | MVP | Alpha target |
|---------|-----|--------------|
| Classes | 8 | ~20+ (Vagabond root → tier-1 → branches across all archetypes) |
| Abilities/spells | 14 | ~80+ |
| Items/equipment | 12 | ~50+ (incl. consumables) |
| Character templates | 8 | ~20+ |
| Maps | 6 | ~15+ (editor-built, per tier) |
| Terrain types | small set | expanded effectful set (A0) |
| Events | — | a small Event/Boon/Hazard table (A8) |

---

## 11. Risks & Notes

- **Pipeline/editor dependency.** A9 can't scale until A2 and A1 are solid; if either lags, authoring stalls — sequence accordingly.
- **Reference rot.** The more content, the more dangling-id risk; rely on the extended referential validation and run it often.
- **Balance creep.** Resist tuning during authoring; record balance concerns for A10 rather than fixing them ad hoc.
- **Tree coherence.** Without the blueprint, classes can duplicate roles or orphan; keep the blueprint authoritative and validate the tree shape.
- **Schema gaps.** If content wants something the schema can't express, scope a follow-up phase — don't quietly extend mechanics inside A9.
- **A3 conformance.** All new spells must use `mag_scaling`/`MAG`/`RES`; auditing a few ensures authors aren't reverting to MVP flat values.
- **Volume vs quality.** Hitting counts with bland content is a false win; aim for distinct, role-readable classes/abilities even at draft balance.

---

## 12. Phase A9 Deliverables Checklist

- [ ] Job tree authored across all archetypes (Vagabond → tier-1 → advanced/elite), MVP classes folded in; meets/re-scopes the class target (§3, §10).
- [ ] Ability/spell library authored against the A3 model (`mag_scaling`/`MAG`/`RES`) with `jp_cost`s (§4).
- [ ] Equipment (with `price` + class access) and consumables to target (§5).
- [ ] Character templates + per-race name tables to target (§6).
- [ ] Maps (editor-built, per tier, condensed) and expanded effectful terrain to target (§7).
- [ ] Loot/shop/event tables authored, referencing only real content (§7, §8).
- [ ] Validator referential checks extended (tree rooted/acyclic, access, economy/run refs); passes at boot and on CSV import (§8).
- [ ] Integration smoke test loads the whole library clean; an A8 run draws varied content with viable builds.
- [ ] Git tag `alpha-phaseA9-complete`.
