#!/usr/bin/env python3
"""Generate monster data for the RPG battle simulator."""

import json
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(os.path.dirname(SCRIPT_DIR), "data")

MONSTER_RACES = [
    {"id": "bat", "name": "Bat", "base_stats": {"spd": 7, "atk": 3, "rng": 1, "def": 2, "hp": 18, "jump": 3, "wp": 2, "mag": 1, "res": 1}, "flavor": "Darting winged vermin that attack in swarms, overwhelming foes with speed."},
    {"id": "imp", "name": "Imp", "base_stats": {"spd": 6, "atk": 3, "rng": 1, "def": 2, "hp": 20, "jump": 2, "wp": 5, "mag": 4, "res": 2}, "flavor": "Tiny fiendish tricksters with a penchant for fire and mischief."},
    {"id": "kobold", "name": "Kobold", "base_stats": {"spd": 6, "atk": 3, "rng": 1, "def": 3, "hp": 20, "jump": 2, "wp": 3, "mag": 2, "res": 2}, "flavor": "Cunning trap-setters who compensate for frailty with cleverness."},
    {"id": "slime", "name": "Slime", "base_stats": {"spd": 3, "atk": 2, "rng": 1, "def": 4, "hp": 22, "jump": 1, "wp": 1, "mag": 2, "res": 4}, "flavor": "Amorphous blobs of corrosive ooze that dissolve anything they engulf."},
    {"id": "insectoid", "name": "Insectoid", "base_stats": {"spd": 5, "atk": 4, "rng": 1, "def": 4, "hp": 20, "jump": 2, "wp": 1, "mag": 1, "res": 2}, "flavor": "Chitinous hive creatures that swarm with stingers and mandibles."},
    {"id": "goblin", "name": "Goblin", "base_stats": {"spd": 6, "atk": 4, "rng": 1, "def": 3, "hp": 25, "jump": 2, "wp": 3, "mag": 2, "res": 2}, "flavor": "Small but numerous, goblins rely on dirty tricks and overwhelming numbers."},
    {"id": "wolf", "name": "Wolf", "base_stats": {"spd": 7, "atk": 5, "rng": 1, "def": 3, "hp": 26, "jump": 2, "wp": 1, "mag": 1, "res": 1}, "flavor": "Pack hunters whose coordinated attacks bring down prey much larger than themselves."},
    {"id": "spider", "name": "Spider", "base_stats": {"spd": 5, "atk": 4, "rng": 1, "def": 3, "hp": 25, "jump": 2, "wp": 2, "mag": 2, "res": 2}, "flavor": "Venomous arachnids that snare prey in webs before delivering a fatal bite."},
    {"id": "zombie", "name": "Zombie", "base_stats": {"spd": 3, "atk": 5, "rng": 1, "def": 4, "hp": 30, "jump": 1, "wp": 1, "mag": 1, "res": 1}, "flavor": "Shambling corpses driven by dark magic, relentless but slow."},
    {"id": "orc", "name": "Orc", "base_stats": {"spd": 5, "atk": 6, "rng": 1, "def": 4, "hp": 32, "jump": 2, "wp": 2, "mag": 1, "res": 2}, "flavor": "Brutish warriors who prize strength above all, charging headlong into battle."},
    {"id": "gnoll", "name": "Gnoll", "base_stats": {"spd": 5, "atk": 5, "rng": 1, "def": 4, "hp": 30, "jump": 2, "wp": 3, "mag": 2, "res": 2}, "flavor": "Hyena-folk raiders who revel in savagery and dark rituals."},
    {"id": "hobgoblin", "name": "Hobgoblin", "base_stats": {"spd": 5, "atk": 5, "rng": 1, "def": 5, "hp": 32, "jump": 2, "wp": 3, "mag": 2, "res": 3}, "flavor": "Disciplined goblinoid soldiers who fight in organized formations."},
    {"id": "lizardfolk", "name": "Lizardfolk", "base_stats": {"spd": 4, "atk": 5, "rng": 1, "def": 5, "hp": 33, "jump": 2, "wp": 3, "mag": 2, "res": 3}, "flavor": "Cold-blooded warriors at home in swamps, armored in thick scales."},
    {"id": "skeleton", "name": "Skeleton", "base_stats": {"spd": 4, "atk": 5, "rng": 1, "def": 4, "hp": 28, "jump": 2, "wp": 2, "mag": 3, "res": 3}, "flavor": "Animated bones held together by necromantic energy, tireless and fearless."},
    {"id": "ogre", "name": "Ogre", "base_stats": {"spd": 3, "atk": 7, "rng": 1, "def": 5, "hp": 40, "jump": 1, "wp": 1, "mag": 1, "res": 2}, "flavor": "Massive brutes who crush foes with raw power and hurled boulders."},
    {"id": "minotaur", "name": "Minotaur", "base_stats": {"spd": 4, "atk": 7, "rng": 1, "def": 5, "hp": 38, "jump": 2, "wp": 2, "mag": 1, "res": 2}, "flavor": "Bull-headed titans who gore enemies with devastating charges."},
    {"id": "troll", "name": "Troll", "base_stats": {"spd": 4, "atk": 6, "rng": 1, "def": 4, "hp": 42, "jump": 2, "wp": 3, "mag": 2, "res": 2}, "flavor": "Regenerating monstrosities that shrug off wounds and keep fighting."},
    {"id": "golem", "name": "Golem", "base_stats": {"spd": 3, "atk": 6, "rng": 1, "def": 7, "hp": 45, "jump": 1, "wp": 1, "mag": 1, "res": 5}, "flavor": "Animated constructs of stone and metal, nearly impervious to harm."},
    {"id": "treant", "name": "Treant", "base_stats": {"spd": 3, "atk": 5, "rng": 1, "def": 6, "hp": 42, "jump": 1, "wp": 4, "mag": 3, "res": 4}, "flavor": "Ancient tree guardians who protect the forest with root and branch."},
    {"id": "gargoyle", "name": "Gargoyle", "base_stats": {"spd": 4, "atk": 5, "rng": 1, "def": 7, "hp": 38, "jump": 2, "wp": 2, "mag": 2, "res": 5}, "flavor": "Stone sentinels that blend with architecture before swooping to attack."},
    {"id": "dire_beast", "name": "Dire Beast", "base_stats": {"spd": 5, "atk": 7, "rng": 1, "def": 4, "hp": 38, "jump": 2, "wp": 1, "mag": 1, "res": 1}, "flavor": "Oversized predators twisted by dark energies into unstoppable killing machines."},
    {"id": "elemental", "name": "Elemental", "base_stats": {"spd": 4, "atk": 3, "rng": 1, "def": 5, "hp": 30, "jump": 2, "wp": 6, "mag": 6, "res": 5}, "flavor": "Manifestations of primal forces -- fire, ice, lightning, and stone."},
    {"id": "wraith", "name": "Wraith", "base_stats": {"spd": 5, "atk": 3, "rng": 1, "def": 3, "hp": 25, "jump": 2, "wp": 6, "mag": 6, "res": 5}, "flavor": "Spectral undead that drain the life from the living with a chilling touch."},
    {"id": "naga", "name": "Naga", "base_stats": {"spd": 5, "atk": 4, "rng": 1, "def": 4, "hp": 30, "jump": 2, "wp": 5, "mag": 5, "res": 4}, "flavor": "Serpentine sorcerers ruling ancient ruins with arcane mastery."},
    {"id": "merfolk", "name": "Merfolk", "base_stats": {"spd": 5, "atk": 4, "rng": 1, "def": 4, "hp": 28, "jump": 2, "wp": 5, "mag": 5, "res": 4}, "flavor": "Aquatic warriors and spellcasters who command the tides."},
    {"id": "harpy", "name": "Harpy", "base_stats": {"spd": 6, "atk": 4, "rng": 1, "def": 3, "hp": 26, "jump": 3, "wp": 4, "mag": 4, "res": 3}, "flavor": "Winged predators whose shrieks disorient and terrify their prey."},
    {"id": "demon", "name": "Demon", "base_stats": {"spd": 5, "atk": 6, "rng": 1, "def": 5, "hp": 38, "jump": 2, "wp": 5, "mag": 5, "res": 4}, "flavor": "Infernal beings of immense power, commanding fire and dark magic."},
    {"id": "drake", "name": "Drake", "base_stats": {"spd": 5, "atk": 6, "rng": 1, "def": 6, "hp": 40, "jump": 2, "wp": 4, "mag": 4, "res": 5}, "flavor": "Lesser dragons with devastating breath weapons and armored scales."},
]

