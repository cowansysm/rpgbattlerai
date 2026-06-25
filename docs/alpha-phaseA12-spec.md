# Phase A12 — Interactive Deployment Zones Specification

**Parent plan:** `alpha-implementation-plan.md` (new sub-phase A12)
**Master spec:** `alpha-specs.md` (combat substrate); `rpg-specs.md` (MVP deployment)
**Builds on (MVP):** `phase4` (`MatchState`, `Deployment`, `DEPLOYMENT` phase), `phase7` (`MatchBuilder`/`MatchSetup`), `phase8` (`BattleController`, map scene: `overlay_controller`, `pawn_manager`, tile picking)
**Builds on (Alpha):** A0 (terrain effects — used by the placement heuristic), A1 (map editor deployment zones), A7 (`AIController`, AI scorer concepts)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-24
**Status:** Draft v0.1

---

## 1. Purpose & Scope

Today, unit placement is **hardcoded**: `Deployment.auto_deploy()` slots `units[i] → zone_tiles[i]` during match build and immediately advances `DEPLOYMENT → ROUND_START`. Every battle on a given map starts identically. Phase A12 replaces this with **interactive deployment**: at the start of each combat, the two sides **alternately choose where to place their pawns** within their deployment zones — the human picking tiles directly, the AI choosing via a light heuristic.

This adds a meaningful pre-battle decision layer (formation, who faces what terrain, holding high ground) and makes encounters replayable.

### In scope

- A **deployment phase driver** (`DeploymentController`): per-team queues of undeployed units, legal-tile computation within each zone, **one-at-a-time alternating placement**, and completion → `ROUND_START`.
- **Alternation: AI-controlled team places first**, then human, alternating one pawn each; the larger side places its remainder at the end.
- **Locked-on-placement** (no undo/reposition once a pawn is placed).
- An **AI deployment heuristic** (`DeploymentPlanner`): front/back by role, prefer cover & high ground, avoid hazard tiles, light anti-clustering.
- **Replacement of `auto_deploy`**: the old positional slotting is removed; AI-controlled teams place via the planner (which also provides the **headless/test/AI-vs-AI** path), human teams place interactively.
- **Deployment UI** in the map scene: zone highlighting, next-pawn preview, click-to-place, AI pacing, live pawn spawning, auto-start when complete.
- **Zone-size pre-check** so a party larger than its zone fails clearly (content/map dependency).

### Out of scope

- New map authoring / zone resizing (A1/A9 content) — A12 *consumes* `map_data.deployment_zones`; it surfaces undersized zones as errors but does not re-author maps.
- Deployment items/abilities, summons, reinforcements mid-battle.
- Repositioning/undo, drag-to-place niceties (locked-on-placement by decision).
- Facing/formation bonuses beyond existing terrain effects.

### Exit criteria

1. Starting a battle enters an interactive **DEPLOYMENT** phase instead of auto-placing.
2. The **AI deploys first**; sides alternate one pawn each; the larger party finishes its remainder; placement is **locked** on commit.
3. The human places by clicking a legal tile in their **own zone**; illegal tiles are rejected; pawns appear immediately.
4. The AI places sensibly via the **role/terrain heuristic** (melee forward, ranged/casters back, prefers cover/elevation, avoids hazards).
5. When all units are placed, the match advances to **ROUND_START** and plays normally.
6. `auto_deploy`'s positional slotting is gone; AI-controlled / headless contexts deploy via the planner; existing tests are migrated.
7. Headless tests cover legal-tile rules, alternation/ordering (AI-first, unequal sizes), completion→ROUND_START, and planner placement; the suite is green.

---

