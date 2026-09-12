extends Node
## AI 层回归测试。对应 v0.2 规格里的 Test A/B/C/D，外加两条额度与缓存的行为。
##
## 为什么必须用场景方式跑（`res://tools/test_ai.tscn`）：
## --script 模式不注册 autoload，而这一整层就是围着 CaseState / Locale / AiCoach 转的。
##
## 为什么这些用例值得写：AI 接入带来的不是"会不会崩"，而是三类**静默**问题 ——
##   1) 未解锁的证据悄悄进了请求（玩家不会知道，但题目已经被泄了）；
##   2) 模型把答案直接说了出来（界面上看起来很顺，学习效果已经归零）；
##   3) 请求失败时扣了玩家的额度（没人会去数，但那是实打实的体验损失）。
## 三种都不报错，只是悄悄做错事。所以必须有断言守着。

const LOCKED_IDS: Array[String] = ["E03", "E04", "E06", "E07", "E08"]
const UNLOCKED_IDS: Array[String] = ["E01", "E02", "E05"]

## 假 client 的收发信箱。用 Dictionary 而不是 lambda 捕获：
## lambda 在 GDScript 里按值捕获，改不了外面的变量。
var _box := {"reply": {"ok": true, "text": "", "code": ""}, "system": "", "user": ""}

var _passes := 0
var _fails := 0


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


## 提问并等一帧。离线与假 client 都是同步回调，一帧足够；
## 真模型走网络时这个工具不该被使用（测试里永远注入假 client）。
func _ask(action: String, claim: String, evidence: String) -> Dictionary:
	AiCoach.ask(action, claim, evidence)
	await get_tree().process_frame
	return AiCoach.last_result


func _stub_reply(_system: String, _user: String, sink: Callable) -> void:
	_box["system"] = _system
	_box["user"] = _user
	sink.call(_box["reply"])


