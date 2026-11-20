class_name DrawLayer
extends Node2D

# One canvas item of the frame. Render systems own the state and hand the layer
# a painter: the layer only decides WHERE in the frame (z, material, light mask)
# the painter's draw calls land. Splitting the old monolithic Game._draw() into
# these layers is what lets lights, shadows and post effects hit only the parts
# of the frame they belong to.

var painter: Callable


func _init(p_name := "", p_z := 0, p_painter := Callable()) -> void:
	if p_name != "":
		name = p_name
	z_index = p_z
	painter = p_painter


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)


static func unshaded_material(blend := CanvasItemMaterial.BLEND_MODE_MIX) -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	m.blend_mode = blend
	return m
