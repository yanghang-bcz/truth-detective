extends Node
## AiCoach —— 夹在 Evidence 与 Judgment 之间的那一层（autoload，全局名 AiCoach）。
##
## 三层保护，缺一不可：
##   1) AiContextBuilder 只把玩家看得见的内容发出去（白名单）；
##   2) AiPromptBuilder 明确禁止编造、禁止提未解锁的证据、禁止给答案；
##   3) AiResponseValidator 在显示之前再检一遍 —— 假设模型不守规矩。
##
## 前提是一句话：**LLM 不是事实的来源，案件数据库才是。**
##
## 出任何问题都不让游戏坏掉。三条失败路径（没配 key、请求失败、答复被拦下）
## 一律退回本地规则引擎的答复，而且**不扣** Analyst Token：
## 玩家不该为一个他没拿到的答复付费。这也是为什么这个游戏在没有 API key 的
## 机器上依然完整可玩 —— 它从来不靠 LLM 活着。
##
## 注意：这个脚本故意不写 class_name。它作为 autoload 已占用 "AiCoach" 这个全局名。
##
## 状态放在哪：**耐久状态（次数、历史）归 CaseState**，本文件只留瞬时状态
## （busy / 缓存）。否则"重开案件"要清两处，迟早漏一处。

signal state_changed
signal answered(result: Dictionary)

## 测试注入点：形如 func(system, user, sink) -> void 的可调用对象。
## 用 Callable 而不是 Node 子类：调用处不必知道对方是什么类型，
## 假 client 也不必继承任何东西 —— 一个 lambda 就够。
var transport: Callable = Callable()

var busy := false
var last_result: Dictionary = {}

var _client: DeepSeekClient = null
var _cache: Dictionary = {}
var _pending: Dictionary = {}


func _ready() -> void:
	CaseState.case_started.connect(_on_case_started)


# ─────────────────────────────────────────────────────────────
#  对外状态
# ─────────────────────────────────────────────────────────────
func available() -> bool:
	return AiConfig.has_key()


func tokens() -> int:
	return CaseState.analyst_tokens


func can_use_ai() -> bool:
	return available() and tokens() > 0 and not busy


func state() -> Dictionary:
	return {
		"available": available(),
		"tokens": tokens(),
		"tokens_max": CaseState.ANALYST_TOKENS_MAX,
		"busy": busy,
	}


## 玩家当前在看的那张 Claim 上的判断 / 把握。取最后一条记录 ——
## 历史是追加的，最后一条才是"他现在怎么看"。
func judgment_of(claim_id: String) -> String:
	for i in range(CaseState.history.size() - 1, -1, -1):
		var entry: Dictionary = CaseState.history[i]
		if str(entry.get("claim", "")) == claim_id:
			return str(entry.get("judgment", ""))
	return ""


func confidence_of(claim_id: String) -> int:
	for i in range(CaseState.history.size() - 1, -1, -1):
		var entry: Dictionary = CaseState.history[i]
		if str(entry.get("claim", "")) == claim_id:
			return int(entry.get("confidence", 50))
	return 50


## 本案里**存在**的编号（不区分解锁与否）。Validator 需要它来区分
## "那是还没解锁的证据"（泄题）和"那个编号根本不存在"（编造）。
func known_evidence_ids() -> Array:
	var out: Array = []
	for card in CaseState.data.get("evidence", []):
		out.append(str(card.get("id", "")))
	return out


# ─────────────────────────────────────────────────────────────
#  提问
# ─────────────────────────────────────────────────────────────
func ask(action: String, claim_id: String, evidence_id: String) -> void:
	if busy:
		return
	var needs_card := action == "explain" or action == "not_prove"
	if needs_card and evidence_id == "":
		return

	if not can_use_ai():
		_deliver(action, claim_id, _offline(action, claim_id, evidence_id))
		return

	var ctx := AiContextBuilder.build(CaseState.data, CaseState.unlocked, claim_id,
		judgment_of(claim_id), confidence_of(claim_id), action)
	var target := evidence_id if needs_card else ""
	if target != "":
		ctx["target_evidence"] = target

	var key := _cache_key(ctx)
	if _cache.has(key):
		var hit: Dictionary = _cache[key]
		_deliver(action, claim_id, {
			"ok": true,
			"text": str(hit.get("text", "")),
			"basis": hit.get("basis", []),
			"source": "cache",
		})
		return

	busy = true
	_pending = {"action": action, "claim": claim_id, "evidence": evidence_id, "key": key}
	state_changed.emit()
	_send(AiPromptBuilder.system_prompt(Locale.lang),
		AiPromptBuilder.user_prompt(ctx, Locale.lang, target),
		_on_response)


