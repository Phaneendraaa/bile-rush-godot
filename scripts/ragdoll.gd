extends Node3D
## Rider ragdoll spawned on a crash: rigid limbs joined with cone-twist joints.

var bodies: Array[RigidBody3D] = []


func spawn(model: Node3D, velocity: Vector3, suit: Material, leather: Material, helmet_mat: Material) -> void:
	var xf := model.global_transform
	var P: Dictionary = model.get("pose")
	if P.is_empty():
		return
	var g := func(k: String) -> Vector3: return xf * (P[k] as Vector3)
	var parts := {}
	parts["pelvis"] = _limb(g.call("hip_l"), g.call("hip_r"), 0.13, 16.0, suit)
	parts["chest"] = _limb(g.call("pelvis"), g.call("chest"), 0.16, 26.0, suit)
	parts["head"] = _ball(g.call("head"), 0.15, 5.0, helmet_mat)
	for sd in ["l", "r"]:
		parts["ua_" + sd] = _limb(g.call("shoulder_" + sd), g.call("elbow_" + sd), 0.055, 2.5, suit)
		parts["fa_" + sd] = _limb(g.call("elbow_" + sd), g.call("hand_" + sd), 0.05, 2.0, leather)
		parts["th_" + sd] = _limb(g.call("hip_" + sd), g.call("knee_" + sd), 0.075, 8.0, suit)
		parts["sh_" + sd] = _limb(g.call("knee_" + sd), g.call("foot_" + sd), 0.06, 4.5, leather)
	_joint(parts["pelvis"], parts["chest"], g.call("pelvis"), 35.0, 25.0)
	_joint(parts["chest"], parts["head"], g.call("head") - Vector3(0, 0.15, 0), 40.0, 40.0)
	for sd in ["l", "r"]:
		_joint(parts["chest"], parts["ua_" + sd], g.call("shoulder_" + sd), 80.0, 45.0)
		_joint(parts["ua_" + sd], parts["fa_" + sd], g.call("elbow_" + sd), 70.0, 10.0)
		_joint(parts["pelvis"], parts["th_" + sd], g.call("hip_" + sd), 70.0, 30.0)
		_joint(parts["th_" + sd], parts["sh_" + sd], g.call("knee_" + sd), 70.0, 10.0)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for b in bodies:
		b.linear_velocity = velocity * 0.92 + Vector3(rng.randf_range(-1, 1), rng.randf_range(1.0, 3.0), rng.randf_range(-1, 1))
		b.angular_velocity = Vector3(rng.randf_range(-4, 4), rng.randf_range(-4, 4), rng.randf_range(-4, 4))


func _body(mass_: float, pos: Vector3) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.mass = mass_
	b.collision_layer = 8
	b.collision_mask = 1 | 2
	b.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.7
	pm.bounce = 0.1
	b.physics_material_override = pm
	b.linear_damp = 0.05
	b.angular_damp = 0.8
	add_child(b)
	b.global_position = pos
	bodies.append(b)
	return b


func _limb(a: Vector3, c: Vector3, radius: float, mass_: float, mat: Material) -> RigidBody3D:
	var mid := (a + c) * 0.5
	var b := _body(mass_, mid)
	var d := c - a
	var length := maxf(d.length(), 0.05)
	var y := d / length
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	b.global_basis = Basis(x, y, z)
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = length + radius * 2.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	b.add_child(cs)
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = shape.height
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	b.add_child(mi)
	return b


func _ball(p: Vector3, radius: float, mass_: float, mat: Material) -> RigidBody3D:
	var b := _body(mass_, p)
	var shape := SphereShape3D.new()
	shape.radius = radius
	var cs := CollisionShape3D.new()
	cs.shape = shape
	b.add_child(cs)
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = mat
	b.add_child(mi)
	return b


func _joint(a: RigidBody3D, b: RigidBody3D, at: Vector3, swing_deg: float, twist_deg: float) -> void:
	var j := ConeTwistJoint3D.new()
	add_child(j)
	j.global_position = at
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
	j.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(swing_deg))
	j.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(twist_deg))
	j.set_param(ConeTwistJoint3D.PARAM_SOFTNESS, 0.8)
	j.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 1.0)


func settled() -> bool:
	for b in bodies:
		if b.linear_velocity.length() > 0.6:
			return false
	return true
