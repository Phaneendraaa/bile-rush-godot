extends Node3D
## Bike Rush 3D — game controller: menu showroom, race flow, player & AI riders, crashes, HUD.
## Command-line modes (after `--`):
##   --autotest   headless: full AI race on every track (physics validation), quit
##   --shots      render screenshots (world + bikes) into $SHOTS_DIR, quit

const TD = preload("res://scripts/track_data.gd")
const WorldBuilder = preload("res://scripts/world_builder.gd")
const BikeScript = preload("res://scripts/bike.gd")
const BikeModel = preload("res://scripts/bike_model.gd")
const AIRider = preload("res://scripts/ai_rider.gd")
const CamScript = preload("res://scripts/cam.gd")
const UIScript = preload("res://scripts/ui.gd")
const EngineAudio = preload("res://scripts/engine_audio.gd")
const Ragdoll = preload("res://scripts/ragdoll.gd")
const FX = preload("res://scripts/fx.gd")
const Traffic = preload("res://scripts/traffic.gd")
const Cockpit = preload("res://scripts/cockpit.gd")
const BIKE_TYPES := ["sport", "naked", "cruiser"]

const COLORS := [
	Color(0.78, 0.06, 0.08), Color(0.08, 0.3, 0.85), Color(0.05, 0.55, 0.22), Color(0.95, 0.7, 0.05),
	Color(1.0, 0.38, 0.05), Color(0.42, 0.18, 0.8), Color(0.92, 0.92, 0.94), Color(0.06, 0.06, 0.07),
]
const SUITS := [
	Color(0.12, 0.12, 0.14), Color(0.9, 0.9, 0.92), Color(0.1, 0.14, 0.3), Color(0.15, 0.15, 0.15),
	Color(0.2, 0.12, 0.08), Color(0.92, 0.9, 0.85), Color(0.6, 0.06, 0.08), Color(0.85, 0.55, 0.05),
]
const NAMES := ["YOU", "Marco", "Kenji", "Lucas", "Aiden", "Rafa"]
const QUALITY := [
	{"glow": false, "shadows": false, "shadow_dist": 50.0, "terrain_seg": 90, "trees": 450, "tree_range": 450.0,
		"tree_shadows": false, "grass": 0, "grass_range": 40.0, "scale": 0.75, "msaa": 0},
	{"glow": true, "shadows": true, "shadow_dist": 70.0, "terrain_seg": 110, "trees": 800, "tree_range": 600.0,
		"tree_shadows": false, "grass": 110, "grass_range": 55.0, "scale": 0.9, "msaa": 1},
	{"glow": true, "shadows": true, "shadow_dist": 100.0, "terrain_seg": 140, "trees": 1100, "tree_range": 800.0,
		"tree_shadows": true, "grass": 180, "grass_range": 75.0, "scale": 1.0, "msaa": 2},
]
const DIFF := [
	{"pace": [0.88, 0.93], "margin": 0.66, "decel": 6.5},
	{"pace": [0.94, 0.99], "margin": 0.74, "decel": 7.0},
	{"pace": [0.99, 1.03], "margin": 0.82, "decel": 7.5},
]
const LAPS := [1, 3, 5]

var settings := {"mode": 0, "track": 0, "bike": 1, "color": 1, "difficulty": 1, "laps": 1, "steering": 0, "throttle": 0,
	"aids": 1, "graphics": 1, "sound": 0}
var args := PackedStringArray()
var autotest := false

var tr: TD
var world: Node3D
var builder
var loaded_key := ""
var cam
var ui
var audio
var bikes: Array = []          # Array of Dictionaries {body, model, ai, name, idx, finished, time, best, lap_start, ragdoll, respawn}
var player: Dictionary = {}
var state := "menu"
var countdown := 0.0
var race_time := 0.0
var finish_order: Array = []
var show_bike
var orbit := 0.0
var steer_in := 0.0
var last_lap_shown := 0
var finished_timer := 0.0
var traffic
var score := 0.0
var dist := 0.0
var near := 0
var combo_t := 0.0
var top_speed := 0.0
var wheelie_t := 0.0
var bonus_msg_t := 0.0


func _ready() -> void:
	args = OS.get_cmdline_user_args()
	autotest = "--autotest" in args
	_setup_input()
	cam = CamScript.new()
	cam.near = 0.08
	cam.far = 6000.0
	cam.fov = 62.0
	cam.doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(cam)
	cam.current = true
	if autotest:
		_run_autotest()
		return
	if "--shots" in args:
		_run_shots()
		return
	ui = UIScript.new()
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	audio = EngineAudio.new()
	add_child(audio)
	ui.build_menu(settings, _tracks(), COLORS)
	ui.build_hud()
	ui.build_pause()
	ui.build_results()
	ui.set_lights(0, false)
	ui.start_race.connect(_on_start)
	ui.resume.connect(func(): _set_paused(false))
	ui.restart.connect(_on_start)
	ui.quit_to_menu.connect(_go_menu)
	ui.next_track.connect(func():
		settings["track"] = (int(settings["track"]) + 1) % _tracks().size()
		_on_start())
	ui.pause_pressed.connect(func(): _set_paused(state != "paused"))
	ui.setting_changed.connect(_on_setting)
	ui.show_hud(false, false)
	ui.show_menu(false)
	ui.show_loading(true)
	await get_tree().process_frame
	await get_tree().process_frame
	audio.setup()
	_apply_graphics()
	_go_menu()


