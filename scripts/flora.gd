extends RefCounted
## Procedural vegetation & rocks (meshes with materials baked in, for MultiMesh use).

const Mats = preload("res://scripts/materials.gd")

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 4242


func _bark() -> StandardMaterial3D:
	var m := Mats.std(Color(0.32, 0.24, 0.17), 0.95)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.normal_enabled = true
	m.normal_texture = Mats.noise_tex(77, 0.15, 3, 128, true, 8.0)
	m.uv1_scale = Vector3(2.0, 3.0, 1.0)
	return m


func _leaf_mat(leaf_tex: Texture2D, col: Color, scale: float = 1.0) -> ShaderMaterial:
	var m := Mats.shader_mat(Mats.FOLIAGE_SHADER)
	m.set_shader_parameter("leaf_mask", leaf_tex)
	m.set_shader_parameter("leaf_col", col)
	m.set_shader_parameter("mask_scale", scale)
	m.set_shader_parameter("cutoff", 0.5)
	return m


# tapered cylinder between two points
func _cyl(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, segs: int, v0: float) -> void:
	var axis := (b - a).normalized()
	var ref := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var w := axis.cross(u).normalized()
	var length := a.distance_to(b)
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var d0 := u * cos(a0) + w * sin(a0)
		var d1 := u * cos(a1) + w * sin(a1)
		var p00 := a + d0 * r0
		var p01 := a + d1 * r0
		var p10 := b + d0 * r1
		var p11 := b + d1 * r1
		var u0 := float(k) / segs
		var u1 := float(k + 1) / segs
		_vert(st, p00, d0, Vector2(u0, v0))
		_vert(st, p10, d0, Vector2(u0, v0 + length))
		_vert(st, p01, d1, Vector2(u1, v0))
		_vert(st, p01, d1, Vector2(u1, v0))
		_vert(st, p10, d0, Vector2(u0, v0 + length))
		_vert(st, p11, d1, Vector2(u1, v0 + length))


func _vert(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2) -> void:
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(p)


# leaf card: quad centred at c, facing roughly `n`, normals bent outward from crown centre
func _card(st: SurfaceTool, c: Vector3, size: float, crown_c: Vector3, tilt: float = 0.0) -> void:
	var out := (c - crown_c).normalized()
	if out.length_squared() < 0.01:
		out = Vector3.UP
	var yaw := rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, rng.randf_range(-0.9, 0.9) + tilt)
	var ax := b.x * size * 0.5
	var ay := b.y * size * 0.5
	var n := (out * 0.75 + Vector3.UP * 0.35).normalized()
	var p := [c - ax - ay, c + ax - ay, c + ax + ay, c - ax + ay]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for idx in [0, 1, 2, 0, 2, 3]:
		_vert(st, p[idx], n, uv[idx])


func _commit_two(trunk: SurfaceTool, trunk_mat: Material, leaves: SurfaceTool, leaf_mat: Material) -> ArrayMesh:
	trunk.generate_tangents()
	var mesh := trunk.commit()
	mesh.surface_set_material(0, trunk_mat)
	if leaves:
		leaves.commit(mesh)
		mesh.surface_set_material(1, leaf_mat)
	return mesh


func broadleaf_tree(leaf_tex: Texture2D, col: Color) -> ArrayMesh:
	var t := SurfaceTool.new(); t.begin(Mesh.PRIMITIVE_TRIANGLES)
	var l := SurfaceTool.new(); l.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(rng.randf_range(-0.3, 0.3), 4.6, rng.randf_range(-0.3, 0.3))
	_cyl(t, Vector3.ZERO, top, 0.32, 0.2, 7, 0.0)
	var crown := top + Vector3(0, 2.4, 0)
	for k in 4:
		var dir := Vector3(cos(k * 1.7), 0.8, sin(k * 1.7)).normalized()
		_cyl(t, top - Vector3(0, 0.6, 0), top + dir * 2.4, 0.13, 0.05, 5, 0.0)
	_cyl(t, top, crown + Vector3(0, 1.0, 0), 0.18, 0.06, 6, 0.0)
	for k in 46:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 1), rng.randf_range(-1, 1))
		if d.length() > 1.0:
			d = d.normalized()
		var c := crown + Vector3(d.x * 3.2, d.y * 2.5, d.z * 3.2)
		_card(l, c, rng.randf_range(1.7, 2.6), crown)
	return _commit_two(t, _bark(), l, _leaf_mat(leaf_tex, col, 1.3))


