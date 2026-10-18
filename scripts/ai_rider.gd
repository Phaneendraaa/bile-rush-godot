extends RefCounted
## Racing AI: follows a racing line with pure-pursuit, plans speed from upcoming curvature
## and braking distance, avoids riders ahead. Drives the bike through the same inputs as a human.

const TD = preload("res://scripts/track_data.gd")

var skill := 1.0          # 0.85 .. 1.05 (pace)
var corner_margin := 0.88 # fraction of grip used in corners
var brake_decel := 8.5
var lane_bias := 0.0
var _d_target := 0.0
var _steer := 0.0


## Returns [steer, throttle, brake]
func drive(bike, track: TD, others: Array, dt: float) -> Array:
	var v: float = maxf(bike.speed, 0.0)
	var s: float = bike.progress
	var look := 14.0 + v * 0.55
	# racing line: swing to the inside of the upcoming bend
	var k_ahead := track.curv_at(s + look + 10.0)
	var line := clampf(-k_ahead * 520.0, -5.2, 5.2) + lane_bias
	# overtaking / avoidance
	for o in others:
		if o == bike or o.is_crashed:
			continue
		var gap: float = o.progress - s
		if gap > 0.0 and gap < 18.0 + v * 0.3 and absf(o.lateral - bike.lateral) < 2.2 and v > o.speed - 1.0:
			line = o.lateral + (2.8 if o.lateral < 0.0 else -2.8)
	line = clampf(line, -TD.ROAD_HALF + 1.3, TD.ROAD_HALF - 1.3)
	_d_target = lerpf(_d_target, line, clampf(dt * 1.2, 0.0, 1.0))
	_steer = lerpf(_steer, pursuit_steer(bike, track, _d_target), clampf(dt * 10.0, 0.0, 1.0))
	var lean_max := deg_to_rad(8.0) + deg_to_rad(52.0) * smoothstep(3.0, 20.0, v)
	lean_max = minf(lean_max, atan(1.18 * 0.93))

	var vt := target_speed(bike, track, corner_margin, skill, brake_decel)
	var thr := clampf((vt - v) * 0.45 + 0.15, 0.0, 1.0)
	var brk := clampf((v - vt - 1.0) * 0.22, 0.0, 1.0)
	if brk > 0.0:
		thr = 0.0
	# ease off while leaned hard
	thr *= 1.0 - 0.5 * smoothstep(0.6, 0.95, absf(bike.lean) / maxf(lean_max, 0.1))
	return [_steer, thr, brk]


## Pure-pursuit steering command (-1..1, + = lean right) toward lateral offset d_target ahead.
func pursuit_steer(bike, track: TD, d_target: float) -> float:
	var v: float = maxf(bike.speed, 0.0)
	var look := 14.0 + v * 0.55
	var f: Dictionary = track.frame(bike.progress + look, d_target)
	var tp: Vector3 = f["pos"]
	var xf: Transform3D = bike.global_transform
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var to := tp - xf.origin
	to.y = 0.0
	var dist := maxf(to.length(), 1.0)
	var cross := fwd.cross(to / dist).y      # + = target is to the left
	var alpha := asin(clampf(cross, -1.0, 1.0))
	var kappa := 2.0 * sin(alpha) / dist
	var lean_needed := atan(v * v * kappa / 9.81)
	var lean_max := deg_to_rad(8.0) + deg_to_rad(52.0) * smoothstep(3.0, 20.0, v)
	lean_max = minf(lean_max, atan(1.18 * 0.93))
	return clampf(-lean_needed / lean_max, -1.0, 1.0)


## Highest speed that still allows braking for every corner in the next 320 m.
static func target_speed(bike, track: TD, margin: float, pace: float, decel: float) -> float:
	var v: float = maxf(bike.speed, 0.0)
	var s: float = bike.progress
	var vt := 95.0 * pace
	var mu_use := 1.18 * margin
	var x := 0.0
	while x < 320.0:
		var kk := absf(track.curv_at(s + x))
		if kk > 1e-4:
			var vc := sqrt(9.81 * mu_use / kk) * pace
			var allow := sqrt(vc * vc + 2.0 * decel * maxf(x - v * 0.25, 0.0))
			vt = minf(vt, allow)
		x += 6.0
	return vt
