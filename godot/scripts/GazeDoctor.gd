class_name GazeDoctor
extends RefCounted
## The silent tracking doctor: nobody has to know what the layers are. While you play it watches how the choices of the last few barriers went (no lit gate, no questions),
## names what looks wrong, changes ONE thing, waits a few more barriers, and keeps the change only if the picture got better; otherwise it puts it back.
##
## Per barrier with two or more gates it sees: which gate your gaze sat nearest, which gate the game locked onto (and how fast, how often it changed its mind or let go),
## which gate the board went through, and how far your gaze moved. From the last WIN of them:
##   lock_rate  how often the game locked onto any gate
##   honored    how often the board went through the gate it had locked onto
##   agree      how often the board went through the gate your gaze was nearest
##   flips      how often it changed its mind inside one barrier
##   range      how far your gaze point travelled across the screen (fraction of the width)
## Diagnoses (first match wins, one action at a time, a cooldown of WIN barriers after each):
##   NO_LOCK       you move your gaze but the game rarely locks            -> gaze-zones pick, then a shorter latch time, then fixation hold
##   NOT_HONORED   it locks but the board goes through a different gate    -> start the pull toward the chosen gate earlier, then pull harder
##   NARROW        your gaze hardly travels across the screen              -> a calibration sweep (once), then a bigger look-to-cursor gain
##   FLIPPY        it keeps changing its mind                              -> fixation hold, then a longer latch time
##   WRONG_PICK    the board follows the lock but the lock is not where you look -> gaze-zones pick
## Every action is logged with the numbers that triggered it and, WIN barriers later, with the verdict (kept or put back). The log is what a person validates afterwards.

const WIN := 6
const MIN_GATES := 2
const MAX_ACTIONS := 10
const GOOD_ENOUGH := 0.8             # at or above this score the doctor leaves everything alone
const KEEP_MARGIN := -0.08            # an action is kept unless the score fell by more than this

var records: Array = []               # barrier records since the last action settled
var log: Array = []                   # finished entries: {issue, evidence, action, before, after, verdict}
var pending: Dictionary = {}          # the action being verified
var cooldown: int = 0
var actions_done: int = 0
var enabled: bool = true
var sweep_wanted: bool = false        # the doctor asks the rig to run a calibration sweep at the next calm moment
var _tried: Dictionary = {}           # "ISSUE:step" -> true: each remedy is tried once per session


static func metrics(recs: Array) -> Dictionary:
	var n := 0
	var locks := 0
	var honored := 0
	var lock_n := 0
	var agree := 0
	var agree_n := 0
	var flips := 0.0
	var rng := 0.0
	for r: Dictionary in recs:
		if int(r.get("n", 0)) < MIN_GATES:
			continue
		n += 1
		var ae := int(r.get("aim_end", -1))
		var went := int(r.get("went", -1))
		if ae >= 0:
			locks += 1
			lock_n += 1
			if went == ae:
				honored += 1
		var lk := int(r.get("looked", -1))
		if lk >= 0:
			agree_n += 1
			if went == lk:
				agree += 1
		flips += float(r.get("flips", 0))
		rng += float(r.get("cur_max", 0.5)) - float(r.get("cur_min", 0.5))
	var nn := maxf(float(n), 1.0)
	var m := {"n": n, "lock_rate": snappedf(float(locks) / nn, 0.01), "honored": snappedf(float(honored) / maxf(float(lock_n), 1.0), 0.01),
		"agree": snappedf(float(agree) / maxf(float(agree_n), 1.0), 0.01), "flips": snappedf(flips / nn, 0.01), "range": snappedf(rng / nn, 0.01)}
	m["score"] = snappedf(0.6 * float(m["agree"]) + 0.25 * float(m["honored"]) + 0.15 * float(m["lock_rate"]) - 0.05 * minf(float(m["flips"]), 4.0), 0.001)
	return m


## One finished barrier. Returns a log entry when something was decided (an action taken, or one judged), else {}.
func add_barrier(rec: Dictionary) -> Dictionary:
	if not enabled or int(rec.get("n", 0)) < MIN_GATES:
		return {}
	records.append(rec)
	while records.size() > WIN * 2:
		records.remove_at(0)
	if not pending.is_empty():
		pending["seen"] = int(pending["seen"]) + 1
		pending["after_recs"].append(rec)
		if int(pending["seen"]) >= WIN:
			return _judge()
		return {}
	if cooldown > 0:
		cooldown -= 1
		return {}
	if records.size() < WIN or actions_done >= MAX_ACTIONS:
		return {}
	return _diagnose()


