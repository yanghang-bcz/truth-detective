class_name CaseData
extends RefCounted
## 案件数据的加载与查询。
##
## 案件内容全部放在 data/*.json 里，一行代码都不写进 UI。这样 Case 002 不需要
## 重写游戏，只需要换一份数据 —— 这个项目要证明的是"能承载多个案件的系统"，
## 不是"做死一个关卡"。

## 按语言加载案件。中文版是 data/case_001.zh.json；缺了就退回英文 ——
## 缺翻译的时候看到英文，比看到一片空白好。
## 语言不从 Locale 直接读：这个函数要能在 headless 工具里跑，
## 而 --script 模式下 autoload 是不注册的，引用 Locale 会直接编译失败。
static func load_localized(case_id: String, lang: String) -> Dictionary:
	var localized := "res://data/%s.%s.json" % [case_id, lang]
	if lang != "en" and FileAccess.file_exists(localized):
		return load_case(localized)
	return load_case("res://data/%s.json" % case_id)


## 读一份案件。返回的字典里会额外挂两个索引（下划线开头）：
##   _evidence: id -> 证据字典
##   _claims:   id -> Claim 字典
static func load_case(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("CaseData: 找不到案件文件 " + path)
		return {}
	var raw := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CaseData: " + path + " 不是合法的 JSON 对象")
		return {}
	var data: Dictionary = parsed

	# JSON 里的数字全是 float，这里统一收敛成 int，免得后面到处写 int(...)。
	data["investigation_points"] = int(data.get("investigation_points", 10))
	var evidence_index := {}
	for e in data.get("evidence", []):
		e["cost"] = int(e.get("cost", 1))
		e["index"] = int(e.get("index", 0))
		evidence_index[str(e.get("id", ""))] = e
	var claim_index := {}
	for c in data.get("claims", []):
		claim_index[str(c.get("id", ""))] = c
	data["_evidence"] = evidence_index
	data["_claims"] = claim_index
	diagnose(data)
	return data


static func evidence(data: Dictionary, id: String) -> Dictionary:
	var index: Dictionary = data.get("_evidence", {})
	return index.get(id, {})


static func claim(data: Dictionary, id: String) -> Dictionary:
	var index: Dictionary = data.get("_claims", {})
	return index.get(id, {})


static func claims(data: Dictionary) -> Array:
	return data.get("claims", [])


static func sources(data: Dictionary) -> Array:
	return data.get("sources", [])


## 这张证据属于哪个调查方向。
static func source_of(data: Dictionary, evidence_id: String) -> Dictionary:
	var wanted := str(evidence(data, evidence_id).get("source", ""))
	for s in sources(data):
		if str(s.get("id", "")) == wanted:
			return s
	return {}


## 一次"挑战我的判断"要说的话。数据和文本都在 JSON 里。
static func challenge(data: Dictionary, claim_id: String, judgment: String) -> String:
	var table: Dictionary = data.get("challenges", {})
	var by_claim: Dictionary = table.get(claim_id, {})
	return str(by_claim.get(judgment, ""))


## 当前还没覆盖到的信息缺口（"我还漏了什么"）。返回第一个能给出的提示。
static func first_gap(data: Dictionary, unlocked: Array) -> Dictionary:
	for gap in data.get("gaps", []):
		var covered := false
		for id in gap.get("requires_any", []):
			if id in unlocked:
				covered = true
				break
		if not covered:
			return gap
	return {}


# ─────────────────────────────────────────────────────────────
#  判断一致性评价（v0.3）
#
#  这一层只回答一个问题：**玩家的最终判断，是否落在案件参考判断的接受范围里。**
#  它不是批判性思维评分，也不是稳定的个人能力测评 —— 单局行为撑不住那种结论。
#
#  v0.2 只读 claim.verdict 一个字符串，于是 Claim D 被判为 unsupported、玩家选
#  insufficient 时会被标成"错误"，而案件数据本身早就写着两种都接受。
#  现在一律走 verdict_accepts（为空才回退到 verdict）。
# ─────────────────────────────────────────────────────────────
## 合法的判定标签。与 UIKit.JUDGMENT_ORDER 同源，但这里不能引用 UIKit ——
## CaseData 要被 headless 的 --script 工具调用，那个模式不注册 autoload。
const JUDGMENT_KEYS: Array[String] = ["supported", "suspicious", "unsupported", "insufficient"]


## 标签规范化。大小写、前后空格都不该改变含义。
static func normalize_judgment(value: String) -> String:
	return value.strip_edges().to_lower()


## 一条 Claim 接受的答案集合。
## 规则：verdict_accepts 非空就用它，否则回退到单个 verdict。
## 注意 verdict 自身也要在规范化之后被包含进来，不能因为大小写差异被意外排除。
static func accepted_verdicts(claim: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for raw in claim.get("verdict_accepts", []):
		var v := normalize_judgment(str(raw))
		if v != "" and not (v in out):
			out.append(v)
	if out.is_empty():
		var fallback := normalize_judgment(str(claim.get("verdict", "")))
		if fallback != "":
			out.append(fallback)
	return out


## 玩家的答案是否在参考判断的接受范围内。
## 未作答一律不算一致 —— "" 不是答案，不该被当成"碰巧对了"。
static func is_aligned(claim: Dictionary, judgment: String) -> bool:
	var answer := normalize_judgment(judgment)
	if answer == "":
		return false
	return answer in accepted_verdicts(claim)


## 整卷的一致性计数，返回 [一致条数, 总条数]。
static func alignment_tally(data: Dictionary, final_judgments: Dictionary) -> Array:
	var total := 0
	var hit := 0
	for c in claims(data):
		var id := str(c.get("id", ""))
		total += 1
		var answer := str(final_judgments.get(id, {}).get("judgment", ""))
		if is_aligned(c, answer):
			hit += 1
	return [hit, total]


## 开发期数据诊断。数据写错时**不要**静默把玩家判成错的 ——
## 那会让"案件数据有问题"伪装成"玩家答错了"，是最难查的一类 bug。
## 只在 debug 构建里跑，导出包里零开销。
static func diagnose(data: Dictionary) -> Array[String]:
	if not OS.is_debug_build():
		return []
	var problems: Array[String] = []
	for c in claims(data):
		var id := str(c.get("id", ""))
		var accepted := accepted_verdicts(c)
		if accepted.is_empty():
			problems.append("Claim %s 既没有 verdict_accepts 也没有 verdict" % id)
		for v in accepted:
			if not (v in JUDGMENT_KEYS):
				problems.append("Claim %s 接受了未知标签 %s" % [id, v])
		var declared := normalize_judgment(str(c.get("verdict", "")))
		if declared != "" and accepted.size() > 0 and not (declared in accepted):
			problems.append("Claim %s 的 verdict=%s 不在自己的 verdict_accepts 里" % [id, declared])
	for p in problems:
		push_warning("CaseData: " + p)
	return problems


# ─────────────────────────────────────────────────────────────
#  复盘反馈（v0.3）
#
#  个性化反馈走 Deterministic Feedback：**不用 LLM 现场编**。
#  依据玩家实际选错的那个选项，取一条预先写好、经过人工审核的说明。
#  "所有错误答案共用一段安慰话"是 v0.2 最大的问题 —— 玩家读完不知道自己错在哪。
# ─────────────────────────────────────────────────────────────
## 某个 Claim 下，玩家选了某个（不在接受范围内的）答案时的针对性说明。
## 返回 {text, training}；没有对应条目时返回空字典，界面据此不显示这一块
## —— 宁可不说话，也不要硬套一段模板。
static func feedback_for(data: Dictionary, claim_id: String, judgment: String) -> Dictionary:
	var table: Dictionary = data.get("feedback", {}).get("claims", {})
	var by_claim: Dictionary = table.get(claim_id, {})
	var options: Dictionary = by_claim.get("options", {})
	return options.get(normalize_judgment(judgment), {})


## 四条全部一致时的总结（不含能力等级，只讲证据边界）。
static func feedback_all_aligned(data: Dictionary) -> String:
	return str(data.get("feedback", {}).get("all_aligned", ""))


## 判断与参考一致、但关键证据没解锁时的那句提示（§9.6）。
## 案件数据要能可靠判定"关键证据"范围才显示 —— decisive_evidence 为空就不显示。
static func feedback_aligned_unseen(data: Dictionary, claim_id: String,
		unlocked: Array) -> String:
	var claim := claim(data, claim_id)
	var decisive: Array = claim.get("decisive_evidence", [])
	if decisive.is_empty():
		return ""
	for id in decisive:
		if str(id) in unlocked:
			return ""
	return str(data.get("feedback", {}).get("aligned_unseen", ""))


## 锚定在参考标签上的一句释义（§9.7）。避免把 Unsupported 读成"已证明为假"。
static func verdict_gloss(data: Dictionary, judgment: String) -> String:
	var table: Dictionary = data.get("feedback", {}).get("gloss", {})
	return str(table.get(normalize_judgment(judgment), ""))
