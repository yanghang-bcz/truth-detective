extends Area3D
## 地铁口的交互触发。
##
## 案件界面不是用 change_scene_to_file 切的，而是作为一个高层的 CanvasLayer
## 叠在街区之上 —— 街区不卸载，所以从案件回到街上没有任何加载等待
## （重新加载一遍 playable_neighborhood 要 1 秒，来回一次就够玩家难受了）。
##
## 玩家也没有被"传送"：进案件时原地冻结，出来时还站在地铁口。
## 这正是策划案要的效果，而且实现上比记录/恢复坐标更不容易出错。

const CASE_SCENE := "res://scenes/cases/case_001/case_001.tscn"

## 触发区中心与尺寸。地铁口台阶顶端在 z≈8.5，所以触发区放在台阶前方，
## 玩家走到台阶口自然进入。这两个常量只作为默认值的记录 —— 实际数值存在
## playable_neighborhood.tscn 里，这样在编辑器里可以直接拖动调整，脚本不会覆盖它。
const TRIGGER_CENTER := Vector3(-4.8, 0.9, 9.7)
const TRIGGER_SIZE := Vector3(3.6, 2.6, 2.6)

## 进出案件的方向必须自己记住。Curtain 只会报告"黑透了"和"亮透了"，
## 它不知道这是打开的中场还是关闭的中场 —— 而这两件事要做的事刚好相反。
enum State { IDLE, OPENING, OPEN, CLOSING }

var _inside := false
var _state: int = State.IDLE
var _completed := false
var _player: CharacterBody3D

var _hud: CanvasLayer
var _prompt: Control
var _prompt_box: PanelContainer
var _prompt_label: Label
var _objective: Control
var _objective_label: Label

var _fade_layer: CanvasLayer
var _curtain: Curtain
var _case_layer: CanvasLayer
var _case: CaseManager


func _ready() -> void:
	position = TRIGGER_CENTER
	collision_layer = 0
	collision_mask = 1
	monitorable = false
	monitoring = true

	_ensure_input_actions()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_player = _find_player()
	if _player != null:
		_player.add_to_group("detective")

	_build_hud()
	_build_fade_layer()
	set_process_input(true)


# ─────────────────────────────────────────────────────────────
#  输入
# ─────────────────────────────────────────────────────────────
func _ensure_input_actions() -> void:
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	if not InputMap.action_has_event("interact", key):
		InputMap.action_add_event("interact", key)

func _is_busy() -> bool:
	return _state != State.IDLE

func _input(event: InputEvent) -> void:
	if _is_busy() or not _inside:
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_open_case()

