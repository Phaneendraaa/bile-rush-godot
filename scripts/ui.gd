extends CanvasLayer
## Menu, HUD, multitouch controls, pause & results — all built in code.

signal start_race
signal resume
signal restart
signal quit_to_menu
signal next_track
signal pause_pressed
signal setting_changed(key, value)

const ACC := Color(1.0, 0.36, 0.12)
const ACC2 := Color(1.0, 0.8, 0.25)

var theme_: Theme
var menu: Control
var hud: Control
var pause_box: Control
var results_box: Control
var loading: Control
var touch: Node2D
var msg_label: Label
var msg_timer := 0.0
var lbl := {}
var minimap: Control
var mini_pts := PackedVector2Array()
var mini_dots: Array = []   # [Vector2 (normalised), Color, bool is_player]
var settings: Dictionary
var btn_nodes := {}
var rev_bar: ProgressBar
var lights: Array = []


func _ready() -> void:
	layer = 10
	theme_ = _make_theme()
	_build_loading()


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.78)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 14; sb.content_margin_right = 14
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	var hov: StyleBoxFlat = sb.duplicate()
	hov.bg_color = Color(0.12, 0.13, 0.17, 0.9)
	var sel: StyleBoxFlat = sb.duplicate()
	sel.bg_color = ACC
	sel.border_color = Color(1, 0.6, 0.4, 0.8)
	for s in ["normal", "focus"]:
		t.set_stylebox(s, "Button", sb)
	t.set_stylebox("hover", "Button", hov)
	t.set_stylebox("pressed", "Button", sel)
	t.set_stylebox("hover_pressed", "Button", sel)
	t.set_color("font_color", "Button", Color(0.95, 0.95, 0.97))
	t.set_color("font_pressed_color", "Button", Color(1, 1, 1))
	t.set_color("font_hover_pressed_color", "Button", Color(1, 1, 1))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.04, 0.05, 0.08, 0.82)
	panel.border_color = Color(1, 1, 1, 0.1)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(20)
	panel.content_margin_left = 18; panel.content_margin_right = 18
	panel.content_margin_top = 14; panel.content_margin_bottom = 14
	t.set_stylebox("panel", "PanelContainer", panel)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(1, 1, 1, 0.12)
	bar_bg.set_corner_radius_all(6)
	var bar_fg := StyleBoxFlat.new()
	bar_fg.bg_color = ACC
	bar_fg.set_corner_radius_all(6)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fg)
	return t


