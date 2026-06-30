# Feature Scan & Competitive Analysis

**Project:** RPG Battle Simulator (FFT-style tactical battler, Godot 4.6.3 / GDScript)
**Date:** 2026-06-30
**Method:** Code-level scan of `src/`, `scenes/`, `data/` (not docs); competitive comparison against the tactics-RPG genre.
**Purpose:** Establish the current implemented feature set, then propose differentiated features benchmarked against comparable games. This is a planning document — suggestions are options with trade-offs, not commitments.

---

## Part 1 — Current Feature Set (as implemented in code)

### Combat
Alternating-activation turn structure (not full-team turns) with a 2-AP action economy: Move (1), Attack (1), Ability (1–2), Defend/Wait/Item (1). Dual damage resolution — a physical branch (`roll + ATK + weapon + height − DEF − cover`) and a magical branch (`roll + value + mag_scaling×MAG − RES`), both with a 1d6 roll, a +2 high-ground bonus, and a Defend die that reduces either type. Willpower (WP) gates spell/ability use per-ability and per-character. Min-range 2 for ranged attacks (cannot hit adjacent). Victory on enemy wipe; a rout threshold and a down/permadeath model layer on top in the run. **13 status effects** are implemented (poison, regen, slowed, immobilized, sleep, blind, silence, confusion, provoked, stun, dispel, cleanse, and related). Key files: `combat_resolver.gd`, `turn_actions.gd`, `round_manager.gd`, `match_state.gd`.

*Partial / absent:* AoE shapes are authored on abilities but multi-tile application is incomplete (the schema is missing `area.length`/`area.depth`, per `content-pipeline-pending-changes.md`); no elemental weakness/resistance table, no critical hits, no facing/back-attack rules, no reaction/counter abilities, and turn order is flat alternation rather than a speed-driven tick.

### Hex & terrain
Flat-top axial hex grid with elevation. Elevation-aware Dijkstra pathfinding with a jump/climb budget, hybrid LoS with height interpolation (higher attacker sees over obstacles), and range queries. **17 terrain types** with structured effects: move cost, impassability, LoS blocking, cover value, damage-on-enter (spikes), damage-per-turn (lava), status-on-enter (bog/ice → slowed), and occupant stat modifiers (cursed/blessed ground). Condensed map format `[q, r, elev, terrain]`. Key files: `hex.gd`, `movement.gd`, `line_of_sight.gd`, `terrain_props.gd`.

### Characters & progression
Persistent `CharacterInstance` with generated identity, level/XP, per-class JP, unlocked classes, learned abilities, a loadout, and equipment. **9 stats** (SPD, ATK, RNG, DEF, HP, JUMP, WP, MAG, RES). FFT-style job tree rooted at Vagabond → Thief/Soldier/Adept at level 3 → advanced/elite branches across physical/magical/control/support archetypes, gated by level + JP. Class-driven stat growth on level-up; abilities learned by spending JP; 4 equipment slots. Key files: `character_instance.gd`, `instance_stat_resolver.gd`, `class_data.gd`.

### Bands, economy & save
`BattleBand` roster (cap 12) with shared equipment/consumable inventory and gold. Versioned JSON save under `user://` (band, profile, in-progress run) with atomic writes. Shops with buy/sell (sell at a fraction), authored loot tables with depth scaling, recruiting from templates scaled to band power, consumables as stacked items. Key files: `battle_band.gd`, `save_manager.gd`, `shop_service.gd`, `loot_roller.gd`, `pricing.gd`.

### AI
`AIController` issues actions through the same `TurnActions` backend as the human (no privileged access). `AIPlanner` enumerates candidate plans (move × action × target, pruned to ~12 tiles); `AIScorer` is a weighted utility heuristic over expected damage, kills, exposure, cover, elevation, hazards, target priority, ability value, and AP/WP economy, evaluated with the average die (deterministic scoring). Variance via top-N softmax sampling with a temperature/difficulty parameter. *Single-turn greedy horizon — no lookahead or multi-unit coordination.* Key files: `ai_planner.gd`, `ai_scorer.gd`.

### Roguelike run & meta
Branching node graph (Battle, Boss, Event, Boon, Hazard, Shop, Rest) with depth-scaled difficulty, encounter generation (map + scaled enemy band), down-limit permadeath (default tunable), and run win/loss. Account-level `Profile` with meta-unlocks (templates/classes), data-driven unlock rules (run_complete / boss_kill / depth_reached / runs_completed), and starting boons. Key files: `run_graph.gd`, `encounter_generator.gd`, `death_model.gd`, `profile.gd`, `meta_unlock_engine.gd`.

### UI, visuals & dev tooling
Scenes for main/draft/band-management/run/battle, plus a dev menu and map editor. 3D hex rendering with pawns, overlays, range markers, dice markers, status markers, and a generated icon atlas. Dev tooling: headless map editor model + GUI, CSV↔JSON content pipeline for all entity types, and dev-flag-gated cheats. Key files: `battle_controller.gd`, `map_builder.gd`, `map_editor_model.gd`, `csv_exporter.gd`/`csv_importer.gd`, `dev_cheat_service.gd`.

