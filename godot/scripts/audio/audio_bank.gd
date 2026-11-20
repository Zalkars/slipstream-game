extends RefCounted

# Loads the baked OGG assets under res://audio/ (built by tools/audio/build_audio.py)
# and caches them. A missing file returns null so the game stays silent instead
# of crashing, e.g. before the first import on a fresh checkout.

const BASE := "res://audio/"

const ENGINE_SPECS := preload("res://scripts/audio/engine_specs.gd")

static var _cache: Dictionary = {}


static func stream(asset: String, loop := false) -> AudioStream:
	if _cache.has(asset):
		return _cache[asset]
	var path := BASE + asset + ".ogg"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path) as AudioStream
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = loop
	_cache[asset] = s
	return s


static func clear() -> void:
	_cache.clear()


static func stream_length(asset: String) -> float:
	var s := stream(asset)
	return s.get_length() if s != null else 0.0


static func engines() -> Dictionary:
	return ENGINE_SPECS.SPECS
