class_name ZonesPad
extends Control

# Two-zone driving control: left half moves left, right half moves right.
# Touching both zones simultaneously engages braking.
# Robust touch-tracking prevents phantom turns when pressing or releasing the brake.

signal lane_left
signal lane_right
signal brake_changed(on: bool)

var font_bold: Font
var font_ui: Font
var accent := Color("#e23b30")
var amber := Color("#f2b134")

var touches := {}
var _braking_touch_ids := {}
var _suppressed_touch_ids := {}

var _left_down := false
var _right_down := false
var _braking := false

var _pending_turn_side := 0 # -1 left, +1 right, 0 none
var _pending_turn_timer := 0.0
var _pending_turn_id := -999

var _brake_release_cooldown := 0.0
var _repeat_left := 0.0
var _repeat_right := 0.0

var _anim_left := 0.0
var _anim_right := 0.0
var _anim_brake := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(720, 260)
	set_process(true)


func reset() -> void:
	touches.clear()
	_braking_touch_ids.clear()
	_suppressed_touch_ids.clear()
	_left_down = false
	_right_down = false
	_pending_turn_side = 0
	_pending_turn_timer = 0.0
	_pending_turn_id = -999
	_brake_release_cooldown = 0.0
	if _braking:
		_braking = false
		brake_changed.emit(false)
	_anim_left = 0.0
	_anim_right = 0.0
	_anim_brake = 0.0
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var idx: int = event.index
		if event.pressed:
			touches[idx] = event.position
			_on_touch_down(idx, event.position)
		else:
			_on_touch_up(idx)
			touches.erase(idx)
			_braking_touch_ids.erase(idx)
			_suppressed_touch_ids.erase(idx)
			_evaluate_touches()
		accept_event()
	elif event is InputEventScreenDrag:
		var idx: int = event.index
		touches[idx] = event.position
		_evaluate_touches()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var idx := -1
		if event.pressed:
			touches[idx] = event.position
			_on_touch_down(idx, event.position)
		else:
			_on_touch_up(idx)
			touches.erase(idx)
			_braking_touch_ids.erase(idx)
			_suppressed_touch_ids.erase(idx)
			_evaluate_touches()
		accept_event()


func _on_touch_down(idx: int, pos: Vector2) -> void:
	var mid_x := size.x * 0.5
	var side := -1 if pos.x < mid_x else 1

	# Check if both sides now have active touches
	var has_left := false
	var has_right := false
	for tid in touches:
		var p: Vector2 = touches[tid]
		if p.x < mid_x:
			has_left = true
		else:
			has_right = true

	if has_left and has_right:
		# Simultaneous two-zone touch -> engage brake immediately
		_pending_turn_side = 0
		_pending_turn_timer = 0.0
		_pending_turn_id = -999
		_suppress_all_current_touches()
		if not _braking:
			_braking = true
			brake_changed.emit(true)
		_left_down = false
		_right_down = false
		queue_redraw()
		return

	if _braking:
		_suppressed_touch_ids[idx] = true
		return

	# If cooldown from a recent brake release is still running, suppress lingering finger
	if _brake_release_cooldown > 0.0:
		_suppressed_touch_ids[idx] = true
		return

	# Buffer single tap briefly (45ms) so if the other thumb lands almost simultaneously to brake,
	# no accidental turn is triggered!
	_pending_turn_side = side
	_pending_turn_timer = 0.045
	_pending_turn_id = idx


func _on_touch_up(idx: int) -> void:
	# Quick tap release before buffer expired: trigger immediate turn if not suppressed
	if idx == _pending_turn_id and _pending_turn_side != 0 and not _suppressed_touch_ids.has(idx):
		if _pending_turn_side == -1:
			lane_left.emit()
		elif _pending_turn_side == 1:
			lane_right.emit()
		_pending_turn_side = 0
		_pending_turn_timer = 0.0
		_pending_turn_id = -999


