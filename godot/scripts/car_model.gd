class_name CarModel3D
extends Node3D

# Procedural 3D garage model. Every car is built from lofted, shaded meshes:
# body shell, greenhouse, wheels, arches and class hardware. No assets and no
# textures — just generated geometry and StandardMaterial3D.
#
# The model faces +Z (nose towards the camera). Units are metres, wheels rest
# at y = 0 so the stage camera can frame it like a real turntable shot.

const CAB_P := 0.36

const _BASE := {
	"L": 4.10, "W": 1.78, "clr": 0.26, "belt": 0.94, "roof": 1.42,
	"wr": 0.34, "ww": 0.23, "wb": 0.58,
	"cab0": 0.28, "cab1": 0.72, "cabw": 0.79,
	"tail": 0.80, "deck": 0.86, "hood": 0.70, "nose": 0.62,
	"p": 0.55, "flare": 0.062,
	"rails": false, "rack": false, "spare": false, "lightbar": false,
	"bullbar": false, "scoop": false, "bed": false, "vent": false,
	"cargo": false, "wing": 0.0, "splitter": false, "diffuser": false,
	"glass_roof": false, "big_tires": false, "visor": false,
}

const SPECS := {
	"hatch": {"L": 3.80, "W": 1.70, "belt": 0.92, "roof": 1.44, "cab0": 0.18, "cab1": 0.70,
		"tail": 0.78, "deck": 0.84, "hood": 0.68, "nose": 0.60, "p": 0.42, "clr": 0.21, "cabw": 0.80},
	"van": {"L": 4.60, "W": 1.86, "belt": 1.16, "roof": 1.84, "cab0": 0.12, "cab1": 0.86,
		"tail": 0.98, "deck": 0.98, "hood": 0.86, "nose": 0.78, "p": 0.30, "clr": 0.24,
		"cabw": 0.90, "vent": true},
	"sedan": {"L": 4.32, "W": 1.80, "belt": 0.94, "roof": 1.42, "cab0": 0.30, "cab1": 0.70,
		"tail": 0.80, "deck": 0.86, "hood": 0.69, "nose": 0.60, "p": 0.42, "clr": 0.21, "cabw": 0.78},
	"offroad": {"L": 4.30, "W": 1.90, "belt": 1.08, "roof": 1.74, "cab0": 0.20, "cab1": 0.78,
		"tail": 0.86, "deck": 0.92, "hood": 0.78, "nose": 0.70, "clr": 0.34,
		"wr": 0.42, "ww": 0.30, "p": 0.28, "flare": 0.085, "cabw": 0.84,
		"rails": true, "rack": true, "spare": true, "lightbar": true,
		"bullbar": true, "big_tires": true},
	"muscle": {"L": 4.40, "W": 1.86, "belt": 0.98, "roof": 1.36, "cab0": 0.34, "cab1": 0.66,
		"tail": 0.82, "deck": 0.88, "hood": 0.74, "nose": 0.64, "p": 0.40, "clr": 0.21,
		"cabw": 0.80, "scoop": true, "wing": 0.14},
	"pickup": {"L": 4.55, "W": 1.88, "belt": 1.02, "roof": 1.50, "cab0": 0.40, "cab1": 0.74,
		"tail": 0.62, "deck": 0.62, "hood": 0.74, "nose": 0.66, "p": 0.30, "clr": 0.28,
		"cabw": 0.82, "bed": true, "cargo": true},
	"sport": {"L": 4.24, "W": 1.86, "belt": 0.86, "roof": 1.22, "cab0": 0.24, "cab1": 0.64,
		"tail": 0.74, "deck": 0.80, "hood": 0.62, "nose": 0.56, "p": 0.42, "clr": 0.17,
		"cabw": 0.76, "wing": 0.26, "splitter": true, "diffuser": true},
	"ev": {"L": 4.30, "W": 1.84, "belt": 0.92, "roof": 1.40, "cab0": 0.20, "cab1": 0.74,
		"tail": 0.78, "deck": 0.84, "hood": 0.68, "nose": 0.60, "p": 0.42, "clr": 0.21,
		"cabw": 0.78, "glass_roof": true},
	"hyper": {"L": 4.36, "W": 1.98, "belt": 0.82, "roof": 1.14, "cab0": 0.20, "cab1": 0.60,
		"tail": 0.70, "deck": 0.76, "hood": 0.58, "nose": 0.52, "p": 0.38, "clr": 0.15,
		"cabw": 0.80, "wing": 0.34, "splitter": true, "diffuser": true, "visor": true},
}

