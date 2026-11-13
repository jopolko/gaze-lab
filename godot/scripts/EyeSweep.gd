class_name EyeSweep
extends RefCounted
## One quick calibration pass: a dot glides around the screen for about four seconds and you follow it with your eyes. No
## waiting on dots, no staring: following a moving thing is what eyes do easily (smooth pursuit), and the tracker reads a
## steady stream of "eyes here, dot there" pairs across the whole screen, including both edges, which is exactly what the
## scale and offset of the gaze point need.
##
## fit() lines the readings up with where the dot was a fraction of a second EARLIER (your eyes and the tracker are behind the
## dot), trying a few delays and keeping the one that agrees best, then fits a straight line per axis, ignoring the worst
## fifth of the readings (blinks, glances away).

const LEAD := 0.8                       # seconds the dot waits at the start so you can find it (no readings kept)
const SPEED := 1.05                     # screen fractions per second along the path
const WAYPOINTS: Array[Vector2] = [Vector2(0.5, 0.5), Vector2(0.1, 0.5), Vector2(0.1, 0.1), Vector2(0.9, 0.1), Vector2(0.9, 0.9), Vector2(0.1, 0.9), Vector2(0.1, 0.5), Vector2(0.5, 0.5)]
const LAGS: Array[float] = [0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45]
const MIN_SAMPLES := 22


static func length() -> float:
	var t := 0.0
	for i in WAYPOINTS.size() - 1:
		t += WAYPOINTS[i].distance_to(WAYPOINTS[i + 1])
	return t


## How long the moving part lasts, in seconds.
static func duration() -> float:
	return length() / SPEED


## Where the dot is `t` seconds after the lead-in ended (t <= 0: at the start, t >= duration: at the end).
static func dot(t: float) -> Vector2:
	var d := clampf(t, 0.0, duration()) * SPEED
	for i in WAYPOINTS.size() - 1:
		var seg := WAYPOINTS[i].distance_to(WAYPOINTS[i + 1])
		if d <= seg:
			return WAYPOINTS[i].lerp(WAYPOINTS[i + 1], d / maxf(seg, 0.0001))
		d -= seg
	return WAYPOINTS[WAYPOINTS.size() - 1]


## samples: Array of [t, u, v] (t as for dot(), u/v the gaze reading before our correction).
## Returns {"ok": bool, "why": String, "lag", "ax", "sx", "ay", "sy", "rms": Vector2, "n": int}: screen = a + s * reading.
static func fit(samples: Array) -> Dictionary:
	var out := {"ok": false, "why": "too few readings", "n": samples.size()}
	if samples.size() < MIN_SAMPLES:
		return out
	var best: Dictionary = {}
	var best_score := 1.0e9
	for lag in LAGS:
		var xs := PackedFloat32Array()
		var ys := PackedFloat32Array()
		var us := PackedFloat32Array()
		var vs := PackedFloat32Array()
		for s: Array in samples:
			var p := dot(float(s[0]) - lag)
			xs.append(p.x)
			ys.append(p.y)
			us.append(float(s[1]))
			vs.append(float(s[2]))
		var fx := _line(us, xs)
		var fy := _line(vs, ys)
		var score: float = float(fx["rms"]) + float(fy["rms"])
		if score < best_score:
			best_score = score
			best = {"lag": lag, "ax": fx["a"], "sx": fx["s"], "ay": fy["a"], "sy": fy["s"], "rms": Vector2(fx["rms"], fy["rms"]), "su": fx["span"], "sv": fy["span"]}
	out = best
	out["n"] = samples.size()
	out["ok"] = false
	var rms: Vector2 = best["rms"]
	if float(best["su"]) < 0.05 or float(best["sv"]) < 0.03:
		out["why"] = "your eyes barely moved: follow the dot with your eyes"
	elif float(best["sx"]) < 0.3 or float(best["sx"]) > 6.0 or float(best["sy"]) < 0.3 or float(best["sy"]) > 6.0:
		out["why"] = "the readings did not follow the dot"
	elif rms.x > 0.14 or rms.y > 0.14:
		out["why"] = "too noisy: more light on your face, sit still, face the screen"
	else:
		out["ok"] = true
		out["why"] = ""
	return out


## Least squares y = a + s*x, then again without the worst fifth. Also the spread (10th to 90th percentile) of x.
static func _line(x: PackedFloat32Array, y: PackedFloat32Array) -> Dictionary:
	var idx: Array = range(x.size())
	var ab := _ols(x, y, idx)
	var res: Array = []
	for i in idx:
		res.append([absf(y[i] - (ab.x + ab.y * x[i])), i])
	res.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	var keep: Array = []
	for k in int(float(res.size()) * 0.8):
		keep.append(res[k][1])
	ab = _ols(x, y, keep)
	var e2 := 0.0
	for i in keep:
		var e := y[i] - (ab.x + ab.y * x[i])
		e2 += e * e
	var sx := x.duplicate()
	sx.sort()
	var span := sx[int(float(sx.size()) * 0.9)] - sx[int(float(sx.size()) * 0.1)]
	return {"a": ab.x, "s": ab.y, "rms": sqrt(e2 / maxf(keep.size(), 1.0)), "span": span}


static func _ols(x: PackedFloat32Array, y: PackedFloat32Array, idx: Array) -> Vector2:
	var n := float(idx.size())
	if n < 2.0:
		return Vector2(0.0, 1.0)
	var mx := 0.0
	var my := 0.0
	for i in idx:
		mx += x[i]
		my += y[i]
	mx /= n
	my /= n
	var sxx := 0.0
	var sxy := 0.0
	for i in idx:
		sxx += (x[i] - mx) * (x[i] - mx)
		sxy += (x[i] - mx) * (y[i] - my)
	var s := sxy / maxf(sxx, 1.0e-9)
	return Vector2(my - s * mx, s)