func _label(text: String, size: int, col: Color = Color.WHITE, italic := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _full() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.theme = theme_
	add_child(c)
	return c


# ------------------------------------------------------------ loading
func _build_loading() -> void:
	loading = _full()
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.add_child(bg)
	var l := _label("BIKE RUSH 3D", 64, ACC)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	loading.add_child(l)
	var l2 := _label("Building track…", 22, Color(1, 1, 1, 0.7))
	l2.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	l2.position.y -= 80
	l2.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.add_child(l2)
	lbl["loading"] = l2


func show_loading(on: bool, text: String = "Building track…") -> void:
	loading.visible = on
	lbl["loading"].text = text


# ------------------------------------------------------------ menu
func build_menu(s: Dictionary, tracks: Array, colors: Array) -> void:
	settings = s
	menu = _full()
	var left := VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.offset_left = 40
	left.offset_top = 30
	left.offset_bottom = -30
	left.custom_minimum_size.x = 380
	left.add_theme_constant_override("separation", 6)
	menu.add_child(left)
	var title := _label("BIKE RUSH", 72, Color.WHITE)
	left.add_child(title)
	var sub := _label("3 D   S U P E R B I K E   R A C I N G", 18, ACC2)
	left.add_child(sub)
	var tag := _label("Real two-wheel physics · 6 riders · 3 circuits", 18, Color(1, 1, 1, 0.75))
	left.add_child(tag)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(spacer)
	var go := Button.new()
	go.text = "RACE  ▶"
	go.custom_minimum_size = Vector2(360, 86)
	go.add_theme_font_size_override("font_size", 40)
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = ACC
	gsb.set_corner_radius_all(18)
	go.add_theme_stylebox_override("normal", gsb)
	go.add_theme_stylebox_override("hover", gsb)
	go.add_theme_stylebox_override("pressed", gsb)
	go.add_theme_stylebox_override("focus", gsb)
	go.pressed.connect(func(): start_race.emit())
	left.add_child(go)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -660
	panel.offset_right = -30
	panel.offset_top = 24
	panel.offset_bottom = -24
	menu.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)

	_option_row(col, "MODE", "mode", ["Two-way traffic", "One-way traffic", "Circuit race"], 3)
	var tnames: Array = []
	for t in tracks:
		tnames.append(str(t["name"]) + "\n" + str(t["desc"]))
	_option_row(col, "ROAD" if int(settings.get("mode", 0)) < 2 else "TRACK", "track", tnames, mini(tnames.size(), 4) if tnames.size() == 4 else 3, 84)
	_option_row(col, "BIKE", "bike", ["Sport 1000", "Naked 900", "Cruiser 1800"], 3)
	_color_row(col, colors)
	_option_row(col, "THROTTLE", "throttle", ["Manual GAS", "Auto throttle"], 2)
	if int(settings.get("mode", 0)) == 2:
		_option_row(col, "DIFFICULTY", "difficulty", ["Rookie", "Pro", "Legend"], 3)
		_option_row(col, "LAPS", "laps", ["1 lap", "3 laps", "5 laps"], 3)
	_option_row(col, "STEERING", "steering", ["◀ ▶ Buttons", "Tilt phone", "Tilt (inverted)"], 3)
	_option_row(col, "RIDER AIDS", "aids", ["Full assist", "Sport", "Off (real)"], 3)
	_option_row(col, "GRAPHICS", "graphics", ["Performance", "Balanced", "Quality"], 3)
	_option_row(col, "SOUND", "sound", ["On", "Off"], 2)


func _section(parent: Control, title: String) -> void:
	var l := _label(title, 14, Color(1, 1, 1, 0.6))
	parent.add_child(l)


func _option_row(parent: Control, title: String, key: String, opts: Array, cols: int, h: int = 50) -> void:
	_section(parent, title)
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	var group := ButtonGroup.new()
	for i in opts.size():
		var b := Button.new()
		b.text = opts[i]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, h)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 16 if h > 60 else 18)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.clip_text = true
		b.button_pressed = int(settings.get(key, 0)) == i
		var idx := i
		b.pressed.connect(func():
			settings[key] = idx
			setting_changed.emit(key, idx))
		grid.add_child(b)