var _root: Node3D
var _sig := ""

# --- build-time state -------------------------------------------------------
var _spec: Dictionary = {}
var _sil := "sedan"
var _L := 4.1
var _W := 1.78
var _clr := 0.26
var _belt := 0.94
var _roof := 1.42
var _wr := 0.34
var _ww := 0.23
var _wb := 0.58
var _cab0 := 0.28
var _cab1 := 0.72
var _cabw := 0.79
var _p := 0.55
var _flare := 0.062
var _tail := 0.80
var _deck := 0.86
var _hood := 0.70
var _nose := 0.62
var _wz_f := 0.0
var _wz_r := 0.0
var _topk: Array = []
var _widk: Array = []
var _cabk: Array = []
var _stripe_on := false
var _paint_mat: StandardMaterial3D
var _roof_mat: StandardMaterial3D
var _stripe_mat: StandardMaterial3D
var _glass_mat: StandardMaterial3D
var _trim_mat: StandardMaterial3D
var _rub_mat: StandardMaterial3D
var _rim_mat: StandardMaterial3D
var _chrome_mat: StandardMaterial3D
var _lamp_w: StandardMaterial3D
var _lamp_r: StandardMaterial3D
var _lamp_a: StandardMaterial3D


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
	m.metallic = 0.02
	m.roughness = 0.50
	m.metallic_specular = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _flat(c: Color, rough := 0.55, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	m.metallic_specular = 0.08
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.135, 0.165, 0.205)
	m.metallic = 0.38
	m.roughness = 0.13
	m.metallic_specular = 1.0
	m.emission_enabled = true
	m.emission = Color(0.030, 0.042, 0.058)
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
	_p = float(_spec["p"])
	_flare = float(_spec["flare"])
	_tail = float(_spec["tail"])
	_deck = float(_spec["deck"])
	_hood = float(_spec["hood"])
	_nose = float(_spec["nose"])
	_wz_f = _wb * 0.5 * _L
	_wz_r = -_wz_f
	_stripe_on = stripe_on

	_paint_mat = _paint(paint)
	_roof_mat = _paint(paint.darkened(0.14))
	_stripe_mat = _flat(stripe, 0.42)
	_glass_mat = _glass()
	_trim_mat = _flat(Color(0.055, 0.060, 0.068), 0.72)
	_rub_mat = _flat(Color(0.038, 0.040, 0.044), 0.94)
	_rim_mat = _metal(Color(0.62, 0.65, 0.70), 0.28, 0.55)
	_chrome_mat = _metal(Color(0.80, 0.82, 0.86), 0.12, 0.55)
	_lamp_w = _emissive(Color(1.0, 0.96, 0.86), 1.3)
	_lamp_r = _emissive(Color(1.0, 0.13, 0.09), 1.7)
	_lamp_a = _emissive(Color(1.0, 0.52, 0.10), 1.1)

	_make_keys()
	_build_body(root)
	_build_cabin(root)
	_build_stripes(root)
	var sill_hw := _body_hw(0.5) - 0.004
	for sd in [-1.0, 1.0]:
		_box(root, Vector3(0.028, 0.085, _L * 0.70),
			Vector3(sd * sill_hw, _clr + 0.045, 0.02), _trim_mat)
	_build_wheels(root)
	_build_hardware(root)
	_build_lights(root)


