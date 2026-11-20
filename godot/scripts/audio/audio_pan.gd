extends RefCounted

# Stereo placement through AudioStreamPlayer2D.
#
# Godot pans a 2D player by its x offset from the AudioListener2D divided by the
# viewport width, scaled by panning_strength and the project-wide
# audio/general/2d_panning_strength (default 0.5) and a constant 0.5, with a
# linear law (l = 1 - p, r = p). The listener and every player live at y = 0
# with a huge max_distance, so distance attenuation is ~1 and volume is ours.

const STRENGTH := 4.0
const MAX_DIST := 1.0e7

static var _global_strength := -1.0


static func make_player(bus_name: String) -> AudioStreamPlayer2D:
	var p := AudioStreamPlayer2D.new()
	p.bus = bus_name
	p.max_distance = MAX_DIST
	p.attenuation = 1.0
	p.panning_strength = STRENGTH
	p.area_mask = 0
	return p


static func _width(p: Node) -> float:
	var vp := p.get_viewport() if p.is_inside_tree() else null
	if vp == null:
		return 720.0
	# With an AudioListener2D Godot multiplies the offset by the canvas scale
	# (stretch mode), so divide it back out.
	var canvas_scale := absf((vp.get_global_canvas_transform() * vp.get_canvas_transform()).get_scale().x)
	return maxf(1.0, vp.get_visible_rect().size.x) / maxf(0.01, canvas_scale)


# pan: -1 hard left .. +1 hard right. volume_db is the loudness a centred,
# non-positional player would have; the linear pan law is compensated so a
# sound keeps its loudness as it moves across.
static func place(p: Node, pan: float, volume_db: float) -> void:
	var k := clampf(pan, -1.0, 1.0)
	if _global_strength < 0.0:
		_global_strength = float(ProjectSettings.get_setting("audio/general/2d_panning_strength", 0.5))
	var scale := maxf(0.05, STRENGTH * _global_strength)
	(p as Node2D).position = Vector2(k * _width(p) / scale, 0.0)
	var l := 0.5 - k * 0.5
	var r := 0.5 + k * 0.5
	p.volume_db = volume_db + 10.0 * log(2.0 / maxf(0.25, l * l + r * r)) / log(10.0)
