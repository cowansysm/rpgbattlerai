# RPG Battle Simulator — Specification (Alpha / Progression, Content & Single-Player)

**Status:** Draft v0.2
**Scope:** Alpha feature set — builds on the completed MVP (Phases 0–11)
**Medium:** Digital game (single-application, FFT-style tactics)
**Date:** 2026-06-17
**Supersedes nothing:** extends `rpg-specs.md` (MVP). The MVP combat, hex, and data foundations remain the substrate; Alpha layers progression, content, tooling, and a single-player meta-game on top.

---

## 0. How to Read This Document

This is the **master specification** for the Alpha phase. It defines *what* the Alpha systems are and *why*, in the same house style as `rpg-specs.md`. The *how* and *when* — the sub-phase breakdown with done-states — will live in a companion `alpha-implementation-plan.md` and per-sub-phase `alpha-phase<N>-spec.md` / `-implementation-plan.md` files, exactly mirroring the MVP's documentation layout.

§13 contains a **proposed sub-phase roadmap** as a starting point for that planning.

### Settled decisions

The following scope decisions are settled and drive this draft: the map editor is an **internal dev tool**, reachable only when a **dev flag** is enabled, and architected for player-facing release later; the data-authoring pipeline is **CSV ↔ JSON round-trip**; progression is **FFT-style full** (levels + job points + job tree + gold/shop + loot); classes follow an **MMORPG archetype paradigm** rooted in a shared **Vagabond** starting class; the single-player structure is a **roguelike run** of nodes (battles, events, helpful/harmful encounters); and character death uses a **per-run down limit** (default: permadeath on the third down).

### Open design decisions

A second tier of decisions was made by the author of this draft and is flagged inline with **[ASSUMPTION]**. These are reasonable defaults chosen to keep the spec complete and internally consistent; each is a candidate for revision in review:

- **In-battle multiclass** model (primary class + free-form ability loadout) — §5.4.
- Two **new stat keys** (`MAG`, `RES`) to support deeper casting jobs — §5.6.
- **Save-system** location and format — §9.4.
- Existing **hotseat PvP** from the MVP is retained, not removed — §10.

---

## 1. Overview & Vision

The MVP delivered the core fantasy: points-constrained drafting and alternating-activation tactical combat on a 3D hex map, with a premade roster. Alpha turns that combat sandbox into a **game with persistence and a reason to keep playing**.

Three pillars define the Alpha:

- **Characters that grow.** A combatant is no longer a static premade entry. It is a **unique, persistent instance** — a named individual with a level, learned abilities, an unlocking job tree, and equipment it keeps between battles, in the spirit of *Final Fantasy Tactics*.
- **A roster to nurture.** Players manage a **Battle Band**: a stable of character instances they recruit, level, equip, and field. The band persists across battles and across runs.
- **A single-player loop.** A **roguelike run** strings battles and events together into escalating sessions, played against a **tactical AI** that is competent but imperfect. This is the first version of the game playable solo, start to finish, with stakes.

Supporting these pillars are two force-multipliers: a **map editor** (internal tooling now, the foundation of player-created content later) and a **content pipeline** (CSV ↔ JSON) that makes authoring large libraries of classes, abilities, items, and characters a spreadsheet task rather than a hand-edited-JSON task.

### Continuity with the MVP

Nothing in the MVP combat model is discarded. Alpha extends the data model rather than replacing it: authored content is still consolidated JSON validated at load; runtime combat still operates on `BattleUnit` wrappers; the `StatKey` enum is still the single point of stat expansion. The major shift is that the **source of a `BattleUnit` changes**: in the MVP it derived from an immutable `CharacterData` premade; in Alpha it derives from a mutable, persistent **`CharacterInstance`** owned by a band.

---

## 2. Core Terminology (additions)

These extend the MVP glossary (`rpg-specs.md` §2); MVP terms still apply.