func _make_keys() -> void:
	_topk = [
		[0.0, _tail],
		[0.05, _deck],
		[maxf(0.06, _cab0 - 0.10), _deck],
		[_cab0, _belt],
		[_cab1, _belt],
		[minf(0.985, _cab1 + 0.085), _hood],
		[1.0, _nose],
	]
	_widk = [
		[0.0, 0.88], [0.035, 0.95], [0.10, 1.0],
		[0.90, 1.0], [0.965, 0.95], [1.0, 0.88],
	]
	var b := _belt
	var r := _roof
	_cabk = [
		[0.0, b + 0.045],
		[0.09, lerpf(b, r, 0.62)],
		[0.22, r],
		[0.80, r],
		[0.91, lerpf(b, r, 0.64)],
		[1.0, b + 0.055],
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


func _body_bot(t: float) -> float:
	return _clr + _profile([[0.0, 0.085], [0.05, 0.0], [0.95, 0.0], [1.0, 0.07]], t)


func _body_hw(t: float) -> float:
	var hw := (_W * 0.5 - 0.100) * _profile(_widk, t)
	var fl := 0.0
	for wz in [_wz_f, _wz_r]:
		var tt := (float(wz) + _L * 0.5) / _L
		var d := absf(t - tt)
		if d < 0.105:
			fl = maxf(fl, _flare * (1.0 - pow(d / 0.105, 2.0)))
	return hw + fl


func _cab_hw(u: float) -> float:
	return _W * 0.5 * _cabw * (0.975 - 0.075 * pow(2.0 * u - 1.0, 2.0))


func _cab_y0(u: float) -> float:
	return _body_top(lerpf(_cab0, _cab1, u)) - 0.03


func _cab_y1(u: float) -> float:
	return maxf(_profile(_cabk, u), _cab_y0(u) + 0.04)


# Superellipse cross-section: rounded rectangle, closed loop, CCW from +Z.
func _se_ring(hw: float, y0: float, y1: float, p: float, n: int, z: float) -> Dictionary:
	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()
	pts.resize(n)
	nrm.resize(n)
	var ym := (y0 + y1) * 0.5
	var hh := maxf(0.004, (y1 - y0) * 0.5)
	var hws := maxf(0.004, hw)
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var c := cos(a)
		var s := sin(a)
		var ac := absf(c)
		var asc := absf(s)
		pts[i] = Vector2(hws * signf(c) * pow(ac, p), ym + hh * signf(s) * pow(asc, p))
		var nx := signf(c) * pow(maxf(ac, 0.0001), 2.0 - p) / hws
		var ny := signf(s) * pow(maxf(asc, 0.0001), 2.0 - p) / hh
		var l := sqrt(nx * nx + ny * ny)
		nrm[i] = Vector2(nx / l, ny / l)
	return {"z": z, "pts": pts, "nrm": nrm}


# Height of a section's top surface at lateral position x.
func _surface_y(hw: float, y0: float, y1: float, p: float, x: float) -> float:
	var ym := (y0 + y1) * 0.5
	var hh := (y1 - y0) * 0.5
	var k := clampf(absf(x) / maxf(0.0001, hw), 0.0, 1.0)
	return ym + hh * pow(maxf(0.0, 1.0 - pow(k, 2.0 / p)), p * 0.5)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3) -> void:
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
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
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
		var dz := maxf(0.0001, zb - za)
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
			dz = dz
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


# Grid patch from rows of points, shaded as a smooth upward surface.
func _patch(parent: Node3D, rows: Array, mat: Material) -> MeshInstance3D:
	if rows.size() < 2:
		return null
	var cols: int = (rows[0] as PackedVector3Array).size()
	if cols < 2:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(rows.size() - 1):
		var a: PackedVector3Array = rows[i]
		var b: PackedVector3Array = rows[i + 1]
		for j in range(cols - 1):
			var p00 := a[j]
			var p10 := a[j + 1]
			var p01 := b[j]
			var p11 := b[j + 1]
			var nrm := (p10 - p00).cross(p01 - p00)
			if nrm.y < 0.0:
				nrm = -nrm
			nrm = (nrm.normalized() + Vector3.UP * 0.8).normalized()
			_tri(st, p00, p01, p11, nrm, nrm, nrm)
			_tri(st, p00, p11, p10, nrm, nrm, nrm)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
	return mi


# Sweep a closed loop of points along a path; normals radiate from the ring centre.
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
				var v0 := r[i]
				var v1 := r[j]
				var nn := (v1 - c).cross(v0 - c).normalized()
				if flip:
					nn = -nn
				_tri(st, c, v0, v1, nn, nn, nn)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
	return mi


# --- primitives -------------------------------------------------------------

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


# --- body -------------------------------------------------------------------

