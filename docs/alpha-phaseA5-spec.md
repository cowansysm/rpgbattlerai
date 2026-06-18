# Phase A5 — Battle Bands & Save System Specification

**Parent plan:** `alpha-implementation-plan.md` (Phase A5)
**Master spec:** `alpha-specs.md` (§7 Battle Bands, §9.2/§9.4 save model)
**Builds on (Alpha):** `alpha-phaseA4-spec.md` (`CharacterInstance`, `BattleUnit.from_instance`, progression ops)
**Builds on (MVP):** `phase7-spec.md` (`MatchBuilder`, draft flow), `phase1` (`GameData`), autoload layout
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-17

---

## 1. Purpose & Scope

Phase A5 gives the player a **persistent roster they own and manage** — the **Battle Band** — and the **save system** that makes A4's instances durable across sessions. It turns "a character instance exists in memory" into "a band of named, growing characters the player builds up, equips, and takes into battle."

It composes the A4 progression model into a managed roster and wires a band's **fielded selection** into the existing match construction via `BattleUnit.from_instance`, while keeping the MVP hotseat/quick-battle path working.

### In scope

- A **`BattleBand`** model: roster of `CharacterInstance`s, a shared inventory (equipment + consumables), and gold.
- A **`SaveManager`** autoload: versioned JSON persistence under `user://`, supporting **multiple bands** (and forward-compatible slots for the A8 run and an A8/A10 profile).
- (De)serialization of `CharacterInstance` and `BattleBand` (`to_dict`/`from_dict`).
- A **band management UI** (out-of-battle scene): inspect, spend JP / learn, unlock / switch class, assemble loadout, equip from inventory, recruit, dismiss.
- **Band → battle** wiring: build a party from a fielded selection of instances; carry it through `MatchData`; a quick-battle-from-band path that proves the end-to-end instance party.
- **Recruitment**: generate scaled Vagabond instances from templates.
- Instance **BP recompute** (value metric) from level/stats/loadout/equipment.

### Out of scope

- **Economy depth** — loot tables, shops, sell flow (Phase A6). A5 may spend gold on recruits as a simple deduction, but the shop/loot systems are A6.
- **The roguelike run** (Phase A8): node graph, encounter generation, depth scaling, down-limit death. A5 leaves a save slot for run state but does not implement it.
- **AI** (A7) — quick-battle-from-band may field a second band controlled manually or by a placeholder until A7.
- **Meta-progression profile unlocks** (A8/A10) — the save schema reserves a profile slot; unlock logic is later.
- **Save encryption / cloud** — plain versioned JSON only.

### Exit criteria

Phase A5 is complete when:

1. A player can create and name a band and populate it with generated instances.
2. Through the management UI they can inspect an instance, spend JP to learn abilities, unlock/switch classes, assemble a loadout, and equip gear from the band inventory (all A4 ops surfaced).
3. The band (roster, instances, inventory, gold) **saves to `user://` and reloads intact** across an app restart — a tested round-trip.
4. A fielded subset of the band builds a party of `BattleUnit`s (via `from_instance`) and plays a battle.
5. The MVP hotseat/quick-battle path still works (throwaway generated bands or premade templates).
6. Band/instance serialization and operations are covered by headless tests; the UI by a manual checklist.

---

