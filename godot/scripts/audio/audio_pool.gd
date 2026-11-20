extends Node

# A fixed set of players reused for one-shots: nothing is allocated while
# driving. When every voice is busy the oldest one is stolen.
#
# Positional pools use AudioStreamPlayer2D only for its stereo panning: the
# players sit on a line through the session's AudioListener2D, so "pan" is a
# plain -1..1 value and distance attenuation stays in our own volume maths.

const PAN := preload("res://scripts/audio/audio_pan.gd")

var bus := "SFX"
var positional := false
var _players: Array = []
var _started: PackedFloat64Array = PackedFloat64Array()


func setup(count: int, bus_name: String, is_positional: bool) -> void:
	bus = bus_name
	positional = is_positional
	for i in range(count):
		var p: Node
		if positional:
			p = PAN.make_player(bus_name)
		else:
			var q := AudioStreamPlayer.new()
			q.bus = bus_name
			p = q
		add_child(p)
		_players.append(p)
	_started.resize(count)


func play(stream: AudioStream, volume_db := 0.0, pitch := 1.0, pan := 0.0, from := 0.0) -> Node:
	if stream == null or _players.is_empty():
		return null
	var pick := -1
	var oldest := INF
	for i in range(_players.size()):
		if not _players[i].playing:
			pick = i
			break
		if _started[i] < oldest:
			oldest = _started[i]
			pick = i
	var p: Node = _players[pick]
	p.stop()
	p.stream = stream
	p.pitch_scale = clampf(pitch, 0.05, 4.0)
	if positional:
		PAN.place(p, pan, volume_db)
	else:
		p.volume_db = volume_db
	p.play(from)
	_started[pick] = Time.get_ticks_msec() / 1000.0
	return p


func stop_all() -> void:
	for p in _players:
		p.stop()
