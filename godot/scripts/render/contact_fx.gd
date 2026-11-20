class_name ContactFx
extends RefCounted

# Tyre marks baked into the road buffer (Stage 1 port of the 0.7.0 marks).

var game  # Game
var stack  # RenderStack
var _has_prev := false
var _prev_l := Vector2.ZERO
var _prev_r := Vector2.ZERO
var _prev_scroll := 0.0


func setup(p_game, p_stack) -> void:
	game = p_game
	stack = p_stack


func frame(_dt: float) -> void:
	var g = game
	var skidding: bool = g.braking and not g.overheated and g.running and not g.crashed and g.speed > 130.0
	if not skidding:
		_has_prev = false
		return
	var wheel_y: float = g.player_y + g.car_h * 0.34
	var l := Vector2(g.player_x - g.car_w * 0.31, wheel_y)
	var r := Vector2(g.player_x + g.car_w * 0.31, wheel_y)
	var scroll: float = g.scroll
	if _has_prev:
		var travel := scroll - _prev_scroll
		var col := Color(0.04, 0.05, 0.06, 0.40)
		var w: float = g.car_w * 0.16
		stack.road_buffer.line(_prev_l + Vector2(0, travel), l, w, col, scroll)
		stack.road_buffer.line(_prev_r + Vector2(0, travel), r, w, col, scroll)
	_prev_l = l
	_prev_r = r
	_prev_scroll = scroll
	_has_prev = true