| Term | Meaning |
|------|---------|
| **Character Template** | An authored archetype (the MVP "premade character") used as the *seed* for generating new instances. Immutable authored data. Formerly just "Character" in the MVP. |
| **Character Instance** | A unique, persistent, mutable combatant generated from a template: has a generated identity, level/XP, per-class job points and learned abilities, unlocked classes, and an assigned equipment loadout. The thing players actually own and grow. |
| **Battle Band** | A player-owned, persistent roster of character instances plus a shared inventory (equipment, consumables) and currency (gold). The unit of save data the player manages and takes into combat. |
| **Run** | A single roguelike playthrough: a band traverses a graph of **nodes**, fighting and resolving events with escalating difficulty, until the run is won or lost. |
| **Node** | A single stop on the run graph. Node kinds: **Battle**, **Event** (random/narrative), **Boon** (helpful), **Hazard** (harmful), **Shop**, **Rest**, **Boss**. |
| **Archetype** | An MMORPG-style role family a class belongs to: **Support**, **Control**, **Physical Might** (Melee / Ranged), or **Magical Might** (Arcane / Divine·Holy). |
| **Vagabond** | The basic starting class every character begins as (analogous to FFT's Squire); root of the job tree. |
| **Job / Job Tree** | The class-progression structure. Classes are *unlocked* via prerequisites and their abilities are *learned* by spending **Job Points (JP)**. |
| **Job Points (JP)** | A per-character, per-class currency earned in battle and spent to learn that class's abilities. |
| **XP / Level** | Experience and the character level it produces; level drives stat scaling and gates class unlocks. |
| **Gold** | Band-level currency for buying equipment, consumables, and recruits. |
| **Loot** | Equipment, gold, or consumables awarded by battles and nodes. |
| **Meta-progression** | Account-level unlocks (new templates, classes, starting bonuses) that persist *across* runs, earned by playing. |
| **Dev mode** | A developer-only state, toggled by the **dev flag**, that exposes internal tooling (the map editor, debug overlays). Off in player builds. |
| **Controller** | The agent that issues a unit's actions during its activation — either the human `BattleController` (MVP) or the new `AIController`. Both speak to the same `TurnActions` backend. |

---

## 3. Map Editor

**Decision: internal developer tool in Alpha, reachable only in dev mode, architected so it can be exposed to players in a later phase.**

### 3.1 Purpose

Authoring maps by hand-editing tile arrays in JSON does not scale to the content volume Alpha needs. The map editor is a GUI scene for **painting maps visually** — terrain, elevation, deployment zones, and metadata — and saving them to the map JSON format.

### 3.2 Dev mode & access

The editor (and other internal tooling) is gated behind a **dev flag** — a single toggle that turns developer tools on or off.

- A `dev_mode` flag controls whether dev tooling is reachable. It is sourced from a project/`user://` config value and overridable by a launch argument or debug-build define, so developers can flip it without code changes and player builds ship with it **off by default**.
- When dev mode is **on**, a **Dev Tools menu** is exposed — an entry on the main menu and/or a debug hotkey/overlay — providing the entry point to the map editor and any future dev utilities (content tools, scenario runners).
- When dev mode is **off**, the Dev Tools menu and all entry points are hidden and the editor scene is unreachable through normal navigation.
- The same flag gates other developer affordances (e.g., the existing `DebugReadout` overlay) under one switch, so "dev tools" is a single, coherent on/off concept.
- No dev-only code path affects the shipped player experience when the flag is off.

This keeps the editor an internal tool while giving developers a real in-app entry point, and it is the seam through which a curated subset of tooling could later be exposed to players.

### 3.3 Functional requirements

The editor is a dedicated scene that reuses the existing 3D map rendering (`map_builder`, `hex_tile`, `tile_mesh`, `camera_rig`) and tile-picking (`tile_picker`).

| Capability | Description |
|------------|-------------|
| **New / load / save** | Create a blank map of a chosen size, load any existing `data/maps/*.json` for editing, and save back to the schema. Save runs the standard validator before writing. |
| **Grid sizing** | Set map dimensions (hexes across) and reshape the playable region (add/remove tiles to make non-rectangular maps). |
| **Terrain painting** | Select a terrain type from a palette and paint it onto tiles by clicking/dragging. Palette is data-driven from `terrain.json` (§4). |
| **Elevation editing** | Raise/lower a tile's integer elevation with a brush; optional flatten and ramp tools. |
| **Deployment zones** | Mark tiles as `playerA` / `playerB` deployment hexes (and, for runs, generic `enemy` / `player` zones). |
| **Metadata** | Edit map `id`, display name, and `tier`. |
| **Tile inspector** | Click a tile to view/edit its full record (q, r, elevation, terrain, zone membership). |
| **Undo / redo** | A bounded undo stack for destructive edits. |
| **Validation feedback** | On save (and on demand), surface validator errors inline rather than aborting silently. |

### 3.4 Architecture constraints (for later player-facing release)

- **Editor logic is separate from editor UI.** A headless `MapEditorModel` (in `src/core/` or a dedicated `src/tools/`) holds the editable map state and mutation operations (`set_terrain`, `set_elevation`, `add_tile`, `remove_tile`, `set_zone`, `to_map_data`, `from_map_data`). The editor scene is a thin controller over it. This mirrors the MVP's core/UI separation and is what makes a future player-facing editor a re-skin rather than a rewrite.
- **Save format is the stable contract.** The editor reads and writes the same map JSON consumed by the game (serialized per §4.4). No editor-only fields leak into the saved map; any editor session state lives in a separate sidecar if needed.
- **Round-trip fidelity.** `from_map_data(to_map_data(x)) == x` for any valid map.

### 3.5 Out of scope for Alpha (map editor)

In-editor playtesting, map sharing/distribution, prefab/decoration brushes beyond terrain, and a player-facing entry point. The architecture (§3.4) must not preclude them.

---

## 4. Terrain Types & Terrain Effects

The MVP shipped a small terrain table with move cost, LoS, and soft cover (`rpg-specs.md` §3.2). Alpha makes terrain **data-driven and effectful**: terrain types live in `terrain.json` with a structured effect schema, and the map editor paints from that data.

### 4.1 Terrain effect model

Each terrain type declares a set of effects. The schema is additive — new effect fields extend the table without breaking existing terrain.

| Effect field | Type | Meaning |
|--------------|------|---------|
| `move_cost` | `int` or `"impassable"` | AP-movement cost to enter (the MVP "slow" concept generalizes here). |
| `blocks_los` | `bool` | Whether the tile blocks line of sight (subject to elevation rules). |
| `cover` | `int` | Soft-cover ranged-DEF bonus granted to an occupant (the MVP `COVER_DEF` generalized to a per-terrain value). |
| `damage_on_enter` | `int` | Damage dealt when a unit enters the tile (e.g., caltrops). |
| `damage_per_turn` | `int` | Damage dealt at the start of an occupant's activation (e.g., lava, poison bog) — the **"dangerous"** category. |
| `status_on_enter` | `{status_id, duration}` | Status applied on entry (e.g., shallow-water → `slowed`). |
| `occupant_modifiers` | `[StatModifier]` | Stat modifiers applied while occupying (e.g., deep cover → +DEF, mud → −SPD). |
| `is_water` | `bool` | Tags the tile as water for ability/movement interactions (e.g., abilities that only target/avoid water). |
| `tags` | `[String]` | Free-form classification (`"hazard"`, `"water"`, `"forest"`, …) for content and AI heuristics. |

### 4.2 Terrain categories (the requested set)

The named categories from the feature request map onto the schema as follows; exact values are tunable content, not fixed here.

| Category | Realised via |
|----------|--------------|
| **Slow** | `move_cost > 1` (e.g., brush, mud, shallow water). |
| **Cover** | `cover > 0` and/or `blocks_los` (soft vs. hard cover). |
| **Dangerous** | `damage_on_enter` / `damage_per_turn` and/or `status_on_enter` (lava, spikes, poison bog). |
| **Water** | `is_water = true`; shallow = passable with `move_cost`/penalties, deep = `impassable` (MVP) or swimmable later. |

### 4.3 Combat & movement integration

Terrain effects are consumed by existing systems through their **injected providers** (the MVP already passes terrain properties to spatial-rule functions via a provider rather than direct `GameData` access — see CLAUDE.md "Dependency injection"). Specifically:

- **Pathfinding / movement** reads `move_cost` and `impassable`.
- **LoS / range** reads `blocks_los` (with the existing "higher attacker sees over" rule).
- **Resolution** reads `cover` for ranged defense.
- **Turn lifecycle** applies `damage_per_turn` at activation start and `damage_on_enter` / `status_on_enter` during movement resolution — new hooks in the round/turn system.
- **Stat layer** pushes/pops `occupant_modifiers` as units enter/leave tiles, using the existing `StatModifier` stack with `source = "terrain"`.

### 4.4 Map JSON — condensed serialization

Map files are **machine-generated by the editor and not intended for human editing**, so they are written in a **condensed, whitespace-minimal format**:

- **Minified JSON.** Saved maps contain no pretty-printing — no indentation or superfluous newlines. The whole file is a single compact line.
- **Compact tile records.** Each tile is serialized as a positional array rather than a verbose object — e.g. `[q, r, elevation, terrain]` (terrain as a short id/index) — instead of `{"q":…,"r":…,"elevation":…,"terrain":…}`. This drops repeated keys across what can be hundreds of tiles.
- **Terrain by reference.** Tile records reference terrain by id/short-code; terrain *effects* live once in `terrain.json` (§4.1), never duplicated per tile.
- **Loader contract.** At load, the condensed records are expanded back into typed `TileRecord` objects exactly as before; downstream consumers are unaffected. The loader accepts the condensed form; a one-time migration converts any remaining verbose MVP maps. Round-trip fidelity (§3.4) is preserved regardless of on-disk compactness.

> Rationale: terrain/map files are dense, generated data; compactness keeps them small and diff-noise low, and there is no need for them to be readable by hand now that the editor exists. Human-authored content (classes, abilities, items, characters) remains in the readable consolidated-JSON form and is edited via the CSV pipeline (§12), not by hand-editing these condensed map files.

---

## 5. Character Instances & Progression

This is the heart of the Alpha. It mirrors *Final Fantasy Tactics*: characters are individuals who **level up, learn abilities by job, change and upgrade jobs, and carry persistent gear**.

### 5.1 Template vs. instance

- A **Character Template** is authored data (the MVP `CharacterData`, conceptually renamed). It defines a starting archetype seed: race, identity/name tables, a **recommended path** (the archetype or class the template is built toward), and recommended starting equipment. Templates seed recruitment.
- A **Character Instance** is generated from a template and is the persistent, mutable object the player owns. **Every instance begins as a Vagabond at level 1** (§5.4) regardless of its template's recommended path; the template guides recruitment flavor and suggested progression, not the starting class. Instances are saved with the band (§9).

### 5.2 Generated identity

On creation, an instance receives a **unique id** and a **generated name** drawn from race-appropriate name tables (`data/names/*` or a `names` block in template data). Optionally a small appearance seed (color/symbol variation) for visual distinction; cosmetic only in Alpha. Identity is fixed for the instance's lifetime.

### 5.3 Leveling & stat scaling

- Characters earn **XP** from battles (and some nodes). Crossing an XP threshold grants a **level**.
- Each level applies **stat growth**. Growth is **class-driven** (FFT-style): the character's *active class at level-up* determines the per-level growth applied, via per-class growth rates authored in class data (e.g., `growth: {hp: 1.4, atk: 0.4, ...}` accumulated and floored, or a simpler flat per-level increment — exact model is a tunable in §5.7).
- Effective stats at any time = base (template) + accumulated growth + race/class modifiers + runtime modifier stack. The MVP three-layer stat model (`rpg-specs.md` §9.6.1) is preserved; growth feeds the **base** layer of the instance.
- An instance caps at a **max level** (tunable).

### 5.4 Classes, archetypes & the job tree

**Archetype paradigm.** Class design follows an **MMORPG archetype model**. Every class belongs to an archetype that defines its battlefield role; the job tree fans out across these roles so that builds read clearly as "tanky melee," "controller," "arcane nuker," "healer," etc.

| Archetype | Sub-branch | Role |
|-----------|------------|------|
| **Support** | — | Healing-adjacent utility, buffs, sustain, mobility aid. |
| **Control** | — | Debuffs, status effects, zoning, battlefield manipulation. |
| **Physical Might** | Melee | Front-line melee damage and durability. |
| **Physical Might** | Ranged | Ranged physical damage and skirmishing. |
| **Magical Might** | Arcane | Offensive elemental/arcane spellcasting. |
| **Magical Might** | Divine / Holy | Healing and holy magic (support-leaning casting). |

**Foundational job tree.**

- **Vagabond (starting class).** Every character begins as a **Vagabond** — a basic generalist with a small kit of fundamental abilities (e.g., a basic attack skill and a basic utility/move skill), analogous to FFT's Squire. It is the **root** of the job tree.
- At **character level 3**, the Vagabond **unlocks three tier-1 classes — Thief, Soldier, and Adept** — the first forays onto the archetype paths:
  - **Soldier** → opens the **Physical Might** path (melee and, downstream, ranged martial classes).
  - **Adept** → opens the **Magical Might** path (arcane and, downstream, divine/holy casting classes).
  - **Thief** → opens the **Control** and **Support** paths (utility, status, mobility).
- From these three tier-1 classes, **the job tree branches and explodes in complexity** — advanced and elite classes gated by JP/level prerequisites in their predecessors, spreading across all archetypes and their sub-branches.

The level-3 unlock point is a tunable (`TIER1_UNLOCK_LEVEL`, §5.7).

**Progression mechanics.**

- An instance has a set of **unlocked classes** (always including Vagabond).
- New classes unlock via **prerequisites**: reaching a JP/level threshold in a prerequisite class, and/or paying a cost. Prerequisites are authored per class, forming the **job tree**.
- Within a class, **abilities are learned by spending JP** earned for that class. Learned abilities persist on the instance permanently.
- **Class upgrading** is expressed as unlocking an advanced class along the tree and switching the active class to it; the character retains everything learned in prior classes.

**[ASSUMPTION] In-battle multiclass model.** Each instance fields with one **active (primary) class** that determines stat growth context, equipment access, and innate kit. On top of that, the player assembles a **free-form ability loadout**: any abilities the instance has *learned in any unlocked class*, up to an **ability-slot capacity** (tunable, see §5.7). This honours the project's stated "no hard two-job cap" vision while keeping battle UI and balance tractable. (Alternative models — strict FFT primary+secondary, or fully unrestricted — are easy to swap given the loadout abstraction.)

### 5.5 Equipment (persistent)

- Equipment is **owned by the band's inventory** and **assigned** to instances across the MVP slots (Weapon / Armor / Shield / Accessory). Assignments persist between battles.
- Equipment access is gated by the active class's `equipment_access`.
- Equipment carries `bp_value` (already in the MVP item schema) and now also an economic **price** (buy/sell) for the shop (§7.3).
- Item-bound abilities (MVP §4.5) continue to work: an instance gains an item's granted abilities while it has the item equipped.

### 5.6 Stat additions

**[ASSUMPTION] Two new canonical stats** are added to support deeper casting jobs that the larger content library (and FFT parity) imply:

| Enum value | String key | Meaning |
|------------|------------|---------|
| `MAG` | `"mag"` | Magic power — scales spell damage/heal values. |
| `RES` | `"res"` | Magic defense — mitigates magical damage. |

This uses the MVP's deliberate **single-point-of-expansion** design (`rpg-specs.md` §4.2.1): adding a stat means adding enum values; validation, derivation, and the modifier stack iterate over `StatKey.values()`. Resolution math gains a magical branch parallel to the physical one (spell value scales with `MAG`, mitigated by `RES`), replacing the MVP's "magic folded into per-ability values and DEF" simplification. **This is the most invasive Alpha change to combat math and should be confirmed before implementation.**

### 5.7 Progression-related tunables

```
MAX_LEVEL          = 50        // instance level cap
TIER1_UNLOCK_LEVEL = 3         // Vagabond unlocks Thief/Soldier/Adept at this level
XP_CURVE           = ...       // XP required per level (formula/table)
JP_PER_BATTLE      = ...       // base JP awarded to the active class
JP_SHARE           = ...       // JP to non-active unlocked classes (if any)
GROWTH_MODEL       = "per_class_rate"   // how level-ups apply stat growth
ABILITY_SLOTS      = 6         // free-form learned-ability loadout capacity
CLASS_UNLOCK_COST  = ...       // JP/gold cost to unlock an advanced class
```

---

## 6. Battle Bands

A **Battle Band** is the player's persistent roster and the primary thing they manage between battles.

### 6.1 Composition

| Element | Description |
|---------|-------------|
| **Identity** | Band name (player-chosen) and a stable id. |
| **Roster** | A list of character instances (size cap tunable; larger than any single fielded party). |
| **Inventory** | Owned equipment not currently equipped, plus consumable items. |
| **Gold** | Band currency. |
| **Fielded selection** | The subset of roster taken into a given battle, chosen under the tier's BP/size rules at deployment. |

### 6.2 Management (out of battle)

A management UI (its own scene, sibling to the draft scene) lets players:

- **Inspect** an instance: stats, level/XP, unlocked classes, learned abilities, equipment, BP.
- **Level/spend:** allocate JP to learn abilities; unlock/upgrade classes; set the active class; assemble the ability loadout.
- **Equip:** assign/unassign equipment from inventory.
- **Recruit / dismiss:** add a new instance (generated from an available template, for a gold or run cost) or remove one.
- **Shop:** buy/sell equipment and consumables (§7.3), where the node/context allows.

### 6.3 Recruitment

New instances are generated from **available templates**. Availability can be gated by meta-progression (§8.6) and by run context (e.g., a "recruit" event node). Generation produces identity (§5.2), starts the instance as a Vagabond (§5.4), and grants a starting kit appropriate to the band's current power level (tunable scaling so recruits aren't dead weight).