### Content (live vs staged)
The **live JSON** the game loads: 25 classes, 82 abilities, 46 items, 20 character templates, 4 races, 17 terrains, 6 maps, 73 encounters, 2 loot tables, 4 shop pools, small event/boon/hazard and meta-unlock sets.

A **much larger library is staged in `data/csv/`** — **268 classes, 787 abilities, 160 characters, 32 races, 128 items** — not yet imported because it needs the n-tier class-validator change and the AoE schema columns (see `class-tree-engine-changes.md`, `content-pipeline-pending-changes.md`; import is folded into roadmap phase A11).

### Status against genre baseline
The project already has the *hard* tactical foundations most comparators are known for: job tree with JP, height/LoS tactics, terrain effects, a competent utility AI, permadeath, and a roguelike meta-loop. The gaps are mostly in **combat texture** (reactions, facing, elements, AoE completion, speed-based turn order) and **signature systems** that make a tactics game memorable.

---

## Part 2 — Competitive Landscape

How the touchstones differentiate themselves:

| Game | Signature systems worth studying |
|------|----------------------------------|
| **Final Fantasy Tactics** | Charge-Time (CT) speed-based turn order; primary + **secondary job** ability sets; **Reaction / Support / Movement** passive slots (counter, auto-potion, etc.); facing & back/side attacks; Brave/Faith hidden stats; Zodiac compatibility multipliers; monster recruitment & breeding; permadeath with crystals/treasure on death. |
| **Tactics Ogre (Reborn / LUCT)** | Branching **Law/Chaos/Neutral** story routes; **CHARM/persuade** to recruit enemies mid-battle; class-based (not character-based) leveling; the **WORLD** tarot system for rewinding to branch points; training battles; buff/debuff-rich finishers; team morale. |
| **Disgaea** | **Geo Panels / Geo Symbols** — a tile-color puzzle layer with chain-clear bonuses; **Item World** (procedural dungeons *inside* every item to level the item); **lift & throw / tower** stacking of units; **Magichange** (monster→weapon); **Reincarnation** (reset to level 1 with higher caps/innate carryover); huge numbers (level cap 9999); **Evilities** (passive trait slots); the Cheat Shop / Dark Assembly (player-tunable rules and unlocks via vote). |
| **Fire Emblem / Three Houses** | **Battle forecast** (perfect pre-attack hit/damage/crit preview); weapon triangle; support/relationship bonuses between adjacent units; classic permadeath; gambits/combat arts. |
| **Into the Breach** | **Full enemy-intent telegraphing** with perfect information — the entire next enemy turn is shown; tight 8-turn puzzle loops; reposition/shove as the core verb; a single-undo "reset turn" affordance. |
| **XCOM** | Overwatch/reaction fire; percent-to-hit with flanking/cover bonuses; squad-level meta between missions; injury/fatigue downtime. |

---

## Part 3 — Differentiated Feature Suggestions

Each suggestion lists the comparator it draws from, why it differentiates *this* game, rough effort, and where it slots against the existing code seams / `roadmap-A11-onward.md`. Effort is relative (S/M/L).

### A. Combat texture — closing the genre baseline (high value, builds on existing seams)

1. **Complete AoE shapes (burst/ring/line/cone).** *Source: all comparators.* Already authored; just needs the schema columns + multi-tile application loop in `turn_actions._collect_affected_units`. **Effort S.** Slots into A11's content-import prerequisite. This is the single highest-leverage fix — 24 line/cone abilities currently degrade to single-tile.

2. **Reaction / Support / Movement passive slots.** *Source: FFT.* Add passive ability slots on `CharacterInstance` (counter-attack, auto-potion, defend-on-low-HP, +1 move). High identity payoff, reuses the ability/JP system. **Effort M.** New progression sub-feature; hooks `combat_resolver` for reaction triggers.

3. **Facing & flanking.** *Source: FFT, Tactics Ogre, Fire Emblem, XCOM.* Track unit facing; back/side attacks get hit/damage bonuses. Pairs naturally with the hex grid (6 facings) and the existing height bonus. **Effort M.** Touches `combat_resolver`, deployment facing, and AI scoring.

4. **Speed-based turn order (CT tick).** *Source: FFT, Tactics Ogre.* Replace flat alternation with a Charge-Time clock driven by SPD, so fast units act more often and Slow/Haste become meaningful. **Effort L** (reworks `round_manager`, AI assumptions, HUD turn-order display) — a deeper change; consider as its own phase. The A13 coin-flip cleanly handles *opening* initiative regardless.

5. **Elemental affinities & reactions.** *Source: Disgaea, FF series.* Per-unit/terrain element resist/weak table; optional chain reactions (fire on bog → burn, ice on water → freeze). The expanded 787-ability library is element-tagged, so the data is largely ready. **Effort M.**

