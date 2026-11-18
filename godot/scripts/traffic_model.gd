extends RefCounted

# Commercial bodies use the same rounded lofts, materials and detailed wheels
# as the garage cars. +Z is forward; dimensions and axle positions are metres.
static func build(m, root: Node3D, silhouette: String) -> void:
	m._stripe_root = Node3D.new()
	root.add_child(m._stripe_root)
	m._cargo_mat = m._paint(Color("#d9dad6"))
	m._accent_mat = m._paint(Color("#d64a3a"))
	if silhouette == "truck":
		_truck(m, root)
	else:
		_bus(m, root)


static func _truck(m, root: Node3D) -> void:
	# Rigid delivery truck: a cab-over chassis, separate aluminium box body,
	# twin rear axles, roll-up rear doors and a roof air deflector.
	m._rbox(root, Vector3(1.65, 0.25, 6.35), Vector3(0, 0.64, -0.12), m._gap_mat)
	m._wz_f = 2.40
	m._wz_r = -1.72
	var rings: Array = []
	for i in range(51):
		var z := lerpf(1.22, 3.55, float(i) / 50.0)
		var d := absf(z - 2.40)
		var bottom := 0.48
		if d < 0.52:
			bottom = maxf(bottom, 0.46 + sqrt(0.52 * 0.52 - d * d))
		var top := 2.65 - maxf(0.0, z - 3.15) * 0.35
		rings.append(m._sec(1.10, 1.01, bottom, top, 0.07, 0.13, z))
	m._loft(root, rings, m._paint_mat, true, true)
	# Cargo sits above the rear tyres, leaving actual clearance to the chassis.
	m._rbox(root, Vector3(2.30, 2.10, 4.63), Vector3(0, 2.07, -1.20), m._cargo_mat, Vector3.ZERO, 0.055)
	m._rbox(root, Vector3(2.36, 0.075, 4.70), Vector3(0, 3.14, -1.20), m._chrome_mat)
	# Pressed roof ribs and gutters remain visible from the chase camera.
	for x: float in [-0.84, -0.42, 0.0, 0.42, 0.84]:
		m._rbox(root, Vector3(0.055, 0.035, 4.28), Vector3(x, 3.185, -1.20), m._cargo_mat, Vector3.ZERO, 0.015)
	for side: float in [-1.0, 1.0]:
		m._box(root, Vector3(0.035, 0.045, 4.41), Vector3(side * 1.11, 3.18, -1.20), m._rim_mat)
	for side: float in [-1.0, 1.0]:
		# Window seals and inset side glass, door handle, step, mirror stalk.
		m._rbox(root, Vector3(0.025, 0.81, 1.50), Vector3(side * 1.095, 2.03, 2.39), m._seal_mat)
		_glass_box(m, root, Vector3(0.030, 0.70, 1.37), Vector3(side * 1.11, 2.04, 2.39))
		m._box(root, Vector3(0.035, 0.68, 0.045), Vector3(side * 1.13, 2.04, 2.77), m._trim_mat)
		m._box(root, Vector3(0.035, 0.055, 0.23), Vector3(side * 1.12, 1.46, 1.68), m._chrome_mat)
		m._box(root, Vector3(0.018, 0.82, 0.018), Vector3(side * 1.11, 1.10, 1.55), m._gap_mat)
		m._box(root, Vector3(0.018, 0.018, 0.52), Vector3(side * 1.11, 0.72, 1.82), m._gap_mat)
		m._rbox(root, Vector3(0.24, 0.10, 0.66), Vector3(side * 1.09, 0.46, 1.47), m._rim_dark)
		m._box(root, Vector3(0.29, 0.045, 0.045), Vector3(side * 1.19, 1.94, 3.13), m._trim_mat)
		m._rbox(root, Vector3(0.15, 0.39, 0.21), Vector3(side * 1.34, 2.02, 3.12), m._trim_mat)
		m._box(root, Vector3(0.02, 0.28, 0.15), Vector3(side * 1.423, 2.03, 3.11), m._lens)
		# Cargo rub rail, fine panel ribs and amber side markers.
		m._box(root, Vector3(0.04, 0.10, 4.50), Vector3(side * 1.16, 1.12, -1.20), m._rim_mat)
		for z: float in [-3.30, -2.50, -1.70, -0.90, -0.10, 0.82]:
			m._box(root, Vector3(0.018, 1.90, 0.024), Vector3(side * 1.155, 2.08, z), m._rim_mat)
			m._box(root, Vector3(0.035, 0.07, 0.13), Vector3(side * 1.18, 1.21, z), m._lamp_a)
		for z: float in [2.40, -1.72, -2.78]:
			m._wheel(root, side, z)
			if z < 0:
				m._box(root, Vector3(0.32, 0.39, 0.045), Vector3(side * 1.0, 0.35, z - 0.49), m._rub_mat)
	# Glazing sits outside the cab's front cap across its full height.
	m._rbox(root, Vector3(1.94, 0.77, 0.045), Vector3(0, 2.02, 3.58), m._seal_mat)
	_glass_box(m, root, Vector3(1.82, 0.65, 0.050), Vector3(0, 2.03, 3.61))
	m._commercial_wipers(root, 3.63, 1.74, 0.86)
	m._rbox(root, Vector3(2.12, 0.28, 0.20), Vector3(0, 0.70, 3.53), m._trim_mat)
	m._rbox(root, Vector3(1.20, 0.42, 0.055), Vector3(0, 1.16, 3.56), m._gap_mat)
	for y: float in [1.02, 1.13, 1.24, 1.35]:
		m._box(root, Vector3(1.12, 0.025, 0.02), Vector3(0, y, 3.60), m._rim_mat)
	m._rbox(root, Vector3(1.94, 0.24, 1.30), Vector3(0, 2.80, 1.95), m._roof_mat, Vector3(-12, 0, 0), 0.10)
	# Rear double doors with hinges and locking rods.
	for side: float in [-1.0, 1.0]:
		m._box(root, Vector3(1.04, 1.89, 0.035), Vector3(side * 0.55, 2.07, -3.54), m._cargo_mat)
		m._box(root, Vector3(0.028, 1.65, 0.03), Vector3(side * 0.32, 2.07, -3.57), m._chrome_mat)
		for y: float in [1.40, 2.05, 2.72]:
			m._box(root, Vector3(0.17, 0.065, 0.045), Vector3(side * 1.01, y, -3.58), m._rim_mat)
	m._box(root, Vector3(0.025, 1.96, 0.04), Vector3(0, 2.07, -3.57), m._trim_mat)
	for i in range(9):
		m._box(root, Vector3(0.20, 0.065, 0.045), Vector3(-0.92 + i * 0.23, 1.14, -3.58), m._lamp_r if i % 2 == 0 else m._lens)
	for x: float in [-0.84, -0.42, 0, 0.42, 0.84]:
		m._rbox(root, Vector3(0.10, 0.055, 0.10), Vector3(x, 2.68, 3.02), m._lamp_a)
	m._box(root, Vector3(2.24, 0.12, 0.16), Vector3(0, 0.61, -3.53), m._rim_mat)
	_lamps(m, root, 3.64, -3.60, 0.86, 0.83)


