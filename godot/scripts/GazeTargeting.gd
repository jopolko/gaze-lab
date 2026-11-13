class_name GazeTargeting
extends Node
## Hands-free gameplay layer ("Dead Eye Goose").
##
##  * Gaze picks things: enemies, props and loot within a snap radius of the gaze
##    point (cone-snap), with a short grace period so webcam jitter never resets a lock.
##  * STARE at an enemy/prop to LOCK it (up to 3). The first lock drops the world
##    into bullet time; a hard blink (or the timer running out) fires the volley.
##  * STARE at loot to magnetise it. STARE at the floor to walk there (auto-stops
##    when enemies get close: that's your "stage").
##  * Looking near the screen edge pans the camera (dead zone in the middle).
##  * Face gestures: wink-left kick, wink-right next weapon, mouth-open burp
##    shockwave, eyebrows jump.
## Low tracking confidence widens the snap radius and slows dwell timers.

const DWELL_TARGET := 0.35
const DWELL_PICKUP := 0.2
const DWELL_FLOOR := 0.7
const GRACE := 0.18
const MAX_TAGS := 3
const BULLET_SCALE := 0.35
const TAG_WINDOW := 2.0
const SNAP_PX := 95.0
const DEAD_ZONE := Vector2(0.27, 0.22)
const PAN_YAW := 1.7
const PAN_PITCH := 1.0

var pan_enabled: bool = true
var player: PlayerController
var tags: Array[Node3D] = []
var target: Node3D = null
var dwell: float = 0.0
var need: float = DWELL_TARGET
var waypoint: Vector3 = Vector3.INF
var bullet_time: bool = false

## Tutorial checklist shown while hands-free is on; ticks itself off.
var guide: Dictionary = {"lock": false, "fire": false, "swap": false, "move": false}
var _guide_t: float = 0.0
## Peek level: eyes lock exposed baddies, blink fires at the lock, resting your gaze on a rock sniffs behind it.
var peek_lock: EnemyAI = null
var sniffs: int = 0
var _peek_target: EnemyAI = null
var _peek_dwell: float = 0.0
var _sniff_cover: int = -1
var _sniff_t: float = 0.0
var _sniff_cd: float = 0.0
var _grace: float = 0.0
var _window: float = 0.0
var _floor_pt: Vector3 = Vector3.INF
var _floor_dwell: float = 0.0
var _wp_time: float = 0.0
var _volleying: bool = false
var _burp_cd: float = 0.0
var _lock_cd: float = 0.0
var _wink_cd: float = 0.0
var _walk_move: Vector2 = Vector2.ZERO
var _lvl: int = -1
var _gaze_px: Vector2 = Vector2.ZERO
## Peek accuracy: a short history of the gaze (so a blink shot uses where you looked just BEFORE the lid closed), and shots waiting to be scored.
var _gh: Array = []
var _pending: Array = []
var _stat_shots: int = 0
var _eye_look: Vector2 = Vector2.ZERO
var _eye_look_out: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("gaze")
	player = (get_parent() as MainLevel).player
	pan_enabled = not Game.demo_mode   # the demo arena is faced forward; gaze never spins the view
	GazeProvider.blinked.connect(_on_blink)
	Game.peek_shot.connect(_on_peek_shot)
	GazeProvider.winked.connect(_on_wink)
	GazeProvider.mouth_opened.connect(_on_mouth)
	GazeProvider.brows_raised.connect(_on_brows)
	GazeProvider.mode_changed.connect(func(on: bool) -> void:
		if on:
			_guide_t = 0.0
		else:
			reset())


func _exit_tree() -> void:
	Game.peek_eye_look = Vector2.ZERO
	AimStats.save()
	if bullet_time:
		Engine.time_scale = 1.0


## Screen radius that counts as "looking at" something. Webcam gaze is coarse (3-5 degrees),
## so it gets a big forgiving radius and the nearest enemy wins.
func _snap() -> float:
	var b := GazeProvider.backend
	if b == GazeProvider.Backend.CAMERA or b == GazeProvider.Backend.UDP:
		return 200.0
	if b == GazeProvider.Backend.TOUCH:
		return 130.0
	return SNAP_PX


func _real(delta: float) -> float:
	return delta / maxf(Engine.time_scale, 0.05)


func _process(delta: float) -> void:
	var rd := _real(delta)
	_burp_cd = maxf(_burp_cd - rd, 0.0)
	_wink_cd = maxf(_wink_cd - rd, 0.0)
	_lock_cd = maxf(_lock_cd - rd, 0.0)
	var lv := get_parent() as MainLevel
	if lv != null and lv.level_index != _lvl:
		_lvl = lv.level_index
		reset()
	if Game.peek_mode and player != null and not player.dead and not GazeProvider.sweep_active:
		_peek_gaze(rd)
	elif peek_lock != null or _peek_target != null:
		_peek_clear()
	if not Game.peek_mode:
		Game.peek_eye_look = Vector2.ZERO
	_score_pending(rd)
	if not GazeProvider.active or player == null or player.dead or GazeProvider.calibrating:
		if target != null or not tags.is_empty() or bullet_time or waypoint != Vector3.INF:
			reset()
		return

	_guide_t += rd
	var cam := player.camera
	_gaze_px = GazeProvider.gaze * get_viewport().get_visible_rect().size
	if pan_enabled:
		_pan(rd)
	var conf := clampf(GazeProvider.confidence, 0.4, 1.0)

	var cand := _pick(cam, _gaze_px, _snap() / conf)
	var cnode := cand.get("node") as Node3D
	if cnode != null and not tags.has(cnode) and _lock_cd <= 0.0:
		if cnode != target:
			target = cnode
			dwell = 0.0
			need = DWELL_PICKUP if cnode.is_in_group("pickups") else DWELL_TARGET
		_grace = GRACE
		_floor_pt = Vector3.INF
		_floor_dwell = 0.0
		dwell += rd * conf
		if dwell >= need:
			_complete(cnode)
	else:
		_grace -= rd
		if _grace <= 0.0:
			target = null
			dwell = maxf(dwell - rd * 2.0, 0.0)
		if cnode == null:
			_floor_step(cam, rd * conf)
		else:
			_floor_pt = Vector3.INF
			_floor_dwell = 0.0

	if bullet_time and not _volleying:
		for i in range(tags.size() - 1, -1, -1):
			var t := tags[i]
			if not is_instance_valid(t) or (t is EnemyAI and (t as EnemyAI).dying):
				tags.remove_at(i)
		if tags.is_empty():
			_end_bullet()
		else:
			_window -= rd
			if _window <= 0.0:
				fire_volley()

	_walk(delta)
	var hm := GazeProvider.head_move
	if hm.length() > 0.3:
		guide["move"] = true
	player.auto_move = (_walk_move + hm).limit_length(1.0)


# --------------------------------------------------------------------------
# Camera pan from gaze position (and head pose when a tracker supplies it)
# --------------------------------------------------------------------------
func _pan(rd: float) -> void:
	var g := GazeProvider.gaze - Vector2(0.5, 0.5)
	var px := signf(g.x) * maxf(absf(g.x) - DEAD_ZONE.x, 0.0) / (0.5 - DEAD_ZONE.x)
	var py := signf(g.y) * maxf(absf(g.y) - DEAD_ZONE.y, 0.0) / (0.5 - DEAD_ZONE.y)
	var k := 0.45 if target != null else 1.0
	player.rotate_y(-px * PAN_YAW * k * rd)
	player.head.rotation.x = clampf(player.head.rotation.x - py * PAN_PITCH * k * rd, -1.2, 1.2)


