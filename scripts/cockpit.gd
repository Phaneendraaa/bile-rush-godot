extends Node3D
## First-person rider view geometry: handlebars, gloved hands, switchgear, levers, mirrors,
## instruments (digital or analog) and the top of the tank. Built per bike type and attached
## to the bike body (bike-local coordinates: forward -Z, up +Y).

const Mats = preload("res://scripts/materials.gd")

var bike_type := "sport"
var bars: Node3D            # steers with the front wheel
var speed_lbl: Label3D
var gear_lbl: Label3D
var rpm_bar: MeshInstance3D
var needle: Node3D
var rpm_needle: Node3D
var mirror_vp: SubViewport
var mirror_cam: Camera3D
var mirror_mat: StandardMaterial3D
var eye := Vector3(0, 1.4, 0.12)
var head_axis_z := -0.5
var _rpm_bar_len := 0.16

const EYES := {"sport": Vector3(0, 1.36, 0.1), "naked": Vector3(0, 1.56, 0.12), "cruiser": Vector3(0, 1.5, 0.34)}


func build(type: String, paint: Material, glove_col: Color, sleeve_col: Color, live_mirrors: bool) -> void:
	bike_type = type
	eye = EYES.get(type, EYES["sport"])
	var dark := Mats.std(Color(0.05, 0.05, 0.055), 0.45, 0.3)
	var alu := Mats.std(Color(0.7, 0.72, 0.75), 0.25, 1.0)
	var chrome := Mats.std(Color(0.92, 0.92, 0.94), 0.05, 1.0)
	var rubber := Mats.std(Color(0.03, 0.03, 0.03), 0.85)
	rubber.normal_enabled = true
	rubber.normal_texture = Mats.noise_tex(201, 0.9, 2, 64, true, 6.0)
	var glove := Mats.std(glove_col, 0.55)
	var sleeve := Mats.std(sleeve_col, 0.6)
	var gold := Mats.std(Color(0.86, 0.66, 0.28), 0.2, 1.0)
	# mirror surface: live rear-view render on high settings, otherwise a reflective glass
	if live_mirrors:
		mirror_vp = SubViewport.new()
		mirror_vp.size = Vector2i(256, 112)
		mirror_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		mirror_vp.msaa_3d = Viewport.MSAA_DISABLED
		add_child(mirror_vp)
		mirror_cam = Camera3D.new()
		mirror_cam.fov = 38.0
		mirror_cam.far = 400.0
		mirror_vp.add_child(mirror_cam)
		mirror_mat = StandardMaterial3D.new()
		mirror_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mirror_mat.albedo_texture = mirror_vp.get_texture()
		mirror_mat.uv1_scale = Vector3(-1, 1, 1)
		mirror_mat.uv1_offset = Vector3(1, 0, 0)
	else:
		mirror_mat = Mats.std(Color(0.55, 0.58, 0.62), 0.02, 1.0)

	bars = Node3D.new()
	add_child(bars)
	match type:
		"cruiser":
			_build_cruiser(paint, chrome, rubber, dark, glove, sleeve)
		"naked":
			_build_naked(paint, alu, rubber, dark, glove, sleeve, gold)
		_:
			_build_sport(paint, alu, rubber, dark, glove, sleeve, gold)


