extends Node
## Autoload "Prog": XP / levels, the skill tree, equipped gear, timed power-ups,
## kill-combo "style", coins, and saving. Everything that scales gameplay asks
## this node: Prog.mult("kick_damage"), Prog.flag("shockboots"), ...

signal changed
signal leveled_up(new_level: int)
signal powerup_changed

const SAVE_PATH := "user://goose_chaos_save.json"
const COMBO_TIME := 3.5

const BRANCHES := [
	{"name": "BRAWLER", "tag": "Boots, bruises and bad decisions", "color": Color(1.0, 0.55, 0.3)},
	{"name": "GADGETEER", "tag": "Fans, plungers and physics crimes", "color": Color(0.4, 0.8, 1.0)},
	{"name": "SURVIVOR", "tag": "Dignity is overrated. Hit points aren't", "color": Color(0.5, 1.0, 0.5)},
]

# req = prerequisite skill id (needs req_rank in it). One point per rank.
const SKILLS := [
	{"id": "boots", "branch": 0, "name": "Steel-Toed Boots", "max": 5, "req": "", "req_rank": 0,
		"desc": "+20% kick damage and +12% kick force per rank."},
	{"id": "hustle", "branch": 0, "name": "Hamstring Hustle", "max": 5, "req": "", "req_rank": 0,
		"desc": "+8% movement speed per rank."},
	{"id": "roundhouse", "branch": 0, "name": "Roundhouse", "max": 3, "req": "boots", "req_rank": 1,
		"desc": "Your kick hits a wider, longer area (+25% per rank)."},
	{"id": "grease", "branch": 0, "name": "Grease Lightning", "max": 3, "req": "hustle", "req_rank": 1,
		"desc": "Slides are 15% faster and bowl enemies for +20% damage per rank."},
	{"id": "shockboots", "branch": 0, "name": "SHOCKWAVE BOOTS", "max": 1, "req": "roundhouse", "req_rank": 2,
		"desc": "CAPSTONE: every kick also unleashes a shockwave that launches and damages everything nearby."},

	{"id": "turbofan", "branch": 1, "name": "Turbo Fan", "max": 5, "req": "", "req_rank": 0,
		"desc": "Leaf blower +15% power, +12% range and +15% damage-over-time per rank."},
	{"id": "suction", "branch": 1, "name": "Industrial Suction", "max": 5, "req": "", "req_rank": 0,
		"desc": "Plunger reels +15% harder, flings +15% faster per rank."},
	{"id": "funnybone", "branch": 1, "name": "Funny Bone", "max": 5, "req": "turbofan", "req_rank": 1,
		"desc": "+10% damage with everything per rank."},
	{"id": "exhaust", "branch": 1, "name": "Exhaust Port", "max": 3, "req": "suction", "req_rank": 1,
		"desc": "Leaf blower rocket-jump thrust +15% per rank."},
	{"id": "yeetcannon", "branch": 1, "name": "YEET CANNON", "max": 1, "req": "funnybone", "req_rank": 2,
		"desc": "CAPSTONE: anything you fling with the plunger EXPLODES on impact."},

	{"id": "thickskin", "branch": 2, "name": "Thick Skin", "max": 5, "req": "", "req_rank": 0,
		"desc": "+12% max HP per rank."},
	{"id": "soup", "branch": 2, "name": "Chicken Soup", "max": 3, "req": "thickskin", "req_rank": 1,
		"desc": "Regenerate +0.8 HP/s per rank after a few safe seconds."},
	{"id": "luckyduck", "branch": 2, "name": "Lucky Duck", "max": 5, "req": "", "req_rank": 0,
		"desc": "+10% loot drop chance and +10% coins per rank."},
	{"id": "rubber", "branch": 2, "name": "Rubber Bones", "max": 3, "req": "thickskin", "req_rank": 1,
		"desc": "-10% damage taken and -15% knockback per rank."},
	{"id": "quickstudy", "branch": 2, "name": "Quick Study", "max": 3, "req": "luckyduck", "req_rank": 1,
		"desc": "+10% XP per rank."},
	{"id": "secondwind", "branch": 2, "name": "SECOND WIND", "max": 1, "req": "rubber", "req_rank": 2,
		"desc": "CAPSTONE: once per wave, a lethal hit instead heals you to 50% and blasts enemies away."},
]

