class_name Asphalt
extends RefCounted

# Road surface and markings (port of the 0.7.0 painter; replaced by the
# procedural material in Stage 3).

var game  # Game
var asphalt_tex: Texture2D


func _init(p_game) -> void:
	game = p_game


func apply_params(_p: Dictionary) -> void:
	pass


func paint_surface(ci: CanvasItem) -> void:
	var g = game
	var H: float = g.H
	var road_x: float = g.road_x
	var road_w: float = g.road_w
	var lane_w: float = g.lane_w
	var scroll: float = g.scroll
	var amb := Color.WHITE  # ambient comes from the CanvasModulate
	if g.rain_amount > 0.01:
		amb = amb.lerp(amb * Color(0.78, 0.78, 0.82), g.rain_amount * 0.42)
	ci.draw_rect(Rect2(road_x, 0.0, road_w, H), Color(0.355, 0.365, 0.385) * amb)
	if asphalt_tex:
		var tile := 256.0
		var off := fposmod(scroll, tile)
		ci.draw_texture_rect(asphalt_tex, Rect2(road_x, off - tile, road_w, H + tile * 2.0), true, amb)
	for l in range(g.LANES):
		var cx: float = g._lane_x(l)
		var sw := lane_w * 0.19
		ci.draw_rect(Rect2(cx - lane_w * 0.35 - sw * 0.5, 0.0, sw, H), Color(0.06, 0.06, 0.07, 0.060))
		ci.draw_rect(Rect2(cx + lane_w * 0.35 - sw * 0.5, 0.0, sw, H), Color(0.06, 0.06, 0.07, 0.060))
	var ew := 34.0
	Fx.hgrad(ci, Rect2(road_x, 0.0, ew, H), Color(0, 0, 0, 0.22), Color(0, 0, 0, 0.0))
	Fx.hgrad(ci, Rect2(road_x + road_w - ew, 0.0, ew, H), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.22))
	var seam_period := 760.0
	var seam_y := fposmod(scroll, seam_period) - seam_period
	while seam_y < H + seam_period:
		ci.draw_rect(Rect2(road_x + 5.0, seam_y, road_w - 10.0, 2.0), Color(0.05, 0.05, 0.06, 0.11))
		seam_y += seam_period
	var wet: float = g.wetness
	if wet > 0.03:
		ci.draw_rect(Rect2(road_x, 0.0, road_w, H), Color(0.08, 0.10, 0.14, wet * 0.15))


func paint_markings(ci: CanvasItem) -> void:
	var g = game
	var H: float = g.H
	var road_x: float = g.road_x
	var road_w: float = g.road_w
	var lane_w: float = g.lane_w
	var scroll: float = g.scroll
	var paint := Color(0.95, 0.94, 0.89, 0.93)
	ci.draw_rect(Rect2(road_x + 12.0, 0.0, 7.0, H), paint)
	ci.draw_rect(Rect2(road_x + road_w - 19.0, 0.0, 7.0, H), paint)
	var period := 250.0
	var dash := 96.0
	var off := fposmod(scroll, period)
	for l in range(1, g.LANES):
		var x := road_x + lane_w * l - 3.5
		var y := off - period
		while y < H + period:
			ci.draw_rect(Rect2(x, y, 7.0, dash), paint)
			y += period