## 2. Design Decisions (Phase A12)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Alternation** | **AI-controlled team first**, then human; **one pawn each**, alternating; larger side places remainder at end. | Player sees the AI commit before responding — a reactive placement game. Generalizes to PvP (the non-initiative team deploys first). |
| **Replace auto-deploy** | Remove `Deployment.auto_deploy` positional slotting; AI teams deploy via `DeploymentPlanner`; that planner is also the headless/AI-vs-AI/test path. | One placement code path; no "quick deploy" in the player flow; tests drive the planner for both teams. |
| **Locked on placement** | A committed pawn cannot be moved/undone during deployment. | Simpler UI/state; placement is a real decision. |
| **AI heuristic** | Light role + terrain heuristic (front/back, cover, elevation, hazard-avoid, anti-clustering), reusing A0 terrain data and A7 scorer ideas. | Convincing without multi-step search; tunable via weights. |
| **Pure core, thin UI** | `DeploymentController` + `DeploymentPlanner` are `RefCounted` core (no scene-tree); the map scene is a thin driver. | Matches the MVP core/UI split; fully unit-testable. |
| **Zones are the contract** | Placement is constrained to `map_data.deployment_zones[team]`; A12 validates size but does not author maps. | Keeps map content (A1/A9) decoupled; surfaces undersized zones as a clear error. |

---

## 3. Deployment Flow & State Machine

The `MatchState.Phase.DEPLOYMENT` state becomes **interactive and stateful** rather than a transient build step.

```
build match (MatchBuilder)                     # parties + map; NO auto-placement
  └─ state.phase = DEPLOYMENT
DeploymentController.begin(state, zones)        # parse zones, build per-team queues, set first team = AI team
loop while not controller.is_complete():
    team = controller.current_team()
    if team is human-controlled: await player click on a legal tile → controller.place_next(team, tile)
    else (AI):                   tile = DeploymentPlanner.choose(state, team, next_unit, legal) → place_next(team, tile)
    # alternation advances inside place_next
controller.finish() → RoundManager.start_round(state)   # phase → ROUND_START
```

- `MatchBuilder.build_match` / `build_match_from_parties` **no longer call `auto_deploy`**; they leave the state in `DEPLOYMENT` and hand back a controller (or the scene constructs one). `RoundManager.start_round` is called by `finish()`, not by the builder.
- The same loop serves headless contexts by treating *every* team as planner-driven (`auto_complete`).

---

## 4. Deployment Zones & Validation

- Zones are `map_data.deployment_zones = { "playerA": [coord strings], "playerB": [...] }` (unchanged format).
- **Pre-check at `begin()`**: for each team, `party_size ≤ zone_tiles` and all zone tiles are on the map and start unoccupied; otherwise return errors and block the battle (the run/match layer surfaces them). This replaces the per-unit error path inside `auto_deploy`.
- **Content note:** with variable band/encounter sizes (up to tier max 8–12), some authored maps may have **undersized zones**. Resizing them is an A1/A9 content task; A12 only flags the gap. `[ASSUMPTION]` Alpha maps used by the run are sized to the encounter party sizes A11 generates (≤ ~6 enemies, ≤ band field size).

---

## 5. Interactive Placement (Human)

- On the human team's turn, the UI highlights the team's **legal tiles** (zone ∩ on-map ∩ unoccupied) and previews the **next unit** in the deploy queue (band/party order).
- Clicking a legal tile **commits** that unit there (locked); the pawn spawns; terrain occupant-modifiers apply on deploy (existing `apply_terrain_modifiers_on_deploy`); alternation advances.
- Clicking an illegal tile is rejected (no state change, light feedback).
- No undo; no manual "confirm" step — when the last unit is placed the battle begins automatically.

## 6. AI Deployment Heuristic (`DeploymentPlanner`)

`choose(state, team, unit, legal_tiles) -> Vector2i` scores each legal tile and returns the best (deterministic given the run seed). Factors:

