class_name RunRig
extends DownhillRig
## DOWNHILL: free carving down an open slope. No lanes, no gates, no markers: the course is natural (tree lines, boulder bands, scattered
## trees and rocks) with openings you read and aim for. Reach the finish line without wiping out.
##
##   steering   continuous, from where you look (the iris inside the eye, see DownhillRig._eyes_only_offs): a look aside carves that way,
##              a look back to the middle straightens. Keys A / D, a lean (no camera) and the mouse stand in.
##   aim assist look at an opening and keep looking for a moment (AIM_LINGER): it latches, and the board is gently pulled through it.
##              Look somewhere else and it lets go. After you pass it, the next opening is yours to choose.
##   speed      the hill pulls harder the further you go (steeper slope, less drag), so the run keeps getting faster.
##              Carving costs speed, a tuck (chin down) saves it.
##
## It reuses the DownhillRig terrain, trees, rocks, camera, pause monitor and gaze pipeline; only the course, the physics, the HUD and
## the scoring are different. lane_ctl stays at 2 (STEER) so the base gaze tick produces _steer_gaze and the reticle position.

const FINISH_Z := -4200.0
const PULL_RAMP := 3500.0            # metres until the hill is at full pull
const AIM_LINGER := 0.22             # seconds your eyes must stay on an opening before it latches
const AIM_MIN_DIST := 14.0
const AIM_MAX_DIST := 125.0
const START_CALM := 2                # the first segments are open snow
const MIN_SPEED := 14.0

var carve_assist: float = 1.0        # how hard a latched opening pulls the board: it is the main control, the raw look only trims
var aim_enabled: bool = true         # tests: switch the opening choice off to check the raw look-trim alone
var _aim_cx: float = -1.0           # your look, smoothed over ~0.2 s, for choosing an opening (the raw cursor jitters by several percent of the screen)
var autopilot: bool = false          # tests: steer toward the safe opening of the next barrier
var _aim: Dictionary = {}
var _aim_row: Dictionary = {}
var _cand: Dictionary = {}
var _cand_t: float = 0.0
var _aim_w: float = 0.0
var _aim_want: float = 0.0
var _finished: bool = false
var _end_t: float = 0.0
var _run_t: float = 0.0
var _run_seed: int = 424242
var _best_time: float = 0.0
var _passed_ok: int = 0
var _tight_n: int = 0
var _clean: bool = true
var _last_rz: float = 0.0


func setup(p_player: PlayerController) -> void:
	lane_ctl = 2
	lane_mode = true
	super.setup(p_player)
	name = "RunRig"
	_load_view_pref()
	_zone_scale = 1.8                    # the trim from the raw look is looser: full lock at about +-19% of the screen, not +-10%
	_toast("Look where you want to go", Color(0.9, 0.95, 1.0))
	if OS.has_feature("web"):
		_tr_auto = bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).has('trace')"))
		var rsq := str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('rs') || ''"))
		if rsq == "auto":
			_rs_off = false
		elif rsq != "":
			_rs_pin = clampf(float(rsq), 0.3, 1.0)
			_rs = _rs_pin
			get_viewport().scaling_3d_scale = _rs


# --------------------------------------------------------------------------
# Terrain: the base slope, getting steeper with distance
# --------------------------------------------------------------------------
func terrain_h(x: float, z: float) -> float:
	var u := maxf(-z, 0.0)
	var h := z * SLOPE - 0.00002 * u * u
	h += 0.9 * sin(z * 0.031 + 1.3) * cos(x * 0.045) + 0.5 * sin(z * 0.011 - x * 0.02)          # swells, much gentler than the lane game's: a bump must never launch you by accident
	h += 0.6 * sin(z * 0.045 + x * 0.025 + 0.7) * sin(x * 0.03 - z * 0.02)
	var ax := absf(x) - W_HALF
	if ax > 0.0:
		h += 0.0085 * ax * ax
	for k in _kickers:
		var kz: float = k["z"]
		if z > kz + 1.0 or z < kz - float(k["len"]) - 1.0:
			continue
		var uu := (kz - z) / float(k["len"])
		if uu < 0.0 or uu >= 1.0:
			continue
		var half: float = float(k["w"]) * 0.5
		var lat := 1.0 - smoothstep(half - 2.0, half, absf(x - float(k["x"])))
		h += float(k["rise"]) * uu * lat
	return h


func _course_diff(z0: float) -> float:
	return clampf(0.12 + (-z0) / absf(FINISH_Z) * 0.88, 0.0, 1.0)


func progress() -> float:
	return clampf(-spos.z / absf(FINISH_Z), 0.0, 1.0)


# --------------------------------------------------------------------------
# Course: every segment has a barrier (a line of trees / boulders with openings) at a random depth, and scattered singles in between.
# The safe opening drifts by at most about 36 m from one barrier to the next, so it is always reachable with a carve.
# --------------------------------------------------------------------------
func _gen_segment(j: int) -> void:
	var z0 := -ROW_GAP * float(j)
	var d := _course_diff(z0)
	var post_air := _force_far_next
	var rz := z0 - _rng.randf_range(50.0, 60.0) if _force_far_next else z0 - _rng.randf_range(26.0, 60.0)
	_force_far_next = false
	# now and then a segment has no barrier at all: an air segment, with an epic kicker at the top and room to land
	var air_seg := j > START_CALM and not _last_air and rz > FINISH_Z + 260.0 and (j == 3 or _rng.randf() < 0.2)
	_last_air = air_seg
	var has_row := j >= START_CALM and rz > FINISH_Z + 40.0 and not air_seg
	var row: Dictionary = {"j": j, "z": rz, "z0": z0, "gaps": [], "obs": PackedFloat32Array(), "banks": [], "nodes": [],
		"passed": false, "crash": false, "has_row": has_row, "buffs": [], "pads": [], "layout": "none"}
	var cones: Array[Transform3D] = []
	var cone_cols := PackedColorArray()
	var trunks: Array[Transform3D] = []
	var trunk_cols := PackedColorArray()
	var rocks: Array[Transform3D] = []
	var rock_cols := PackedColorArray()
	var obs: PackedFloat32Array = row["obs"]
	var prev_x := _good_x
	var prev_rz := _last_rz
	if has_row:
		var shift := clampf((_last_rz - rz) * 0.30, 8.0, 14.0 if post_air else 36.0)          # after a jump you land close to where you left the line: the next gate is not far off it          # the safe opening moves at most a third of the distance since the last barrier: always reachable
		_last_rz = rz
		_good_x = clampf(_good_x + _rng.randf_range(-1.0, 1.0) * shift * (0.6 + 0.4 * d), -42.0, 42.0)
		var gaps: Array = row["gaps"]
		var g0 := _mk_gap(_good_x, lerpf(17.0, 10.0, d) * _rng.randf_range(0.92, 1.1), "open", true)
		g0["lane"] = -1
		gaps.append(g0)
		g0["iso"] = false
		_layout_gaps(row, gaps, d, prev_x, prev_rz, rz)
		# the barrier: a line of trees, a boulder band or a mix, two staggered rows, skipping the openings
		var style := _rng.randi() % 3
		var p_rock: float = [0.12, 0.8, 0.4][style]
		for line in 2:
			var lz := rz - 2.9 * float(line)
			var k := 0
			while true:
				var x := -W_HALF + (float(k) + 0.5 * float(line)) * 3.7 + _rng.randf_range(-0.4, 0.4)
				k += 1
				if x > W_HALF:
					break
				var inside := false
				for g in gaps:
					if absf(x - float(g["x"])) < float(g["w"]) * 0.5 + 1.6:
						inside = true
				if inside:
					continue
				if _rng.randf() < p_rock:
					_add_rock(rocks, rock_cols, obs, x, lz + _rng.randf_range(-0.6, 0.6), _rng.randf_range(1.1, 1.7), Color(0.55, 0.58, 0.64), _rng.randf_range(0.9, 1.4))
				else:
					_add_tree(cones, cone_cols, trunks, trunk_cols, obs, x, lz + _rng.randf_range(-0.6, 0.6), _rng.randf_range(0.8, 1.25), true)
	row["px"] = prev_x
	row["pz"] = prev_rz
	# scattered singles between this barrier and the one before it; the straight line from the last safe opening to this one stays clear
	if has_row:
		var n_single := int(minf(prev_rz - rz, ROW_GAP * 1.3) / ROW_GAP * (2.5 + 4.0 * d)) + 1          # after an air segment the span is long: no more singles than a normal one has
		for i in n_single:
			var sz := _rng.randf_range(rz + 9.0, minf(prev_rz - 9.0, -30.0))
			var sx := _rng.randf_range(-W_HALF + 3.0, W_HALF - 3.0)
			if absf(sx - path_x(row, sz)) < 9.0:
				continue
			var in_air_zone := false
			for az in _air_zones:
				if sz < float(az["z0"]) and sz > float(az["z1"]) and absf(sx - float(az["x"])) < 16.0:
					in_air_zone = true
			if in_air_zone:
				continue
			if _rng.randf() < 0.35:
				_add_rock(rocks, rock_cols, obs, sx, sz, _rng.randf_range(1.0, 1.6), Color(0.55, 0.58, 0.64), _rng.randf_range(0.9, 1.3))
			else:
				_add_tree(cones, cone_cols, trunks, trunk_cols, obs, sx, sz, _rng.randf_range(0.8, 1.3), true)
	_place_kicker(row, obs, prev_rz, rz, z0, has_row, j, air_seg)
	if has_row:
		_place_buffs(row, d, prev_rz, rz)
	# forest and boulders on both sides (visual only)
	for side in [-1.0, 1.0]:
		for i in 22:
			var fx: float = float(side) * (W_HALF + 2.5 + _rng.randf_range(0.0, 70.0))
			_add_tree(cones, cone_cols, trunks, trunk_cols, PackedFloat32Array(), fx, z0 - _rng.randf_range(0.0, ROW_GAP), _rng.randf_range(0.9, 1.6), false)
	for side2 in [-1.0, 1.0]:
		for ci in 2:
			var cxx: float = float(side2) * (W_HALF + _rng.randf_range(8.0, 36.0))
			_add_rock(rocks, rock_cols, PackedFloat32Array(), cxx, z0 - _rng.randf_range(0.0, ROW_GAP), _rng.randf_range(7.0, 14.0), Color.WHITE, _rng.randf_range(0.9, 1.5), false)
	var zlo := 1.0e9
	var zhi := -1.0e9
	var oi := 0
	while oi < obs.size():
		zlo = minf(zlo, obs[oi + 1])
		zhi = maxf(zhi, obs[oi + 1])
		oi += 4
	row["zmin"] = zlo - 4.0
	row["zmax"] = zhi + 4.0
	_add_mm(row, _m_shadow, _sh_xf, _sh_col, _m_shadow_mat)
	_sh_xf.clear()
	_sh_col = PackedColorArray()
	_add_mm(row, _m_cone, cones, cone_cols)
	_add_mm(row, _m_trunk, trunks, trunk_cols)
	_add_mm(row, _m_rock, rocks, rock_cols)
	if z0 > FINISH_Z and z0 - ROW_GAP <= FINISH_Z:
		_make_finish(row)
	_rows[j] = row
	_chunks[j] = _build_chunk(j)


## The finish: two tall posts and a chequered bar across the whole run.
func _make_finish(row: Dictionary) -> void:
	var red := _flat_mat(Color(0.92, 0.18, 0.15))
	for sx in [-1.0, 1.0]:
		var px: float = float(sx) * 24.0
		var post := MeshInstance3D.new()
		post.mesh = _m_post
		post.material_override = red
		post.scale = Vector3(2.4, 2.4, 2.4)
		add_child(post)
		post.global_position = Vector3(px, terrain_h(px, FINISH_Z) + 6.0, FINISH_Z)
		(row["nodes"] as Array).append(post)
	for i in 12:
		var bx := -22.0 + 4.0 * float(i)
		var seg := MeshInstance3D.new()
		seg.mesh = _m_bar
		seg.scale = Vector3(4.0, 1.8, 0.8)
		seg.material_override = _flat_mat(Color(0.97, 0.97, 1.0) if i % 2 == 0 else Color(0.12, 0.12, 0.16))
		add_child(seg)
		seg.global_position = Vector3(bx, terrain_h(bx, FINISH_Z) + 12.4, FINISH_Z)
		(row["nodes"] as Array).append(seg)


# --------------------------------------------------------------------------
# Gate layouts: a barrier is one of several shapes, so reading the slope pays off.
#   scatter  the safe gate plus 0-2 gates at random places (the original)
#   pair     two gates a carve apart
#   trio     three gates evenly spaced across the slope
#   decoy    the safe gate plus one isolated, narrower gate far to the side that carries a better buff
# The safe gate never moves faster than a carve can follow; an isolated gate is only placed where it can be reached from the last barrier.
# --------------------------------------------------------------------------
func _gate_w(d: float) -> float:
	return lerpf(15.0, 9.0, d) * _rng.randf_range(0.92, 1.1)


func _add_gate(gaps: Array, x: float, w: float, iso: bool) -> void:
	var ge := _mk_gap(x, w, "open", false)
	ge["lane"] = -1
	ge["iso"] = iso
	gaps.append(ge)


func _layout_gaps(row: Dictionary, gaps: Array, d: float, prev_x: float, prev_rz: float, rz: float) -> void:
	var gx := _good_x
	var roll := _rng.randf()
	var layout := "scatter"
	if roll >= 0.26:
		layout = "pair" if roll < 0.48 else ("trio" if roll < 0.74 else "decoy")
	if layout == "trio":
		var sp := _rng.randf_range(27.0, 32.0)
		# evenly spaced, with the safe gate at either end or in the middle, whichever keeps all three on the slope
		var steps: Array = [-1.0, 1.0]
		if gx + sp > 46.0:
			steps = [-1.0, -2.0]
		elif gx - sp < -46.0:
			steps = [1.0, 2.0]
		for sg in steps:
			var ex: float = gx + float(sg) * sp
			if absf(ex) <= 46.0:
				_add_gate(gaps, ex, _gate_w(d), false)
		if gaps.size() < 3:
			layout = "pair"
	if layout == "pair" and gaps.size() < 2:
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var ex2 := gx + side * _rng.randf_range(24.0, 30.0)
		if absf(ex2) > 46.0:
			ex2 = gx - side * _rng.randf_range(24.0, 30.0)
		if absf(ex2) <= 46.0:
			_add_gate(gaps, ex2, _gate_w(d), false)
		else:
			layout = "scatter"
	if layout == "decoy":
		var pref := 1.0 if prev_x >= gx else -1.0              # off toward where you came from: far from the safe gate, still within a carve's reach
		if absf(prev_x - gx) < 6.0 and _rng.randf() < 0.5:
			pref = -pref
		var placed := false
		for sd in [pref, -pref]:
			var ex3 := clampf(gx + float(sd) * _rng.randf_range(26.0, 34.0), -46.0, 46.0)
			if absf(ex3 - gx) >= 24.0 and absf(ex3 - prev_x) <= 0.33 * (prev_rz - rz):
				_add_gate(gaps, ex3, lerpf(13.0, 8.0, d) * _rng.randf_range(0.92, 1.1), true)
				placed = true
				break
		if not placed:
			layout = "scatter"
	if layout == "scatter":
		var extra := (1 if _rng.randf() < 0.55 + 0.3 * d else 0) + (1 if d > 0.5 and _rng.randf() < 0.5 else 0)
		for e in extra:
			for attempt in 10:
				var ex4 := _rng.randf_range(-46.0, 46.0)
				var ew := _gate_w(d)
				var ok := true
				for g in gaps:
					if absf(ex4 - float(g["x"])) < (float(g["w"]) + ew) * 0.5 + 9.0:
						ok = false
				if ok:
					_add_gate(gaps, ex4, ew, false)
					break
	row["layout"] = layout


# --------------------------------------------------------------------------
# Buffs: the things worth looking at.
#   boost   a burst of speed and less drag for a few seconds (faster is harder to steer)
#   shield  absorbs the next crash
#   mult    double points for 10 s
# They sit in two kinds of place: in front of an opening (always the isolated one, sometimes the others), on a short lead-in trail of
# small orbs; and out beside the safe line between two barriers, on a curved trail, so you have to want it and look there.
# Look at one for a moment and the board leans toward it (like an opening); the avoidance still keeps you off the trees.
# --------------------------------------------------------------------------
const BOOST_S := 3.0
const MULT_S := 10.0
const SPEED_CAP := 57.0              # a boost never pushes you past this (the hill alone reaches about 51 m/s)
const BUFF_COL := {"boost": Color(1.0, 0.55, 0.1), "shield": Color(0.3, 0.85, 1.0), "mult": Color(0.95, 0.4, 1.0), "donut": Color(1.0, 0.45, 0.7), "orb": Color(1.0, 0.9, 0.45)}

var shield: int = 0
var _boost_t: float = 0.0
var _mult_t: float = 0.0
var buffs_spawned: int = 0
var buffs_got: int = 0
var buff_log: Dictionary = {}
var spawned_kind: Dictionary = {}
var got_kind: Dictionary = {}
var orbs_got: int = 0
var _buff_tgt: Dictionary = {}
var _buff_cand: Dictionary = {}
var _buff_cand_t: float = 0.0
var _buff_w: float = 0.0
var _buff_want: float = 0.0
var _buff_assist: bool = true
var _buff_mesh: Dictionary = {}
var _buff_mat: Dictionary = {}


func _pick_buff(iso: bool) -> String:
	var r := _rng.randf()
	if iso:
		return "mult" if r < 0.3 else ("shield" if r < 0.65 else ("boost" if r < 0.85 else "donut"))
	return "boost" if r < 0.3 else ("shield" if r < 0.52 else ("mult" if r < 0.8 else "donut"))


func _clear_of_obs(obs: PackedFloat32Array, x: float, z: float, m: float) -> bool:
	var i := 0
	while i < obs.size():
		var dx := obs[i] - x
		var dz := obs[i + 1] - z
		var rr := obs[i + 2] + m
		if dx * dx + dz * dz < rr * rr:
			return false
		i += 4
	return true


var _glow_tex: GradientTexture2D
var _fxm: Dictionary = {}


func _glow_texture() -> GradientTexture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0.0)])
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 128
		_glow_tex.height = 128
	return _glow_tex


