class_name BoardPhase
extends CasePhase
## Investigation Board。玩家在这里花掉十个调查点。
##
## 三栏的职责是分开的，而且顺序有意：
##   左 = 你还不知道什么（调查方向，标价）
##   中 = 你已经拿到什么（证据板，纸）
##   右 = 你现在怎么想（判定 + 分析员）
## 从左到右，正好是"获取 → 持有 → 判断"这条链。玩家不需要读说明就知道往哪点。
##
## 关键设计：10 点买不下全部 8 张卡（总共要 12 点）。所以"先查什么"必须成为一个
## 真实的选择，而不是把资料点一遍。这是本案唯一的策略层。

var focused_claim := "B"

var _rows := {}                  ## evidence id -> 左栏那一行
var _cards := {}                 ## evidence id -> 证据卡
var _confidence_by_claim := {}
var _pending_trigger := "revised"
var _detail: EvidenceDetail

var _judge_scroll: ScrollContainer
var _source_box: VBoxContainer
var _board_grid: GridContainer
var _board_empty: Control
var _board_count: Label
var _claim_text: Label
var _claim_short: Label
var _judgment: JudgmentRow
var _confidence_box: VBoxContainer
var _claim_tabs := {}
var _hint: Label
var _analyst: AnalystPanel


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", UIKit.GUTTER)
	margin.add_theme_constant_override("margin_right", UIKit.GUTTER)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 16)
	margin.add_child(shell)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", UIKit.COL_GAP)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(columns)

	columns.add_child(_build_sources())
	columns.add_child(_build_board())
	columns.add_child(_build_judgment())
	shell.add_child(_build_footer())

	_refresh_sources()
	_refresh_board()
	_sync_judgment_panel()

	for claim in CaseData.claims(case):
		_confidence_by_claim[str(claim.get("id", ""))] = 50

# ─────────────────────────────────────────────────────────────
#  左栏：调查方向
# ─────────────────────────────────────────────────────────────
func _build_sources() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(300, 0)
	col.add_theme_constant_override("separation", 12)
	col.add_child(section(Locale.t("board.sources")))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UIKit.style_scroll(scroll)
	col.add_child(scroll)

	_source_box = VBoxContainer.new()
	_source_box.add_theme_constant_override("separation", 18)
	_source_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_source_box)
	return col

func _refresh_sources() -> void:
	for child in _source_box.get_children():
		child.queue_free()
	_rows.clear()

	for source in CaseData.sources(case):
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", 7)
		_source_box.add_child(block)

		# 分组标题原本用 INK4（那是给分隔线用的颜色），在深底上几乎读不出来。
		var head := UIKit.meta(str(source.get("label", "")), 10, UIKit.MUTED.lightened(0.14), 2)
		block.add_child(head)
		var note := UIKit.paragraph(str(source.get("note", "")), 11,
			Color(UIKit.SLATE.r, UIKit.SLATE.g, UIKit.SLATE.b, 0.75))
		block.add_child(note)
		block.add_child(UIKit.gap(2))

		for id in source.get("evidence", []):
			var row := _source_row(str(id))
			_rows[str(id)] = row
			block.add_child(row)

func _source_row(evidence_id: String) -> Control:
	var e := CaseData.evidence(case, evidence_id)
	var unlocked: bool = CaseState.is_unlocked(evidence_id)
	var opened: bool = CaseState.is_opened(evidence_id)
	var cost := int(e.get("cost", 1))
	var affordable: bool = CaseState.can_afford(cost)

	var rail := PanelContainer.new()
	rail.mouse_filter = Control.MOUSE_FILTER_STOP
	rail.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	sb.content_margin_left = 11
	sb.content_margin_right = 11
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	sb.anti_aliasing = true

	var title_color := UIKit.SLATE
	if unlocked:
		sb.bg_color = Color(UIKit.INK2.r, UIKit.INK2.g, UIKit.INK2.b, 0.55)
		sb.border_color = UIKit.INK3.darkened(0.2)
		title_color = UIKit.SLATE
	elif affordable:
		sb.bg_color = UIKit.INK2
		sb.border_color = UIKit.INK3
		title_color = UIKit.FOG
	else:
		sb.bg_color = Color(UIKit.INK1.r, UIKit.INK1.g, UIKit.INK1.b, 0.6)
		sb.border_color = UIKit.INK3.darkened(0.35)
		title_color = UIKit.INK4
	rail.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_child(row)

	var badge := UIKit.label(evidence_id, 10, title_color, UIKit.tracked(UIKit.font_mono(), 1))
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)

	var title := UIKit.label(str(e.get("title", "")), 13, title_color, UIKit.font_ui())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.clip_text = true
	row.add_child(title)

	var price := ""
	var price_color := UIKit.MUTED
	if unlocked:
		price = Locale.t("board.read") if opened else Locale.t("board.open")
		price_color = UIKit.MUTED
	else:
		price = Locale.tf("board.cost", [cost])
		price_color = UIKit.LAMP if affordable else UIKit.MUTED.darkened(0.30)
	var cost_label := UIKit.meta(price, 10, price_color, 1)
	cost_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cost_label)

	rail.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_source_pressed(evidence_id)
			rail.accept_event())
	rail.mouse_entered.connect(func() -> void:
		sb.border_color = UIKit.INK4
		rail.add_theme_stylebox_override("panel", sb))
	rail.mouse_exited.connect(func() -> void:
		if unlocked:
			sb.border_color = UIKit.INK3.darkened(0.2)
		elif affordable:
			sb.border_color = UIKit.INK3
		else:
			sb.border_color = UIKit.INK3.darkened(0.35)
		rail.add_theme_stylebox_override("panel", sb))
	return rail