func _setup_input() -> void:
	var keys := {
		"left": [KEY_LEFT, KEY_A], "right": [KEY_RIGHT, KEY_D], "gas": [KEY_UP, KEY_W],
		"brake": [KEY_DOWN, KEY_S, KEY_SPACE], "cam": [KEY_C], "pause": [KEY_ESCAPE, KEY_P],
	}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		for k in keys[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)


# ------------------------------------------------------------------ world / settings
func _highway() -> bool:
	return int(settings["mode"]) < 2


func _tracks() -> Array:
	# traffic modes run on the same three environments as the circuit races
	return TD.DEFS


func _bike_type() -> String:
	return BIKE_TYPES[int(settings["bike"])]

func _quality() -> Dictionary:
	return QUALITY[int(settings["graphics"])]


func _apply_graphics() -> void:
	var q := _quality()
	var vp := get_viewport()
	vp.scaling_3d_scale = float(q["scale"])
	vp.msaa_3d = int(q["msaa"]) as Viewport.MSAA


func _ensure_world() -> void:
	var key := "%d|%d" % [int(settings["track"]), int(settings["graphics"])]
	if key == loaded_key and world != null:
		return
	_clear_bikes()
	if show_bike:
		show_bike.queue_free()
		show_bike = null
	if world:
		world.free()
		world = null
	tr = TD.new()
	var tl := _tracks()
	var def: Dictionary = (tl[clampi(int(settings["track"]), 0, tl.size() - 1)] as Dictionary).duplicate()
	def["two_way"] = int(settings["mode"]) == 0
	tr.build(def)
	builder = WorldBuilder.new()
	world = builder.build(tr, self, _quality())
	loaded_key = key
	if ui:
		var pts := PackedVector2Array()
		var b: Rect2 = tr.bounds
		var sz := maxf(b.size.x, b.size.y)
		for i in range(0, tr.N, 6):
			pts.append(Vector2((b.end.x - tr.X[i]) / sz + (sz - b.size.x) / sz * 0.5 - 0.0, (tr.Z[i] - b.position.y) / sz + (sz - b.size.y) / sz * 0.5))
		ui.set_minimap(pts)


func _mini_pos(p: Vector3) -> Vector2:
	var b: Rect2 = tr.bounds
	var sz := maxf(b.size.x, b.size.y)
	return Vector2((b.end.x - p.x) / sz + (sz - b.size.x) / sz * 0.5, (p.z - b.position.y) / sz + (sz - b.size.y) / sz * 0.5)


func _on_setting(key: String, value: int) -> void:
	if key == "sound":
		audio.muted = value == 1
	if state != "menu":
		return
	if key == "mode":
		ui.rebuild_menu(settings, _tracks(), COLORS)
	if key == "graphics":
		_apply_graphics()
	if key == "track" or key == "graphics" or key == "color" or key == "mode" or key == "bike":
		ui.show_loading(true)
		await get_tree().process_frame
		await get_tree().process_frame
		_ensure_world()
		_showroom()
		ui.show_loading(false)


func _aids() -> Dictionary:
	match int(settings["aids"]):
		0:
			return {"abs": true, "tc": true, "wheelie": true, "lean_limit": true}
		1:
			return {"abs": true, "tc": true, "wheelie": true, "lean_limit": true}
	return {"abs": false, "tc": false, "wheelie": false, "lean_limit": false}


# ------------------------------------------------------------------ bikes
func _make_bike(idx: int, color_idx: int, s: float, d: float, is_player: bool) -> Dictionary:
	var body = BikeScript.new()
	body.name = "Bike%d" % idx
	body.set("track", tr)
	add_child(body)
	var btype := _bike_type() if is_player else "sport"
	body.set_type(btype)
	var model = BikeModel.new()
	body.add_child(model)
	model.build(COLORS[color_idx], SUITS[color_idx], idx + 1 if not is_player else 7, btype)
	body.place(s, d, 0.0)
	var entry := {
		"body": body, "model": model, "ai": null, "name": NAMES[idx] if idx < NAMES.size() else "Rider",
		"idx": idx, "color": COLORS[color_idx], "player": is_player, "finished": false, "time": 0.0,
		"best": 1e9, "lap_start": 0.0, "laps_done": 0, "ragdoll": null, "crash_t": 0.0, "voice": null,
		"cockpit": null,
	}
	if is_player and not autotest:
		var ck = Cockpit.new()
		body.add_child(ck)
		var suit_c: Color = SUITS[color_idx]
		var glove_c := Color(0.07, 0.07, 0.08)
		ck.build(btype, model.get("paint"), glove_c, suit_c.darkened(0.25), int(settings["graphics"]) == 2)
		entry["cockpit"] = ck
		cam.eye = ck.eye
	if not is_player or autotest:
		var ai = AIRider.new()
		var dd: Dictionary = DIFF[int(settings["difficulty"])]
		var pace: Array = dd["pace"]
		ai.skill = lerpf(float(pace[1]), float(pace[0]), float(idx % 6) / 5.0)
		ai.corner_margin = float(dd["margin"])
		ai.brake_decel = float(dd["decel"])
		ai.lane_bias = (float(idx % 3) - 1.0) * 1.2
		entry["ai"] = ai
	body.set("aids", _aids() if is_player else {"abs": true, "tc": true, "wheelie": true, "lean_limit": true})
	body.connect("crashed", _on_crashed)
	if not autotest:
		var smoke := FX.emitter("smoke")
		var dust := FX.emitter("dust")
		for e in [smoke, dust]:
			body.add_child(e)
			e.position = Vector3(0, 0.12, 0.72)
		entry["smoke"] = smoke
		entry["dust"] = dust
	if not is_player and not autotest:
		var v: AudioStreamPlayer3D = EngineAudio.rival_player()
		body.add_child(v)
		v.position = Vector3(0, 0.6, 0.4)
		v.play()
		entry["voice"] = v
	return entry


