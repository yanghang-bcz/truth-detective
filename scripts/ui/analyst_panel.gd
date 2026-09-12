class_name AnalystPanel
extends VBoxContainer
## Analyst —— 分析员面板。
##
## 它不是聊天机器人，也**不是一个输入框**。四个固定动作，每个动作都只能基于
## 玩家已经打开过的证据来回答。这条限制同时写在三处（Safe Context 白名单、
## 系统提示、回复校验），界面上也标出来（每次回答底部写着基于几张已打开的证据）——
## 让玩家看得见这个约束，比让玩家相信它更重要。
##
## v0.2 起它后面接了两套引擎，界面不区分"谁在答"，只区分**用了什么资源**：
##   AI 咨询  —— 花 1 次 Analyst Token，走模型，回答经校验后才显示；
##   离线推理 —— 花 1 点调查点，走本地规则引擎，永远不会编造。
## 前者不可用（没配 key / 额度用完 / 请求失败 / 回答被拦下）时自动落到后者。
## 所以这一屏在任何机器上都是可玩的 —— 游戏从来不靠 LLM 活着。
##
## 这一层刻意保持朴素：loading 只用几个跳动的方块，不用 shader、不用模糊。
## 案件界面全屏时街区已经停了渲染（见 case_trigger.gd），
## 不能因为一个 spinner 把省下来的预算又送回去。

signal spent(cost: int)
signal answered      ## 已经产出一条回答（棋盘据此把面板滚进视野）

var focused_claim := "B"

var _buttons: Array[Button] = []
var _token_row: HBoxContainer
var _token_dots: HBoxContainer
var _token_label: Label
var _mode: Label
var _cost_chip: Label
var _blurb: Label
var _no_key_note: Label
var _loading: HBoxContainer
var _loading_dots: Array[ColorRect] = []
var _loading_label: Label
var _loading_timer: Timer
var _loading_delay: Timer
var _empty_hint: PanelContainer
var _response_box: PanelContainer
var _response_text: Label
var _basis_row: HBoxContainer
var _note: Label
var _footer: Label


static func make(claim_id: String) -> AnalystPanel:
	var p := AnalystPanel.new()
	p.focused_claim = claim_id
	p.add_theme_constant_override("separation", 10)
	p._build()
	return p


# ─────────────────────────────────────────────────────────────
func _build() -> void:
	# ── 抬头：状态灯 + 名字 + 模式 ─────────────────────────
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	add_child(head)
	head.add_child(_status_dot())
	var title := UIKit.label(Locale.t("analyst.title"), 15, UIKit.CYAN, UIKit.font_ui())
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	head.add_child(UIKit.fill(UIKit.hgap(0)))
	_mode = UIKit.meta("", 10, UIKit.MUTED, 2)
	_mode.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_mode)

	_blurb = UIKit.paragraph("", 12, Color(UIKit.SLATE.r, UIKit.SLATE.g, UIKit.SLATE.b, 0.95))
	add_child(_blurb)

	# 没配 key 时给一句产品化的说明，而不是让它变成一个坏掉的功能。
	# 这一行只在真的没有 AI 时出现，措辞是"这个版本没有配"，不是"出错了"。
	_no_key_note = UIKit.paragraph(Locale.t("analyst.no_key"), 11, UIKit.MUTED)
	_no_key_note.visible = false
	add_child(_no_key_note)

	# ── 额度：●●● ────────────────────────────────────────
	_token_row = HBoxContainer.new()
	_token_row.add_theme_constant_override("separation", 8)
	add_child(_token_row)
	_token_dots = HBoxContainer.new()
	_token_dots.add_theme_constant_override("separation", 4)
	_token_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_token_row.add_child(_token_dots)
	_token_label = UIKit.meta("", 10, UIKit.MUTED, 2)
	_token_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_token_row.add_child(_token_label)
	_token_row.add_child(UIKit.fill(UIKit.hgap(0)))
	_cost_chip = UIKit.meta("", 10, UIKit.SLATE, 2)
	_cost_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_token_row.add_child(_cost_chip)

	add_child(UIKit.gap(2))

	# ── 四个固定动作 ──────────────────────────────────────
	var actions := [
		["explain", Locale.t("analyst.a.explain")],
		["not_prove", Locale.t("analyst.a.not_prove")],
		["challenge", Locale.t("analyst.a.challenge")],
		["missing", Locale.t("analyst.a.missing")],
	]
	for pair in actions:
		var b := UIKit.ghost_button(pair[1])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 34)
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(_run.bind(pair[0] as String))
		add_child(b)
		_buttons.append(b)

	# ── 等待态 ────────────────────────────────────────────
	add_child(_build_loading())

	# ── 回答区 ────────────────────────────────────────────
	_empty_hint = UIKit.slot_panel(14)
	_empty_hint.add_child(UIKit.meta(Locale.t("analyst.empty"), 10, UIKit.INK4, 2))
	add_child(_empty_hint)

	_response_box = UIKit.slot_panel(14)
	_response_box.visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_response_box.add_child(col)

	_basis_row = HBoxContainer.new()
	_basis_row.add_theme_constant_override("separation", 6)
	col.add_child(_basis_row)

	_response_text = UIKit.paragraph("", 13, UIKit.FOG)
	col.add_child(_response_text)

	_note = UIKit.paragraph("", 11, UIKit.MUTED)
	_note.visible = false
	col.add_child(_note)

	col.add_child(UIKit.hairline(Color(UIKit.INK3.r, UIKit.INK3.g, UIKit.INK3.b, 0.7)))
	_footer = UIKit.meta("", 9, UIKit.INK4, 1)
	col.add_child(_footer)

	add_child(_response_box)

	CaseState.points_changed.connect(func(_r: int) -> void: _refresh())
	CaseState.unlocked_changed.connect(func(_id: String) -> void: _refresh())
	CaseState.analyst_tokens_changed.connect(func(_n: int) -> void: _refresh())
	AiCoach.state_changed.connect(_refresh)
	AiCoach.answered.connect(_on_answered)

	_restore_last()
	_refresh()


