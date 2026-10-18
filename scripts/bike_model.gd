extends Node3D
## Visual superbike + rider. Rebuilt every frame from physics state:
## suspension travel, steering, wheel spin, brake light, rider pose (tuck / hang-off) via 2-bone IK.

const Mats = preload("res://scripts/materials.gd")
const R := 0.31
const WB := 1.42

var paint: StandardMaterial3D
var suit: StandardMaterial3D
var parts := {}
var bones := {}           # name -> [MeshInstance3D, nominal length]
var front_wheel: Node3D
var rear_wheel: Node3D
var front_spin: Node3D
var rear_spin: Node3D
var swingarm: Node3D
var fork_l: MeshInstance3D
var fork_r: MeshInstance3D
var steer_node: Node3D
var tail_mat: StandardMaterial3D
var rider_root: Node3D
var helmet: Node3D
var torso_mi: MeshInstance3D
var pose := {}            # last computed rider joint positions (bike-local), used by ragdoll
var number := 1
var btype := "sport"

static var _shared := {}


static func shared() -> Dictionary:
	if not _shared.is_empty():
		return _shared
	var tire := Mats.std(Color(0.05, 0.05, 0.055), 0.82)
	tire.normal_enabled = true
	tire.normal_texture = Mats.noise_tex(101, 0.25, 2, 128, true, 4.0)
	_shared["tire"] = tire
	_shared["alu"] = Mats.std(Color(0.72, 0.74, 0.77), 0.22, 1.0)
	_shared["dark_alu"] = Mats.std(Color(0.12, 0.12, 0.13), 0.35, 0.9)
	_shared["gold"] = Mats.std(Color(0.86, 0.66, 0.28), 0.18, 1.0)
	_shared["chrome"] = Mats.std(Color(0.9, 0.9, 0.92), 0.08, 1.0)
	_shared["titanium"] = Mats.std(Color(0.55, 0.5, 0.62), 0.25, 1.0)
	_shared["disc"] = Mats.std(Color(0.6, 0.6, 0.62), 0.32, 0.95)
	_shared["plastic"] = Mats.std(Color(0.04, 0.04, 0.045), 0.42)
	_shared["carbon"] = Mats.std(Color(0.06, 0.06, 0.07), 0.25, 0.3)
	_shared["seat"] = Mats.std(Color(0.05, 0.05, 0.05), 0.75)
	var glass := Mats.std(Color(0.12, 0.14, 0.18, 0.45), 0.04)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shared["glass"] = glass
	var visor := Mats.std(Color(0.08, 0.08, 0.1), 0.03, 1.0)
	_shared["visor"] = visor
	var head := Mats.std(Color(1, 1, 1), 0.2)
	head.emission_enabled = true
	head.emission = Color(1.0, 0.97, 0.9)
	head.emission_energy_multiplier = 3.0
	_shared["headlight"] = head
	var leather := Mats.std(Color(0.08, 0.08, 0.09), 0.6)
	_shared["leather"] = leather
	var boot := Mats.std(Color(0.12, 0.12, 0.13), 0.45)
	_shared["boot"] = boot
	return _shared


