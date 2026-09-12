extends Node
## 语言状态与界面文案。
##
## 分两层，因为这两类文字的生命周期不一样：
##   界面文案（按钮、小标题、提示）写在下面这张表里，用 t() 取 —— 它跟着代码走；
##   案件内容（帖文、证据、Claim、复盘）在 data/case_001.<lang>.json，
##   由 CaseData 按当前语言挑文件 —— 它跟着剧本走。
##
## 为什么不接 Godot 自带的 TranslationServer + .translation：那套要先生成资源、
## 要在编辑器里配导入选项，而这个 headless 工具链里最容易出问题的恰好就是
## "资源没导入导致字符串变回 key"。只有两种语言、文案量也不大，一张常量表更直接。
##
## 另一个约束：**不要把 tr() 用在会显示给玩家的案件内容上**，
## 那些一律走 CaseData，否则同一个句子的两种语言会分散在两个地方，改的时候必漏。

signal changed(lang: String)

const LANGS: Array[String] = ["en", "zh"]

var lang := "en"

func _ready() -> void:
	_register_cjk_fallback()
	_push_judgment_names()


## Web 导出版没有系统字体可用：font_ui() 里的 SF Pro / PingFang 在浏览器里
## 一个都不存在，中文会变成一排空方块（tofu）。桌面端不受影响是因为 macOS
## 有 PingFang 兜底。
## 解法：工程内嵌思源黑体（OFL，见 ASSET_CREDITS.md），注册成**全局兜底字体**。
## 只在"指定字体缺这个字"时才会被用到，所以桌面端外观完全不变，
## Web 端拉丁字符继续走 Godot 内置字体，中文落到思源黑体。
func _register_cjk_fallback() -> void:
	const CJK_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
	if not ResourceLoader.exists(CJK_PATH):
		push_warning("CJK fallback font missing: " + CJK_PATH)
		return
	var cjk: Font = load(CJK_PATH)
	if cjk == null:
		return
	ThemeDB.fallback_font = cjk
	## 注意：ThemeDB.fallback_font 在 Web 导出包里不会被当缺字形兜底用
	## （实测所有取字路径都渲染成 codepoint 方框）。可靠的兜底是
	## Font.fallbacks 数组——HUD 这类不指定字体的控件走默认主题字体，
	## 把它也挂上。案件界面里显式指定字体的控件由 UIKit._cached 统一挂。
	var dt := ThemeDB.get_default_theme()
	if dt != null and dt.default_font != null and not dt.default_font.fallbacks.has(cjk):
		dt.default_font.fallbacks.append(cjk)

func set_lang(l: String) -> void:
	if not DICT.has(l) or l == lang:
		return
	lang = l
	_push_judgment_names()
	changed.emit(lang)

## 判定名是 UIKit 用来画四个按钮的，但它住在语言表里。
## 与其让 UIKit 去引用 autoload（那会让 --script 模式的工具链编译失败），
## 不如由这里主动推过去。
func _push_judgment_names() -> void:
	var table := {}
	for key in UIKit.JUDGMENT_ORDER:
		table[key] = t("j." + key)
	UIKit.judgment_names = table

## 两种语言之间来回切。顶栏那个小按钮就调这一个函数。
func toggle() -> void:
	set_lang(LANGS[(LANGS.find(lang) + 1) % LANGS.size()])

func t(key: String) -> String:
	var table: Dictionary = DICT.get(lang, {})
	if table.has(key):
		return str(table[key])
	return str(DICT["en"].get(key, key))

## 需要往文案里塞数字的时候用这个（"%d / %d" 这类）。
func tf(key: String, args: Array) -> String:
	return t(key) % args

## 语言自己的名字。永远用该语言写自己（EN / 中文），不跟着界面语言走。
func self_name(l: String) -> String:
	match l:
		"zh": return "中文"
		_: return "EN"

