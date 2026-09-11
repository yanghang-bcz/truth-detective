class_name AnalystPanel
extends VBoxContainer
## Analyst —— 分析员面板。
##
## 它不是聊天机器人。只有四个固定动作，而且四个动作都**只能**基于玩家已经打开过的
## 证据来回答。这条限制是硬性的，并且写在界面上（每次回答底部都会标出
## "基于 N / 8 张已打开的证据"）—— 让玩家看得见这个约束，比让玩家相信它更重要。
##
## 这也是为什么它没有接大模型：一个只能引用 E01–E08 的规则引擎，
## 在"不编造证据"这件事上天然比模型可靠。要接模型，替换 _answer 的内容来源即可，
## 但那条硬规则必须保留。

signal spent(cost: int)
signal answered      ## 已经产出一条回答（棋盘据此把面板滚进视野）

const COST := 1

var focused_claim := "B"

var _buttons: Array[Button] = []
var _response_box: PanelContainer
var _response_text: Label
var _basis_row: HBoxContainer
var _footer: Label
var _empty_hint: PanelContainer
var _answers := 0

static func make(claim_id: String) -> AnalystPanel:
	var p := AnalystPanel.new()
	p.focused_claim = claim_id
	p.add_theme_constant_override("separation", 10)
	p._build()
	return p

func _build() -> void:
	# ── 抬头 ──────────────────────────────────────────────
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	add_child(head)
	head.add_child(_status_dot())
	var title := UIKit.label("Analyst", 15, UIKit.CYAN, UIKit.font_ui())
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	head.add_child(UIKit.fill(UIKit.hgap(0)))
	var cost := UIKit.meta("%d IP / CONSULT" % COST, 10, UIKit.SLATE, 2)
	cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(cost)

	var blurb := UIKit.paragraph(
		"Reads only what you have opened. It will not tell you the answer.", 12,
		Color(UIKit.SLATE.r, UIKit.SLATE.g, UIKit.SLATE.b, 0.95))
	add_child(blurb)

	add_child(UIKit.gap(2))

	# ── 四个固定动作 ──────────────────────────────────────
	var actions := [
		["explain", "Explain this evidence"],
		["not_prove", "What this does NOT prove"],
		["challenge", "Challenge my judgment"],
		["missing", "What am I missing?"],
	]
	for pair in actions:
		var b := UIKit.ghost_button(pair[1])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 34)
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(_run.bind(pair[0] as String))
		add_child(b)
		_buttons.append(b)

	# ── 回答区 ────────────────────────────────────────────
	_empty_hint = UIKit.slot_panel(14)
	_empty_hint.add_child(UIKit.meta("no question asked yet", 10, UIKit.INK4, 2))
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

	var rule := UIKit.hairline(Color(UIKit.INK3.r, UIKit.INK3.g, UIKit.INK3.b, 0.7))
	col.add_child(rule)

	_footer = UIKit.meta("", 9, UIKit.INK4, 1)
	col.add_child(_footer)

	add_child(_response_box)

	CaseState.points_changed.connect(func(_r: int) -> void: _refresh())
	CaseState.unlocked_changed.connect(func(_id: String) -> void: _refresh())
	_refresh()

## 棋盘每次切换聚焦的 Claim / 证据时调用。
func set_context(claim_id: String, judgment: String, evidence_id: String) -> void:
	focused_claim = claim_id
	_refresh()

# ─────────────────────────────────────────────────────────────
func _refresh() -> void:
	var has_evidence := _current_evidence_id() != ""
	var has_judgment := _judgment() != ""
	var affordable: bool = CaseState.can_afford(COST)
	_set_enabled(0, has_evidence and affordable)
	_set_enabled(1, has_evidence and affordable)
	_set_enabled(2, has_judgment and affordable)
	_set_enabled(3, affordable)

func _set_enabled(i: int, on: bool) -> void:
	if i < _buttons.size():
		_buttons[i].disabled = not on

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
func _run(action: String) -> void:
	if not CaseState.spend(COST):
		return
	CaseState.ai_calls += 1
	spent.emit(COST)
	var data: Dictionary = CaseState.data
	var evidence_id := _current_evidence_id()

	match action:
		"explain":
			var e := CaseData.evidence(data, evidence_id)
			_answer(str(e.get("analyst", "")), [evidence_id])

		"not_prove":
			var e := CaseData.evidence(data, evidence_id)
			var lines := "Nothing in this card establishes the following:\n"
			for item in e.get("does_not_prove", []):
				lines += "\n— " + str(item)
			_answer(lines, [evidence_id])

		"challenge":
			var text := CaseData.challenge(data, focused_claim, _judgment())
			if text == "":
				text = "No counter-argument is available for this combination yet."
			# 挑战只引用玩家已经打开的证据，绝不替玩家补证据。
			_answer(text, CaseState.unlocked.duplicate())

		"missing":
			var gap := CaseData.first_gap(data, CaseState.unlocked)
			if gap.is_empty():
				_answer("Every category in this file has been opened. The remaining question is not what else exists, but what the record can actually support.", CaseState.unlocked.duplicate())
			else:
				_answer(str(gap.get("message", "")), CaseState.unlocked.duplicate())

	_answers += 1
	_refresh()
	answered.emit()

func _answer(text: String, basis: Array) -> void:
	_empty_hint.visible = false
	_response_box.visible = true
	for child in _basis_row.get_children():
		child.queue_free()
	_basis_row.add_child(UIKit.meta("Based on", 9, UIKit.INK4, 2))
	for id in basis:
		if str(id) == "":
			continue
		_basis_row.add_child(UIKit.tag(str(id), UIKit.CYAN))
	if basis.is_empty():
		_basis_row.add_child(UIKit.tag("—", UIKit.INK4))
	_response_text.text = text
	_footer.text = "LOCAL REASONING · %d OF %d EVIDENCE OPENED" % [CaseState.unlocked.size(), 8]

	# 一次很轻的淡入。回答是"出现"的，不是"弹出来"的。
	_response_box.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(_response_box, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE)

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
