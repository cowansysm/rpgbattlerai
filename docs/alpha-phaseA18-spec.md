# Phase A18 — Reaction / Support / Movement Passives Specification

**Parent plan:** `roadmap-A11-onward.md` (sub-phase A18)
**Master spec:** `alpha-specs.md` (progression, combat); `feature-scan-and-competitive-analysis.md` (Part 3, #2)
**Builds on (Alpha):** A4 (`CharacterInstance`, learned abilities, JP), A5 (loadout/equip UI), A3/A16 (resolution hooks)
**Coordinates with:** A15 (telegraph annotates likely reactions), A17 (auto-revive/auto-potion hook the KO lifecycle), A19 (counter interacts with facing)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-30
**Status:** Draft v0.1

---

## 1. Purpose & Scope

Introduce **passive ability slots** in the FFT mold — abilities that trigger automatically rather than being actively spent. This is the largest missing pillar of the job system's identity: it makes build choices (which passives to equip) as meaningful as which active abilities to bring, and it deepens every combat without new action-economy rules.

Three passive **categories**, each with one equip slot per character:

- **Reaction** — triggers in response to an event (e.g., *Counter* on being meleed, *Auto-Potion* on taking damage, *Defend Reflex* on low HP).
- **Support** — always-on modifiers (e.g., *+1 AP regen condition*, *Equip Heavy*, *Magic Boost*, *Half WP cost*).
- **Movement** — locomotion passives (e.g., *+1 Jump*, *Ignore hazard tiles*, *Move +1*, *Waterwalk*).

### In scope

- Passive **slot model** on `CharacterInstance`: `reaction_slot`, `support_slot`, `movement_slot` (one each), populated from learned passive abilities.
- A **passive ability type**: extend `AbilityData` with `passive_kind` (`reaction` | `support` | `movement` | empty for active) and a `trigger`/`modifier` descriptor; learned via JP like active abilities.
- **Trigger dispatch** in the combat lifecycle: a small event bus where `resolve_damage`, the turn/AP lifecycle, and movement query hooks fire passive checks (on-hit, on-damaged, on-low-HP, on-turn-start, movement-budget, hazard-entry).
- A **seed set of passives** authored against existing systems (Counter, Auto-Potion, +1 Jump, Move +1, Ignore Hazards, Half WP, Magic/Attack Boost, Defend Reflex).
- **UI**: passive slot assignment in band/loadout screens; passive indicators on the unit panel.
- **AI & telegraph awareness**: `AIScorer` accounts for known enemy reaction passives (e.g., avoid meleeing a Counter unit); A15 annotates likely reactions in intent.

### Out of scope

- Multiple slots per category or passive-stacking depth (one slot each this phase).
- A full passive library for all classes (A9/A11 content) — A18 ships the engine + a seed set.
- New active abilities or action types.
- Reworking growth/JP curves (A10/A11 tuning).

### Exit criteria

1. A character can **learn passive abilities** (JP) and **equip one** in each of the reaction / support / movement slots, persisted in the save.
2. **Reaction** passives fire on their event (Counter deals a retaliatory hit on melee; Auto-Potion consumes a potion when damaged; Defend Reflex applies Defend at low HP) with correct, deterministic resolution.
3. **Support** passives modify the relevant computation (stat boost, WP cost, equip access) via the stat/derivation pipeline.
4. **Movement** passives change pathfinding inputs (jump budget, hazard cost, move range) through the existing injected providers.
5. Triggers route through one **dispatch seam** (no ad-hoc checks scattered across resolution); headless and deterministic.
6. `AIScorer` factors known enemy reactions into plan scoring; A15 telegraph annotates reactions; combat remains seed-reproducible.
7. Tests cover learning/equipping/persistence, each seed passive's trigger and effect, the no-passive baseline (unchanged outcomes), and AI avoidance of a Counter target.

---

## 2. Design Decisions

- **One dispatch bus, typed events.** A `PassiveDispatch` raises typed events (`ON_HIT`, `ON_DAMAGED`, `ON_LOW_HP`, `ON_TURN_START`, `ON_MOVE_QUERY`, `ON_HAZARD_ENTER`); equipped passives subscribe declaratively. Keeps resolution code clean and makes new passives data-first.
- **Reactions are deterministic and bounded.** A reaction fires at most once per triggering event and cannot infinitely chain (a counter does not trigger a counter); resolution reuses `CombatResolver` and the shared dice/RNG so seeds hold.
- **Support/Movement are modifiers, not events.** They feed the existing `StatBlock` modifier stack and the pathfinding/LoS providers rather than the event bus, so they compose with terrain (A0) and equipment automatically.
- **AI honesty.** Because telegraphing (A15) is core, enemy reaction passives are *known* and shown; the AI must not exploit hidden reactions.

---

## 3. Files

**New:**
- `src/core/combat/passive_dispatch.gd` (`PassiveDispatch`) — typed trigger bus + resolution.
- `src/core/progression/passive_slots.gd` (or fields on `character_instance.gd`).

**Modified:**
- `src/core/data/ability_data.gd` — `passive_kind`, `trigger`, `modifier`.
- `src/core/progression/character_instance.gd` — slots, learn/equip, `to_dict`/`from_dict`.
- `src/core/progression/instance_stat_resolver.gd` — apply support modifiers.
- `src/core/hex/movement.gd` (via providers) — movement passives.
- `src/core/combat/combat_resolver.gd` / `turn_actions.gd` — raise lifecycle events.
- `src/core/ai/ai_scorer.gd` — reaction-aware scoring; A15 telegraph annotation.
- `src/ui/band_management_scene.gd` — slot assignment UI.
- `data/abilities.json` (+ `data/csv/abilities.csv`) — seed passives; `data/constants.json` — tunables.

---

## 4. Test Plan

- Learn/equip/persist a passive in each slot across save→load.
- Counter: melee on a Counter unit triggers exactly one retaliation; no chain.
- Auto-Potion: damage with a potion in inventory heals; without, no-op.
- Support: Magic Boost raises spell damage by the configured amount; Half WP halves cost.
- Movement: +1 Jump expands reachable tiles; Ignore Hazards zeroes hazard entry cost.
- No-passive baseline reproduces current outcomes.
- AI avoids meleeing a known Counter target when a better plan exists.
