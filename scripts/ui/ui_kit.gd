class_name UIKit
extends RefCounted
## 案件界面的设计系统。所有颜色、字体、间距、控件样式只在这里定义一次。
##
## 视觉主张（不是装饰，是论证）：
##   屏幕是冷的、在发光 —— 帖文、播放器、传播数字，都属于这一类；
##   文件是暖的、有重量 —— 证据卡、证词、官方记录，都属于这一类。
## 整个游戏要玩家做的事，就是从左边那一类里，把右边那一类挑出来。
## 所以这两类东西在视觉上必须一眼可分。
##
## 排版主张：
##   标题用 Cinzel（衬线大写，有档案感），元数据用等宽体大写加字距（像打印在标签上），
##   正文用无衬线体。三种字体各管一件事，不混用。

# ─────────────────────────────────────────────────────────────
#  颜色
# ─────────────────────────────────────────────────────────────
const INK0 := Color(0.0392, 0.0510, 0.0706)   # 0a0d12 最深，画布底
const INK1 := Color(0.0706, 0.0863, 0.1137)   # 12161d 主背景
const INK2 := Color(0.1020, 0.1216, 0.1569)   # 1a1f28 面板
const INK3 := Color(0.1451, 0.1725, 0.2157)   # 252c37 细线
const INK4 := Color(0.2000, 0.2353, 0.2863)   # 333c49 强调细线

const SLATE := Color(0.4431, 0.5020, 0.5608)  # 71808f 次要文字 / 标签
const MUTED := Color(0.3020, 0.3569, 0.4275)  # 4d5b6d 最暗的可读文字（INK4 是给线用的，不是给字用的）
const FOG := Color(0.7059, 0.7529, 0.8000)    # b4c0cc 正文
const CHALK := Color(0.8941, 0.9137, 0.9333)  # e4e9ee 标题

const PAPER := Color(0.9137, 0.8863, 0.8275)      # e9e2d3 纸张
const PAPER_SOFT := Color(0.8510, 0.8157, 0.7412) # d9d0bd 纸张暗面
const PAPER_EDGE := Color(0.7529, 0.7098, 0.6196) # c0b59e 纸张描边
const PAPER_INK := Color(0.1490, 0.1647, 0.1922)  # 262a31 纸上正文
const PAPER_INK_SOFT := Color(0.3608, 0.3922, 0.4392) # 5c6470 纸上次要文字

const LAMP := Color(0.9137, 0.6627, 0.3725)   # e9a95f 暖灯，全场唯一的高饱和色
const LAMP_DIM := Color(0.5412, 0.3922, 0.2196) # 8a6438
const CYAN := Color(0.4353, 0.7137, 0.7686)   # 6fb6c4 屏幕的冷光
const SCREEN_BG := Color(0.0471, 0.0863, 0.1020)  # 0c161a
const SCREEN_EDGE := Color(0.1137, 0.2275, 0.2588) # 1d3a42

# 判定用色。刻意避开红/绿那套：这不是涨跌，是"证据能不能撑住这句话"的温度。
const J_SUPPORTED := Color(0.3725, 0.6392, 0.5804)    # 5fa394 青，立得住
const J_SUSPICIOUS := Color(0.8235, 0.6275, 0.3333)   # d2a055 琥珀，有地方对不上
const J_UNSUPPORTED := Color(0.7059, 0.4118, 0.4314)  # b4696e 褪色玫瑰，撑不住
const J_INSUFFICIENT := Color(0.4667, 0.5255, 0.6078) # 77869b 石板灰，问不出答案

# 同样的两种语义色，用在纸面上。浅底上不需要那么亮才看得清，
# 而且纸上的墨水本来就该比屏幕上的光暗一档。
const PAPER_PROVES := Color(0.2471, 0.4863, 0.4353)    # 3f7c6f
const PAPER_DOES_NOT := Color(0.5882, 0.3255, 0.3529)  # 96535a

# ─────────────────────────────────────────────────────────────
#  间距与尺寸（设计基准 1600x1000）
# ─────────────────────────────────────────────────────────────
const GUTTER := 56       # 屏幕左右安全边距
const COL_GAP := 22
const RADIUS := 3        # 纸张是裁出来的，直角；屏幕是玻璃，圆角
const SCREEN_RADIUS := 6
const HAIRLINE := 1
const WIDE := 760        # 单栏正文的最大宽度

