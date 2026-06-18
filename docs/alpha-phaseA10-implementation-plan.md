# Phase A10 — Implementation Plan

**Source spec:** `alpha-phaseA10-spec.md`
**Master spec:** `alpha-specs.md` (§8.6, §14)
**Builds on (Alpha):** all prior phases — A4 (growth/XP/JP), A5 (`SaveManager` profile slot, management UI), A6 (economy), A7 (AI difficulty), A8 (run + light meta hooks)
**Builds on (MVP):** `phase11-implementation-plan.md` (polish), `phase10` (tuning)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages; more refinement/playtest than new code.
**Date:** 2026-06-17

---

## How to use this plan

Five **work groups** (A–E). Across groups: **A** (meta-progression) is the main new code; **B** (tuning) is data iteration over exposed constants; **C** (UX polish) refines existing scenes; **D** (seam audit) is verification/docs; **E** (final integration) ties it off. A–C can proceed in parallel; D and E trail.

Each task lists a **done state**. There is little new system code — A10 fills the A5 profile slot, wires gating, tunes values, and polishes UI. Treat tuning and the seam audit as first-class deliverables.

> **Carry-over:** the `profile` slot already exists in A5's save document and A8 writes light progress to it; A10 gives it rules, gating, and UI. All balance levers already live in `constants.json`/`run_config.json` — A10 changes values, not formulas. Polish reuses the MVP HUD/marker systems.

---

## Group A — Meta-Progression

*The main new code. Fills the A5 profile slot.*

### A1. `Profile` model + persistence
- Define the profile fields; `to_dict`/`from_dict`; `SaveManager` load/save it alongside bands; pre-A10 saves load with an empty profile.
- **Done:** profile survives save/restart; old saves migrate to empty profile (tested in E).

```gdscript
# src/core/progression/profile.gd
class_name Profile
extends RefCounted

var profile_id: String = "default"
var unlocked_templates: Array[String] = []
var unlocked_classes: Array[String] = []
var completed_runs: int = 0
var meta_unlocks: Array[String] = []

func to_dict() -> Dictionary:
    return {"profile_id": profile_id, "unlocked_templates": unlocked_templates,
        "unlocked_classes": unlocked_classes, "completed_runs": completed_runs,
        "meta_unlocks": meta_unlocks}
```

### A2. Unlock sources
- `data/meta_unlocks.json` maps milestones (run complete, boss kill, depth reached) to unlock grants; apply on run-end.
- **Done:** completing a run grants the configured unlocks and increments `completed_runs`.

```gdscript
# applied at run-end (A8 hook)
func grant_run_completion(profile: Profile, run: RunState, table: Dictionary) -> void:
    profile.completed_runs += 1
    for rule in table.get("on_run_complete", []):
        _apply_unlock(profile, rule)
```

### A3. Gating wiring
- Recruitment (A5) filters templates by `unlocked_templates`; job tree (A4) consults `unlocked_classes`; embark (A8) applies optional starting boons.
- **Done:** locked templates/classes are unavailable until unlocked; boons apply at embark only.

### A4. Notifications
- A post-run summary / unlock toast surfacing earned meta-progress.
- **Done:** the player sees what they unlocked.

---

## Group B — Balance & Tuning Pass

*Data iteration over exposed constants. No formula changes.*

### B1. Curve validation harness
- Use seeded runs + the A0 dev tools to compare outcomes across constant sets; capture a few reference runs.
- **Done:** a repeatable way to compare tuning changes exists.

### B2. Tune the cross-loop levers
- Adjust XP/JP/growth (A4), `DEPTH_BP_CURVE` (A8), economy (A6), AI presets (A7), `DOWN_LIMIT` (A8) toward a sensible difficulty arc.
- **Done:** early nodes winnable, late nodes threatening; presets feel distinct.

### B3. Roster/BP sanity
- Validate the BP heuristic tracks real combat value; check the class/ability set for dominant or dead picks; adjust draft values.
- **Done:** informal playtests show no dominant/dead picks (MVP Phase 10 bar).