func build(body_color: Color, suit_color: Color, race_number: int, type_: String = "sport") -> void:
	number = race_number
	btype = type_
	var S := shared()
	paint = Mats.std(body_color, 0.28, 0.35)
	paint.clearcoat_enabled = true
	paint.clearcoat = 1.0
	paint.clearcoat_roughness = 0.04
	suit = Mats.std(suit_color, 0.55)
	tail_mat = Mats.std(Color(0.3, 0.0, 0.0), 0.3)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.05, 0.02)
	tail_mat.emission_energy_multiplier = 1.0
	var white := Mats.std(Color(0.92, 0.92, 0.93), 0.3, 0.1)
	white.clearcoat_enabled = true
	white.clearcoat = 1.0

	# ---------- wheels
	front_wheel = Node3D.new(); add_child(front_wheel)
	rear_wheel = Node3D.new(); add_child(rear_wheel)
	front_spin = _wheel(front_wheel, S, true)
	rear_spin = _wheel(rear_wheel, S, false)

	# ---------- frame & body (static relative to chassis)
	# twin-spar aluminium frame
	for sx in [-1.0, 1.0]:
		_strut(Vector3(sx * 0.13, 1.0, -0.47), Vector3(sx * 0.16, 0.62, 0.22), 0.05, 0.08, S["alu"])
	# engine
	_box(Vector3(0.36, 0.34, 0.46), Vector3(0, 0.52, -0.12), S["dark_alu"], Vector3(0.25, 0, 0))
	_cyl(0.13, 0.4, Vector3(0, 0.46, -0.05), S["alu"], Vector3(0, 0, PI / 2))
	_box(Vector3(0.28, 0.2, 0.32), Vector3(0, 0.78, -0.2), S["dark_alu"], Vector3(-0.3, 0, 0))
	# radiator
	_box(Vector3(0.42, 0.32, 0.05), Vector3(0, 0.72, -0.48), S["plastic"], Vector3(0.2, 0, 0))
	if btype == "sport":
		# fairing: nose, sides, belly pan
		_ell(Vector3(0.25, 0.27, 0.42), Vector3(0, 0.96, -0.66), paint, Vector3(-0.3, 0, 0))
		_ell(Vector3(0.13, 0.08, 0.06), Vector3(0.08, 0.95, -1.04), S["headlight"])
		_ell(Vector3(0.13, 0.08, 0.06), Vector3(-0.08, 0.95, -1.04), S["headlight"])
		for sx in [-1.0, 1.0]:
			var side := _box(Vector3(0.05, 0.46, 0.78), Vector3(sx * 0.215, 0.74, -0.38), paint, Vector3(0.22, sx * 0.08, 0))
			var stripe := _box(Vector3(0.052, 0.08, 0.7), Vector3(sx * 0.218, 0.86, -0.36), white, Vector3(0.22, sx * 0.08, 0))
			var lbl := Label3D.new()
			lbl.text = str(race_number)
			lbl.font_size = 64
			lbl.pixel_size = 0.004
			lbl.outline_size = 8
			lbl.modulate = Color(1, 1, 1)
			lbl.outline_modulate = Color(0, 0, 0)
			lbl.position = Vector3(sx * 0.245, 0.68, -0.42)
			lbl.rotation.y = sx * PI / 2
			add_child(lbl)
		_box(Vector3(0.4, 0.12, 0.62), Vector3(0, 0.38, -0.12), paint, Vector3(-0.08, 0, 0))
		# windscreen
		_box(Vector3(0.3, 0.012, 0.3), Vector3(0, 1.17, -0.58), S["glass"], Vector3(-0.95, 0, 0))
	elif btype == "naked":
		_ell(Vector3(0.12, 0.12, 0.1), Vector3(0, 1.05, -0.8), paint)                 # headlight cowl
		_ell(Vector3(0.1, 0.1, 0.03), Vector3(0, 1.04, -0.89), S["headlight"])
		_box(Vector3(0.36, 0.1, 0.5), Vector3(0, 0.36, -0.12), S["plastic"], Vector3(-0.08, 0, 0))
		for sx in [-1.0, 1.0]:
			_box(Vector3(0.05, 0.22, 0.34), Vector3(sx * 0.2, 0.92, -0.42), paint, Vector3(0.3, sx * 0.1, 0))  # tank shrouds
	else:
		_ell(Vector3(0.15, 0.15, 0.13), Vector3(0, 0.98, -0.95), S["chrome"])          # headlight bucket
		_ell(Vector3(0.12, 0.12, 0.03), Vector3(0, 0.98, -1.06), S["headlight"])
		for sx in [-1.0, 1.0]:
			_cyl(0.11, 0.42, Vector3(sx * 0.13, 0.66, -0.12), S["chrome"], Vector3(0, 0, sx * 0.55))   # V-twin cylinders
		_box(Vector3(0.46, 0.06, 0.9), Vector3(0, 0.98, 0.62), paint, Vector3(0.05, 0, 0))            # rear fender
		_box(Vector3(0.32, 0.05, 0.5), Vector3(0, 1.06, -0.85), paint, Vector3(-0.6, 0, 0))           # front fender
	# tank
	if btype == "cruiser":
		_ell(Vector3(0.26, 0.15, 0.4), Vector3(0, 0.98, -0.18), paint)
	else:
		_ell(Vector3(0.24, 0.15, 0.32), Vector3(0, 1.05, -0.16), paint)
	# seat + tail
	_box(Vector3(0.24, 0.07, 0.38), Vector3(0, 1.0, 0.24), S["seat"], Vector3(0.1, 0, 0))
	_box(Vector3(0.22, 0.2, 0.5), Vector3(0, 1.05, 0.52), paint, Vector3(0.28, 0, 0))
	_box(Vector3(0.2, 0.04, 0.02), Vector3(0, 1.1, 0.79), tail_mat)
	# exhaust (underseat-right silencer)
	_cyl(0.065, 0.55, Vector3(0.16, 0.62, 0.48), S["titanium"], Vector3(PI / 2 - 0.35, 0, 0))
	_cyl(0.05, 0.03, Vector3(0.16, 0.71, 0.75), S["carbon"], Vector3(PI / 2 - 0.35, 0, 0))
	# footpegs
	for sx in [-1.0, 1.0]:
		_cyl(0.015, 0.12, Vector3(sx * 0.2, 0.45, 0.3), S["alu"], Vector3(0, 0, PI / 2))

	# ---------- swingarm (pivots with rear suspension)
	swingarm = Node3D.new()
	swingarm.position = Vector3(0, 0.58, 0.18)
	add_child(swingarm)
	for sx in [-1.0, 1.0]:
		var sa := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.1, 0.56)
		sa.mesh = bm
		sa.material_override = S["alu"]
		sa.position = Vector3(sx * 0.11, 0, 0.28)
		swingarm.add_child(sa)

	# ---------- steering assembly (forks, bars, front mudguard)
	steer_node = Node3D.new()
	add_child(steer_node)
	fork_l = _mi(CylinderMesh.new(), S["gold"]); steer_node.add_child(fork_l)
	fork_r = _mi(CylinderMesh.new(), S["gold"]); steer_node.add_child(fork_r)
	for f in [fork_l, fork_r]:
		var cm: CylinderMesh = f.mesh
		cm.top_radius = 0.032; cm.bottom_radius = 0.032; cm.height = 1.0; cm.radial_segments = 10
	for sx in [-1.0, 1.0]:
		var bar := _mi(CylinderMesh.new(), S["dark_alu"])
		var bc: CylinderMesh = bar.mesh
		bc.top_radius = 0.016; bc.bottom_radius = 0.016; bc.height = 0.28
		bar.position = Vector3(sx * 0.2, 1.05, -0.42)
		bar.rotation = Vector3(0, 0, PI / 2 + sx * 0.15)
		steer_node.add_child(bar)
		var mirror := _mi(BoxMesh.new(), S["plastic"])
		var mb: BoxMesh = mirror.mesh
		mb.size = Vector3(0.1, 0.05, 0.03)
		mirror.position = Vector3(sx * 0.27, 1.12, -0.62)
		steer_node.add_child(mirror)

	# ---------- rider
	rider_root = Node3D.new()
	add_child(rider_root)
	_bone("pelvis", 0.13, 0.22, suit)
	_bone("torso", 0.15, 0.5, suit)
	_bone("ua_l", 0.055, 0.3, suit); _bone("ua_r", 0.055, 0.3, suit)
	_bone("fa_l", 0.05, 0.3, S["leather"]); _bone("fa_r", 0.05, 0.3, S["leather"])
	_bone("th_l", 0.075, 0.44, suit); _bone("th_r", 0.075, 0.44, suit)
	_bone("sh_l", 0.06, 0.44, S["leather"]); _bone("sh_r", 0.06, 0.44, S["leather"])
	_bone("ft_l", 0.045, 0.2, S["boot"]); _bone("ft_r", 0.045, 0.2, S["boot"])
	helmet = Node3D.new()
	rider_root.add_child(helmet)
	var hm := _mi(SphereMesh.new(), paint)
	var hs: SphereMesh = hm.mesh
	hs.radius = 0.15; hs.height = 0.3
	hm.scale = Vector3(1.0, 0.95, 1.12)
	helmet.add_child(hm)
	var vs := _mi(SphereMesh.new(), S["visor"])
	var vsm: SphereMesh = vs.mesh
	vsm.radius = 0.12; vsm.height = 0.2
	vs.scale = Vector3(1.05, 0.55, 0.8)
	vs.position = Vector3(0, 0.0, -0.07)
	helmet.add_child(vs)
	var hump := _mi(SphereMesh.new(), white)
	var hhs: SphereMesh = hump.mesh
	hhs.radius = 0.1; hhs.height = 0.2
	hump.scale = Vector3(0.7, 0.6, 1.0)
	hump.position = Vector3(0, 0.05, 0.08)
	helmet.add_child(hump)


