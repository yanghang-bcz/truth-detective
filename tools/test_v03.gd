extends Node
## v0.3 验收测试。对应 V0.3 需求里此前**没有任何自动化覆盖**的四块：
##
##   [conf]    Confidence 必须能被真实鼠标点击/拖动改变，且一次拖动只记一条事件
##   [state]   判定状态继承链：initial / current / final 三者不许互相顶替
##   [lang]    切换语言不许丢草稿、初判、当前判断、把握、事件历史
##   [events]  事件历史的计数、顺序、前后值、证据快照
##   [debrief] 四种玩家情形下**实际渲染出来的文字**（不是评分函数的返回值）
##   [ai]      AI 咨询在"提问时刻"打快照，等待期间玩家改答案不许污染记录
##
## 为什么必须用场景方式跑（res://tools/test_v03.tscn）：
## --script 模式不注册 autoload，而这一整层围着 CaseState / Locale / AiCoach 转。
##
## 为什么 Confidence 要喂真实事件而不是直接赋值 slider.value：
##   v0.2 的两个 bug（尺寸被清零、一次拖动记成几十次）都**只在真实交互路径上**出现。
##   `slider.value = 80` 会绕过 _gui_input、绕过 _set_from_x、绕过 committed ——
##   那样测出来的"通过"跟玩家实际能不能拖动毫无关系。

var _passes := 0
var _fails := 0

## 假 client 的信箱。用 Dictionary 而不是 lambda 捕获：lambda 按值捕获，改不了外面的变量。
var _box := {"reply": {"ok": true, "text": "", "code": ""}, "sink": Callable()}


func _ready() -> void:
	call_deferred("run")


func _check(ok: bool, msg: String) -> void:
	if ok:
		_passes += 1
		print("PASS ", msg)
	else:
		_fails += 1
		print("FAIL ", msg)


func _note(msg: String) -> void:
	print("NOTE ", msg)


func _eq(got: Variant, want: Variant, msg: String) -> void:
	_check(got == want, "%s（期望 %s，实际 %s）" % [msg, str(want), str(got)])


