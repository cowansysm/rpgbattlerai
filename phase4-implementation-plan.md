# Phase 4 — Implementation Plan

**Source spec:** `phase4-spec.md`
**Builds on:** `phase0` (hex math), `phase1` (data layer, `BattleUnit`), `phase2` (rendered map), `phase3` (movement, range, LoS, overlays)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-06-03

---

## How to use this plan

Seven **work groups** (A–G). Within a group, tasks can be done in any order unless noted. Across groups: **A** (match state) is the foundation; **B** (deployment) needs A; **C** (activation loop) needs A + B; **D** (action system) needs C + Phase 3 spatial rules; **E** (individual actions) needs D; **F** (demo wiring) ties it together; **G** (tests) trails the logic.

Each task lists a **done state**. Code stubs are Godot 4 / GDScript — drop-in starting points. All combat logic is unit-testable without a running scene (no autoload dependency for tests). Phase 4 validates action structure but does **not** resolve damage — Attack/Ability actions log records and succeed structurally.

> **Carry-over:** consumes `BattleUnit`, `StatBlock`, `StatModifier`, `CharacterData`, `AbilityData`, `ItemData`, `MapData` from Phase 1; `HexGraph`, `Movement`, `RangeQuery`, `LineOfSight` from Phase 3; `GameData` facade. The `BattleUnit` already has `position`, `current_hp`, `ap_remaining`, `is_activated`, `team` fields from Phase 1's skeleton.

---

## Group A — Match State Machine

*Foundation for all combat flow. No dependencies beyond Phase 1 data types.*

### A1. `MatchState` — core state container

- Holds parties, round number, activation queue, occupancy, current unit, logs.
- Explicit state transitions via methods. No scene-tree dependency.
- **Done:** can create a `MatchState`, assign parties, and query state fields.

```gdscript
# src/core/combat/match_state.gd
class_name MatchState
extends RefCounted

enum Phase { SETUP, DEPLOYMENT, ROUND_START, AWAITING_ACTIVATION, UNIT_TURN, MATCH_OVER }

var phase: int = Phase.SETUP
var round_number: int = 0
var parties: Dictionary = {}           # "playerA" -> Array[BattleUnit], "playerB" -> Array[BattleUnit]
var initiative: String = ""            # Team with first activation this round
var activation_queue: Array = []       # Array of team strings, interleaved
var current_index: int = 0
var current_unit: BattleUnit = null
var turn_log: Array = []               # Action records for current turn
var match_log: Array = []              # All action records
var graph: HexGraph = null
var occupancy: Dictionary = {}         # Vector2i -> BattleUnit

func living_units(team: String) -> Array:
    return parties.get(team, []).filter(func(u: BattleUnit) -> bool: return u.current_hp > 0)

func unactivated_units(team: String) -> Array:
    return living_units(team).filter(func(u: BattleUnit) -> bool: return not u.is_activated)

func unit_at(pos: Vector2i) -> BattleUnit:
    return occupancy.get(pos, null)

func is_occupied(pos: Vector2i) -> bool:
    return occupancy.has(pos)
```

### A2. `MatchSetup` — match initialization

- Creates a `MatchState` from two party arrays, a `MapData`, and terrain provider.
- Builds the `HexGraph`, determines first activation (highest SPD comparison, random tie-break).
- **Done:** `MatchSetup.create()` returns a `MatchState` in `SETUP` phase with initiative assigned.

```gdscript
# src/core/combat/match_setup.gd
class_name MatchSetup
extends RefCounted

static func create(
    party_a: Array[BattleUnit],
    party_b: Array[BattleUnit],
    map_data: MapData,
    terrain_provider: Callable
) -> MatchState:
    var state := MatchState.new()
    state.parties = { "playerA": party_a, "playerB": party_b }

    # Tag units with their team
    for u in party_a: u.team = "playerA"
    for u in party_b: u.team = "playerB"

    # Build graph
    state.graph = HexGraph.new()
    state.graph.build(map_data, terrain_provider)

    # Determine initiative: highest SPD wins; ties random
    state.initiative = _determine_initiative(party_a, party_b)
    return state

static func _determine_initiative(a: Array, b: Array) -> String:
    var max_a := 0
    for u in a: max_a = max(max_a, u.stats.effective_move())
    var max_b := 0
    for u in b: max_b = max(max_b, u.stats.effective_move())
    if max_a > max_b: return "playerA"
    if max_b > max_a: return "playerB"
    return "playerA" if randi() % 2 == 0 else "playerB"
```

