class_name ChallengeFiles
extends RefCounted

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const SHORT_LENGTH := 8
const EXTENSION := ".slipstream"
const HEADER := "SLIPSTREAM REPLAY 1\n"
const MAX_FILE_BYTES := ChallengeCodec.MAX_CODE_LENGTH + 128


static func short_code(replay: String) -> String:
	var digest := replay.sha256_buffer()
	var bits := 0
	for i in range(5):
		bits = (bits << 8) | digest[i]
	var code := ""
	for shift in range(35, -1, -5):
		code += ALPHABET[(bits >> shift) & 31]
	return code


static func normalize_code(value: String) -> String:
	var code := value.strip_edges().to_upper()
	if code.length() != SHORT_LENGTH:
		return ""
	for c in code:
		if not ALPHABET.contains(c):
			return ""
	return code


static func extract_code(value: String) -> String:
	var marker := "Код вызова"
	var offset := value.findn(marker)
	if offset >= 0:
		var token := value.substr(offset + marker.length()).strip_edges().left(SHORT_LENGTH + 1)
		if token.length() == SHORT_LENGTH or (token.length() > SHORT_LENGTH and token[SHORT_LENGTH] in [" ", "\n", "\r", "\t"]):
			return normalize_code(token.left(SHORT_LENGTH))
	return normalize_code(value)


static func filename(code: String) -> String:
	return "Slipstream-" + code + EXTENSION


static func contents(replay: String) -> String:
	return HEADER + replay + "\n"


static func read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Не удалось открыть файл заезда."}
	var bytes := file.get_buffer(MAX_FILE_BYTES + 1)
	if bytes.size() > MAX_FILE_BYTES:
		return {"ok": false, "error": "Файл заезда слишком большой."}
	var text := bytes.get_string_from_utf8()
	if not text.begins_with(HEADER):
		return {"ok": false, "error": "Это не файл вызова SLIPSTREAM."}
	return ChallengeCodec.decode(text.substr(HEADER.length()))


static func write(path: String, replay: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(contents(replay))
	file.flush()
	return file.get_error()