# 判定选项的稳定顺序，谁都别改这个顺序，玩家的肌肉记忆靠它
const JUDGMENT_ORDER: Array[String] = ["supported", "suspicious", "unsupported", "insufficient"]

# ─────────────────────────────────────────────────────────────
#  字体
# ─────────────────────────────────────────────────────────────
static var _fonts := {}

static func _cached(key: String, make: Callable) -> Font:
	if not _fonts.has(key):
		_fonts[key] = make.call()
		_append_cjk_fallback(_fonts[key])
	return _fonts[key]

## Web 端没有系统字体。ThemeDB.fallback_font 在导出包里**不会**被当作缺字形
## 兜底（实测所有取字路径都渲染成 codepoint 方框），可靠的兜底是
## Font.fallbacks 数组。把内嵌思源黑体挂到每个基础字体后面：
## 只在基础字体缺这个字时启用，桌面端外观不变。
static func _append_cjk_fallback(f: Font) -> void:
	const CJK_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
	if f == null or not ResourceLoader.exists(CJK_PATH):
		return
	var cjk: Font = load(CJK_PATH)
	if cjk != null and not f.fallbacks.has(cjk):
		f.fallbacks.append(cjk)

## 衬线大写，档案感。用于案件标题、Claim 原文。
static func font_display() -> Font:
	return _cached("display", func(): return load("res://assets/fonts/Cinzel.ttf"))

## 衬线斜体，用于引述与结语。它是这份档案里唯一"有人在说话"的字体。
static func font_quote() -> Font:
	return _cached("quote", func(): return load("res://assets/fonts/DMSerifDisplay-Italic.ttf"))

## 正文无衬线体。带中文回退，避免混排出现豆腐块。
static func font_ui() -> Font:
	return _cached("ui", func():
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["SF Pro Text", "Helvetica Neue", "PingFang SC", "Arial"])
		f.allow_system_fallback = true
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		return f)

## 等宽体。所有"打印在标签上"的东西都用它：编号、来源、成本、可靠性。
static func font_mono() -> Font:
	return _cached("mono", func():
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["SF Mono", "Menlo", "Monaco", "Consolas", "Courier New"])
		f.allow_system_fallback = true
		return f)

## 加字距。大写字母必须拉开，否则就只是"大写"，不是"刻上去的"。
static func tracked(base: Font, px: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.spacing_glyph = px
	return fv

# ─────────────────────────────────────────────────────────────
#  文字控件
# ─────────────────────────────────────────────────────────────
static func label(text: String, size: int = 15, color: Color = FOG, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font != null:
		l.add_theme_font_override("font", font)
	return l

## 元数据：等宽 + 大写 + 字距。CASE 001 / SOURCE / 1 IP 全都走这个。
static func meta(text: String, size: int = 12, color: Color = SLATE, spacing: int = 2) -> Label:
	var l := label(text.to_upper(), size, color, tracked(font_mono(), spacing))
	l.add_theme_constant_override("line_spacing", 4)
	return l

## 章节小标题。
static func eyebrow(text: String, color: Color = SLATE) -> Label:
	return meta(text, 11, color, 3)

## 正文段落。行高给足，这类界面最大的敌人是挤。
static func paragraph(text: String, size: int = 16, color: Color = FOG) -> Label:
	var l := label(text, size, color, font_ui())
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_constant_override("line_spacing", 9)
	return l

static func heading(text: String, size: int = 30, color: Color = CHALK) -> Label:
	var l := label(text, size, color, font_display())
	l.add_theme_constant_override("line_spacing", 6)
	return l

## 引述 / Claim 原文。斜体衬线，稍微放大，行高宽松。
static func quote(text: String, size: int = 21, color: Color = CHALK) -> Label:
	var l := label(text, size, color, font_quote())
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_constant_override("line_spacing", 10)
	return l

## 给叠在 3D 画面上的文字加一层暗描边，保证任何背景下都读得清。
static func readable(l: Label, strength: float = 0.75) -> Label:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, strength))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 4)
	return l

# ─────────────────────────────────────────────────────────────
#  面板
# ─────────────────────────────────────────────────────────────
static func _stylebox(bg: Color, border: Color, radius: int, border_w: int,
		pad: int, shadow: Color = Color(0, 0, 0, 0), shadow_size: int = 0,
		shadow_offset: Vector2 = Vector2.ZERO) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	if shadow_size > 0:
		sb.shadow_color = shadow
		sb.shadow_size = shadow_size
		sb.shadow_offset = shadow_offset
	sb.anti_aliasing = true
	return sb

