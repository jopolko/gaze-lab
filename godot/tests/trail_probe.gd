extends Node
## The forest trail: with the eyes resting on the middle, does the board ride the trail, pass the poles on the right side and stay out of the trees?


func _ready() -> void:
	Prog.save_enabled = false
	Prog.reset()
	var level: MainLevel = load("res://scenes/MainLevel.tscn").instantiate()
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	await get_tree().process_frame
	level.director.autostart = false
	Game.touch_mode = false
	level.load_level(11)
	for i in 5:
		await get_tree().physics_frame
	var rig: RunRig = level._dh as RunRig
	rig.set_physics_process(false)
	rig.set_process(false)
	for run in 3:
		rig.trail = true
		rig.bend = OS.get_environment("BEND") != ""
		if OS.get_environment("MODE") != "":
			rig.mode = OS.get_environment("MODE")
		rig._restart()
		var dt := 1.0 / 60.0
		var off_max := 0.0
		var off_sum := 0.0
		var n := 0
		var air := 0.0
		var high := 0.0
		var vmax := 0.0
		var gl_t := {}
		var px_prev := 0.0
		var vx_prev := 0.0
		var sv_last := 0.0
		var pk_last := ""
		var jolt := 0.0
		var xmin := 0.0
		var hrev := 0
		var h_ext := 0.0
		var h_dir := 0.0
		var h_prev := 0.0
		var hrate := 0.0
		var xmax := 0.0
		var hmax := 0.0
		var tg: Array = []
		for i in 60 * 90:
			GazeProvider.set_scripted(Vector2(0.5, 0.45))
			if OS.get_environment("PICK") != "":
				rig.pick_override = 1.0 if (int(-rig.spos.z / 400.0) % 2 == 0) else -1.0          # a look held to one side, changing sides every 400 m
			if OS.get_environment("GLANCE") != "":
				# a short glance (0.5 s) at one side as each pair of things comes up, the left one and the right one in turn; eyes on the middle the rest of the time
				var far := float(OS.get_environment("GLANCE"))
				var cl: Dictionary = rig._card_l
				var cr: Dictionary = rig._card_r
				var c: Dictionary = cl if not cl.is_empty() else cr
				rig.zone_test = 0
				rig.zn_test = 99.0
				if OS.get_environment("SWITCH") != "" and not tg.is_empty() and not tg.back()["closed"]:
					# after the first glance, the eyes rest on the middle for half a second, then look across at the other thing of the same choice for half a second
					var tl: Dictionary = tg.back()
					var gg := int(tl["f"]["g"])
					var swt := float(OS.get_environment("SWT")) if OS.get_environment("SWT") != "" else 1.0
					if gl_t.has(gg) and float(gl_t[gg]) >= 0.5 and float(gl_t[gg]) < swt + 0.6:
						gl_t[gg] = float(gl_t[gg]) + dt
						if float(gl_t[gg]) >= swt:
							var alt: Dictionary = {}
							for cc in [rig._card_l, rig._card_r, rig._card_m]:
								if not (cc as Dictionary).is_empty() and int(cc["g"]) == gg and not is_same(cc, tl["f"]):
									alt = cc
							if not alt.is_empty():
								tl["alt"] = alt
								rig.zone_test = int(alt.get("cs", 0))
								if is_same(rig._line_pick, alt):
									tl["switched"] = true
				if not c.is_empty():
					var g := int(c["g"])
					var want: Dictionary = cl if (g % 2 == 0 and not cl.is_empty()) else (cr if not cr.is_empty() else cl)
					if rig.spos.z - float(want["za"]) < far:
						if not gl_t.has(g) and not (tg.is_empty() or tg.back()["closed"]):
							pass                                   # still on the way to the last thing glanced at: one choice at a time
						elif not gl_t.has(g):
							gl_t[g] = 0.0
							tg.append({"f": want, "picked": false, "got": false, "closed": false, "nx0": rig._feat_nx(want)})
						if gl_t.has(g) and float(gl_t[g]) < (99.0 if OS.get_environment("HOLD") != "" else 0.5):
							gl_t[g] = float(gl_t[g]) + dt
							for t0 in tg:
								if int(t0["f"]["g"]) == g:
									want = t0["f"]                      # the thing this glance began on, whatever the cards show now
							if OS.get_environment("LOOK") == "thing":
								rig.zn_test = rig._feat_nx(want) / 0.75          # eyes on the thing itself, where it is on screen right now
							else:
								rig.zone_test = int(want.get("cs", 0))            # eyes on its look target at the side of the screen
			rig._physics_process(dt)
			if OS.get_environment("NODES") != "" and i == 1500 and run == 0:
				var cnt := {}
				var stack: Array = [level]
				while not stack.is_empty():
					var nd: Node = stack.pop_back()
					for ch in nd.get_children():
						stack.append(ch)
					if nd is MeshInstance3D and (nd as MeshInstance3D).is_visible_in_tree():
						var mm := (nd as MeshInstance3D).mesh
						var key := "Mesh %s %s" % [mm.get_class() if mm != null else "none", ("surfaces %d" % mm.get_surface_count()) if mm != null else ""]
						cnt[key] = int(cnt.get(key, 0)) + 1
					elif nd is MultiMeshInstance3D:
						var k2 := "MultiMesh inst %d" % (nd as MultiMeshInstance3D).multimesh.visible_instance_count
						cnt[k2] = int(cnt.get(k2, 0)) + 1
					elif nd is GPUParticles3D or nd is CPUParticles3D:
						cnt["Particles"] = int(cnt.get("Particles", 0)) + 1
					elif nd is Light3D:
						cnt["Light"] = int(cnt.get("Light", 0)) + 1
				var ks: Array = cnt.keys()
				ks.sort_custom(func(x, y): return int(cnt[x]) > int(cnt[y]))
				for kx in ks.slice(0, 14):
					print("NODES  %5d  %s" % [cnt[kx], kx])
			if OS.get_environment("NXMEAS") != "" and i % 6 == 0:
				for kk in rig._rows:
					for f in (rig._rows[kk] as Dictionary).get("feats", []):
						if f.has("hz") or f["done"]:
							continue
						var dzf: float = rig.spos.z - float(f["za"])
						if dzf > 110.0 or dzf < 0.0:
							continue
						var nxv: float = rig._feat_nx(f)
						if dzf <= 70.0 and not f.has("m70") and nxv != 99.0:
							f["m70"] = nxv * float(f["sd"])
						if nxv == 99.0:
							f["m_off"] = int(f.get("m_off", 0)) + 1
							continue
						f["m_lo"] = minf(float(f.get("m_lo", 9.0)), nxv)
						f["m_hi"] = maxf(float(f.get("m_hi", -9.0)), nxv)
						f["m_n"] = int(f.get("m_n", 0)) + 1
			for t in tg:
				if t["closed"]:
					continue
				var tf: Dictionary = t["f"]
				if is_same(rig._line_pick, tf):
					t["picked"] = true
				if is_same(rig._rail, tf) or rig._feat_got(tf):
					t["got"] = true
				if not t.has("dbg") and rig.spos.z <= float(tf["za"]):
					t["dbg"] = "at start: dx %.1f  grounded %s  y above %.1f  pick same %s  hurt %.1f" % [rig.spos.x - rig._feat_x(tf, rig.spos.z), rig.grounded, rig.spos.y - rig.terrain_h(rig.spos.x, rig.spos.z), is_same(rig._line_pick, tf), rig.hurt_t]
				if OS.get_environment("TRACE") != "" and i % 6 == 0:
					if not t.has("log"):
						t["log"] = []
					(t["log"] as Array).append("z%d zone%d x%.0f pick[%s] rail[%s] T[%s %d sec%d]" % [int(-rig.spos.z), rig.zone_test, rig.spos.x, ("%s %d" % [rig._line_pick["kind"], int(-float(rig._line_pick["za"]))]) if not rig._line_pick.is_empty() else "", ("%d" % int(-float(rig._rail["za"]))) if not rig._rail.is_empty() else "", tf["kind"], int(-float(tf["za"])), int(rig._feat_nx(tf) * 100.0)] + " dx %.1f yrel %.1f gr %s hurt %.1f inrows %s" % [rig.spos.x - rig._feat_x(tf, rig.spos.z), rig.spos.y - (rig._rail_y(tf, rig.spos.z) if tf["kind"] == "rail" else rig.spos.y), rig.grounded, rig.hurt_t, _in_rows(rig, tf)])
				if tf["done"]:
					t["closed"] = true
			for t2 in tg:
				if t2.has("alt"):
					var al: Dictionary = t2["alt"]
					if is_same(rig._rail, al):
						t2["alt_got"] = true
					if al["done"] and not t2.has("alt_chk"):
						t2["alt_chk"] = true
						if rig._feat_got(al):
							t2["alt_got"] = true
			rig._process(dt)
			var vx_now: float = (rig.spos.x - px_prev) / dt
			if i > 120 and rig._rail.is_empty() and rig.hurt_t <= 0.0:
				jolt = maxf(jolt, absf(vx_now - vx_prev))
			if OS.get_environment("JOLT") != "" and i > 120 and absf(vx_now - vx_prev) > 12.0:
				print("JOLT(prev slide_v %.1f, prev pick %s) t%.2f dvx %.1f  vx %.1f->%.1f  rail %s grounded %s hurt %.1f slide_v %.1f steer %.2f heading %.1f pick %s lockage %.1f vel.x %.1f" % [sv_last, pk_last, float(i) * dt, vx_now - vx_prev, vx_prev, vx_now, not rig._rail.is_empty(), rig.grounded, rig.hurt_t, rig._slide_v, rig.steer, rad_to_deg(rig.heading), (rig._line_pick["kind"] + str(int(rig._line_pick["sd"]))) if not rig._line_pick.is_empty() else "-", rig._lock_age, rig.vel.x])
			vx_prev = vx_now
			sv_last = rig._slide_v
			pk_last = (rig._line_pick["kind"] + str(int(rig._line_pick["sd"]))) if not rig._line_pick.is_empty() else "-"
			xmin = minf(xmin, rig.spos.x)
			xmax = maxf(xmax, rig.spos.x)
			hmax = maxf(hmax, absf(rad_to_deg(atan2(rig.vel.x, maxf(-rig.vel.y, 1.0)))))
			var hd := rad_to_deg(atan2(rig.vel.x, maxf(-rig.vel.y, 1.0)))
			if i > 120:
				hrate = maxf(hrate, absf(hd - h_prev) / dt)
				var sl := signf(hd - h_prev) if absf(hd - h_prev) > 0.02 else h_dir
				if sl != h_dir and h_dir != 0.0:
					if absf(h_prev - h_ext) > 8.0:
						hrev += 1
					h_ext = h_prev
				h_dir = sl
			h_prev = hd
			px_prev = rig.spos.x
			if -rig.spos.z > 200.0 and not rig._finished:
				var off := absf(rig.spos.x - rig.trail_x(rig.spos.z))
				off_max = maxf(off_max, off)
				off_sum += off
				n += 1
				if not rig.grounded:
					air += dt
					high = maxf(high, rig.spos.y - rig.terrain_h(rig.spos.x, rig.spos.z))
				vmax = maxf(vmax, rig.vel.length())
		print("TRAIL run %d: %d m in 90 s, crashes %d, poles %d (clean %d, shaved %d, wrong side %d), off the middle %.1f m on average and %.1f m at worst, %.1f s in the air (highest %.1f m), top speed %d km/h, best flow x%.1f, score %d" % [run, int(-rig.spos.z), rig.crashes, rig.poles_clean + rig.poles_wrong, rig.poles_clean, rig.poles_shaved, rig.poles_wrong, off_sum / maxf(float(n), 1.0), off_max, air, high, int(vmax * 3.6), rig.best_flow, rig.score])
		print("TRAIL   %s: jumps %d of %d, rails %d of %d (%d m), treats %d of %d (orbs %d), choices %d, chosen %d (left %d, right %d), time penalty %.0f s, pops %d" % [rig.mode, rig.jumps_done, rig.jumps_built, rig.rails_done, rig.rails_built, int(rig.rail_m), rig.buffs_got, rig.buffs_spawned, rig.orbs_got, rig.choices_built, rig.picks, int(rig.picks_side.get(-1, 0)), int(rig.picks_side.get(1, 0)), rig.time_pen, rig.pops_flat])
		print("TRAIL   swing: %d turns of the board's heading back the other way by more than 8 deg, fastest heading change %d deg/s" % [hrev, int(hrate)])
		print("TRAIL   weave: board x from %.1f to %.1f m, steepest heading %.1f deg" % [xmin, xmax, hmax])
		print("TRAIL   hazards: %d built, %d hit, crashes %d" % [rig.hazards_built, rig.hazards_hit, rig.crashes])
		print("TRAIL   biggest sideways jolt in one frame: %.1f m/s" % jolt)
		print("TRAIL   ", rig.choice_summary(), "  ", rig.choice_n)
		if OS.get_environment("NXMEAS") != "":
			var rs: Array = []
			var s70: Array = []
			var flips := 0
			var offs := 0
			var nn := 0
			for kk in rig._rows:
				for f in (rig._rows[kk] as Dictionary).get("feats", []):
					if f.has("m70"):
						s70.append(float(f["m70"]))
					if f.has("m_n") and int(f["m_n"]) > 8:
						rs.append(float(f["m_hi"]) - float(f["m_lo"]))
						nn += 1
						flips += 1 if (float(f["m_lo"]) < -0.15 and float(f["m_hi"]) > 0.15) else 0
						offs += 1 if int(f.get("m_off", 0)) > 0 else 0
			rs.sort()
			if s70.size() > 2:
				var mu := 0.0
				for v in s70:
					mu += float(v)
				mu /= float(s70.size())
				var sdv := 0.0
				for v in s70:
					sdv += (float(v) - mu) * (float(v) - mu)
				print("TRAIL   NX70: where an object sits across the screen 70 m before it (signed by its lane): mean %.2f, spread (std) %.2f over %d objects" % [mu, sqrt(sdv / float(s70.size())), s70.size()])
			if nn > 0:
				print("TRAIL   NX: %d objects watched over their last 110 m: screen position swings %.2f (median) to %.2f (worst) of the half-screen; %d cross from the left of the screen to the right; %d leave the picture at some point" % [nn, rs[nn / 2], rs[nn - 1], flips, offs])
		if OS.get_environment("DEC") != "":
			for rc in (rig.choice_log as Array).slice(0, 6):
				print("   CHOICE z%d %s/%s verdict %s pick %d got %d  md %s" % [rc["z"], rc["left"], rc["right"], rc["v"], rc["pick"], rc["got"], rc.get("md", [])])
				for de in rc.get("dec", []):
					print("        ", de)
		if OS.get_environment("GLANCE") != "":
			var np := 0
			var ng := 0
			var nc := 0
			var miss: Array = []
			for t in tg:
				if not t["closed"] and rig.spos.z > float(t["f"]["zb"]):
					continue
				nc += 1
				np += 1 if t["picked"] else 0
				ng += 1 if t["got"] else 0
				if not t["got"]:
					if t.has("log") and miss.is_empty():
						for ln in t["log"]:
							print("   ", ln)
					miss.append("%s at %d m %s nx %.2f [%s]" % [t["f"]["kind"], int(-float(t["f"]["za"])), "picked" if t["picked"] else "NOT picked", float(t["nx0"]), t.get("dbg", "")])
			if not tg.is_empty():
				var lb: Dictionary = tg.back()
				print("TRAIL   last glance: %s at %d m, done %s closed %s picked %s got %s; board at %d m, rail %s, hurt %.1f, finished %s" % [lb["f"]["kind"], int(-float(lb["f"]["za"])), lb["f"]["done"], lb["closed"], lb["picked"], lb["got"], int(-rig.spos.z), not rig._rail.is_empty(), rig.hurt_t, rig._finished])
			if OS.get_environment("SWITCH") != "":
				var nsw := 0
				var nalt := 0
				for t in tg:
					if t.has("alt"):
						nalt += 1
						nsw += 1 if t.get("switched", false) else 0
				var ngot := 0
				var lost: Array = []
				for t in tg:
					if t.get("switched", false):
						if t.get("alt_got", false):
							ngot += 1
						elif t.has("alt_chk") or t["closed"]:
							lost.append("%s at %d m" % [t["alt"]["kind"], int(-float(t["alt"]["za"]))])
				print("TRAIL   SWITCHED AND TAKEN: %d of %d   switched but lost: %s" % [ngot, nsw, lost])
				print("TRAIL   SWITCHES: %d of %d looks across at the other thing took the lock" % [nsw, nalt])
			print("TRAIL   GLANCES: %d things glanced at, %d chosen by the game, %d taken by the board   not taken: %s" % [nc, np, ng, miss])
		if rig.crashes > 0:
			print("TRAIL   crash log: ", rig.crash_log)
	get_tree().quit()


func _in_rows(rig, tf: Dictionary) -> bool:
	for kk in rig._rows:
		for f in (rig._rows[kk] as Dictionary).get("feats", []):
			if is_same(f, tf):
				return true
	return false
