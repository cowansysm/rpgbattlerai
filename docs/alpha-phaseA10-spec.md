# Phase A10 — Polish & Meta-Progression Specification

**Parent plan:** `alpha-implementation-plan.md` (Phase A10)
**Master spec:** `alpha-specs.md` (§8.6 Meta-progression, §14 Out of Scope / seams)
**Builds on (Alpha):** all prior phases — A4 (instances/growth), A5 (`SaveManager` profile slot, management UI), A6 (economy), A7 (AI difficulty), A8 (run, light meta hooks)
**Builds on (MVP):** `phase11-spec.md` (polish precedent), `phase10` (balance/tuning precedent)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-17

---

## 1. Purpose & Scope

Phase A10 is the **finale**: it turns the working-but-rough loop from A8 into a **coherent, demonstrable first playable** of the single-player Alpha. It does three things — completes **meta-progression** (the across-runs layer A8 only scaffolded), runs a **balance & tuning pass** over the whole loop, and applies **UX polish** — then **confirms the architecture leaves clean seams** for the deferred features (master-spec §14).

It is the Alpha analogue of MVP Phase 11: little new system-building, much refinement, and a clear "the MVP-of-the-Alpha is done" bar.

### In scope

- **Meta-progression:** a persistent **`Profile`** (unlocked templates/classes, completed runs, unlock tokens) with **unlock rules** earned by playing, **gating** wired into recruitment (A5) and the job tree (A4), and optional **starting boons** for new runs.
- **Balancing & tuning:** validate and adjust the cross-loop curves and constants (XP/JP/growth, `DEPTH_BP_CURVE`, loot/economy, AI difficulty, `DOWN_LIMIT`, BP heuristic) against playtests; expose them for quick iteration.
- **UX polish:** feedback cues, clear indicators (downs remaining, run progress, unlock notifications), and quality-of-life across the management, shop, run-map, and battle screens.
- **Seam confirmation:** verify (and document) that deferred features can be added without reworking core systems.
- **Final integration:** a full run plays start to finish and *feels* coherent and fair.

### Out of scope

- **New mechanics or content systems** — A10 refines what A0–A9 built; it does not add node kinds, stats, effect types, or combat rules.
- **The deferred features themselves** (player-facing map editor, networked multiplayer, rich narrative campaign, deep/coordinated AI, crafting) — A10 only confirms their seams (master-spec §14).
- **Final art/audio** — placeholder visuals continue; polish is functional/feedback, not asset production.
- **Bulk content authoring** (A9) — A10 may add a few items but its job is tuning, not volume.

### Exit criteria

Phase A10 is complete when:

1. A **`Profile`** persists across runs with unlocks that **gate recruitment templates and seeded classes**, plus optional starting boons; completing runs grants meta-progress.
2. The cross-loop curves are tuned so a run has a sensible **difficulty arc** (early winnable, late threatening) and the sample roster shows **no dominant or dead picks** in informal playtests — with the relevant constants exposed for iteration.
3. UX polish lands: **clear feedback and indicators** (downs remaining, run/node progress, rewards, unlocks) and quality-of-life across all screens.
4. The deferred-feature **seams are confirmed and documented** — each can be added without reworking core systems.
5. A complete run plays **embark → traverse → victory/defeat → meta-progress**, coherent end to end; the full regression suite is green.

---

## 2. Design Decisions (Phase A10)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Profile in the save slot** | Fill the `profile` slot reserved in A5's save document; `SaveManager` owns it like bands. | The data path already exists (A5/A8); A10 gives it rules and UI. |
| **Unlocks gate, don't grant power mid-run** | Meta-unlocks change what's *available* for future runs (templates/classes/boons), not a unit's in-run strength. | Keeps per-run balance clean; meta is a between-runs pull. |
| **Tuning via exposed constants** | All cross-loop curves live in `constants.json`/`run_config.json`; A10 adjusts values, not formulas. | The systems were built tunable on purpose; iteration is data, not code. |
| **Polish, not assets** | UX work is feedback/indicators/QoL reusing the MVP marker/HUD systems; no art/audio pipeline. | Matches the "functional first playable" bar; art is post-Alpha. |
| **Seam confirmation is a deliverable** | Explicitly audit and document each deferred feature's extension point. | The master spec promises these seams; A10 verifies the promise held. |
| **Playtest-driven** | Balance acceptance is informal playtest ("no dominant/dead picks"), aided by replay/seeded runs. | Mirrors MVP Phase 10; numbers settle against play, not theory. |