func _build_body(root: Node3D) -> void:
	var n := 36
	var rings: Array = []
	for i in range(n):
		var t := float(i) / float(n - 1)
		rings.push_back(_se_ring(_body_hw(t), _body_bot(t), _body_top(t), _p, 44, _zw(t)))
	_loft(root, rings, _paint_mat, true, true)
	_box(root, Vector3(_W * 0.72, _clr * 1.55, _L * 0.76), Vector3(0, _clr * 0.775, 0),
		_flat(Color(0.045, 0.048, 0.055), 0.85))


func _build_cabin(root: Node3D) -> void:
	var n := 20
	var rings: Array = []
	for i in range(n):
		var u := float(i) / float(n - 1)
		var t := lerpf(_cab0, _cab1, u)
		rings.push_back(_se_ring(_cab_hw(u), _cab_y0(u), _cab_y1(u), CAB_P, 32, _zw(t)))
	_loft(root, rings, _glass_mat, true, true)

	# roof panel in body colour (or glass on the EV)
	var rows: Array = []
	var cols := 9
	for i in range(15):
		var u := lerpf(0.205, 0.815, float(i) / 14.0)
		var t := lerpf(_cab0, _cab1, u)
		var hw := _cab_hw(u)
		var y0 := _cab_y0(u)
		var y1 := _cab_y1(u)
		var row := PackedVector3Array()
		for j in range(cols):
			var x := lerpf(-hw * 0.76, hw * 0.76, float(j) / float(cols - 1))
			row.push_back(Vector3(x, _surface_y(hw, y0, y1, CAB_P, x) + 0.005, _zw(t)))
		rows.push_back(row)
	_patch(root, rows, _roof_mat)
	if bool(_spec["glass_roof"]):
		var grow: Array = []
		for i in range(11):
			var gu := lerpf(0.26, 0.76, float(i) / 10.0)
			var gt := lerpf(_cab0, _cab1, gu)
			var ghw := _cab_hw(gu)
			var gy0 := _cab_y0(gu)
			var gy1 := _cab_y1(gu)
			var grow_row := PackedVector3Array()
			for j in range(7):
				var gx := lerpf(-ghw * 0.50, ghw * 0.50, float(j) / 6.0)
				grow_row.push_back(Vector3(gx, _surface_y(ghw, gy0, gy1, CAB_P, gx) + 0.012, _zw(gt)))
			grow.push_back(grow_row)
		_patch(root, grow, _glass_mat)

	# visor strip: dark band across the top of the windscreen
	if bool(_spec["visor"]):
		var u0 := 0.10
		var t := lerpf(_cab0, _cab1, u0)
		var hw := _cab_hw(u0) * 0.94
		var row2 := PackedVector3Array()
		for j in range(5):
			var x := lerpf(-hw, hw, float(j) / 4.0)
			row2.push_back(Vector3(x, _cab_y1(u0) - 0.05, _zw(t)))
		var rows2: Array = [row2, row2]
		rows2[1] = PackedVector3Array()
		for j in range(5):
			var x := lerpf(-hw, hw, float(j) / 4.0)
			rows2[1].push_back(Vector3(x, _cab_y1(u0) - 0.05, _zw(t) - 0.05))
		_patch(root, rows2, _trim_mat)


# Twin racing stripes over hood, roof and deck, hugging each surface.
func _build_stripes(root: Node3D) -> void:
	if not _stripe_on:
		return
	var si := _W * 0.055
	var so := _W * 0.155
	for s in [-1.0, 1.0]:
		# hood
		var rows: Array = []
		for i in range(10):
			var t := lerpf(_cab1 + 0.075, 0.975, float(i) / 9.0)
			rows.push_back(_body_stripe_row(t, s, si, so))
		_patch(root, rows, _stripe_mat)
		# deck / boot
		var rows2: Array = []
		for i in range(7):
			var t := lerpf(0.035, maxf(0.05, _cab0 - 0.085), float(i) / 6.0)
			rows2.push_back(_body_stripe_row(t, s, si, so))
		_patch(root, rows2, _stripe_mat)
		# roof
		var rows3: Array = []
		for i in range(9):
			var u := lerpf(0.235, 0.79, float(i) / 8.0)
			var t := lerpf(_cab0, _cab1, u)
			var hw := _cab_hw(u)
			var y0 := _cab_y0(u)
			var y1 := _cab_y1(u)
			var row := PackedVector3Array()
			for j in range(3):
				var x := lerpf(si, so, float(j) / 2.0) * float(s)
				row.push_back(Vector3(x, _surface_y(hw, y0, y1, CAB_P, x) + 0.010, _zw(t)))
			rows3.push_back(row)
		_patch(root, rows3, _stripe_mat)