## 棋盘每次切换聚焦的 Claim / 证据时调用。
func set_context(claim_id: String, judgment: String, evidence_id: String) -> void:
	focused_claim = claim_id
	_refresh()


func _exit_tree() -> void:
	if AiCoach.answered.is_connected(_on_answered):
		AiCoach.answered.disconnect(_on_answered)
	if AiCoach.state_changed.is_connected(_refresh):
		AiCoach.state_changed.disconnect(_refresh)


# ─────────────────────────────────────────────────────────────
#  状态
# ─────────────────────────────────────────────────────────────
func _refresh() -> void:
	var busy: bool = AiCoach.busy
	var ai := AiCoach.available()
	var tokens := AiCoach.tokens()

	_mode.text = Locale.t("analyst.offline") if (not ai or tokens == 0) else ""
	_blurb.text = Locale.tf("analyst.blurb_ai", [CaseState.ANALYST_TOKENS_MAX]) if ai \
		else Locale.t("analyst.blurb")
	_no_key_note.visible = not ai
	_token_row.visible = ai
	_cost_chip.text = Locale.t("analyst.cost_ai") if (ai and tokens > 0) \
		else Locale.tf("analyst.cost", [1])
	_paint_tokens(tokens)

	var affordable: bool = AiCoach.can_use_ai() or CaseState.can_afford(1)
	var has_evidence := _current_evidence_id() != ""
	var has_judgment := _judgment() != ""
	_set_enabled(0, has_evidence and affordable and not busy)
	_set_enabled(1, has_evidence and affordable and not busy)
	_set_enabled(2, has_judgment and affordable and not busy)
	_set_enabled(3, affordable and not busy)

	# 等待态要"慢半拍"才出现：请求很快返回时闪一下 loading 比不显示更难受。
	if busy:
		_loading_delay.start()
	else:
		_loading_delay.stop()
		_set_loading(false)


func _set_enabled(i: int, on: bool) -> void:
	if i < _buttons.size():
		_buttons[i].disabled = not on


func _paint_tokens(left: int) -> void:
	var total: int = CaseState.ANALYST_TOKENS_MAX
	for child in _token_dots.get_children():
		child.queue_free()
	for i in range(total):
		var rect := ColorRect.new()
		rect.color = UIKit.CYAN if i < left else Color(UIKit.INK4.r, UIKit.INK4.g, UIKit.INK4.b, 0.5)
		rect.custom_minimum_size = Vector2(7, 7)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_token_dots.add_child(rect)
	_token_label.text = Locale.tf("analyst.consults", [left, total])


func _current_evidence_id() -> String:
	if CaseState.focused_evidence != "" and CaseState.is_unlocked(CaseState.focused_evidence):
		return CaseState.focused_evidence
	if CaseState.unlocked.size() == 1:
		return CaseState.unlocked[0]
	return ""


func _judgment() -> String:
	for entry in CaseState.journey(focused_claim):
		if str(entry["judgment"]) != "":
			return str(entry["judgment"])
	return ""


# ─────────────────────────────────────────────────────────────
#  提问
# ─────────────────────────────────────────────────────────────
func _run(action: String) -> void:
	if AiCoach.busy:
		return
	AiCoach.ask(action, focused_claim, _current_evidence_id())
	# AiCoach 可能同步就返回了（离线路径 / 缓存），这时不该进等待态。
	_refresh()


