class_name DebriefPhase
extends CasePhase
## Reasoning Debrief（v0.3 重构）。
##
## v0.2 的问题不是不好看，而是**玩家读完不知道自己错在哪**：
## 它把每一条都盖上一个 STRONG，包括答错的那两条。三轮真机测试里，不同玩家的
## 复盘几乎一模一样，因为那几行评价是固定的，跟玩家选了什么毫无关系。
##
## v0.3 分三块：
##
##   Part A · Judgment Review
##     逐条对照"你的答案"与"案件参考判断"，明确写出 Aligned / Not Aligned。
##     评价对象只有一个：判断是否落在参考范围内。不是智商、不是批判性思维。
##
##   Part B · What You Can Learn
##     确定性反馈（不用 LLM 现场编）：按玩家实际选错的那个选项，取一条预先写好、
##     经过人工审核的说明。答错的选项不同，读到的解释就不同。
##
##   Part C · Your Investigation
##     只陈述发生过的行为：开过几份档案、改过几次判、调过几次把握、问过几次分析员。
##     全部来自事件记录，不再出现 STRONG / WEAK 这类能力等级 ——
##     单局行为撑不起"你是一个怎样的思考者"这种结论。
##
## 本轮**取消**：Context Awareness / Overgeneralisation / Premature Judgment /
## AI Collaboration 四个能力评级。它们此前是固定的，与玩家实际表现无关。

## Part B 默认最多展开几张反馈卡。错误多于两张时，剩下的折起来 ——
## 一次给四个"你错了"的解释，玩家一个都记不住。
const FEEDBACK_PRIMARY := 2


func _build() -> void:
	var c := scroll_column(900)
	c.add_child(UIKit.gap(38))
	c.add_child(UIKit.eyebrow(Locale.t("phase.debrief")))
	c.add_child(UIKit.gap(12))
	c.add_child(UIKit.heading(str(case.get("debrief", {}).get("title", Locale.t("debrief.title"))), 34))
	c.add_child(UIKit.gap(16))
	c.add_child(UIKit.rule(Color(UIKit.INK4.r, UIKit.INK4.g, UIKit.INK4.b, 0.9)))
	c.add_child(UIKit.gap(18))
	c.add_child(UIKit.paragraph(str(case.get("debrief", {}).get("lede", "")), 16, UIKit.FOG))
	c.add_child(UIKit.gap(34))

	c.add_child(_part_a())
	c.add_child(UIKit.gap(46))
	c.add_child(_part_b())
	c.add_child(UIKit.gap(46))
	c.add_child(_part_c())
	c.add_child(UIKit.gap(40))

	c.add_child(_closing())
	c.add_child(UIKit.gap(34))
	c.add_child(_footer())
	c.add_child(UIKit.gap(48))
	stagger_fade(c, 0.04)


# ─────────────────────────────────────────────────────────────
#  Part A · Judgment Review
# ─────────────────────────────────────────────────────────────
func _part_a() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)

	var tally: Array = CaseData.alignment_tally(case, CaseState.final_judgments)
	var hit := int(tally[0])
	var total := int(tally[1])

	box.add_child(section(Locale.t("debrief.part_a")))
	box.add_child(UIKit.gap(22))
	box.add_child(_tally_strip(hit, total))
	box.add_child(UIKit.gap(14))
	box.add_child(UIKit.paragraph(Locale.t("debrief.aligned_note"), 11, UIKit.MUTED))
	box.add_child(UIKit.gap(30))

	for claim in CaseData.claims(case):
		box.add_child(_claim_review(claim))
		box.add_child(UIKit.gap(26))
	return box


