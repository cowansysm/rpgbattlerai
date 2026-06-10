# Phase 4 — Combat Core: Activation & Action Economy Specification

**Parent plan:** `rpg-implementation-plan.md` (Phase 4)
**Builds on:** `phase0-spec.md` (hex math), `phase1-spec.md` (data layer, `BattleUnit` skeleton), `phase2-spec.md` (rendered map, tiles), `phase3-spec.md` (movement, range, LoS, overlays)
**Source spec:** `rpg-specs.md` (§7.1–7.4, §9.6)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-03

---

## 1. Purpose & Scope

Phase 4 makes the **turn structure** real. On top of the spatial rules from Phase 3, it implements match setup with deployment zones, the alternating-activation round loop, and the 2 AP action economy. Characters are placed on the map, take turns activating, and spend AP on the core action catalog. It does **not** resolve damage, apply status effects, or compute accuracy — those are Phase 5.

Phase 4 is validated by two manually controlled parties alternating activations through a full round, spending AP on moves and basic actions, with correct spent/reset cycling between rounds.

### In scope

- A **match state machine** managing match lifecycle: setup → deployment → rounds → (end).
- **Deployment**: placing characters from both parties into their map's deployment zones.
- **First-activation determination**: comparing highest SPD per party; ties broken randomly.
- **Alternating activation round loop**: players take turns activating one un-activated character; uneven party sizes handled by consecutive activations; spent/reset cycle at round boundaries.
- **2 AP action economy**: each activated character has 2 AP to spend on the action catalog.
- **Action catalog** (structural, not resolution): Move, Attack, Ability/Spell, Use Item, Defend/Overwatch, Wait — each with AP cost and validation (range, LoS, AP remaining), but no damage/heal computation.
- **Per-ability AP restrictions**: abilities may cost 2 AP or restrict combination with other actions.
- **Unit occupancy**: tiles occupied by units block movement (not LoS); deployed units registered on the graph.

### Out of scope

- Damage formulas, accuracy rolls, healing, HP reduction, downing (Phase 5).
- Status effects, elemental interactions, area-of-effect resolution (Phase 5).
- Victory conditions, rout detection, match-end logic (Phase 9).
- Party building UI, drafting flow (Phase 7).
- AI decision-making, animations, combat log presentation (later phases).

### Exit criteria

Phase 4 is complete when:

1. Two parties can be deployed into a map's deployment zones with BattleUnit instances placed on valid tiles.
2. First activation is determined by comparing highest SPD; ties broken randomly.
3. Players alternate activating one un-activated character per turn; the round ends when all characters are spent; a new round begins with all characters reset.
4. Uneven party sizes are handled: the player with remaining un-activated characters takes consecutive activations.
5. An activated character has 2 AP; the action catalog (Move, Attack, Ability, Item, Defend, Wait) correctly validates and deducts AP.
6. Move actions use the Phase 3 movement system (reachable set, pathfinding) and update the unit's position on the graph.
7. Attack and Ability actions validate range + LoS but do **not** resolve damage (they log "would hit" for verification).
8. Defend grants a temporary +DEF modifier via the StatBlock modifier stack; Wait ends the activation with unspent AP.
9. Unit occupancy is enforced: occupied tiles are not valid move destinations.
10. Pure logic (match state, activation order, AP spending, action validation) is unit-tested headless; a manual demo validates the full round loop.

---