### 6.4 BP in the Alpha

BP no longer gates a draft against a human opponent in single-player; instead it is the **value metric** used to (a) scale and match enemy bands to run difficulty (§8.5) and (b) preserve the existing tier rules for retained hotseat PvP (§10). Instance BP is **derived** from current level, effective stats, learned-ability loadout, and equipment, via the MVP's BP heuristic (`rpg-specs.md` §7.6) recomputed on change.

---

## 7. Economy: Gold, Shops & Loot

### 7.1 Currency

**Gold** is band-level. Earned from battles, Boon nodes, and selling equipment. Spent on equipment, consumables, recruits, and class unlocks.

### 7.2 Loot

Battle and node rewards draw from **loot tables** scaled by run depth: gold, equipment (by tier/slot), and consumables. Loot tables are authored data.

### 7.3 Shops

Shop nodes (and the out-of-battle management screen, where permitted) expose a **buy/sell** interface. Prices derive from item `price` (authored) or fall back to a function of `bp_value`. Sell value is a tunable fraction of buy price.

### 7.4 Economy tunables

```
SELL_RATIO         = 0.5       // fraction of price recovered on sell
LOOT_DEPTH_SCALE   = ...       // how reward quality scales with run depth
RECRUIT_COST       = ...       // gold to recruit from a template
```