func _on_source_pressed(evidence_id: String) -> void:
	if CaseState.is_unlocked(evidence_id):
		_open_detail(evidence_id)
		return
	var e := CaseData.evidence(case, evidence_id)
	var cost := int(e.get("cost", 1))
	if not CaseState.can_afford(cost):
		_flash_hint(Locale.tf("board.broke", [evidence_id, cost, CaseState.remaining()]),
			UIKit.J_UNSUPPORTED)
		return
	if not CaseState.unlock(evidence_id):
		return
	_refresh_sources()
	_refresh_board(true, evidence_id)
	_pending_trigger = "evidence:" + evidence_id
	_open_detail(evidence_id)

# ─────────────────────────────────────────────────────────────
#  中栏：证据板
# ─────────────────────────────────────────────────────────────
func _build_board() -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var section_box := section(Locale.t("board.evidence"))
	section_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(section_box)

	_board_count = UIKit.meta("", 10, UIKit.SLATE, 1)
	_board_count.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_board_count)

	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(stack)

	stack.add_child(_pinboard())

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 14.0
	scroll.offset_top = 14.0
	scroll.offset_right = -14.0
	scroll.offset_bottom = -14.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UIKit.style_scroll(scroll)
	stack.add_child(scroll)

	_board_grid = GridContainer.new()
	_board_grid.columns = 2
	_board_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_grid.add_theme_constant_override("h_separation", 18)
	_board_grid.add_theme_constant_override("v_separation", 18)
	scroll.add_child(_board_grid)

	_board_empty = _empty_state()
	_board_empty.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_empty.offset_left = 14.0
	_board_empty.offset_top = 14.0
	_board_empty.offset_right = -14.0
	_board_empty.offset_bottom = -14.0
	stack.add_child(_board_empty)
	return col

## 证据板底下那层"钉板"。同一块空白，有没有托底读法完全不同：
## 有托底 = 这块板子还空着；没托底 = 这里什么都没有。
func _pinboard() -> Control:
	var surface := PanelContainer.new()
	surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.055, 0.071, 0.9)
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.border_color = UIKit.INK3
	sb.anti_aliasing = true
	surface.add_theme_stylebox_override("panel", sb)
	return surface


func _empty_state() -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UIKit.INK1.r, UIKit.INK1.g, UIKit.INK1.b, 0.5)
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.border_color = UIKit.INK3
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)

	var title := UIKit.meta(Locale.t("board.empty_title"), 11, UIKit.INK4, 3)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var body := UIKit.paragraph(Locale.t("board.empty_body"), 13,
		Color(UIKit.SLATE.r, UIKit.SLATE.g, UIKit.SLATE.b, 0.9))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(body)
	return panel

func _refresh_board(animate_new: bool = false, new_id: String = "") -> void:
	for child in _board_grid.get_children():
		child.queue_free()
	_cards.clear()

	for e in CaseState.unlocked_evidence():
		var card := EvidenceCard.make(e)
		var id := str(e.get("id", ""))
		if CaseState.is_opened(id):
			card.examined = true
			var stored: Dictionary = CaseState.classification_of(id)
			if not stored.is_empty():
				card.set_classification(str(stored.get("relevance", "")), str(stored.get("kind", "")))
		card.opened.connect(_open_detail)
		_board_grid.add_child(card)
		_cards[id] = card
		if animate_new and id == new_id:
			card.modulate = Color(1, 1, 1, 0)
			var tween := create_tween()
			tween.tween_property(card, "modulate:a", 1.0, 0.32).set_trans(Tween.TRANS_SINE)

	var total_opened: int = CaseState.unlocked.size()
	_board_count.text = Locale.tf("board.opened", [total_opened, 8])
	_board_empty.visible = CaseState.unlocked.is_empty()

