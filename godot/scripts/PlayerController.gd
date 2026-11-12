class_name PlayerController
extends CharacterBody3D
## First-person slapstick controller.
##
## Features: mouse-look + speed-reactive FOV, WASD/sprint/jump (with coyote time
## and jump buffering), a momentum slide that turns slopes into speed ramps, a
## box-query kick that launches props and ragdolls enemies, and a spring-based
## camera (recoil + trauma shake).

signal slide_started
signal slide_ended
signal kicked
signal died

@export_group("Look")
@export var mouse_sensitivity: float = 0.0022
@export var stick_sensitivity: float = 3.2  ## radians/sec at full stick deflection
@export var base_fov: float = 80.0
@export var sprint_fov_bonus: float = 9.0
@export var slide_fov_bonus: float = 16.0
@export var fov_lerp: float = 7.0

@export_group("Movement")
@export var walk_speed: float = 7.0
@export var sprint_speed: float = 12.5
@export var crouch_speed: float = 3.5
@export var ground_accel: float = 55.0
@export var ground_friction: float = 45.0
@export var air_accel: float = 20.0
@export var jump_velocity: float = 9.0
@export var gravity: float = 24.0
@export var coyote_time: float = 0.1
@export var jump_buffer_time: float = 0.12

@export_group("Slide")
@export var slide_min_speed: float = 6.5
@export var slide_boost: float = 1.25
@export var slide_max_speed: float = 40.0
@export var slide_end_speed: float = 3.0
@export var slide_flat_friction: float = 4.0
@export var slide_slope_accel: float = 45.0
@export var slide_steer: float = 1.8
@export var slide_cooldown: float = 0.35

@export_group("Body")
@export var stand_height: float = 1.8
@export var low_height: float = 1.0

@export_group("Health")
@export var base_max_health: float = 100.0

@export_group("Kick")
@export var kick_damage: float = 28.0
@export var kick_range: float = 2.8
@export var kick_cooldown: float = 0.6
@export var kick_prop_speed: float = 26.0
@export var kick_enemy_speed: float = 30.0
@export var kick_lift: float = 0.3

@export_group("Juice")
@export var spring_stiffness: float = 170.0
@export var spring_damping: float = 13.0
@export var trauma_decay: float = 1.6
@export var shake_max_angle_deg: float = 4.5
@export var shake_max_offset: float = 0.08
@export var shake_speed: float = 38.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var foot: MeshInstance3D = $Head/Camera/KickFoot
@onready var body_shape: CollisionShape3D = $CollisionShape3D
@onready var weapons: WeaponManager = $Head/Camera/WeaponManager

var _capsule: CapsuleShape3D
var _height: float = 1.8
var _low: bool = false
var _sliding: bool = false
var _slide_cd: float = 0.0
var _kick_cd: float = 0.0
var _coyote: float = 0.0
var _air_time: float = 0.0
var _jump_buf: float = 0.0
var _was_on_floor: bool = false
var _input_dir: Vector2 = Vector2.ZERO
var _foot_rest: Vector3
var _foot_tween: Tween

# Camera juice state
var _trauma: float = 0.0
var _noise_t: float = 0.0
var _noise := FastNoiseLite.new()
var _pitch_pos: float = 0.0
var _pitch_vel: float = 0.0
var _off_pos: Vector3 = Vector3.ZERO
var _off_vel: Vector3 = Vector3.ZERO
var _roll: float = 0.0

# Health / status
var health: float = 100.0
var dead: bool = false
var _invuln: float = 0.0
var _regen_delay: float = 0.0
var _stun: float = 0.0
var _second_wind: bool = true
var _speed_mult: float = 1.0
## Extra movement input (x strafe, y back/forward) injected by hands-free mode.
var auto_move: Vector2 = Vector2.ZERO
## On-rails (peek level): no free walking. The body follows `rail_anchor` plus the magnified head lean,
## so leaning out of cover really moves (and exposes) the player. Collisions with the cover still apply.
var rail_lock: bool = false
var rail_anchor: Vector3 = Vector3.ZERO
var slippery_until: int = 0
var sticky_until: int = 0