## 2. Design Decisions (Phase 4)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Match state machine** | A `MatchState` class holds the authoritative match state (parties, round number, activation queue, current unit). State transitions are explicit methods, not implicit scene-tree manipulation. | Keeps combat logic testable without a running scene. The state machine is the source of truth; UI observes it. |
| **Activation order** | A simple queue: at round start, all non-downed units are shuffled into an activation queue ordered by team alternation, starting with the initiative holder. When one team runs out, the other takes consecutive turns. | Matches spec §7.3. No CT clock — SPD determines first activation and movement, not turn frequency. |
| **Action system** | Actions are validated and executed through a `TurnActions` static class. Each action method checks preconditions (AP, range, LoS, occupancy) and returns success/failure. On success it mutates `BattleUnit` state (position, AP, modifiers) and emits an action record. | Separates validation from resolution. Phase 5 adds resolution (damage, healing) without changing the action validation API. |
| **Action records** | Each executed action produces a `Dictionary` record (`{action, actor, target, ...}`) appended to a turn log. Phase 4 records structural data only (who did what, where); Phase 5 adds outcome fields (damage dealt, HP remaining). | Provides an auditable trail for testing and future combat log UI. |
| **Defend / Overwatch** | MVP Defend pushes a `StatModifier("def", +2, "defend")` onto the unit's modifier stack, removed at the unit's next activation start. Overwatch is deferred to a later phase (requires reaction triggers). | Keeps Phase 4 simple. The modifier stack from Phase 1 already supports push/pop by source. |
| **Unit occupancy** | Occupied tiles are excluded from reachable-set computation and pathfinding. LoS is **not** blocked by units (MVP simplification). | Prevents stacking; future phases may add unit-based LoS blocking or zone-of-control. |
| **Initiative** | MVP: initiative alternates each round (spec §7.3 default). The player who goes second in round N goes first in round N+1. | Simple, fair; configurable constant for future variants. |
| **Deployment** | Characters are placed onto deployment-zone tiles in order. Validation ensures no two units occupy the same tile, the tile is in the correct zone, and the zone has enough tiles for the party. | Uses existing `MapData.deployment_zones` (authored in Phase 1, validated in Phase 1). |

---

## 3. Match State Machine

### 3.1 States

The match progresses through a linear sequence of phases:

| State | Description | Transitions to |
|-------|-------------|----------------|
| `SETUP` | Match created, parties assigned, map loaded. | `DEPLOYMENT` |
| `DEPLOYMENT` | Players place characters into deployment zones. | `ROUND_START` |
| `ROUND_START` | New round begins: increment round counter, reset all units' `is_activated`, build activation queue. | `AWAITING_ACTIVATION` |
| `AWAITING_ACTIVATION` | Waiting for the current player to choose which of their un-activated characters to activate. | `UNIT_TURN` |
| `UNIT_TURN` | The chosen character spends AP on actions. | `AWAITING_ACTIVATION` (if more units remain) or `ROUND_START` (if all spent) |
| `MATCH_OVER` | Terminal state (Phase 9 adds victory logic). | — |

### 3.2 `MatchState` data

```
round_number: int               # Current round (1-indexed)
phase: String                   # Current state machine phase
parties: Dictionary             # {"playerA": Array[BattleUnit], "playerB": Array[BattleUnit]}
initiative: String              # Team ID ("playerA" or "playerB") with first activation
activation_queue: Array         # Ordered list of [team, unit] pairs for the current round
current_index: int              # Index into activation_queue
current_unit: BattleUnit        # The unit currently being activated (null between activations)
turn_log: Array                 # Action records for the current turn
match_log: Array                # All action records across all rounds
graph: HexGraph                 # The map's hex graph (from Phase 3)
occupancy: Dictionary           # Vector2i -> BattleUnit (tracks which unit is on which tile)
```

### 3.3 Round lifecycle

1. **Round start**: `round_number += 1`. All living units: `is_activated = false`, `ap_remaining = 2`. Remove expired modifiers (e.g., Defend). Build activation queue (§4).
2. **Activation loop**: Pop next entry from queue → set `current_unit` → unit spends AP → mark `is_activated = true` → advance queue. Repeat until queue empty.
3. **Round end**: When all units are spent, transition to `ROUND_START` for the next round. Flip initiative.

---

## 4. Alternating Activation

### 4.1 Building the activation queue

At round start, given initiative holder `I` and other team `O`:

1. Collect all un-activated (living) units for team `I` and team `O`.
2. Interleave: `I[0], O[0], I[1], O[1], ...`
3. When one team is exhausted, append remaining units from the other team consecutively.

The queue does not prescribe *which* unit — only *which team* activates next. Within their turn, a player chooses which of their un-activated units to activate.

### 4.2 First activation (match start)

Determined once at match setup:

1. Compare the **highest SPD** across each party's roster.
2. Higher SPD party has initiative.
3. Ties: random coin flip.

### 4.3 Initiative alternation