func _start_traffic() -> void:
	if traffic:
		traffic.queue_free()
	traffic = Traffic.new()
	traffic.audio_on = not autotest and (audio == null or not audio.muted)
	add_child(traffic)
	var counts := [14, 20, 26]
	traffic.setup(tr, int(settings["mode"]) == 0, counts[int(settings["graphics"])])
	traffic.populate(float(player["body"].get("progress")))
	traffic.near_miss.connect(_on_near_miss)
	score = 0.0
	dist = 0.0
	near = 0
	top_speed = 0.0
	wheelie_t = 0.0


func _stop_traffic() -> void:
	if traffic:
		traffic.queue_free()
		traffic = null


func _on_near_miss(_kind, oncoming) -> void:
	if state != "race":
		return
	near += 1
	combo_t = 3.0
	var pts := 500 if oncoming else 300
	score += pts
	if ui:
		ui.message("NEAR MISS  +%d" % pts, 1.0)


func _clear_bikes() -> void:
	for b in bikes:
		if b["ragdoll"] != null and is_instance_valid(b["ragdoll"]):
			b["ragdoll"].queue_free()
		var body: Node = b["body"]
		if is_instance_valid(body):
			body.queue_free()
	bikes.clear()
	player = {}
	_stop_traffic()


func _spawn_grid() -> void:
	_clear_bikes()
	if _highway() and not autotest:
		var e := _make_bike(0, int(settings["color"]), 20.0, 1.75, true)
		e["name"] = "YOU"
		bikes.append(e)
		player = e
		_start_traffic()
		return
	var others: Array = []
	for i in COLORS.size():
		if i != int(settings["color"]):
			others.append(i)
	var n := 6
	for i in n:
		var row := i / 2
		var s := -9.0 - row * 9.0
		var d := -3.0 if i % 2 == 0 else 3.0
		var is_player := i == n - 1 and not autotest
		var col: int = int(settings["color"]) if is_player else int(others[(i * 3 + int(settings["track"])) % others.size()])
		var e := _make_bike(i, col, s, d, is_player)
		bikes.append(e)
		if is_player:
			player = e
	if player.is_empty():
		player = bikes[bikes.size() - 1]


func _set_frozen(on: bool) -> void:
	for b in bikes:
		var body: RigidBody3D = b["body"]
		body.freeze = on


# ------------------------------------------------------------------ flow
func _showroom() -> void:
	_clear_bikes()
	if show_bike:
		show_bike.queue_free()
	var f: Dictionary = tr.frame(-12.0 if not _highway() else 30.0, 0.0 if not _highway() else 1.75)
	show_bike = BikeModel.new()
	add_child(show_bike)
	show_bike.build(COLORS[int(settings["color"])], SUITS[int(settings["color"])], 7, _bike_type())
	var fwd: Vector3 = f["fwd"]
	show_bike.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), f["pos"])
	# park it on its suspension, slight lean onto the side stand
	var fake := {"front_ext": 0.13, "rear_ext": 0.13, "steer_angle": 0.25, "wheel_spin_angle": 0.0,
		"brake": 0.0, "speed": 0.0, "lean": 0.0, "rider_offset": 0.0}
	show_bike.sync(fake, 0.0)
	show_bike.rotate_object_local(Vector3.FORWARD, -0.05)
	cam.target = null


func _go_menu() -> void:
	get_tree().paused = false
	state = "menu"
	audio.silence()
	ui.show_loading(true)
	ui.show_hud(false, false)
	ui.show_pause(false)
	ui.hide_results()
	await get_tree().process_frame
	await get_tree().process_frame
	_ensure_world()
	_showroom()
	ui.show_loading(false)
	ui.show_menu(true)


func _on_start() -> void:
	get_tree().paused = false
	ui.show_menu(false)
	ui.show_pause(false)
	ui.hide_results()
	ui.show_loading(true, "Preparing race…")
	await get_tree().process_frame
	await get_tree().process_frame
	_ensure_world()
	if show_bike:
		show_bike.queue_free()
		show_bike = null
	_spawn_grid()
	_set_frozen(true)
	cam.target = player["body"]
	cam.mode = 0
	cam.snap()
	race_time = 0.0
	finish_order.clear()
	countdown = 5.6
	state = "countdown"
	ui.set_hud_titles(["SCORE", "DISTANCE", "TIME", "NEAR MISS"] if _highway() else ["POS", "LAP", "TIME", "BEST"])
	last_lap_shown = 0
	ui.show_loading(false)
	ui.show_hud(true, int(settings["steering"]) > 0)
	ui.set_lights(0, true)


func _set_paused(on: bool) -> void:
	if state == "finished" or state == "menu":
		return
	get_tree().paused = on
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	ui.show_pause(on)
	if on:
		audio.silence()
		state = "paused"
	else:
		state = "race" if countdown <= 0.0 else "countdown"


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if state == "race" or state == "countdown":
			_set_paused(true)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if state == "race" or state == "countdown":
			_set_paused(true)
		elif state == "paused":
			_set_paused(false)
		elif state == "finished":
			_go_menu()
		else:
			get_tree().quit()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		_set_paused(state != "paused")


