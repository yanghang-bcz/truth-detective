extends Node
## 案件期间的状态中枢（autoload 单例，全局名 CaseState）。
##
## 刻意做成单例而不是在节点之间传引用：调查点、已解锁证据、判定状态
## 这几样东西需要同时被四个界面阶段读写，而且 Debrief 要复盘的东西
## 恰恰是"玩家中途改过什么" —— 状态必须是一份、连续的、可回溯的。
##
## 注意：这个脚本故意不写 class_name。它已经作为 autoload 占用 "CaseState"
## 这个全局名，再加 class_name 会撞名。
##
## ── v0.3 判定状态模型 ────────────────────────────────────────
##
## 三个容器语义严格区分，**不许互相顶替**：
##
##   initial_judgments  开场那一次提交的快照。进入调查后不可修改。
##   current_judgments  **唯一可信的"当前判断"**。调查页、Final Review、
##                      AI Analyst 全部读写这一份。
##   final_judgments    玩家点下"确认最终判定"时，对 current 的快照。
##                      日常操作绝不写它。
##
## 空状态统一用空字符串 ""。**不要**用 null / "unanswered" / "none" 混着表示
## "未作答" —— 多一种写法就多一个"UI 认为没答、状态认为答了"的机会。
##
## 另外，**当前状态与事件历史是两件事**：
##   current_judgments  回答"他现在怎么看"
##   events             回答"他什么时候改成了什么"
## v0.2 把两者塞进同一个 history 数组，导致"从历史里倒推当前状态"，
## 于是改判统计把首次作答和最终确认也算成了改判。v0.3 彻底分开。

signal points_changed(remaining: int)
signal unlocked_changed(id: String)
signal judgment_changed(claim_id: String, judgment: String, confidence: int)
signal event_recorded(event: Dictionary)
signal final_confirmed
signal analyst_tokens_changed(left: int)
## 一个案件从头开始（含重开）。AiCoach 听它清缓存 ——
## 用信号而不是让 CaseState 反向调用 AiCoach：autoload 互相调用容易
## 撞上初始化顺序，而"谁清谁的缓存"和"案件什么时候开始"本来也是两件事。
signal case_started

const CASE_ID := "case_001"

## AI 咨询的额度。跟调查点分开记：调查点是"调查资源"，
## 它是"AI 协作资源"，两者混在一起就说不清玩家到底在省什么。
const ANALYST_TOKENS_MAX := 3

# ── 判定状态常量 ────────────────────────────────────────────
const EMPTY_JUDGMENT := ""
const DEFAULT_CONFIDENCE := 50

## 事件类型。改判统计只认 JUDGMENT_REVISED 一种。
const EV_INITIAL_CONFIRMED := "INITIAL_CONFIRMED"
const EV_JUDGMENT_SELECTED := "JUDGMENT_SELECTED"
const EV_JUDGMENT_REVISED := "JUDGMENT_REVISED"
const EV_JUDGMENT_CLEARED := "JUDGMENT_CLEARED"
const EV_CONFIDENCE_ADJUSTED := "CONFIDENCE_ADJUSTED"
const EV_FINAL_CONFIRMED := "FINAL_CONFIRMED"

var data: Dictionary = {}

var points_total: int = 10
var points_used: int = 0

var unlocked: Array[String] = []
var opened: Array[String] = []         ## 打开过详情页的证据（unlocked 是解锁，opened 是读过）
var classifications: Dictionary = {}   ## evidence id -> {"relevance": .., "kind": ..}
var focused_evidence: String = ""

## ── 判定状态 ────────────────────────────────────────────────
## 形状统一为 {"judgment": String, "confidence": int}
var initial_judgments: Dictionary = {}
var current_judgments: Dictionary = {}
var final_judgments: Dictionary = {}
## 开场页还没提交的草稿。切语言会重建开场页，草稿必须活下来 ——
## 否则"选好了还没点开始调查"时换一次语言，选的东西就没了。
var intro_draft: Dictionary = {}

## ── 事件历史 ────────────────────────────────────────────────
## 每条：
##   event_id, event_type, claim_id,
##   previous_judgment, new_judgment,
##   previous_confidence, new_confidence,
##   unlocked_evidence_ids (快照，深拷贝),
##   event_order (单调递增),
##   case_elapsed_ms,
##   cause (界面用的触发说明：initial / final / analyst / evidence:Exx / revised)
##
## FINAL_CONFIRMED 是全局事件（claim_id 为空串），额外带一个 snapshot 字段
## 记录提交时的全部答案 —— 不硬把它伪装成某条 Claim 的修改。
var events: Array[Dictionary] = []

var ai_calls: int = 0

