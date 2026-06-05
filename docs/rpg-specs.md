# RPG Battle Simulator — Specification (MVP / Core Systems)

**Status:** Draft v0.1
**Scope:** Minimum viable, core systems only
**Medium:** Digital game (single-application, FFT-style tactics)
**Date:** 2026-05-29

---

## 1. Overview & Vision

A tactical battle simulator in which players assemble a **party** of classic J/RPG and W/RPG fantasy archetypes (black mage, white mage, fighter, barbarian, bard, rogue, and so on) and fight on small, three-dimensional maps. Combat draws its style and feel from *Final Fantasy Tactics* — grid movement, elevation, classes, and skill-driven turns — but diverges in three deliberate ways:

- **Wargame feel.** Moment-to-moment play emphasizes positioning, points-based list building, and tactical commitment, closer to *Warhammer 40,000* or *Infinity* than to a story-driven campaign.
- **Deeper jobs.** The long-term goal is a far richer class/job system with many more skills, spells, and abilities to mix and match.
- **Free-form builds.** Characters are not restricted to two classes as in FFT; the design intends multiclassing with no hard two-job cap.

### MVP boundaries

This document specifies the **first playable**. To keep scope manageable:

- Characters are **premade** and drafted from a shared, static pool available to all players.
- Each premade character ships with a **fixed loadout** (equipment + abilities). No in-app character builder yet.
- The systems below are designed so the deep builder, large content libraries, and progression can be layered on later **without** reworking the combat or data model.

The pillars that must be true in the MVP: points-constrained party drafting, alternating-activation tactical combat on a 3D hex map, and a roster that immediately reads as classic sword-and-sorcery.

---

## 2. Core Terminology

| Term | Meaning |
|------|---------|
| **Party / Parties** | A team of one or more characters controlled by one player. |
| **Character** | A single combatant, defined by race + class(es), stats, equipment, and abilities. |
| **Battle Points (BP)** | The point cost of a character; the primary constraint on party formation. Analogous to Army Points (40k) or Squad Cost (Infinity). |
| **Class / Job** | An archetype (Archer, Black Mage, etc.) that grants stats, abilities, and equipment access. |
| **Race** | Ancestry (Human, Elf, Halfling, etc.) that modifies base stats and flavor. |
| **Loadout** | A character's fixed set of equipment and abilities in the MVP. |
| **Ability** | Any activatable action: a melee skill, a spell, an item effect, etc. |
| **Item-bound ability** | An ability that exists only because the character carries a specific item. |
| **Tier** | A defined bracket of BP cap + party-size bounds for a match. |

---

## 3. Maps

### 3.1 Geometry

Maps are **three-dimensional**, using a **hex grid** in the horizontal plane plus **height** as the third dimension.

- The play surface is a grid of **hex tiles**. Adjacency is the standard six neighbors.
- Each tile has an integer **elevation** (height in tile-units). Stacked elevations form ramps, cliffs, plateaus, and pits.
- A tile's traversability depends on the elevation difference to its neighbors and on the unit's movement attributes (see §7.4).

Recommended MVP map size: **8–14 hexes across**, elevation range **0–8**. Small, readable, fast to resolve.

### 3.2 Terrain & wilderness

Each tile carries a **terrain type** that affects movement and combat. The MVP ships a small but expressive set:

| Terrain | Move cost | LoS / Cover effect | Notes |
|---------|-----------|--------------------|-------|
| Grass / dirt | 1 | none | Default open ground. |
| Road / stone | 1 | none | Cosmetic baseline; reserved for future bonuses. |
| Tall grass / brush | 2 | soft cover (ranged DEF bonus) | Partially obscures occupants. |
| Trees (forest) | 2 | blocks line of sight; soft cover | Cannot be entered if "dense"; "sparse" passable. |
| Rocks / boulders | impassable | blocks LoS | Full obstacle; can be shot over only from higher elevation. |
| Shallow water | 2 | none | Passable; may impose minor penalties later. |
| Deep water | impassable (MVP) | none | Blocks ground movement. |
| Cliff face | impassable | blocks LoS | Vertical surface between elevations. |

