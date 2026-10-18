extends RigidBody3D
## Single-track vehicle physics.
##   - two ray-cast wheels with torus tyre profile, progressive spring/damper suspension
##   - tyre model: slip-angle + camber thrust, friction circle per surface, rolling resistance
##   - 1000cc-class engine torque curve, 6-speed sequential box, clutch slip, engine braking
##   - aero drag (tuck), front/rear brakes with optional ABS, traction & wheelie control
##   - rider balance: lean controller (abstracts counter-steering), kinematic steering angle
##   - crash detection: lowside (front slide), highside-ish (rear slide), loop-out, wall impact
## Local frame: forward = -Z, right = +X, up = +Y. Origin on the ground under the COM.

const TD = preload("res://scripts/track_data.gd")

signal crashed(bike)

# ---------------- tunables
const WHEELBASE := 1.42
const R := 0.31            # wheel radius
const RT := 0.09           # tyre crown radius (profile)
const TRAVEL := 0.17       # suspension travel
const SPRING_F := 30000.0
const SPRING_R := 34000.0
const DAMP_BUMP := 2300.0
const DAMP_REB := 3400.0
const CDA_TUCK := 0.30
const CDA_UP := 0.45
const REDLINE := 13000.0
const IDLE := 1600.0
const GEAR_TOP := [0.0, 31.0, 42.0, 51.5, 60.5, 70.0, 82.0]   # m/s at redline per gear
const TORQUE_RPM := [0.0, 1500.0, 4000.0, 6000.0, 8000.0, 10000.0, 11500.0, 13000.0, 14000.0]
const TORQUE_NM := [20.0, 48.0, 72.0, 84.0, 98.0, 108.0, 112.0, 101.0, 70.0]
const C_ALPHA := 13.0      # normalised cornering stiffness (1/rad)
const C_GAMMA := 0.95      # camber thrust coefficient

# ---------------- inputs (set by player/AI each frame)
var steer := 0.0       # -1..1 desired lean direction (+ = right)
var throttle := 0.0
var brake := 0.0
var tuck := 1.0
var aids := {"abs": true, "tc": true, "wheelie": true, "lean_limit": true}

# ---------------- state / telemetry
var track: TD
var idx_hint := 0
var lap_s := 0.0          # distance in current lap
var progress := 0.0       # total distance raced (laps * L + lap_s)
var lateral := 0.0
var speed := 0.0
var gear := 1
var rpm := IDLE
var lean := 0.0           # actual lean angle (+ right)
var lean_target := 0.0
var steer_angle := 0.0
var pitch := 0.0
var front_load := 0.0
var rear_load := 0.0
var front_slide := 0.0
var rear_slide := 0.0
var wheelspin := 0.0
var surface := "road"
var on_ground := true
var is_crashed := false
var crash_timer := 0.0
var shift_timer := 0.0
var wheel_spin_angle := 0.0
var front_comp := 0.0
var rear_comp := 0.0
var front_ext := 0.12
var rear_ext := 0.12
var abs_active := false
var tc_active := false
var scrape := 0.0
var _pending_reset: Variant = null
var _prev_comp := [0.0, 0.0]
var _normals := [Vector3.UP, Vector3.UP]
var _slide_time := 0.0
var _laps_base := 0
var _last_lap_s := 0.0
var rider_offset := 0.0   # visual hang-off -1..1


func _ready() -> void:
	mass = 250.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.62, 0.05)
	inertia = Vector3(62.0, 58.0, 19.0)
	gravity_scale = 1.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.4
	can_sleep = false
	continuous_cd = true
	custom_integrator = false
	contact_monitor = true
	max_contacts_reported = 4
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.05
	physics_material_override = pm
	_add_shape(_box(Vector3(0.36, 0.55, 1.45)), Vector3(0, 0.78, 0))
	var cap := CapsuleShape3D.new()
	cap.radius = 0.24
	cap.height = 0.9
	_add_shape(cap, Vector3(0, 1.28, 0.0), Basis(Vector3.RIGHT, -1.0))
	for z in [-WHEELBASE * 0.5, WHEELBASE * 0.5]:
		var sp := SphereShape3D.new()
		sp.radius = 0.2
		_add_shape(sp, Vector3(0, R, z))
	body_entered.connect(_on_body_entered)