func _color_row(parent: Control, colors: Array) -> void:
	_section(parent, "YOUR BIKE")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var group := ButtonGroup.new()
	for i in colors.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(46, 46)
		var c: Color = colors[i]
		for st in ["normal", "hover", "focus"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = c
			sb.set_corner_radius_all(23)
			sb.border_color = Color(1, 1, 1, 0.25)
			sb.set_border_width_all(2)
			b.add_theme_stylebox_override(st, sb)
		var sp := StyleBoxFlat.new()
		sp.bg_color = c
		sp.set_corner_radius_all(23)
		sp.border_color = Color.WHITE
		sp.set_border_width_all(4)
		b.add_theme_stylebox_override("pressed", sp)
		b.add_theme_stylebox_override("hover_pressed", sp)
		b.button_pressed = int(settings.get("color", 0)) == i
		var idx := i
		b.pressed.connect(func():
			settings["color"] = idx
			setting_changed.emit("color", idx))
		row.add_child(b)


func rebuild_menu(s: Dictionary, tracks: Array, colors: Array) -> void:
	var was := menu != null and menu.visible
	if menu:
		menu.queue_free()
		menu = null
	build_menu(s, tracks, colors)
	menu.visible = was
	# keep the loading/pause/results layers above the menu
	if loading:
		move_child(loading, get_child_count() - 1)


func show_menu(on: bool) -> void:
	if menu:
		menu.visible = on


# ------------------------------------------------------------ HUD
func build_hud() -> void:
	hud = _full()
	hud.visible = false
	# top-left: position / lap / time
	var tl := HBoxContainer.new()
	tl.position = Vector2(24, 18)
	tl.add_theme_constant_override("separation", 10)
	hud.add_child(tl)
	var pause := Button.new()
	pause.text = "❚❚"
	pause.custom_minimum_size = Vector2(64, 64)
	pause.pressed.connect(func(): pause_pressed.emit())
	tl.add_child(pause)
	btn_nodes["pause"] = pause
	for k in [["POS", "pos", "6/6", 40], ["LAP", "lap", "1/3", 30], ["TIME", "time", "0:00.00", 30], ["BEST", "best", "--", 24]]:
		var pc := PanelContainer.new()
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", -4)
		pc.add_child(vb)
		var tl_ := _label(k[0], 12, Color(1, 1, 1, 0.6))
		vb.add_child(tl_)
		lbl["t_" + str(k[1])] = tl_
		var v := _label(k[2], k[3])
		vb.add_child(v)
		lbl[k[1]] = v
		tl.add_child(pc)
	# minimap
	minimap = Control.new()
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.offset_left = -214
	minimap.offset_right = -24
	minimap.offset_top = 18
	minimap.offset_bottom = 208
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(_draw_minimap)
	hud.add_child(minimap)
	# speedo bottom-centre
	var sp := VBoxContainer.new()
	sp.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sp.offset_left = -170
	sp.offset_right = 170
	sp.offset_top = -150
	sp.offset_bottom = -14
	sp.alignment = BoxContainer.ALIGNMENT_END
	sp.add_theme_constant_override("separation", 0)
	hud.add_child(sp)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	sp.add_child(row)
	var gear := _label("1", 64, ACC2)
	row.add_child(gear)
	lbl["gear"] = gear
	var spd := _label("0", 72)
	row.add_child(spd)
	lbl["speed"] = spd
	var unit := _label("km/h", 20, Color(1, 1, 1, 0.75))
	unit.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(unit)
	rev_bar = ProgressBar.new()
	rev_bar.custom_minimum_size = Vector2(300, 10)
	rev_bar.show_percentage = false
	rev_bar.max_value = 13500
	sp.add_child(rev_bar)
	var aids := HBoxContainer.new()
	aids.alignment = BoxContainer.ALIGNMENT_CENTER
	aids.add_theme_constant_override("separation", 12)
	sp.add_child(aids)
	for a in ["TC", "ABS", "SLIDE"]:
		var al := _label(a, 16, Color(1, 1, 1, 0.18))
		aids.add_child(al)
		lbl["aid_" + a] = al
	# centre message
	msg_label = _label("", 72)
	msg_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	msg_label.offset_top = 150
	msg_label.offset_left = -500
	msg_label.offset_right = 500
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(msg_label)
	# start lights
	var lrow := HBoxContainer.new()
	lrow.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lrow.offset_top = 70
	lrow.offset_left = -160
	lrow.offset_right = 160
	lrow.alignment = BoxContainer.ALIGNMENT_CENTER
	lrow.add_theme_constant_override("separation", 12)
	hud.add_child(lrow)
	for i in 5:
		var c := Panel.new()
		c.custom_minimum_size = Vector2(44, 44)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.15, 0.02, 0.02, 0.9)
		sb.set_corner_radius_all(22)
		sb.border_color = Color(0, 0, 0, 0.8)
		sb.set_border_width_all(3)
		c.add_theme_stylebox_override("panel", sb)
		lrow.add_child(c)
		lights.append(sb)
	lbl["lights"] = lrow
	_build_touch()