---

## 8. Single-Player: The Roguelike Run

The single-player experience is a **roguelike run**: a band embarks, traverses a graph of nodes of escalating difficulty, and either completes the run (boss/final node) or is defeated.

### 8.1 Run structure

- A run is a **graph of nodes** (a branching path, à la *Slay the Spire*; a simple linear or small-branching layout is acceptable for Alpha). The player chooses which node to advance to among available next nodes.
- Difficulty scales with **depth** (distance into the run).
- The run ends in **victory** (clearing the final/Boss node) or **defeat** (band wiped or a run-ending failure).

### 8.2 Node kinds

| Node | Behavior | Alpha completeness |
|------|----------|--------------------|
| **Battle** | A tactical battle vs. an AI-controlled enemy band on a selected/generated map. The core node. | Full. |
| **Boss** | A harder, set-piece battle terminating a run or act. | Full (one boss is enough for Alpha). |
| **Event** | A random narrative encounter with one or more choices and outcomes. | **Simple / feature-incomplete OK** — a small authored event table with text + basic outcomes. |
| **Boon** | A purely helpful outcome (heal, gold, item, XP/JP). | Simple. |
| **Hazard** | A harmful outcome (damage, gold loss, status). | Simple. |
| **Shop** | Buy/sell (§7.3). | Functional. |
| **Rest** | Recover HP / clear injuries; possibly spend to upgrade. | Functional. |