## Shared materials: "solid" glowing colour, "add" additive translucent, "halo" soft billboard glow, "spark" particle colour from vertex colours.
func _fx_mat(kind: String, col: Color, energy: float = 1.8) -> StandardMaterial3D:
	var key := "%s_%s_%.1f" % [kind, col.to_html(true), energy]
	if _fxm.has(key):
		return _fxm[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	if kind == "solid":
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = energy
	else:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if kind == "halo":
			m.albedo_texture = _glow_texture()
			m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		elif kind == "ground":
			m.albedo_texture = _glow_texture()
		elif kind == "spark":
			m.vertex_color_use_as_albedo = true
	_fxm[key] = m
	return m


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(n)
	n.position = pos
	return n


func _cone(r: float, h: float, down: bool = false) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 6
	c.rings = 1
	var n := MeshInstance3D.new()
	n.mesh = c
	if down:
		n.rotation.x = PI
	return n


func _torus(inner: float, outer: float) -> TorusMesh:
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 20
	tm.ring_segments = 8
	return tm


## A small cloud of sparkles that stays around an item (turned on only when it is close, so far ones cost nothing).
func _sparkler(parent: Node3D, col: Color, radius: float, n: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	sm.radial_segments = 5
	sm.rings = 2
	p.mesh = sm
	p.material_override = _fx_mat("spark", Color(1, 1, 1, 1))
	p.amount = n
	p.lifetime = 1.3
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.5
	p.color = col
	var cr := Gradient.new()
	cr.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	cr.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.color_ramp = cr
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


## One pickup, built from simple shapes but lit like a treat: a spinning gem, a soft halo, a pool of light on the snow and a few sparkles.
##   boost   orange double-cone crystal with a white-hot core and orbiting sparks
##   shield  two crossed cyan rings round a glass bubble
##   mult    a magenta-gold gem with a floating x2
func _food_mat(col: Color, glow: float = 0.35) -> StandardMaterial3D:
	var key := "food_%s_%.2f" % [col.to_html(false), glow]
	if _fxm.has(key):
		return _fxm[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.5
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = glow
	_fxm[key] = m
	return m


func _fm(parent: Node3D, mesh: Mesh, col: Color, pos: Vector3, sc: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var n := _mi(parent, mesh, _food_mat(col), pos)
	n.scale = sc
	return n


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 16
	c.rings = 1
	return c


## One pickup, built from simple shapes and lit like a treat. Everything edible is eaten by opening your eyes wide.
##   boost   BURGER      a stack of bun, patty, cheese, lettuce, tomato, sesame bun
##   shield  ICE CREAM   a waffle cone with two scoops and a cherry
##   mult    CANDY       a wrapped sweet with twisted ends
##   donut   DONUT       pink frosting and sprinkles
func _make_item(t: String) -> Dictionary:
	var col: Color = BUFF_COL[t]
	var root := Node3D.new()
	var spin := Node3D.new()
	root.add_child(spin)
	var halo := _mi(root, _quad(6.2), _fx_mat("halo", Color(col.r, col.g, col.b, 0.8)))
	var pool := _mi(root, _quad(7.0), _fx_mat("ground", Color(col.r, col.g, col.b, 0.55)), Vector3(0, -1.6, 0))
	pool.rotation.x = -PI * 0.5
	var body := Node3D.new()
	spin.add_child(body)
	body.scale = Vector3(1.3, 1.3, 1.3)
	match t:
		"boost":
			_fm(body, _sphere_mesh(1.0), Color(0.93, 0.62, 0.28), Vector3(0, -0.62, 0), Vector3(1.0, 0.42, 1.0))
			_fm(body, _cyl(1.02, 0.3), Color(0.36, 0.18, 0.09), Vector3(0, -0.22, 0))
			var ch := _fm(body, BoxMesh.new(), Color(1.0, 0.82, 0.15), Vector3(0, -0.02, 0))
			(ch.mesh as BoxMesh).size = Vector3(1.95, 0.07, 1.95)
			ch.rotation.y = 0.785
			_fm(body, _cyl(1.08, 0.1), Color(0.35, 0.8, 0.25), Vector3(0, 0.1, 0))
			_fm(body, _cyl(0.95, 0.15), Color(0.9, 0.2, 0.15), Vector3(0, 0.23, 0))
			_fm(body, _sphere_mesh(1.05), Color(0.95, 0.6, 0.22), Vector3(0, 0.42, 0), Vector3(1.0, 0.62, 1.0))
			for i in 7:
				var a := float(i) * TAU / 7.0
				_fm(body, _sphere_mesh(0.07), Color(1.0, 0.97, 0.85), Vector3(cos(a) * 0.5, 0.82 - 0.05 * float(i % 2), sin(a) * 0.5), Vector3(1.0, 0.6, 1.0))
		"shield":
			var cone := _cone(0.62, 1.6, true)
			cone.material_override = _food_mat(Color(0.86, 0.6, 0.3))
			cone.position = Vector3(0, -0.7, 0)
			body.add_child(cone)
			_fm(body, _sphere_mesh(0.7), Color(1.0, 0.55, 0.75), Vector3(0, 0.3, 0))
			_fm(body, _sphere_mesh(0.62), Color(0.8, 0.95, 1.0), Vector3(0, 0.95, 0))
			_fm(body, _sphere_mesh(0.18), Color(0.9, 0.1, 0.15), Vector3(0.05, 1.5, 0.0))
			_fm(body, _sphere_mesh(0.2), Color(1.0, 0.55, 0.75), Vector3(0.6, 0.0, 0.1), Vector3(0.8, 1.3, 0.8))
		"mult":
			_fm(body, _sphere_mesh(0.7), Color(0.95, 0.25, 0.75), Vector3.ZERO, Vector3(1.3, 0.85, 0.85))
			for sx in [-1.0, 1.0]:
				var tw := _cone(0.5, 0.9)
				tw.material_override = _food_mat(Color(1.0, 0.85, 0.25))
				tw.position = Vector3(float(sx) * 1.25, 0.0, 0.0)
				tw.rotation.z = -float(sx) * PI * 0.5
				body.add_child(tw)
			var ring := _mi(body, _torus(0.62, 0.74), _food_mat(Color(1, 1, 1), 0.5))
			ring.rotation.z = PI * 0.5
			ring.scale = Vector3(1.0, 1.0, 1.0)
		_:
			body.rotation.x = 1.0
			_fm(body, _torus(0.4, 1.0), Color(0.9, 0.65, 0.35), Vector3.ZERO)
			_fm(body, _torus(0.42, 0.96), Color(0.98, 0.4, 0.66), Vector3(0, 0.12, 0), Vector3(1.0, 0.6, 1.0))
			var sc: Array = [Color(1, 1, 0.3), Color(0.3, 0.9, 1.0), Color(1, 1, 1), Color(0.5, 1.0, 0.4)]
			for i in 12:
				var a2 := float(i) * TAU / 12.0
				var sp2 := _fm(body, BoxMesh.new(), sc[i % 4], Vector3(cos(a2) * 0.7, 0.3, sin(a2) * 0.7))
				(sp2.mesh as BoxMesh).size = Vector3(0.22, 0.06, 0.07)
				sp2.rotation.y = -a2 + float(i) * 0.9
	var sp := _sparkler(root, Color(col.r * 0.5 + 0.5, col.g * 0.5 + 0.5, col.b * 0.5 + 0.5, 1.0), 1.6, 10)
	return {"root": root, "spin": spin, "halo": halo, "sp": sp, "extra": []}


var _quad_meshes: Dictionary = {}
var _sph_meshes: Dictionary = {}


func _quad(sz: float) -> QuadMesh:
	if not _quad_meshes.has(sz):
		var q := QuadMesh.new()
		q.size = Vector2(sz, sz)
		_quad_meshes[sz] = q
	return _quad_meshes[sz]


func _sphere_mesh(r: float) -> SphereMesh:
	if not _sph_meshes.has(r):
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 12
		s.rings = 6
		_sph_meshes[r] = s
	return _sph_meshes[r]


func _buff_assets(t: String) -> void:
	if _buff_mesh.has(t):
		return
	var os := SphereMesh.new()
	os.radius = 0.5
	os.height = 1.0
	os.radial_segments = 8
	os.rings = 4
	_buff_mesh[t] = os
	var cm := CylinderMesh.new()
	cm.top_radius = 0.1
	cm.bottom_radius = 0.16
	cm.height = 9.0
	cm.radial_segments = 6
	_buff_mesh["beacon"] = cm
	for key in BUFF_COL:
		if not _buff_mat.has(key):
			var c: Color = BUFF_COL[key]
			_buff_mat[key] = _fx_mat("solid", c, 2.0)
			_buff_mat["beacon_" + str(key)] = _fx_mat("add", Color(c.r, c.g, c.b, 0.3))


func _spawn_orb(row: Dictionary, x: float, z: float, t: String) -> Node3D:
	_buff_assets("orb")
	var n := MeshInstance3D.new()
	n.mesh = _buff_mesh["orb"]
	n.material_override = _buff_mat["orb"]
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n)
	n.global_position = Vector3(x, terrain_h(x, z) + 1.3, z)
	(row["nodes"] as Array).append(n)
	return n


## A buff with a lead-in trail of small orbs (x, z pairs, ordered from far to near).
func _spawn_buff(row: Dictionary, t: String, x: float, z: float, trail: Array, kind: String, lift: float = 0.0) -> void:
	_buff_assets("orb")
	var it := _make_item(t)
	var bn: Node3D = it["root"]
	add_child(bn)
	bn.global_position = Vector3(x, terrain_h(x, z) + 1.9 + lift, z)
	(row["nodes"] as Array).append(bn)
	var bc := MeshInstance3D.new()
	bc.mesh = _buff_mesh["beacon"]
	bc.material_override = _buff_mat["beacon_" + t]
	bc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bn.add_child(bc)
	bc.position = Vector3(0.0, 5.4, 0.0)
	var orbs: Array = []
	for p in trail:
		var pv: Vector2 = p
		orbs.append({"n": _spawn_orb(row, pv.x, pv.y, "orb"), "x": pv.x, "z": pv.y, "taken": false})
	(row["buffs"] as Array).append({"t": t, "x": x, "z": z, "taken": false, "n": bn, "y": bn.position.y, "ph": _rng.randf() * TAU, "orbs": orbs, "kind": kind, "lift": lift,
		"spin": it["spin"], "halo": it["halo"], "sp": it["sp"], "extra": it["extra"]})
	buffs_spawned += 1
	spawned_kind[kind] = int(spawned_kind.get(kind, 0)) + 1


func _place_buffs(row: Dictionary, d: float, prev_rz: float, rz: float) -> void:
	var gaps: Array = row["gaps"]
	var obs: PackedFloat32Array = row["obs"]
	# in front of an opening
	for g in gaps:
		var iso: bool = g.get("iso", false)
		var p := 1.0 if iso else (0.22 if g["good"] else 0.16)
		if _rng.randf() >= p:
			continue
		var gx: float = g["x"]
		var bz := 0.0
		var bxx := gx
		var found := false
		for dzv in [12.0, 17.0, 9.0, 22.0]:
			for dxv in [0.0, 3.0, -3.0]:
				if not found and _clear_of_obs(obs, gx + dxv, rz + dzv, 4.0):
					bz = rz + dzv
					bxx = gx + dxv
					found = true
		if not found:
			continue
		var trail: Array = []
		for i in 3:
			trail.append(Vector2(gx, rz + 29.0 - 6.0 * float(i)))
		g["buff"] = true
		_spawn_buff(row, _pick_buff(iso), bxx, bz, trail, "safe" if g["good"] else "gate")
	# beside the safe line, between two barriers: you have to look there and want it
	var span := prev_rz - rz
	if span >= 80.0 and (int(row["j"]) == START_CALM or _rng.randf() < 0.5):
		for attempt in 6:
			var zb := prev_rz - span * _rng.randf_range(0.42, 0.58)          # mid-way: time to pick it out after the last barrier and to get back before the next
			var bx0 := path_x(row, zb)
			var off := _rng.randf_range(8.0, 13.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
			if absf(bx0 + off) > 42.0:
				off = -off
			var bx := bx0 + off
			if absf(bx) > 42.0 or not _clear_of_obs(obs, bx, zb, 4.5):
				continue
			var tz := zb + 26.0
			var sx := path_x(row, tz)
			var trail2: Array = []
			for i in 4:
				var u := float(i + 1) / 5.0
				var s := u * u * (3.0 - 2.0 * u)
				var px := lerpf(sx, bx, s)
				var pz := zb + 26.0 * (1.0 - u)
				if _clear_of_obs(obs, px, pz, 2.5):
					trail2.append(Vector2(px, pz))
			_spawn_buff(row, "boost" if int(row["j"]) == START_CALM else _pick_buff(false), bx, zb, trail2, "path")
			break


func _gain(pts: int) -> void:
	score += pts * (2 if _mult_t > 0.0 else 1)


func _tick_buffs(delta: float) -> void:
	_boost_t = maxf(_boost_t - delta, 0.0)
	_mult_t = maxf(_mult_t - delta, 0.0)


var _hop_t: float = 1.0
var _hop_dur: float = 0.6
var _hop_h: float = 1.0
var _hop_spin: float = 0.0
var _hop_pitch: float = 0.0
var _hop_return: bool = false
var _pop_col: Color = Color.WHITE
var _pop_a: float = 0.0
var _hud_pops: Array = []
var _bubble: MeshInstance3D
var _trail_boost: CPUParticles3D
var _trail_mult: CPUParticles3D


func _start_hop(h: float, dur: float, spin: float, pitch: float, ret: bool) -> void:
	_hop_t = 0.0
	_hop_h = h
	_hop_dur = dur
	_hop_spin = spin
	_hop_pitch = pitch
	_hop_return = ret


## An explosion of sparkles at pos. dir / spread shape it (180 = a ball), grav pulls the sparks down (negative) or floats them up.
func _burst(pos: Vector3, col: Color, n: int, speed: float, life: float, size: float, dir: Vector3 = Vector3.UP, spread: float = 180.0, grav: float = -6.0) -> void:
	var p := CPUParticles3D.new()
	p.mesh = _sphere_mesh(0.1)
	p.material_override = _fx_mat("spark", Color(1, 1, 1, 1))
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = n
	p.lifetime = life
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, grav, 0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size * 1.6
	p.color = col
	var cr := Gradient.new()
	cr.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	cr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	p.color_ramp = cr
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.4).timeout.connect(p.queue_free)


## A ring of light that expands and fades: standing (facing the camera) or flat on the snow.
func _ring(pos: Vector3, col: Color, r_end: float, dur: float, standing: bool) -> void:
	var m := MeshInstance3D.new()
	m.mesh = _torus(0.9, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(col.r, col.g, col.b, 0.95)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_position = pos
	if standing:
		m.rotation.x = PI * 0.5
	m.scale = Vector3.ONE * 0.3
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * r_end, dur).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(m.queue_free)


## What a pickup feels like, one flavour each. Everything here is visual (sparkles, light, a hop of the rider); it never changes where the board goes.
##   boost   orange fireworks + a forward streak, a nose-up pop, the field of view kicks wide
##   shield  cool blue sparkle and two shock rings, a full graceful spin in the air
##   mult    gold and magenta confetti, a half turn to face the camera and back
func _buff_pop(b: Dictionary, shown: String) -> void:
	var t: String = b["t"]
	var col: Color = BUFF_COL[t]
	var pos := Vector3(float(b["x"]), terrain_h(float(b["x"]), float(b["z"])) + 1.9, float(b["z"]))
	var fwd3 := Vector3(sin(heading), 0.25, -cos(heading))
	_pop_col = col
	_pop_a = 1.0
	_hud_pops.append({"p": pos, "col": col, "t": 0.0, "text": shown})
	match t:
		"boost":
			_burst(pos, Color(1.0, 0.6, 0.15), 70, 14.0, 0.9, 1.0)
			_burst(pos, Color(1.0, 0.95, 0.6), 36, 24.0, 0.6, 0.8, fwd3, 20.0, -2.0)
			_ring(pos, col, 7.0, 0.45, true)
			_start_hop(1.0, 0.55, 0.0, 0.5, false)
			_fov_punch = 9.0
			_shake = maxf(_shake, 0.45)
		"shield":
			_burst(pos, col, 56, 9.0, 1.0, 1.0, Vector3.UP, 180.0, -3.0)
			_burst(pos, Color(1, 1, 1), 26, 5.0, 1.2, 0.7, Vector3.UP, 180.0, 1.5)
			_ring(pos, col, 9.0, 0.6, true)
			_ring(pos + Vector3(0, -1.6, 0), col, 13.0, 0.75, false)
			_start_hop(1.35, 0.8, TAU, 0.0, false)
			_shake = maxf(_shake, 0.25)
		"donut":
			_burst(pos, Color(1.0, 0.45, 0.7), 56, 10.0, 1.2, 1.2, Vector3.UP, 180.0, -8.0)
			_burst(pos, Color(1.0, 0.95, 0.4), 30, 9.0, 1.2, 0.9, Vector3.UP, 180.0, -8.0)
			_ring(pos, col, 8.0, 0.5, true)
			_start_hop(1.0, 0.6, TAU, 0.0, false)
			_shake = maxf(_shake, 0.2)
		_:
			_burst(pos, Color(1.0, 0.85, 0.3), 56, 11.0, 1.3, 1.3, Vector3.UP, 180.0, -9.0)
			_burst(pos, Color(0.95, 0.35, 1.0), 56, 11.0, 1.3, 1.3, Vector3.UP, 180.0, -9.0)
			_ring(pos, Color(1.0, 0.85, 0.3), 8.0, 0.5, true)
			_start_hop(1.15, 0.7, PI, 0.0, true)
			_shake = maxf(_shake, 0.2)


func _ensure_fx() -> void:
	if _bubble != null or _sled == null:
		return
	_bubble = MeshInstance3D.new()
	_bubble.mesh = _sphere_mesh(1.55)
	_bubble.material_override = _fx_mat("add", Color(0.3, 0.85, 1.0, 0.2))
	_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubble.visible = false
	_sled.add_child(_bubble)
	_bubble.position = Vector3(0, 1.0, 0)
	_trail_boost = _sparkler(_sled, Color(1.0, 0.65, 0.2, 1.0), 0.35, 26)
	_trail_boost.position = Vector3(0, 0.5, 1.0)
	_trail_boost.direction = Vector3(0, 0.2, 1)
	_trail_boost.spread = 18.0
	_trail_boost.initial_velocity_min = 4.0
	_trail_boost.initial_velocity_max = 9.0
	_trail_boost.lifetime = 0.5
	_trail_boost.gravity = Vector3.ZERO
	_trail_boost.local_coords = false
	_trail_mult = _sparkler(_sled, Color(1.0, 0.85, 0.35, 1.0), 0.9, 16)
	_trail_mult.position = Vector3(0, 1.0, 0)
	_trail_mult.local_coords = false
	if _tip_pivot == null and cam != null:
		_build_tip()


func _juice(delta: float) -> void:
	_ensure_fx()
	_pop_a = maxf(_pop_a - 2.4 * delta, 0.0)
	for pp in _hud_pops:
		pp["t"] = float(pp["t"]) + delta
	while not _hud_pops.is_empty() and float(_hud_pops[0]["t"]) > 0.85:
		_hud_pops.remove_at(0)
	if _bubble != null:
		_bubble.visible = shield > 0
		if shield > 0:
			var s := 1.0 + 0.05 * sin(_age * 6.0)
			_bubble.scale = Vector3(s, s, s)
		_trail_boost.emitting = _boost_t > 0.0 and not _finished
		_trail_mult.emitting = _mult_t > 0.0 and not _finished
	if _hop_t < 1.0:
		_hop_t = minf(_hop_t + delta / _hop_dur, 1.0)
		var u := _hop_t
		var y := _hop_h * 4.0 * u * (1.0 - u)
		var spin := _hop_spin * (sin(PI * u) if _hop_return else smoothstep(0.0, 1.0, u))
		_sled.global_position.y += y
		_sled.rotate_object_local(Vector3.RIGHT, _hop_pitch * sin(PI * u))
		_sled.rotate_object_local(Vector3.UP, spin)
		var sq := 0.0
		if u > 0.82:
			sq = sin((u - 0.82) / 0.18 * PI) * 0.14
		_sled.scale = Vector3(1.0 + sq * 0.6, 1.0 - sq, 1.0 + sq * 0.6)
		_hop_vis_spin = spin
		_hop_vis_pitch = _hop_pitch * sin(PI * u)
	else:
		_hop_vis_spin = 0.0
		_hop_vis_pitch = 0.0
	_view_juice()


var _hop_vis_spin: float = 0.0
var _hop_vis_pitch: float = 0.0


func _view_juice() -> void:
	_hop_cam = (_hop_h * 4.0 * _hop_t * (1.0 - _hop_t) * 0.5) if _hop_t < 1.0 else 0.0
	var ts := _trk_spin if _in_air else _trk_vis_spin
	var tf := _trk_flip if _in_air else _trk_vis_flip
	var grabbing := _in_air and (nod_p < -0.10 or trick_grab_override or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))
	if not view_fp:
		if _in_air or absf(ts) > 0.01 or absf(tf) > 0.01:
			_sled.rotate_object_local(Vector3.RIGHT, tf + (0.3 if grabbing else 0.0))
			_sled.rotate_object_local(Vector3.UP, ts)
	_sled.visible = _sled.visible and not view_fp
	if _tip_pivot != null:
		_tip_pivot.visible = view_fp and (hurt_t <= 0.0 or int(_age * 14.0) % 2 == 0)
		if view_fp:
			# Everything eases toward where it should be, so the board seems to glide and slide on the snow instead of snapping: it lags a turn, skids a little sideways
			# when you carve hard, and hums softly with speed.
			var dt := get_process_delta_time()
			var d := wrapf(heading - atan2(_cam_look.x, -_cam_look.y), -PI, PI)
			var right := Vector2(cos(heading), sin(heading))
			var slip := vel.dot(right)
			var sp := clampf(vel.length() / 45.0, 0.0, 1.0)
			_tip_yaw = lerpf(_tip_yaw, -d, 1.0 - exp(-6.0 * dt))
			_tip_roll = lerpf(_tip_roll, -steer * 0.26, 1.0 - exp(-5.0 * dt))
			_tip_x = lerpf(_tip_x, clampf(-slip * 0.012, -0.14, 0.14), 1.0 - exp(-4.0 * dt))
			var hum := (0.008 * sin(_age * 17.0) + 0.005 * sin(_age * 29.0)) * sp if grounded else 0.0
			_tip_pivot.position = Vector3(_tip_x, -1.15 + hum - (0.1 if grabbing else 0.0), 0.0)
			_tip_pivot.rotation = Vector3(tf + _hop_vis_pitch + (0.2 if grabbing else 0.0) + 0.02 * sp, _tip_yaw + ts + _hop_vis_spin, _tip_roll)


func _process(delta: float) -> void:
	super._process(delta)
	_juice(delta)


func _take_buff(b: Dictionary) -> void:
	b["taken"] = true
	var n: Variant = b["n"]
	if is_instance_valid(n):
		(n as Node3D).visible = false
	buffs_got += 1
	var t: String = b["t"]
	buff_log[t] = int(buff_log.get(t, 0)) + 1
	var kd: String = b.get("kind", "path")
	got_kind[kd] = int(got_kind.get(kd, 0)) + 1
	var shown := "+%d" % (60 * (2 if _mult_t > 0.0 else 1))
	_gain(60)
	_flash = 0.25
	match t:
		"boost":
			_boost_t = BOOST_S
			var fwd := Vector2(sin(heading), -cos(heading))
			var sp0 := vel.length()
			vel += fwd * 6.0
			if vel.length() > maxf(SPEED_CAP, sp0):
				vel = vel.normalized() * maxf(SPEED_CAP, sp0)
			_toast("BURGER BOOST!", BUFF_COL["boost"])
			Game.sfx(&"buff_boost")
		"shield":
			shield = 1
			_toast("ICE SHIELD!", BUFF_COL["shield"])
			Game.sfx(&"buff_shield")
		"mult":
			_mult_t = MULT_S
			shown = "x2"
			_toast("SUGAR RUSH x2!", BUFF_COL["mult"])
			Game.sfx(&"buff_mult")
		"donut":
			shown = "+%d" % (220 * (2 if _mult_t > 0.0 else 1))
			_gain(160)
			_toast("DONUT!", BUFF_COL["donut"])
			Game.sfx(&"loot")
	_buff_pop(b, shown)
	if is_same(_buff_tgt, b):
		_buff_tgt = {}


func _collect_buffs() -> void:
	if _finished:
		return
	var above := spos.y - terrain_h(spos.x, spos.z)
	for k in _rows:
		var r: Dictionary = _rows[k]
		if absf(float(r["z"]) - spos.z) > 150.0:
			continue
		for b in r["buffs"]:
			for o in b["orbs"]:
				if not o["taken"] and absf(float(o["z"]) - spos.z) < 2.4 and absf(float(o["x"]) - spos.x) < 2.6 and above < 5.0:
					o["taken"] = true
					var on: Variant = o["n"]
					if is_instance_valid(on):
						(on as Node3D).visible = false
					orbs_got += 1
					_gain(int(10.0 * groove))
					if is_instance_valid(on):
						_burst((on as Node3D).global_position, BUFF_COL["orb"], 6, 5.0, 0.45, 0.6)
			if b["taken"]:
				continue
			if b.get("kind", "") == "air":
				if absf(float(b["z"]) - spos.z) < 3.8 and absf(float(b["x"]) - spos.x) < 4.2 and above > 0.8 and absf(float(b["y"]) - spos.y) < 3.6:
					_eat_or_bounce(b)
			elif absf(float(b["z"]) - spos.z) < 3.2 and absf(float(b["x"]) - spos.x) < 3.6 and above < 6.0:
				_eat_or_bounce(b)


func _animate_buffs() -> void:
	for k in _rows:
		var r: Dictionary = _rows[k]
		if absf(float(r["z"]) - spos.z) > 210.0:
			continue
		for b in r["buffs"]:
			var n: Variant = b["n"]
			if b["taken"] or not is_instance_valid(n):
				continue
			if b.get("moving", false):
				continue
			var nn := n as Node3D
			var ph := float(b["ph"])
			nn.position.y = float(b["y"]) + sin(_age * 2.4 + ph) * 0.35
			var sp: Variant = b.get("spin")
			if sp is Node3D and is_instance_valid(sp):
				(sp as Node3D).rotation.y = _age * (2.8 if b["t"] == "boost" else 1.7) + ph
			var hl: Variant = b.get("halo")
			if hl is Node3D and is_instance_valid(hl):
				var hs := 1.0 + 0.12 * sin(_age * 3.4 + ph)
				(hl as Node3D).scale = Vector3(hs, hs, hs)
			var ex: Array = b.get("extra", [])
			for ei in ex.size():
				if is_instance_valid(ex[ei]):
					var en := ex[ei] as Node3D
					if ei == 0:
						en.rotation.x = _age * 1.4 + ph
					elif ei == 1:
						en.rotation.y = _age * 1.9 + ph
					else:
						en.rotation.z = _age * 2.3 + ph
			var spk: Variant = b.get("sp")
			if spk is CPUParticles3D and is_instance_valid(spk):
				(spk as CPUParticles3D).emitting = absf(float(b["z"]) - spos.z) < 150.0
			var orbs: Array = b["orbs"]
			for oi in orbs.size():
				var o: Dictionary = orbs[oi]
				var on: Variant = o["n"]
				if not o["taken"] and is_instance_valid(on):
					var sc := 0.85 + 0.35 * maxf(sin(_age * 7.0 - float(oi) * 0.9), 0.0)         # a pulse runs along the trail toward the pickup
					(on as Node3D).scale = Vector3(sc, sc, sc)


## Looking at a buff for a moment leans the board toward it: the same dwell as an opening, with a wide look tolerance.
func _update_buff_aim(delta: float) -> void:
	var live := _eye_on and not _finished and aim_enabled and _buff_assist and not _paused and not (trace_on and _tr_phase != 3)
	if not live:
		_buff_tgt = {}
		_buff_cand = {}
		_buff_cand_t = 0.0
		_buff_w = move_toward(_buff_w, 0.0, 6.0 * delta)
		return
	var vs := get_viewport().get_visible_rect().size
	var cx := _aim_cx if _aim_cx >= 0.0 else _cursor_px.x
	var best: Dictionary = {}
	var best_d := 1.0e9
	for k in _rows:
		var r: Dictionary = _rows[k]
		for b in r["buffs"]:
			if b["taken"] or float(b.get("arm", 0.0)) > 0.0:
				continue
			var dz := spos.z - float(b["z"])
			if dz < 8.0 or dz > 95.0 or absf(float(b["x"]) - spos.x) > 0.34 * dz + 4.0:
				continue
			var wp := Vector3(float(b["x"]), terrain_h(float(b["x"]), float(b["z"])) + 1.7 + float(b.get("lift", 0.0)), float(b["z"]))
			if cam.is_position_behind(wp):
				continue
			var dd := absf(cam.unproject_position(wp).x - cx) / (0.1 * vs.x)
			if is_same(b, _buff_tgt):
				dd *= 0.7
			if dd < best_d:
				best_d = dd
				best = b
	if not best.is_empty() and best_d < 1.0:
		if is_same(best, _buff_tgt):
			_buff_cand = {}
			_buff_cand_t = 0.0
		elif is_same(best, _buff_cand):
			_buff_cand_t += delta
			if _buff_cand_t >= AIM_LINGER:
				_buff_tgt = best
				_buff_cand = {}
				_buff_cand_t = 0.0
		else:
			_buff_cand = best
			_buff_cand_t = 0.0
	else:
		_buff_cand = {}
		_buff_cand_t = 0.0
		if best_d > 1.6:
			_buff_tgt = {}
	if not _buff_tgt.is_empty() and spos.z - float(_buff_tgt["z"]) < 2.0:
		_buff_tgt = {}                                   # passed it (taken or missed)
	if _buff_tgt.is_empty():
		_buff_w = move_toward(_buff_w, 0.0, 6.0 * delta)
	else:
		_buff_w = move_toward(_buff_w, 1.0, 4.0 * delta)
		_buff_want = clampf((float(_buff_tgt["x"]) - (spos.x + vel.x * 0.45)) / 12.0, -0.9, 0.9)


# --------------------------------------------------------------------------
# Physics: the hill pulls, carving costs speed, the board turns on a short spring, momentum follows through grip
# --------------------------------------------------------------------------
## The safe line toward a barrier: straight from the safe opening of the barrier before it to the safe opening of this one.
func path_x(row: Dictionary, z: float) -> float:
	var gx := 0.0
	for g in row["gaps"]:
		if g["good"]:
			gx = float(g["x"])
	var span := float(row["pz"]) - float(row["z"])
	if span < 1.0:
		return gx
	return lerpf(float(row["px"]), gx, clampf((float(row["pz"]) - z) / span, 0.0, 1.0))


func _auto_steer() -> float:
	var best: Dictionary = {}
	for kk in _rows:
		var r: Dictionary = _rows[kk]
		if not r["has_row"] or r["passed"]:
			continue
		if best.is_empty() or float(r["z"]) > float(best["z"]):
			best = r
	if best.is_empty():
		return 0.0
	var zl := spos.z + vel.y * 0.5
	return clampf((path_x(best, zl) - (spos.x + vel.x * 0.3)) / 14.0, -0.7, 0.7)


# --------------------------------------------------------------------------
# The board looks after itself: it swerves just enough around a lone tree or rock, and it always commits to a gate in a barrier.
# The skill is choosing the right gate, in time, with your eyes. A wrong choice carries you through that gate (no crash) and you recover for the next one.
# --------------------------------------------------------------------------
const WALL_FAR := 80.0               # the barrier ahead starts pulling you into a gate this far away ...
const WALL_NEAR := 34.0              # ... and pulls with full strength from here
var avoid_enabled: bool = true
var gate_assist: bool = true
var _wall_gap: Dictionary = {}
var _wall_row_j: int = -999
var _wall_w: float = 0.0             # how hard the nearest barrier pulls (0..1), for the HUD and the report
var _swerve_s: float = 0.0           # the sideways shift the board is making right now (m)
var swerves: int = 0
var _swerving: bool = false
var _swerve_idle: float = 0.0
var wrong_gates: int = 0             # barriers passed through a gate other than the one the eyes had latched


## Smallest sideways shift (m) that clears every lone tree/rock closer than max_t seconds ahead, and the time to the nearest of them.
func _free_shift(max_t: float, sp: float, above: float, skip_wall: bool = false) -> Vector2:
	var cs := PackedFloat32Array()
	var rs := PackedFloat32Array()
	var tmin := 9.0
	var look := sp * max_t
	for jj in _rows:
		var rj: Dictionary = _rows[jj]
		if spos.z - look > float(rj["zmax"]) or spos.z + 3.0 < float(rj["zmin"]):
			continue
		var rzz := float(rj["z"]) if rj["has_row"] else 1.0e9
		var obs: PackedFloat32Array = rj["obs"]
		var i := 0
		while i < obs.size():
			var ox := obs[i]
			var oz := obs[i + 1]
			var orad := obs[i + 2]
			var okind := obs[i + 3]
			i += 4
			if skip_wall and rj["has_row"] and absf(oz - rzz) < 7.0:
				continue                                         # the long look-ahead is for lone trees and rocks; a barrier is for the gate you chose
			var dz := spos.z - oz
			if dz < -1.5 or dz > look:
				continue
			if above > (7.0 if okind < 0.5 else 3.0) + 0.5:
				continue                                         # in the air above it
			var t := maxf(dz, 0.0) / sp
			var rr := orad + SLED_R + 1.0
			var c := spos.x + vel.x * t - ox
			if absf(c) >= rr + 5.0:
				continue
			cs.append(c)
			rs.append(rr)
			if absf(c) < rr:
				tmin = minf(tmin, t)
	if tmin > 8.0:
		return Vector2(0.0, 9.0)
	var best := 1.0e9
	var cand := PackedFloat32Array([0.0])
	for k in cs.size():
		cand.append(-cs[k] - rs[k] - 0.05)
		cand.append(-cs[k] + rs[k] + 0.05)
	for s in cand:
		if absf(spos.x + s) > W_HALF - 3.0:
			continue
		var ok := true
		for k in cs.size():
			if absf(cs[k] + s) < rs[k] - 0.001:
				ok = false
				break
		if ok and absf(s) < absf(best):
			best = s
	return Vector2(0.0 if best > 1.0e8 else best, tmin)


## Returns the steering added by the avoidance and gate commitment, and nudges the board sideways at the last moment if a swerve is still owed.
func _guard_path(delta: float, s_in: float) -> float:
	_swerve_s = 0.0
	_wall_w = 0.0
	if _finished or hurt_t > 0.0:
		return 0.0
	var add := 0.0
	# 1) the barrier ahead: commit to a gate
	var row: Dictionary = {}
	var bd := 1.0e9
	for kk in _rows:
		var r: Dictionary = _rows[kk]
		if not r["has_row"]:
			continue
		var d := spos.z - float(r["z"])
		if d < -6.0 or d >= bd:
			continue
		bd = d
		row = r
	var gate_done := false
	var spd_w := maxf(-vel.y, MIN_SPEED)
	var wall_far := clampf(spd_w * 2.4, WALL_FAR, 180.0)       # the hill speeds up, so the pull starts earlier in metres, not in seconds
	var wall_near := clampf(spd_w * 1.0, WALL_NEAR, 70.0)
	if gate_assist and not row.is_empty() and bd <= wall_far:
		if int(row["j"]) != _wall_row_j:
			_wall_row_j = int(row["j"])
			_wall_gap = {}
		var tgt: Dictionary = {}
		var eyes_chose := not _aim.is_empty() and is_same(_aim_row, row)
		if eyes_chose:
			tgt = _aim
			row["eyes_gap"] = _aim                            # remembered for scoring: this is the gate YOU chose
		elif row.has("eyes_gap") and not (row["eyes_gap"] as Dictionary).is_empty():
			tgt = row["eyes_gap"]                             # your eyes let go inside the last 14 m (the tracker cannot resolve it): keep the gate you chose
		else:
			var px := spos.x + vel.x * 0.7 + s_in * 4.0
			var bd2 := 1.0e9
			for g in row["gaps"]:
				var dd := absf(float(g["x"]) - px) * (0.6 if is_same(g, _wall_gap) else 1.0)
				if dd < bd2:
					bd2 = dd
					tgt = g
			_wall_gap = tgt
		# a gate too far sideways to reach in the distance that is left cannot be flown to (the course itself never asks for more than ~0.3 m sideways per metre):
		# carry on through the reachable gate nearest to it instead
		var reach_m := 0.38 * maxf(bd - 6.0, 2.0) + 4.0
		var from_x := spos.x + vel.x * 0.3
		if absf(float(tgt["x"]) - from_x) - float(tgt["w"]) * 0.3 > reach_m:
			var alt: Dictionary = {}
			var alt_d := 1.0e9
			for g in row["gaps"]:
				if absf(float(g["x"]) - from_x) - float(g["w"]) * 0.3 > reach_m:
					continue
				var ad := absf(float(g["x"]) - float(tgt["x"]))
				if ad < alt_d:
					alt_d = ad
					alt = g
			if alt.is_empty():
				alt_d = 1.0e9
				for g in row["gaps"]:
					var ad2 := absf(float(g["x"]) - from_x)
					if ad2 < alt_d:
						alt_d = ad2
						alt = g
			tgt = alt
		var u := clampf((wall_far - bd) / (wall_far - wall_near), 0.0, 1.0)
		var w := u
		if eyes_chose:
			w = maxf(carve_assist * _assist_conf() * _aim_w, u)
		_wall_w = w
		var want := clampf((float(tgt["x"]) - (spos.x + vel.x * 0.45)) / 12.0, -0.9, 0.9)
		var yield_to_buff := _buff_w * clampf((bd - (wall_near + 8.0)) / 10.0, 0.0, 1.0)       # a buff you are looking at wins until the barrier is close
		add += w * want * (1.0 - 0.6 * absf(s_in)) * (1.0 - 0.85 * yield_to_buff)
		gate_done = true
	if not gate_done:
		add += carve_assist * _assist_conf() * _aim_w * _aim_want * (1.0 - 0.6 * absf(s_in))
	if _buff_w > 0.0 and not _buff_tgt.is_empty():
		add += _buff_w * _buff_want * (1.0 - 0.6 * absf(s_in))
	# 2) a lone tree or rock on the way: swerve by just what is needed
	var av := 0.0
	if avoid_enabled:
		var sp := maxf(-vel.y, 6.0)
		var above := spos.y - terrain_h(spos.x, spos.z)
		var far := _free_shift(clampf(95.0 / sp, 1.6, 2.4), sp, above, true)
		if absf(far.x) > 0.001:
			av = clampf(far.x / 5.0, -0.9, 0.9)
			_swerve_idle = 0.0
			if not _swerving:
				_swerving = true
				swerves += 1
			var near := _free_shift(0.55, sp, above)
			if absf(near.x) > 0.001:
				var nudge := near.x * clampf(delta / maxf(near.y, 0.1), 0.0, 1.0)
				nudge = clampf(nudge, -12.0 * delta, 12.0 * delta)
				spos.x += nudge
				_swerve_s = nudge / maxf(delta, 0.0001)
		else:
			_swerve_idle += delta
			if _swerve_idle > 0.6:
				_swerving = false
	return add + av


var _rs: float = 1.0                 # 3D render scale: the game and the face model share one GPU, so the game gives up pixels before the tracker starves
var _rs_t: float = 0.0
var _rs_pin: float = -1.0            # &rs=0.7 pins it
var _rs_off: bool = true             # the automatic governor is opt-in (&rs=auto): resizing the 3D buffer can itself hitch, and on the one laptop tested it bought nothing
var _rs_drop_fps: float = 0.0
# where a game frame goes (milliseconds, smoothed): so a slow game can be told apart from a slow tracker
var _pf_phys: float = 0.0
var _pf_hud: float = 0.0
var _pf_focus: float = 0.0


func _pf(cur: float, t0: int) -> float:
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	return ms if cur <= 0.0 else lerpf(cur, ms, 0.05)


func _render_governor(delta: float) -> void:
	if _rs_pin > 0.0 or DisplayServer.get_name() == "headless":
		return
	_rs_t += delta
	if _rs_t < 1.5:
		return
	_rs_t = 0.0
	var f := float(Engine.get_frames_per_second())
	if _rs_off:
		return
	if f < 46.0:
		if _rs_drop_fps > 0.0 and f < _rs_drop_fps * 1.12:
			# the last drop in resolution bought less than 12% more frames: the game is not pixel-bound, so stop trading looks for nothing
			_rs = 1.0
			_rs_off = true
			get_viewport().scaling_3d_scale = 1.0
			_log_ev("render scale did not raise the frame rate (%d fps): back to full" % int(f))
			return
		_rs_drop_fps = f
		_rs = maxf(_rs - 0.1, 0.5)
	elif f > 57.0:
		_rs = minf(_rs + 0.05, 1.0)
		_rs_drop_fps = 0.0
	get_viewport().scaling_3d_scale = _rs


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_scale = 1.0


func _physics_process(delta: float) -> void:
	if _paused:
		return
	var pf0 := Time.get_ticks_usec()
	_render_governor(delta)
	_age += delta
	var ns := GazeProvider.nod_state(delta)
	nod_p = ns.x
	nod_v = ns.y
	var pk := GazeProvider.peek_offset(delta)
	var key := (1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
	hurt_t = maxf(hurt_t - delta, 0.0)
	_tick_buffs(delta)
	_eye_on = _eye_mode()
	_clock += delta
	if _finished:
		_end_t += delta
	else:
		_run_t += delta
	var dist := maxf(-spos.z, 0.0)
	var prog := clampf(dist / PULL_RAMP, 0.0, 1.0)
	# steering: your gaze when the eyes are on (a head lean must not steer), else a lean, plus keys; a latched opening adds a gentle pull
	var eye_s := _guard_gaze(_steer_gaze, delta) if _eye_on else 0.0
	# A webcam gaze is a slow, noisy signal (a few percent of the screen of jitter), so the eyes CHOOSE the opening and the board carves to it; free steering from the
	# raw look only trims (0.6 with nothing chosen, 0.15 once an opening is locked).
	var eye_gain := lerpf(0.6, 0.15, _aim_w)
	var s_in := key + (eye_s * eye_gain if _eye_on else clampf(pk.x / 1.8, -1.0, 1.0))
	if autopilot:
		s_in = _auto_steer()
	s_in = clampf(s_in, -1.0, 1.0)
	steer = clampf(s_in + _guard_path(delta, s_in), -1.0, 1.0)
	if _finished:
		steer = 0.0
	_steer_s = lerpf(_steer_s, steer, 1.0 - exp(-steer_rate * delta))
	steer = _steer_s
	var tuck := nod_p < -0.10 and not _finished
	tucking = tuck and grounded
	braking = false
	gliding = false
	var theta_t := steer * THETA_MAX
	heading += (theta_t - heading) * (1.0 - exp(-delta / (0.18 if grounded else 0.35)))
	var fwd := Vector2(sin(heading), -cos(heading))
	var right := Vector2(cos(heading), sin(heading))
	var prev := spos
	var g := _grad(spos.x, spos.z)
	if grounded:
		var spd := vel.length()
		if spd < MIN_SPEED and not _finished:
			vel += fwd * (MIN_SPEED - spd) * 1.2 * delta        # never stalls: always pushes the way the board points, never along a sideways or backward slide
		vel += -G * g / (1.0 + g.length_squared()) * delta
		var sp := vel.length()
		var drag := DRAG * (0.55 if tucking else 1.0) * lerpf(1.0, 0.5, prog) * (0.3 if _boost_t > 0.0 else 1.0)          # less drag the further you go: the hill keeps pulling harder
		if _boost_t > 0.0 and spd < SPEED_CAP:
			vel += fwd * 7.0 * delta                                  # a boost pushes along where the board points
		var fr := 0.22 + (3.0 if _finished else 0.0)
		if _finished:
			vel *= exp(-1.3 * delta)
		if sp > 0.01:
			var dec := minf((fr + drag * sp * sp) * delta, sp)
			vel -= vel / sp * dec
		var old_sp := vel.length()
		var along := vel.dot(fwd)
		var lat := vel.dot(right)
		var lat_new := lat * exp(-GRIP * (0.75 if tucking else 1.0) * delta)
		along += absf(lat - lat_new) * 0.6 * signf(along if absf(along) > 0.01 else 1.0)          # a carve costs some speed
		vel = fwd * along + right * lat_new
		if vel.length() > old_sp:
			vel = vel.normalized() * old_sp
	else:
		var sp2 := vel.length()
		if sp2 > 0.01:
			vel -= vel / sp2 * minf(DRAG * 0.4 * sp2 * sp2 * delta, sp2)
		vel += right * steer * 3.0 * delta
		air_t += delta
	if not _finished:
		vel.y = minf(vel.y, -3.0)          # the hill always carries you down it: a slide off a tree can never turn into a run uphill
	spos.x += vel.x * delta
	spos.z = minf(spos.z + vel.y * delta, 0.0)
	if absf(spos.x) >= W_HALF - 2.5:
		spos.x = clampf(spos.x, -(W_HALF - 2.5), W_HALF - 2.5)
		vel.x = -vel.x * 0.2
	var gh := terrain_h(spos.x, spos.z)
	var gvy := (gh - _gh_prev) / maxf(delta, 0.0001)
	if grounded:
		var vg := (gh - prev.y) / maxf(delta, 0.0001)
		if vg < vy - G * delta - 0.4:
			grounded = false
			air_t = 0.0
			vy = vy - G * delta
			spos.y = prev.y + vy * delta
		else:
			spos.y = gh
			vy = vg
	else:
		vy -= G * delta
		spos.y += vy * delta
		if spos.y <= gh:
			_land(maxf(gvy - vy, 0.0), gh, gvy)
	_gh_prev = gh
	_collide()
	_collect_buffs()
	_update_eye_actions(delta)
	_update_pads()
	_update_ramps(delta)
	_update_balls(delta)
	_update_tricks(delta, key, pk)
	_animate_buffs()
	_update_rows()
	if not _finished and spos.z <= FINISH_Z:
		_finish()
	if int(float(_next_j) * ROW_GAP) < int(-spos.z + AHEAD):
		_gen_segment(_next_j)
		_next_j += 1
	_cleanup()
	_pf_phys = _pf(_pf_phys, pf0)


func _collide() -> void:
	if hurt_t > 0.0 or _finished:
		return
	var above := spos.y - terrain_h(spos.x, spos.z)
	for jj in _rows:
		var rj: Dictionary = _rows[jj]
		if spos.z < float(rj["zmin"]) or spos.z > float(rj["zmax"]):
			continue
		var obs: PackedFloat32Array = rj["obs"]
		var i := 0
		while i < obs.size():
			var ox := obs[i]
			var oz := obs[i + 1]
			var orad := obs[i + 2]
			var okind := obs[i + 3]
			i += 4
			var dx := spos.x - ox
			var dz := spos.z - oz
			if dx * dx + dz * dz < (orad + SLED_R) * (orad + SLED_R):
				var limit := 7.0 if okind < 0.5 else 3.0
				if above < limit:
					var v_pre := vel
					var n := Vector2(dx, dz).normalized()
					spos.x = ox + n.x * (orad + SLED_R + 0.1)
					spos.z = oz + n.y * (orad + SLED_R + 0.1)
					if grounded:
						spos.y = terrain_h(spos.x, spos.z)
						_gh_prev = spos.y
					vel = vel.slide(n) * 0.4
					var wallhit: bool = rj["has_row"] and absf(oz - float(rj["z"])) < 7.0
					_crash("TREE!" if okind < 0.5 else "ROCK!", "%s swerving %s wallPull %.2f latched %s speed %.0f sideways %.1f" % ["WALL" if wallhit else "SINGLE", str(_swerving), _wall_w, str(not _aim.is_empty()), v_pre.length(), v_pre.x])
					if wallhit:
						hurt_t = 2.2          # still inside the barrier band: enough grace to be carried out of it instead of into the next tree
					return


func _crash(msg: String, ctx: String = "") -> void:
	if hurt_t > 0.0 or _finished:
		return
	if shield > 0:
		shield = 0
		hurt_t = 0.8
		_flash = 0.35
		_shake = 0.5
		_toast("SHIELD BROKE", BUFF_COL["shield"])
		var bp := spos + Vector3(0, 1.2, 0)
		_burst(bp, BUFF_COL["shield"], 44, 12.0, 0.8, 1.0)
		_ring(bp, BUFF_COL["shield"], 8.0, 0.4, true)
		Game.sfx(&"hurt")
		return
	crashes += 1
	_clean = false
	crash_log.append("%s at z=%.0f x=%.1f v=%.1f %s" % [msg, spos.z, spos.x, vel.length(), ctx])
	hurt_t = 1.1
	vel *= 0.3
	chain = 0
	groove = 1.0
	_shake = 0.9
	_toast(msg, Color(1.0, 0.4, 0.35))
	Game.sfx(&"hurt")
	for k in _rows:
		var r: Dictionary = _rows[k]
		if absf(float(r["z"]) - spos.z) < 30.0:
			r["crash"] = true


## Scores a barrier the moment you cross it: the opening you went through, how close to its middle, and the flow chain.
func _update_rows() -> void:
	for k in _rows:
		var r: Dictionary = _rows[k]
		if not r["has_row"] or r["passed"]:
			continue
		if spos.z <= float(r["z"]):
			r["passed"] = true
			rows_passed += 1
			var chosen: Dictionary = {}
			for g in r["gaps"]:
				if absf(spos.x - float(g["x"])) <= float(g["w"]) * 0.5 + 1.2:
					chosen = g
			if chosen.is_empty() or r["crash"]:
				continue
			_passed_ok += 1
			# with the eyes on, the points are for the gate you chose with them; the board's own pick (or a wrong one) carries you through but is worth little
			var eg: Dictionary = r.get("eyes_gap", {})
			if _eye_on and gate_assist and not autopilot and not is_same(eg, chosen):
				_gain(10)
				chain = 0
				groove = 1.0
				if eg.is_empty():
					_toast("AUTO GATE", Color(0.8, 0.8, 0.85))
				else:
					wrong_gates += 1
					_toast("WRONG GATE: RECOVER", Color(1.0, 0.75, 0.3))
				continue
			var margin := clampf(1.0 - absf(spos.x - float(chosen["x"])) / (float(chosen["w"]) * 0.5), 0.0, 1.0)
			var pts := 40 + int(30.0 * margin)
			if float(chosen["w"]) < 11.5:
				pts += 30
				_tight_n += 1
				_toast("TIGHT", Color(0.4, 1.0, 0.7))
			chain += 1
			groove = 1.0 + 0.25 * minf(float(chain), 8.0)
			best_flow = maxf(best_flow, groove)
			_gain(int(float(pts) * groove))
			Game.sfx(&"coin")


func _finish() -> void:
	_finished = true
	_end_t = 0.0
	if _best_time <= 0.0 or (_clean and _run_t < _best_time):
		_best_time = _run_t
	if _clean:
		score += 1000
	Game.sfx(&"boom")
	_flash = 0.6
	_toast("FINISH!", Color(1.0, 0.9, 0.4))


func _restart() -> void:
	cleanup()
	_run_seed += 1
	_rng.seed = _run_seed
	_next_j = 0
	_good_x = 0.0
	_last_rz = 0.0
	score = 0
	chain = 0
	groove = 1.0
	crashes = 0
	best_flow = 1.0
	rows_passed = 0
	_passed_ok = 0
	_tight_n = 0
	_clean = true
	_finished = false
	_end_t = 0.0
	_run_t = 0.0
	hurt_t = 0.0
	crash_log.clear()
	spos = Vector3(0.0, terrain_h(0.0, 0.0), 0.0)
	vel = Vector2(0.0, -10.0)
	vy = vel.y * SLOPE
	heading = 0.0
	grounded = true
	steer = 0.0
	_steer_s = 0.0
	_gh_prev = spos.y
	_aim = {}
	_aim_row = {}
	_cand = {}
	_cand_t = 0.0
	_aim_w = 0.0
	swerves = 0
	wrong_gates = 0
	shield = 0
	_boost_t = 0.0
	_mult_t = 0.0
	buffs_spawned = 0
	buffs_got = 0
	buff_log = {}
	spawned_kind = {}
	got_kind = {}
	orbs_got = 0
	_buff_tgt = {}
	_buff_cand = {}
	_buff_cand_t = 0.0
	_buff_w = 0.0
	Engine.time_scale = 1.0
	_slowmo_t = 0.0
	_air_moves.clear()
	_trk_comment_t = 0.0
	ridiculous = 0
	_kickers.clear()
	_ramp_charge = 0.0
	_ramp_prev_z = 0.0
	pops_done = 0
	_air_zones.clear()
	_force_far_next = false
	_last_air = false
	air_segments = 0
	for bb in _balls:
		if is_instance_valid(bb["n"]):
			(bb["n"] as Node).queue_free()
	_balls.clear()
	_next_ball_z = -420.0
	snow_spawned = 0
	snow_braced = 0
	snow_hit = 0
	snow_dodged = 0
	foods_bounced = 0
	foods_lost = 0
	pads_hit = 0
	epics_built = 0
	_wide_last = -10.0
	_squint_last = -10.0
	_fx_rng.seed = _run_seed + 99
	kickers_built = 0
	tricks_landed = 0
	trick_score = 0
	best_trick = ""
	_in_air = false
	_trk_spin = 0.0
	_trk_flip = 0.0
	_trk_flip_goal = 0.0
	_trk_vis_spin = 0.0
	_trk_vis_flip = 0.0
	_trk_text_t = 0.0
	_hop_t = 1.0
	_pop_a = 0.0
	_hud_pops.clear()
	_swerving = false
	_wall_gap = {}
	_wall_row_j = -999
	while float(_next_j) * ROW_GAP < AHEAD:
		_gen_segment(_next_j)
		_next_j += 1
	_place_camera(1.0, true)
	_toast("Look where you want to go", Color(0.9, 0.95, 1.0))


# --------------------------------------------------------------------------
# Eyes as buttons. LOOK steers and chooses. OPEN WIDE (or hold SPACE) eats a food as you reach it. SQUINT (or hold SHIFT) braces against a snowball.
# A food you drive past without eating it bounces away like rubber, once, and waits for a second try; miss that and it pops.
# Opening wide a moment early counts (0.5 s), because the tracker is a little late.
# --------------------------------------------------------------------------
const FOOD_NAME := {"boost": "BURGER", "shield": "ICE CREAM", "mult": "CANDY", "donut": "DONUT"}
var wide_override: bool = false
var squint_override: bool = false
var eat_enabled: bool = false              # false (the default): every pickup is taken by touching it. true: you must open your eyes wide to eat (experimental, needs a reliable tracker)
var foods_bounced: int = 0
var foods_lost: int = 0
var _wide_last: float = -10.0
var _squint_last: float = -10.0
var _squinting_now: bool = false
var _squint_vis: float = 0.0
var _eat_hint: bool = false
var _fx_rng := RandomNumberGenerator.new()


func _wide_now() -> bool:
	return wide_override or Input.is_key_pressed(KEY_SPACE) or (_eye_on and GazeProvider.wide_held())


func _squint_now() -> bool:
	return squint_override or Input.is_key_pressed(KEY_SHIFT) or (_eye_on and GazeProvider.squint_held())


func _can_eat() -> bool:
	return (not eat_enabled) or wide_override or _age - _wide_last < 0.5


func _braced() -> bool:
	return squint_override or _age - _squint_last < 0.45


func _update_eye_actions(delta: float) -> void:
	if _wide_now():
		_wide_last = _age
	var sq := _squint_now()
	var tk := nod_p < -0.10                                              # ducking your chin braces too: it is the one signal that is always reliable
	_squinting_now = (sq or tk) and not _balls.is_empty()               # only means something while a snowball is about: a stray one costs nothing
	if _squinting_now:
		_squint_last = _age
		if sq and grounded and not _finished:
			vel *= 1.0 - 0.12 * delta                 # squinting costs speed: you are hunched up and half blind


func _eat_or_bounce(b: Dictionary) -> void:
	if float(b.get("arm", 0.0)) > 0.0:
		return
	if _can_eat():
		_take_buff(b)
	else:
		_bounce_food(b)


func _food_pos(b: Dictionary) -> Vector3:
	var n: Variant = b["n"]
	if is_instance_valid(n):
		return (n as Node3D).global_position
	return Vector3(float(b["x"]), terrain_h(float(b["x"]), float(b["z"])) + 1.9, float(b["z"]))


func _bounce_food(b: Dictionary) -> void:
	var n: Variant = b["n"]
	var col: Color = BUFF_COL[b["t"]]
	var p0 := _food_pos(b)
	if b.get("bounced", false):
		b["taken"] = true
		foods_lost += 1
		if is_instance_valid(n):
			(n as Node3D).visible = false
		_burst(p0, col, 34, 7.0, 0.7, 0.9)
		Game.sfx(&"squeak")
		return
	b["bounced"] = true
	foods_bounced += 1
	var nx := clampf(spos.x + vel.x * 0.25 + _fx_rng.randf_range(-7.0, 7.0), -40.0, 40.0)
	var nz := spos.z - 32.0 - _fx_rng.randf_range(0.0, 12.0)
	var ny := terrain_h(nx, nz) + 1.9
	b["x"] = nx
	b["z"] = nz
	b["arm"] = 0.8
	b["moving"] = true
	b["lift"] = 0.0
	b["kind"] = "bounced"
	_burst(p0, col, 18, 6.0, 0.5, 0.7)
	Game.sfx(&"boing")
	if is_instance_valid(n):
		var nn := n as Node3D
		var s0 := nn.global_position
		var tw := create_tween()
		tw.tween_method(func(u: float) -> void:
			if is_instance_valid(nn):
				nn.global_position = Vector3(lerpf(s0.x, nx, u), lerpf(s0.y, ny, u) + sin(PI * u) * 9.0, lerpf(s0.z, nz, u)), 0.0, 1.0, 0.8)
		tw.tween_callback(func() -> void:
			b["arm"] = 0.0
			b["moving"] = false
			b["y"] = ny)
	else:
		b["arm"] = 0.0
		b["moving"] = false


# --------------------------------------------------------------------------
# Snowballs: one rolls in from the side now and then, aimed at where you will be in about 2.6 s. Three ways through:
#   carve away   steer out of its line (or behind it)       no cost
#   outrun it    be across its line first (a burger helps)  no cost
#   squint       brace: it shatters on you                  a little speed, no shove, the chain keeps; and you are blind and slow while you squint
# Do nothing and it hits: 40% of your speed gone, a shove the way it was rolling, your flow chain reset. An ice cream shield absorbs it too.
# --------------------------------------------------------------------------
const BALL_R := 3.0
var balls_enabled: bool = true
var _balls: Array = []
var _next_ball_z: float = -420.0
var snow_spawned: int = 0
var snow_braced: int = 0
var snow_hit: int = 0
var snow_dodged: int = 0
var _ball_hint: bool = false


func _spawn_ball() -> void:
	var d := _course_diff(spos.z)
	var T := 2.6
	var sp := maxf(-vel.y, 24.0)
	var px := clampf(spos.x + vel.x * T, -38.0, 38.0)
	var pz := spos.z - sp * T
	var vb := 12.0 + 6.0 * d
	var side := 1.0 if px < 0.0 else -1.0
	var sx := clampf(px + side * 44.0, -(W_HALF - 4.0), W_HALF - 4.0)
	var sz := pz + vb * T
	var vx := (px - sx) / T
	var n := Node3D.new()
	_mi(n, _sphere_mesh(BALL_R), _fx_mat("solid", Color(0.95, 0.97, 1.0), 0.9))
	for i in 5:
		var a := float(i) * 1.7
		_mi(n, _sphere_mesh(1.1), _fx_mat("solid", Color(0.88, 0.93, 1.0), 0.8), Vector3(cos(a), sin(a * 1.3), sin(a)) * 2.4)
	add_child(n)
	n.global_position = Vector3(sx, terrain_h(sx, sz) + BALL_R, sz)
	_balls.append({"n": n, "x": sx, "z": sz, "vx": vx, "vz": -vb, "t": 0.0, "done": false})
	snow_spawned += 1
	_next_ball_z = spos.z - _fx_rng.randf_range(150.0, 230.0) * lerpf(1.0, 0.7, d)
	_toast("SNOWBALL!", Color(0.85, 0.95, 1.0))
	Game.sfx(&"whoosh")
	if not _ball_hint:
		_ball_hint = true
		_toast("Carve away, outrun it, or duck your chin / squint to brace", Color(0.85, 0.95, 1.0))


func _update_balls(delta: float) -> void:
	if balls_enabled and not _finished and _balls.is_empty() and spos.z < _next_ball_z and spos.z > FINISH_Z + 260.0:
		_spawn_ball()
	for i in range(_balls.size() - 1, -1, -1):
		var b: Dictionary = _balls[i]
		b["t"] = float(b["t"]) + delta
		b["x"] = float(b["x"]) + float(b["vx"]) * delta
		b["z"] = float(b["z"]) + float(b["vz"]) * delta
		var n: Variant = b["n"]
		var bx := float(b["x"])
		var bz := float(b["z"])
		if float(b["t"]) < 0.9 and float(b["vx"]) != 0.0:
			# the first moments: keep the roll timed to where you will be (the hill speeds you up more than a guess can say). After that it is fixed, so a late boost or a sidestep still beats it.
			var tl := absf((spos.x + vel.x * 1.5 - bx) / float(b["vx"]))
			tl = clampf(tl, 0.6, 4.0)
			var want_vz := (spos.z + vel.y * tl - bz) / tl
			b["vz"] = lerpf(float(b["vz"]), clampf(want_vz, -34.0, -8.0), 0.15)
		if is_instance_valid(n):
			var nn := n as Node3D
			nn.global_position = Vector3(bx, terrain_h(bx, bz) + BALL_R, bz)
			nn.rotate_x(float(b["vz"]) * delta / BALL_R)
			nn.rotate_z(-float(b["vx"]) * delta / BALL_R)
		if not b["done"]:
			var dx := spos.x - bx
			var dz := spos.z - bz
			var above := spos.y - terrain_h(spos.x, spos.z)
			if dx * dx + dz * dz < (BALL_R + 1.1) * (BALL_R + 1.1) and above < BALL_R + 1.0:
				_ball_hit(b)
			elif bz > spos.z + 6.0:
				b["done"] = true
				snow_dodged += 1
				_gain(60)
				_toast("DODGED", Color(0.7, 1.0, 0.8))
		if bz > spos.z + 70.0 or float(b["t"]) > 14.0 or b.get("gone", false):
			if is_instance_valid(n):
				(n as Node).queue_free()
			_balls.remove_at(i)


func _ball_hit(b: Dictionary) -> void:
	b["done"] = true
	var pos := Vector3(float(b["x"]), terrain_h(float(b["x"]), float(b["z"])) + BALL_R, float(b["z"]))
	if _braced():
		snow_braced += 1
		vel *= 0.9
		_gain(80)
		_toast("BRACED!", Color(0.6, 0.9, 1.0))
		_shake = maxf(_shake, 0.5)
		_flash = 0.3
	elif shield > 0:
		shield = 0
		_toast("ICE SHIELD TOOK IT", BUFF_COL["shield"])
		_shake = maxf(_shake, 0.5)
		_flash = 0.3
	else:
		snow_hit += 1
		vel *= 0.6
		vel.x += signf(float(b["vx"])) * 9.0
		hurt_t = maxf(hurt_t, 0.5)
		chain = 0
		groove = 1.0
		_shake = 0.9
		_flash = 0.5
		_toast("SNOWBALL HIT", Color(1.0, 0.5, 0.4))
	_burst(pos, Color(0.95, 0.98, 1.0), 90, 15.0, 1.0, 2.2, Vector3.UP, 180.0, -9.0)
	_ring(pos, Color(0.85, 0.95, 1.0), 10.0, 0.5, true)
	Game.sfx(&"boom")
	var n: Variant = b["n"]
	if is_instance_valid(n):
		(n as Node3D).visible = false
	b["gone"] = true


# --------------------------------------------------------------------------
# Boost pads (chevrons on the snow, usually just before a kicker) and epic kickers: a taller ramp with a pad and two pickups in the air.
# --------------------------------------------------------------------------
var pads_hit: int = 0
var _ramp_charge: float = 0.0
var _ramp_prev_z: float = 0.0
var pops_done: int = 0
var trick_charge_override: bool = false


## On a ramp, tuck (chin down, or S) to charge; the pop at the lip is bigger the longer you held it. Or just ride the pads and let the ramp do the work.
func _update_ramps(delta: float) -> void:
	var on_ramp := false
	var crossed := false
	for k in _kickers:
		var kz: float = k["z"]
		var lipz: float = kz - float(k["len"])
		if absf(spos.x - float(k["x"])) < float(k["w"]) * 0.5:
			if spos.z < kz + 4.0 and spos.z > lipz - 1.0:
				on_ramp = true
			if _ramp_prev_z > lipz and spos.z <= lipz:
				crossed = true
	_ramp_prev_z = spos.z
	var tucking_in := nod_p < -0.10 or trick_charge_override or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
	if on_ramp and grounded and tucking_in:
		_ramp_charge = minf(_ramp_charge + delta / 0.9, 1.0)
	elif not crossed:
		_ramp_charge = move_toward(_ramp_charge, 0.0, delta * (0.6 if on_ramp else 2.5))
	if crossed:
		if _ramp_charge > 0.15:
			vy += 3.0 * _ramp_charge
			pops_done += 1
			_toast("CHARGED POP!" if _ramp_charge > 0.7 else "POP!", Color(1.0, 0.85, 0.4))
			_burst(spos + Vector3(0, 0.5, 0), Color(1.0, 0.85, 0.4), 30 + int(40.0 * _ramp_charge), 10.0, 0.7, 1.0, Vector3(0, 1, 0.4), 50.0, -4.0)
			Game.sfx(&"boing")
			_fov_punch = 4.0 + 5.0 * _ramp_charge
		_ramp_charge = 0.0


func _make_pad(row: Dictionary, x: float, z: float, epic: bool) -> void:
	var col := Color(1.0, 0.55, 0.1) if not epic else Color(1.0, 0.25, 0.55)
	var mat := _fx_mat("solid", col, 2.6)
	var holder := Node3D.new()
	add_child(holder)
	for i in 3:
		var cz := z - float(i) * 2.2
		var gy := _grad(x, cz).y
		for sx in [-1.0, 1.0]:
			var bm := BoxMesh.new()
			bm.size = Vector3(2.4, 0.08, 0.45)
			var m := _mi(holder, bm, mat, Vector3(x + float(sx) * 1.0, terrain_h(x + float(sx) * 1.0, cz) + 0.2, cz))
			m.rotation = Vector3(-atan(gy), float(sx) * 0.55, 0.0)
	var pool := _mi(holder, _quad(8.0), _fx_mat("ground", Color(col.r, col.g, col.b, 0.5)), Vector3(x, terrain_h(x, z - 2.2) + 0.15, z - 2.2))
	pool.rotation.x = -PI * 0.5 - atan(_grad(x, z - 2.2).y)
	(row["nodes"] as Array).append(holder)
	(row["pads"] as Array).append({"x": x, "z": z, "used": false, "epic": epic})


func _update_pads() -> void:
	if _finished or not grounded:
		return
	for k in _rows:
		var r: Dictionary = _rows[k]
		if absf(float(r["z"]) - spos.z) > 130.0:
			continue
		for p in r["pads"]:
			if p["used"]:
				continue
			if absf(float(p["z"]) - 2.2 - spos.z) < 3.4 and absf(float(p["x"]) - spos.x) < 3.2:
				p["used"] = true
				pads_hit += 1
				_boost_t = maxf(_boost_t, 1.8)
				var fwd := Vector2(sin(heading), -cos(heading))
				var sp0 := vel.length()
				vel += fwd * 5.0
				if vel.length() > maxf(SPEED_CAP, sp0):
					vel = vel.normalized() * maxf(SPEED_CAP, sp0)
				_fov_punch = 7.0
				_shake = maxf(_shake, 0.25)
				_burst(spos + Vector3(0, 0.6, 0), Color(1.0, 0.6, 0.2), 40, 12.0, 0.6, 0.9, Vector3(0, 0.3, 1.0), 40.0, -3.0)
				Game.sfx(&"buff_boost")
				_toast("LAUNCH PAD" if p["epic"] else "BOOST PAD", Color(1.0, 0.7, 0.3))


# --------------------------------------------------------------------------
# View: first person (default, like a snowboarding game: only the tip of the board shows, which is also the best view for eye tracking, because the
# gates are where you look) or third person (shows the rider, so tricks and pickup hops can be seen). V or the VIEW label toggles it.
# --------------------------------------------------------------------------
var view_fp: bool = true
var _tip_pivot: Node3D
var _tip_yaw: float = 0.0
var _tip_roll: float = 0.0
var _tip_x: float = 0.0
var _cam_look: Vector2 = Vector2(0.0, -1.0)
var _hop_cam: float = 0.0
var _view_msec: int = 0
const VIEW_CFG := "user://carve_view.cfg"


func _load_view_pref() -> void:
	var cf := ConfigFile.new()
	if cf.load(VIEW_CFG) == OK:
		view_fp = bool(cf.get_value("carve", "fp", true))
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('view') || ''"))
		if q == "3p" or q == "3":
			view_fp = false
		elif q == "1p" or q == "1":
			view_fp = true


func _toggle_view() -> void:
	view_fp = not view_fp
	var cf := ConfigFile.new()
	cf.set_value("carve", "fp", view_fp)
	cf.save(VIEW_CFG)
	_place_camera(0.016, true)
	_toast("FIRST PERSON" if view_fp else "THIRD PERSON", Color(0.9, 0.95, 1.0))


func _view_rect() -> Rect2:
	var s := get_viewport().get_visible_rect().size
	var k := _hud_scale()
	return Rect2(s.x - 24.0 * k - 56.0 * k, 24.0 * k + 30.0 * k + 46.0 * k, 56.0 * k, 30.0 * k)


## A phone held upright is a tall, narrow window: keep the HORIZONTAL field of view (so the gates are still in sight) instead of the vertical one.
func _fit_fov() -> void:
	var vs := get_viewport().get_visible_rect().size
	if vs.y > vs.x * 1.05:
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.fov = clampf(78.0 + (vel.length() - 18.0) * 0.5, 76.0, 96.0) + _fov_punch
	else:
		cam.keep_aspect = Camera3D.KEEP_HEIGHT


func _place_camera(delta: float, snap: bool = false) -> void:
	if not view_fp:
		super._place_camera(delta, snap)
		_fit_fov()
		return
	var sp := vel.length()
	var vdir := vel / sp if sp > 1.0 else Vector2(0.0, -1.0)
	var hd := Vector2(sin(heading), -cos(heading))
	var want := (vdir * 0.5 + hd * 0.5).normalized()
	_cam_look = want if snap else _cam_look.lerp(want, 1.0 - exp(-7.0 * delta)).normalized()
	_cdir = _cam_look
	var eye := Vector3(spos.x, spos.y + 1.72 + _hop_cam, spos.z) - Vector3(_cam_look.x, 0.0, _cam_look.y) * 0.25
	eye.y = maxf(eye.y, terrain_h(eye.x, eye.z) + 1.2)
	cam.global_position = eye
	var ahead := spos + Vector3(_cam_look.x, 0.0, _cam_look.y) * 18.0
	ahead.y = terrain_h(ahead.x, ahead.z) + 1.4 + _hop_cam * 0.5
	if (ahead - eye).length() > 0.5:
		cam.look_at(ahead, Vector3.UP)
	cam.basis = cam.basis * Basis(Vector3(0, 0, 1), -steer * 0.10 - _trk_cam_roll) * Basis(Vector3(1, 0, 0), _trk_cam_pitch)
	_shake = maxf(_shake - 1.6 * delta, 0.0)
	cam.h_offset = randf_range(-1.0, 1.0) * _shake * 0.3
	cam.v_offset = randf_range(-1.0, 1.0) * _shake * 0.3
	_fov_punch = maxf(_fov_punch - 24.0 * delta, 0.0)
	cam.fov = clampf(80.0 + (sp - 18.0) * 0.6, 78.0, 108.0) + _fov_punch
	_fit_fov()


## The view model: just the tip of the board at the bottom of the screen. It swings with the board's heading (so you can see where it points relative to
## where you are going), leans into a turn, bobs on the snow and carries the tricks.
func _build_tip() -> void:
	_tip_pivot = Node3D.new()
	cam.add_child(_tip_pivot)
	_tip_pivot.position = Vector3(0.0, -1.15, 0.0)
	var body := BoxMesh.new()
	body.size = Vector3(0.8, 0.09, 0.82)                 # short, squat and wide: only the front of the board shows, low at the bottom of the view
	var b := _mi(_tip_pivot, body, _flat_mat(Color(0.15, 0.3, 0.75)), Vector3(0.0, 0.0, -1.05))
	var nose := BoxMesh.new()
	nose.size = Vector3(0.8, 0.06, 0.16)
	var n := _mi(_tip_pivot, nose, _flat_mat(Color(0.97, 0.97, 1.0)), Vector3(0.0, 0.05, -1.5))
	n.rotation.x = 0.35
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.07, 0.1, 0.6)
	_mi(_tip_pivot, stripe, _flat_mat(Color(1.0, 0.55, 0.15)), Vector3(0.0, 0.03, -1.1))
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --------------------------------------------------------------------------
# Jumps and tricks. A kicker (a ramp of snow) sits beside the safe line now and then, usually with a pickup floating above its lip: look at it, ride it,
# and in the air:
#   spin   look hard left or right (or A / D): each half turn counts (180, 360, 540 ...)
#   grab   chin down (or S): hold it for bonus points
#   flip   snap your chin up (or W): a backflip
# You always land: the landing straightens the board to the nearest half turn, so a trick never costs you a crash. Doing more than one at once multiplies the points.
# --------------------------------------------------------------------------
const KICK_LEN := 26.0
const KICK_W := 18.0
var kickers_built: int = 0
var kick_log: Array = []
var epics_built: int = 0
var _force_far_next: bool = false
var _last_air: bool = false
var air_segments: int = 0
var _air_zones: Array = []
var _air_epic: bool = false
var tricks_landed: int = 0
var trick_score: int = 0
var best_trick: String = ""
var trick_look_override: float = 0.0           # tests: stand-in for the look
var trick_grab_override: bool = false
var trick_flip_override: bool = false
var _in_air: bool = false
var _trk_spin: float = 0.0
var _trk_spin_v: float = 0.0
var _trk_flip: float = 0.0
var _trk_flip_goal: float = 0.0
var _trk_grab_t: float = 0.0
var _trk_vis_spin: float = 0.0
var _trk_vis_flip: float = 0.0
var _trk_cam_roll: float = 0.0
var _trk_cam_pitch: float = 0.0
var _trk_text: String = ""
var _trk_text_t: float = 0.0
var _trk_hint: bool = false
var _flip_key_prev: bool = false
var _air_peak: float = 0.0


## A hard landing costs speed but never wipes you out: the hill is steep and a landing is rarely your fault (a bump, a ramp you chose).
func _land(impact: float, gh: float, gvy: float) -> void:
	super._land(minf(impact, 15.0), gh, gvy)


func _place_kicker(row: Dictionary, obs: PackedFloat32Array, prev_rz: float, rz: float, z0: float, has_row: bool, j: int, air: bool = false) -> void:
	var span := (prev_rz - rz) if has_row else ROW_GAP
	if has_row and span < 78.0:
		return
	if not air:
		return                                              # ramps are big and sit in air segments only: no small lumps to hit by accident
	if has_row and _rng.randf() > 0.7:
		return
	var d := _course_diff(z0)
	var first := has_row and prev_rz > -1.0
	var epic := air or (has_row and first and _rng.randf() < 0.6)
	var prev_obs := PackedFloat32Array()
	if _rows.has(j - 1):
		prev_obs = (_rows[j - 1] as Dictionary)["obs"]
	for attempt in 8:
		if attempt == 4:
			epic = false                                    # no room for an epic one here: a plain kicker will do
		var kz: float
		if air:
			kz = z0 - 6.0
		elif first:
			kz = rz + (_rng.randf_range(125.0, 150.0) if epic else _rng.randf_range(90.0, 120.0))          # the first barrier: the ramp comes well after the start
		elif has_row:
			kz = prev_rz - span * _rng.randf_range(0.10, 0.19)
		else:
			kz = z0 - _rng.randf_range(18.0, 34.0)
		var lipz := kz - KICK_LEN
		if has_row and lipz < rz + (88.0 if epic else 50.0 + 12.0 * d):
			continue
		var cxl: float = path_x(row, kz) if has_row else (_good_x if air else 0.0)
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var koff := _rng.randf_range(4.0, 8.0) if air else _rng.randf_range(14.0, 19.0)
		var kx := cxl + side * koff
		if absf(kx) > 40.0:
			kx = cxl - side * koff
		if absf(kx) > 40.0:
			continue
		var ok := true
		for zz in [kz, lipz, lipz - 12.0, lipz - 26.0, lipz - 40.0 if epic else lipz - 26.0]:
			for xx in [kx - 8.0, kx, kx + 8.0]:
				if not _clear_of_obs(obs, xx, zz, 4.0) or not _clear_of_obs(prev_obs, xx, zz, 4.0):
					ok = false
		if not ok:
			continue
		var rise := _rng.randf_range(0.95, 1.05) * 3.3 * (36.0 / (34.0 + 17.0 * d))          # a ramp rising this fast over its length throws you about 1.3 s into the air and 50-70 m down the slope at any speed (tests/jump_probe); a charged pop adds up to 3 m/s
		_kickers.append({"x": kx, "z": kz, "len": KICK_LEN, "w": KICK_W, "rise": rise, "epic": epic})
		kick_log.append("%.0f/%.0f%s" % [kz, kx, "E" if epic else ""])
		row["kick"] = {"x": kx, "z": kz, "lip": lipz, "epic": epic}
		kickers_built += 1
		if epic:
			epics_built += 1
		if air:
			air_segments += 1
			_force_far_next = true                          # the barrier after an air segment starts well below the landing
			_air_zones.append({"z0": kz + 4.0, "z1": lipz - 105.0, "x": kx})
		var lc := Color(1.0, 0.6, 0.15) if not epic else Color(1.0, 0.3, 0.6)
		var lipm := BoxMesh.new()
		lipm.size = Vector3(KICK_W - 2.0, 0.12, 0.5)
		var lp := _mi(self, lipm, _fx_mat("solid", lc, 1.6), Vector3(kx, terrain_h(kx, lipz + 0.8) + 0.12, lipz + 0.8))
		(row["nodes"] as Array).append(lp)
		for sx in [-1.0, 1.0]:
			var pole := CylinderMesh.new()
			pole.top_radius = 0.07
			pole.bottom_radius = 0.09
			pole.height = 3.2 if not epic else 4.6
			pole.radial_segments = 5
			var px: float = kx + float(sx) * (KICK_W * 0.5 - 0.6)
			var pn := _mi(self, pole, _fx_mat("solid", lc, 1.4), Vector3(px, terrain_h(px, lipz + 1.0) + pole.height * 0.5, lipz + 1.0))
			(row["nodes"] as Array).append(pn)
			var flag := _mi(pn, _quad(1.4 if not epic else 2.2), _fx_mat("halo", Color(lc.r, lc.g, lc.b, 0.9)), Vector3(0.0, pole.height * 0.42, 0.0))
			flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pad_n := 0
		for pz in [kz + 10.0, kz - KICK_LEN * 0.5, lipz + 4.0]:
			if (pad_n == 0 and pz == lipz + 4.0) or _rng.randf() < 0.65:
				_make_pad(row, kx, pz, true)
				pad_n += 1
		if epic or _rng.randf() < 0.8:
			var trail: Array = [Vector2(kx, kz + 18.0), Vector2(kx, kz + 10.0), Vector2(kx, kz + 2.0)]
			_spawn_buff(row, _pick_buff(true), kx, lipz - 9.0, trail, "air", 2.4)
			if epic:
				_spawn_buff(row, _pick_buff(true), kx, lipz - 26.0, [], "air", 3.4)
		return


func _tricks_look(key: float, pk: Vector3) -> float:
	var look := key + (_steer_gaze if _eye_on else clampf(pk.x / 1.8, -1.0, 1.0))
	return clampf(look + trick_look_override, -1.5, 1.5)


const SPIN_NAMES := ["", "THE LAZY SUSAN", "THE FULL LAZY SUSAN", "THE WASHING MACHINE", "HELICOPTER DAD", "THE EXORCIST", "WEATHER REPORT", "ABSOLUTE TORNADO"]
const FLIP_NAMES := ["THE BACKFLIP", "THE PANCAKE", "OOPS ALL FLIPS", "THE SPICY FLIP", "SOMERSAULT SALAD"]
const GRAB_NAMES := ["THE BAGEL GRAB", "GRANDMA'S GRAB", "THE BURGER GRAB", "THE NOPE ROPE", "MELON GRAB (LIGHT)"]
const SHAKE_NAMES := ["THE BOBBLEHEAD", "NOPE NOPE NOPE", "THE WET DOG", "MAXIMUM NOPE"]
const CROSS_NAMES := ["BIG BRAIN TIME", "THE CROSS-EYED CRUSADER", "SPOOKY EYES", "ONE EYE ON EACH THING"]
const CRAZY_NAMES := ["THE GOOSE EYES", "WIGGLE WIGGLE", "THE LOOSE MARBLES", "CHAOS PUPILS"]
const SLAM_NAMES := ["THE ELBOW DROP OF DESTINY", "THE PEOPLE'S ELBOW", "FLYING SPLASH OFF THE CLIFF", "THE PILEDRIVER (INTO SNOW)", "THE SUPLEX (OF SADNESS)"]
const COMMENTARY := ["AND THE CROWD GOES WILD!", "SOMEONE CALL HIS MOTHER!", "I'VE NEVER SEEN ANYTHING LIKE IT!", "THE JUDGES ARE WEEPING!", "IS HE EVEN HUMAN?!", "NO FEAR! NO KNEES!", "SCIENTISTS ARE BAFFLED!", "PUT THAT ON A T-SHIRT!", "THE SNOW WILL REMEMBER THIS!", "ABSOLUTE UNIT!", "BRING BACK THE REPLAY!", "WHAT A TIME TO BE ALIVE!", "MOM! GET THE CAMERA!", "THE PHYSICS TEAM IS SWEATING!"]
const SLAM_LINES := ["TABLES! WE NEED TABLES!", "OH THE HUMANITY!", "DING DING DING!", "HE'S GOING FOR THE PIN!", "THE ROPES ARE BURNING!"]
const FALL_LINES := ["...that was just falling.", "Ten out of ten for gravity.", "A bold choice to do nothing.", "Please do something next time.", "The snow was not impressed."]
const MOVE_PTS := {"shake": 120, "cross": 150, "crazy": 150, "slam": 300}

var head_shake_override: bool = false
var cross_override: bool = false
var crazy_override: bool = false
var slam_override: bool = false
var ridiculous: int = 0
var _air_moves: Array = []
var _move_name: Dictionary = {}
var _chaos_pts: int = 0
var _chaos_last: String = ""
var _trk_comment: String = ""
var _trk_comment_t: float = 0.0
var _trk_burst_t: float = 0.0
var _slowmo_t: float = 0.0
var _air_time: float = 0.0
var _slam_fell: bool = false
var _hs_state: Dictionary = {}
var _cz_state: Dictionary = {}


## A zigzag detector: how many times has a value turned round, by at least `amp`, in the last `window` seconds? (Head shakes and darting eyes.)
func _zig_push(st: Dictionary, v: float, t: float, amp: float, window: float) -> int:
	if not st.has("ext"):
		st["ext"] = v
		st["dir"] = 0.0
		st["revs"] = []
		return 0
	var dir: float = st["dir"]
	var ext: float = st["ext"]
	if dir == 0.0:
		if absf(v - ext) > amp:
			st["dir"] = signf(v - ext)
			st["ext"] = v
	elif (v - ext) * dir > 0.0:
		st["ext"] = v
	elif absf(v - ext) > amp:
		(st["revs"] as Array).append(t)
		st["dir"] = -dir
		st["ext"] = v
	var revs: Array = st["revs"]
	while not revs.is_empty() and t - float(revs[0]) > window:
		revs.remove_at(0)
	return revs.size()


func _head_shake_now() -> bool:
	if not GazeProvider.head_rpy_ok or not _eye_on:
		return false
	return _zig_push(_hs_state, -rad_to_deg(GazeProvider.head_rpy.x), _age, 4.0, 1.0) >= 3


func _crazy_eyes_now() -> bool:
	if not _eye_on:
		return false
	var amp := maxf(0.35 * _ex_full, 0.006)
	return _zig_push(_cz_state, GazeProvider.eih.x, _age, amp, 0.9) >= 4


func _pick(arr: Array) -> String:
	return String(arr[_fx_rng.randi() % arr.size()])


## One extra move in the air: a name, a bit of noise and a line from the commentators.
func _add_move(id: String) -> void:
	if _air_moves.has(id):
		return
	_air_moves.append(id)
	var nm := ""
	match id:
		"shake":
			nm = _pick(SHAKE_NAMES)
			Game.sfx(&"squeak")
		"cross":
			nm = _pick(CROSS_NAMES)
			Game.sfx(&"boing")
		"crazy":
			nm = _pick(CRAZY_NAMES)
			Game.sfx(&"honk")
		"slam":
			nm = _pick(SLAM_NAMES)
			Game.sfx(&"bell")
			vy -= 7.0                                          # a slam: you drop out of the sky
			_slam_fell = true
			_shake = maxf(_shake, 0.4)
	_move_name[id] = nm
	_trk_text = nm + "!"
	_trk_text_t = 1.0
	_trk_comment = _pick(SLAM_LINES if id == "slam" else COMMENTARY)
	_trk_comment_t = 1.6
	_trk_burst_t = 0.5
	_gain(20)
	var big := _air_peak > 2.5 or _air_epic
	if _fx_rng.randf() < (0.45 if big else 0.2):
		_chaos_event()


## The ridiculous part: now and then, a move sets off something nobody asked for.
func _chaos_event() -> void:
	var opts := ["goose", "snowman", "slowmo", "fireworks", "crowd"]
	opts.erase(_chaos_last)
	var pick: String = opts[_fx_rng.randi() % opts.size()]
	_chaos_last = pick
	ridiculous += 1
	var pos := Vector3(spos.x, spos.y + 2.0, spos.z)
	match pick:
		"goose":
			_burst(pos, Color(1.0, 0.95, 0.7), 60, 12.0, 1.0, 1.4)
			_toast("HONK!!!  A GOOSE HAS ENTERED THE CHAT", Color(1.0, 0.95, 0.6))
			Game.sfx(&"honk")
			_chaos_pts += 150
		"snowman":
			_spawn_snowman()
			_toast("A SNOWMAN APPEARS TO WATCH", Color(0.9, 0.97, 1.0))
			Game.sfx(&"pop")
			_chaos_pts += 100
		"slowmo":
			_slowmo_t = 0.45
			Engine.time_scale = 0.45
			_toast("HANG TIME!", Color(0.8, 0.9, 1.0))
			_chaos_pts += 120
		"fireworks":
			for fi in 4:
				var fp := pos + Vector3(_fx_rng.randf_range(-9.0, 9.0), _fx_rng.randf_range(2.0, 9.0), -_fx_rng.randf_range(0.0, 14.0))
				var fc := Color.from_hsv(_fx_rng.randf(), 0.8, 1.0)
				_burst(fp, fc, 50, 11.0, 1.2, 1.2, Vector3.UP, 180.0, -3.0)
			_toast("FIREWORKS (NOBODY ASKED)", Color(1.0, 0.85, 0.5))
			Game.sfx(&"boom")
			_chaos_pts += 200
		_:
			_burst(pos, Color(1.0, 0.8, 0.3), 70, 10.0, 1.4, 1.3, Vector3.UP, 180.0, -9.0)
			_burst(pos, Color(0.4, 0.9, 1.0), 70, 10.0, 1.4, 1.3, Vector3.UP, 180.0, -9.0)
			_toast("THE CROWD GOES WILD (WHAT CROWD?)", Color(1.0, 0.9, 0.5))
			Game.sfx(&"crowd")
			_chaos_pts += 150


func _spawn_snowman() -> void:
	var sx := clampf(spos.x + (9.0 if _fx_rng.randf() < 0.5 else -9.0), -42.0, 42.0)
	var sz := spos.z - 26.0
	var n := Node3D.new()
	_mi(n, _sphere_mesh(1.0), _food_mat(Color(0.97, 0.98, 1.0), 0.3), Vector3(0, 1.0, 0))
	_mi(n, _sphere_mesh(0.75), _food_mat(Color(0.97, 0.98, 1.0), 0.3), Vector3(0, 2.3, 0))
	_mi(n, _sphere_mesh(0.55), _food_mat(Color(0.97, 0.98, 1.0), 0.3), Vector3(0, 3.35, 0))
	var nose := _cone(0.12, 0.7)
	nose.material_override = _food_mat(Color(1.0, 0.5, 0.1))
	n.add_child(nose)
	nose.position = Vector3(0, 3.35, 0.7)
	nose.rotation.x = PI * 0.5
	for ex in [-0.2, 0.2]:
		_mi(n, _sphere_mesh(0.07), _food_mat(Color(0.05, 0.05, 0.08), 0.0), Vector3(float(ex), 3.5, 0.5))
	add_child(n)
	n.global_position = Vector3(sx, terrain_h(sx, sz) - 0.2, sz)
	n.scale = Vector3.ONE * 0.1
	n.rotation.y = PI
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3.ONE * 1.5, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(5.0)
	tw.tween_callback(n.queue_free)


func _update_tricks(delta: float, key: float, pk: Vector3) -> void:
	_trk_text_t = maxf(_trk_text_t - delta, 0.0)
	_trk_comment_t = maxf(_trk_comment_t - delta, 0.0)
	_trk_burst_t = maxf(_trk_burst_t - delta, 0.0)
	if _slowmo_t > 0.0:
		_slowmo_t -= delta
		if _slowmo_t <= 0.0:
			Engine.time_scale = 1.0
	var alt := spos.y - terrain_h(spos.x, spos.z)
	var air := (not grounded) and alt > 0.6 and air_t > 0.1 and not _finished and hurt_t <= 0.0
	if air:
		if not _in_air:
			_in_air = true
			_trk_spin = 0.0
			_trk_spin_v = 0.0
			_trk_flip = 0.0
			_trk_flip_goal = 0.0
			_trk_grab_t = 0.0
			_air_peak = 0.0
			_air_time = 0.0
			_air_moves.clear()
			_move_name.clear()
			_chaos_pts = 0
			_slam_fell = false
			_air_epic = false
			for ke in _kickers:
				if bool(ke.get("epic", false)) and spos.z <= float(ke["z"]) and float(ke["z"]) - spos.z < 40.0 and absf(spos.x - float(ke["x"])) < 12.0:
					_air_epic = true
			if _air_epic:
				_toast("EPIC JUMP!", Color(1.0, 0.45, 0.7))
				_fov_punch = 6.0
			if not _trk_hint and alt > 0.8:
				_trk_hint = true
				_toast("In the air: look aside to spin, chin down to grab, shake your head, cross your eyes...", Color(0.9, 0.95, 1.0))
		_air_peak = maxf(_air_peak, alt)
		_air_time += delta
		var look := _tricks_look(key, pk)
		var landing := alt < 2.0 and vy < 0.0
		var target := 0.0
		if absf(look) > 0.45 and not landing:
			target = signf(look) * TAU * 0.85
		_trk_spin_v = lerpf(_trk_spin_v, target, 1.0 - exp(-8.0 * delta))
		_trk_spin += _trk_spin_v * delta
		if landing:
			_trk_spin = lerpf(_trk_spin, roundf(_trk_spin / PI) * PI, 1.0 - exp(-12.0 * delta))
		var grab := nod_p < -0.10 or trick_grab_override or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
		if grab:
			_trk_grab_t += delta
		var fk := nod_v > 1.1 or trick_flip_override or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
		if fk and not _flip_key_prev and alt > 1.2 and _trk_flip >= _trk_flip_goal - 0.2 and _trk_flip_goal < TAU * 2.0:
			_trk_flip_goal += TAU
		_flip_key_prev = fk
		_trk_flip = move_toward(_trk_flip, _trk_flip_goal, TAU * (3.0 if landing else 1.7) * delta)
		if alt > 1.0:
			if head_shake_override or Input.is_key_pressed(KEY_H) or _head_shake_now():
				_add_move("shake")
			if cross_override or Input.is_key_pressed(KEY_X) or GazeProvider.cross_eyed():
				_add_move("cross")
			if crazy_override or Input.is_key_pressed(KEY_Z) or _crazy_eyes_now():
				_add_move("crazy")
			if alt > 2.0 and (slam_override or Input.is_key_pressed(KEY_F) or nod_v < -1.6):
				_add_move("slam")
		var parts := _trick_parts(false)
		if not parts.is_empty() and _trk_text_t < 0.3:
			_trk_text = " + ".join(parts)
			_trk_text_t = 0.25
	elif _in_air:
		_in_air = false
		if _slowmo_t > 0.0:
			_slowmo_t = 0.0
			Engine.time_scale = 1.0
		if hurt_t > 0.0:
			_trk_text = "BAILED"
			_trk_comment = "(he's fine, he's fine)"
			_trk_text_t = 1.2
			_trk_comment_t = 1.4
		else:
			_land_tricks()
		_trk_vis_spin = _trk_spin - roundf(_trk_spin / TAU) * TAU
		_trk_vis_flip = _trk_flip - roundf(_trk_flip / TAU) * TAU
		_trk_spin = 0.0
		_trk_flip = 0.0
		_trk_flip_goal = 0.0
		_trk_spin_v = 0.0
	if not _in_air:
		_trk_vis_spin = move_toward(_trk_vis_spin, 0.0, 14.0 * delta)
		_trk_vis_flip = move_toward(_trk_vis_flip, 0.0, 14.0 * delta)
	var ts := (_trk_spin if _in_air else _trk_vis_spin)
	var tf := (_trk_flip if _in_air else _trk_vis_flip)
	var wob := 0.0
	if _in_air and (_air_moves.has("shake") or _air_moves.has("crazy")):
		wob = sin(_age * 40.0) * 0.07
	_trk_cam_roll = lerpf(_trk_cam_roll, sin(ts) * 0.16 + wob, 1.0 - exp(-14.0 * delta))
	_trk_cam_pitch = lerpf(_trk_cam_pitch, sin(tf) * 0.3, 1.0 - exp(-14.0 * delta))


## The plain list while you are in the air (degrees and the moves so far), or the silly names once you land.
func _trick_parts(funny: bool) -> Array:
	var parts: Array = []
	var n := int(roundf(absf(_trk_spin) / PI))
	if n >= 1:
		parts.append(SPIN_NAMES[mini(n, SPIN_NAMES.size() - 1)] if funny else str(n * 180))
	var fl := int(floorf(_trk_flip / TAU + 0.25))
	if fl >= 1:
		parts.append((FLIP_NAMES[_fx_rng.randi() % FLIP_NAMES.size()] if fl == 1 else "DOUBLE " + FLIP_NAMES[_fx_rng.randi() % FLIP_NAMES.size()]) if funny else ("FLIP" if fl == 1 else "DOUBLE FLIP"))
	if _trk_grab_t >= 0.35:
		parts.append(_pick(GRAB_NAMES) if funny else "GRAB")
	for mv in _air_moves:
		parts.append(String(_move_name.get(mv, mv)))
	return parts


func _land_tricks() -> void:
	var n := int(roundf(absf(_trk_spin) / PI))
	var fl := int(floorf(_trk_flip / TAU + 0.25))
	var gr := mini(int(_trk_grab_t / 0.35), 5)
	var pts := 0
	var kinds := 0
	if n >= 1:
		pts += [0, 100, 250, 450, 700, 1000][mini(n, 5)]
		kinds += 1
	if fl >= 1:
		pts += 220 * fl
		kinds += 1
	if gr >= 1:
		pts += 40 * gr
		kinds += 1
	for mv in _air_moves:
		pts += int(MOVE_PTS.get(mv, 100))
		kinds += 1
	if _air_peak > 2.5:
		pts += 30
	if pts <= 30:
		if _air_time > 0.8:
			_trk_text = "JUST FALLING"
			_trk_comment = _pick(FALL_LINES)
			_trk_text_t = 1.6
			_trk_comment_t = 1.8
		return
	var mult := minf(1.0 + 0.5 * float(maxi(kinds - 1, 0)), 4.0)
	pts = int(float(pts) * mult) + _chaos_pts
	if _air_epic:
		pts = int(float(pts) * 1.6)
	var name := " + ".join(_trick_parts(true))
	if _air_epic:
		name = "EPIC " + name
	tricks_landed += 1
	trick_score += pts
	if best_trick == "" or pts > int(best_trick.get_slice("|", 1)):
		best_trick = "%s|%d" % [name, pts]
	_gain(pts)
	chain += 1
	groove = 1.0 + 0.25 * minf(float(chain), 8.0)
	best_flow = maxf(best_flow, groove)
	var shown := name
	if shown.length() > 64:
		shown = shown.substr(0, 61) + "..."
	_trk_text = "%s  +%d" % [shown, pts] if name != "" else "AIR  +%d" % pts
	_trk_text_t = 2.2
	_trk_comment = _pick(SLAM_LINES if _air_moves.has("slam") else COMMENTARY)
	_trk_comment_t = 2.4
	_trk_burst_t = 0.7
	_flash = 0.3
	_shake = maxf(_shake, 0.3)
	_pop_col = Color(1.0, 0.85, 0.3)
	_pop_a = 0.8
	var gp := Vector3(spos.x, spos.y + 1.0, spos.z)
	_burst(gp, Color(1.0, 0.9, 0.5), 40, 10.0, 0.9, 1.0)
	_ring(Vector3(spos.x, spos.y + 0.3, spos.z), Color(1.0, 0.85, 0.4), 9.0, 0.5, false)
	if _slam_fell:
		_ring(Vector3(spos.x, spos.y + 0.3, spos.z), Color(1.0, 0.5, 0.3), 16.0, 0.7, false)
		_burst(gp, Color(0.95, 0.98, 1.0), 80, 14.0, 1.0, 2.0, Vector3.UP, 180.0, -9.0)
		_shake = maxf(_shake, 0.9)
		Game.sfx(&"boom")
		Game.sfx(&"crowd")
	if _air_epic or kinds >= 3:
		Game.sfx(&"levelup")
	else:
		Game.sfx(&"buff_mult")


func _draw_eyes_hud(font: Font, s: Vector2, k: float) -> void:
	# squinting: the top and bottom of the view close in, like narrowed eyes
	_squint_vis = lerpf(_squint_vis, 1.0 if _squinting_now else 0.0, 0.25)
	if _squint_vis > 0.02:
		var bh := s.y * 0.14 * _squint_vis
		_hud.draw_rect(Rect2(0.0, 0.0, s.x, bh), Color(0.02, 0.03, 0.08, 0.88))
		_hud.draw_rect(Rect2(0.0, s.y - bh, s.x, bh), Color(0.02, 0.03, 0.08, 0.88))
	# the nearest food you can still reach: what to do with your eyes
	if eat_enabled and not _finished:
		var best: Dictionary = {}
		var bd := 1.0e9
		for kk in _rows:
			var r: Dictionary = _rows[kk]
			if absf(float(r["z"]) - spos.z) > 130.0:
				continue
			for b in r["buffs"]:
				if b["taken"] or float(b.get("arm", 0.0)) > 0.0:
					continue
				var dz := spos.z - float(b["z"])
				if dz < 3.0 or dz > 36.0 or absf(float(b["x"]) - spos.x) > 0.3 * dz + 4.0:
					continue
				if dz < bd:
					bd = dz
					best = b
		if not best.is_empty():
			var bp := _food_pos(best) + Vector3(0, 2.8, 0)
			if not cam.is_position_behind(bp):
				var sc := cam.unproject_position(bp)
				var can := _can_eat()
				var txt := "CHOMP!" if can else "OPEN WIDE"
				var col := Color(0.5, 1.0, 0.6) if can else Color(1.0, 0.9, 0.4)
				var pulse := 1.0 + 0.12 * sin(_age * 10.0)
				var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(24.0 * k * pulse)).x
				_text(font, sc + Vector2(-w * 0.5, 0.0), txt, int(24.0 * pulse), col)
	# snowballs: where they are and what to do
	for b2 in _balls:
		if b2["done"]:
			continue
		var wp := Vector3(float(b2["x"]), terrain_h(float(b2["x"]), float(b2["z"])) + BALL_R + 3.0, float(b2["z"]))
		if cam.is_position_behind(wp):
			continue
		var sp2 := cam.unproject_position(wp)
		var dist := maxf(spos.z - float(b2["z"]), 0.0)
		var near := dist < 30.0
		var t2 := "DUCK / SQUINT!" if near and not _braced() else ("BRACED" if near else "SNOWBALL")
		var c2 := Color(1.0, 0.55, 0.4) if near and not _braced() else Color(0.8, 0.95, 1.0)
		var w2 := font.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, int(24.0 * k)).x
		_text(font, sp2 + Vector2(-w2 * 0.5, 0.0), t2, 24, c2)
		_hud.draw_arc(sp2 + Vector2(0, 40.0 * k), 22.0 * k, 0.0, TAU, 24, Color(c2.r, c2.g, c2.b, 0.8), 3.0 * k)