# ─────────────────────────────────────────────────────────────
#  右栏：当前判定 + 分析员
# ─────────────────────────────────────────────────────────────
func _build_judgment() -> Control:
	var outer := VBoxContainer.new()
	outer.custom_minimum_size = Vector2(344, 0)
	outer.add_theme_constant_override("separation", 14)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UIKit.style_scroll(scroll)
	_judge_scroll = scroll
	outer.add_child(scroll)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	# ── 判定面板 ──────────────────────────────────────────
	var panel := UIKit.slot_panel(18)
	col.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 13)
	panel.add_child(inner)

	inner.add_child(UIKit.eyebrow(Locale.t("board.current")))
	inner.add_child(_claim_tab_row())

	_claim_short = UIKit.meta("", 10, UIKit.SLATE, 2)
	inner.add_child(_claim_short)

	_claim_text = UIKit.quote("", 17, UIKit.CHALK)
	inner.add_child(_claim_text)

	_judgment = JudgmentRow.make(true, true)
	_judgment.selected.connect(_on_judgment_changed)
	inner.add_child(_judgment)

	_confidence_box = VBoxContainer.new()
	inner.add_child(_confidence_box)

	# ── 分析员 ────────────────────────────────────────────
	_analyst = AnalystPanel.make(focused_claim)
	_analyst.spent.connect(func(_c: int) -> void: _pending_trigger = "analyst")
	# 回答出现在面板下方，可能落在视野之外 —— 主动把它滚进来，
	# 否则玩家点了按钮却看不到任何反应，会以为坏了。
	_analyst.answered.connect(_on_analyst_answered)
	col.add_child(_analyst)
	return outer

func _on_analyst_answered() -> void:
	if _judge_scroll == null or _analyst == null:
		return
	# 回答是自动换行的，要等一次布局才有最终高度。
	# 立刻滚，滚到的是它还没长高时的位置 —— 结果就是答案的下半句被裁掉。
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(_judge_scroll):
		return
	# 回答通常比剩下的空间高，所以直接滚到底：让玩家看见回答的开头，
	# 比让它"部分可见"有用得多。四个动作按钮往上挪一格，是可以接受的代价。
	var bar: VScrollBar = _judge_scroll.get_v_scroll_bar()
	_judge_scroll.scroll_vertical = int(bar.max_value)


func _claim_tab_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	for claim in CaseData.claims(case):
		var id := str(claim.get("id", ""))
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 4)

		var b := Button.new()
		b.text = id
		b.toggle_mode = true
		b.add_theme_font_override("font", UIKit.tracked(UIKit.font_mono(), 0))
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", UIKit.SLATE)
		b.add_theme_color_override("font_hover_color", UIKit.CHALK)
		b.add_theme_color_override("font_pressed_color", UIKit.CHALK)
		b.add_theme_color_override("font_hover_pressed_color", UIKit.CHALK)
		b.add_theme_stylebox_override("normal", _tab_box(Color(0, 0, 0, 0), UIKit.INK3))
		b.add_theme_stylebox_override("hover", _tab_box(UIKit.INK2, UIKit.INK4))
		b.add_theme_stylebox_override("pressed", _tab_box(UIKit.INK3, UIKit.INK4))
		b.add_theme_stylebox_override("hover_pressed", _tab_box(UIKit.INK3, UIKit.INK4))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.custom_minimum_size = Vector2(38, 32)
		b.pressed.connect(_select_claim.bind(id))
		stack.add_child(b)

		# 已经给过判定的 Claim，在字母下面点一颗对应颜色的点。
		# 四个 Claim 的状态一眼看完，不用逐个点开。
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(38, 2)
		dot.color = Color(0, 0, 0, 0)
		stack.add_child(dot)

		_claim_tabs[id] = {"button": b, "dot": dot}
		row.add_child(stack)

	row.add_child(UIKit.fill(UIKit.hgap(0)))
	return row

func _tab_box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.anti_aliasing = true
	return sb

func _select_claim(id: String) -> void:
	focused_claim = id
	_sync_judgment_panel()

