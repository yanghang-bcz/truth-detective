class_name ConfidenceSlider
extends Control
## 置信度滑条。自绘而不是用 HSlider：需要刻度、需要暖光手柄、
## 需要"往右拖 = 更确定"这条在视觉上立得住。
##
## 0 和 100 都不是好答案。所以两端各有一个刻度被刻意做暗，
## 让人下意识避开绝对。

signal changed(value: int)

const TRACK_H := 4.0
const HANDLE_W := 5.0
const HANDLE_H := 22.0
const PAD := 6.0

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

func _ready() -> void:
	custom_minimum_size = Vector2(0, 34)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(queue_redraw)
	mouse_entered.connect(func() -> void:
		_hovering = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hovering = false
		queue_redraw())

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_set_from_x(event.position.x)
		accept_event()
		queue_redraw()
	elif event is InputEventMouseMotion and _dragging:
		_set_from_x(event.position.x)
		accept_event()

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

	# 手柄。悬停或拖动时才发光 —— 光芒是一种回应，不该一直亮着。
	var active := _dragging or _hovering
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

func _box(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	return sb
