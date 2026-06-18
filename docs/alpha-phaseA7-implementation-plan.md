# Phase A7 — Implementation Plan

**Source spec:** `alpha-phaseA7-spec.md`
**Master spec:** `alpha-specs.md` (§11)
**Builds on (Alpha):** `alpha-phaseA0` (terrain effects), `alpha-phaseA5-implementation-plan.md` (quick-battle-from-band opponent)
**Builds on (MVP):** `phase4`/`phase5` (`TurnActions`, `RoundManager`, `MatchState`, `BattleController`), `phase3` (`Movement`, `RangeQuery`, `LineOfSight`, `HexGraph`)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-06-17

---

## How to use this plan

Six **work groups** (A–F). Across groups: **A** (plan model + enumeration) unblocks scoring; **B** (scorer) needs A; **C** (selection/variance) needs A+B; **D** (controller) needs A–C and the MVP turn flow; **E** (integration + tunables) wires it into battles; **F** (tests) trails A–D.

Each task lists a **done state**. Code stubs are Godot 4 / GDScript — pure-core planner reusing `Movement`/`RangeQuery`/`LineOfSight`/`HexGraph`; the controller calls existing `TurnActions`/`RoundManager`.

> **Carry-over:** the AI acts only through `TurnActions.execute_*` and `RoundManager.end_activation`, reading shared `MatchState`. It reuses `Movement.reachable`, `RangeQuery.effective_range`/`in_range`, `LineOfSight`, and A0's `HexGraph` cover/elevation/hazard accessors. Quick-battle-from-band (A5) is the proving ground.

---

## Group A — Plan Model & Enumeration

*Pure core. Unblocks B–D.*

### A1. `AIPlan` / `AIStep`
- Define the step kinds and a plan container; a helper to check a plan fits the unit's AP.
- **Done:** plans construct and report their AP cost.

```gdscript
# src/core/ai/ai_plan.gd
class_name AIPlan
extends RefCounted

# step := {"kind": String, "target_pos": Vector2i, "ability_id": String, "item_id": String}
var steps: Array = []
```

### A2. Candidate enumeration
- Enumerate bounded, legal candidate plans for the active unit: reachable tiles (capped), legal attacks/abilities per origin/target via range+LoS, composite 2-AP plans, plus defend/wait fallbacks.
- **Done:** enumeration yields only legal candidates and always includes a fallback (tested in F1).

```gdscript
# src/core/ai/ai_planner.gd
class_name AIPlanner
extends RefCounted

static func enumerate(state: MatchState, unit: BattleUnit, max_tiles: int) -> Array:
    var plans: Array = []
    var jump: int = unit.stats.effective_jump_climb()
    var reach: Dictionary = Movement.reachable(state.graph, unit.position, unit.stats.effective_move(), jump)
    var tiles: Array = _top_tiles(reach.keys(), state, unit, max_tiles)   # prune to promising tiles
    tiles.append(unit.position)                                          # "stay" option
    for tile in tiles:
        for tgt in _legal_attack_targets(state, unit, tile):
            plans.append(_plan_move_then(tile, {"kind": "attack", "target_pos": tgt}, unit))
        for ab in unit.character.abilities:
            for tgt in _legal_ability_targets(state, unit, tile, ab):
                plans.append(_plan_move_then(tile, {"kind": "ability", "ability_id": ab, "target_pos": tgt}, unit))
    plans.append(_single({"kind": "defend"}))
    plans.append(_single({"kind": "wait"}))
    return plans
```

### A3. Legal-target helpers
- `_legal_attack_targets` / `_legal_ability_targets` using `RangeQuery` + `LineOfSight` + min-range/friendly rules (matching `TurnActions` validation).
- **Done:** helpers return only targets `TurnActions` would accept.

---

## Group B — Utility Scorer

*Depends on A.*

### B1. `AIScorer`
- Score a candidate by predicted end state: damage/kills, exposure/positioning (A0 cover/elevation/hazard), target priority, ability value, resource economy.
- **Done:** scores rank an obviously-good plan above an obviously-bad one (F2).

```gdscript
# src/core/ai/ai_scorer.gd
class_name AIScorer
extends RefCounted

static func score(state: MatchState, unit: BattleUnit, plan: Array, w: Dictionary) -> float:
    var s := 0.0
    var end_pos: Vector2i = _end_position(unit, plan)
    s += w["damage"]   * _expected_damage(state, unit, plan)
    s += w["kill"]     * _expected_kills(state, unit, plan)
    s -= w["exposure"] * _exposure(state, unit, end_pos)       # enemy range, open ground
    s += w["cover"]    * state.graph.effective_cover(end_pos)
    s += w["elev"]     * state.graph.elevation(end_pos)
    s -= w["hazard"]   * state.graph.damage_per_turn(end_pos)
    s += w["target"]   * _target_value(state, unit, plan)      # low-HP / casters
    s += w["ability"]  * _ability_value(state, unit, plan)     # heals/buffs/AoE
    s -= w["resource"] * _resource_cost(unit, plan)            # wasted AP/WP
    return s
```

### B2. Expected-value helpers
- Reuse `CombatResolver` expectations (incl. A3 magic) for predicted damage/heal; estimate exposure from enemy reachable+range.
- **Done:** expected damage tracks the resolution model's mean.

---

## Group C — Selection & Variance

*Depends on A+B.*

### C1. Rank + top-N temperature sampling
- Score all candidates, take top-N, sample by temperature via injected RNG.
- **Done:** low temperature → near-optimal; high → more random; deterministic per seed (F3).