func _draw_tricks(font: Font, s: Vector2, k: float) -> void:
	if _ramp_charge > 0.02:
		var bw := 180.0 * k
		var bx := s.x * 0.5 - bw * 0.5
		var by := s.y * 0.8
		_hud.draw_rect(Rect2(bx, by, bw, 14.0 * k), Color(0.05, 0.1, 0.2, 0.6))
		_hud.draw_rect(Rect2(bx, by, bw * _ramp_charge, 14.0 * k), Color(1.0, 0.7 + 0.25 * _ramp_charge, 0.2, 0.95))
		_ctext(font, by - 8.0 * k, "CHARGING: pop at the lip" if _ramp_charge < 0.95 else "FULL CHARGE!", 22, Color(1, 1, 1, 0.9))
	if _trk_text_t > 0.0 and _trk_text != "":
		var a := clampf(_trk_text_t / 0.5, 0.0, 1.0)
		var big := _trk_text_t > 0.3 and not _in_air
		var ty := s.y * (0.27 if big else 0.34)
		if _trk_burst_t > 0.0:
			var u := 1.0 - _trk_burst_t / 0.7
			var rad := (150.0 + 90.0 * u) * k
			var c0 := Vector2(s.x * 0.5, ty + 12.0 * k)
			var pts := PackedVector2Array()
			for si in 24:
				var ang := float(si) * TAU / 24.0 + _age * 0.8
				var rr := rad * (1.0 if si % 2 == 0 else 0.62)
				pts.append(c0 + Vector2(cos(ang), sin(ang)) * rr)
			_hud.draw_colored_polygon(pts, Color(1.0, 0.45, 0.1, 0.55 * clampf(_trk_burst_t / 0.4, 0.0, 1.0)))
		_ctext(font, ty, _trk_text, 46 if big else 30, Color(1.0, 0.88, 0.35, a))
		if _trk_comment_t > 0.0 and _trk_comment != "":
			_ctext(font, ty + 52.0 * k, _trk_comment, 24, Color(1.0, 1.0, 1.0, clampf(_trk_comment_t / 0.5, 0.0, 1.0)))
	var vr := _view_rect()
	_hud.draw_rect(vr, Color(0.05, 0.12, 0.25, 0.5))
	_text(font, vr.position + Vector2(6.0 * k, 21.0 * k), "1ST" if view_fp else "3RD", 18, Color(1, 1, 1, 0.9))