## 剩下的 AI 咨询次数 / 这次案件里问过分析员什么。
## 每条：{consultation_id, action, claim, judgment, confidence, evidence, opened,
##        source, response, time, ...}
##   judgment / confidence 是**请求发起那一刻**的快照，不是回复时的状态
##   （见 ai_coach.gd 的 _pending）。
var analyst_tokens: int = ANALYST_TOKENS_MAX
var ai_history: Array[Dictionary] = []

var _started_msec: int = 0
var _event_seq: int = 0


func _ready() -> void:
	data = CaseData.load_localized(CASE_ID, Locale.lang)
	if data.is_empty():
		push_error("CaseState: 无法加载 " + CASE_ID)
	reset_judgments()


## 切语言时重新读一遍内容。**只换文本，不动进度** ——
## 玩家翻到一半换语言，调查点、已开档案、判定状态都该原样还在。
func reload_for_language() -> void:
	var fresh := CaseData.load_localized(CASE_ID, Locale.lang)
	if fresh.is_empty():
		return
	data = fresh
	points_total = int(data.get("investigation_points", points_total))
	points_changed.emit(remaining())


func start(payload: Dictionary = {}) -> void:
	if payload.is_empty():
		payload = CaseData.load_localized(CASE_ID, Locale.lang)
	data = payload
	points_total = int(data.get("investigation_points", 10))
	points_used = 0
	unlocked.clear()
	opened.clear()
	classifications.clear()
	focused_evidence = ""
	ai_calls = 0
	analyst_tokens = ANALYST_TOKENS_MAX
	ai_history.clear()
	_started_msec = Time.get_ticks_msec()
	reset_judgments()
	points_changed.emit(remaining())
	analyst_tokens_changed.emit(analyst_tokens)
	case_started.emit()


# ─────────────────────────────────────────────────────────────
#  判定状态：读
# ─────────────────────────────────────────────────────────────
## 建/清全部判定状态。开一局新案件时必须走这里 ——
## 上一局的 initial / current / final / 事件 / 草稿一个都不能留。
func reset_judgments() -> void:
	initial_judgments.clear()
	current_judgments.clear()
	final_judgments.clear()
	events.clear()
	_event_seq = 0
	intro_draft = _slot()
	for c in CaseData.claims(data):
		current_judgments[str(c.get("id", ""))] = _slot()


func current_judgment(claim_id: String) -> String:
	return str(current_judgments.get(claim_id, {}).get("judgment", EMPTY_JUDGMENT))


func current_confidence(claim_id: String) -> int:
	return int(current_judgments.get(claim_id, {}).get("confidence", DEFAULT_CONFIDENCE))


func has_judgment(claim_id: String) -> bool:
	return current_judgment(claim_id) != EMPTY_JUDGMENT


## 还没作答的 Claim（按案件里的顺序）。
func unanswered_claims() -> Array[String]:
	var out: Array[String] = []
	for c in CaseData.claims(data):
		var id := str(c.get("id", ""))
		if not has_judgment(id):
			out.append(id)
	return out


func all_answered() -> bool:
	return unanswered_claims().is_empty()


func final_judgment(claim_id: String) -> String:
	return str(final_judgments.get(claim_id, {}).get("judgment", EMPTY_JUDGMENT))


func final_confidence(claim_id: String) -> int:
	return int(final_judgments.get(claim_id, {}).get("confidence", DEFAULT_CONFIDENCE))


# ─────────────────────────────────────────────────────────────
#  判定状态：写
#
#  所有写入口都必须经过这里，好让"当前状态"和"事件历史"永远同步 ——
#  之前的问题正是有人绕过状态直接改 UI 缓存，于是 UI 说 80、状态说 50。
# ─────────────────────────────────────────────────────────────
## 开场提交初判。写 initial + current，记一次 INITIAL_CONFIRMED。
## 初判是对"玩家第一次怎么看"的快照，**不算改判**。
func confirm_initial(claim_id: String, judgment: String, confidence: int) -> void:
	var prev: Dictionary = initial_judgments.get(claim_id, _slot())
	initial_judgments[claim_id] = _slot(judgment, confidence)
	_apply_current(claim_id, judgment, confidence)
	intro_draft = _slot(judgment, confidence)
	_record_event(EV_INITIAL_CONFIRMED, claim_id, str(prev["judgment"]), judgment,
		int(prev["confidence"]), confidence, "initial")