SUFFIX_ROLE_MAP = {
    "soldier": ("physical_attack", "melee"), "warrior": ("physical_attack", "melee"),
    "raider": ("physical_attack", "melee"), "bruiser": ("physical_attack", "melee"),
    "smasher": ("physical_attack", "melee"), "berserker": ("physical_attack", "melee"),
    "charger": ("physical_attack", "melee"), "maw": ("physical_attack", "melee"),
    "feral": ("physical_attack", "melee"), "render": ("physical_attack", "melee"),
    "ravager": ("physical_attack", "melee"), "pouncer": ("physical_attack", "melee"),
    "talon": ("physical_attack", "melee"), "diver": ("physical_attack", "melee"),
    "stalker": ("physical_attack", "melee"), "drone": ("physical_attack", "melee"),
    "stinger": ("physical_attack", "melee"), "reaver": ("physical_attack", "melee"),
    "brute": ("physical_attack", "melee"), "crusher": ("physical_attack", "melee"),
    "maneater": ("physical_attack", "melee"), "reaper": ("physical_attack", "melee"),
    "savage": ("physical_attack", "melee"), "packleader": ("physical_attack", "melee"),
    "venomfang": ("physical_attack", "melee"), "ambusher": ("physical_attack", "melee"),
    "striker": ("physical_attack", "melee"), "tunneler": ("physical_attack", "melee"),
    "swarmer": ("physical_attack", "melee"), "shambler": ("physical_attack", "melee"),
    "devourer": ("physical_attack", "melee"), "bloated": ("physical_attack", "melee"),
    "acidic": ("physical_attack", "melee"), "corrosive": ("physical_attack", "melee"),
    "splitter": ("physical_attack", "melee"), "flameling": ("physical_attack", "melee"),
    "painbringer": ("physical_attack", "melee"), "legionnaire": ("physical_attack", "melee"),
    "captain": ("physical_attack", "melee"), "drillmaster": ("physical_attack", "melee"),
    "dreadlord": ("physical_attack", "melee"), "elder": ("physical_attack", "melee"),
    "soulrender": ("physical_attack", "melee"), "specter": ("physical_attack", "melee"),
    "swarm": ("physical_attack", "melee"), "spearfisher": ("physical_attack", "melee"),
    "labyrinth_stalker": ("physical_attack", "melee"),
    "archer": ("physical_attack", "ranged"), "crossbowman": ("physical_attack", "ranged"),
    "skirmisher": ("physical_attack", "ranged"), "hunter": ("physical_attack", "ranged"),
    "skyhunter": ("physical_attack", "ranged"), "boulder_hurler": ("physical_attack", "ranged"),
    "skywatcher": ("physical_attack", "ranged"), "boulderhurl": ("physical_attack", "ranged"),
    "knight": ("physical_defense", "tank"), "guardian": ("physical_defense", "tank"),
    "sentinel": ("physical_defense", "tank"), "bulwark": ("physical_defense", "tank"),
    "stoneguard": ("physical_defense", "tank"), "carapace": ("physical_defense", "tank"),
    "warden": ("physical_defense", "tank"), "wardstone": ("physical_defense", "tank"),
    "scalelord": ("physical_defense", "tank"), "colossus": ("physical_defense", "tank"),
    "runeguard": ("physical_defense", "tank"), "stoneheart": ("physical_defense", "tank"),
    "coreguard": ("physical_defense", "tank"), "tidewarden": ("physical_defense", "tank"),
    "shaman": ("magical_attack", "magical"), "bonecaster": ("magical_attack", "magical"),
    "firebrand": ("magical_attack", "magical"), "hellfire": ("magical_attack", "magical"),
    "pyre": ("magical_attack", "magical"), "frostform": ("magical_attack", "magical"),
    "tempest": ("magical_attack", "magical"), "firebreather": ("magical_attack", "magical"),
    "echocaster": ("magical_attack", "magical"), "spiritcaller": ("magical_attack", "magical"),
    "warcaster": ("magical_attack", "magical"), "hydromancer": ("magical_attack", "magical"),
    "spellweaver": ("magical_attack", "magical"), "thorncaster": ("magical_attack", "magical"),
    "wavecaller": ("magical_attack", "magical"), "swampcaller": ("magical_attack", "magical"),
    "windcaller": ("magical_attack", "magical"), "demoncaller": ("magical_attack", "magical"),
    "tormentor": ("magical_attack", "magical"),
    "corruptor": ("magical_defense", "support"), "siren": ("support", "support"),
    "charmer": ("support", "support"), "grovekeeper": ("support", "support"),
    "regenerator": ("support", "support"), "hauntcaller": ("magical_defense", "support"),
    "plaguebearer": ("magical_defense", "support"), "bog_shaman": ("magical_attack", "magical"),
    "trapper": ("control", "control"), "trapsmith": ("control", "control"),
    "screecher": ("control", "control"), "spinner": ("control", "control"),
    "weaver": ("control", "control"), "nightstalker": ("control", "control"),
    "veil": ("control", "control"), "engulfer": ("control", "control"),
    "howler": ("control", "control"),
}