# --------------------------------------------------------------------------
# Aim: the opening you look at, and keep looking at for a moment, pulls the board through it
# --------------------------------------------------------------------------
func _update_focus(delta: float) -> void:
	var pf0 := Time.get_ticks_usec()
	super._update_focus(delta)
	_update_aim(delta)
	_update_buff_aim(delta)
	_trace_tick(delta)
	_pf_focus = _pf(_pf_focus, pf0)


func _update_aim(delta: float) -> void:
	if _paused:
		return
	var row: Dictionary = {}
	var keys: Array = _rows.keys()
	keys.sort()
	for kk in keys:
		var r: Dictionary = _rows[kk]
		if not r["has_row"] or r["passed"]:
			continue
		var dist := spos.z - float(r["z"])
		if dist < AIM_MIN_DIST or dist > AIM_MAX_DIST:
			continue
		row = r
		break
	if row.is_empty() or not _eye_on or _finished or not aim_enabled or (trace_on and _tr_phase != 3):
		_aim = {}
		_aim_row = {}
		_cand = {}
		_cand_t = 0.0
		_aim_w = move_toward(_aim_w, 0.0, 6.0 * delta)
		return
	if not is_same(_aim_row, row):
		_aim = {}
		_aim_row = {}
	var vs := get_viewport().get_visible_rect().size
	if _aim_cx < 0.0:
		_aim_cx = _cursor_px.x
	_aim_cx = lerpf(_aim_cx, _cursor_px.x, 1.0 - exp(-delta / 0.18))
	var cx := _aim_cx
	var best: Dictionary = {}
	var best_d := 1.0e9
	for g in row["gaps"]:
		var sc := _gap_screen(row, g)
		if sc.is_empty():
			continue
		var c: Vector2 = sc["c"]
		var tol := maxf(float(sc["hw"]) * 1.15, 0.12 * vs.x * clampf(68.0 / maxf(cam.fov, 40.0), 0.55, 1.0))          # a wider view packs the gates closer together on screen: look more precisely
		var dd := absf(c.x - cx) / tol
		if is_same(g, _aim):
			dd *= 0.7
		if dd < best_d:
			best_d = dd
			best = g
	if best_d < 1.0:
		if is_same(best, _aim):
			_cand = {}
			_cand_t = 0.0
		elif is_same(best, _cand):
			_cand_t += delta
			if _cand_t >= AIM_LINGER:
				_aim = best
				_aim_row = row
				_cand = {}
				_cand_t = 0.0
		else:
			_cand = best
			_cand_t = 0.0
	else:
		_cand = {}
		_cand_t = 0.0
		if best_d > 1.6:
			_aim = {}
			_aim_row = {}
	if _aim.is_empty():
		_aim_w = move_toward(_aim_w, 0.0, 6.0 * delta)
	else:
		_aim_w = move_toward(_aim_w, 1.0, 4.0 * delta)
		_aim_want = clampf((float(_aim["x"]) - (spos.x + vel.x * 0.45)) / 12.0, -0.9, 0.9)