static func panel(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = RADIUS,
		pad: int = 18, border_w: int = 0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _stylebox(bg, border, radius, border_w, pad))
	return p

## 文件：暖、直角、有厚度。阴影往下偏，像压在桌面上。
static func paper_panel(pad: int = 22, bg: Color = PAPER, edge: Color = PAPER_EDGE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _stylebox(
		bg, edge, RADIUS, 1, pad,
		Color(0, 0, 0, 0.55), 10, Vector2(0, 4)))
	return p

## 屏幕：冷、圆角、向外发光。发光是关键——它在往外推销自己。
static func screen_panel(pad: int = 20) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _stylebox(
		SCREEN_BG, SCREEN_EDGE, SCREEN_RADIUS, 1, pad,
		Color(0.10, 0.34, 0.40, 0.28), 18, Vector2(0, 6)))
	return p

## 无装饰的深色分组，用于三栏面板之间做层次。
static func slot_panel(pad: int = 16, bg: Color = INK2, border: Color = INK3) -> PanelContainer:
	return panel(bg, border, 4, pad, 1)

static func hairline(color: Color = INK3, height: int = HAIRLINE) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, height)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## 两端细、中间实的分隔线，用来代替生硬的 1px 横线。
static func rule(color: Color = INK3, tall: int = 1) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var faint := func(w: float) -> ColorRect:
		var c := ColorRect.new()
		c.color = Color(color.r, color.g, color.b, color.a * 0.25)
		c.custom_minimum_size = Vector2(w, tall)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return c
	box.add_child(faint.call(0.0))
	var solid := ColorRect.new()
	solid.color = color
	solid.custom_minimum_size = Vector2(0, tall)
	solid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	solid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(solid)
	box.add_child(faint.call(0.0))
	return box

static func gap(height: float = 12) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func hgap(width: float = 12) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## 让子控件在容器里横向撑满 / 纵向撑满。
static func fill(c: Control, horizontal: bool = true, vertical: bool = false) -> Control:
	if horizontal:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c