> Per the feature request, **Event/Boon/Hazard nodes may be simple and feature-incomplete in Alpha** — a minimal data-driven table of outcomes is sufficient. The node *framework* should be extensible so richer events can be added without restructuring runs.

### 8.3 Run rewards & progression

Within a run, battles and nodes grant XP, JP, gold, and loot to the band (§5, §7). The band's growth *within* a run is the moment-to-moment power curve; meta-progression (§8.6) is the *between*-run curve.

### 8.4 Defeat, downing & death

Death follows a **per-run down limit**: a character can be knocked out only so many times before the loss becomes permanent.

- During a battle, a downed unit (HP ≤ 0) is removed from that battle as in the MVP.
- Each character carries a **down counter scoped to the current run**. A character may be downed up to **`DOWN_LIMIT` (default 2)** times and recover after each (recovery may require a Rest node or an HP/gold cost).
- On the **next down past the limit — the 3rd by default — the character permanently dies** and is removed from the band.
- The down counter **resets at the start of a new run**.
- **`DOWN_LIMIT` is tunable for difficulty and progression**: harder runs or higher difficulty tiers may lower it (toward true permadeath at 0), while meta-progression perks or easier modes may raise it.

A **run is lost** when the band can no longer field a legal party (all fielded units down with no reserves, or an objective failure).

