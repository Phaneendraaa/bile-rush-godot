extends RefCounted
## Particle effects: tyre smoke (wheelspin / slides) and dust (off track).

static var _mats := {}


static func emitter(kind: String) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 48 if kind == "smoke" else 36
	p.lifetime = 1.8 if kind == "smoke" else 1.2
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 8, 16))
	p.process_material = _process_mat(kind)
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = _draw_mat(kind)
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func _process_mat(kind: String) -> ParticleProcessMaterial:
	var key := "pm_" + kind
	if _mats.has(key):
		return _mats[key]
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.15
	m.direction = Vector3(0, 1, 0)
	m.spread = 70.0
	m.initial_velocity_min = 0.4
	m.initial_velocity_max = 2.2
	m.gravity = Vector3(0, 0.5 if kind == "smoke" else -1.5, 0)
	m.damping_min = 1.0
	m.damping_max = 2.0
	m.scale_min = 0.7
	m.scale_max = 1.4
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.5))
	sc.add_point(Vector2(1.0, 3.2 if kind == "smoke" else 2.2))
	var sct := CurveTexture.new()
	sct.curve = sc
	m.scale_curve = sct
	var g := Gradient.new()
	var c := Color(0.92, 0.92, 0.92) if kind == "smoke" else Color(0.55, 0.45, 0.32)
	g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	g.colors = PackedColorArray([Color(c, 0.0), Color(c, 0.42 if kind == "smoke" else 0.5), Color(c, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	m.angle_min = -180.0
	m.angle_max = 180.0
	_mats[key] = m
	return m


static func _draw_mat(kind: String) -> StandardMaterial3D:
	var key := "dm_" + kind
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# soft round puff from a radial gradient
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	m.albedo_texture = t
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.6
	_mats[key] = m
	return m