func _on_body_entered(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	_player = body
	_inside = true
	if not _is_busy():
		_show_prompt(true)

func _on_body_exited(body: Node3D) -> void:
	if body != _player:
		return
	_inside = false
	_show_prompt(false)

# ─────────────────────────────────────────────────────────────
#  进入 / 退出案件
# ─────────────────────────────────────────────────────────────
func _open_case() -> void:
	if _is_busy():
		return
	_state = State.OPENING
	_show_prompt(false)
	_set_player_frozen(true)
	_curtain.fade_out(0.34)


## 全黑。此时屏幕被挡住，建/拆案件层都不会被玩家看到闪动。
func _on_curtain_covered() -> void:
	match _state:
		State.OPENING:
			_build_case()
			_curtain.fade_in(0.38)
		State.CLOSING:
			_teardown_case()
			_curtain.fade_in(0.32)
		_:
			pass


## 全亮。这里才是「这个方向真正走完了」的时刻。
func _on_curtain_cleared() -> void:
	match _state:
		State.OPENING:
			# 案件已经露出来了 —— 从这里开始才算「开着」，
			# 才允许 _close_case 生效。
			_state = State.OPEN
		State.CLOSING:
			_state = State.IDLE
			_objective.visible = false
			_set_player_frozen(false)
			if _inside:
				_show_prompt(true)
		_:
			pass


func _build_case() -> void:
	if _case != null:
		return
	CaseState.start()
	_case_layer = CanvasLayer.new()
	_case_layer.name = "CaseLayer"
	_case_layer.layer = 20
	get_tree().root.add_child(_case_layer)

	var packed: PackedScene = load(CASE_SCENE)
	if packed == null:
		# 载不出来就别把玩家锁在黑屏里。
		push_error("CaseTrigger: 找不到案件场景 " + CASE_SCENE)
		_state = State.IDLE
		_set_player_frozen(false)
		_curtain.fade_in(0.2)
		if _inside:
			_show_prompt(true)
		return
	_case = packed.instantiate()
	_case_layer.add_child(_case)
	_case.closed.connect(_close_case)


func _close_case() -> void:
	if _state != State.OPEN:
		return
	_state = State.CLOSING
	_curtain.fade_out(0.32)


func _teardown_case() -> void:
	if _case_layer != null and is_instance_valid(_case_layer):
		_case_layer.queue_free()
	_case_layer = null
	_case = null
	_completed = true

func _set_player_frozen(frozen: bool) -> void:
	var player := _player if _player != null else _find_player()
	if player == null:
		return
	_player = player
	# 复用 detective.gd 已有的 automated 通道：把输入喂成零，
	# 角色会停下并正常播放 Idle，而不是僵在半步的姿势上。
	player.automated = frozen
	if frozen:
		player.test_input = Vector2.ZERO
		player.test_run = false

func _find_player() -> CharacterBody3D:
	var parent := get_parent()
	if parent != null:
		var found := parent.get_node_or_null("Detective")
		if found is CharacterBody3D:
			return found
	var in_group := get_tree().get_first_node_in_group("detective")
	if in_group is CharacterBody3D:
		return in_group
	return null


# ─────────────────────────────────────────────────────────────
#  界面：目标提示 + 交互提示
# ─────────────────────────────────────────────────────────────
func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	_hud.layer = 10
	add_child(_hud)

	var layer := Control.new()
	layer.name = "HudRoot"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(layer)

	layer.add_child(_build_objective())
	layer.add_child(_build_prompt())

## 左上角的目标行。街区是固定视角的俯视，找路并不总是直观 ——
## 这行字只解决"往哪走"，不解决"看到了什么"。
func _build_objective() -> Control:
	var holder := HBoxContainer.new()
	holder.set_anchors_preset(Control.PRESET_TOP_LEFT)
	holder.offset_left = UIKit.GUTTER - 12
	holder.offset_top = 26
	holder.add_theme_constant_override("separation", 10)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective = holder

	var dot := ColorRect.new()
	dot.color = UIKit.LAMP
	dot.custom_minimum_size = Vector2(6, 6)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(dot)

	_objective_label = UIKit.readable(UIKit.meta("Objective — the metro entrance", 11, UIKit.FOG, 3))
	_objective_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.add_child(_objective_label)

	# 极慢的呼吸，提醒"这里还有一个目标"，但绝不闪烁。
	var tween := create_tween().set_loops()
	tween.tween_property(dot, "modulate:a", 0.35, 2.0).set_trans(Tween.TRANS_SINE)
	tween.tween_property(dot, "modulate:a", 1.0, 2.0).set_trans(Tween.TRANS_SINE)
	return holder

func _build_prompt() -> Control:
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	holder.offset_top = -136
	holder.offset_bottom = -70
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt = holder

	_prompt_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UIKit.INK2.r, UIKit.INK2.g, UIKit.INK2.b, 0.94)
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.border_color = UIKit.INK4
	sb.content_margin_left = 16
	sb.content_margin_right = 20
	sb.content_margin_top = 11
	sb.content_margin_bottom = 11
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 6)
	sb.anti_aliasing = true
	_prompt_box.add_theme_stylebox_override("panel", sb)
	holder.add_child(_prompt_box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 13)
	_prompt_box.add_child(row)

	row.add_child(UIKit.keycap("E"))

	_prompt_label = UIKit.readable(UIKit.label("Investigate the metro entrance", 15, UIKit.CHALK, UIKit.font_ui()))
	_prompt_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_prompt_label)

	holder.visible = false
	holder.modulate = Color(1, 1, 1, 0)
	return holder

func _show_prompt(show_it: bool) -> void:
	if _prompt == null:
		return
	if show_it:
		_prompt_label.text = "Reopen the case file" if _completed else "Investigate the metro entrance"
	if _prompt.visible == show_it:
		return
	if show_it:
		_prompt.visible = true
		_prompt.offset_top = -122
		_prompt.offset_bottom = -56
		var tin := create_tween().set_parallel(true)
		tin.tween_property(_prompt, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE)
		tin.tween_property(_prompt, "offset_top", -136.0, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tin.tween_property(_prompt, "offset_bottom", -70.0, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		var tout := create_tween()
		tout.tween_property(_prompt, "modulate:a", 0.0, 0.16).set_trans(Tween.TRANS_SINE)
		tout.tween_callback(func() -> void: _prompt.visible = false)


# ─────────────────────────────────────────────────────────────
func _build_fade_layer() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "FadeLayer"
	_fade_layer.layer = 40
	add_child(_fade_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(root)

	_curtain = Curtain.attach(root)
	_curtain.covered.connect(_on_curtain_covered)
	_curtain.cleared.connect(_on_curtain_cleared)