### 8.5 Encounter generation & difficulty

For each Battle node, the run generator selects:

- A **map** (from the authored/edited map pool, filtered by tier/size for the depth).
- An **enemy band** — composed from templates and scaled to a **target BP** for the current depth (§6.4), so encounters track the player's growing power.

Generation parameters (depth→BP curve, composition rules, map pool) are authored/tunable data, not hard-coded.

### 8.6 Meta-progression

Completing runs (and milestones within them) grants **account-level unlocks** stored in a profile (§9.4): new templates available for recruitment, new classes seeded as unlocked, and optional starting boons. Meta-progression is intentionally light in Alpha but the **profile/unlock data model exists** so it can grow.

### 8.7 Run tunables

```
RUN_LENGTH         = ...       // nodes/acts per run
DEPTH_BP_CURVE     = ...       // enemy target BP by depth
DOWN_LIMIT         = 2         // downs allowed per character per run; next down = permadeath
NODE_WEIGHTS       = ...       // relative frequency of node kinds
```

---

## 9. Data Model (Alpha additions)

Alpha **adds** schemas and **extends** a few existing ones. The MVP entity schemas (Character→Template, Class, Ability, Item, Map) remain, with the noted additions. The fundamental rule is unchanged: **authored content** is immutable, validated JSON; **persistent player state** (instances, bands, runs, profile) is mutable save data, kept strictly separate from authored content.

### 9.1 Authored-content additions/extensions

- **Class** gains: `archetype` (Support / Control / Physical Might / Magical Might) and optional `branch` (Melee, Ranged, Arcane, Divine); `growth` rates (§5.3); `prerequisites` (job-tree edges); `jp_costs` per granted ability; `tier` (starting/tier-1/advanced/elite); and the new stat keys in `stat_modifiers`.
- **Ability** gains: `jp_cost`, optional `mag_scaling` (for the magical resolution branch, §5.6), and richer `effect_type`s as content grows (additive to the MVP effect-type table).
- **Item** gains: `price` (economy), and supports the new stat keys in passives.
- **Terrain** gains: the full effect schema (§4.1).
- **Character Template** gains: `name_tables` (or reference), `recommended_path` (target archetype/class; the *actual* starting class is always Vagabond), and `recruit_availability` (meta-gating).
- **New authored tables:** `names` (per-race), `loot_tables`, `events` (Event/Boon/Hazard outcomes), `shop_pools`, `run_config` (depth curves, node weights), and `meta_unlocks`.

### 9.2 Persistent player-state schemas (new, saved)

```json
// CharacterInstance — persistent, mutable
{
  "instance_id": "ci_8f3a...",        // generated unique
  "template_id": "human_recruit",
  "name": "Aldric Fenn",               // generated identity
  "race": "human",
  "level": 7,
  "xp": 1240,
  "active_class": "soldier",
  "unlocked_classes": ["vagabond", "soldier"],   // always includes vagabond
  "jp": { "vagabond": 0, "soldier": 60 },
  "learned_abilities": ["basic_strike", "guard", "power_strike", "..."],
  "ability_loadout": ["power_strike", "guard", "..."],   // ≤ ABILITY_SLOTS
  "equipment": { "weapon": "short_sword", "armor": "studded_leather", "shield": "buckler", "accessory": null },
  "growth_accumulated": { "hp": 9, "atk": 3, "...": 0 },
  "downs_this_run": 0                  // run-scoped; permadeath when it would exceed DOWN_LIMIT
}
```

```json
// BattleBand — persistent, mutable
{
  "band_id": "bb_1",
  "name": "The Ashen Few",
  "roster": ["ci_8f3a...", "ci_2b9c..."],
  "inventory": { "equipment": ["short_sword", "..."], "consumables": [{"id":"potion","qty":3}] },
  "gold": 540
}
```

```json
// RunState — persistent during a run
{
  "run_id": "run_42",
  "band_id": "bb_1",
  "seed": 1234567,
  "graph": { "nodes": ["..."], "edges": ["..."] },
  "position": "node_12",
  "depth": 3,
  "down_limit": 2                      // snapshot of the tunable for this run
}
```

```json
// Profile — account-level meta-progression
{
  "profile_id": "default",
  "unlocked_templates": ["human_recruit", "..."],
  "unlocked_classes": ["..."],
  "completed_runs": 2,
  "meta_unlocks": ["..."]
}
```

### 9.3 Instance → BattleUnit at battle start

At deployment, each fielded `CharacterInstance` produces a `BattleUnit` exactly as the MVP did from `CharacterData`, except the source of base stats is the instance's **derived effective stats** (template base + growth + class/race modifiers) and the kit is the instance's **ability loadout** and equipped items. The combat layer below `BattleUnit` is unchanged.

### 9.4 Save system

