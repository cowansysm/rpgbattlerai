# Phase A6 — Implementation Plan

**Source spec:** `alpha-phaseA6-spec.md`
**Master spec:** `alpha-specs.md` (§7)
**Builds on (Alpha):** `alpha-phaseA5-implementation-plan.md` (`BattleBand` gold/inventory, `SaveManager`), `alpha-phaseA2` (item CSV)
**Builds on (MVP):** `phase1` (`ItemData`, `DataFactory`, `Validator`, `GameData`)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-06-17

---

## How to use this plan

Six **work groups** (A–F). Across groups: **A** (item price) unblocks shops; **B** (loot) and **C** (shop) both need A and the A5 band; **D** (UI) needs B+C; **E** (tunables/accessors/A2 sync) supports all; **F** (tests) trails B–C.

Each task lists a **done state**. Code stubs are Godot 4 / GDScript — reusing `BattleBand` (A5) and `ItemData`/`GameData` (MVP).

> **Carry-over:** A6 mutates the A5 `BattleBand` (gold + `inventory`), so transactions persist through `SaveManager`. Loot uses an injected RNG (A8 seeds it from the run). Item `price` round-trips via the A2 item CSV column. A6 exposes the shop in the A5 management screen; A8 reuses it at Shop nodes.

---

## Group A — Item Price & Data

*Unblocks shops. Extends `ItemData` + factory + validator.*

### A1. `ItemData.price` + derivation
- Add `price` (default `-1`); a `buy_price(item)` helper deriving from `bp_value` when unset; `sell_value(item)`.
- **Done:** every item yields a buy and sell value (tested in F).

```gdscript
# src/core/data/item_data.gd  (addition)
@export var price: int = -1     # -1 → derive from bp_value

# src/core/economy/pricing.gd
class_name Pricing
extends RefCounted

static func buy_price(item: ItemData) -> int:
    if item.price >= 0: return item.price
    return item.bp_value * int(Constants.get_value("PRICE_PER_BP", 5))

static func sell_value(item: ItemData) -> int:
    return int(round(buy_price(item) * float(Constants.get_value("SELL_RATIO", 0.5))))
```

### A2. Factory + validator
- Parse `price` in `DataFactory.make_item`; `Validator.validate_item` checks `price` is an int ≥ -1.
- **Done:** authored prices load; a bad price errors.

---

## Group B — Loot System

*Depends on A + A5 band.*

### B1. Loot table data + accessor
- `data/loot_tables.json` (gold range, weighted drops, rolls); `GameData.get_loot_table(id)`.
- **Done:** tables load and validate (references resolve).

### B2. `LootRoller`
- `roll(table_id, depth, rng)` → `{gold, equipment[], consumables[]}`, depth-scaled, weighted picks via injected RNG.
- **Done:** a fixed seed + depth yields a fixed result (F2).

```gdscript
# src/core/economy/loot_roller.gd
class_name LootRoller
extends RefCounted

static func roll(table: Dictionary, depth: int, rng: RandomNumberGenerator) -> Dictionary:
    var scale: float = 1.0 + float(Constants.get_value("LOOT_DEPTH_SCALE", 0.1)) * depth
    var g: Dictionary = table.get("gold", {"min": 0, "max": 0})
    var gold: int = int(round(rng.randi_range(int(g["min"]), int(g["max"])) * scale))
    var equipment: Array = []
    var consumables: Array = []
    for _i in range(int(table.get("rolls", 1))):
        var pick: Dictionary = _weighted_pick(table.get("drops", []), rng)
        match pick.get("kind", "nothing"):
            "equipment":  equipment.append(_pick_from_pool(str(pick["pool"]), depth, rng))
            "consumable": consumables.append({"id": pick["id"], "qty": int(pick.get("qty", 1))})
            _: pass
    return {"gold": gold, "equipment": equipment, "consumables": consumables}
```

### B3. Reward application
- `grant_rewards(band, rolled)` adds gold, equipment ids, and stacks consumable qty into the band inventory.
- **Done:** a band's gold/inventory reflect the rolled rewards.

---

## Group C — Shop System

*Depends on A + A5 band.*

### C1. Shop pools + accessor
- `data/shop_pools.json` (named lists of item ids, optional depth gating); `GameData.get_shop_pool(id)`.
- **Done:** pools load and validate.