func _body_stripe_row(t: float, s: float, si: float, so: float) -> PackedVector3Array:
	var hw := _body_hw(t)
	var y0 := _body_bot(t)
	var y1 := _body_top(t)
	var row := PackedVector3Array()
	for j in range(3):
		var x := lerpf(si, so, float(j) / 2.0) * float(s)
		row.push_back(Vector3(x, _surface_y(hw, y0, y1, _p, x) + 0.007, _zw(t)))
	return row


# --- wheels -----------------------------------------------------------------

func _build_wheels(root: Node3D) -> void:
	var x_out := _W * 0.5 + 0.045
	var cx := x_out - _ww * 0.5
	for s in [-1.0, 1.0]:
		for zc in [_wz_f, _wz_r]:
			_wheel(root, cx * s, zc, s)
			_arch(root, zc, s)


func _wheel(root: Node3D, x: float, zc: float, side: float) -> void:
	var r := _wr
	var rot := Vector3(0, 0, 90)
	_cyl(root, r, _ww, Vector3(x, r, zc), _rub_mat, rot, 28)
	_cyl(root, r * 0.66, _ww * 1.07, Vector3(x, r, zc), _rim_mat, rot, 24)
	_cyl(root, r * 0.42, _ww * 1.12, Vector3(x, r, zc), _chrome_mat, rot, 24)
	_cyl(root, r * 0.26, _ww * 1.16, Vector3(x, r, zc), _trim_mat, rot, 16)
	if bool(_spec["big_tires"]):
		for i in range(16):
			var a := TAU * (float(i) + 0.5) / 16.0
			var pos := Vector3(x, r * sin(a), zc + r * cos(a))
			_box(root, Vector3(_ww * 0.94, 0.06, 0.10), pos, _rub_mat,
				Vector3(rad_to_deg(PI * 0.5 - a), 0, 0))


# Fender flare: a swept band hugging the top half of the wheel.
func _arch(root: Node3D, zc: float, side: float) -> void:
	var t := (zc + _L * 0.5) / _L
	var bx := _body_hw(t)
	var x0 := (bx - 0.020) * side
	var x1 := (_W * 0.5 + 0.072) * side
	var r0 := _wr + 0.014
	var r1 := _wr + 0.014 + _flare
	var amin := asin(clampf((_body_bot(t) + 0.01) / r1, 0.12, 0.92))
	var a0 := amin
	var a1 := PI - amin
	var steps := 14
	var rings: Array = []
	for i in range(steps + 1):
		var a := lerpf(a0, a1, float(i) / float(steps))
		var sa := sin(a)
		var ca := cos(a)
		var ring := PackedVector3Array()
		ring.push_back(Vector3(x0, r1 * sa, zc + r1 * ca))
		ring.push_back(Vector3(x1, r1 * sa, zc + r1 * ca))
		ring.push_back(Vector3(x1, r0 * sa, zc + r0 * ca))
		ring.push_back(Vector3(x0, r0 * sa, zc + r0 * ca))
		rings.push_back(ring)
	_sweep(root, rings, _paint_mat, true)


# --- hardware ---------------------------------------------------------------

func _build_hardware(root: Node3D) -> void:
	# mirrors
	var mz := _zw(_cab1) - 0.10
	for s in [-1.0, 1.0]:
		var bx := _body_hw(_cab1)
		_box(root, Vector3(0.11, 0.032, 0.055), Vector3(s * (bx + 0.040), _belt - 0.02, mz), _trim_mat)
		_box(root, Vector3(0.10, 0.075, 0.05), Vector3(s * (bx + 0.110), _belt + 0.015, mz), _paint_mat)
	if float(_spec["wing"]) > 0.0:
		_build_wing(root)
	if bool(_spec["splitter"]):
		_box(root, Vector3(_W * 0.92, 0.035, 0.34), Vector3(0, _clr + 0.012, _L * 0.5 - 0.07), _trim_mat)
	if bool(_spec["diffuser"]):
		_box(root, Vector3(_W * 0.80, 0.05, 0.30), Vector3(0, _clr + 0.075, -_L * 0.5 + 0.15), _trim_mat, Vector3(-14, 0, 0))
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