# ------------------------------------------------------------------ per-frame
func _physics_process(dt: float) -> void:
	if bikes.is_empty() or state == "menu" or state == "paused":
		return
	var running := state == "race" or state == "finished"
	var bodies: Array = []
	for b in bikes:
		bodies.append(b["body"])
	for b in bikes:
		var body: RigidBody3D = b["body"]
		if bool(body.get("is_crashed")):
			body.set("throttle", 0.0)
			body.set("brake", 0.3)
			continue
		if b["ai"] != null or b["finished"]:
			var ai = b["ai"]
			if ai == null:
				ai = AIRider.new()
				ai.skill = 0.8
				b["ai"] = ai
			if traffic and b == player:
				ai.cars = traffic.cars
				ai.lanes = traffic.lanes_same if not traffic.two_way else [1.75, 5.25, -1.75]
			var cmd: Array = ai.drive(body, tr, bodies, dt)
			body.set("steer", cmd[0])
			body.set("throttle", cmd[1] if running else 0.0)
			body.set("brake", cmd[2] if running else 1.0)
			if b["finished"] and not autotest:
				body.set("throttle", minf(float(cmd[1]), 0.35))
		else:
			_player_controls(b, dt, running)
	if traffic and not player.is_empty():
		var pb: RigidBody3D = player["body"]
		traffic.update(dt, float(pb.get("progress")), float(pb.get("lateral")), maxf(float(pb.get("speed")), 0.0))
	# rubber-banding: keep the pack close to the player
	if running and not autotest and not player.is_empty():
		var pp: float = player["body"].get("progress")
		for b in bikes:
			if b["ai"] == null or b["player"]:
				continue
			var ai = b["ai"]
			var base: float = ai.get_meta("base_skill", ai.skill)
			ai.set_meta("base_skill", base)
			var gap: float = (pp - float(b["body"].get("progress"))) / tr.L
			ai.skill = base * (1.0 + clampf(gap * 0.25, -0.05, 0.07))


func _player_controls(b: Dictionary, dt: float, running: bool) -> void:
	var body: RigidBody3D = b["body"]
	var want := 0.0
	var steer_mode := int(settings["steering"])
	if steer_mode == 0:
		want = Input.get_action_strength("right") - Input.get_action_strength("left")
	else:
		var g := Input.get_gravity()
		var t := clampf(g.x / 4.5, -1.0, 1.0)
		if steer_mode == 2:
			t = -t
		want = t
		var kb := Input.get_action_strength("right") - Input.get_action_strength("left")
		if absf(kb) > 0.1:
			want = kb
	# lean builds up while a button is held, returns when released
	var rate := 3.2 if absf(want) > absf(steer_in) else 4.5
	steer_in = move_toward(steer_in, want, rate * dt)
	var steer := steer_in
	# full assist: lane keeping when no steering input
	if int(settings["aids"]) == 0:
		if not b.has("helper"):
			b["helper"] = AIRider.new()
		var helper = b["helper"]
		var lat: float = body.get("lateral")
		var keep: float = helper.pursuit_steer(body, tr, clampf(lat, -TD.ROAD_HALF + 1.0, TD.ROAD_HALF - 1.0))
		steer = clampf(steer + keep * (1.0 - absf(steer)), -1.0, 1.0)
	body.set("steer", steer)
	var gas := Input.get_action_strength("gas")
	var brk := Input.get_action_strength("brake")
	if int(settings["throttle"]) == 1 and brk < 0.1:
		gas = maxf(gas, 1.0)
	body.set("throttle", gas if running else 0.0)
	body.set("brake", brk if running else 1.0)
	body.set("tuck", 1.0 if brk < 0.2 else 0.3)
	if not running:
		# rev on the grid
		body.set("rpm", lerpf(float(body.get("rpm")), 1600.0 + gas * 9000.0, clampf(dt * 6.0, 0.0, 1.0)))
		body.set("throttle", gas)


func _process(dt: float) -> void:
	if autotest:
		return
	if state == "menu":
		audio.silence()
		_menu_camera(dt)
		return
	if bikes.is_empty():
		return
	if Input.is_action_just_pressed("cam") and cam.target != null:
		cam.cycle()
		ui.message(cam.mode_name(), 0.9)
	if state == "countdown":
		countdown -= dt
		var lit := clampi(int((5.6 - countdown) / 0.9), 0, 5)
		if countdown > 0.6:
			if lit != int(get_meta("lit", -1)):
				set_meta("lit", lit)
				if lit > 0:
					audio.beep(520.0, 0.18)
			ui.set_lights(lit, true)
		else:
			state = "race"
			ui.set_lights(0, false)
			ui.message("GO!", 1.0)
			audio.beep(980.0, 0.4)
			_set_frozen(false)
			for b in bikes:
				b["lap_start"] = 0.0
	if state == "race" or state == "finished":
		race_time += dt
	_update_bikes_visual(dt)
	_race_logic(dt)
	if _highway() and not player.is_empty():
		_highway_tick(dt)
	_update_hud()
	if not player.is_empty():
		var pb: RigidBody3D = player["body"]
		audio.update(pb, state == "race" or state == "countdown" or (state == "finished" and finished_timer < 2.5))
		if bool(pb.get("is_crashed")):
			cam.shake = maxf(cam.shake, 0.0)


