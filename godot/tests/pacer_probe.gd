extends Node
## Prints the pacer's curve: the target level, the phase, how hostile the course is and how often molecules turn up (for a player at 0 and at half of the target).


func _ready() -> void:
	for mins in [10, 240]:
		var p := DhPacer.new()
		p.session_s = float(mins) * 60.0
		print("SESSION %d min" % mins)
		for q in 11:
			p.t = p.session_s * float(q) / 10.0 - (1.0 if q == 10 else 0.0)
			print("  %3d%%  %-8s target %.2f  hazards x%.2f  molecules x%.2f (at 0)  x%.2f (at half)" % [q * 10, p.phase_name(), p.target(), p.hazard_k(), p.spawn_bias(0.0), p.spawn_bias(p.target() * 0.5)])
	var c := DhPacer.new()
	c.t = 5.0
	var h1 := c.hazard_k()
	c.t = 25.0
	print("first 20 s: hazards x%.2f   after: x%.2f" % [h1, c.hazard_k()])
	get_tree().quit()