# --------------------------------------------------------------------------
# Picking
# --------------------------------------------------------------------------
func _pick(cam: Camera3D, gp: Vector2, radius: float) -> Dictionary:
	var found: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as EnemyAI
		if en != null and not en.dying:
			_consider(found, cam, gp, radius, en, en.global_position + Vector3.UP, 0.0, 70.0)
	for p in get_tree().get_nodes_in_group("props"):
		var pn := p as Node3D
		if pn != null:
			_consider(found, cam, gp, radius, pn, pn.global_position, 35.0, 40.0)
	for k in get_tree().get_nodes_in_group("pickups"):
		var kn := k as Node3D
		if kn != null:
			_consider(found, cam, gp, radius, kn, kn.global_position, 10.0, 40.0)
	if found.is_empty():
		return {}
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var space := cam.get_world_3d().direct_space_state
	for f: Array in found:
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, f[2], Game.MASK_WORLD)
		if space.intersect_ray(q).is_empty():
			return {"node": f[1], "pos": f[2]}
	return {}


func _consider(found: Array, cam: Camera3D, gp: Vector2, radius: float, n: Node3D, pos: Vector3, penalty: float, max_dist: float) -> void:
	if cam.is_position_behind(pos) or pos.distance_to(cam.global_position) > max_dist:
		return
	var dv := cam.unproject_position(pos) - gp
	# Webcam gaze is much weaker vertically than horizontally, and enemies stand on the ground,
	# so for camera gaze a vertical miss counts for less than a horizontal one.
	var vy := 1.0
	if GazeProvider.backend == GazeProvider.Backend.CAMERA or GazeProvider.backend == GazeProvider.Backend.UDP:
		vy = 0.4
	var d := Vector2(dv.x, dv.y * vy).length()
	if d < radius:
		found.append([d + penalty, n, pos])


func _complete(n: Node3D) -> void:
	dwell = 0.0
	if n is Pickup:
		(n as Pickup).attract()
		Game.sfx(&"pop", n.global_position)
		return
	if tags.size() >= MAX_TAGS:
		return
	tags.append(n)
	guide["lock"] = true
	Game.sfx(&"pop", n.global_position)
	Game.popup("LOCKED %d/%d" % [tags.size(), MAX_TAGS], n.global_position + Vector3.UP * 1.8, Color(1.0, 0.35, 0.25), 0.8)
	if not bullet_time:
		_begin_bullet()
	_window = 0.5 if tags.size() >= MAX_TAGS else TAG_WINDOW


# --------------------------------------------------------------------------
# Floor-gaze auto-walk
# --------------------------------------------------------------------------
func _floor_step(cam: Camera3D, rd: float) -> void:
	var from := cam.project_ray_origin(_gaze_px)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(_gaze_px) * 45.0, Game.MASK_WORLD)
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.7:
		_floor_pt = Vector3.INF
		_floor_dwell = 0.0
		return
	var pt: Vector3 = hit["position"]
	if _floor_pt == Vector3.INF or pt.distance_to(_floor_pt) > 2.5:
		_floor_pt = pt
		_floor_dwell = 0.0
	_floor_dwell += rd
	if _floor_dwell >= DWELL_FLOOR and not _enemy_near(9.0):
		waypoint = pt
		guide["move"] = true
		_wp_time = 0.0
		_floor_dwell = 0.0
		Game.sfx(&"pop", pt)


func _walk(delta: float) -> void:
	_walk_move = Vector2.ZERO
	if waypoint == Vector3.INF:
		return
	_wp_time += delta
	var to := waypoint - player.global_position
	to.y = 0.0
	if to.length() < 1.6 or _wp_time > 9.0 or _enemy_near(9.0):
		_clear_waypoint()
		return
	player.rotation.y = lerp_angle(player.rotation.y, atan2(-to.x, -to.z), minf(1.0, 4.0 * delta))
	_walk_move = Vector2(0.0, -1.0)


func _enemy_near(radius: float) -> bool:
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as EnemyAI
		if en != null and not en.dying:
			var d := en.global_position - player.global_position
			d.y = 0.0
			if d.length() < radius:
				return true
	return false


func _clear_waypoint() -> void:
	waypoint = Vector3.INF
	_wp_time = 0.0
	if player != null:
		player.auto_move = Vector2.ZERO


# --------------------------------------------------------------------------
# Bullet time + volley
# --------------------------------------------------------------------------
func _begin_bullet() -> void:
	bullet_time = true
	Engine.time_scale = BULLET_SCALE
	player.add_trauma(0.25, 0.4)


func _end_bullet() -> void:
	if bullet_time:
		Engine.time_scale = 1.0
		bullet_time = false


func reset() -> void:
	_peek_clear()
	tags.clear()
	target = null
	dwell = 0.0
	_grace = 0.0
	_floor_pt = Vector3.INF
	_floor_dwell = 0.0
	_clear_waypoint()
	_end_bullet()


func fire_volley() -> void:
	if _volleying or tags.is_empty() or player == null:
		return
	_volleying = true
	guide["fire"] = true
	_lock_cd = 2.0
	var list: Array[Node3D] = tags.duplicate()
	tags.clear()
	var n := list.size()
	for i in n:
		_fire_one(list[i], i, n)
		if i < n - 1:
			await get_tree().create_timer(0.12, true, false, true).timeout
			if not is_inside_tree():
				return
	var tail := 0.4
	var cw := player.weapons.current_weapon()
	if cw != null:
		tail = cw.volley_tail
	await get_tree().create_timer(tail, true, false, true).timeout
	if is_inside_tree():
		_end_bullet()
		_lock_cd = 0.8
		tags.clear()
	_volleying = false


func _fire_one(node: Node3D, idx: int, n: int) -> void:
	if not is_instance_valid(node):
		return
	var w := player.weapons.current_weapon()
	var to := node.global_position + (Vector3.UP if node is EnemyAI else Vector3.ZERO)
	if w != null and w.fire_at(to, node, true):
		Game.add_chaos(1)
		return
	# Weapons without lock-on support (blower, plunger) get a generic stare-bolt.
	var cam := player.camera
	var from := cam.global_position + (-cam.global_basis.z) * 0.8 + Vector3.DOWN * 0.25
	var ball := Roster.mi(get_parent(), Roster.sphere(0.2), Vector3.ZERO, Color(1.0, 0.9, 0.15), Vector3.ZERO, 2.0)
	ball.global_position = from
	Game.sfx(&"whoosh", from)
	var tw := ball.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(ball, "global_position", to, 0.1)
	tw.tween_callback(_impact.bind(node, from, idx, n))
	tw.tween_callback(ball.queue_free)