## 调查页 / Final Review 里玩家选了一个判定。
## 事件类型按"改之前是什么"自动判定：
##   空 → 非空  JUDGMENT_SELECTED（首次作答，不算改判）
##   非空 → 空  JUDGMENT_CLEARED （主动清空，单独记，不算改判）
##   非空 → 非空 JUDGMENT_REVISED （真正的改判）
## 两个参数都没变时**直接返回**，不制造虚假事件 ——
## 但"改回同一个值又改走再改回来"是三次真实变化，三次都会留下记录。
func select_judgment(claim_id: String, judgment: String, confidence: int = -1,
		cause: String = "revised") -> void:
	var prev_j := current_judgment(claim_id)
	var prev_c := current_confidence(claim_id)
	var conf := confidence if confidence >= 0 else prev_c
	if judgment == prev_j and conf == prev_c:
		return
	_apply_current(claim_id, judgment, conf)
	var kind := EV_JUDGMENT_REVISED
	if prev_j == EMPTY_JUDGMENT:
		kind = EV_JUDGMENT_SELECTED
	elif judgment == EMPTY_JUDGMENT:
		kind = EV_JUDGMENT_CLEARED
	_record_event(kind, claim_id, prev_j, judgment, prev_c, conf, cause)


## 只动确定程度。**不算改判**，记成 CONFIDENCE_ADJUSTED。
## 一次拖动应该在松手时调用一次 —— 拖 50→80 不是 30 次调整，是 1 次。
##
## 拖动过程中要实时同步的话用 set_confidence()（不记事件），
## 松手时用 commit_confidence()（记一次）。
func adjust_confidence(claim_id: String, confidence: int) -> void:
	var previous := current_confidence(claim_id)
	set_confidence(claim_id, confidence)
	commit_confidence(claim_id, previous)


## 拖动过程中的实时同步：只改当前状态，不记事件。
## 这样"UI 上显示的"和"状态里的"任何时刻都相等，
## 但一次拖动不会在历史里留下几十条噪声。
func set_confidence(claim_id: String, confidence: int) -> void:
	var conf := clampi(confidence, 0, 100)
	if conf == current_confidence(claim_id):
		return
	_apply_current(claim_id, current_judgment(claim_id), conf)


## 一次拖动/一次点击**结束**：用交互开始前的值，记一条 CONFIDENCE_ADJUSTED。
## 值没变就不记 —— 点一下手柄不该留下痕迹。
func commit_confidence(claim_id: String, previous: int) -> void:
	var now := current_confidence(claim_id)
	var prev := clampi(previous, 0, 100)
	if now == prev:
		return
	var judgment := current_judgment(claim_id)
	_record_event(EV_CONFIDENCE_ADJUSTED, claim_id, judgment, judgment, prev, now, "revised")


## 终判提交。对 current 做快照，记一次 FINAL_CONFIRMED（全局事件，不算改判）。
## 四个 Claim 没答完时不提交，返回 false。
func confirm_final() -> bool:
	if not all_answered():
		return false
	final_judgments.clear()
	for c in CaseData.claims(data):
		var id := str(c.get("id", ""))
		final_judgments[id] = _slot(current_judgment(id), current_confidence(id))
	var ev := _record_event(EV_FINAL_CONFIRMED, "", EMPTY_JUDGMENT, EMPTY_JUDGMENT,
		DEFAULT_CONFIDENCE, DEFAULT_CONFIDENCE, "final")
	ev["snapshot"] = final_judgments.duplicate(true)
	final_confirmed.emit()
	return true


func _slot(judgment: String = EMPTY_JUDGMENT, confidence: int = DEFAULT_CONFIDENCE) -> Dictionary:
	return {"judgment": judgment, "confidence": clampi(confidence, 0, 100)}


func _apply_current(claim_id: String, judgment: String, confidence: int) -> void:
	current_judgments[claim_id] = _slot(judgment, confidence)
	judgment_changed.emit(claim_id, judgment, confidence)


func _record_event(kind: String, claim_id: String, prev_j: String, new_j: String,
		prev_c: int, new_c: int, cause: String) -> Dictionary:
	_event_seq += 1
	var ev := {
		"event_id": "ev_%04d" % _event_seq,
		"event_type": kind,
		"claim_id": claim_id,
		"previous_judgment": prev_j,
		"new_judgment": new_j,
		"previous_confidence": prev_c,
		"new_confidence": new_c,
		# 快照必须深拷贝：存引用的话，玩家之后解锁新证据会把历史里
		# "当时看到几张"一起改掉，时间轴就假了。
		"unlocked_evidence_ids": unlocked.duplicate(),
		"event_order": _event_seq,
		"case_elapsed_ms": elapsed_msec(),
		"cause": cause,
	}
	events.append(ev)
	event_recorded.emit(ev)
	return ev


# ─────────────────────────────────────────────────────────────
#  事件历史的派生视图
# ─────────────────────────────────────────────────────────────
## 改判次数。**只数 JUDGMENT_REVISED** ——
## 首次作答、清空、调确定程度、最终确认、进出页面都不算。
func revision_count(claim_id: String = "") -> int:
	var n := 0
	for e in events:
		if str(e.get("event_type", "")) != EV_JUDGMENT_REVISED:
			continue
		if claim_id != "" and str(e.get("claim_id", "")) != claim_id:
			continue
		n += 1
	return n