**Height interactions (MVP):**

- **Line of sight** is blocked by tiles/objects taller than the line between attacker and target; higher attackers can see and shoot over lower obstacles.
- **Elevation advantage**: attacking from higher ground grants a flat accuracy/damage bonus (tunable constant; see §7.5).
- **Movement up/down** between adjacent tiles is limited by the character's **Jump/Climb** allowance (derived stat, §4.3).

---

## 4. Characters

### 4.1 Definition: Race + Class

A character is defined by a **race** and **one or more classes**. Examples: *Human Archer*, *Elf Black Mage*, *Halfling White Mage*.

- **Race** sets base stat modifiers and flavor (e.g., Elves favor magic stats; Halflings are nimble; Humans are balanced).
- **Class** grants a stat profile, equipment access, and an ability set.
- A character **may hold more than one class** (multiclass). In the MVP this is expressed only through the premade roster (some premades are multiclass); free-form multiclassing is a later feature, but the data model supports it now (§9).

### 4.2 Core stat block

Every character exposes these primary stats (the same fields shown in the example roster):

| Stat | Abbr. | Meaning |
|------|-------|---------|
| Battle Points | **BP** | Point cost for party building. |
| Level | **LVL** | Power band of the character; informs BP and stat scaling. |
| Speed | **SPD** | Movement allowance in hexes per move action; also tie-breaks activation order. |
| Attack | **ATK** | Physical damage power. |
| Range | **RNG** | Base reach of the character's standard attack, in hexes (0 = melee/self for casters who rely on spell range). |
| Defense | **DEF** | Physical damage mitigation. |
| Hit Points | **HP** | Health; at 0 the character is downed/removed. |

> **Note on caster stats.** Spellcasters (e.g., Black Mage) commonly show ATK/RNG/DEF of 0 because their offense comes from **spells**, whose own range and power are defined on the ability, not the character's basic attack.

#### 4.2.1 Canonical stat keys (`StatKey`)

All stat references across data files, Resource classes, and runtime code use the following exact string keys, enforced by a shared **`StatKey` enum** defined in the codebase:

| Enum value | String key | Used by |
|------------|------------|---------|
| `SPD` | `"spd"` | base_stats, stat_modifiers, StatBlock |
| `ATK` | `"atk"` | base_stats, stat_modifiers, StatBlock |
| `RNG` | `"rng"` | base_stats, stat_modifiers, StatBlock |
| `DEF` | `"def"` | base_stats, stat_modifiers, StatBlock |
| `HP`  | `"hp"`  | base_stats, stat_modifiers, StatBlock |

The `StatKey` enum is the **single point of expansion** when future stats are added (e.g., `magic_power`, `magic_def`). Adding a stat means adding one enum value — all validation, derivation, and modifier-stack code iterates over `StatKey.values()` rather than maintaining independent key lists. Any stat-keyed dictionary containing a key not present in `StatKey` is rejected at load-time validation.

### 4.3 Derived stats (computed, MVP)

- **Move** = SPD (hexes per move action).
- **Jump/Climb** = elevation difference a character can traverse in a single step. Default `floor(SPD / 2) + 1`; agile classes (Rogue) get a bonus.
- **Magic Power / Magic Defense** = for the MVP, folded into per-ability values and DEF respectively; broken out as full stats in a later version.

### 4.4 Equipment

Each character carries **default equipment** that justifies its abilities and BP cost. Equipment falls into slots:

- **Weapon** (e.g., Bow, Sword, Staff) — defines basic-attack profile and may grant abilities.
- **Armor** (Light / Medium / Heavy) — contributes to DEF and may gate SPD.
- **Shield** — adds DEF / block chance.
- **Accessory** (e.g., Bracer of Accuracy) — passive bonuses or item-bound abilities.