func _wheel(parent: Node3D, S: Dictionary, front: bool) -> Node3D:
	var spin := Node3D.new()
	parent.add_child(spin)
	var tire := _mi(TorusMesh.new(), S["tire"])
	var tm: TorusMesh = tire.mesh
	tm.inner_radius = R - 0.115
	tm.outer_radius = R
	tm.rings = 32
	tm.ring_segments = 12
	tire.rotation.z = PI / 2
	spin.add_child(tire)
	# 3-spoke cast rim
	for k in 3:
		var sp := _mi(BoxMesh.new(), S["dark_alu"])
		var bm: BoxMesh = sp.mesh
		bm.size = Vector3(0.04, R - 0.06, 0.05)
		sp.rotation.x = TAU * k / 3.0
		sp.position = Vector3(0, cos(TAU * k / 3.0) * (R - 0.06) * 0.5, sin(TAU * k / 3.0) * (R - 0.06) * 0.5)
		spin.add_child(sp)
	var rim := _mi(TorusMesh.new(), S["dark_alu"])
	var rm: TorusMesh = rim.mesh
	rm.inner_radius = R - 0.13
	rm.outer_radius = R - 0.1
	rm.rings = 24
	rm.ring_segments = 6
	rim.rotation.z = PI / 2
	spin.add_child(rim)
	var hub := _mi(CylinderMesh.new(), S["alu"])
	var hcm: CylinderMesh = hub.mesh
	hcm.top_radius = 0.05; hcm.bottom_radius = 0.05; hcm.height = 0.14
	hub.rotation.z = PI / 2
	spin.add_child(hub)
	# brake discs (do not spin visually different; fine to spin with wheel)
	var discs := [-0.08, 0.08] if front else [0.07]
	for dx in discs:
		var d := _mi(CylinderMesh.new(), S["disc"])
		var dm: CylinderMesh = d.mesh
		dm.top_radius = 0.16 if front else 0.11
		dm.bottom_radius = dm.top_radius
		dm.height = 0.008
		d.rotation.z = PI / 2
		d.position.x = dx
		spin.add_child(d)
	# caliper (non spinning)
	var cal := _mi(BoxMesh.new(), S["gold"] if front else S["dark_alu"])
	var cb: BoxMesh = cal.mesh
	cb.size = Vector3(0.05, 0.12, 0.08)
	cal.position = Vector3(0.1 if front else 0.08, 0.1, 0.08)
	parent.add_child(cal)
	return spin


