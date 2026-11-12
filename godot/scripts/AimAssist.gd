class_name AimAssist
extends RefCounted
## Aim assist that scales with how imprecise the input device is.
##
## Why it exists: a webcam gaze is only good to ~3-5 degrees, a thumb on a phone
## covers the target it is aiming at, and a 1080p screen at arm's length is about
## 24 pixels per degree. A mouse needs almost nothing; gaze needs a lot.
## The assist only ever bends a shot toward an enemy you are already roughly
## aiming at (inside the cone) and that you can actually see (line of sight).

const CONE_MOUSE := 1.2
const CONE_PAD := 3.0
const CONE_TOUCH := 5.0
const CONE_GAZE_SIM := 5.0     # mouse/finger driving hands-free
const CONE_GAZE_CAM := 7.5     # real camera gaze


## The baddy your eyes have locked (Peek level). Shots that land near it snap to it, much harder than normal assist.
static var locked: Node3D = null


static func cone_deg() -> float:
	if GazeProvider.active:
		var b := GazeProvider.backend
		if b == GazeProvider.Backend.UDP or b == GazeProvider.Backend.CAMERA:
			return CONE_GAZE_CAM * clampf(1.4 - GazeProvider.confidence * 0.4, 1.0, 1.4)
		return CONE_GAZE_SIM
	if Game.touch_mode:
		return CONE_TOUCH
	if Game.using_gamepad:
		return CONE_PAD
	return CONE_MOUSE


## Best visible enemy within `cone` degrees of the ray. {} when none.
static func find(tree: SceneTree, cam: Camera3D, origin: Vector3, dir: Vector3, cone: float = -1.0, max_dist: float = 90.0) -> Dictionary:
	if cone < 0.0:
		cone = cone_deg()
	if locked != null and is_instance_valid(locked) and locked is EnemyAI and not (locked as EnemyAI).dying:
		var lp := (locked as EnemyAI).global_position + Vector3.UP * (locked as EnemyAI).s
		var lto := lp - origin
		var lang := rad_to_deg(dir.angle_to(lto))
		if lang < maxf(cone * 4.0, 6.0) and lto.length() < max_dist:
			var lq := PhysicsRayQueryParameters3D.create(origin, lp, Game.MASK_WORLD)
			if cam.get_world_3d().direct_space_state.intersect_ray(lq).is_empty():
				return {"node": locked, "point": lp, "angle": lang}
	var best: EnemyAI = null
	var best_ang := cone
	var best_pos := Vector3.ZERO
	var space := cam.get_world_3d().direct_space_state
	for n in tree.get_nodes_in_group("enemies"):
		var e := n as EnemyAI
		if e == null or e.dying:
			continue
		var p := e.global_position + Vector3.UP
		var to := p - origin
		var d := to.length()
		if d > max_dist or d < 1.0:
			continue
		var ang := rad_to_deg(dir.angle_to(to))
		if ang >= best_ang:
			continue
		var q := PhysicsRayQueryParameters3D.create(origin, p, Game.MASK_WORLD)
		if not space.intersect_ray(q).is_empty():
			continue
		best = e
		best_ang = ang
		best_pos = p
	if best == null:
		return {}
	return {"node": best, "point": best_pos, "angle": best_ang}


## Aim direction after assist (unchanged when nothing is in the cone).
static func assist(tree: SceneTree, cam: Camera3D, origin: Vector3, dir: Vector3) -> Vector3:
	var r := find(tree, cam, origin, dir)
	if r.is_empty():
		return dir
	return ((r["point"] as Vector3) - origin).normalized()
