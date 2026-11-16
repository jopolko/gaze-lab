extends SceneTree
## The three places learned while playing, with made-up readings: a laptop (a look moves the iris about 0.09) and a phone (about 0.03).


func _run(name: String, mv: float) -> void:
	var k := KitEye.new()
	k.auto_zones = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var t := 0.0
	var seq: Array = []
	# rests (0.9 s), then left, middle, right, middle, left, right, each held 0.7 s
	var plan := [[0.0, 1.6], [1.0, 0.7], [0.0, 0.8], [-1.0, 0.7], [0.0, 0.8], [1.0, 0.7], [-1.0, 0.7], [0.0, 0.8]]
	var hit := 0
	var tot := 0
	for st in plan:
		var want := int(-signf(float(st[0])))          # left (+) reads as zone -1
		var n := int(float(st[1]) * 30.0)
		var got_n := 0
		for i in n:
			t += 1.0 / 30.0
			k.set_feat(KitEye.AUTO_M + float(st[0]) * mv + rng.randfn(0.0, 0.0025), 0.0, 0.1, 0.0, 0.0, 0.0, 0.1)
			k.add(k.feat[0], 0.3, 0.3, t)
			if float(i) / 30.0 > 0.3 and not k.zones.is_empty():
				tot += 1
				if k.zone == want:
					got_n += 1
					hit += 1
		seq.append("%d:%d/%d" % [want, got_n, maxi(n - 9, 0)])
	print("AUTOZONES %s: %d of %d samples read right   %s   learned dl %.3f dr %.3f" % [name, hit, tot, seq, float(k.zones.get("dl", 0.0)), float(k.zones.get("dr", 0.0))])


func _run2(name: String, mv: float, off: float) -> void:
	# the middle was taken a little off in the first 1.6 s; then 25 s of play, mostly resting, now and then a look to a side (equal left and right)
	var k := KitEye.new()
	k.auto_zones = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var t := 0.0
	for i in 48:
		t += 1.0 / 30.0
		k.set_feat(KitEye.AUTO_M + off + rng.randfn(0.0, 0.0025), 0.0, 0.1, 0.0, 0.0, 0.0, 0.1)
		k.add(k.feat[0], 0.3, 0.3, t)
	var hit := 0
	var tot := 0
	var rest_wrong := 0
	var rest_n := 0
	var side_ok := 0
	var side_n := 0
	var tt := 0.0
	while tt < 25.0:
		var r := rng.randf()
		var look := 0.0 if r < 0.6 else (1.0 if r < 0.8 else -1.0)
		var dur := rng.randf_range(0.7, 1.3)
		var want := int(-signf(look))
		for i in int(dur * 30.0):
			t += 1.0 / 30.0
			tt += 1.0 / 30.0
			k.set_feat(KitEye.AUTO_M + look * mv + rng.randfn(0.0, 0.0025), 0.0, 0.1, 0.0, 0.0, 0.0, 0.1)
			k.add(k.feat[0], 0.3, 0.3, t)
			if tt > 10.0 and float(i) / 30.0 > 0.35:
				if look == 0.0:
					rest_n += 1
					rest_wrong += 1 if k.zone != 0 else 0
				else:
					side_n += 1
					side_ok += 1 if k.zone == want else 0
	print("AUTOZONES-OFF %s, middle taken %.3f off: resting read as a side %d of %d (%.0f%%), looks to a side read right %d of %d (%.0f%%)" % [name, off, rest_wrong, rest_n, 100.0 * rest_wrong / maxf(rest_n, 1), side_ok, side_n, 100.0 * side_ok / maxf(side_n, 1)])


func _init() -> void:
	for off in [0.0, 0.012, -0.012, 0.02, -0.02]:
		_run2("phone", 0.03, off)
	_run2("laptop", 0.09, 0.03)
	_run("laptop (moves 0.09)", 0.09)
	_run("phone (moves 0.03)", 0.03)
	_run("small look (moves 0.045)", 0.045)
	quit()
