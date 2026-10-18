extends RefCounted
## Procedural circuit: a closed, non-self-intersecting loop sampled every ~2 m.
## Everything (road mesh, terrain, AI racing line, minimap) is derived from these samples.
## Heading convention: h = 0 points along +Z, forward = (sin h, 0, cos h), right = (-cos h, 0, sin h).

const ROAD_HALF := 7.0     # 14 m wide asphalt
const CURB := 1.2
const RUNOFF := 15.0       # armco barrier distance from centre line

const DEFS := [
	{
		"id": "valley", "name": "Green Valley", "desc": "Rolling hills, flowing fast sweepers",
		"R": 560.0, "harm": [[2, 0.2, 0.3], [3, 0.12, 1.4], [5, 0.05, 2.2], [7, 0.025, 0.4]],
		"hills": 30.0, "seed": 11, "time": "noon", "biome": "grass",
	},
	{
		"id": "coast", "name": "Sunset Coast", "desc": "Seaside curves at golden hour",
		"R": 600.0, "harm": [[2, 0.14, 2.0], [3, 0.16, 0.2], [4, 0.06, 1.1], [6, 0.035, 2.8]],
		"hills": 18.0, "seed": 23, "time": "sunset", "biome": "coast",
	},
	{
		"id": "canyon", "name": "Desert Canyon", "desc": "Hairpins between red rock mesas",
		"R": 500.0, "harm": [[3, 0.2, 0.9], [4, 0.1, 2.5], [5, 0.07, 0.1], [8, 0.02, 1.7]],
		"hills": 36.0, "seed": 37, "time": "afternoon", "biome": "desert",
	},
]

var def: Dictionary
var N: int = 0
var L: float = 0.0
var ds: float = 2.0
var X := PackedFloat32Array()
var Y := PackedFloat32Array()
var Z := PackedFloat32Array()
var HD := PackedFloat32Array()   # heading
var K := PackedFloat32Array()    # signed curvature (+ = left turn)
var GR := PackedFloat32Array()   # grade angle
var BK := PackedFloat32Array()   # bank angle
var min_radius: float = 0.0
var water_level: float = -1000.0
var bounds := Rect2()
var _grid := {}
const CELL := 30.0


static func wrap_angle(a: float) -> float:
	return wrapf(a, -PI, PI)


func _terrain_raw(x: float, z: float) -> float:
	var H: float = def["hills"]
	var sd: float = float(def["seed"])
	return H * (0.55 * sin(x * 0.0042 + 1.3) * cos(z * 0.0037 - 0.7) \
		+ 0.3 * sin((x + z) * 0.0071 + sd) \
		+ 0.15 * cos((x - z) * 0.013 - sd * 0.5) \
		+ 0.05 * sin(x * 0.031 + z * 0.027))


func build(d: Dictionary) -> void:
	def = d
	if def["biome"] == "coast":
		water_level = -6.0
	# control polygon
	var N0 := 72
	var curve := Curve3D.new()
	curve.bake_interval = 1.0
	var pts: Array[Vector3] = []
	for i in N0:
		var a := float(i) / N0 * TAU
		var r := 1.0
		for hm in def["harm"]:
			r += float(hm[1]) * sin(float(hm[0]) * a + float(hm[2]))
		r *= float(def["R"])
		pts.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	# Catmull-Rom -> Bezier handles
	for i in N0:
		var p0 := pts[(i - 1 + N0) % N0]
		var p1 := pts[i]
		var p2 := pts[(i + 1) % N0]
		var tan_v := (p2 - p0) / 6.0
		curve.add_point(p1, -tan_v, tan_v)
	curve.add_point(pts[0], -(pts[1] - pts[N0 - 1]) / 6.0, (pts[1] - pts[N0 - 1]) / 6.0)
	L = curve.get_baked_length()
	N = int(round(L / 2.0))
	ds = L / N
	var px := PackedFloat32Array(); px.resize(N)
	var pz := PackedFloat32Array(); pz.resize(N)
	var py := PackedFloat32Array(); py.resize(N)
	for i in N:
		var p := curve.sample_baked(i * ds, true)
		px[i] = p.x; pz[i] = p.z
		py[i] = _terrain_raw(p.x, p.z)
	var ys := py
	for _p in 4:
		ys = _blur(ys, 30)
	if water_level > -999.0:
		for i in N:
			ys[i] = maxf(ys[i], water_level + 5.0)
	for _p in 2:
		ys = _blur(ys, 10)
	var head := PackedFloat32Array(); head.resize(N)
	var curv := PackedFloat32Array(); curv.resize(N)
	for i in N:
		var j := (i + 1) % N
		var h := (i - 1 + N) % N
		head[i] = atan2(px[j] - px[h], pz[j] - pz[h])
	for i in N:
		var j := (i + 1) % N
		var h := (i - 1 + N) % N
		curv[i] = wrap_angle(head[j] - head[h]) / (2.0 * ds)
	var cs := _blur(_blur(curv, 3), 3)
	# start/finish on the straightest stretch
	var best := 0
	var best_v := 1e9
	for i in N:
		var v := 0.0
		var k := -70
		while k <= 20:
			v += absf(cs[(i + k + N) % N])
			k += 2
		if v < best_v:
			best_v = v; best = i
	X = _shift(px, best); Z = _shift(pz, best); Y = _shift(ys, best)
	HD = _shift(head, best); K = _shift(cs, best)
	GR.resize(N); BK.resize(N)
	var maxk := 0.0
	for i in N:
		GR[i] = atan2(Y[(i + 1) % N] - Y[(i - 1 + N) % N], 2.0 * ds)
		BK[i] = clampf(K[i] * 9.0, -0.1, 0.1)
		maxk = maxf(maxk, absf(K[i]))
	min_radius = 1.0 / maxk
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for i in N:
		mn.x = minf(mn.x, X[i]); mn.y = minf(mn.y, Z[i])
		mx.x = maxf(mx.x, X[i]); mx.y = maxf(mx.y, Z[i])
		var key := _key(floori(X[i] / CELL), floori(Z[i] / CELL))
		if not _grid.has(key):
			_grid[key] = PackedInt32Array()
		var arr: PackedInt32Array = _grid[key]
		arr.append(i)
		_grid[key] = arr
	bounds = Rect2(mn, mx - mn)


