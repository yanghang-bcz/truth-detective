class_name CaseManager
extends Control
## 案件界面的总控。负责外壳（顶栏、背景、画面质感）和四个阶段之间的路由。
##
## 阶段之间只走 finished(next) 一个信号，路由表在这里。要插一个新阶段
## （比如调查中途的过场），只改这张表，四个阶段本身一行都不用动。
##
## 顶栏右端是语言切换。切换时**不重开一次案件**：只把案件内容重读一遍、
## 把当前这一页重建一遍。玩家的调查点、已开档案、判定历史全部原样保留 ——
## 翻到一半想换语言，不该被罚一次重来。

signal closed          ## 玩家看完 Debrief 点了"返回街区"

const PHASE_SCENES := {
	"intro": "res://scenes/cases/case_001/case_001_intro.tscn",
	"board": "res://scenes/cases/case_001/investigation_board.tscn",
	"final": "res://scenes/cases/case_001/final_judgment.tscn",
	"debrief": "res://scenes/cases/case_001/debrief.tscn",
}

const PHASE_ORDER: Array[String] = ["intro", "board", "final", "debrief"]

var _host: Control
var _phase: CasePhase
var _phase_name := ""
var _code_label: Label
var _title_label: Label
var _points_group: Control
var _points_label: Label
var _points_caption: Label
var _meter: PointMeter
var _step_bars: Array[ColorRect] = []
var _lang_buttons: Array[Button] = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_shell()
	if CaseState.data.is_empty():
		CaseState.start()
	_show("intro")
	Locale.changed.connect(_on_locale_changed)

func _exit_tree() -> void:
	if Locale.changed.is_connected(_on_locale_changed):
		Locale.changed.disconnect(_on_locale_changed)

func _on_locale_changed(_lang: String) -> void:
	CaseState.reload_for_language()
	_retranslate()
	_show(_phase_name)

# ─────────────────────────────────────────────────────────────
func _build_shell() -> void:
	add_child(_background())

	var shell := VBoxContainer.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.add_theme_constant_override("separation", 0)
	add_child(shell)

	shell.add_child(_top_bar())

	var rule := UIKit.hairline(Color(UIKit.INK3.r, UIKit.INK3.g, UIKit.INK3.b, 0.85))
	shell.add_child(rule)

	_host = Control.new()
	_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.add_child(_host)

	# 画面质感铺在最上层，但不拦截任何输入。
	ScreenFX.attach(self)

## 从上到下极缓的明暗过渡。纯色底会让这么大的界面显得平，
## 一点点渐变就能把它从"网页"拉回"夜里的一间房"。
func _background() -> Control:
	var grad := Gradient.new()
	grad.set_color(0, UIKit.INK1)
	grad.set_color(1, UIKit.INK0)
	grad.add_point(0.58, Color(0.0549, 0.0706, 0.0941))

	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = 8
	tex.height = 512

	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

func _top_bar() -> Control:
	var bar := MarginContainer.new()
	bar.add_theme_constant_override("margin_left", UIKit.GUTTER)
	bar.add_theme_constant_override("margin_right", UIKit.GUTTER)
	bar.add_theme_constant_override("margin_top", 14)
	bar.add_theme_constant_override("margin_bottom", 14)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)

	# ── 左：案件编号 + 标题 ────────────────────────────────
	_code_label = UIKit.meta(str(CaseState.data.get("code", "")), 11, UIKit.LAMP, 3)
	_code_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_code_label)

	var divider := ColorRect.new()
	divider.color = UIKit.INK3
	divider.custom_minimum_size = Vector2(1, 16)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(divider)

	_title_label = UIKit.meta(str(CaseState.data.get("title", "")), 11, UIKit.SLATE, 2)
	_title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_title_label)

	row.add_child(UIKit.fill(UIKit.hgap(0)))

	# ── 右：四段进度 ───────────────────────────────────────
	for i in range(PHASE_ORDER.size()):
		var segment := ColorRect.new()
		segment.custom_minimum_size = Vector2(26, 2)
		segment.color = UIKit.INK3
		segment.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(segment)
		_step_bars.append(segment)

	row.add_child(UIKit.hgap(16))

	# ── 右：调查点。开场页不显示（那时玩家还不知道 IP 是什么，
	#         也没机会花掉它），进了调查板才淡进来。
	_points_group = HBoxContainer.new()
	_points_group.add_theme_constant_override("separation", 9)
	_points_group.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_points_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_points_group)

	_points_label = UIKit.label("", 15, UIKit.CHALK, UIKit.tracked(UIKit.font_mono(), 0))
	_points_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_points_group.add_child(_points_label)

	_points_caption = UIKit.meta(Locale.t("bar.points"), 10, UIKit.SLATE, 1)
	_points_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_points_group.add_child(_points_caption)

	_meter = PointMeter.new()
	_meter.custom_minimum_size = Vector2(130, 6)
	_meter.total = CaseState.points_total
	_meter.remaining = CaseState.remaining()
	_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_points_group.add_child(_meter)

	# ── 最右：语言 ─────────────────────────────────────────
	row.add_child(UIKit.hgap(6))
	var langs := HBoxContainer.new()
	langs.add_theme_constant_override("separation", 4)
	langs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(langs)
	for code in Locale.LANGS:
		var b := UIKit.chip_button(Locale.self_name(code))
		b.button_pressed = (code == Locale.lang)
		b.tooltip_text = Locale.t("lang.tip")
		b.pressed.connect(Locale.set_lang.bind(code))
		langs.add_child(b)
		_lang_buttons.append(b)

	CaseState.points_changed.connect(_on_points_changed)
	_on_points_changed(CaseState.remaining())
	return bar

