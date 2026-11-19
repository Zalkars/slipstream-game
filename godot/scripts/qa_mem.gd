extends SceneTree

# Throw-away memory probe: how much RAM/VRAM a full model cache costs.

const MODEL := preload("res://scripts/car_model.gd")
const CARS := preload("res://scripts/cars.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var m := MODEL.new()
	root.add_child(m)
	await process_frame
	var v0: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
	var s0: int = OS.get_static_memory_usage()
	print("[mem] start  vram %.1f MB  static %.1f MB" % [v0 / 1048576.0, s0 / 1048576.0])
	for i in range(CARS.LIST.size()):
		var c: Dictionary = CARS.get_car(i)
		m.show_car({
			"silhouette": c.silhouette,
			"color": c.color,
			"stripe": bool(c.stripe),
			"stripe_color": c.stripe_color,
		})
		await process_frame
		var v: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
		var s: int = OS.get_static_memory_usage()
		print("[mem] %-8s car %d  vram +%.1f MB total %.1f MB  static %.1f MB" % [
			str(c.silhouette), i, (v - v0) / 1048576.0, v / 1048576.0, s / 1048576.0])
	quit(0)