## 把右栏刷新成"当前聚焦的 Claim"的样子：原文、已记录的判定、置信度、分析员上下文。
func _sync_judgment_panel() -> void:
	for id in _claim_tabs:
		var tab: Dictionary = _claim_tabs[id]
		tab["button"].button_pressed = (id == focused_claim)

	var claim := CaseData.claim(case, focused_claim)
	_claim_short.text = Locale.tf("board.claim_short",
		[focused_claim, str(claim.get("short", "")).to_upper()])
	_claim_text.text = "“" + str(claim.get("text", "")) + "”"

	var last := _last_judgment(focused_claim)
	_judgment.value = str(last.get("judgment", ""))

	var confidence := int(last.get("confidence", _confidence_by_claim.get(focused_claim, 50)))
	_confidence_by_claim[focused_claim] = confidence
	for child in _confidence_box.get_children():
		child.queue_free()
	var row := confidence_row(confidence, func(v: int) -> void: _on_confidence_changed(v))
	_confidence_box.add_child(row[0])

	_refresh_tab_dots()
	if _analyst != null:
		_analyst.set_context(focused_claim, str(last.get("judgment", "")), CaseState.focused_evidence)

func _refresh_tab_dots() -> void:
	for id in _claim_tabs:
		var stored := _last_judgment(id)
		var dot: ColorRect = _claim_tabs[id]["dot"]
		if stored.is_empty() or str(stored.get("judgment", "")) == "":
			dot.color = Color(0, 0, 0, 0)
		else:
			dot.color = UIKit.judgment_color(str(stored["judgment"]))

func _last_judgment(claim_id: String) -> Dictionary:
	var entries := CaseState.journey(claim_id)
	if entries.is_empty():
		return {}
	return entries[entries.size() - 1]

func _on_judgment_changed(_key: String) -> void:
	_record()

func _on_confidence_changed(v: int) -> void:
	_confidence_by_claim[focused_claim] = v
	_record()

func _record() -> void:
	var judgment := _judgment.value
	if judgment == "":
		return
	CaseState.record_judgment(focused_claim, judgment, int(_confidence_by_claim.get(focused_claim, 50)), _pending_trigger)
	_refresh_tab_dots()
	if _analyst != null:
		_analyst.set_context(focused_claim, judgment, CaseState.focused_evidence)

# ─────────────────────────────────────────────────────────────
#  证据详情
# ─────────────────────────────────────────────────────────────
func _open_detail(evidence_id: String) -> void:
	if _detail != null and is_instance_valid(_detail):
		_detail.queue_free()
	CaseState.focused_evidence = evidence_id
	CaseState.mark_opened(evidence_id)
	_pending_trigger = "evidence:" + evidence_id

	var card: EvidenceCard = _cards.get(evidence_id, null)
	if card != null:
		card.examined = true

	_detail = EvidenceDetail.open(self, case, evidence_id)
	_detail.classified.connect(_on_classified)
	_detail.closed.connect(func() -> void:
		_refresh_sources()
		_refresh_tab_dots()
		if _analyst != null:
			_analyst.set_context(focused_claim, _judgment.value, evidence_id))
	if _analyst != null:
		_analyst.set_context(focused_claim, _judgment.value, evidence_id)

func _on_classified(evidence_id: String, relevance: String, kind: String) -> void:
	CaseState.classify(evidence_id, relevance, kind)
	var card: EvidenceCard = _cards.get(evidence_id, null)
	if card != null:
		card.examined = true
		card.set_classification(relevance, kind)

# ─────────────────────────────────────────────────────────────
#  底栏
# ─────────────────────────────────────────────────────────────
func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)

	_hint = UIKit.paragraph(Locale.t("board.hint"), 12,
		Color(UIKit.SLATE.r, UIKit.SLATE.g, UIKit.SLATE.b, 0.85))
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_hint)

	var submit := UIKit.primary_button(Locale.t("board.submit"))
	submit.custom_minimum_size = Vector2(300, 46)
	submit.pressed.connect(func() -> void: finished.emit("final"))
	row.add_child(submit)
	return row

func _flash_hint(text: String, color: Color) -> void:
	_hint.text = text
	_hint.add_theme_color_override("font_color", color)
	var tween := create_tween()
	tween.tween_property(_hint, "modulate", Color(1.4, 1.15, 0.9, 1.0), 0.12)
	tween.tween_property(_hint, "modulate", Color.WHITE, 0.5)
	tween.tween_callback(func() -> void:
		_hint.add_theme_color_override("font_color", Color(UIKit.SLATE.r, UIKit.SLATE.g, UIKit.SLATE.b, 0.85)))
