class_name KitEye
## The sideways eye reading from the STARGAZE tracker, ported as it is (no calibration, no Kalman filter, no blending of several readings): on the player's phone it
## followed a sideways look well, where the blend of three readings used here before did not.
##
##   hx    where the iris sits along the line between the corners of the eye, averaged over both eyes (0 = the middle, in eye widths)
##   x     hx minus its own slow centre (it follows over about 4 s), times 14, limited to -1 .. +1, through a One-Euro filter. + = looking to the right of the screen.
##
## The reading is held while the lids are moving (a blink drags the iris landmark with it). "Open" is judged against this face's own resting lid level, because the raw
## blink score for open eyes is much higher when you look down at a phone.

const GAIN := 14.0
const CENTRE_S := 4.0
const MIN_CUT := 1.6
const BETA := 0.5

var x: float = 0.0
var ready: bool = false
var centre: float = 0.0
var held: bool = false           # this frame was skipped (lids moving)
var _n: int = 0
# the calibrated look (see the end of this file): fitted on a few seconds of following a dot
const NF := 7
## Which of the seven readings the fit may use: the iris along the eye and nothing else. With the head turn and the face position let in, the fit followed how the phone
## was held (on two phones it moved with head pose, not with the iris), so a hand-held phone steered by wobbling.
const FIT_ON := [true, false, false, false, false, false, false]
const RECENTRE_S := 20.0          # the resting place of the iris drifts as the phone is re-gripped: the fitted look follows it this slowly
var lost: bool = false            # no reading for a moment: the face is out of the picture
var lost_s: float = 0.0
var refit_due: bool = false       # the face was away long enough that the fit may belong to someone else
var fit_raw: Dictionary = {}      # what the last fit was made from, for the log
var _drift: float = 0.0
var feat := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
var has_feat: bool = false
var model: Dictionary = {}
var gaze_x: float = 0.0          # -1 .. +1 = the left and right edges of the screen
var recording: bool = false
var _rec: Array = []             # [t, PackedFloat32Array]
var _gx: float = 0.0
var _gdx: float = 0.0
var _g_init: bool = false
var _g_cut: float = 0.9
var _t: float = -1.0
var _fx: float = 0.0
var _fdx: float = 0.0
var _f_init: bool = false
var _base := [-1.0, -1.0]
var _closed: bool = false
var _open_t: float = -10.0
# LEFT / MIDDLE / RIGHT (see the end of this file): three places on the screen, told apart by where the iris rests for each
const Z_IN := 0.5                 # more than half way to a side target: that side
const Z_OUT := 0.3                # back inside this: the middle again
var zones: Dictionary = {}        # {m, dl, dr, noise}: the iris reading for a look at the middle, and how far it moves for a look at the left and the right target
var zone: int = 0                 # -1 left, 0 middle, +1 right
var zn: float = 0.0               # the same thing unrounded: -1 = on the left target, +1 = on the right target
var zone_t: float = 0.0           # when the zone last changed
var _zh: Array = []
var _zdrift: float = 0.0
var _zbuf: Array = []             # the last ~12 s of readings: where the eyes REST is where most of them are, whatever the middle was first taken to be
var _zbt: float = 0.0
var _zside_s: float = 0.0
# NO DOTS. With auto_zones the three places are learned while playing: the middle is where the iris rests in the first moments, and the size of a look to a side starts at
# a typical phone value and follows the looks the player really makes (every look to a side that reaches past the line teaches how far that side is).
var auto_zones: bool = false
var _zauto: Array = []
var _zpk: float = 0.0
const AUTO_M := 0.018              # where the iris rests, typical (measured on a phone and on a laptop: 0.014 to 0.021)
const AUTO_D := 0.03               # how far it moves for a look to a side, small (a phone: 0.026 to 0.034; a laptop moves about 3x that)


func reset() -> void:
	x = 0.0
	ready = false
	_n = 0
	_t = -1.0
	_f_init = false
	_base = [-1.0, -1.0]
	_closed = false
	model = {}
	recording = false
	lost = false
	lost_s = 0.0
	refit_due = false
	_drift = 0.0
	zones = {}
	zone = 0
	zn = 0.0
	_zh.clear()
	_zdrift = 0.0
	_zbuf.clear()
	_zbt = 0.0
	_zside_s = 0.0
	_zauto.clear()
	_zpk = 0.0