func _ready() -> void:
	add_to_group("player")
	_noise.frequency = 1.0
	_noise.seed = randi()
	_capsule = (body_shape.shape as CapsuleShape3D).duplicate()
	body_shape.shape = _capsule
	_height = stand_height
	_foot_rest = foot.position
	foot.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Game.touch_mode else Input.MOUSE_MODE_CAPTURED
	health = max_hp()
	Prog.changed.connect(func() -> void: health = minf(health, max_hp()))
	Prog.leveled_up.connect(func(_l: int) -> void: heal(max_hp() * 0.3))


# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x - motion.relative.y * mouse_sensitivity, -1.5, 1.5)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not GazeProvider.active and not Game.touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		weapons.block_input(0.15)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --------------------------------------------------------------------------
# Public API (used by weapons / enemies)
# --------------------------------------------------------------------------
## Add instantaneous velocity (shoves, blower thrust, grapple pull).
func apply_push(dv: Vector3, max_speed: float = 0.0) -> void:
	velocity += dv
	if max_speed > 0.0 and velocity.length() > max_speed:
		velocity = velocity.limit_length(max_speed)


## Screen-shake. `cap` stops continuous sources from stacking beyond a level.
func add_trauma(amount: float, cap: float = 1.0) -> void:
	_trauma = maxf(_trauma, minf(_trauma + amount, cap))
	Game.rumble(_trauma * 0.6, _trauma, 0.12)


## Spring kick on camera pitch. Positive = look up, peak in degrees.
func add_recoil(peak_deg: float, kick_back: float = 0.0) -> void:
	_pitch_vel += deg_to_rad(peak_deg) * sqrt(spring_stiffness)
	_off_vel.z += kick_back * sqrt(spring_stiffness)


func is_sliding() -> bool:
	return _sliding