func _retranslate() -> void:
	if _code_label != null:
		_code_label.text = str(CaseState.data.get("code", ""))
	if _title_label != null:
		_title_label.text = str(CaseState.data.get("title", ""))
	if _points_caption != null:
		_points_caption.text = Locale.t("bar.points")
	for i in range(_lang_buttons.size()):
		_lang_buttons[i].button_pressed = (Locale.LANGS[i] == Locale.lang)

func _on_points_changed(remaining: int) -> void:
	if _points_label == null:
		return
	_points_label.text = "%d / %d" % [remaining, CaseState.points_total]
	_points_label.add_theme_color_override("font_color", UIKit.CHALK if remaining > 0 else UIKit.J_UNSUPPORTED)
	_meter.total = CaseState.points_total
	_meter.set_remaining(remaining)

## 开场页不显示调查点。用透明度而不是 visible：visible 会让顶栏右侧
## 重新排版，语言切换钮会跟着左右跳一下。
func _set_points_visible(on: bool) -> void:
	if _points_group == null:
		return
	var target := 1.0 if on else 0.0
	if is_equal_approx(_points_group.modulate.a, target):
		return
	var tween := create_tween()
	tween.tween_property(_points_group, "modulate:a", target, 0.35).set_trans(Tween.TRANS_SINE)

# ─────────────────────────────────────────────────────────────
#  阶段路由
# ─────────────────────────────────────────────────────────────
func _show(phase_name: String) -> void:
	if not PHASE_SCENES.has(phase_name):
		return
	var packed: PackedScene = load(PHASE_SCENES[phase_name])
	if packed == null:
		push_error("CaseManager: 找不到阶段场景 " + PHASE_SCENES[phase_name])
		return

	var instance := packed.instantiate()
	if not (instance is CasePhase):
		push_error("CaseManager: %s 的根节点不是 CasePhase" % phase_name)
		instance.queue_free()
		return

	var old := _phase
	_phase = instance
	_phase_name = phase_name
	_host.add_child(_phase)
	_phase.setup(CaseState.data)
	_phase.finished.connect(_on_phase_finished)

	if old != null and is_instance_valid(old):
		old.queue_free()

	# 新阶段从透明浮现。够快，不会打断操作节奏，又避免了硬切。
	_phase.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(_phase, "modulate:a", 1.0, 0.24).set_trans(Tween.TRANS_SINE)

	_update_steps()
	_set_points_visible(phase_name != "intro")

func _on_phase_finished(next: String) -> void:
	if next == "close":
		closed.emit()
		return
	_show(next)

func _update_steps() -> void:
	var index := PHASE_ORDER.find(_phase_name)
	for i in range(_step_bars.size()):
		var bar: ColorRect = _step_bars[i]
		if i < index:
			bar.color = UIKit.LAMP_DIM
		elif i == index:
			bar.color = UIKit.LAMP
		else:
			bar.color = UIKit.INK3