---

## Group B — Deployment

*Depends on A. Places units onto deployment-zone tiles.*

### B1. `Deployment` — auto-deploy units

- Places each party's units onto their deployment-zone tiles in order.
- Validates: zone tiles exist on graph, no double-occupancy, party fits in zone.
- Updates `MatchState.occupancy` and each `BattleUnit.position`.
- Transitions state from `SETUP` to `DEPLOYMENT` to `ROUND_START`.
- **Done:** after deploy, all units have valid positions, occupancy dict is populated, state is `ROUND_START`.

```gdscript
# src/core/combat/deployment.gd
class_name Deployment
extends RefCounted

static func auto_deploy(state: MatchState, zones: Dictionary) -> Array[String]:
    var errors: Array[String] = []
    state.phase = MatchState.Phase.DEPLOYMENT

    for team in ["playerA", "playerB"]:
        var units: Array = state.parties.get(team, [])
        var zone_strs: Array = zones.get(team, [])
        var zone_tiles: Array[Vector2i] = []
        for s in zone_strs:
            var parts := str(s).split(",")
            zone_tiles.append(Vector2i(int(parts[0]), int(parts[1])))

        if units.size() > zone_tiles.size():
            errors.append("Team '%s' has %d units but only %d zone tiles" % [team, units.size(), zone_tiles.size()])
            continue

        for i in range(units.size()):
            var tile: Vector2i = zone_tiles[i]
            if not state.graph.has_tile(tile):
                errors.append("Zone tile %s not on map for team '%s'" % [str(tile), team])
                continue
            if state.is_occupied(tile):
                errors.append("Zone tile %s already occupied for team '%s'" % [str(tile), team])
                continue
            units[i].position = tile
            state.occupancy[tile] = units[i]

    if errors.is_empty():
        state.phase = MatchState.Phase.ROUND_START
    return errors
```

---

## Group C — Activation Loop

*Depends on A + B. Implements the alternating activation round structure.*

### C1. `RoundManager` — round lifecycle

- Starts a new round: increments counter, resets all units, removes expired modifiers (Defend), builds activation queue.
- Advances through the queue, letting each team choose a unit to activate.
- Ends the round when the queue is exhausted; flips initiative.
- **Done:** a full round cycles through all living units, alternating teams, with correct spent/reset.

```gdscript
# src/core/combat/round_manager.gd
class_name RoundManager
extends RefCounted

static func start_round(state: MatchState) -> void:
    state.round_number += 1
    state.phase = MatchState.Phase.ROUND_START

    # Reset all living units
    for team in state.parties.keys():
        for u: BattleUnit in state.living_units(team):
            u.is_activated = false
            u.ap_remaining = 2
            # Remove defend modifiers from previous round
            u.stats.remove_modifiers_by_source("defend")

    # Build activation queue (team strings, interleaved)
    state.activation_queue = _build_queue(state)
    state.current_index = 0
    state.current_unit = null
    state.phase = MatchState.Phase.AWAITING_ACTIVATION

static func _build_queue(state: MatchState) -> Array:
    var init_team: String = state.initiative
    var other_team: String = "playerB" if init_team == "playerA" else "playerA"
    var count_i: int = state.unactivated_units(init_team).size()
    var count_o: int = state.unactivated_units(other_team).size()
    var queue: Array = []
    var i := 0
    var o := 0
    while i < count_i or o < count_o:
        if i < count_i:
            queue.append(init_team)
            i += 1
        if o < count_o:
            queue.append(other_team)
            o += 1
    return queue

static func current_team(state: MatchState) -> String:
    if state.current_index >= state.activation_queue.size():
        return ""
    return str(state.activation_queue[state.current_index])

static func activate_unit(state: MatchState, unit: BattleUnit) -> String:
    var team := current_team(state)
    if team.is_empty():
        return "No more activations this round"
    if unit.team != team:
        return "It is %s's turn to activate, not %s's" % [team, unit.team]
    if unit.is_activated:
        return "Unit '%s' is already activated this round" % unit.character.id
    if unit.current_hp <= 0:
        return "Unit '%s' is downed" % unit.character.id

    state.current_unit = unit
    state.turn_log = []
    state.phase = MatchState.Phase.UNIT_TURN
    return ""

static func end_activation(state: MatchState) -> void:
    if state.current_unit:
        state.current_unit.is_activated = true
        state.current_unit.ap_remaining = 0
        state.match_log.append_array(state.turn_log)
    state.current_unit = null
    state.current_index += 1

    if state.current_index >= state.activation_queue.size():
        _end_round(state)
    else:
        state.phase = MatchState.Phase.AWAITING_ACTIVATION

static func _end_round(state: MatchState) -> void:
    # Flip initiative
    state.initiative = "playerB" if state.initiative == "playerA" else "playerA"
    state.phase = MatchState.Phase.ROUND_START
```

