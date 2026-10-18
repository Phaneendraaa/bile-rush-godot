extends Node
## Procedurally synthesised audio (no sample files): inline-4 engine loops (on/off throttle),
## wind, tyre squeal, crash. Loops are generated once and pitch-shifted by rpm.

const RATE := 22050
const F0 := 210.0          # firing frequency of the loops (Hz)
const RPM_AT_F0 := 6300.0  # inline-4: 2 firings per crank revolution

static var _cache := {}

var on_p: AudioStreamPlayer
var off_p: AudioStreamPlayer
var wind_p: AudioStreamPlayer
var squeal_p: AudioStreamPlayer
var fx_p: AudioStreamPlayer
var muted := false


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


static func engine_loop(bright: float, seed: int) -> AudioStreamWAV:
	var key := "eng_%d_%d" % [int(bright * 100), seed]
	if _cache.has(key):
		return _cache[key]
	var n := RATE  # 1 s = exactly 210 firing cycles
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# harmonic recipe: orders relative to firing frequency (0.5 = crank-order rumble)
	var orders := [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 10.0, 12.0]
	var amps := []
	var phases := []
	for o in orders:
		var a := 1.0 / pow(float(o), 0.85 - bright * 0.35)
		if float(o) == 0.5 or float(o) == 1.5:
			a *= 0.45
		amps.append(a)
		phases.append(rng.randf() * TAU)
	var lp := 0.0
	var peak := 0.0
	for i in n:
		var t := float(i) / RATE
		var ph := TAU * F0 * t
		var v := 0.0
		for h in orders.size():
			v += float(amps[h]) * sin(ph * float(orders[h]) + float(phases[h]))
		# combustion noise shaped by firing phase
		var nz := rng.randf_range(-1.0, 1.0)
		lp += (nz - lp) * (0.25 + bright * 0.4)
		v += lp * (0.1 + bright * 0.18) * (0.55 + 0.45 * cos(ph))
		# soft clip for growl
		v = tanh(v * (0.9 + bright * 0.6))
		out[i] = v
		peak = maxf(peak, absf(v))
	for i in n:
		out[i] = out[i] / peak * 0.9
	var w := _wav(out, true)
	_cache[key] = w
	return w


static func noise_loop(cut: float, reso: float, key: String) -> AudioStreamWAV:
	if _cache.has(key):
		return _cache[key]
	var n := RATE * 2
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = key.hash()
	# 2-pole resonant low/band-pass (state variable filter)
	var low := 0.0
	var band := 0.0
	var f := 2.0 * sin(PI * cut / RATE)
	var q := 1.0 / reso
	var peak := 0.001
	for i in n:
		var x := rng.randf_range(-1.0, 1.0)
		low += f * band
		var high := x - low - q * band
		band += f * high
		var v := band if reso > 1.5 else low
		out[i] = v
		peak = maxf(peak, absf(v))
	# crossfade the loop seam
	var fade := 2000
	for i in fade:
		var a := float(i) / fade
		out[i] = out[i] * a + out[n - fade + i] * (1.0 - a)
	for i in n:
		out[i] = out[i] / peak * 0.85
	var w := _wav(out, true)
	_cache[key] = w
	return w


static func crash_sound() -> AudioStreamWAV:
	if _cache.has("crash"):
		return _cache["crash"]
	var n := int(RATE * 1.2)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 3.5)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.3
		var thud := sin(TAU * (70.0 - 30.0 * t) * t) * exp(-t * 9.0)
		var scrape := rng.randf_range(-1.0, 1.0) * 0.25 * exp(-t * 1.5) * (0.5 + 0.5 * sin(t * 90.0))
		out[i] = clampf(lp * env * 0.8 + thud * 0.9 + scrape, -1.0, 1.0)
	var w := _wav(out, false)
	_cache["crash"] = w
	return w


func setup() -> void:
	# everything starts silent: volumes are driven by update() only while racing
	on_p = _player(engine_loop(0.8, 1), -80.0)
	off_p = _player(engine_loop(0.15, 2), -80.0)
	wind_p = _player(noise_loop(900.0, 0.7, "wind"), -80.0)
	squeal_p = _player(noise_loop(1350.0, 6.0, "squeal"), -80.0)
	fx_p = AudioStreamPlayer.new()
	add_child(fx_p)
	for p in [on_p, off_p, wind_p, squeal_p]:
		p.play()


func _player(stream: AudioStream, vol: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol
	add_child(p)
	return p


func update(bike, active: bool) -> void:
	if on_p == null:
		return
	var rpm: float = bike.rpm
	var thr: float = bike.throttle
	var pitch := clampf(rpm / RPM_AT_F0, 0.22, 2.3)
	on_p.pitch_scale = pitch
	off_p.pitch_scale = pitch
	var ld := clampf(thr, 0.0, 1.0)
	var base := 0.0 if active and not muted else -80.0
	var rv := rpm / 13000.0
	on_p.volume_db = base + linear_to_db(maxf(0.02, ld * (0.55 + 0.45 * rv))) - 2.0
	off_p.volume_db = base + linear_to_db(maxf(0.02, (1.0 - ld) * (0.4 + 0.4 * rv))) - 4.0
	var spd: float = absf(bike.speed)
	wind_p.volume_db = base + linear_to_db(clampf(spd * spd / 5500.0, 0.001, 0.9)) - 6.0
	wind_p.pitch_scale = 0.8 + spd / 120.0
	var slide: float = maxf(bike.front_slide, bike.rear_slide) + bike.wheelspin * 0.6
	var sq := clampf(slide * 2.0, 0.0, 1.0) if bike.on_ground and spd > 3.0 and not bike.is_crashed else 0.0
	squeal_p.volume_db = base + linear_to_db(maxf(sq, 0.001)) - 8.0
	squeal_p.pitch_scale = 0.9 + randf() * 0.05


## Mute all looping sounds (menu, loading, pause, results).
func silence() -> void:
	for p in [on_p, off_p, wind_p, squeal_p]:
		if p != null:
			p.volume_db = -80.0


func is_silent() -> bool:
	for p in [on_p, off_p, wind_p, squeal_p]:
		if p != null and p.volume_db > -70.0:
			return false
	return true


func play_crash() -> void:
	if muted or fx_p == null:
		return
	fx_p.stream = crash_sound()
	fx_p.volume_db = -2.0
	fx_p.play()


func beep(freq: float, dur: float) -> void:
	if muted or fx_p == null:
		return
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		# soft sine chime with a short attack and release (no clicks)
		var env := minf(1.0, t * 200.0) * minf(1.0, (dur - t) * 25.0)
		out[i] = (sin(TAU * freq * t) * 0.8 + sin(TAU * freq * 2.0 * t) * 0.2) * 0.35 * env
	fx_p.stream = _wav(out, false)
	fx_p.volume_db = -8.0
	fx_p.play()


## 3D engine voice for rival bikes
static func rival_player() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = engine_loop(0.8, 1)
	p.unit_size = 9.0
	p.max_distance = 220.0
	p.volume_db = -4.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	p.attenuation_filter_cutoff_hz = 6000.0
	return p