func _key(cx: int, cz: int) -> int:
	return cx * 73856093 ^ cz * 19349663


func _blur(arr: PackedFloat32Array, rad: int) -> PackedFloat32Array:
	var n := arr.size()
	var out := PackedFloat32Array(); out.resize(n)
	var sum := 0.0
	for k in range(-rad, rad + 1):
		sum += arr[(k + n) % n]
	for i in n:
		out[i] = sum / (2 * rad + 1)
		sum += arr[(i + rad + 1) % n] - arr[(i - rad + n) % n]
	return out


func _shift(arr: PackedFloat32Array, by: int) -> PackedFloat32Array:
	var n := arr.size()
	var out := PackedFloat32Array(); out.resize(n)
	for i in n:
		out[i] = arr[(i + by) % n]
	return out


## Nearest track sample to a world xz point. Returns [index, distance] or [-1, 1e9].
func nearest(x: float, z: float) -> Array:
	var cx := floori(x / CELL)
	var cz := floori(z / CELL)
	var bd := 1e18
	var bi := -1
	for a in range(-2, 3):
		for b in range(-2, 3):
			var key := _key(cx + a, cz + b)
			if not _grid.has(key):
				continue
			var cell: PackedInt32Array = _grid[key]
			for i in cell:
				var dx := X[i] - x
				var dz := Z[i] - z
				var d2 := dx * dx + dz * dz
				if d2 < bd:
					bd = d2; bi = i
	if bi < 0:
		return [-1, 1e9]
	return [bi, sqrt(bd)]


## Signed lateral offset of a point relative to sample i (+ = right of track).
func lateral(i: int, x: float, z: float) -> float:
	return (x - X[i]) * -cos(HD[i]) + (z - Z[i]) * sin(HD[i])


func ground_height(x: float, z: float) -> float:
	var base := _terrain_raw(x, z)
	var q := nearest(x, z)
	var h := base
	if q[0] >= 0:
		var i: int = q[0]
		var dd := clampf(lateral(i, x, z), -20.0, 20.0)
		var road := Y[i] + sin(BK[i]) * dd - 0.7
		h = lerpf(road, base, smoothstep(19.0, 70.0, q[1]))
	if water_level > -999.0:
		var r := sqrt(x * x + z * z)
		var R: float = def["R"]
		var sea := smoothstep(R * 1.35, R * 1.75, r) * smoothstep(-0.2, 0.5, x / (r + 1.0))
		var far := 1.0 if q[0] < 0 else smoothstep(35.0, 130.0, q[1])
		h = lerpf(h, water_level - 14.0, sea * far)
	return h


## Interpolated frame at arc distance s (any real) and lateral offset d.
## Returns Dictionary {pos, heading, k, grade, bank, fwd, right}
func frame(s: float, d: float) -> Dictionary:
	var f := fposmod(s, L) / ds
	var i := int(floor(f)) % N
	var j := (i + 1) % N
	var t := f - floor(f)
	var h := HD[i] + wrap_angle(HD[j] - HD[i]) * t
	var bk := lerpf(BK[i], BK[j], t)
	var right := Vector3(-cos(h), 0.0, sin(h))
	var p := Vector3(lerpf(X[i], X[j], t), lerpf(Y[i], Y[j], t), lerpf(Z[i], Z[j], t))
	p += right * d
	p.y += sin(bk) * d
	return {
		"pos": p, "heading": h, "k": lerpf(K[i], K[j], t), "grade": lerpf(GR[i], GR[j], t),
		"bank": bk, "fwd": Vector3(sin(h), 0.0, cos(h)), "right": right,
	}


func curv_at(s: float) -> float:
	var i := int(floor(fposmod(s, L) / ds)) % N
	return K[i]


## Track progress (arc distance within lap) of a world point, using a hint index for speed.
func project(p: Vector3, hint: int) -> Array:
	var best := hint
	var bd := 1e18
	for k in range(-40, 41):
		var i := (hint + k + N) % N
		var dx := X[i] - p.x
		var dz := Z[i] - p.z
		var d2 := dx * dx + dz * dz
		if d2 < bd:
			bd = d2; best = i
	if bd > 900.0:
		var q := nearest(p.x, p.z)
		if q[0] >= 0:
			best = q[0]
	# refine along segment
	var j := (best + 1) % N
	var seg := Vector2(X[j] - X[best], Z[j] - Z[best])
	var rel := Vector2(p.x - X[best], p.z - Z[best])
	var t := clampf(rel.dot(seg) / maxf(seg.length_squared(), 1e-6), -1.0, 1.0)
	var s := (best + t) * ds
	return [best, s, lateral(best, p.x, p.z)]