---

## Group D — Action System Framework

*Depends on C + Phase 3. Provides the validation and execution framework for all actions.*

### D1. `ActionType` enum

- Enumerates all action types for structured references.
- **Done:** enum values match the spec's action catalog.

```gdscript
# src/core/combat/action_type.gd
class_name ActionType
extends RefCounted

enum Type { MOVE, ATTACK, ABILITY, USE_ITEM, DEFEND, WAIT }
```

### D2. `TurnActions` — action validation and execution

- Static methods for each action type: validate preconditions, execute mutation, return action record or error.
- All methods take `MatchState` + action parameters and produce a result.
- Movement filters out occupied tiles from the reachable set.
- **Done:** each action validates and executes correctly; AP is deducted; action records are appended.

```gdscript
# src/core/combat/turn_actions.gd
class_name TurnActions
extends RefCounted

static func execute_move(state: MatchState, destination: Vector2i) -> Dictionary:
    var unit: BattleUnit = state.current_unit
    if not unit: return { "error": "No active unit" }
    if unit.ap_remaining < 1: return { "error": "Not enough AP" }

    var move: int = unit.stats.effective_move()
    var jump: int = unit.stats.effective_jump_climb()
    var reach := Movement.reachable(state.graph, unit.position, move, jump)

    # Filter out occupied tiles (except self)
    for pos in state.occupancy.keys():
        if pos != unit.position and reach.has(pos):
            reach.erase(pos)

    if not reach.has(destination):
        return { "error": "Destination not reachable" }

    var old_pos: Vector2i = unit.position
    state.occupancy.erase(old_pos)
    unit.position = destination
    state.occupancy[destination] = unit
    unit.ap_remaining -= 1

    var record := {
        "action": "move",
        "actor": unit.character.id,
        "from": old_pos,
        "to": destination,
        "cost": int(reach[destination]),
    }
    state.turn_log.append(record)
    return record

static func execute_attack(state: MatchState, target_pos: Vector2i) -> Dictionary:
    var unit: BattleUnit = state.current_unit
    if not unit: return { "error": "No active unit" }
    if unit.ap_remaining < 1: return { "error": "Not enough AP" }

    var target: BattleUnit = state.unit_at(target_pos)
    if not target: return { "error": "No target at position" }
    if target.team == unit.team: return { "error": "Cannot attack friendly unit" }

    var rng: int = unit.stats.effective("rng")
    if RangeQuery.effective_range(unit.position, target_pos, state.graph) > rng:
        return { "error": "Target out of range" }
    if not LineOfSight.has_los(state.graph, unit.position, target_pos):
        return { "error": "No line of sight to target" }

    unit.ap_remaining -= 1

    var record := {
        "action": "attack",
        "actor": unit.character.id,
        "target": target.character.id,
        "target_pos": target_pos,
        # Phase 5 adds: "damage", "target_hp_after"
    }
    state.turn_log.append(record)
    return record

static func execute_ability(state: MatchState, ability_id: String, target_pos: Vector2i) -> Dictionary:
    var unit: BattleUnit = state.current_unit
    if not unit: return { "error": "No active unit" }

    # Look up the ability
    var ability: AbilityData = _find_ability(unit, ability_id)
    if not ability: return { "error": "Unit does not have ability '%s'" % ability_id }
    if unit.ap_remaining < ability.ap_cost:
        return { "error": "Not enough AP (need %d, have %d)" % [ability.ap_cost, unit.ap_remaining] }

    # Range check
    if RangeQuery.effective_range(unit.position, target_pos, state.graph) > ability.ability_range:
        return { "error": "Target out of ability range" }
    # LoS check
    if not LineOfSight.has_los(state.graph, unit.position, target_pos):
        return { "error": "No line of sight to target" }

    unit.ap_remaining -= ability.ap_cost

    var record := {
        "action": "ability",
        "actor": unit.character.id,
        "ability": ability_id,
        "target_pos": target_pos,
        "ap_spent": ability.ap_cost,
        # Phase 5 adds: effect resolution fields
    }
    state.turn_log.append(record)
    return record

static func execute_defend(state: MatchState) -> Dictionary:
    var unit: BattleUnit = state.current_unit
    if not unit: return { "error": "No active unit" }
    if unit.ap_remaining < 1: return { "error": "Not enough AP" }

    unit.stats.push_modifier(StatModifier.new("def", 2, "defend"))
    unit.ap_remaining -= 1

    var record := {
        "action": "defend",
        "actor": unit.character.id,
        "modifier": "+2 DEF",
    }
    state.turn_log.append(record)
    return record

static func execute_wait(state: MatchState) -> Dictionary:
    var unit: BattleUnit = state.current_unit
    if not unit: return { "error": "No active unit" }

    var record := {
        "action": "wait",
        "actor": unit.character.id,
        "ap_forfeited": unit.ap_remaining,
    }
    unit.ap_remaining = 0
    state.turn_log.append(record)
    return record

static func execute_use_item(state: MatchState, item_id: String, target_pos: Vector2i) -> Dictionary:
    var unit: BattleUnit = state.current_unit
    if not unit: return { "error": "No active unit" }
    if unit.ap_remaining < 1: return { "error": "Not enough AP" }

    # Verify unit has the item
    if item_id not in unit.character.equipment:
        return { "error": "Unit does not have item '%s'" % item_id }

    unit.ap_remaining -= 1

    var record := {
        "action": "use_item",
        "actor": unit.character.id,
        "item": item_id,
        "target_pos": target_pos,
        # Phase 5 adds: effect resolution fields
    }
    state.turn_log.append(record)
    return record

# --- Helpers ---

static func _find_ability(unit: BattleUnit, ability_id: String) -> AbilityData:
    # Check character's direct abilities + class-granted + equipment-granted
    # For MVP, we accept any ability the character data lists
    if ability_id in unit.character.abilities:
        return GameData.get_ability(ability_id)
    # Check class-granted abilities
    for cls_id in unit.character.classes:
        var cls: ClassData = GameData.get_job_class(cls_id)
        if cls and ability_id in cls.granted_abilities:
            return GameData.get_ability(ability_id)
    # Check equipment-granted abilities
    for eq_id in unit.character.equipment:
        var item: ItemData = GameData.get_item(eq_id)
        if item and ability_id in item.granted_abilities:
            return GameData.get_ability(ability_id)
    return null
```

