extends RefCounted
## Builds the whole 3D world for a TrackData: lighting, sky, road, terrain, collisions and scenery.

const Mats = preload("res://scripts/materials.gd")
const MU = preload("res://scripts/mesh_util.gd")
const Flora = preload("res://scripts/flora.gd")
const TD = preload("res://scripts/track_data.gd")

var tr: TD
var root: Node3D
var quality: Dictionary
var rng := RandomNumberGenerator.new()
var tex := {}
var curb_mask := PackedByteArray()   # per sample: 1 if curbs present
var env: Environment
var sun: DirectionalLight3D
var cx := 0.0
var cz := 0.0
var size := 0.0

const PALETTES := {
	"grass": {"a": Color(0.20, 0.33, 0.09), "b": Color(0.30, 0.40, 0.12), "dirt": Color(0.36, 0.29, 0.2), "rock": Color(0.42, 0.4, 0.37), "sand": Color(0.7, 0.62, 0.45), "rock_slope": 0.62},
	"coast": {"a": Color(0.36, 0.4, 0.16), "b": Color(0.52, 0.48, 0.28), "dirt": Color(0.58, 0.5, 0.36), "rock": Color(0.5, 0.45, 0.4), "sand": Color(0.82, 0.74, 0.55), "rock_slope": 0.6},
	"snow": {"a": Color(0.86, 0.88, 0.9), "b": Color(0.78, 0.8, 0.84), "dirt": Color(0.42, 0.4, 0.38), "rock": Color(0.36, 0.36, 0.38), "sand": Color(0.8, 0.8, 0.82), "rock_slope": 0.5},
	"desert": {"a": Color(0.72, 0.46, 0.27), "b": Color(0.8, 0.56, 0.34), "dirt": Color(0.62, 0.36, 0.2), "rock": Color(0.56, 0.3, 0.18), "sand": Color(0.86, 0.68, 0.45), "rock_slope": 0.55},
}
const TIMES := {
	"noon": {"sun_dir": Vector3(-0.35, -0.82, -0.45), "sun_col": Color(1.0, 0.96, 0.9), "sun_e": 2.4,
		"zenith": Color(0.13, 0.32, 0.68), "horizon": Color(0.62, 0.76, 0.92), "ground": Color(0.35, 0.38, 0.4),
		"amb": 0.55, "fog": Color(0.66, 0.77, 0.9), "cloud": 0.5, "cloud_b": 1.0, "exposure": 1.0},
	"sunset": {"sun_dir": Vector3(0.7, -0.16, 0.66), "sun_col": Color(1.0, 0.62, 0.35), "sun_e": 2.6,
		"zenith": Color(0.16, 0.2, 0.45), "horizon": Color(1.0, 0.56, 0.32), "ground": Color(0.3, 0.22, 0.2),
		"amb": 0.45, "fog": Color(0.95, 0.62, 0.45), "cloud": 0.45, "cloud_b": 0.9, "exposure": 1.05},
	"overcast": {"sun_dir": Vector3(-0.3, -0.7, -0.5), "sun_col": Color(0.92, 0.94, 1.0), "sun_e": 1.1,
		"zenith": Color(0.55, 0.6, 0.66), "horizon": Color(0.82, 0.84, 0.86), "ground": Color(0.6, 0.62, 0.64),
		"amb": 0.95, "fog": Color(0.8, 0.82, 0.85), "cloud": 0.2, "cloud_b": 0.95, "exposure": 1.05},
	"afternoon": {"sun_dir": Vector3(-0.55, -0.58, 0.55), "sun_col": Color(1.0, 0.9, 0.76), "sun_e": 2.7,
		"zenith": Color(0.18, 0.42, 0.75), "horizon": Color(0.86, 0.8, 0.7), "ground": Color(0.5, 0.38, 0.28),
		"amb": 0.5, "fog": Color(0.88, 0.8, 0.7), "cloud": 0.62, "cloud_b": 1.05, "exposure": 0.95},
}


func build(track, parent: Node3D, q: Dictionary) -> Node3D:
	tr = track
	quality = q
	rng.seed = int(tr.def["seed"]) * 977
	root = Node3D.new()
	root.name = "World"
	parent.add_child(root)
	_textures()
	_curb_mask()
	_environment()
	_road()
	_terrain()
	_barriers()
	_collision()
	_scenery()
	_props()
	if tr.def.get("highway", false):
		_highway_props()
	return root


