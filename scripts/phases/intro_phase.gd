class_name IntroPhase
extends CasePhase
## 案件开场：先看那条被转发的帖子，再做第一次判断。
##
## 排版顺序是刻意的：帖子（冷色、发光）在前，判断（暖色、纸面手感）在后。
## 玩家在视觉上先被"屏幕"抓住，然后被要求停下来写自己的读数 ——
## 这个顺序本身就是案子的论点。

var _judgment_row: JudgmentRow
var _confidence_getter: Callable
var _hint: Label
var _start_button: Button

func _build() -> void:
	var _c := scroll_column(800)
	_c.add_child(UIKit.gap(18))

	_c.add_child(UIKit.eyebrow(str(case.get("opening", {}).get("eyebrow", "CASE FILE"))))
	_c.add_child(UIKit.gap(12))
	_c.add_child(UIKit.heading(str(case.get("title", "")), 34))
	_c.add_child(UIKit.gap(12))
	_c.add_child(UIKit.rule(Color(UIKit.INK4.r, UIKit.INK4.g, UIKit.INK4.b, 0.9)))
	_c.add_child(UIKit.gap(14))
	_c.add_child(UIKit.paragraph(str(case.get("opening", {}).get("lede", "")), 16, UIKit.FOG))
	_c.add_child(UIKit.gap(18))

	_c.add_child(_post_card())
	_c.add_child(UIKit.gap(18))

	_c.add_child(section("BASED ON WHAT YOU KNOW NOW"))
	_c.add_child(UIKit.gap(12))
	_c.add_child(_claim_quote())
	_c.add_child(UIKit.gap(13))

	_judgment_row = JudgmentRow.make(false, true)
	_judgment_row.value = ""
	_c.add_child(_judgment_row)
	_c.add_child(UIKit.gap(14))

	var confidence := confidence_row(50)
	_c.add_child(confidence[0])
	_confidence_getter = confidence[1]
	_c.add_child(UIKit.gap(4))

	_hint = UIKit.paragraph(str(case.get("opening", {}).get("instruction", "")), 13,
		Color(UIKit.SLATE.r, UIKit.SLATE.g, UIKit.SLATE.b, 0.9))
	_c.add_child(_hint)
	_c.add_child(UIKit.gap(12))

	_c.add_child(_footer())
	_c.add_child(UIKit.gap(16))

	stagger_fade(_c)

# ─────────────────────────────────────────────────────────────
#  被转发的那条帖子。冷色、发光、有传播数字 —— 它是"屏幕"这一类东西的代表。
# ─────────────────────────────────────────────────────────────
func _post_card() -> Control:
	var post: Dictionary = case.get("post", {})
	var card := UIKit.screen_panel(15)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 11)
	col.add_child(head)

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
	var stamp := UIKit.meta("%s · %s views" % [str(post.get("timestamp", "")), str(post.get("views", ""))], 10, UIKit.INK4, 1)
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(stamp)

	col.add_child(UIKit.gap(0))
	col.add_child(_still())
	col.add_child(UIKit.gap(0))

	col.add_child(UIKit.label(str(post.get("caption", "")), 19, UIKit.CHALK, UIKit.font_ui()))
	var body := UIKit.paragraph(str(post.get("body", "")), 14, Color(UIKit.SLATE.r, UIKit.SLATE.g, UIKit.SLATE.b, 1.0))
	col.add_child(body)

	col.add_child(UIKit.hairline(Color(UIKit.SCREEN_EDGE.r, UIKit.SCREEN_EDGE.g, UIKit.SCREEN_EDGE.b, 0.9)))

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 18)
	col.add_child(stats)
	for pair in [["likes", "likes"], ["comments", "comments"], ["shares", "shares"]]:
		stats.add_child(UIKit.meta("%s %s" % [str(post.get(pair[0], "")), pair[1]], 10, UIKit.SLATE, 1))
	stats.add_child(UIKit.fill(UIKit.hgap(0)))
	stats.add_child(UIKit.meta(str(post.get("topic", "")), 10, UIKit.CYAN, 1))

	return card