---

## 3. Meta-Progression

### 3.1 Profile

The account-level `Profile` (master-spec §9.2), persisted in `SaveManager` (A5):

```json
{ "profile_id": "default",
  "unlocked_templates": ["..."],
  "unlocked_classes": ["..."],
  "completed_runs": 0,
  "meta_unlocks": ["..."] }
```

### 3.2 Unlock sources

Meta-progress is earned by playing: completing a run, defeating the boss, reaching depth milestones, or one-off achievements. Each grants entries to `meta_unlocks` and/or `unlocked_templates`/`unlocked_classes`, and increments `completed_runs`. Sources are **data-driven** (`data/meta_unlocks.json`) so designers can add milestones without code.

### 3.3 Gating

- **Recruitment (A5):** template availability is filtered by `unlocked_templates` — new races/archetype seeds open as the player progresses.
- **Job tree (A4):** some advanced/elite classes may be **seeded as unlocked** via `unlocked_classes`, or their prerequisites eased, so the meta layer broadens build options across runs.
- **Starting boons (optional):** a new run may begin with a small bonus (extra gold, a free recruit, a higher starting `DOWN_LIMIT`) drawn from `meta_unlocks`.

Gating is applied at the relevant entry points (recruit screen, embark) and never alters in-progress balance.

### 3.4 Notification

Earned unlocks are surfaced to the player (a post-run summary / unlock toast) so progress is legible.

---

## 4. Balancing & Tuning

A10 validates and adjusts the curves that span the loop; it changes **values**, not systems.

| Lever | Source | Goal |
|-------|--------|------|
| **XP / JP / growth** | A4 (`XP_CURVE`, `JP_PER_BATTLE`, `growth`) | Leveling/job progress paces with run depth — meaningful but not trivializing. |
| **Encounter scaling** | A8 (`DEPTH_BP_CURVE`) | Early nodes winnable, late nodes threatening; a readable difficulty arc. |
| **Economy** | A6 (`PRICE_PER_BP`, `SELL_RATIO`, `LOOT_DEPTH_SCALE`) | Gold/loot feel rewarding without breaking scarcity. |
| **AI difficulty** | A7 (`AI_TOP_N`, `AI_TEMPERATURE`, weights, presets) | Presets feel distinct; default AI is competent but beatable. |
| **Death stakes** | A8 (`DOWN_LIMIT`) | Tension without excessive frustration; difficulty modes may vary it. |
| **BP heuristic** | MVP §7.6 / A5 recompute | Instance BP tracks real combat value so encounter scaling is fair; validate against playtests. |

**Method:** seeded runs for reproducible comparison; informal playtests against the "no dominant or dead picks" bar (MVP Phase 10 precedent); the dev tools (A0) for quick scenario setup. Keep all levers in `constants.json`/`run_config.json` for fast iteration.

---

## 5. UX Polish

Functional polish reusing the MVP HUD/marker systems (no new art):

| Screen | Polish |
|--------|--------|
| **Battle** | Confirm hit/heal/move cues read clearly with the new content; surface terrain-effect feedback (hazard damage, cover) and AI actions legibly in the log. |
| **Run map (A8)** | Clear current/selectable/visited states, node-kind icons, run/depth progress, and route legibility. |
| **Band management (A5)** | Readable instance inspector (incl. `MAG`/`RES`, downs remaining), clear JP/unlock/loadout affordances, smooth equip flow. |
| **Shop (A6)** | Clear prices, affordability, buy/sell feedback, reward summaries. |
| **Cross-cutting** | Unlock notifications, run-result screen, save/resume clarity, and general quality-of-life (confirmations, error legibility). |

The bar is **readability and feedback**, not visual fidelity.

---

## 6. Extensibility — Seam Confirmation