# --------------------------------------------------------------------------
# Input, pause, report
# --------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if _pause_input(event):
		get_viewport().set_input_as_handled()
		return
	if not _paused:
		if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_V:
			_toggle_view()
			get_viewport().set_input_as_handled()
			return
		var vpos := Vector2.INF
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			vpos = (event as InputEventMouseButton).position
		elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
			vpos = (event as InputEventScreenTouch).position
		if vpos.is_finite() and _view_rect().has_point(vpos):
			if Time.get_ticks_msec() - _view_msec > 300:
				_view_msec = Time.get_ticks_msec()
				_toggle_view()
			get_viewport().set_input_as_handled()
			return
	if not _paused and event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var tk := (event as InputEventKey).keycode
		if tk == KEY_T:
			if trace_on:
				_trace_end()
			else:
				_trace_start()
			get_viewport().set_input_as_handled()
			return
		if trace_on and _tr_phase == 4 and tk == KEY_R:
			_trace_start()
			get_viewport().set_input_as_handled()
			return
		if trace_on and _tr_phase == 4 and tk == KEY_C:
			_trace_copy()
			get_viewport().set_input_as_handled()
			return
	if trace_on and _tr_phase == 4 and not _paused and ((event is InputEventMouseButton and (event as InputEventMouseButton).pressed) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)):
		_trace_copy()
		get_viewport().set_input_as_handled()
		return
	if _finished and _end_t > 1.2 and not _paused and not trace_on:
		var again := false
		if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
			var kc := (event as InputEventKey).keycode
			again = kc == KEY_R or kc == KEY_SPACE or kc == KEY_ENTER
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			again = true
		elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
			again = true
		if again:
			_restart()
			get_viewport().set_input_as_handled()


