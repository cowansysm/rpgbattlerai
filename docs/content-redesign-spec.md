# Content Redesign — Adopt the Expanded 10-Tier Library (Design Project)

**Date:** 2026-07-06
**Status:** PHASE 0 COMPLETE — design signed off (2026-07-06). Ready for Phase 1 implementation. Multi-session.
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

## Design review — SIGNED OFF (Phase 0, 2026-07-06)

All five gates resolved. Outcomes below are the canonical design of record.

1. **Progression model — CONFIRMED.** Level-gated class-unlock chain is canonical
   (`prerequisites: {"classes": [["<prereq>", <level>]]}`; reach the required level in a prereq
   class to unlock the next). Single root `vagabond` (t0) → 8 tier-1 classes at vagabond L3 →
   chains through 10 tiers; valid DAG (multi-parent merges allowed, e.g. `oracle` from `cleric`
   or `seer`). Replaces the old "unlock Thief/Soldier/Adept at level 3."
   - **Recruit start (DECISION):** **skill-less** — recruits carry only intrinsic actions and
     learn every skill via JP. To avoid a dead first turn, `Recruiter.recruit()`/
     `CharacterInstance.generate()` grants a **small random starting JP pool** to the starting
     class. Proposed tunables in `constants.json`: `RECRUIT_STARTING_JP_MIN = 20`,
     `RECRUIT_STARTING_JP_MAX = 50` (context: `JP_PER_BATTLE = 20`; vagabond abilities cost
     20–50, so a recruit can immediately buy 1–2 baseline skills). Final numbers are a Phase 6 tuning knob.
2. **Balance intent — CONFIRMED (user).** The rebalanced class `stats`/`growth` and the expanded
   library are intended and adopted as the current product. Balance is still unplaytested → Phase 3/6.
3. **Roster identity — CONFIRMED.** 20 playable templates, all `vagabond`-rooted; `recommended_path`
   is an **archetype label** (`physical`/`magical`/`control`/`support`), each richly covered in the
   tree (physical→physical_attack/defense 55, magical→magical_attack/defense 38, control 16,
   support 19). No dangling paths.
4. **Economy fit — CLEAN.** `shop_pools.json` (46 items) and `loot_tables.json` resolve fully against
   the 128-item set (0 dangling). **Follow-up (Phase 4, non-blocking):** 82 new items are not yet in
   any shop pool or loot table — wire the desirable ones in.
5. **Meta / encounters — CLEAN.** All 73 encounters (121 distinct enemy templates) resolve against the
   160 characters; `meta_unlocks.json` rules grant only meta flags (no template/class refs). 0 dangling.

**Save compatibility (DECISION):** **clean-slate** — bump the save version in `SaveManager` and
discard/reset incompatible saves on load (acceptable for in-dev alpha). No ID-migration table.

### Canonical tier-1 branches (from `vagabond` at L3)

| Tier-1 class | Archetype | Leads toward |
|---|---|---|
| `squire` | physical_attack | soldier/warrior/monk/knight_errant → berserker, dragoon, gladiator, warlord, swordmaster |
| `footman` | physical_defense | defender/guardian/knight/man_at_arms → paladin, sentinel, shieldmaster, vanguard, ironclad |
| `slinger` | physical_attack (ranged) | archer/gunner → hunter, marksman, crossbowman, pistoleer, rifleman |
| `apprentice` | magical_attack | mage/cultist/scholar → black_mage, elementalist, necromancer, chronomancer, sage |
| `acolyte` | magical_defense | cleric/seer/white_mage/templar/medic → bishop, oracle, paladin, field_surgeon |
| `cutpurse` | control | thief/scout/duelist/bard → rogue, trickster, saboteur, ranger, swordmaster |
| `page` | support | herald/tactician/medic/bard/white_mage → strategist, beastmaster, crusader |
| `tinker` | support (gadget) | chemist/artificer/gunner/ironclad → alchemist, bombardier, artillerist, dreadnought |

## Work breakdown

**Phase 0 — Design review. ✅ COMPLETE (2026-07-06).** Five gates resolved (see "Design review —
SIGNED OFF" above); canonical job tree captured. Ready for Phase 1.

**Phase 1 — Import + boot + start-state wiring.** On a feature branch: rebuild `abilities.csv`
(live 91 + 699 historical), `import all`, confirm 0 errors and clean boot (`790 / 268 / 128 / 160`).
Then land the two Phase-0 decisions: (a) add `RECRUIT_STARTING_JP_MIN`/`_MAX` to `constants.json`
and grant a random JP pool to the starting class in `Recruiter.recruit()` /
`CharacterInstance.generate()` (skill-less start, seeded JP); (b) bump the `SaveManager` save
version and reset incompatible saves on load. Add tests for both. Exit: clean boot + a fresh recruit
has starting JP and zero learned skills.

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
- **Save compatibility.** RESOLVED (Phase 0): clean-slate via save-version bump; no migration table.
  Existing dev saves referencing removed IDs (`adept`, etc.) are reset on load.
- **Doc/design drift.** CLAUDE.md is heavily invested in the 4-tier tree; Phase 5 is non-trivial.

## Rollback

All content lives in `data/csv/` + `data/*.json`; the initiative runs on a feature branch. Until
Phase 5 merges, `development` remains on the current design. Revert = drop the branch.

## Enablers already landed on `development`

- `Affinity.ELEMENTS` extended with `poison, arcane, steam, alchemical, aether, sonic` (inert today).
- `docs/content-import-followup.md` — proven import recipe + root-cause of the ability-library gap.