## Every frame: when the readings stop (no face in the picture) the look eases back to straight ahead instead of staying where it was.
func idle(now: float, delta: float) -> void:
	if _t < 0.0:
		return
	if now - _t > 0.7:
		lost = true
		lost_s += delta
		gaze_x = move_toward(gaze_x, 0.0, delta * 1.5)
		_gx = gaze_x
		x = move_toward(x, 0.0, delta * 1.5)
		_fx = x
		if zone != 0:
			zone = 0
			zone_t = now
		zn = 0.0
		_zh.clear()
		if lost_s > 8.0 and fitted():
			refit_due = true
	else:
		lost = false
		lost_s = 0.0


func _alpha(cut: float, dt: float) -> float:
	var r := TAU * cut * dt
	return r / (r + 1.0)


## The other six things the fit uses, from the same camera frame: iris height in the eye, upper lid, head turn and nod, where the face is in the picture.
func set_feat(hx: float, hy: float, lid: float, yaw: float, pitch: float, fx: float, fy: float) -> void:
	feat[0] = hx
	feat[1] = hy
	feat[2] = lid
	feat[3] = yaw
	feat[4] = pitch
	feat[5] = fx
	feat[6] = fy
	has_feat = true


func add(hx: float, blink_l: float, blink_r: float, t: float) -> float:
	var dt := clampf(t - _t, 0.001, 1.0) if _t >= 0.0 else 0.033
	_t = t
	if float(_base[0]) < 0.0:
		_base = [minf(blink_l, 0.5), minf(blink_r, 0.5)]
	var sc := [blink_l, blink_r]
	var lo := 1.0
	var hi := 0.0
	for i in 2:
		var b := float(_base[i])
		var s := float(sc[i])
		if s < b:
			b += (s - b) * 0.3                                  # drops to a lower reading at once ...
		elif not _closed:
			b += (minf(s, 0.6) - b) * minf(1.0, dt / 8.0)       # ... and creeps up only slowly
		_base[i] = b
		var nb := clampf((s - b) / maxf(1.0 - b, 0.01), 0.0, 1.0)
		lo = minf(lo, nb)
		hi = maxf(hi, nb)
	if not _closed and lo > 0.5:
		_closed = true
	elif _closed and lo < 0.28:
		_closed = false
		_open_t = t
	held = not (hi < 0.38 and not _closed and t - _open_t > 0.12)
	if held:
		return x
	if has_feat:
		if recording:
			_rec.append([t, feat.duplicate()])
		if not zones.is_empty():
			_zone_step(hx, dt, t)
		elif auto_zones:
			_zauto.append(hx)
			if _zauto.size() >= 40:
				var m0 := _median(_zauto)
				zones = {"m": m0, "dl": AUTO_D, "dr": -AUTO_D, "noise": 0.0025, "auto": true}
				_zauto.clear()
				_zpk = 0.0
		if not model.is_empty():
			var pr := _predict(model, feat) - float(model["c"])
			_drift += (pr - _drift) * minf(1.0, dt / RECENTRE_S)
			var pv := (pr - _drift) * float(model["g"]) + float(model["c"])
			pv = clampf(pv, -1.2, 1.2)
			if not _g_init:
				_gx = pv
				_gdx = 0.0
				_g_init = true
			else:
				var gdv := (pv - _gx) / dt
				_gdx += _alpha(1.0, dt) * (gdv - _gdx)
				_gx += _alpha(_g_cut + 0.45 * absf(_gdx), dt) * (pv - _gx)
			gaze_x = _gx
	if _n == 0:
		centre = hx
	centre += (hx - centre) * minf(1.0, dt / CENTRE_S)
	var v := clampf(-(hx - centre) * GAIN, -1.0, 1.0)        # the camera picture is not mirrored: iris toward its right = looking to the left of the screen
	if not _f_init:
		_fx = v
		_fdx = 0.0
		_f_init = true
	else:
		var dv := (v - _fx) / dt
		_fdx += _alpha(1.0, dt) * (dv - _fdx)
		_fx += _alpha(MIN_CUT + BETA * absf(_fdx), dt) * (v - _fx)
	x = _fx
	_n += 1
	ready = _n >= 20
	return x


