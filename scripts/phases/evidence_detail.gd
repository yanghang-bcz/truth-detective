class_name EvidenceDetail
extends Control
## 一张证据卡打开之后的样子。
##
## 这是整个游戏里最像"翻档案"的地方，所以它长得最像纸：顶部一条深色标签条
## （编号和标题是从档案盒侧面看到的那一行），下面全是纸面。
##
## 卡片的正文只讲事实，真正教东西的是后面两栏：
## "这份材料能立住什么" / "这份材料立不住什么"。这两个小标题是本案的论点，
## 所以它们被排在正文之后、玩家自己的分类之前 —— 先看工具怎么用，再自己用一次。

signal closed
signal classified(evidence_id: String, relevance: String, kind: String)

const PANEL_W := 960
const BODY_H := 500

var evidence: Dictionary = {}
var _relevance := ""
var _kind := ""
var _groups := {}

static func open(parent: Control, data: Dictionary, evidence_id: String) -> EvidenceDetail:
	var d := EvidenceDetail.new()
	d.evidence = CaseData.evidence(data, evidence_id)
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(d)
	d._build()
	return d

func _build() -> void:
	var stored := CaseState.classification_of(str(evidence.get("id", "")))
	_relevance = str(stored.get("relevance", ""))
	_kind = str(stored.get("kind", ""))

	# 背板。点它可以关掉 —— 但要比点别处更费力一点，所以整块都可点。
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.012, 0.020, 0.027, 0.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(backdrop)
	var fade := create_tween()
	fade.tween_property(backdrop, "color:a", 0.78, 0.18)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var paper := UIKit.paper_panel(0)
	paper.custom_minimum_size = Vector2(PANEL_W, 0)
	paper.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(paper)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	paper.add_child(col)

	col.add_child(_masthead())

	var body_margin := MarginContainer.new()
	for side in ["left", "right"]:
		body_margin.add_theme_constant_override("margin_" + side, 34)
	body_margin.add_theme_constant_override("margin_top", 26)
	body_margin.add_theme_constant_override("margin_bottom", 26)
	col.add_child(body_margin)

	var body_scroll := ScrollContainer.new()
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.custom_minimum_size = Vector2(0, BODY_H)
	UIKit.style_scroll(body_scroll, true)
	body_margin.add_child(body_scroll)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(body)

	body.add_child(UIKit.paragraph(str(evidence.get("summary", "")), 17, UIKit.PAPER_INK))
	body.add_child(UIKit.gap(18))
	body.add_child(_readout())
	body.add_child(UIKit.gap(20))
	for line in evidence.get("body", []):
		body.add_child(UIKit.paragraph(str(line), 15, UIKit.PAPER_INK))
		body.add_child(UIKit.gap(12))

	body.add_child(UIKit.gap(10))
	body.add_child(_list_block("What this establishes", evidence.get("proves", []), UIKit.PAPER_PROVES))
	body.add_child(UIKit.gap(16))
	body.add_child(_list_block("What this does not establish", evidence.get("does_not_prove", []), UIKit.PAPER_DOES_NOT))

	body.add_child(UIKit.gap(22))
	body.add_child(_hook())
	body.add_child(UIKit.gap(20))

	# "YOUR READING" 钉在卡片底部，不进滚动区。它是这张卡上唯一需要玩家动手
	# 的部分 —— 把它压在折叠线以下，玩家很容易看完材料就按 File It 走了。
	col.add_child(_classification())
	col.add_child(_footer())

	# 面板本身的上浮。位置归 CenterContainer 管，所以只做位移入场是不行的，
	# 用透明度 + 轻微缩放来做"落下来"的感觉。
	paper.pivot_offset = Vector2(PANEL_W * 0.5, 0)
	paper.modulate = Color(1, 1, 1, 0)
	paper.scale = Vector2(0.985, 0.985)
	var rise := create_tween().set_parallel(true)
	rise.tween_property(paper, "modulate:a", 1.0, 0.20).set_trans(Tween.TRANS_SINE)
	rise.tween_property(paper, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)

## 档案盒侧面那一条：编号在左，标题在右。
func _masthead() -> Control:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIKit.PAPER_INK
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	bar.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	bar.add_child(row)

	var id_label := UIKit.label(str(evidence.get("id", "")), 22, UIKit.LAMP, UIKit.tracked(UIKit.font_mono(), 2))
	id_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(id_label)

	var divider := ColorRect.new()
	divider.color = Color(UIKit.PAPER.r, UIKit.PAPER.g, UIKit.PAPER.b, 0.18)
	divider.custom_minimum_size = Vector2(1, 26)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(divider)

	var title := UIKit.label(str(evidence.get("title", "")), 21, UIKit.PAPER, UIKit.font_display())
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	var source: Dictionary = CaseData.source_of(CaseState.data, str(evidence.get("id", "")))
	var src := UIKit.meta(str(source.get("label", "")), 10, Color(UIKit.PAPER.r, UIKit.PAPER.g, UIKit.PAPER.b, 0.45), 2)
	src.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(src)
	return bar

## 四项读数。用等宽体排成四列，像盖在文件上的四个章。
func _readout() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	var entries := [
		["TYPE", str(evidence.get("type", ""))],
		["RELIABILITY", str(evidence.get("reliability", ""))],
		["CONTEXT", str(evidence.get("context", ""))],
		["COST", "%d IP" % int(evidence.get("cost", 1))],
	]
	for pair in entries:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		cell.add_child(UIKit.meta(pair[0], 9, Color(UIKit.PAPER_INK_SOFT.r, UIKit.PAPER_INK_SOFT.g, UIKit.PAPER_INK_SOFT.b, 0.75), 2))
		cell.add_child(UIKit.label(pair[1], 13, UIKit.PAPER_INK, UIKit.font_ui()))
		row.add_child(cell)
	return row