func confidence_adjustment_count(claim_id: String = "") -> int:
	var n := 0
	for e in events:
		if str(e.get("event_type", "")) != EV_CONFIDENCE_ADJUSTED:
			continue
		if claim_id != "" and str(e.get("claim_id", "")) != claim_id:
			continue
		n += 1
	return n


func events_of(claim_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		if str(e.get("claim_id", "")) == claim_id:
			out.append(e)
	return out


## 判断轨迹：只取"判断本身变过"的事件（含首次作答与清空），
## 转成界面直接能画的形状。Debrief 的时间轴与棋盘的空心圆点都读它。
func journey(claim_id: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		var kind := str(e.get("event_type", ""))
		if kind != EV_INITIAL_CONFIRMED and kind != EV_JUDGMENT_SELECTED \
				and kind != EV_JUDGMENT_REVISED and kind != EV_JUDGMENT_CLEARED:
			continue
		if claim_id != "" and str(e.get("claim_id", "")) != claim_id:
			continue
		out.append({
			"claim": str(e.get("claim_id", "")),
			"judgment": str(e.get("new_judgment", "")),
			"confidence": int(e.get("new_confidence", DEFAULT_CONFIDENCE)),
			"trigger": str(e.get("cause", "revised")),
			"points_used": points_used,
			"evidence_seen": (e.get("unlocked_evidence_ids", []) as Array).size(),
		})
	return out


## 在某条证据之后真的改过判断的 Claim（中性描述用，不评价好坏）。
## 只陈述"发生了什么"，不说"这说明你如何如何"。
func revised_after(evidence_id: String) -> Array[String]:
	var out: Array[String] = []
	for e in events:
		if str(e.get("event_type", "")) != EV_JUDGMENT_REVISED:
			continue
		if str(e.get("cause", "")) != "evidence:" + evidence_id:
			continue
		var claim_id := str(e.get("claim_id", ""))
		if not (claim_id in out):
			out.append(claim_id)
	return out


# ─────────────────────────────────────────────────────────────
#  AI 咨询
# ─────────────────────────────────────────────────────────────
## 案件开始到现在过了多少毫秒。历史条目里存它，而不是存绝对时间戳 ——
## 复盘要回答的是"他先看了证据还是先问了 AI"。
func elapsed_msec() -> int:
	if _started_msec == 0:
		return 0
	return Time.get_ticks_msec() - _started_msec


func elapsed_seconds() -> float:
	return float(elapsed_msec()) / 1000.0


func consume_analyst_token() -> bool:
	if analyst_tokens <= 0:
		return false
	analyst_tokens -= 1
	analyst_tokens_changed.emit(analyst_tokens)
	return true


func note_consult() -> void:
	ai_calls += 1


func record_ai(entry: Dictionary) -> void:
	ai_history.append(entry)


## 用了模型的那几次（不含离线兜底）。只用于判断"这一节是不是在讲离线引擎"，
## **不再**用来给玩家打 AI 协作等级。
func ai_uses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in ai_history:
		if str(entry.get("source", "")) == "ai":
			out.append(entry)
	return out


# ─────────────────────────────────────────────────────────────
#  调查点
# ─────────────────────────────────────────────────────────────
func remaining() -> int:
	return maxi(points_total - points_used, 0)

func can_afford(cost: int) -> bool:
	return remaining() >= cost

func spend(cost: int) -> bool:
	if not can_afford(cost):
		return false
	points_used += cost
	points_changed.emit(remaining())
	return true


# ─────────────────────────────────────────────────────────────
#  证据
# ─────────────────────────────────────────────────────────────
func is_unlocked(id: String) -> bool:
	return id in unlocked

## 花点解锁一张证据卡。返回是否成功。
func unlock(id: String) -> bool:
	if is_unlocked(id):
		return true
	var e := CaseData.evidence(data, id)
	if e.is_empty():
		return false
	if not spend(int(e.get("cost", 1))):
		return false
	unlocked.append(id)
	unlocked_changed.emit(id)
	return true

func unlocked_evidence() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in unlocked:
		out.append(CaseData.evidence(data, id))
	return out

func classify(id: String, relevance: String, kind: String) -> void:
	classifications[id] = {"relevance": relevance, "kind": kind}

func classification_of(id: String) -> Dictionary:
	return classifications.get(id, {})

func mark_opened(id: String) -> void:
	if not (id in opened):
		opened.append(id)

func is_opened(id: String) -> bool:
	return id in opened

## 解锁顺序里的第几张（用于 Journey 上的 "After Evidence #04"）
func evidence_number(id: String) -> int:
	return int(CaseData.evidence(data, id).get("index", 0))


func clear() -> void:
	start(data)
