# Phase A12 — Implementation Plan

**Source spec:** `alpha-phaseA12-spec.md`
**Builds on (MVP):** `phase4` (`MatchState`, `Deployment`, `DEPLOYMENT` phase), `phase7` (`MatchBuilder`/`MatchSetup`), `phase8` (`BattleController`, `overlay_controller`, `pawn_manager`, tile picking)
**Builds on (Alpha):** A0 (terrain effects), A1 (map editor zones), A7 (`AIController`)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-06-24

---

## How to use this plan

Six **work groups** (A–F):

- **A — Deployment controller** is the load-bearing core (queues, legal tiles, alternation, completion). Pure; unblocks everything.
- **B — AI deployment planner** scores tiles for AI placement; also the headless/test path.
- **C — Match-build integration** removes `auto_deploy`, leaves the state in `DEPLOYMENT`, and routes completion to `ROUND_START`.
- **D — Deployment UI** drives the phase in the map scene (zone highlights, click-to-place, AI pacing, live pawns).
- **E — Migration & validation** removes the old path, fixes tests, adds the zone-size pre-check.
- **F — Tests & verification** locks the rules.

Each task lists a **done state**. A/B are `RefCounted` core (no scene tree); D is a thin scene driver. Decision recap: **AI deploys first**, one pawn each; **auto-deploy is replaced**; **locked on placement**; **light role/terrain AI heuristic**.

> **Carry-over:** placement reuses `state.graph` (on-map/occupancy), `map_data.deployment_zones`, `TurnActions.apply_terrain_modifiers_on_deploy` (A0), `RoundManager.start_round` (to begin combat), and the A7 `AIController` for pacing/feedback. No new data schema.

---

## Group A — Deployment Controller (core)

*Pure `RefCounted`. Unblocks B–F.*

### A1. Controller skeleton + zone parsing + pre-check
- Parse `deployment_zones[team]` to `Array[Vector2i]`; build per-team **queues** of undeployed units (party order); validate each team's `party_size ≤ zone_tiles`, tiles on-map and unoccupied.
- **Done:** `begin()` returns errors for undersized/invalid zones; otherwise leaves `state.phase = DEPLOYMENT` ready to place.

```gdscript
# src/core/combat/deployment_controller.gd
class_name DeploymentController
extends RefCounted

var _state: MatchState
var _queue: Dictionary = {}          # team -> Array[BattleUnit] (undeployed, in order)
var _zone: Dictionary = {}           # team -> Array[Vector2i]
var _turn_team: String = ""
var first_team: String = "playerB"   # AI/non-initiative team; resolved in begin()

func begin(state: MatchState, zones: Dictionary, ai_teams: Array) -> Array[String]:
    _state = state
    state.phase = MatchState.Phase.DEPLOYMENT
    var errors: Array[String] = []
    for team in ["playerA", "playerB"]:
        _zone[team] = _parse_zone(zones.get(team, []))
        _queue[team] = (state.parties.get(team, []) as Array).duplicate()
        if _queue[team].size() > _zone[team].size():
            errors.append("Team '%s': %d units > %d zone tiles" % [team, _queue[team].size(), _zone[team].size()])
    first_team = _resolve_first(ai_teams)
    _turn_team = first_team
    return errors
```

### A2. Legal tiles + placement
- `legal_tiles(team)` = zone tiles on-map and unoccupied. `place_next(team, tile)` validates, assigns the team's next queued unit, sets occupancy, applies terrain modifiers on deploy, pops the queue, and **advances the turn** (alternate; skip a team whose queue is empty).
- **Done:** placing into a legal tile commits the next unit; illegal tile → error/no-op; turn advances per alternation.

```gdscript
func legal_tiles(team: String) -> Array[Vector2i]:
    return (_zone.get(team, []) as Array).filter(
        func(t): return _state.graph.has_tile(t) and not _state.is_occupied(t))

func place_next(team: String, tile: Vector2i) -> Array[String]:
    if team != _turn_team: return ["not %s's turn" % team]
    if _queue[team].is_empty(): return ["%s has no units to place" % team]
    if tile not in legal_tiles(team): return ["illegal tile %s" % str(tile)]
    var unit: BattleUnit = _queue[team].pop_front()
    unit.position = tile
    _state.occupancy[tile] = unit
    TurnActions.apply_terrain_modifiers_on_deploy(unit, _state.graph)
    _advance_turn()
    return []
```

