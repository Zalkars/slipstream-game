class_name CarModel3D
extends Node3D

# Procedural 3D car model, shared by the garage turntable and the race sprites.
# Every car is built from lofted, shaded meshes: body shell, greenhouse with
# inset glass, wheels, arches and class hardware. No assets and no textures,
# just generated geometry and StandardMaterial3D.
#
# The model faces +Z (nose towards the camera). Units are metres, wheels rest
# at y = 0 so the stage camera can frame it like a real turntable shot.
#
# Shape language: every cross-section is a rounded rectangle with separate
# bottom/top half widths (tumblehome) and corner radii. That keeps flanks flat
# and shoulders crisp instead of the inflated look a plain superellipse gives.
# Wheel arches are real cut-outs: the body's bottom edge rises over each wheel
# so the tyre sits in an opening, and a dark underbody closes the well.

const _CAB_N := 58

const _BASE := {
	"L": 4.10, "W": 1.78, "clr": 0.21, "belt": 0.94, "roof": 1.45,
	"wr": 0.33, "ww": 0.22, "wb": 0.60,
	"cab0": 0.10, "cab1": 0.73, "cabw": 0.80, "roof0": 0.20, "roof1": 0.80,
	"tail": 0.80, "deck": 0.86, "hood": 0.88, "nose": 0.82,
	"flare": 0.050,
	"rails": false, "rack": false, "spare": false, "lightbar": false,
	"bullbar": false, "scoop": false, "bed": false, "vent": false,
	"cargo": false, "wing": 0.0, "splitter": false, "diffuser": false,
	"glass_roof": false, "big_tires": false, "visor": false,
}

const SPECS := {
	"hatch": {"L": 3.86, "W": 1.72, "belt": 0.94, "roof": 1.40, "cab0": 0.055, "cab1": 0.735,
		"roof0": 0.20, "roof1": 0.80, "tail": 0.80, "deck": 0.86, "hood": 0.88, "nose": 0.82,
		"clr": 0.20, "cabw": 0.83, "wr": 0.325, "ww": 0.215, "wb": 0.60, "flare": 0.052},
	"van": {"L": 4.62, "W": 1.88, "belt": 1.12, "roof": 1.86, "cab0": 0.045, "cab1": 0.865,
		"roof0": 0.16, "roof1": 0.90, "tail": 1.00, "deck": 1.04, "hood": 1.06, "nose": 0.98,
		"clr": 0.24, "cabw": 0.88, "wr": 0.34, "ww": 0.22, "wb": 0.62, "flare": 0.040,
		"vent": true},
	"sedan": {"L": 4.36, "W": 1.80, "belt": 0.95, "roof": 1.45, "cab0": 0.22, "cab1": 0.73,
		"roof0": 0.22, "roof1": 0.78, "tail": 0.82, "deck": 0.88, "hood": 0.89, "nose": 0.83,
		"clr": 0.21, "cabw": 0.82, "wr": 0.335, "ww": 0.225, "wb": 0.60, "flare": 0.048},
	"offroad": {"L": 4.32, "W": 1.92, "belt": 1.08, "roof": 1.76, "cab0": 0.13, "cab1": 0.79,
		"roof0": 0.20, "roof1": 0.84, "tail": 0.88, "deck": 0.94, "hood": 1.02, "nose": 0.94,
		"clr": 0.34, "wr": 0.40, "ww": 0.28, "wb": 0.58, "flare": 0.080, "cabw": 0.85,
		"rails": true, "rack": true, "spare": true, "lightbar": true,
		"bullbar": true, "big_tires": true},
	"muscle": {"L": 4.44, "W": 1.88, "belt": 0.98, "roof": 1.38, "cab0": 0.28, "cab1": 0.66,
		"roof0": 0.24, "roof1": 0.76, "tail": 0.84, "deck": 0.90, "hood": 0.92, "nose": 0.84,
		"clr": 0.20, "cabw": 0.82, "wr": 0.345, "ww": 0.235, "wb": 0.60, "flare": 0.056,
		"scoop": true, "wing": 0.14},
	"pickup": {"L": 4.60, "W": 1.90, "belt": 1.06, "roof": 1.54, "cab0": 0.40, "cab1": 0.75,
		"roof0": 0.12, "roof1": 0.85, "tail": 0.80, "deck": 0.80, "hood": 0.96, "nose": 0.88,
		"clr": 0.21, "cabw": 0.84, "wr": 0.290, "ww": 0.225, "wb": 0.585, "flare": 0.060,
		"bed": true, "cargo": true},
	"sport": {"L": 4.28, "W": 1.88, "belt": 0.86, "roof": 1.24, "cab0": 0.20, "cab1": 0.66,
		"roof0": 0.24, "roof1": 0.78, "tail": 0.76, "deck": 0.82, "hood": 0.80, "nose": 0.70,
		"clr": 0.16, "cabw": 0.80, "wr": 0.34, "ww": 0.245, "wb": 0.60, "flare": 0.058,
		"wing": 0.26, "splitter": true, "diffuser": true},
	"ev": {"L": 4.34, "W": 1.86, "belt": 0.93, "roof": 1.44, "cab0": 0.075, "cab1": 0.75,
		"roof0": 0.18, "roof1": 0.80, "tail": 0.80, "deck": 0.86, "hood": 0.87, "nose": 0.80,
		"clr": 0.20, "cabw": 0.83, "wr": 0.335, "ww": 0.225, "wb": 0.61, "flare": 0.048,
		"glass_roof": true},
	"hyper": {"L": 4.40, "W": 2.00, "belt": 0.82, "roof": 1.16, "cab0": 0.18, "cab1": 0.62,
		"roof0": 0.26, "roof1": 0.76, "tail": 0.72, "deck": 0.78, "hood": 0.735, "nose": 0.66,
		"clr": 0.15, "cabw": 0.82, "wr": 0.325, "ww": 0.26, "wb": 0.605, "flare": 0.065,
		"wing": 0.34, "splitter": true, "diffuser": true, "visor": true},
}

var _root: Node3D
var _sig := ""

# --- build-time state -------------------------------------------------------
var _spec: Dictionary = {}
var _sil := "sedan"
var _L := 4.1
var _W := 1.78
var _clr := 0.21
var _belt := 0.94
var _roof := 1.45
var _wr := 0.33
var _ww := 0.22
var _wb := 0.60
var _cab0 := 0.10
var _cab1 := 0.73
var _cabw := 0.80
var _roof0 := 0.20
var _roof1 := 0.80
var _flare := 0.05
var _tail := 0.80
var _deck := 0.86
var _hood := 0.70
var _nose := 0.64
var _wz_f := 0.0
var _wz_r := 0.0
var _topk: Array = []
var _widk: Array = []
var _cabk: Array = []
var _body_ts: PackedFloat32Array
var _stripe_on := false
var _paint_mat: StandardMaterial3D
var _roof_mat: StandardMaterial3D
var _stripe_mat: StandardMaterial3D
var _glass_mat: StandardMaterial3D
var _seal_mat: StandardMaterial3D
var _trim_mat: StandardMaterial3D
var _rub_mat: StandardMaterial3D
var _tyre_mat: StandardMaterial3D
var _gap_mat: StandardMaterial3D
var _rim_mat: StandardMaterial3D
var _rim_dark: StandardMaterial3D
var _chrome_mat: StandardMaterial3D
var _lamp_w: StandardMaterial3D
var _lens: StandardMaterial3D
var _lamp_r: StandardMaterial3D
var _lamp_a: StandardMaterial3D
var _caliper: StandardMaterial3D


func show_car(car: Dictionary) -> void:
	var sil := str(car.get("silhouette", "sedan"))
	var paint := Color(str(car.get("color", "#b32b26")))
	var stripe_on := bool(car.get("stripe", false))
	var stripe := Color(str(car.get("stripe_color", "#f0ede4")))
	var sig := "%s|%s|%s|%s" % [sil, paint.to_html(), str(stripe_on), stripe.to_html()]
	if sig == _sig and _root != null:
		return
	_sig = sig
	if _root != null:
		_root.queue_free()
	_root = Node3D.new()
	_root.name = "Car"
	add_child(_root)
	_build(_root, sil, paint, stripe_on, stripe)


# --- materials --------------------------------------------------------------