func _textures() -> void:
	tex["grain"] = Mats.noise_tex(3, 0.09, 4, 512)
	tex["grain_n"] = Mats.noise_tex(5, 0.12, 3, 512, true, 5.0)
	tex["macro"] = Mats.noise_tex(9, 0.012, 5, 256)
	tex["detail"] = Mats.noise_tex(13, 0.035, 5, 512)
	tex["detail_n"] = Mats.noise_tex(17, 0.05, 4, 512, true, 7.0)
	tex["cloud"] = Mats.noise_tex(21, 0.006, 6, 512)
	tex["leaf"] = Mats.noise_tex(31, 0.09, 3, 256, false, 1.0, null, true)


func _curb_mask() -> void:
	curb_mask.resize(tr.N)
	for i in tr.N:
		var m := 0.0
		for k in range(-12, 13, 3):
			m = maxf(m, absf(tr.K[(i + k + tr.N) % tr.N]))
		curb_mask[i] = 1 if m > 1.0 / 420.0 else 0


func has_curb(s: float) -> bool:
	var i := int(floorf(fposmod(s, tr.L) / tr.ds)) % tr.N
	return curb_mask[i] == 1


# ---------------------------------------------------------------- environment
func _environment() -> void:
	var t: Dictionary = TIMES[tr.def["time"]]
	var sky_mat := Mats.shader_mat(Mats.SKY_SHADER)
	sky_mat.set_shader_parameter("zenith", t["zenith"])
	sky_mat.set_shader_parameter("horizon", t["horizon"])
	sky_mat.set_shader_parameter("ground_col", t["ground"])
	sky_mat.set_shader_parameter("sun_tint", t["sun_col"])
	sky_mat.set_shader_parameter("cloud_cover", t["cloud"])
	sky_mat.set_shader_parameter("cloud_bright", t["cloud_b"])
	sky_mat.set_shader_parameter("cloud_noise", tex["cloud"])
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = t["amb"]
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = t["exposure"]
	env.glow_enabled = quality.get("glow", true)
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_light_color = t["fog"]
	env.fog_density = 0.00055
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.45
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	var sd: Vector3 = t["sun_dir"]
	sun.basis = Basis.looking_at(sd.normalized(), Vector3.UP if absf(sd.normalized().y) < 0.99 else Vector3.FORWARD)
	sun.light_color = t["sun_col"]
	sun.light_energy = t["sun_e"]
	sun.shadow_enabled = quality.get("shadows", true)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = quality.get("shadow_dist", 90.0)
	sun.directional_shadow_split_1 = 0.18
	sun.shadow_blur = 1.2
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	root.add_child(sun)


# ---------------------------------------------------------------- road surfaces
func _ribbon(laterals: Array, lifts: Array, step: int, uv_mode: int) -> Array:
	# laterals: lateral offsets across (left -> right); returns [verts, uvs, rows, cols]
	var rows := int(ceilf(float(tr.N) / step)) + 1
	var cols := laterals.size()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(rows * cols)
	uvs.resize(rows * cols)
	for r in rows:
		var i := mini(r * step, tr.N)
		var s := i * tr.ds
		var ii := i % tr.N
		var h := tr.HD[ii]
		var right := Vector3(-cos(h), 0.0, sin(h))
		var base := Vector3(tr.X[ii], tr.Y[ii], tr.Z[ii])
		var bk := sin(tr.BK[ii])
		for c in cols:
			var d: float = laterals[c]
			var p := base + right * d
			p.y += bk * d + float(lifts[c])
			verts[r * cols + c] = p
			uvs[r * cols + c] = Vector2(d, s) if uv_mode == 0 else Vector2(float(c) / (cols - 1), s)
	return [verts, uvs, rows, cols]


