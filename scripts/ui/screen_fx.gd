class_name ScreenFX
extends Control
## 铺在界面最上层的画面质感：暗角、颗粒、以及顶部那盏"暖灯"。
## 全部 mouse_filter = IGNORE，绝不拦截输入。

## 挂到某个 Control 上（通常是案件的根节点）。with_glow 控制顶部暖光，
## 街区里的提示层不需要它，那层要保持通透。
static func attach(parent: Control, with_glow: bool = true) -> ScreenFX:
	var fx := ScreenFX.new()
	fx.name = "ScreenFX"
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(fx)
	fx._build(with_glow)
	return fx

func _build(with_glow: bool) -> void:
	if with_glow:
		add_child(_lamp_glow())
	add_child(_tinted_rect("Vignette", "res://shaders/ui_vignette.gdshader"))
	add_child(_tinted_rect("Grain", "res://shaders/ui_grain.gdshader"))

## 顶部偏中偏左的一小片暖光，模拟画面外有一盏台灯。
## 这是整个界面里唯一"有光源"的地方，所有暖色元素都该和它方向一致。
func _lamp_glow() -> TextureRect:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 384
	tex.height = 384
	var rect := TextureRect.new()
	rect.name = "LampGlow"
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.modulate = Color(UIKit.LAMP.r, UIKit.LAMP.g, UIKit.LAMP.b, 0.085)
	rect.custom_minimum_size = Vector2(1200, 900)
	rect.anchor_left = 0.30
	rect.anchor_right = 0.30
	rect.anchor_top = -0.30
	rect.anchor_bottom = -0.30
	rect.offset_left = -600
	rect.offset_right = 600
	rect.offset_top = -300
	rect.offset_bottom = 600
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

func _tinted_rect(node_name: String, shader_path: String) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color.WHITE
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	rect.material = mat
	return rect
