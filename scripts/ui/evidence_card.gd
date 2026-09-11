class_name EvidenceCard
extends PanelContainer
## 证据卡。整个界面里"文件"这一类东西的代表：暖色、直角、有厚度、往下投影。
##
## 和 screen_panel（帖文那类冷色发光的东西）形成对立 —— 玩家要学的就是分辨这两类，
## 所以它们在视觉上必须先分清。

signal opened(id: String)

var id := ""
var data := {}
var examined := false:
	set(v):
		examined = v
		_refresh(false)

var _title: Label
var _summary: Label
var _bar: ColorRect
var _index_chip: PanelContainer
var _bottom: HBoxContainer
var _hovered := false

static func make(d: Dictionary) -> EvidenceCard:
	var card := EvidenceCard.new()
	card.data = d
	card.id = str(d.get("id", ""))
	card._build()
	return card

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 13)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	_bar = ColorRect.new()
	_bar.color = Color(UIKit.PAPER_INK.r, UIKit.PAPER_INK.g, UIKit.PAPER_INK.b, 0.18)
	_bar.custom_minimum_size = Vector2(3, 0)
	_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_bar)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	# ── 顶部：档案编号 + 成本 ──────────────────────────────
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)

	_index_chip = PanelContainer.new()
	var chip_sb := StyleBoxFlat.new()
	chip_sb.bg_color = UIKit.PAPER_INK
	chip_sb.set_corner_radius_all(2)
	chip_sb.content_margin_left = 7
	chip_sb.content_margin_right = 7
	chip_sb.content_margin_top = 2
	chip_sb.content_margin_bottom = 2
	_index_chip.add_theme_stylebox_override("panel", chip_sb)
	var idx := str(data.get("id", ""))
	_index_chip.add_child(UIKit.label(idx, 11, UIKit.PAPER, UIKit.tracked(UIKit.font_mono(), 1)))
	head.add_child(_index_chip)

	head.add_child(UIKit.fill(UIKit.hgap(0)))

	var cost := int(data.get("cost", 1))
	head.add_child(_paper_tag("%d IP" % cost, UIKit.LAMP_DIM))

	# ── 标题与摘要 ────────────────────────────────────────
	_title = UIKit.label(str(data.get("title", "")), 19, UIKit.PAPER_INK, UIKit.font_display())
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_title)

	var src := _source_label(str(data.get("source", "")))
	col.add_child(src)

	_summary = UIKit.paragraph(str(data.get("summary", "")), 13, UIKit.PAPER_INK_SOFT)
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_summary)

	col.add_child(UIKit.fill(UIKit.gap(0), true, true))

	col.add_child(_paper_rule())

	# ── 底部：可信度读数 / 或玩家自己的分类结果 ───────────────
	_bottom = HBoxContainer.new()
	_bottom.add_theme_constant_override("separation", 8)
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_bottom)

	gui_input.connect(_on_input)
	mouse_entered.connect(func() -> void:
		_hovered = true
		_refresh(true))
	mouse_exited.connect(func() -> void:
		_hovered = false
		_refresh(false))
	_refresh(false)

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		opened.emit(id)
		accept_event()

## examined 之后，底部从"可信度读数"换成玩家自己给出的两个分类 ——
## 让界面回读一次玩家的输入，比弹一句"已保存"有用得多。
func set_classification(relevance: String, kind: String) -> void:
	for child in _bottom.get_children():
		child.queue_free()
	if relevance != "":
		_bottom.add_child(_paper_tag(relevance.to_upper(), UIKit.PAPER_INK_SOFT))
	if kind != "":
		_bottom.add_child(_paper_tag(kind.to_upper(), UIKit.PAPER_INK_SOFT))

func _refresh(hovered: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIKit.PAPER
	sb.set_corner_radius_all(UIKit.RADIUS)
	sb.set_border_width_all(1)
	sb.border_color = UIKit.PAPER_EDGE
	sb.content_margin_left = 16
	sb.content_margin_right = 18
	sb.content_margin_top = 15
	sb.content_margin_bottom = 15
	sb.anti_aliasing = true
	if hovered:
		sb.border_color = UIKit.PAPER_INK_SOFT
		sb.shadow_color = Color(0, 0, 0, 0.62)
		sb.shadow_size = 16
		sb.shadow_offset = Vector2(0, 7)
	else:
		sb.shadow_color = Color(0, 0, 0, 0.50)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2(0, 4)
	add_theme_stylebox_override("panel", sb)

	var ink := UIKit.PAPER_INK if hovered else Color(UIKit.PAPER_INK.r, UIKit.PAPER_INK.g, UIKit.PAPER_INK.b, 0.92)
	_title.add_theme_color_override("font_color", ink)
	_bar.color = Color(UIKit.PAPER_INK.r, UIKit.PAPER_INK.g, UIKit.PAPER_INK.b, 0.55 if hovered else 0.18)

	if not examined:
		for child in _bottom.get_children():
			child.queue_free()
		var reliability := str(data.get("reliability", ""))
		var context := str(data.get("context", ""))
		if reliability != "":
			_bottom.add_child(_paper_tag(reliability.to_upper(), UIKit.PAPER_INK_SOFT))
		if context != "":
			_bottom.add_child(_paper_tag("CONTEXT " + context.to_upper(), UIKit.PAPER_INK_SOFT))

func _source_label(source_id: String) -> Label:
	var text := source_id.replace("_", " ")
	return UIKit.meta(text, 10, Color(UIKit.PAPER_INK_SOFT.r, UIKit.PAPER_INK_SOFT.g, UIKit.PAPER_INK_SOFT.b, 0.95), 2)

func _paper_tag(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_corner_radius_all(2)
	sb.set_border_width_all(1)
	sb.border_color = Color(color.r, color.g, color.b, 0.40)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(UIKit.meta(text, 9, Color(color.r, color.g, color.b, 0.95), 1))
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return p

func _paper_rule() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := ColorRect.new()
	line.color = Color(UIKit.PAPER_INK.r, UIKit.PAPER_INK.g, UIKit.PAPER_INK.b, 0.14)
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	return box
