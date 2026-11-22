class_name ChallengeCodec
extends RefCounted

# Compact ghost + deterministic seed codec for asynchronous Friend Duels
# and deterministic Daily Challenges (no backend required).

const MAGIC_0 := 0x53  # 'S'
const MAGIC_1 := 0x4C  # 'L'
# The version also selects simulation rules. SLIP1 uses dry grip, SLIP2
# adds wet grip, and SLIP3 introduces separate seeded weather scheduling.
const VERSION := 3
const WEATHER_VERSION := 3
const LEGACY_VERSION := 1
const PREFIX := "SLIP3-"
const PREFIXES := [PREFIX, "SLIP2-", "SLIP1-"]
const WEATHER := preload("res://scripts/weather_schedule.gd")
const BASE_STEP_MS := 200
const MAX_SAMPLES := 900
const MAX_DECOMPRESSED := 65536


static func _crc16(bytes: PackedByteArray, length: int) -> int:
	var h := 0x9E37
	for i in range(length):
		h = ((h * 33) ^ int(bytes[i])) & 0xFFFF
	return h


static func _b64url_encode(raw: PackedByteArray) -> String:
	var s := Marshalls.raw_to_base64(raw)
	s = s.replace("+", "-").replace("/", "_")
	while s.ends_with("="):
		s = s.left(s.length() - 1)
	return s


static func _b64url_decode(s: String) -> PackedByteArray:
	var clean := s.strip_edges().replace("-", "+").replace("_", "/")
	var rem := clean.length() % 4
	if rem == 2:
		clean += "=="
	elif rem == 3:
		clean += "="
	elif rem == 1:
		return PackedByteArray()
	return Marshalls.base64_to_raw(clean)


static func _encode_u16(buf: PackedByteArray, off: int, v: int) -> void:
	buf[off] = v & 0xFF
	buf[off + 1] = (v >> 8) & 0xFF


static func _decode_u16(buf: PackedByteArray, off: int) -> int:
	return int(buf[off]) | (int(buf[off + 1]) << 8)


static func _encode_u32(buf: PackedByteArray, off: int, v: int) -> void:
	buf[off] = v & 0xFF
	buf[off + 1] = (v >> 8) & 0xFF
	buf[off + 2] = (v >> 16) & 0xFF
	buf[off + 3] = (v >> 24) & 0xFF


static func _decode_u32(buf: PackedByteArray, off: int) -> int:
	return int(buf[off]) | (int(buf[off + 1]) << 8) | (int(buf[off + 2]) << 16) | (int(buf[off + 3]) << 24)


static func sanitize_name(name_str: String) -> String:
	var cleaned := name_str.strip_edges()
	if cleaned.is_empty():
		return "ГОНЩИК"
	if cleaned.length() > 12:
		cleaned = cleaned.left(12)
	return cleaned


static func encode(data: Dictionary) -> String:
	var samples_in: Array = data.get("samples", [])
	var step_ms := int(data.get("step_ms", BASE_STEP_MS))
	var packed_samples: Array = samples_in.duplicate()
	while packed_samples.size() > MAX_SAMPLES and step_ms < 6400:
		var reduced: Array = []
		for i in range(0, packed_samples.size(), 2):
			reduced.append(packed_samples[i])
		if packed_samples.size() % 2 == 0 and not packed_samples.is_empty():
			reduced[reduced.size() - 1] = packed_samples.back()
		packed_samples = reduced
		step_ms *= 2

	var name_bytes := sanitize_name(str(data.get("name", "ГОНЩИК"))).to_utf8_buffer()
	if name_bytes.size() > 36:
		name_bytes = name_bytes.slice(0, 36)

	var header_len := 25 + name_bytes.size()
	var count := mini(packed_samples.size(), 65535)
	var total_len := header_len + count * 4 + 2
	var raw := PackedByteArray()
	raw.resize(total_len)

	raw[0] = MAGIC_0
	raw[1] = MAGIC_1
	var ver := clampi(int(data.get("physics", VERSION)), LEGACY_VERSION, VERSION)
	raw[2] = ver
	_encode_u32(raw, 3, int(data.get("seed", 1)) & 0x7FFFFFFF)
	raw[7] = clampi(int(data.get("car_index", 0)), 0, 255)
	_encode_u32(raw, 8, maxi(0, int(data.get("score", 0))))
	_encode_u32(raw, 12, maxi(0, int(data.get("distance", 0))))
	_encode_u16(raw, 16, clampi(int(data.get("near", 0)), 0, 65535))
	raw[18] = clampi(int(round(fposmod(float(data.get("tod", 0.15)), 1.0) * 255.0)), 0, 255)
	raw[19] = clampi(int(data.get("weather", 0)), 0, 4)
	_encode_u16(raw, 20, clampi(step_ms, 50, 65535))
	_encode_u16(raw, 22, clampi(int(round(maxf(0.0, float(data.get("end_time", 0.0))) * 10.0)), 0, 65535))
	raw[24] = name_bytes.size()
	for i in range(name_bytes.size()):
		raw[25 + i] = name_bytes[i]

	var prev_scroll := 0
	for i in range(count):
		var s: Dictionary = packed_samples[i]
		var sc := maxi(0, int(round(float(s.get("scroll", 0.0)))))
		var d_sc := clampi(sc - prev_scroll, 0, 65535)
		prev_scroll += d_sc
		var x_byte := clampi(int(round(clampf(float(s.get("x_norm", 0.5)), 0.0, 1.0) * 255.0)), 0, 255)
		var flags := int(s.get("flags", 0)) & 0xFF
		var off := header_len + i * 4
		_encode_u16(raw, off, d_sc)
		raw[off + 2] = x_byte
		raw[off + 3] = flags

	var crc := _crc16(raw, total_len - 2)
	_encode_u16(raw, total_len - 2, crc)

	var compressed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	return PREFIXES[VERSION - ver] + _b64url_encode(compressed)