### A3. Alternation + completion
- `_advance_turn()` flips to the other team if it still has units, else stays; `current_team()` returns the team to act (or `""`); `is_complete()` when both queues empty; `finish()` asserts completion and calls `RoundManager.start_round(state)` (→ `ROUND_START`).
- **Done:** AI-first one-each alternation; larger side finishes remainder; completion advances to ROUND_START.

### A4. Headless `auto_complete`
- `auto_complete(planner)` loops: while not complete, ask the planner (B) for the current team's tile and `place_next`, then `finish()`. Used by AI-vs-AI / headless / tests (replaces `auto_deploy`).
- **Done:** a match with no UI fully deploys via the planner and starts.

---

## Group B — AI Deployment Planner

*Depends on A. Pure-ish (reads state for terrain/positions).*

### B1. Tile scoring
- `choose(state, team, unit, legal_tiles) -> Vector2i`: score each legal tile by front/back (role vs enemy-zone centroid), cover, elevation, hazard penalty, anti-clustering; return the best (seeded tie-break).
- **Done:** melee pick forward tiles, ranged/casters pick back tiles; cover/high ground preferred; hazards avoided.

```gdscript
# src/core/ai/deployment_planner.gd
class_name DeploymentPlanner
extends RefCounted

static func choose(state: MatchState, team: String, unit: BattleUnit, legal: Array, w: Dictionary) -> Vector2i:
    var enemy_centroid := _centroid(state, _other(team))
    var melee := _is_frontline(unit)            # range<=1 / ATK-leaning / physical_*
    var best: Vector2i = legal[0]; var best_s := -INF
    for t in legal:
        var s := 0.0
        var d := float(Hex.distance(t, enemy_centroid))
        s += (-d if melee else d) * float(w.get("frontline", 6.0)) * 0.1
        s += state.graph.cover(t) * float(w.get("cover", 4.0))
        s += state.graph.elevation(t) * float(w.get("elevation", 2.0))
        if state.graph.is_hazard(t): s -= float(w.get("hazard", 8.0))
        s -= _adjacent_allies(state, team, t) * float(w.get("spacing", 2.0))
        if s > best_s: best_s = s; best = t
    return best
```

### B2. Role classification + terrain reads
- `_is_frontline(unit)` from range/ATK-vs-MAG/archetype; cover/elevation/hazard read via the injected terrain provider (A0). No new data.
- **Done:** classification and terrain reads return sensible values on the existing maps.

---

## Group C — Match-Build Integration

*Depends on A.*

### C1. Stop auto-deploying in the builder
- `MatchBuilder.build_match` and `build_match_from_parties`: remove the `Deployment.auto_deploy` calls and the `RoundManager.start_round` call; leave `state.phase = DEPLOYMENT`; return the state (deployment driven by the scene or `auto_complete`).
- **Done:** a freshly built match is in DEPLOYMENT with undeployed parties.

### C2. Controller construction + AI-team awareness
- Construct a `DeploymentController`, call `begin(state, map.deployment_zones, MatchData.ai_teams)`; expose it to the caller (scene). Headless callers immediately `auto_complete`.
- **Done:** the builder/caller has a ready controller and knows which team(s) are AI.

---

## Group D — Deployment UI (map scene)

*Depends on A, B, C.*

### D1. Phase entry + zone/legal highlights
- On entering DEPLOYMENT, render the **active team's** legal tiles via `overlay_controller`; show remaining-to-place counts and the next unit preview.
- **Done:** the player sees exactly where they may place and what comes next.

### D2. Player placement input
- On the human team's turn, a click on a legal tile calls `place_next`; spawn the pawn (`pawn_manager`/`pawn_factory`); refresh highlights; advance. Illegal clicks give light feedback; no undo.
- **Done:** the human deploys their band one pawn at a time, locked.

### D3. AI placement turn
- On the AI team's turn, after `DEPLOY_PACE_DELAY`, call `DeploymentPlanner.choose` → `place_next`; spawn the pawn with feedback (reuse `AIController` pacing).
- **Done:** the AI visibly places each pawn; alternation reads clearly.

### D4. Auto-start on completion
- When `is_complete()`, call `finish()` (→ ROUND_START) and hand off to the normal battle loop. No manual confirm.
- **Done:** deployment flows straight into round 1.

