extends Node3D
## Highway traffic: procedural cars, vans, trucks and buses on lanes of the track.
## Cars are kinematic (AnimatableBody3D) so the bike physically collides with them.
## Same-direction cars follow each other and brake for the rider; oncoming cars use the left lanes.

const TD = preload("res://scripts/track_data.gd")
const Mats = preload("res://scripts/materials.gd")

signal near_miss(car_type, oncoming)

# [length, width, height, kind]
const TYPES := {
	"sedan": [4.7, 1.84, 1.45], "hatch": [4.1, 1.78, 1.5], "suv": [4.8, 1.95, 1.78],
	"pickup": [5.3, 1.95, 1.85], "van": [5.2, 2.0, 2.25], "truck": [8.6, 2.5, 3.4], "bus": [12.0, 2.55, 3.25],
}
const TYPE_WEIGHTS := [["sedan", 0.3], ["hatch", 0.2], ["suv", 0.18], ["pickup", 0.08], ["van", 0.1], ["truck", 0.09], ["bus", 0.05]]
const PAINTS := [Color(0.92, 0.92, 0.93), Color(0.72, 0.73, 0.75), Color(0.05, 0.05, 0.06), Color(0.55, 0.06, 0.06),
	Color(0.08, 0.16, 0.42), Color(0.33, 0.35, 0.37), Color(0.6, 0.6, 0.58), Color(0.12, 0.25, 0.18), Color(0.85, 0.85, 0.82)]

var track: TD
var two_way := true
var lanes_same: Array = []      # lateral offsets of lanes in the riding direction
var lanes_onc: Array = []       # oncoming lanes
var cars: Array = []            # Array of Dictionaries
var rng := RandomNumberGenerator.new()
var count := 22
static var _meshes := {}
static var _mats := {}


func setup(tr: TD, two_way_: bool, n: int) -> void:
	track = tr
	two_way = two_way_
	count = n
	rng.randomize()
	if two_way:
		lanes_same = [1.75, 5.25]
		lanes_onc = [-1.75, -5.25]
	else:
		lanes_same = [-5.25, -1.75, 1.75, 5.25]
		lanes_onc = []


func clear() -> void:
	for c in cars:
		var n: Node = c["node"]
		if is_instance_valid(n):
			n.queue_free()
	cars.clear()


## Fill the road ahead of the rider (call once at the start of a run).
func populate(player_s: float) -> void:
	clear()
	for i in count:
		var c := _new_car()
		cars.append(c)
		_respawn(c, player_s, true)


# ------------------------------------------------------------------ simulation
func update(dt: float, player_s: float, player_lat: float, player_v: float) -> void:
	for c in cars:
		var oncoming: bool = c["onc"]
		var s: float = c["s"]
		var lane: float = c["lane"]
		var want: float = c["v_des"]
		# follow the vehicle ahead in the same lane (and the rider)
		var gap_min := 1e9
		var lead_v := want
		for o in cars:
			if o == c or o["onc"] != oncoming or absf(float(o["lane"]) - lane) > 1.0:
				continue
			var gap: float = (float(o["s"]) - s) * (-1.0 if oncoming else 1.0)
			gap -= (float(o["len"]) + float(c["len"])) * 0.5
			if gap > 0.0 and gap < gap_min:
				gap_min = gap
				lead_v = o["v"]
		if not oncoming:
			var pg := player_s - s - float(c["len"]) * 0.5 - 1.2
			if pg > 0.0 and pg < gap_min and absf(player_lat - lane) < 1.6:
				gap_min = pg
				lead_v = player_v
		var v: float = c["v"]
		var safe := 8.0 + v * 1.1
		if gap_min < safe:
			want = minf(want, lead_v - (safe - gap_min) * 0.25)
		var acc := clampf((want - v) * 0.8, -7.0, 2.2)
		v = maxf(0.0, v + acc * dt)
		c["v"] = v
		s += v * dt * (-1.0 if oncoming else 1.0)
		c["s"] = s
		# smooth lane changes (rare, same-direction only)
		if not oncoming and rng.randf() < dt * 0.02 and lanes_same.size() > 1:
			var target: float = lanes_same[rng.randi() % lanes_same.size()]
			if _lane_free(target, s, false):
				c["lane"] = target
		c["d"] = lerpf(float(c["d"]), float(c["lane"]), clampf(dt * 0.8, 0.0, 1.0))
		_place(c)
		# near miss: rider passes close at > 100 km/h
		var rel := s - player_s
		var side := signf(rel)
		if side != float(c["side"]) and float(c["side"]) != 0.0 and absf(rel) < 6.0:
			var lat_gap := absf(float(c["d"]) - player_lat) - float(c["wid"]) * 0.5
			if lat_gap < 1.4 and lat_gap > -0.2 and player_v > 27.8:
				near_miss.emit(c["type"], oncoming)
		c["side"] = side
		# recycle
		var behind := player_s - s
		if behind > 260.0 or (oncoming and behind > 120.0) or s - player_s > 1500.0:
			_respawn(c, player_s, false)


