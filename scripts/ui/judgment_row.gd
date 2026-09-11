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
	var _hovered := false
	var _label: Label
	var _bar: ColorRect
	var _mark: PanelContainer

	func setup(k: String, text: String, col: Color, is_compact: bool) -> void:
		key = k
		_color = col
		custom_minimum_size = Vector2(0, 36 if is_compact else 44)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)

		# 两道标记同时亮：左边缘 3px 竖线（扫一眼就知道选了哪个），
		# 紧挨着一个 9px 方块（近看能分清"选中"和"没选中"）。
		# 只靠颜色深浅是不够的 —— 亮度低的屏幕上四个选项会糊成一片，
		# 而"我到底选了什么"是这一页唯一必须被看清的事。
		_bar = ColorRect.new()
		_bar.custom_minimum_size = Vector2(3, 0)
		_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_bar)

		_mark = PanelContainer.new()
		_mark.custom_minimum_size = Vector2(9, 9)
		_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_mark)

		_label = UIKit.label(text, 13 if is_compact else 14, UIKit.SLATE, UIKit.font_ui())
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_label)

		gui_input.connect(_on_input)
		mouse_entered.connect(func() -> void:
			_hovered = true
			_refresh())
		mouse_exited.connect(func() -> void:
			_hovered = false
			_refresh())
		_refresh()

	func _on_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			picked.emit(key)
			accept_event()

	func set_selected(on: bool) -> void:
		if _selected == on:
			return
		_selected = on
		_refresh()
		if on:
			# 选中是一次"按下去了"的回应，所以给它一点回弹，
			# 而不是颜色一变了事。0.22 秒，短到不打断节奏。
			modulate = Color(1.30, 1.15, 0.94, 1.0)
			var tween := create_tween()
			tween.tween_property(self, "modulate", Color.WHITE, 0.22).set_trans(Tween.TRANS_SINE)

	func _refresh() -> void:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 10
		sb.content_margin_right = 12
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		sb.anti_aliasing = true

		if _selected:
			# 四件事一起做：底色填充、边框加粗并提亮、左侧竖线满色、文字提亮。
			# 少做任何一件，低亮度屏上就可能看不出来。
			sb.set_border_width_all(2)
			sb.bg_color = Color(_color.r, _color.g, _color.b, 0.20)
			sb.border_color = _color
			sb.shadow_color = Color(_color.r, _color.g, _color.b, 0.20)
			sb.shadow_size = 10
			_bar.color = _color
			_mark.add_theme_stylebox_override("panel",
				_radio_box(_color, _color.lightened(0.25)))
			_label.add_theme_color_override("font_color", _color.lightened(0.62))
		elif _hovered:
			sb.set_border_width_all(1)
			sb.bg_color = UIKit.INK2
			sb.border_color = UIKit.INK4
			_bar.color = Color(_color.r, _color.g, _color.b, 0.45)
			_mark.add_theme_stylebox_override("panel",
				_radio_box(Color(0, 0, 0, 0), Color(_color.r, _color.g, _color.b, 0.55)))
			_label.add_theme_color_override("font_color", UIKit.FOG)
		else:
			sb.set_border_width_all(1)
			sb.bg_color = Color(UIKit.INK1.r, UIKit.INK1.g, UIKit.INK1.b, 0.55)
			sb.border_color = UIKit.INK3
			_bar.color = Color(_color.r, _color.g, _color.b, 0.16)
			_mark.add_theme_stylebox_override("panel",
				_radio_box(Color(0, 0, 0, 0), UIKit.INK4))
			_label.add_theme_color_override("font_color", UIKit.SLATE)
		add_theme_stylebox_override("panel", sb)

	func _radio_box(bg: Color, border: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(2)
		sb.set_border_width_all(1)
		sb.border_color = border
		sb.anti_aliasing = true
		return sb
