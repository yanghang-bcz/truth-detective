class_name CasePhase
extends Control
## 四个界面阶段的共同骨架。
##
## 每个阶段都是一个完整的 Control，由 case_manager 负责挂载和卸载。
## 阶段之间不直接互相引用，只通过 finished(next) 这一个信号接力 ——
## 这样以后要插一个新阶段（比如调查中途的过场），只改 manager 的路由表就行。

signal finished(next: String)

var case: Dictionary = {}

func setup(data: Dictionary) -> void:
	case = data
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()

func _build() -> void:
	pass


# ─────────────────────────────────────────────────────────────
#  布局骨架
# ─────────────────────────────────────────────────────────────
## 居中的单栏正文。返回里面那个 VBox，往它里面塞内容即可。
## 一律走 ScrollContainer：这个界面在任何窗口尺寸下都不该出现被裁掉的内容。
func scroll_column(width: int = UIKit.WIDE) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	UIKit.style_scroll(scroll)
	add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(center)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(width, 0)
	col.add_theme_constant_override("separation", 0)
	center.add_child(col)
	return col

## 等宽三栏（调查板用）。
func three_columns(left_width: int, right_width: int) -> Array:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, UIKit.GUTTER)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", UIKit.COL_GAP)
	margin.add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(left_width, 0)
	left.add_theme_constant_override("separation", 12)
	columns.add_child(left)

	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 12)
	columns.add_child(middle)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(right_width, 0)
	right.add_theme_constant_override("separation", 14)
	columns.add_child(right)

	return [left, middle, right]


# ─────────────────────────────────────────────────────────────
#  共用组件
# ─────────────────────────────────────────────────────────────
## 章节标题：小号等宽大写 + 一条两端渐隐的分隔线。
func section(text: String, color: Color = UIKit.SLATE) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	box.add_child(UIKit.eyebrow(text, color))
	box.add_child(UIKit.rule(Color(UIKit.INK3.r, UIKit.INK3.g, UIKit.INK3.b, 0.9)))
	return box

## 置信度行：左边一行字，右边一个大号的百分比读数，下面一条滑条。
## 三个阶段共用同一套手感 —— 玩家学会一次就够。
## 返回 [控件, 取值函数]，取值函数在需要提交时调用。
func confidence_row(initial: int, on_change: Callable = Callable()) -> Array:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	var caption := UIKit.meta("confidence", 10, UIKit.SLATE, 2)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(caption)
	head.add_child(UIKit.fill(UIKit.hgap(0)))
	var readout := UIKit.label("%d%%" % initial, 22, UIKit.LAMP, UIKit.tracked(UIKit.font_mono(), 0))
	readout.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(readout)

	var slider := ConfidenceSlider.new()
	slider.value = initial
	box.add_child(slider)

	slider.changed.connect(func(v: int) -> void:
		readout.text = "%d%%" % v
		if on_change.is_valid():
			on_change.call(v))

	return [box, func() -> int: return slider.value]


## 让一栏内容自上而下依次浮现，像一份文件正在被摊开。
## 比"整屏淡入"多花不到半秒，但界面会显得是"被放置"的而不是"被打开"的。
## 注意：只动 modulate，不动位置 —— 位置归容器管，动画去抢位置一定会打架。
func stagger_fade(container: Container, step: float = 0.045, duration: float = 0.34) -> void:
	var children := container.get_children()
	for i in range(children.size()):
		var node := children[i]
		if not (node is Control):
			continue
		var child: Control = node
		child.modulate = Color(1, 1, 1, 0)
		var tween := create_tween()
		tween.tween_interval(float(i) * step)
		tween.tween_property(child, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_SINE)


## 一个不可交互的判定位（Debrief 里回显用）。
func verdict_pill(judgment: String, filled: bool = true) -> PanelContainer:
	var color := UIKit.judgment_color(judgment)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r, color.g, color.b, 0.16 if filled else 0.06)
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	sb.border_color = Color(color.r, color.g, color.b, 0.60 if filled else 0.30)
	sb.content_margin_left = 11
	sb.content_margin_right = 11
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(UIKit.meta(UIKit.judgment_label(judgment), 10, color.lightened(0.20), 1))
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return p


## 一条带状态的横向计量条（Debrief 的推理模式用）。
func meter(fraction: float, color: Color) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 6)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rail := ColorRect.new()
	rail.set_anchors_preset(Control.PRESET_FULL_RECT)
	rail.color = UIKit.INK3
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(rail)
	var fill_rect := ColorRect.new()
	fill_rect.anchor_left = 0.0
	fill_rect.anchor_top = 0.0
	fill_rect.anchor_bottom = 1.0
	fill_rect.anchor_right = clampf(fraction, 0.0, 1.0)
	fill_rect.offset_right = 0.0
	fill_rect.color = color
	fill_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(fill_rect)
	# 动画：条子长出来，而不是瞬间出现。
	fill_rect.anchor_right = 0.0
	var tween := create_tween()
	tween.tween_property(fill_rect, "anchor_right", clampf(fraction, 0.0, 1.0), 0.7)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return holder