# --------------------------------------------------------------------------
# Physics
# --------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_kick_cd = maxf(_kick_cd - delta, 0.0)
	_slide_cd = maxf(_slide_cd - delta, 0.0)
	_invuln = maxf(_invuln - delta, 0.0)
	_regen_delay -= delta
	_stun = maxf(_stun - delta, 0.0)
	_speed_mult = Prog.mult("move_speed")
	if not dead and _regen_delay <= 0.0 and health < max_hp():
		health = minf(max_hp(), health + Prog.bonus("regen") * delta)
	var can_act := not dead and _stun <= 0.0

	var on_floor := is_on_floor()
	if on_floor:
		_coyote = coyote_time
		_air_time = 0.0
	else:
		_coyote -= delta
		_air_time += delta
	var landed := on_floor and not _was_on_floor
	_was_on_floor = on_floor

	_input_dir = (Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back") + auto_move).limit_length(1.0) if (can_act and not rail_lock) else Vector2.ZERO
	var wish := (global_basis * Vector3(_input_dir.x, 0.0, _input_dir.y)).normalized()
	var crouch_held := can_act and not rail_lock and Input.is_action_pressed(&"crouch")
	var sprinting := can_act and not rail_lock and Input.is_action_pressed(&"sprint") and _input_dir.y < -0.1

	if can_act and not rail_lock and Input.is_action_just_pressed(&"jump"):
		_jump_buf = jump_buffer_time
	else:
		_jump_buf -= delta

	var h := Vector3(velocity.x, 0.0, velocity.z)

	# --- slide start: crouch while fast on the ground (or land while holding crouch)
	if not _sliding and crouch_held and on_floor and _slide_cd <= 0.0 \
			and h.length() >= slide_min_speed \
			and (Input.is_action_just_pressed(&"crouch") or landed):
		h = _start_slide(h)

	if _sliding:
		h = _slide_step(h, wish, delta, on_floor, crouch_held)
	else:
		h = _walk_step(h, wish, delta, on_floor, sprinting)

	# --- crouch stance (stay low under ceilings)
	var want_low := _sliding or crouch_held
	if not want_low and _low:
		want_low = not _can_stand()
	_low = want_low
	_height = lerpf(_height, low_height if _low else stand_height, 1.0 - exp(-14.0 * delta))
	_capsule.height = _height
	body_shape.position.y = _height * 0.5
	head.position.y = _height - 0.2

	# --- vertical
	if on_floor and velocity.y <= 0.0:
		velocity.y = 0.0
	else:
		velocity.y -= gravity * maxf(Prog.mult("gravity"), 0.2) * Game.gravity_scale * delta
	if _jump_buf > 0.0 and _coyote > 0.0 and (_can_stand() or _sliding):
		velocity.y = jump_velocity * Prog.mult("jump") * (0.7 if Time.get_ticks_msec() < sticky_until else 1.0)
		_jump_buf = 0.0
		_coyote = 0.0
		Game.sfx(&"pop", global_position)

	if Game.peek_mode and rail_lock and not dead:
		h = _peek_velocity(delta)
	velocity.x = h.x
	velocity.z = h.z

	var pre_speed := h.length()
	var pre_dir := h.normalized()
	move_and_slide()
	_shove_bodies(pre_speed, pre_dir)

	if can_act and Input.is_action_just_pressed(&"kick") and _kick_cd <= 0.0:
		_do_kick()


## Velocity that takes the body to the rail anchor plus the (magnified) head lean.
func _peek_velocity(delta: float) -> Vector3:
	var pk := GazeProvider.peek_offset(delta)
	var want := Vector3(rail_anchor.x + pk.x, 0.0, rail_anchor.z - pk.z)
	var err := Vector3(want.x - global_position.x, 0.0, want.z - global_position.z)
	return (err * 14.0).limit_length(28.0)


func _walk_step(h: Vector3, wish: Vector3, delta: float, on_floor: bool, sprinting: bool) -> Vector3:
	var target_speed := walk_speed * _speed_mult
	if _low:
		target_speed = crouch_speed * _speed_mult
	elif sprinting:
		target_speed = sprint_speed * _speed_mult

	var now := Time.get_ticks_msec()
	if now < sticky_until:
		target_speed *= 0.45
	if on_floor:
		var rate := ground_accel if wish != Vector3.ZERO else ground_friction
		if now < slippery_until:
			rate *= 0.08
		return h.move_toward(wish * target_speed, rate * delta)

	# Air control that preserves momentum (blower launches, slide-jumps).
	if wish != Vector3.ZERO:
		var before := h.length()
		h += wish * air_accel * delta
		var cap_speed := maxf(before, target_speed)
		if h.length() > cap_speed:
			h = h.normalized() * cap_speed
	return h


func _start_slide(h: Vector3) -> Vector3:
	_sliding = true
	var new_speed := minf(h.length() * slide_boost * Prog.mult("slide_speed"), slide_max_speed * Prog.mult("slide_speed"))
	var dir := h.normalized()
	Game.sfx(&"squeak", global_position)
	if new_speed > 9.0:
		Game.popup("SLIP!", global_position + dir * 1.5 + Vector3.UP * 1.0, Color(0.5, 0.9, 1.0))
	add_trauma(0.18, 0.4)
	slide_started.emit()
	return dir * new_speed


func _end_slide() -> void:
	_sliding = false
	_slide_cd = slide_cooldown
	slide_ended.emit()


func _slide_step(h: Vector3, wish: Vector3, delta: float, on_floor: bool, crouch_held: bool) -> Vector3:
	var slope := 0.0
	if on_floor:
		# Down-slope vector: length == sin(slope angle). Steeper = more speed.
		var downhill := Vector3.DOWN.slide(get_floor_normal())
		slope = downhill.length()
		var flat := Vector3(downhill.x, 0.0, downhill.z)
		if slope > 0.04 and flat.length() > 0.001:
			h += flat.normalized() * slide_slope_accel * Prog.mult("slide_speed") * slope * delta
		# Friction fades out on slopes so a good ramp keeps you flying.
		var friction := slide_flat_friction * clampf(1.0 - slope * 3.0, 0.0, 1.0)
		var s := maxf(h.length() - friction * delta, 0.0)
		h = h.normalized() * s if s > 0.0 else Vector3.ZERO

	# Limited steering: rotate velocity toward input without changing speed.
	if wish != Vector3.ZERO and h.length() > 0.1:
		var spd := h.length()
		h = h.lerp(wish * spd, clampf(slide_steer * delta, 0.0, 1.0))
		if h.length() > 0.001:
			h = h.normalized() * spd

	h = h.limit_length(slide_max_speed * Prog.mult("slide_speed"))

	var downhill_strong := on_floor and slope > 0.1
	if not crouch_held \
			or (h.length() < slide_end_speed and not downhill_strong) \
			or (not on_floor and _air_time > 0.35):
		_end_slide()
	return h


func _can_stand() -> bool:
	var needed := stand_height - _capsule.height + 0.05
	if needed <= 0.06:
		return true
	return not test_move(global_transform, Vector3.UP * needed)


## Fast bodies plow through physics props and bowl over enemies.
func _shove_bodies(speed: float, dir: Vector3) -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var other := c.get_collider()
		if other is RigidBody3D:
			var rb := other as RigidBody3D
			rb.apply_central_impulse(-c.get_normal() * clampf(speed, 2.0, 30.0) * rb.mass * 0.5)
		elif other is EnemyAI and speed > 10.0:
			var enemy := other as EnemyAI
			enemy.apply_hit(dir * speed * 1.3 + Vector3.UP * 4.0, c.get_position(), &"slide", 22.0 * Prog.mult("slide_damage"))


# --------------------------------------------------------------------------
# Kick
# --------------------------------------------------------------------------
func _do_kick() -> void:
	_kick_cd = kick_cooldown
	Game.sfx(&"whoosh", camera.global_position)
	add_trauma(0.45, 0.8)
	add_recoil(-2.5, 0.05)
	kicked.emit()
	_play_foot_anim()

	var width := Prog.mult("kick_width")
	var reach := kick_range * (0.6 + 0.4 * width)
	var dmg := kick_damage * Prog.mult("kick_damage")
	var force := Prog.mult("kick_force")
	var fwd := -camera.global_basis.z
	var box := BoxShape3D.new()
	box.size = Vector3(1.7 * width, 1.7, reach)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(camera.global_basis, camera.global_position + fwd * reach * 0.5)
	query.collision_mask = Game.MASK_ENEMY | Game.MASK_PROPS
	query.exclude = [get_rid()]

	var launch_dir := (fwd + Vector3.UP * kick_lift).normalized()
	var results := get_world_3d().direct_space_state.intersect_shape(query, 24)
	var hit_any := false
	var seen: Dictionary = {}
	for r: Dictionary in results:
		var collider: Object = r["collider"]
		if seen.has(collider):
			continue
		seen[collider] = true
		if collider is EnemyAI:
			var enemy := collider as EnemyAI
			enemy.apply_hit(launch_dir * kick_enemy_speed * force, enemy.global_position + Vector3.UP, &"kick", dmg)
			hit_any = true
		elif collider is RigidBody3D:
			var rb := collider as RigidBody3D
			rb.apply_central_impulse(launch_dir * kick_prop_speed * force * rb.mass)
			rb.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * rb.mass * 3.0)
			Game.popup("BONK!", rb.global_position + Vector3.UP * 0.5, Color(1.0, 0.8, 0.2))
			Game.sfx(&"bonk", rb.global_position)
			hit_any = true
	if hit_any:
		add_trauma(0.4, 1.0)
	if Prog.flag("shockboots"):
		Fx.shockwave(self, global_position + fwd * 1.5, 6.0, 18.0, 15.0, false, true, &"shockwave")