func _menu_camera(dt: float) -> void:
	if show_bike == null:
		return
	orbit += dt * 0.16
	var p: Vector3 = show_bike.global_position
	var r := 5.2
	cam.global_position = p + Vector3(cos(orbit) * r, 1.5 + sin(orbit * 0.6) * 0.35, sin(orbit) * r)
	cam.look_at(p + Vector3(0, 0.75, 0), Vector3.UP)
	# frame the bike in the gap between the title column and the settings panel
	var right: Vector3 = cam.global_basis.x
	cam.look_at(p + Vector3(0, 0.75, 0) + right * 1.1, Vector3.UP)
	cam.fov = 50.0


func _update_bikes_visual(dt: float) -> void:
	for b in bikes:
		var body: RigidBody3D = b["body"]
		var model = b["model"]
		model.sync(body, dt)
		if b == player:
			var crashed_: bool = body.get("is_crashed")
			var m: int = cam.mode
			var in_cockpit := (m == 0 or m == 4) and not crashed_
			model.visible = not in_cockpit
			if not crashed_:
				model.set_rider_visible(m != 1)
			if b["cockpit"] != null:
				b["cockpit"].sync(body, m == 0 and not crashed_)
		if b.has("smoke"):
			var spd := absf(float(body.get("speed")))
			var slide := maxf(float(body.get("rear_slide")), float(body.get("front_slide")))
			var spin: float = body.get("wheelspin")
			var grounded: bool = body.get("on_ground")
			var crashed: bool = body.get("is_crashed")
			var on_grass: bool = str(body.get("surface")) == "grass"
			var sm: GPUParticles3D = b["smoke"]
			var du: GPUParticles3D = b["dust"]
			sm.emitting = grounded and not on_grass and (spin > 0.15 or (slide > 0.2 and spd > 6.0) or (crashed and spd > 4.0))
			du.emitting = (grounded or crashed) and on_grass and spd > 4.0
		if b["voice"] != null:
			var v: AudioStreamPlayer3D = b["voice"]
			v.pitch_scale = clampf(float(body.get("rpm")) / EngineAudio.RPM_AT_F0, 0.25, 2.3)
			v.volume_db = -2.0 if not audio.muted else -80.0


func _race_logic(dt: float) -> void:
	var laps: int = LAPS[int(settings["laps"])]
	for b in bikes:
		var body: RigidBody3D = b["body"]
		var prog: float = body.get("progress")
		# crash & respawn (traffic modes: a crash ends the run)
		if bool(body.get("is_crashed")) and _highway() and not autotest:
			continue
		if bool(body.get("is_crashed")):
			b["crash_t"] = float(b["crash_t"]) + dt
			if float(b["crash_t"]) > 3.2:
				_respawn(b)
			continue
		if state != "race" and state != "finished":
			continue
		if _highway() and not autotest:
			continue
		var done := int(floorf(prog / tr.L))
		if done > int(b["laps_done"]) and done >= 1:
			var lt := race_time - float(b["lap_start"])
			b["best"] = minf(float(b["best"]), lt)
			b["lap_start"] = race_time
			b["laps_done"] = done
			if b == player and done < laps and not autotest:
				ui.message("FINAL LAP" if done == laps - 1 else "LAP %d / %d" % [done + 1, laps], 1.8)
				audio.beep(1200.0, 0.12)
			if done >= laps and not b["finished"]:
				b["finished"] = true
				b["time"] = race_time
				finish_order.append(b)
				if b == player and not autotest:
					_player_finished()
	if state == "finished" and not autotest:
		finished_timer += dt
		if finished_timer > 2.5 and finished_timer - dt <= 2.5:
			_show_results()


func _respawn(b: Dictionary) -> void:
	var body = b["body"]
	var prog: float = body.get("progress")
	var lat: float = clampf(float(body.get("lateral")), -TD.ROAD_HALF + 1.5, TD.ROAD_HALF - 1.5)
	body.place(prog, lat, 8.0)
	b["crash_t"] = 0.0
	var model = b["model"]
	model.set_rider_visible(true)
	if b["ragdoll"] != null and is_instance_valid(b["ragdoll"]):
		b["ragdoll"].queue_free()
	b["ragdoll"] = null
	if b == player:
		cam.snap()


func _on_crashed(body) -> void:
	for b in bikes:
		if b["body"] == body:
			var model = b["model"]
			model.set_rider_visible(false)
			if b["ragdoll"] != null and is_instance_valid(b["ragdoll"]):
				b["ragdoll"].queue_free()
			var rd = Ragdoll.new()
			add_child(rd)
			rd.spawn(model, (body as RigidBody3D).linear_velocity, model.get("suit"), BikeModel.shared()["leather"], model.get("paint"))
			b["ragdoll"] = rd
			if b == player and not autotest:
				audio.play_crash()
				cam.shake = 1.0
				ui.message("CRASH!", 1.6)
				if _highway() and state == "race":
					state = "finished"
					finished_timer = 0.0
			if autotest:
				print("  crash: %s reason=%s v=%.0fkm/h lean=%.0f° s=%.0f lat=%.1f" % [b["name"], str(body.get_meta("crash_reason", "?")),
					float(body.get("speed")) * 3.6, rad_to_deg(float(body.get("lean"))), float(body.get("progress")), float(body.get("lateral"))])
			return


func _positions() -> Array:
	var arr := bikes.duplicate()
	arr.sort_custom(func(a, c):
		if a["finished"] and c["finished"]:
			return float(a["time"]) < float(c["time"])
		if a["finished"] != c["finished"]:
			return bool(a["finished"])
		return float(a["body"].get("progress")) > float(c["body"].get("progress")))
	return arr


