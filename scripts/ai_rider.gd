extends RefCounted
## Racing AI: follows a racing line with pure-pursuit, plans speed from upcoming curvature
## and braking distance, avoids riders ahead. Drives the bike through the same inputs as a human.

const TD = preload("res://scripts/track_data.gd")

var skill := 1.0          # 0.85 .. 1.05 (pace)
var corner_margin := 0.8  # lateral acceleration used in corners (g)
var brake_decel := 8.5
var lane_bias := 0.0
var _d_target := 0.0
var _steer := 0.0
var cars: Array = []        # highway traffic (dicts from traffic.gd) to weave through
var lanes: Array = [1.75, 5.25]


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
	var traffic_cap := 1e9
	if not cars.is_empty():
		# pick the lane whose nearest vehicle ahead is furthest away; slow down if all are blocked
		var best_lane: float = line
		var best_gap := -1.0
		for ln in lanes:
			var gap := 1e9
			for c in cars:
				var ds: float = float(c["s"]) - s
				if ds > -6.0 and ds < 140.0 and absf(float(c["d"]) - float(ln)) < 2.3:
					gap = minf(gap, ds - float(c["len"]) * 0.5)
			var cost := gap - absf(float(ln) - bike.lateral) * 4.0
			if cost > best_gap:
				best_gap = cost
				best_lane = ln
		line = best_lane
		for c in cars:
			var ds2: float = float(c["s"]) - s
			if ds2 > 0.0 and ds2 < 70.0 and absf(float(c["d"]) - bike.lateral) < 2.0:
				var cv: float = c["v"]
				if c["onc"]:
					cv = -cv
				traffic_cap = minf(traffic_cap, cv + ds2 * 0.35)
	line = clampf(line, -TD.ROAD_HALF + 1.3, TD.ROAD_HALF - 1.3)
	_d_target = lerpf(_d_target, line, clampf(dt * 1.2, 0.0, 1.0))
	_steer = lerpf(_steer, pursuit_steer(bike, track, _d_target), clampf(dt * 10.0, 0.0, 1.0))
	var lean_max := deg_to_rad(8.0) + deg_to_rad(52.0) * smoothstep(3.0, 20.0, v)
	lean_max = minf(lean_max, atan(1.18 * 0.93))

	var vt := minf(target_speed(bike, track, corner_margin, skill, brake_decel), traffic_cap)
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
	var mu_use := margin   # lateral grip budget in g
	var x := 0.0
	while x < 320.0:
		var kk := absf(track.curv_at(s + x))
		if kk > 1e-4:
			var vc := sqrt(9.81 * mu_use / kk) * pace
			var allow := sqrt(vc * vc + 2.0 * decel * maxf(x - v * 0.25, 0.0))
			vt = minf(vt, allow)
		x += 6.0
	return vt
