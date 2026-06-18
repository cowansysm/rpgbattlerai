# Phase A6 — Economy: Gold, Shops & Loot Specification

**Parent plan:** `alpha-implementation-plan.md` (Phase A6)
**Master spec:** `alpha-specs.md` (§7 Economy)
**Builds on (Alpha):** `alpha-phaseA5-spec.md` (`BattleBand` gold + inventory, `SaveManager`), `alpha-phaseA4` (instances/recruits), `alpha-phaseA2` (item CSV `price` column)
**Builds on (MVP):** `phase1` (`ItemData`, `Validator`, `GameData`)
**Engine:** Godot **4.6.3** · **Language:** GDScript (typed)
**Date:** 2026-06-17

---

## 1. Purpose & Scope

Phase A6 adds the **reward-and-spend loop** that gives progression stakes: **gold**, **item prices**, **shops** (buy/sell), and **loot tables** that pay out after battles and nodes. It builds on A5's band — which already holds gold and an inventory — by giving items economic value, a way to acquire them, and a way to convert them back to gold.

A6 delivers the economy **systems and data**; the **run** (Phase A8) wires shop and reward nodes into the node graph. A6 exposes the shop in the A5 management screen so the loop is testable now.

### In scope

- An item **`price`** field (authored, or derived from `bp_value` as a fallback).
- A **`ShopService`**: buy (deduct gold, add to band inventory) and sell (remove from inventory, add gold at `SELL_RATIO`), with shop pools defining stock.
- **Loot tables** (authored data) and a **`LootRoller`** that produces rewards (gold / equipment / consumables) scaled by a **depth** parameter, with an injectable RNG for determinism.
- **Reward application** that grants rolled loot to a band.
- Treating **consumables** as inventory items with a quantity, buyable/sellable like equipment.
- Economy **tunables** (`SELL_RATIO`, `LOOT_DEPTH_SCALE`) and validation of the new data.

### Out of scope

- **Run nodes** (Phase A8): the Shop/Boon/Hazard/Battle nodes that *invoke* shops and loot live in A8; A6 provides the services they call.
- **Crafting / equipment upgrading** (post-Alpha).
- **Deep in-battle consumable mechanics** — A6 makes consumables a tradeable inventory item; richer in-combat consumption builds on the existing `use_item` path and is not a focus here.
- **Meta-progression unlock economy** (A8/A10).
- **AI** (A7) and price balancing at scale (tuning pass is A10).

### Exit criteria

Phase A6 is complete when:

1. Items have a buy `price` (authored or `bp_value`-derived); sell value = `round(price × SELL_RATIO)`.
2. A shop interface lets a band **buy** (gold↓, inventory↑) and **sell** (inventory↓, gold↑), rejecting purchases it can't afford; changes persist via the A5 save.
3. A **loot table rolls** gold/equipment/consumables scaled by a depth parameter, deterministically under a seeded RNG, and the rewards are granted to a band.
4. Loot tables and shop pools **validate** (reference real items); item prices validate.
5. The systems are covered by headless tests (shop invariants, seeded loot determinism, validation); the shop UI by a manual checklist.

---

## 2. Design Decisions (Phase A6)

| Area | Decision | Rationale / implications |
|------|----------|--------------------------|
| **Price with fallback** | `ItemData.price` is authored; if absent, derive from `bp_value` via a simple function. | Every item is sellable/buyable without authoring a price for all of them up front; authored prices override. |
| **Services operate on a band** | `ShopService` and reward application mutate a `BattleBand` (gold + inventory) directly. | Bands are the persistence unit (A5); keeping transactions band-scoped means saves "just work." |
| **Injectable RNG** | `LootRoller` takes an RNG (seeded from the run in A8; fixed in tests). | Deterministic, reproducible loot for debugging and testing. |
| **Depth-scaled rewards** | Loot quality/quantity scale with a `depth` argument via `LOOT_DEPTH_SCALE`. | Rewards track the player's growing power across a run (A8 supplies depth). |
| **Consumables = inventory items w/ qty** | Consumables live in `inventory.consumables` as `{id, qty}`; buy/sell adjusts qty. | Reuses the A5 inventory shape; no new container. |
| **Authored tables** | `loot_tables.json` and `shop_pools.json` are authored content, validated like other data. | Designers tune drops/stock without code; the CSV pipeline (A2) can author them. |
| **Expose in management now** | The shop panel lives in the A5 management screen for A6; A8 reuses it at Shop nodes. | Makes the loop testable before the run exists; one shop UI, two entry points. |

---

## 3. Item Prices

`ItemData` gains:

```gdscript
@export var price: int = -1   # buy price; -1 = derive from bp_value
```

- **Buy price** = `price` if ≥ 0, else `derived_price(bp_value)` (a simple monotonic function, e.g., `bp_value × PRICE_PER_BP`).
- **Sell value** = `round(buy_price × SELL_RATIO)`.

Prices are authored in `items.json` (and round-trip via the A2 item CSV `price` column). Balancing the actual numbers is an A10 task; A6 needs them present and consistent.

---

## 4. Loot

### 4.1 Loot table schema

Authored `data/loot_tables.json` — named tables, each a weighted set of reward entries:

```json
{
  "standard_battle": {
    "gold": { "min": 10, "max": 30 },
    "drops": [
      { "weight": 3, "kind": "equipment", "pool": "tier1_weapons" },
      { "weight": 2, "kind": "consumable", "id": "potion", "qty": 1 },
      { "weight": 5, "kind": "nothing" }
    ],
    "rolls": 1
  }
}
```

- `gold` — a range, scaled by depth.
- `drops` — weighted entries; `kind` ∈ `equipment` (from a named pool) / `consumable` / `nothing`.
- `rolls` — how many drop picks (may scale with depth).

### 4.2 `LootRoller`

`LootRoller.roll(table_id, depth, rng) -> {gold, equipment: [ids], consumables: [{id, qty}]}`:

- Rolls `gold` in range, scaled by `LOOT_DEPTH_SCALE × depth`.
- Performs `rolls` weighted picks from `drops`; resolves `equipment` picks against the named pool (filtered by tier/depth).
- Uses the injected `rng` so a given seed + depth yields the same result.

### 4.3 Reward application

`grant_rewards(band, rolled)` adds gold and items/consumables to the band's inventory (stacking consumable qty). It is what A8's Battle/Boon nodes call after resolving.

---

## 5. Shops

### 5.1 Shop pools

Authored `data/shop_pools.json` — named pools listing item ids available for purchase (optionally weighted or depth-gated). A shop instance presents a pool's items at their buy price.

### 5.2 `ShopService`

Operates on a `BattleBand`:

- `buy(band, item_id)` — if `band.gold >= buy_price`, deduct gold and add the item to inventory (consumables increment qty); else reject.
- `sell(band, item_id)` — if the band holds the item, remove one and add `sell_value` gold; else reject.
- Pure-ish: mutates the band, returns success/failure + the transaction detail for the UI/log.

Invariants: gold never goes negative; selling an unheld item is rejected; buy/sell are inverse in gold terms only up to `SELL_RATIO` (selling recovers a fraction).

---

## 6. UI (Shop Panel)

A shop panel added to the A5 band-management screen (and reused by A8 Shop nodes):

| Element | Function |
|---------|----------|
| **Gold display** | Current band gold. |
| **Buy list** | Items from the active shop pool with buy prices; Buy button disabled when unaffordable. |
| **Sell list** | Band inventory (equipment + consumables) with sell values; Sell button. |
| **Transaction feedback** | Confirmation / rejection messages; gold and lists refresh after each transaction. |

A **reward summary** (used after battles/nodes in A8) lists granted gold/items; A6 provides the widget, A8 triggers it.

---

## 7. Data Model Summary

- **ItemData** — add `price` (default `-1` → derive).
- **New authored data** — `data/loot_tables.json`, `data/shop_pools.json`.
- **New services** — `LootRoller`, `ShopService`, `grant_rewards`.
- **BattleBand** — gold/inventory already exist (A5); A6 adds the transaction/grant operations over them.
- **Validator** — validate item `price` (int ≥ -1); loot tables and shop pools reference real items/pools.
- **GameData** — accessors for loot tables and shop pools.
- **A2 pipeline** — item CSV `price` column (forward-referenced in A2); loot/shop tables authorable as data (CSV optional).
- **Tunables** — `SELL_RATIO` (0.5), `LOOT_DEPTH_SCALE`, `PRICE_PER_BP` (alpha-specs §7.4).

---

## 8. Risks & Notes

- **Gold integrity.** Guard every transaction so gold cannot go negative and items can't be sold if not held; cover with tests.
- **Loot determinism.** Always roll through the injected RNG; never call global `randi()` directly, or runs won't be reproducible.
- **Price/sell exploits.** With `SELL_RATIO < 1`, buy→sell loses gold (intended). Watch for any item whose derived price + sell ratio enables a profit loop; the fraction prevents it as long as `SELL_RATIO < 1`.
- **Pool/table references.** Loot pools and shop pools must reference real item ids and real pools; validate at boot and on CSV import.
- **Consumable shape.** Keep consumables as `{id, qty}` and stack on grant/buy; don't fork a second representation.
- **Depth coupling.** A6 defines the `depth` parameter but A8 supplies real values; keep the scaling function in one place for A8/A10 tuning.
- **Scope creep.** No run nodes, no crafting, no deep in-battle consumption, no balance pass — systems and data only.

---

## 9. Phase A6 Deliverables Checklist

- [ ] `ItemData.price` with `bp_value` fallback; sell = `round(price × SELL_RATIO)` (§3).
- [ ] `loot_tables.json` schema + `LootRoller` (seeded RNG, depth scaling) producing gold/equipment/consumables (§4.1–4.2).
- [ ] `grant_rewards(band, rolled)` applying loot to a band (stacking consumables) (§4.3).
- [ ] `shop_pools.json` + `ShopService.buy/sell` over a band with gold/holding guards (§5).
- [ ] Shop panel in the management screen (buy/sell lists, gold, feedback); reward-summary widget (§6).
- [ ] Validation of item prices and loot/shop references; `GameData` accessors (§7).
- [ ] Tunables (`SELL_RATIO`, `LOOT_DEPTH_SCALE`, `PRICE_PER_BP`) in `constants.json`; A2 item `price` column round-trips (§7).
- [ ] Headless tests: shop invariants (no negative gold, reject unheld sell), seeded loot determinism, validation; manual shop UI checklist.
- [ ] Git tag `alpha-phaseA6-complete`.