# --------------------------------------------------------------------------
# The fit (sideways only). While a dot sweeps left and right for a few seconds the seven readings are recorded; a ridge regression then maps them to where the dot was.
# It also finds by how much the eyes and the camera trail the dot (0 to 0.42 s), drops the worst readings once (glances away, half blinks) and stretches the result so it
# reaches the edges of the screen. Which reading does the work is up to the fit: on a hand-held phone it is often the small turn of the head, not the iris.
# --------------------------------------------------------------------------
func begin_fit() -> void:
	_rec.clear()
	recording = true


static func _solve(a: Array, b: Array) -> Array:
	var n := b.size()
	for i in n:
		var p := i
		for r in range(i + 1, n):
			if absf(float(a[r][i])) > absf(float(a[p][i])):
				p = r
		var tr: Array = a[i]
		a[i] = a[p]
		a[p] = tr
		var tb: float = b[i]
		b[i] = b[p]
		b[p] = tb
		var d := float(a[i][i])
		if absf(d) < 1.0e-12:
			d = 1.0e-12
		for r in range(i + 1, n):
			var f := float(a[r][i]) / d
			if f == 0.0:
				continue
			for c in range(i, n):
				a[r][c] = float(a[r][c]) - f * float(a[i][c])
			b[r] = float(b[r]) - f * float(b[i])
	var xs: Array = []
	xs.resize(n)
	for i in range(n - 1, -1, -1):
		var sm := float(b[i])
		for c in range(i + 1, n):
			sm -= float(a[i][c]) * float(xs[c])
		var dd := float(a[i][i])
		xs[i] = sm / (dd if absf(dd) > 1.0e-12 else 1.0e-12)
	return xs


static func _predict(m: Dictionary, f: PackedFloat32Array) -> float:
	var w: Array = m["w"]
	var mean: Array = m["mean"]
	var sd: Array = m["std"]
	var v := float(w[NF])
	for j in NF:
		v += float(w[j]) * (f[j] - float(mean[j])) / float(sd[j])
	return v


## pairs: [[PackedFloat32Array, x], ...] -> model, or {}
static func _ridge(pairs: Array) -> Dictionary:
	var n := pairs.size()
	if n < 30:
		return {}
	var mean: Array = []
	var sd: Array = []
	for j in NF:
		mean.append(0.0)
		sd.append(0.0)
	for p in pairs:
		for j in NF:
			mean[j] = float(mean[j]) + (p[0] as PackedFloat32Array)[j] / float(n)
	for p in pairs:
		for j in NF:
			sd[j] = float(sd[j]) + pow((p[0] as PackedFloat32Array)[j] - float(mean[j]), 2.0) / float(n)
	for j in NF:
		sd[j] = maxf(sqrt(float(sd[j])), 1.0e-6)
	var dn := NF + 1
	var xtx: Array = []
	var xt: Array = []
	for a in dn:
		var rowa: Array = []
		for b in dn:
			rowa.append(0.0)
		xtx.append(rowa)
		xt.append(0.0)
	var row: Array = []
	row.resize(dn)
	for p in pairs:
		for j in NF:
			row[j] = ((p[0] as PackedFloat32Array)[j] - float(mean[j])) / float(sd[j]) if FIT_ON[j] else 0.0
		row[NF] = 1.0
		for a in dn:
			xt[a] = float(xt[a]) + float(row[a]) * float(p[1])
			for b in dn:
				xtx[a][b] = float(xtx[a][b]) + float(row[a]) * float(row[b])
	for j in NF:
		xtx[j][j] = float(xtx[j][j]) + 0.03 * float(n)
	var m := {"mean": mean, "std": sd, "w": _solve(xtx, xt), "g": 1.0, "c": 0.0}
	var preds := PackedFloat32Array()
	var mx := 0.0
	var pm := 0.0
	for p in pairs:
		var q := _predict(m, p[0])
		preds.append(q)
		mx += float(p[1]) / float(n)
		pm += q / float(n)
	var se := 0.0
	var tt := 0.0
	var pp := 0.0
	var res := PackedFloat32Array()
	for i in n:
		var e := float(pairs[i][1]) - preds[i]
		res.append(absf(e))
		se += e * e
		tt += pow(float(pairs[i][1]) - mx, 2.0)
		pp += pow(preds[i] - pm, 2.0)
	m["r2"] = 1.0 - se / maxf(tt, 1.0e-9)
	m["g"] = clampf(sqrt(tt / maxf(pp, 1.0e-9)), 1.0, 2.2)          # a shrunken fit still spans the screen
	m["c"] = pm
	m["rms"] = sqrt(se / float(n))
	m["res"] = res
	m["n"] = n
	return m