static func extract_code(text: String) -> String:
	var idx := -1
	var prefix := ""
	for pf: String in PREFIXES:
		idx = text.find(pf)
		if idx >= 0:
			prefix = pf
			break
	if idx < 0:
		return ""
	var out := prefix
	for i in range(idx + prefix.length(), text.length()):
		var ch := text[i]
		var code_pt := ch.unicode_at(0)
		var ok := (
			(code_pt >= 48 and code_pt <= 57) or
			(code_pt >= 65 and code_pt <= 90) or
			(code_pt >= 97 and code_pt <= 122) or
			ch == "-" or ch == "_"
		)
		if not ok:
			break
		out += ch
	return out if out.length() > prefix.length() + 8 else ""


static func decode(raw_text: String) -> Dictionary:
	var code := extract_code(raw_text)
	if code.is_empty():
		return {"ok": false, "error": "Код вызова SLIP… не найден"}
	var payload := code.substr(PREFIX.length())
	var compressed := _b64url_decode(payload)
	if compressed.is_empty():
		return {"ok": false, "error": "Повреждённый код вызова"}
	var raw := compressed.decompress_dynamic(MAX_DECOMPRESSED, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() < 27:
		return {"ok": false, "error": "Неверный формат кода"}
	var ver := int(raw[2])
	if raw[0] != MAGIC_0 or raw[1] != MAGIC_1 or ver < LEGACY_VERSION or ver > VERSION or code.substr(0, 6) != PREFIXES[VERSION - ver]:
		return {"ok": false, "error": "Неподдерживаемая версия кода"}
	var body_len := raw.size() - 2
	var expected_crc := _decode_u16(raw, body_len)
	if _crc16(raw, body_len) != expected_crc:
		return {"ok": false, "error": "Ошибка контрольной суммы кода"}

	var name_len := int(raw[24])
	var header_len := 25 + name_len
	if header_len > body_len or (body_len - header_len) % 4 != 0:
		return {"ok": false, "error": "Повреждённые данные траектории"}

	var name_str := "ГОНЩИК"
	if name_len > 0:
		name_str = sanitize_name(raw.slice(25, header_len).get_string_from_utf8())

	var step_ms := _decode_u16(raw, 20)
	var step_sec := maxf(0.05, float(step_ms) / 1000.0)
	var sample_count := int((body_len - header_len) / 4)
	var samples: Array = []
	var cur_scroll := 0.0
	for i in range(sample_count):
		var off := header_len + i * 4
		cur_scroll += float(_decode_u16(raw, off))
		var x_norm := float(raw[off + 2]) / 255.0
		var flags := int(raw[off + 3])
		samples.append({
			"scroll": cur_scroll,
			"x_norm": x_norm,
			"flags": flags,
		})

	var end_scroll := cur_scroll
	var end_time := float(_decode_u16(raw, 22)) / 10.0
	if end_time <= 0.0 and sample_count > 0:
		end_time = float(maxi(0, sample_count - 1)) * step_sec

	return {
		"ok": true,
		"type": "duel",
		"code": code,
		"id": code_id(code),
		"seed": _decode_u32(raw, 3),
		"physics": ver,
		"car_index": clampi(int(raw[7]), 0, Cars.LIST.size() - 1),
		"score": _decode_u32(raw, 8),
		"distance": _decode_u32(raw, 12),
		"near": _decode_u16(raw, 16),
		"tod": float(raw[18]) / 255.0,
		"weather": clampi(int(raw[19]), 0, 4),
		"step_ms": step_ms,
		"step_sec": step_sec,
		"end_time": end_time,
		"end_scroll": end_scroll,
		"name": name_str,
		"samples": samples,
	}


static func code_id(code: String) -> String:
	var h1 := 0x811C9DC5
	var h2 := 0x1000193
	var bytes := code.to_utf8_buffer()
	for b in bytes:
		h1 = ((h1 ^ int(b)) * 16777619) & 0xFFFFFFFF
		h2 = ((h2 * 31) + int(b)) & 0xFFFFFFFF
	return "%08x%08x" % [h1, h2]


static func sample_ghost(data: Dictionary, duel_time: float) -> Dictionary:
	var samples: Array = data.get("samples", [])
	if samples.is_empty():
		return {"scroll": 0.0, "x_norm": 0.5, "braking": false, "boosting": false, "slingshot": false, "rewinding": false, "finished": true}
	var step_sec := maxf(0.05, float(data.get("step_sec", 0.2)))
	var end_time := float(data.get("end_time", float(samples.size() - 1) * step_sec))
	if duel_time >= end_time:
		var last: Dictionary = samples.back()
		return {
			"scroll": float(last.scroll),
			"x_norm": float(last.x_norm),
			"braking": false,
			"boosting": false,
			"slingshot": false,
			"rewinding": false,
			"finished": true,
		}
	var f_idx := clampf(duel_time / step_sec, 0.0, float(samples.size() - 1))
	var i0 := int(floor(f_idx))
	var i1 := mini(i0 + 1, samples.size() - 1)
	var frac := f_idx - float(i0)
	var s0: Dictionary = samples[i0]
	var s1: Dictionary = samples[i1]
	var flags := int(s0.flags)
	return {
		"scroll": lerpf(float(s0.scroll), float(s1.scroll), frac),
		"x_norm": lerpf(float(s0.x_norm), float(s1.x_norm), frac),
		"braking": (flags & 1) != 0,
		"boosting": (flags & 2) != 0,
		"slingshot": (flags & 4) != 0,
		"rewinding": (flags & 8) != 0,
		"finished": false,
	}


static func weather_label(w: int) -> String:
	match w:
		1:
			return "ОБЛАЧНО"
		2:
			return "ДОЖДЬ"
		3:
			return "ГРОЗА"
		4:
			return "ТУМАН"
		_:
			return "ЯСНО"


static func time_label(tod: float) -> String:
	var h := int(fposmod(tod * 24.0 + 6.0, 24.0))
	if h >= 6 and h < 17:
		return "ДЕНЬ"
	if h >= 17 and h < 21:
		return "ЗАКАТ"
	if h >= 21 or h < 5:
		return "НОЧЬ"
	return "РАССВЕТ"


static func daily_challenge(date_dict: Dictionary = {}) -> Dictionary:
	var d := date_dict if not date_dict.is_empty() else Time.get_date_dict_from_system()
	var y := int(d.get("year", 2026))
	var m := int(d.get("month", 1))
	var day := int(d.get("day", 1))
	var date_key := "%04d-%02d-%02d" % [y, m, day]
	var raw_key := y * 10000 + m * 100 + day
	var rng := RandomNumberGenerator.new()
	rng.seed = (raw_key * 2654435761) & 0x7FFFFFFF
	if rng.seed == 0:
		rng.seed = 20261119
	var seed_val := rng.randi() & 0x7FFFFFFF
	if seed_val == 0:
		seed_val = 777123
	var car_idx := rng.randi_range(0, Cars.LIST.size() - 1)
	var tod_choices := [0.15, 0.42, 0.68, 0.90]
	var tod := float(tod_choices[rng.randi_range(0, tod_choices.size() - 1)])
	var weather := WEATHER.pick(rng.randi_range(0, 99))
	var car := Cars.get_car(car_idx)
	var speed_k := float(car.top) / 1150.0
	var bronze := int(round(6500.0 * speed_k / 500.0)) * 500
	var silver := int(round(14500.0 * speed_k / 500.0)) * 500
	var gold := int(round(26000.0 * speed_k / 500.0)) * 500
	return {
		"ok": true,
		"type": "daily",
		"date_key": date_key,
		"seed": seed_val,
		"car_index": car_idx,
		"tod": tod,
		"weather": weather,
		"weather_label": weather_label(weather),
		"time_label": time_label(tod),
		"bronze": bronze,
		"silver": silver,
		"gold": gold,
	}


static func format_share_message(data: Dictionary, code: String, is_rematch := false) -> String:
	var car := Cars.get_car(int(data.get("car_index", 0)))
	var score := int(data.get("score", 0))
	var dist := int(data.get("distance", 0))
	var w_lbl := weather_label(int(data.get("weather", 0))).to_lower()
	var t_lbl := time_label(float(data.get("tod", 0.15))).to_lower()
	var head := "Реванш в SLIPSTREAM!" if is_rematch else "Вызов в SLIPSTREAM!"
	return "%s Я набрал %d очк. (%d м) на %s (%s, %s). Скопируй это сообщение и жми «ПРИНЯТЬ ВЫЗОВ»:\n%s" % [
		head, score, dist, str(car.name), t_lbl, w_lbl, code
	]