func _build_wing(root: Node3D) -> void:
	var h := float(_spec["wing"])
	var wz := _zw(0.085)
	var wy := _deck + h
	var span := _W * 0.88
	for s in [-1.0, 1.0]:
		_box(root, Vector3(0.05, h + 0.14, 0.11), Vector3(s * _W * 0.30, _deck + h * 0.5, wz), _trim_mat)
		_box(root, Vector3(0.025, 0.16, 0.44), Vector3(s * span * 0.5, wy + 0.03, wz), _trim_mat)
	var wm: Material = _trim_mat
	_box(root, Vector3(span, 0.045, 0.38), Vector3(0, wy, wz), wm, Vector3(9, 0, 0))


func _hw_offroad(root: Node3D) -> void:
	var rw := _W * 0.5 * _cabw
	var z0 := _zw(_cab0) + 0.12
	var z1 := _zw(_cab1) - 0.28
	var ry := _roof + 0.06
	for s in [-1.0, 1.0]:
		_box(root, Vector3(0.055, 0.055, z1 - z0), Vector3(s * rw * 0.90, ry, (z0 + z1) * 0.5), _trim_mat)
		for zz in [z0 + 0.05, z1 - 0.05]:
			_box(root, Vector3(0.05, 0.10, 0.05), Vector3(s * rw * 0.90, _roof + 0.01, zz), _trim_mat)
	for i in range(3):
		var zz := lerpf(z0 + 0.10, z1 - 0.10, float(i) / 2.0)
		_box(root, Vector3(rw * 1.86, 0.045, 0.05), Vector3(0, ry + 0.02, zz), _trim_mat)
	# spare wheel lying flat on the rack
	var sz := z1 - 0.30
	_cyl(root, _wr * 0.92, _ww * 0.72, Vector3(0, ry + _ww * 0.42, sz), _rub_mat, Vector3.ZERO, 26)
	_cyl(root, _wr * 0.52, _ww * 0.76, Vector3(0, ry + _ww * 0.42, sz), _trim_mat, Vector3.ZERO, 20)
	# roof light bar
	var lbz := _zw(_cab1) + 0.05
	_box(root, Vector3(rw * 1.42, 0.09, 0.10), Vector3(0, _roof + 0.15, lbz), _trim_mat)
	for s in [-1.0, 1.0]:
		_cyl(root, 0.072, 0.11, Vector3(s * rw * 0.44, _roof + 0.15, lbz + 0.05), _lamp_w, Vector3(90, 0, 0), 18)
	# bull bar
	var bz := _L * 0.5 + 0.055
	for s in [-1.0, 1.0]:
		_cyl(root, 0.032, 0.54, Vector3(s * _W * 0.33, _clr + 0.28, bz), _trim_mat, Vector3.ZERO, 12)
	_cyl(root, 0.032, _W * 0.76, Vector3(0, _clr + 0.50, bz), _trim_mat, Vector3(0, 0, 90), 12)
	_cyl(root, 0.032, _W * 0.76, Vector3(0, _clr + 0.22, bz), _trim_mat, Vector3(0, 0, 90), 12)
	for s in [-1.0, 1.0]:
		_cyl(root, 0.055, 0.09, Vector3(s * _W * 0.24, _clr + 0.36, bz + 0.05), _lamp_w, Vector3(90, 0, 0), 14)
	# rock sliders
	for s in [-1.0, 1.0]:
		_box(root, Vector3(0.075, 0.07, _L * 0.42), Vector3(s * (_W * 0.5 - 0.015), _clr + 0.035, 0), _trim_mat)
	# hood vents
	for s in [-1.0, 1.0]:
		_box(root, Vector3(0.24, 0.028, 0.17), Vector3(s * 0.27, _body_top(0.86) + 0.015, _zw(0.86)), _trim_mat)