func _box(sz: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = sz
	return b


func _add_shape(s: Shape3D, pos: Vector3, basis: Basis = Basis()) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.transform = Transform3D(basis, pos)
	add_child(cs)


## Place the bike upright on the track at distance s, lateral d.
func place(s: float, d: float, v: float = 0.0) -> void:
	var f: Dictionary = track.frame(s, d)
	var fwd: Vector3 = f["fwd"]
	var pos: Vector3 = f["pos"] + Vector3(0, 0.02, 0)
	var basis := Basis.looking_at(fwd, Vector3.UP)
	_pending_reset = [Transform3D(basis, pos), fwd * v]
	global_transform = Transform3D(basis, pos)
	linear_velocity = fwd * v
	angular_velocity = Vector3.ZERO
	idx_hint = int(fposmod(s, track.L) / track.ds) % track.N
	_laps_base = int(floorf(s / track.L))
	lap_s = fposmod(s, track.L)
	_last_lap_s = lap_s
	progress = s
	is_crashed = false
	crash_timer = 0.0
	gear = 1 if v < 20.0 else 3
	lean = 0.0
	_slide_time = 0.0


func torque_at(r: float) -> float:
	for i in range(1, TORQUE_RPM.size()):
		if r <= TORQUE_RPM[i]:
			var a: float = TORQUE_RPM[i - 1]
			var b: float = TORQUE_RPM[i]
			return lerpf(TORQUE_NM[i - 1], TORQUE_NM[i], (r - a) / (b - a))
	return 0.0


func gear_ratio(g: int) -> float:
	# engine rev/s per wheel rev/s
	var wheel_rps: float = GEAR_TOP[g] / (TAU * R)
	return (REDLINE / 60.0) / wheel_rps


func _integrate_forces(st: PhysicsDirectBodyState3D) -> void:
	var dt := st.step
	if _pending_reset != null:
		var pr: Array = _pending_reset
		st.transform = pr[0]
		st.linear_velocity = pr[1]
		st.angular_velocity = Vector3.ZERO
		_pending_reset = null
		_prev_comp = [0.0, 0.0]
		return
	var xf := st.transform
	var b := xf.basis
	var up := b.y.normalized()
	var right := b.x.normalized()
	var fwd := -b.z.normalized()
	var com := xf.origin + b * center_of_mass   # world-space COM
	var v := st.linear_velocity
	speed = v.dot(fwd)
	var space := st.get_space_state()

	# ---- track progress & surface
	_update_progress(xf.origin)
	surface = "road"
	var al := absf(lateral)
	if al > TD.ROAD_HALF + 0.05:
		surface = "curb" if al < TD.ROAD_HALF + TD.CURB and _curb_here() else "grass"
	var mu := 1.18
	var roll_res := 0.016
	if surface == "curb":
		mu = 0.98; roll_res = 0.03
	elif surface == "grass":
		mu = 0.55; roll_res = 0.11
	if is_crashed:
		mu *= 0.5

	# ---- engine & drivetrain
	shift_timer = maxf(0.0, shift_timer - dt)
	var wheel_rps := absf(speed) / (TAU * R)
	var eng_rps := wheel_rps * gear_ratio(gear)
	var r_from_wheel := eng_rps * 60.0
	# auto shift
	if not is_crashed and shift_timer <= 0.0:
		if r_from_wheel > REDLINE * 0.965 and gear < 6:
			gear += 1; shift_timer = 0.14
		elif gear > 1 and wheel_rps * gear_ratio(gear - 1) * 60.0 < REDLINE * 0.8 and (r_from_wheel < 7200.0 or (brake > 0.3 and r_from_wheel < 9500.0)):
			gear -= 1; shift_timer = 0.1
	var clutch_rpm := IDLE + throttle * 6500.0
	var slipping := gear == 1 and r_from_wheel < clutch_rpm
	var target_rpm := maxf(r_from_wheel, clutch_rpm) if slipping else maxf(r_from_wheel, IDLE)
	rpm = lerpf(rpm, minf(target_rpm, REDLINE * 1.02), clampf(dt * 12.0, 0.0, 1.0))
	var drive := 0.0
	if not is_crashed and shift_timer <= 0.06:
		var tq := torque_at(rpm) * throttle
		if r_from_wheel >= REDLINE * 1.01:
			tq = 0.0  # limiter
		drive = tq * gear_ratio(gear) * 0.9 / R
		if throttle < 0.05 and speed > 2.0:
			drive -= (rpm / REDLINE) * 380.0  # engine braking
		# wheelie control: cut drive as the front lifts (uses last step's pitch)
		if aids["wheelie"] and drive > 0.0 and pitch > deg_to_rad(4.0):
			drive *= clampf(1.0 - (pitch - deg_to_rad(4.0)) / deg_to_rad(5.0), 0.0, 1.0)
			tc_active = true
	var d_tuck := lerpf(CDA_UP, CDA_TUCK, tuck)
	var drag := 0.5 * 1.2 * d_tuck * speed * absf(speed)
	st.apply_central_force(-fwd * drag)

	# ---- wheels
	var on_cnt := 0
	var loads := [0.0, 0.0]
	front_slide = 0.0
	rear_slide = 0.0
	abs_active = false
	tc_active = false
	wheelspin = 0.0
	var spd_h := maxf(absf(speed), 0.5)
	# kinematic steering from current lean (coordinated turn), plus low-speed direct steering
	var phi := lean
	var kin := -atan(WHEELBASE * 9.81 * tan(clampf(phi, -1.2, 1.2)) / maxf(speed * speed, 9.0))
	var low := 1.0 - smoothstep(2.0, 6.0, absf(speed))
	steer_angle = clampf(lerpf(kin, -steer * 0.5, low), -0.55, 0.55)
	if is_crashed:
		steer_angle = 0.0
	var brake_f := brake * (0.0 if is_crashed else 1.0)
	var mean_n := Vector3.ZERO
	for w in 2:
		var zloc := -WHEELBASE * 0.5 if w == 0 else WHEELBASE * 0.5
		var anchor := xf * Vector3(0.0, R + 0.12, zloc)
		var n: Vector3 = _normals[w]
		var dn := -n - right * (-n).dot(right)
		if dn.length_squared() < 1e-4:
			dn = -up
		dn = dn.normalized()
		var origin := anchor + dn * (R - RT) + n * 0.6
		var target := origin - n * (TRAVEL + R + 1.0)
		var q := PhysicsRayQueryParameters3D.create(origin, target, 1, [get_rid()])
		var hit := space.intersect_ray(q)
		var ext := TRAVEL
		var contact := Vector3.ZERO
		var grounded := false
		if not hit.is_empty():
			var hn: Vector3 = hit["normal"]
			if hn.dot(Vector3.UP) < 0.0:
				hn = -hn
			var gp: Vector3 = hit["position"]
			var qpt := anchor + dn * (R - RT) - hn * RT
			var nu := hn.dot(up)
			if nu > 0.2:
				var s_star := hn.dot(qpt - gp) / nu
				if s_star < TRAVEL:
					grounded = true
					ext = maxf(s_star, 0.0)
					contact = anchor - up * ext + dn * (R - RT) - hn * RT
					_normals[w] = _normals[w].lerp(hn, 0.5).normalized()
					n = _normals[w]
		if w == 0:
			front_ext = ext
		else:
			rear_ext = ext
		var comp := TRAVEL - ext
		var cvel: float = (comp - _prev_comp[w]) / dt
		_prev_comp[w] = comp
		if not grounded:
			continue
		on_cnt += 1
		mean_n += n
		var k := SPRING_F if w == 0 else SPRING_R
		var fs := k * comp * (1.0 + 1.5 * comp)  # progressive
		fs += (DAMP_BUMP if cvel > 0.0 else DAMP_REB) * cvel
		if comp > TRAVEL * 0.92:
			fs += 250000.0 * (comp - TRAVEL * 0.92)  # bump stop
		fs = maxf(fs, 0.0)
		var fz := fs * maxf(n.dot(up), 0.2)
		loads[w] = fz
		var rel := contact - xf.origin
		st.apply_force(n * fz, rel)

		# --- tyre forces
		var wf := fwd
		if w == 0:
			wf = fwd.rotated(up, steer_angle)
		wf = (wf - n * wf.dot(n)).normalized()
		var wr := wf.cross(n)              # right in contact plane
		var vc := st.get_velocity_at_local_position(rel)
		var vlong := vc.dot(wf)
		var vlat := vc.dot(wr)
		# camber: lean of wheel plane relative to ground normal (+ = leaning right)
		var gamma := atan2(up.dot(wr), up.dot(n))
		var alpha := atan2(vlat, maxf(absf(vlong), 6.0))
		var fy := fz * (-C_ALPHA * alpha + C_GAMMA * gamma) if not is_crashed else -fz * clampf(vlat, -1.0, 1.0)
		# longitudinal demand
		var fx := 0.0
		if w == 1:
			fx += drive
		var bmax := fz * mu * (1.05 if w == 0 else 0.7)
		var bdem := brake_f * (0.75 if w == 0 else 0.25) * (fz * 1.5 + 1500.0)
		if aids["abs"] and bdem > bmax * 0.97:
			bdem = bmax * 0.97
			if brake_f > 0.1 and absf(vlong) > 3.0:
				abs_active = true
		var lock := bdem > bmax
		if absf(vlong) > 0.3:
			fx -= signf(vlong) * bdem
		else:
			fx -= vlong * mass * 0.5 * brake_f
		fx -= signf(vlong) * roll_res * fz
		var fmax := mu * fz
		# traction control: keep rear demand inside grip budget
		if w == 1 and aids["tc"]:
			var budget := maxf(sqrt(maxf(fmax * fmax - fy * fy, 0.0)) * 0.96, fmax * 0.3)
			if fx > budget:
				fx = budget
				if throttle > 0.2:
					tc_active = true
		var ftot := Vector2(fx, fy)
		var flen := ftot.length()
		var sl := 0.0
		if flen > fmax and fmax > 0.0:
			sl = (flen - fmax) / fmax
			ftot *= fmax / flen
			if lock and w == 0:
				ftot.y *= 0.35  # locked front: steering grip gone
		if w == 0:
			front_slide = sl
		else:
			rear_slide = sl
			if w == 1 and drive > fmax:
				wheelspin = clampf((drive - fmax) / fmax, 0.0, 1.0)
		st.apply_force(wf * ftot.x + wr * ftot.y, rel)
	front_load = loads[0]
	rear_load = loads[1]
	on_ground = on_cnt > 0
	var gn := (mean_n / on_cnt).normalized() if on_cnt > 0 else Vector3.UP

	# ---- rider: lean control (balancing + counter-steering abstraction)
	var gf := (fwd - gn * fwd.dot(gn)).normalized()
	var gr := gf.cross(gn)
	lean = atan2(up.dot(gr), up.dot(gn))
	pitch = asin(clampf(fwd.dot(Vector3.UP), -1.0, 1.0)) - asin(clampf(gf.dot(Vector3.UP), -1.0, 1.0))
	var vmag := absf(speed)
	var lean_max := deg_to_rad(8.0) + deg_to_rad(52.0) * smoothstep(3.0, 20.0, vmag)
	if aids["lean_limit"]:
		lean_max = minf(lean_max, atan(mu * 0.93))
	lean_target = steer * lean_max
	rider_offset = lerpf(rider_offset, clampf(lean / 0.9, -1.0, 1.0), clampf(dt * 4.0, 0.0, 1.0))
	if not is_crashed:
		var roll_rate := st.angular_velocity.dot(gf)
		# PD on lean about the contact line (I_eff ~ 120 kg m^2), near-critically damped,
		# plus gravity feed-forward for the target lean and a hard stop beyond the limit
		var kp := 9000.0 + 110.0 * vmag
		var kd := 1.9 * sqrt(kp * 120.0)
		var tau := kp * (lean_target - lean) - kd * roll_rate
		tau += mass * 9.81 * 0.62 * sin(lean_target) * 0.35
		var over := absf(lean) - (lean_max + deg_to_rad(6.0))
		if over > 0.0:
			tau -= signf(lean) * over * 40000.0
		if not on_ground:
			tau *= 0.3
		st.apply_torque(gf * tau)
		# yaw stabiliser at very low speed (rider's feet / steering)
		if vmag < 4.0 and on_ground:
			var want_yaw := -steer * 0.8 * smoothstep(0.3, 2.0, vmag)
			st.apply_torque(gn * (want_yaw - st.angular_velocity.dot(gn)) * 120.0)
	# ---- crash detection
	if not is_crashed:
		var slide := maxf(front_slide, rear_slide * 0.7)
		if slide > 0.45 and absf(lean) > deg_to_rad(30.0) and vmag > 8.0:
			_slide_time += dt
		else:
			_slide_time = maxf(0.0, _slide_time - dt * 2.0)
		if _slide_time > 0.45:
			_crash("lowside")
		elif absf(lean) > deg_to_rad(68.0) and vmag > 3.0:
			_crash("fell")
		elif up.dot(Vector3.UP) < 0.25:
			_crash("flipped")
		elif pitch > deg_to_rad(65.0):
			_crash("looped")
	else:
		crash_timer += dt


func _update_progress(p: Vector3) -> void:
	var r: Array = track.project(p, idx_hint)
	idx_hint = r[0]
	var s: float = r[1]
	lateral = r[2]
	s = fposmod(s, track.L)
	# lap wrap detection
	if _last_lap_s > track.L * 0.8 and s < track.L * 0.2:
		_laps_base += 1
	elif _last_lap_s < track.L * 0.2 and s > track.L * 0.8:
		_laps_base -= 1
	_last_lap_s = s
	lap_s = s
	progress = _laps_base * track.L + s


func _curb_here() -> bool:
	return absf(track.K[idx_hint]) > 1.0 / 900.0


func _on_body_entered(body: Node) -> void:
	if is_crashed:
		return
	var rel := linear_velocity.length()
	if body.name == "Walls":
		var into := absf(linear_velocity.normalized().dot(_wall_normal()))
		if rel * into > 9.0:
			_crash("wall")
		else:
			scrape = 1.0
	elif body is RigidBody3D:
		var other: RigidBody3D = body
		var dv := (linear_velocity - other.linear_velocity).length()
		if dv > 14.0:
			_crash("collision")


func _wall_normal() -> Vector3:
	var f: Dictionary = track.frame(lap_s, 0.0)
	var r: Vector3 = f["right"]
	return r * signf(lateral)


func _crash(why: String) -> void:
	is_crashed = true
	crash_timer = 0.0
	throttle = 0.0
	set_meta("crash_reason", why)
	crashed.emit(self)


func _physics_process(delta: float) -> void:
	scrape = maxf(0.0, scrape - delta * 3.0)
	wheel_spin_angle += speed / R * delta
