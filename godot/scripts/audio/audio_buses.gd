extends RefCounted

# Bus layout (built in code so project.godot stays untouched):
#
#   Master  <- compressor (glue) -> hard limiter (no clipping on phones)
#   ├─ Music
#   └─ SFX                      (the player's "Sound" switch and slider)
#      ├─ Engine                own car: engine, tyres, brakes, nitro
#      ├─ World                 traffic, impacts, road features; LPF + reverb
#      │                        for fog and bridges/underpasses
#      ├─ Ambient               rain, wind, birds, city; LPF + reverb (fog)
#      └─ UI                    menu and reward sounds, never filtered

const LAYOUT := [
	["SFX", "Master", 0.0],
	["Music", "Master", 0.0],
	["Engine", "SFX", 0.0],
	["World", "SFX", -1.5],
	["Ambient", "SFX", -3.0],
	["UI", "SFX", -2.0],
]

# Effect slots on World and Ambient (index order on the bus).
const FX_LPF := 0
const FX_REVERB := 1


static func setup() -> void:
	for entry in LAYOUT:
		var name: String = entry[0]
		if AudioServer.get_bus_index(name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, name)
	# Sends are set after all buses exist so a child can point at any parent.
	for entry in LAYOUT:
		var idx := AudioServer.get_bus_index(entry[0])
		AudioServer.set_bus_send(idx, entry[1])
		if entry[0] != "SFX" and entry[0] != "Music":
			AudioServer.set_bus_volume_db(idx, entry[2])
	_master_chain()
	_filter_chain("World")
	_filter_chain("Ambient")


static func _master_chain() -> void:
	var m := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(m) > 0:
		return
	var comp := AudioEffectCompressor.new()
	comp.threshold = -14.0
	comp.ratio = 3.0
	comp.attack_us = 8000.0
	comp.release_ms = 180.0
	comp.gain = 1.5
	AudioServer.add_bus_effect(m, comp)
	var lim: AudioEffect
	if ClassDB.class_exists("AudioEffectHardLimiter"):
		lim = ClassDB.instantiate("AudioEffectHardLimiter")
		lim.set("ceiling_db", -0.7)
	else:
		lim = AudioEffectLimiter.new()
		lim.set("ceiling_db", -0.7)
	AudioServer.add_bus_effect(m, lim)


static func _filter_chain(bus: String) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if AudioServer.get_bus_effect_count(idx) > 0:
		return
	var lpf := AudioEffectLowPassFilter.new()
	lpf.cutoff_hz = 20000.0
	lpf.resonance = 0.5
	AudioServer.add_bus_effect(idx, lpf)
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.55
	rev.damping = 0.6
	rev.spread = 0.8
	rev.hipass = 0.15
	rev.predelay_msec = 35.0
	rev.predelay_feedback = 0.25
	rev.dry = 1.0
	rev.wet = 0.0
	AudioServer.add_bus_effect(idx, rev)
	# Effects are off until they matter: a bypassed reverb costs nothing.
	AudioServer.set_bus_effect_enabled(idx, FX_LPF, false)
	AudioServer.set_bus_effect_enabled(idx, FX_REVERB, false)


static func effect(bus: String, slot: int) -> AudioEffect:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0 or slot >= AudioServer.get_bus_effect_count(idx):
		return null
	return AudioServer.get_bus_effect(idx, slot)


# Fog and overhead structures: one call drives both filter chains so the world
# gets muffled and roomy together. amount values are 0..1.
static func set_space(bus: String, cutoff_hz: float, reverb_wet: float, room: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0 or AudioServer.get_bus_effect_count(idx) < 2:
		return
	var lpf := AudioServer.get_bus_effect(idx, FX_LPF) as AudioEffectLowPassFilter
	var rev := AudioServer.get_bus_effect(idx, FX_REVERB) as AudioEffectReverb
	var use_lpf := cutoff_hz < 17000.0
	var use_rev := reverb_wet > 0.01
	if lpf != null:
		lpf.cutoff_hz = cutoff_hz
	if rev != null:
		rev.wet = reverb_wet
		rev.room_size = room
	if AudioServer.is_bus_effect_enabled(idx, FX_LPF) != use_lpf:
		AudioServer.set_bus_effect_enabled(idx, FX_LPF, use_lpf)
	if AudioServer.is_bus_effect_enabled(idx, FX_REVERB) != use_rev:
		AudioServer.set_bus_effect_enabled(idx, FX_REVERB, use_rev)