## targets: [Vector2(time, x)] in the same clock as the readings, in order. Returns {ok, r2, lag, n, rms, eyes, gain} and, when it is good enough, starts using the fit.
func finish_fit(targets: Array) -> Dictionary:
	recording = false
	var rec := _rec
	_rec = []
	fit_raw = {"t0": snappedf(float(rec[0][0]), 0.001) if rec.size() > 0 else 0.0, "s": [], "d": []}
	for sm in rec:
		var fv: PackedFloat32Array = sm[1]
		(fit_raw["s"] as Array).append([snappedf(float(sm[0]) - float(fit_raw["t0"]), 0.001), snappedf(fv[0], 0.0001), snappedf(fv[1], 0.0001), snappedf(fv[3], 0.001), snappedf(fv[4], 0.001), snappedf(fv[5], 0.001)])
	for tg in targets:
		(fit_raw["d"] as Array).append([snappedf((tg as Vector2).x - float(fit_raw["t0"]), 0.001), snappedf((tg as Vector2).y, 0.01)])
	if rec.size() < 40 or targets.size() < 2:
		return {"ok": false, "n": rec.size(), "why": "few readings", "r2": 0.0}
	var best: Dictionary = {}
	var best_lag := 0.0
	var best_pairs: Array = []
	var lag := 0.0
	while lag <= 0.42:
		var pairs: Array = []
		var ti := 0
		for sm in rec:
			var t := float(sm[0]) - lag
			if t <= (targets[0] as Vector2).x or t >= (targets[targets.size() - 1] as Vector2).x:
				continue
			while ti < targets.size() - 2 and (targets[ti + 1] as Vector2).x <= t:
				ti += 1
			var a: Vector2 = targets[ti]
			var b: Vector2 = targets[ti + 1]
			pairs.append([sm[1], lerpf(a.y, b.y, clampf((t - a.x) / maxf(b.x - a.x, 1.0e-4), 0.0, 1.0))])
		var m := _ridge(pairs)
		if not m.is_empty() and (best.is_empty() or float(m["rms"]) < float(best["rms"])):
			best = m
			best_lag = lag
			best_pairs = pairs
		lag += 0.035
	if best.is_empty():
		return {"ok": false, "n": rec.size(), "why": "no fit", "r2": 0.0}
	var cut := 2.2 * float(best["rms"])
	var kept: Array = []
	var res: PackedFloat32Array = best["res"]
	for i in best_pairs.size():
		if res[i] < cut:
			kept.append(best_pairs[i])
	var m2 := _ridge(kept)
	if m2.is_empty():
		m2 = best
	m2.erase("res")
	var r2 := float(m2["r2"])
	# what did the work: the share of the fit carried by the eyes (iris, lid) and by the head and face position
	var w: Array = m2["w"]
	var we := absf(float(w[0])) + absf(float(w[1])) + absf(float(w[2]))
	var wh := absf(float(w[3])) + absf(float(w[4])) + absf(float(w[5])) + absf(float(w[6]))
	var out := {"ok": r2 > 0.3, "r2": snappedf(r2, 0.01), "lag": snappedf(best_lag, 0.01), "n": kept.size(), "rms": snappedf(float(m2["rms"]), 0.01), "eyes": snappedf(we / maxf(we + wh, 1.0e-6), 0.01), "gain": snappedf(float(m2["g"]), 0.01)}
	# how closely each reading moved with the dot on its own (correlation): the iris, the head turn, where the face is in the picture
	for cj in [[0, "c_iris"], [3, "c_head"], [5, "c_face"]]:
		var mf := 0.0
		var mt := 0.0
		for pr in kept:
			mf += (pr[0] as PackedFloat32Array)[int(cj[0])] / float(kept.size())
			mt += float(pr[1]) / float(kept.size())
		var sff := 0.0
		var stt := 0.0
		var sft := 0.0
		for pr in kept:
			var df := (pr[0] as PackedFloat32Array)[int(cj[0])] - mf
			var dt2 := float(pr[1]) - mt
			sff += df * df
			stt += dt2 * dt2
			sft += df * dt2
		out[String(cj[1])] = snappedf(sft / maxf(sqrt(sff * stt), 1.0e-9), 0.01)
		if int(cj[0]) == 0:
			out["iris_sd"] = snappedf(sqrt(sff / maxf(float(kept.size()), 1.0)), 0.0001)
	if out["ok"]:
		model = m2
		_g_init = false
		_drift = 0.0
		refit_due = false
		_g_cut = 0.45 + 0.7 * clampf(r2, 0.0, 1.0)          # a rougher fit gets a heavier filter
	return out