static func _bus(m, root: Node3D) -> void:
	m._wz_f = 2.85
	m._wz_r = -2.55
	# A continuous body with wheel openings rather than wheels hidden by a box.
	var rings: Array = []
	for i in range(151):
		var z := lerpf(-4.50, 4.50, float(i) / 150.0)
		var bottom := 0.37
		for axle: float in [2.85, -2.55]:
			var d := absf(z - axle)
			if d < 0.53:
				bottom = maxf(bottom, 0.46 + sqrt(0.53 * 0.53 - d * d))
		var end := clampf((absf(z) - 4.18) / 0.32, 0, 1)
		rings.append(m._sec(1.20 - end * 0.09, 1.13 - end * 0.08, bottom, 2.95 - end * 0.07, 0.07, 0.15, z))
	m._loft(root, rings, m._paint_mat, true, true)
	m._box(root, Vector3(1.80, 0.18, 7.95), Vector3(0, 0.47, 0), m._gap_mat)
	for side: float in [-1.0, 1.0]:
		# Dark continuous glazing band, separated panes and rubber pillars.
		m._box(root, Vector3(0.035, 1.06, 8.04), Vector3(side * 1.177, 2.13, 0), m._seal_mat)
		for i in range(8):
			var z := -3.49 + float(i) * 0.99
			_glass_box(m, root, Vector3(0.04, 0.91, 0.88), Vector3(side * 1.202, 2.14, z), Vector3.ZERO, 0.045)
			m._box(root, Vector3(0.018, 0.025, 0.84), Vector3(side * 1.228, 2.38, z), m._rim_dark)
		m._box(root, Vector3(0.035, 0.17, 8.13), Vector3(side * 1.21, 1.49, 0), m._accent_mat)
		m._box(root, Vector3(0.045, 0.075, 8.12), Vector3(side * 1.21, 1.34, 0), m._rim_mat)
		# Luggage/service hatch seams below the belt, kept above wheel arches.
		for z: float in [-1.70, -0.60, 0.50, 1.60]:
			m._box(root, Vector3(0.018, 0.62, 0.015), Vector3(side * 1.21, 0.93, z), m._trim_mat)
			m._box(root, Vector3(0.025, 0.035, 0.15), Vector3(side * 1.225, 1.14, z + 0.25), m._rim_mat)
		for z: float in [-4.08, -1.10, 1.20, 4.08]:
			m._box(root, Vector3(0.04, 0.065, 0.12), Vector3(side * 1.23, 1.20, z), m._lamp_a)
		for axle: float in [2.85, -2.55]:
			m._wheel(root, side, axle)
		# Extended coach mirrors.
		m._box(root, Vector3(0.32, 0.05, 0.06), Vector3(side * 1.24, 2.52, 4.05), m._trim_mat)
		m._rbox(root, Vector3(0.17, 0.42, 0.21), Vector3(side * 1.41, 2.35, 4.05), m._trim_mat)
	# Boarding doors on the right; a second inset glass layer reads as two leaves.
	for z: float in [3.54, -0.65]:
		m._box(root, Vector3(0.05, 1.88, 0.94), Vector3(1.24, 1.48, z), m._trim_mat)
		for leaf: float in [-1.0, 1.0]:
			_glass_box(m, root, Vector3(0.025, 1.62, 0.40), Vector3(1.275, 1.53, z + leaf * 0.23))
		m._box(root, Vector3(0.10, 0.07, 0.91), Vector3(1.24, 0.52, z), m._rim_mat)
	# Panoramic windshield, destination display, separate rear glass.
	for z: float in [-4.49, 4.49]:
		m._rbox(root, Vector3(2.05, 1.10, 0.045), Vector3(0, 2.10, z), m._seal_mat, Vector3.ZERO, 0.09)
		_glass_box(m, root, Vector3(1.91, 0.96, 0.055), Vector3(0, 2.11, z * 1.004), Vector3.ZERO, 0.075)
		m._rbox(root, Vector3(2.16, 0.20, 0.14), Vector3(0, 0.55, z), m._trim_mat)
	m._box(root, Vector3(1.22, 0.19, 0.055), Vector3(0, 2.74, 4.48), m._gap_mat)
	for i in range(7):
		m._box(root, Vector3(0.09, 0.065, 0.02), Vector3(-0.43 + i * 0.14, 2.74, 4.52), m._lamp_a)
	m._commercial_wipers(root, 4.53, 1.70, 0.88)
	for y: float in [0.85, 0.96, 1.07, 1.18]:
		m._box(root, Vector3(1.15, 0.035, 0.035), Vector3(0, y, -4.52), m._gap_mat)
	m._box(root, Vector3(2.04, 0.13, 0.045), Vector3(0, 1.43, -4.54), m._accent_mat)
	# Roof HVAC pod, intake slats and two framed emergency hatches.
	m._rbox(root, Vector3(1.65, 0.23, 1.66), Vector3(0, 3.055, -0.85), m._cargo_mat, Vector3.ZERO, 0.09)
	for x: float in [-0.41, 0.41]:
		m._cyl(root, 0.31, 0.025, Vector3(x, 3.185, -0.85), m._rim_dark, Vector3.ZERO, 32)
		for blade in range(7):
			m._box(root, Vector3(0.045, 0.018, 0.49), Vector3(x, 3.207, -0.85), m._rim_mat, Vector3(0, blade * 180.0 / 7.0, 0))
		m._cyl(root, 0.075, 0.025, Vector3(x, 3.22, -0.85), m._trim_mat)
	for z: float in [-1.46, -1.33, -0.36, -0.23]:
		m._box(root, Vector3(1.32, 0.016, 0.04), Vector3(0, 3.18, z), m._trim_mat)
	for z: float in [-3.13, 2.05]:
		m._rbox(root, Vector3(0.89, 0.045, 0.82), Vector3(0, 2.97, z), m._seal_mat)
		m._rbox(root, Vector3(0.78, 0.045, 0.71), Vector3(0, 3.005, z), m._lens)
	_lamps(m, root, 4.56, -4.56, 0.91, 0.96)


