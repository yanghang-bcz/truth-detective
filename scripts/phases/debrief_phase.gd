class_name DebriefPhase
extends CasePhase
## Reasoning Debrief。
##
## 这一页刻意不做成"3 / 4 正确"。玩家在这里看到的应该是自己的判断轨迹 ——
## 一开始怎么想、哪条材料让它变了、最后停在哪儿。
##
## 判定对错依然存在，但它的呈现方式是"你的答案 vs 证据能支持的答案"并排，
## 而不是打勾打叉。差别很关键：前者是让你自己看出差在哪，后者只是给你一个分数。

func _build() -> void:
	var _c := scroll_column(900)
	_c.add_child(UIKit.gap(38))
	_c.add_child(UIKit.eyebrow("REASONING DEBRIEF"))
	_c.add_child(UIKit.gap(12))
	_c.add_child(UIKit.heading("How your reading changed", 34))
	_c.add_child(UIKit.gap(16))
	_c.add_child(UIKit.rule(Color(UIKit.INK4.r, UIKit.INK4.g, UIKit.INK4.b, 0.9)))
	_c.add_child(UIKit.gap(18))
	_c.add_child(UIKit.paragraph(str(case.get("debrief", {}).get("lede", "")), 16, UIKit.FOG))
	_c.add_child(UIKit.gap(26))

	_c.add_child(_stats_strip())
	_c.add_child(UIKit.gap(38))

	_c.add_child(section("YOUR JUDGMENT JOURNEY"))
	_c.add_child(UIKit.gap(20))
	_c.add_child(_journey())
	_c.add_child(UIKit.gap(40))

	_c.add_child(section("CLAIM REVIEW"))
	_c.add_child(UIKit.gap(20))
	for claim in CaseData.claims(case):
		_c.add_child(_claim_review(claim))
		_c.add_child(UIKit.gap(24))

	_c.add_child(UIKit.gap(16))
	_c.add_child(section("REASONING PATTERNS"))
	_c.add_child(UIKit.gap(20))
	_c.add_child(_patterns())
	_c.add_child(UIKit.gap(40))

	_c.add_child(_closing())
	_c.add_child(UIKit.gap(34))
	_c.add_child(_footer())
	_c.add_child(UIKit.gap(48))
	stagger_fade(_c, 0.04)

# ─────────────────────────────────────────────────────────────
## 一串行为读数。这一页不该只讲"你想得对不对"，也该让你看见"你做了什么"。
func _stats_strip() -> Control:
	var panel := UIKit.slot_panel(18)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 34)
	panel.add_child(row)

	var revisions := 0
	for entry in CaseState.history:
		if str(entry.get("trigger", "")) != "Initial":
			revisions += 1

	var entries := [
		["files opened", "%d / 8" % CaseState.unlocked.size()],
		["board revisions", str(revisions)],
		["analyst consults", str(CaseState.ai_calls)],
		["points spent", "%d / %d" % [CaseState.points_used, CaseState.points_total]],
	]
	for pair in entries:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.add_child(UIKit.meta(pair[0], 9, UIKit.MUTED, 2))
		cell.add_child(UIKit.label(pair[1], 20, UIKit.CHALK, UIKit.tracked(UIKit.font_mono(), 0)))
		row.add_child(cell)
	row.add_child(UIKit.fill(UIKit.hgap(0)))
	return panel

