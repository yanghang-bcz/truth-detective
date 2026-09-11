class_name JudgmentRow
extends BoxContainer
## 四选一的判定行。Supported / Suspicious / Unsupported / Not Enough Evidence。
##
## 顺序永远不变（UIKit.JUDGMENT_ORDER），颜色永远对应同一种"温度"。
## 这样玩家第二次、第三次看到它时，不需要重新读文字 —— 这是肌肉记忆，
## 而一个要玩家反复做判断的界面，最不该浪费的就是重新认路的时间。

signal selected(key: String)
## 只要 value 真的变了就发 —— 不管是玩家点的，还是代码回填的。
## 界面里的"状态回显"该听这个；"玩家刚做了什么"才听 selected。
signal value_changed(key: String)

var value: String = "":
	set(v):
		if value == v:
			return
		value = v
		_sync()
		value_changed.emit(value)

var allow_empty := true
var compact := false

var _items := {}

static func make(vertical_mode: bool = false, compact_mode: bool = false) -> JudgmentRow:
	var row := JudgmentRow.new()
	row.vertical = vertical_mode
	row.compact = compact_mode
	row.add_theme_constant_override("separation", 7)
	row._build()
	return row

func _build() -> void:
	for key in UIKit.JUDGMENT_ORDER:
		var opt := Option.new()
		opt.setup(key, UIKit.judgment_label(key), UIKit.judgment_color(key), compact)
		opt.picked.connect(_on_picked)
		add_child(opt)
		_items[key] = opt
	_sync()

func _on_picked(key: String) -> void:
	if value == key and allow_empty:
		value = ""
	else:
		value = key
	selected.emit(value)

func _sync() -> void:
	for key in _items:
		_items[key].set_selected(key == value)


# ─────────────────────────────────────────────────────────────
class Option extends PanelContainer:
	signal picked(key: String)

	var key := ""
	var _color := UIKit.SLATE
	var _selected := false
	var _label: Label
	var _bar: ColorRect

	func setup(k: String, text: String, col: Color, is_compact: bool) -> void:
		key = k
		_color = col
		custom_minimum_size = Vector2(0, 30 if is_compact else 38)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)

		# 左边缘那道 2px 竖线是状态指示器。它比整块变色克制，也不会在
		# 四个选项里制造四个大色块互相抢注意力。
		_bar = ColorRect.new()
		_bar.color = Color(col.r, col.g, col.b, 0.25)
		_bar.custom_minimum_size = Vector2(2, 0)
		_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_bar)

		_label = UIKit.label(text, 13 if is_compact else 14, UIKit.SLATE, UIKit.font_ui())
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_label)

		gui_input.connect(_on_input)
		mouse_entered.connect(func() -> void: _refresh(true))
		mouse_exited.connect(func() -> void: _refresh(false))
		_refresh(false)

	func _on_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			picked.emit(key)
			accept_event()

	func set_selected(on: bool) -> void:
		if _selected == on:
			return
		_selected = on
		_refresh(false)

	func _refresh(hovered: bool) -> void:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 10
		sb.content_margin_right = 12
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		sb.set_border_width_all(1)
		sb.anti_aliasing = true

		if _selected:
			sb.bg_color = Color(_color.r, _color.g, _color.b, 0.16)
			sb.border_color = Color(_color.r, _color.g, _color.b, 0.70)
			sb.shadow_color = Color(_color.r, _color.g, _color.b, 0.22)
			sb.shadow_size = 12
			_bar.color = _color
			_label.add_theme_color_override("font_color", _color.lightened(0.30))
		elif hovered:
			sb.bg_color = UIKit.INK2
			sb.border_color = UIKit.INK4
			_bar.color = Color(_color.r, _color.g, _color.b, 0.55)
			_label.add_theme_color_override("font_color", UIKit.FOG)
		else:
			sb.bg_color = Color(UIKit.INK1.r, UIKit.INK1.g, UIKit.INK1.b, 0.55)
			sb.border_color = UIKit.INK3
			_bar.color = Color(_color.r, _color.g, _color.b, 0.22)
			_label.add_theme_color_override("font_color", UIKit.SLATE)
		add_theme_stylebox_override("panel", sb)