### 4.5 Item-bound abilities

Some abilities exist **only because of a carried item**, for variety and to anchor cost. Even though MVP items are fixed, abilities are attached to the item rather than the character, so:

- Removing/destroying the item (future feature) would remove the ability.
- The same item reused across characters grants the same ability consistently.

Example: a *Bracer of Accuracy* grants a "+accuracy" passive; a *Phoenix Charm* might grant a one-use self-revive. The Archer's accuracy edge is justified by the bracer, not baked into the character.

---

## 5. Party Building

### 5.1 The constraint

Parties are built by spending **Battle Points** up to a cap. Players draft characters from the **shared premade pool**; the same character may be available to both players (mirror picks allowed unless a tier rules otherwise).

- A party comprises **one or more** characters.
- Each tier sets an **upper and lower bound** on total character count and a **BP cap**.
- A legal party: total BP ≤ tier cap, and `min ≤ character count ≤ max`.

### 5.2 Tiers

The MVP defines three brackets so players can choose match size:

| Tier | BP cap | Min chars | Max chars | Feel |
|------|--------|-----------|-----------|------|
| **Skirmish** | 100 | 3 | 5 | Tight, fast, every pick is premium. |
| **Standard** | 150 | 4 | 8 | The default; FFT-sized squads. |
| **Large** | 250 | 6 | 12 | Bigger boards, more bodies, deeper tactics. |

> Both players in a match use the **same tier**. Map size should scale with tier (smaller maps for Skirmish).

### 5.3 Drafting flow (MVP)

1. Players agree on a **tier** and **map**.
2. Each player privately drafts characters from the shared pool until at/under the BP cap and within size bounds.
3. Loadouts are fixed by the premade definition — no editing in the MVP.
4. Parties are revealed; deployment begins (§7.2).

---

## 6. Sample Roster

The three user-provided examples, normalized into the schema, plus additional archetypes to show range. BP values are illustrative and should be balance-tested (§7.6).

| Character | BP | LVL | Class | SPD | ATK | RNG | DEF | HP | Loadout (equipment & abilities) |
|-----------|----|-----|-------|-----|-----|-----|-----|----|----|
| **Human Archer** | 13 | 2 | Archer | 3 | 2 | 2 | 1 | 10 | Bow; Bracer of Accuracy; Light Armor |
| **Elf Black Mage** | 30 | 5 | B.Mage | 3 | 0 | 0 | 0 | 12 | Fire 1, Fire 2, Ice 1, Thunder 1 (Magic) |
| **Halfling White Mage** | 24 | 4 | W.Mage | 2 | 0 | 1 | 0 | 13 | Cure 1, Cure 2, Shield 1 (Magic) |
| **Human Fighter** | 18 | 3 | Fighter | 3 | 3 | 1 | 3 | 16 | Sword; Medium Armor; Shield; Power Strike |
| **Dwarf Barbarian** | 20 | 3 | Barbarian | 3 | 4 | 1 | 2 | 18 | Greataxe; Light Armor; Reckless Swing; Rage |
| **Human Rogue** | 16 | 3 | Rogue | 4 | 2 | 1 | 1 | 11 | Daggers; Light Armor; Backstab; Smoke Bomb (item) |
| **Elf Red Mage** | 26 | 4 | R.Mage | 3 | 2 | 1 | 1 | 13 | Rapier; Fire 1, Cure 1 (Magic); Light Armor |
| **Human Bard** | 17 | 3 | Bard | 3 | 1 | 2 | 1 | 12 | Sling; Inspire (buff song); Lullaby (sleep); Light Armor |

> These are seeds for content, not a final balanced set. The schema (§9) is the source of truth; this table is a human-readable view.

---

## 7. Combat System

### 7.1 Match structure

A match plays out on one map between two parties until a victory condition is met (§8). Time is organized into **rounds**; within each round players **alternate activating one character at a time**.

### 7.2 Setup & deployment