**[ASSUMPTION]** Persistent state is stored as JSON save files under Godot's `user://` directory (e.g., `user://saves/`), separate from `res://data/` authored content. Multiple bands and an in-progress run are supported. A small `SaveManager` autoload handles load/save/migrate. Versioned save schema with a `save_version` field for forward migration. (Binary/encrypted saves are out of scope.)

---

## 10. Multiplayer & Modes

- The MVP's **hotseat two-player skirmish** (shared-pool draft → battle) is **retained** as a mode. With instances/bands, a "quick battle" mode using throwaway generated bands or premade templates can stand in for the old draft so MVP behavior is preserved.
- **Single-player roguelike** (§8) is the new flagship mode.
- **Networked multiplayer remains out of scope** (deferred since the MVP), and nothing in Alpha precludes it.

---

## 11. AI Opponent

The AI controls enemy units in single-player. The bar for Alpha is **"basic but competent, with variance"** — it should use the map and its kit sensibly, threaten the player, and lose to good play, without being perfectly optimal.

### 11.1 Architecture

- An **`AIController`** is a peer of the human `BattleController`: it receives an active unit and issues actions through the **same `TurnActions` backend** the human uses. It has no privileged access — only the legal action surface. This guarantees the AI cannot do anything a player couldn't and keeps combat rules in one place.
- Per-activation, the AI **enumerates candidate plans** (move targets × actions × ability targets, pruned for legality and tractability) and **scores** each with a utility heuristic.

### 11.2 Decision heuristic (Alpha)

A utility function over candidate actions weighing, at minimum:

