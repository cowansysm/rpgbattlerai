# Phase A16 — Elemental Affinities & Critical Hits Specification

**Parent plan:** `roadmap-A11-onward.md` (sub-phase A16)
**Master spec:** `alpha-specs.md` (combat resolution); `feature-scan-and-competitive-analysis.md` (Part 3, #5)
**Builds on (Alpha):** A3 (magical resolution, `MAG`/`RES`, `mag_scaling`), A0 (terrain occupant modifiers feed affinity context)
**Builds on (content):** the expanded ability library (abilities already carry `effect.element`: fire / ice / lightning / dark / holy / …)
**Coordinates with:** A11 (imports the expanded element-tagged abilities; adds `area.length`/`area.depth` so AoE shapes carry their full footprint), A15 (projection ranges must include affinity/crit), A19 (facing crit synergy)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-30
**Status:** Draft v0.1

---

## 1. Purpose & Scope

Two baseline combat features are currently absent from the resolution math even though the data hooks exist:

- **Elemental affinities.** Damage abilities already declare an `element` (`data/abilities.json` → `effect.element`), but `CombatResolver.resolve_damage` ignores it — every element resolves identically. A16 adds a **weakness / resistance / immunity / absorb** model so element choice matters.
- **Critical hits.** No crit mechanic exists. A16 adds a defined crit chance and multiplier integrated into the damage path.

This phase is purely the **resolution-math layer**; it deliberately reuses the existing single- and multi-target application (`TurnActions._collect_affected_units`, already implemented for burst/line/cone/ring) and does not touch targeting, AoE collection, or the action economy.

> **Note on AoE:** multi-tile AoE *application* is already implemented in `turn_actions.gd`. The only outstanding AoE gap is the import schema (`area.length`/`area.depth`), which is owned by **A11**. A16 includes a verification test that line/cone abilities, once imported with full footprints, resolve damage on every collected tile — but adds no new AoE code.

### In scope

- An **affinity model**: `Affinity { WEAK, NEUTRAL, RESIST, IMMUNE, ABSORB }` with tunable multipliers (e.g., weak ×1.5, resist ×0.5, immune ×0, absorb → heal). Affinities are authored **per source** (race base, class, equipment, terrain occupant, and/or status) and stack into an effective per-unit, per-element affinity resolved at hit time.
- **Element-aware damage**: `resolve_damage` applies the target's effective affinity for the ability's element after the base formula, before the `max(1, …)` floor (absorb bypasses the floor to heal).
- **Critical hits**: a crit roll with `CRIT_CHANCE` (base, tunable; modifiable by stats/facing later), `CRIT_MULT` damage multiplier; crits surface in the result dict (`is_crit`) for log/visual.
- **Data plumbing**: new authored fields on `RaceData`/`ClassData`/`ItemData` and `terrain.json` (`affinities: {element: tier}`), loaded by `DataFactory`/pipeline and validated.
- **Projection support**: extend the math so A15's `OutcomeProjection` can report affinity-adjusted ranges and the crit-inclusive `max`.

### Out of scope

- New AoE/targeting code (already present; schema columns owned by A11).
- Status-effect interactions beyond an optional element→status hook (e.g., ice-on-water → slowed) — minimal/forward-noted, not required.
- Authoring the full affinity tables for all 32 races / 268 classes (A9/A11 content task); A16 ships a small seeded set + the engine to read it.
- Reaction/counter on crit (A18).

### Exit criteria

1. A damage ability's `element` is read at resolution; the target's **effective affinity** scales the result (weak amplifies, resist reduces, immune nullifies, absorb heals).
2. Affinities **stack additively across sources** (race + class + equipment + terrain + status) into one effective tier per element, resolved deterministically.
3. **Critical hits** occur at `CRIT_CHANCE`, multiply damage by `CRIT_MULT`, and are flagged in the result for log/visual.
4. The result dict exposes `element`, `affinity`, `is_crit`, and the pre/post-affinity damage for telegraph and logging.
5. New authored affinity fields load and validate; absent fields default to **NEUTRAL** (full backward compatibility with current content).
6. A15 projection reflects affinity and crit (range `max` includes a crit).
7. Tests cover each affinity tier, multi-source stacking, crit application/flagging, the absorb→heal path, the neutral-default backward-compat path, and the AoE-per-tile resolution verification.

---

## 2. Design Decisions

- **Affinity is the target's property; element is the ability's property.** Resolution looks up `target.effective_affinity(element)`.
- **Order of operations:** `base = formula(...)`; `scaled = round(base × affinity_mult)`; apply crit (`× CRIT_MULT` on hit); then Defend die; then `max(1, …)` (except ABSORB, which converts the scaled amount to healing and skips the floor).
- **Stacking:** sum signed tier weights per source (e.g., resist −1, weak +1) → clamp to a tier band → map to a multiplier. Keeps "weak armor on a resistant race" expressible and deterministic.
- **Determinism:** the crit roll uses the same injected dice/RNG path as the attack roll so headless tests and the A8 seed remain reproducible; `AIScorer`/projection use crit *expectation* for the midpoint and crit-inclusive bounds for min/max.
- **Backward compatibility:** all new fields optional; missing → NEUTRAL / no crit-modifier, so existing content and tests pass unchanged.

---

## 3. Files

**New:**
- `src/core/combat/affinity.gd` (`Affinity` enum + multiplier table + stacking helper).

**Modified:**
- `src/core/combat/combat_resolver.gd` — element/affinity scaling + crit in `resolve_damage` (and absorb→heal); enrich result dict.
- `src/core/data/battle_unit.gd` — `effective_affinity(element)` resolved from sources.
- `src/core/data/{race_data,class_data,item_data,terrain_props}.gd` + `data_factory.gd` — load `affinities`.
- `src/core/data/validator.gd` — validate affinity element keys/tiers.
- `data/constants.json` — `AFFINITY_MULT` table, `CRIT_CHANCE`, `CRIT_MULT`.
- (Coordination) A15 `outcome_projection.gd` — affinity/crit-aware bounds.

---

## 4. Test Plan

- Weak/neutral/resist/immune/absorb each produce the expected scaled value at a fixed roll.
- Multi-source stacking resolves to the correct effective tier.
- Crit applies the multiplier and sets `is_crit`; non-crit path unchanged.
- Absorb converts to healing and ignores the damage floor.
- Neutral-default path reproduces current `resolve_damage` numbers exactly (regression guard).
- Imported line/cone abilities resolve on every collected tile (AoE verification, depends A11 schema).