After each round, initiative passes to the other team. MVP default; a future constant can make this configurable.

### 4.4 Uneven party sizes

Handled naturally by the interleaving algorithm (§4.1): once one team's slots are filled, remaining slots go to the other team. No special-casing needed.

---

## 5. Action Economy — 2 AP

### 5.1 AP rules

- Each activation starts with `ap_remaining = 2`.
- Actions deduct their AP cost. An action is invalid if `ap_remaining < cost`.
- **Wait** (0 AP) ends the activation immediately, forfeiting remaining AP.
- An activation ends when `ap_remaining == 0` or the player chooses Wait.

### 5.2 Action catalog

| Action | AP cost | Validation | State mutation | Notes |
|--------|---------|------------|----------------|-------|
| **Move** | 1 | Start tile matches unit position; destination in reachable set (budget=Move, jump=Jump/Climb); destination not occupied. | Update `unit.position`, update `occupancy` dict. | May be taken twice (both AP on movement). |
| **Attack** | 1 | Target unit exists, is enemy, within weapon RNG, has LoS from attacker position. | *Phase 4: log record only, no damage.* Phase 5 adds resolution. | Basic weapon attack. |
| **Ability / Spell** | Per ability (`ap_cost` field) | Target(s) valid per ability rules (range, LoS, area). Enough AP remaining. Per-ability restrictions (e.g., "cannot combine with Move"). | *Phase 4: log record only.* Phase 5 resolves effects. | `ap_cost` from `AbilityData`. |
| **Use Item** | 1 | Item exists in loadout, has a granted ability, target valid. | *Phase 4: log record only.* | Item-bound ability activation. |
| **Defend** | 1 | Unit has AP remaining. | Push `StatModifier("def", +2, "defend")` onto stat block. | Modifier removed at unit's next activation start. |
| **Wait** | 0 | Always valid. | Set `ap_remaining = 0`. | Ends activation immediately. |

### 5.3 Per-ability AP restrictions

Abilities define their AP cost in `AbilityData.ap_cost`. Additional restrictions are encoded as flags:

- `ap_cost: 2` — the ability costs both AP (e.g., powerful spells like Fire 2).
- Future: `"restrict_with_move": true` — cannot be used in the same activation as a Move action. (Deferred; Phase 4 validates only AP cost.)

### 5.4 Action validation flow

For each action request:

1. Check `current_unit.ap_remaining >= action.ap_cost`.
2. Check action-specific preconditions (range, LoS, occupancy, target validity).
3. If valid: execute mutation, deduct AP, append action record to turn log.
4. If invalid: return error string describing the failure.

---

## 6. Deployment

### 6.1 Deployment zones

Each map defines `deployment_zones: {"playerA": [...], "playerB": [...]}` where each value is an array of coordinate strings (e.g., `"0,-4"`). These are validated at data load (Phase 1) to reference existing tiles.

### 6.2 Deployment process

1. For each party, the player places characters one at a time onto tiles in their deployment zone.
2. **Constraints**: the target tile must be in the party's zone and not already occupied.
3. All characters must be placed before transitioning to `ROUND_START`.
4. **MVP simplification**: auto-deploy characters in party order onto available zone tiles (no player choice UI). Manual placement is a future enhancement.

### 6.3 Deployment validation

- Party size ≤ number of tiles in the deployment zone.
- No two units on the same tile.
- Each tile is within the party's designated zone.
- After deployment, the `occupancy` dictionary is populated and the graph reflects unit positions.

---

## 7. Unit Occupancy

### 7.1 Occupancy tracking

A `Dictionary[Vector2i, BattleUnit]` tracks which unit (if any) occupies each tile. Updated on:

- **Deployment**: when a unit is placed.
- **Move action**: old tile cleared, new tile set.
- **Unit removal** (Phase 5): tile cleared when a unit is downed.

### 7.2 Movement exclusion

Occupied tiles are excluded from the reachable set. When computing `Movement.reachable()`, any tile that has an entry in the occupancy dict (and the occupant is not the moving unit) is treated as impassable for movement purposes. Units do **not** block LoS in the MVP.

### 7.3 Integration with HexGraph