### B. Signature systems — what could make this game *stand out*

6. **Geo-Panel-style terrain puzzle layer (hex edition).** *Source: Disgaea Geo Symbols — strongest differentiator.* The terrain system already supports occupant modifiers and per-tile effects; extend it with placeable/destroyable "geo" tokens that color regions, grant stacking effects, and trigger **chain-clear** bursts. On a *hex* grid with elevation this becomes a genuinely novel spatial puzzle no major tactics game offers. **Effort L**, but it's the most ownable idea here and reuses A0 terrain + A1 editor + A14 symbol-pawn feedback.

7. **Into-the-Breach-style enemy-intent telegraphing (as a mode/difficulty).** *Source: Into the Breach.* The AI already plans deterministically with the average die — surface the *intended* enemy plan as a preview before the player commits. Turns the existing AI into a tactical-puzzle generator and is a modern, accessibility-friendly differentiator. **Effort M** (AI already produces plans; needs a preview layer + a "perfect-information" toggle). Strong synergy with the deterministic `TurnActions` log noted in `seam-audit.md`.

8. **Battle forecast / hit preview.** *Source: Fire Emblem.* Show projected damage range, defend-die effect, and resulting HP before confirming an attack. Low risk, high quality-of-life, and the resolver math is already centralized in `combat_resolver`. **Effort S–M.**

9. **Item World — "delve an item to upgrade it."** *Source: Disgaea.* Reuse the *existing* run-graph and encounter generator to generate a short procedural sub-run "inside" a piece of equipment that levels/enhances it. Exceptional reuse of A8 infrastructure for a beloved, sticky progression hook. **Effort M–L.**

10. **Capture / persuade recruitment.** *Source: Tactics Ogre CHARM, FFT monsters.* Let players recruit defeated or persuaded enemies into the band — ties the 73-encounter roster and expanded monster classes directly into roster growth. **Effort M.** Hooks the down/death model and `Recruiter`.

11. **Lean into the coin-flip as a "gambit/luck" subsystem.** *Source: original, seeded by A13.* A13 builds a reusable `CoinFlip`; extend it into high-risk/high-reward gamble events, coin-flip abilities, and tie-breaks. A small, distinctive identity thread that's cheap once A13 lands. **Effort S.** Already on the roadmap as proposed A16.

### C. Meta-progression & replayability

12. **Build-defining run relics / synergies.** *Source: modern roguelikes (Slay the Spire, Hades).* The boon system exists but is thin; add relics that change *rules* (e.g., "Defend die is d8", "first spell each battle is free WP"). High replay value, fits `meta_unlock_engine` + boon plumbing. **Effort M.**

13. **Daily/weekly seeded runs + score.** *Source: roguelike convention.* The run is already seed-deterministic — expose a fixed daily seed and a score metric. **Effort S–M.**

14. **Reincarnation / prestige for characters.** *Source: Disgaea.* Reset a maxed character to level 1 with raised growth/caps and innate ability carryover — long-tail progression for the permadeath roster. **Effort M.** Fits `character_instance` + profile.

### D. Presentation & UX

15. **Telegraphed deployment + (optional) repositioning.** A12 locks placement by design; consider an undo affordance or a one-time reposition, weighed against the intended tension. *Source: Into the Breach's single undo.* **Effort S.** A design call, not just engineering.

16. **Animation & camera polish layer.** A14 (symbol pawns) starts this; a cinematic action camera and hit/cast animations are the largest perceived-quality gap vs. comparators. **Effort L**, best sequenced after combat texture lands. Maps to proposed A17 (audio/game-feel).

---

## Part 4 — Recommended Sequencing

A pragmatic order that maximizes payoff per unit of risk:

1. **Finish the baseline that's already 90% there** — complete AoE (#1, folded into A11), then battle forecast (#8) and reactions/facing (#2, #3). These make every existing encounter feel better immediately.
2. **Pick one signature system to own** — the **hex Geo-Panel layer (#6)** or **enemy-intent telegraphing (#7)**. Either gives the game a one-line identity; #7 is cheaper and leverages the existing AI, #6 is more novel but heavier.
3. **Deepen the meta-loop** — relics (#12) and Item World (#11) extend session length using infrastructure already built (A8/A10).
4. **Polish pass** — speed-based turn order (#4) if the deeper combat rework is wanted, then animation/camera/audio (#16, A17).

The biggest combat decision is **#4 (CT turn order)**: it's the most authentic-to-FFT change but also the most invasive (AI, HUD, balance all shift). Worth a dedicated spec and a deliberate go/no-go rather than bundling it in.

---

*Open question for you:* of the two "signature" candidates — the **hex Geo-Panel puzzle layer** vs. **Into-the-Breach enemy telegraphing** — which direction matches your vision for the game's identity? That choice most shapes the roadmap beyond A14.
