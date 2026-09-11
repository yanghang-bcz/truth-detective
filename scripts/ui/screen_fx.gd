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
	add_child(_motes())
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

## 空气里的浮尘。它的作用不是"好看"，而是让这页静止的界面每帧都和上一帧
## 有一点点不同 —— 完全没有变化的画面，眼睛会判定它是一张图，而不是一个场景。
## 26 颗，极慢，极淡，只在 20fps 上重画（不需要每帧）。
func _motes() -> Control:
	var m := Motes.new()
	m.name = "Motes"
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m


class Motes extends Control:
	var _bits: Array = []
	var _accum := 0.0

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 20260911          # 固定种子：每次运行都一样，方便截图回归对比
		for i in range(26):
			_bits.append({
				"x": rng.randf(),
				"y": rng.randf(),
				"r": rng.randf_range(0.7, 1.9),
				"v": rng.randf_range(0.004, 0.013),
				"phase": rng.randf() * TAU,
				"sway": rng.randf_range(0.003, 0.016),
			})
		set_process(true)

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_accum += delta
		if _accum < 0.05:
			return
		var step := _accum
		_accum = 0.0
		for b in _bits:
			b["y"] = float(b["y"]) - float(b["v"]) * step
			if float(b["y"]) < -0.04:
				b["y"] = 1.04
			b["phase"] = float(b["phase"]) + step * 0.5
		queue_redraw()

	func _draw() -> void:
		for b in _bits:
			var x: float = (float(b["x"]) + sin(float(b["phase"])) * float(b["sway"])) * size.x
			var y: float = float(b["y"]) * size.y
			# 暖色 —— 全场唯一的光源是顶上那盏台灯，浮尘也该是暖的。
			draw_circle(Vector2(x, y), float(b["r"]),
				Color(UIKit.LAMP.r, UIKit.LAMP.g, UIKit.LAMP.b, 0.16))


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