# ─────────────────────────────────────────────────────────────
#  按钮
# ─────────────────────────────────────────────────────────────
static func primary_button(text: String) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.add_theme_font_override("font", tracked(font_mono(), 2))
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", INK0)
	b.add_theme_color_override("font_hover_color", INK0)
	b.add_theme_color_override("font_pressed_color", INK0)
	b.add_theme_color_override("font_disabled_color", Color(INK0.r, INK0.g, INK0.b, 0.35))
	# 光晕从 26/34/18 收到 12/16/8。原先它是整屏最亮的东西，像一张优惠券 ——
	# 而这一页要的是"克制、低饱和"。暖黄色保留，只是不再往外喊。
	b.add_theme_stylebox_override("normal", _btn_box(LAMP.darkened(0.10), 12))
	b.add_theme_stylebox_override("hover", _btn_box(LAMP.lightened(0.06), 16))
	b.add_theme_stylebox_override("pressed", _btn_box(LAMP.darkened(0.22), 8))
	b.add_theme_stylebox_override("disabled", _btn_box(Color(LAMP.r, LAMP.g, LAMP.b, 0.18), 0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(0, 44)
	return b

static func ghost_button(text: String) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.add_theme_font_override("font", tracked(font_mono(), 2))
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", SLATE)
	b.add_theme_color_override("font_hover_color", CHALK)
	b.add_theme_color_override("font_pressed_color", FOG)
	b.add_theme_color_override("font_disabled_color", Color(SLATE.r, SLATE.g, SLATE.b, 0.4))
	b.add_theme_stylebox_override("normal", _btn_box(Color(0, 0, 0, 0), 0, INK3))
	b.add_theme_stylebox_override("hover", _btn_box(INK2, 0, INK4))
	b.add_theme_stylebox_override("pressed", _btn_box(INK1, 0, INK4))
	b.add_theme_stylebox_override("disabled", _btn_box(Color(0, 0, 0, 0), 0, INK3.darkened(0.3)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(0, 42)
	return b

static func _btn_box(bg: Color, glow: int, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	if border.a > 0.0:
		sb.set_border_width_all(1)
		sb.border_color = border
	if glow > 0:
		sb.shadow_color = Color(bg.r, bg.g, bg.b, 0.20)
		sb.shadow_size = glow
	sb.anti_aliasing = true
	return sb

## 顶栏用的极小切换钮（语言）。它不是主操作，所以只做"选中态 + 悬停"，
## 一点光晕都不给 —— 顶栏上最该抢眼的东西是最不该抢眼的东西。
static func chip_button(text: String, color: Color = LAMP) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.add_theme_font_override("font", tracked(font_mono(), 1))
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", MUTED)
	b.add_theme_color_override("font_hover_color", CHALK)
	b.add_theme_color_override("font_pressed_color", color)
	b.add_theme_color_override("font_hover_pressed_color", color)
	b.add_theme_color_override("font_focus_color", MUTED)
	b.add_theme_stylebox_override("normal", _chip_box(Color(0, 0, 0, 0), INK3))
	b.add_theme_stylebox_override("hover", _chip_box(INK2, INK4))
	b.add_theme_stylebox_override("pressed",
		_chip_box(Color(color.r, color.g, color.b, 0.16), Color(color.r, color.g, color.b, 0.60)))
	b.add_theme_stylebox_override("hover_pressed",
		_chip_box(Color(color.r, color.g, color.b, 0.20), Color(color.r, color.g, color.b, 0.72)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(0, 24)
	return b

static func _chip_box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(2)
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sb.anti_aliasing = true
	return sb


## 纯文字的"链接"按钮，用在次要的继续动作上。
static func text_button(text: String, color: Color = SLATE) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.add_theme_font_override("font", tracked(font_mono(), 2))
	b.add_theme_font_size_override("font_size", 11)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, color if state == "font_color" else color.lightened(0.35))
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b

# ─────────────────────────────────────────────────────────────
#  判定
# ─────────────────────────────────────────────────────────────
static func judgment_color(key: String) -> Color:
	match key:
		"supported": return J_SUPPORTED
		"suspicious": return J_SUSPICIOUS
		"unsupported": return J_UNSUPPORTED
		_: return J_INSUFFICIENT

## 判定名。英文是内置的兜底值，Locale 初始化时会用当前语言覆盖它。
static var judgment_names: Dictionary = {
	"supported": "Supported",
	"suspicious": "Suspicious",
	"unsupported": "Unsupported",
	"insufficient": "Not Enough Evidence",
}

static func judgment_label(key: String) -> String:
	return str(judgment_names.get(key, key))

## 一个小色点 + 标签。色点比背景色块克制，也能在任意底色上工作。
static func dot(color: Color, size: int = 8) -> Control:
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(size, size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(r)
	return holder

## 小标签（tag）。等宽大写，1px 描边，透明底。
static func tag(text: String, color: Color = SLATE) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _stylebox(Color(0, 0, 0, 0), Color(color.r, color.g, color.b, 0.35), 2, 0, 0, 0, 3)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(meta(text, 10, color, 1))
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return p

## 统一滚动条外观。
## Godot 默认的滚动条是浅灰圆角的，放在这套深色档案界面上像从别的程序里
## 掉进来的零件。纸面上的又该换一种（深色、更细）。
static func style_scroll(container: ScrollContainer, on_paper: bool = false) -> void:
	container.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var track := Color(0, 0, 0, 0)
	var knob := Color(0, 0, 0, 0.18) if on_paper else Color(1, 1, 1, 0.10)
	var knob_hi := Color(0, 0, 0, 0.32) if on_paper else Color(1, 1, 1, 0.22)
	for bar in [container.get_v_scroll_bar(), container.get_h_scroll_bar()]:
		bar.custom_minimum_size = Vector2(5, 5)
		bar.add_theme_stylebox_override("scroll", _stylebox(track, track, 3, 0, 0))
		bar.add_theme_stylebox_override("scroll_focus", _stylebox(track, track, 3, 0, 0))
		bar.add_theme_stylebox_override("grabber", _stylebox(knob, knob, 3, 0, 0))
		bar.add_theme_stylebox_override("grabber_highlight", _stylebox(knob_hi, knob_hi, 3, 0, 0))
		bar.add_theme_stylebox_override("grabber_pressed", _stylebox(knob_hi, knob_hi, 3, 0, 0))


## 键盘键帽。用来显示 [ E ] 这类提示，比写 "Press E" 有质感。
static func keycap(text: String, color: Color = LAMP) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _stylebox(Color(color.r, color.g, color.b, 0.14), Color(color.r, color.g, color.b, 0.55), 3, 1, 0)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(meta(text, 12, color, 1))
	return p