# ─────────────────────────────────────────────────────────────
const DICT := {
"en": {
	"lang.self": "EN",
	"lang.tip": "Language",

	"phase.intro": "CASE OPENING",
	"phase.board": "INVESTIGATION BOARD",
	"phase.final": "FINAL JUDGMENT",
	"phase.debrief": "REASONING DEBRIEF",
	"bar.points": "IP",

	"hud.objective": "Objective — the metro entrance",
	"hud.interact": "Investigate the metro entrance",
	"hud.reopen": "Reopen the case file",

	"trigger.initial": "First reading",
	"trigger.final": "Final judgment",
	"trigger.analyst": "After consulting the Analyst",
	"trigger.evidence": "After Evidence %s",
	"trigger.revised": "Revised",

	"j.supported": "Supported",
	"j.suspicious": "Suspicious",
	"j.unsupported": "Unsupported",
	"j.insufficient": "Not Enough Evidence",

	"post.stat_fmt": "%s %s",
	"post.views": "views",
	"post.likes": "likes",
	"post.comments": "comments",
	"post.shares": "shares",

	"common.confidence": "confidence",

	"intro.task": "Your first task",
	"intro.task_body": "Judge the claim below. The post above it is what the internet says — not what you are judging.",
	"intro.claim_label": "Claim under review",
	"intro.hint": "Record your first impression.",
	"intro.begin": "Begin Investigation",
	"intro.need_pick": "Pick a judgment first.",

	"board.sources": "Investigation sources",
	"board.evidence": "Evidence board",
	"board.opened": "%d / %d opened",
	"board.empty_title": "the board is empty",
	"board.empty_body": "Nothing filed yet. Open a lead on the left.",
	"board.current": "Current judgment",
	"board.claim_short": "claim %s · %s",
	"board.read": "read",
	"board.open": "open",
	"board.cost": "%d IP",
	"board.hint": "Ten points will not cover all eight files. Spend them where they change your mind.",
	"board.broke": "Not enough points — %s costs %d, you have %d.",
	"board.revised": "revised",
	"board.submit": "Submit Investigation",

	"detail.relevance": "How close is this to the incident?",
	"detail.kind": "What kind of thing is it?",
	"detail.reading": "your reading",
	"detail.establishes": "What this establishes",
	"detail.not_establishes": "What this does not establish",
	"detail.type": "type",
	"detail.reliability": "reliability",
	"detail.context": "context",
	"detail.cost": "cost",
	"detail.note": "Scroll for the rest · ESC closes",
	"detail.file": "File It",

	"analyst.title": "Analyst",
	"analyst.cost": "%d IP / consult",
	"analyst.blurb": "Reads only what you have opened.",
	"analyst.a.explain": "Explain this evidence",
	"analyst.a.not_prove": "What it does not prove",
	"analyst.a.challenge": "Challenge my judgment",
	"analyst.a.missing": "What am I missing?",
	"analyst.empty": "no question asked yet",
	"analyst.based": "based on",
	"analyst.footer": "local reasoning · %d of %d opened",
	"analyst.none": "No counter-argument is available for this combination yet.",
	"analyst.all_open": "Every category is open. The remaining question is not what else exists, but what the record can support.",
	"analyst.not_prove_head": "Nothing in this card establishes the following:",

	"analyst.blurb_ai": "Reads only what you have opened. %d AI consults per case.",
	"analyst.consults": "%d / %d consults left",
	"analyst.offline": "offline reasoning",
	"analyst.no_key": "No AI Analyst is configured in this build. The investigation, and the offline Analyst, remain fully playable.",
	"analyst.busy": "Analysing your reasoning…",
	"analyst.based_only": "Based only on the evidence currently available to you.",
	"analyst.blocked": "That reply referred to material outside your file, so it was withheld.",
	"analyst.failed": "The Analyst could not respond. No consult was used.",
	"analyst.no_points": "Not enough investigation points left to consult the Analyst.",
	"analyst.cost_ai": "1 consult",
	"analyst.footer_ai": "model reply · %d of %d opened",
	"analyst.footer_cache": "cached reply · %d of %d opened",

	"final.title": "Submit your reading of the record",
	"final.lede": "Four claims, one incident. Judge each on its own.",
	"final.unanswered": "unanswered",
	"final.back": "← Back to Investigation",
	"final.submit": "Submit Investigation",
	"final.missing": "Still unanswered: %s",

	"debrief.title": "How your reading changed",
	"debrief.journey": "Your judgment journey",
	"debrief.review": "Claim review",
	"debrief.patterns": "Reasoning patterns",
	"debrief.your_answer": "your answer",
	"debrief.correct": "what the evidence supports",
	"debrief.no_answer": "no answer",
	"debrief.strong": "strong",
	"debrief.weak": "needs attention",
	"debrief.files": "files opened",
	"debrief.revisions": "board revisions",
	"debrief.consults": "analyst consults",
	"debrief.points": "points spent",
	"debrief.others": "Also revised: %s.",
	"debrief.no_journey": "No judgments were recorded.",
	"debrief.claim_of": "claim %s · %s",
	"debrief.footer": "Case 001 ends here.",
	"debrief.return": "Return to Stillwater Corner",

	"debrief.ai": "AI collaboration",
	"debrief.ai_count": "AI consults used: %d of %d",
	"debrief.ai_none": "The Analyst was never consulted. Every reading here is your own.",
	"debrief.ai_offline_only": "The Analyst ran locally — no AI is configured in this build, so this section is about the offline engine.",
	"debrief.ai_strong": "You asked the Analyst to challenge your own conclusion, and you did it after new evidence. That is the order that helps.",
	"debrief.ai_weak": "The Analyst was consulted before any evidence had been opened, and never asked to challenge you. Asking first tends to turn it into an answer machine.",
	"debrief.ai_balanced": "The Analyst was used, but not to test your own reading. The stronger move is to ask it to challenge you after something new arrives.",
	"debrief.balanced": "balanced",
},
"zh": {
	"lang.self": "中文",
	"lang.tip": "语言",

	"phase.intro": "案件开场",
	"phase.board": "调查板",
	"phase.final": "最终判定",
	"phase.debrief": "推理复盘",
	"bar.points": "调查点",

	"hud.objective": "目标 —— 地铁口",
	"hud.interact": "调查地铁口",
	"hud.reopen": "重新打开案件档案",

	"trigger.initial": "初次判断",
	"trigger.final": "最终判定",
	"trigger.analyst": "咨询分析员之后",
	"trigger.evidence": "看过 %s 之后",
	"trigger.revised": "修订",

	"j.supported": "成立",
	"j.suspicious": "存疑",
	"j.unsupported": "不成立",
	"j.insufficient": "证据不足",

	"post.stat_fmt": "%s%s",
	"post.views": "播放",
	"post.likes": "赞",
	"post.comments": "评论",
	"post.shares": "转发",

	"common.confidence": "确定程度",

	"intro.task": "你的第一个任务",
	"intro.task_body": "判断下面这句话。上面的帖子是网上在传的内容，不是你要判断的对象。",
	"intro.claim_label": "待判断的说法",
	"intro.hint": "记下你的第一印象。",
	"intro.begin": "开始调查",
	"intro.need_pick": "先选一个判断。",

	"board.sources": "调查方向",
	"board.evidence": "证据板",
	"board.opened": "已开启 %d / %d",
	"board.empty_title": "板子上还是空的",
	"board.empty_body": "还没有归档。从左边挑一条线索。",
	"board.current": "当前判断",
	"board.claim_short": "说法 %s · %s",
	"board.read": "已读",
	"board.open": "打开",
	"board.cost": "%d 点",
	"board.hint": "十点买不下全部八份材料。花在那些能改变你想法的东西上。",
	"board.broke": "调查点不够 —— %s 需要 %d 点，你还有 %d 点。",
	"board.revised": "已修订",
	"board.submit": "提交调查结果",

	"detail.relevance": "它离事件本身有多近？",
	"detail.kind": "它属于哪一类？",
	"detail.reading": "你的判读",
	"detail.establishes": "这份材料能立住什么",
	"detail.not_establishes": "这份材料立不住什么",
	"detail.type": "类型",
	"detail.reliability": "可信度",
	"detail.context": "语境",
	"detail.cost": "成本",
	"detail.note": "向下滚动看全文 · ESC 关闭",
	"detail.file": "归档",

	"analyst.title": "分析员",
	"analyst.cost": "%d 点 / 次",
	"analyst.blurb": "只读你已经打开过的材料。",
	"analyst.a.explain": "解释这份证据",
	"analyst.a.not_prove": "它证明不了什么",
	"analyst.a.challenge": "质疑我的判断",
	"analyst.a.missing": "我漏了什么？",
	"analyst.empty": "还没有提问",
	"analyst.based": "依据",
	"analyst.footer": "本地推理 · 已开启 %d / %d",
	"analyst.none": "这个组合下暂时没有可用的反驳。",
	"analyst.all_open": "每一类都开了。剩下的问题不是\"还有什么\"，而是\"这份记录到底能撑住什么\"。",
	"analyst.not_prove_head": "这张卡里没有任何内容能立住下面这些：",

	"analyst.blurb_ai": "只读你已经打开过的材料。每个案件 %d 次 AI 咨询。",
	"analyst.consults": "还剩 %d / %d 次咨询",
	"analyst.offline": "离线推理",
	"analyst.no_key": "这个版本没有配置 AI 分析员。调查流程和离线分析员都可以正常玩。",
	"analyst.busy": "正在读你的推理…",
	"analyst.based_only": "只基于你目前掌握的证据。",
	"analyst.blocked": "这次回答提到了你档案之外的材料，已被拦下。",
	"analyst.failed": "分析员没能回应。这次没有消耗次数。",
	"analyst.no_points": "调查点不够了，咨询不了分析员。",
	"analyst.cost_ai": "1 次咨询",
	"analyst.footer_ai": "模型回答 · 已开启 %d / %d",
	"analyst.footer_cache": "缓存回答 · 已开启 %d / %d",

	"final.title": "交出你对这份记录的读法",
	"final.lede": "同一个事件，四句话。一句一句判。",
	"final.unanswered": "未作答",
	"final.back": "← 回到调查板",
	"final.submit": "提交判定",
	"final.missing": "还没作答：%s",

	"debrief.title": "你的读法是怎么变的",
	"debrief.journey": "你的判断轨迹",
	"debrief.review": "逐条回顾",
	"debrief.patterns": "推理模式",
	"debrief.your_answer": "你的答案",
	"debrief.correct": "证据能支持的答案",
	"debrief.no_answer": "没有作答",
	"debrief.strong": "稳",
	"debrief.weak": "值得注意",
	"debrief.files": "已开档案",
	"debrief.revisions": "改判次数",
	"debrief.consults": "咨询分析员",
	"debrief.points": "花掉的点数",
	"debrief.others": "过程中还改过：%s。",
	"debrief.no_journey": "没有记录到任何判断。",
	"debrief.claim_of": "说法 %s · %s",
	"debrief.footer": "案件 001 到此结束。",
	"debrief.return": "回到静水街角",

	"debrief.ai": "AI 协作",
	"debrief.ai_count": "AI 咨询用掉：%d / %d",
	"debrief.ai_none": "你没有咨询过分析员。这里的每一句读法都是你自己的。",
	"debrief.ai_offline_only": "分析员一直是离线推理 —— 这个版本没有配置 AI，所以这一节说的是离线引擎。",
	"debrief.ai_strong": "你让分析员质疑你自己的结论，而且是在看到新证据之后才问的。这个顺序才有用。",
	"debrief.ai_weak": "你在打开任何证据之前就去问了分析员，而且从没让它质疑你。先问，容易把它当成答题机。",
	"debrief.ai_balanced": "你用了分析员，但没有用它检验自己的读法。更有力的做法是：等新东西出现之后，让它来质疑你。",
	"debrief.balanced": "均衡",
},
}