func _suppress_all_current_touches() -> void:
	for tid in touches:
		_braking_touch_ids[tid] = true
		_suppressed_touch_ids[tid] = true


func _evaluate_touches() -> void:
	var mid_x := size.x * 0.5
	var left := false
	var right := false

	for idx in touches:
		var p: Vector2 = touches[idx]
		if p.x < mid_x:
			left = true
		else:
			right = true

	var want_brake := left and right
	if want_brake:
		_suppress_all_current_touches()
		_pending_turn_side = 0
		_pending_turn_timer = 0.0
		_pending_turn_id = -999
		if not _braking:
			_braking = true
			brake_changed.emit(true)
		_left_down = false
		_right_down = false
	else:
		if _braking:
			# Braking ended because at least one thumb lifted
			_braking = false
			brake_changed.emit(false)
			# Grace cooldown: touches that were held during brake MUST NOT steer
			_suppress_all_current_touches()
			_brake_release_cooldown = 0.15
			_left_down = false
			_right_down = false
			_pending_turn_side = 0
			_pending_turn_timer = 0.0
			_pending_turn_id = -999

		# Check for continuous steering only from unsuppressed touches
		var valid_left := false
		var valid_right := false
		for idx in touches:
			if _suppressed_touch_ids.has(idx):
				continue
			var p: Vector2 = touches[idx]
			if p.x < mid_x:
				valid_left = true
			else:
				valid_right = true

		if not valid_left:
			_left_down = false
		if not valid_right:
			_right_down = false

	queue_redraw()


func _process(delta: float) -> void:
	if _brake_release_cooldown > 0.0:
		_brake_release_cooldown = maxf(0.0, _brake_release_cooldown - delta)

	# Handle buffered turn initiation
	if _pending_turn_side != 0:
		_pending_turn_timer -= delta
		if _pending_turn_timer <= 0.0:
			if not _suppressed_touch_ids.has(_pending_turn_id):
				if _pending_turn_side == -1:
					_left_down = true
					_repeat_left = 0.28
					lane_left.emit()
				elif _pending_turn_side == 1:
					_right_down = true
					_repeat_right = 0.28
					lane_right.emit()
			_pending_turn_side = 0
			_pending_turn_timer = 0.0
			_pending_turn_id = -999

	# Handle held repeat
	if not _braking:
		if _left_down:
			_repeat_left -= delta
			if _repeat_left <= 0.0:
				lane_left.emit()
				_repeat_left = 0.18
		if _right_down:
			_repeat_right -= delta
			if _repeat_right <= 0.0:
				lane_right.emit()
				_repeat_right = 0.18

	var target_left := 1.0 if (_left_down or _braking or _pending_turn_side == -1) else 0.0
	var target_right := 1.0 if (_right_down or _braking or _pending_turn_side == 1) else 0.0
	var target_brake := 1.0 if _braking else 0.0
	var k := minf(1.0, delta * 15.0)
	_anim_left = lerpf(_anim_left, target_left, k)
	_anim_right = lerpf(_anim_right, target_right, k)
	_anim_brake = lerpf(_anim_brake, target_brake, k)
	queue_redraw()


