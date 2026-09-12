class_name AiContextBuilder
extends RefCounted
## 把「玩家此刻看得见的东西」整理成模型可以看的 context。
##
## 这个类的全部价值在于它是一个**白名单**。
## 只有下面 EVIDENCE_FIELDS / CLAIM_FIELDS 里点名的字段会被送出去，其余一律不进，
## 包括：
##   kind_answer / relevance_answer —— 分类题的答案；
##   analyst                      —— 离线引擎写好的现成答案（送进去模型只会复述）；
##   verdict / verdict_accepts / decisive_evidence / explanation / note —— 终局答案；
##   challenges / gaps / debrief   —— 复盘用的解读。
##
## 为什么不用黑名单：case_001.json 把「玩家那份」和「答案键」放在同一个文件里，
## 黑名单是「漏一个字段就泄露」，白名单是「漏一个字段只是少给模型一点信息」。
## 以后有人给某张证据加个 analyst_v2，黑名单必然漏，白名单不会。

const EVIDENCE_FIELDS: Array[String] = [
	"id", "title", "type", "reliability",
	"context", "summary", "body", "proves", "does_not_prove",
]
const CLAIM_FIELDS: Array[String] = ["id", "short", "text"]


## 产出模型能看到的全部内容。**不包含任何关于「还有几条没解锁」的信息** ——
## 连总数都不给：知道总数就等于知道了谜题的规模。
static func build(data: Dictionary, unlocked: Array, claim_id: String,
		judgment: String, confidence: int, action: String) -> Dictionary:
	var evidence: Array = []
	var seen := {}
	for raw_id in unlocked:
		var id := str(raw_id)
		if seen.has(id):
			continue
		seen[id] = true
		var card := CaseData.evidence(data, id)
		if card.is_empty():
			continue
		evidence.append(_pick(card, EVIDENCE_FIELDS))

	var ctx := {
		"action": action,
		"claim_under_review": _pick(CaseData.claim(data, claim_id), CLAIM_FIELDS),
		"unlocked_evidence": evidence,
		"player_current_judgment": judgment if judgment != "" else "not stated yet",
		"player_confidence": confidence,
	}

	# 帖子正文是「网上在传的东西」，开场页就摆在玩家眼前，属于公开内容。
	var post: Dictionary = data.get("post", {})
	var post_text := str(post.get("body", "")).strip_edges()
	if post_text != "":
		ctx["public_post_text"] = post_text
	return ctx


## 按白名单从一张卡里取字段。取不到就不放 —— 宁缺勿滥。
static func _pick(src: Dictionary, fields: Array[String]) -> Dictionary:
	var out := {}
	for f in fields:
		if src.has(f):
			out[f] = src[f]
	return out
