class_name GazeTune
extends RefCounted
## The tuning session (Downhill): one gate per barrier is lit and you look at it. Every few barriers the eye-tracking layers change
## to the next test setting, and for each barrier we record how long your gaze point sat on the lit gate (two places: the tracker's
## own gaze point, and the game's cursor after its own correction), how long until the game picked that gate, and whether you went
## through it. From those the barrier is sorted into one of five kinds, so "I looked and it did not follow" is told apart from
## "the gaze point never got there":
##   followed             you went through the lit gate, and your gaze was on it for a good part of the approach
##   assist               you went through it, but your gaze was hardly on it: the game's own help carried you, not your eyes
##   looked-not-followed  the game's cursor sat on the lit gate and you still did not go through it: the PICK or the STEERING failed
##   cursor-lost-it       the tracker's gaze was on it but the game's cursor was not: the game's CORRECTION lost it
##   never-reached        neither was on it: your eyes were elsewhere, or the tracker's reading was off
## What it cannot tell: whether your eyes were really on the gate when the tracker says they were not. It can only say the reading
## never got there, and that the other layers had nothing to work with.

const PER := 4                           # barriers per setting
const ON_FRAC := 0.3                     # share of the approach the gaze must sit on the gate to count as "looked"
const MIN_T := 1.0                       # seconds of approach below which a barrier is not scored
const CONFIGS: Array = [
	{"name": "default", "o": {}},
	{"name": "no Kalman", "o": {"kalman": false}},
	{"name": "fixation hold", "o": {"hold": true}},
	{"name": "gaze zones pick", "o": {"pick": 1}},
	{"name": "zones, no stretch, no learning", "o": {"pick": 1, "stretch": false, "learn": false}},
	{"name": "zones + hold, no median", "o": {"pick": 1, "hold": true, "median": 1}},
	{"name": "bare", "o": {"kalman": false, "stab": false, "stretch": false, "learn": false, "hold": false, "median": 1, "pick": 1}},
]
const KINDS: Array = ["followed", "assist", "looked-not-followed", "cursor-lost-it", "never-reached"]

var active: bool = false
var done: bool = false
var trial_i: int = 0
var results: Array = []
var summary: Array = []
var best: String = ""
var _saved: Dictionary = {}
var _shown: int = -1
## AUTO (loop): after trying every setting once, stay on the best, light every second gate to keep measuring it, and every EXPLOIT_N barriers
## try a challenger for 2*PER lit gates; it takes over only if it clearly does better than the incumbent's recent record.
var loop: bool = false
var phase: String = "explore"
var note: String = ""
var incumbent: int = 0
var _inc_hist: Array = []
var _chal: int = -1
var _chal_prev: int = 0
var _chal_hist: Array = []
var _since_chal: int = 0
const EXPLOIT_N := 12
const WIN := 8
const WIN_BY := 0.15


static func classify(went_target: bool, look_cur: float, look_gaze: float, t: float) -> String:
	if t < MIN_T:
		return "n/a"
	if went_target:
		return "followed" if look_cur >= 0.15 or look_gaze >= 0.15 else "assist"
	if look_cur >= ON_FRAC:
		return "looked-not-followed"
	if look_gaze >= ON_FRAC:
		return "cursor-lost-it"
	return "never-reached"


static func explain(kind: String) -> String:
	match kind:
		"followed":
			return "followed your eyes"
		"assist":
			return "went through, but not by your gaze (the game's help)"
		"looked-not-followed":
			return "your gaze was on it and the game did NOT follow"
		"cursor-lost-it":
			return "tracker had you on it, the game's cursor lost it"
		"never-reached":
			return "the gaze reading never reached it"
	return ""


func config_index() -> int:
	if phase != "explore":
		return _shown
	return mini(trial_i / PER, CONFIGS.size() - 1)


## Which barriers carry a lit gate: all of them while testing, every second one while just using the best setting.
func should_light(j: int) -> bool:
	return phase != "exploit" or j % 2 == 0


func config_name() -> String:
	return String((CONFIGS[config_index()] as Dictionary)["name"])


func total() -> int:
	return PER * CONFIGS.size()


func start() -> void:
	_saved = {}
	for d: Array in GazeProvider.opt_defs():
		_saved[d[0]] = GazeProvider.opt_value(d[0])
	active = true
	done = false
	trial_i = 0
	results = []
	summary = []
	best = ""
	_shown = -1
	_apply(0)


func _apply(ci: int) -> void:
	_shown = ci
	GazeProvider.opts_default()
	var o: Dictionary = (CONFIGS[ci] as Dictionary)["o"]
	for k in o:
		GazeProvider.opt_set(String(k), o[k])


## Which gate of this barrier is lit: left-most, right-most, middle, in turn (never just the one nearest the safe line). `allowed` lists the gates
## that are actually on screen (a gate beyond the edge of the view cannot be looked at, so it is no fair test): with fewer than two of them
## the barrier is not lit at all (-1).
func pick_target(gaps: Array, allowed: Array = []) -> int:
	var idx: Array = range(gaps.size())
	if not allowed.is_empty() or gaps.is_empty():
		idx = allowed.duplicate()
		if idx.size() < 2:
			return -1
	idx.sort_custom(func(a: int, b: int) -> bool: return float(gaps[a]["x"]) < float(gaps[b]["x"]))
	if idx.size() <= 1:
		return 0
	var pat := trial_i % 3
	if pat == 0:
		return idx[0]
	if pat == 1:
		return idx[idx.size() - 1]
	return idx[idx.size() / 2] if idx.size() > 2 else idx[(trial_i / 3) % 2]