func _impact(node: Node3D, from: Vector3, idx: int, n: int) -> void:
	if not is_instance_valid(node):
		return
	var pos := node.global_position + (Vector3.UP if node is EnemyAI else Vector3.ZERO)
	var dirn := (pos - from).normalized()
	var dmg := 38.0 * Prog.mult("kick_damage") * (1.0 + 0.35 * float(n - 1))
	if node is EnemyAI:
		(node as EnemyAI).apply_hit(dirn * 22.0 + Vector3.UP * 6.0, pos, &"gaze", dmg)
		Game.popup("STARE!" if idx == 0 else "STARE x%d!" % (idx + 1), pos + Vector3.UP * 0.8, Color(1.0, 0.85, 0.2), 0.9)
	elif node is RigidBody3D:
		var rb := node as RigidBody3D
		rb.apply_central_impulse((dirn + Vector3.UP * 0.6) * 18.0 * rb.mass)
		Game.popup("BONK!", pos + Vector3.UP * 0.5, Color(1.0, 0.8, 0.2))
		Game.sfx(&"bonk", pos)
	Game.add_chaos(1)
	player.add_trauma(0.3, 0.7)
	if idx == n - 1 and n > 1:
		Fx.shockwave(player, pos, 3.5, 14.0, 12.0, false, true, &"gaze")


# --------------------------------------------------------------------------
# Face gestures
# --------------------------------------------------------------------------
func _live() -> bool:
	return GazeProvider.active and player != null and not player.dead and not GazeProvider.calibrating


func _on_blink() -> void:
	if Game.peek_mode:
		_peek_fire()
		return
	if not _live():
		return
	if not tags.is_empty():
		fire_volley()
	else:
		_fire_at_gaze()


## Blink with nothing locked: shoot wherever you are looking (snapped to an enemy if close).
func _fire_at_gaze() -> void:
	var w := player.weapons.current_weapon()
	if w == null or not w.is_ready() or _volleying:
		return
	var cam := player.camera
	var cand := _pick(cam, _gaze_px, _snap() / clampf(GazeProvider.confidence, 0.4, 1.0))
	var point: Vector3
	var node := cand.get("node") as Node3D
	if node != null and not node.is_in_group("pickups"):
		point = cand["pos"]
	else:
		node = null
		var from := cam.project_ray_origin(_gaze_px)
		var dirn := cam.project_ray_normal(_gaze_px)
		var q := PhysicsRayQueryParameters3D.create(from, from + dirn * 120.0, Game.MASK_WORLD | Game.MASK_ENEMY | Game.MASK_PROPS)
		var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
		point = hit["position"] if not hit.is_empty() else from + dirn * 120.0
	if w.fire_at(point, node):
		guide["fire"] = true


## Either eye's wink swaps guns.
func _on_wink(_left: bool) -> void:
	if Game.peek_mode:
		_peek_swap()
		return
	if not _live() or _wink_cd > 0.0:
		return
	_wink_cd = 0.6
	player.weapons.select(player.weapons.current + 1)
	guide["swap"] = true
	var w := player.weapons.current_weapon()
	if w != null:
		Game.popup(w.display_name.to_upper(), player.global_position + Vector3.UP * 2.2, Color(0.8, 0.9, 1.0), 0.9)
		Game.sfx(&"pop")


func _on_mouth() -> void:
	if not _live() or _burp_cd > 0.0:
		return
	_burp_cd = 5.0
	Game.popup("BRAAAP!", player.global_position + Vector3.UP * 2.0, Color(0.6, 1.0, 0.3), 1.3)
	Fx.shockwave(player, player.global_position, 6.5, 22.0, 20.0, false, true, &"burp")
	player.add_trauma(0.5, 0.9)


func _on_brows() -> void:
	if _live():
		player._jump_buf = player.jump_buffer_time


# --------------------------------------------------------------------------
# HUD overlay (called from Hud._draw)
# --------------------------------------------------------------------------
func draw_overlay(ci: Control) -> void:
	if Game.peek_mode and player != null:
		_draw_peek_hud(ci)
	if not GazeProvider.active or player == null:
		return
	var cam := player.camera
	var font := ThemeDB.fallback_font
	if GazeProvider.sweep_active:
		return                                  # the dot is drawn by the options layer (GazeOptions), in every mode
	if GazeProvider.calibrating:
		_draw_calibration(ci, font)
		return
	if bullet_time:
		ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Color(0.1, 0.35, 0.8, 0.13))
	# dead zone hint
	var dz := Rect2(ci.size * Vector2(DEAD_ZONE.x, DEAD_ZONE.y), ci.size * Vector2(1.0 - 2.0 * DEAD_ZONE.x, 1.0 - 2.0 * DEAD_ZONE.y))
	ci.draw_rect(dz, Color(1, 1, 1, 0.07), false, 1.0)
	# lock progress ring on the current target
	if target != null and is_instance_valid(target) and not tags.has(target):
		var tp := target.global_position + (Vector3.UP if target is EnemyAI else Vector3.ZERO)
		if not cam.is_position_behind(tp):
			var sp := cam.unproject_position(tp)
			var frac := clampf(dwell / need, 0.0, 1.0)
			ci.draw_arc(sp, 36.0, 0.0, TAU, 40, Color(1, 1, 1, 0.25), 3.0)
			ci.draw_arc(sp, 36.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 40, Color(1.0, 0.85, 0.2), 6.0)
	# locked tags
	for i in tags.size():
		var t := tags[i]
		if not is_instance_valid(t):
			continue
		var tp2 := t.global_position + (Vector3.UP if t is EnemyAI else Vector3.ZERO)
		if cam.is_position_behind(tp2):
			continue
		var sp2 := cam.unproject_position(tp2)
		ci.draw_arc(sp2, 42.0, 0.0, TAU, 40, Color(1.0, 0.25, 0.2), 5.0)
		ci.draw_line(sp2 + Vector2(-54, 0), sp2 + Vector2(-30, 0), Color(1.0, 0.25, 0.2), 4.0)
		ci.draw_line(sp2 + Vector2(30, 0), sp2 + Vector2(54, 0), Color(1.0, 0.25, 0.2), 4.0)
		ci.draw_string(font, sp2 + Vector2(-8, 11), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(1, 1, 1))
	# walk waypoint + floor dwell
	if waypoint != Vector3.INF and not cam.is_position_behind(waypoint):
		var wp := cam.unproject_position(waypoint)
		ci.draw_arc(wp, 18.0, 0.0, TAU, 28, Color(0.4, 1.0, 0.5), 4.0)
		ci.draw_circle(wp, 4.0, Color(0.4, 1.0, 0.5))
	elif _floor_pt != Vector3.INF and not cam.is_position_behind(_floor_pt):
		var fp := cam.unproject_position(_floor_pt)
		ci.draw_arc(fp, 20.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(_floor_dwell / DWELL_FLOOR, 0.0, 1.0), 28, Color(0.4, 1.0, 0.5), 4.0)
	if GazeProvider.calibrating:
		var msg := "LOOK AT THE CENTER OF THE SCREEN"
		var mw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
		var cp := ci.size * 0.5
		ci.draw_arc(cp, 46.0, 0.0, TAU, 40, Color(0.5, 1.0, 0.6), 6.0)
		ci.draw_string_outline(font, Vector2(cp.x - mw * 0.5, cp.y - 80.0), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, 8, Color(0, 0, 0, 0.9))
		ci.draw_string(font, Vector2(cp.x - mw * 0.5, cp.y - 80.0), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(0.5, 1.0, 0.6))
	else:
		_draw_guide(ci, font)
	_draw_eye_meters(ci, font)
	_draw_head_monitor(ci, font)
	# gaze cursor, coloured by tracking quality
	var q := GazeProvider.confidence
	var col := Color(0.3, 1.0, 0.4) if q > 0.7 else (Color(1.0, 0.8, 0.2) if q > 0.4 else Color(1.0, 0.3, 0.3))
	ci.draw_circle(_gaze_px, 9.0, Color(0, 0, 0, 0.6))
	ci.draw_circle(_gaze_px, 6.0, col)
	ci.draw_arc(_gaze_px, _snap() / clampf(q, 0.4, 1.0), 0.0, TAU, 48, Color(col, 0.18), 1.5)
	var status := "EYES: %s  %d%%%s" % [GazeProvider.backend_name(), int(q * 100.0),
		"" if GazeProvider.tracking_ok() else "   (no signal, using mouse)"]
	if GazeProvider.backend == GazeProvider.Backend.CAMERA and GazeProvider.camera_status != "":
		status += "   [" + GazeProvider.camera_status + "]"
	ci.draw_string_outline(font, Vector2(ci.size.x * 0.5 - 200.0, ci.size.y - 150.0), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 6, Color(0, 0, 0, 0.9))
	ci.draw_string(font, Vector2(ci.size.x * 0.5 - 200.0, ci.size.y - 150.0), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(col, 1.0))