GROWTH_BY_ROLE = {
    "melee":   {"hp": 1.5, "atk": 0.5, "def": 0.3, "spd": 0.2},
    "ranged":  {"hp": 1.0, "atk": 0.4, "spd": 0.3, "rng": 0.1},
    "tank":    {"hp": 2.0, "def": 0.5, "atk": 0.3, "res": 0.2},
    "magical": {"hp": 1.0, "mag": 0.5, "wp": 0.4, "res": 0.3},
    "support": {"hp": 1.2, "mag": 0.3, "wp": 0.4, "res": 0.3, "def": 0.2},
    "control": {"hp": 1.0, "spd": 0.4, "atk": 0.3, "mag": 0.2},
}

STATS_BY_ROLE = {
    "melee":   {"atk": 2, "hp": 5},
    "ranged":  {"atk": 1, "spd": 1, "hp": 3},
    "tank":    {"def": 3, "hp": 10, "res": 1},
    "magical": {"mag": 3, "wp": 3, "res": 1},
    "support": {"mag": 1, "wp": 3, "def": 1, "hp": 5},
    "control": {"spd": 2, "atk": 1, "mag": 1},
}

ABILITY_POOLS = {
    "melee": ["basic_strike", "power_strike", "reckless_swing", "cleave", "charge",
              "rage", "war_cry", "shield_bash", "fortify", "backstab",
              "poison_strike", "iron_will", "last_stand", "expose_weakness", "cripple"],
    "ranged": ["basic_strike", "aimed_shot", "volley", "snipe", "pinning_shot",
               "barrage", "smoke_bomb", "camouflage", "poison_strike", "cripple"],
    "tank": ["basic_strike", "fortify", "shield_bash", "iron_will", "taunt",
             "war_cry", "last_stand", "protect", "charge", "power_strike",
             "shell", "barrier"],
    "magical": ["fire_1", "fire_2", "ice_1", "ice_2", "thunder_1", "thunder_2",
                "arcane_blast", "dark_pulse", "drain", "silence", "slow",
                "curse", "mana_shield", "chain_lightning"],
    "support": ["cure_1", "cure_2", "regen", "protect", "shell", "haste",
                "silence", "slow", "curse", "dispel", "bless", "inspire",
                "poison_strike", "dark_pulse", "drain"],
    "control": ["lullaby", "blind_strike", "cripple", "poison_strike", "slow",
                "smoke_bomb", "backstab", "expose_weakness", "silence", "discord",
                "steal", "evasion", "shadow_step", "basic_strike", "curse"],
}