```gdscript
static func plan(state: MatchState, unit: BattleUnit, rng: RandomNumberGenerator, diff: Dictionary) -> Array:
    var candidates := enumerate(state, unit, int(diff.get("max_tiles", 12)))
    var w: Dictionary = diff.get("weights", _default_weights())
    candidates.sort_custom(func(a, b): return AIScorer.score(state, unit, a, w) > AIScorer.score(state, unit, b, w))
    var n: int = mini(int(diff.get("top_n", 3)), candidates.size())
    return _temperature_pick(candidates.slice(0, n), state, unit, w, float(diff.get("temperature", 0.5)), rng)
```

### C2. Difficulty presets
- Map `AI_DIFFICULTY` (easy/normal/hard) to `{top_n, temperature, max_tiles, weights}`.
- **Done:** presets produce visibly different play.

---

## Group D — AIController (Driver)

*Depends on A–C + MVP turn flow.*

### D1. Execute a plan via `TurnActions`
- For the active AI unit, get a plan and run each step through the matching `execute_*`, checking results; pace via existing animation timing.
- **Done:** the AI plays an activation and stops gracefully on any illegal step.

```gdscript
# src/map/ai_controller.gd
extends Node

func take_turn(state: MatchState, rng: RandomNumberGenerator, diff: Dictionary) -> void:
    var unit: BattleUnit = state.current_unit
    var steps := AIPlanner.plan(state, unit, rng, diff)
    for step in steps:
        var res: Dictionary = _execute(state, step)
        if res.has("error"):
            break                       # plan invalidated; stop cleanly
        await _pace()                   # reuse human-path animation timing
    RoundManager.end_activation(state)

func _execute(state: MatchState, step: Dictionary) -> Dictionary:
    match step["kind"]:
        "move":    return TurnActions.execute_move(state, step["target_pos"])
        "attack":  return TurnActions.execute_attack(state, step["target_pos"])
        "ability": return TurnActions.execute_ability(state, step["ability_id"], step["target_pos"])
        "defend":  return TurnActions.execute_defend(state)
        "use_item":return TurnActions.execute_use_item(state, step["item_id"], step["target_pos"])
        _:         return TurnActions.execute_wait(state)
```

### D2. Always-progress guarantee
- Ensure the plan ends the activation even if every offensive step fails (fallback wait), so the AI never stalls.
- **Done:** an AI unit with no legal action still ends its turn.

---

## Group E — Integration & Tunables

### E1. Route AI teams
- Mark which teams are AI-controlled at match setup; when the active team is AI, route to `AIController` instead of awaiting input.
- **Done:** AI activations are driven automatically; human activations behave as today.

### E2. Quick-battle opponent
- In quick-battle-from-band (A5), mark the opponent band AI-controlled and seed the planner RNG.
- **Done:** a human-vs-AI battle plays to a winner.

### E3. Constants
- Add `AI_TOP_N`, `AI_TEMPERATURE`, `AI_DIFFICULTY`, and scorer weights to `constants.json`.
- **Done:** readable via `Constants.get_value`.

---

## Group F — Tests & Verification

### F1. Enumeration legality (GUT)
- All enumerated candidates pass `TurnActions` validation; a fallback always exists.
- **Done:** green.

### F2. Scorer sanity (GUT)
- A killing blow scores above a whiff; a cover/high-ground end-position scores above open/hazard; heal scores up when an ally is hurt.
- **Done:** green.

```gdscript
# tests/core/ai/test_ai.gd
extends GutTest

func test_prefers_kill() -> void:
    # state where unit can finish a 1-HP enemy vs hit a full-HP enemy
    var plan := AIPlanner.plan(_state, _unit, _fixed_rng(1), _hard())
    assert_true(_targets_low_hp(plan))

func test_avoids_hazard_tile() -> void:
    # two equal-offense plans; one ends on lava (damage_per_turn), one on grass
    var plan := AIPlanner.plan(_state, _unit, _fixed_rng(1), _hard())
    assert_false(_ends_on_hazard(plan))
```

### F3. Determinism & variance (GUT)
- Same seed+state → identical plan; higher temperature → more spread across repeated seeds.
- **Done:** green.

### F4. Manual human-vs-AI checklist
- [ ] AI moves, attacks, uses abilities, and defends sensibly; uses cover/high ground; avoids hazards.
- [ ] AI focuses low-HP/caster targets; heals hurt allies.
- [ ] Easy vs Hard presets feel different; AI is beatable.
- [ ] AI never stalls; battle reaches a winner.
- **Done:** checklist passes.

---

## Dependency Map

```
A (plan + enumerate) ──> B (scorer) ──> C (selection/variance) ──> D (controller) ──┐
                                                                                     ├──> F (tests)
E (integration + tunables) ──────────────────────────────────────────────────────── ┘
```

**Suggested first pass:** A1–A3 → B1–B2 → C1–C2 → D1–D2 → E1–E3 → F. Get a single unit planning legal moves before adding scoring depth and variance.

---

## Phase A7 Definition of Done

- [ ] `AIPlan`/`AIStep` + bounded, legal-only enumeration with a guaranteed fallback (A).
- [ ] `AIScorer` weighing damage/kills, exposure/positioning (A0 cover/elevation/hazard), target priority, ability value, economy (B).
- [ ] Top-N + temperature selection; difficulty presets; injected seeded RNG (C).
- [ ] `AIController` executes plans via `TurnActions` only, paced/logged like the human path, always ends the activation (D).
- [ ] Battle flow routes AI teams to `AIController`; quick-battle-from-band fields an AI opponent (E).
- [ ] Tunables + scorer weights in `constants.json` (E3).
- [ ] Enumeration-legality, scorer-sanity, and determinism/variance tests green; manual human-vs-AI checklist passed (F).
- [ ] Git tag `alpha-phaseA7-complete`.
