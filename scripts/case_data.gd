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