## 2. Design Decisions (Phase A5)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Save location** | Plain JSON under `user://saves/` via a `SaveManager` autoload; one versioned **root document** holding `profile`, `bands[]`, and an `active_run` slot. | `user://` is the correct, platform-safe writable dir, kept separate from `res://data/` authored content. One document keeps multi-band + profile + run coherent. |
| **Versioned saves** | A `save_version` field with a `migrate()` hook. | Forward migration as the schema grows (run, profile, new instance fields). |
| **Serialization on the models** | `to_dict`/`from_dict` on `CharacterInstance` and `BattleBand`; `SaveManager` orchestrates files. | Keeps serialization next to the data it mirrors; `SaveManager` stays I/O-only. |
| **Band → battle via instances** | A party builder converts a fielded selection to `BattleUnit`s through `BattleUnit.from_instance`; `MatchData` carries the active band + fielded ids. | Reuses A4's bridge and the existing `MatchSetup`/`Deployment`/`RoundManager`; no combat-layer change. |
| **Keep the MVP path** | The premade-draft hotseat flow stays intact; quick-battle-from-band is an additional path. | Preserves MVP behavior (master spec §10) while introducing bands. |
| **BP recompute** | Derive instance BP from level, effective stats, loadout, and equipment via the MVP heuristic; recompute on change. | BP becomes the value metric for fielding rules and (A8) encounter scaling. |
| **Gold present, economy later** | The band holds gold; recruiting may deduct it. Loot/shops are A6. | Lets recruitment have a cost without pulling the whole economy forward. |
| **Profile/run slots reserved** | The save schema includes `profile` and `active_run` placeholders. | A8/A10 fill them without a save-format break. |

---

## 3. The Battle Band Model

A `RefCounted` (aligns with master-spec §9.2):

```
band_id: String
name: String
roster: Array[CharacterInstance]
inventory: {
    equipment: Array[String],            # item ids not currently equipped
    consumables: Array[{id: String, qty: int}]
}
gold: int
```

Operations: add/remove instance (recruit/dismiss), move equipment between inventory and an instance's slots, and query a fielded selection (a subset of `roster` chosen for a battle under tier BP/size rules).

A `ROSTER_CAP` (tunable) bounds roster size; it exceeds any single fielded party so the player keeps reserves.

---

## 4. Save System

### 4.1 Layout

```
user://saves/
└── save.json        # { save_version, profile, bands: [ ... ], active_run }
```

- `save_version: int` — bumped on schema changes; `SaveManager.migrate()` upgrades older documents.
- `profile` — reserved for A8/A10 meta-progression (unlocked templates/classes, completed runs); minimal/empty in A5.
- `bands` — array of serialized `BattleBand`s (each with its serialized instances).
- `active_run` — reserved for A8; `null` in A5.

### 4.2 `SaveManager` (autoload)

Registered after `GameData` (it reads templates/classes when reconstructing instances). Responsibilities:

- `load()` → read `save.json`, run `migrate()`, deserialize into in-memory bands/profile.
- `save()` → serialize current bands/profile/run and write atomically.
- `has_save()`, `create_band(name)`, `delete_band(id)`, `active_band` accessors.
- Robust to a missing/empty file (first run → empty state, not a crash).

### 4.3 Serialization contract

`CharacterInstance.to_dict()/from_dict()` and `BattleBand.to_dict()/from_dict()` are lossless and version-tolerant: an unknown future key is ignored on load; a missing key defaults. The round-trip `from_dict(to_dict(x)) == x` is a tested invariant. Instances reference templates/classes/items by **id**, resolved against `GameData` at load (authored content is never duplicated into saves).

---

## 5. Band Management UI

An out-of-battle scene (sibling to the draft scene), reachable from the main menu (and the A0 Dev Tools menu during development). Functional, unstyled.

| Panel | Function |
|-------|----------|
| **Band overview** | Band name, gold, roster list with each instance's name/level/active class/BP. |
| **Instance inspector** | Stats (incl. `MAG`/`RES`), level/XP, unlocked classes, learned abilities, current loadout, equipment, BP. |
| **Progression** | Spend JP to learn abilities; unlock / switch active class (gated by prerequisites); assemble the ability loadout (≤ `ABILITY_SLOTS`). |
| **Equipment** | Assign/unassign gear between band inventory and instance slots (gated by active-class access). |
| **Recruit / dismiss** | Recruit a new instance from an available template (scaled, optional gold cost); remove an instance. |
| **Save / load** | Save the band; load on launch; create/select band. |

All progression actions call the A4 `CharacterInstance` operations; the UI never mutates instance state directly.

## 6. Recruitment

