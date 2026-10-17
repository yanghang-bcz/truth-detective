class_name FinalPhase
extends CasePhase
## Final Review。玩家在这里**核对并补全**自己的判断，然后一次性确认。
##
## v0.2 这一页叫 Final Judgment，而且进来就把四条答案全部清空、把握一律重置为
## 50 —— 玩家在调查阶段做过的判断被整页抹掉，只能从头再选一遍。三轮真机测试里
## 反馈最集中的就是这条"无意义的重复作答"。
##
## v0.3 改成 Final Review：
##   · 进来直接显示 CaseState.current_judgments，一个字都不改；
##   · 已经答过的不必再动，只补没答的那几条；
##   · 仍可自由修改任意一条，改完立刻写回 current；
##   · 四条全部有答案才允许确认，确认时对 current 做快照。
##
## 界面刻意与调查页右栏保持同一套控件、同一个滑条。"这只是刚才那件事，
## 只不过现在我知道得多了一点"——变化发生在玩家脑子里，不要在界面上重来一遍。

var _rows := {}
var _hint: Label


func _build() -> void:
	var c := scroll_column(860)
	c.add_child(UIKit.gap(30))
	c.add_child(UIKit.eyebrow(Locale.t("phase.final")))
	c.add_child(UIKit.gap(12))
	c.add_child(UIKit.heading(Locale.t("final.title"), 34))
	c.add_child(UIKit.gap(16))
	c.add_child(UIKit.rule(Color(UIKit.INK4.r, UIKit.INK4.g, UIKit.INK4.b, 0.9)))
	c.add_child(UIKit.gap(18))
	c.add_child(UIKit.paragraph(Locale.t("final.lede"), 16, UIKit.FOG))
	c.add_child(UIKit.gap(32))

	for claim in CaseData.claims(case):
		c.add_child(_claim_block(claim))
		c.add_child(UIKit.gap(22))

	c.add_child(_footer())
	c.add_child(UIKit.gap(44))
	stagger_fade(c, 0.05)


func _exit_tree() -> void:
	_flush_all()

func _claim_block(claim: Dictionary) -> Control:
	var id := str(claim.get("id", ""))
	# 读数一律来自统一状态。这里**不写任何默认值** ——
	# 写一个 "" 或 50 进去，就等于把玩家的答案盖掉了。
	var judgment_key := CaseState.current_judgment(id)
	var confidence_value := CaseState.current_confidence(id)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var letter := UIKit.label(id, 20, UIKit.LAMP, UIKit.tracked(UIKit.font_mono(), 2))
	letter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(letter)
	var divider := ColorRect.new()
	divider.color = UIKit.INK3
	divider.custom_minimum_size = Vector2(1, 22)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(divider)
	var short := UIKit.meta(str(claim.get("short", "")), 11, UIKit.SLATE, 2)
	short.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(short)
	head.add_child(UIKit.fill(UIKit.hgap(0)))
	var status := UIKit.meta("", 10, UIKit.MUTED, 1)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(status)
	box.add_child(head)

	box.add_child(UIKit.quote("“" + str(claim.get("text", "")) + "”", 20))

	var judgment := JudgmentRow.make(false, true)
	judgment.value = judgment_key
	box.add_child(judgment)

	var confidence := confidence_row(confidence_value, _on_confidence_live.bind(id),
		_on_confidence_commit.bind(id))
	box.add_child(confidence[0])

	box.add_child(UIKit.gap(4))
	box.add_child(UIKit.rule(Color(UIKit.INK3.r, UIKit.INK3.g, UIKit.INK3.b, 0.8)))

	# 听 value_changed 而不是 selected：selected 只在玩家点击时发，
	# 那么程序化回填的判定会让上面那行状态一直挂着旧文字。
	judgment.value_changed.connect(func(key: String) -> void:
		if key == "":
			status.text = Locale.t("final.unanswered")
			status.add_theme_color_override("font_color", UIKit.MUTED)
		else:
			status.text = UIKit.judgment_label(key).to_upper()
			status.add_theme_color_override("font_color", UIKit.judgment_color(key)))
	# selected 才是"玩家点的"。写回统一状态，并允许在 Final Review 里改。
	judgment.selected.connect(func(key: String) -> void:
		CaseState.select_judgment(id, key, -1, "final")
		_clear_hint())

	_paint_status(status, judgment_key)
	_rows[id] = {
		"judgment": judgment,
		"confidence": confidence[1],
		"slider": confidence[2],
		"status": status,
	}
	return box


func _paint_status(status: Label, key: String) -> void:
	if key == "":
		status.text = Locale.t("final.unanswered")
		status.add_theme_color_override("font_color", UIKit.MUTED)
	else:
		status.text = UIKit.judgment_label(key).to_upper()
		status.add_theme_color_override("font_color", UIKit.judgment_color(key))


func _on_confidence_live(v: int, claim_id: String) -> void:
	CaseState.set_confidence(claim_id, v)

func _on_confidence_commit(_v: int, previous: int, claim_id: String) -> void:
	CaseState.commit_confidence(claim_id, previous)

func _flush_all() -> void:
	for id in _rows:
		var slider: ConfidenceSlider = _rows[id]["slider"]
		if slider != null and is_instance_valid(slider):
			slider.commit_pending()


func _footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)

	var back := UIKit.text_button(Locale.t("final.back"))
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void:
		_flush_all()
		finished.emit("board"))
	row.add_child(back)

	_hint = UIKit.paragraph("", 12, UIKit.MUTED)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_hint)

	var submit := UIKit.primary_button(Locale.t("final.submit"))
	submit.custom_minimum_size = Vector2(300, 46)
	submit.pressed.connect(_on_submit)
	row.add_child(submit)
	return row


func _clear_hint() -> void:
	if _hint != null and CaseState.all_answered():
		_hint.text = ""


func _on_submit() -> void:
	# 提交之前把进行中的拖动全部结算，别让最后那一次调整只留在界面上。
	_flush_all()

	var missing := CaseState.unanswered_claims()
	if not missing.is_empty():
		_hint.text = Locale.tf("final.missing", [", ".join(missing)])
		_hint.add_theme_color_override("font_color", UIKit.J_SUSPICIOUS)
		var tween := create_tween()
		tween.tween_property(_hint, "modulate", Color(1.4, 1.15, 0.9, 1.0), 0.12)
		tween.tween_property(_hint, "modulate", Color.WHITE, 0.5)
		return

	# 对 current 做快照 + 记一次 FINAL_CONFIRMED。这里**不写任何答案** ——
	# 答案早在调查阶段就已经是玩家自己的了。
	if not CaseState.confirm_final():
		return
	finished.emit("debrief")