func _player_finished() -> void:
	state = "finished"
	finished_timer = 0.0
	var pos := finish_order.find(player) + 1
	ui.message("WINNER!" if pos == 1 else "%s PLACE" % _ord(pos), 2.4)
	audio.beep(1500.0 if pos == 1 else 700.0, 0.6)


func _show_results() -> void:
	if _highway():
		var rows: Array = [["", "", "", "", false],
			["SCORE", str(int(score)), "", "", true],
			["DISTANCE", "%.2f km" % (dist / 1000.0), "TIME", UIScript.fmt_time(race_time), false],
			["NEAR MISSES", str(near), "TOP SPEED", "%d km/h" % int(top_speed * 3.6), false]]
		ui.show_results("GAME OVER", rows)
		return
	var order := _positions()
	var pos := order.find(player) + 1
	var rows: Array = [["POS", "RIDER", "TIME", "BEST LAP", false]]
	var laps: int = LAPS[int(settings["laps"])]
	for i in order.size():
		var b: Dictionary = order[i]
		var t := UIScript.fmt_time(float(b["time"])) if b["finished"] else "+%d m" % int(laps * tr.L - float(b["body"].get("progress")))
		rows.append([str(i + 1), b["name"], t, UIScript.fmt_time(float(b["best"])) if float(b["best"]) < 1e8 else "--", b == player])
	ui.show_results(("🏆 " if pos == 1 else "") + "%s PLACE" % _ord(pos), rows)


static func _ord(n: int) -> String:
	if n == 1:
		return "1st"
	if n == 2:
		return "2nd"
	if n == 3:
		return "3rd"
	return "%dth" % n


func _highway_tick(dt: float) -> void:
	var pb: RigidBody3D = player["body"]
	var v := maxf(float(pb.get("speed")), 0.0)
	if state != "race" or bool(pb.get("is_crashed")):
		return
	top_speed = maxf(top_speed, v)
	dist += v * dt
	var lat: float = pb.get("lateral")
	var opposite := int(settings["mode"]) == 0 and lat < 0.0
	var mult := 1.0
	if v > 27.8:
		mult += 0.5
	if opposite and v > 13.9:
		mult *= 2.0
	score += v * dt * 0.5 * mult
	# wheelie bonus
	if float(pb.get("pitch")) > deg_to_rad(9.0) and v > 8.0:
		wheelie_t += dt
		score += 120.0 * dt
		if wheelie_t > 0.6 and bonus_msg_t <= 0.0:
			ui.message("WHEELIE!", 0.8)
			bonus_msg_t = 1.5
	else:
		wheelie_t = 0.0
	bonus_msg_t = maxf(0.0, bonus_msg_t - dt)
	if opposite and v > 13.9 and bonus_msg_t <= 0.0 and randf() < dt * 0.3:
		ui.message("OPPOSITE LANE  x2", 1.0)
		bonus_msg_t = 3.0


func _update_hud() -> void:
	if player.is_empty() or ui == null:
		return
	var pb: RigidBody3D = player["body"]
	if _highway():
		var hd := []
		hd.append([_mini_pos(pb.global_position), player["color"], true])
		if traffic:
			for c in traffic.cars:
				var n: Node3D = c["node"]
				if absf(float(c["s"]) - float(pb.get("progress"))) < 600.0:
					hd.append([_mini_pos(n.global_position), Color(0.85, 0.85, 0.85) if not c["onc"] else Color(1.0, 0.5, 0.3), false])
		ui.update_hud_highway({"score": score, "dist": dist, "time": race_time, "near": near,
			"speed": absf(float(pb.get("speed"))), "gear": int(pb.get("gear")), "rpm": float(pb.get("rpm")),
			"redline": float(pb.get("redline")), "tc": bool(pb.get("tc_active")), "abs": bool(pb.get("abs_active")),
			"slide": float(pb.get("front_slide")) > 0.05 or float(pb.get("rear_slide")) > 0.05, "dots": hd})
		return
	var order := _positions()
	var dots: Array = []
	for b in bikes:
		var body: RigidBody3D = b["body"]
		dots.append([_mini_pos(body.global_position), b["color"], b == player])
	var laps: int = LAPS[int(settings["laps"])]
	ui.update_hud({
		"pos": order.find(player) + 1, "count": bikes.size(),
		"lap": clampi(int(player["laps_done"]) + 1, 1, laps), "laps": laps,
		"time": race_time, "best": float(player["best"]),
		"speed": absf(float(pb.get("speed"))), "gear": int(pb.get("gear")), "rpm": float(pb.get("rpm")),
		"tc": bool(pb.get("tc_active")), "abs": bool(pb.get("abs_active")),
		"slide": float(pb.get("front_slide")) > 0.05 or float(pb.get("rear_slide")) > 0.05,
		"dots": dots,
	})