## 视频静帧。没有真实素材，所以这里给的是一帧被压暗的、构图可辨认的画面，
## 而不是一个写着"视频占位"的空框 —— 前者能让玩家真的"看见"那 14 秒。
func _still() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 190)
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var frame := StillFrame.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)

	var play := PlayGlyph.new()
	play.set_anchors_preset(Control.PRESET_FULL_RECT)
	play.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(play)

	var bottom := HBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 16
	bottom.offset_right = -16
	bottom.offset_top = -30
	bottom.offset_bottom = -14
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bottom)
	bottom.add_child(UIKit.meta("00:07", 10, Color(UIKit.FOG.r, UIKit.FOG.g, UIKit.FOG.b, 0.75), 1))
	bottom.add_child(UIKit.fill(UIKit.hgap(0)))
	bottom.add_child(UIKit.meta("%s CLIP" % str(case.get("post", {}).get("duration", "")), 10, Color(UIKit.FOG.r, UIKit.FOG.g, UIKit.FOG.b, 0.55), 1))

	return holder

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
	col.add_theme_constant_override("separation", 7)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UIKit.meta("claim %s · %s" % [str(claim.get("id", "")), str(claim.get("short", ""))], 10, UIKit.SLATE, 2))
	col.add_child(UIKit.quote("“" + str(claim.get("text", "")) + "”", 19))
	row.add_child(col)
	return row

func _footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)

	var note := UIKit.label("Recorded, and revisable at any time.", 12, UIKit.MUTED, UIKit.font_ui())
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(note)

	_start_button = UIKit.primary_button("Begin Investigation")
	_start_button.custom_minimum_size = Vector2(280, 44)
	_start_button.pressed.connect(_on_start)
	row.add_child(_start_button)
	return row

func _on_start() -> void:
	if _judgment_row.value == "":
		_hint.add_theme_color_override("font_color", UIKit.LAMP)
		var tween := create_tween()
		tween.tween_property(_hint, "modulate", Color(1.5, 1.2, 0.9, 1.0), 0.14)
		tween.tween_property(_hint, "modulate", Color.WHITE, 0.6)
		return
	var confidence: int = _confidence_getter.call()
	CaseState.set_initial("B", _judgment_row.value, confidence)
	CaseState.record_judgment("B", _judgment_row.value, confidence, "Initial")
	finished.emit("board")


# ─────────────────────────────────────────────────────────────
#  两个自绘小件。用 draw 而不是字符或图片：图标字体在导出后不一定有字形，
#  而这里只需要一个三角形和一个圆。
# ─────────────────────────────────────────────────────────────
class StillFrame extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0.027, 0.055, 0.066))
		# 一点从下方打上来的冷光，暗示站台灯
		var bands := 14
		for i in range(bands):
			var t := float(i) / float(bands - 1)
			var y := h * (0.42 + 0.58 * t)
			draw_rect(Rect2(0, y, w, h * 0.58 / float(bands) + 1.0),
				Color(0.10, 0.16, 0.18, 0.10 * (1.0 - t)))
		draw_line(Vector2(0, h * 0.82), Vector2(w, h * 0.82), Color(1, 1, 1, 0.055), 1.0)
		# 两个人影。刻意象，不刻五官。
		_figure(Vector2(w * 0.395, h * 0.82), h * 0.42, w * 0.052, Color(0.086, 0.128, 0.150))
		_figure(Vector2(w * 0.585, h * 0.82), h * 0.48, w * 0.044, Color(0.070, 0.106, 0.126))

	func _figure(foot: Vector2, height: float, width: float, color: Color) -> void:
		draw_rect(Rect2(foot.x - width * 0.5, foot.y - height, width, height), color)
		draw_circle(Vector2(foot.x, foot.y - height - width * 0.52), width * 0.60, color)


class PlayGlyph extends Control:
	func _draw() -> void:
		var center := size * 0.5
		draw_circle(center, 30.0, Color(0, 0, 0, 0.34))
		draw_arc(center, 30.0, 0.0, TAU, 64, Color(1, 1, 1, 0.30), 1.0, true)
		var tri := PackedVector2Array([
			center + Vector2(-6, -11), center + Vector2(-6, 11), center + Vector2(11, 0)])
		draw_colored_polygon(tri, Color(1, 1, 1, 0.72))
