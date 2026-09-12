class_name AiResponseValidator
extends RefCounted
## 显示之前的最后一道闸。
##
## 提示词是「请求模型守规矩」，这里是「假设它不守规矩」。两者都要有：
## 只靠提示词的 AI 系统，出问题的那一次一定发生在演示的时候。
##
## 检查四类问题：
##   1) 提到了未解锁的证据编号（LEAKED）—— 这是最严重的一类，等于泄题；
##   2) 提到了根本不存在的编号（UNKNOWN）—— 属于编造；
##   3) 直接把答案说出来了（FINAL_ANSWER）—— 替玩家做完了题；
##   4) 空回答（EMPTY）。
##
## 任何一类都**不显示给玩家**，由上层换成离线引擎的答复，并且不扣次数。
## 另外它还负责长度收敛：模型天然爱写论文，而这一屏最多两段。

enum Verdict { OK, EMPTY, LEAKED, UNKNOWN, FINAL_ANSWER }

## 按语言给上限。中文一个字的信息量远大于英文一个词，两者不能用同一个数字。
const MAX_CHARS := {"en": 700, "zh": 320}

## 直接给答案的说法。中英都查 —— 只查英文的话，中文答复里模型会畅通无阻。
const ANSWER_PHRASES: Array[String] = [
	"correct answer", "final answer", "the answer is", "you should choose",
	"should select", "正确答案", "标准答案", "答案是", "应该选", "应当选",
]

const ID_PATTERN := "\\bE(\\d{1,2})\\b"
const HASH_PATTERN := "#\\s?(\\d{1,2})\\b"


## 返回 {verdict, reason, ids}。ids 是答复里引用到的证据编号，供「Based on」那一行用。
static func check(text: String, unlocked: Array, known: Array) -> Dictionary:
	var body := text.strip_edges()
	if body == "":
		return _verdict(Verdict.EMPTY, "empty", [])

	var lower := body.to_lower()
	for phrase in ANSWER_PHRASES:
		if lower.contains(phrase):
			return _verdict(Verdict.FINAL_ANSWER, phrase, [])

	var ids := cited_ids(body)
	var unlocked_set := _upper_set(unlocked)
	var known_set := _upper_set(known)
	for id in ids:
		if not known_set.has(id):
			return _verdict(Verdict.UNKNOWN, id, ids)
		if not unlocked_set.has(id):
			return _verdict(Verdict.LEAKED, id, ids)
	return _verdict(Verdict.OK, "", ids)


## 把答复里出现的所有证据编号抓出来。两种写法都要认：
## 数据里用的是 E01，而模型（和本案文案）也爱写 Evidence #04。
static func cited_ids(text: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile(ID_PATTERN)
	for m in re.search_all(text):
		_push_unique(out, "E%02d" % int(m.get_string(1)))
	re.compile(HASH_PATTERN)
	for m in re.search_all(text):
		_push_unique(out, "E%02d" % int(m.get_string(1)))
	return out


## 超长时在句子边界收尾，而不是把一句话砍成两半。
static func clamp(text: String, lang: String) -> String:
	var cap := int(MAX_CHARS.get(lang, 700))
	var body := text.strip_edges()
	if body.length() <= cap:
		return body
	var head := body.substr(0, cap)
	for mark in ["。", "！", "？", ". ", "! ", "? ", "\n"]:
		var at := head.rfind(mark)
		if at > cap * 0.55:
			return head.substr(0, at + mark.length()).strip_edges()
	return head.strip_edges() + "…"


static func _verdict(v: Verdict, reason: String, ids: Array[String]) -> Dictionary:
	return {"verdict": v, "reason": reason, "ids": ids}


static func _upper_set(ids: Array) -> Dictionary:
	var out := {}
	for raw in ids:
		out[str(raw).strip_edges().to_upper()] = true
	return out


static func _push_unique(into: Array[String], value: String) -> void:
	if not into.has(value):
		into.append(value)