func _road() -> void:
	var H: float = TD.ROAD_HALF
	var rb := _ribbon([-H, -H * 0.5, 0.0, H * 0.5, H], [0.0, 0.0, 0.0, 0.0, 0.0], 1, 0)
	var mesh := MU.grid_mesh(rb[0], rb[1], rb[2], rb[3], Vector3.UP)
	var mat := Mats.shader_mat(Mats.ROAD_SHADER)
	mat.set_shader_parameter("grain", tex["grain"])
	mat.set_shader_parameter("grain_n", tex["grain_n"])
	mat.set_shader_parameter("macro", tex["macro"])
	mat.set_shader_parameter("road_half", H)
	mat.set_shader_parameter("track_len", tr.L)
	mat.set_shader_parameter("highway", 1.0 if tr.def.get("highway", false) else 0.0)
	mat.set_shader_parameter("two_way", 1.0 if tr.def.get("two_way", true) else 0.0)
	if tr.def["biome"] == "desert":
		mat.set_shader_parameter("tint", Color(1.06, 1.0, 0.94))
	elif tr.def["biome"] == "snow":
		mat.set_shader_parameter("tint", Color(0.92, 0.95, 1.0))
		mat.set_shader_parameter("wet", 0.6)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.name = "Road"
	root.add_child(mi)

	# curbs: separate pieces where the track bends
	var curb_mat := Mats.shader_mat(Mats.CURB_SHADER)
	curb_mat.set_shader_parameter("grain", tex["grain"])
	for side in [-1.0, 1.0]:
		var start := -1
		for i in tr.N + 1:
			var on := i < tr.N and curb_mask[i] == 1
			if on and start < 0:
				start = i
			elif not on and start >= 0:
				_curb_piece(start, i, side, curb_mat)
				start = -1

	# verge (grass / sand) from curb to beyond the barrier, plus skirt down to terrain
	var pal: Dictionary = PALETTES[tr.def["biome"]]
	var tmat := _terrain_material(pal)
	var R: float = TD.RUNOFF
	for side in [-1.0, 1.0]:
		var lat: Array
		var lifts: Array
		if side < 0:
			lat = [-(R + 4.0), -R, -(H + 1.8), -H]
			lifts = [-0.35, -0.12, -0.05, -0.02]
		else:
			lat = [H, H + 1.8, R, R + 4.0]
			lifts = [-0.02, -0.05, -0.12, -0.35]
		var v := _ribbon(lat, lifts, 2, 0)
		var m := MU.grid_mesh(v[0], v[1], v[2], v[3], Vector3.UP)
		var vm := MeshInstance3D.new()
		vm.mesh = m
		vm.material_override = tmat
		root.add_child(vm)


func _curb_piece(a: int, b: int, side: float, mat: Material) -> void:
	var H: float = TD.ROAD_HALF
	var rows := b - a + 1
	var lat := [H - 0.05, H + 0.6, H + 1.2] if side > 0 else [-(H + 1.2), -(H + 0.6), -(H - 0.05)]
	var lift := [0.015, 0.06, 0.03] if side > 0 else [0.03, 0.06, 0.015]
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for r in rows:
		var i := (a + r) % tr.N
		var h := tr.HD[i]
		var right := Vector3(-cos(h), 0.0, sin(h))
		var base := Vector3(tr.X[i], tr.Y[i], tr.Z[i])
		var bk := sin(tr.BK[i])
		for c in 3:
			var d: float = lat[c]
			var p := base + right * d
			p.y += bk * d + float(lift[c])
			verts.append(p)
			var u := float(c) / 2.0
			uvs.append(Vector2(u if side > 0 else 1.0 - u, (a + r) * tr.ds))
	var mi := MeshInstance3D.new()
	mi.mesh = MU.grid_mesh(verts, uvs, rows, 3, Vector3.UP)
	mi.material_override = mat
	root.add_child(mi)


func _terrain_material(pal: Dictionary) -> ShaderMaterial:
	if tex.has("terrain_mat"):
		return tex["terrain_mat"]
	var m := Mats.shader_mat(Mats.TERRAIN_SHADER)
	m.set_shader_parameter("detail", tex["detail"])
	m.set_shader_parameter("detail_n", tex["detail_n"])
	m.set_shader_parameter("macro", tex["macro"])
	m.set_shader_parameter("col_a", pal["a"])
	m.set_shader_parameter("col_b", pal["b"])
	m.set_shader_parameter("col_dirt", pal["dirt"])
	m.set_shader_parameter("col_rock", pal["rock"])
	m.set_shader_parameter("col_sand", pal["sand"])
	m.set_shader_parameter("rock_slope", pal["rock_slope"])
	m.set_shader_parameter("water_level", tr.water_level)
	tex["terrain_mat"] = m
	return m


# ---------------------------------------------------------------- terrain
var terrain_verts := PackedVector3Array()
var terrain_rows := 0


