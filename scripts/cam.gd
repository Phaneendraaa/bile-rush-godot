extends Camera3D
## Rider views:
##   0 COCKPIT  - first person over the handlebars (hands, mirrors, dash)
##   1 HELMET   - helmet-cam, rolls fully with the bike
##   2 CHASE    - close chase
##   3 FAR      - high/far chase
##   4 ONBOARD  - low camera on the front fairing, road rushing past
##   5 TV       - trackside cinematic cameras

const NAMES := ["COCKPIT", "HELMET CAM", "CHASE", "FAR CHASE", "ONBOARD", "TV CAMERA"]

var target: RigidBody3D
var eye := Vector3(0, 1.4, 0.12)   # set from the cockpit for the current bike
var mode := 0
var shake := 0.0
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _fresh := true
var _yaw := 0.0
var _tv_pos := Vector3.ZERO
var _tv_timer := 0.0
var _t := 0.0


func snap() -> void:
	_fresh = true


func cycle() -> void:
	mode = (mode + 1) % NAMES.size()
	_fresh = true
	_tv_timer = 0.0


func mode_name() -> String:
	return NAMES[mode]


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	_t += delta
	var xf := target.global_transform
	var b := xf.basis.orthonormalized()
	var fwd := -b.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length_squared() < 1e-4:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	var yaw := atan2(-flat.x, -flat.z)
	if _fresh:
		_yaw = yaw
	_yaw = lerp_angle(_yaw, yaw, clampf(delta * 6.0, 0.0, 1.0))
	var dirv := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var spd: float = target.get("speed")
	var lean: float = target.get("lean")
	var crashed: bool = target.get("is_crashed")
	var p := xf.origin
	var sh := Vector3.ZERO
	if shake > 0.0:
		sh = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.08
		shake = maxf(0.0, shake - delta * 2.5)
	# engine / road vibration at speed for the on-bike views
	var vib := Vector3(sin(_t * 61.0), sin(_t * 47.0 + 1.3), 0.0) * 0.0025 * clampf(absf(spd) / 40.0, 0.0, 1.5)
	var fov_t := 62.0 + clampf(spd / 80.0, 0.0, 1.0) * 12.0

	if (mode == 0 or mode == 1 or mode == 4) and not crashed:
		var e := eye
		if mode == 1:
			e = eye + Vector3(0, 0.14, 0.08)
		elif mode == 4:
			e = Vector3(0, 0.95, -0.95)
		var basis_cam := b
		if mode == 0:
			# the rider's head counters part of the lean (horizon tilts less than the bike)
			basis_cam = b.rotated(-b.z.normalized(), -lean * 0.28)
		basis_cam = basis_cam * Basis(Vector3.RIGHT, deg_to_rad(-6.0 if mode != 4 else -2.0))
		global_transform = Transform3D(basis_cam.orthonormalized(), xf * e + b * vib + sh)
		fov = lerpf(fov, fov_t + (10.0 if mode == 0 else 6.0), clampf(delta * 2.0, 0.0, 1.0))
		_pos = global_position
		_look = global_position + (-global_basis.z) * 10.0
		_fresh = false
		return

	var want_pos: Vector3
	var want_look: Vector3
	var roll := 0.0
	var k_pos := 7.0
	if mode == 5:
		# trackside camera: placed ahead beside the road, cut to a new one when passed
		_tv_timer -= delta
		var rel := p - _tv_pos
		if _fresh or _tv_timer <= 0.0 or rel.dot(dirv) > 30.0 or rel.length() > 120.0:
			var side := Vector3(-dirv.z, 0, dirv.x) * (9.0 if randf() < 0.5 else -9.0)
			_tv_pos = p + dirv * (60.0 + spd * 1.2) + side + Vector3(0, 2.2 + randf() * 3.0, 0)
			_tv_timer = 6.0
			_fresh = true
		want_pos = _tv_pos
		want_look = p + Vector3(0, 0.9, 0)
		k_pos = 1000.0
		var dist := _tv_pos.distance_to(p)
		fov_t = clampf(2400.0 / maxf(dist, 1.0), 14.0, 60.0)
	elif mode == 3:
		want_pos = p - dirv * 10.0 + Vector3(0, 3.8, 0)
		want_look = p + dirv * 8.0 + Vector3(0, 0.9, 0)
	else:
		var back := 4.8 + clampf(spd / 80.0, 0.0, 1.0) * 1.2
		want_pos = p - dirv * back + Vector3(0, 1.85, 0)
		want_look = p + dirv * 6.0 + Vector3(0, 1.0, 0)
		roll = -lean * 0.12
	var k := 1.0 if _fresh else clampf(delta * k_pos, 0.0, 1.0)
	_pos = _pos.lerp(want_pos, k)
	_look = _look.lerp(want_look, 1.0 if _fresh else clampf(delta * 14.0, 0.0, 1.0))
	_fresh = false
	global_position = _pos + sh
	if _look.distance_squared_to(global_position) > 0.01:
		look_at(_look, Vector3.UP)
	rotate_object_local(Vector3(0, 0, 1), roll)
	fov = lerpf(fov, fov_t, clampf(delta * (8.0 if mode == 5 else 2.0), 0.0, 1.0))
