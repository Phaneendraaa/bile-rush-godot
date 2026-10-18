extends RefCounted
## Grid mesh builder: rows x cols vertices -> ArrayMesh with smooth normals, tangents, UVs.
## Winding is chosen so faces look toward `up_hint` (Godot treats clockwise as front-facing).

static func grid_mesh(verts: PackedVector3Array, uvs: PackedVector2Array, rows: int, cols: int, up_hint: Vector3, colors: PackedColorArray = PackedColorArray()) -> ArrayMesh:
	var idx := PackedInt32Array()
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for r in rows - 1:
		for c in cols - 1:
			var a := r * cols + c
			var b := a + 1
			var d := a + cols
			var e := d + 1
			_tri(idx, normals, verts, a, d, b, up_hint)
			_tri(idx, normals, verts, b, d, e, up_hint)
	for i in normals.size():
		var n := normals[i]
		normals[i] = n.normalized() if n.length_squared() > 1e-12 else up_hint
	var tangents := PackedFloat32Array()
	tangents.resize(verts.size() * 4)
	for r in rows:
		for c in cols:
			var i := r * cols + c
			var t: Vector3
			if c < cols - 1:
				t = verts[i + 1] - verts[i]
			else:
				t = verts[i] - verts[i - 1]
			var n2 := normals[i]
			t = (t - n2 * n2.dot(t)).normalized()
			tangents[i * 4] = t.x
			tangents[i * 4 + 1] = t.y
			tangents[i * 4 + 2] = t.z
			tangents[i * 4 + 3] = 1.0
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if colors.size() == verts.size():
		arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _tri(idx: PackedInt32Array, normals: PackedVector3Array, v: PackedVector3Array, a: int, b: int, c: int, up: Vector3) -> void:
	var n := (v[b] - v[a]).cross(v[c] - v[a])
	if n.dot(up) > 0.0:
		# clockwise (front) when seen from the up side
		idx.append(a); idx.append(c); idx.append(b)
	else:
		idx.append(a); idx.append(b); idx.append(c)
		n = -n
	# n now points toward `up`
	if n.dot(up) < 0.0:
		n = -n
	normals[a] += n; normals[b] += n; normals[c] += n


## Triangle soup (for ConcavePolygonShape3D) from the same grid.
static func grid_faces(verts: PackedVector3Array, rows: int, cols: int, step_r: int = 1) -> PackedVector3Array:
	var f := PackedVector3Array()
	var r := 0
	while r < rows - 1:
		var r2 := mini(r + step_r, rows - 1)
		for c in cols - 1:
			var a := verts[r * cols + c]
			var b := verts[r * cols + c + 1]
			var d := verts[r2 * cols + c]
			var e := verts[r2 * cols + c + 1]
			f.append(a); f.append(b); f.append(d)
			f.append(b); f.append(e); f.append(d)
		r = r2
	return f


## Merge a list of [Mesh, Transform3D] (single surface primitive meshes) into one ArrayMesh surface.
static func merge(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in parts:
		var m: Mesh = p[0]
		var xf: Transform3D = p[1]
		st.append_from(m, 0, xf)
	st.generate_tangents()
	return st.commit()
