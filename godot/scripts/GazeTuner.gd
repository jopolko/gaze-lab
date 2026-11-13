class_name GazeTuner
extends RefCounted
## The load-time tuner: tries the options of each "budget" knob one after another for a few seconds each, scores them on how smooth the game AND the tracker are at the same time, and keeps the
## best. One knob at a time, in order, then done; the result is saved per device so the next visit skips the search. The same code re-runs when the machine slows down later (heat, battery).
##
## A trial is SETTLE seconds to let the change take effect and the tracker's two-second rate window flush, then WINDOW seconds of measuring (10 samples a second, averaged).
## The default (first) option is only replaced when another one scores clearly better (KEEP_MARGIN), so noise does not make it hop about.
## Score (0..1): half game smoothness (50 fps = full), half tracker rate (20 readings a second = full), minus a penalty for latency over 100 ms.

const SETTLE := 2.2
const WINDOW := 3.0
const KEEP_MARGIN := 0.04

var knobs: Array = []                 # [{id, label, options: [{v, label}]}]
var active: bool = false
var done: bool = false
var k: int = 0                        # knob being tried
var o: int = 0                        # option being tried
var t: float = 0.0
var chosen: Dictionary = {}           # id -> value kept so far
var log: Array = []                   # [{knob, option, score, kept}]
var final_score: float = 0.0
var _scores: Array = []
var _acc: Array = []                  # samples in the measuring window
var _before: Dictionary = {}          # the setting before the search, to put back if cancelled


static func score(m: Dictionary) -> float:
	var game := minf(float(m.get("game", 0.0)) / 50.0, 1.0)
	var trk := minf(float(m.get("trk", 0.0)) / 20.0, 1.0)
	var lat := maxf(float(m.get("lat", 0.0)) - 100.0, 0.0) / 500.0
	return clampf(0.5 * game + 0.5 * trk - lat, 0.0, 1.0)


func start(p_knobs: Array) -> void:
	knobs = p_knobs
	active = not knobs.is_empty()
	done = false
	k = 0
	o = 0
	t = 0.0
	chosen = {}
	log = []
	_scores = []
	_acc = []
	if active:
		_apply_current()


func _apply_current() -> void:
	var kn: Dictionary = knobs[k]
	GazeProvider.tuner_apply(str(kn["id"]), (kn["options"] as Array)[o]["v"])


## Where it is, for the on-screen indicator: {"element", "option", "left", "total", "step", "steps"}.
func status() -> Dictionary:
	if not active:
		return {}
	var kn: Dictionary = knobs[k]
	var opts: Array = kn["options"]
	var total := SETTLE + WINDOW
	var idx := o + 1
	for i in k:
		idx += (knobs[i]["options"] as Array).size()
	return {"element": str(kn["label"]), "option": str((opts[o] as Dictionary)["label"]), "left": maxf(total - t, 0.0), "total": total, "step": idx, "steps": _step_count()}


func _step_count() -> int:
	var n := 0
	for kn: Dictionary in knobs:
		n += (kn["options"] as Array).size()
	return n


## Advance by dt; `m` is the current metrics ({game, trk, lat}). Returns an event when something finished: {"event": "trial"|"knob"|"done", ...}, else {}.
func tick(dt: float, m: Dictionary) -> Dictionary:
	if not active:
		return {}
	t += dt
	if t >= SETTLE:
		_acc.append(m)
	if t < SETTLE + WINDOW:
		return {}
	var sum := {"game": 0.0, "trk": 0.0, "lat": 0.0}
	for a: Dictionary in _acc:
		for key in sum:
			sum[key] = float(sum[key]) + float(a.get(key, 0.0))
	var n := maxf(float(_acc.size()), 1.0)
	for key in sum:
		sum[key] = float(sum[key]) / n
	var sc := score(sum)
	_scores.append(sc)
	var kn: Dictionary = knobs[k]
	var opts: Array = kn["options"]
	log.append({"knob": str(kn["id"]), "option": str((opts[o] as Dictionary)["label"]), "score": snappedf(sc, 0.001), "game": snappedf(float(sum["game"]), 0.1), "trk": snappedf(float(sum["trk"]), 0.1), "lat": int(float(sum["lat"]))})
	t = 0.0
	_acc = []
	if o + 1 < opts.size():
		o += 1
		_apply_current()
		return {"event": "trial", "score": sc}
	# all options of this knob tried: keep the best (the first, the default, unless another one is clearly better)
	var bi := 0
	for i in range(1, _scores.size()):
		if float(_scores[i]) > float(_scores[bi]) + (KEEP_MARGIN if bi == 0 else 0.0):
			bi = i
	chosen[str(kn["id"])] = (opts[bi] as Dictionary)["v"]
	GazeProvider.tuner_apply(str(kn["id"]), (opts[bi] as Dictionary)["v"])
	var ev := {"event": "knob", "knob": str(kn["id"]), "kept": str((opts[bi] as Dictionary)["label"]), "score": float(_scores[bi]), "default": float(_scores[0])}
	_scores = []
	o = 0
	if k + 1 < knobs.size():
		k += 1
		_apply_current()
		return ev
	active = false
	done = true
	final_score = float(ev["score"])
	ev["event"] = "done"
	return ev