# ─────────────────────────────────────────────────────────────
## 判断轨迹。一条时间轴，每个节点记录"什么时候、哪条 Claim、改成了什么、把握多少"。
func _journey() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)

	var primary := str(case.get("claim_for_intro", "B"))
	var entries: Array = CaseState.journey(primary)
	if entries.is_empty():
		entries = CaseState.history
	if entries.is_empty():
		box.add_child(UIKit.paragraph("No judgments were recorded.", 14, UIKit.SLATE))
		return box

	# 时间轴只画主 Claim 那一条弧线。四条 Claim 的最终判定在下面的 Claim Review 里
	# 逐条并排对照，再在这里重复一遍，只会把"我是怎么改变主意的"这条线冲淡。
	var primary_claim := CaseData.claim(case, primary)
	box.add_child(UIKit.meta("claim %s · %s" % [primary, str(primary_claim.get("short", ""))], 10, UIKit.SLATE, 2))
	box.add_child(UIKit.gap(16))

	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)

		var spine := Spine.new()
		spine.custom_minimum_size = Vector2(24, 0)
		spine.size_flags_vertical = Control.SIZE_EXPAND_FILL
		spine.last = (i == entries.size() - 1)
		spine.dot_color = UIKit.judgment_color(str(entry.get("judgment", "")))
		spine.first = (i == 0)
		row.add_child(spine)

		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 7)
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(content)

		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		var trigger := UIKit.meta(str(entry.get("trigger", "")), 10, UIKit.SLATE, 2)
		trigger.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(trigger)
		# 一条两端渐隐的引线。没有它，左边的触发事件和右边的置信度读数是两个孤立的点，
		# 而有它，这一行才读得出"在某个时刻，我的把握是多少"。
		var leader := UIKit.rule(Color(UIKit.INK3.r, UIKit.INK3.g, UIKit.INK3.b, 0.9))
		leader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		leader.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(leader)
		var confidence := UIKit.label("%d%%" % int(entry.get("confidence", 0)), 15, UIKit.LAMP,
			UIKit.tracked(UIKit.font_mono(), 0))
		confidence.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(confidence)
		content.add_child(line)

		var second := HBoxContainer.new()
		second.add_theme_constant_override("separation", 8)
		second.add_child(verdict_pill(str(entry.get("judgment", ""))))
		second.add_child(UIKit.tag("CLAIM %s" % str(entry.get("claim", "")), UIKit.SLATE))
		content.add_child(second)

		content.add_child(UIKit.gap(14))
		box.add_child(row)

	# 其他 Claim 在调查过程中被改过几次，一句话带过。
	var others := {}
	for entry in CaseState.history:
		var claim_id := str(entry.get("claim", ""))
		if claim_id == primary or str(entry.get("trigger", "")) == "Final":
			continue
		others[claim_id] = int(others.get(claim_id, 0)) + 1
	if not others.is_empty():
		var parts: Array[String] = []
		for claim_id in others:
			parts.append("%s ×%d" % [claim_id, others[claim_id]])
		box.add_child(UIKit.gap(16))
		box.add_child(UIKit.paragraph("Also revised during the investigation: " + ", ".join(parts) + ". Those claims are compared in full below.", 12, UIKit.MUTED))
	return box

# ─────────────────────────────────────────────────────────────
## 一条 Claim 的并排复盘。
func _claim_review(claim: Dictionary) -> Control:
	var id := str(claim.get("id", ""))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var letter := UIKit.label(id, 17, UIKit.SLATE, UIKit.tracked(UIKit.font_mono(), 2))
	letter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(letter)
	var short := UIKit.meta(str(claim.get("short", "")), 10, UIKit.MUTED, 2)
	short.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(short)
	box.add_child(head)

	box.add_child(UIKit.quote("“" + str(claim.get("text", "")) + "”", 17, UIKit.FOG))

	var final: Dictionary = CaseState.final_judgments.get(id, {})
	var answer := str(final.get("judgment", ""))
	var correct := str(claim.get("verdict", ""))

	var compare := HBoxContainer.new()
	compare.add_theme_constant_override("separation", 28)
	compare.add_child(_compare_cell("your answer", answer, answer != ""))
	compare.add_child(_compare_cell("what the evidence supports", correct, true))
	box.add_child(compare)

	box.add_child(UIKit.paragraph(str(claim.get("explanation", "")), 14,
		Color(UIKit.FOG.r, UIKit.FOG.g, UIKit.FOG.b, 0.92)))

	var note := str(claim.get("note", ""))
	if note != "":
		box.add_child(UIKit.quote(note, 15, UIKit.MUTED))

	box.add_child(UIKit.gap(4))
	box.add_child(UIKit.rule(Color(UIKit.INK3.r, UIKit.INK3.g, UIKit.INK3.b, 0.7)))
	return box