# Stat bonuses granted PER RANK (additive fractions; regen is HP/s).
const SKILL_STATS := {
	"boots": {"kick_damage": 0.20, "kick_force": 0.12},
	"hustle": {"move_speed": 0.08},
	"roundhouse": {"kick_width": 0.25},
	"grease": {"slide_speed": 0.15, "slide_damage": 0.20},
	"turbofan": {"blower_power": 0.15, "blower_range": 0.12},
	"suction": {"plunger_power": 0.15},
	"funnybone": {"damage": 0.10},
	"exhaust": {"thrust": 0.15},
	"thickskin": {"max_hp": 0.12},
	"soup": {"regen": 0.8},
	"luckyduck": {"drop_rate": 0.10, "coin_gain": 0.10},
	"rubber": {"damage_taken": -0.10, "knockback": -0.15},
	"quickstudy": {"xp_gain": 0.10},
}

const POWERUPS := {
	"megaboots": {"name": "MEGA BOOTS", "color": Color(1.0, 0.5, 0.1), "time": 14.0,
		"stats": {"kick_damage": 2.0, "kick_force": 0.6, "kick_width": 0.5}},
	"burrito": {"name": "TURBO BURRITO", "color": Color(1.0, 0.3, 0.2), "time": 12.0,
		"stats": {"move_speed": 0.5, "slide_speed": 0.3}},
	"socks": {"name": "ANTI-GRAVITY SOCKS", "color": Color(0.6, 0.9, 1.0), "time": 14.0,
		"stats": {"gravity": -0.65, "jump": 0.25}},
	"yeetjuice": {"name": "YEET JUICE", "color": Color(0.7, 0.3, 1.0), "time": 12.0,
		"stats": {"damage": 0.6, "kick_force": 0.5, "plunger_power": 0.5, "blower_power": 0.5}},
	"magnet": {"name": "CHEESE MAGNET", "color": Color(0.9, 0.2, 0.3), "time": 18.0,
		"stats": {"pickup_radius": 12.0}},
	"shield": {"name": "DIGNITY SHIELD", "color": Color(0.3, 0.6, 1.0), "time": 8.0, "stats": {}},
}

const STYLE_NAMES := [
	[0, "Meh"], [2, "Nice-ish"], [4, "SLAPSTICK!"], [7, "CHAOS GOBLIN!"],
	[10, "ABSOLUTE UNIT!!"], [14, "GOOSE GOD!!!"],
]

var save_enabled: bool = true
var level: int = 1
var xp: int = 0
var skill_points: int = 0
var ranks: Dictionary = {}
var gear: Dictionary = {}
var coins: int = 0
var best_wave: int = 0
var powerups: Dictionary = {}
var combo: int = 0
var combo_time: float = 0.0

var _stats: Dictionary = {}


func _ready() -> void:
	load_game()
	_recompute()


func _process(delta: float) -> void:
	if combo > 0:
		combo_time -= delta
		if combo_time <= 0.0:
			combo = 0
	var expired := false
	for id: String in powerups.keys():
		powerups[id] = float(powerups[id]) - delta
		if float(powerups[id]) <= 0.0:
			powerups.erase(id)
			expired = true
	if expired:
		_recompute()
		powerup_changed.emit()


# --------------------------------------------------------------------------
# Stat queries
# --------------------------------------------------------------------------
func bonus(stat: String) -> float:
	return float(_stats.get(stat, 0.0))


func mult(stat: String) -> float:
	return maxf(0.05, 1.0 + bonus(stat))


func flag(id: String) -> bool:
	return int(ranks.get(id, 0)) > 0 or powerups.has(id)


func has_powerup(id: String) -> bool:
	return powerups.has(id)


func crit_chance() -> float:
	return clampf(0.05 + bonus("crit"), 0.0, 0.8)


func _recompute() -> void:
	_stats.clear()
	for id: String in ranks:
		var r := int(ranks[id])
		if SKILL_STATS.has(id):
			var per: Dictionary = SKILL_STATS[id]
			for stat: String in per:
				_add(stat, float(per[stat]) * r)
	_add("damage", 0.02 * (level - 1))
	_add("max_hp", 0.03 * (level - 1))
	for slot: String in gear:
		var item: Dictionary = gear[slot]
		for a: Dictionary in item.get("affixes", []):
			_add(String(a["stat"]), float(a["value"]))
	for pid: String in powerups:
		var st: Dictionary = POWERUPS[pid]["stats"]
		for stat: String in st:
			_add(stat, float(st[stat]))
	changed.emit()