func conifer_tree(leaf_tex: Texture2D) -> ArrayMesh:
	var t := SurfaceTool.new(); t.begin(Mesh.PRIMITIVE_TRIANGLES)
	var l := SurfaceTool.new(); l.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 13.0
	_cyl(t, Vector3.ZERO, Vector3(0, h, 0), 0.3, 0.05, 7, 0.0)
	var layers := 9
	for i in layers:
		var y := 2.2 + i * (h - 2.6) / layers
		var rad := (1.0 - float(i) / layers) * 3.4 + 0.5
		var n := int(5 + rad * 2.0)
		for k in n:
			var a := TAU * k / n + i * 0.7
			var c := Vector3(cos(a) * rad * 0.55, y, sin(a) * rad * 0.55)
			_card(l, c, rad * 1.05 + 0.6, Vector3(0, y + 1.5, 0), 0.5)
	return _commit_two(t, _bark(), l, _leaf_mat(leaf_tex, Color(0.12, 0.22, 0.12), 1.8))


func palm_tree(leaf_tex: Texture2D) -> ArrayMesh:
	var t := SurfaceTool.new(); t.begin(Mesh.PRIMITIVE_TRIANGLES)
	var l := SurfaceTool.new(); l.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := Vector3.ZERO
	var lean := Vector3(rng.randf_range(0.3, 0.7), 0, rng.randf_range(-0.2, 0.2))
	var segs := 6
	for k in segs:
		var q := p + Vector3(0, 1.6, 0) + lean * (0.12 * k)
		_cyl(t, p, q, 0.24 - k * 0.015, 0.23 - (k + 1) * 0.015, 7, k * 1.6)
		p = q
	var crown := p
	var fronds := 10
	for k in fronds:
		var a := TAU * k / fronds + rng.randf() * 0.3
		var dir := Vector3(cos(a), 0, sin(a))
		var side := dir.cross(Vector3.UP).normalized()
		var p0 := crown
		var p1 := crown + dir * 2.4 + Vector3(0, 0.5, 0)
		var p2 := crown + dir * 4.6 + Vector3(0, -0.9, 0)
		var w := 0.8
		for seg in [[p0, p1, 0.0, 0.5], [p1, p2, 0.5, 1.0]]:
			var a0: Vector3 = seg[0]
			var a1: Vector3 = seg[1]
			var v0: float = seg[2]
			var v1: float = seg[3]
			var n := (Vector3.UP * 0.8 + dir * 0.2).normalized()
			var pts := [a0 - side * w, a0 + side * w, a1 + side * w, a1 - side * w]
			var uvs := [Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)]
			for idx in [0, 1, 2, 0, 2, 3]:
				_vert(l, pts[idx], n, uvs[idx])
	var m := Mats.shader_mat(Mats.FOLIAGE_SHADER)
	m.set_shader_parameter("leaf_mask", leaf_tex)
	m.set_shader_parameter("leaf_col", Color(0.22, 0.36, 0.12))
	m.set_shader_parameter("mask_scale", 3.0)
	m.set_shader_parameter("cutoff", 0.38)
	var bark := Mats.std(Color(0.45, 0.36, 0.26), 0.9)
	bark.normal_enabled = true
	bark.normal_texture = Mats.noise_tex(78, 0.3, 2, 128, true, 10.0)
	return _commit_two(t, bark, l, m)


