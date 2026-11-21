class_name GfxBenchmark
extends Node

# "Auto" graphics: the demo behind the menu is switched to the heaviest
# everyday scene (night + rain) on the HIGH preset, with vsync and the frame
# cap lifted, for three seconds. The choice combines that measurement with the
# GPU tier (GfxPresets.pick_auto); everything is then restored.
#
# 0.8.0 fixes (a Galaxy S24 Ultra got "Medium"):
# - Android may keep vsync on whatever we ask: frames pinned at the refresh
#   interval are reported as vsync-bound instead of "16.7 ms = Medium".
# - The median frame is used, after a longer warm-up, so the loading spike
#   and the first shader compiles of the rain scene do not count.
# - The GPU name gives a floor (Adreno 7xx, Mali-G7xx, Immortalis, Xclipse).

signal finished(level: int, avg_ms: float)

const WARMUP := 1.2
const DURATION := 3.0

var game  # Game
var _t := 0.0
var _deltas: PackedFloat32Array = PackedFloat32Array()
var _saved := {}
var _vsync := DisplayServer.VSYNC_ENABLED
var _max_fps := 60
var last_result := {}


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


# A race started during the test: give the frame cap and vsync back and stop
# without a result (start_run resets the scene the test had changed).
func cancel() -> void:
	if game != null:
		Engine.max_fps = _max_fps
		DisplayServer.window_set_vsync_mode(_vsync)
		game.set_graphics(int(_saved.get("level", game.gfx_level)), game.gfx_target_fps)
	game = null
	queue_free()


static func median_ms(deltas: PackedFloat32Array) -> float:
	if deltas.is_empty():
		return 0.0
	var sorted := deltas.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2]) * 1000.0


# Frames that never beat the display's refresh interval: the measurement only
# says "at least refresh-rate fast" (vsync or a compositor cap held it).
static func is_vsync_bound(deltas: PackedFloat32Array, refresh_hz: float) -> bool:
	if deltas.size() < 20:
		return false
	var hz := refresh_hz if refresh_hz > 1.0 else 60.0
	var interval := 1.0 / hz
	var sorted := deltas.duplicate()
	sorted.sort()
	var fast := float(sorted[sorted.size() / 10])  # 10th percentile
	var mid := float(sorted[sorted.size() / 2])
	return fast >= interval * 0.85 and mid <= interval * 1.15


static func resolve(deltas: PackedFloat32Array, refresh_hz: float, adapter: String) -> Dictionary:
	var ms := median_ms(deltas)
	var bound := is_vsync_bound(deltas, refresh_hz)
	var tier := GfxPresets.gpu_tier(adapter)
	return {"ms": ms, "vsync_bound": bound, "tier": tier, "level": GfxPresets.pick_auto(ms, bound, tier)}


func _process(delta: float) -> void:
	if game == null:
		return
	_t += delta
	if _t > WARMUP:
		_deltas.append(delta)
	if _t < WARMUP + DURATION:
		return
	last_result = resolve(_deltas, DisplayServer.screen_get_refresh_rate(), RenderingServer.get_video_adapter_name())
	var level := int(last_result.level)
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
	print("[gfx] auto benchmark: median %.2f ms over %d frames, vsync-bound %s, GPU \"%s\" tier %d -> %s" % [
		float(last_result.ms), _deltas.size(), str(last_result.vsync_bound), RenderingServer.get_video_adapter_name(),
		int(last_result.tier), GfxPresets.level_name(level)])
	finished.emit(level, float(last_result.ms))
	queue_free()
