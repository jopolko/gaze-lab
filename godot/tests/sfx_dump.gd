extends Node
## Renders every sound effect to a wav file (headless): godot --headless --path . res://tests/sfx_dump.tscn


func _ready() -> void:
	var ah := AudioHooks.new()
	add_child(ah)
	for i in 60:
		await get_tree().process_frame
	var out := OS.get_environment("SFX_OUT") if OS.get_environment("SFX_OUT") != "" else "C:/Users/josh/projects/gaze-lab-music-src/sfx"
	DirAccess.make_dir_recursive_absolute(out)
	for k in ah._streams:
		var st := ah._streams[k] as AudioStreamWAV
		if st != null:
			st.save_to_wav("%s/%s.wav" % [out, String(k)])
	print("saved ", ah._streams.size(), " sounds to ", out)
	get_tree().quit()
