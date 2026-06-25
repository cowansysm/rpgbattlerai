# Seam Audit — Deferred Feature Extension Points

Phase A10 deliverable. Confirms each deferred feature's integration seam and notes friction.

---

## 1. Player-Facing Map Editor

**Current state:** Dev-only map editor gated by `Dev.enabled`.

**Key files:**
- `src/tools/map_editor_model.gd` — headless model (`RefCounted`, no scene-tree dependency). Owns tile state, zone mutations, undo/redo (50-step snapshot stack).
- `src/ui/map_editor.gd` — scene-level controller (`Node3D`). Wires model to `MapBuilder` (rendering), `TilePicker` (input), `MapEditorHUD` (UI chrome).

**Extension path:** Replace or augment the UI layer while keeping `MapEditorModel` unchanged. Add new tool types to the `Tool` enum and corresponding `_apply_tool()` match cases. Rendering backend is swappable via `MapBuilder` subclass.

**Friction:** None. Clean model/view separation with explicit signal coupling.

---

## 2. Networked Multiplayer

**Current state:** Local play only. AI opponent uses the same `TurnActions` API as the human player.

**Key files:**
- `src/core/combat/turn_actions.gd` — all-static methods returning serializable `Dictionary` action records (`move`, `attack`, `ability`, `defend`, `wait`, `use_item`). Records append to `state.turn_log`.
- `src/core/combat/match_state.gd` — central game state; `ability_provider` and `item_provider` are injected Callables.

**Extension path:** Introduce a network action queue that serializes turn-log records as JSON. Server validates actions against authoritative `MatchState`, then broadcasts to peers. Replay system is trivial since `TurnActions` is deterministic (no internal RNG; dice rolls are inputs). `AIController` already consumes the same API — remote players slot into the same interface.

**Friction:** None. The action log is the authoritative record and uses plain dictionaries throughout.

---

## 3. Rich Narrative Events

**Current state:** Data-driven events in `data/events.json` resolved by `EventResolver`.

**Key files:**
- `src/core/run/event_resolver.gd` — resolves events by kind; applies effects via match statement in `_apply_effects()`.
- `data/events.json` — authored event definitions with text, choices, and effect arrays.

**Current effect types:** `gold`, `item`, `heal_all`, `damage_all`, `damage_random`, `xp`.

**Extension path:** Add new effect types by adding cases to `_apply_effects()`. Events already support multiple choices with independent effect arrays. Event chaining (linking events) is schema-compatible — add a `chain` field to the event dict.

**Friction (moderate):** Effect types are dispatched via match statement, not a registry. Adding many new effect types will create a long match block. Consider extracting to an `EffectApplier` with registered handlers if the effect vocabulary grows significantly.

---

## 4. Deeper AI

**Current state:** Candidate enumeration → scoring → top-N sampling with temperature.

**Key files:**
- `src/core/ai/ai_planner.gd` — enumerates legal `AIPlan` candidates (bounded to 12 reachable tiles).
- `src/core/ai/ai_scorer.gd` — evaluates plans via 10 weighted heuristics (damage, kills, exposure, cover, elevation, hazards, target priority, ability value, resource cost).
- `src/core/ai/ai_plan.gd` — plan model with step kinds and AP tracking.

**Extension path:** Scoring weights are already configurable per difficulty preset via `constants.json` `AI_DIFFICULTY_PRESETS`. New heuristic terms: add a private static method to `AIScorer` and wire it into `score()`. Alternative scorers: create a new scoring function with the same signature `(state, unit, plan, weights) -> float` and inject it at the planner call site.

**Friction (moderate):** Scorer is tightly coupled to `AIPlan` step structure. Adding new step kinds requires expanding damage/kill estimation methods. No per-unit or per-class scorer customization hooks — scoring is uniform across all units. An `AIScorer` interface/base class would enable class-specific tactics.

---

## 5. Crafting / Equipment Upgrades

**Current state:** Items are immutable `Resource` objects with buy/sell economy.

**Key files:**
- `src/core/data/item_data.gd` — `@export` fields: `id`, `display_name`, `slot`, `bp_value`, `passive` (reserved, unused), `granted_abilities`, `price`, `weapon_power`, `weapon_range`.
- `src/core/economy/pricing.gd` — buy/sell price computation (authored or derived from `bp_value`).
- `src/core/economy/shop_service.gd` — transactional buy/sell on `BattleBand`.

**Extension path:** The `passive: Dictionary` field is reserved and empty — ideal for stat modifiers on equip (e.g., `{"stat_mods": [{"key": "atk", "value": 3}]}`). Add new `@export` fields for crafting recipes, rarity tiers, upgrade chains, or enchantment slots. `Pricing` fallback pattern (authored → derived) extends naturally to craft costs. `ShopService.buy()` routes items to `band.add_to_inventory()` — hook crafting logic post-transaction.

**Friction:** None. `ItemData` is purely additive; new fields are backward-compatible since `DataFactory.make_item()` uses `.get()` with defaults.

---

## 6. New Stats / Effect Types

**Current state:** 9 stats via `StatKey` enum. Effects dispatched by match statement.

**Key files:**
- `src/core/data/stat_key.gd` — `enum Key { SPD, ATK, RNG, DEF, HP, JUMP, WP, MAG, RES }` with string mappings and `KEYS` array.
- `src/core/data/stat_block.gd` — key-agnostic `effective(key_string)` = base + sum(modifiers).
- `src/core/data/stat_modifier.gd` — arbitrary `key: String` modifiers.
- `src/core/combat/turn_actions.gd` — `_resolve_effect()` dispatches by effect type string.

**Extension path (stats):** Edit `stat_key.gd` in 3 places (enum, string map, KEYS array). `StatBlock`, `StatModifier`, and all stat-keyed consumers propagate automatically because they use string keys, not enum values, at runtime.

**Extension path (effects):** Add a case to `TurnActions._resolve_effect()` for new ability effect types. Status effects are stored as `{id, duration, source}` dicts on `BattleUnit` with no hardcoded status list — all status IDs are arbitrary strings.

**Friction (moderate):** Effect types and status mechanics are match-cased in `TurnActions._resolve_effect()` and `AIScorer._ability_value()`. Each new effect or status with special rules requires touching these two locations. A registry-based `EffectResolver` would reduce coupling as the effect vocabulary grows.

---

## Summary

| Feature | Extensibility | Friction |
|---------|:---:|:---:|
| Map editor | Excellent | None |
| Multiplayer | Excellent | None |
| Narrative events | Good | Moderate — match dispatch |
| AI depth | Good | Moderate — scorer coupling |
| Crafting/upgrades | Excellent | None |
| New stats/effects | Good | Moderate — match dispatch |

All six seams are production-ready for extension. The three moderate-friction areas share the same pattern (match-statement dispatch) and would benefit from registry-based handlers if their vocabularies grow significantly. No architectural changes are required to begin work on any deferred feature.