# ------------------------------------------------------------------ CI: headless race
func _run_autotest() -> void:
	var ok := true
	settings["mode"] = 2
	# audio: loops must be silent outside a race (menu / loading / pause)
	audio = EngineAudio.new()
	add_child(audio)
	audio.setup()
	var silent_start: bool = audio.is_silent()
	audio.update({"rpm": 8000.0, "throttle": 1.0, "speed": 30.0, "front_slide": 0.0, "rear_slide": 0.0,
		"wheelspin": 0.0, "on_ground": true, "is_crashed": false}, false)
	var silent_inactive: bool = audio.is_silent()
	audio.update({"rpm": 8000.0, "throttle": 1.0, "speed": 30.0, "front_slide": 0.0, "rear_slide": 0.0,
		"wheelspin": 0.0, "on_ground": true, "is_crashed": false}, true)
	var audible_racing: bool = not audio.is_silent()
	audio.silence()
	print("AUDIO silent_at_start=%s silent_when_inactive=%s audible_when_racing=%s silent_after_silence=%s" % [
		silent_start, silent_inactive, audible_racing, audio.is_silent()])
	if not (silent_start and silent_inactive and audible_racing and audio.is_silent()):
		ok = false
	audio.queue_free()
	audio = null
	if not await _test_controls_and_traffic():
		ok = false
	settings["laps"] = 0
	for ti in TD.DEFS.size():
		settings["track"] = ti
		loaded_key = ""
		var t0 := Time.get_ticks_msec()
		_ensure_world()
		print("TRACK %s L=%.0fm minR=%.0fm built in %dms" % [TD.DEFS[ti]["id"], tr.L, tr.min_radius, Time.get_ticks_msec() - t0])
		_spawn_grid()
		state = "race"
		countdown = 0.0
		race_time = 0.0
		finish_order.clear()
		var counter := {"n": 0}
		var crash_cb := func(_b): counter["n"] += 1
		for b in bikes:
			b["body"].connect("crashed", crash_cb)
		var sim := 0.0
		var next_log := 0.0
		var max_t := tr.L / 22.0 + 60.0
		while sim < max_t:
			await get_tree().physics_frame
			sim += 1.0 / 120.0
			race_time = sim
			_race_logic(1.0 / 120.0)
			if ti == 0 and sim < 70.0 and int(sim * 120.0) % 30 == 0:
				var mb = bikes[1]["body"]
				var ai = bikes[1]["ai"]
				print("  TRACE t=%.2f s=%.0f k=%.4f v=%.1f vt=%.1f steer=%.2f leanT=%.1f lean=%.1f lat=%.2f fs=%.2f rs=%.2f surf=%s thr=%.2f brk=%.2f" % [
					sim, float(mb.progress), tr.curv_at(float(mb.progress)), float(mb.speed),
					AIRider.target_speed(mb, tr, ai.corner_margin, ai.skill, ai.brake_decel), float(mb.steer),
					rad_to_deg(float(mb.lean_target)), rad_to_deg(float(mb.lean)), float(mb.lateral),
					float(mb.front_slide), float(mb.rear_slide), str(mb.surface), float(mb.throttle), float(mb.brake)])
			if sim >= next_log:
				next_log += 10.0
				var line := "  t=%3.0fs" % sim
				for b in bikes:
					var body: RigidBody3D = b["body"]
					line += " | %s %.0fm %3.0fkm/h g%d lean%3.0f" % [b["name"], float(body.get("progress")),
						float(body.get("speed")) * 3.6, int(body.get("gear")), rad_to_deg(float(body.get("lean")))]
				print(line)
			if finish_order.size() == bikes.size():
				break
		var fin := finish_order.size()
		var res := ""
		for b in finish_order:
			res += "%s %.1fs  " % [b["name"], float(b["time"])]
		print("RESULT %s finished=%d/%d crashes=%d  %s" % [TD.DEFS[ti]["id"], fin, bikes.size(), counter["n"], res])
		if fin < 4:
			ok = false
		_clear_bikes()
		await get_tree().physics_frame
	print("AUTOTEST PASS" if ok else "AUTOTEST FAIL")
	get_tree().quit(0 if ok else 1)


