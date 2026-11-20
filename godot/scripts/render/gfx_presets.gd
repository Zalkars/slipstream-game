class_name GfxPresets
extends RefCounted

# Graphics quality presets (0.8.0). Every visual system reads its budget from
# the dictionary returned by params(); nothing else in the renderer hard-codes
# a quality decision. "Auto" is resolved once by a short benchmark and stored
# as a concrete level, so the choice is stable between launches.

const LOW := 0
const MEDIUM := 1
const HIGH := 2
const ULTRA := 3
const AUTO := -1

const NAMES := ["НИЗКО", "СРЕДНЕ", "ВЫСОКО", "УЛЬТРА"]
const KEYS := ["low", "medium", "high", "ultra"]

# Post-effect buffer scales the dynamic resolution may step through.
const DYN_STEPS := [1.0, 0.75, 0.5, 0.35, 0.25]


static func params(level: int) -> Dictionary:
	match clampi(level, LOW, ULTRA):
		LOW:
			return {
				"level": LOW,
				"lights": 4,            # PointLight2D pool size
				"shadow_lights": 0,     # nearest N lights cast shadows
				"shadow_filter": 0,     # Light2D.SHADOW_FILTER_*
				"normal_maps": false,
				"post_scale": 0.25,     # fog / bloom buffer resolution
				"bloom": false,
				"rain_density": 0.35,
				"rain_layers": 2,
				"splashes": 40,
				"screen_drops": 0,      # 0 off, 1 lens sprites, 2 refraction
				"fog_octaves": 1,
				"fog_lights": 2,        # lights scattered by the fog shader
				"road_buffer_scale": 0.5,
				"trails": false,
				"max_sparks": 60,
				"spark_lights": 0,
				"puddle_ripples": false,
				"asphalt_detail": 0,    # 0 albedo only, 1 + variety, 2 + wet map
			}
		MEDIUM:
			return {
				"level": MEDIUM,
				"lights": 8,
				"shadow_lights": 2,
				"shadow_filter": 0,
				"normal_maps": true,
				"post_scale": 0.5,
				"bloom": true,
				"rain_density": 0.6,
				"rain_layers": 3,
				"splashes": 90,
				"screen_drops": 1,
				"fog_octaves": 2,
				"fog_lights": 4,
				"road_buffer_scale": 0.5,
				"trails": true,
				"max_sparks": 120,
				"spark_lights": 1,
				"puddle_ripples": true,
				"asphalt_detail": 1,
			}
		HIGH:
			return {
				"level": HIGH,
				"lights": 12,
				"shadow_lights": 4,
				"shadow_filter": 1,
				"normal_maps": true,
				"post_scale": 0.5,
				"bloom": true,
				"rain_density": 0.85,
				"rain_layers": 3,
				"splashes": 150,
				"screen_drops": 2,
				"fog_octaves": 3,
				"fog_lights": 6,
				"road_buffer_scale": 1.0,
				"trails": true,
				"max_sparks": 200,
				"spark_lights": 2,
				"puddle_ripples": true,
				"asphalt_detail": 2,
			}
	return {
		"level": ULTRA,
		"lights": 16,
		"shadow_lights": 8,
		"shadow_filter": 2,
		"normal_maps": true,
		"post_scale": 1.0,
		"bloom": true,
		"rain_density": 1.0,
		"rain_layers": 3,
		"splashes": 220,
		"screen_drops": 2,
		"fog_octaves": 4,
		"fog_lights": 8,
		"road_buffer_scale": 1.0,
		"trails": true,
		"max_sparks": 320,
		"spark_lights": 2,
		"puddle_ripples": true,
		"asphalt_detail": 2,
	}


static func level_name(level: int) -> String:
	if level == AUTO:
		return "АВТО"
	return NAMES[clampi(level, LOW, ULTRA)]


static func level_from_key(key: String) -> int:
	if key == "auto":
		return AUTO
	var i := KEYS.find(key)
	return i if i >= 0 else AUTO


static func key_from_level(level: int) -> String:
	if level == AUTO:
		return "auto"
	return KEYS[clampi(level, LOW, ULTRA)]


# The Auto benchmark renders the night-rain scene on HIGH with vsync and the
# frame cap disabled, then maps the average frame time to a preset. Medium
# costs roughly 60% of High and Low about 35%, so the thresholds leave each
# chosen preset ~20% headroom under a 16.7 ms (60 FPS) budget.
static func pick_from_benchmark(avg_ms: float) -> int:
	if avg_ms <= 0.0:
		return MEDIUM
	if avg_ms < 8.5:
		return ULTRA
	if avg_ms < 13.5:
		return HIGH
	if avg_ms < 22.0:
		return MEDIUM
	return LOW


# Dynamic resolution for post-effect buffers. Pure state machine so it can be
# unit-tested without a renderer: feed frame times, read scale().
class DynamicRes:
	extends RefCounted
	var max_step := 0          # index into DYN_STEPS allowed by the preset
	var step := 0
	var _avg := 0.0
	var _slow_t := 0.0
	var _fast_t := 0.0
	var budget := 1.0 / 60.0
	# With vsync the frame time sits at the budget even when there is headroom,
	# so recovering is a probe: step up after a calm period, and if that
	# immediately overloads again, wait twice as long before the next probe.
	var probe_wait := 8.0
	var _since_up := 99.0

	func reset(preset_scale: float, target_fps: int) -> void:
		max_step = 0
		for i in range(DYN_STEPS.size()):
			if DYN_STEPS[i] <= preset_scale + 0.001:
				max_step = i
				break
		step = max_step
		_avg = 0.0
		_slow_t = 0.0
		_fast_t = 0.0
		probe_wait = 8.0
		_since_up = 99.0
		budget = 1.0 / float(maxi(20, target_fps))

	func scale() -> float:
		return DYN_STEPS[step]

	# Returns true when the scale changed this frame.
	func feed(frame_s: float) -> bool:
		if frame_s <= 0.0 or frame_s > 0.25:
			return false  # hitches (loading, alt-tab) say nothing about load
		_since_up += frame_s
		_avg = frame_s if _avg <= 0.0 else lerpf(_avg, frame_s, 0.08)
		if _avg > budget * 1.18:
			_slow_t += frame_s
			_fast_t = 0.0
		elif _avg < budget * 1.06:
			_fast_t += frame_s
			_slow_t = 0.0
		else:
			_slow_t = 0.0
			_fast_t = 0.0
		if _slow_t > 1.5 and step < DYN_STEPS.size() - 1:
			step += 1
			_slow_t = 0.0
			_fast_t = 0.0
			if _since_up < 4.0:
				probe_wait = minf(probe_wait * 2.0, 64.0)
			return true
		if _fast_t > probe_wait and step > max_step:
			step -= 1
			_fast_t = 0.0
			_since_up = 0.0
			return true
		return false