def _pick_abilities(class_id, role, count=5):
    """Pick count abilities from the role pool, seeded by class_id hash for variety."""
    pool = ABILITY_POOLS[role]
    h = hash(class_id) & 0xFFFFFFFF
    start = h % len(pool)
    picked = []
    idx = start
    while len(picked) < count and len(picked) < len(pool):
        ability = pool[idx % len(pool)]
        if ability not in picked:
            picked.append(ability)
        idx += 1
    return picked


def _make_abbr(class_id):
    """First 3 characters of the class_id, uppercased."""
    return class_id[:3].upper()


def _display_name(class_id):
    """Convert snake_case id to Title Case display name."""
    return " ".join(word.capitalize() for word in class_id.split("_"))


def load_json(filename):
    path = os.path.join(DATA_DIR, filename)
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_json(filename, data, indent=2, compact=False):
    path = os.path.join(DATA_DIR, filename)
    with open(path, "w", encoding="utf-8") as f:
        if compact:
            f.write("[\n")
            for i, entry in enumerate(data):
                line = json.dumps(entry, separators=(", ", ": "), ensure_ascii=False)
                if i < len(data) - 1:
                    f.write("  %s,\n" % line)
                else:
                    f.write("  %s\n" % line)
            f.write("]\n")
        else:
            json.dump(data, f, indent=indent, ensure_ascii=False)
            f.write("\n")


