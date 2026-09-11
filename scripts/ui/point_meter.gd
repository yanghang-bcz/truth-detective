class_name PointMeter
extends Control
## 调查点仪表。10 个小格，用掉一格就灭一格 —— 这是案件里唯一真正稀缺的资源，
## 必须让玩家在点击之前就看见它在减少。
##
## 用连续的 _lit 而不是整数计数，是为了让"熄灭"有个极短的过渡而不是硬切换：
## 消耗资源这件事应该有触感。

var total: int = 10:
	set(v):
		total = maxi(v, 1)
		queue_redraw()

var remaining: int = 10:
	set(v):
		remaining = clampi(v, 0, total)
		queue_redraw()

const PIP_H := 6.0
const PIP_GAP := 3.0

var _lit := 10.0
var _tween: Tween

func _ready() -> void:
	custom_minimum_size = Vector2(0, PIP_H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lit = float(remaining)
	resized.connect(queue_redraw)

## animate = true 时，熄灭的过程有 0.35 秒的过渡。
func set_remaining(v: int, animate: bool = true) -> void:
	var target := clampi(v, 0, total)
	var from := _lit
	remaining = target
	if not animate:
		_lit = float(target)
		queue_redraw()
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_lit, from, float(target), 0.35)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _set_lit(v: float) -> void:
	_lit = v
	queue_redraw()

func _draw() -> void:
	if total <= 0:
		return
	var w := (size.x - PIP_GAP * float(total - 1)) / float(total)
	if w <= 0.0:
		return
	var spent := UIKit.INK3.darkened(0.35)
	for i in range(total):
		var t := clampf(_lit - float(i), 0.0, 1.0)
		var col := spent.lerp(UIKit.LAMP, t)
		if t <= 0.001:
			col = spent
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(2)
		sb.anti_aliasing = true
		if t > 0.99 and i == int(ceil(_lit)) - 1:
			sb.shadow_color = Color(UIKit.LAMP.r, UIKit.LAMP.g, UIKit.LAMP.b, 0.35)
			sb.shadow_size = 7
		draw_style_box(sb, Rect2(float(i) * (w + PIP_GAP), (size.y - PIP_H) * 0.5, w, PIP_H))