A10 explicitly verifies and documents that each deferred feature (master-spec §14) can be added **without reworking core systems**:

| Deferred feature | Confirmed seam |
|------------------|----------------|
| **Player-facing map editor** | A1's `MapEditorModel`/UI split + dev-flag gating — expose a curated UI; no model rewrite. |
| **Networked multiplayer** | Combat acts only through `TurnActions`/`MatchState`; a network layer drives the same surface (as the AI does). |
| **Rich narrative events** | A8's node framework + `events.json` table — richer events are more data/handlers, not a run-structure change. |
| **Deeper/coordinated AI** | A7's `AIPlanner`/`AIScorer` seams — add lookahead/coordination behind the same plan interface. |
| **Crafting / equipment upgrades** | A6 economy + item data — add recipes/upgrade ops over existing items/inventory. |
| **New stats / effect types** | The `StatKey` single-point-of-expansion (A3) and the effect-type table (MVP §9.3.1). |

The deliverable is a short **seam audit** confirming each, noting any friction found (and filing it as a future-phase note rather than fixing it here).

---

## 7. Final Integration & Coherence

A10 ends with a **full-loop pass**: embark with a band → traverse a generated run → fight AI battles that scale → resolve events/shops/rests → win or lose → earn meta-progress → start again with new options. The experience should be coherent and fair, the regression suite green, and the deferred seams confirmed — the bar for "the Alpha is a demonstrable first playable."

---

## 8. Data Model & Touch Points

- **Profile** — fill the `profile` slot in the A5 save document; `SaveManager` load/save it; `to_dict`/`from_dict`.
- **New data** — `data/meta_unlocks.json` (milestone → unlock rules); optional starting-boon definitions.
- **Wiring** — recruitment (A5) reads `unlocked_templates`; job tree (A4) consults `unlocked_classes`; embark (A8) applies starting boons; run-end writes meta-progress.
- **Tuning** — adjust values in `constants.json` / `run_config.json` (no formula changes).
- **UX** — polish existing scenes (battle HUD, run map, management, shop) + unlock/result notifications.
- **Docs** — the seam-audit note; update the project README/CLAUDE phase status to reflect Alpha completion.

---

## 9. Risks & Notes

- **Meta vs in-run balance.** Keep meta-unlocks to *availability*, not in-run power spikes, or per-run tuning becomes a moving target.
- **Tuning rabbit holes.** Balance is iterative; time-box passes and lean on the "no dominant/dead picks" bar rather than chasing perfection.
- **Polish scope.** "Polish" can absorb unlimited effort; cap it at readability/feedback/QoL and defer anything art/audio.
- **Profile migration.** Profile is new persistent state; version it with the save document and test loading a pre-A10 save (empty profile).
- **Seam audit honesty.** If a seam turns out to need rework, document it as a future-phase item — don't quietly expand A10.
- **Regression.** Touching tunables and UI can break tests/flows; run the full suite and the manual full-run checklist before declaring done.

---

## 10. Phase A10 Deliverables Checklist

- [ ] `Profile` model persisted via `SaveManager`; `to_dict`/`from_dict`; survives save/restart (incl. pre-A10 save → empty profile) (§3.1, §8).
- [ ] Unlock sources (`meta_unlocks.json`) granted on run completion/milestones; `completed_runs` increments (§3.2).
- [ ] Gating wired: recruitment filters by `unlocked_templates`; job tree consults `unlocked_classes`; optional starting boons at embark (§3.3).
- [ ] Unlock/result notifications surface meta-progress (§3.4, §5).
- [ ] Balance pass: XP/JP/growth, `DEPTH_BP_CURVE`, economy, AI presets, `DOWN_LIMIT`, BP heuristic validated against playtests; constants exposed (§4).
- [ ] UX polish across battle/run-map/management/shop with clear indicators and QoL (§5).
- [ ] Seam audit confirming each deferred feature's extension point, with any friction filed as future notes (§6).
- [ ] Full-run coherence pass green; regression suite green; manual full-run + meta-progression checklist passed (§7).
- [ ] README/CLAUDE phase status updated to reflect Alpha completion (§8).
- [ ] Git tag `alpha-phaseA10-complete`.