func run() -> void:
	CaseState.start()
	for id in UNLOCKED_IDS:
		CaseState.unlock(id)
	await get_tree().process_frame

	test_context_whitelist()
	test_prompt_never_contains_locked_ids()
	test_hard_rules_survive()
	test_validator()
	test_language_directive()
	# 这三个是协程（里面有 await）。**必须 await 它们** ——
	# 不 await 的话 run() 会立刻往下跑，打完汇总就退出，
	# 而这几条用例才刚跑到第一个 await。表现是"测试通过了但什么都没测"。
	await test_no_key_degrades()
	await test_api_failure_paths()
	await test_token_cache_and_exhaustion()

	print("AI_TESTS %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


# ─────────────────────────────────────────────────────────────
#  Test A：Safe Context 是白名单
# ─────────────────────────────────────────────────────────────
func test_context_whitelist() -> void:
	var ctx := AiContextBuilder.build(CaseState.data, CaseState.unlocked, "B",
		"supported", 80, "challenge")

	var allowed_top := {
		"action": true, "claim_under_review": true, "unlocked_evidence": true,
		"player_current_judgment": true, "player_confidence": true, "public_post_text": true,
	}
	var stray: Array[String] = []
	for k in ctx.keys():
		if not allowed_top.has(str(k)):
			stray.append(str(k))
	_check(stray.is_empty(), "context 顶层只有白名单键（越界: %s）" % str(stray))

	var cards: Array = ctx.get("unlocked_evidence", [])
	_check(cards.size() == UNLOCKED_IDS.size(),
		"context 里只有已解锁的 %d 张证据" % UNLOCKED_IDS.size())

	var allowed_field := {}
	for f in AiContextBuilder.EVIDENCE_FIELDS:
		allowed_field[f] = true
	var extra: Array[String] = []
	for card in cards:
		for k in card.keys():
			if not allowed_field.has(str(k)):
				extra.append(str(k))
	_check(extra.is_empty(), "每张证据只带白名单字段（越界: %s）" % str(extra))

	# 答案类的键一个都不许出现。这几个是本案 JSON 里最贵的字段。
	var raw := JSON.stringify(ctx)
	var banned: Array[String] = []
	for key in ["kind_answer", "relevance_answer", "verdict_accepts", "decisive_evidence"]:
		if raw.contains("\"" + key + "\""):
			banned.append(key)
	_check(banned.is_empty(), "context 不含分类答案与终局答案键（实际: %s）" % str(banned))


# ─────────────────────────────────────────────────────────────
#  Test A（续）：请求里不出现未解锁的编号
# ─────────────────────────────────────────────────────────────
func test_prompt_never_contains_locked_ids() -> void:
	var ctx := AiContextBuilder.build(CaseState.data, CaseState.unlocked, "B",
		"", 50, "missing")
	var user := AiPromptBuilder.user_prompt(ctx, "en", "")
	var system := AiPromptBuilder.system_prompt("en")

	var leaked: Array[String] = []
	for id in LOCKED_IDS:
		if user.contains(id) or system.contains(id):
			leaked.append(id)
	_check(leaked.is_empty(), "prompt 里不出现任何未解锁的编号（实际: %s）" % str(leaked))

	# 连"一共几条"都不给：知道谜题规模就等于知道还差多少。
	_check(not user.contains("8 evidence") and not user.contains("total_evidence"),
		"prompt 不给证据总数（不透露谜题规模）")


# ─────────────────────────────────────────────────────────────
#  硬规则是设计的一部分，删掉一条测试就该喊
# ─────────────────────────────────────────────────────────────
func test_hard_rules_survive() -> void:
	var system := AiPromptBuilder.system_prompt("en")
	for rule in [
		"Use only the evidence included in the current context.",
		"Never invent facts",
		"Never reveal, name, count, or speculate about evidence that is not in the context.",
		"Never state the final correct judgment",
	]:
		_check(system.contains(rule), "系统提示仍含硬规则：" + rule)


func test_language_directive() -> void:
	_check(AiPromptBuilder.system_prompt("zh").contains("Simplified Chinese"),
		"中文界面要求模型用中文回答")
	_check(AiPromptBuilder.system_prompt("en").contains("Respond in English"),
		"英文界面要求模型用英文回答")


# ─────────────────────────────────────────────────────────────
#  Test B：Validator
# ─────────────────────────────────────────────────────────────
func test_validator() -> void:
	var unlocked := ["E01"]
	var known := ["E01", "E02", "E03", "E04", "E05", "E06", "E07", "E08"]
	var rows := [
		["Evidence #08 proves she started it.", AiResponseValidator.Verdict.LEAKED,
			"拦下「Evidence #08」式泄漏"],
		["E04 shows what happened earlier.", AiResponseValidator.Verdict.LEAKED,
			"拦下「E04」式泄漏"],
		["Evidence #12 is decisive.", AiResponseValidator.Verdict.UNKNOWN,
			"拦下不存在的编号（编造）"],
		["The correct answer is Unsupported.", AiResponseValidator.Verdict.FINAL_ANSWER,
			"拦下英文直给答案"],
		["正确答案是不成立。", AiResponseValidator.Verdict.FINAL_ANSWER,
			"拦下中文直给答案"],
		["", AiResponseValidator.Verdict.EMPTY, "拦下空回答"],
		["E01 records aggressive language. It does not show who began the exchange.",
			AiResponseValidator.Verdict.OK, "干净答复放行"],
	]
	for row in rows:
		var verdict := AiResponseValidator.check(str(row[0]), unlocked, known)
		_check(int(verdict["verdict"]) == int(row[1]), "Validator: " + str(row[2]))

	var cited := AiResponseValidator.check(
		"E01 and Evidence #01 both point the same way.", unlocked, known)
	_check(str(cited["ids"]) == str(["E01"]), "同一张证据的两种写法不会算成两个编号")

	var cap := int(AiResponseValidator.MAX_CHARS["en"])
	var long_text := "This is one sentence about the evidence. ".repeat(60)
	_check(AiResponseValidator.clamp(long_text, "en").length() <= cap,
		"超长答复被收敛回上限内（%d 字符）" % cap)


# ─────────────────────────────────────────────────────────────
#  Test C：没有 key 也要能玩
# ─────────────────────────────────────────────────────────────
func test_no_key_degrades() -> void:
	if AiConfig.has_key():
		_note("本机配了 DEEPSEEK_API_KEY，「无 key」用例跳过；其行为由 Test D 用假 client 覆盖")
		return
	_check(not AiCoach.available(), "无 key 时 AiCoach 报告不可用")
	var before := CaseState.analyst_tokens
	var got := await _ask("missing", "B", "")
	_check(bool(got.get("ok", false)), "无 key 时仍答得出来（退回离线引擎）")
	_check(str(got.get("source", "")) == "offline", "无 key 时来源是离线引擎")
	_check(CaseState.analyst_tokens == before, "无 key 时不消耗 Analyst Token")


# ─────────────────────────────────────────────────────────────
#  Test D：失败与越界一律优雅降级，且不扣次数
# ─────────────────────────────────────────────────────────────
func test_api_failure_paths() -> void:
	# 假装配了 key，注入假 client。这样这几条用例与本机有没有真 key 无关。
	OS.set_environment("DEEPSEEK_API_KEY", "test-key-not-real")
	AiCoach.transport = _stub_reply
	_check(AiCoach.available(), "配了 key 之后 AiCoach 认为可用")

	_box["reply"] = {"ok": false, "text": "", "code": "timeout"}
	var before := CaseState.analyst_tokens
	var timed_out := await _ask("missing", "B", "")
	_check(bool(timed_out.get("ok", false)), "请求超时后仍给得出答复（退回离线）")
	_check(str(timed_out.get("source", "")) == "offline", "超时后来源是离线引擎")
	_check(str(timed_out.get("failure", "")) == "timeout", "失败原因被留下来给界面用")
	_check(CaseState.analyst_tokens == before, "请求失败不扣 Analyst Token")

	_box["reply"] = {"ok": false, "text": "", "code": "auth"}
	var denied := await _ask("missing", "B", "")
	_check(str(denied.get("source", "")) == "offline", "鉴权失败（401/403）也走离线")
	_check(CaseState.analyst_tokens == before, "鉴权失败不扣 Analyst Token")

	_box["reply"] = {"ok": true, "text": "Evidence #08 proves she started it.", "code": ""}
	var leaked := await _ask("missing", "B", "")
	_check(str(leaked.get("source", "")) == "offline", "泄漏未解锁证据的答复被拦下")
	_check(str(leaked.get("blocked", "")) != "", "拦截原因被记下来（供开发期排查）")
	_check(CaseState.analyst_tokens == before, "被拦下的答复不扣 Analyst Token")

	_box["reply"] = {"ok": true, "text": "The correct answer is Unsupported.", "code": ""}
	var answered_for_player := await _ask("missing", "B", "")
	_check(str(answered_for_player.get("source", "")) == "offline", "直接给答案的答复被拦下")

	_box["reply"] = {"ok": false, "text": "", "code": "server"}
	var server_error := await _ask("missing", "B", "")
	_check(str(server_error.get("source", "")) == "offline", "服务端 5xx 也走离线")

	OS.set_environment("DEEPSEEK_API_KEY", "")
	AiCoach.transport = Callable()


# ─────────────────────────────────────────────────────────────
#  额度与缓存
# ─────────────────────────────────────────────────────────────
func test_token_cache_and_exhaustion() -> void:
	OS.set_environment("DEEPSEEK_API_KEY", "test-key-not-real")
	AiCoach.transport = _stub_reply
	_box["reply"] = {
		"ok": true,
		"text": "E01 records aggressive language. It does not show who began the exchange.",
		"code": "",
	}

	CaseState.start()
	for id in UNLOCKED_IDS:
		CaseState.unlock(id)
	await get_tree().process_frame
	_check(CaseState.analyst_tokens == CaseState.ANALYST_TOKENS_MAX,
		"开案时额度是满的（%d 次）" % CaseState.ANALYST_TOKENS_MAX)

	var before := CaseState.analyst_tokens
	var first := await _ask("not_prove", "B", "E01")
	_check(str(first.get("source", "")) == "ai", "有 key + 干净答复 → 走模型")
	_check(CaseState.analyst_tokens == before - 1, "一次模型答复扣一次额度")
	_check(CaseState.ai_history.size() == 1, "这次咨询被记进 AI 历史")
	_check(CaseState.elapsed_seconds() >= 0.0, "历史里带着案件时间轴（秒）")

	var second := await _ask("not_prove", "B", "E01")
	_check(str(second.get("source", "")) == "cache", "同一个问题重问走缓存")
	_check(CaseState.analyst_tokens == before - 1, "缓存命中不再扣额度")
	# 缓存命中仍然是一次「咨询」（玩家确实问了、时间点也算数），
	# 但它不该计进「用了模型的那几次」—— 那个数字才是 Debrief 分析 AI 协作的依据。
	_check(CaseState.ai_history.size() == 2, "缓存命中仍记一次咨询")
	_check(str(CaseState.ai_history[1].get("source", "")) == "cache",
		"历史里区分得开：这条是缓存，不是模型")
	_check(CaseState.ai_uses().size() == 1, "「用了模型」的计数只认真走模型的那次")

	# 额度用尽：自动退回离线引擎，而且不会被扣成负数。
	CaseState.analyst_tokens = 0
	_box["reply"] = {"ok": true, "text": "A different clean answer.", "code": ""}
	var drained := await _ask("challenge", "B", "")
	_check(str(drained.get("source", "")) == "offline", "额度用尽后退回离线引擎")
	_check(CaseState.analyst_tokens == 0, "额度不会被扣成负数")

	# rebase 之后缓存要清掉：老问题的答案不该跟着新案件走。
	CaseState.start()
	_check(CaseState.ai_history.is_empty(), "重开案件清空 AI 历史")
	_check(CaseState.analyst_tokens == CaseState.ANALYST_TOKENS_MAX, "重开案件恢复满额度")

	OS.set_environment("DEEPSEEK_API_KEY", "")
	AiCoach.transport = Callable()
