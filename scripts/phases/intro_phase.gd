class_name IntroPhase
extends CasePhase
## 案件开场。这一页要回答玩家两个问题："我在看什么"和"现在要我做什么"。
##
## 所以它只有两块内容：上面是网上正在传的东西（冷色、发光，属于"屏幕"那一类），
## 下面是你要判的那一句话（暖色、纸面手感，属于"文件"那一类）。
##
## 中间那行"你的第一个任务"是后加的，而且很关键：帖子标题是一句关于一代人的问句，
## 待判的 Claim 是一句关于某个动作的陈述 —— 两者层级完全不同。
## 并排放而不加区分，玩家会不知道自己在判哪一句。
##
## 另外，待判的那条 Claim 不写内部编号（不写 "CLAIM B"）。玩家此刻不该知道
## 后面还有 A、C、D，也不该猜到这是一把四级的梯子。编号留到最终判定再出现。

var _judgment_row: JudgmentRow
var _confidence_getter: Callable
var _hint: Label
var _idle_hint := ""
var _tracking: FontVariation

func _build() -> void:
	# 玩家已经给过初始判定的话（切语言会让这一页被重建），把读数还回去 ——
	# 否则换一次语言会像是"我刚选的被吃掉了"。
	var stored: Dictionary = CaseState.initial_judgments.get("B", {})

	var c := scroll_column(760)
	c.add_child(UIKit.gap(12))

	c.add_child(UIKit.eyebrow(str(case.get("opening", {}).get("eyebrow", ""))))
	c.add_child(UIKit.gap(10))
	c.add_child(_title())
	c.add_child(UIKit.gap(16))
	c.add_child(UIKit.rule(Color(UIKit.INK4.r, UIKit.INK4.g, UIKit.INK4.b, 0.9)))
	c.add_child(UIKit.gap(22))

	c.add_child(_post_card())
	c.add_child(UIKit.gap(26))

	c.add_child(section(Locale.t("intro.task")))
	c.add_child(UIKit.gap(10))
	c.add_child(UIKit.paragraph(Locale.t("intro.task_body"), 14,
		Color(UIKit.FOG.r, UIKit.FOG.g, UIKit.FOG.b, 0.82)))
	c.add_child(UIKit.gap(18))
	c.add_child(_claim_quote())
	c.add_child(UIKit.gap(18))

	_judgment_row = JudgmentRow.make(false, true)
	_judgment_row.value = str(stored.get("judgment", ""))
	c.add_child(_judgment_row)
	c.add_child(UIKit.gap(18))

	var confidence := confidence_row(int(stored.get("confidence", 50)))
	c.add_child(confidence[0])
	_confidence_getter = confidence[1]
	c.add_child(UIKit.gap(10))

	_idle_hint = Locale.t("intro.hint")
	_hint = UIKit.paragraph(_idle_hint, 13, UIKit.SLATE)
	c.add_child(_hint)
	c.add_child(UIKit.gap(18))

	c.add_child(_footer())
	c.add_child(UIKit.gap(20))

	stagger_fade(c, 0.05, 0.40)
	_focus_title()

# ─────────────────────────────────────────────────────────────
#  标题
# ─────────────────────────────────────────────────────────────
func _title() -> Label:
	# 字距从宽收到零。0.85 秒，比单纯淡入多一点点"对焦"的感觉，
	# 而且它只动一个 FontVariation 属性，几乎不花钱。
	_tracking = FontVariation.new()
	_tracking.base_font = UIKit.font_display()
	_tracking.spacing_glyph = 11
	var l := UIKit.label(str(case.get("title", "")), 38, UIKit.CHALK, _tracking)
	l.add_theme_constant_override("line_spacing", 6)
	return l

func _focus_title() -> void:
	if _tracking == null:
		return
	var t := create_tween()
	t.tween_property(_tracking, "spacing_glyph", 0.0, 0.85)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# ─────────────────────────────────────────────────────────────
#  那条被转发的帖子
# ─────────────────────────────────────────────────────────────
func _post_card() -> Control:
	var post: Dictionary = case.get("post", {})
	var card := UIKit.screen_panel(16)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)

	col.add_child(_post_header(post))

	var frame := VideoStill.new()
	frame.custom_minimum_size = Vector2(0, 232)
	col.add_child(frame)

	# 标题用无衬线而不是衬线：它是平台上的一句话，不是档案里的一行字。
	var caption := UIKit.label(str(post.get("caption", "")), 20, UIKit.CHALK, UIKit.font_ui())
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(caption)

	col.add_child(UIKit.paragraph(str(post.get("body", "")), 14,
		Color(UIKit.SLATE.r, UIKit.SLATE.g, UIKit.SLATE.b, 1.0)))

	col.add_child(UIKit.hairline(Color(UIKit.SCREEN_EDGE.r, UIKit.SCREEN_EDGE.g, UIKit.SCREEN_EDGE.b, 0.9)))

	col.add_child(_post_stats(post))
	return card