Rather than modifying `HexGraph` to be occupancy-aware (which would couple spatial rules to combat state), occupancy filtering is applied **at the action level**: the reachable set is computed normally, then occupied tiles are subtracted. This keeps Phase 3 code unchanged and occupancy as a Phase 4 concern.

---

## 8. Data Flow & Integration

### 8.1 From prior phases

| Source | Data consumed |
|--------|---------------|
| Phase 0 | `Hex.distance()`, `Hex.neighbors()` |
| Phase 1 | `CharacterData`, `AbilityData`, `ItemData`, `MapData`, `BattleUnit.from_character()`, `StatBlock`, `StatModifier`, `GameData` facade |
| Phase 2 | `MapBuilder` (tile rendering, for future UI) |
| Phase 3 | `HexGraph`, `Movement.reachable()`, `Movement.path()`, `RangeQuery.in_range()`, `RangeQuery.effective_range()`, `LineOfSight.has_los()` |

### 8.2 New data authored

- No new data files. Phase 4 consumes existing character, ability, item, and map data. The `AbilityData.ap_cost` field (authored in Phase 1) becomes meaningful this phase.

### 8.3 Outputs

- `MatchState`: authoritative state of the match, observable by UI/AI.
- Action records (turn log): structured dictionaries recording each action taken.
- `BattleUnit` mutations: position, AP, is_activated, stat modifiers.

---

## 9. Risks & Notes

- **No damage resolution.** Phase 4 validates actions and logs "would hit" records. Attack/Ability actions succeed structurally but produce no HP change. Phase 5 adds resolution without changing the action validation API.
- **Occupancy filtering at action level.** Filtering occupied tiles outside `HexGraph` means the AStar3D pathfinding doesn't know about occupancy. The `Movement.path()` result may route through occupied tiles. Mitigation: Phase 4 validates that the **destination** is unoccupied; intermediate tiles on the path are allowed (units can move through friendly units in many tactics games). If blocking is needed later, a filtered-graph wrapper can be introduced.
- **Auto-deployment.** MVP skips manual placement UI; characters are placed automatically. This is sufficient for testing and AI-vs-AI matches. Manual deployment is a Phase 7+ concern.
- **No reaction system.** Overwatch (reaction to enemy movement) is deferred. MVP Defend is a simple +DEF modifier, not a triggered reaction. The action record system provides a hook for future reaction triggers.
- **Ability restriction flags.** Only `ap_cost` is validated in Phase 4. Complex restrictions ("cannot combine with Move", "must be first action") are deferred. The action record trail makes it possible to add retrospective validation later.
- **State machine testability.** `MatchState` is a plain object with no scene-tree dependencies. All state transitions are testable headlessly through method calls.
- **Initiative alternation.** The spec (§7.3) leaves the rule configurable. MVP uses strict alternation; a constant can switch to "last-to-finish goes first" if preferred during balancing.

---

## 10. Phase 4 Deliverables Checklist

- [ ] `MatchState` class with explicit state machine (setup → deployment → rounds → match over) (§3).
- [ ] Deployment system: auto-place units into deployment zones with occupancy tracking (§6).
- [ ] First-activation determination by highest SPD with random tie-break (§4.2).
- [ ] Alternating activation queue with interleaving and consecutive-turn handling for uneven parties (§4.1, §4.4).
- [ ] Round lifecycle: spent/reset cycle, initiative alternation (§3.3, §4.3).
- [ ] 2 AP action economy with the full action catalog: Move, Attack, Ability, Item, Defend, Wait (§5).
- [ ] Move action integrates with Phase 3 movement (reachable set, path, position update) (§5.2).
- [ ] Attack and Ability actions validate range + LoS, log action records without resolving damage (§5.2).
- [ ] Defend pushes a +DEF modifier via StatBlock modifier stack, removed at next activation (§5.2).
- [ ] Unit occupancy tracking: occupied tiles excluded from movement destinations (§7).
- [ ] Action validation flow with precondition checking and error reporting (§5.4).
- [ ] GUT tests for match state, activation order, AP spending, action validation, occupancy (headless, no autoload); manual demo validates full round loop.
- [ ] Git tag `phase-4-complete`.
