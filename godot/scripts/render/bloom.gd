class_name Bloom
extends Node

# Restrained bloom. Only things that are actually light sources (lamps, stop
# lights, sparks, nitro flames) are painted into a small source buffer by their
# owners; nothing else on screen can bloom, so the threshold is "is it a lamp",
# not a brightness cut that would make a sunny road glow. The source buffer is
# blurred once at the same reduced resolution and added over the frame with a
# single bilinear tap per screen pixel.

const BLUR_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D src : filter_linear, repeat_disable;
uniform vec2 texel;
void fragment() {
	// 13-tap wide blur in one pass; at quarter/half resolution this is cheap
	// and wide enough that a lamp gets a soft halo instead of a hard disc.
	vec2 uv = UV;
	vec4 c = texture(src, uv) * 0.16;
	vec2 o1 = texel * 1.4;
	vec2 o2 = texel * 3.3;
	vec2 o3 = texel * 5.8;
	c += (texture(src, uv + vec2(o1.x, 0.0)) + texture(src, uv - vec2(o1.x, 0.0))
		+ texture(src, uv + vec2(0.0, o1.y)) + texture(src, uv - vec2(0.0, o1.y))) * 0.10;
	c += (texture(src, uv + o2 * vec2(0.7, 0.7)) + texture(src, uv + o2 * vec2(-0.7, 0.7))
		+ texture(src, uv + o2 * vec2(0.7, -0.7)) + texture(src, uv + o2 * vec2(-0.7, -0.7))) * 0.07;
	c += (texture(src, uv + vec2(o3.x, 0.0)) + texture(src, uv - vec2(o3.x, 0.0))
		+ texture(src, uv + vec2(0.0, o3.y)) + texture(src, uv - vec2(0.0, o3.y))) * 0.04;
	COLOR = c;
}
"""

var enabled := true
var src_vp: SubViewport
var blur_vp: SubViewport
var src_layer: DrawLayer
var blur_rect: ColorRect
var composite: TextureRect
var _blur_mat: ShaderMaterial
var _screen := Vector2(720, 1560)
var _scale := 0.25
var intensity := 1.0


# painter draws in SCREEN coordinates; the layer is scaled into the buffer.
func setup(screen: Vector2, post_scale: float, painter: Callable, overlay: CanvasLayer) -> void:
	_screen = screen
	if src_vp == null:
		src_vp = SubViewport.new()
		src_vp.name = "BloomSource"
		src_vp.transparent_bg = true
		src_vp.disable_3d = true
		src_vp.gui_disable_input = true
		src_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(src_vp)
		src_layer = DrawLayer.new("Sources", 0, painter)
		src_layer.material = DrawLayer.unshaded_material(CanvasItemMaterial.BLEND_MODE_ADD)
		src_vp.add_child(src_layer)
		# Created after the source so the RenderingServer draws it second.
		blur_vp = SubViewport.new()
		blur_vp.name = "BloomBlur"
		blur_vp.transparent_bg = true
		blur_vp.disable_3d = true
		blur_vp.gui_disable_input = true
		blur_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(blur_vp)
		blur_rect = ColorRect.new()
		var sh := Shader.new()
		sh.code = BLUR_SHADER
		_blur_mat = ShaderMaterial.new()
		_blur_mat.shader = sh
		_blur_mat.set_shader_parameter("src", src_vp.get_texture())
		blur_rect.material = _blur_mat
		blur_vp.add_child(blur_rect)
		composite = TextureRect.new()
		composite.name = "BloomComposite"
		composite.texture = blur_vp.get_texture()
		composite.stretch_mode = TextureRect.STRETCH_SCALE
		composite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		composite.material = DrawLayer.unshaded_material(CanvasItemMaterial.BLEND_MODE_ADD)
		overlay.add_child(composite)
	set_post_scale(post_scale)


func set_post_scale(s: float) -> void:
	_scale = clampf(s, 0.2, 1.0)
	# Bloom never needs more than half resolution: it is a blur.
	var bs := minf(_scale, 0.5)
	var size := Vector2i(maxi(16, int(_screen.x * bs)), maxi(16, int(_screen.y * bs)))
	if src_vp == null:
		return
	src_vp.size = size
	blur_vp.size = size
	blur_rect.position = Vector2.ZERO
	blur_rect.size = Vector2(size)
	src_layer.scale = Vector2(float(size.x) / _screen.x, float(size.y) / _screen.y)
	_blur_mat.set_shader_parameter("texel", Vector2(1.0 / float(size.x), 1.0 / float(size.y)))
	composite.position = Vector2.ZERO
	composite.size = _screen


func set_enabled(on: bool) -> void:
	enabled = on
	_active = on
	if src_vp == null:
		return
	var mode := SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	src_vp.render_target_update_mode = mode
	blur_vp.render_target_update_mode = mode
	composite.visible = on


# active = false when nothing on screen can bloom (a dry day with no stop
# lights or sparks): both buffer passes and the full-screen composite are
# skipped. They come back on the same frame a source appears.
var _active := true


func frame(screen: Vector2, active := true) -> void:
	if src_vp == null or not enabled:
		return
	if active != _active:
		_active = active
		var mode := SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
		src_vp.render_target_update_mode = mode
		blur_vp.render_target_update_mode = mode
		composite.visible = active
	if not active:
		return
	if screen != _screen:
		_screen = screen
		set_post_scale(_scale)
	composite.modulate = Color(intensity, intensity, intensity, 1.0)
	src_layer.queue_redraw()