> **Note on `_find_ability`:** This helper uses `GameData` autoload for ability/class/item lookup. For testability, tests that exercise ability actions will either: (a) test only the AP/range/LoS validation path with a mock, or (b) use a test-specific helper that injects ability data. The core validation logic (AP, range, LoS) is testable without `GameData`.

---

## Group E — Action Integration Details

*Depends on D. Refines individual action behaviors.*

### E1. Move action — occupancy-aware reachable set

- `execute_move` computes the reachable set, then subtracts occupied tiles (§7 of spec).
- The path is not pre-validated for intermediate occupancy (units can move through allies in MVP).
- **Done:** moving to an occupied tile fails; moving to a valid empty tile succeeds and updates occupancy.

### E2. Attack action — weapon range from stats

- The attacker's weapon range comes from `unit.stats.effective("rng")`.
- Validates enemy target at position, range, and LoS.
- **Done:** attack against out-of-range or no-LoS target fails with descriptive error; valid attack succeeds structurally.

### E3. Defend action — modifier stack integration

- Pushes `StatModifier("def", 2, "defend")` onto the unit's stat block.
- Removed at round start by `RoundManager.start_round()` via `remove_modifiers_by_source("defend")`.
- **Done:** after Defend, `unit.stats.effective("def")` increases by 2; after next round start, it returns to base.

### E4. Wait action — activation end

- Sets `ap_remaining = 0`, ending the unit's activation.
- **Done:** Wait always succeeds and ends the turn.

---

## Group F — Demo Wiring

*Ties A–E together for the exit-criteria demo. Updates the Phase 3 demo.*

### F1. `Phase4Demo` — round-loop demo controller