func _pause_action(id: String) -> void:
	if id == "ctl":
		_copy_note = "carve steers continuously from where you look"
		return
	if id == "trace":
		_paused = false
		_trace_start()
		return
	if id == "trace_off":
		_trace_end()
		_copy_note = "trace ended"
		return
	super._pause_action(id)


func _pause_report() -> Dictionary:
	var r := super._pause_report()
	r["carve"] = {"distance": int(-spos.z), "finishAt": int(-FINISH_Z), "speedKmh": int(vel.length() * 3.6), "crashes": crashes, "barriersPassed": _passed_ok,
		"tight": _tight_n, "crashLog": crash_log.slice(maxi(crash_log.size() - 12, 0)), "swerves": swerves, "wrongGates": wrong_gates, "buffs": {"got": buffs_got, "spawned": buffs_spawned, "byType": buff_log, "gotByKind": got_kind, "spawnedByKind": spawned_kind, "orbs": orbs_got, "latched": not _buff_tgt.is_empty(), "pull": snappedf(_buff_w, 0.01)}, "foods": {"bounced": foods_bounced, "lost": foods_lost, "eyeOpenFast": snappedf(GazeProvider.eye_open_fast, 0.01), "squinting": _squinting_now}, "snowballs": {"spawned": snow_spawned, "braced": snow_braced, "hit": snow_hit, "dodged": snow_dodged}, "pads": pads_hit, "pops": pops_done, "epicKickers": epics_built, "tricks": {"ridiculous": ridiculous, "landed": tricks_landed, "score": trick_score, "best": best_trick, "kickers": kickers_built, "view": "1p" if view_fp else "3p"}, "gatePull": snappedf(_wall_w, 0.01), "aimLatched": not _aim.is_empty(), "aimPull": snappedf(_aim_w, 0.01), "runTime": snappedf(_run_t, 0.1), "finished": _finished, "events": _ev}
	if not _tr_res.is_empty():
		r["trace"] = _tr_res
	return r


