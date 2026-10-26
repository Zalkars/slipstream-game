class_name ToggleSwitch
extends Control

signal toggled(on: bool)

var on := true
var label_font: Font
var accent := Color("#e23b30")
var _anim := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(116, 58)
	set_process(true)


func set_on(v: bool, notify := false) -> void:
	if on == v:
		return
	on = v
	if notify:
		toggled.emit(on)
	queue_redraw()


func _process(delta: float) -> void:
	var target := 1.0 if on else 0.0
	if absf(_anim - target) > 0.001:
		_anim = lerpf(_anim, target, minf(1.0, delta * 15.0))
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var rad := size.y * 0.5
	var bg := Color("#3a4046").lerp(accent, _anim)
	Art.rr(self, Rect2(Vector2(0.0, 2.0), size), bg, rad)
	Art.rr(self, r, bg, rad)
	Art.rr(self, Rect2(Vector2(2.0, 2.0), size - Vector2(4.0, 4.0)), Color(1, 1, 1, 0.06), rad - 2.0)
	var kr := size.y * 0.5 - 6.0
	var x := lerpf(6.0 + kr, size.x - 6.0 - kr, _anim)
	draw_circle(Vector2(x, size.y * 0.5 + 2.0), kr, Color(0, 0, 0, 0.22))
	draw_circle(Vector2(x, size.y * 0.5), kr, Color(0.97, 0.96, 0.94))
	draw_circle(Vector2(x - kr * 0.22, size.y * 0.5 - kr * 0.24), kr * 0.45, Color(1, 1, 1, 0.55))
	if label_font:
		var txt := "ВКЛ" if on else "ВЫКЛ"
		var fs := 14
		var tw := label_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
		var tx := 17.0 if on else (size.x - 17.0 - tw)
		var cy := size.y * 0.5 + fs * 0.36
		draw_string(label_font, Vector2(tx, cy), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Color(1, 1, 1, 0.86))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if not event.pressed:
			_toggle()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_toggle()


func _toggle() -> void:
	on = not on
	toggled.emit(on)
	queue_redraw()