func record(trial: Dictionary) -> void:
	trial["i"] = trial_i
	trial["ci"] = config_index()
	trial["cfg"] = config_name()
	trial["phase"] = phase
	results.append(trial)
	trial_i += 1
	note = ""
	if loop and phase != "explore":
		_loop_step(1.0 if String(trial["verdict"]) == "followed" else 0.0)
		return
	if trial_i >= total():
		if loop:
			_enter_exploit()
		else:
			finish()
	elif config_index() != _shown:
		_apply(config_index())


func _mean(a: Array) -> float:
	var t := 0.0
	for v in a:
		t += float(v)
	return t / maxf(a.size(), 1.0)


func _pick_best() -> int:
	var bi := -1
	var br := -1.0
	for i in summary.size():
		var s: Dictionary = summary[i]
		if int(s["n"]) < 2:
			continue
		var score := float(s["rate"]) - 0.02 * float(s["mean_lock_s"])
		if score > br:
			br = score
			bi = i
	return bi


func _enter_exploit() -> void:
	summary = summarise()
	GazeProvider.tune_summary = summary
	GazeProvider.tune_trials = results
	var bi := _pick_best()
	incumbent = maxi(bi, 0)
	best = String((CONFIGS[incumbent] as Dictionary)["name"])
	_inc_hist = []
	for r: Dictionary in results:
		if int(r["ci"]) == incumbent:
			_inc_hist.append(1.0 if String(r["verdict"]) == "followed" else 0.0)
	while _inc_hist.size() > WIN:
		_inc_hist.remove_at(0)
	phase = "exploit"
	_since_chal = 0
	_apply(incumbent)
	note = "AUTO: best so far is '%s'; keeping it, and checking challengers as you play" % best


func _loop_step(ok: float) -> void:
	if phase == "exploit":
		_inc_hist.append(ok)
		while _inc_hist.size() > WIN:
			_inc_hist.remove_at(0)
		_since_chal += 1
		if _since_chal >= EXPLOIT_N:
			var c := (_chal_prev + 1) % CONFIGS.size()
			if c == incumbent:
				c = (c + 1) % CONFIGS.size()
			_chal = c
			_chal_prev = c
			_chal_hist = []
			phase = "challenge"
			_apply(c)
			note = "AUTO: trying '%s' against '%s'" % [config_name(), best]
	else:
		_chal_hist.append(ok)
		if _chal_hist.size() >= PER * 2:
			var cr := _mean(_chal_hist)
			var ir := _mean(_inc_hist)
			var cname := String((CONFIGS[_chal] as Dictionary)["name"])
			if cr >= ir + WIN_BY:
				incumbent = _chal
				best = cname
				_inc_hist = _chal_hist.duplicate()
				note = "AUTO: '%s' beat the old setting (%.0f%% vs %.0f%%): now using it" % [cname, cr * 100.0, ir * 100.0]
			else:
				note = "AUTO: '%s' did not beat '%s' (%.0f%% vs %.0f%%): staying" % [cname, best, cr * 100.0, ir * 100.0]
			phase = "exploit"
			_since_chal = 0
			_apply(incumbent)


func summarise() -> Array:
	var out: Array = []
	for c in CONFIGS.size():
		var counts := {}
		for k in KINDS:
			counts[k] = 0
		var n := 0
		var lock_sum := 0.0
		var lock_n := 0
		var cur_sum := 0.0
		for r: Dictionary in results:
			if int(r.get("ci", int(r["i"]) / PER)) != c or String(r["verdict"]) == "n/a":
				continue
			n += 1
			counts[r["verdict"]] = int(counts[r["verdict"]]) + 1
			cur_sum += float(r["look_cur"])
			if float(r["aim_t"]) >= 0.0:
				lock_sum += float(r["aim_t"])
				lock_n += 1
		out.append({"name": (CONFIGS[c] as Dictionary)["name"], "n": n, "followed": counts["followed"], "assist": counts["assist"], "looked_not_followed": counts["looked-not-followed"],
			"cursor_lost_it": counts["cursor-lost-it"], "never_reached": counts["never-reached"], "mean_look": snappedf(cur_sum / maxf(n, 1.0), 0.01),
			"mean_lock_s": snappedf(lock_sum / maxf(lock_n, 1.0), 0.01), "rate": snappedf(float(counts["followed"]) / maxf(n, 1.0), 0.01)})
	return out


func finish() -> void:
	active = false
	done = true
	summary = summarise()
	var bi := -1
	var br := -1.0
	for i in summary.size():
		var s: Dictionary = summary[i]
		if int(s["n"]) < 2:
			continue
		var score := float(s["rate"]) - 0.02 * float(s["mean_lock_s"])
		if score > br:
			br = score
			bi = i
	if bi >= 0:
		best = String(summary[bi]["name"])
		_apply(bi)
	else:
		for k in _saved:
			GazeProvider.opt_set(String(k), _saved[k])
	GazeProvider.tune_summary = summary
	GazeProvider.tune_trials = results