---

## Group C — UX Polish

*Refines existing scenes; reuses MVP HUD/markers.*

### C1. Battle & run-map clarity
- Confirm hit/heal/move cues and terrain-effect feedback read with new content; polish run-map current/selectable/visited states + progress.
- **Done:** battle and run-map states are legible at a glance.

### C2. Management & shop polish
- Readable inspector (incl. `MAG`/`RES`, downs remaining), clear JP/unlock/loadout/equip affordances; clear shop prices/affordability/feedback.
- **Done:** management and shop flows are smooth and clear.

### C3. Cross-cutting QoL
- Unlock/result notifications, run-result screen, save/resume clarity, confirmations, error legibility.
- **Done:** the loop's transitions and feedback are coherent.

---

## Group D — Seam Audit

*Verification + docs. No feature implementation.*

### D1. Confirm deferred-feature seams
- Walk each deferred feature (player editor, networking, rich events, deeper AI, crafting, new stats/effects) and confirm its extension point holds; note any friction.
- **Done:** a short seam-audit note documents each seam (and files frictions as future-phase items).

---

## Group E — Final Integration & Verification

### E1. Full-loop coherence pass
- Play embark → traverse → battles → events/shops/rests → win/lose → meta-progress → re-embark with new options.
- **Done:** the loop is coherent and fair end to end.

### E2. Profile/meta tests (GUT)
- Profile round-trip; pre-A10 save loads empty; run-completion grants unlocks; gating hides locked content; boons apply at embark only.
- **Done:** green.

```gdscript
# tests/core/progression/test_meta.gd
extends GutTest

func test_profile_round_trip() -> void:
    var p := Profile.new(); p.completed_runs = 2; p.unlocked_classes = ["sage"]
    var q := Profile.from_dict(p.to_dict())
    assert_eq(q.completed_runs, 2)
    assert_true(q.unlocked_classes.has("sage"))

func test_locked_template_unavailable() -> void:
    var p := Profile.new()   # nothing unlocked beyond defaults
    assert_false(_recruitable_templates(p).has("locked_template_id"))
```

### E3. Regression suite + manual checklist
- Run the full GUT suite; complete the manual full-run + meta checklist.
- [ ] A full run plays to victory and to defeat.
- [ ] Meta-progress persists; unlocks gate the next run's options.
- [ ] Difficulty arc feels fair; AI presets differ; no dominant/dead picks.
- [ ] Indicators (downs, progress, rewards, unlocks) are clear.
- [ ] Seam audit complete; README/CLAUDE updated.
- **Done:** suite green; checklist passed.

### E4. Docs update
- Update README/CLAUDE phase status to reflect Alpha completion; add the seam-audit note to `docs/`.
- **Done:** project docs reflect the finished Alpha.

---

## Dependency Map

```
A (meta-progression) ──┐
B (tuning) ────────────┼──> E (final integration + verification)
C (UX polish) ─────────┤
D (seam audit) ────────┘
```

**Suggested first pass:** A1–A4 → C1–C3 and B1–B3 (parallel) → D1 → E1–E4. Land the profile + gating early so tuning and polish exercise the full meta loop.

---

## Phase A10 Definition of Done

- [ ] `Profile` persisted via `SaveManager` (round-trip; pre-A10 save → empty profile) (A1, E2).
- [ ] Unlock sources granted on run completion/milestones; `completed_runs` increments (A2).
- [ ] Gating wired (recruitment templates, job-tree classes, embark boons); notifications surfaced (A3–A4).
- [ ] Cross-loop tuning validated against playtests; constants exposed; no dominant/dead picks (B).
- [ ] UX polish across battle/run-map/management/shop with clear indicators and QoL (C).
- [ ] Seam audit documenting each deferred-feature extension point (D).
- [ ] Full-run coherence pass + meta/profile tests + regression suite green; manual checklist passed (E1–E3).
- [ ] README/CLAUDE updated to Alpha completion; seam-audit note added (E4).
- [ ] Git tag `alpha-phaseA10-complete`.
