class_name FinalPhase
extends CasePhase
## Final Judgment。四条 Claim 依次判断。
##
## 和开场那一问共用同一套判定控件和同一个滑条 —— 玩家在这里应该立刻感到
## "这只是刚才那件事，只不过现在我知道得多了一点"。
## 界面长得一模一样，是刻意的：变化发生在玩家脑子里，不在界面上。

var _rows := {}
var _hint: Label

func _build() -> void:
	var _c := scroll_column(860)
	_c.add_child(UIKit.gap(38))
	_c.add_child(UIKit.eyebrow("FINAL JUDGMENT"))
	_c.add_child(UIKit.gap(12))
	_c.add_child(UIKit.heading("Submit your reading of the record", 34))
	_c.add_child(UIKit.gap(16))
	_c.add_child(UIKit.rule(Color(UIKit.INK4.r, UIKit.INK4.g, UIKit.INK4.b, 0.9)))
	_c.add_child(UIKit.gap(18))
	_c.add_child(UIKit.paragraph(
		"Four claims, drawn from the same incident. Some of them the evidence can carry, and some of them it cannot. Judge each one on its own.",
		16, UIKit.FOG))
	_c.add_child(UIKit.gap(34))

	for claim in CaseData.claims(case):
		_c.add_child(_claim_block(claim))
		_c.add_child(UIKit.gap(24))

	_c.add_child(_footer())
	_c.add_child(UIKit.gap(48))
	stagger_fade(_c, 0.05)

func _claim_block(claim: Dictionary) -> Control:
	var id := str(claim.get("id", ""))
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
	var status := UIKit.meta("unanswered", 10, UIKit.MUTED, 1)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(status)
	box.add_child(head)

	box.add_child(UIKit.quote("“" + str(claim.get("text", "")) + "”", 20))

	var judgment := JudgmentRow.make(false, true)
	judgment.value = ""
	box.add_child(judgment)

	var confidence := confidence_row(50)
	box.add_child(confidence[0])

	box.add_child(UIKit.gap(4))
	box.add_child(UIKit.rule(Color(UIKit.INK3.r, UIKit.INK3.g, UIKit.INK3.b, 0.8)))

	# 听 value_changed 而不是 selected：selected 只在玩家点击时发，
	# 那么程序化回填的判定会让上面那行 "unanswered" 一直挂着。
	judgment.value_changed.connect(func(key: String) -> void:
		if key == "":
			status.text = "unanswered"
			status.add_theme_color_override("font_color", UIKit.MUTED)
		else:
			status.text = UIKit.judgment_label(key).to_upper()
			status.add_theme_color_override("font_color", UIKit.judgment_color(key)))

	_rows[id] = {"judgment": judgment, "confidence": confidence[1], "status": status}
	return box

func _footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)

	var back := UIKit.text_button("← Back to Investigation")
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void: finished.emit("board"))
	row.add_child(back)

	_hint = UIKit.paragraph("", 12, UIKit.MUTED)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_hint)

	var submit := UIKit.primary_button("Submit Investigation")
	submit.custom_minimum_size = Vector2(300, 46)
	submit.pressed.connect(_on_submit)
	row.add_child(submit)
	return row

func _on_submit() -> void:
	var missing: Array[String] = []
	for id in _rows:
		if _rows[id]["judgment"].value == "":
			missing.append(id)
	if not missing.is_empty():
		_hint.text = "Still unanswered: " + ", ".join(missing) + ". Every claim needs a reading, even if the reading is that the file cannot say."
		_hint.add_theme_color_override("font_color", UIKit.J_SUSPICIOUS)
		var tween := create_tween()
		tween.tween_property(_hint, "modulate", Color(1.4, 1.15, 0.9, 1.0), 0.12)
		tween.tween_property(_hint, "modulate", Color.WHITE, 0.5)
		return

	for id in _rows:
		var judgment: String = _rows[id]["judgment"].value
		var confidence: int = _rows[id]["confidence"].call()
		CaseState.set_final(id, judgment, confidence)
		CaseState.record_judgment(id, judgment, confidence, "Final")

	finished.emit("debrief")
