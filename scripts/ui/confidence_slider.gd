class_name ConfidenceSlider
extends Control
## 置信度滑条。自绘而不是用 HSlider：需要刻度、需要暖光手柄、
## 需要"往右拖 = 更确定"这条在视觉上立得住。
##
## 0 和 100 都不是好答案。所以两端各有一个刻度被刻意做暗，
## 让人下意识避开绝对。
##
## ── v0.3 修的两个问题 ────────────────────────────────────────
##
## 1) **尺寸被清零。** 旧代码在 _ready() 里无条件写
##    `custom_minimum_size = Vector2(0, 34)`。而 confidence_row() 是在
##    滑条**入树之前**设好 200×28 的（那时 _ready 还没跑），入树后 _ready
##    又把宽度打回 0 —— 于是滑条实际渲染成 5px 宽的一根竖条，
##    玩家根本点不到它。现在 _ready 只补默认值，绝不覆盖调用方设好的尺寸。
##
## 2) **一次拖动记成几十次调整。** 现在分两个信号：
##      changed   —— 值实时在变（更新读数、同步当前状态），每像素都发；
##      committed —— 一次交互**结束**时才发，带起始值。
##    事件历史只认 committed，所以 50→80 是一次 CONFIDENCE_ADJUSTED。
##    拖动被中途打断（切 Claim、离开页面）时，由 commit_pending() 结算，
##    不会出现"显示 80、状态 50、事件里没有"的三方不一致。

signal changed(value: int)
## 一次操作结束：value 是停下来的值，previous 是这次操作开始前的值。
signal committed(value: int, previous: int)

const TRACK_H := 4.0
const HANDLE_W := 5.0
const HANDLE_H := 22.0
const PAD := 6.0

## 键盘步长。按住 Shift 走小步，方便微调。
const STEP := 5
const STEP_FINE := 1

var value: int = 50:
	set(v):
		v = clampi(v, 0, 100)
		if v == value:
			return
		value = v
		queue_redraw()
		changed.emit(value)

var accent: Color = UIKit.LAMP

var _dragging := false
var _hovering := false
## 本次拖动开始时的值。-1 表示当前没有待结算的操作。
var _drag_origin := -1

func _ready() -> void:
	# 只在调用方没给尺寸时才补默认值。无条件覆盖会把 confidence_row
	# 入树前设的宽度打回 0，滑条就变成了一条点不到的竖线。
	if custom_minimum_size.x <= 0.0:
		custom_minimum_size = Vector2(200, 34)
	if custom_minimum_size.y <= 0.0:
		custom_minimum_size.y = 34
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	resized.connect(queue_redraw)
	mouse_entered.connect(func() -> void:
		_hovering = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hovering = false
		queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_origin = value
			grab_focus()
			_set_from_x(event.position.x)
		elif _dragging:
			_dragging = false
			commit_pending()
		accept_event()
		queue_redraw()
	elif event is InputEventMouseMotion and _dragging:
		_set_from_x(event.position.x)
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		# 键盘可达性。一次按键 = 一次确定的变化，所以直接结算。
		var step := STEP_FINE if event.shift_pressed else STEP
		match event.keycode:
			KEY_LEFT, KEY_DOWN:
				_nudge(-step)
				accept_event()
			KEY_RIGHT, KEY_UP:
				_nudge(step)
				accept_event()
			KEY_HOME:
				_nudge(0 - value)
				accept_event()
			KEY_END:
				_nudge(100 - value)
				accept_event()

func _nudge(delta: int) -> void:
	var previous := value
	value = clampi(value + delta, 0, 100)
	if value != previous:
		committed.emit(value, previous)

## 结算一次进行中的拖动。切 Claim、离开页面、提交之前都应该调一次，
## 保证当前状态、显示值、事件记录三者一致 —— 不会因为被打断而少记一次。
func commit_pending() -> void:
	if _drag_origin < 0:
		return
	var origin := _drag_origin
	_drag_origin = -1
	if value != origin:
		committed.emit(value, origin)

func _set_from_x(x: float) -> void:
	var span := maxf(size.x - PAD * 2.0, 1.0)
	value = int(round(clampf((x - PAD) / span, 0.0, 1.0) * 100.0))

func _draw() -> void:
	var mid := size.y * 0.5
	var span := maxf(size.x - PAD * 2.0, 1.0)
	var t := value / 100.0
	var handle_x := PAD + span * t

	# 刻度。端点的两个特意更暗：0% 和 100% 都不该是舒服的选择。
	for i in range(5):
		var frac := i / 4.0
		var x := PAD + span * frac
		var edge := i == 0 or i == 4
		var col := UIKit.INK3.darkened(0.25) if edge else UIKit.INK3
		var h := 4.0 if edge else 6.0
		draw_line(Vector2(x, mid + 11.0 - h), Vector2(x, mid + 11.0), col, 1.0)

	draw_style_box(_box(UIKit.INK4, 2), Rect2(PAD, mid - TRACK_H * 0.5, span, TRACK_H))
	if t > 0.001:
		draw_style_box(_box(accent, 2), Rect2(PAD, mid - TRACK_H * 0.5, span * t, TRACK_H))

	# 手柄。悬停、拖动或键盘聚焦时才发光 —— 光芒是一种回应，不该一直亮着。
	var active := _dragging or _hovering or has_focus()
	var handle := _box(UIKit.CHALK, 2)
	if active:
		handle.shadow_color = Color(accent.r, accent.g, accent.b, 0.55)
		handle.shadow_size = 12
	else:
		handle.shadow_color = Color(0, 0, 0, 0.5)
		handle.shadow_size = 5
		handle.shadow_offset = Vector2(0, 2)
	var hh := HANDLE_H + (2.0 if _dragging else 0.0)
	draw_style_box(handle, Rect2(handle_x - HANDLE_W * 0.5, mid - hh * 0.5, HANDLE_W, hh))

	# 键盘聚焦时给一条底线，否则玩家不知道自己现在能按方向键。
	if has_focus():
		draw_line(Vector2(PAD, size.y - 3.0), Vector2(PAD + span, size.y - 3.0),
			Color(accent.r, accent.g, accent.b, 0.55), 1.0)

func _box(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	return sb
