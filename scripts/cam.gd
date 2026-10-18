extends Camera3D
## Chase / close / onboard camera with spring smoothing, speed FOV and shake.

var target: RigidBody3D
var mode := 0
var shake := 0.0
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _init := true
var _yaw := 0.0


func snap() -> void:
	_init = true


func cycle() -> void:
	mode = (mode + 1) % 3
	_init = true


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var xf := target.global_transform
	var fwd := -xf.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length_squared() < 1e-4:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	var yaw := atan2(-flat.x, -flat.z)
	if _init:
		_yaw = yaw
	_yaw = lerp_angle(_yaw, yaw, clampf(delta * (14.0 if mode == 2 else 5.0), 0.0, 1.0))
	var dirv := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var spd: float = target.get("speed")
	var lean: float = target.get("lean")
	var p := xf.origin
	var want_pos: Vector3
	var want_look: Vector3
	var roll := 0.0
	if mode == 0:
		var back := 5.4 + clampf(spd / 80.0, 0.0, 1.0) * 1.0
		want_pos = p - dirv * back + Vector3(0, 2.1, 0)
		want_look = p + dirv * 6.0 + Vector3(0, 1.0, 0)
		roll = -lean * 0.12
	elif mode == 1:
		want_pos = p - dirv * 9.5 + Vector3(0, 3.6, 0)
		want_look = p + dirv * 8.0 + Vector3(0, 0.9, 0)
		roll = 0.0
	else:
		# helmet cam: rides with the bike, partially counter-rolls like a rider's head
		want_pos = xf * Vector3(0.0, 1.62, -0.05)
		want_look = xf * Vector3(0.0, 1.35, -12.0)
		roll = -lean * 0.55
	var k := 1.0 if _init else clampf(delta * (40.0 if mode == 2 else 7.0), 0.0, 1.0)
	_pos = _pos.lerp(want_pos, k)
	_look = _look.lerp(want_look, 1.0 if _init else clampf(delta * 14.0, 0.0, 1.0))
	_init = false
	var sh := Vector3.ZERO
	if shake > 0.0:
		sh = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.08
		shake = maxf(0.0, shake - delta * 2.5)
	global_position = _pos + sh
	if _look.distance_squared_to(global_position) > 0.01:
		look_at(_look, Vector3.UP)
	rotate_object_local(Vector3(0, 0, 1), roll)
	var fov_t := 62.0 + clampf(spd / 80.0, 0.0, 1.0) * 12.0
	if mode == 2:
		fov_t += 6.0
	fov = lerpf(fov, fov_t, clampf(delta * 2.0, 0.0, 1.0))