func _lane_free(lane: float, s: float, oncoming: bool) -> bool:
	for o in cars:
		if o["onc"] == oncoming and absf(float(o["lane"]) - lane) < 1.0 and absf(float(o["s"]) - s) < 28.0:
			return false
	return true


func _respawn(c: Dictionary, player_s: float, initial: bool) -> void:
	var oncoming := two_way and rng.randf() < 0.42
	var lanes: Array = lanes_onc if oncoming else lanes_same
	for _try in 12:
		var lane: float = lanes[rng.randi() % lanes.size()]
		var s := 0.0
		if initial:
			s = player_s + rng.randf_range(70.0, 1100.0)
		elif oncoming:
			s = player_s + rng.randf_range(700.0, 1200.0)
		else:
			s = player_s + rng.randf_range(450.0, 1100.0)
		if _lane_free(lane, s, oncoming):
			c["onc"] = oncoming
			c["lane"] = lane
			c["d"] = lane
			c["s"] = s
			var kind: String = c["type"]
			var heavy := kind == "truck" or kind == "bus"
			c["v_des"] = rng.randf_range(15.0, 22.0) if heavy else rng.randf_range(19.0, 30.0)
			c["v"] = c["v_des"]
			c["side"] = 0.0
			_place(c)
			return
	# road too busy: park far ahead (will retry next recycle)
	c["s"] = player_s + 2000.0


func _place(c: Dictionary) -> void:
	var f: Dictionary = track.frame(float(c["s"]), float(c["d"]))
	var fwd: Vector3 = f["fwd"]
	if c["onc"]:
		fwd = -fwd
	var up := Vector3.UP
	var p: Vector3 = f["pos"]
	var body: AnimatableBody3D = c["node"]
	body.global_transform = Transform3D(Basis.looking_at(fwd, up), p)
	body.set_meta("vel", fwd * float(c["v"]))


# ------------------------------------------------------------------ car construction
func _new_car() -> Dictionary:
	var pick := rng.randf()
	var kind := "sedan"
	var acc := 0.0
	for tw in TYPE_WEIGHTS:
		acc += float(tw[1])
		if pick <= acc:
			kind = tw[0]
			break
	var dims: Array = TYPES[kind]
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	body.collision_layer = 16
	body.collision_mask = 0
	body.name = "Car"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(float(dims[1]), float(dims[2]) * 0.9, float(dims[0]))
	cs.shape = bs
	cs.position = Vector3(0, float(dims[2]) * 0.5, 0)
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = car_mesh(kind)
	var paint := _paint(PAINTS[rng.randi() % PAINTS.size()]) if kind != "bus" else _paint(Color(0.85, 0.62, 0.08))
	mi.set_surface_override_material(0, paint)
	body.add_child(mi)
	add_child(body)
	return {"node": body, "type": kind, "len": dims[0], "wid": dims[1], "s": 0.0, "d": 0.0, "lane": 0.0,
		"v": 0.0, "v_des": 25.0, "onc": false, "side": 0.0}


static func _paint(col: Color) -> StandardMaterial3D:
	var key := col.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.55
	m.roughness = 0.32
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.05
	_mats[key] = m
	return m


static func _mat(name_: String) -> StandardMaterial3D:
	if _mats.has(name_):
		return _mats[name_]
	var m := StandardMaterial3D.new()
	match name_:
		"glass":
			m.albedo_color = Color(0.04, 0.05, 0.07)
			m.metallic = 0.9
			m.roughness = 0.05
		"trim":
			m.albedo_color = Color(0.03, 0.03, 0.035)
			m.roughness = 0.6
		"tyre":
			m.albedo_color = Color(0.02, 0.02, 0.02)
			m.roughness = 0.9
		"rim":
			m.albedo_color = Color(0.7, 0.71, 0.73)
			m.metallic = 1.0
			m.roughness = 0.25
		"head":
			m.albedo_color = Color(1, 1, 1)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.97, 0.9)
			m.emission_energy_multiplier = 2.5
		"tail":
			m.albedo_color = Color(0.4, 0.0, 0.0)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.05, 0.02)
			m.emission_energy_multiplier = 2.0
		"plate":
			m.albedo_color = Color(0.92, 0.92, 0.88)
			m.roughness = 0.5
		"cargo":
			m.albedo_color = Color(0.88, 0.88, 0.86)
			m.roughness = 0.55
	_mats[name_] = m
	return m