func _on_response(result: Dictionary) -> void:
	var action := str(_pending.get("action", ""))
	var claim := str(_pending.get("claim", ""))
	var evidence := str(_pending.get("evidence", ""))
	var key := str(_pending.get("key", ""))

	if not bool(result.get("ok", false)):
		# 请求就没成功。退回离线答复，并把原因留给界面显示 ——
		# 但**不扣次数**：玩家没拿到东西。
		var offline := _offline(action, claim, evidence)
		offline["failure"] = str(result.get("code", ""))
		_deliver(action, claim, offline)
		return

	var text := AiResponseValidator.clamp(str(result.get("text", "")), Locale.lang)
	var verdict := AiResponseValidator.check(text, CaseState.unlocked, known_evidence_ids())
	if int(verdict.get("verdict", 0)) != AiResponseValidator.Verdict.OK:
		# 模型不守规矩。不显示、不扣次数。reason 留给开发期排查，
		# 界面上只出现一句人话。
		var safe := _offline(action, claim, evidence)
		safe["blocked"] = str(verdict.get("reason", ""))
		_deliver(action, claim, safe)
		return

	# 走到这里才算一次真正的 AI 答复。
	var cited: Array = verdict.get("ids", [])
	var basis: Array = cited if not cited.is_empty() else CaseState.unlocked.duplicate()
	CaseState.consume_analyst_token()
	_cache[key] = {"text": text, "basis": basis}
	_deliver(action, claim, {"ok": true, "text": text, "basis": basis, "source": "ai"})


## 所有出口都走这里：统一记账、统一发信号。
func _deliver(action: String, claim: String, payload: Dictionary) -> void:
	busy = false
	_pending = {}

	var text := str(payload.get("text", ""))
	var source := str(payload.get("source", "offline"))
	var result := {
		"ok": bool(payload.get("ok", false)),
		"action": action,
		"text": text,
		"basis": payload.get("basis", []),
		"source": source,
		"failure": str(payload.get("failure", "")),
		"blocked": str(payload.get("blocked", "")),
		"cost_ip": int(payload.get("cost_ip", 0)),
		"cost_token": int(payload.get("cost_token", 0)),
	}
	last_result = result
	state_changed.emit()
	if not result["ok"]:
		return

	# ai_calls 记的是「咨询次数」，不区分走的是模型还是离线引擎 ——
	# Debrief 里那一行问的是"你问了几次分析员"，不是"你花了多少电"。
	CaseState.note_consult()
	CaseState.record_ai({
		"action": action,
		"claim": claim,
		"judgment": judgment_of(claim),
		"confidence": confidence_of(claim),
		"evidence": result["basis"],
		"opened": CaseState.unlocked.size(),
		"source": source,
		"response": text,
		"time": CaseState.elapsed_seconds(),
	})
	answered.emit(result)


# ─────────────────────────────────────────────────────────────
#  离线规律引擎
# ─────────────────────────────────────────────────────────────
## 本地规则引擎。它同时是三条路径的兜底：没配 key、请求失败、答复被拦下。
##
## 内容全部来自 case_001.json 里的人工撰写字段（analyst / does_not_prove /
## challenges / gaps）。它读的是同一份数据库，所以永远不会编造证据 ——
## 在"不编造"这件事上，规则引擎天然比模型可靠。这正是它能当兜底的原因。
##
## 它花 1 点调查点（老行为，不变）。AI 咨询花的是 Analyst Token，两者分开记：
## 调查点是"调查资源"，Analyst Token 是"AI 协作资源"。
func _offline(action: String, claim_id: String, evidence_id: String) -> Dictionary:
	if not CaseState.spend(1):
		return {"ok": false, "text": "", "basis": [], "source": "offline", "failure": "no_points"}
	var data: Dictionary = CaseState.data
	match action:
		"explain":
			var card := CaseData.evidence(data, evidence_id)
			return _offline_ok(str(card.get("analyst", "")), [evidence_id])
		"not_prove":
			var card2 := CaseData.evidence(data, evidence_id)
			var lines := Locale.t("analyst.not_prove_head")
			for item in card2.get("does_not_prove", []):
				lines += "\n\n— " + str(item)
			return _offline_ok(lines, [evidence_id])
		"challenge":
			var text := CaseData.challenge(data, claim_id, judgment_of(claim_id))
			if text == "":
				text = Locale.t("analyst.none")
			return _offline_ok(text, CaseState.unlocked.duplicate())
		"missing":
			var gap := CaseData.first_gap(data, CaseState.unlocked)
			var message := Locale.t("analyst.all_open") if gap.is_empty() \
				else str(gap.get("message", ""))
			return _offline_ok(message, CaseState.unlocked.duplicate())
	return {"ok": false, "text": "", "basis": [], "source": "offline", "failure": "unknown_action"}


static func _offline_ok(text: String, basis: Array) -> Dictionary:
	return {"ok": true, "text": text, "basis": basis, "source": "offline",
		"cost_ip": 1, "cost_token": 0}


# ─────────────────────────────────────────────────────────────
func _send(system: String, user: String, sink: Callable) -> void:
	if transport.is_valid():
		transport.call(system, user, sink)
		return
	if _client == null:
		_client = DeepSeekClient.new()
		add_child(_client)
	_client.ask(system, user, sink)


## 缓存键就是完整的 context 本身：证据集合、判断、把握、动作，
## 只要有一项不同就是新问题。玩家重复问同一个问题不该再花一次额度。
func _cache_key(ctx: Dictionary) -> String:
	return str(JSON.stringify(ctx).hash())


func _on_case_started() -> void:
	_cache.clear()
	_pending.clear()
	busy = false
	last_result = {}
	state_changed.emit()