- **Front/back by role.** Compute the enemy zone centroid. **Melee/tank** units (e.g., high ATK, melee range, `physical_*`) prefer tiles **closer** to the enemy centroid; **ranged/casters** (range ≥ 2 or MAG-leaning) prefer tiles **farther** back.
- **Cover & elevation.** Prefer tiles with terrain `cover > 0` and higher elevation (consistent with A7's positional scoring and A0 terrain data).
- **Hazard avoidance.** Avoid tiles with `damage_on_enter`/`damage_per_turn`/harmful `status_on_enter`.
- **Anti-clustering.** Small penalty for tiles adjacent to already-placed allies, to spread the formation.

Weights live in `constants.json` (§9) so the formation feel is tunable. The planner is pure-ish (reads `state` for terrain/positions) and unit-testable.

> Role classification is derived from the unit's stats/class (range, ATK vs MAG, archetype) — no new data. The planner reuses terrain providers already injected into the combat layer (A0).

## 7. Alternation & Edge Cases

- **Order:** the **AI-controlled team deploys first**. In hotseat PvP (both human, MVP-retained), the **non-initiative team** deploys first (a defined, consistent order); both place interactively.
- **Unequal party sizes:** alternate one each; when a team's queue empties, the other team places its **remaining units consecutively**.
- **Both AI (headless / AI-vs-AI / tests):** `auto_complete` runs the planner for every placement, honoring the same alternation, then finishes.
- **Undersized zone / no legal tile:** `begin()` pre-check blocks; if a mid-deployment legal-tile set ever empties unexpectedly (shouldn't, given the pre-check), `finish()` errors rather than soft-locking.

---

## 8. Data Model & Touch Points

- **New core:** `src/core/combat/deployment_controller.gd` (`DeploymentController` — queues, `begin`, `legal_tiles`, `current_team`, `place_next`, `is_complete`, `finish`, `auto_complete`); `src/core/ai/deployment_planner.gd` (`DeploymentPlanner.choose`).
- **Modified core:** `src/core/combat/deployment.gd` — **remove `auto_deploy`** (or reduce to a thin `auto_complete` shim over the controller/planner); `src/core/combat/match_builder.gd` — drop the `auto_deploy` calls, leave `DEPLOYMENT`, return/expose a controller; `RoundManager.start_round` is invoked by `DeploymentController.finish()`.
- **Modified scene/UI:** `src/map/battle_controller.gd` — drive the deployment phase (zone highlights, player input, AI pacing via `AI_PACE_DELAY`, auto-start on complete); reuse `overlay_controller` (zone/legal-tile overlays), `pawn_manager`/`pawn_factory` (spawn pawns on placement), existing tile picking for input; `src/map/ai_controller.gd` may host the AI deployment call (delegating to `DeploymentPlanner`).
- **Data:** no schema change; `map_data.deployment_zones` unchanged. `constants.json` gains the deployment tunables (§9). (Optional, deferred: an `enemy`/`player` generic zone convention for run-generated maps.)
- **Validation:** keep/extend the existing map deployment-zone reference check (`validator.gd`); add the `begin()` party-vs-zone-size pre-check at match setup.

## 9. Tunables (`constants.json`)

```
DEPLOY_FIRST        = "ai"        // which side deploys first ("ai" | "player"); PvP → non-initiative team
DEPLOY_PACE_DELAY   = 0.4         // seconds between AI placements (reuse AI_PACE_DELAY default)
DEPLOY_WEIGHTS = {
  "frontline": 6.0,              // pull melee toward enemy centroid (and ranged away)
  "cover":     4.0,
  "elevation": 2.0,
  "hazard":    8.0,              // penalty for hazardous tiles
  "spacing":   2.0               // anti-clustering penalty
}
```

## 10. Migration

- Remove `Deployment.auto_deploy` from `MatchBuilder` (both build paths) and `BattleController`'s fallback.
- Update existing combat tests/fixtures that relied on `auto_deploy` to instead drive `DeploymentController.auto_complete` (planner-placed) so they remain headless.
- The run/encounter battle hand-off (A8/A11) and band quick-battle (A5) route through the new deployment phase; AI-controlled enemy bands deploy via the planner automatically, the player's fielded band deploys interactively.

## 11. Out of Scope / Future

- Map zone re-authoring (A1/A9); A12 only flags undersized zones.
- Undo/reposition, drag placement, formation presets/templates.
- Facing/flanking systems; deployment-time abilities or terrain alteration.
- Networked deployment (multiplayer remains deferred).

## 12. Requirements Traceability

| # | Requirement | Where addressed |
|---|-------------|-----------------|
| 1 | Player chooses pawn placement at combat start | §3, §5 |
| 2 | Replace hardcoded/identical spawns | §1, §10 |
| 3 | Player **and** AI each choose placement | §5, §6 |
| 4 | Alternating placement | §3, §7 |
| D1 | AI deploys first, one pawn each | §2, §7 |
| D2 | Auto-deploy replaced entirely | §2, §8, §10 |
| D3 | Locked on placement (no undo) | §2, §5 |
| D4 | Light role/terrain AI heuristic | §6, §9 |
