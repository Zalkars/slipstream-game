extends Node

# Offline normal-map atlas builder (0.8.0). Renders every catalogued car with a
# view-space normal shader and writes cars_N_n.png with exactly the layout of
# the committed colour atlases (sprites.gd), so no colour page changes.
# Needs a graphical Compatibility renderer:
#   godot --path godot res://tests/BakeRaceNormals.tscn -- --bake-race-normals
const ART = preload("res://scripts/race_art.gd")
const PALETTE = preload("res://scripts/traffic_palette.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if not "--bake-race-normals" in OS.get_cmdline_user_args():
		push_error("Pass -- --bake-race-normals to regenerate the normal atlases")
		get_tree().quit(1)
		return
	var sprites = load(ART.SPRITES_PATH)
	var art := ART.new()
	add_child(art)
	art.set_process(false)
	await get_tree().process_frame
	var pages: Array = []
	for path: String in sprites.PAGES:
		var tex: Texture2D = load(path)
		var img := Image.create(tex.get_width(), tex.get_height(), false, Image.FORMAT_RGBA8)
		img.fill(Color(0.5, 0.5, 1.0, 0.0))
		pages.append(img)
	var variants: Array = []
	variants.append_array(Cars.LIST)
	for sil: String in PALETTE.SILHOUETTES:
		for colour_index in range(PALETTE.TRAFFIC_COLORS.size()):
			variants.append_array(PALETTE.variants(sil, colour_index))
	var done := {}
	for car: Dictionary in variants:
		var key: String = art._key(car)
		if done.has(key) or not sprites.ENTRIES.has(key):
			continue
		var e: Array = sprites.ENTRIES[key]
		var pair: Array = await art.render_pair(car)
		if pair.is_empty():
			push_error("Blank normal sprite: " + key)
			continue
		var nrm: Image = pair[1]
		var size := Vector2i(int(e[3]), int(e[4]))
		if nrm.get_size() != size:
			nrm.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
		pages[int(e[0])].blit_rect(nrm, Rect2i(Vector2i.ZERO, size), Vector2i(int(e[1]), int(e[2])))
		done[key] = true
		if done.size() % 64 == 0:
			print("[bake-normals] ", done.size(), "/", sprites.ENTRIES.size())
	for i in range(pages.size()):
		var path := ART.NORMAL_PAGE % i
		assert(pages[i].save_png(ProjectSettings.globalize_path(path)) == OK)
		if not FileAccess.file_exists(path + ".import"):
			var f := FileAccess.open(path + ".import", FileAccess.WRITE)
			# Normal maps must stay uncompressed-linear: lossy VRAM formats and
			# sRGB both bend the vectors.
			f.store_string('[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n\n[deps]\nsource_file="%s"\n\n[params]\ncompress/mode=0\ncompress/normal_map=1\nmipmaps/generate=true\nmipmaps/limit=2\nprocess/fix_alpha_border=false\n' % path)
			f.close()
	print("[bake-normals] Done: ", done.size(), " sprites, ", pages.size(), " pages")
	get_tree().quit()