func bush(leaf_tex: Texture2D, col: Color) -> ArrayMesh:
	var t := SurfaceTool.new(); t.begin(Mesh.PRIMITIVE_TRIANGLES)
	var l := SurfaceTool.new(); l.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cyl(t, Vector3.ZERO, Vector3(0, 0.6, 0), 0.08, 0.04, 5, 0.0)
	var c0 := Vector3(0, 0.8, 0)
	for k in 18:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.8), rng.randf_range(-1, 1)).limit_length(1.0)
		_card(l, c0 + d * Vector3(1.3, 0.7, 1.3), rng.randf_range(1.0, 1.5), c0)
	return _commit_two(t, _bark(), l, _leaf_mat(leaf_tex, col, 1.6))


func cactus() -> ArrayMesh:
	var t := SurfaceTool.new(); t.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cyl(t, Vector3.ZERO, Vector3(0, 5.0, 0), 0.38, 0.33, 12, 0.0)
	_cyl(t, Vector3(0, 2.0, 0), Vector3(0.9, 2.3, 0), 0.24, 0.24, 10, 0.0)
	_cyl(t, Vector3(0.9, 2.2, 0), Vector3(1.0, 3.8, 0), 0.24, 0.2, 10, 0.0)
	_cyl(t, Vector3(0, 2.8, 0), Vector3(-0.75, 3.0, 0.1), 0.21, 0.21, 10, 0.0)
	_cyl(t, Vector3(-0.75, 2.9, 0.1), Vector3(-0.85, 4.2, 0.1), 0.21, 0.17, 10, 0.0)
	var m := Mats.std(Color(0.26, 0.38, 0.18), 0.7)
	m.normal_enabled = true
	var ridges := Mats.noise_tex(91, 0.5, 1, 64, true, 6.0)
	m.normal_texture = ridges
	m.uv1_scale = Vector3(6.0, 0.4, 1.0)
	t.generate_tangents()
	var mesh := t.commit()
	mesh.surface_set_material(0, m)
	return mesh


func rock(detail: Texture2D, col: Color) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 1.6
	sm.height = 2.4
	sm.radial_segments = 14
	sm.rings = 8
	var arrays := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n := FastNoiseLite.new()
	n.frequency = 0.6
	n.seed = 7
	for i in verts.size():
		var v := verts[i]
		var k := 1.0 + 0.35 * n.get_noise_3dv(v)
		verts[i] = Vector3(v.x * k, maxf(v.y * k, -0.4), v.z * k)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()
	var m := Mats.std(col, 0.9)
	m.albedo_texture = detail
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.4, 0.4, 0.4)
	mesh.surface_set_material(0, m)
	return mesh


func grass_clump(root_c: Color, tip_c: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 9:
		var a := rng.randf() * TAU
		var off := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x) * 0.045
		var hgt := rng.randf_range(0.28, 0.6)
		var bend := dir * rng.randf_range(0.05, 0.22)
		var p0 := off - side
		var p1 := off + side
		var pm0 := off - side * 0.6 + Vector3(0, hgt * 0.55, 0) + bend * 0.4
		var pm1 := off + side * 0.6 + Vector3(0, hgt * 0.55, 0) + bend * 0.4
		var tip := off + Vector3(0, hgt, 0) + bend
		var n := Vector3.UP
		_vert(st, p0, n, Vector2(0, 0)); _vert(st, p1, n, Vector2(1, 0)); _vert(st, pm1, n, Vector2(1, 0.55))
		_vert(st, p0, n, Vector2(0, 0)); _vert(st, pm1, n, Vector2(1, 0.55)); _vert(st, pm0, n, Vector2(0, 0.55))
		_vert(st, pm0, n, Vector2(0, 0.55)); _vert(st, pm1, n, Vector2(1, 0.55)); _vert(st, tip, n, Vector2(0.5, 1.0))
	var mesh := st.commit()
	var m := Mats.shader_mat(Mats.GRASS_SHADER)
	m.set_shader_parameter("root_col", root_c)
	m.set_shader_parameter("tip_col", tip_c)
	mesh.surface_set_material(0, m)
	return mesh