func _guide_done() -> bool:
	for k: String in guide:
		if not guide[k]:
			return false
	return true


## The "how to play hands-free" card: four steps that tick off as you do them.
func _draw_guide(ci: Control, font: Font) -> void:
	if _guide_done() or _guide_t > 25.0:
		return
	var touch := Game.touch_mode
	var intro := "Touch the screen: your finger is your eyes." if touch else "Move the mouse: it is your eyes."
	var steps := [
		["lock", "LOOK at an enemy to LOCK it (up to 3)"],
		["fire", "BLINK to FIRE" + ("  (tap BLINK)" if touch else "  (press B)")],
		["swap", "WINK to SWAP GUNS" + ("  (tap WINK)" if touch else "  (press Z)")],
		["move", "LEAN to MOVE  (or LOOK at the floor)"],
	]
	var w := 440.0
	var h := 64.0 + 38.0 * steps.size()
	var x := 20.0
	var y := 92.0
	ci.draw_rect(Rect2(x, y, w, h), Color(0.04, 0.05, 0.12, 0.82))
	ci.draw_rect(Rect2(x, y, w, h), Color(1.0, 0.85, 0.3), false, 3.0)
	ci.draw_string(font, Vector2(x + 18, y + 30), "HANDS-FREE MODE", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.85, 0.3))
	ci.draw_string(font, Vector2(x + 18, y + 52), intro, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))
	var next_found := false
	for i in steps.size():
		var st: Array = steps[i]
		var done: bool = guide[st[0]]
		var col := Color(0.4, 1.0, 0.5) if done else Color(1, 1, 1)
		var is_next := not done and not next_found
		if is_next:
			next_found = true
			ci.draw_rect(Rect2(x + 8, y + 66 + 38.0 * i, w - 16, 34), Color(1.0, 0.85, 0.3, 0.16))
		var mark := "[x]" if done else "[ ]"
		var line := "%s  %s" % [mark, st[1]]
		if st.size() > 2 and st[2] != "":
			line += "  " + String(st[2])
		ci.draw_string(font, Vector2(x + 18, y + 90 + 38.0 * i), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)