# --------------------------------------------------------------------------
# LEFT / MIDDLE / RIGHT. The phone camera cannot place a look on the screen to the centimetre, but it can tell three places apart: a look from the middle of the screen
# to a side moves the iris by several times the noise of the reading. So the game asks for exactly that and nothing finer.
#   learning   a dot jumps between the middle, the left and the right of the screen. For each stop the resting iris reading is the median of what came in once the eyes
#              had landed (0.45 s after the jump). That gives the reading for the middle and how far it moves for each side, plus the noise of the reading.
#   live       the median of the last three readings (one stray reading cannot flip it), measured from the middle, as a fraction of the way to the side target.
#              Past half way = that side; back inside 0.3 = the middle. Nothing is smoothed over time, so a look registers within two camera frames.
#   drift      a re-gripped phone moves the resting place slowly, a look moves it at once. While the look is in the middle the middle follows it (3 s); a look held on a
#              side for 4 s is taken as resting on that side's target.
# Only the iris along the eye is used: the head and where the face sits in the picture are left out, so wobbling the phone does not steer.
# --------------------------------------------------------------------------
func fitted() -> bool:
	return not zones.is_empty() or not model.is_empty()


static func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	var h := b.size() >> 1
	return float(b[h]) if (b.size() & 1) == 1 else (float(b[h - 1]) + float(b[h])) * 0.5


func _zn_of(d: float) -> float:
	var dl := float(zones["dl"])
	var dr := float(zones["dr"])
	return clampf(-d / dl if d * dl > 0.0 else d / dr, -1.6, 1.6)


func _zone_step(hx: float, dt: float, t: float) -> void:
	_zh.append(hx)
	if _zh.size() > 3:
		_zh.pop_front()
	var d := _median(_zh) - float(zones["m"]) - _zdrift
	zn = _zn_of(d)
	var z := zone
	if zn > Z_IN:
		z = 1
	elif zn < -Z_IN:
		z = -1
	elif absf(zn) < Z_OUT:
		z = 0
	if zone != 0:
		_zpk = maxf(_zpk, absf(d))
	if z != zone:
		if zone != 0 and bool(zones.get("auto", false)) and _zside_s > 0.12:
			var k := "dl" if zone < 0 else "dr"
			var tgt := clampf(_zpk, 0.02, 0.14)
			var cur := absf(float(zones[k]))
			if tgt > cur * 0.7:
				zones[k] = signf(float(zones[k])) * lerpf(cur, tgt, 0.6)          # a look that reached further than assumed: that side is further; one that fell short of 70% is not taken as evidence
		_zpk = 0.0
		zone = z
		zone_t = t
		_zside_s = 0.0
	if zone == 0:
		_zdrift += d * minf(1.0, dt / 3.0)
	else:
		_zside_s += dt          # (a look held on a side is NOT taken as the resting place any more: a middle that was learned a little off would stay stuck on one side)
	# the middle follows the long-run median of the readings, so a middle that was learned badly in the first second corrects itself within seconds
	_zbuf.append(hx)
	if _zbuf.size() > 360:
		_zbuf.pop_front()
	_zbt += dt
	if _zbt >= 0.5 and _zbuf.size() >= 60 and bool(zones.get("auto", false)):
		_zbt = 0.0
		var mdn := _median(_zbuf)
		var m0 := float(zones["m"]) + _zdrift
		zones["m"] = float(zones["m"]) + (mdn - m0) * 0.35
	gaze_x = clampf(zn, -1.2, 1.2)