func _diagnose() -> Dictionary:
	var recent := records.slice(records.size() - WIN)
	var m := metrics(recent)
	if int(m["n"]) < WIN - 1:
		return {}
	if float(m["score"]) >= GOOD_ENOUGH:
		return {}                       # it is working: a side effect (it changes its mind a lot, say) that is not hurting the choices is not a problem to fix
	var issue := ""
	if float(m["lock_rate"]) < 0.5 and float(m["range"]) >= 0.2:
		issue = "NO_LOCK"
	elif float(m["lock_rate"]) >= 0.5 and float(m["honored"]) < 0.6:
		issue = "NOT_HONORED"
	elif float(m["range"]) < 0.15:
		issue = "NARROW"
	elif float(m["flips"]) >= 1.5:
		issue = "FLIPPY"
	elif float(m["lock_rate"]) >= 0.5 and float(m["honored"]) >= 0.7 and float(m["agree"]) < 0.5:
		issue = "WRONG_PICK"
	if issue == "":
		return {}
	var act := _next_remedy(issue)
	if act.is_empty():
		return {}
	_apply(act)
	actions_done += 1
	pending = {"issue": issue, "action": act, "before": m, "seen": 0, "after_recs": []}
	return {"event": "action", "issue": issue, "evidence": m, "action": str(act["label"])}


## The remedies for each issue, in the order they are tried; a remedy already tried (or already in effect) is skipped.
func _next_remedy(issue: String) -> Dictionary:
	var steps: Array = []
	match issue:
		"NO_LOCK":
			steps = [{"id": "zones", "label": "pick the gate nearest your gaze (zones)", "kind": "opt", "key": "pick", "val": 1},
				{"id": "linger", "label": "latch onto a gate sooner", "kind": "param", "key": "p_linger", "mul": 0.6, "min": 0.35},
				{"id": "hold", "label": "steady the gaze point (fixation hold)", "kind": "opt", "key": "hold", "val": true}]
		"NOT_HONORED":
			steps = [{"id": "pull_early", "label": "start steering toward the chosen gate earlier", "kind": "param", "key": "p_pull", "mul": 0.65, "min": 0.1},
				{"id": "pull_hard", "label": "steer toward the chosen gate harder", "kind": "param", "key": "p_carve", "mul": 1.25, "max": 1.6}]
		"NARROW":
			steps = [{"id": "sweep", "label": "calibrate the eyes with one sweep", "kind": "sweep"},
				{"id": "gain", "label": "make a small look move the cursor further", "kind": "param", "key": "p_reach", "mul": 1.25, "max": 2.0}]
		"FLIPPY":
			steps = [{"id": "hold", "label": "steady the gaze point (fixation hold)", "kind": "opt", "key": "hold", "val": true},
				{"id": "linger_up", "label": "wait a little longer before latching", "kind": "param", "key": "p_linger", "mul": 1.3, "max": 2.0}]
		"WRONG_PICK":
			steps = [{"id": "zones", "label": "pick the gate nearest your gaze (zones)", "kind": "opt", "key": "pick", "val": 1}]
	for st: Dictionary in steps:
		var key := issue + ":" + str(st["id"])
		if _tried.has(key):
			continue
		if str(st["kind"]) == "opt" and GazeProvider.opt_value(str(st["key"])) == st["val"]:
			_tried[key] = true
			continue
		if str(st["kind"]) == "param":
			var cur := float(GazeProvider.get(str(st["key"])))
			var nxt := cur * float(st["mul"])
			if (st.has("min") and cur <= float(st["min"]) + 0.001) or (st.has("max") and cur >= float(st["max"]) - 0.001):
				_tried[key] = true
				continue
		_tried[key] = true
		return st
	return {}


func _apply(act: Dictionary) -> void:
	match str(act["kind"]):
		"opt":
			act["old"] = GazeProvider.opt_value(str(act["key"]))
			GazeProvider.opt_set(str(act["key"]), act["val"])
		"param":
			var cur := float(GazeProvider.get(str(act["key"])))
			act["old"] = cur
			var nxt := cur * float(act["mul"])
			if act.has("min"):
				nxt = maxf(nxt, float(act["min"]))
			if act.has("max"):
				nxt = minf(nxt, float(act["max"]))
			GazeProvider.set(str(act["key"]), nxt)
		"sweep":
			sweep_wanted = true
			act["old"] = null


func _revert(act: Dictionary) -> void:
	match str(act["kind"]):
		"opt":
			GazeProvider.opt_set(str(act["key"]), act["old"])
		"param":
			GazeProvider.set(str(act["key"]), float(act["old"]))
		"sweep":
			pass


func _judge() -> Dictionary:
	var act: Dictionary = pending["action"]
	var before: Dictionary = pending["before"]
	var after := metrics(pending["after_recs"])
	var kept := true
	if str(act["kind"]) != "sweep":
		kept = float(after["score"]) - float(before["score"]) >= KEEP_MARGIN
	if not kept:
		_revert(act)
	var entry := {"event": "verdict", "issue": pending["issue"], "action": str(act["label"]), "before": before, "after": after, "verdict": "kept" if kept else "put back"}
	log.append({"issue": pending["issue"], "evidence": before, "action": str(act["label"]), "after": after, "verdict": entry["verdict"]})
	pending = {}
	records.clear()
	cooldown = WIN
	return entry