func _post_header(post: Dictionary) -> Control:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 11)

	var avatar := PanelContainer.new()
	var avatar_sb := StyleBoxFlat.new()
	avatar_sb.bg_color = Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, 0.16)
	avatar_sb.set_corner_radius_all(3)
	avatar_sb.set_border_width_all(1)
	avatar_sb.border_color = Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, 0.40)
	avatar_sb.content_margin_left = 9
	avatar_sb.content_margin_right = 9
	avatar_sb.content_margin_top = 5
	avatar_sb.content_margin_bottom = 5
	avatar.add_theme_stylebox_override("panel", avatar_sb)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar.add_child(UIKit.label("CP", 11, UIKit.CYAN, UIKit.tracked(UIKit.font_mono(), 1)))
	head.add_child(avatar)

	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 1)
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	names.add_child(UIKit.label(str(post.get("display_name", "")), 14, UIKit.CHALK, UIKit.font_ui()))
	names.add_child(UIKit.meta(str(post.get("handle", "")), 10, UIKit.CYAN, 1))
	head.add_child(names)
	head.add_child(UIKit.fill(UIKit.hgap(0)))

	# 平台名 + 时间。两样都是"这条内容在平台上"的证据，而不是内容本身。
	var stamp := UIKit.meta("%s · %s" % [str(post.get("platform", "")), str(post.get("timestamp", ""))],
		10, UIKit.MUTED, 2)
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(stamp)
	return head

## 传播数字。播放量放在最前面并且提亮 —— 这一页要玩家先意识到"它已经被看了很多次"，
## 那是这段画面之所以值得怀疑的唯一理由。
func _post_stats(post: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	row.add_child(UIKit.meta(_stat(str(post.get("views", "")), "post.views"), 10, UIKit.FOG, 1))
	for pair in [["likes", "post.likes"], ["comments", "post.comments"], ["shares", "post.shares"]]:
		row.add_child(UIKit.meta(_stat(str(post.get(pair[0], "")), pair[1]), 10, UIKit.SLATE, 1))

	row.add_child(UIKit.fill(UIKit.hgap(0)))
	row.add_child(UIKit.meta(str(post.get("topic", "")), 10, UIKit.CYAN, 1))
	return row

func _stat(value: String, unit_key: String) -> String:
	return Locale.t("post.stat_fmt") % [value, Locale.t(unit_key)]

# ─────────────────────────────────────────────────────────────
#  待判的那一条
# ─────────────────────────────────────────────────────────────
func _claim_quote() -> Control:
	var claim := CaseData.claim(case, str(case.get("claim_for_intro", "B")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var bar := ColorRect.new()
	bar.color = UIKit.LAMP_DIM
	bar.custom_minimum_size = Vector2(2, 0)
	bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(bar)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UIKit.meta(Locale.t("intro.claim_label"), 10, UIKit.LAMP_DIM.lightened(0.30), 3))
	col.add_child(UIKit.quote("“" + str(claim.get("text", "")) + "”", 20))
	row.add_child(col)
	return row

# ─────────────────────────────────────────────────────────────
func _footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.add_child(UIKit.fill(UIKit.hgap(0)))

	var _start_button := UIKit.primary_button(Locale.t("intro.begin"))
	_start_button.custom_minimum_size = Vector2(268, 44)
	_start_button.pressed.connect(_on_start)
	row.add_child(_start_button)
	return row

func _on_start() -> void:
	if _judgment_row.value == "":
		_hint.text = Locale.t("intro.need_pick")
		_hint.add_theme_color_override("font_color", UIKit.LAMP)
		var tween := create_tween()
		tween.tween_property(_hint, "modulate", Color(1.5, 1.2, 0.9, 1.0), 0.14)
		tween.tween_property(_hint, "modulate", Color.WHITE, 0.6)
		return
	var confidence: int = _confidence_getter.call()
	CaseState.set_initial("B", _judgment_row.value, confidence)
	CaseState.record_judgment("B", _judgment_row.value, confidence, "Initial")
	finished.emit("board")