func _paint(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.10
	m.roughness = 0.46
	m.metallic_specular = 0.30
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _flat(c: Color, rough := 0.55, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	m.metallic_specular = 0.20
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# Neither the garage nor the QA rig has a sky, so a mirror-smooth metallic glass
# renders as a black hole. Keep it slightly diffuse and glossy instead: ambient
# gives it a dark blue-grey body, the lights draw a readable broad highlight.
func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.285, 0.325, 0.385)
	m.vertex_color_use_as_albedo = true
	m.metallic = 0.12
	m.roughness = 0.20
	m.metallic_specular = 0.95
	m.emission_enabled = true
	m.emission = Color(0.020, 0.030, 0.046)
	m.emission_energy_multiplier = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _emissive(c: Color, e := 1.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	m.roughness = 0.28
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _metal(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# --- build ------------------------------------------------------------------

func _build(root: Node3D, sil: String, paint: Color, stripe_on: bool, stripe: Color) -> void:
	_sil = sil if SPECS.has(sil) else "sedan"
	_spec = (_BASE as Dictionary).duplicate()
	var ov: Dictionary = SPECS.get(_sil, {})
	for k in ov.keys():
		_spec[k] = ov[k]
	_L = float(_spec["L"])
	_W = float(_spec["W"])
	_clr = float(_spec["clr"])
	_belt = float(_spec["belt"])
	_roof = float(_spec["roof"])
	_wr = float(_spec["wr"])
	_ww = float(_spec["ww"])
	_wb = float(_spec["wb"])
	_cab0 = float(_spec["cab0"])
	_cab1 = float(_spec["cab1"])
	_cabw = float(_spec["cabw"])
	_roof0 = float(_spec["roof0"])
	_roof1 = float(_spec["roof1"])
	_flare = float(_spec["flare"])
	_tail = float(_spec["tail"])
	_deck = float(_spec["deck"])
	_hood = float(_spec["hood"])
	_nose = float(_spec["nose"])
	_wz_f = _wb * 0.5 * _L
	_wz_r = -_wz_f
	_stripe_on = stripe_on

	_paint_mat = _paint(paint)
	_roof_mat = _paint(paint.darkened(0.10))
	_stripe_mat = _flat(stripe, 0.86)
	_stripe_mat.metallic_specular = 0.10
	# decal on painted metal: its own panel's shadow map would stripe it
	_stripe_mat.disable_receive_shadows = true
	_glass_mat = _glass()
	_seal_mat = _flat(Color(0.022, 0.024, 0.028), 0.85)
	_trim_mat = _flat(Color(0.075, 0.080, 0.088), 0.62)
	_rub_mat = _flat(Color(0.030, 0.031, 0.034), 0.92)
	_tyre_mat = _flat(Color(0.082, 0.084, 0.090), 0.86)
	_gap_mat = _flat(Color(0.018, 0.019, 0.022), 0.95)
	_rim_mat = _metal(Color(0.66, 0.69, 0.74), 0.24, 0.70)
	_rim_dark = _metal(Color(0.085, 0.090, 0.105), 0.38, 0.50)
	_chrome_mat = _metal(Color(0.86, 0.88, 0.92), 0.10, 0.75)
	_lamp_w = _emissive(Color(1.0, 0.97, 0.90), 0.55)
	_lens = _metal(Color(0.72, 0.78, 0.86), 0.06, 0.55)
	_lamp_r = _emissive(Color(0.95, 0.10, 0.07), 0.85)
	_lamp_a = _emissive(Color(1.0, 0.50, 0.09), 0.70)
	_caliper = _flat(Color(0.58, 0.13, 0.09), 0.50)

	_make_keys()
	_body_ts = _make_body_ts()
	_build_body(root)
	_build_underbody(root)
	_build_valances(root)
	_build_cabin(root)
	_build_glass(root)
	_build_seams(root)
	_build_stripes(root)
	_build_wheels(root)
	_build_hardware(root)
	_build_lights(root)


func _make_keys() -> void:
	var a0 := clampf(_cab0 - 0.055, 0.014, 0.45)
	_topk = [
		[0.0, _tail],
		[0.014, _deck],
		[a0, _deck],
		[_cab0, _belt],
		[_cab1, _belt],
		[minf(0.972, _cab1 + 0.060), _hood],
		[minf(0.993, _cab1 + 0.200), lerpf(_hood, _nose, 0.55)],
		[1.0, _nose],
	]
	_widk = [
		[0.0, 0.905], [0.025, 0.968], [0.085, 1.0],
		[0.915, 1.0], [0.975, 0.968], [1.0, 0.915],
	]
	var b := _belt
	var r := _roof
	_cabk = [
		[0.0, b + 0.030],
		[_roof0 * 0.52, lerpf(b, r, 0.54)],
		[_roof0, r],
		[_roof1, r],
		[_roof1 + (1.0 - _roof1) * 0.52, lerpf(b, r, 0.54)],
		[1.0, b + 0.040],
	]


# --- shape helpers ----------------------------------------------------------

func _zw(t: float) -> float:
	return _L * (t - 0.5)


# Interpolate a keyed profile: [[t, v], ...] sorted by t.
func _profile(keys: Array, t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	for i in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t >= float(a[0]) and t <= float(b[0]):
			var span := maxf(0.0001, float(b[0]) - float(a[0]))
			var k := (t - float(a[0])) / span
			k = k * k * (3.0 - 2.0 * k)
			return lerpf(float(a[1]), float(b[1]), k)
	return float(keys[keys.size() - 1][1])


func _body_top(t: float) -> float:
	return _profile(_topk, t)


# Height the body's bottom edge reaches over the wheels: a real arch cut-out.
func _arch_lift(t: float) -> float:
	var lift := 0.0
	var rad := _wr + 0.038
	for wz in [_wz_f, _wz_r]:
		var dz := t * _L - _L * 0.5 - float(wz)
		var d := absf(dz) / rad
		if d >= 1.0:
			continue
		var arc := _wr + sqrt(maxf(0.0, rad * rad - dz * dz))
		var w := clampf((1.0 - d) / 0.24, 0.0, 1.0)
		var y := lerpf(_clr, arc, w * w * (3.0 - 2.0 * w))
		lift = maxf(lift, y - _clr)
	return lift


func _body_bot(t: float) -> float:
	var base := _clr + _profile([[0.0, 0.070], [0.030, 0.0], [0.970, 0.0], [1.0, 0.070]], t)
	return base + _arch_lift(t)


func _flare_at(t: float) -> float:
	var fl := 0.0
	var span := (_wr + 0.085) / _L
	for wz in [_wz_f, _wz_r]:
		var tw := (float(wz) + _L * 0.5) / _L
		var d := absf(t - tw)
		if d < span:
			fl = maxf(fl, _flare * (1.0 - pow(d / span, 2.2)))
	return fl


# Half width of the body at the shoulder (its widest line).
func _body_hw(t: float) -> float:
	return (_W * 0.5 - 0.075) * _profile(_widk, t) + _flare_at(t)


# A rounded-rectangle section: flat flanks, crisp shoulders, flat hood/roof.
func _sec(hwb: float, hwt: float, y0: float, y1: float, rb: float, rt: float,
		z: float, n_side := 2, n_corner := 4) -> Dictionary:
	var h := maxf(0.024, y1 - y0)
	rb = clampf(rb, 0.004, h * 0.44)
	rt = clampf(rt, 0.004, h * 0.44)
	hwb = maxf(hwb, rb + 0.008)
	hwt = maxf(hwt, rt + 0.008)
	var half: Array = []
	var hnr: Array = []
	# bottom, centre -> right
	half.push_back(Vector2(0.0, y0))
	hnr.push_back(Vector2(0.0, -1.0))
	half.push_back(Vector2((hwb - rb) * 0.5, y0))
	hnr.push_back(Vector2(0.0, -1.0))
	half.push_back(Vector2(hwb - rb, y0))
	hnr.push_back(Vector2(0.0, -1.0))
	# bottom-right corner
	for i in range(1, n_corner + 1):
		var a := -PI * 0.5 + PI * 0.5 * float(i) / float(n_corner)
		half.push_back(Vector2(hwb - rb + cos(a) * rb, y0 + rb + sin(a) * rb))
		hnr.push_back(Vector2(cos(a), sin(a)))
	# flank
	var side := Vector2(hwt - hwb, (y1 - rt) - (y0 + rb))
	var sn := Vector2(side.y, -side.x).normalized()
	for i in range(1, n_side + 1):
		var k := float(i) / float(n_side + 1)
		half.push_back(Vector2(lerpf(hwb, hwt, k), lerpf(y0 + rb, y1 - rt, k)))
		hnr.push_back(sn)
	# top-right corner
	for i in range(1, n_corner + 1):
		var a2 := PI * 0.5 * float(i) / float(n_corner)
		half.push_back(Vector2(hwt - rt + cos(a2) * rt, y1 - rt + sin(a2) * rt))
		hnr.push_back(Vector2(cos(a2), sin(a2)))
	# top, right -> centre
	half.push_back(Vector2((hwt - rt) * 0.5, y1))
	hnr.push_back(Vector2(0.0, 1.0))
	half.push_back(Vector2(0.0, y1))
	hnr.push_back(Vector2(0.0, 1.0))

	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()
	var m := half.size()
	for i in range(m):
		pts.push_back(half[i])
		nrm.push_back(hnr[i])
	for i in range(m - 2, 0, -1):
		var v: Vector2 = half[i]
		var nv: Vector2 = hnr[i]
		pts.push_back(Vector2(-v.x, v.y))
		nrm.push_back(Vector2(-nv.x, nv.y))
	return {"z": z, "pts": pts, "nrm": nrm}


# Body section parameters at a longitudinal position.
func _body_sec(t: float) -> Dictionary:
	var hw := _body_hw(t)
	var y0 := _body_bot(t)
	var y1 := maxf(_body_top(t), y0 + 0.055)
	var h := y1 - y0
	var nose := clampf(1.0 - t / 0.16, 0.0, 1.0) + clampf((t - 0.86) / 0.14, 0.0, 1.0)
	var rb := clampf(0.11 * h, 0.040, 0.095)
	var rt := clampf((0.085 + 0.075 * nose) * h, 0.026, 0.068)
	return {"hwb": hw * 0.945, "hwt": hw, "y0": y0, "y1": y1, "rb": rb, "rt": rt}


# X of the body's flank at a height, used by seams, sills and stripes.
func _body_side_x(t: float, y: float) -> float:
	var s := _body_sec(t)
	var y0: float = s.y0
	var y1: float = s.y1
	var rb: float = s.rb
	var rt: float = s.rt
	var hwb: float = s.hwb
	var hwt: float = s.hwt
	if y <= y0 + rb:
		var dy := clampf(y0 + rb - y, 0.0, rb)
		return hwb - rb + sqrt(maxf(0.0, rb * rb - dy * dy))
	if y >= y1 - rt:
		var dy2 := clampf(y - (y1 - rt), 0.0, rt)
		return hwt - rt + sqrt(maxf(0.0, rt * rt - dy2 * dy2))
	return lerpf(hwb, hwt, (y - (y0 + rb)) / maxf(0.001, (y1 - rt) - (y0 + rb)))


# Y of the body's top surface at a lateral position.
func _body_top_y(t: float, x: float) -> float:
	var s := _body_sec(t)
	var hwt: float = s.hwt
	var rt: float = s.rt
	var y1: float = s.y1
	var ax := absf(x)
	if ax <= hwt - rt:
		return y1
	var k := clampf((ax - (hwt - rt)) / maxf(0.0005, rt), 0.0, 1.0)
	return y1 - rt + sqrt(maxf(0.0, rt * rt * (1.0 - k * k)))


func _make_body_ts() -> PackedFloat32Array:
	var acc: Array = []
	var n := 44
	for i in range(n):
		acc.append(float(i) / float(n - 1))
	for wz in [_wz_f, _wz_r]:
		var tw := (float(wz) + _L * 0.5) / _L
		var half := (_wr + 0.115) / _L
		for k in range(9):
			acc.append(tw + lerpf(-half, half, (float(k) + 0.5) / 9.0))
	acc.sort()
	var out := PackedFloat32Array()
	for v in acc:
		var t := clampf(float(v), 0.0, 1.0)
		if out.size() > 0 and t - out[out.size() - 1] < 0.0022:
			continue
		out.append(t)
	return out


# --- primitives -------------------------------------------------------------

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3,
		ca := Color(0, 0, 0, 0), cb := Color(0, 0, 0, 0),
		cc := Color(0, 0, 0, 0)) -> void:
	# Keep the geometric winding in front of the shading normal: Godot negates
	# the normal on back faces of double-sided materials, so a mirrored part
	# with reversed winding would otherwise shade completely differently.
	if (b - a).cross(c - a).dot(na) > 0.0:
		var tv := b
		b = c
		c = tv
		var tn := nb
		nb = nc
		nc = tn
		var tc := cb
		cb = cc
		cc = tc
	if ca.a > 0.0 or cb.a > 0.0 or cc.a > 0.0:
		st.set_color(ca)
	st.set_normal(na)
	st.add_vertex(a)
	if ca.a > 0.0 or cb.a > 0.0 or cc.a > 0.0:
		st.set_color(cb)
	st.set_normal(nb)
	st.add_vertex(b)
	if ca.a > 0.0 or cb.a > 0.0 or cc.a > 0.0:
		st.set_color(cc)
	st.set_normal(nc)
	st.add_vertex(c)


# Loft a list of rings ({z, pts, nrm}) into a closed, smooth-shaded shell.
func _loft(parent: Node3D, rings: Array, mat: Material,
		cap_start := true, cap_end := true) -> MeshInstance3D:
	if rings.size() < 2:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = (rings[0]["pts"] as PackedVector2Array).size()
	var m := rings.size()
	for k in range(m - 1):
		var a: Dictionary = rings[k]
		var b: Dictionary = rings[k + 1]
		var ap: PackedVector2Array = a["pts"]
		var an: PackedVector2Array = a["nrm"]
		var bp: PackedVector2Array = b["pts"]
		var bn: PackedVector2Array = b["nrm"]
		var za := float(a["z"])
		var zb := float(b["z"])
		var kp: Dictionary = rings[maxi(0, k - 1)]
		var kn: Dictionary = rings[mini(m - 1, k + 2)]
		var pp: PackedVector2Array = kp["pts"]
		var pn: PackedVector2Array = kn["pts"]
		var z0 := float(kp["z"])
		var z1 := float(kn["z"])
		var zs := maxf(0.0001, z1 - z0)
		for i in range(n):
			var j := (i + 1) % n
			var dxi := (pn[i].x - pp[i].x) / zs
			var dyi := (pn[i].y - pp[i].y) / zs
			var dxj := (pn[j].x - pp[j].x) / zs
			var dyj := (pn[j].y - pp[j].y) / zs
			var v0 := Vector3(ap[i].x, ap[i].y, za)
			var v1 := Vector3(ap[j].x, ap[j].y, za)
			var v2 := Vector3(bp[j].x, bp[j].y, zb)
			var v3 := Vector3(bp[i].x, bp[i].y, zb)
			var n0 := Vector3(an[i].x, an[i].y, -(dxi * an[i].x + dyi * an[i].y)).normalized()
			var n1 := Vector3(an[j].x, an[j].y, -(dxj * an[j].x + dyj * an[j].y)).normalized()
			var n2 := Vector3(bn[j].x, bn[j].y, -(dxj * bn[j].x + dyj * bn[j].y)).normalized()
			var n3 := Vector3(bn[i].x, bn[i].y, -(dxi * bn[i].x + dyi * bn[i].y)).normalized()
			_tri(st, v0, v1, v2, n0, n1, n2)
			_tri(st, v0, v2, v3, n0, n2, n3)
	if cap_end:
		var r: PackedVector2Array = rings[m - 1]["pts"]
		var zc := float(rings[m - 1]["z"])
		var c := Vector2.ZERO
		for i in range(n):
			c += r[i]
		c /= float(n)
		var nz := Vector3(0, 0, 1)
		for i in range(n):
			var j := (i + 1) % n
			_tri(st, Vector3(c.x, c.y, zc), Vector3(r[i].x, r[i].y, zc),
				Vector3(r[j].x, r[j].y, zc), nz, nz, nz)
	if cap_start:
		var r0: PackedVector2Array = rings[0]["pts"]
		var z0c := float(rings[0]["z"])
		var c0 := Vector2.ZERO
		for i in range(n):
			c0 += r0[i]
		c0 /= float(n)
		var nz0 := Vector3(0, 0, -1)
		for i in range(n):
			var j := (i + 1) % n
			_tri(st, Vector3(c0.x, c0.y, z0c), Vector3(r0[j].x, r0[j].y, z0c),
				Vector3(r0[i].x, r0[i].y, z0c), nz0, nz0, nz0)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi


# Grid of quads with per-vertex normals. Optional per-vertex colours (same
# shape as `rows`) drive the glass gradient.
func _grid(parent: Node3D, rows: Array, nrms: Array, mat: Material,
		cols: Array = []) -> MeshInstance3D:
	if rows.size() < 2:
		return null
	var cols_n: int = (rows[0] as PackedVector3Array).size()
	if cols_n < 2:
		return null
	var use_col := cols.size() == rows.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(rows.size() - 1):
		var a: PackedVector3Array = rows[i]
		var b: PackedVector3Array = rows[i + 1]
		var na: PackedVector3Array = nrms[i]
		var nb: PackedVector3Array = nrms[i + 1]
		var ca := PackedColorArray()
		var cb := PackedColorArray()
		if use_col:
			ca = cols[i]
			cb = cols[i + 1]
		for j in range(cols_n - 1):
			if use_col:
				_tri(st, a[j], a[j + 1], b[j + 1], na[j], na[j + 1], nb[j + 1],
					ca[j], ca[j + 1], cb[j + 1])
				_tri(st, a[j], b[j + 1], b[j], na[j], nb[j + 1], nb[j],
					ca[j], cb[j + 1], cb[j])
			else:
				_tri(st, a[j], a[j + 1], b[j + 1], na[j], na[j + 1], nb[j + 1])
				_tri(st, a[j], b[j + 1], b[j], na[j], nb[j + 1], nb[j])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
	return mi


# Grid patch given an explicit, constant normal.
func _grid_patch(parent: Node3D, rows: Array, nrm: Vector3,
		mat: Material) -> MeshInstance3D:
	if rows.size() < 2:
		return null
	var nrms: Array = []
	for r in rows:
		var row: PackedVector3Array = r
		var nrow := PackedVector3Array()
		for p in row:
			nrow.push_back(nrm)
		nrms.push_back(nrow)
	return _grid(parent, rows, nrms, mat)


# Grid patch shaded as a smooth upward-facing surface.
func _patch(parent: Node3D, rows: Array, mat: Material) -> MeshInstance3D:
	if rows.size() < 2:
		return null
	var nrms: Array = []
	for r in rows:
		var row: PackedVector3Array = r
		var nrow := PackedVector3Array()
		for p in row:
			nrow.push_back(Vector3.UP)
		nrms.push_back(nrow)
	return _grid(parent, rows, nrms, mat)


func _sweep(parent: Node3D, rings: Array, mat: Material, caps := true) -> MeshInstance3D:
	if rings.size() < 2:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = (rings[0] as PackedVector3Array).size()
	for k in range(rings.size() - 1):
		var a: PackedVector3Array = rings[k]
		var b: PackedVector3Array = rings[k + 1]
		var ca := Vector3.ZERO
		var cb := Vector3.ZERO
		for i in range(n):
			ca += a[i]
			cb += b[i]
		ca /= float(n)
		cb /= float(n)
		for i in range(n):
			var j := (i + 1) % n
			var na := (a[i] - ca).normalized()
			var naj := (a[j] - ca).normalized()
			var nb := (b[i] - cb).normalized()
			var nbj := (b[j] - cb).normalized()
			_tri(st, a[i], a[j], b[j], na, naj, nbj)
			_tri(st, a[i], b[j], b[i], na, nbj, nb)
	if caps:
		for idx in [0, rings.size() - 1]:
			var r: PackedVector3Array = rings[idx]
			var c := Vector3.ZERO
			for i in range(n):
				c += r[i]
			c /= float(n)
			var flip: bool = idx == 0
			for i in range(n):
				var j := (i + 1) % n
				var nn := (r[j] - c).cross(r[i] - c).normalized()
				if flip:
					nn = -nn
				_tri(st, c, r[i], r[j], nn, nn, nn)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO,
		rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = sz
	return _add_mesh(parent, bm, mat, pos, rot)


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material,
		rot := Vector3.ZERO, segs := 24) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	return _add_mesh(parent, cm, mat, pos, rot)


# Lathe around the Y axis, normals taken from the profile tangent, so a domed
# part (spare cover, hub cap) shades smoothly instead of stacking rings.
func _lathe_y(parent: Node3D, cx: float, cz: float, y0: float,
		prof: Array, mat: Material, segs := 28) -> MeshInstance3D:
	var m := prof.size()
	var nrm: Array = []
	for i in range(m):
		var a: Vector2 = prof[maxi(0, i - 1)]
		var b: Vector2 = prof[mini(m - 1, i + 1)]
		var t := b - a
		nrm.append(Vector2(t.y, -t.x).normalized())
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(m - 1):
		var pa: Vector2 = prof[i]
		var pb: Vector2 = prof[i + 1]
		var na: Vector2 = nrm[i]
		var nb: Vector2 = nrm[i + 1]
		for k in range(segs):
			var a0 := TAU * float(k) / float(segs)
			var a1 := TAU * float(k + 1) / float(segs)
			var c0 := cos(a0)
			var s0 := sin(a0)
			var c1 := cos(a1)
			var s1 := sin(a1)
			var a00 := Vector3(cx + pa.x * c0, y0 + pa.y, cz + pa.x * s0)
			var a10 := Vector3(cx + pa.x * c1, y0 + pa.y, cz + pa.x * s1)
			var b00 := Vector3(cx + pb.x * c0, y0 + pb.y, cz + pb.x * s0)
			var b10 := Vector3(cx + pb.x * c1, y0 + pb.y, cz + pb.x * s1)
			var na0 := Vector3(na.x * c0, na.y, na.x * s0).normalized()
			var na1 := Vector3(na.x * c1, na.y, na.x * s1).normalized()
			var nb0 := Vector3(nb.x * c0, nb.y, nb.x * s0).normalized()
			var nb1 := Vector3(nb.x * c1, nb.y, nb.x * s1).normalized()
			_tri(st, a00, a10, b10, na0, na1, nb1)
			_tri(st, a00, b10, b00, na0, nb1, nb0)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
	return mi


# A thin ring lying in the plane perpendicular to its X axis (rim lips, bezels).
func _ring(parent: Node3D, r_major: float, r_tube: float, pos: Vector3,
		mat: Material, rot := Vector3.ZERO, segs := 24) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = maxf(0.001, r_major - r_tube)
	tm.outer_radius = r_major + r_tube
	tm.rings = segs
	tm.ring_segments = 8
	return _add_mesh(parent, tm, mat, pos, rot)


# Rounded box: a short loft with rounded sections and slightly drawn-in ends.
func _rbox(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		rot := Vector3.ZERO, r := 0.03) -> MeshInstance3D:
	var hw := size.x * 0.5
	var hh := size.y * 0.5
	var hd := size.z * 0.5
	r = clampf(r, 0.0008, minf(hw, hh) * 0.92)
	var rings: Array = []
	var n := 6
	for i in range(n):
		var k := float(i) / float(n - 1)
		var e := 1.0
		if k < 0.18:
			e = 0.84 + 0.16 * (k / 0.18)
		elif k > 0.82:
			e = 0.84 + 0.16 * ((1.0 - k) / 0.18)
		rings.push_back(_sec(hw * e, hw * e, -hh, hh, r, r, lerpf(-hd, hd, k)))
	var mi := _loft(parent, rings, mat, true, true)
	if mi != null:
		mi.position = pos
		mi.rotation_degrees = rot
	return mi


# Revolve a (axial offset, radius) profile around the X axis.
func _revolve_x(parent: Node3D, cx: float, zc: float, prof: Array, mat: Material,
		segs := 26) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ps: Array = []
	var ns: Array = []
	for i in range(prof.size()):
		var pa: Vector2 = prof[maxi(0, i - 1)]
		var pb: Vector2 = prof[mini(prof.size() - 1, i + 1)]
		var d := pb - pa
		var n2 := Vector2(-d.y, d.x)
		if n2.length() < 0.00005:
			n2 = Vector2(0.0, 1.0)
		n2 = n2.normalized()
		var a: float = prof[i].x
		var r: float = prof[i].y
		var pts := PackedVector3Array()
		var nrm := PackedVector3Array()
		for j in range(segs):
			var th := TAU * float(j) / float(segs)
			var s := sin(th)
			var c := cos(th)
			pts.push_back(Vector3(cx + a, r * s, zc + r * c))
			nrm.push_back(Vector3(n2.x, n2.y * s, n2.y * c).normalized())
		ps.push_back(pts)
		ns.push_back(nrm)
	for i in range(ps.size() - 1):
		var a2: PackedVector3Array = ps[i]
		var b2: PackedVector3Array = ps[i + 1]
		var na: PackedVector3Array = ns[i]
		var nb: PackedVector3Array = ns[i + 1]
		for j in range(segs):
			var k := (j + 1) % segs
			_tri(st, a2[j], a2[k], b2[k], na[j], na[k], nb[k])
			_tri(st, a2[j], b2[k], b2[j], na[j], nb[k], nb[j])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
	return mi


# Body-profile band hugging the flanks between two heights above the sill.
# The section width tracks the body at both edges of the band, so the trim
# follows the flank instead of cutting across it and z-fighting with the paint.
func _band(root: Node3D, t0: float, t1: float, dy0: float, dy1: float,
		mat: Material, out := 0.005) -> void:
	var rings: Array = []
	var n := maxi(6, int(absf(t1 - t0) * 110.0))
	for i in range(n + 1):
		var t := lerpf(t0, t1, float(i) / float(n))
		var yb := _body_bot(t) + dy0
		var yt := maxf(yb + 0.020, _body_bot(t) + dy1)
		var z := _zw(t)
		# pull the end caps a hair off the body's own caps (they are coplanar)
		if i == 0 and t0 <= 0.0001:
			z -= 0.0015
		if i == n and t1 >= 0.9999:
			z += 0.0015
		var hwb := _body_side_x(t, yb) + out
		var hwt := _body_side_x(t, yt) + out
		var rt := minf(0.016, (yt - yb) * 0.3)
		rings.push_back(_sec(hwb, hwt, yb, yt, 0.008, rt, z))
	_loft(root, rings, mat, true, true)


# --- body -------------------------------------------------------------------

func _build_body(root: Node3D) -> void:
	var rings: Array = []
	for i in range(_body_ts.size()):
		var t := _body_ts[i]
		var s := _body_sec(t)
		rings.push_back(_sec(s.hwb, s.hwt, s.y0, s.y1, s.rb, s.rt, _zw(t)))
	_loft(root, rings, _paint_mat, true, true)


# Dark panel under the body: closes the floor and the wheel arch ceilings.
func _build_underbody(root: Node3D) -> void:
	var rows: Array = []
	for i in range(_body_ts.size()):
		var t := _body_ts[i]
		var s := _body_sec(t)
		var hw := float(s.hwb) * 0.94
		var y := float(s.y0) - 0.008
		var row := PackedVector3Array()
		for j in range(5):
			var x := lerpf(-hw, hw, float(j) / 4.0)
			row.push_back(Vector3(x, y, _zw(t)))
		rows.push_back(row)
	var nrms: Array = []
	for r in rows:
		var src: PackedVector3Array = r
		var row2 := PackedVector3Array()
		for j in range(src.size()):
			row2.push_back(Vector3.DOWN)
		nrms.push_back(row2)
	_grid(root, rows, nrms, _rub_mat)


func _build_valances(root: Node3D) -> void:
	# front and rear bumper bands, and the rocker between the arches
	_band(root, 0.905, 1.0, 0.002, 0.115, _trim_mat, 0.006)
	_band(root, 0.0, 0.100, 0.002, 0.130, _trim_mat, 0.006)
	_band(root, 0.305, 0.695, 0.004, 0.070, _trim_mat, 0.004)


# --- greenhouse -------------------------------------------------------------

# The greenhouse starts just inside the body's shoulder so the beltline is a
# thin ledge instead of a shelf the cabin sits on.
func _cab_hw(u: float) -> float:
	var t := lerpf(_cab0, _cab1, u)
	return _body_hw(t) - 0.016


func _cab_sec(u: float) -> Dictionary:
	var t := lerpf(_cab0, _cab1, u)
	var hwb := _cab_hw(u)
	var y0 := _body_top(t) - 0.030
	var y1 := maxf(_profile(_cabk, u), y0 + 0.070)
	var h := y1 - y0
	return {
		"hwb": hwb, "hwt": hwb * 0.905, "y0": y0, "y1": y1,
		"rb": 0.012, "rt": clampf(h * 0.20, 0.030, 0.105),
	}


# Point on the greenhouse shell. w -1..1 runs along the upper contour:
# -1 = left belt, 0 = roof centre, +1 = right belt.
func _cab_pt(u: float, w: float) -> Vector3:
	u = clampf(u, 0.0, 1.0)
	var s := _cab_sec(u)
	var y0: float = s.y0
	var y1: float = s.y1
	var hwb: float = s.hwb
	var hwt: float = s.hwt
	var rb: float = s.rb
	var rt: float = s.rt
	var side_h := maxf(0.001, (y1 - rt) - (y0 + rb))
	var l_side := sqrt((hwt - hwb) * (hwt - hwb) + side_h * side_h)
	var l_arc := rt * PI * 0.5
	var l_flat := maxf(0.001, hwt - rt)
	var total := l_side + l_arc + l_flat
	var d := (1.0 - clampf(absf(w), 0.0, 1.0)) * total
	var px := 0.0
	var py := 0.0
	if d <= l_side:
		var k := d / l_side
		px = lerpf(hwb, hwt, k)
		py = lerpf(y0 + rb, y1 - rt, k)
	elif d <= l_side + l_arc:
		var k2 := (d - l_side) / maxf(0.0001, l_arc)
		var a := k2 * PI * 0.5
		px = hwt - rt + cos(a) * rt
		py = y1 - rt + sin(a) * rt
	else:
		var k3 := (d - l_side - l_arc) / l_flat
		px = lerpf(hwt - rt, 0.0, k3)
		py = y1
	if w < 0.0:
		px = -px
	return Vector3(px, py, _zw(lerpf(_cab0, _cab1, u)))


func _cab_nrm(u: float, w: float) -> Vector3:
	var du := 0.004
	var dw := 0.02
	var tu := _cab_pt(minf(1.0, u + du), w) - _cab_pt(maxf(0.0, u - du), w)
	var tw := _cab_pt(u, minf(1.0, w + dw)) - _cab_pt(u, maxf(-1.0, w - dw))
	var n := tw.cross(tu)
	if n.length() < 0.00001:
		n = Vector3.UP
	n = n.normalized()
	var s := _cab_sec(u)
	var c := Vector3(0.0, (float(s.y0) + float(s.y1)) * 0.5,
		_zw(lerpf(_cab0, _cab1, u)))
	if n.dot(_cab_pt(u, w) - c) < 0.0:
		n = -n
	return n


# Y of the roof surface at a lateral position.
func _cab_top_y(u: float, x: float) -> float:
	var s := _cab_sec(u)
	var hwt: float = s.hwt
	var rt: float = s.rt
	var y1: float = s.y1
	var ax := absf(x)
	if ax <= hwt - rt:
		return y1
	var k := clampf((ax - (hwt - rt)) / maxf(0.0005, rt), 0.0, 1.0)
	return y1 - rt + sqrt(maxf(0.0, rt * rt * (1.0 - k * k)))


func _build_cabin(root: Node3D) -> void:
	# Dense rings with cosine spacing: the shell bends hardest at the pillars,
	# so the loft has to follow the silhouette closely or it pokes through the
	# glass panels laid just millimetres proud of it.
	var n := _CAB_N
	var rings: Array = []
	for i in range(n):
		var u := 0.5 - 0.5 * cos(PI * float(i) / float(n - 1))
		var s := _cab_sec(u)
		rings.push_back(_sec(s.hwb, s.hwt, s.y0, s.y1, s.rb, s.rt,
			_zw(lerpf(_cab0, _cab1, u))))
	_loft(root, rings, _paint_mat, true, true)

	# glass roof panel: a rounded panel with a black frit border, laid on the
	# roof surface rather than stuck on as a rectangular decal
	if bool(_spec["glass_roof"]):
		_roof_glass(root, _roof0 + 0.055, _roof1 - 0.055, _cab_hw(0.5) * 0.46)

	# dark visor band across the top of the windscreen
	if bool(_spec["visor"]):
		var rows2: Array = []
		for i in range(2):
			var u := lerpf(_roof1 + 0.016, _roof1 + 0.042, float(i))
			var hw := _cab_hw(u) * 0.66
			var row2 := PackedVector3Array()
			for j in range(7):
				var x := lerpf(-hw, hw, float(j) / 6.0)
				row2.push_back(Vector3(x, _cab_top_y(u, x) + 0.007,
					_zw(lerpf(_cab0, _cab1, u))))
			rows2.push_back(row2)
		_patch(root, rows2, _gap_mat)


# w value of the roof rail: the point where the flat top of the section starts
# to roll over into the shoulder. Windows stop here, so their upper edge runs
# parallel to the roof instead of cutting across the corner.
func _cab_w_rail(u: float) -> float:
	var sec := _cab_sec(u)
	var y0: float = sec.y0
	var y1: float = sec.y1
	var hwb: float = sec.hwb
	var hwt: float = sec.hwt
	var rb: float = sec.rb
	var rt: float = sec.rt
	var side_h := maxf(0.001, (y1 - rt) - (y0 + rb))
	var l_side := sqrt((hwt - hwb) * (hwt - hwb) + side_h * side_h)
	var l_arc := rt * PI * 0.5
	var l_flat := maxf(0.001, hwt - rt)
	var total := l_side + l_arc + l_flat
	return clampf(1.0 - (l_side + l_arc) / total, 0.05, 0.95)


# w value where the cabin contour passes through height y. Used to keep the
# bottom edge of the side windows on a straight beltline.
func _cab_w_at(u: float, y: float) -> float:
	var sec := _cab_sec(u)
	var y0: float = sec.y0
	var y1: float = sec.y1
	var hwb: float = sec.hwb
	var hwt: float = sec.hwt
	var rb: float = sec.rb
	var rt: float = sec.rt
	var side_h := maxf(0.001, (y1 - rt) - (y0 + rb))
	var l_side := sqrt((hwt - hwb) * (hwt - hwb) + side_h * side_h)
	var l_arc := rt * PI * 0.5
	var l_flat := maxf(0.001, hwt - rt)
	var total := l_side + l_arc + l_flat
	var d := 0.0
	if y > y1 - rt:
		var k := clampf((y - (y1 - rt)) / maxf(0.001, rt), 0.0, 1.0)
		d = l_side + l_arc * (asin(k) / (PI * 0.5))
	elif y > y0 + rb:
		d = l_side * clampf((y - (y0 + rb)) / side_h, 0.0, 1.0)
	return clampf(1.0 - d / total, 0.05, 0.995)


# A window: dark rubber surround, then the glass panel just proud of it.
#
# The surround is drawn *under* the glass and kept only slightly larger, so the
# wrap over the shoulder cannot cross in front of the glass. Panels are finely
# tessellated in u: a coarse chord would sink below the lofted shell between
# rings and let the paint poke through the middle of a window.
func _window(root: Node3D, u0: float, u1: float, w0: float, w1: float,
		nu: int, nw: int) -> void:
	var a := func(_u: float) -> Vector2: return Vector2(w0, w1)
	_window_ex(root, u0, u1, a, 0.022, 0.012, nu, nw)


# Window whose edges may vary along the cabin: f(u) -> Vector2(w_lo, w_hi).
func _window_ex(root: Node3D, u0: float, u1: float, f: Callable,
		pad_lo: float, pad_hi: float, nu: int, nw: int) -> void:
	var seal := func(u: float) -> Vector2:
		var v: Vector2 = f.call(u)
		var lo := v.x - signf(v.x) * pad_lo
		var hi := v.y + signf(v.y) * pad_hi
		return Vector2(lo, hi)
	_window_panel(root, u0 - 0.006, u1 + 0.006, seal, nu, nw, 0.0046, _seal_mat)
	_window_panel(root, u0, u1, f, nu, nw, 0.0085, _glass_mat)


# Windscreen or rear glass: a panel spanning the top of the greenhouse, with its
# corners rounded off instead of running square into the pillars.
func _window_round(root: Node3D, u0: float, u1: float, wh: float,
		pad_lo: float, pad_hi: float, nu: int, nw: int) -> void:
	var rr := clampf((u1 - u0) * 0.30, 0.012, 0.045)
	var f := func(u: float) -> Vector2:
		var k := clampf(minf((u - u0) / rr, (u1 - u) / rr), 0.0, 1.0)
		var q := 1.0 - pow(1.0 - k, 2.4)
		var ww := wh - 0.050 * (1.0 - q)
		return Vector2(-ww, ww)
	# The seal is a black frit band just outside the glass outline: it hides the
	# panel edge against the paint and keeps the corners rounded.
	var seal := func(u: float) -> Vector2:
		var v: Vector2 = f.call(u)
		return Vector2(v.x - pad_lo, v.y + pad_hi)
	_window_panel(root, u0, u1, seal, nu, nw, 0.0046, _seal_mat)
	_window_panel(root, u0, u1, f, nu, nw, 0.0085, _glass_mat, "u")


# Sky-reflection tint for glass: dark interior at the bottom of the pane,
# brighter towards its top edge. Real glass in a showroom does this with the
# environment; we bake it into the vertex colours instead.
func _glass_tint(t: float) -> Color:
	var v := lerpf(0.28, 0.86, pow(clampf(t, 0.0, 1.0), 2.4))
	return Color(v, v, v, 1.0)


func _window_panel(root: Node3D, u0: float, u1: float, f: Callable,
		nu: int, nw: int, out: float, mat: Material, vert := "w") -> void:
	var rows: Array = []
	var nrms: Array = []
	var cols: Array = []
	var tint := mat == _glass_mat
	for i in range(nu):
		var u := lerpf(u0, u1, float(i) / float(nu - 1))
		var ww: Vector2 = f.call(u)
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for j in range(nw):
			var w := lerpf(ww.x, ww.y, float(j) / float(nw - 1))
			var n := _cab_nrm(u, w)
			row.push_back(_cab_pt(u, w) + n * out)
			nrow.push_back(n)
			var t := float(i) / float(nu - 1) if vert == "u" else float(j) / float(nw - 1)
			crow.push_back(_glass_tint(t))
		rows.push_back(row)
		nrms.push_back(nrow)
		cols.push_back(crow)
	if tint:
		_grid(root, rows, nrms, mat, cols)
	else:
		_grid(root, rows, nrms, mat)


func _build_glass(root: Node3D) -> void:
	# side windows: rear door then front door, with a painted B-pillar. The top
	# edge follows the roof rail and the bottom edge the beltline.
	for sd: float in [-1.0, 1.0]:
		var side := func(u: float) -> Vector2:
			return Vector2(sd * _cab_w_at(u, _belt - 0.008), sd * (_cab_w_rail(u) + 0.012))
		if _sil == "pickup":
			# crew cab: keep a painted C-pillar and a proper B-pillar
			_window_ex(root, 0.220, 0.500, side, 0.016, 0.010, 26, 12)
			_window_ex(root, 0.560, 0.800, side, 0.016, 0.010, 26, 12)
		else:
			_window_ex(root, 0.235, 0.520, side, 0.016, 0.010, 26, 12)
			_window_ex(root, 0.558, 0.800, side, 0.016, 0.010, 26, 12)
	# windscreen and rear glass; the hatch glass runs further back into the tailgate.
	# A van has a near-upright screen at the very front of its tall cab, so its
	# glass has to start where the flat roof actually ends, not on the roof.
	var ws0 := 0.830
	var ws1 := 0.965
	var wsw := 0.560
	if _sil == "pickup":
		ws0 = 0.868
		ws1 = 0.972
	elif _sil == "van":
		# tall cab: the same w span would wrap right around the A-pillar, so
		# pull the edges in until a proper painted pillar is left standing
		ws0 = 0.910
		ws1 = 0.964
		wsw = 0.440
	_window_round(root, ws0, ws1, wsw, 0.014, 0.010, 34, 26)
	var rear_hi := 0.150 if _sil == "sedan" else 0.190
	if _sil == "pickup":
		# an upright rear window with a painted cab back below it
		_window_round(root, 0.035, 0.115, 0.560, 0.014, 0.010, 22, 20)
	else:
		_window_round(root, 0.030, rear_hi, 0.560, 0.014, 0.010, 26, 20)


# Panoramic roof glass: the same rounded-outline treatment as the screens, but
# laid on the roof surface with the width tapering towards the ends.
func _roof_glass(root: Node3D, u0: float, u1: float, wh: float) -> void:
	var rr := clampf((u1 - u0) * 0.30, 0.015, 0.085)
	var f := func(u: float) -> float:
		var k := clampf(minf((u - u0) / rr, (u1 - u) / rr), 0.0, 1.0)
		var q := 1.0 - pow(1.0 - k, 2.6)
		return wh - 0.085 * (1.0 - q)
	var seal := func(u: float) -> float: return float(f.call(u)) + 0.026
	_roof_patch(root, u0 - 0.007, u1 + 0.007, seal, 0.0044, _seal_mat)
	_roof_patch(root, u0, u1, f, 0.0082, _glass_mat)


func _roof_patch(root: Node3D, u0: float, u1: float, f: Callable,
		out: float, mat: Material) -> void:
	var rows: Array = []
	for u in _cab_rows(u0, u1):
		var hw: float = f.call(u)
		var row := PackedVector3Array()
		for j in range(7):
			var x := lerpf(-hw, hw, float(j) / 6.0)
			row.push_back(Vector3(x, _cab_top_y(u, x) + out,
				_zw(lerpf(_cab0, _cab1, u))))
		rows.push_back(row)
	_patch(root, rows, mat)


# --- shut lines -------------------------------------------------------------

func _seam_v(root: Node3D, t: float, y0: float, y1: float, side: float) -> void:
	var rows: Array = []
	var nrms: Array = []
	var nrm := Vector3(side, 0, 0)
	for i in range(5):
		var y := lerpf(y0, y1, float(i) / 4.0)
		var x := side * (_body_side_x(t, y) + 0.0022)
		rows.push_back(PackedVector3Array([
			Vector3(x, y, _zw(t) - 0.0024), Vector3(x, y, _zw(t) + 0.0024)]))
		nrms.push_back(PackedVector3Array([nrm, nrm]))
	var _sm := _grid(root, rows, nrms, _gap_mat)
	if _sm != null: _sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _seam_h(root: Node3D, t0: float, t1: float, y: float, side: float) -> void:
	var rows: Array = []
	var nrms: Array = []
	var nrm := Vector3(side, 0, 0)
	for i in range(5):
		var t := lerpf(t0, t1, float(i) / 4.0)
		var x := side * (_body_side_x(t, y) + 0.0022)
		rows.push_back(PackedVector3Array([
			Vector3(x, y - 0.0024, _zw(t)), Vector3(x, y + 0.0024, _zw(t))]))
		nrms.push_back(PackedVector3Array([nrm, nrm]))
	var _sm := _grid(root, rows, nrms, _gap_mat)
	if _sm != null: _sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# A painted or plastic strip at a constant height along the flank (side
# mouldings). Sampled per ring so it follows the tumblehome instead of
# floating off the body like a straight box would.
func _strip_h(root: Node3D, t0: float, t1: float, y: float, h: float,
		side: float, mat: Material, out := 0.005) -> void:
	var rows: Array = []
	var nrms: Array = []
	var nrm := Vector3(side, 0, 0)
	var n := maxi(6, int(absf(t1 - t0) * 70.0))
	for i in range(n + 1):
		var t := lerpf(t0, t1, float(i) / float(n))
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		for j in range(4):
			var yy := y + lerpf(-h, h, float(j) / 3.0) * 0.5
			row.push_back(Vector3(side * (_body_side_x(t, yy) + out), yy, _zw(t)))
			nrow.push_back(nrm)
		rows.push_back(row)
		nrms.push_back(nrow)
	_grid(root, rows, nrms, mat)


func _seam_top(root: Node3D, t: float, x0: float, x1: float) -> void:
	var rows: Array = []
	var nrms: Array = []
	var n := maxi(10, int(absf(x1 - x0) * 90.0))
	for k in range(2):
		var z := _zw(t) + (0.0026 if k == 0 else -0.0026)
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		for j in range(n + 1):
			var x := lerpf(x0, x1, float(j) / float(n))
			row.push_back(Vector3(x, _body_top_y(t, x) + 0.0045, z))
			nrow.push_back(Vector3.UP)
		rows.push_back(row)
		nrms.push_back(nrow)
	var _sm := _grid(root, rows, nrms, _gap_mat)
	if _sm != null: _sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _seam_top_long(root: Node3D, t0: float, t1: float, x: float) -> void:
	var rows: Array = []
	var nrms: Array = []
	var n := maxi(14, int(absf(t1 - t0) * _L * 26.0))
	for i in range(n + 1):
		var t := lerpf(t0, t1, float(i) / float(n))
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		for k in range(2):
			var xx := x + (0.0026 if k == 0 else -0.0026)
			row.push_back(Vector3(xx, _body_top_y(t, xx) + 0.0045, _zw(t)))
			nrow.push_back(Vector3.UP)
		rows.push_back(row)
		nrms.push_back(nrow)
	var _sm := _grid(root, rows, nrms, _gap_mat)
	if _sm != null: _sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_seams(root: Node3D) -> void:
	var belt := _belt - 0.008
	var arch_t := (_wr + 0.055) / _L
	var tw_f := 0.5 + _wb * 0.5
	var tw_r := 0.5 - _wb * 0.5
	var t_front := minf(_cab1 - 0.010, tw_f - arch_t)
	var t_rear := maxf(_cab0 + 0.060, tw_r + arch_t)
	var t_mid := (t_front + t_rear) * 0.5
	# doors: front and rear edge, the B-pillar and the lower shut line
	for sd: float in [-1.0, 1.0]:
		for t in [t_front, t_rear]:
			_seam_v(root, t, _body_bot(t) + 0.068, belt, sd)
		_seam_v(root, t_mid, _body_bot(t_mid) + 0.075, belt, sd)
		_seam_h(root, t_rear + 0.004, t_front - 0.004, _body_bot(t_mid) + 0.060, sd)
	# bonnet: two long edges and the front cut line, kept on the flat top
	var tx := minf(0.958, _cab1 + 0.215)
	var hs := _body_sec(0.90)
	var hw_hood: float = (float(hs.hwt) - float(hs.rt)) * 0.955
	_seam_top(root, tx, -hw_hood, hw_hood)
	_seam_top_long(root, _cab1 + 0.085, tx, -hw_hood)
	_seam_top_long(root, _cab1 + 0.085, tx, hw_hood)
	# tailgate, also inside the flat top
	var tt := maxf(0.030, _cab0 - 0.030)
	var ts := _body_sec(0.10)
	var hw_tail: float = (float(ts.hwt) - float(ts.rt)) * 0.94
	_seam_top(root, tt, -hw_tail, hw_tail)


# --- stripes ----------------------------------------------------------------

func _build_stripes(root: Node3D) -> void:
	if not _stripe_on:
		return
	var si := _W * 0.048
	var so := _W * 0.130
	if _sil == "muscle":
		# outboard stripes, leaving the centre of the hood for the scoop
		si = _W * 0.135
		so = _W * 0.235
	# bonnet: from the cowl shut line to just behind the nose. Rows are placed on
	# the body's own rings: a decal sampled between them would sit below the
	# loft's chords where the profile turns concave and get cut into segments.
	var ta := minf(_cab1 + 0.030, 0.900)
	var tb := 0.944
	for s: float in [-1.0, 1.0]:
		if tb - ta > 0.02:
			var rows: Array = []
			for t in _body_rows(ta, tb):
				rows.push_back(_body_stripe_row(t, s, si, so))
			_patch(root, rows, _stripe_mat)
		# boot lid, only when there is a real deck behind the cabin
		if _cab0 > 0.145 and not bool(_spec["bed"]):
			var rows2: Array = []
			for t2 in _body_rows(0.040, _cab0 - 0.070):
				rows2.push_back(_body_stripe_row(t2, s, si, so))
			_patch(root, rows2, _stripe_mat)
		# roof, unless a glass panel already covers it
		if not bool(_spec["glass_roof"]):
			var rows3: Array = []
			for u in _cab_rows(_roof0 + 0.03, _roof1 - 0.03):
				var row := PackedVector3Array()
				for j in range(3):
					var x := lerpf(si, so, float(j) / 2.0) * s
					row.push_back(Vector3(x, _cab_top_y(u, x) + 0.0105,
						_zw(lerpf(_cab0, _cab1, u))))
				rows3.push_back(row)
			_patch(root, rows3, _stripe_mat)


# The body loft's ring positions inside a range, so decals can share its chords.
func _body_rows(t0: float, t1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.append(t0)
	for v in _body_ts:
		if float(v) > t0 + 0.001 and float(v) < t1 - 0.001:
			out.append(float(v))
	out.append(t1)
	return out


# The greenhouse loft's ring positions inside a range.
func _cab_rows(u0: float, u1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.append(u0)
	for i in range(_CAB_N):
		var u := 0.5 - 0.5 * cos(PI * float(i) / float(_CAB_N - 1))
		if u > u0 + 0.001 and u < u1 - 0.001:
			out.append(u)
	out.append(u1)
	return out


func _body_stripe_row(t: float, s: float, si: float, so: float) -> PackedVector3Array:
	var row := PackedVector3Array()
	for j in range(3):
		var x := lerpf(si, so, float(j) / 2.0) * s
		row.push_back(Vector3(x, _body_top_y(t, x) + 0.0105, _zw(t)))
	return row


# --- wheels -----------------------------------------------------------------

func _build_wheels(root: Node3D) -> void:
	for s: float in [-1.0, 1.0]:
		for zc in [_wz_f, _wz_r]:
			_wheel(root, s, zc)


func _wheel(root: Node3D, side: float, zc: float) -> void:
	var t := (zc + _L * 0.5) / _L
	var face := side * (_body_hw(t) - 0.020)
	var hw := _ww * 0.5
	var cx := face - side * hw
	var r := _wr
	var rim := r * 0.655
	# tyre: a short sidewall around a wide tread
	var base: Array = [
		Vector2(-hw * 0.99, rim * 0.985),
		Vector2(-hw * 0.955, lerpf(rim, r, 0.52)),
		Vector2(-hw * 0.80, lerpf(rim, r, 0.93)),
		Vector2(-hw * 0.54, r * 1.002),
		Vector2(0.0, r * 1.008),
		Vector2(hw * 0.54, r * 1.002),
		Vector2(hw * 0.80, lerpf(rim, r, 0.93)),
		Vector2(hw * 0.955, lerpf(rim, r, 0.52)),
		Vector2(hw * 0.99, rim * 0.985),
	]
	var prof: Array = []
	for p in base:
		prof.append(Vector2((p as Vector2).x * side, (p as Vector2).y))
	var tyre := _revolve_x(root, cx, zc, prof, _tyre_mat, 32)
	tyre.position.y = r
	# rim: a dark back plate deep in the barrel, then the brake, the spokes, and
	# finally a bright lip + hub. Every layer sits at its own depth.
	var plane := cx + side * hw
	_cyl(root, rim * 0.99, 0.012, Vector3(plane - side * 0.058, r, zc),
		_rim_dark, Vector3(0, 0, 90), 26)
	# brake disc, deep in the barrel
	_cyl(root, rim * 0.70, 0.012, Vector3(plane - side * 0.046, r, zc),
		_flat(Color(0.235, 0.245, 0.265), 0.58, 0.40), Vector3(0, 0, 90), 24)
	var ca := deg_to_rad(118.0)
	_box(root, Vector3(0.028, r * 0.20, r * 0.10),
		Vector3(plane - side * 0.050, r + r * 0.30 * sin(ca), zc + r * 0.30 * cos(ca)),
		_caliper, Vector3(rad_to_deg(ca) - 90.0, 0, 0))
	# five twin spokes
	var boxes: Array = []
	var phase := side * 0.20 + (0.12 if zc > 0.0 else 0.0)
	for i in range(5):
		var a0 := TAU * float(i) / 5.0 + phase
		for o in [-0.130, 0.130]:
			var a := a0 + float(o)
			var rc := r * 0.375
			boxes.append({
				"size": Vector3(0.018, r * 0.44, r * 0.095),
				"pos": Vector3(plane - side * 0.030, r + rc * sin(a), zc + rc * cos(a)),
				"rot": Vector3(rad_to_deg(a) - 90.0, 0, 0),
			})
	_merge_boxes(root, boxes, _rim_mat)
	# bright lip at the outer edge of the barrel, kept inside the tyre bead
	_ring(root, rim * 0.950, 0.008, Vector3(plane - side * 0.016, r, zc),
		_chrome_mat, Vector3(0, 0, 90), 28)
	# hub cap and badge, sitting proud of the spoke roots
	_cyl(root, rim * 0.265, 0.016, Vector3(plane - side * 0.020, r, zc),
		_chrome_mat, Vector3(0, 0, 90), 22)
	_cyl(root, rim * 0.180, 0.012, Vector3(plane - side * 0.013, r, zc),
		_rim_mat, Vector3(0, 0, 90), 20)
	_cyl(root, rim * 0.068, 0.010, Vector3(plane - side * 0.008, r, zc),
		_gap_mat, Vector3(0, 0, 90), 14)


func _merge_boxes(root: Node3D, boxes: Array, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in boxes:
		var bm := BoxMesh.new()
		var sz: Vector3 = b["size"]
		bm.size = sz
		var rd: Vector3 = b["rot"]
		var pos: Vector3 = b["pos"]
		var tr := Transform3D(Basis.from_euler(rd * (PI / 180.0)), pos)
		st.append_from(bm, 0, tr)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	root.add_child(mi)
	return mi


# --- hardware ---------------------------------------------------------------

func _build_hardware(root: Node3D) -> void:
	# mirrors on the A-pillar base: painted shell, dark glass face
	var u := _roof1 - 0.015
	var mt := lerpf(_cab0, _cab1, u)
	var mz := _zw(mt)
	var bx := _body_hw(mt) - 0.020
	for s: float in [-1.0, 1.0]:
		_box(root, Vector3(0.060, 0.030, 0.052), Vector3(s * (bx + 0.026), _belt + 0.014, mz), _trim_mat)
		_rbox(root, Vector3(0.098, 0.078, 0.175), Vector3(s * (bx + 0.082), _belt + 0.046, mz - 0.012),
			_roof_mat, Vector3.ZERO, 0.026)
		_box(root, Vector3(0.074, 0.058, 0.010), Vector3(s * (bx + 0.082), _belt + 0.046, mz - 0.100),
			_glass_mat)
	# door handles: short dark recesses, sunk into the flank
	for s: float in [-1.0, 1.0]:
		for t in [0.660, 0.440]:
			var y := _belt - 0.150
			_box(root, Vector3(0.012, 0.024, 0.092),
				Vector3(s * (_body_side_x(t, y) + 0.004), y, _zw(t)), _trim_mat)
	# fuel flap, right rear quarter
	var ft := maxf(0.235, _cab0 + 0.10)
	var fy := _belt - 0.200
	_cyl(root, 0.062, 0.008, Vector3(_body_side_x(ft, fy) + 0.002, fy, _zw(ft)),
		_gap_mat, Vector3(0, 0, 90), 20)
	_cyl(root, 0.053, 0.010, Vector3(_body_side_x(ft, fy) + 0.004, fy, _zw(ft)),
		_paint_mat, Vector3(0, 0, 90), 20)
	# shark-fin aerial
	if _sil in ["hatch", "sedan", "sport", "ev"]:
		_rbox(root, Vector3(0.045, 0.058, 0.130),
			Vector3(0, _roof + 0.018, _zw(lerpf(_cab0, _cab1, _roof0 + 0.13))),
			_roof_mat, Vector3(-12, 0, 0), 0.020)
	if float(_spec["wing"]) > 0.0:
		_build_wing(root)
	if bool(_spec["splitter"]):
		var ns := _body_sec(0.988)
		var sw: float = float(ns.hwb) * 0.99
		var sy := _body_bot(0.988) - 0.010
		_box(root, Vector3(sw * 2.0, 0.022, 0.26),
			Vector3(0, sy, _L * 0.5 - 0.098), _trim_mat, Vector3(-3, 0, 0))
		# splitter turning vanes
		for s: float in [-1.0, 1.0]:
			_box(root, Vector3(0.016, 0.030, 0.16),
				Vector3(s * sw * 0.62, sy + 0.020, _L * 0.5 - 0.110), _trim_mat)
	if bool(_spec["diffuser"]):
		var dy := _body_bot(0.020) + 0.010
		_box(root, Vector3(_W * 0.72, 0.040, 0.34),
			Vector3(0, dy + 0.030, -_L * 0.5 + 0.150), _trim_mat, Vector3(-13, 0, 0))
		for i in range(3):
			var fx := lerpf(-0.30, 0.30, float(i) / 2.0)
			_box(root, Vector3(0.016, 0.085, 0.30),
				Vector3(fx, dy + 0.048, -_L * 0.5 + 0.150), _trim_mat, Vector3(-13, 0, 0))
	match _sil:
		"offroad":
			_hw_offroad(root)
		"van":
			_hw_van(root)
		"muscle":
			_hw_muscle(root)
		"pickup":
			_hw_pickup(root)
		"sport":
			_hw_sport(root)
		"ev":
			_hw_ev(root)
		"hyper":
			_hw_hyper(root)


# Rear wing: a swept aerofoil section on two stanchions, with end plates. A
# box reads as a floating plank; the rounded section reads as a wing.
func _build_wing(root: Node3D) -> void:
	var h := float(_spec["wing"])
	var tw := 0.090
	var wz := _zw(tw)
	var wy := _body_top(tw) + h
	var span := _W * 0.78
	var chord := 0.250
	var th := 0.050
	var tilt := 7.0
	var tr := deg_to_rad(tilt)
	# stanchions
	for s: float in [-1.0, 1.0]:
		var x := s * _W * 0.250
		var y0 := _body_top_y(tw + 0.020, x) - 0.010
		var hh := maxf(0.06, wy - y0)
		_box(root, Vector3(0.034, hh, 0.118),
			Vector3(x, y0 + hh * 0.5, wz + 0.012), _trim_mat, Vector3(tilt * 0.30, 0, 0))
		_box(root, Vector3(0.076, 0.020, 0.190),
			Vector3(x, y0 + 0.008, wz + 0.016), _trim_mat)
	# aerofoil section swept along x
	var prof: Array = []
	var np := 9
	for k in range(np):
		var u := float(k) / float(np - 1)
		prof.append(Vector2(chord * (0.5 - u), th * 0.5 * pow(sin(PI * u), 0.60)))
	for k in range(np - 2, 0, -1):
		var u := float(k) / float(np - 1)
		prof.append(Vector2(chord * (0.5 - u), -th * 0.5 * pow(sin(PI * u), 0.60)))
	var rings: Array = []
	var ns := 11
	for i in range(ns):
		var x := lerpf(-span * 0.5, span * 0.5, float(i) / float(ns - 1))
		var ring := PackedVector3Array()
		for p in prof:
			var pv: Vector2 = p
			var rz := pv.x * cos(tr) - pv.y * sin(tr)
			var ry := pv.x * sin(tr) + pv.y * cos(tr)
			ring.push_back(Vector3(x, wy + ry, wz + rz))
		rings.push_back(ring)
	_sweep(root, rings, _trim_mat, false)
	# gurney flap at the trailing edge, and the end plates
	_box(root, Vector3(span * 0.96, 0.030, 0.012),
		Vector3(0, wy - 0.004, wz - chord * 0.480), _trim_mat, Vector3(tilt, 0, 0))
	for s: float in [-1.0, 1.0]:
		_box(root, Vector3(0.010, 0.090, chord * 0.86),
			Vector3(s * span * 0.5, wy + 0.004, wz), _trim_mat, Vector3(tilt, 0, 0))


func _hw_offroad(root: Node3D) -> void:
	var roof_s := _cab_sec(0.5)
	var rw: float = roof_s.hwt
	var z0 := _zw(lerpf(_cab0, _cab1, 0.115))
	var z1 := _zw(lerpf(_cab0, _cab1, 0.845))
	var ry := _cab_top_y(0.5, 0.0) + 0.040
	# rack frame: two side rails on feet, three cross bars
	for s: float in [-1.0, 1.0]:
		_box(root, Vector3(0.048, 0.040, z1 - z0),
			Vector3(s * rw * 0.80, ry, (z0 + z1) * 0.5), _trim_mat, Vector3.ZERO)
		for zz in [z0 + 0.09, (z0 + z1) * 0.5, z1 - 0.09]:
			_box(root, Vector3(0.042, 0.058, 0.048),
				Vector3(s * rw * 0.80, ry - 0.027, zz), _trim_mat)
	for i in range(3):
		var zz2 := lerpf(z0 + 0.10, z1 - 0.10, float(i) / 2.0)
		_box(root, Vector3(rw * 1.64, 0.030, 0.045), Vector3(0, ry + 0.008, zz2), _trim_mat)
	# spare wheel lying flat on the rack under a soft cover: a bulging dome with
	# a bolt down the middle, not a plain black drum
	var sz := lerpf(z0, z1, 0.38)
	var sy := ry + 0.024
	var cr := _wr * 0.90
	var prof: Array = [
		Vector2(cr * 0.66, 0.000), Vector2(cr * 0.90, 0.022),
		Vector2(cr * 1.00, 0.072), Vector2(cr * 0.985, 0.132),
		Vector2(cr * 0.86, 0.174), Vector2(cr * 0.62, 0.199),
		Vector2(cr * 0.32, 0.210),
	]
	_lathe_y(root, 0.0, sz, sy, prof, _flat(Color(0.150, 0.155, 0.160), 0.88), 30)
	_cyl(root, cr * 0.34, 0.020, Vector3(0, sy + 0.214, sz),
		_flat(Color(0.135, 0.140, 0.145), 0.90), Vector3.ZERO, 20)
	_cyl(root, cr * 0.13, 0.034, Vector3(0, sy + 0.228, sz), _chrome_mat, Vector3.ZERO, 14)
	# light bar across the front of the rack: one slim housing with an LED strip
	var lbz := z1 - 0.012
	var lby := ry + 0.062
	_rbox(root, Vector3(rw * 1.66, 0.052, 0.080), Vector3(0, lby, lbz),
		_trim_mat, Vector3.ZERO, 0.022)
	_box(root, Vector3(rw * 1.50, 0.017, 0.012), Vector3(0, lby + 0.003, lbz + 0.041),
		_lamp_w)
	_box(root, Vector3(rw * 1.42, 0.006, 0.014), Vector3(0, lby - 0.011, lbz + 0.041),
		_flat(Color(0.10, 0.11, 0.12), 0.45))
	for s: float in [-1.0, 1.0]:
		_box(root, Vector3(0.030, 0.048, 0.052),
			Vector3(s * rw * 0.72, lby - 0.044, lbz), _trim_mat)
	# bull bar, tight to the nose
	var bz := _L * 0.5 + 0.045
	for s: float in [-1.0, 1.0]:
		_cyl(root, 0.026, 0.46, Vector3(s * _W * 0.30, _clr + 0.26, bz), _trim_mat, Vector3.ZERO, 10)
	_cyl(root, 0.026, _W * 0.70, Vector3(0, _clr + 0.46, bz), _trim_mat, Vector3(0, 0, 90), 10)
	_cyl(root, 0.026, _W * 0.70, Vector3(0, _clr + 0.20, bz), _trim_mat, Vector3(0, 0, 90), 10)
	# rock sliders
	for s: float in [-1.0, 1.0]:
		_box(root, Vector3(0.070, 0.060, _L * 0.42),
			Vector3(s * (_W * 0.5 - 0.024), _clr + 0.035, 0), _trim_mat)
	# hood vents: paint-coloured bezels with dark recesses and louvres, pushed
	# outboard of the stripe band
	for s: float in [-1.0, 1.0]:
		var hx := s * 0.335
		var hz := _zw(0.858)
		var hy := _body_top_y(0.858, hx)
		_rbox(root, Vector3(0.255, 0.010, 0.205), Vector3(hx, hy + 0.002, hz),
			_paint_mat, Vector3.ZERO, 0.058)
		_rbox(root, Vector3(0.201, 0.012, 0.153), Vector3(hx, hy + 0.010, hz),
			_gap_mat, Vector3.ZERO, 0.038)
		for k in range(3):
			_box(root, Vector3(0.170, 0.009, 0.022),
				Vector3(hx, hy + 0.018, hz - 0.044 + float(k) * 0.044),
				_paint_mat, Vector3(-16, 0, 0))


func _hw_van(root: Node3D) -> void:
	# side moulding along the sliding door, hugging the flank
	for sd: float in [-1.0, 1.0]:
		_strip_h(root, 0.105, 0.885, _belt - 0.300, 0.055, sd, _trim_mat, 0.005)
	# roof rails on short feet
	var u0 := 0.190
	var u1 := 0.870
	var z0 := _zw(lerpf(_cab0, _cab1, u0))
	var z1 := _zw(lerpf(_cab0, _cab1, u1))
	var rm := (z0 + z1) * 0.5
	for sd: float in [-1.0, 1.0]:
		var x := _cab_hw(0.5) * 0.78
		var ytop := _cab_top_y(0.5, x)
		_box(root, Vector3(0.034, 0.026, z1 - z0), Vector3(sd * x, ytop + 0.036, rm), _trim_mat)
		for zz in [z0 + 0.07, rm, z1 - 0.07]:
			_box(root, Vector3(0.030, 0.040, 0.058),
				Vector3(sd * x, ytop + 0.012, zz), _trim_mat)
	# roof vent / AC pod: a rounded housing with louvres, so it reads as a
	# moulded part rather than a black brick
	var vz := _zw(lerpf(_cab0, _cab1, 0.42))
	var vy := _cab_top_y(0.42, 0.0)
	_rbox(root, Vector3(0.46, 0.050, 0.52), Vector3(0, vy + 0.021, vz),
		_flat(Color(0.20, 0.21, 0.23), 0.70), Vector3.ZERO, 0.040)
	for k in range(3):
		_box(root, Vector3(0.30, 0.008, 0.026),
			Vector3(0, vy + 0.048, vz - 0.10 + float(k) * 0.10),
			_flat(Color(0.10, 0.11, 0.12), 0.55))


func _hw_muscle(root: Node3D) -> void:
	var hz := _zw(0.815)
	var sy := _body_top_y(0.815, 0.0)
	# shaker scoop in body colour, rounded, with a dark forward-facing mouth
	_rbox(root, Vector3(0.42, 0.072, 0.52), Vector3(0, sy + 0.026, hz),
		_paint_mat, Vector3.ZERO, 0.030)
	_rbox(root, Vector3(0.33, 0.046, 0.055), Vector3(0, sy + 0.042, hz + 0.262),
		_gap_mat, Vector3.ZERO, 0.018)
	for k in range(2):
		_box(root, Vector3(0.27, 0.009, 0.026),
			Vector3(0, sy + 0.048, hz + 0.238 + float(k) * 0.034),
			_flat(Color(0.10, 0.11, 0.12), 0.50))
	# hood pins
	for s: float in [-1.0, 1.0]:
		_cyl(root, 0.016, 0.014, Vector3(s * 0.30, _body_top_y(0.905, s * 0.30) + 0.006,
			_zw(0.905)), _chrome_mat, Vector3.ZERO, 12)
		_strip_h(root, 0.310, 0.690, _body_bot(0.5) + 0.040, 0.070, s, _trim_mat, 0.010)
	_box(root, Vector3(_W * 0.78, 0.16, 0.03), Vector3(0, _tail - 0.10, -_L * 0.5 - 0.008), _trim_mat)


func _hw_pickup(root: Node3D) -> void:
	var zt := -_L * 0.5 + 0.048          # tailgate centre
	var z0 := zt + 0.048                 # inner face of the tailgate
	var z1 := _zw(_cab0 - 0.035)
	var mid := (z0 + z1) * 0.5
	var wh := 0.215
	var hw: float = _body_hw(0.20)
	var wall := 0.085
	var liner := _flat(Color(0.105, 0.108, 0.118), 0.80)
	# side walls and bulkhead, sunk 32 mm into the deck so that no face is
	# coplanar with the body's top surface (that z-fights into bright lines)
	for s: float in [-1.0, 1.0]:
		_rbox(root, Vector3(wall, wh + 0.032, z1 - z0),
			Vector3(s * (hw - wall * 0.62), _deck + wh * 0.5 - 0.016, mid),
			_paint_mat, Vector3.ZERO, 0.018)
	_rbox(root, Vector3(hw * 1.84, wh + 0.032, wall),
		Vector3(0, _deck + wh * 0.5 - 0.016, z1 - 0.006),
		_paint_mat, Vector3.ZERO, 0.018)
	# tailgate, flush with the rear face, with a handle
	_rbox(root, Vector3(hw * 1.86, wh + 0.030, 0.092),
		Vector3(0, _deck + wh * 0.5 - 0.015, zt),
		_paint_mat, Vector3.ZERO, 0.020)
	_box(root, Vector3(0.30, 0.022, 0.018),
		Vector3(0, _deck + wh * 0.66, zt - 0.048), _chrome_mat)
	# tub liner: floor and inner panels
	var fw := hw - wall * 1.12
	var fy := _deck + 0.010
	var rows: Array = []
	for i in range(10):
		var z := lerpf(z0 + 0.006, z1 - 0.045, float(i) / 9.0)
		var row := PackedVector3Array()
		for j in range(3):
			row.push_back(Vector3(lerpf(-fw, fw, float(j) / 2.0), fy, z))
		rows.push_back(row)
	_patch(root, rows, liner)
	for s: float in [-1.0, 1.0]:
		var rows2: Array = []
		for i in range(6):
			var z := lerpf(z0 + 0.010, z1 - 0.050, float(i) / 5.0)
			var row2 := PackedVector3Array()
			for j in range(2):
				row2.push_back(Vector3(s * (fw + 0.002),
					lerpf(fy, _deck + wh * 0.80, float(j)), z))
			rows2.push_back(row2)
		var side := _grid_patch(root, rows2, Vector3(-s, 0, 0), liner)
		if side != null:
			side.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# rails on top of the walls and the tailgate
	for s: float in [-1.0, 1.0]:
		_box(root, Vector3(0.098, 0.026, z1 - z0),
			Vector3(s * (hw - wall * 0.62), _deck + wh + 0.010, mid), _trim_mat)
	_box(root, Vector3(hw * 1.86, 0.026, 0.098),
		Vector3(0, _deck + wh + 0.010, z1 - 0.006), _trim_mat)
	_box(root, Vector3(hw * 1.86, 0.026, 0.104),
		Vector3(0, _deck + wh + 0.010, zt), _trim_mat)
	# cargo: a crate and a barrel standing on the liner
	_box(root, Vector3(0.52, 0.30, 0.48), Vector3(-0.22, fy + 0.150, mid + 0.14), _flat(Color(0.46, 0.36, 0.24), 0.8))
	_box(root, Vector3(0.46, 0.05, 0.42), Vector3(-0.22, fy + 0.320, mid + 0.14), _flat(Color(0.55, 0.44, 0.30), 0.8))
	_cyl(root, 0.135, 0.34, Vector3(0.36, fy + 0.170, mid - 0.30), _flat(Color(0.28, 0.34, 0.40), 0.55, 0.4), Vector3.ZERO, 16)


func _hw_sport(root: Node3D) -> void:
	var ky := _body_bot(0.5) + 0.032
	for s: float in [-1.0, 1.0]:
		_strip_h(root, 0.318, 0.682, ky, 0.052, s, _trim_mat, 0.012)
		# hood vent: a paint-coloured bezel with a soft outline, a dark recess
		# inside it and three louvres catching the light
		var hx := s * 0.40
		var hz := _zw(0.805)
		var hy := _body_top_y(0.805, hx)
		_rbox(root, Vector3(0.262, 0.010, 0.232), Vector3(hx, hy + 0.003, hz),
			_paint_mat, Vector3.ZERO, 0.055)
		_rbox(root, Vector3(0.206, 0.012, 0.178), Vector3(hx, hy + 0.011, hz),
			_gap_mat, Vector3.ZERO, 0.036)
		for k in range(3):
			_box(root, Vector3(0.168, 0.010, 0.026),
				Vector3(hx, hy + 0.019, hz - 0.048 + float(k) * 0.048),
				_paint_mat, Vector3(-18, 0, 0))
	_box(root, Vector3(_W * 0.66, 0.05, 0.10), Vector3(0, _tail - 0.05, -_L * 0.5 + 0.030), _trim_mat)


func _hw_ev(root: Node3D) -> void:
	var s := _body_sec(1.0)
	var hw: float = s.hwt
	_box(root, Vector3(hw * 1.34, 0.030, 0.05),
		Vector3(0, float(s.y1) - 0.145, _L * 0.5 + 0.020), _lamp_w)
	var r := _body_sec(0.0)
	_box(root, Vector3(float(r.hwt) * 1.46, 0.026, 0.04),
		Vector3(0, _tail - 0.09, -_L * 0.5 - 0.020), _lamp_r)
	for sd: float in [-1.0, 1.0]:
		for t in [0.34, 0.62]:
			_box(root, Vector3(0.020, 0.032, 0.150),
				Vector3(sd * (_body_side_x(t, _belt - 0.150) + 0.004), _belt - 0.150, _zw(t)), _chrome_mat)


func _hw_hyper(root: Node3D) -> void:
	for i in range(5):
		var x := lerpf(-0.62, 0.62, float(i) / 4.0)
		_box(root, Vector3(0.03, 0.12, 0.28), Vector3(x, _clr + 0.085, -_L * 0.5 + 0.16), _trim_mat, Vector3(-14, 0, 0))
	for s: float in [-1.0, 1.0]:
		_box(root, Vector3(0.03, 0.20, 0.46),
			Vector3(s * (_body_side_x(0.30, _belt - 0.140) + 0.004), _belt - 0.140, _zw(0.30)), _trim_mat)
	for i in range(3):
		_box(root, Vector3(0.62, 0.02, 0.07), Vector3(0, _deck + 0.008, _zw(0.16) - float(i) * 0.11), _trim_mat)
	# roof intake: a paint-coloured scoop with a soft outline and a dark mouth
	var iy := _cab_top_y(0.34, 0.0)
	var iz := _zw(lerpf(_cab0, _cab1, 0.34))
	_rbox(root, Vector3(0.235, 0.062, 0.400), Vector3(0, iy + 0.016, iz + 0.030),
		_paint_mat, Vector3.ZERO, 0.062)
	_rbox(root, Vector3(0.170, 0.034, 0.055), Vector3(0, iy + 0.036, iz + 0.206),
		_gap_mat, Vector3.ZERO, 0.014)
	_box(root, Vector3(0.140, 0.008, 0.030), Vector3(0, iy + 0.050, iz + 0.196),
		_flat(Color(0.12, 0.13, 0.15), 0.55))


# --- lights -----------------------------------------------------------------

func _build_lights(root: Node3D) -> void:
	var fs := _body_sec(1.0)
	var fw: float = fs.hwt
	var fy1: float = fs.y1
	var fy0: float = fs.y0
	var nz := _L * 0.5
	# grille, kept between the headlamps, with a chrome surround and badge
	var gin := fw - 0.360
	_rbox(root, Vector3(gin * 2.0, 0.092, 0.034), Vector3(0, fy1 - 0.102, nz + 0.006),
		_gap_mat, Vector3.ZERO, 0.016)
	_rbox(root, Vector3(gin * 2.0, 0.010, 0.030), Vector3(0, fy1 - 0.062, nz + 0.014),
		_chrome_mat, Vector3.ZERO, 0.005)
	for k in range(3):
		var gy := fy1 - 0.078 - float(k) * 0.022
		_rbox(root, Vector3(gin * 1.96, 0.008, 0.024), Vector3(0, gy, nz + 0.012),
			_flat(Color(0.13, 0.14, 0.16), 0.55, 0.35), Vector3.ZERO, 0.004)
	_rbox(root, Vector3(0.115, 0.046, 0.022), Vector3(0, fy1 - 0.086, nz + 0.022),
		_chrome_mat, Vector3.ZERO, 0.010)
	# headlamps: dark pod, glass lens, a bright DRL strip under the lens
	for s: float in [-1.0, 1.0]:
		var lx := s * (fw - 0.200)
		_rbox(root, Vector3(0.320, 0.116, 0.046), Vector3(lx, fy1 - 0.096, nz + 0.004),
			_gap_mat, Vector3.ZERO, 0.028)
		_rbox(root, Vector3(0.272, 0.082, 0.040), Vector3(lx, fy1 - 0.098, nz + 0.020),
			_lens, Vector3.ZERO, 0.022)
		_box(root, Vector3(0.250, 0.016, 0.010), Vector3(lx, fy1 - 0.132, nz + 0.032), _lamp_w)
		_rbox(root, Vector3(0.052, 0.030, 0.014), Vector3(s * (fw - 0.075), fy1 - 0.100, nz + 0.026),
			_lamp_a, Vector3.ZERO, 0.010)
	# front valance: the body colour carries the bumper, a slim dark intake
	# sits below it and a pair of ducts closes the corners
	_rbox(root, Vector3(fw * 1.02, 0.092, 0.045), Vector3(0, fy1 - 0.208, nz + 0.010),
		_gap_mat, Vector3.ZERO, 0.030)
	_rbox(root, Vector3(fw * 0.96, 0.030, 0.030), Vector3(0, fy0 + 0.052, nz + 0.014),
		_gap_mat, Vector3.ZERO, 0.012)
	for s: float in [-1.0, 1.0]:
		_rbox(root, Vector3(0.090, 0.060, 0.030),
			Vector3(s * (fw - 0.105), fy0 + 0.058, nz + 0.012), _gap_mat, Vector3.ZERO, 0.014)
	# rear face
	var rs := _body_sec(0.0)
	var rw: float = rs.hwt
	var ry1: float = rs.y1
	var ry0: float = rs.y0
	var tz := -_L * 0.5
	for s: float in [-1.0, 1.0]:
		var lx2 := s * (rw - 0.175)
		_rbox(root, Vector3(0.225, 0.255, 0.055), Vector3(lx2, ry1 - 0.185, tz - 0.010),
			_gap_mat, Vector3.ZERO, 0.030)
		_rbox(root, Vector3(0.175, 0.190, 0.050), Vector3(lx2, ry1 - 0.180, tz - 0.020),
			_lamp_r, Vector3.ZERO, 0.026)
		_box(root, Vector3(0.160, 0.034, 0.020), Vector3(lx2, ry1 - 0.262, tz - 0.044), _lamp_w)
		_box(root, Vector3(0.090, 0.030, 0.014), Vector3(lx2, ry1 - 0.094, tz - 0.042), _lamp_a)
	# rear valance
	_rbox(root, Vector3(rw * 1.02, 0.088, 0.045), Vector3(0, ry0 + 0.062, tz - 0.008),
		_trim_mat, Vector3.ZERO, 0.028)
	_rbox(root, Vector3(0.385, 0.130, 0.026), Vector3(0, ry0 + 0.180, tz - 0.014),
		_gap_mat, Vector3.ZERO, 0.014)
	_box(root, Vector3(0.335, 0.098, 0.014), Vector3(0, ry0 + 0.180, tz - 0.024),
		_flat(Color(0.88, 0.89, 0.86), 0.60))
	if _sil in ["sport", "hyper", "muscle"]:
		for s: float in [-1.0, 1.0]:
			_cyl(root, 0.050, 0.10, Vector3(s * 0.30, ry0 + 0.030, tz - 0.030),
				_chrome_mat, Vector3(90, 0, 0), 14)
			_cyl(root, 0.036, 0.020, Vector3(s * 0.30, ry0 + 0.030, tz - 0.082),
				_gap_mat, Vector3(90, 0, 0), 12)
	else:
		_cyl(root, 0.036, 0.11, Vector3(rw * 0.62, ry0 + 0.030, tz - 0.035),
			_chrome_mat, Vector3(90, 0, 0), 14)


# --- measurement ------------------------------------------------------------

func bounds() -> AABB:
	var acc := AABB()
	var has := false
	var stack: Array = [self]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var tr := Transform3D.IDENTITY
			var p: Node = mi
			while p != null and p != self:
				tr = (p as Node3D).transform * tr
				p = p.get_parent()
			var b: AABB = tr * mi.get_aabb()
			acc = b if not has else acc.merge(b)
			has = true
		for c in n.get_children():
			stack.push_back(c)
	return acc
