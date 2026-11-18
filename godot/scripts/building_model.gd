extends Node3D

# Metres, Y up. Facades, roofs and balconies are actual geometry; floor rows
# run up the walls, never across the ground plane.
var dimensions := Vector3.ZERO
var floors := 1
var _materials: Dictionary = {}


func _mat(hex: String) -> StandardMaterial3D:
	if _materials.has(hex):
		return _materials[hex]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(hex)
	material.roughness = 0.88
	_materials[hex] = material
	return material


func _box(center: Vector3, size: Vector3, color: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _mat(color)
	node.mesh = mesh
	node.position = center
	add_child(node)
	return node


func build(index: int) -> void:
	var apartment := index < 2
	floors = 5 if apartment else 1
	dimensions = [Vector3(12, 15, 26), Vector3(12, 15, 26), Vector3(9, 5.6, 12),
		Vector3(10, 4.2, 13), Vector3(10, 6, 16), Vector3(9, 4.4, 12)][index]
	var w := dimensions.x
	var h := dimensions.y
	var length := dimensions.z
	var wall: String = ["#c0bc9f", "#b99e87", "#d3c5a4", "#c2c8b3", "#aa775a", "#aaa995"][index]
	var roof: String = ["#778079", "#7c7f78", "#765044", "#818a82", "#57716b", "#777e72"][index]
	_box(Vector3(0, 0.16, 0), Vector3(w + 0.5, 0.32, length + 0.5), "#6f7167")
	_box(Vector3(0, h * 0.5, 0), Vector3(w, h, length), wall)
	# Plinth and cornice give the block a clearly readable base and top.
	_box(Vector3(0, 0.45, 0), Vector3(w + 0.12, 0.6, length + 0.12), "#858777")
	_box(Vector3(0, h - 0.18, 0), Vector3(w + 0.3, 0.28, length + 0.3), "#d0cdb6")
	for floor_index in range(floors):
		var y := 1.65 + floor_index * 2.85 if apartment else h * 0.54
		# Windows on both long sides, recessed panes behind raised stone frames.
		for side in [-1, 1]:
			var bays := 9 if apartment else 3
			for bay in range(bays):
				var z := -length * 0.5 + (bay + 0.5) * length / bays
				_box(Vector3(side * (w * 0.5 + 0.055), y, z), Vector3(0.13, 1.65, 1.65), "#ddd8bd")
				_box(Vector3(side * (w * 0.5 + 0.13), y, z), Vector3(0.05, 1.36, 1.35), "#395665")
				_box(Vector3(side * (w * 0.5 + 0.17), y, z), Vector3(0.07, 1.38, 0.065), "#a5b5af")
				_box(Vector3(side * (w * 0.5 + 0.17), y + 0.15, z), Vector3(0.07, 0.065, 1.35), "#a5b5af")
				_box(Vector3(side * (w * 0.5 + 0.19), y - 0.86, z), Vector3(0.3, 0.1, 1.85), "#a4a793")
				if apartment and floor_index > 0 and bay % 3 == 1:
					_balcony(side, w, y, z)
			# Windows on the end facades show five horizontal rows in the camera.
			for bay in range(3):
				var x := (bay - 1) * w * 0.27
				_box(Vector3(x, y, side * (length * 0.5 + 0.05)), Vector3(1.8, 1.65, 0.12), "#ddd8bd")
				_box(Vector3(x, y, side * (length * 0.5 + 0.13)), Vector3(1.5, 1.35, 0.05), "#3e6170")
				_box(Vector3(x, y, side * (length * 0.5 + 0.17)), Vector3(0.07, 1.36, 0.06), "#acb9af")
				_box(Vector3(x, y + 0.1, side * (length * 0.5 + 0.17)), Vector3(1.5, 0.07, 0.06), "#acb9af")
		if apartment:
			_box(Vector3(0, floor_index * 2.85 + 0.4, 0), Vector3(w + 0.05, 0.08, length + 0.05), "#a6a796")
	if index == 2 or index == 4:
		# Pitched roof: two sloping slabs meeting at the ridge.
		var pitch := deg_to_rad(25)
		var run := w * 0.5 + 0.55
		for side in [-1, 1]:
			var panel := _box(Vector3(side * run * 0.5, h + sin(pitch) * run * 0.5, 0),
				Vector3(run / cos(pitch), 0.2, length + 1.0), roof)
			panel.rotation.z = -side * pitch
		_box(Vector3(-2, h + 1.3, 2), Vector3(0.8, 2.5, 0.8), "#a18a70")
	else:
		_box(Vector3(0, h + 0.04, 0), Vector3(w, 0.16, length), roof)
		for side in [-1, 1]:
			_box(Vector3(side * w * 0.5, h + 0.3, 0), Vector3(0.22, 0.6, length + 0.2), "#b3b7a1")
			_box(Vector3(0, h + 0.3, side * length * 0.5), Vector3(w, 0.6, 0.22), "#b3b7a1")
		for z in [-length * 0.27, length * 0.26]:
			_box(Vector3(0.2, h + 0.6, z), Vector3(3, 1.1, 2.8), "#a5aa98")
			_box(Vector3(0.2, h + 1.21, z), Vector3(3.2, 0.12, 3), "#687a7b")
			_box(Vector3(-w * 0.3, h + 0.4, z + 2), Vector3(1.1, 0.8, 1.4), "#c0c1ad")
			for i in range(5):
				_box(Vector3(-w * 0.3, h + 0.82, z + 1.5 + i * 0.22), Vector3(0.85, 0.03, 0.06), "#4a5b56")
	# Ground-level entrances, concrete stairs and projecting canopies.
	for side in [-1, 1]:
		for z in ([-8.0, 0.0, 8.0] if apartment else [0.0]):
			_box(Vector3(side * (w * 0.5 + 0.1), 1.0, z), Vector3(0.2, 2, 1.4), "#43564e")
			_box(Vector3(side * (w * 0.5 + 0.7), 2.35, z), Vector3(1.8, 0.18, 2.4), "#b8bba5")
			_box(Vector3(side * (w * 0.5 + 0.7), 0.15, z), Vector3(1.8, 0.3, 2.3), "#a3a491")
	if index == 3:
		for side in [-1, 1]:
			for i in range(8):
				_box(Vector3(side * (w * 0.5 + 0.7), 2.9, -4.4 + i * 1.1), Vector3(1.8, 0.16, 1.1), "#b3604a" if i % 2 == 0 else "#e0d8ba")
	if index >= 4:
		_box(Vector3(0, 1.4, -length * 0.5 - 0.12), Vector3(w * 0.68, 2.8, 0.25), "#6b7c76")
		for i in range(7):
			_box(Vector3(0, 0.3 + i * 0.37, -length * 0.5 - 0.27), Vector3(w * 0.65, 0.04, 0.04), "#a7b0a0")


func _balcony(side: int, width: float, y: float, z: float) -> void:
	var x := side * (width * 0.5 + 0.6)
	_box(Vector3(x, y - 0.95, z), Vector3(1.45, 0.18, 2.25), "#bfc1ab")
	_box(Vector3(side * (width * 0.5 + 1.25), y - 0.4, z), Vector3(0.09, 0.95, 2.2), "#939e93")
	for end in [-1, 1]:
		_box(Vector3(x, y - 0.4, z + end * 1.08), Vector3(1.4, 0.95, 0.08), "#a1aa9a")
