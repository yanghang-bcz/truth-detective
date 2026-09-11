class_name Curtain
extends Control
## 全屏淡入淡出。街区 ↔ 案件之间那一层黑。
## 比换场景（change_scene_to_file）轻得多：案件界面是叠在 3D 之上的，
## 街区不卸载，回来时是瞬时的，也没有重新加载 1 秒的顿挫。

signal covered  ## 已经完全遮黑
signal cleared  ## 已经完全透明，输入不再被拦截

var _rect: ColorRect
var _tween: Tween

static func attach(parent: Control) -> Curtain:
	var c := Curtain.new()
	c.name = "Curtain"
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	c._rect = ColorRect.new()
	c._rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	c._rect.color = Color(UIKit.INK0.r, UIKit.INK0.g, UIKit.INK0.b, 0.0)
	c._rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(c._rect)
	return c

## 变黑。遮黑后发射 covered。
func fade_out(duration: float = 0.4) -> void:
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_run(1.0, duration, func(): covered.emit())

## 变亮。
func fade_in(duration: float = 0.4) -> void:
	_run(0.0, duration, func():
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cleared.emit())

func is_opaque() -> bool:
	return _rect.color.a > 0.9

func _run(target_alpha: float, duration: float, on_done: Callable) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", target_alpha, duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(on_done)