# --------------------------------------------------------------------------
# HUD: speed, distance, flow, the gaze ring. Nothing else on the snow.
# --------------------------------------------------------------------------
func _draw_hud() -> void:
	var pf0 := Time.get_ticks_usec()
	_draw_hud_inner()
	_pf_hud = _pf(_pf_hud, pf0)


func _draw_pops(font: Font, s: Vector2, k: float) -> void:
	if _pop_a > 0.0:
		var c := _pop_col
		for i in 7:
			_hud.draw_rect(Rect2(Vector2.ZERO, s).grow(-float(i) * 10.0 * k), Color(c.r, c.g, c.b, _pop_a * (0.2 - 0.026 * float(i))), false, 12.0 * k)
	for pp in _hud_pops:
		var p3: Vector3 = pp["p"]
		if cam.is_position_behind(p3):
			continue
		var sc := cam.unproject_position(p3)
		var u := clampf(float(pp["t"]) / 0.8, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - u, 3.0)
		var c2: Color = pp["col"]
		_hud.draw_arc(sc, (14.0 + 120.0 * e) * k, 0.0, TAU, 32, Color(c2.r, c2.g, c2.b, 1.0 - u), 5.0 * k * (1.0 - u) + 1.0)
		for ri in 10:
			var ang := float(ri) * TAU / 10.0 + 0.3
			var d := Vector2(cos(ang), sin(ang))
			_hud.draw_line(sc + d * (20.0 + 90.0 * e) * k, sc + d * (30.0 + 150.0 * e) * k, Color(1.0, 1.0, 0.9, 1.0 - u), 3.0 * k * (1.0 - u) + 1.0)
		_text(font, sc + Vector2(-24.0 * k, (-30.0 - 60.0 * e) * k), String(pp["text"]), 30, Color(c2.r * 0.4 + 0.6, c2.g * 0.4 + 0.6, c2.b * 0.4 + 0.6, 1.0 - u * u))


func _draw_hud_inner() -> void:
	var font := ThemeDB.fallback_font
	var s := _hud.size
	var k := _hud_scale()
	var m := 24.0 * k
	if hurt_t > 0.0:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(1.0, 0.1, 0.1, 0.22 * clampf(hurt_t, 0.0, 1.0)))
	if _flash > 0.0:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(1.0, 1.0, 1.0, 0.3 * _flash))
	_draw_pops(font, s, k)
	_draw_tricks(font, s, k)
	_draw_eyes_hud(font, s, k)
	# speed lines at the edge of the screen: the faster you go, the more of them
	var sp_f := clampf((vel.length() - 26.0) / 40.0, 0.0, 1.0)
	if sp_f > 0.02:
		var c0 := s * 0.5 + Vector2(0.0, s.y * 0.04)
		var rmax := s.length() * 0.5
		for i in 30:
			var a := float(i) * 2.399963 + floorf(_age * 3.0 + float(i) * 0.37) * 1.3
			var f := fposmod(_age * (1.3 + 0.07 * float(i % 5)) + float(i) * 0.173, 1.0)
			var r0 := lerpf(0.42, 0.95, f) * rmax
			var r1 := r0 + (0.03 + 0.12 * f) * rmax * (0.5 + sp_f)
			var dir := Vector2(cos(a), sin(a))
			_hud.draw_line(c0 + dir * r0, c0 + dir * r1, Color(1.0, 1.0, 1.0, 0.22 * sp_f * f), 2.0 * k)
	# the opening you have latched: two soft posts at its edges
	if not _aim.is_empty() and not _aim_row.is_empty():
		var asc := _gap_screen(_aim_row, _aim)
		if not asc.is_empty():
			var ac: Vector2 = asc["c"]
			var ahw: float = asc["hw"]
			var aa := 0.35 + 0.5 * _aim_w
			for sx in [-1.0, 1.0]:
				_hud.draw_line(ac + Vector2(float(sx) * ahw, -64.0 * k), ac + Vector2(float(sx) * ahw, 14.0 * k), Color(0.45, 1.0, 0.65, aa), 4.0 * k)
	if not _cand.is_empty():
		for kk in _rows:
			var rr: Dictionary = _rows[kk]
			if not rr["has_row"] or rr["passed"]:
				continue
			for gg in rr["gaps"]:
				if is_same(gg, _cand):
					var csc := _gap_screen(rr, gg)
					if not csc.is_empty():
						var cc: Vector2 = csc["c"]
						_hud.draw_arc(cc, 16.0 * k, -PI * 0.5, -PI * 0.5 + TAU * clampf(_cand_t / AIM_LINGER, 0.0, 1.0), 24, Color(1.0, 1.0, 1.0, 0.85), 3.5 * k)
	# the buff you are looking at: a dwell arc while it is being picked, a ring once it has you
	for bb in [_buff_cand, _buff_tgt]:
		var bd2: Dictionary = bb
		if bd2.is_empty() or bd2["taken"]:
			continue
		var bp := Vector3(float(bd2["x"]), terrain_h(float(bd2["x"]), float(bd2["z"])) + 2.4, float(bd2["z"]))
		if cam.is_position_behind(bp):
			continue
		var bs := cam.unproject_position(bp)
		var bcol: Color = BUFF_COL[bd2["t"]]
		if is_same(bd2, _buff_tgt):
			_hud.draw_arc(bs, 22.0 * k, 0.0, TAU, 28, Color(bcol.r, bcol.g, bcol.b, 0.35 + 0.5 * _buff_w), 4.0 * k)
		else:
			_hud.draw_arc(bs, 22.0 * k, -PI * 0.5, -PI * 0.5 + TAU * clampf(_buff_cand_t / AIM_LINGER, 0.0, 1.0), 24, Color(1.0, 1.0, 1.0, 0.85), 3.5 * k)
	# gaze reticle
	if _eye_on and not _paused:
		var cur_px := _cursor_px if _cursor_px != Vector2.ZERO else _gaze_px
		for ti in _gaze_trail.size():
			var ta := float(ti + 1) / float(_gaze_trail.size() + 1)
			_hud.draw_circle(_gaze_trail[ti], 5.0 * k * ta, Color(1.0, 0.6, 0.1, 0.35 * ta))
		_hud.draw_circle(cur_px, 15.0 * k, Color(1.0, 0.6, 0.1, 0.18))
		_hud.draw_arc(cur_px, 15.0 * k, 0.0, TAU, 24, Color(1.0, 0.6, 0.1, 0.95), 3.5 * k)
		_hud.draw_circle(cur_px, 4.5 * k, Color(1.0, 0.6, 0.1, 0.95))
	# progress bar (top centre), score (top left), eyes status (top right)
	var bw := minf(s.x * 0.34, 420.0 * k)
	var bx := s.x * 0.5 - bw * 0.5
	_hud.draw_rect(Rect2(bx, m, bw, 10.0 * k), Color(0.05, 0.12, 0.25, 0.5))
	_hud.draw_rect(Rect2(bx, m, bw * progress(), 10.0 * k), Color(1.0, 0.85, 0.35, 0.95))
	_hud.draw_rect(Rect2(bx + bw - 3.0 * k, m - 4.0 * k, 3.0 * k, 18.0 * k), Color(1, 1, 1, 0.9))
	_text(font, Vector2(m, m + 22.0 * k), "%d" % score, 34, Color(1, 1, 1))
	var by := m + 52.0 * k
	if _boost_t > 0.0:
		_text(font, Vector2(m, by), "BOOST %.1f" % _boost_t, 20, BUFF_COL["boost"])
		by += 26.0 * k
	if _mult_t > 0.0:
		_text(font, Vector2(m, by), "x2 POINTS %.1f" % _mult_t, 20, BUFF_COL["mult"])
		by += 26.0 * k
	if shield > 0:
		_text(font, Vector2(m, by), "SHIELD", 20, BUFF_COL["shield"])
	var eye_txt := "EYES OFF"
	if GazeProvider.backend == GazeProvider.Backend.CAMERA:
		eye_txt = "EYES"
	elif GazeProvider.backend == GazeProvider.Backend.MOUSE and not Game.touch_mode:
		eye_txt = "MOUSE EYES"
	var ecol := Color(0.5, 1.0, 0.6) if _eye_on else Color(1, 1, 1, 0.55)
	var ew := font.get_string_size(eye_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20.0 * k)).x
	_text(font, Vector2(s.x - m - ew, m + 18.0 * k), eye_txt, 20, ecol)
	_text(font, Vector2(m, s.y - m - 30.0 * k), "%d km/h" % int(vel.length() * 3.6), 30, Color(1, 1, 1))
	if chain > 0:
		_text(font, Vector2(m, s.y - m), "FLOW x%.1f" % groove, 22, Color(1.0, 0.85, 0.3))
	var dtxt := "%d m" % int(maxf(-spos.z, 0.0))
	var dw := font.get_string_size(dtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(26.0 * k)).x
	_text(font, Vector2(s.x - m - dw, s.y - m), dtxt, 26, Color(1, 1, 1, 0.85))
	var ty := s.y * 0.2
	for t in _toasts:
		var a2 := clampf(float(t["t"]) / 0.5, 0.0, 1.0)
		var col2: Color = t["color"]
		col2.a = a2
		_ctext(font, ty, String(t["text"]), 30, col2)
		ty += 38.0 * k
	if _finished:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.07, 0.15, 0.55))
		_ctext(font, s.y * 0.34, "FINISH", 64, Color(1.0, 0.9, 0.4))
		_ctext(font, s.y * 0.34 + 56.0 * k, "time %.1f s   crashes %d   score %d" % [_run_t, crashes, score], 30, Color(1, 1, 1))
		if crashes == 0:
			_ctext(font, s.y * 0.34 + 98.0 * k, "CLEAN RUN +1000", 28, Color(0.5, 1.0, 0.6))
		if _end_t > 1.2:
			_ctext(font, s.y * 0.34 + 148.0 * k, "press R, SPACE or tap to ride again", 22, Color(1, 1, 1, 0.85))
	if not _paused:
		var pr := _pause_rect()
		_hud.draw_rect(pr, Color(0.05, 0.12, 0.25, 0.5))
		_hud.draw_rect(Rect2(pr.position.x + pr.size.x * 0.32, pr.position.y + pr.size.y * 0.25, pr.size.x * 0.12, pr.size.y * 0.5), Color(1, 1, 1, 0.9))
		_hud.draw_rect(Rect2(pr.position.x + pr.size.x * 0.56, pr.position.y + pr.size.y * 0.25, pr.size.x * 0.12, pr.size.y * 0.5), Color(1, 1, 1, 0.9))
	else:
		_draw_pause(font, s, k)
	if _coach_t > 0.0 and _coach_text != "":
		var ca := clampf(_coach_t / 0.6, 0.0, 1.0)
		var ccol := Color(0.5, 1.0, 0.6, ca) if _coach_good else Color(1.0, 0.85, 0.4, ca)
		_ctext(font, s.y * 0.30, _coach_text, 24, ccol)
	var cmsg := GazeProvider.camera_message()
	if String(cmsg["text"]) != "" and (_age < 12.0 or not GazeProvider._camera_fresh()):
		_ctext(font, s.y * 0.12, String(cmsg["text"]), 20, cmsg["color"])
	if trace_on and not _paused:
		_draw_trace(font, s, k)


# --------------------------------------------------------------------------
# TRACE test: follow a highlighted dot with your eyes while the game measures how well the tracking keeps up.
# Start it from Pause -> TRACE TEST, with the T key, or by opening the page with &trace=1.
#   1 FOLLOW: the dot sweeps back and forth, faster and faster (smooth following: scale, lag, wobble)
#   2 JUMP:   the dot jumps to a new spot every 2 s (glance reaction, where you land, how steady you hold)
#   3 DOWNHILL:  the real game, steering with your eyes along a highlighted line (how far off the line, the steering lag)
# The board drives itself in 1 and 2, so all you have to do is look.
# --------------------------------------------------------------------------
const TR_INTRO := 3.0
const TR_PURSUIT := 24.0
const TR_JUMPS := 22.0
const TR_JUMP_HOLD := 2.0
const TR_CARVE := 40.0
const TR_HZ := 30.0

var trace_on: bool = false
var _tr_phase: int = -1                 # 0 intro, 1 follow, 2 jump, 3 carve, 4 results
var _tr_t: float = 0.0
var _tr_acc: float = 0.0
var _tr_bead: Vector2 = Vector2(0.5, 0.46)   # the dot, as fractions of the screen
var _tr_samp: Array = [[], [], [], []]       # by phase; each: PackedFloat32Array(t, dot x, dot y, gaze x, gaze y, metres off the line, steer, steer needed)
var _tr_jx: Array = []
var _tr_jy: Array = []
var _tr_res: Dictionary = {}
var _tr_lines: Array = []
var _tr_rng := RandomNumberGenerator.new()
var _tr_crash0: int = 0
var _tr_pass0: int = 0
var _tr_total: int = 0
var _tr_miss: int = 0
var _tr_auto: bool = false
var _tr_note: String = ""


func _trace_start() -> void:
	trace_on = true
	_restart()
	_tr_samp = [[], [], [], []]
	_tr_res = {}
	_tr_lines = []
	_tr_total = 0
	_tr_miss = 0
	_tr_note = ""
	_tr_rng.seed = 7777
	_paused = false
	_trace_phase(0)


func _trace_end() -> void:
	if not trace_on:
		return
	trace_on = false
	_tr_phase = -1
	autopilot = false
	_restart()


func _trace_phase(p: int) -> void:
	_tr_phase = p
	_tr_t = 0.0
	_tr_acc = 0.0
	autopilot = p != 3
	if p == 2:
		_tr_jx.clear()
		_tr_jy.clear()
		var prev := 0.5
		for i in int(TR_JUMPS / TR_JUMP_HOLD):
			var nx := prev
			var tries := 0
			while absf(nx - prev) < 0.28 and tries < 40:
				nx = _tr_rng.randf_range(0.12, 0.88)
				tries += 1
			_tr_jx.append(nx)
			_tr_jy.append(_tr_rng.randf_range(0.30, 0.58))
			prev = nx
	elif p == 3:
		_tr_crash0 = crashes
		_tr_pass0 = _passed_ok
	elif p == 4:
		_trace_finish()


## Where the dot is during FOLLOW: a sweep that speeds up from 0.08 to 0.4 swings a second.
func _tr_pursuit_pos(t: float) -> Vector2:
	var ph := TAU * (0.08 * t + (0.40 - 0.08) * t * t / (2.0 * TR_PURSUIT))
	return Vector2(0.5 + 0.30 * sin(ph), 0.46 + 0.04 * sin(t * 0.9))


## The safe line at a height z: toward the nearest barrier at or beyond z.
func _safe_x_at(z: float) -> float:
	var keys: Array = _rows.keys()
	keys.sort()
	for kk in keys:
		var r: Dictionary = _rows[kk]
		if not r["has_row"] or r["passed"]:
			continue
		if float(r["z"]) <= z + 0.001:
			return path_x(r, z)
	return 0.0


func _tr_world_px(x: float, z: float, up: float) -> Vector2:
	var wp := Vector3(x, terrain_h(x, z) + up, z)
	if cam.is_position_behind(wp):
		return Vector2(-9999.0, -9999.0)
	return cam.unproject_position(wp)


func _trace_tick(delta: float) -> void:
	if _tr_auto and _age > 1.5 and not _paused:
		_tr_auto = false
		_trace_start()
		return
	if not trace_on or _paused or _tr_phase < 0 or _tr_phase >= 4:
		return
	_tr_t += delta
	var vs := get_viewport().get_visible_rect().size
	match _tr_phase:
		0:
			_tr_bead = Vector2(0.5, 0.46)
			if _tr_t >= TR_INTRO:
				_trace_phase(1)
		1:
			_tr_bead = _tr_pursuit_pos(_tr_t)
			if _tr_t >= TR_PURSUIT:
				_trace_phase(2)
		2:
			var i := mini(int(_tr_t / TR_JUMP_HOLD), _tr_jx.size() - 1)
			_tr_bead = Vector2(float(_tr_jx[i]), float(_tr_jy[i]))
			if _tr_t >= TR_JUMPS:
				_trace_phase(3)
		3:
			var zt := spos.z - 38.0
			var sp := _tr_world_px(_safe_x_at(zt), zt, 0.5)
			if sp.x > -9000.0:
				_tr_bead = Vector2(clampf(sp.x / vs.x, 0.02, 0.98), clampf(sp.y / vs.y, 0.05, 0.95))
			if _tr_t >= TR_CARVE or _finished:
				_trace_phase(4)
	if _tr_phase < 1 or _tr_phase > 3:
		return
	_tr_acc += delta
	while _tr_acc >= 1.0 / TR_HZ:
		_tr_acc -= 1.0 / TR_HZ
		_tr_record(vs)


func _tr_record(vs: Vector2) -> void:
	_tr_total += 1
	if not _eye_on or _cursor_px == Vector2.ZERO or GazeProvider.confidence < 0.5:
		_tr_miss += 1
		return
	var off := 0.0
	var need := 0.0
	if _tr_phase == 3:
		off = spos.x - _safe_x_at(spos.z)
		need = _auto_steer()
	var raw := -1.0
	if not GazeProvider._limb_buf.is_empty():
		raw = (GazeProvider._limb_buf.back() as Vector2).x       # the iris-in-eye reading as it came from the camera, before any smoothing
	# 9 head yaw (rad), 10 screen-gaze x from the face geometry, 11 smoothed iris-in-eye x: candidate signals, all fitted against the dot afterwards
	(_tr_samp[_tr_phase] as Array).append(PackedFloat32Array([_tr_t, _tr_bead.x, _tr_bead.y, _cursor_px.x / vs.x, _cursor_px.y / vs.y, off, steer, need, raw, GazeProvider.head_rpy.x, GazeProvider.direct.x, GazeProvider.eih.x]))


## Least squares of column ycol on the columns xcols (shifted `lag` samples later). Columns are standardised first. Returns the fit error as a
## spread in the units of ycol (screen fraction) and the correlation of the fit with the dot.
func _tr_ols(s: Array, ycol: int, xcols: Array, lag: int) -> Dictionary:
	var k := xcols.size()
	var rows: Array = []
	for i in s.size():
		var j := i + lag
		if j < 0 or j >= s.size():
			continue
		var r: Array = [(s[i] as PackedFloat32Array)[ycol]]
		for c in xcols:
			r.append((s[j] as PackedFloat32Array)[int(c)])
		rows.append(r)
	var n := rows.size()
	if n < 40:
		return {"r": -2.0, "err": 1.0}
	var mu: Array = []
	var sd: Array = []
	for c in k + 1:
		var m := 0.0
		for r in rows:
			m += float(r[c])
		m /= float(n)
		var v := 0.0
		for r in rows:
			v += (float(r[c]) - m) * (float(r[c]) - m)
		mu.append(m)
		sd.append(maxf(sqrt(v / float(n)), 1.0e-9))
	var A: Array = []
	var b: Array = []
	for a in k:
		A.append([])
		for c in k:
			(A[a] as Array).append(0.0)
		b.append(0.0)
	for r in rows:
		for a in k:
			var xa := (float(r[a + 1]) - float(mu[a + 1])) / float(sd[a + 1])
			b[a] += xa * (float(r[0]) - float(mu[0]))
			for c in k:
				A[a][c] += xa * (float(r[c + 1]) - float(mu[c + 1])) / float(sd[c + 1])
	for a in k:
		A[a][a] += 1.0e-6 * float(n)
	for c in k:
		var p := c
		for r2 in range(c + 1, k):
			if absf(A[r2][c]) > absf(A[p][c]):
				p = r2
		var tmp = A[c]
		A[c] = A[p]
		A[p] = tmp
		var tb = b[c]
		b[c] = b[p]
		b[p] = tb
		for r2 in range(c + 1, k):
			var f: float = A[r2][c] / A[c][c]
			for cc in range(c, k):
				A[r2][cc] -= f * A[c][cc]
			b[r2] -= f * b[c]
	var w: Array = []
	w.resize(k)
	for c in range(k - 1, -1, -1):
		var acc: float = b[c]
		for cc in range(c + 1, k):
			acc -= float(A[c][cc]) * float(w[cc])
		w[c] = acc / A[c][c]
	var sse := 0.0
	for r in rows:
		var pred := 0.0
		for a in k:
			pred += float(w[a]) * (float(r[a + 1]) - float(mu[a + 1])) / float(sd[a + 1])
		var e := float(r[0]) - float(mu[0]) - pred
		sse += e * e
	var vy := float(sd[0]) * float(sd[0])
	var ev := sse / float(n)
	return {"r": sqrt(maxf(1.0 - ev / vy, 0.0)), "err": sqrt(ev)}