- Expected damage dealt / kills secured.
- Expected damage taken / exposure (prefer cover, higher elevation, avoid hazard terrain — directly using §4 effects).
- Positioning toward valuable targets (low-HP enemies, vulnerable casters) and away from overwhelming threats.
- Ability value (use heals when allies are hurt, buffs when impactful, AoE on clusters).
- WP/AP economy (don't waste resources).

### 11.3 Variance & difficulty

To avoid robotic optimality, the AI **does not always pick the top-scored plan**. It samples from the top-N scored plans with a temperature/ε parameter, and difficulty levels tune that randomness (and optionally search breadth). This delivers the requested "variance in optimality." A fixed RNG seed (from the run) keeps battles reproducible for debugging.

### 11.4 Scope & extension points

Alpha targets **single-activation tactical decisions** (greedy with variance), not multi-turn look-ahead or coordinated team planning. The scorer and plan-enumerator are the designated extension points for smarter AI later.

### 11.5 AI tunables

```
AI_TOP_N           = 3         // sample among top-N scored plans
AI_TEMPERATURE     = ...       // randomness of selection
AI_DIFFICULTY      = "normal"  // presets adjusting top_n/temperature/breadth
```

---

## 12. Content Expansion & Authoring Pipeline

Alpha **greatly expands** the content libraries — classes, abilities/spells, items, and character templates — and introduces tooling so that authoring at volume is a spreadsheet workflow.

### 12.1 CSV ↔ JSON round-trip

**Decision: a converter that exports the consolidated JSON tables to CSV and re-imports CSV back to JSON**, so content can be edited in Google Sheets / Excel.

- **Tooling:** a converter (CLI script runnable headless, and/or an editor utility) per entity type. `json→csv` for export, `csv→json` for import. Import runs the existing **validator** before writing; invalid content is rejected with precise errors (reusing the MVP validation layer).
- **Lossless round-trip:** `csv→json(json→csv(x))` is semantically identical to `x`. This is a tested invariant.
- **Flattening convention for nested fields:** the JSON schemas contain nested structures (e.g., ability `effect`, `area`; stat dicts). The pipeline defines a **flattening convention** — the working assumption is **dotted column headers** for fixed nested keys (e.g., `effect.effect_type`, `effect.value`, `area.shape`, `area.radius`, `stats.hp`) and **JSON-encoded cells** for variable-length/complex fields (e.g., arrays like `granted_abilities`, `prerequisites`). The exact convention is finalized in the pipeline sub-phase; round-trip fidelity is the acceptance test.
- **Scope:** the CSV pipeline targets **human-authored content** (classes, abilities, items, character templates, terrain definitions). The **condensed, generated map files** (§4.4) are produced by the map editor, not the CSV pipeline.
- **Workflow:** export JSON→CSV → edit in spreadsheet → import CSV→JSON → validate → commit. The authored JSON in `res://data/` remains the source of truth the game loads; CSV is an authoring convenience, not a runtime format.

### 12.2 Content targets (aspirational, tunable)

Volume goals to make builds "deep and meaningful" — seeds for planning, not contractual. Classes are organized across the §5.4 archetypes and the Vagabond-rooted job tree.

| Content | MVP | Alpha target |
|---------|-----|--------------|
| Classes | 8 | ~20+ (Vagabond root → Thief/Soldier/Adept → branches across all archetypes) |
| Abilities/spells | 14 | ~80+ |
| Items/equipment | 12 | ~50+ |
| Character templates | 8 | ~20+ |
| Maps | 6 | ~15+ (accelerated by the editor) |
| Terrain types | (small set) | expanded effectful set (§4) |

### 12.3 Validation at scale

The MVP validator (structural + referential) is extended to the new fields (class archetype/branch, job-tree prerequisites, jp_costs, prices, terrain effects, loot/event tables) and remains the gate for both boot-load and CSV import. Referential checks grow to cover new cross-references (class prerequisites resolve and form a valid tree rooted at Vagabond, loot/shop pools reference real items, events reference real outcomes).

---

## 13. Proposed Sub-Phase Roadmap

Mirroring the MVP's phased approach. This is a **starting proposal** for `alpha-implementation-plan.md`; ordering reflects dependencies (foundations and tooling first, the run that ties everything together last). Each sub-phase should end in a demonstrable state with tests, as in the MVP.

| Sub-phase | Theme | Rationale / dependencies |
|-----------|-------|--------------------------|
| **A0** | Terrain effects, condensed map format & dev flag | Foundational; needed by editor, combat hooks, and AI heuristics. Extends `terrain.json` + combat/turn hooks; adds the dev-mode toggle and condensed map serialization. |
| **A1** | Map editor (dev tool) | Builds on terrain + dev flag (A0) and existing rendering. Accelerates all later map content. |
| **A2** | CSV ↔ JSON content pipeline | Tooling to enable content volume; extends validator. Independent of combat. |
| **A3** | Stat additions & magical resolution (`MAG`/`RES`) | Combat-math change underpinning deeper casters; do before mass ability authoring. |
| **A4** | Character instances, classes & job tree | Templates→instances, Vagabond start, leveling, growth, JP, archetype job tree, ability loadout. Core data shift. |
| **A5** | Battle Bands & save system | Persistent roster/inventory/gold + `user://` saves. Depends on A4. |
| **A6** | Economy: gold, shops, loot | Currency, loot tables, shop UI. Depends on A5. |
| **A7** | AI opponent | `AIController` over `TurnActions` with scored, variance-driven decisions. Depends on A0 (terrain awareness). |
| **A8** | Roguelike run framework | Node graph, node kinds, encounter generation, run state, down-limit death model. Ties A4–A7 together. |
| **A9** | Content expansion | Author the large libraries via the A2 pipeline + A1 editor. Parallelizable once A2–A4 land. |
| **A10** | Polish & meta-progression | Profile/unlocks, run rewards tuning, UX polish, balance. First coherent solo experience. |

> Like the MVP, content authoring (A9) runs in parallel once its dependencies (pipeline A2, schema A3–A4) are stable.

---

## 14. Out of Scope (Alpha) / Future Work

Deferred, but the Alpha systems are designed to accommodate them:

- **Player-facing map editor** distribution and sharing (architecture-ready, §3.4).
- **Networked multiplayer** (still deferred).
- **Rich narrative events / story campaign** — Alpha events are intentionally minimal (§8.2).
- **Deep AI** — multi-turn planning, team coordination, learned behavior (§11.4).
- **Advanced progression** — equipment crafting/upgrading, status/elemental affinity systems beyond the MVP, reaction/overwatch depth.
- **Full art, audio, and VFX** — placeholder visuals (procedural tokens/symbols) continue.
- **Mod support** beyond the CSV authoring convenience.

---

## Appendix A — Requirements Traceability

| # | Alpha requirement | Where addressed |
|---|-------------------|-----------------|
| 1 | Map editor with full GUI support | §3 |
| 2 | Map editor as dev tool now, player-facing later | §3 (decision), §3.4 |
| 3 | Map editor reachable via dev-flag-gated dev tools UI | §3.2 |
| 4 | Multiple terrain types & effects (slow, cover, dangerous, water) | §4, §4.2 |
| 5 | Terrain effects integrated into movement/LoS/combat | §4.3 |
| 6 | Condensed, whitespace-minimal map/terrain file format | §4.4 |
| 7 | Character instances with unique generated identities | §5.1, §5.2 |
| 8 | Leveling & scaling stats | §5.3 |
| 9 | Vagabond starting class; L3 unlocks Thief/Soldier/Adept | §5.4 |
| 10 | MMORPG archetype paradigm (support/control/physical/magical) | §5.4 |
| 11 | Class upgrading / job tree | §5.4 |
| 12 | Persistent equipment | §5.5, §6.1 |
| 13 | FFT-style progression depth (XP, JP, gold, loot) | §5, §7 (decision) |
| 14 | New stats for deeper casters (`MAG`/`RES`) | §5.6 |
| 15 | Persistent characters & Battle Bands | §6 |
| 16 | Band management: upgrade, add/remove, field | §6.2 |
| 17 | Single-player support | §8, §10 |
| 18 | Basic AI with variance in optimality | §11, §11.3 |
| 19 | Roguelike run of nodes (battles + events) | §8, §8.2 (decision) |
| 20 | Helpful/harmful & random event nodes (may be simple) | §8.2 |
| 21 | Character death: 2 downs/run, 3rd = permadeath, tunable | §8.4, §8.7 |
| 22 | Greatly expanded classes/items/characters/abilities | §12, §12.2 |
| 23 | Visual data editing via CSV ↔ JSON | §12.1 (decision) |
| 24 | Persistence / save system | §9.2, §9.4 |
| 25 | Sub-phase breakdown like the MVP | §0, §13 |
| 26 | Headroom for features arising during Alpha | §0, §13 (extensible), §14 |