- Replaces or extends Phase 3's demo. Creates two small parties from loaded characters, auto-deploys, and runs the activation loop with keyboard controls.
- Keyboard: N = activate next unit (auto-selects first unactivated for current team), M = move to selected tile, A = attack selected tile, D = defend, W = wait, R = start new round.
- Prints state to the debug readout / console log.
- **Done:** a full round of alternating activations is demonstrable; AP spending, movement, and action logging are visible.

```gdscript
# src/map/phase4_demo.gd
class_name Phase4Demo
extends Node

var _state: MatchState
var _map_data: MapData

func setup(builder: MapBuilder, map_data: MapData) -> void:
    _map_data = map_data

    # Create two small parties from loaded characters
    var party_a: Array[BattleUnit] = []
    var party_b: Array[BattleUnit] = []
    # Example: 2 vs 2 for testing
    party_a.append(_make_unit("human_fighter"))
    party_a.append(_make_unit("human_rogue"))
    party_b.append(_make_unit("elf_black_mage"))
    party_b.append(_make_unit("halfling_white_mage"))

    _state = MatchSetup.create(party_a, party_b, map_data, GameData.get_terrain)

    var errors := Deployment.auto_deploy(_state, map_data.deployment_zones)
    if not errors.is_empty():
        for e in errors: Log.error("Phase4Demo", e)
        return

    RoundManager.start_round(_state)
    _log_state()

func _make_unit(char_id: String) -> BattleUnit:
    var c := GameData.get_character(char_id)
    var fs := GameData.get_final_stats(char_id)
    return BattleUnit.from_character(c, fs)

func _log_state() -> void:
    Log.info("Phase4Demo", "Round %d | Initiative: %s | Phase: %d" % [
        _state.round_number, _state.initiative, _state.phase])
    var team := RoundManager.current_team(_state)
    if not team.is_empty():
        var available := _state.unactivated_units(team)
        Log.info("Phase4Demo", "Waiting for %s to activate (%d available)" % [
            team, available.size()])
```

### F2. Input actions (project.godot)

- Add input actions for Phase 4 demo keys: `demo_next` (N), `demo_attack` (A), `demo_defend` (D), `demo_wait` (W), `demo_round` (R).
- Phase 3 keys (M, T, Escape) remain; M is reused for "move to selected tile" in Phase 4 context.
- **Done:** input actions registered in project.godot.

### F3. Scene wiring (map_scene.gd)

- Swap Phase3Demo for Phase4Demo (or gate by a config flag).
- **Done:** the map scene boots into the Phase 4 demo loop.

---

## Group G — Verification

*Logic is unit-tested; the demo is checklist-verified.*

### G1. Match state tests (GUT)

- Create a `MatchState` with two stub parties, verify phase transitions.
- Test `living_units`, `unactivated_units`, `unit_at`, `is_occupied`.
- **Done:** green, headless.

```gdscript
# tests/core/combat/test_match_state.gd
extends GutTest

func _make_unit(id: String, team: String, spd: int = 3) -> BattleUnit:
    var c := CharacterData.new()
    c.id = id
    c.classes = []
    c.equipment = []
    c.abilities = []
    var sb := StatBlock.new()
    sb.set_base("spd", spd)
    sb.set_base("hp", 10)
    var u := BattleUnit.from_character(c, sb)
    u.team = team
    return u

func test_initial_phase_is_setup() -> void:
    var state := MatchState.new()
    assert_eq(state.phase, MatchState.Phase.SETUP)
```

### G2. Deployment tests (GUT)

- Auto-deploy two parties into zones; verify positions, occupancy, state phase.
- Deploy more units than zone tiles → error.
- Deploy to already-occupied tile → error.
- **Done:** green.

### G3. Activation order tests (GUT)

- Two equal-size parties: queue alternates correctly.
- Uneven parties (3 vs 2): last team member gets consecutive activation.
- Initiative flips between rounds.
- **Done:** green.

```gdscript
# tests/core/combat/test_round_manager.gd
extends GutTest

func test_activation_queue_alternates() -> void:
    # Setup state with 2v2
    var state := _setup_deployed_state(2, 2)
    RoundManager.start_round(state)
    assert_eq(state.activation_queue.size(), 4)
    # First and third entries are initiative team
    assert_eq(state.activation_queue[0], state.initiative)
    assert_ne(state.activation_queue[1], state.activation_queue[0])

func test_uneven_parties_consecutive() -> void:
    var state := _setup_deployed_state(3, 2)
    RoundManager.start_round(state)
    assert_eq(state.activation_queue.size(), 5)
    # Last entry should be from the larger team
```