def main():
    encounters = load_json("encounters.json")
    monster_ids = set()
    for enc in encounters:
        for enemy in enc["enemies"]:
            monster_ids.add(enemy["character"])
    print("Found %d unique monster character IDs in encounters.json" % len(monster_ids))

    existing_races = load_json("races.json")
    existing_classes = load_json("classes.json")
    existing_characters = load_json("characters.json")
    abilities_data = load_json("abilities.json")

    existing_race_ids = {r["id"] for r in existing_races}
    existing_class_ids = {c["id"] for c in existing_classes}
    existing_char_ids = {c["id"] for c in existing_characters}
    valid_ability_ids = {a["id"] for a in abilities_data}

    print("Existing: %d races, %d classes, %d characters, %d abilities" % (
        len(existing_races), len(existing_classes),
        len(existing_characters), len(valid_ability_ids)))

    race_ids = [r["id"] for r in MONSTER_RACES]
    race_lookup = {r["id"]: r for r in MONSTER_RACES}

    def find_race(char_id):
        best_race = None
        best_len = 0
        for rid in race_ids:
            prefix = rid + "_"
            if char_id.startswith(prefix) and len(prefix) > best_len:
                best_race = rid
                best_len = len(prefix)
        if best_race is None:
            raise ValueError("No race match for character: %s" % char_id)
        suffix = char_id[best_len:]
        return best_race, suffix

    race_chars = {r: [] for r in race_ids}
    for mid in sorted(monster_ids):
        race_id, suffix = find_race(mid)
        race_chars[race_id].append((mid, suffix))

    new_classes = []
    ability_errors = []

    for race_id in race_ids:
        for char_id, suffix in race_chars[race_id]:
            if suffix not in SUFFIX_ROLE_MAP:
                print("  WARNING: Unknown suffix for %s, defaulting to melee" % char_id)
                archetype = "physical_attack"
                role = "melee"
            else:
                archetype, role = SUFFIX_ROLE_MAP[suffix]

            abilities = _pick_abilities(char_id, role, 5)

            for ab in abilities:
                if ab not in valid_ability_ids:
                    ability_errors.append("  %s: ability %s not in abilities.json" % (char_id, ab))

            cls = {
                "id": char_id,
                "name": _display_name(char_id),
                "abbr": _make_abbr(char_id),
                "archetype": archetype,
                "branch": "",
                "tier": 0,
                "stats": dict(STATS_BY_ROLE[role]),
                "growth": dict(GROWTH_BY_ROLE[role]),
                "derived_bonuses": {},
                "equipment_access": [],
                "granted_abilities": abilities,
                "jp_costs": {},
                "level_max": 10,
                "required_classes": [],
                "prerequisites": {},
            }
            new_classes.append(cls)

    if ability_errors:
        print("ABILITY VALIDATION ERRORS:")
        for err in ability_errors:
            print(err)
        sys.exit(1)

    print("Generated %d monster classes" % len(new_classes))

    new_characters = []
    for race_id in race_ids:
        race_data = race_lookup[race_id]
        for char_id, suffix in race_chars[race_id]:
            char = {
                "id": char_id,
                "name": _display_name(char_id),
                "race": race_id,
                "classes": [char_id],
                "level": 1,
                "bp": 3,
                "recommended_path": "",
                "stats": dict(race_data["base_stats"]),
                "equipment": [],
                "abilities": [],
            }
            new_characters.append(char)

    print("Generated %d monster character templates" % len(new_characters))

    new_races = []
    for r in MONSTER_RACES:
        race_entry = {
            "id": r["id"],
            "name": r["name"],
            "stats": {},
            "base_stats": dict(r["base_stats"]),
            "flavor": r["flavor"],
        }
        new_races.append(race_entry)

    print("Generated %d monster races" % len(new_races))

    # Check for ID collisions
    for r in new_races:
        if r["id"] in existing_race_ids:
            print("  WARNING: Race %s already exists, skipping" % r["id"])
    for c in new_classes:
        if c["id"] in existing_class_ids:
            print("  WARNING: Class %s already exists, skipping" % c["id"])
    for c in new_characters:
        if c["id"] in existing_char_ids:
            print("  WARNING: Character %s already exists, skipping" % c["id"])

    new_races = [r for r in new_races if r["id"] not in existing_race_ids]
    new_classes = [c for c in new_classes if c["id"] not in existing_class_ids]
    new_characters = [c for c in new_characters if c["id"] not in existing_char_ids]

    merged_races = existing_races + new_races
    merged_classes = existing_classes + new_classes
    merged_characters = existing_characters + new_characters

    save_json("races.json", merged_races, indent=2)
    print("Wrote data/races.json: %d total (%d existing + %d new)" % (
        len(merged_races), len(existing_races), len(new_races)))

    save_json("classes.json", merged_classes, indent=2)
    print("Wrote data/classes.json: %d total (%d existing + %d new)" % (
        len(merged_classes), len(existing_classes), len(new_classes)))

    save_json("characters.json", merged_characters, compact=True)
    print("Wrote data/characters.json: %d total (%d existing + %d new)" % (
        len(merged_characters), len(existing_characters), len(new_characters)))

    print("")
    print("=== VALIDATION SUMMARY ===")

    all_char_ids = {c["id"] for c in merged_characters}
    missing = monster_ids - all_char_ids
    if missing:
        print("ERROR: %d encounter characters still missing: %s" % (len(missing), sorted(missing)))
        sys.exit(1)
    else:
        print("All %d encounter character references resolved." % len(monster_ids))

    all_race_ids = {r["id"] for r in merged_races}
    for c in merged_characters:
        if c["race"] not in all_race_ids:
            print("ERROR: Character %s references unknown race %s" % (c["id"], c["race"]))
            sys.exit(1)

    all_class_ids = {cl["id"] for cl in merged_classes}
    for c in merged_characters:
        for cls_ref in c["classes"]:
            if cls_ref not in all_class_ids:
                print("ERROR: Character %s references unknown class %s" % (c["id"], cls_ref))
                sys.exit(1)

    for cl in merged_classes:
        for ab in cl.get("granted_abilities", []):
            if ab not in valid_ability_ids:
                print("ERROR: Class %s references unknown ability %s" % (cl["id"], ab))
                sys.exit(1)

    print("All race, class, and ability references valid.")
    print("Done!")


if __name__ == "__main__":
    main()