func _hw_van(root: Node3D) -> void:
	# roof vent: a dark hatch with a painted lid, not a white brick
	var vz := _zw(0.30)
	_box(root, Vector3(0.46, 0.055, 0.56), Vector3(0, _roof + 0.012, vz), _flat(Color(0.30, 0.31, 0.33), 0.72))
	_box(root, Vector3(0.38, 0.035, 0.46), Vector3(0, _roof + 0.048, vz + 0.02), _roof_mat)
	# heavy front bumper
	_box(root, Vector3(_W * 0.90, 0.15, 0.12), Vector3(0, _clr + 0.10, _L * 0.5 + 0.03), _trim_mat)
	# side rub strips
	for s in [-1.0, 1.0]:
		_box(root, Vector3(0.02, 0.06, _L * 0.62), Vector3(s * (_body_hw(0.5) + 0.002), _belt - 0.26, 0), _trim_mat)
	# roof rails: only over the flat part of the roof, on short feet
	var rz0 := _zw(lerpf(_cab0, _cab1, 0.24))
	var rz1 := _zw(lerpf(_cab0, _cab1, 0.80))
	var rmid := (rz0 + rz1) * 0.5
	for s in [-1.0, 1.0]:
		_box(root, Vector3(0.05, 0.05, rz1 - rz0), Vector3(s * _W * 0.34, _roof + 0.055, rmid), _trim_mat)
		for zz in [rz0 + 0.08, rmid, rz1 - 0.08]:
			_box(root, Vector3(0.038, 0.065, 0.05), Vector3(s * _W * 0.34, _roof + 0.015, zz), _trim_mat)


func _hw_muscle(root: Node3D) -> void:
	# bonnet scoop
	var hz := _zw(0.82)
	_box(root, Vector3(0.44, 0.09, 0.56), Vector3(0, _body_top(0.82) + 0.04, hz), _roof_mat)
	_box(root, Vector3(0.38, 0.05, 0.10), Vector3(0, _body_top(0.82) + 0.09, hz + 0.26), _trim_mat)
	# rocker panels
	for s in [-1.0, 1.0]:
		_box(root, Vector3(0.06, 0.08, _L * 0.40), Vector3(s * (_W * 0.5 - 0.012), _clr + 0.04, 0), _trim_mat)
	# black rear panel
	_box(root, Vector3(_W * 0.78, 0.16, 0.03), Vector3(0, _tail - 0.10, -_L * 0.5 - 0.005), _trim_mat)


func _hw_pickup(root: Node3D) -> void:
	var z0 := _zw(0.045)
	var z1 := _zw(_cab0 - 0.035)
	var mid := (z0 + z1) * 0.5
	var wh := 0.26
	# bed side walls
	for s in [-1.0, 1.0]:
		_box(root, Vector3(0.085, wh, z1 - z0), Vector3(s * (_body_hw(0.2) - 0.085), _deck + wh * 0.5, mid), _paint_mat)
	# tailgate
	_box(root, Vector3(_W * 0.80, wh, 0.09), Vector3(0, _deck + wh * 0.5, z0), _paint_mat)
	# cargo
	_box(root, Vector3(0.52, 0.34, 0.50), Vector3(-0.20, _deck + 0.17, mid + 0.12), _flat(Color(0.46, 0.36, 0.24), 0.8))
	_box(root, Vector3(0.46, 0.05, 0.44), Vector3(-0.20, _deck + 0.36, mid + 0.12), _flat(Color(0.55, 0.44, 0.30), 0.8))
	_cyl(root, 0.15, 0.36, Vector3(0.34, _deck + 0.18, mid - 0.28), _flat(Color(0.28, 0.34, 0.40), 0.55, 0.4), Vector3.ZERO, 16)
	# bed rail caps
	for s in [-1.0, 1.0]:
		_box(root, Vector3(0.10, 0.03, z1 - z0), Vector3(s * (_body_hw(0.2) - 0.085), _deck + wh + 0.015, mid), _trim_mat)


func _hw_sport(root: Node3D) -> void:
	for s in [-1.0, 1.0]:
		_box(root, Vector3(0.06, 0.06, _L * 0.40), Vector3(s * (_W * 0.5 - 0.012), _clr + 0.03, 0), _trim_mat)
		_box(root, Vector3(0.20, 0.025, 0.15), Vector3(s * 0.44, _body_top(0.84) + 0.012, _zw(0.84)), _trim_mat)
	# rear vent panel
	_box(root, Vector3(_W * 0.66, 0.05, 0.10), Vector3(0, _tail - 0.05, -_L * 0.5 + 0.03), _trim_mat)


