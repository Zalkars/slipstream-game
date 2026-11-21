extends Node

# 0.8.0 playtest batch: traffic lane changes (rarer, an indicator always means
# a move that happens or is switched off at once, no cutting into the
# player's space), the staged road-works zone (layout scaled by speed,
# knock-over signs/cones for points, solid STOP barrier, traffic waiting
# behind the closure, determinism) and the Auto graphics choice (GPU tier,
# vsync-bound benchmark, loading spike).

var failures := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var game := Game.new()
	game.use_3d_cars = false
	add_child(game)
	game.set_process(false)
	check_lane_change_frequency(game)
	check_indicator_commits(game)
	check_no_cut_in_near_player(game)
	check_signals_in_traffic(game)
	check_roadworks_layout()
	check_roadworks_collisions(game)
	check_roadworks_traffic(game)
	check_roadworks_determinism(game)
	check_auto_preset()
	print("[road] lane-change rate, indicator commits/cancels, no cut-in near player, road-works layout/knocks/STOP/traffic/determinism, auto preset tiers: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(1 if failures else 0)


func _car(game: Game, lane: int, y: float, rel := 0.7) -> Dictionary:
	return {
		"lane": lane, "x": game._lane_x(lane), "y": y, "w": game.car_w, "h": game.car_h,
		"kind": 0, "color": Color.GRAY, "rel": rel, "cur_speed": rel * game.base_speed,
		"braking": false, "demo_speed": 0.0, "near": false, "cutin": false, "from_rear": false,
	}


func _fresh(game: Game) -> void:
	game.challenge_config = {}
	game.car_index = 0
	game.start_run()
	game.road_event_t = 9999.0
	game.cars.clear()
	game.items.clear()
	game.lane = 3
	game.player_x = game._lane_x(3)


func check_lane_change_frequency(game: Game) -> void:
	_fresh(game)
	var lo := INF
	var hi := 0.0
	for _i in range(40):
		game._traffic_lc_t = 0.0
		game._update_traffic_signals(0.0)
		lo = minf(lo, game._traffic_lc_t)
		hi = maxf(hi, game._traffic_lc_t)
	check(lo >= 3.0 and hi <= 5.2, "Spontaneous lane changes come every 3.0-5.2 s (was 1.5-2.7 s)")


func check_indicator_commits(game: Game) -> void:
	# Signals only for a move already checked as possible, then completes it.
	_fresh(game)
	var c := _car(game, 1, 300.0)
	game.cars = [c]
	check(game._try_start_lane_change(c, false), "A free lane lets a car signal")
	var target := int(c.signal_target)
	var dangling := false
	for _i in range(90):
		game._update_traffic_signals(1.0 / 60.0)
		if int(c.get("signal_dir", 0)) != 0 and float(c.get("signal_t", 0.0)) <= 0.0 and float(c.get("lane_move_t", 0.0)) <= 0.0:
			dangling = true
		if float(c.get("lane_move_t", 0.0)) > 0.0:
			c["lane_move_t"] = maxf(0.0, float(c.lane_move_t) - 1.0 / 60.0)
			if float(c.lane_move_t) <= 0.0:
				c["signal_dir"] = 0
	check(int(c.lane) == target, "A car that signalled changes lane")
	check(not dangling, "An indicator never blinks without a move in progress")

	# Blocked in both directions: no indicator at all.
	_fresh(game)
	c = _car(game, 1, 300.0)
	game.cars = [c, _car(game, 0, 300.0), _car(game, 2, 330.0)]
	check(not game._try_start_lane_change(c, false) and int(c.get("signal_dir", 0)) == 0, "No indicator when no lane change is possible")

	# Gap closes while signalling: indicator off at once, car stays.
	_fresh(game)
	c = _car(game, 1, 300.0)
	game.cars = [c, _car(game, 0, 300.0)]
	check(game._try_start_lane_change(c, false) and int(c.signal_target) == 2, "Signals towards the free side")
	game._update_traffic_signals(1.0 / 60.0)
	game.cars.append(_car(game, 2, 320.0))
	game._update_traffic_signals(1.0 / 60.0)
	check(int(c.get("signal_dir", 0)) == 0 and float(c.get("signal_t", 0.0)) == 0.0 and int(c.lane) == 1, "A move that becomes unsafe switches the indicator off immediately")

	# A faster car closing in from behind in the target lane also forbids it.
	_fresh(game)
	c = _car(game, 1, 300.0, 0.6)
	var fast := _car(game, 2, 300.0 + game.car_h * 2.6, 0.95)
	game.cars = [c, fast, _car(game, 0, 300.0)]
	check(not game._try_start_lane_change(c, false), "No lane change into the path of a faster car closing from behind")


func check_no_cut_in_near_player(game: Game) -> void:
	_fresh(game)
	game.lane = 1
	game.player_x = game._lane_x(1)
	game.speed = 1100.0
	var horizon := 1.25 + Game.LC_MOVE_TIME
	var ahead := _car(game, 2, game.player_y - game.car_h * 2.0)
	game.cars = [ahead]
	check(not game._lane_change_safe(ahead, 1, horizon), "No lane change into the space just ahead of the player")
	var beside := _car(game, 2, game.player_y)
	game.cars = [beside]
	check(not game._lane_change_safe(beside, 1, horizon), "No lane change into the player from beside")
	check(game._lane_change_safe(beside, 3, horizon), "Moving away from the player is fine")
	var far := _car(game, 2, game.player_y - 2600.0, 0.9)
	game.cars = [far]
	check(game._lane_change_safe(far, 1, horizon), "A car far ahead may still move into the player's lane")
	# The safe distance grows with the closing speed.
	var mid := _car(game, 2, game.player_y - 1250.0, 0.9)
	game.cars = [mid]
	game.speed = 0.9 * game.base_speed
	var ok_slow := game._lane_change_safe(mid, 1, horizon)
	game.speed = 1900.0
	var ok_fast := game._lane_change_safe(mid, 1, horizon)
	check(ok_slow and not ok_fast, "The gap kept in front of the player scales with relative speed")
	# Player mid lane change: both lanes count as the player's.
	game.speed = 1100.0
	game.lane = 2
	game.player_x = (game._lane_x(1) + game._lane_x(2)) * 0.5
	var near1 := _car(game, 0, game.player_y - game.car_h * 1.5)
	game.cars = [near1]
	check(not game._lane_change_safe(near1, 1, horizon), "The lane the player is leaving is still protected")


# A real seeded run: every lane commit into the player's lane keeps the gap,
# and no indicator is ever left blinking without a move.
func check_signals_in_traffic(game: Game) -> void:
	game.challenge_config = {"type": "daily", "seed": 424242, "car_index": 2, "tod": 0.3, "weather": Game.WEATHER_CLEAR}
	game.start_run()
	game.challenge_config = {}
	game._rewind_invuln = 9999.0
	var commits := 0
	var bad_cut := 0
	var dangling := 0
	for _i in range(60 * 45):
		var before := {}
		for c in game.cars:
			before[c.get_instance_id() if c is Object else str(c.get("_id", ""))] = 0
		var lanes_before: Array = []
		for c in game.cars:
			lanes_before.append([c, int(c.lane)])
		game._rewind_invuln = 9999.0
		game._tick(1.0 / 60.0)
		for pair in lanes_before:
			var c: Dictionary = pair[0]
			if int(c.lane) != int(pair[1]) and game.cars.has(c):
				commits += 1
				if game._player_lanes().has(int(c.lane)):
					var gap := game.player_y - float(c.y)
					if absf(gap) < (game.car_h + float(c.h)) * 0.5 + game.car_h * 0.8:
						bad_cut += 1
		for c in game.cars:
			if int(c.get("signal_dir", 0)) != 0 and float(c.get("signal_t", 0.0)) <= 0.0 and float(c.get("lane_move_t", 0.0)) <= 0.0:
				dangling += 1
		if game.crashed:
			break
	print("[road] 45 s seeded run: %d lane changes, %d near the player rejected-as-unsafe check failures" % [commits, bad_cut])
	check(commits > 0, "Traffic still changes lanes in a 45 s run")
	check(commits <= 34, "Lane changes are noticeably rarer (%d in 45 s)" % commits)
	check(bad_cut == 0, "No lane change ends right in front of or beside the player (%d)" % bad_cut)
	check(dangling == 0, "No indicator blinks without a lane change in progress (%d frames)" % dangling)


func check_roadworks_layout() -> void:
	for spd in [600.0, 900.0, 1300.0, 1580.0]:
		var ev := Game.roadworks_layout(0, spd)
		var lead := float(ev.lead)
		check(lead / spd >= Game.RW_REACT_TIME - 0.01, "At %d px/s the warning sign comes %.1f s before the STOP barrier" % [int(spd), lead / spd])
		var arrows := 0
		var cones := 0
		var last_off := 0.0
		var last_u := -1.0
		var ordered := true
		for o in ev.objs:
			if float(o.off) <= last_off or float(o.off) > lead:
				ordered = false
			last_off = float(o.off)
			if str(o.kind) == "arrow":
				arrows += 1
				if cones > 0:
					ordered = false
			else:
				cones += 1
				if float(o.u) <= last_u:
					ordered = false
				last_u = float(o.u)
		check(ordered, "Road order: sign, arrow signs, cone taper, STOP barrier (%d px/s)" % int(spd))
		check(arrows == 2 and cones == Game.RW_CONES, "Two arrow signs and %d cones" % Game.RW_CONES)
		check(float(ev.taper_len) >= 480.0, "The cone taper is long enough to move over smoothly")
	check(float(Game.roadworks_layout(0, 200.0).lead) == Game.RW_LEAD_MIN, "Slow runs still get the minimum warning distance")
	check(float(Game.roadworks_layout(3, 9000.0).lead) == Game.RW_LEAD_MAX, "Warning distance is capped")


func _roadworks(game: Game, closed: int) -> void:
	_fresh(game)
	game.closed_lane = closed
	game.road_event_type = Game.EVENT_ROADWORKS
	game.road_event = Game.roadworks_layout(closed, game.speed)
	game.road_event["warned"] = true


func _first(game: Game, kind: String) -> Dictionary:
	for o in game.road_event.objs:
		if str(o.kind) == kind:
			return o
	return {}


func check_roadworks_collisions(game: Game) -> void:
	# Cone: points, small speed loss, no crash, knocked only once.
	_roadworks(game, 0)
	var cone := _first(game, "cone")
	game.road_event["y"] = game.player_y + float(cone.off)
	game.lane = 0
	game.player_x = game.roadworks_object_pos(cone).x
	var bonus0 := game.bonus
	var speed0 := game.speed
	game._update_road_events(1.0 / 60.0, 0.0)
	check(bool(cone.hit) and not game.crashed, "Driving into a cone knocks it over without a crash")
	var knocked := 0
	for o in game.road_event.objs:
		if bool(o.hit):
			knocked += 1
	check(knocked >= 1 and knocked <= 3 and game.bonus == bonus0 + knocked * Game.RW_CONE_PTS * game._effective_score_mult(), "Each knocked cone gives bonus points (%d knocked)" % knocked)
	check(game.speed < speed0 and game.speed > speed0 * 0.9, "A cone costs a little speed")
	var bonus1 := game.bonus
	game._update_road_events(1.0 / 60.0, 0.0)
	check(game.bonus == bonus1, "A cone pays only once")

	# Arrow sign: more points, more speed loss.
	_roadworks(game, 3)
	var arrow := _first(game, "arrow")
	game.road_event["y"] = game.player_y + float(arrow.off)
	game.lane = 3
	game.player_x = game.roadworks_object_pos(arrow).x
	bonus0 = game.bonus
	speed0 = game.speed
	game._update_road_events(1.0 / 60.0, 0.0)
	check(bool(arrow.hit) and not game.crashed and game.bonus == bonus0 + Game.RW_SIGN_PTS * game._effective_score_mult(), "An arrow sign can be knocked over for points")
	check(game.speed < speed0 * 0.97, "A sign costs more speed than a cone")

	# STOP barrier: crash in the closed lane, nothing in the open one.
	_roadworks(game, 0)
	game.road_event["y"] = (game.player_y - game.car_h * 0.40 - 10.0) + float(game.road_event.lead)
	game.lane = 1
	game.player_x = game._lane_x(1)
	game._update_road_events(1.0 / 60.0, 0.0)
	check(not game.crashed, "The open lane passes the STOP barrier")
	_roadworks(game, 0)
	game.road_event["y"] = (game.player_y - game.car_h * 0.40 - 10.0) + float(game.road_event.lead)
	game.lane = 0
	game.player_x = game._lane_x(0)
	game.rewind_frames.append(game._snapshot_state())
	game.nitro = 0.0
	game._update_road_events(1.0 / 60.0, 0.0)
	check(game.crashed and game.can_revive(), "Hitting the STOP barrier is a normal crash (revive still possible)")
	# Chrono-Shield applies too.
	_roadworks(game, 0)
	game.road_event["y"] = (game.player_y - game.car_h * 0.40 - 10.0) + float(game.road_event.lead)
	game.lane = 0
	game.player_x = game._lane_x(0)
	for _i in range(4):
		game.rewind_frames.append(game._snapshot_state())
	game.nitro = 1.0
	game._update_road_events(1.0 / 60.0, 0.0)
	check(game.rewinding and game._shield_active, "The Chrono-Shield catches a STOP barrier crash")
	# Warning text on first sight.
	_roadworks(game, 0)
	game.road_event["warned"] = false
	game.road_event["y"] = -100.0
	var banners: Array = []
	var cb := func(title: String, _sub: String, _col: Color): banners.append(title)
	game.road_event_banner.connect(cb)
	game._update_road_events(1.0 / 60.0, 80.0)
	game.road_event_banner.disconnect(cb)
	check(banners.has("ДОРОЖНЫЕ РАБОТЫ!"), "The warning shows when the roadside sign comes into view")


func check_roadworks_traffic(game: Game) -> void:
	# A car stuck in the closed lane (the lane beside it is full) waits behind
	# the taper instead of driving through the works.
	_roadworks(game, 0)
	game._rewind_invuln = 9999.0
	var taper_y := game.player_y - 600.0
	game.road_event["y"] = taper_y + float(game.road_event.lead) - float(game.road_event.taper_len)
	var stuck := _car(game, 0, taper_y + game.car_h * 1.6)
	var wall: Array = []
	for k in range(6):
		wall.append(_car(game, 1, taper_y - 200.0 + float(k) * game.car_h * 1.05, 0.7))
	game.cars = [stuck] + wall
	var passed := false
	for _i in range(120):
		for w in wall:
			w["cur_speed"] = float(stuck.get("cur_speed", 0.0))
		game._rewind_invuln = 9999.0
		game.road_event["y"] = float(game.road_event.y) + game.speed / 60.0
		game._move_traffic(1.0 / 60.0, game.speed, game.base_speed, false)
		if not game.cars.has(stuck):
			break  # scrolled off the bottom while waiting
		if int(stuck.lane) == 0 and float(stuck.get("lane_move_t", 0.0)) <= 0.0:
			if float(stuck.y) - float(stuck.h) * 0.5 < game.roadworks_taper_y() - 12.0:
				passed = true
	check(not passed, "Traffic in the closed lane never drives into the taper")
	check(float(stuck.cur_speed) < 40.0 or int(stuck.lane) != 0, "It stops behind the closure (or has left the lane)")
	# Nothing new appears in the closed lane, and no car moves into it.
	_roadworks(game, 0)
	var c := _car(game, 1, 400.0)
	game.cars = [c]
	check(not game._lane_change_safe(c, 0, 2.0), "No lane change into the closed lane")


func _rw_run_signature(game: Game) -> Array:
	game.challenge_config = {"type": "daily", "seed": 777001, "car_index": 1, "tod": 0.2, "weather": Game.WEATHER_CLEAR}
	game.start_run()
	game.road_event_t = 0.5
	game._last_event_type = Game.EVENT_BLACKOUT
	var hits := 0
	var seen := false
	for _i in range(60 * 30):
		game._rewind_invuln = 9999.0
		# Steer into the closed lane's cones when they come, deterministically.
		if game.road_event_type == Game.EVENT_ROADWORKS and game.lane != game.closed_lane:
			game.move_lane(-1 if game.closed_lane < game.lane else 1)
		game._tick(1.0 / 60.0)
		if game.road_event_type == Game.EVENT_ROADWORKS:
			seen = true
	if game.road_event_type == Game.EVENT_ROADWORKS:
		for o in game.road_event.objs:
			if bool(o.hit):
				hits += 1
	var sig: Array = [int(game.score), game.bonus, game.lane, game.cars.size(), game.road_event_type, hits, seen]
	for car in game.cars:
		sig.append([int(car.lane), snappedf(float(car.y), 0.01)])
	return sig


func check_roadworks_determinism(game: Game) -> void:
	var a := _rw_run_signature(game)
	seed(12345)
	var b := _rw_run_signature(game)
	print("[road] determinism run signature: ", a.slice(0, 7))
	check(a == b, "Two identical seeded runs through road works give identical results")


func check_auto_preset() -> void:
	var tiers := {
		"Adreno (TM) 750": GfxPresets.ULTRA,      # Galaxy S24 Ultra
		"Adreno (TM) 830": GfxPresets.ULTRA,
		"Adreno (TM) 740": GfxPresets.ULTRA,
		"Adreno (TM) 730": GfxPresets.HIGH,
		"Adreno (TM) 650": GfxPresets.MEDIUM,
		"Adreno (TM) 610": GfxPresets.LOW,
		"Mali-G715-Immortalis MC11": GfxPresets.ULTRA,
		"Immortalis-G720": GfxPresets.ULTRA,
		"Mali-G715 MC7": GfxPresets.HIGH,
		"Mali-G710 MC10": GfxPresets.HIGH,
		"Mali-G78 MP20": GfxPresets.MEDIUM,
		"Mali-G610 MC6": GfxPresets.MEDIUM,
		"Mali-G57 MC2": GfxPresets.LOW,
		"Samsung Xclipse 940": GfxPresets.ULTRA,
		"Samsung Xclipse 920": GfxPresets.HIGH,
		"llvmpipe (LLVM 15.0.7, 256 bits)": -1,
		"": -1,
	}
	for name in tiers:
		check(GfxPresets.gpu_tier(name) == int(tiers[name]), "GPU tier of \"%s\"" % name)
	# The S24 Ultra case: frames pinned at 60 Hz vsync on a top GPU -> Ultra.
	var pinned := PackedFloat32Array()
	for i in range(180):
		pinned.append(1.0 / 60.0 + (0.0004 if i % 2 == 0 else -0.0003))
	check(GfxBenchmark.is_vsync_bound(pinned, 60.0), "Frames pinned at the refresh interval are vsync-bound")
	check(int(GfxBenchmark.resolve(pinned, 60.0, "Adreno (TM) 750").level) == GfxPresets.ULTRA, "S24 Ultra (Adreno 750, vsync-bound 60 Hz) -> Ultra")
	check(int(GfxBenchmark.resolve(pinned, 60.0, "unknown GPU").level) == GfxPresets.HIGH, "Holding 60 FPS on High under vsync is at least High")
	var pinned120 := PackedFloat32Array()
	for i in range(240):
		pinned120.append(1.0 / 120.0)
	check(int(GfxBenchmark.resolve(pinned120, 120.0, "unknown GPU").level) == GfxPresets.ULTRA, "120 Hz vsync-bound -> Ultra")
	# Loading spike: a few huge frames must not decide the result.
	var spiky := PackedFloat32Array()
	for i in range(200):
		spiky.append(0.25 if i < 12 else 0.006)
	check(GfxBenchmark.median_ms(spiky) < 7.0, "The median ignores the loading spike")
	check(int(GfxBenchmark.resolve(spiky, 60.0, "").level) == GfxPresets.ULTRA, "Fast frames with a spike still give Ultra")
	check(not GfxBenchmark.is_vsync_bound(spiky, 60.0), "Uncapped fast frames are not vsync-bound")
	# A genuinely slow phone stays low; the tier lifts a slow result by one step only.
	var slow := PackedFloat32Array()
	for i in range(120):
		slow.append(0.032)
	check(int(GfxBenchmark.resolve(slow, 60.0, "Mali-G57 MC2").level) == GfxPresets.LOW, "Slow Mali-G57 -> Low")
	check(int(GfxBenchmark.resolve(slow, 60.0, "Adreno (TM) 750").level) == GfxPresets.HIGH, "A throttled flagship gets one step under its tier")
	check(GfxPresets.pick_auto(0.0, false, -1) == GfxPresets.MEDIUM, "No measurement and unknown GPU -> Medium")
