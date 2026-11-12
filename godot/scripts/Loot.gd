class_name Loot
extends RefCounted
## Procedural gear: 3 slots x 5 rarities x random stat affixes, with silly names.

const RARITIES := [
	{"name": "Common", "color": Color(0.82, 0.82, 0.82), "mult": 1.0, "affixes": 1, "weight": 60.0},
	{"name": "Uncommon", "color": Color(0.4, 1.0, 0.4), "mult": 1.4, "affixes": 2, "weight": 26.0},
	{"name": "Rare", "color": Color(0.3, 0.6, 1.0), "mult": 1.9, "affixes": 2, "weight": 10.0},
	{"name": "Epic", "color": Color(0.8, 0.4, 1.0), "mult": 2.6, "affixes": 3, "weight": 3.5},
	{"name": "Legendary", "color": Color(1.0, 0.7, 0.1), "mult": 3.6, "affixes": 4, "weight": 0.5},
]

# base = value at Common. unit "%" shows percent, "hp/s" shows raw.
const STAT_INFO := {
	"max_hp": {"suffix": "of Thickness", "base": 0.10, "label": "Max HP", "unit": "%"},
	"move_speed": {"suffix": "of Zoomies", "base": 0.06, "label": "Move Speed", "unit": "%"},
	"jump": {"suffix": "of Boing", "base": 0.06, "label": "Jump Height", "unit": "%"},
	"gravity": {"suffix": "of Floating", "base": -0.05, "label": "Gravity", "unit": "%"},
	"kick_damage": {"suffix": "of Stomping", "base": 0.15, "label": "Kick Damage", "unit": "%"},
	"kick_force": {"suffix": "of Yeeting", "base": 0.15, "label": "Kick Force", "unit": "%"},
	"kick_width": {"suffix": "of Sweeping", "base": 0.12, "label": "Kick Area", "unit": "%"},
	"slide_speed": {"suffix": "of Butter", "base": 0.08, "label": "Slide Speed", "unit": "%"},
	"slide_damage": {"suffix": "of Grease", "base": 0.15, "label": "Slide Damage", "unit": "%"},
	"thrust": {"suffix": "of Blast-Off", "base": 0.12, "label": "Rocket Thrust", "unit": "%"},
	"blower_power": {"suffix": "of Gale", "base": 0.12, "label": "Blower Power", "unit": "%"},
	"plunger_power": {"suffix": "of Suction", "base": 0.12, "label": "Plunger Power", "unit": "%"},
	"damage": {"suffix": "of Hilarity", "base": 0.08, "label": "All Damage", "unit": "%"},
	"crit": {"suffix": "of Luck", "base": 0.04, "label": "Crit Chance", "unit": "%"},
	"xp_gain": {"suffix": "of Learning", "base": 0.08, "label": "XP Gain", "unit": "%"},
	"coin_gain": {"suffix": "of Greed", "base": 0.10, "label": "Coins", "unit": "%"},
	"drop_rate": {"suffix": "of Fortune", "base": 0.08, "label": "Drop Chance", "unit": "%"},
	"regen": {"suffix": "of Soup", "base": 0.5, "label": "Regen", "unit": "hp/s"},
	"damage_taken": {"suffix": "of Padding", "base": -0.06, "label": "Damage Taken", "unit": "%"},
}

const SLOT_STATS := {
	"Hat": ["max_hp", "xp_gain", "crit", "drop_rate", "damage_taken", "coin_gain", "damage", "regen"],
	"Boots": ["move_speed", "jump", "slide_damage", "gravity", "kick_force", "slide_speed", "thrust"],
	"Gloves": ["kick_damage", "blower_power", "plunger_power", "damage", "crit", "kick_force", "kick_width"],
}

const BASES := {
	"Hat": ["Traffic Cone", "Propeller Beanie", "Cowboy Hat", "Chef's Toque", "Bucket", "Paper Crown", "Sombrero", "Colander"],
	"Boots": ["Clown Shoes", "Flip-Flops", "Moon Boots", "Rocket Skates", "Gumboots", "Roller Skates", "Fuzzy Slippers"],
	"Gloves": ["Oven Mitts", "Foam Finger", "Boxing Gloves", "Rubber Gloves", "Jazz Hands", "Lobster Claws"],
}

const PREFIXES := [
	["Sad", "Plain", "Damp", "Tired"],
	["Decent", "Shiny", "Perky"],
	["Fancy", "Dapper", "Zesty"],
	["Radical", "Gnarly", "Absurd"],
	["LEGENDARY", "Mythic", "Cosmic"],
]


static func rarity_color(rarity: int) -> Color:
	return RARITIES[clampi(rarity, 0, RARITIES.size() - 1)]["color"]


static func rarity_name(rarity: int) -> String:
	return RARITIES[clampi(rarity, 0, RARITIES.size() - 1)]["name"]


static func generate(min_rarity: int = 0, luck: float = 1.0) -> Dictionary:
	# Weighted rarity roll (luck boosts Rare+).
	var total := 0.0
	var weights: Array[float] = []
	for i in RARITIES.size():
		var w: float = RARITIES[i]["weight"]
		if i >= 2:
			w *= luck
		if i < min_rarity:
			w = 0.0
		weights.append(w)
		total += w
	var roll := randf() * total
	var rarity := min_rarity
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			rarity = i
			break

	var slots: Array = SLOT_STATS.keys()
	var slot: String = slots.pick_random()
	var pool: Array = (SLOT_STATS[slot] as Array).duplicate()
	pool.shuffle()
	var r: Dictionary = RARITIES[rarity]
	var affixes: Array = []
	for i in mini(int(r["affixes"]), pool.size()):
		var stat: String = pool[i]
		var base: float = STAT_INFO[stat]["base"]
		affixes.append({"stat": stat, "value": snappedf(base * float(r["mult"]) * randf_range(0.8, 1.2), 0.001)})

	var base_name: String = (BASES[slot] as Array).pick_random()
	var prefix: String = (PREFIXES[rarity] as Array).pick_random()
	var suffix: String = STAT_INFO[affixes[0]["stat"]]["suffix"]
	return {
		"slot": slot, "rarity": rarity, "affixes": affixes,
		"name": "%s %s %s" % [prefix, base_name, suffix], "base": base_name,
	}


static func rating(item: Dictionary) -> float:
	var total := 0.0
	for a: Dictionary in item.get("affixes", []):
		var base := absf(float(STAT_INFO[a["stat"]]["base"]))
		total += absf(float(a["value"])) / base
	return total


static func sell_value(item: Dictionary) -> int:
	return int(4.0 * rating(item) * (1.0 + int(item["rarity"])))


static func describe(item: Dictionary) -> String:
	var lines: PackedStringArray = []
	for a: Dictionary in item.get("affixes", []):
		var info: Dictionary = STAT_INFO[a["stat"]]
		var v := float(a["value"])
		if info["unit"] == "hp/s":
			lines.append("%+.1f HP/s Regen" % v)
		else:
			lines.append("%+d%% %s" % [int(round(v * 100.0)), info["label"]])
	return "\n".join(lines)