## Touch controls + manual riding + highway traffic, exactly as on a phone.
func _test_controls_and_traffic() -> bool:
	var ok := true
	ui = UIScript.new()
	add_child(ui)
	ui.build_menu(settings, _tracks(), COLORS)
	ui.build_hud()
	ui.build_pause()
	ui.build_results()
	ui.show_menu(false)
	ui.show_loading(false)
	ui.show_hud(true, false)
	await get_tree().process_frame
	# 1) every on-screen button must drive its input action when touched
	for act in ["left", "right", "gas", "brake"]:
		var centre: Vector2 = ui.button_centre(act)
		# events arrive in window pixels; map from canvas coordinates
		centre = get_viewport().get_final_transform() * centre
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.position = centre
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame
		var pressed := Input.is_action_pressed(act)
		ev = ev.duplicate()
		ev.pressed = false
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame
		var released := not Input.is_action_pressed(act)
		print("TOUCH %s at %s -> pressed=%s released=%s" % [act, str(centre), pressed, released])
		if not (pressed and released):
			ok = false
	# 2) highway run with the player's bike under manual control
	settings["mode"] = 0
	settings["track"] = 0
	settings["aids"] = 1
	settings["throttle"] = 0
	loaded_key = ""
	_ensure_world()
	autotest = false
	var e := _make_bike(0, 1, 20.0, 1.75, true)
	autotest = true
	bikes.append(e)
	player = e
	_start_traffic()
	print("TRAFFIC cars=%d two_way=%s" % [traffic.cars.size(), str(traffic.two_way)])
	state = "race"
	var pb: RigidBody3D = player["body"]
	var t := 0.0
	while t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 120.0
	var v_idle := absf(float(pb.get("speed")))
	print("CONTROL no input for 3s: speed=%.2f m/s (must stay ~0, no self-driving)" % v_idle)
	if v_idle > 1.0:
		ok = false
	Input.action_press("gas")
	t = 0.0
	while t < 6.0:
		await get_tree().physics_frame
		t += 1.0 / 120.0
	var v_gas := float(pb.get("speed"))
	print("CONTROL gas 6s: speed=%.1f km/h gear=%d" % [v_gas * 3.6, int(pb.get("gear"))])
	if v_gas < 15.0:
		ok = false
	var lat0: float = pb.get("lateral")
	Input.action_press("right")
	t = 0.0
	while t < 0.9:
		await get_tree().physics_frame
		t += 1.0 / 120.0
	Input.action_release("right")
	t = 0.0
	while t < 1.2:
		await get_tree().physics_frame
		t += 1.0 / 120.0
	var lat1: float = pb.get("lateral")
	print("CONTROL right 0.9s: lateral %.2f -> %.2f (lean peak while held)" % [lat0, lat1])
	if lat1 - lat0 < 0.5:
		ok = false
	Input.action_press("left")
	t = 0.0
	while t < 0.9:
		await get_tree().physics_frame
		t += 1.0 / 120.0
	Input.action_release("left")
	t = 0.0
	while t < 1.5:
		await get_tree().physics_frame
		t += 1.0 / 120.0
	var lat2: float = pb.get("lateral")
	print("CONTROL left 0.9s: lateral %.2f -> %.2f" % [lat1, lat2])
	if lat2 - lat1 > -0.5:
		ok = false
	Input.action_press("brake")
	Input.action_release("gas")
	t = 0.0
	while t < 2.0:
		await get_tree().physics_frame
		t += 1.0 / 120.0
	Input.action_release("brake")
	print("CONTROL brake 2s: speed=%.1f km/h" % (float(pb.get("speed")) * 3.6))
	var ck = player["cockpit"]
	if ck != null:
		ck.sync(pb, true)
		print("COCKPIT ok eye=%s" % str(ck.eye))
	# 3) autopilot through traffic for 40 s: cars move, near misses register, no script errors
	player["ai"] = AIRider.new()
	var crashes := {"n": 0}
	pb.connect("crashed", func(_b): crashes["n"] += 1)
	var s0: float = traffic.cars[0]["s"]
	t = 0.0
	while t < 40.0:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		if bool(pb.get("is_crashed")):
			await get_tree().physics_frame
			var pbu = player["body"]
			pbu.place(float(pb.get("progress")), 1.75, 20.0)
	var moved := absf(float(traffic.cars[0]["s"]) - s0)
	print("TRAFFIC after 40s: rider %.0f m, %d near misses, %d crashes, car0 moved %.0f m" % [float(pb.get("progress")), near, crashes["n"], moved])
	if moved < 50.0:
		ok = false
	_clear_bikes()
	state = "menu"
	settings["mode"] = 2
	settings["track"] = 0
	loaded_key = ""
	ui.queue_free()
	ui = null
	return ok


# ------------------------------------------------------------------ CI: screenshots
func _run_shots() -> void:
	var dir := OS.get_environment("SHOTS_DIR")
	if dir == "":
		dir = OS.get_user_data_dir() + "/shots"
	DirAccess.make_dir_recursive_absolute(dir)
	settings["mode"] = 2
	ui = UIScript.new()
	add_child(ui)
	ui.build_menu(settings, TD.DEFS, COLORS)
	ui.build_hud()
	ui.build_pause()
	ui.build_results()
	audio = EngineAudio.new()
	add_child(audio)
	audio.muted = true
	settings["graphics"] = 2
	for ti in TD.DEFS.size():
		settings["track"] = ti
		_ensure_world()
		# menu shot
		_showroom()
		state = "menu"
		ui.show_loading(false)
		ui.show_menu(true)
		ui.show_hud(false, false)
		for _f in 40:
			await get_tree().process_frame
		_save(dir, "%s_menu" % TD.DEFS[ti]["id"])
		# race shots: AI drives everybody, player camera follows
		ui.show_menu(false)
		autotest = true
		_spawn_grid()
		autotest = false
		player = bikes[bikes.size() - 1]
		cam.target = player["body"]
		cam.snap()
		state = "race"
		countdown = 0.0
		ui.show_hud(true, false)
		ui.set_lights(0, false)
		for k in 3:
			for _f in 90:
				await get_tree().process_frame
			cam.mode = k % 3
			_save(dir, "%s_race%d" % [TD.DEFS[ti]["id"], k])
		_clear_bikes()
		state = "menu"
	# highway: cockpit + chase + TV views with traffic
	for mode_ in [0, 1]:
		settings["mode"] = mode_
		for ti in ([0, 2] if mode_ == 0 else [1]):
			settings["track"] = ti
			loaded_key = ""
			_ensure_world()
			var e := _make_bike(0, 1, 20.0, 1.75, true)
			bikes.append(e)
			player = e
			e["ai"] = AIRider.new()
			_start_traffic()
			cam.target = e["body"]
			state = "race"
			ui.show_menu(false)
			ui.show_hud(true, false)
			ui.set_hud_titles(["SCORE", "DISTANCE", "TIME", "NEAR MISS"])
			ui.set_lights(0, false)
			var id: String = _tracks()[ti]["id"]
			for k in [0, 2, 5, 1]:
				cam.mode = k
				cam.snap()
				for _f in 70:
					await get_tree().process_frame
				_save(dir, "hw_%s_%d" % [id, k])
			_clear_bikes()
	settings["mode"] = 2
	print("SHOTS DONE")
	get_tree().quit(0)


func _save(dir: String, name_: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name_])
	print("SHOT ", name_)