func begin_zones() -> void:
	_rec.clear()
	recording = true


## stops: [[time the dot jumped there, time it left, x of the dot (-, 0, +)], ...] in the clock of the readings. Returns {ok, sep, noise, dl, dr, agree, n, react} and,
## when the three places can be told apart, starts reading them.
func finish_zones(stops: Array) -> Dictionary:
	recording = false
	var rec := _rec
	_rec = []
	fit_raw = {"t0": snappedf(float(rec[0][0]), 0.001) if rec.size() > 0 else 0.0, "s": [], "d": []}
	for sm in rec:
		var fv: PackedFloat32Array = sm[1]
		(fit_raw["s"] as Array).append([snappedf(float(sm[0]) - float(fit_raw["t0"]), 0.001), snappedf(fv[0], 0.0001), snappedf(fv[1], 0.0001), snappedf(fv[3], 0.001), snappedf(fv[4], 0.001), snappedf(fv[5], 0.001)])
	for st in stops:
		(fit_raw["d"] as Array).append([snappedf(float(st[0]) - float(fit_raw["t0"]), 0.001), snappedf(float(st[2]), 0.01)])
	var meds: Array = []            # per stop: [side, median, spread]
	var grp := {-1: [], 0: [], 1: []}
	var spreads: Array = []
	for st in stops:
		var v: Array = []
		for sm in rec:
			var t := float(sm[0])
			if t >= float(st[0]) + 0.45 and t <= float(st[1]):
				v.append((sm[1] as PackedFloat32Array)[0])
		if v.size() < 4:
			continue
		var md := _median(v)
		var dev: Array = []
		for q in v:
			dev.append(absf(float(q) - md))
		var sp := _median(dev) * 1.48
		var side := int(signf(float(st[2])))
		meds.append([side, md, sp])
		(grp[side] as Array).append(md)
		spreads.append(sp)
	var out := {"ok": false, "n": rec.size(), "stops": meds.size(), "sep": 0.0, "agree": 0}
	if (grp[-1] as Array).is_empty() or (grp[0] as Array).is_empty() or (grp[1] as Array).is_empty():
		out["why"] = "few readings"
		return out
	var m := _median(grp[0])
	var dl := _median(grp[-1]) - m
	var dr := _median(grp[1]) - m
	var noise := maxf(_median(spreads), 1.0e-5)
	out["m"] = snappedf(m, 0.0001)
	out["dl"] = snappedf(dl, 0.0001)
	out["dr"] = snappedf(dr, 0.0001)
	out["noise"] = snappedf(noise, 0.0001)
	var sep := minf(absf(dl), absf(dr)) / noise
	out["sep"] = snappedf(sep, 0.1)
	if dl * dr >= 0.0:
		out["why"] = "left and right read the same way"
		return out
	# does every stop, on its own, land in the place it was shown at?
	var keep := zones
	zones = {"m": m, "dl": dl, "dr": dr, "noise": noise}
	var agree := 0
	for md in meds:
		var n := _zn_of(float(md[1]) - m)
		var got := 1 if n > Z_IN else (-1 if n < -Z_IN else 0)
		if got == int(md[0]):
			agree += 1
	out["agree"] = agree
	# how long after a jump to a side the reading got there (eyes + camera + tracker)
	var reacts: Array = []
	for st in stops:
		var side := int(signf(float(st[2])))
		if side == 0:
			continue
		for sm in rec:
			var t := float(sm[0])
			if t > float(st[0]) and t <= float(st[1]) and _zn_of((sm[1] as PackedFloat32Array)[0] - m) * float(side) > Z_IN:
				reacts.append(t - float(st[0]))
				break
	out["react"] = snappedf(_median(reacts), 0.01)
	out["ok"] = sep >= 2.0 and agree >= meds.size() - 1
	if out["ok"]:
		model = {}
		zone = 0
		zn = 0.0
		_zh.clear()
		_zdrift = 0.0
		_zside_s = 0.0
		refit_due = false
	else:
		zones = keep
		out["why"] = "too close to the noise" if sep < 2.0 else "stops disagree"
	return out
