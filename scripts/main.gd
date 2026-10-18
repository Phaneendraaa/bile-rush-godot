extends Node3D
# Temporary bootstrap: validates the CI pipeline while the full game is written.
const TrackData = preload("res://scripts/track_data.gd")

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	for d in TrackData.DEFS:
		var tr = TrackData.new()
		tr.build(d)
		print("track %s L=%.0f N=%d minR=%.1f" % [d["id"], tr.L, tr.N, tr.min_radius])
	print("build ms ", Time.get_ticks_msec() - t0)
	if "--autotest" in OS.get_cmdline_user_args():
		print("AUTOTEST PASS")
		get_tree().quit(0)