1. Determine **first activation** (e.g., coin flip, or compare the highest single SPD in each party; ties → random).
2. Players deploy their characters into their **deployment zone** (a marked set of edge hexes per the map).

### 7.3 Alternating activation

- A **round** consists of players taking turns **activating one un-activated character each**, starting with the player who has initiative.
- Players alternate until all characters on both sides have activated once. The round then ends and a new round begins.
- If one party has more characters than the other, the player with remaining un-activated characters takes consecutive activations once the other side is exhausted.
- An activated character is marked **spent** for the round; reset at round start.
- **Initiative for the next round** passes to (configurable) the player who finished activating last, or alternates — to be locked during balancing (§7.6). MVP default: initiative alternates each round.

> SPD does **not** drive a continuous CT clock in this design; it governs movement distance and the deployment/first-turn tie-break.

### 7.4 Action economy — 2 Action Points

On its activation, a character has **2 Action Points (AP)**. AP may be spent on any mix of the following (each costs 1 AP unless noted):

| Action | AP | Notes |
|--------|----|----|
| **Move** | 1 | Move up to SPD hexes, respecting move cost and Jump/Climb. May be taken twice (move 1 AP, then move again) to cover more ground. |
| **Attack** | 1 | Basic weapon attack within RNG and LoS. |
| **Ability / Spell** | 1 | Use a class or item-bound ability per its own rules (range, area, cost). |
| **Use item** | 1 | Consumable or activated item effect. |
| **Defend / Overwatch** | 1 | Take a defensive stance or set a reaction (MVP: simple +DEF until next activation). |
| **Wait** | 0 | End activation with unspent AP. |

- A given **ability may restrict** how it's used (e.g., "costs both AP," "may not be combined with Move").
- Spending **both AP on the same heavy ability** (e.g., a powerful spell) is a common pattern and is defined per-ability.

### 7.5 Resolution math (MVP baseline)

Kept deliberately simple and deterministic-leaning, tunable by constants:

- **Physical damage** = `max(1, (ATK + weapon_power + elevation_bonus) − target_DEF)`.
- **Spell damage / heal** = value defined on the ability (e.g., *Fire 1* = 4 damage in a 1-hex burst), modified by elevation/cover where applicable.
- **Accuracy** (if a hit roll is used): base hit chance modified by `+accuracy` sources (e.g., Bracer of Accuracy), cover (soft cover from brush/trees reduces it), and elevation. MVP may start **auto-hit** for melee and a simple cover-based reduction for ranged; lock during balancing.
- **Elevation bonus**: attacking from higher ground grants a flat `+1` to damage and/or accuracy (constant `ELEV_BONUS`).
- **Cover**: soft cover grants the defender a flat ranged-defense bonus (`COVER_DEF`); hard cover/obstacles can block the shot entirely (no LoS).
- **Range & LoS**: an attack/ability is legal only if the target is within range (hex distance, accounting for elevation) **and** line of sight is unobstructed per §3.2.
- **Downed**: at HP ≤ 0 the character is removed from play (MVP). Revive effects (e.g., *Phoenix Charm*) are item-bound exceptions.

### 7.6 Balancing notes (BP derivation)

BP should be a **function of combat value**, validated by playtest rather than hand-set. A starting heuristic for premades:

```
BP ≈ w1·HP + w2·ATK + w3·DEF + w4·SPD + w5·(RNG value)
   + Σ(ability_value) + Σ(equipment_value)
```

Weights are tuning constants. The roster table values in §6 are seeds; expect iteration. Item-bound and class abilities each carry their own point value so that two characters with identical base stats but different abilities cost differently.

---

## 8. Victory Conditions (MVP)

**Last party standing / rout.** A player wins when the opposing party is **eliminated or routed**:

- **Elimination:** all enemy characters are downed/removed.
- **Rout threshold:** a party is considered routed when reduced below a configurable fraction of its starting strength (default: **≤ 25% of starting characters remaining**, or all remaining characters downed). The surviving party wins immediately.
- **Mutual loss / draw:** if a single action downs the last characters of both parties simultaneously, the match is a draw (or resolved by a tie-break constant).

Other modes (objective control, turn-limit scoring) are **out of scope** for the MVP but the data model should not preclude them.

---

## 9. Data Model (MVP)

Schemas are illustrative (JSON-style) and are the source of truth over the human-readable roster table.

### 9.1 Character

```json
{
  "id": "human_archer",
  "name": "Human Archer",
  "race": "human",
  "classes": ["archer"],          // array → multiclass-ready
  "level": 2,
  "bp": 13,
  "stats": { "spd": 3, "atk": 2, "rng": 2, "def": 1, "hp": 10 },  // keys validated against StatKey
  "equipment": ["bow", "bracer_of_accuracy", "light_armor"],
  "abilities": []                 // most abilities resolved via class/equipment
}
```

### 9.2 Class

```json
{
  "id": "black_mage",
  "name": "Black Mage",
  "stat_modifiers": { "atk": 0, "def": 0 },
  "equipment_access": ["staff", "robe"],
  "granted_abilities": ["fire_1", "ice_1", "thunder_1"]
}
```

### 9.3 Ability / Spell

```json
{
  "id": "fire_2",
  "name": "Fire 2",
  "type": "spell",
  "ap_cost": 2,
  "range": 4,
  "area": { "shape": "burst", "radius": 1 },
  "effect": { "effect_type": "damage", "value": 7, "element": "fire" },
  "source": "class"               // or "item"
}
```

#### 9.3.1 Effect type schemas

The `effect` object must contain an `effect_type` field selecting one of the known effect schemas below. Unknown effect types are rejected at validation. Phase 1 validates the *structure*; Phase 5 interprets *behavior*.

| `effect_type` | Required fields | Optional fields | Example |
|---------------|----------------|-----------------|---------|
| `"damage"` | `value: int` | `element: String` | `{"effect_type":"damage","value":7,"element":"fire"}` |
| `"heal"` | `value: int` | — | `{"effect_type":"heal","value":5}` |
| `"status"` | `status_id: String`, `duration: int` | `value: int` | `{"effect_type":"status","status_id":"sleep","duration":2}` |
| `"buff"` | `stat: String` (valid `StatKey`), `value: int`, `duration: int` | — | `{"effect_type":"buff","stat":"def","value":2,"duration":3}` |

New effect types are added to this table, the validation branch, and the combat resolver. The structured schema ensures every ability's effect is machine-parseable before combat code exists to consume it.

### 9.4 Item / Equipment

```json
{
  "id": "bracer_of_accuracy",
  "name": "Bracer of Accuracy",
  "slot": "accessory",
  "bp_value": 2,
  "passive": { "accuracy": "+1" },
  "granted_abilities": []         // item-bound abilities listed here when present
}
```

### 9.5 Map

```json
{
  "id": "forest_clearing",
  "tier": "standard",
  "tiles": [
    { "q": 0, "r": 0, "elevation": 0, "terrain": "grass" },
    { "q": 1, "r": 0, "elevation": 2, "terrain": "trees" }
    // ... axial hex coordinates (q, r)
  ],
  "deployment_zones": { "playerA": ["..."], "playerB": ["..."] }
}
```

> At load, each tile dictionary is converted into a typed `TileRecord` object (with fields `q`, `r`, `elevation`, `terrain`). All downstream consumers access tile properties through typed fields, not dictionary keys.

### 9.6 Runtime state model

The data model separates **authored data** (Resources, immutable post-load) from **runtime state** (per-battle mutable wrappers). Combat systems operate on runtime state objects, never on the authored Resources directly.

**`BattleUnit`** — the runtime wrapper for a deployed character:

- References the authored `CharacterData` (read-only).
- Owns a `StatBlock` initialized from the character's load-time derived stats, with a modifier stack for runtime changes (equipment passives, buffs, debuffs, situational bonuses).
- Holds mutable per-battle fields: `position: Vector2i`, `current_hp: int`, `ap_remaining: int`, `is_activated: bool`, `team: String`.
- Created at deployment (Phase 4); disposed at match end.
- The separation ensures that loading content and running a battle are independent — content is loaded once and shared; each match instantiates its own set of `BattleUnit`s.

```json
// Conceptual (not a data file — created at runtime):
{
  "character_ref": "human_archer",
  "position": [2, 3],
  "current_hp": 10,
  "ap_remaining": 2,
  "is_activated": false,
  "team": "playerA",
  "stat_modifiers": []
}
```

#### 9.6.1 Stat resolution model

Stats flow through three layers:

1. **Base values** — computed at load from character `base_stats` + race modifiers + class modifiers (additive). These never change during a match.
2. **Modifier stack** — an ordered list of `StatModifier` entries, each with: `key` (a valid `StatKey`), `value: int` (additive), `source: String` (e.g., `"equipment"`, `"buff"`, `"elevation"`). Modifiers are pushed/popped at runtime (e.g., entering cover, casting a buff, equipping an item).
3. **Effective values** — queried on demand: `effective(key) = base(key) + sum(modifiers where modifier.key == key)`. Derived stats (`move`, `jump_climb`) recompute from effective values.

The MVP modifier stack is **additive only**. Multiplicative and priority-ordered modifiers are deferred. Equipment passives, elevation bonuses, buffs, and debuffs all use the same push/pop mechanism — no special-casing per modifier source.

### 9.7 Tunable constants

```
ELEV_BONUS      = 1     // damage/accuracy bonus from higher ground
COVER_DEF       = 1     // soft-cover ranged defense bonus
ROUT_THRESHOLD  = 0.25  // party routs at/below this fraction of starting size
```

---

## 10. Out of Scope (MVP) / Future Work

The following are explicitly **deferred** but the systems above are designed to accommodate them:

- **In-app character builder** with free-form multiclassing and point-buy loadouts.
- **Large content libraries**: many classes, hundreds of skills/spells, weapons, armor, shields, accessories — the depth that makes building "deep and meaningful."
- **Progression / campaign**: leveling, XP, persistent rosters.
- **Additional victory modes**: objective control, capture points, turn-limit scoring.
- **Reaction/overwatch depth**, status-effect library, elemental affinities and resistances.
- **Multiplayer/networking, AI opponents, animations, and presentation.**

---

## Appendix A — Requirements Traceability

| # | Requirement | Where addressed |
|---|-------------|-----------------|
| 1 | RPG battle simulator, squad + small-map battles | §1 |
| 2 | 3D maps with height | §3.1 |
| 3 | Terrain & wilderness (trees, water, rocks) | §3.2 |
| 4 | Teams called Parties | §2 |
| 5 | Individuals called Characters | §2 |
| 6 | Party of one or more characters | §5.1 |
| 7 | Party upper/lower bounds | §5.2 |
| 8 | Characters defined by race + class | §4.1 |
| 9 | One or more classes per character | §4.1, §9.1 |
| 10 | Per-character BP value | §4.2 |
| 11 | BP analogous to 40k/Infinity | §2, §5.1 |
| 12 | Draft from shared premade pool | §5.1, §5.3 |
| 13 | Default equipment justifies abilities/cost | §4.4 |
| 14 | Some abilities item-bound | §4.5 |
| 15 | Example draftable characters | §6 |
| 16 | Classic JRPG/WRPG archetypes | §1, §6 |
| 17 | Eventual deep, meaningful building | §1, §10 |
| 18 | Premade + static loadout for now | §1 (MVP boundaries) |
| 19 | Combat mimics FFT | §1, §7 |
| 20 | FFT-but: wargame feel, deeper jobs, more skills, free-form builds | §1, §7.3, §7.4, §10 |