## 顶部那行 "2 / 4"。刻意不做成百分比 —— 百分比会立刻被读成分数，
## 而这一页要说的恰恰是"这不是分数"。
func _tally_strip(hit: int, total: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var color := UIKit.J_SUPPORTED if hit == total else UIKit.LAMP
	var number := UIKit.label("%d / %d" % [hit, total], 40, color,
		UIKit.tracked(UIKit.font_mono(), 1))
	number.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(number)

	var caption := UIKit.meta(Locale.t("debrief.aligned_caption"), 11, UIKit.SLATE, 2)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# 这里**不能**开 autowrap。开了之后它的最小宽度会塌到"最长的一个词"，
	# 而右边那个 fill 弹簧会立刻把余量全部吃掉 —— 结果就是这句话被拆成
	# 一个字一行、竖着排下来（中英都中招）。meta() 本来就不折行，
	# 说明文字也够短，内容列 860px 放得下，保持不折行即可。
	row.add_child(caption)
	row.add_child(UIKit.fill(UIKit.hgap(0)))
	return row


## 一条 Claim 的并排复盘。
func _claim_review(claim: Dictionary) -> Control:
	var id := str(claim.get("id", ""))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)

	var answer := CaseState.final_judgment(id)
	var aligned := CaseData.is_aligned(claim, answer)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var letter := UIKit.label(id, 17, UIKit.SLATE, UIKit.tracked(UIKit.font_mono(), 2))
	letter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(letter)
	var short := UIKit.meta(str(claim.get("short", "")), 10, UIKit.MUTED, 2)
	short.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(short)
	head.add_child(UIKit.fill(UIKit.hgap(0)))

	var result_color := UIKit.J_SUPPORTED if aligned else UIKit.J_SUSPICIOUS
	var result := UIKit.meta(Locale.t("debrief.aligned") if aligned else Locale.t("debrief.not_aligned"),
		10, result_color, 2)
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(result)
	box.add_child(head)

	box.add_child(UIKit.quote("“" + str(claim.get("text", "")) + "”", 17, UIKit.FOG))

	# 你的答案 / 案件参考判断。参考一侧可能接受不止一种答案，用 · 连起来展示，
	# 免得出现「你的答案：证据不足 / 参考：不成立 / 结果：错」这种看起来自相矛盾的呈现。
	var reference := CaseData.accepted_verdicts(claim)
	var compare := HBoxContainer.new()
	compare.add_theme_constant_override("separation", 28)
	compare.add_child(_compare_cell(Locale.t("debrief.your_answer"), [answer]))
	compare.add_child(_compare_cell(Locale.t("debrief.case_reference"), reference))
	box.add_child(compare)

	# Unsupported 不等于"已证明为假"。参考标签旁边给一句释义，避免误读。
	var gloss := CaseData.verdict_gloss(case, str(claim.get("verdict", "")))
	if gloss != "":
		box.add_child(UIKit.paragraph(gloss, 11, UIKit.MUTED))

	box.add_child(UIKit.paragraph(str(claim.get("explanation", "")), 14,
		Color(UIKit.FOG.r, UIKit.FOG.g, UIKit.FOG.b, 0.92)))

	var note := str(claim.get("note", ""))
	if note != "":
		box.add_child(UIKit.quote(note, 15, UIKit.MUTED))

	# 猜中了但没看关键证据：如实说出来，但不评价（§9.6）。
	var unseen := CaseData.feedback_aligned_unseen(case, id, CaseState.unlocked)
	if aligned and unseen != "":
		box.add_child(_aside(unseen, UIKit.LAMP_DIM))

	box.add_child(UIKit.gap(4))
	box.add_child(UIKit.rule(Color(UIKit.INK3.r, UIKit.INK3.g, UIKit.INK3.b, 0.7)))
	return box


## 一格对照。"你的判断"和"案件参考判断"用的是同一种色块 ——
## 参考一侧可能接受不止一种答案，所以它也可能并排出现两个。
func _compare_cell(caption: String, keys: Array) -> Control:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 7)
	cell.add_child(UIKit.meta(caption, 10, UIKit.SLATE, 2))
	var shown := 0
	for k in keys:
		if str(k) != "":
			shown += 1
	if shown == 0:
		cell.add_child(UIKit.tag(Locale.t("debrief.no_answer"), UIKit.MUTED))
		return cell
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for k in keys:
		if str(k) != "":
			row.add_child(verdict_pill(str(k)))
	cell.add_child(row)
	return cell