New instances are generated from **available templates** via the A4 `CharacterInstance.generate(template)` (starting Vagabond L1) with a **starting kit scaled** to the band's current power (a tunable so recruits aren't dead weight). Template availability may later be gated by meta-progression (A8); in A5 all base templates are available. Recruiting may cost gold (`RECRUIT_COST`).

---

## 7. Band → Battle Wiring

### 7.1 Party from instances

A party builder converts a fielded selection (`Array[CharacterInstance]`) into `Array[BattleUnit]` using `BattleUnit.from_instance(instance, race_provider, class_provider)` (A4). This reuses the existing `MatchSetup` → `Deployment` → `RoundManager` pipeline unchanged.

### 7.2 Scene hand-off

`MatchData` gains references for the **active band** and the **fielded selection** (and, later, the run context). The battle scene builds the match from these, mirroring how `DraftScene` currently sets `MatchData.match_state`/`map_id`.

### 7.3 Quick battle (proof + retained MVP)

- **Quick-battle-from-band:** field a subset of the player's band against an opponent band (generated from templates) on a chosen map — proves the instance party end-to-end. The opponent is manually controlled (or placeholder) until A7's AI.
- **MVP hotseat:** the premade-draft path is retained unchanged for two-human play.

### 7.4 BP recompute

Instance BP is recomputed from current level, effective stats, ability loadout, and equipment via the MVP BP heuristic (`rpg-specs.md` §7.6) whenever those change, so fielding rules (and A8 encounter scaling) have a current value.

---

## 8. Data Model Summary

- **BattleBand** (new, persistent) — §3.
- **CharacterInstance** — add `to_dict`/`from_dict` (A4 model unchanged otherwise).
- **Save document** — `{ save_version, profile, bands[], active_run }` under `user://saves/save.json` (§4).
- **MatchData** — add active-band + fielded-selection references (+ reserved run ref).
- **MatchBuilder / party builder** — add an instance-party path reusing `from_instance`.
- **New autoload** — `SaveManager` (after `GameData`).
- **Tunables** — `ROSTER_CAP`, `RECRUIT_COST`, recruit power-scaling (alpha-specs §7/§8 economy partials).

---

## 9. Risks & Notes

- **Save/runtime divergence.** Saves store ids and mutable state; authored content stays in `res://`. If a referenced template/class/item id disappears, loading must degrade gracefully (warn + skip or substitute), not crash.
- **Migration discipline.** Bump `save_version` and add a migration step with every schema change; test loading an old document.
- **Atomic writes.** Write to a temp file then rename to avoid corrupting a save on crash mid-write.
- **Serialization fidelity.** Instance dicts (jp, growth, equipment, loadout) must round-trip exactly; cover with tests, especially after A4 field additions.
- **BP heuristic drift.** Recomputed BP must stay consistent with how A8 scales encounters; centralize the calculation.
- **Scope creep.** No shops/loot (A6), no run/nodes (A8), no AI (A7), no profile unlock logic — bands, persistence, management, and the instance party path only.

---

## 10. Phase A5 Deliverables Checklist

- [ ] `BattleBand` model (roster, inventory, gold) with add/remove/equipment-move ops and `ROSTER_CAP` (§3).
- [ ] `CharacterInstance.to_dict/from_dict` and `BattleBand.to_dict/from_dict`; lossless round-trip (§4.3).
- [ ] `SaveManager` autoload: versioned `user://saves/save.json`, multiple bands, profile/run slots, migrate hook, safe first-run (§4).
- [ ] Band management UI: inspect, JP/learn, unlock/switch class, loadout, equip, recruit/dismiss, save/load (§5).
- [ ] Recruitment generating scaled Vagabond instances from templates (optional gold cost) (§6).
- [ ] Party-from-instances builder via `BattleUnit.from_instance`; `MatchData` band/fielded refs; quick-battle-from-band plays (§7).
- [ ] MVP hotseat/premade-draft path retained and working (§7.3).
- [ ] Instance BP recompute on change (§7.4).
- [ ] Headless tests: serialization round-trip, band ops, save/load across a simulated restart, fielded party builds; manual UI checklist.
- [ ] Git tag `alpha-phaseA5-complete`.