func _terrain() -> void:
	var b: Rect2 = tr.bounds
	cx = b.position.x + b.size.x * 0.5
	cz = b.position.y + b.size.y * 0.5
	size = maxf(b.size.x, b.size.y) + 1800.0
	var seg: int = quality.get("terrain_seg", 120)
	# keep terrain cells ~25 m on long highways so the ground never pokes through the verges
	seg = clampi(maxi(seg, int(size / 25.0)), seg, 230)
	var n := seg + 1
	terrain_rows = n
	terrain_verts.resize(n * n)
	var uvs := PackedVector2Array()
	uvs.resize(n * n)
	for r in n:
		for c in n:
			var x := cx - size * 0.5 + size * c / seg
			var z := cz - size * 0.5 + size * r / seg
			terrain_verts[r * n + c] = Vector3(x, tr.ground_height(x, z), z)
			uvs[r * n + c] = Vector2(x, z)
	var pal: Dictionary = PALETTES[tr.def["biome"]]
	var mi := MeshInstance3D.new()
	mi.mesh = MU.grid_mesh(terrain_verts, uvs, n, n, Vector3.UP)
	mi.material_override = _terrain_material(pal)
	mi.name = "Terrain"
	root.add_child(mi)

	if tr.water_level > -999.0:
		var w := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(size * 3.0, size * 3.0)
		w.mesh = pm
		w.position = Vector3(cx, tr.water_level, cz)
		var wm := Mats.shader_mat(Mats.WATER_SHADER)
		wm.set_shader_parameter("wave_n", Mats.noise_tex(41, 0.03, 4, 512, true, 3.0))
		w.material_override = wm
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(w)

	# distant mountain ring (or mesas)
	var ring_r := maxf(tr.bounds.size.x, tr.bounds.size.y) * 0.5 + 1300.0
	var segs := 96
	var rings := 4
	var mv := PackedVector3Array()
	var muv := PackedVector2Array()
	var desert: bool = tr.def["biome"] == "desert"
	var coast: bool = tr.def["biome"] == "coast"
	for r in rings:
		for c in segs + 1:
			var a := TAU * c / segs
			var rad := ring_r + r * 260.0
			var hgt := 0.0
			if r > 0 and r < rings - 1:
				var nn := sin(a * 7.0 + 1.3) * 0.5 + sin(a * 13.0 + 0.4) * 0.3 + sin(a * 29.0) * 0.2
				hgt = (140.0 if desert else 330.0) * (0.55 + 0.45 * nn) * (1.0 if r == 1 else 0.8)
				if desert:
					hgt = floor(hgt / 45.0) * 45.0 + 20.0 # stepped mesa silhouettes
				if coast and cos(a) > 0.15:
					hgt = -40.0
			else:
				hgt = -30.0 if r == 0 else -60.0
			mv.append(Vector3(cx + cos(a) * rad, hgt, cz + sin(a) * rad))
			muv.append(Vector2(c, r))
	var mm := MeshInstance3D.new()
	mm.mesh = MU.grid_mesh(mv, muv, rings, segs + 1, Vector3.UP)
	var mmat := Mats.shader_mat(Mats.MOUNTAIN_SHADER)
	mmat.set_shader_parameter("rock", Color(0.62, 0.38, 0.26) if desert else (Color(0.42, 0.4, 0.45) if coast else Color(0.36, 0.4, 0.42)))
	mmat.set_shader_parameter("snow_line", 9999.0 if desert or coast else (60.0 if tr.def["biome"] == "snow" else 230.0))
	mmat.set_shader_parameter("detail", tex["detail"])
	mm.material_override = mmat
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mm)