## 一句旁注：左侧一道暖色竖线，和正文区分开。
func _aside(text: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var bar := ColorRect.new()
	bar.color = color
	bar.custom_minimum_size = Vector2(2, 0)
	bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	var body := UIKit.paragraph(text, 12, Color(UIKit.FOG.r, UIKit.FOG.g, UIKit.FOG.b, 0.9))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(body)
	return row


# ─────────────────────────────────────────────────────────────
#  Part B · What You Can Learn
# ─────────────────────────────────────────────────────────────
func _part_b() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)

	box.add_child(section(Locale.t("debrief.part_b")))
	box.add_child(UIKit.gap(20))

	var wrong: Array[Dictionary] = []
	var aligned_count := 0
	for claim in CaseData.claims(case):
		var id := str(claim.get("id", ""))
		var answer := CaseState.final_judgment(id)
		if CaseData.is_aligned(claim, answer):
			aligned_count += 1
			continue
		var fb := CaseData.feedback_for(case, id, answer)
		wrong.append({"claim": claim, "answer": answer, "feedback": fb})
	if aligned_count == int(CaseData.alignment_tally(case, CaseState.final_judgments)[1]):
		wrong.clear()

	if wrong.is_empty():
		# 全部一致时**不要制造不存在的错误**。只给证据边界总结。
		var text := CaseData.feedback_all_aligned(case)
		if text != "":
			box.add_child(UIKit.paragraph(text, 14, UIKit.FOG))
		return box

	var folded := VBoxContainer.new()
	folded.add_theme_constant_override("separation", 26)
	folded.visible = false
	var toggle: Button = null

	for i in range(wrong.size()):
		var card := _feedback_card(wrong[i]["claim"], str(wrong[i]["answer"]), wrong[i]["feedback"])
		if i < FEEDBACK_PRIMARY:
			box.add_child(card)
			if i < FEEDBACK_PRIMARY - 1 and i < wrong.size() - 1:
				box.add_child(UIKit.gap(26))
		else:
			folded.add_child(card)

	if wrong.size() > FEEDBACK_PRIMARY:
		box.add_child(UIKit.gap(20))
		toggle = UIKit.text_button(Locale.tf("debrief.show_all", [wrong.size()]))
		toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		toggle.pressed.connect(func() -> void:
			folded.visible = not folded.visible
			toggle.text = Locale.t("debrief.show_less") if folded.visible \
				else Locale.tf("debrief.show_all", [wrong.size()]))
		box.add_child(toggle)

	box.add_child(folded)
	return box


## 一张针对"选错的那一项"的说明卡。
## 文案全部来自案件数据，不由模型现场生成 —— 让 LLM 自由点评玩家的推理，
## 恰恰是这一轮要消除的东西。
func _feedback_card(claim: Dictionary, answer: String, feedback: Dictionary) -> Control:
	var id := str(claim.get("id", ""))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(UIKit.label(id, 15, UIKit.LAMP, UIKit.tracked(UIKit.font_mono(), 2)))
	var short := UIKit.meta(str(claim.get("short", "")), 10, UIKit.MUTED, 2)
	short.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(short)
	head.add_child(UIKit.fill(UIKit.hgap(0)))
	if answer != "":
		head.add_child(verdict_pill(answer))
	box.add_child(head)

	var text := str(feedback.get("text", ""))
	if text == "":
		# 没有预先审核过的说明时，宁可只给出案件自己的解释，也不要套一段通用模板。
		text = str(claim.get("explanation", ""))
	box.add_child(UIKit.paragraph(text, 14, Color(UIKit.FOG.r, UIKit.FOG.g, UIKit.FOG.b, 0.94)))

	var training := str(feedback.get("training", ""))
	if training != "":
		box.add_child(_aside(Locale.t("debrief.training") + training, UIKit.LAMP_DIM))
	return box


# ─────────────────────────────────────────────────────────────
#  Part C · Your Investigation
# ─────────────────────────────────────────────────────────────
func _part_c() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)

	box.add_child(section(Locale.t("debrief.part_c")))
	box.add_child(UIKit.gap(20))
	box.add_child(_stats())

	# 中性观察：只陈述发生过什么，不解释它说明了玩家的什么能力。
	var observations := _observations()
	if not observations.is_empty():
		box.add_child(UIKit.gap(22))
		for line in observations:
			box.add_child(_bullet(line))
			box.add_child(UIKit.gap(8))

	box.add_child(UIKit.gap(34))
	box.add_child(section(Locale.t("debrief.journey")))
	box.add_child(UIKit.gap(20))
	box.add_child(_journey())
	return box


func _stats() -> Control:
	var panel := UIKit.slot_panel(18)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	panel.add_child(row)

	var unlocked_total := int(case.get("evidence", []).size())
	var entries := [
		[Locale.t("debrief.files"), "%d / %d" % [CaseState.unlocked.size(), unlocked_total]],
		# 只数真正的改判：首次作答、清空、调把握、最终确认都不算。
		[Locale.t("debrief.revisions"), str(CaseState.revision_count())],
		[Locale.t("debrief.confidence_changes"), str(CaseState.confidence_adjustment_count())],
		[Locale.t("debrief.consults"), str(CaseState.ai_calls)],
		[Locale.t("debrief.points"), "%d / %d" % [CaseState.points_used, CaseState.points_total]],
	]
	for pair in entries:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.add_child(UIKit.meta(pair[0], 9, UIKit.MUTED, 2))
		cell.add_child(UIKit.label(pair[1], 20, UIKit.CHALK, UIKit.tracked(UIKit.font_mono(), 0)))
		row.add_child(cell)
	row.add_child(UIKit.fill(UIKit.hgap(0)))
	return panel


