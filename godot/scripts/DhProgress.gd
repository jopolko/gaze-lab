class_name DhProgress
extends RefCounted
## The player's progress in Downhill: points earned in runs turn into XP, XP into a level, and levels open up the looks and the sandbox toys one at a time, so the game
## starts simple and grows. Kept on this device only.

const SAVE := "user://downhill_progress.cfg"
const LEVEL_XP := [0, 300, 800, 1600, 2800, 4500, 7000, 10000, 14000]          # XP at which levels 1..9 begin

## What opens at which level. Keys are the menu setting names; "theme:<id>" is a look.
const UNLOCK := {
	"theme:psychedelic": 1, "theme:alpine": 1,
	"theme:tunnel": 2, "m_grav": 2, "m_pads": 2,
	"theme:desert": 3, "m_hat": 3, "m_ramps": 3, "m_rocks": 3,
	"m_glints": 4, "m_faces": 4, "m_ice": 4,
	"m_head": 5,
	"m_bounce": 6,
	"m_trike": 7,
}
const NAMES := {
	"theme:tunnel": "Tunnel Road", "theme:desert": "Desert Sun", "m_grav": "Gravity", "m_pads": "Boost pads", "m_hat": "Hats", "m_ramps": "Ramp frequency", "m_rocks": "Rock frequency",
	"m_glints": "Glint rain", "m_faces": "Face challenge rate", "m_ice": "Ice rink", "m_head": "Big head", "m_bounce": "Bouncy snow", "m_trike": "Tricycle",
}

static var xp: float = -1.0


static func _load() -> void:
	if xp >= 0.0:
		return
	xp = 0.0
	var cf := ConfigFile.new()
	if cf.load(SAVE) == OK:
		xp = float(cf.get_value("p", "xp", 0.0))
	if OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("unlock"):
		xp = 1.0e6                                          # ?unlock: everything open, for testing


static func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("p", "xp", xp)
	cf.save(SAVE)


static func get_xp() -> float:
	_load()
	return xp


static func level_of(x: float) -> int:
	var lv := 1
	for i in LEVEL_XP.size():
		if x >= float(LEVEL_XP[i]):
			lv = i + 1
	return lv


static func level() -> int:
	_load()
	return level_of(xp)


## XP into this level and XP the level needs: for the bar in the menu.
static func progress() -> Vector2:
	_load()
	var lv := level()
	if lv > LEVEL_XP.size() - 1:
		return Vector2(1.0, 1.0)
	return Vector2(xp - float(LEVEL_XP[lv - 1]), float(LEVEL_XP[lv]) - float(LEVEL_XP[lv - 1]))


static func need(key: String) -> int:
	return int(UNLOCK.get(key, 1))


static func unlocked(key: String) -> bool:
	return level() >= need(key)


## Adds XP; returns the list of names opened by it (empty if the level did not change).
static func add(a: float) -> Array:
	_load()
	var before := level_of(xp)
	xp += a
	var after := level_of(xp)
	_save()
	var opened: Array = []
	if after > before:
		for key in UNLOCK:
			var n: int = UNLOCK[key]
			if n > before and n <= after and NAMES.has(key):
				opened.append(NAMES[key])
	return opened


static func unlock_all() -> void:
	_load()
	xp = maxf(xp, 1.0e6)
	_save()