## The sweep: a dot waits, then glides round the screen edge and back to the middle. Follow it with your eyes.
func _draw_sweep(ci: Control, font: Font) -> void:
	var t := GazeProvider.sweep_t
	var p := EyeSweep.dot(t) * ci.size
	ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Color(0.02, 0.03, 0.08, 0.6))
	var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() / 140.0)
	var moving := t >= 0.0
	var col := Color(0.4, 1.0, 0.5) if moving else Color(1.0, 0.85, 0.3)
	ci.draw_circle(p, 34.0 * pulse, Color(col, 0.22))
	ci.draw_circle(p, 13.0, col)
	var msg := "FOLLOW THE DOT WITH YOUR EYES" if moving else "READY? find the dot"
	var mw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	var y := ci.size.y * 0.5
	ci.draw_string_outline(font, Vector2(ci.size.x * 0.5 - mw * 0.5, y), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, 8, Color(0, 0, 0, 0.9))
	ci.draw_string(font, Vector2(ci.size.x * 0.5 - mw * 0.5, y), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
	var sub := "keep your head still, only your eyes move   (tap to skip)"
	var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	ci.draw_string(font, Vector2(ci.size.x * 0.5 - sw * 0.5, y + 32.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.8))


func _draw_calibration(ci: Control, font: Font) -> void:
	var i := GazeProvider.cal_index
	var pt: Vector2 = GazeProvider.CAL_POINTS[i] * ci.size
	ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Color(0.02, 0.03, 0.08, 0.72))
	var col := Color(1.0, 0.85, 0.3) if GazeProvider.cal_settling else Color(0.4, 1.0, 0.5)
	var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() / 160.0)
	ci.draw_circle(pt, 30.0 * pulse, Color(col, 0.25))
	ci.draw_circle(pt, 12.0, col)
	ci.draw_arc(pt, 42.0, -PI * 0.5, -PI * 0.5 + TAU * GazeProvider.cal_progress, 40, col, 6.0)
	var msg := "CALIBRATION  %d / %d:  look at the dot" % [i + 1, GazeProvider.CAL_POINTS.size()]
	var sub := "keep your head still, only move your eyes"
	var mw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	ci.draw_string_outline(font, Vector2(ci.size.x * 0.5 - mw * 0.5, ci.size.y * 0.33), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, 8, Color(0, 0, 0, 0.9))
	ci.draw_string(font, Vector2(ci.size.x * 0.5 - mw * 0.5, ci.size.y * 0.33), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
	ci.draw_string(font, Vector2(ci.size.x * 0.5 - sw * 0.5, ci.size.y * 0.33 + 34.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.8))


## Two small bars show how closed each eye reads (above its own open baseline), with the
## trigger line, so you can SEE what blinks / winks the detector is getting.
func _draw_eye_meters(ci: Control, font: Font) -> void:
	var b := GazeProvider.backend
	if b != GazeProvider.Backend.CAMERA and b != GazeProvider.Backend.UDP:
		return
	var base := Vector2(24.0, ci.size.y - 150.0)
	if b == GazeProvider.Backend.CAMERA and GazeProvider.face_size > 0.0:
		var fs := GazeProvider.face_size
		var good := fs >= 0.26
		var tip := "face size %d%%  %s" % [int(fs * 100.0), "ok" if good else "TOO SMALL: sit closer / zoom in"]
		ci.draw_string_outline(font, base + Vector2(0, -34), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, Color(0, 0, 0, 0.9))
		ci.draw_string(font, base + Vector2(0, -34), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.5, 1.0, 0.6) if good else Color(1.0, 0.6, 0.3))
		if GazeProvider.cal_error >= 0.0:
			ci.draw_string(font, base + Vector2(0, -56), "aim error ~%d%% of screen (C = recalibrate)" % int(round(GazeProvider.cal_error * 100.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.85))
	ci.draw_string(font, base + Vector2(0, -8), "eyes (blink = both, wink = one)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))
	var vals := [GazeProvider.dbg_l, GazeProvider.dbg_r]
	for k in 2:
		var x := base.x + 36.0 * k
		ci.draw_rect(Rect2(x, base.y, 26, 90), Color(0, 0, 0, 0.55))
		var h := clampf(float(vals[k]) / 0.6, 0.0, 1.0) * 90.0
		var on: bool = float(vals[k]) > GazeProvider.BLINK_ON
		ci.draw_rect(Rect2(x, base.y + 90.0 - h, 26, h), Color(1.0, 0.35, 0.25) if on else Color(0.5, 0.8, 1.0))
		ci.draw_line(Vector2(x, base.y + 90.0 - GazeProvider.BLINK_ON / 0.6 * 90.0), Vector2(x + 26, base.y + 90.0 - GazeProvider.BLINK_ON / 0.6 * 90.0), Color.WHITE, 2.0)
		ci.draw_string(font, Vector2(x + 7, base.y + 108.0), "L" if k == 0 else "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	var age := Time.get_ticks_msec() / 1000.0 - GazeProvider.last_event_t
	if age < 0.8 and GazeProvider.last_event != "":
		var t := GazeProvider.last_event + "!"
		ci.draw_string_outline(font, Vector2(base.x + 84.0, base.y + 56.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, 8, Color(0, 0, 0, 0.9))
		ci.draw_string(font, Vector2(base.x + 84.0, base.y + 56.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(1.0, 0.85, 0.3))


## A live 3D monitor of what the tracker sees: a cube that turns like your head (shown as in a mirror: turn
## right and it turns right) with a floor grid for reference, an amber nose line, and a green arrow for the
## 3D gaze direction (head + eyes). If a direction is wrong, you will see it here.
func _draw_head_monitor(ci: Control, font: Font) -> void:
	if GazeProvider.backend != GazeProvider.Backend.CAMERA or not GazeProvider.head_rpy_ok:
		return
	var panel := Rect2(ci.size.x - 226.0, ci.size.y * 0.22, 210.0, 214.0)
	ci.draw_rect(panel, Color(0.03, 0.04, 0.09, 0.62))
	ci.draw_rect(panel, Color(1, 1, 1, 0.35), false, 2.0)
	var c := panel.position + Vector2(105.0, 100.0)
	var S := 44.0
	var yaw := -GazeProvider.head_rpy.x          # mirror view: your right = screen right
	var pit := GazeProvider.head_rpy.y
	var rol := -GazeProvider.head_rpy.z
	var head := Basis(Vector3.BACK, rol) * Basis(Vector3.RIGHT, pit) * Basis(Vector3.UP, yaw)
	var view := Basis(Vector3.RIGHT, -0.32)       # look at the scene from slightly above
	var proj := func(p3: Vector3) -> Vector2:
		var q: Vector3 = view * p3
		var k := 1.0 / (1.0 - q.z * 0.10)
		return c + Vector2(q.x * k, -q.y * k) * S
	# floor grid (static: it does not turn with your head)
	for i in range(-2, 3):
		var a: Vector2 = proj.call(Vector3(float(i), -1.7, -2.0))
		var b: Vector2 = proj.call(Vector3(float(i), -1.7, 2.0))
		ci.draw_line(a, b, Color(1, 1, 1, 0.16), 1.0)
		var a2: Vector2 = proj.call(Vector3(-2.0, -1.7, float(i)))
		var b2: Vector2 = proj.call(Vector3(2.0, -1.7, float(i)))
		ci.draw_line(a2, b2, Color(1, 1, 1, 0.16), 1.0)
	# cube
	var pts: Array[Vector3] = []
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				pts.append(head * Vector3(sx, sy, sz))
	for i in 8:
		for j in range(i + 1, 8):
			var diff := 0
			for ax in 3:
				if not is_equal_approx((pts[i] as Vector3)[ax], (pts[j] as Vector3)[ax]):
					pass
			# edges join corners that differ in exactly one coordinate (index bits)
			var x := i ^ j
			if x == 1 or x == 2 or x == 4:
				var front := (i & 1) == 1 and (j & 1) == 1       # both corners on the +z (face) side
				var col := Color(1.0, 0.8, 0.25, 0.95) if front else Color(1, 1, 1, 0.55)
				ci.draw_line(proj.call(pts[i]), proj.call(pts[j]), col, 3.0 if front else 1.6)
	var nose: Vector2 = proj.call(head * Vector3(0, 0, 2.0))
	ci.draw_line(proj.call(Vector3.ZERO), nose, Color(1.0, 0.8, 0.25), 3.0)
	ci.draw_circle(nose, 4.0, Color(1.0, 0.8, 0.25))
	# 3D gaze direction (head + eyes), same mirror convention
	var ga := GazeProvider.gaze_ang
	var gdir := Vector3(sin(-ga.x) * cos(ga.y), -sin(ga.y), cos(-ga.x) * cos(ga.y))
	var gp: Vector2 = proj.call(gdir * 2.6)
	ci.draw_line(proj.call(Vector3.ZERO), gp, Color(0.3, 1.0, 0.5), 3.0)
	ci.draw_circle(gp, 5.0, Color(0.3, 1.0, 0.5))
	var txt := "head  yaw %+d  pitch %+d  roll %+d" % [int(roundf(-rad_to_deg(GazeProvider.head_rpy.x))), int(roundf(rad_to_deg(GazeProvider.head_rpy.y))), int(roundf(-rad_to_deg(GazeProvider.head_rpy.z)))]
	ci.draw_string(font, panel.position + Vector2(8, 186), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.8, 0.25))
	ci.draw_string(font, panel.position + Vector2(8, 204), "green = gaze (head + eyes)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.3, 1.0, 0.5))


## Peek level HUD: the head monitor (camera mode) and a lean gauge so you can see what your lean does.
func _draw_peek_hud(ci: Control) -> void:
	var font := ThemeDB.fallback_font
	_draw_head_monitor(ci, font)
	# Camera status: loading / permission / error, so you always know whether head tracking is live.
	var cm := GazeProvider.camera_message()
	if String(cm["text"]) != "":
		var msg: String = cm["text"]
		var mw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		var mp := Vector2(ci.size.x * 0.5 - mw * 0.5, 84.0)
		ci.draw_string_outline(font, mp, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 7, Color(0, 0, 0, 0.9))
		ci.draw_string(font, mp, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, cm["color"])
	var dbg := GazeProvider.debug_line()
	ci.draw_string_outline(font, Vector2(12.0, ci.size.y - 8.0), dbg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(0, 0, 0, 0.9))
	ci.draw_string(font, Vector2(12.0, ci.size.y - 8.0), dbg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.75))
	var pk := GazeProvider.peek_offset_current()
	var w := 340.0
	var x0 := ci.size.x * 0.5 - w * 0.5
	var y0 := ci.size.y - 96.0
	ci.draw_rect(Rect2(x0, y0, w, 10.0), Color(0, 0, 0, 0.55))
	ci.draw_line(Vector2(x0 + w * 0.5, y0 - 5.0), Vector2(x0 + w * 0.5, y0 + 15.0), Color(1, 1, 1, 0.55), 2.0)
	var mx := x0 + w * 0.5 + clampf(pk.x / 1.8, -1.0, 1.0) * w * 0.5
	ci.draw_circle(Vector2(mx, y0 + 5.0), 10.0, Color(1.0, 0.8, 0.25))
	var live := GazeProvider.backend == GazeProvider.Backend.CAMERA
	var tip := "LEAN left / right to peek around cover" if live else "arrow keys: peek   (or START WITH CAMERA and lean)"
	ci.draw_string_outline(font, Vector2(x0, y0 - 12.0), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 6, Color(0, 0, 0, 0.9))
	ci.draw_string(font, Vector2(x0, y0 - 12.0), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.9))
	_draw_peek_eyes(ci, font)
	_draw_aim_panel(ci, font)


func _draw_aim_panel(ci: Control, font: Font) -> void:
	var br := _aim_btn_rect(ci.size)
	var on := Game.peek_eye_aim
	ci.draw_rect(br, Color(0.1, 0.45, 0.3, 0.75) if on else Color(0.35, 0.28, 0.08, 0.75))
	ci.draw_string(font, br.position + Vector2(10.0, 26.0), "AIM: EYES  (tap / M)" if on else "AIM: HEAD  (tap / M)", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.95))
	var off_e := (GazeProvider.gaze - Vector2(0.5, 0.5))
	var inside := absf(off_e.x) < 0.07 and absf(off_e.y) < 0.07
	var dbg := "gaze %.2f %.2f   view yaw %+.0f pitch %+.0f deg   %s" % [GazeProvider.gaze.x, GazeProvider.gaze.y, rad_to_deg(Game.peek_eye_look.x), rad_to_deg(Game.peek_eye_look.y), ("IN THE DEAD ZONE: no turn" if inside else "turning toward the gaze") if on else "head aiming"]
	ci.draw_string_outline(font, Vector2(12.0, ci.size.y - 160.0), dbg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(0, 0, 0, 0.9))
	ci.draw_string(font, Vector2(12.0, ci.size.y - 160.0), dbg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.9, 0.5) if (on and inside) else Color(1, 1, 1, 0.9))
	var sr := _sweep_btn_rect(ci.size)
	ci.draw_rect(sr, Color(0.12, 0.25, 0.45, 0.75))
	ci.draw_string(font, sr.position + Vector2(10.0, 26.0), "SWEEP  (tap / V)", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.95))
	if GazeProvider.sweep_note != "":
		ci.draw_string_outline(font, Vector2(412.0, ci.size.y - 122.0), GazeProvider.sweep_note, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(0, 0, 0, 0.9))
		ci.draw_string(font, Vector2(412.0, ci.size.y - 122.0), GazeProvider.sweep_note, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.85))
	var y := ci.size.y - 52.0
	for m in ["head", "eyes"]:
		var t := AimStats.line(m)
		var col := Color(1, 1, 1, 0.95) if (m == "eyes") == on else Color(1, 1, 1, 0.45)
		ci.draw_string_outline(font, Vector2(12.0, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(0, 0, 0, 0.9))
		ci.draw_string(font, Vector2(12.0, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
		y += 18.0


# --------------------------------------------------------------------------
# Peek level: eyes
# --------------------------------------------------------------------------
func _peek_eyes_live() -> bool:
	return GazeProvider.backend == GazeProvider.Backend.CAMERA and GazeProvider._camera_fresh()


func _peek_clear() -> void:
	peek_lock = null
	_peek_target = null
	_peek_dwell = 0.0
	_sniff_cover = -1
	_sniff_t = 0.0
	AimAssist.locked = null


var _cap_t: float = 0.0


func _peek_gaze(rd: float) -> void:
	_sniff_cd = maxf(_sniff_cd - rd, 0.0)
	if not _peek_eyes_live():
		_eye_look = Vector2.ZERO
		_eye_look_out = Vector2.ZERO
		Game.peek_eye_look = Vector2.ZERO
		if peek_lock != null or _peek_target != null:
			_peek_clear()
		return
	var cam := player.camera
	var gp := GazeProvider.gaze * get_viewport().get_visible_rect().size
	var now_s := float(Time.get_ticks_msec()) / 1000.0
	_gh.append([now_s, gp])
	if GazeProvider.capture_on:
		_cap_t -= rd
		if _cap_t <= 0.0:
			_cap_t = 1.2
			var lock_x := -1.0
			if peek_lock != null and is_instance_valid(peek_lock) and not cam.is_position_behind(peek_lock.global_position):
				lock_x = snappedf(cam.unproject_position(peek_lock.global_position + Vector3.UP * peek_lock.s).x / get_viewport().get_visible_rect().size.x, 0.01)
			GazeProvider.capture_frame("peek", {"eyeAim": Game.peek_eye_aim, "eyeLook": [snappedf(Game.peek_eye_look.x, 0.01), snappedf(Game.peek_eye_look.y, 0.01)], "lockX": lock_x, "target": _peek_target != null})
	while _gh.size() > 2 and now_s - float((_gh[0] as Array)[0]) > 1.0:
		_gh.remove_at(0)
	if Game.peek_eye_aim:
		_eye_follow(cam, gp, rd)
	# 1. lock: stare at a baddy you can actually see
	var best: EnemyAI = null
	if Game.peek_eye_aim:
		best = _eye_pick(cam, gp)
	else:
		var bd := _snap()
		for n in get_tree().get_nodes_in_group("enemies"):
			var e := n as EnemyAI
			if e == null or e.dying or not e.cover or not e._exposed_to_player():
				continue
			var pt := e.global_position + Vector3.UP * e.s
			if cam.is_position_behind(pt):
				continue
			var d := cam.unproject_position(pt).distance_to(gp)
			if d < bd:
				bd = d
				best = e
	if best != null:
		if best == _peek_target:
			_peek_dwell += rd
		else:
			_peek_target = best
			_peek_dwell = 0.0
		if _peek_dwell >= (0.15 if Game.peek_eye_aim else 0.3) and peek_lock != best:
			peek_lock = best
			AimAssist.locked = best
			Game.sfx(&"pop", best.global_position)
			Game.popup("LOCKED", best.global_position + Vector3.UP * (2.2 * best.s), Color(1.0, 0.35, 0.25), 0.9)
	else:
		_peek_target = null
		_peek_dwell = 0.0
	# the lock lapses when the baddy ducks back behind cover or dies
	if peek_lock != null and (not is_instance_valid(peek_lock) or peek_lock.dying or not peek_lock._exposed_to_player()):
		peek_lock = null
		AimAssist.locked = null
	# the tracker's own error: while locked on a baddy you are looking at it, so the distance from the gaze reading to it is the reading's error
	if peek_lock != null and is_instance_valid(peek_lock):
		var fp := peek_lock.global_position + Vector3.UP * peek_lock.s
		if not cam.is_position_behind(fp):
			AimStats.fixation("eyes", cam.unproject_position(fp).distance_to(gp) / get_viewport().get_visible_rect().size.x * 100.0)
	# 2. snuffle: rest your gaze on a rock and it tells you whether something hides behind it
	_peek_sniff(rd, cam, gp)


func _peek_sniff(rd: float, cam: Camera3D, gp: Vector2) -> void:
	var lv := get_parent() as MainLevel
	if lv == null:
		return
	var pz: float = LevelBuilder.PEEK_STATIONS[lv.peek_station]
	var hit := -1
	var hd := 150.0
	for i in LevelBuilder.PEEK_COVER_X.size():
		var c := Vector3(LevelBuilder.PEEK_COVER_X[i], 1.4, pz - LevelBuilder.PEEK_COVER_DIST)
		if cam.is_position_behind(c):
			continue
		var d := cam.unproject_position(c).distance_to(gp)
		if d < hd:
			hd = d
			hit = i
	if hit == -1 or hit != _sniff_cover:
		_sniff_cover = hit
		_sniff_t = 0.0
		return
	_sniff_t += rd
	if _sniff_t < 0.7 or _sniff_cd > 0.0:
		return
	_sniff_t = 0.0
	_sniff_cd = 1.6
	sniffs += 1
	var base := Vector3(LevelBuilder.PEEK_COVER_X[hit], 0.0, pz - LevelBuilder.PEEK_COVER_DIST)
	var found := false
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as EnemyAI
		if e == null or e.dying or not e.cover or e._exposed_to_player():
			continue
		if Vector2(e.global_position.x - base.x, e.global_position.z - base.z).length() < 5.5:
			e.rustle()
			found = true
	Game.popup("sniff... someone is back there!" if found else "sniff... nothing", base + Vector3(0, 3.4, 0), Color(1.0, 0.9, 0.4) if found else Color(1, 1, 1, 0.6), 1.0 if found else 0.7)


func _peek_fire() -> void:
	if Game.peek_eye_aim:
		_peek_fire_eyes()
		return
	if player == null or player.dead or peek_lock == null or not is_instance_valid(peek_lock) or not _peek_eyes_live():
		return
	var w := player.weapons.current_weapon()
	if w == null or not w.is_ready():
		return
	if w.fire_at(peek_lock.global_position + Vector3.UP * 0.9 * peek_lock.s, peek_lock):
		Game.peek_shot.emit(&"blink")


## Eye mode: which baddy are the eyes pointing at? Every exposed baddy gets a tolerance sized to how big it looks on screen (never less than a fifth of the screen width: the reading
## is coarse), the nearest to the gaze wins, and the one already held is favoured so a flicker does not drop it. If nothing is under the gaze but you are looking hard to one
## side, it is the nearest exposed baddy on that side: far ones are always reachable, however far the reading is from them.
func _eye_pick(cam: Camera3D, gp: Vector2) -> EnemyAI:
	var vs := get_viewport().get_visible_rect().size
	var c := vs * 0.5
	var best: EnemyAI = null
	var bscore := 1.0e9
	var side_best: EnemyAI = null
	var side_d := 1.0e9
	var hard := absf(gp.x - c.x) / vs.x > 0.3
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as EnemyAI
		if e == null or e.dying or not e.cover or not e._exposed_to_player():
			continue
		var mid := e.global_position + Vector3.UP * e.s
		if cam.is_position_behind(mid):
			continue
		var sp := cam.unproject_position(mid)
		var half_h := absf(cam.unproject_position(e.global_position + Vector3.UP * 1.8 * e.s).y - cam.unproject_position(e.global_position).y) * 0.5
		var tol := maxf(half_h * 1.6 + 60.0, 0.2 * vs.x)
		var dx := absf(sp.x - gp.x)
		var dy := absf(sp.y - gp.y) * 0.6
		var score := sqrt(dx * dx + dy * dy) / tol
		if e == peek_lock:
			score *= 0.6
		if score < bscore:
			bscore = score
			best = e
		if hard and signf(sp.x - c.x) == signf(gp.x - c.x) and dx < side_d:
			side_d = dx
			side_best = e
	if best != null and bscore < 1.0:
		return best
	return side_best


## Aiming by eye, the view follows. The gaze is only a hint: a baddy near it becomes the point the view is turned toward (the game focuses in), otherwise the view
## drifts toward where you look, and it settles when you look at the middle. Turn rate is a fraction of the remaining angle per second, so a noisy reading
## wobbles the view very little. The crosshair stays in the middle, as with the head.
func _eye_follow(cam: Camera3D, gp: Vector2, rd: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	var c := vs * 0.5
	var p := gp
	var focus := false
	var fe: EnemyAI = _peek_target if (_peek_target != null and is_instance_valid(_peek_target)) else peek_lock          # the baddy you are looking at starts pulling the view at once, the lock confirms it
	if fe != null and is_instance_valid(fe) and not fe.dying and not cam.is_position_behind(fe.global_position):
		p = cam.unproject_position(fe.global_position + Vector3.UP * 0.9 * fe.s)
		focus = true
	var off := (p - c) / vs
	var dz := 0.015 if focus else 0.07
	var ox := signf(off.x) * maxf(absf(off.x) - dz, 0.0)
	var oy := signf(off.y) * maxf(absf(off.y) - dz, 0.0)
	var th := tan(deg_to_rad(cam.fov) * 0.5)
	var ax := atan(2.0 * ox * th * vs.x / vs.y)
	var ay := atan(2.0 * oy * th)
	var k := 1.0 - exp(-rd / 0.15) if focus else (2.2 + 3.0 * maxf(absf(off.x), absf(off.y))) * rd          # focused: close on it (a fraction of the angle left, 0.15 s time constant); otherwise a steady drift toward the gaze
	_eye_look.x = clampf(_eye_look.x - ax * k, -0.7, 0.7)          # looking right turns the view right, which is a negative yaw
	_eye_look.y = clampf(_eye_look.y - ay * k, -0.5, 0.5)          # looking up pitches the view up
	if not focus and ox == 0.0 and oy == 0.0:
		_eye_look = _eye_look.move_toward(Vector2.ZERO, 0.12 * rd)             # nothing to look at and looking at the middle: the view slowly comes home
	_eye_look_out = _eye_look_out.lerp(_eye_look, 1.0 - exp(-rd / 0.1))
	Game.peek_eye_look = _eye_look_out


## Blink in eye mode: the view has already followed your gaze, so fire at the locked baddy, or else the one nearest where you were looking just before the lid closed.
func _peek_fire_eyes() -> void:
	if player == null or player.dead or not _peek_eyes_live():
		return
	var w := player.weapons.current_weapon()
	if w == null or not w.is_ready():
		return
	var cam := player.camera
	var gp := _gaze_before_blink()
	var near := _nearest_exposed(cam, gp, _snap())
	if peek_lock != null and is_instance_valid(peek_lock) and not peek_lock.dying:
		near = {"e": peek_lock, "d": 0.0}
	var fired := false
	if not near.is_empty():
		var e := near["e"] as EnemyAI
		fired = w.fire_at(e.global_position + Vector3.UP * 0.9 * e.s, e)
	else:
		var cp := get_viewport().get_visible_rect().size * 0.5
		var from := cam.project_ray_origin(cp)
		var dirn := cam.project_ray_normal(cp)
		var q := PhysicsRayQueryParameters3D.create(from, from + dirn * 120.0, Game.MASK_WORLD | Game.MASK_ENEMY | Game.MASK_PROPS)
		var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
		fired = w.fire_at(hit["position"] if not hit.is_empty() else from + dirn * 120.0, null)
	if fired:
		Game.peek_shot.emit(&"blink")


## Median gaze over the 0.45 s up to 0.12 s ago: a blink drags the iris reading down as the lid closes, so the last 0.12 s are not trusted.
func _gaze_before_blink() -> Vector2:
	var now_s := float(Time.get_ticks_msec()) / 1000.0
	var xs: Array = []
	var ys: Array = []
	for h in _gh:
		var age := now_s - float((h as Array)[0])
		if age >= 0.12 and age <= 0.45:
			xs.append(((h as Array)[1] as Vector2).x)
			ys.append(((h as Array)[1] as Vector2).y)
	if xs.size() < 3:
		return GazeProvider.gaze * get_viewport().get_visible_rect().size
	xs.sort()
	ys.sort()
	return Vector2(float(xs[xs.size() / 2]), float(ys[ys.size() / 2]))


func _nearest_exposed(cam: Camera3D, p: Vector2, max_px: float) -> Dictionary:
	var best: EnemyAI = null
	var bd := max_px
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as EnemyAI
		if e == null or e.dying or not e.cover or not e._exposed_to_player():
			continue
		var pt := e.global_position + Vector3.UP * e.s
		if cam.is_position_behind(pt):
			continue
		var d := cam.unproject_position(pt).distance_to(p)
		if d < bd:
			bd = d
			best = e
	return {} if best == null else {"e": best, "d": bd}


## A shot was fired: record how far from the nearest baddy you were aiming (HEAD: the middle of the screen, EYES: the gaze), and check 0.8 s later if it was hurt.
func _on_peek_shot(src: StringName) -> void:
	if not Game.peek_mode or player == null or player.dead:
		return
	var mode := "eyes" if Game.peek_eye_aim else "head"
	var vs := get_viewport().get_visible_rect().size
	var p := vs * 0.5          # both modes aim with the middle of the screen (the view follows the head, or follows the eyes), so the errors compare
	var near := _nearest_exposed(player.camera, p, vs.x * 0.5)
	if near.is_empty():
		AimStats.shot(mode, -1.0)
		return
	AimStats.shot(mode, float(near["d"]) / vs.x * 100.0)
	var e := near["e"] as EnemyAI
	_pending.append({"e": e, "hp": e.health, "t": 0.8, "mode": mode})
	_stat_shots += 1
	if _stat_shots % 10 == 0:
		AimStats.save()


func _score_pending(rd: float) -> void:
	for i in range(_pending.size() - 1, -1, -1):
		var pd: Dictionary = _pending[i]
		var e: Variant = pd["e"]
		pd["t"] = float(pd["t"]) - rd
		if not is_instance_valid(e) or (e as EnemyAI).dying or (e as EnemyAI).health < float(pd["hp"]) - 0.001:
			AimStats.hit(String(pd["mode"]))
			_pending.remove_at(i)
		elif float(pd["t"]) <= 0.0:
			_pending.remove_at(i)


## HEAD <-> EYES. The head-tracked Peek is the default and is untouched when this is off.
func toggle_peek_aim() -> void:
	Game.peek_eye_aim = not Game.peek_eye_aim
	if Game.peek_eye_aim and not GazeProvider.sweep_done and GazeProvider.backend == GazeProvider.Backend.CAMERA:
		GazeProvider.start_sweep()          # first time on eyes: the four-second sweep
	_eye_look = Vector2.ZERO
	_eye_look_out = Vector2.ZERO
	Game.peek_eye_look = Vector2.ZERO
	AimStats.save()
	Game.banner_requested.emit("AIM WITH YOUR EYES" if Game.peek_eye_aim else "AIM WITH YOUR HEAD", Color(0.5, 1.0, 0.7) if Game.peek_eye_aim else Color(1.0, 0.85, 0.4), 1.6)


func _sweep_btn_rect(vs: Vector2) -> Rect2:
	return Rect2(252.0, vs.y - 150.0, 150.0, 40.0)


func _aim_btn_rect(vs: Vector2) -> Rect2:
	return Rect2(12.0, vs.y - 150.0, 230.0, 40.0)


func _input(event: InputEvent) -> void:
	if not Game.peek_mode:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var kc := (event as InputEventKey).keycode
		if GazeProvider.sweep_active:
			GazeProvider.cancel_sweep()
			get_viewport().set_input_as_handled()
			return
		if kc == KEY_M:
			toggle_peek_aim()
		elif kc == KEY_K:
			DisplayServer.clipboard_set(AimStats.report())
			Game.banner_requested.emit("AIM NUMBERS COPIED", Color(0.8, 0.9, 1.0), 1.4)
		elif kc == KEY_V:
			GazeProvider.start_sweep()
		return
	var pos := Vector2.INF
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pos = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		pos = (event as InputEventScreenTouch).position
	if pos.is_finite() and GazeProvider.sweep_active:
		GazeProvider.cancel_sweep()
		get_viewport().set_input_as_handled()
	elif pos.is_finite() and _aim_btn_rect(get_viewport().get_visible_rect().size).has_point(pos):
		toggle_peek_aim()
		get_viewport().set_input_as_handled()
	elif pos.is_finite() and _sweep_btn_rect(get_viewport().get_visible_rect().size).has_point(pos):
		GazeProvider.start_sweep()
		get_viewport().set_input_as_handled()


func _peek_swap() -> void:
	if player == null or player.dead or _wink_cd > 0.0 or not _peek_eyes_live():
		return
	_wink_cd = 0.6
	player.weapons.select(player.weapons.current + 1)
	var w := player.weapons.current_weapon()
	if w != null:
		Game.popup(w.display_name.to_upper(), player.global_position + Vector3.UP * 2.2, Color(0.8, 0.9, 1.0), 0.9)
		Game.sfx(&"pop")


func _draw_peek_eyes(ci: Control, font: Font) -> void:
	if not _peek_eyes_live() or player == null:
		return
	var cam := player.camera
	var gp := GazeProvider.gaze * ci.size
	ci.draw_circle(gp, 6.0, Color(0.3, 1.0, 0.5, 0.9))
	ci.draw_arc(gp, 15.0, 0.0, TAU, 24, Color(0.3, 1.0, 0.5, 0.35), 2.0)
	if _peek_target != null and is_instance_valid(_peek_target) and peek_lock != _peek_target:
		var tp := _peek_target.global_position + Vector3.UP * _peek_target.s
		if not cam.is_position_behind(tp):
			var sp := cam.unproject_position(tp)
			ci.draw_arc(sp, 40.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(_peek_dwell / 0.3, 0.0, 1.0), 32, Color(1.0, 0.85, 0.3), 5.0)
	if peek_lock != null and is_instance_valid(peek_lock):
		var lp := peek_lock.global_position + Vector3.UP * peek_lock.s
		if not cam.is_position_behind(lp):
			var ls := cam.unproject_position(lp)
			ci.draw_arc(ls, 46.0, 0.0, TAU, 40, Color(1.0, 0.25, 0.2), 5.0)
			ci.draw_line(ls + Vector2(-62, 0), ls + Vector2(-38, 0), Color(1.0, 0.25, 0.2), 4.0)
			ci.draw_line(ls + Vector2(38, 0), ls + Vector2(62, 0), Color(1.0, 0.25, 0.2), 4.0)
			var t := "BLINK to fire"
			ci.draw_string_outline(font, ls + Vector2(-50, 74), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, Color(0, 0, 0, 0.9))
			ci.draw_string(font, ls + Vector2(-50, 74), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.8, 0.7))