## Emit one triangle facing `out` (Godot treats clockwise-from-outside as the front face).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
	var g := (b - a).cross(c - a)
	if g.dot(out) > 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_normal(out)
		st.add_vertex(v)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, centre: Vector3) -> void:
	var n := (b - a).cross(d - a)
	if n.length_squared() < 1e-10:
		n = (c - b).cross(a - b)
	n = n.normalized()
	if n.dot((a + b + c + d) * 0.25 - centre) < 0.0:
		n = -n
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)


## Box with independent bottom and top rectangles (gives sloped windscreens / tapered roofs).
## Rectangles are [x_half, z_front, z_back] at heights y0 / y1. Forward is -Z.
static func _hexa(st: SurfaceTool, b: Array, y0: float, t: Array, y1: float) -> void:
	var p := [
		Vector3(-b[0], y0, b[1]), Vector3(b[0], y0, b[1]), Vector3(b[0], y0, b[2]), Vector3(-b[0], y0, b[2]),
		Vector3(-t[0], y1, t[1]), Vector3(t[0], y1, t[1]), Vector3(t[0], y1, t[2]), Vector3(-t[0], y1, t[2]),
	]
	_faces(st, p)


static func _offset_box(st: SurfaceTool, c: Vector3, sz: Vector3) -> void:
	var h := sz * 0.5
	var p := [
		Vector3(c.x - h.x, c.y - h.y, c.z - h.z), Vector3(c.x + h.x, c.y - h.y, c.z - h.z),
		Vector3(c.x + h.x, c.y - h.y, c.z + h.z), Vector3(c.x - h.x, c.y - h.y, c.z + h.z),
		Vector3(c.x - h.x, c.y + h.y, c.z - h.z), Vector3(c.x + h.x, c.y + h.y, c.z - h.z),
		Vector3(c.x + h.x, c.y + h.y, c.z + h.z), Vector3(c.x - h.x, c.y + h.y, c.z + h.z),
	]
	_faces(st, p)


static func _faces(st: SurfaceTool, p: Array) -> void:
	var centre := Vector3.ZERO
	for v in p:
		centre += v
	centre /= 8.0
	for fc in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7], [3, 2, 1, 0]]:
		_quad(st, p[fc[0]], p[fc[1]], p[fc[2]], p[fc[3]], centre)


static func _wheel(st: SurfaceTool, c: Vector3, r: float, w: float) -> void:
	var segs := 14
	var o := Vector3(w * 0.5, 0, 0)
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var p0 := Vector3(0, sin(a0) * r, cos(a0) * r)
		var p1 := Vector3(0, sin(a1) * r, cos(a1) * r)
		var n := Vector3(0, sin((a0 + a1) * 0.5), cos((a0 + a1) * 0.5))
		_tri(st, c + p0 - o, c + p1 - o, c + p1 + o, n)
		_tri(st, c + p0 - o, c + p1 + o, c + p0 + o, n)
		for sx in [-1.0, 1.0]:
			var off := Vector3(sx * w * 0.5, 0, 0)
			_tri(st, c + off, c + p0 + off, c + p1 + off, Vector3(sx, 0, 0))