---

## Group E — Migration & Validation

*Depends on A–C.*

### E1. Remove the old path
- Delete `Deployment.auto_deploy` (or reduce to a thin `auto_complete` shim); remove the `BattleController` fallback that called it.
- **Done:** no caller references the old positional slotting.

### E2. Update tests/fixtures
- Repoint combat tests that assumed `auto_deploy` to `DeploymentController.auto_complete(planner)` so they remain headless and deterministic.
- **Done:** the existing combat/integration suite builds matches via the new path.

### E3. Zone-size pre-check surfacing
- Ensure `begin()` errors propagate to the match/run layer (block the battle with a clear message); keep the map-load deployment-zone reference check in `validator.gd`.
- **Done:** an undersized zone fails loudly at setup, not mid-battle.

---

## Group F — Tests & Verification

### F1. Controller tests (GUT)
- Legal tiles exclude occupied/off-map; `place_next` rejects illegal tiles and wrong-team turns; **AI-first** order; one-each alternation; larger side finishes remainder; `is_complete`/`finish` → ROUND_START; undersized-zone errors.
- **Done:** green.

```gdscript
# tests/core/combat/test_deployment_controller.gd
func test_ai_first_alternation():
    var c := _begin_2v2(ai=["playerB"])
    assert_eq(c.current_team(), "playerB")
    c.place_next("playerB", _legal(c,"playerB")[0])
    assert_eq(c.current_team(), "playerA")

func test_larger_side_finishes_remainder():
    var c := _begin(sizes={"playerA":3,"playerB":1}, ai=["playerB"])
    # B(1) then A(3): B places, A places, (B empty) A places, A places
    ...
```

### F2. Planner tests (GUT)
- Frontline units pick tiles nearer the enemy centroid; ranged/casters pick farther; cover/elevation preferred; hazard tiles avoided; deterministic given seed.
- **Done:** green.

### F3. Integration tests (GUT)
- `auto_complete` deploys both AI teams and reaches ROUND_START; a built match starts in DEPLOYMENT (no auto-placement); terrain modifiers applied on deploy.
- **Done:** green.

### F4. Manual checklist
- [ ] Battle opens in deployment; AI places its first pawn, then the player places, alternating.
- [ ] Only legal zone tiles are selectable; placed pawns are locked.
- [ ] AI melee deploy forward, ranged/casters back; AI favors cover/high ground, avoids hazards.
- [ ] Unequal party sizes: the larger side finishes its remainder.
- [ ] All placed → round 1 begins automatically; combat plays normally.
- [ ] Undersized zone → clear error, battle blocked.
- **Done:** checklist passes.

---

## Dependency Map

```
A (controller) ──┬──> C (build integration) ──> D (deployment UI) ──┐
                 ├──> B (AI planner) ───────────────────────────────┤
                 └──> E (migration & validation)                    ├──> F (tests)
B ──> A4 (auto_complete) ──────────────────────────────────────────┘
```

**Suggested first pass:** A1–A4 → F1 → B1–B2 → F2 → C1–C2 → E1–E3 → D1–D4 → F3–F4. Lock the controller (with tests) before the UI and migration ride on it; build the planner early so `auto_complete` keeps headless tests green.

---

## Phase A12 Definition of Done

- [ ] `DeploymentController`: zone parse + pre-check; legal tiles; `place_next` with validation + terrain-on-deploy; **AI-first** one-each alternation; larger side remainder; `finish()` → ROUND_START (A).
- [ ] `DeploymentPlanner`: role front/back, cover, elevation, hazard-avoid, anti-clustering; deterministic; `auto_complete` deploys AI/headless (B, A4).
- [ ] `MatchBuilder` no longer auto-deploys; match starts in DEPLOYMENT; controller wired with `ai_teams` (C).
- [ ] Deployment UI: zone/legal highlights, next-unit preview, click-to-place (locked), AI pacing, auto-start on completion (D).
- [ ] `auto_deploy` removed; combat tests migrated to `auto_complete`; zone-size errors surfaced at setup (E).
- [ ] `DEPLOY_*` tunables in `constants.json`; controller/planner/integration tests green; manual checklist passed (F).
- [ ] Git tag `alpha-phaseA12-complete`.
