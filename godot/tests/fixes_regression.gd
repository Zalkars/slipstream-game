extends Node

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
	check_crash_frame_stops_scoring(game)
	check_cutin_not_double_counted(game)
	check_cutin_needs_real_overtake(game)
	check_rewind_restores_cutin(game)
	check_resize_keeps_lanes(game)
	print("[fixes] crash totals, cutin double-count, chasing cutin, rewind cutin trace, resize lanes: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(1 if failures else 0)


func _traffic(game: Game, y_off: float, cur_speed: float) -> Dictionary:
	return {
		"lane": game.lane,
		"x": game.player_x,
		"y": game.player_y + y_off,
		"w": game.car_w,
		"h": game.car_h,
		"kind": 0,
		"color": Color(0.5, 0.5, 0.5),
		"rel": 0.7,
		"cur_speed": cur_speed,
		"braking": false,
		"demo_speed": 0.0,
		"near": false,
		"cutin": false,
		"from_rear": false,
	}


# The result is fixed at the moment of the crash: the rest of the frame must not
# keep collecting pickups or scoring passes and drift away from that counter.
func check_crash_frame_stops_scoring(game: Game) -> void:
	game.start_run()
	game.cars = [_traffic(game, -10.0, game.speed)]
	# A coin about to land on the player: a post-crash pickup pass would claim it.
	game.items = [{"lane": game.lane, "x": game.player_x, "y": game.player_y - 30.0, "kind": 0, "phase": 0.0}]
	var sent := [-1, -1, -1, -1]
	var cb := func(score: int, dist: int, near: int, coins: int):
		sent.assign([score, dist, near, coins])
	game.run_ended.connect(cb)
	game._tick(1.0 / 60.0)
	game.run_ended.disconnect(cb)
	check(sent[3] >= 0, "Crash must emit a run result")
	check(game.crashed and not game.running, "Crash must end the run")
	check(game.items.size() == 1, "Coin must not be collected on the crash frame")
	check(game.pickup_coins == 0 and game.near == 0, "No pickups or passes may add to the totals after the crash")
	check(game._coins_total() == sent[3], "Game counter coins must match the result after the crash frame")
	check(int(game.score) == sent[0], "Game counter score must match the result after the crash frame")


# A car that already paid for a close pass must not be paid again as a cutin.
func check_cutin_not_double_counted(game: Game) -> void:
	game.start_run()
	game.speed = 900.0
	game.nitro = 0.5
	var car := _traffic(game, game.car_h + 60.0, 500.0)
	car["near"] = true
	game.cars = [car]
	game._cutin_window = 0.5
	game._cutin_lane = game.lane
	var before := [game.near, game.combo, game.bonus, game.nitro, game.pickup_coins]
	game._update_cutin(0.1)
	check(game.near == before[0] and game.combo == before[1] and game.bonus == before[2],
		"A car already paid as a close pass must not pay a second cutin")
	check(game.nitro == before[3] and game.pickup_coins == before[4],
		"A car already paid as a close pass must not pay a second charge or coins")
	check(not bool(car.get("cutin", false)), "The car must not be marked as cut in twice")


# A cutin needs a real overtake: the car's actual speed, not its theoretical
# target, decides whether it is still closing the gap.
func check_cutin_needs_real_overtake(game: Game) -> void:
	game.start_run()
	game.speed = 900.0
	game.nitro = 0.5
	var chasing := _traffic(game, game.car_h + 60.0, 1000.0)
	chasing["from_rear"] = true
	game.cars = [chasing]
	game._cutin_window = 0.5
	game._cutin_lane = game.lane
	game._update_cutin(0.1)
	check(game.nitro == 0.5 and game.near == 0 and game.combo == 0,
		"Cutting in on a car that is still catching up must not award nitro")
	# A car that has actually fallen behind still pays a clean cutin.
	game.start_run()
	game.speed = 900.0
	game.nitro = 0.5
	game.cars = [_traffic(game, game.car_h + 60.0, 500.0)]
	game._cutin_window = 0.5
	game._cutin_lane = game.lane
	game._update_cutin(0.1)
	check(game.near == 1 and game.combo == 1 and game.nitro > 0.5,
		"A genuinely overtaken car must still award the cutin charge")


# Rewinding must restore the state at the snapshot time, including any cut-in
# window in flight, so an undone maneuver cannot award nitro afterwards.
func check_rewind_restores_cutin(game: Game) -> void:
	game.start_run()
	game.tutorial_mode = true
	game._cutin_window = 0.0
	game._cutin_lane = -1
	game.cars = [_traffic(game, game.car_h + 60.0, 500.0)]
	game.rewind_frames = [game._snapshot_state()]
	# Later the player changes lanes, crashes, and rewinds to that snapshot.
	game._cutin_window = 0.8
	game._cutin_lane = game.lane
	game._begin_rewind()
	game._tick_rewind(0.04)
	check(not game.rewinding and game.running, "Rewind must finish")
	check(game._cutin_window == 0.0, "Rewind must not keep the canceled maneuver's cut-in window")
	check(game._cutin_lane == -1, "Rewind must not keep the canceled maneuver's cut-in lane")
	var nitro_before := game.nitro
	var near_before := game.near
	game._update_cutin(0.1)
	check(game.nitro == nitro_before and game.near == near_before,
		"No cutin may fire without a fresh lane change after rewind")


# A window resize moves the road and the player; already-spawned traffic and
# pickups must follow their lanes and keep their spacing.
func check_resize_keeps_lanes(game: Game) -> void:
	game.start_run()
	var car_lane := 1
	var item_lane := 2
	var car := _traffic(game, game.car_h + 400.0, game.speed)
	car["lane"] = car_lane
	car["x"] = game._lane_x(car_lane)
	game.cars = [car]
	game.items = [{"lane": item_lane, "x": game._lane_x(item_lane), "y": game.player_y - 260.0, "kind": 0, "phase": 0.0}]
	var old_player_y := game.player_y
	var car_ratio_w := float(car["w"]) / game.car_w
	var car_ratio_h := float(car["h"]) / game.car_h
	var car_y := float(car["y"])
	var item_y := float(game.items[0]["y"])
	game._layout(Vector2(360.0, 780.0))
	check(is_equal_approx(float(car["x"]), game._lane_x(car_lane)), "Traffic must stay on its lane after a resize")
	check(is_equal_approx(float(game.items[0]["x"]), game._lane_x(item_lane)), "Pickups must stay on their lane after a resize")
	check(is_equal_approx(float(car["y"]) - game.player_y, car_y - old_player_y), "Traffic must keep its distance from the player after a resize")
	check(is_equal_approx(float(game.items[0]["y"]) - game.player_y, item_y - old_player_y), "Pickups must keep their distance from the player after a resize")
	check(is_equal_approx(float(car["w"]) / game.car_w, car_ratio_w), "Traffic width must scale with the car after a resize")
	check(is_equal_approx(float(car["h"]) / game.car_h, car_ratio_h), "Traffic height must scale with the car after a resize")