func _add(stat: String, v: float) -> void:
	_stats[stat] = float(_stats.get(stat, 0.0)) + v


# --------------------------------------------------------------------------
# XP / combo / coins
# --------------------------------------------------------------------------
func xp_needed(lv: int = -1) -> int:
	if lv < 0:
		lv = level
	return int(60.0 + 40.0 * pow(float(lv), 1.35))


func combo_mult() -> float:
	return 1.0 + minf(float(combo), 20.0) * 0.05


func style_name() -> String:
	var out := "Meh"
	for row: Array in STYLE_NAMES:
		if combo >= int(row[0]):
			out = String(row[1])
	return out


func register_kill() -> void:
	combo += 1
	combo_time = COMBO_TIME


func add_xp(base: int) -> int:
	var amount := int(round(float(base) * mult("xp_gain") * combo_mult()))
	xp += amount
	while xp >= xp_needed(level):
		xp -= xp_needed(level)
		level += 1
		skill_points += 1
		_recompute()
		leveled_up.emit(level)
		Game.banner("LEVEL %d!   +1 skill point  [Tab]" % level, Color(1.0, 0.9, 0.3), 2.5)
		Game.sfx(&"levelup")
		save_game()
	return amount


func add_coins(base: int) -> int:
	var n := int(round(float(base) * mult("coin_gain")))
	coins += maxi(n, 1)
	return maxi(n, 1)


# --------------------------------------------------------------------------
# Skills
# --------------------------------------------------------------------------
func skill_def(id: String) -> Dictionary:
	for s: Dictionary in SKILLS:
		if s["id"] == id:
			return s
	return {}


## "" when purchasable, otherwise a human-readable reason.
func can_buy(id: String) -> String:
	var s := skill_def(id)
	if s.is_empty():
		return "Unknown skill"
	if int(ranks.get(id, 0)) >= int(s["max"]):
		return "Already maxed"
	var req: String = s["req"]
	if req != "" and int(ranks.get(req, 0)) < int(s["req_rank"]):
		return "Needs %s rank %d" % [skill_def(req)["name"], int(s["req_rank"])]
	if skill_points <= 0:
		return "No skill points (level up!)"
	return ""


func buy(id: String) -> bool:
	if can_buy(id) != "":
		return false
	ranks[id] = int(ranks.get(id, 0)) + 1
	skill_points -= 1
	_recompute()
	save_game()
	return true


func respec() -> void:
	var spent := 0
	for id: String in ranks:
		spent += int(ranks[id])
	ranks.clear()
	skill_points += spent
	_recompute()
	save_game()


# --------------------------------------------------------------------------
# Gear and power-ups
# --------------------------------------------------------------------------
## Equip if better than what's in that slot, else sell. Returns true if equipped.
func try_loot(item: Dictionary) -> bool:
	var slot: String = item["slot"]
	if not gear.has(slot) or Loot.rating(item) > Loot.rating(gear[slot]):
		gear[slot] = item
		_recompute()
		save_game()
		return true
	coins += Loot.sell_value(item)
	changed.emit()
	return false


func grant_powerup(id: String) -> void:
	if not POWERUPS.has(id):
		return
	powerups[id] = float(POWERUPS[id]["time"])
	_recompute()
	powerup_changed.emit()


# --------------------------------------------------------------------------
# Save / load
# --------------------------------------------------------------------------
func reset(erase_save: bool = false) -> void:
	level = 1
	xp = 0
	skill_points = 0
	ranks.clear()
	gear.clear()
	coins = 0
	powerups.clear()
	combo = 0
	_recompute()
	if erase_save and FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func save_game() -> void:
	if not save_enabled:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"level": level, "xp": xp, "points": skill_points, "ranks": ranks,
		"gear": gear, "best_wave": best_wave, "coins": coins,
	}))


func load_game() -> void:
	if not save_enabled or not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		return
	var d: Dictionary = data
	level = maxi(1, int(d.get("level", 1)))
	xp = int(d.get("xp", 0))
	skill_points = int(d.get("points", 0))
	best_wave = int(d.get("best_wave", 0))
	coins = int(d.get("coins", 0))
	ranks.clear()
	var r: Dictionary = d.get("ranks", {})
	for id: String in r:
		ranks[id] = int(r[id])
	gear.clear()
	var g: Dictionary = d.get("gear", {})
	for slot: String in g:
		var item: Dictionary = g[slot]
		item["rarity"] = int(item.get("rarity", 0))
		gear[slot] = item