func _list_block(title: String, items: Array, color: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(UIKit.meta(title, 10, color, 2))
	for item in items:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var mark := ColorRect.new()
		mark.color = color
		mark.custom_minimum_size = Vector2(6, 6)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mark_holder := CenterContainer.new()
		mark_holder.custom_minimum_size = Vector2(6, 18)
		mark_holder.add_child(mark)
		line.add_child(mark_holder)
		var text := UIKit.paragraph(str(item), 14, UIKit.PAPER_INK)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		box.add_child(line)
	return box

## 卡片末尾那句"注意这里"。斜体衬线，左边一道细线 —— 它是这份文件里
## 唯一一个"有人在跟你说话"的声音，所以它必须和上面的事实性条文长得不一样。
func _hook() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var bar := ColorRect.new()
	bar.color = UIKit.LAMP_DIM
	bar.custom_minimum_size = Vector2(2, 0)
	bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	var text := UIKit.quote(str(evidence.get("hook", "")), 18, UIKit.PAPER_INK_SOFT)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	return row

# ─────────────────────────────────────────────────────────────
#  玩家自己的两问分类
# ─────────────────────────────────────────────────────────────
func _classification() -> Control:
	# 和页脚连成一条"底部控制台"：上面是材料，下面是玩家要做的事。
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIKit.PAPER_SOFT
	sb.border_width_top = 1
	sb.border_color = UIKit.PAPER_EDGE
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 14
	sb.content_margin_bottom = 16
	bar.add_theme_stylebox_override("panel", sb)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 11)
	bar.add_child(box)
	box.add_child(UIKit.meta("your reading", 10, Color(UIKit.PAPER_INK_SOFT.r, UIKit.PAPER_INK_SOFT.g, UIKit.PAPER_INK_SOFT.b, 0.9), 3))

	# 两问并排。竖着排会把第二问推到折叠线以下，而两问都是非答不可的。
	var spec: Dictionary = CaseState.data.get("classification", {})
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 26)
	box.add_child(cols)
	var relevance := _choice_row("relevance", "How relevant is this?", spec.get("relevance", []), _relevance)
	relevance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(relevance)
	var kind := _choice_row("kind", "What kind of information is this?", spec.get("kind", []), _kind)
	kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(kind)
	return bar

func _choice_row(group: String, prompt: String, options: Array, current: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.add_child(UIKit.label(prompt, 13, UIKit.PAPER_INK, UIKit.font_ui()))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var button_group := ButtonGroup.new()
	for option in options:
		var b := _paper_chip(str(option))
		b.button_group = button_group
		b.button_pressed = (str(option) == current)
		b.pressed.connect(_on_choice.bind(group, str(option)))
		row.add_child(b)
	box.add_child(row)
	_groups[group] = row
	return box

func _on_choice(group: String, value: String) -> void:
	if group == "relevance":
		_relevance = value
	else:
		_kind = value
	classified.emit(str(evidence.get("id", "")), _relevance, _kind)

func _paper_chip(text: String) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.toggle_mode = true
	b.add_theme_font_override("font", UIKit.tracked(UIKit.font_mono(), 1))
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_color_override("font_color", UIKit.PAPER_INK_SOFT)
	b.add_theme_color_override("font_hover_color", UIKit.PAPER_INK)
	b.add_theme_color_override("font_pressed_color", UIKit.PAPER)
	b.add_theme_color_override("font_hover_pressed_color", UIKit.PAPER)
	b.add_theme_color_override("font_focus_color", UIKit.PAPER_INK_SOFT)
	b.add_theme_stylebox_override("normal", _chip_box(Color(0, 0, 0, 0), UIKit.PAPER_EDGE))
	b.add_theme_stylebox_override("hover", _chip_box(UIKit.PAPER_SOFT, UIKit.PAPER_INK_SOFT))
	b.add_theme_stylebox_override("pressed", _chip_box(UIKit.PAPER_INK, UIKit.PAPER_INK))
	b.add_theme_stylebox_override("hover_pressed", _chip_box(UIKit.PAPER_INK, UIKit.PAPER_INK))
	b.add_theme_stylebox_override("focus", _chip_box(Color(0, 0, 0, 0), UIKit.PAPER_INK_SOFT))
	b.custom_minimum_size = Vector2(0, 30)
	return b

func _chip_box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(2)
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.content_margin_left = 11
	sb.content_margin_right = 11
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	sb.anti_aliasing = true
	return sb

func _footer() -> Control:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIKit.PAPER_SOFT
	sb.border_width_top = 1
	sb.border_color = UIKit.PAPER_EDGE
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	bar.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	bar.add_child(row)

	var note := UIKit.label("Scroll for the full card · this file stays open until you close it.", 12, UIKit.PAPER_INK_SOFT, UIKit.font_ui())
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(note)

	var close_button := UIKit.primary_button("File It")
	close_button.custom_minimum_size = Vector2(150, 40)
	close_button.pressed.connect(close)
	row.add_child(close_button)
	return bar

func close() -> void:
	closed.emit()
	queue_free()

## ESC 也能关。翻档案的时候手会先去找 ESC，这是不需要教的。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
