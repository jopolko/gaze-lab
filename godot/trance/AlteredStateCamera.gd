class_name AlteredStateCamera
extends Camera3D
## A camera that never quite holds still, driven by one `intensity` (0 = a normal steady camera, 1 = very strong).
##
##   vestibular drift   slow, smooth, non-repeating sway in pitch / yaw / roll plus a little positional float (FastNoiseLite)
##   head bob / nod     two phases per cycle: a slow lift, then a gravity drop (pow(x, 3.0): slow start, fast finish)
##   nystagmus          sawtooth: a slow drift one way, then a rapid snap back. `nystagmus_uv` feeds the post shader.
##
## Strong camera motion can make people dizzy or queasy. Keep `intensity` modest by default and always let the player
## lower it (see TranceRig: - / = keys, the slider, and C for calm).

## 0.0 .. 1.0. Everything below scales with this.
@export_range(0.0, 1.0) var intensity: float = 0.4
@export var drift_speed: float = 0.35
@export var bob_hz: float = 0.28            # about one breath every 3.5 s
@export var nystagmus_hz: float = 1.1
@export var nystagmus_slow_fraction: float = 0.8     # share of each cycle spent in the slow drift

var nystagmus_phase: float = 0.0            # 0..1 sawtooth position
var nystagmus_value: float = 0.0            # -1..1 (slow drift out, fast snap back)
## Screen-space offset for the post-process shader (UV units).
var nystagmus_uv: Vector2 = Vector2.ZERO

var _noise := FastNoiseLite.new()
var _t: float = 0.0
var _base := Transform3D.IDENTITY
var _have_base: bool = false
var _punch: float = 0.0


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.fractal_octaves = 2
	_noise.seed = randi()
	set_base(transform)


## Remember the "steady" pose the effects are added on top of.
func set_base(t: Transform3D) -> void:
	_base = t
	_have_base = true


## A one-off jolt (used on a release). Decays by itself.
func punch(amount: float) -> void:
	_punch = maxf(_punch, amount)


## Pure: the sawtooth. Slow drift 0 -> 1 over `slow_fraction` of the cycle, then a fast snap back 1 -> 0.
static func sawtooth(phase: float, slow_fraction: float) -> float:
	var p := fposmod(phase, 1.0)
	if p < slow_fraction:
		return p / slow_fraction
	return 1.0 - (p - slow_fraction) / (1.0 - slow_fraction)


## Pure: the bob. Slow lift, then a gravity drop. Returns 0..1.
static func bob(phase: float) -> float:
	var u := fposmod(phase, 1.0)
	if u < 0.5:
		return sin((u / 0.5) * PI * 0.5)            # ease-out lift
	var d := (u - 0.5) / 0.5
	return 1.0 - pow(d, 3.0)                        # gravity: slow to start falling, fast at the bottom


func _process(delta: float) -> void:
	if not _have_base:
		return
	_t += delta
	var i := clampf(intensity, 0.0, 1.0)
	var ts := _t * drift_speed
	var drift := Vector3(_noise.get_noise_2d(ts, 0.0), _noise.get_noise_2d(ts, 37.0), _noise.get_noise_2d(ts * 0.8, 91.0))
	var rot := Vector3(drift.x * 0.035, drift.y * 0.05, drift.z * 0.06) * i          # radians: about 2, 3 and 3.5 degrees
	var sway := Vector3(_noise.get_noise_2d(ts, 140.0), _noise.get_noise_2d(ts, 190.0), 0.0) * 0.06 * i

	var lift := AlteredStateCamera.bob(_t * bob_hz)
	rot.x += (lift - 0.5) * 0.03 * i                                                # nod
	sway.y += (lift - 0.5) * 0.05 * i                                               # rise and drop

	nystagmus_phase = fposmod(_t * nystagmus_hz, 1.0)
	nystagmus_value = AlteredStateCamera.sawtooth(nystagmus_phase, nystagmus_slow_fraction) * 2.0 - 1.0
	rot.y += nystagmus_value * 0.022 * i
	nystagmus_uv = Vector2(nystagmus_value * 0.006 * i, 0.0)

	_punch = maxf(_punch - 2.5 * delta, 0.0)
	rot.x += _punch * 0.04 * sin(_t * 40.0)
	rot.z += _punch * 0.05 * sin(_t * 33.0)

	var b := _base.basis * Basis.from_euler(rot)
	transform = Transform3D(b, _base.origin + _base.basis * sway)