# ---------------------------------------------------------------- barriers
func _barriers() -> void:
	var R: float = TD.RUNOFF
	# W-beam (armco) profile: [lateral offset from barrier line, height]
	var prof := [[0.0, 0.48], [0.1, 0.55], [0.03, 0.62], [0.1, 0.69], [0.0, 0.76]]
	var metal := Mats.std(Color(0.62, 0.64, 0.66), 0.42, 0.85)
	metal.cull_mode = BaseMaterial3D.CULL_DISABLED
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.12, 0.85, 0.1)
	var post_mat := Mats.std(Color(0.35, 0.36, 0.37), 0.6, 0.7)
	post_mesh.material = post_mat
	var post_xf: Array[Transform3D] = []
	for side in [-1.0, 1.0]:
		var step := 2
		var rows := int(ceilf(float(tr.N) / step)) + 1
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		for r in rows:
			var i := mini(r * step, tr.N) % tr.N
			var h := tr.HD[i]
			var right := Vector3(-cos(h), 0.0, sin(h))
			var base := Vector3(tr.X[i], tr.Y[i], tr.Z[i])
			var bk := sin(tr.BK[i])
			for c in prof.size():
				var off: float = prof[c][0]
				var d: float = side * (R - off)
				var p := base + right * d
				p.y += bk * d + float(prof[c][1])
				verts.append(p)
				uvs.append(Vector2(float(c) / 4.0, r * step * tr.ds * 0.25))
			if r % 2 == 0:
				var dpost: float = side * (R + 0.12)
				var pp := base + right * dpost
				pp.y += bk * dpost + 0.42
				post_xf.append(Transform3D(Basis(Vector3.UP, h), pp))
		var mi := MeshInstance3D.new()
		mi.mesh = MU.grid_mesh(verts, uvs, rows, prof.size(), right_dir_hint(side))
		mi.material_override = metal
		root.add_child(mi)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = post_mesh
	mm.instance_count = post_xf.size()
	for k in post_xf.size():
		mm.set_instance_transform(k, post_xf[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)


func right_dir_hint(side: float) -> Vector3:
	# barrier faces the track; exact orientation does not matter (double sided)
	return Vector3.UP


# ---------------------------------------------------------------- collision
func _collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var H: float = TD.ROAD_HALF
	var R: float = TD.RUNOFF
	# drivable surface (road + curbs + verge) at full resolution
	var rb := _ribbon([-(R + 4.0), -R, -(H + 1.8), -H, -H * 0.5, 0.0, H * 0.5, H, H + 1.8, R, R + 4.0],
		[-0.35, -0.12, -0.05, 0.0, 0.0, 0.0, 0.0, 0.0, -0.05, -0.12, -0.35], 1, 0)
	_add_trimesh(body, MU.grid_faces(rb[0], rb[2], rb[3], 1))
	# terrain (coarser rows are fine: only reached after a crash over the barrier)
	_add_trimesh(body, MU.grid_faces(terrain_verts, terrain_rows, terrain_rows, 1))
	# barriers as walls
	var walls := StaticBody3D.new()
	walls.name = "Walls"
	walls.collision_layer = 2
	walls.collision_mask = 0
	root.add_child(walls)
	for side in [-1.0, 1.0]:
		var w := _ribbon([side * R, side * R], [-0.6, 1.1], 2, 0)
		_add_trimesh(walls, MU.grid_faces(w[0], w[2], w[3], 1))


func _add_trimesh(body: StaticBody3D, faces: PackedVector3Array) -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


# ---------------------------------------------------------------- scenery
func _scenery() -> void:
	var biome: String = tr.def["biome"]
	var flora = Flora.new()
	var tree_count: int = quality.get("trees", 900)
	var kinds: Array = []
	if biome == "snow":
		kinds = [[flora.conifer_tree(tex["leaf"], Color(0.2, 0.26, 0.22)), 0.55], [flora.conifer_tree(tex["leaf"], Color(0.5, 0.55, 0.55)), 0.3], [flora.rock(tex["detail"], Color(0.42, 0.42, 0.44)), 0.15]]
	elif biome == "grass":
		kinds = [[flora.broadleaf_tree(tex["leaf"], Color(0.2, 0.33, 0.1)), 0.45], [flora.conifer_tree(tex["leaf"]), 0.4], [flora.broadleaf_tree(tex["leaf"], Color(0.3, 0.38, 0.12)), 0.15]]
	elif biome == "coast":
		kinds = [[flora.palm_tree(tex["leaf"]), 0.6], [flora.broadleaf_tree(tex["leaf"], Color(0.27, 0.36, 0.13)), 0.25], [flora.bush(tex["leaf"], Color(0.3, 0.38, 0.15)), 0.15]]
	else:
		kinds = [[flora.cactus(), 0.45], [flora.bush(tex["leaf"], Color(0.42, 0.4, 0.2)), 0.25], [flora.rock(tex["detail"], Color(0.55, 0.3, 0.18)), 0.3]]
	# chunked placement so far chunks are culled by visibility range
	var CH := 250.0
	var chunks := {}
	var placed := 0
	var tries := 0
	var ext := size * 0.5 - 80.0
	while placed < tree_count and tries < tree_count * 12:
		tries += 1
		var x := cx + rng.randf_range(-ext, ext)
		var z := cz + rng.randf_range(-ext, ext)
		if rng.randf() < 0.6:
			# most trees line the circuit where the rider actually sees them
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var off := TD.RUNOFF + 8.0 + pow(rng.randf(), 2.0) * 160.0
			var fp: Dictionary = tr.frame(rng.randf() * tr.L, side * off)
			var pp: Vector3 = fp["pos"]
			x = pp.x
			z = pp.z
		var q := tr.nearest(x, z)
		var dist: float = q[1] if q[0] >= 0 else 120.0
		if dist < TD.RUNOFF + 7.0 or (dist > 600.0):
			continue
		# denser near the track where the player sees it
		if dist > 140.0 and rng.randf() < 0.55:
			continue
		var y := tr.ground_height(x, z)
		if tr.water_level > -999.0 and y < tr.water_level + 1.5:
			continue
		var pick := rng.randf()
		var k := 0
		var acc := 0.0
		for j in kinds.size():
			acc += float(kinds[j][1])
			if pick <= acc:
				k = j
				break
		var key := Vector3i(floori(x / CH), floori(z / CH), k)
		if not chunks.has(key):
			chunks[key] = []
		var s := rng.randf_range(0.75, 1.35)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s)), Vector3(x, y - 0.15, z))
		chunks[key].append(xf)
		placed += 1
	for key in chunks:
		var arr: Array = chunks[key]
		var kind: Array = kinds[key.z]
		var mesh: Mesh = kind[0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = arr.size()
		for j in arr.size():
			mm.set_instance_transform(j, arr[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = quality.get("tree_range", 700.0)
		mmi.visibility_range_end_margin = 40.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality.get("tree_shadows", true) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)

	# grass tufts along the verges (chunked by track distance)
	if biome != "desert" and biome != "snow" and quality.get("grass", 0) > 0:
		var gm: Mesh = flora.grass_clump(Color(0.12, 0.2, 0.06) if biome == "grass" else Color(0.22, 0.24, 0.1), Color(0.48, 0.62, 0.24) if biome == "grass" else Color(0.62, 0.6, 0.32))
		var per_chunk: int = quality.get("grass", 0)
		var chunk_len := 60.0
		var nchunks := int(tr.L / chunk_len)
		for ci in nchunks:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = gm
			mm.instance_count = per_chunk
			var center := Vector3.ZERO
			for j in per_chunk:
				var s := (ci + rng.randf()) * chunk_len
				var side := -1.0 if rng.randf() < 0.5 else 1.0
				var d := side * rng.randf_range(TD.ROAD_HALF + 2.0, TD.RUNOFF - 0.5)
				var f: Dictionary = tr.frame(s, d)
				var p: Vector3 = f["pos"]
				p.y -= 0.07 + 0.02 * (absf(d) - TD.ROAD_HALF)  # follow verge droop
				var sc := rng.randf_range(0.6, 1.3)
				mm.set_instance_transform(j, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), p))
				center += p
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.visibility_range_end = quality.get("grass_range", 70.0)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)

	# desert mesas close to the track
	if biome == "desert":
		var rock_mat := Mats.shader_mat(Mats.MOUNTAIN_SHADER)
		rock_mat.set_shader_parameter("rock", Color(0.6, 0.32, 0.2))
		rock_mat.set_shader_parameter("snow_line", 9999.0)
		rock_mat.set_shader_parameter("detail", tex["detail"])
		var m := 0
		var t2 := 0
		while m < 22 and t2 < 400:
			t2 += 1
			var x := cx + rng.randf_range(-size * 0.35, size * 0.35)
			var z := cz + rng.randf_range(-size * 0.35, size * 0.35)
			var q := tr.nearest(x, z)
			var dist: float = q[1] if q[0] >= 0 else 150.0
			if dist < 90.0:
				continue
			var cyl := CylinderMesh.new()
			var rr := rng.randf_range(20.0, 48.0)
			var hh := rng.randf_range(30.0, 75.0)
			cyl.top_radius = rr * 0.86
			cyl.bottom_radius = rr
			cyl.height = hh
			cyl.radial_segments = 9
			cyl.rings = 3
			var mi := MeshInstance3D.new()
			mi.mesh = cyl
			mi.material_override = rock_mat
			mi.position = Vector3(x, tr.ground_height(x, z) + hh * 0.5 - 3.0, z)
			mi.rotation.y = rng.randf() * TAU
			root.add_child(mi)
			m += 1


