class_name GfxBenchmark
extends Node

# "Auto" graphics: on the first launch the demo behind the menu is switched to
# the heaviest everyday scene (night + rain) on the HIGH preset, with vsync and
# the frame cap lifted, for three seconds. The average frame time picks the
# preset (GfxPresets.pick_from_benchmark); everything is then restored.

signal finished(level: int, avg_ms: float)

const WARMUP := 0.6
const DURATION := 3.0

var game  # Game
var _t := 0.0
var _frames := 0
var _sum := 0.0
var _saved := {}
var _vsync := DisplayServer.VSYNC_ENABLED
var _max_fps := 60


func start(p_game) -> void:
	game = p_game
	_saved = {
		"tod": game.time_of_day, "weather": game.weather_state, "timer": game.weather_timer,
		"rain": game.rain_amount, "fog": game.fog_amount, "cloud": game.cloud_amount,
		"storm": game.storm_amount, "wet": game.wetness, "level": game.gfx_level,
	}
	game.time_of_day = 0.70
	game._snap_challenge_weather(0.70, game.WEATHER_RAIN)
	game.set_graphics(GfxPresets.HIGH, game.gfx_target_fps)
	_max_fps = Engine.max_fps
	_vsync = DisplayServer.window_get_vsync_mode()
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _process(delta: float) -> void:
	if game == null:
		return
	_t += delta
	if _t > WARMUP:
		_frames += 1
		_sum += delta
	if _t < WARMUP + DURATION:
		return
	var avg_ms := (_sum / maxf(1.0, float(_frames))) * 1000.0
	var level := GfxPresets.pick_from_benchmark(avg_ms)
	Engine.max_fps = _max_fps
	DisplayServer.window_set_vsync_mode(_vsync)
	game.time_of_day = float(_saved.tod)
	game.weather_state = int(_saved.weather)
	game.weather_timer = float(_saved.timer)
	game.rain_amount = float(_saved.rain)
	game.fog_amount = float(_saved.fog)
	game.cloud_amount = float(_saved.cloud)
	game.storm_amount = float(_saved.storm)
	game.wetness = float(_saved.wet)
	game.set_graphics(level, game.gfx_target_fps)
	print("[gfx] auto benchmark: %.2f ms over %d frames -> %s" % [avg_ms, _frames, GfxPresets.level_name(level)])
	finished.emit(level, avg_ms)
	queue_free()