# Match the passenger cars' tinted glass. Vertex colours give a broad sky
# reflection without transparency sorting, extra lights or reflection probes.
static func _glass_box(m, root: Node3D, size: Vector3, pos: Vector3,
		rot := Vector3.ZERO, radius := 0.03) -> void:
	var panel: MeshInstance3D = m._rbox(root, size, pos, m._glass_mat, rot, radius)
	var shaded := ArrayMesh.new()
	for surface in range(panel.mesh.get_surface_count()):
		var arrays: Array = panel.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colours := PackedColorArray()
		var uvs := PackedVector2Array()
		for vertex in vertices:
			var height := clampf(vertex.y / size.y + 0.5, 0.0, 1.0)
			colours.append(Color(0.20, 0.29, 0.42).lerp(Color(0.82, 0.92, 1.0), height))
			var horizontal := vertex.x / size.x if size.z < size.x else vertex.z / size.z
			uvs.append(Vector2(horizontal + 0.5, height))
		arrays[Mesh.ARRAY_COLOR] = colours
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		shaded.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	panel.mesh = shaded


static func _lamps(m, root: Node3D, front: float, rear: float, x: float, y: float) -> void:
	for side: float in [-1.0, 1.0]:
		m._rbox(root, Vector3(0.35, 0.22, 0.065), Vector3(side * x, y, front), m._seal_mat)
		m._rbox(root, Vector3(0.25, 0.13, 0.075), Vector3(side * x, y + 0.02, front + 0.025), m._lamp_w)
		m._box(root, Vector3(0.10, 0.06, 0.075), Vector3(side * (x + 0.10), y - 0.09, front + 0.02), m._lamp_a)
		m._rbox(root, Vector3(0.23, 0.26, 0.075), Vector3(side * x, y, rear), m._seal_mat)
		m._box(root, Vector3(0.16, 0.10, 0.085), Vector3(side * x, y + 0.05, rear - 0.015), m._lamp_r)
		m._box(root, Vector3(0.16, 0.065, 0.085), Vector3(side * x, y - 0.06, rear - 0.015), m._lamp_a)
	for z: float in [front + 0.01, rear - 0.02]:
		m._box(root, Vector3(0.40, 0.12, 0.035), Vector3(0, y - 0.15, z), m._seal_mat)
		m._box(root, Vector3(0.32, 0.075, 0.045), Vector3(0, y - 0.15, z), m._lamp_w)