# ---------------------------------------------------------------- props
func _props() -> void:
	if tr.def.get("highway", false):
		return
	var f: Dictionary = tr.frame(0.0, 0.0)
	var dark := Mats.std(Color(0.16, 0.17, 0.19), 0.6, 0.3)
	var white := Mats.std(Color(0.85, 0.86, 0.88), 0.5)
	var red := Mats.std(Color(0.7, 0.08, 0.06), 0.45)
	var R: float = TD.RUNOFF
	# start / finish gantry
	var g := Node3D.new()
	g.position = f["pos"]
	g.rotation.y = f["heading"]
	root.add_child(g)
	for sx in [-1.0, 1.0]:
		_box(g, Vector3(0.9, 8.5, 0.9), Vector3(sx * (R + 0.8), 4.25, 0.0), dark)
	_box(g, Vector3(R * 2.0 + 2.6, 1.6, 0.7), Vector3(0, 8.0, 0), red)
	var lbl := Label3D.new()
	lbl.text = "START  ·  FINISH"
	lbl.font_size = 160
	lbl.pixel_size = 0.01
	lbl.outline_size = 0
	lbl.position = Vector3(0, 8.0, -0.37)
	lbl.rotation.y = PI
	lbl.modulate = Color(1, 1, 1)
	g.add_child(lbl)
	var lbl2: Label3D = lbl.duplicate()
	lbl2.position = Vector3(0, 8.0, 0.37)
	lbl2.rotation.y = 0.0
	g.add_child(lbl2)
	# start lights
	for k in 5:
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22; sm.height = 0.44
		lamp.mesh = sm
		lamp.position = Vector3(-2.0 + k, 7.0, -0.2)
		lamp.name = "Lamp%d" % k
		lamp.material_override = Mats.std(Color(0.1, 0.02, 0.02), 0.3)
		g.add_child(lamp)
	g.name = "Gantry"

	# grandstand + pit building along the main straight
	var gs := Node3D.new()
	var fg: Dictionary = tr.frame(-60.0, -(R + 14.0))
	gs.position = fg["pos"]
	gs.rotation.y = fg["heading"]
	root.add_child(gs)
	var crowd := Mats.shader_mat("""
shader_type spatial;
void fragment() {
	vec2 c = floor(UV * vec2(160.0, 10.0));
	float h = fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453);
	float h2 = fract(h * 13.7);
	vec3 col = h < 0.15 ? vec3(0.8, 0.1, 0.1) : h < 0.3 ? vec3(0.9, 0.8, 0.2) : h < 0.45 ? vec3(0.15, 0.3, 0.8) : h < 0.6 ? vec3(0.9) : h < 0.75 ? vec3(0.1) : vec3(0.5, 0.35, 0.25);
	vec2 fu = fract(UV * vec2(160.0, 10.0));
	float body = step(0.2, fu.x) * step(fu.x, 0.8) * step(fu.y, 0.75);
	ALBEDO = mix(vec3(0.25, 0.26, 0.28), col * (0.7 + 0.3 * h2), body);
	ROUGHNESS = 0.9;
}
""")
	for r in 5:
		var step := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.4, 1.1, 120.0)
		step.mesh = bm
		step.position = Vector3(-r * 2.4, 0.55 + r * 1.1, 0.0)
		step.material_override = crowd if r > 0 else dark
		gs.add_child(step)
	_box(gs, Vector3(14.0, 0.4, 124.0), Vector3(-5.0, 7.6, 0.0), white).rotation.z = -0.08
	for z in range(-60, 61, 20):
		_box(gs, Vector3(0.3, 7.6, 0.3), Vector3(-11.0, 3.8, float(z)), dark)
	# pit building on the right
	var pb := Node3D.new()
	var fp: Dictionary = tr.frame(-80.0, R + 16.0)
	pb.position = fp["pos"]
	pb.rotation.y = fp["heading"]
	root.add_child(pb)
	_box(pb, Vector3(12.0, 6.0, 150.0), Vector3(6.0, 3.0, 0.0), white)
	_box(pb, Vector3(12.4, 0.5, 152.0), Vector3(6.0, 6.2, 0.0), dark)
	for k in 10:
		_box(pb, Vector3(0.2, 4.0, 11.0), Vector3(-0.05, 2.0, -67.5 + k * 15.0), dark)

	# brake marker boards (300 / 200 / 100 m) before tight corners
	var board_mat := Mats.std(Color(0.95, 0.95, 0.95), 0.6)
	var last := -1e9
	var i := 0
	while i < tr.N:
		var k := absf(tr.K[i])
		var s := i * tr.ds
		if k > 1.0 / 130.0 and s - last > 400.0 and s > 350.0:
			last = s
			var side := 1.0 if tr.K[i] > 0.0 else -1.0  # outside of the corner
			for dist in [300, 200, 100]:
				var fb: Dictionary = tr.frame(s - dist - 40.0, side * (R + 2.0))
				var bnode := Node3D.new()
				bnode.position = fb["pos"]
				bnode.rotation.y = float(fb["heading"]) + PI
				root.add_child(bnode)
				_box(bnode, Vector3(1.4, 1.0, 0.08), Vector3(0, 1.4, 0), board_mat)
				_box(bnode, Vector3(0.1, 1.0, 0.1), Vector3(0, 0.45, 0.02), dark)
				var t3 := Label3D.new()
				t3.text = str(dist)
				t3.font_size = 96
				t3.pixel_size = 0.006
				t3.modulate = Color(0.05, 0.05, 0.05)
				t3.outline_size = 0
				t3.position = Vector3(0, 1.4, -0.05)
				t3.rotation.y = PI
				bnode.add_child(t3)
			i += 60
		i += 3