## Every candidate signal (and the useful combinations) fitted against the dot over the follow and jump phases, each at its own best delay.
func _tr_signals() -> Dictionary:
	var s: Array = (_tr_samp[1] as Array) + (_tr_samp[2] as Array)
	var cands := {"iris": [8], "irisSmooth": [11], "screenGaze": [10], "head": [9], "iris+head": [8, 9], "screen+head": [10, 9], "all": [8, 9, 10]}
	var out := {}
	for nm in cands:
		var best: Dictionary = {"r": -2.0, "err": 1.0}
		var bl := 0
		for lag in range(-3, 31, 2):
			var f := _tr_ols(s, 1, cands[nm], lag)
			if float(f["r"]) > float(best["r"]):
				best = f
				bl = lag
		out[nm] = {"r": snappedf(float(best["r"]), 0.01), "errPct": snappedf(float(best["err"]) * 100.0, 0.1), "lagMs": int(roundf(float(bl) * 1000.0 / TR_HZ))}
	var hy := PackedFloat32Array()
	for e in s:
		hy.append(rad_to_deg((e as PackedFloat32Array)[9]))
	out["headYawStdDeg"] = snappedf(_tr_std(hy), 0.1) if hy.size() > 3 else -1.0
	return out


# ---- analysis
## Fit of series ci against series bi with ci shifted `lag` samples later: Pearson r, slope, intercept, residual spread.
func _tr_lagfit(s: Array, i0: int, i1: int, bi: int, ci: int, lag: int) -> Dictionary:
	var n := 0
	var sb := 0.0
	var sc := 0.0
	var sbb := 0.0
	var scc := 0.0
	var sbc := 0.0
	for i in range(i0, mini(i1, s.size())):
		var j := i + lag
		if j < 0 or j >= s.size():
			continue
		var b: float = (s[i] as PackedFloat32Array)[bi]
		var c: float = (s[j] as PackedFloat32Array)[ci]
		n += 1
		sb += b
		sc += c
		sbb += b * b
		scc += c * c
		sbc += b * c
	if n < 20:
		return {"n": n, "r": -2.0, "slope": 1.0, "icpt": 0.0, "resid": 0.0}
	var fn := float(n)
	var mb := sb / fn
	var mc := sc / fn
	var vb := sbb / fn - mb * mb
	var vc := scc / fn - mc * mc
	var cv := sbc / fn - mb * mc
	if vb < 1.0e-9 or vc < 1.0e-12:
		return {"n": n, "r": -2.0, "slope": 1.0, "icpt": 0.0, "resid": 0.0}
	var slope := cv / vb
	return {"n": n, "r": cv / sqrt(vb * vc), "slope": slope, "icpt": mc - slope * mb, "resid": sqrt(maxf(vc - slope * slope * vb, 0.0))}


func _tr_best(s: Array, i0: int, i1: int, bi: int, ci: int) -> Dictionary:
	var best: Dictionary = {"r": -2.0, "n": 0, "slope": 1.0, "icpt": 0.0, "resid": 0.0}
	var bl := 0
	for lag in range(-3, 31):
		var f := _tr_lagfit(s, i0, i1, bi, ci, lag)
		if float(f["r"]) > float(best["r"]):
			best = f
			bl = lag
	best["lagMs"] = int(roundf(float(bl) * 1000.0 / TR_HZ))
	return best


func _tr_win(s: Array, ta: float, tb: float, ci: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for e in s:
		var t: float = (e as PackedFloat32Array)[0]
		if t >= ta and t < tb:
			out.append((e as PackedFloat32Array)[ci])
	return out


func _tr_mean(a: PackedFloat32Array) -> float:
	if a.size() < 3:
		return NAN
	var m := 0.0
	for v in a:
		m += v
	return m / float(a.size())


func _tr_std(a: PackedFloat32Array) -> float:
	var m := _tr_mean(a)
	if is_nan(m):
		return NAN
	var q := 0.0
	for v in a:
		q += (v - m) * (v - m)
	return sqrt(q / float(a.size()))


func _tr_median(a: Array) -> float:
	if a.is_empty():
		return NAN
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])


func _tr_jump_stats() -> Dictionary:
	var s: Array = _tr_samp[2]
	var t50s: Array = []
	var errs: Array = []
	var overs: Array = []
	var jit: Array = []
	var missed := 0
	var prev_x := 0.5
	for k in _tr_jx.size():
		var t0 := float(k) * TR_JUMP_HOLD
		var tx := float(_tr_jx[k])
		var st := _tr_mean(_tr_win(s, t0 + 1.2, t0 + TR_JUMP_HOLD, 3))
		if is_nan(st):
			missed += 1
			prev_x = tx
			continue
		errs.append(absf(st - tx))
		jit.append(_tr_std(_tr_win(s, t0 + 1.2, t0 + TR_JUMP_HOLD, 3)))
		var p0 := _tr_mean(_tr_win(s, t0 - 0.2, t0, 3))
		if k > 0 and not is_nan(p0):
			var travel := st - p0
			if absf(travel) < 0.05:
				missed += 1
			else:
				var dir := signf(travel)
				var ov := 0.0
				var got := -1.0
				for e in s:
					var ee := e as PackedFloat32Array
					if ee[0] < t0 or ee[0] > t0 + 1.2:
						continue
					if got < 0.0 and (ee[3] - p0) * dir >= 0.5 * absf(travel):
						got = (ee[0] - t0) * 1000.0
					ov = maxf(ov, (ee[3] - st) * dir)
				if got >= 0.0:
					t50s.append(got)
				overs.append(ov)
		prev_x = tx
	var worst := 0.0
	for v in t50s:
		worst = maxf(worst, float(v))
	return {"reactMs": int(_tr_median(t50s)) if not t50s.is_empty() else -1, "worstMs": int(worst), "landErr": _tr_median(errs), "overshoot": _tr_median(overs), "stillJitter": _tr_median(jit), "missed": missed, "jumps": _tr_jx.size() - 1}


func _trace_finish() -> void:
	autopilot = true
	var res: Dictionary = {}
	# 1 FOLLOW
	var s1: Array = _tr_samp[1]
	var h := s1.size() / 2
	var f_all := _tr_best(s1, 0, s1.size(), 1, 3)
	var f_slow := _tr_best(s1, 0, h, 1, 3)
	var f_fast := _tr_best(s1, h, s1.size(), 1, 3)
	res["follow"] = {"samples": s1.size(), "r": snappedf(float(f_all["r"]), 0.01), "lagMs": f_all["lagMs"], "lagSlowMs": f_slow["lagMs"], "lagFastMs": f_fast["lagMs"], "gain": snappedf(float(f_all["slope"]), 0.01), "offset": snappedf(float(f_all["icpt"]), 0.001), "wobble": snappedf(float(f_all["resid"]), 0.001)}
	# 2 JUMP
	var js := _tr_jump_stats()
	res["jump"] = {"reactMs": js["reactMs"], "worstMs": js["worstMs"], "landErr": snappedf(float(js["landErr"]), 0.001) if not is_nan(float(js["landErr"])) else -1.0, "overshoot": snappedf(float(js["overshoot"]), 0.001) if not is_nan(float(js["overshoot"])) else -1.0, "stillJitter": snappedf(float(js["stillJitter"]), 0.001) if not is_nan(float(js["stillJitter"])) else -1.0, "missed": js["missed"], "jumps": js["jumps"]}
	# 3 DOWNHILL
	var s3: Array = _tr_samp[3]
	var sum_off := 0.0
	var within := 0
	var sum_gz := 0.0
	for e in s3:
		var ee := e as PackedFloat32Array
		sum_off += absf(ee[5])
		if absf(ee[5]) < 2.5:
			within += 1
		sum_gz += absf(ee[3] - ee[1])
	var n3 := maxi(s3.size(), 1)
	var f_st := _tr_best(s3, 0, s3.size(), 7, 6)
	res["carve"] = {"samples": s3.size(), "offLineM": snappedf(sum_off / float(n3), 0.1), "withinPct": int(100.0 * float(within) / float(n3)), "gazeOnLineErr": snappedf(sum_gz / float(n3), 0.001), "steerLagMs": f_st["lagMs"], "steerR": snappedf(float(f_st["r"]), 0.01), "crashes": crashes - _tr_crash0, "barriers": _passed_ok - _tr_pass0}
	# tracker health and the settings in force
	res["tracker"] = {"fps": snappedf(float(GazeProvider._pkt_times.size()) / 2.0, 0.1), "latencyMs": int(GazeProvider.trk_lat_ms), "modelMs": int(GazeProvider.trk_inf_ms), "detectMs": int(GazeProvider.trk_det_ms), "delegate": GazeProvider.trk_delegate, "video": GazeProvider.trk_video, "renderScale": snappedf(_rs, 0.01), "frameMs": {"physics": snappedf(_pf_phys, 0.01), "hud": snappedf(_pf_hud, 0.01), "focus": snappedf(_pf_focus, 0.01), "poll": snappedf(GazeProvider.poll_ms, 0.01)}, "faceCropPx": GazeProvider.trk_roi, "eyePatches": GazeProvider.trk_patches, "cropMoves": GazeProvider.trk_roi_moves, "cropLost": GazeProvider.trk_roi_lost, "camFrames": GazeProvider.trk_cam_frames, "dropped": GazeProvider.trk_dropped, "gameFps": int(Engine.get_frames_per_second()), "signalLostPct": int(100.0 * float(_tr_miss) / float(maxi(_tr_total, 1))), "eyeWeights": [snappedf(GazeProvider.eye_w.x, 0.01), snappedf(GazeProvider.eye_w.y, 0.01)], "eyesOnly": eyes_only and GazeProvider.eih_ok}
	res["signals"] = _tr_signals()
	var suggest := reach
	var gain := float(f_all["slope"])
	if float(f_all["r"]) >= 0.6 and gain > 0.4 and gain < 2.5:
		suggest = clampf(reach / gain, 0.6, 4.0)
	res["tune"] = {"reach": snappedf(reach, 0.01), "suggestReach": snappedf(suggest, 0.01), "smoothMs": int(look_smooth * 1000.0), "steerRate": steer_rate, "zoneScale": snappedf(_zone_scale, 0.01), "curve": snappedf(steer_curve, 0.01), "assist": carve_assist}
	# the raw series (15 per second: time, dot x, raw iris-in-eye x, cursor x) for fitting the smoothing offline
	var csv := PackedStringArray(["phase,t,dotx,raw,cursorx,headDeg,screenGaze,irisSmooth"])
	for ph in [1, 2]:
		var sa: Array = _tr_samp[ph]
		var si := 0
		while si < sa.size():
			var e := sa[si] as PackedFloat32Array
			csv.append("%d,%.2f,%.3f,%.4f,%.3f,%.1f,%.3f,%.4f" % [ph, e[0], e[1], e[8], e[3], rad_to_deg(e[9]), e[10], e[11]])
			si += 2
	res["seriesCsv"] = "\n".join(csv)
	_tr_res = res
	_tr_build_lines()
	_trace_copy()
	var brief := res.duplicate()
	brief.erase("seriesCsv")
	print("TRACE ", JSON.stringify(brief))


func _tr_grade(v: float, good: float, ok: float) -> Color:
	if v <= good:
		return Color(0.5, 1.0, 0.6)
	if v <= ok:
		return Color(1.0, 0.85, 0.4)
	return Color(1.0, 0.5, 0.45)


func _tr_build_lines() -> void:
	var fo: Dictionary = _tr_res["follow"]
	var jp: Dictionary = _tr_res["jump"]
	var cv: Dictionary = _tr_res["carve"]
	var tk: Dictionary = _tr_res["tracker"]
	var tn: Dictionary = _tr_res["tune"]
	var L: Array = []
	L.append(["GAZE TRACE RESULTS", Color(1, 1, 1), 26])
	L.append(["FOLLOW  gaze tracks the dot: r %.2f   scale x%.2f   wobble %.1f%% of screen" % [float(fo["r"]), float(fo["gain"]), float(fo["wobble"]) * 100.0], _tr_grade(1.0 - float(fo["r"]), 0.1, 0.25), 16])
	L.append(["        lag %d ms   (slow sweep %d ms, fast sweep %d ms)" % [int(fo["lagMs"]), int(fo["lagSlowMs"]), int(fo["lagFastMs"])], _tr_grade(float(fo["lagMs"]), 150.0, 280.0), 16])
	L.append(["JUMP    reaction %d ms (worst %d)   lands %.1f%% off   overshoot %.1f%%" % [int(jp["reactMs"]), int(jp["worstMs"]), float(jp["landErr"]) * 100.0, float(jp["overshoot"]) * 100.0], _tr_grade(float(jp["reactMs"]), 330.0, 520.0), 16])
	L.append(["        held still: jitter %.1f%%   missed %d of %d jumps" % [float(jp["stillJitter"]) * 100.0, int(jp["missed"]), int(jp["jumps"])], _tr_grade(float(jp["stillJitter"]), 0.02, 0.04), 16])
	L.append(["DOWNHILL   %.1f m off the line, %d%% within 2.5 m   crashes %d   barriers %d" % [float(cv["offLineM"]), int(cv["withinPct"]), int(cv["crashes"]), int(cv["barriers"])], _tr_grade(float(cv["offLineM"]), 3.0, 6.0), 16])
	L.append(["        eyes on the line within %.1f%%   steering lag %d ms" % [float(cv["gazeOnLineErr"]) * 100.0, int(cv["steerLagMs"])], _tr_grade(float(cv["steerLagMs"]), 250.0, 450.0), 16])
	L.append(["TRACKER %d frames/s (%d dropped)   latency %d ms   model %d ms   game %d/s   lost %d%%" % [int(float(tk["fps"])), int(tk["dropped"]), int(tk["latencyMs"]), int(tk["modelMs"]), int(tk["gameFps"]), int(tk["signalLostPct"])], _tr_grade(30.0 - float(tk["fps"]), 4.0, 10.0), 16])
	var sg: Dictionary = _tr_res["signals"]
	L.append(["SIGNALS error vs dot, %% of screen (head moved %.1f deg):  iris %.1f  screen %.1f  head %.1f  iris+head %.1f  all %.1f" % [float(sg["headYawStdDeg"]), float(sg["iris"]["errPct"]), float(sg["screenGaze"]["errPct"]), float(sg["head"]["errPct"]), float(sg["iris+head"]["errPct"]), float(sg["all"]["errPct"])], Color(0.8, 0.9, 1.0), 16])
	L.append(["", Color(1, 1, 1), 12])
	var adv: Array = []
	var gain: float = float(fo["gain"])
	if float(fo["r"]) < 0.6:
		adv.append("Barely followed the dot: check light, face in view, glasses glare.")
	elif absf(gain - 1.0) > 0.15:
		adv.append("Your gaze moved x%.2f as far as the dot: set REACH about x%.2f (now x%.2f)." % [gain, float(tn["suggestReach"]), float(tn["reach"])])
	if int(fo["lagMs"]) > 250:
		adv.append("Late by %d ms: the tracker adds %d ms, smoothing %d ms: try SNAPPIER." % [int(fo["lagMs"]), int(maxf(float(tk["latencyMs"]), 0.0)), int(tn["smoothMs"])])
	if float(fo["wobble"]) > 0.045 or float(jp["stillJitter"]) > 0.035:
		adv.append("Jittery: try STEADIER, or more light on your face.")
	if int(tk["signalLostPct"]) > 10:
		adv.append("Lost your eyes %d%% of the time." % int(tk["signalLostPct"]))
	if float(tk["fps"]) < 20.0:
		adv.append("Camera only %d frames/s: more light, or ?fast." % int(float(tk["fps"])))
	if adv.is_empty():
		adv.append("Tracking looks healthy. Copy the report and send it for tuning.")
	for a in adv:
		L.append([String(a), Color(0.85, 0.92, 1.0), 15])
	L.append(["", Color(1, 1, 1), 12])
	L.append(["tap or press C to copy the report   R run again   T end", Color(1, 1, 1, 0.75), 15])
	if _tr_note != "":
		L.append([_tr_note, Color(0.6, 1.0, 0.7), 15])
	_tr_lines = L


# ---- steering safety: a gaze signal that flails or disappears must never throw the board around
var _fl_clock: float = 0.0
var _fl_side: int = 0
var _fl_flips: Array = []
var _flail_t: float = 0.0
var _lost_t: float = 0.0
var _ev: Array = []
var _ev_ex_sign: float = 1.0
var _ev_conf_low: bool = false
var _ev_head_far: bool = false


func _note(msg: String) -> void:
	_log_ev(msg)


func _log_ev(msg: String) -> void:
	_ev.append("%.0fs %dm %s" % [_clock, int(maxf(-spos.z, 0.0)), msg])
	if _ev.size() > 40:
		_ev.remove_at(0)


## The eye steering, checked: if the look keeps flipping hard from one side to the other, or the tracker has stopped, the board is eased back toward straight.
func _guard_gaze(s: float, delta: float) -> float:
	_fl_clock += delta
	var side := 0
	if s > 0.5:
		side = 1
	elif s < -0.5:
		side = -1
	if side != 0 and side != _fl_side:
		if _fl_side != 0:
			_fl_flips.append(_fl_clock)
		_fl_side = side
	while not _fl_flips.is_empty() and _fl_clock - float(_fl_flips[0]) > 1.2:
		_fl_flips.remove_at(0)
	if _fl_flips.size() >= 3 and _flail_t <= 0.0:
		_log_ev("steering flipped side %d times in 1.2 s: softened (conf %.2f, spread %.3f)" % [_fl_flips.size(), GazeProvider.confidence, _stat_std])
		_toast("Tracking jittery: steering softened", Color(1.0, 0.8, 0.4))
		_flail_t = 2.0
		_fl_flips.clear()
	_flail_t = maxf(_flail_t - delta, 0.0)
	# events for the report: what the tracker was doing when things went wrong
	if _ex_sign != _ev_ex_sign:
		_ev_ex_sign = _ex_sign
		_log_ev("eye direction flipped to %s" % ("normal" if _ex_sign > 0.0 else "reversed"))
	var low := GazeProvider.confidence < 0.5
	if low != _ev_conf_low:
		_ev_conf_low = low
		_log_ev("tracker confidence %s (%.2f)" % ["low" if low else "back", GazeProvider.confidence])
	var turn := absf(rad_to_deg(GazeProvider.head_rpy.x))
	var far := turn > 25.0
	if far != _ev_head_far:
		_ev_head_far = far
		_log_ev("head turned %s (%.0f deg)" % ["far" if far else "back", turn])
	var live := GazeProvider.backend != GazeProvider.Backend.CAMERA or GazeProvider._camera_fresh()
	if not live:
		if _lost_t <= 0.0:
			_log_ev("tracker stopped sending frames")
			_toast("Lost your eyes", Color(1.0, 0.5, 0.45))
		_lost_t = 1.0
		return 0.0
	_lost_t = maxf(_lost_t - delta, 0.0)
	return s * (0.3 if _flail_t > 0.0 else 1.0)


func _trace_copy() -> void:
	DisplayServer.clipboard_set(JSON.stringify(_pause_report(), "  "))
	_tr_note = "report copied"
	_tr_build_lines()


func _draw_trace(font: Font, s: Vector2, k: float) -> void:
	if _tr_phase < 0:
		return
	var m := 24.0 * k
	if _tr_phase == 4:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.07, 0.15, 0.86))
		var y := m
		for ln in _tr_lines:
			var sz: int = int(ln[2])
			y += float(sz) * 1.5 * k
			_text(font, Vector2(m, y), String(ln[0]), sz, ln[1])
		return
	var cy := Color(1.0, 0.15, 0.7)
	if _tr_phase == 1:
		var pts := PackedVector2Array()
		for i in 13:
			pts.append(_tr_pursuit_pos(minf(_tr_t + float(i) * 0.1, TR_PURSUIT)) * s)
		_hud.draw_polyline(pts, Color(cy.r, cy.g, cy.b, 0.35), 4.0 * k)
	elif _tr_phase == 3:
		var rp := PackedVector2Array()
		var d := 6.0
		while d < 150.0:
			var zt := spos.z - d
			var p := _tr_world_px(_safe_x_at(zt), zt, 0.4)
			if p.x > -9000.0:
				rp.append(p)
			d += 7.0
		if rp.size() > 1:
			_hud.draw_polyline(rp, Color(cy.r, cy.g, cy.b, 0.6), 5.0 * k)
	var bp := _tr_bead * s
	_hud.draw_circle(bp, 26.0 * k, Color(cy.r, cy.g, cy.b, 0.35))
	_hud.draw_arc(bp, 26.0 * k, 0.0, TAU, 28, Color(0, 0, 0, 0.8), 6.0 * k)
	_hud.draw_arc(bp, 26.0 * k, 0.0, TAU, 28, Color(1, 1, 1, 0.95), 3.0 * k)
	_hud.draw_circle(bp, 9.0 * k, Color(0, 0, 0, 0.8))
	_hud.draw_circle(bp, 7.0 * k, Color(1, 1, 1, 1.0))
	var title := ""
	var left := 0.0
	match _tr_phase:
		0:
			title = "GAZE TRACE: follow the glowing dot with your eyes"
			left = TR_INTRO - _tr_t
		1:
			title = "1 of 3  FOLLOW the dot"
			left = TR_PURSUIT - _tr_t
		2:
			title = "2 of 3  look at the dot each time it jumps"
			left = TR_JUMPS - _tr_t
		3:
			title = "3 of 3  DOWNHILL: steer with your eyes along the line"
			left = TR_CARVE - _tr_t
	_ctext(font, m + 64.0 * k, "%s   %d s" % [title, int(ceilf(maxf(left, 0.0)))], 22, Color(0.8, 0.95, 1.0))
