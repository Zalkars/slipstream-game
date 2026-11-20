class_name GroundPainter
extends RefCounted

# Grass verge and concrete shoulders: the bottom layer of the frame. Lit by the
# 2D lights (light mask 1) so headlights and street lamps spill onto the verge.

var game  # Game
var grass_tex: Texture2D


func _init(p_game) -> void:
	game = p_game


func paint(ci: CanvasItem) -> void:
	_paint_grass(ci)
	_paint_shoulders(ci)


func _paint_grass(ci: CanvasItem) -> void:
	var W: float = game.W
	var H: float = game.H
	var scroll: float = game.scroll
	var amb := Color.WHITE  # ambient comes from the CanvasModulate
	ci.draw_rect(Rect2(0.0, 0.0, W, H), Color(0.40, 0.50, 0.30))
	if grass_tex:
		var off := fposmod(scroll, 128.0)
		ci.draw_texture_rect(grass_tex, Rect2(0.0, off - 128.0, W, H + 128.0), true, Color(amb.r, amb.g, amb.b, 0.62))
	var period := 380.0
	var off2 := fposmod(scroll, period)
	var count := int(H / period) + 3
	for i in range(count):
		var y := off2 + i * period - period
		ci.draw_circle(Vector2(W * 0.06, y + 40.0), 34.0, Color(0.26, 0.35, 0.19, 0.18))
		ci.draw_circle(Vector2(W * 0.94, y + 170.0), 42.0, Color(0.26, 0.35, 0.19, 0.16))
	# A wet verge goes darker and a little cooler.
	var wet: float = game.wetness
	if wet > 0.03:
		ci.draw_rect(Rect2(0.0, 0.0, W, H), Color(0.04, 0.07, 0.06, wet * 0.22))


func _paint_shoulders(ci: CanvasItem) -> void:
	var H: float = game.H
	var road_x: float = game.road_x
	var road_w: float = game.road_w
	var scroll: float = game.scroll
	var amb := Color.WHITE  # ambient comes from the CanvasModulate
	var sh := 27.0
	var col := Color(0.62, 0.62, 0.58) * amb
	col.a = 1.0
	var wet: float = game.wetness
	if wet > 0.03:
		col = col.lerp(col * Color(0.62, 0.64, 0.68), wet * 0.6)
	ci.draw_rect(Rect2(road_x - sh, 0.0, sh, H), col)
	ci.draw_rect(Rect2(road_x + road_w, 0.0, sh, H), col)
	ci.draw_rect(Rect2(road_x - sh, 0.0, sh, H), Color(0.35, 0.36, 0.33, 0.10))
	ci.draw_rect(Rect2(road_x + road_w, 0.0, sh, H), Color(0.35, 0.36, 0.33, 0.10))
	ci.draw_rect(Rect2(road_x - sh - 2.0, 0.0, 2.0, H), Color(0.15, 0.16, 0.14, 0.55))
	ci.draw_rect(Rect2(road_x + road_w, 0.0, 2.0, H), Color(0.15, 0.16, 0.14, 0.55))
	ci.draw_rect(Rect2(road_x - sh, 0.0, 2.0, H), Color(0.16, 0.17, 0.16, 0.35))
	ci.draw_rect(Rect2(road_x + road_w + sh - 2.0, 0.0, 2.0, H), Color(0.16, 0.17, 0.16, 0.35))
	var period := 170.0
	var off := fposmod(scroll, period)
	var y := off - period
	while y < H + period:
		ci.draw_rect(Rect2(road_x - sh, y, sh, 1.5), Color(0.18, 0.18, 0.17, 0.35))
		ci.draw_rect(Rect2(road_x + road_w, y, sh, 1.5), Color(0.18, 0.18, 0.17, 0.35))
		y += period
	# Sand and grit washed against the kerb: a thin speckled strip that scrolls
	# with the road (road details, Stage 3).
	var grit_period := 64.0
	var gy := fposmod(scroll, grit_period) - grit_period
	var i := 0
	while gy < H + grit_period:
		var h := float((i * 7919) % 97) / 97.0
		for side in [0, 1]:
			var gx: float = road_x + 3.0 + h * 9.0 if side == 0 else road_x + road_w - 12.0 + h * 9.0
			ci.draw_rect(Rect2(gx, gy + h * 40.0, 2.0 + h * 2.0, 1.5), Color(0.62, 0.58, 0.48, 0.20))
		gy += grit_period
		i += 1