# ------------------------------------------------------------------ primitives
func _mi(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


func _tube(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = a.distance_to(b)
	cm.radial_segments = 14
	cm.rings = 1
	var m := _mi(parent, cm, mat)
	var y := (b - a).normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	m.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	# rounded joint so bends look continuous
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	var j := _mi(parent, sm, mat)
	j.position = b
	return m


func _box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = sz
	var m := _mi(parent, bm, mat)
	m.position = pos
	m.rotation = rot
	return m


func _ell(parent: Node3D, radii: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 24
	sm.rings = 12
	var m := _mi(parent, sm, mat)
	m.position = pos
	m.rotation = rot
	m.scale = radii
	return m


## Grip with a gloved hand wrapped around it and the forearm running back toward the rider.
func _grip_and_hand(at: Vector3, axis: Vector3, side: float, rubber: Material, dark: Material, glove: Material, sleeve: Material) -> void:
	var ax := axis.normalized()
	_tube(bars, at - ax * 0.065, at + ax * 0.065, 0.019, rubber)
	_box(bars, Vector3(0.05, 0.045, 0.06), at - ax * 0.1 + Vector3(0, 0.005, 0), dark)        # switchgear
	# lever in front of the grip
	_tube(bars, at - ax * 0.08 + Vector3(0, 0.0, -0.04), at + ax * 0.06 + Vector3(0, -0.01, -0.07), 0.007, dark)
	# glove: knuckles over the top/front of the grip, fingers curling under
	var palm := _ell(bars, Vector3(0.05, 0.035, 0.055), at + Vector3(0, 0.03, 0.005), glove)
	palm.rotation = Vector3(0.2, 0, 0)
	for k in 4:
		var off := ax * (-0.045 + k * 0.03)
		_tube(bars, at + off + Vector3(0, 0.03, -0.03), at + off + Vector3(0, -0.012, -0.03), 0.011, glove)
	_tube(bars, at - ax * 0.05 + Vector3(0, 0.02, 0.03), at - ax * 0.07 + Vector3(0, 0.0, -0.02), 0.012, glove)  # thumb
	# knuckle armour plate
	_box(bars, Vector3(0.07, 0.012, 0.035), at + Vector3(0, 0.06, -0.005), Mats.std(Color(0.15, 0.15, 0.16), 0.3, 0.5), Vector3(0.3, 0, 0))
	# glove cuff and the start of the forearm; it drops out of view below the camera
	var wrist := at + Vector3(0, 0.03, 0.05)
	var elbow := Vector3(side * (absf(at.x) + 0.12), eye.y - 0.62, eye.z - 0.12)
	var cuff := wrist.lerp(elbow, 0.12)
	_tube(bars, wrist, cuff, 0.03, glove)
	_tube(bars, cuff, wrist.lerp(elbow, 0.45), 0.034, sleeve)


func _mirror(stalk_from: Vector3, head: Vector3, radii: Vector2, housing: Material, stalk_mat: Material) -> void:
	var parent: Node3D = bars if bike_type != "sport" else self
	_tube(parent, stalk_from, head, 0.008, stalk_mat)
	var turn := -signf(head.x) * 0.22   # angled slightly toward the rider
	_ell(parent, Vector3(radii.x, radii.y, 0.03), head, housing, Vector3(0.1, turn, 0))
	var face := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radii.x * 1.8, radii.y * 1.8)
	face.mesh = q
	face.material_override = mirror_mat
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	face.rotation = Vector3(0.1, turn, 0)
	face.position = head + Basis.from_euler(face.rotation) * Vector3(0, 0, 0.031)
	parent.add_child(face)


func _digital_dash(pos: Vector3, tilt: float, size: Vector2, screen_col: Color, text_col: Color, housing: Material) -> void:
	var dash := Node3D.new()
	dash.position = pos
	dash.rotation.x = tilt
	add_child(dash)
	_box(dash, Vector3(size.x + 0.03, size.y + 0.03, 0.04), Vector3(0, 0, 0.0), housing)
	var scr := StandardMaterial3D.new()
	scr.albedo_color = screen_col * 0.4
	scr.emission_enabled = true
	scr.emission = screen_col
	scr.emission_energy_multiplier = 0.35
	scr.roughness = 0.15
	_box(dash, Vector3(size.x, size.y, 0.005), Vector3(0, 0, 0.022), scr)
	speed_lbl = Label3D.new()
	speed_lbl.text = "0"
	speed_lbl.font_size = 96
	speed_lbl.pixel_size = size.y * 0.0042
	speed_lbl.modulate = text_col
	speed_lbl.outline_size = 0
	speed_lbl.position = Vector3(-size.x * 0.08, size.y * 0.05, 0.026)
	speed_lbl.shaded = false
	dash.add_child(speed_lbl)
	var kmh := Label3D.new()
	kmh.text = "km/h"
	kmh.font_size = 32
	kmh.pixel_size = size.y * 0.0042
	kmh.modulate = Color(text_col, 0.8)
	kmh.outline_size = 0
	kmh.position = Vector3(size.x * 0.22, -size.y * 0.12, 0.026)
	dash.add_child(kmh)
	gear_lbl = Label3D.new()
	gear_lbl.text = "1"
	gear_lbl.font_size = 72
	gear_lbl.pixel_size = size.y * 0.0042
	gear_lbl.modulate = Color(1.0, 0.75, 0.2)
	gear_lbl.outline_size = 0
	gear_lbl.position = Vector3(size.x * 0.34, size.y * 0.1, 0.026)
	dash.add_child(gear_lbl)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(1.0, 0.45, 0.1)
	rm.emission_enabled = true
	rm.emission = Color(1.0, 0.45, 0.1)
	rm.emission_energy_multiplier = 1.5
	_rpm_bar_len = size.x * 0.9
	rpm_bar = _box(dash, Vector3(_rpm_bar_len, size.y * 0.1, 0.004), Vector3(0, size.y * 0.36, 0.026), rm)


func _analog_dial(pos: Vector3, tilt: float, r: float, housing: Material) -> void:
	var dial := Node3D.new()
	dial.position = pos
	dial.rotation.x = tilt
	add_child(dial)
	var cm := CylinderMesh.new()
	cm.top_radius = r + 0.012
	cm.bottom_radius = r + 0.02
	cm.height = 0.05
	var bezel := _mi(dial, cm, housing)
	bezel.rotation.x = PI / 2
	var face_m := StandardMaterial3D.new()
	face_m.albedo_color = Color(0.05, 0.05, 0.06)
	face_m.roughness = 0.3
	var fm := CylinderMesh.new()
	fm.top_radius = r
	fm.bottom_radius = r
	fm.height = 0.004
	var face := _mi(dial, fm, face_m)
	face.rotation.x = PI / 2
	face.position.z = 0.026
	# ticks and numbers 0..220 km/h over 270 degrees
	var tick := Mats.std(Color(0.95, 0.95, 0.95), 0.5)
	for k in 12:
		var a := deg_to_rad(225.0 - k * 270.0 / 11.0)
		var p := Vector3(cos(a), sin(a), 0) * r * 0.86
		var t := _box(dial, Vector3(0.004, r * 0.14, 0.002), p + Vector3(0, 0, 0.029), tick)
		t.rotation.z = a - PI / 2
		if k % 2 == 0:
			var l := Label3D.new()
			l.text = str(k * 20)
			l.font_size = 40
			l.pixel_size = r * 0.0017
			l.outline_size = 0
			l.modulate = Color(0.95, 0.95, 0.95)
			l.position = Vector3(cos(a), sin(a), 0) * r * 0.62 + Vector3(0, 0, 0.03)
			dial.add_child(l)
	needle = Node3D.new()
	needle.position.z = 0.031
	dial.add_child(needle)
	var nm := StandardMaterial3D.new()
	nm.albedo_color = Color(1.0, 0.2, 0.05)
	nm.emission_enabled = true
	nm.emission = Color(1.0, 0.2, 0.05)
	nm.emission_energy_multiplier = 1.2
	_box(needle, Vector3(0.004, r * 0.85, 0.002), Vector3(0, r * 0.4, 0), nm)
	var hub := CylinderMesh.new()
	hub.top_radius = r * 0.08
	hub.bottom_radius = r * 0.08
	hub.height = 0.006
	var hb := _mi(dial, hub, housing)
	hb.rotation.x = PI / 2
	hb.position.z = 0.033
	gear_lbl = Label3D.new()
	gear_lbl.text = "1"
	gear_lbl.font_size = 48
	gear_lbl.pixel_size = r * 0.0018
	gear_lbl.outline_size = 0
	gear_lbl.modulate = Color(0.4, 1.0, 0.5)
	gear_lbl.position = Vector3(0, -r * 0.45, 0.03)
	dial.add_child(gear_lbl)


# ------------------------------------------------------------------ bike types
func _build_sport(paint: Material, alu: Material, rubber: Material, dark: Material, glove: Material, sleeve: Material, gold: Material) -> void:
	head_axis_z = -0.5
	# upper fairing, screen and TFT
	_ell(self, Vector3(0.27, 0.13, 0.24), Vector3(0, 1.02, -0.74), paint, Vector3(-0.15, 0, 0))
	var glass := Mats.std(Color(0.12, 0.14, 0.18, 0.4), 0.03)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_box(self, Vector3(0.36, 0.3, 0.006), Vector3(0, 1.2, -0.76), glass, Vector3(-0.85, 0, 0))
	_digital_dash(Vector3(0, 1.1, -0.64), -0.55, Vector2(0.15, 0.085), Color(0.08, 0.1, 0.14), Color(0.92, 0.96, 1.0), dark)
	# tank
	_ell(self, Vector3(0.23, 0.13, 0.32), Vector3(0, 0.98, -0.16), paint)
	_ell(self, Vector3(0.05, 0.012, 0.05), Vector3(0, 1.105, -0.26), alu)   # filler cap
	# triple clamp, fork caps, clip-ons
	_box(bars, Vector3(0.25, 0.025, 0.12), Vector3(0, 1.02, -0.5), alu)
	for sx in [-1.0, 1.0]:
		var cap := CylinderMesh.new()
		cap.top_radius = 0.026
		cap.bottom_radius = 0.026
		cap.height = 0.03
		_mi(bars, cap, gold).position = Vector3(sx * 0.105, 1.04, -0.5)
		var a := Vector3(sx * 0.105, 0.995, -0.49)
		var grip := Vector3(sx * 0.29, 0.975, -0.43)
		_tube(bars, a, grip - Vector3(sx * 0.065, 0, 0), 0.016, alu)
		_grip_and_hand(grip, Vector3(sx, -0.05, 0.25), sx, rubber, dark, glove, sleeve)
		_mirror(Vector3(sx * 0.22, 1.08, -0.68), Vector3(sx * 0.36, 1.13, -0.62), Vector2(0.07, 0.04), paint, dark)


func _build_naked(paint: Material, alu: Material, rubber: Material, dark: Material, glove: Material, sleeve: Material, gold: Material) -> void:
	head_axis_z = -0.48
	var lcd := Color(0.95, 0.35, 0.1)
	_digital_dash(Vector3(0, 1.2, -0.6), -0.7, Vector2(0.13, 0.06), Color(0.35, 0.08, 0.02), Color(1.0, 0.92, 0.85), dark)
	# small headlight cowl visible beyond the dash
	_ell(self, Vector3(0.12, 0.11, 0.1), Vector3(0, 1.08, -0.78), paint)
	_ell(self, Vector3(0.24, 0.13, 0.3), Vector3(0, 1.0, -0.14), paint)
	_ell(self, Vector3(0.05, 0.012, 0.05), Vector3(0, 1.125, -0.24), alu)
	_box(bars, Vector3(0.22, 0.03, 0.11), Vector3(0, 1.1, -0.5), alu)
	for sx in [-1.0, 1.0]:
		var cap := CylinderMesh.new()
		cap.top_radius = 0.024
		cap.bottom_radius = 0.024
		cap.height = 0.03
		_mi(bars, cap, gold).position = Vector3(sx * 0.1, 1.12, -0.5)
		# tapered bar: clamp -> rise -> sweep back
		var p0 := Vector3(sx * 0.05, 1.15, -0.5)
		var p1 := Vector3(sx * 0.2, 1.17, -0.48)
		var grip := Vector3(sx * 0.38, 1.2, -0.4)
		_tube(bars, p0, p1, 0.014, dark)
		_tube(bars, p1, grip - Vector3(sx * 0.065, 0, -0.015), 0.012, dark)
		_grip_and_hand(grip, Vector3(sx, 0.05, 0.22), sx, rubber, dark, glove, sleeve)
		_mirror(grip - Vector3(sx * 0.08, -0.02, 0.0), Vector3(sx * 0.43, 1.45, -0.46), Vector2(0.065, 0.065), dark, dark)


func _build_cruiser(paint: Material, chrome: Material, rubber: Material, dark: Material, glove: Material, sleeve: Material) -> void:
	head_axis_z = -0.62
	_ell(self, Vector3(0.16, 0.15, 0.13), Vector3(0, 0.98, -0.95), chrome)   # headlight bucket
	_analog_dial(Vector3(0, 1.12, -0.63), -0.75, 0.075, chrome)
	_ell(self, Vector3(0.26, 0.15, 0.38), Vector3(0, 0.95, -0.12), paint)    # teardrop tank
	_ell(self, Vector3(0.045, 0.012, 0.045), Vector3(0, 1.09, -0.22), chrome)
	for sx in [-1.0, 1.0]:
		var riser_b := Vector3(sx * 0.07, 1.02, -0.62)
		var riser_t := Vector3(sx * 0.07, 1.14, -0.6)
		var mid := Vector3(sx * 0.3, 1.16, -0.56)
		var grip := Vector3(sx * 0.5, 1.2, -0.3)
		_tube(bars, riser_b, riser_t, 0.022, chrome)
		_tube(bars, riser_t, mid, 0.016, chrome)
		_tube(bars, mid, grip - Vector3(sx * 0.05, 0, -0.05), 0.016, chrome)
		_grip_and_hand(grip, Vector3(sx * 0.6, 0.0, 0.6), sx, rubber, dark, glove, sleeve)
		_mirror(mid + Vector3(sx * 0.05, 0.01, 0), Vector3(sx * 0.4, 1.42, -0.55), Vector2(0.075, 0.05), chrome, chrome)


# ------------------------------------------------------------------ per frame
func sync(bike, active: bool) -> void:
	visible = active
	if mirror_vp:
		mirror_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if not active:
		return
	var sa: float = bike.steer_angle
	bars.transform = Transform3D(Basis(Vector3.UP, sa * 1.3), Vector3(0, 0, head_axis_z)) * Transform3D(Basis(), Vector3(0, 0, -head_axis_z))
	var kmh := absf(float(bike.speed)) * 3.6
	if speed_lbl:
		speed_lbl.text = str(int(round(kmh)))
	if gear_lbl:
		gear_lbl.text = str(int(bike.gear))
	if rpm_bar:
		var k := clampf(float(bike.rpm) / float(bike.redline), 0.02, 1.0)
		rpm_bar.scale.x = k
		rpm_bar.position.x = -_rpm_bar_len * 0.5 * (1.0 - k)
	if needle:
		needle.rotation.z = deg_to_rad(225.0 - clampf(kmh, 0.0, 220.0) / 220.0 * 270.0) - PI / 2
	if mirror_cam:
		var xf: Transform3D = (bike as Node3D).global_transform
		mirror_cam.global_transform = Transform3D(xf.basis.rotated(xf.basis.y, PI), xf * Vector3(0, eye.y - 0.05, eye.z - 0.4))