func _play_foot_anim() -> void:
	if _foot_tween:
		_foot_tween.kill()
	foot.visible = true
	foot.position = _foot_rest
	_foot_tween = create_tween()
	_foot_tween.tween_property(foot, "position", _foot_rest + Vector3(0.0, 0.35, -1.1), 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_foot_tween.tween_interval(0.08)
	_foot_tween.tween_property(foot, "position", _foot_rest, 0.18)
	_foot_tween.tween_callback(func() -> void: foot.visible = false)


# --------------------------------------------------------------------------
# Camera: FOV, spring recoil, trauma shake, lean
# --------------------------------------------------------------------------
func _process(delta: float) -> void:
	# Right-stick look (squared response for fine aim at small deflection).
	var look := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if look != Vector2.ZERO:
		look = look * look.length()
		rotate_y(-look.x * stick_sensitivity * delta)
		head.rotation.x = clampf(head.rotation.x - look.y * stick_sensitivity * 0.75 * delta, -1.5, 1.5)

	var hspeed := Vector3(velocity.x, 0.0, velocity.z).length()
	var fov_target := base_fov
	if _sliding:
		fov_target += slide_fov_bonus
	elif hspeed > walk_speed + 1.0:
		fov_target += sprint_fov_bonus
	fov_target += clampf((hspeed - sprint_speed) * 0.4, 0.0, 14.0)
	# Portrait phones: keep the HORIZONTAL field of view so the world is not a thin slit.
	var vs := get_viewport().get_visible_rect().size
	camera.keep_aspect = Camera3D.KEEP_WIDTH if vs.y > vs.x else Camera3D.KEEP_HEIGHT
	camera.fov = lerpf(camera.fov, fov_target, 1.0 - exp(-fov_lerp * delta))

	# Damped springs (semi-implicit Euler).
	_pitch_vel += (-spring_stiffness * _pitch_pos - spring_damping * _pitch_vel) * delta
	_pitch_pos += _pitch_vel * delta
	_off_vel += (-spring_stiffness * _off_pos - spring_damping * _off_vel) * delta
	_off_pos += _off_vel * delta

	_trauma = maxf(_trauma - trauma_decay * delta, 0.0)
	_noise_t += delta * shake_speed
	var s := _trauma * _trauma
	var nx := _noise.get_noise_2d(_noise_t, 0.0)
	var ny := _noise.get_noise_2d(_noise_t, 100.0)
	var nz := _noise.get_noise_2d(_noise_t, 200.0)

	var target_roll := -_input_dir.x * deg_to_rad(2.0)
	if _stun > 0.0:
		target_roll += deg_to_rad(22.0) * sin(_stun * 16.0)
	if dead:
		target_roll += deg_to_rad(70.0)
	if _sliding:
		target_roll += deg_to_rad(4.0)
	_roll = lerpf(_roll, target_roll, 1.0 - exp(-8.0 * delta))

	var ang := deg_to_rad(shake_max_angle_deg)
	var peek_rot := Vector3.ZERO
	var peek_y := 0.0
	if Game.peek_mode and rail_lock:
		var pk := GazeProvider.peek_offset_current()
		var plook := GazeProvider.peek_look(delta)
		peek_rot = Vector3(plook.y, plook.x, -pk.x * 0.05)     # head turn / nod, and a little roll into the lean
		peek_y = clampf(pk.y, -0.9, 0.3)                      # stooping lowers the eyes without pitching at the ground
	camera.rotation = Vector3(_pitch_pos + nx * s * ang + peek_rot.x, ny * s * ang + peek_rot.y, _roll + nz * s * ang + peek_rot.z)
	camera.position = _off_pos + Vector3(nx, ny, 0.0) * s * shake_max_offset + Vector3(0.0, peek_y, 0.0)


# --------------------------------------------------------------------------
# Health
# --------------------------------------------------------------------------
func max_hp() -> float:
	return base_max_health * Prog.mult("max_hp")


func heal(amount: float) -> void:
	if dead:
		return
	health = minf(max_hp(), health + amount)


func take_damage(amount: float, _from: Vector3, knockback: Vector3 = Vector3.ZERO) -> void:
	if dead or amount <= 0.0 or _invuln > 0.0:
		return
	if Prog.has_powerup("shield"):
		Game.popup("NOPE!", global_position + Vector3.UP * 1.8, Color(0.4, 0.7, 1.0))
		_invuln = 0.3
		return
	var dmg := amount * Prog.mult("damage_taken")
	health -= dmg
	_invuln = 0.55
	_regen_delay = 4.0
	apply_push(knockback * Prog.mult("knockback"))
	add_trauma(0.55, 0.9)
	Game.rumble(0.5, 0.9, 0.25)
	Game.sfx(&"hurt")
	Game.player_hurt.emit(dmg)
	if health > 0.0:
		return
	if Prog.flag("secondwind") and _second_wind:
		_second_wind = false
		health = max_hp() * 0.5
		_invuln = 1.5
		Game.banner("SECOND WIND!", Color(0.4, 1.0, 0.6), 1.8)
		Fx.shockwave(self, global_position, 9.0, 30.0, 40.0, false, true, &"shockwave")
		return
	health = 0.0
	dead = true
	if _sliding:
		_end_slide()
	died.emit()


## Banana-peel stumble: brief loss of control, a little damage.
func slip() -> void:
	if dead:
		return
	_stun = 0.9
	var h := Vector3(velocity.x, 0.0, velocity.z)
	var dir := h.normalized() if h.length() > 0.5 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	velocity = dir * maxf(h.length(), 6.0) * 1.2 + Vector3.UP * 7.0
	if _sliding:
		_end_slide()
	take_damage(6.0, global_position)


func revive(at: Vector3) -> void:
	dead = false
	health = max_hp()
	_invuln = 2.0
	_stun = 0.0
	velocity = Vector3.ZERO
	global_position = at
	head.rotation.x = 0.0
	_second_wind = true


func reset_wave_state() -> void:
	_second_wind = true