### G4. Action tests (GUT)

- **Move**: move to valid tile succeeds, AP decremented, position updated, occupancy updated. Move to occupied tile fails.
- **Attack**: valid attack returns record (no damage). Out of range fails. No LoS fails. Friendly fire fails.
- **Defend**: modifier pushed, DEF increases. After round start, modifier removed.
- **Wait**: AP set to 0, activation ends.
- **AP enforcement**: action with insufficient AP fails.
- Tests use stub data (no `GameData` autoload) for movement/attack validation; ability/item tests may require lightweight stubs.
- **Done:** green.

```gdscript
# tests/core/combat/test_turn_actions.gd
extends GutTest

func test_move_updates_position() -> void:
    var state := _setup_with_active_unit()
    var dest := Vector2i(1, 0)  # adjacent tile
    var result := TurnActions.execute_move(state, dest)
    assert_false(result.has("error"), "Move should succeed")
    assert_eq(state.current_unit.position, dest)
    assert_eq(state.current_unit.ap_remaining, 1)

func test_move_to_occupied_tile_fails() -> void:
    var state := _setup_with_active_unit_and_blocker()
    var result := TurnActions.execute_move(state, Vector2i(1, 0))
    assert_true(result.has("error"))

func test_defend_pushes_modifier() -> void:
    var state := _setup_with_active_unit()
    var base_def: int = state.current_unit.stats.effective("def")
    TurnActions.execute_defend(state)
    assert_eq(state.current_unit.stats.effective("def"), base_def + 2)
```

### G5. Integration tests (GUT)

- Full round cycle: deploy → start round → activate all units (with Move/Wait actions) → verify round ends → start next round → verify initiative flipped.
- **Done:** green.

### G6. Manual demo checklist

- [ ] Two parties deploy correctly into deployment zones.
- [ ] Activation alternates between teams; console shows correct team/unit.
- [ ] Moving a unit updates position and costs 1 AP.
- [ ] Moving to an occupied tile is rejected.
- [ ] Attacking a valid target logs a "would hit" record.
- [ ] Defending increases DEF by 2; reset next round.
- [ ] Waiting ends the activation.
- [ ] After all units activate, round ends and new round starts with flipped initiative.
- [ ] Uneven party sizes handled (consecutive activations visible in log).
- **Done:** checklist passes.

---

## Dependency Map

```
Phase 1 (BattleUnit, StatBlock, data) ──> A (MatchState, MatchSetup) ──> B (Deployment) ──> C (RoundManager)
Phase 3 (Movement, Range, LoS) ─────────────────────────────────────────────────> D (TurnActions)
C + D ──> E (action integration details)
A + B + C + D + E ──> F (Phase4Demo, scene wiring)
A,B,C,D,E ──> G1–G5 (unit tests);  F ──> G6 (manual checklist)
```

**Suggested first pass:** A1–A2 → B1 → C1 → D1–D2 → E1–E4 → F1–F3 → G. Groups A–D are sequential; E follows D; F ties together; G trails.

---

## Phase 4 Definition of Done

- [ ] `MatchState` with explicit state machine (setup → deployment → round start → activation → unit turn → round end cycle) (A).
- [ ] `MatchSetup` creates state with initiative by highest SPD, random tie-break (A).
- [ ] `Deployment.auto_deploy` places units into zones with occupancy tracking and validation (B).
- [ ] `RoundManager` implements alternating activation queue, interleaving, consecutive turns for uneven parties, round start/end with spent/reset, initiative flip (C).
- [ ] `TurnActions` validates and executes Move, Attack, Ability, Use Item, Defend, Wait with AP enforcement (D, E).
- [ ] Move integrates with Phase 3 `Movement.reachable()` and excludes occupied tiles (E1).
- [ ] Attack/Ability validate range + LoS, log records without damage resolution (E2).
- [ ] Defend pushes +2 DEF modifier, removed at round start (E3).
- [ ] Wait ends activation (E4).
- [ ] Phase4Demo demonstrates a full round loop with keyboard controls (F).
- [ ] GUT tests for match state, deployment, activation order, all actions, and full round integration (headless) (G1–G5).
- [ ] Manual demo checklist verified (G6).
- [ ] Git tag `phase-4-complete`.