func set_lights(n: int, visible_: bool) -> void:
	lbl["lights"].visible = visible_
	for i in lights.size():
		var sb: StyleBoxFlat = lights[i]
		sb.bg_color = Color(1.0, 0.08, 0.05) if i < n else Color(0.15, 0.02, 0.02, 0.9)


func _circle_tex(col: Color, size: int) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.88, 0.94, 1.0])
	g.colors = PackedColorArray([Color(col, col.a * 0.55), Color(col, col.a * 0.75), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t


func _touch_button(action: String, text: String, size: int, col: Color, passby: bool) -> TouchScreenButton:
	var b := TouchScreenButton.new()
	b.texture_normal = _circle_tex(col, size)
	b.texture_pressed = _circle_tex(Color(col.r * 1.4, col.g * 1.4, col.b * 1.4, 0.95), size)
	var sh := CircleShape2D.new()
	sh.radius = size * 0.5
	b.shape = sh
	b.shape_centered = true
	b.action = action
	b.passby_press = passby
	var l := _label(text, int(size * 0.2))
	l.size = Vector2(size, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(l)
	touch.add_child(b)
	btn_nodes[action] = b
	return b


func _build_touch() -> void:
	touch = Node2D.new()
	add_child(touch)
	_touch_button("left", "◀", 170, Color(1, 1, 1, 0.5), true)
	_touch_button("right", "▶", 170, Color(1, 1, 1, 0.5), true)
	_touch_button("brake", "BRAKE", 150, Color(1.0, 0.3, 0.25, 0.6), false)
	_touch_button("gas", "GAS", 190, Color(0.3, 0.9, 0.4, 0.6), false)
	_touch_button("cam", "CAM", 84, Color(1, 1, 1, 0.35), false)
	get_viewport().size_changed.connect(layout_touch)
	layout_touch()


func layout_touch() -> void:
	if touch == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var m := 26.0
	_place("left", Vector2(m, vs.y - 170 - m))
	_place("right", Vector2(m + 190, vs.y - 170 - m))
	_place("gas", Vector2(vs.x - 190 - m, vs.y - 190 - m))
	_place("brake", Vector2(vs.x - 190 - m - 165, vs.y - 150 - m - 10))
	_place("cam", Vector2(vs.x - 84 - 240, 22))


func _place(k: String, p: Vector2) -> void:
	var b: Node2D = btn_nodes[k]
	b.position = p


func show_hud(on: bool, tilt: bool) -> void:
	hud.visible = on
	touch.visible = on
	btn_nodes["left"].visible = on and not tilt
	btn_nodes["right"].visible = on and not tilt


func set_minimap(points: PackedVector2Array) -> void:
	mini_pts = points


func _draw_minimap() -> void:
	var sz := minimap.size
	minimap.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.04, 0.05, 0.08, 0.7))
	if mini_pts.size() < 2:
		return
	var pts := PackedVector2Array()
	for p in mini_pts:
		pts.append(p * (sz - Vector2(24, 24)) + Vector2(12, 12))
	pts.append(pts[0])
	minimap.draw_polyline(pts, Color(0, 0, 0, 0.6), 9.0, true)
	minimap.draw_polyline(pts, Color(0.95, 0.95, 0.95), 4.5, true)
	for d in mini_dots:
		var p: Vector2 = d[0] * (sz - Vector2(24, 24)) + Vector2(12, 12)
		var c: Color = d[1]
		var me: bool = d[2]
		minimap.draw_circle(p, 9.0 if me else 7.0, Color.BLACK)
		minimap.draw_circle(p, 6.5 if me else 5.0, Color.WHITE if me else c)
		if me:
			minimap.draw_arc(p, 9.5, 0, TAU, 20, c, 3.0)


func set_hud_titles(titles: Array) -> void:
	var keys := ["pos", "lap", "time", "best"]
	for i in keys.size():
		lbl["t_" + keys[i]].text = titles[i]


## Highway HUD: score / distance / time / near misses
func update_hud_highway(d: Dictionary) -> void:
	lbl["pos"].text = str(int(d["score"]))
	lbl["lap"].text = "%.2f km" % (float(d["dist"]) / 1000.0)
	lbl["time"].text = fmt_time(d["time"])
	lbl["best"].text = "x%d" % int(d["near"])
	lbl["speed"].text = str(int(round(float(d["speed"]) * 3.6)))
	lbl["gear"].text = str(d["gear"])
	rev_bar.value = float(d["rpm"]) / float(d["redline"]) * 13500.0
	var on := Color(1.0, 0.75, 0.2)
	var off := Color(1, 1, 1, 0.18)
	lbl["aid_TC"].add_theme_color_override("font_color", on if d["tc"] else off)
	lbl["aid_ABS"].add_theme_color_override("font_color", on if d["abs"] else off)
	lbl["aid_SLIDE"].add_theme_color_override("font_color", Color(1, 0.3, 0.2) if d["slide"] else off)
	mini_dots = d["dots"]
	minimap.queue_redraw()


func update_hud(d: Dictionary) -> void:
	lbl["pos"].text = "%d/%d" % [d["pos"], d["count"]]
	lbl["lap"].text = "%d/%d" % [d["lap"], d["laps"]]
	lbl["time"].text = fmt_time(d["time"])
	lbl["best"].text = fmt_time(d["best"]) if d["best"] < 1e8 else "--"
	lbl["speed"].text = str(int(round(float(d["speed"]) * 3.6)))
	lbl["gear"].text = str(d["gear"])
	rev_bar.value = d["rpm"]
	var on := Color(1.0, 0.75, 0.2)
	var off := Color(1, 1, 1, 0.18)
	lbl["aid_TC"].add_theme_color_override("font_color", on if d["tc"] else off)
	lbl["aid_ABS"].add_theme_color_override("font_color", on if d["abs"] else off)
	lbl["aid_SLIDE"].add_theme_color_override("font_color", Color(1, 0.3, 0.2) if d["slide"] else off)
	mini_dots = d["dots"]
	minimap.queue_redraw()


static func fmt_time(t: float) -> String:
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return "%d:%05.2f" % [m, s]


func message(text: String, dur: float = 1.5) -> void:
	msg_label.text = text
	msg_timer = dur


func _process(delta: float) -> void:
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0:
			msg_label.text = ""


# ------------------------------------------------------------ pause / results
func build_pause() -> void:
	pause_box = _full()
	pause_box.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_box.add_child(dim)
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	pause_box.add_child(pc)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(380, 0)
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	var t := _label("PAUSED", 48)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	for b in [["RESUME", resume], ["RESTART RACE", restart], ["MAIN MENU", quit_to_menu]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(0, 62)
		var sig: Signal = b[1]
		btn.pressed.connect(func(): sig.emit())
		vb.add_child(btn)


func show_pause(on: bool) -> void:
	pause_box.visible = on
	touch.visible = not on and hud.visible


func build_results() -> void:
	results_box = _full()
	results_box.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	results_box.add_child(dim)
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	results_box.add_child(pc)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(640, 0)
	vb.add_theme_constant_override("separation", 6)
	pc.add_child(vb)
	var t := _label("1st PLACE", 52, ACC2)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	lbl["res_title"] = t
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 26)
	vb.add_child(g)
	lbl["res_grid"] = g
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	for b in [["RACE AGAIN", restart], ["NEXT TRACK", next_track], ["MENU", quit_to_menu]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(0, 62)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sig: Signal = b[1]
		btn.pressed.connect(func(): sig.emit())
		row.add_child(btn)


func show_results(title: String, rows: Array) -> void:
	lbl["res_title"].text = title
	var g: GridContainer = lbl["res_grid"]
	for c in g.get_children():
		c.queue_free()
	for r in rows:
		for k in 4:
			var col: Color = ACC2 if r[4] else Color.WHITE
			g.add_child(_label(str(r[k]), 22, col))
	results_box.visible = true
	touch.visible = false


func hide_results() -> void:
	results_box.visible = false