static func car_mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var dims: Array = TYPES[kind]
	var L: float = dims[0]
	var W: float = dims[1]
	var H: float = dims[2]
	var hw := W * 0.5
	var hl := L * 0.5
	var surfaces := {}
	for k in ["paint", "glass", "trim", "tyre", "rim", "head", "tail", "plate", "cargo"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[k] = st
	var P: SurfaceTool = surfaces["paint"]
	var G: SurfaceTool = surfaces["glass"]
	var T: SurfaceTool = surfaces["trim"]
	var wr := 0.34 if L < 6.0 else 0.5
	var clear := 0.18
	if kind == "truck":
		var cab_l := 2.3
		_hexa(P, [hw, -hl, -hl + cab_l], 0.55, [hw - 0.08, -hl + 0.25, -hl + cab_l], H * 0.82)
		_hexa(G, [hw - 0.06, -hl + 0.06, -hl + 0.9], H * 0.5, [hw - 0.1, -hl + 0.3, -hl + 1.0], H * 0.78)
		_offset_box(surfaces["cargo"], Vector3(0, H * 0.55, -hl + cab_l + (L - cab_l) * 0.5 + 0.1), Vector3(W, H * 0.9, L - cab_l - 0.2))
		_offset_box(T, Vector3(0, 0.55, 0), Vector3(W * 0.9, 0.3, L * 0.98))
	elif kind == "bus":
		_hexa(P, [hw, -hl, hl], 0.45, [hw, -hl + 0.15, hl], H)
		_offset_box(G, Vector3(0, H * 0.66, 0.2), Vector3(W + 0.02, H * 0.3, L * 0.86))
		_offset_box(G, Vector3(0, H * 0.55, -hl - 0.01), Vector3(W * 0.88, H * 0.55, 0.04))
	elif kind == "van":
		_hexa(P, [hw, -hl, hl], clear + 0.2, [hw - 0.05, -hl + 0.15, hl], H * 0.55)
		_hexa(P, [hw - 0.05, -hl + 0.15, hl], H * 0.55, [hw - 0.12, -hl + 1.1, hl - 0.05], H)
		_hexa(G, [hw - 0.03, -hl + 0.2, -hl + 1.4], H * 0.56, [hw - 0.1, -hl + 1.05, -hl + 1.5], H * 0.92)
		_offset_box(G, Vector3(0, H * 0.75, hl + 0.005), Vector3(W * 0.7, H * 0.28, 0.02))
	else:
		# body tub
		var belt := H * (0.52 if kind != "suv" else 0.55)
		_hexa(P, [hw, -hl + 0.15, hl - 0.1], clear + 0.12, [hw, -hl, hl], belt)
		var roof_f := -hl + L * (0.36 if kind != "hatch" else 0.3)
		var roof_b := hl - L * (0.2 if kind == "sedan" else 0.06)
		if kind == "pickup":
			roof_b = -hl + L * 0.58
			_offset_box(T, Vector3(0, belt + 0.05, hl - L * 0.2), Vector3(W * 0.92, 0.08, L * 0.38))
		var cab_f := roof_f - L * 0.13
		var cab_b := roof_b + (L * 0.1 if kind == "sedan" else 0.04)
		# glasshouse (windows) with painted roof on top
		_hexa(G, [hw - 0.06, cab_f, cab_b], belt, [hw - 0.18, roof_f, roof_b], H - 0.06)
		_hexa(P, [hw - 0.17, roof_f + 0.04, roof_b - 0.04], H - 0.07, [hw - 0.2, roof_f + 0.08, roof_b - 0.08], H)
		# A/B pillars hint
		for sx in [-1.0, 1.0]:
			_offset_box(P, Vector3(sx * (hw - 0.12), (belt + H) * 0.5, (cab_f + roof_f) * 0.5 + 0.05), Vector3(0.07, H - belt, 0.07))
	# bumpers, grille, lights, plate
	_offset_box(T, Vector3(0, clear + 0.22, -hl - 0.03), Vector3(W * 0.96, 0.22, 0.12))
	_offset_box(T, Vector3(0, clear + 0.22, hl + 0.03), Vector3(W * 0.96, 0.22, 0.12))
	var ly := clear + 0.48 if L < 6.0 else 0.85
	for sx in [-1.0, 1.0]:
		_offset_box(surfaces["head"], Vector3(sx * (hw - 0.3), ly, -hl - 0.02), Vector3(0.38, 0.12, 0.06))
		_offset_box(surfaces["tail"], Vector3(sx * (hw - 0.2), ly + 0.05, hl + 0.02), Vector3(0.3, 0.16, 0.06))
		_offset_box(T, Vector3(sx * (hw + 0.07), (clear + 0.12 + ly) * 0.5 + 0.35, -hl + L * 0.33), Vector3(0.12, 0.08, 0.16))  # mirror
	_offset_box(surfaces["plate"], Vector3(0, clear + 0.32, hl + 0.1), Vector3(0.52, 0.12, 0.02))
	_offset_box(surfaces["plate"], Vector3(0, clear + 0.32, -hl - 0.1), Vector3(0.52, 0.12, 0.02))
	# wheels
	var axles := [-hl + L * 0.18, hl - L * 0.18]
	if kind == "truck":
		axles = [-hl + 1.3, hl - 2.4, hl - 1.2]
	elif kind == "bus":
		axles = [-hl + 2.4, hl - 3.0]
	for z in axles:
		for sx in [-1.0, 1.0]:
			_wheel(surfaces["tyre"], Vector3(sx * (hw - 0.14), wr, z), wr, 0.24)
			_wheel(surfaces["rim"], Vector3(sx * (hw - 0.01), wr, z), wr * 0.6, 0.02)
	var mesh := ArrayMesh.new()
	var order := ["paint", "glass", "trim", "tyre", "rim", "head", "tail", "plate", "cargo"]
	for k in order:
		var st: SurfaceTool = surfaces[k]
		var arr := st.commit_to_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			# keep surface indices stable: add a degenerate triangle
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for _i in 3:
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3.ZERO)
			arr = st.commit_to_arrays()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mat(k) if k != "paint" else _paint(Color(0.7, 0.7, 0.7)))
	_meshes[kind] = mesh
	return mesh
