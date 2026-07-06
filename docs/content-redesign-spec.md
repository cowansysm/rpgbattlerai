# Content Redesign — Adopt the Expanded 10-Tier Library (Design Project)

**Date:** 2026-07-06
**Status:** SCOPED — approved as a deliberate design initiative (not an import fix). Multi-session.
**Depends on:** the import-enabler work already merged (`docs/content-import-followup.md`,
`Affinity.ELEMENTS` extension).

## Decision

Adopt the staged `data/csv/` library as the game's new canonical content: a **10-tier job
tree**, an **expanded ability library (~790)**, **128 player + 140 monster classes**, **160
characters**, and **128 items** — replacing the current 4-tier / 91-ability / 146-class design.
This is a rebalance and progression overhaul, so it is run as a design project with review
gates, not a mechanical import.

## Why this is a redesign, not an expansion

Confirmed by inspecting the staged CSVs after a clean spike import:

| Dimension | Current (live) | Staged (target) |
|-----------|----------------|-----------------|
| Job-tree tiers | 4 (starting/tier1/advanced/elite) | **10** (numeric 0–9) |
| Tier-1 classes | Thief / Soldier / Adept | **squire, footman, apprentice, acolyte, page, cutpurse, tinker, slinger** |
| `adept` | exists | **removed** |
| soldier / thief | tier 1 | **tier 2** |
| Unlock rule | JP thresholds / level-3 branch | **level-gated class chain** (`prerequisites: {"classes": [["vagabond", 3]]}`) |
| Ability acquisition | mostly class `granted_abilities` | player classes **empty granted**, all via `jp_costs` (learn-via-JP) |
| Abilities | 91 | **~790** (699 restored from the pre-A18 library) |
| Classes | 146 | **268** (128 player + 140 monster) |
| Characters | 141 | **160** (20 playable + 140 monster/NPC) |
| Items | 46 | **128** |
| Class stat mods / growth | current balance | **rebalanced** (e.g. vagabond loses atk/def mods) |

The mechanical import is already proven to boot clean (see `content-import-followup.md`): restore
the 787-ability library + keep the 6 re-added elements → `import abilities/classes/items/characters`
yields 0 errors and `Loaded 790 / 268 / 128 / 160`. `races.json` and `terrain.json` are unchanged.

## Non-goal clarified: no "baseline granted_abilities" needed

Core combat actions are **intrinsic** to the action economy — `TurnActions.execute_move`,
`execute_attack` (equipped-weapon, no ability), `execute_defend`, `execute_wait`,
`execute_use_item`. The AI planner enumerates the basic attack intrinsically
(`AIPlan.make_attack_only`/`make_move_attack`); the HUD only disables the *Abilities sub-menu*
when a unit has no learned skills. So a player class with empty `granted_abilities` is **fully
combat-functional** — there is no baseline-attack regression and nothing to grant. Skills/spells
layer on via `jp_costs` → learn → loadout, which already works for progressed characters.

## Design decisions requiring sign-off (review gates)

Resolve these before implementation; each shapes tests and docs:

1. **Progression model.** Confirm level-gated class unlocks (reach level N in a prereq class) as
   the canonical rule, replacing the documented "unlock Thief/Soldier/Adept at level 3." Confirm
   whether fresh recruits get any default learned loadout or start skill-less (learn-via-JP).
2. **Balance intent.** Confirm the rebalanced class `stats`/`growth` are intended and internally
   consistent (spot-check caster/tank/dps archetypes across tiers). This is the riskiest unknown.
3. **Roster identity.** The 20 playable templates still map to `vagabond`; confirm the intended
   tier-1→elite paths per template (`recommended_path`) under the new tree.
4. **Economy fit.** 128 items vs. current shop pools / loot tables (`shop_pools.json`,
   `loot_tables.json`, `encounters.json`) — confirm price coverage and drop wiring for new items.
5. **Meta / encounters.** 140 monster classes + 160 characters vs. `encounters.json` (73) and
   `meta_unlocks.json` — confirm references resolve and scaling still holds.

## Work breakdown

**Phase 0 — Design review.** Resolve the five decisions above; capture the canonical job-tree
diagram and balance targets. Exit: signed-off design.

**Phase 1 — Import + boot.** On a feature branch: rebuild `abilities.csv` (live 91 + 699 historical),
`import all`, confirm 0 errors and clean boot. Exit: `790 / 268 / 128 / 160` loads green in the pipeline.

**Phase 2 — Test reconciliation (~148 failures).** Rewrite against the new design, not to silence:
- `tests/core/data/test_full_library.gd` (128): `test_every_class_has_granted_abilities` →
  assert each class provides an ability path (`granted_abilities` **or** `jp_costs`) + refs resolve.
- `tests/core/data/test_roster.gd` (14): update signature-ability checks from `granted_abilities`
  to `jp_costs`; **replace `adept` cases**; update tier assertions (soldier/thief → tier 2); refresh
  stat expectations (Fighter atk/def/wp) to the rebalanced derivation; re-verify weapon-power rows.
- `tests/core/combat/test_ability_resolver_all.gd` (5): supply abilities via loadout
  (`character.abilities`) rather than assuming class grants; drop `basic_strike`-granted assumptions.
- `tests/core/ai/test_ai_planner.gd` (1): give the test soldier a learned/slotted ability instead of
  relying on class-granted `power_strike`.
- Add a positive guard: a fresh unit from each playable template yields a legal move/attack/defend/wait plan.

**Phase 3 — Combat/AI validation.** Playtest or scripted-sim a few encounters with the new balance;
confirm the AI uses `jp_costs`-learned abilities via loadout and that fights resolve sensibly.

**Phase 4 — Economy / encounter / meta wiring.** Reconcile shop pools, loot tables, encounter
compositions, and meta-unlock references to the new class/character/item IDs; add/adjust tests.

**Phase 5 — Documentation overhaul.** Rewrite the CLAUDE.md job-tree section (4-tier → 10-tier,
remove Thief/Soldier/Adept@3 language), refresh all content counts, update README + roadmap, and
retire the now-historical `class-tree-engine-changes.md` / `content-pipeline-pending-changes.md`.

**Phase 6 — Balance pass.** Iterative tuning of JP/WP costs, growth, tier gating across 790 abilities
/ 268 classes. Largest and most iterative; gated on Phase 3 findings.

## Risks

- **Balance is unvalidated.** The rebalanced stats/growth have never been playtested; Phase 3 may
  surface broken archetypes requiring content rework (feeds Phase 6).
- **Save compatibility.** Existing saves reference current class IDs (`adept`, etc.); adopting the new
  tree needs a `SaveManager` migration or a clean-save assumption — decide in Phase 0.
- **Doc/design drift.** CLAUDE.md is heavily invested in the 4-tier tree; Phase 5 is non-trivial.

## Rollback

All content lives in `data/csv/` + `data/*.json`; the initiative runs on a feature branch. Until
Phase 5 merges, `development` remains on the current design. Revert = drop the branch.

## Enablers already landed on `development`

- `Affinity.ELEMENTS` extended with `poison, arcane, steam, alchemical, aether, sonic` (inert today).
- `docs/content-import-followup.md` — proven import recipe + root-cause of the ability-library gap.