## 行为观察。措辞严格限制在"发生了什么"：
## 可以说"你在 E04 可用之后改了 B"，**不能**说"你的信念更新能力很强"——
## 时间上先后发生，不足以证明因果，也撑不起能力判断。
func _observations() -> Array[String]:
	var out: Array[String] = []
	for claim in CaseData.claims(case):
		var id := str(claim.get("id", ""))
		if CaseState.current_judgment(id) == "":
			out.append(Locale.tf("debrief.obs_unanswered", [id]))
	for card in CaseState.unlocked_evidence():
		var eid := str(card.get("id", ""))
		for cid in CaseState.revised_after(eid):
			out.append(Locale.tf("debrief.obs_revised",
				["#%02d" % CaseState.evidence_number(eid), cid]))
		if out.size() >= 4:
			break
	if CaseState.ai_calls == 0:
		out.append(Locale.t("debrief.ai_none"))
	elif CaseState.ai_uses().is_empty():
		# 没配 key 时每一次咨询都来自离线引擎。把这一节说成"AI 协作"是不诚实的。
		out.append(Locale.t("debrief.ai_offline_only"))
	return out


func _bullet(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var tick := UIKit.meta("—", 11, UIKit.MUTED, 1)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tick)
	var body := UIKit.paragraph(text, 12, Color(UIKit.FOG.r, UIKit.FOG.g, UIKit.FOG.b, 0.88))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(body)
	return row


# ─────────────────────────────────────────────────────────────
## 判断轨迹。一条时间轴，每个节点记录"什么时候、哪条 Claim、改成了什么、把握多少"。
## 只画主 Claim 那条弧线 —— 四条 Claim 的最终判定在 Part A 已经逐条并排对照过，
## 在这里再重复一遍只会把"我是怎么改变主意的"这条线冲淡。
func _journey() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)

	var primary := str(case.get("claim_for_intro", "B"))
	var entries: Array = CaseState.journey(primary)
	if entries.is_empty():
		entries = CaseState.journey()
	if entries.is_empty():
		box.add_child(UIKit.paragraph(Locale.t("debrief.no_journey"), 14, UIKit.SLATE))
		return box

	var primary_claim := CaseData.claim(case, primary)
	box.add_child(UIKit.meta(Locale.tf("debrief.claim_of",
		[primary, str(primary_claim.get("short", ""))]), 10, UIKit.SLATE, 2))
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
		var trigger := UIKit.meta(_trigger_text(str(entry.get("trigger", ""))), 10, UIKit.SLATE, 2)
		trigger.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(trigger)
		# 一条两端渐隐的引线。没有它，左边的触发事件和右边的把握读数是两个孤立的点，
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
		var judgment := str(entry.get("judgment", ""))
		if judgment == "":
			second.add_child(UIKit.tag(Locale.t("debrief.no_answer"), UIKit.MUTED))
		else:
			second.add_child(verdict_pill(judgment))
		second.add_child(UIKit.tag(Locale.tf("debrief.claim_of",
			[str(entry.get("claim", "")), str(CaseData.claim(case, str(entry.get("claim", ""))).get("short", ""))]), UIKit.SLATE))
		content.add_child(second)

		content.add_child(UIKit.gap(14))
		box.add_child(row)
	return box


## 历史里存的是触发事件的"键"（initial / final / analyst / evidence:Exx），
## 不是给人看的文字 —— 否则切一次语言，整条时间轴都会留在旧语言里。
func _trigger_text(raw: String) -> String:
	if raw.begins_with("evidence:"):
		return Locale.tf("trigger.evidence", [raw.substr(9)])
	match raw:
		"initial": return Locale.t("trigger.initial")
		"final": return Locale.t("trigger.final")
		"analyst": return Locale.t("trigger.analyst")
		_: return Locale.t("trigger.revised")


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

	# 页脚兼作一句免责声明：这个世界里的人和账号都是编的。
	# 放在最后、压到最暗 —— 它是必要的，但不该被当成一句台词。
	var note := UIKit.paragraph("%s  %s" % [Locale.t("debrief.footer"),
		str(case.get("fiction_notice", ""))], 12, UIKit.MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(note)

	var back := UIKit.primary_button(Locale.t("debrief.return"))
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
