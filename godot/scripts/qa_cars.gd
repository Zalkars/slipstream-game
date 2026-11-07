extends SceneTree

# Temporary review sheet: every car in the garage stage, one frame each.

const W := 616
const H := 600
const COLS := 3


class Stage extends SubViewport:
	var stage: CarStage

	func _init(car_index: int) -> void:
		size = Vector2i(W, H)
		transparent_bg = false
		render_target_update_mode = SubViewport.UPDATE_ALWAYS
		gui_disable_input = true
		stage = CarStage.new()
		stage.car = Cars.get_car(car_index)
		stage.size = Vector2(W, H)
		add_child(stage)
		stage.set_process(false)
		stage.set_time(1.7)


func _initialize() -> void:
	call_deferred("_run")


func _capture(vp: Viewport) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _run() -> void:
	var count := Cars.LIST.size()
	var rows := int(ceil(float(count) / float(COLS)))
	var sheet := Image.create(W * COLS, H * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.04, 0.05, 0.06, 1.0))
	for i in range(count):
		var vp := Stage.new(i)
		root.add_child(vp)
		await process_frame
		var img := await _capture(vp)
		var x := (i % COLS) * W
		var y := int(i / COLS) * H
		sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i(x, y))
		vp.queue_free()
	var path := ProjectSettings.globalize_path("res://shots/qa_cars.png")
	sheet.save_png(path)
	print("[qa] wrote ", path, " ", sheet.get_size())
	quit(0)