# ─────────────────────────────────────────────────────────────
func run() -> void:
	Locale.set_lang("en")
	await get_tree().process_frame

	await _pick_input_route()

	# 全都是协程（里面有 await），**逐个 await**。
	# 漏掉任何一个，它就会挂起在第一个 await 上，而 run() 继续往下跑 ——
	# 等它恢复时 CaseState 已经被后面的用例重置过好几轮，
	# 断言读到的就是别人的状态。这种假失败看起来像产品 bug，其实是用例写错。
	await test_confidence_real_drag()
	await test_confidence_interrupted_drag()
	await test_state_inheritance()
	await test_language_switch_keeps_state()
	await test_event_history()
	await test_debrief_four_players()
	await test_ai_snapshot_at_request()

	print("V03_TESTS %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


# ─────────────────────────────────────────────────────────────
#  [conf] 真实鼠标交互
# ─────────────────────────────────────────────────────────────
## 投递路径。理想是 push_input —— 走 Godot 自己的 GUI 命中测试与派发。
## 但 headless 下没有真实操作系统鼠标，viewport 的 GUI 命中往往收不到合成事件。
## 收不到就退回直接调用 _gui_input：那**仍然走真实的拖拽代码路径**
## （_set_from_x 的位置→数值换算、_drag_origin 的起始值、_dragging 状态、committed 分批），
## 只是绕过了"这个点落在哪个控件上"这一步 —— 那一步由浏览器端到端验收覆盖。
var _route_via_viewport := true


## 先探测一次：headless 里 viewport 派发到底通不通。用一个一次性的滑条测，别弄脏真用例。
func _pick_input_route() -> void:
	var probe := _make_slider()
	await get_tree().process_frame
	var before := probe.value
	_dispatch(probe, "button", Vector2(200, 15), true)
	await get_tree().process_frame
	_route_via_viewport = probe.value != before
	_dispatch(probe, "button", Vector2(200, 15), false)
	probe.get_parent().queue_free()
	await get_tree().process_frame
	if not _route_via_viewport:
		_note("[conf] headless 收不到 viewport 合成鼠标；改走 _gui_input 直投（同一套拖拽代码路径）")


## 造一个真实事件并投递。`local` 是相对滑条左上角的坐标 ——
## 走 viewport 时换算成全局坐标（命中测试要的是全局），直投时就是控件局部坐标。
func _dispatch(slider: Control, kind: String, local: Vector2, pressed: bool = true) -> void:
	var ev: InputEvent
	if kind == "button":
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = pressed
		ev = b
	else:
		var m := InputEventMouseMotion.new()
		m.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		ev = m
	ev.global_position = slider.global_position + local
	ev.position = (slider.global_position + local) if _route_via_viewport else local
	if _route_via_viewport:
		get_viewport().push_input(ev)
	else:
		slider._gui_input(ev)


func _make_slider() -> ConfidenceSlider:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.position = Vector2(20, 20)
	holder.size = Vector2(400, 60)
	add_child(holder)

	var s := ConfidenceSlider.new()
	s.custom_minimum_size = Vector2(200, 30)
	s.position = Vector2(0, 10)
	s.size = Vector2(300, 30)
	holder.add_child(s)
	return s


func test_confidence_real_drag() -> void:
	_note("[conf] 真实鼠标拖动（viewport 命中测试 → _gui_input），三个界面共用同一个控件")
	CaseState.start()
	var claim := "B"
	var s := _make_slider()
	await get_tree().process_frame

	# 尺寸没有被 _ready 打回 0 —— v0.2 的滑条正是坏在这里，5px 宽根本点不到。
	_check(s.size.x >= 200.0, "[conf] 滑条渲染宽度正常（>=200，实际 %d）" % int(s.size.x))

	# 接线照抄 board_phase / final_phase：changed 实时写状态，committed 结算一次
	var committed: Array = []
	s.changed.connect(func(v: int) -> void: CaseState.set_confidence(claim, v))
	s.committed.connect(func(v: int, prev: int) -> void:
		committed.append([v, prev])
		CaseState.commit_confidence(claim, prev))

	var base := Vector2.ZERO
	_dispatch(s, "button", base + Vector2(100, 15), true)     # 按下（≈33%）
	await get_tree().process_frame
	_dispatch(s, "motion", base + Vector2(200, 15), true)     # 拖动中（≈67%）
	await get_tree().process_frame
	var mid_events := CaseState.confidence_adjustment_count(claim)
	_dispatch(s, "motion", base + Vector2(250, 15), true)     # 拖到目标（≈85%）
	await get_tree().process_frame
	_dispatch(s, "button", base + Vector2(250, 15), false)    # 松手
	await get_tree().process_frame

	_check(s.value > 50, "[conf] 拖动后滑条值真的变了（= %d）" % s.value)
	_check(not committed.is_empty(), "[conf] 松手产生了一次 committed 结算")
	_check(CaseState.current_confidence(claim) == s.value,
		"[conf] 当前状态与界面一致（state=%d ui=%d）" % [CaseState.current_confidence(claim), s.value])
	_eq(mid_events, 0, "[conf] 拖动过程中**不**记事件")
	_eq(CaseState.confidence_adjustment_count(claim), 1,
		"[conf] 一次拖动只记 1 条 CONFIDENCE_ADJUSTED")
	if not committed.is_empty():
		_eq(int(committed[0][1]), 50, "[conf] 结算带上了拖动开始前的值")

	# 离开页面再回来（新建控件）→ 用状态里的值回填，不该回落到 50
	var again := _make_slider()
	await get_tree().process_frame
	_eq(again.value, 50, "[conf] 新控件的默认值就是 50（对照用）")
	again.value = CaseState.current_confidence(claim)
	_eq(again.value, s.value, "[conf] 重进页面回显保存过的把握")
	_check(again.value != 50, "[conf] 回显值不是默认的 50（v0.2 的「切页回落 50%」不复现）")

	s.get_parent().queue_free()
	again.get_parent().queue_free()


func test_confidence_interrupted_drag() -> void:
	_note("[conf] 拖动被中途打断（没松手就切 Claim / 离开页面）")
	CaseState.start()
	var s := _make_slider()
	await get_tree().process_frame

	s.changed.connect(func(v: int) -> void: CaseState.set_confidence("B", v))
	s.committed.connect(func(_v: int, prev: int) -> void: CaseState.commit_confidence("B", prev))

	var base := Vector2.ZERO
	_dispatch(s, "button", base + Vector2(100, 15), true)
	await get_tree().process_frame
	_dispatch(s, "motion", base + Vector2(200, 15), true)
	await get_tree().process_frame

	# 不松手，直接结算 —— 真实场景里"切 Claim / 离开页面"就是这么做的
	s.commit_pending()
	await get_tree().process_frame
	_eq(CaseState.confidence_adjustment_count("B"), 1,
		"[conf] 被打断的拖动也会结算，不留「显示变了、事件没有」的缺口")
	_eq(CaseState.current_confidence("B"), s.value, "[conf] 被打断后状态仍是界面显示的值")

	s.commit_pending()
	_eq(CaseState.confidence_adjustment_count("B"), 1, "[conf] 重复 commit_pending 不重复记账")
	s.get_parent().queue_free()


# ─────────────────────────────────────────────────────────────
#  [state] 判定状态继承链
# ─────────────────────────────────────────────────────────────
func test_state_inheritance() -> void:
	_note("[state] 初判 → 改判 → 切走 → 切回 → Final Review → 回调查 → 再进 Final Review → 提交")
	CaseState.start()

	CaseState.confirm_initial("B", "supported", 80)
	_eq(CaseState.current_judgment("B"), "supported", "[state] 初判写进了 current")
	_eq(CaseState.current_confidence("B"), 80, "[state] 初判的把握写进了 current")

	CaseState.select_judgment("B", "unsupported", -1, "evidence:E04")
	_eq(CaseState.current_judgment("B"), "unsupported", "[state] 调查阶段改判生效")
	_eq(CaseState.current_confidence("B"), 80, "[state] 只改判定时把握被继承下来（仍是 80）")

	# 切到别的 Claim 再切回来：状态不该被"页面重建"影响
	CaseState.select_judgment("A", "supported", 70, "revised")
	_eq(CaseState.current_judgment("B"), "unsupported", "[state] 操作 A 不影响 B")
	_eq(CaseState.current_confidence("B"), 80, "[state] 操作 A 不影响 B 的把握")
	_eq(CaseState.current_judgment("A"), "supported", "[state] A 的首次作答已记录")
	_eq(CaseState.current_confidence("A"), 70, "[state] A 的把握已记录")

	# 四条答完才允许确认
	_eq(CaseState.all_answered(), false, "[state] 还有未作答时 all_answered 为假")
	_eq(CaseState.confirm_final(), false, "[state] 未答完不允许确认终判")
	CaseState.select_judgment("C", "insufficient", 60, "revised")
	CaseState.select_judgment("D", "unsupported", 55, "revised")
	_eq(CaseState.all_answered(), true, "[state] 四条齐了")

	_eq(CaseState.final_judgments.size(), 0, "[state] 点确认之前 final 是空的（日常操作不写它）")
	_eq(CaseState.confirm_final(), true, "[state] 可以确认终判")
	eq_snapshot_matches_current()

	# 确认之后日常操作**不许**再动 final_judgments
	var frozen := CaseState.final_judgment("B")
	CaseState.select_judgment("B", "suspicious", 20, "revised")
	_eq(CaseState.final_judgment("B"), frozen, "[state] 终判之后改 current 不会污染 final 快照")
	_eq(CaseState.current_judgment("B"), "suspicious", "[state] current 仍然跟着玩家走")

	# 重开案件必须清干净
	CaseState.start()
	_eq(CaseState.current_judgment("B"), "", "[state] 重开后 current 清空")
	_eq(CaseState.final_judgment("B"), "", "[state] 重开后 final 清空")
	_eq(CaseState.initial_judgments.size(), 0, "[state] 重开后 initial 清空")
	_eq(CaseState.events.size(), 0, "[state] 重开后事件历史清空")
	_eq(str(CaseState.intro_draft.get("judgment", "")), "", "[state] 重开后开场草稿清空")


func eq_snapshot_matches_current() -> void:
	var ok := true
	for cid in ["A", "B", "C", "D"]:
		if CaseState.final_judgment(cid) != CaseState.current_judgment(cid):
			ok = false
		if CaseState.final_confidence(cid) != CaseState.current_confidence(cid):
			ok = false
	_check(ok, "[state] final 快照与 current 逐条一致（含把握）")


# ─────────────────────────────────────────────────────────────
#  [lang] 切语言不丢状态
# ─────────────────────────────────────────────────────────────
func test_language_switch_keeps_state() -> void:
	_note("[lang] 中英切换不丢草稿 / 初判 / 当前判断 / 把握 / 事件 / 调查进度")

	# ── 阶段 1：Intro 草稿（选了但**还没点「开始调查」**）
	#  这是最容易坏的一处：切语言会重建开场页，读错来源就等于替玩家提交了初判。
	CaseState.start()
	CaseState.unlock("E01")
	CaseState.intro_draft["judgment"] = "suspicious"
	CaseState.intro_draft["confidence"] = 42
	for lang in ["zh", "en", "zh"]:
		Locale.set_lang(lang)
		CaseState.reload_for_language()
		await get_tree().process_frame
		_eq(str(CaseState.intro_draft.get("judgment", "")), "suspicious",
			"[lang] 切到 %s 后未提交的开场草稿还在" % lang)
		_eq(int(CaseState.intro_draft.get("confidence", 0)), 42,
			"[lang] 切到 %s 后草稿里的把握还在" % lang)
		_eq(CaseState.initial_judgments.size(), 0,
			"[lang] 切到 %s 不会替玩家提交初判" % lang)
		_eq(CaseState.current_judgment("B"), "",
			"[lang] 切到 %s 不会把草稿写进当前判断" % lang)

	# ── 阶段 2：已提交的初判 + 调查阶段的当前判断
	CaseState.confirm_initial("B", "supported", 80)
	CaseState.select_judgment("B", "unsupported", -1, "evidence:E04")
	CaseState.select_judgment("A", "supported", 70, "revised")
	CaseState.mark_opened("E01")

	var events_before := CaseState.events.size()
	var points_before := CaseState.points_used
	var unlocked_before := CaseState.unlocked.size()
	var opened_before := CaseState.opened.size()

	for lang in ["zh", "en", "zh"]:
		Locale.set_lang(lang)
		CaseState.reload_for_language()
		await get_tree().process_frame

		_eq(str(CaseState.initial_judgments.get("B", {}).get("judgment", "")), "supported",
			"[lang] 切到 %s 后已提交的初判还在" % lang)
		_eq(CaseState.current_judgment("B"), "unsupported", "[lang] 切到 %s 后当前判断还在" % lang)
		_eq(CaseState.current_confidence("B"), 80, "[lang] 切到 %s 后把握还在" % lang)
		_eq(CaseState.current_judgment("A"), "supported", "[lang] 切到 %s 后 A 的判断还在" % lang)
		_eq(CaseState.current_confidence("A"), 70, "[lang] 切到 %s 后 A 的把握还在" % lang)
		_eq(CaseState.events.size(), events_before, "[lang] 切到 %s 后事件条数不变" % lang)
		_eq(CaseState.points_used, points_before, "[lang] 切到 %s 后已花调查点不变" % lang)
		_eq(CaseState.unlocked.size(), unlocked_before, "[lang] 切到 %s 后已解档案不变" % lang)
		_eq(CaseState.opened.size(), opened_before, "[lang] 切到 %s 后已开启档案不变" % lang)
		_check(not CaseState.data.is_empty(), "[lang] 切到 %s 后案件数据仍可读" % lang)

	# 内容确实换了语言（否则"没丢"可能只是因为它压根没切）
	Locale.set_lang("zh")
	CaseState.reload_for_language()
	var zh_title := str(CaseState.data.get("title", ""))
	Locale.set_lang("en")
	CaseState.reload_for_language()
	var en_title := str(CaseState.data.get("title", ""))
	_check(zh_title != "" and en_title != "" and zh_title != en_title,
		"[lang] 两种语言的案件内容确实不同（zh=「%s」／en=「%s」）" % [zh_title, en_title])
	_eq(CaseState.current_judgment("B"), "unsupported", "[lang] 换完内容后判断仍在")
	_eq(CaseState.current_confidence("B"), 80, "[lang] 换完内容后把握仍在")


# ─────────────────────────────────────────────────────────────
#  [events] 事件历史
# ─────────────────────────────────────────────────────────────
func test_event_history() -> void:
	_note("[events] 按指定操作序列核对计数 / 顺序 / 前后值 / 证据快照")
	CaseState.start()
	CaseState.unlock("E01")

	# 序列：初判 B=Supported/80
	CaseState.confirm_initial("B", "supported", 80)
	_eq(CaseState.events.size(), 1, "[events] 初判记 1 条事件")
	_eq(str(CaseState.events[0]["event_type"]), "INITIAL_CONFIRMED", "[events] 初判事件类型正确")
	_eq(int(CaseState.events[0]["previous_confidence"]), 50, "[events] 初判带上了改之前的值")

	# 证据快照必须是**深拷贝**：之后解锁新证据不许改到这条历史
	CaseState.unlock("E02")
	_eq((CaseState.events[0]["unlocked_evidence_ids"] as Array).size(), 1,
		"[events] 历史里的证据快照是深拷贝，不会被后来的解锁改掉")

	# 调查 B=Unsupported/80
	CaseState.select_judgment("B", "unsupported", -1, "evidence:E04")
	_eq(str(CaseState.events[-1]["event_type"]), "JUDGMENT_REVISED", "[events] 真改判记成 REVISED")
	_eq(str(CaseState.events[-1]["previous_judgment"]), "supported", "[events] 记录改之前的判断")
	_eq(str(CaseState.events[-1]["new_judgment"]), "unsupported", "[events] 记录改之后的判断")
	_eq(str(CaseState.events[-1]["cause"]), "evidence:E04", "[events] 记下触发原因")

	# 把握 80 → 55
	CaseState.set_confidence("B", 55)
	CaseState.commit_confidence("B", 80)
	_eq(CaseState.confidence_adjustment_count(), 1, "[events] 把握调整记 1 条")
	_eq(int(CaseState.events[-1]["previous_confidence"]), 80, "[events] 把握事件记住旧值")
	_eq(int(CaseState.events[-1]["new_confidence"]), 55, "[events] 把握事件记住新值")

	# A=Supported/70 首次作答 → 不算改判
	CaseState.select_judgment("A", "supported", 70, "revised")
	_eq(str(CaseState.events[-1]["event_type"]), "JUDGMENT_SELECTED", "[events] 首次作答记成 SELECTED")

	# ── V0.3 规格里的期望值
	_eq(CaseState.revision_count(), 1, "[events] Judgment Revised = 1")
	_eq(CaseState.confidence_adjustment_count(), 1, "[events] Confidence Adjusted = 1")
	_eq(CaseState.revision_count("A"), 0, "[events] Claim A 首次作答不计入改判")
	_eq(CaseState.revision_count("B"), 1, "[events] 改判计数能按 Claim 分开")

	# 终判：全局事件，不计入改判
	CaseState.select_judgment("C", "insufficient", 60, "revised")
	CaseState.select_judgment("D", "unsupported", 55, "revised")
	_eq(CaseState.confirm_final(), true, "[events] 四条齐后确认终判")
	_eq(str(CaseState.events[-1]["event_type"]), "FINAL_CONFIRMED", "[events] 终判事件类型正确")
	_eq(str(CaseState.events[-1]["claim_id"]), "", "[events] 终判是全局事件，不伪装成某条 Claim")
	_eq(CaseState.revision_count(), 1, "[events] Final Confirmed 不计入改判")
	_check(CaseState.events[-1].has("snapshot"), "[events] 终判事件带提交时的答案快照")

	# 顺序：event_order 严格递增
	var ok_order := true
	for i in range(CaseState.events.size()):
		if int(CaseState.events[i]["event_order"]) != i + 1:
			ok_order = false
	_check(ok_order, "[events] event_order 从 1 开始严格递增，无覆盖无重复")

	# 空状态统一用 ""，不许混入 null / "unanswered"
	var ok_empty := true
	for ev in CaseState.events:
		for key in ["previous_judgment", "new_judgment"]:
			var v: Variant = ev.get(key)
			if v == null or (v is String and str(v) == "unanswered"):
				ok_empty = false
	_check(ok_empty, "[events] 未作答统一表示为空串，没有 null / \"unanswered\" 混用")

	# 改回去再改走：两次真实变化，两条记录
	var before := CaseState.revision_count()
	CaseState.select_judgment("B", "supported", -1, "revised")
	CaseState.select_judgment("B", "unsupported", -1, "revised")
	_eq(CaseState.revision_count(), before + 2, "[events] 改回去再改走是两次真实改判")

	# 没有变化时不许制造虚假事件
	var n := CaseState.events.size()
	CaseState.select_judgment("B", "unsupported", -1, "revised")
	_eq(CaseState.events.size(), n, "[events] 值没变时不产生虚假事件")


# ─────────────────────────────────────────────────────────────
#  [debrief] 四种玩家情形（看**实际渲染出来的文字**）
# ─────────────────────────────────────────────────────────────
func _collect_text(node: Node, out: Array) -> void:
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	elif node is RichTextLabel:
		out.append((node as RichTextLabel).text)
	for c in node.get_children():
		_collect_text(c, out)


## 把当前状态下的 Debrief 界面**真的建出来**，返回它渲染出的全部文字（已转小写）。
func _build_debrief_text() -> String:
	Locale.set_lang("en")
	CaseState.reload_for_language()
	var p := DebriefPhase.new()
	add_child(p)          # 必须在 setup 之前入树：_build 里的 stagger_fade 要 create_tween
	p.setup(CaseState.data)
	var texts: Array = []
	_collect_text(p, texts)
	var joined := ""
	for t in texts:
		joined += str(t) + "\n"
	p.queue_free()
	return joined.to_lower()


## 摆出一局并渲染 Debrief。
func _play_and_render(answers: Dictionary, unlocked: Array) -> String:
	CaseState.start()
	for id in unlocked:
		CaseState.unlock(str(id))
	for cid in answers:
		CaseState.select_judgment(str(cid), str(answers[cid]), 70, "revised")
	if not CaseState.all_answered():
		_note("[debrief] 用例数据不全，无法确认终判")
	CaseState.confirm_final()
	return _build_debrief_text()


## 读界面上统计条里某一项的数值（读界面，不读函数）
func _stat_value(rendered: String, caption_key: String) -> String:
	var lines := rendered.split("\n")
	var want := Locale.t(caption_key).to_lower()
	for i in range(lines.size() - 1):
		if lines[i].strip_edges() == want:
			return lines[i + 1].strip_edges()
	return "<未找到 %s>" % caption_key


func test_debrief_four_players() -> void:
	_note("[debrief] 玩家 A 全对 / B 错两项 / C 选 Insufficient / D 不用 AI 且多次改判")
	var all_unlocked := ["E01", "E02", "E04", "E08"]
	var rendered: Array[String] = []

	# ── A：四项全一致 → 4/4，且**不编造错误**
	var a := _play_and_render({
		"A": "supported", "B": "unsupported", "C": "insufficient", "D": "unsupported",
	}, all_unlocked)
	rendered.append(a)
	_check(a.contains("4 / 4"), "[debrief:A] 全对显示 4 / 4")
	_check(a.contains("not a verdict on you"), "[debrief:A] 全对时只给证据边界总结")
	_check(not a.contains("training point"), "[debrief:A] 全对时不出现纠错卡（无训练要点）")

	# ── B1：错两项（B 选 supported、D 选 suspicious）→ 2/4 + 各自的解释
	var b1 := _play_and_render({
		"A": "supported", "B": "supported", "C": "insufficient", "D": "suspicious",
	}, all_unlocked)
	rendered.append(b1)
	_check(b1.contains("2 / 4"), "[debrief:B] 错两项显示 2 / 4")
	_check(b1.contains("load-bearing phrase"), "[debrief:B] B 选 supported 时给出该选项专属解释")
	_check(b1.contains("one order of magnitude larger"), "[debrief:B] D 选 suspicious 时给出该选项专属解释")
	_check(b1.contains("training point"), "[debrief:B] 错误项带一条可迁移的训练要点")

	# ── B2：同一条 Claim 换一个错误选项 → 读到的解释必须不同
	var b2 := _play_and_render({
		"A": "supported", "B": "insufficient", "C": "insufficient", "D": "suspicious",
	}, all_unlocked)
	rendered.append(b2)
	_check(b2.contains("this is not a gap"), "[debrief:B] B 选 insufficient 时换成了另一条解释")
	_check(not b2.contains("load-bearing phrase"),
		"[debrief:B] 换了错误选项，就不再出现上一个选项的解释")
	_check(b1 != b2, "[debrief:B] 不同的错误选择产生不同的教学反馈")

	# ── B3：错误多于两张时，其余折起来
	var b3 := _play_and_render({
		"A": "unsupported", "B": "supported", "C": "supported", "D": "suspicious",
	}, all_unlocked)
	rendered.append(b3)
	_check(b3.contains("0 / 4"), "[debrief:B] 全错时显示 0 / 4")
	_check(b3.contains("show all"), "[debrief:B] 错误多于两张时给出展开按钮")

	# ── C：verdict_accepts 识别（D 接受 unsupported 或 insufficient）
	var c := _play_and_render({
		"A": "supported", "B": "unsupported", "C": "insufficient", "D": "insufficient",
	}, all_unlocked)
	rendered.append(c)
	_check(c.contains("4 / 4"), "[debrief:C] D 选 Insufficient 也判为一致（verdict_accepts 生效）")
	var c2 := _play_and_render({
		"A": "supported", "B": "unsupported", "C": "unsupported", "D": "unsupported",
	}, all_unlocked)
	rendered.append(c2)
	_check(c2.contains("3 / 4"), "[debrief:C] C 选 unsupported 不算一致，得 3 / 4")
	_check(c2.contains("leans against"), "[debrief:C] 解释「缺口」与「矛盾」的区别")

	# ── D：不用 AI + 多次改判 → 行为统计准确
	CaseState.start()
	CaseState.select_judgment("B", "supported", 50, "revised")      # 首次作答（不算改判）
	CaseState.select_judgment("B", "unsupported", -1, "revised")    # 改判 1
	CaseState.select_judgment("B", "suspicious", -1, "revised")     # 改判 2
	CaseState.select_judgment("B", "unsupported", -1, "revised")    # 改判 3
	CaseState.set_confidence("B", 70)
	CaseState.commit_confidence("B", 50)                            # 调整 1
	CaseState.set_confidence("B", 40)
	CaseState.commit_confidence("B", 70)                            # 调整 2
	CaseState.select_judgment("A", "supported", 70, "revised")
	CaseState.select_judgment("C", "insufficient", 60, "revised")
	CaseState.select_judgment("D", "unsupported", 55, "revised")
	CaseState.confirm_final()
	_eq(CaseState.revision_count(), 3, "[debrief:D] 三次改判被数成 3（首次作答不计）")
	_eq(CaseState.confidence_adjustment_count(), 2, "[debrief:D] 两次调整被数成 2")
	_eq(CaseState.ai_calls, 0, "[debrief:D] 没问过分析员")

	var d := _build_debrief_text()   # 直接渲染当前这局，不重置
	rendered.append(d)
	_eq(_stat_value(d, "debrief.revisions"), "3", "[debrief:D] 界面上的改判数与实际一致")
	_eq(_stat_value(d, "debrief.confidence_changes"), "2", "[debrief:D] 界面上的把握调整数与实际一致")
	_eq(_stat_value(d, "debrief.consults"), "0", "[debrief:D] 界面上的咨询次数与实际一致")
	_check(d.contains("never consulted"),
		"[debrief:D] 没问过分析员时如实说明，而不是编造 AI 协作评价")

	# ── 不许出现缺乏证据支持的能力评级
	var banned := ["strong", "weak", "balanced", "context awareness",
		"overgeneralisation", "overgeneralization", "premature judgment",
		"ai collaboration", "needs attention"]
	for text in rendered:
		var hit := ""
		for w in banned:
			if text.contains(w):
				hit = w
		_check(hit == "", "[debrief] 复盘里不含能力评级词（命中：%s）" % (hit if hit != "" else "无"))

	# ── 猜中但没看关键证据：如实说明（§9.6）
	var unseen := _play_and_render({
		"A": "supported", "B": "unsupported", "C": "insufficient", "D": "unsupported",
	}, [])   # 一份档案都没开
	_check(unseen.contains("was never opened"),
		"[debrief] 判断一致但关键证据未解锁时，如实提示没看过（不评价）")


# ─────────────────────────────────────────────────────────────
#  [ai] 提问时刻的快照
# ─────────────────────────────────────────────────────────────
func _stub_capture(_system: String, _user: String, sink: Callable) -> void:
	_box["sink"] = sink


func test_ai_snapshot_at_request() -> void:
	_note("[ai] 请求等待期间玩家改答案，不许污染「提问时刻」的记录")
	CaseState.start()
	for id in ["E01", "E02"]:
		CaseState.unlock(id)
	CaseState.confirm_initial("B", "supported", 80)

	OS.set_environment("DEEPSEEK_API_KEY", "test-key-not-real")
	AiCoach.transport = _stub_capture
	_box["sink"] = Callable()

	AiCoach.ask("challenge", "B", "")     # 发出请求，但**先不给回复**
	await get_tree().process_frame
	_check(AiCoach.busy, "[ai] 请求已发出、正在等待")
	_check(_box["sink"].is_valid(), "[ai] 传输层收到了这次请求")

	# 玩家在等待回复的这几秒里改了判断和把握
	CaseState.select_judgment("B", "unsupported", 20, "revised")

	# 现在才把模型的回复送回来
	_box["sink"].call({"ok": true,
		"text": "The file records the language but not what led to it. That gap is what the claim crosses.",
		"code": ""})
	await get_tree().process_frame

	_eq(CaseState.ai_history.size(), 1, "[ai] 记下了一次咨询")
	if CaseState.ai_history.size() == 1:
		var rec: Dictionary = CaseState.ai_history[0]
		_eq(str(rec.get("judgment", "")), "supported",
			"[ai] 历史里记的是**提问那一刻**的判断，不是回复时的")
		_eq(int(rec.get("confidence", 0)), 80, "[ai] 把握同样是提问那一刻的快照")
		_eq(str(rec.get("judgment_at_response", "")), "unsupported",
			"[ai] 回复时刻的状态另存一处，供排查用")
		_check(str(rec.get("consultation_id", "")) != "", "[ai] 咨询有稳定的 id")
		_eq((rec.get("unlocked_at_request", []) as Array).size(), 2,
			"[ai] 记下提问时解锁了哪些证据")

	AiCoach.transport = Callable()
	_box["sink"] = Callable()
	OS.set_environment("DEEPSEEK_API_KEY", "")