func _compare_cell(caption: String, judgment: String, dim_if_empty: bool) -> Control:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 7)
	cell.add_child(UIKit.meta(caption, 10, UIKit.SLATE, 2))
	if judgment == "":
		cell.add_child(UIKit.tag("NO ANSWER", UIKit.MUTED))
	else:
		cell.add_child(verdict_pill(judgment, not dim_if_empty))
	return cell

# ─────────────────────────────────────────────────────────────
func _patterns() -> Control:
	var specs: Dictionary = case.get("debrief", {}).get("patterns", {})
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)

	var rows := [
		["context", CaseState.context_awareness()],
		["overgeneralisation", not CaseState.overgeneralised()],
		["premature", not CaseState.premature()],
	]
	for pair in rows:
		box.add_child(_pattern_row(str(pair[0]), bool(pair[1]), specs))
	return box

func _pattern_row(key: String, ok: bool, specs: Dictionary) -> Control:
	var spec: Dictionary = specs.get(key, {})
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var label := UIKit.meta(str(spec.get("label", key)), 11, UIKit.SLATE, 2)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(label)
	head.add_child(UIKit.fill(UIKit.hgap(0)))
	var color := UIKit.J_SUPPORTED if ok else UIKit.J_SUSPICIOUS
	var status := UIKit.meta("strong" if ok else "needs attention", 10, color, 2)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(status)
	box.add_child(head)

	box.add_child(meter(1.0 if ok else 0.24, color))
	box.add_child(UIKit.paragraph(str(spec.get("good" if ok else "weak", "")), 13,
		Color(UIKit.FOG.r, UIKit.FOG.g, UIKit.FOG.b, 0.9)))
	return box

# ─────────────────────────────────────────────────────────────
func _closing() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	box.add_child(UIKit.rule(Color(UIKit.LAMP_DIM.r, UIKit.LAMP_DIM.g, UIKit.LAMP_DIM.b, 0.55)))

	var text := UIKit.quote(str(case.get("debrief", {}).get("closing", "")), 24, UIKit.CHALK)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(text)

	var note := UIKit.meta(str(case.get("debrief", {}).get("closing_note", "")), 11, UIKit.SLATE, 2)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	return box

func _footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)

	var note := UIKit.paragraph("Case 001 ends here. The station is still outside.", 12, UIKit.MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(note)

	var back := UIKit.primary_button("Return to Stillwater Corner")
	back.custom_minimum_size = Vector2(340, 46)
	back.pressed.connect(func() -> void: finished.emit("close"))
	row.add_child(back)
	return row


# ─────────────────────────────────────────────────────────────
## 时间轴上的那根脊椎。自己画，因为一根线加上一个圆点不值得为它做一张贴图。
class Spine extends Control:
	var dot_color := UIKit.SLATE
	var first := false
	var last := false

	func _draw() -> void:
		var x := size.x * 0.5
		var top := 10.0
		var line_color := Color(UIKit.MUTED.r, UIKit.MUTED.g, UIKit.MUTED.b, 0.70)
		if first:
			# 第一个节点只往下连，上面不接 —— 故事从这里开始。
			draw_line(Vector2(x, top), Vector2(x, size.y), line_color, 1.0)
		elif last:
			# 最后一个节点只往上连。
			draw_line(Vector2(x, 0.0), Vector2(x, top), line_color, 1.0)
		else:
			draw_line(Vector2(x, 0.0), Vector2(x, size.y), line_color, 1.0)
		draw_circle(Vector2(x, top), 4.0, dot_color)
		draw_arc(Vector2(x, top), 4.0, 0.0, TAU, 32, Color(0, 0, 0, 0.55), 2.0, true)