func _draw() -> void:
	var h := size.y
	# Left zone box: x 16 .. 270 (width 254)
	var r_left := Rect2(16, 12, 254, h - 24)
	# Right zone box: x (size.x - 270) .. (size.x - 16) (width 254)
	var r_right := Rect2(size.x - 270.0, 12, 254, h - 24)
	var rad := 22.0

	var base_bg := Color(0.04, 0.05, 0.06, 0.36)
	var active_left_bg := Color(0.20, 0.25, 0.30, 0.58).lerp(Color(0.48, 0.20, 0.08, 0.65), _anim_brake)
	var active_right_bg := Color(0.20, 0.25, 0.30, 0.58).lerp(Color(0.48, 0.20, 0.08, 0.65), _anim_brake)

	var bg_l := base_bg.lerp(active_left_bg, _anim_left)
	var bg_r := base_bg.lerp(active_right_bg, _anim_right)

	# Shadow & card backgrounds
	Art.rr(self, Rect2(r_left.position + Vector2(0, 2), r_left.size), Color(0, 0, 0, 0.24), rad)
	Art.rr(self, r_left, bg_l, rad)
	Art.rr(self, Rect2(r_right.position + Vector2(0, 2), r_right.size), Color(0, 0, 0, 0.24), rad)
	Art.rr(self, r_right, bg_r, rad)

	# Borders
	var border_l := Color(1, 1, 1, 0.12).lerp(amber, _anim_brake).lerp(Color(1, 1, 1, 0.45), _anim_left * (1.0 - _anim_brake))
	var border_r := Color(1, 1, 1, 0.12).lerp(amber, _anim_brake).lerp(Color(1, 1, 1, 0.45), _anim_right * (1.0 - _anim_brake))
	_draw_rect_outline(r_left, rad, border_l, 1.8)
	_draw_rect_outline(r_right, rad, border_r, 1.8)

	# Left chevron + label
	var c_l := r_left.get_center()
	var col_l := Color(1, 1, 1, 0.90 if _left_down else 0.62).lerp(amber, _anim_brake)
	_draw_chevron(c_l + Vector2(-36, 0), -1.0, 24.0, col_l)
	if font_bold:
		var txt_l := "ВЛЕВО"
		var fs := 22
		draw_string(font_bold, c_l + Vector2(-8, fs * 0.35), txt_l, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col_l)

	# Right chevron + label
	var c_r := r_right.get_center()
	var col_r := Color(1, 1, 1, 0.90 if _right_down else 0.62).lerp(amber, _anim_brake)
	_draw_chevron(c_r + Vector2(36, 0), 1.0, 24.0, col_r)
	if font_bold:
		var txt_r := "ВПРАВО"
		var fs := 22
		var tw := font_bold.get_string_size(txt_r, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
		draw_string(font_bold, c_r + Vector2(8 - tw, fs * 0.35), txt_r, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col_r)

	# Top hint / braking status
	if font_bold:
		if _braking:
			var txt_b := "— ТОРМОЖЕНИЕ —"
			var fs_b := 20
			var tw_b := font_bold.get_string_size(txt_b, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_b).x
			draw_string(font_bold, Vector2((size.x - tw_b) * 0.5, 26), txt_b, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_b, amber)
		else:
			var txt_h := "ОБЕ СТОРОНЫ: ТОРМОЗ"
			var fs_h := 16
			var tw_h := font_bold.get_string_size(txt_h, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_h).x
			draw_string(font_bold, Vector2((size.x - tw_h) * 0.5, 24), txt_h, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_h, Color(1, 1, 1, 0.38))


func _draw_chevron(c: Vector2, dir: float, r: float, col: Color) -> void:
	var w := r * 0.46
	var h := r * 0.75
	draw_polyline(
		PackedVector2Array([
			Vector2(c.x - dir * w, c.y - h),
			Vector2(c.x + dir * w * 0.6, c.y),
			Vector2(c.x - dir * w, c.y + h),
		]),
		col, 4.0, true
	)


func _draw_rect_outline(rect: Rect2, rad: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	var segs := 8
	var corners := [
		Vector2(rect.position.x + rad, rect.position.y + rad),
		Vector2(rect.end.x - rad, rect.position.y + rad),
		Vector2(rect.end.x - rad, rect.end.y - rad),
		Vector2(rect.position.x + rad, rect.end.y - rad),
	]
	var angles := [PI, PI * 1.5, 0.0, PI * 0.5]
	for i in range(4):
		var cc: Vector2 = corners[i]
		var a0: float = angles[i]
		for s in range(segs + 1):
			var a: float = a0 + (PI * 0.5) * (float(s) / float(segs))
			pts.append(cc + Vector2(cos(a), sin(a)) * rad)
	pts.append(pts[0])
	draw_polyline(pts, col, width, true)