func _hw_ev(root: Node3D) -> void:
	# full-width light signature
	_box(root, Vector3(_W * 0.66, 0.035, 0.05), Vector3(0, _nose - 0.07, _L * 0.5 + 0.012), _lamp_w)
	_box(root, Vector3(_W * 0.74, 0.03, 0.04), Vector3(0, _tail - 0.06, -_L * 0.5 - 0.012), _lamp_r)
	# flush door handles
	for s in [-1.0, 1.0]:
		for t in [0.34, 0.62]:
			_box(root, Vector3(0.02, 0.035, 0.16), Vector3(s * (_body_hw(t) + 0.002), _belt - 0.16, _zw(t)), _chrome_mat)


func _hw_hyper(root: Node3D) -> void:
	# diffuser fins
	for i in range(5):
		var x := lerpf(-0.62, 0.62, float(i) / 4.0)
		_box(root, Vector3(0.03, 0.12, 0.28), Vector3(x, _clr + 0.09, -_L * 0.5 + 0.16), _trim_mat, Vector3(-14, 0, 0))
	# high twin exhausts
	for s in [-1.0, 1.0]:
		_cyl(root, 0.058, 0.12, Vector3(s * 0.26, _tail - 0.15, -_L * 0.5 - 0.02), _chrome_mat, Vector3(90, 0, 0), 16)
	# side intakes
	for s in [-1.0, 1.0]:
		_box(root, Vector3(0.03, 0.20, 0.46), Vector3(s * (_body_hw(0.30) + 0.002), _belt - 0.14, _zw(0.30)), _trim_mat)
	# engine cover louvres
	for i in range(3):
		_box(root, Vector3(0.62, 0.02, 0.07), Vector3(0, _deck + 0.008, _zw(0.16) - float(i) * 0.11), _trim_mat)
	# roof snorkel
	_box(root, Vector3(0.16, 0.06, 0.30), Vector3(0, _roof + 0.02, _zw(0.36)), _trim_mat)


# --- lights -----------------------------------------------------------------

func _build_lights(root: Node3D) -> void:
	var nz := _L * 0.5
	var tz := -_L * 0.5
	var gh := clampf(_nose - _clr - 0.22, 0.08, 0.26)
	_box(root, Vector3(_W * 0.54, gh, 0.06), Vector3(0, _clr + 0.11 + gh * 0.5, nz - 0.01), _trim_mat)
	var hy := _nose - 0.085
	if _sil == "hyper":
		for s in [-1.0, 1.0]:
			_box(root, Vector3(_W * 0.24, 0.045, 0.06), Vector3(s * _W * 0.28, hy + 0.02, nz + 0.01), _lamp_w, Vector3(0, s * -16.0, 0))
			_box(root, Vector3(_W * 0.14, 0.03, 0.05), Vector3(s * _W * 0.34, _clr + 0.20, nz + 0.005), _lamp_a, Vector3(0, s * -16.0, 0))
	else:
		for s in [-1.0, 1.0]:
			_box(root, Vector3(_W * 0.17, 0.07, 0.06), Vector3(s * _W * 0.295, hy, nz + 0.005), _lamp_w)
	if _sil != "ev":
		for s in [-1.0, 1.0]:
			_box(root, Vector3(_W * 0.24, 0.10, 0.05), Vector3(s * _W * 0.30, _tail - 0.10, tz - 0.005), _lamp_r)
	# front bumper lip
	_box(root, Vector3(_W * 0.86, 0.075, 0.07), Vector3(0, _clr + 0.055, nz + 0.015), _trim_mat)
	# rear plate
	_box(root, Vector3(0.30, 0.085, 0.02), Vector3(0, _clr + 0.19, tz - 0.008), _flat(Color(0.86, 0.87, 0.84), 0.6))
	if _sil in ["sport", "hyper", "muscle"]:
		for s in [-1.0, 1.0]:
			_cyl(root, 0.052, 0.10, Vector3(s * 0.30, _clr + 0.10, tz - 0.01), _chrome_mat, Vector3(90, 0, 0), 14)


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
