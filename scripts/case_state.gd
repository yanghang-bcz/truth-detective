extends Node
## 案件期间的状态中枢（autoload 单例，全局名 CaseState）。
##
## 刻意做成单例而不是在节点之间传引用：调查点、已解锁证据、判定历史
## 这三样东西需要同时被四个界面阶段读写，而且 Debrief 要复盘的东西
## 恰恰是"玩家中途改过什么" —— 状态必须是一份、连续的、可回溯的。
##
## 注意：这个脚本故意不写 class_name。它已经作为 autoload 占用 "CaseState"
## 这个全局名，再加 class_name 会撞名。

signal points_changed(remaining: int)
signal unlocked_changed(id: String)
signal judgment_recorded(entry: Dictionary)

const CASE_ID := "case_001"

var data: Dictionary = {}

var points_total: int = 10
var points_used: int = 0

var unlocked: Array[String] = []
var opened: Array[String] = []         ## 打开过详情页的证据（unlocked 是解锁，opened 是读过）
var classifications: Dictionary = {}   ## evidence id -> {"relevance": .., "kind": ..}
var focused_evidence: String = ""

## 判定历史。每条：
##   {claim, judgment, confidence, trigger, points_used, evidence_seen}
## trigger 是"触发这次记录的事件"，Debrief 的 Your Judgment Journey 全靠它。
var history: Array[Dictionary] = []
var initial_judgments: Dictionary = {}
var final_judgments: Dictionary = {}

var ai_calls: int = 0


func _ready() -> void:
	data = CaseData.load_localized(CASE_ID, Locale.lang)
	if data.is_empty():
		push_error("CaseState: 无法加载 " + CASE_ID)


## 切语言时重新读一遍内容。**只换文本，不动进度** ——
## 玩家翻到一半换语言，调查点、已开档案、判定历史都该原样还在。
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
	history.clear()
	initial_judgments.clear()
	final_judgments.clear()
	focused_evidence = ""
	ai_calls = 0
	points_changed.emit(remaining())


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


# ─────────────────────────────────────────────────────────────
#  判定
# ─────────────────────────────────────────────────────────────
## 记录一次判定。两种情况下不写新条目：
##   1) 和该 Claim 上一条完全相同（滑条来回蹭不该留下痕迹）；
##   2) 和该 Claim 上一条同属一个触发事件（看完同一张证据改好几次，只算一次）。
## Journey 上要看到的是"看法在哪些节点变了"，不是操作日志。
func record_judgment(claim: String, judgment: String, confidence: int, trigger: String) -> void:
	var entry := {
		"claim": claim,
		"judgment": judgment,
		"confidence": confidence,
		"trigger": trigger,
		"points_used": points_used,
		"evidence_seen": unlocked.size(),
	}
	for i in range(history.size() - 1, -1, -1):
		if history[i]["claim"] != claim:
			continue
		if history[i]["judgment"] == judgment and history[i]["confidence"] == confidence:
			return
		if str(history[i]["trigger"]) == trigger:
			history[i] = entry
			judgment_recorded.emit(entry)
			return
		break
	history.append(entry)
	judgment_recorded.emit(entry)

func set_initial(claim: String, judgment: String, confidence: int) -> void:
	initial_judgments[claim] = {"judgment": judgment, "confidence": confidence}

func set_final(claim: String, judgment: String, confidence: int) -> void:
	final_judgments[claim] = {"judgment": judgment, "confidence": confidence}

func journey(claim: String = "") -> Array[Dictionary]:
	if claim == "":
		return history
	var out: Array[Dictionary] = []
	for e in history:
		if e["claim"] == claim:
			out.append(e)
	return out


# ─────────────────────────────────────────────────────────────
#  Debrief 用的三项推理模式
# ─────────────────────────────────────────────────────────────
## 上下文意识：是否主动翻到过长视频 / 完整录像。
func context_awareness() -> bool:
	return is_unlocked("E04") or is_unlocked("E08")

## 过度概括：有没有让"一个人"或"一代人"从单次事件里被推出来。
func overgeneralised() -> bool:
	for claim_id in ["C", "D"]:
		var f: Dictionary = final_judgments.get(claim_id, {})
		if str(f.get("judgment", "")) == "supported":
			return true
	return false

## 过早下结论：在还没看到能撑住高置信度的材料之前，就先给了很高的把握。
##
## 判据：在翻到"第二段录像"（E04）之前，就已经在 Claim B 上记录过 70% 以上的把握。
## 这里用记录条目的 evidence_seen 近似 —— 历史条目本来就带着当时看过几张证据，
## 所以不需要额外标记，直接从历史里读得出来。
func premature() -> bool:
	var e04_seen_at := history.size()
	for i in range(history.size()):
		if int(history[i].get("evidence_seen", 0)) >= 3:
			e04_seen_at = i
			break
	for i in range(history.size()):
		var entry: Dictionary = history[i]
		if str(entry["claim"]) != "B":
			continue
		if int(entry["confidence"]) >= 70 and i < e04_seen_at:
			return true
	return false

func clear() -> void:
	start(data)