func _box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------- highway props: houses & overpasses
func _highway_props() -> void:
	var R: float = TD.RUNOFF
	var wall_mats := [Mats.std(Color(0.86, 0.82, 0.74), 0.85), Mats.std(Color(0.72, 0.62, 0.52), 0.85),
		Mats.std(Color(0.9, 0.9, 0.88), 0.8), Mats.std(Color(0.55, 0.38, 0.3), 0.85)]
	var roof_mats := [Mats.std(Color(0.55, 0.2, 0.15), 0.7), Mats.std(Color(0.25, 0.25, 0.28), 0.7),
		Mats.std(Color(0.4, 0.28, 0.2), 0.75)]
	if tr.def["biome"] == "snow":
		roof_mats = [Mats.std(Color(0.9, 0.92, 0.95), 0.6)]
	var glass := Mats.std(Color(0.08, 0.1, 0.13), 0.1, 0.6)
	var door := Mats.std(Color(0.3, 0.2, 0.12), 0.7)
	var s := 300.0
	while s < tr.L - 300.0:
		s += rng.randf_range(160.0, 420.0)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var n := rng.randi_range(1, 3)
		for k in n:
			var d := side * rng.randf_range(R + 18.0, R + 70.0)
			var f: Dictionary = tr.frame(s + k * rng.randf_range(18.0, 30.0), d)
			var p: Vector3 = f["pos"]
			p.y = tr.ground_height(p.x, p.z)
			if tr.water_level > -999.0 and p.y < tr.water_level + 1.0:
				continue
			var house := Node3D.new()
			house.position = p
			house.rotation.y = float(f["heading"]) + (PI * 0.5 if rng.randf() < 0.5 else 0.0)
			root.add_child(house)
			var w := rng.randf_range(7.0, 12.0)
			var dpt := rng.randf_range(6.0, 10.0)
			var h := rng.randf_range(3.0, 6.5)
			_box(house, Vector3(w, h, dpt), Vector3(0, h * 0.5 - 0.3, 0), wall_mats[rng.randi() % wall_mats.size()])
			var roof := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(w + 0.8, rng.randf_range(1.8, 3.2), dpt + 0.8)
			roof.mesh = pm
			roof.position = Vector3(0, h - 0.3 + pm.size.y * 0.5, 0)
			roof.material_override = roof_mats[rng.randi() % roof_mats.size()]
			house.add_child(roof)
			for wx in [-w * 0.28, w * 0.28]:
				_box(house, Vector3(1.2, 1.1, 0.06), Vector3(wx, h * 0.55, dpt * 0.5 + 0.02), glass)
			_box(house, Vector3(1.0, 2.0, 0.06), Vector3(0, 0.7, dpt * 0.5 + 0.02), door)
	# overpasses
	var concrete := Mats.std(Color(0.62, 0.62, 0.6), 0.9)
	var os := 900.0
	while os < tr.L - 600.0:
		var f: Dictionary = tr.frame(os, 0.0)
		var op := Node3D.new()
		op.position = f["pos"]
		op.rotation.y = f["heading"]
		root.add_child(op)
		var span := (R + 6.0) * 2.0
		_box(op, Vector3(span + 10.0, 1.2, 12.0), Vector3(0, 7.6, 0), concrete)
		for sz in [-1.0, 1.0]:
			_box(op, Vector3(span + 10.0, 1.0, 0.3), Vector3(0, 8.7, sz * 5.9), concrete)
			for sx in [-1.0, 1.0]:
				_box(op, Vector3(1.4, 7.6, 1.4), Vector3(sx * (R + 3.0), 3.4, sz * 3.5), concrete)
		os += rng.randf_range(1400.0, 2400.0)
