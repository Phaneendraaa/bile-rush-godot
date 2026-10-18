extends Node3D
## Build 2: world showcase. A camera flies along the circuit; tap/click to switch track.
## Command-line modes (after `--`):
##   --autotest   headless: build every track, report timings, quit
##   --shots      render screenshots of every track into res://build/shots, quit

const TD = preload("res://scripts/track_data.gd")
const WorldBuilder = preload("res://scripts/world_builder.gd")

const QUALITY := {
	"glow": true, "shadows": true, "shadow_dist": 90.0, "terrain_seg": 120,
	"trees": 900, "tree_range": 700.0, "tree_shadows": true, "grass": 160, "grass_range": 70.0,
}

var track_idx := 0
var tr: TD
var world: Node3D
var cam: Camera3D
var s_cam := 0.0
var label: Label
var args := PackedStringArray()


func _ready() -> void:
	args = OS.get_cmdline_user_args()
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.1
	cam.far = 6000.0
	add_child(cam)
	cam.current = true
	_hud()
	if "--autotest" in args:
		_autotest()
		return
	if "--shots" in args:
		_shots()
		return
	_load_track(0)


func _hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	label = Label.new()
	label.position = Vector2(24, 18)
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 8)
	cl.add_child(label)


func _load_track(i: int) -> void:
	if world:
		world.queue_free()
		world = null
	track_idx = i
	tr = TD.new()
	tr.build(TD.DEFS[i])
	var wb = WorldBuilder.new()
	world = wb.build(tr, self, QUALITY)
	s_cam = 0.0
	label.text = "BIKE RUSH 3D  ·  %s   (tap to change track)" % TD.DEFS[i]["name"]


func _unhandled_input(e: InputEvent) -> void:
	var tap := (e is InputEventScreenTouch or e is InputEventMouseButton) and e.is_pressed()
	if tap and tr:
		_load_track((track_idx + 1) % TD.DEFS.size())


func _process(dt: float) -> void:
	if tr == null or "--shots" in args:
		return
	s_cam += dt * 38.0
	_place_camera(s_cam, sin(s_cam * 0.004) * 3.0, 1.4)


func _place_camera(s: float, d: float, h: float) -> void:
	var f: Dictionary = tr.frame(s, d)
	var ahead: Dictionary = tr.frame(s + 25.0, d * 0.8)
	var p: Vector3 = f["pos"]
	var target: Vector3 = ahead["pos"]
	cam.global_position = p + Vector3(0, h, 0)
	cam.look_at(target + Vector3(0, h * 0.7, 0), Vector3.UP)


# ------------------------------------------------------------------ CI modes
func _autotest() -> void:
	var ok := true
	for i in TD.DEFS.size():
		var t0 := Time.get_ticks_msec()
		tr = TD.new()
		tr.build(TD.DEFS[i])
		var t1 := Time.get_ticks_msec()
		var wb = WorldBuilder.new()
		var w: Node3D = wb.build(tr, self, QUALITY)
		var t2 := Time.get_ticks_msec()
		var meshes := w.find_children("*", "MeshInstance3D", true, false).size()
		var mms := w.find_children("*", "MultiMeshInstance3D", true, false).size()
		var shapes := w.find_children("*", "CollisionShape3D", true, false).size()
		print("TRACK %s L=%.0fm N=%d minR=%.0fm data=%dms world=%dms meshes=%d multimesh=%d shapes=%d" % [
			TD.DEFS[i]["id"], tr.L, tr.N, tr.min_radius, t1 - t0, t2 - t1, meshes, mms, shapes])
		if meshes < 5 or shapes < 3:
			ok = false
		w.free()
	print("AUTOTEST PASS" if ok else "AUTOTEST FAIL")
	get_tree().quit(0 if ok else 1)


func _shots() -> void:
	var dir := OS.get_environment("SHOTS_DIR")
	if dir == "":
		dir = OS.get_user_data_dir() + "/shots"
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().size = Vector2i(1280, 720)
	for i in TD.DEFS.size():
		_load_track(i)
		var views := [[0.0, 0.0, 1.4], [tr.L * 0.27, 2.5, 1.3], [tr.L * 0.55, -3.0, 6.0], [tr.L * 0.8, 0.0, 1.2]]
		for v in views.size():
			_place_camera(views[v][0], views[v][1], views[v][2])
			for _f in 45:
				await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			var path := "%s/%s_%d.png" % [dir, TD.DEFS[i]["id"], v]
			img.save_png(path)
			print("SHOT ", path)
	print("SHOTS DONE")
	get_tree().quit(0)