func _mi(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	return m


func _box(sz: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = sz
	var m := _mi(bm, mat)
	m.position = pos
	m.rotation = rot
	add_child(m)
	return m


func _ell(radii: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 20
	sm.rings = 10
	var m := _mi(sm, mat)
	m.position = pos
	m.rotation = rot
	m.scale = radii
	add_child(m)
	return m


func _cyl(r: float, h: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 14
	var m := _mi(cm, mat)
	m.position = pos
	m.rotation = rot
	add_child(m)
	return m


func _strut(a: Vector3, b: Vector3, w: float, h: float, mat: Material) -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, a.distance_to(b))
	var m := _mi(bm, mat)
	m.transform = Transform3D(Basis.looking_at(b - a, Vector3.UP), (a + b) * 0.5)
	add_child(m)


func _bone(name_: String, radius: float, length: float, mat: Material) -> void:
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = maxf(length + radius * 2.0, radius * 2.0 + 0.01)
	cm.radial_segments = 12
	cm.rings = 4
	var m := _mi(cm, mat)
	rider_root.add_child(m)
	bones[name_] = [m, length]


func _place_bone(name_: String, a: Vector3, b: Vector3) -> void:
	var arr: Array = bones[name_]
	var m: MeshInstance3D = arr[0]
	var nominal: float = arr[1]
	var d := b - a
	var blen := d.length()
	if blen < 1e-4:
		return
	var y := d / blen
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	var s := blen / nominal
	m.transform = Transform3D(Basis(x, y * s, z), (a + b) * 0.5)


static func ik(a: Vector3, c: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var ac := c - a
	var d := clampf(ac.length(), 0.01, l1 + l2 - 0.001)
	var dir := ac.normalized()
	var x := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - x * x, 0.0))
	var pp := pole - dir * pole.dot(dir)
	if pp.length_squared() < 1e-6:
		pp = Vector3.UP
	return a + dir * x + pp.normalized() * h


## Called every frame with the physics body (bike.gd)
func sync(bike, delta: float) -> void:
	var fe: float = bike.front_ext
	var re: float = bike.rear_ext
	# wheel hubs follow suspension (rays are cast from local y = R + 0.12)
	var fh := Vector3(0, R + 0.12 - fe, -WB * 0.5)
	var rh := Vector3(0, R + 0.12 - re, WB * 0.5)
	var sa: float = bike.steer_angle
	front_wheel.transform = Transform3D(Basis(Vector3.UP, sa), fh)
	rear_wheel.position = rh
	var ang: float = -bike.wheel_spin_angle
	front_spin.rotation.x = ang
	rear_spin.rotation.x = ang
	# swingarm from pivot to rear hub
	var piv := swingarm.position
	var to_hub := rh - piv
	swingarm.rotation.x = -atan2(to_hub.y, to_hub.z)
	# forks from head stock to front hub; steering rotates about the head axis
	var head := Vector3(0, 1.0, -0.5)
	for k in 2:
		var sx := -0.1 if k == 0 else 0.1
		var top := head + Vector3(sx, 0, 0)
		var bot := fh + Vector3(sx, 0.02, 0)
		bot = Vector3(sx * cos(sa), bot.y, bot.z) + Vector3(0, 0, -sin(sa) * sx)
		var f: MeshInstance3D = fork_l if k == 0 else fork_r
		var d := top - bot
		var y := d.normalized()
		var x := Vector3.RIGHT.rotated(Vector3.UP, sa)
		var z := x.cross(y).normalized()
		x = y.cross(z).normalized()
		f.transform = Transform3D(Basis(x, y * d.length(), z), (top + bot) * 0.5)
	steer_node.transform = Transform3D(Basis(Vector3.UP, sa * 0.6), Vector3.ZERO)
	# brake light
	tail_mat.emission_energy_multiplier = 6.0 if bike.brake > 0.1 else 1.0
	_pose_rider(bike)


func _pose_rider(bike) -> void:
	var spd: float = absf(bike.speed)
	var tuck: float = clampf((spd - 12.0) / 30.0, 0.0, 1.0) * (1.0 - bike.brake * 0.7)
	var lean: float = bike.lean
	var hang: float = bike.rider_offset   # -1..1 (into the corner)
	var sa: float = bike.steer_angle
	if btype == "cruiser":
		tuck = 0.0
	elif btype == "naked":
		tuck *= 0.5
	var up_base := 0.75 if btype == "sport" else (0.45 if btype == "naked" else 0.12)
	var up_ang := lerpf(up_base, 1.32, tuck)      # torso angle from vertical
	var pelvis := Vector3(hang * 0.17, 1.12 if btype != "cruiser" else 0.98, (0.26 if btype != "cruiser" else 0.34) - tuck * 0.04)
	var shoulder_c := pelvis + Vector3(hang * 0.12, cos(up_ang) * 0.52, -sin(up_ang) * 0.52)
	var neck := shoulder_c + Vector3(hang * 0.05, 0.07, -0.05)
	var head_p := neck + Vector3(hang * 0.07, 0.13 - tuck * 0.03, -0.08 - tuck * 0.05)
	_place_bone("pelvis", pelvis + Vector3(-0.1, 0, 0), pelvis + Vector3(0.1, 0, 0))
	_place_bone("torso", pelvis + Vector3(0, 0.05, 0), shoulder_c)
	helmet.position = head_p
	helmet.rotation = Vector3(-(up_ang - 0.75) * 0.6 + 0.15, 0, -lean * 0.35 + hang * 0.25)
	for side in [-1.0, 1.0]:
		var sname := "l" if side < 0 else "r"
		var sh := shoulder_c + Vector3(side * 0.19, -0.02, 0)
		var grip := Vector3(side * 0.31, 1.07, -0.45)
		if btype == "naked":
			grip = Vector3(side * 0.38, 1.2, -0.4)
		elif btype == "cruiser":
			grip = Vector3(side * 0.5, 1.2, -0.3)
		var headp := Vector3(0, 1.0, -0.5)
		grip = headp + (grip - headp).rotated(Vector3.UP, sa * 0.6)
		var elbow := ik(sh, grip, 0.3, 0.3, Vector3(side * 0.6, -0.6, 0.3))
		_place_bone("ua_" + sname, sh, elbow)
		_place_bone("fa_" + sname, elbow, grip)
		var hip := pelvis + Vector3(side * 0.12, -0.02, 0)
		var peg := Vector3(side * 0.2, 0.5, 0.32) if btype != "cruiser" else Vector3(side * 0.3, 0.42, -0.35)
		var inside := 1.0 if signf(hang) == side and absf(hang) > 0.2 else 0.0
		var knee_pole := Vector3(side * (0.4 + inside * 0.9 * absf(hang)), 0.3, -1.0)
		var knee := ik(hip, peg + Vector3(0, 0.05, -0.02), 0.44, 0.44, knee_pole)
		_place_bone("th_" + sname, hip, knee)
		_place_bone("sh_" + sname, knee, peg + Vector3(0, 0.05, 0))
		_place_bone("ft_" + sname, peg + Vector3(0, 0.03, 0.06), peg + Vector3(0, 0.0, -0.13))
		pose["shoulder_" + sname] = sh
		pose["elbow_" + sname] = elbow
		pose["hand_" + sname] = grip
		pose["hip_" + sname] = hip
		pose["knee_" + sname] = knee
		pose["foot_" + sname] = peg
	pose["pelvis"] = pelvis
	pose["chest"] = shoulder_c
	pose["head"] = head_p


func set_rider_visible(v: bool) -> void:
	rider_root.visible = v