func _on_answered(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_empty_hint.visible = false
		_response_box.visible = true
		_show_note(Locale.t("analyst.no_points"))
		_footer.text = ""
		return
	_render(str(result.get("text", "")), result.get("basis", []),
		str(result.get("source", "offline")), str(result.get("failure", "")),
		str(result.get("blocked", "")))
	spent.emit(int(result.get("cost_ip", 0)))
	answered.emit()


func _render(text: String, basis: Array, source: String, failure: String, blocked: String) -> void:
	_empty_hint.visible = false
	_response_box.visible = true
	for child in _basis_row.get_children():
		child.queue_free()
	_basis_row.add_child(UIKit.meta(Locale.t("analyst.based"), 9, UIKit.INK4, 2))
	var any := false
	for id in basis:
		if str(id) == "":
			continue
		any = true
		_basis_row.add_child(UIKit.tag(str(id), UIKit.CYAN))
	if not any:
		_basis_row.add_child(UIKit.tag("—", UIKit.INK4))
	_response_text.text = text

	# 提示行的优先级：拿不到东西 > 被拦下 > 这是模型说的。
	# 玩家永远看不到 HTTP 状态码 —— 他不是来调试 API 的。
	var note := ""
	if failure == "no_points":
		note = Locale.t("analyst.no_points")
	elif failure != "":
		note = Locale.t("analyst.failed")
	elif blocked != "":
		note = Locale.t("analyst.blocked")
	elif source == "ai":
		note = Locale.t("analyst.based_only")
	_show_note(note)

	match source:
		"ai": _footer.text = Locale.tf("analyst.footer_ai", [CaseState.unlocked.size(), 8])
		"cache": _footer.text = Locale.tf("analyst.footer_cache", [CaseState.unlocked.size(), 8])
		_: _footer.text = Locale.tf("analyst.footer", [CaseState.unlocked.size(), 8])

	# 一次很轻的淡入。回答是"出现"的，不是"弹出来"的。
	_response_box.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(_response_box, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE)


func _show_note(text: String) -> void:
	_note.text = text
	_note.visible = text != ""


## 切语言会把这一屏整个重建。把最后一条咨询恢复出来，
## 否则玩家换一下语言，刚才读的回答就没了。
func _restore_last() -> void:
	var last := {}
	for entry in CaseState.ai_history:
		if str(entry.get("claim", "")) == focused_claim:
			last = entry
	if last.is_empty():
		return
	var source := str(last.get("source", "offline"))
	if source == "cache":
		source = "offline"
	_render(str(last.get("response", "")), last.get("evidence", []), source, "", "")


# ─────────────────────────────────────────────────────────────
#  等待态
# ─────────────────────────────────────────────────────────────
func _build_loading() -> Control:
	_loading = HBoxContainer.new()
	_loading.add_theme_constant_override("separation", 6)
	_loading.visible = false

	for _i in range(3):
		var rect := ColorRect.new()
		rect.color = UIKit.CYAN
		rect.custom_minimum_size = Vector2(4, 4)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var holder := CenterContainer.new()
		holder.custom_minimum_size = Vector2(5, 12)
		holder.add_child(rect)
		_loading.add_child(holder)
		_loading_dots.append(rect)

	_loading_label = UIKit.meta(Locale.t("analyst.busy"), 10, UIKit.CYAN, 2)
	_loading_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_loading.add_child(_loading_label)

	_loading_delay = Timer.new()
	_loading_delay.one_shot = true
	_loading_delay.wait_time = 0.3
	_loading_delay.timeout.connect(func() -> void: _set_loading(AiCoach.busy))
	add_child(_loading_delay)

	# 三个方块轮流亮。用 0.34s 的 Timer 而不是每帧重绘 ——
	# 一个等待动画不值得每帧动一次 UI。
	_loading_timer = Timer.new()
	_loading_timer.wait_time = 0.34
	_loading_timer.timeout.connect(_advance_loading)
	add_child(_loading_timer)
	return _loading


func _set_loading(on: bool) -> void:
	_loading.visible = on
	if on:
		if not _loading_timer.is_stopped():
			return
		_loading_timer.start()
		_advance_loading()
	else:
		_loading_timer.stop()


func _advance_loading() -> void:
	var phase: int = int(Time.get_ticks_msec() / 340) % _loading_dots.size()
	for i in range(_loading_dots.size()):
		_loading_dots[i].color = Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b,
			1.0 if i == phase else 0.22)


# ─────────────────────────────────────────────────────────────
func _status_dot() -> Control:
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(9, 9)
	var rect := ColorRect.new()
	rect.color = UIKit.CYAN
	rect.custom_minimum_size = Vector2(9, 9)
	holder.add_child(rect)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# 极慢的呼吸。它是"在运行"的提示，不该抢注意力。
	var tween := create_tween().set_loops()
	tween.tween_property(rect, "modulate:a", 0.35, 1.6).set_trans(Tween.TRANS_SINE)
	tween.tween_property(rect, "modulate:a", 1.0, 1.6).set_trans(Tween.TRANS_SINE)
	return holder