### C2. `ShopService` buy/sell
- `buy(band, item_id)` / `sell(band, item_id)` with gold and holding guards.
- **Done:** affordable buys/valid sells succeed; others rejected; gold never negative (F1).

```gdscript
# src/core/economy/shop_service.gd
class_name ShopService
extends RefCounted

static func buy(band: BattleBand, item_id: String, item_provider: Callable) -> bool:
    var price: int = Pricing.buy_price(item_provider.call(item_id))
    if band.gold < price: return false
    band.gold -= price
    band.add_equipment(item_id)        # or increment consumable qty
    return true

static func sell(band: BattleBand, item_id: String, item_provider: Callable) -> bool:
    if not band.has_item(item_id): return false
    band.remove_equipment(item_id)
    band.gold += Pricing.sell_value(item_provider.call(item_id))
    return true
```

---

## Group D — UI (Shop Panel & Reward Summary)

*Depends on B+C. Extends the A5 management screen.*

### D1. Shop panel
- Gold display, buy list (from a pool, prices, disabled when unaffordable), sell list (band inventory, sell values), feedback.
- **Done:** buy/sell from the UI update gold/inventory and persist on save.

### D2. Reward summary widget
- A panel listing granted gold/items, shown after `grant_rewards`.
- **Done:** widget renders a rolled reward; A8 will trigger it post-node.

---

## Group E — Tunables, Accessors & A2 Sync

### E1. Constants
- Add `SELL_RATIO` (0.5), `LOOT_DEPTH_SCALE`, `PRICE_PER_BP` to `constants.json`.
- **Done:** readable via `Constants.get_value`.

### E2. A2 item price column
- Ensure the A2 item CSV schema includes `price`; round-trip verified.
- **Done:** `price` exports/imports without loss.

---

## Group F — Tests & Verification

### F1. Shop invariants (GUT)
- Buy with insufficient gold rejected; gold never negative; sell unheld item rejected; buy then sell nets a `SELL_RATIO` loss.
- **Done:** green.

```gdscript
# tests/core/economy/test_shop.gd
extends GutTest

func test_cannot_overspend() -> void:
    var band := _band(gold = 5)
    assert_false(ShopService.buy(band, "sword", _item_provider))   # sword costs more
    assert_eq(band.gold, 5)

func test_sell_adds_fractional_gold() -> void:
    var band := _band(gold = 0); band.add_equipment("sword")
    assert_true(ShopService.sell(band, "sword", _item_provider))
    assert_eq(band.gold, Pricing.sell_value(_item("sword")))
```

### F2. Loot determinism (GUT)
- Same seed + depth → identical roll; higher depth → scaled gold.
- **Done:** green.

### F3. Validation
- Loot/shop tables referencing a missing item id error; valid tables pass; bad item price errors.
- **Done:** green.

### F4. Manual shop UI checklist
- [ ] Buy an affordable item — gold↓, inventory↑; unaffordable buttons disabled.
- [ ] Sell an item — gold↑ by sell value, inventory↓.
- [ ] Changes persist after save/reload (A5).
- [ ] Reward summary shows a granted loot roll.
- **Done:** checklist passes.

---

## Dependency Map

```
A (item price) ──┬──> B (loot) ──┐
                 ├──> C (shop) ──┤
                 │               ├──> D (UI) ──> F (tests)
E (tunables/accessors/A2) ───────┘
```

**Suggested first pass:** A1–A2 → E1 → B1–B3 and C1–C2 (parallel) → F1–F3 → D1–D2 → E2/F4.

---

## Phase A6 Definition of Done

- [ ] `ItemData.price` + `Pricing` (buy with `bp_value` fallback, sell at `SELL_RATIO`); factory/validator updated (A).
- [ ] `loot_tables.json` + `LootRoller` (seeded, depth-scaled) + `grant_rewards` applying to a band (B).
- [ ] `shop_pools.json` + `ShopService.buy/sell` with gold/holding guards (C).
- [ ] Shop panel + reward-summary widget in the management screen; transactions persist via A5 save (D).
- [ ] Tunables in `constants.json`; A2 item `price` column round-trips; loot/shop validation (E, F3).
- [ ] Shop-invariant, loot-determinism, and validation tests green; manual shop UI checklist passed (F).
- [ ] Git tag `alpha-phaseA6-complete`.
