extends Node
## 冒烟测试：地铁口 → [E] → 案件界面 → 关闭 → 回到街上。
##
## 存在的理由：这条路径从没被验证过。截图工具只测了案件界面本身，
## test_player.gd 只测了移动和碰撞 —— 中间"触发区到底有没有检测到玩家、
## E 键到底有没有响应、进出之后玩家还在不在原地"这一段是空的。
## 而这段恰恰是最容易静默失效的：Area3D 少了 CollisionShape3D、
## collision_mask 和玩家的 collision_layer 对不上、owner 设早了导致形状没存进场景
## —— 三种情况都是"跑起来不报错，走过去按 E 没反应"。
##
## 用场景方式跑（--script 模式不注册 autoload，引用 CaseState 会编译失败）：
##   godot --path <项目> res://tools/test_case_trigger.tscn

const SCENE := "res://scenes/playable_neighborhood.tscn"
const TRIGGER_PATH := "MetroEntranceTrigger"
const PLAYER_PATH := "Detective"

var _fails := 0


func _ready() -> void:
	call_deferred("run")


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS ", msg)
	else:
		print("FAIL ", msg)
		_fails += 1


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _physics_steps(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame


func run() -> void:
	var packed: PackedScene = load(SCENE)
	if packed == null:
		print("FAIL 加载不了 ", SCENE)
		_finish()
		return
	var street: Node = packed.instantiate()
	add_child(street)
	await _settle(0.8)

	# ── 1. 场景里真的有这个触发区，而且它是完整的 ──────────────
	var trigger := street.get_node_or_null(TRIGGER_PATH)
	_check(trigger != null, "场景里有 %s" % TRIGGER_PATH)
	if trigger == null:
		_finish()
		return

	var shapes := trigger.find_children("*", "CollisionShape3D", true, false)
	_check(shapes.size() == 1, "触发区带一个 CollisionShape3D（少一个就是个空壳）")
	if shapes.size() == 1:
		var shape: CollisionShape3D = shapes[0]
		_check(shape.shape is BoxShape3D, "碰撞形状是 BoxShape3D")
		if shape.shape is BoxShape3D:
			var size := (shape.shape as BoxShape3D).size
			_check(size.x > 0.5 and size.y > 0.5 and size.z > 0.5,
				"碰撞盒尺寸合理 %s（全 0 说明形状没被写进场景）" % str(size))
		# owner 必须和触发区同一个，否则打包时会被丢掉
		_check(shape.owner == trigger.owner,
			"CollisionShape3D 的 owner 正确（owner 设早了它就不会被存进场景）")

	_check(trigger is Area3D, "触发区是 Area3D")
	_check(trigger.monitoring, "触发区开着 monitoring")

	var player := street.get_node_or_null(PLAYER_PATH)
	_check(player != null, "场景里有 %s" % PLAYER_PATH)
	if player == null:
		_finish()
		return

	# 玩家和触发区的碰撞层必须对得上，否则永远不会触发
	var area: Area3D = trigger
	var player_layer: int = player.collision_layer
	_check((area.collision_mask & player_layer) != 0,
		"触发区 mask(%d) 能匹配玩家 layer(%d)" % [area.collision_mask, player_layer])

	# ── 2. 玩家走进去之前，提示应该是藏着的 ─────────────────────
	_check(not trigger._prompt.visible, "进入之前不显示 [E] 提示")

	# ── 3. 走进触发区 ────────────────────────────────────────
	var center: Vector3 = area.global_position
	player.global_position = Vector3(center.x, player.global_position.y, center.z)
	await _physics_steps(4)
	await _settle(0.4)

	_check(trigger._inside, "站进触发区后 _inside = true")
	_check(trigger._prompt.visible, "站进触发区后显示 [E] 提示")

	# ── 4. 按键注册：InputMap 里确实有 interact，E 能匹配上 ────
	_check(InputMap.has_action("interact"), "InputMap 注册了 interact 动作")
	var pressed := InputEventKey.new()
	pressed.physical_keycode = KEY_E
	pressed.pressed = true
	_check(InputMap.event_is_action(pressed, "interact"),
		"E 键能匹配 interact 动作（触发区在 _ready 里自己注册的）")

	var released := InputEventKey.new()
	released.physical_keycode = KEY_E
	released.pressed = false

	# 记下"进案件之前"的位置。这是进出案件不许搬动玩家的基准线。
	var before: Vector3 = player.global_position

	# ── 5. 按 E ─────────────────────────────────────────────
	Input.parse_input_event(pressed)
	await _settle(0.1)
	Input.parse_input_event(released)
	await _settle(0.3)

	if not trigger._is_busy():
		# 无焦点窗口下注入的事件可能根本不会被派发（这是测试环境的限制，
		# 不是游戏的 bug）。退一步直接调用处理器，把"处理逻辑通不通"
		# 和"事件派发通不通"分开报告，免得把环境问题误报成代码问题。
		print("NOTE 注入事件未派发（窗口无焦点），改为直接调用 _input() 验证处理逻辑")
		trigger._input(pressed)
		await _settle(0.3)

	_check(trigger._is_busy(), "按下 E 之后触发区进入忙状态（说明 _open_case 跑了）")

	await _settle(0.9)   # 让遮罩黑掉并挂上 CaseLayer

	var layer := get_tree().root.get_node_or_null("CaseLayer")
	_check(layer != null, "打开案件后挂上了 CaseLayer")
	if layer != null:
		# 按类型找，不按节点名找 —— 场景根节点叫 Case001，写死名字很容易假失败。
		var manager: Node = null
		for child in layer.get_children():
			if child is CaseManager:
				manager = child
				break
		_check(manager != null, "CaseLayer 里装着 CaseManager")
		_check(layer.layer > 10, "CaseLayer 盖在 HUD(layer 10) 之上")
		if manager != null:
			_check(manager._phase_name == "intro", "案件停在第一个阶段 intro")
			_check(manager._phase != null and manager._phase.get_child_count() > 0,
				"intro 阶段真的建起来了（不是个空壳）")
	_check(player.automated, "进案件时玩家被冻结（automated = true）")

	# ── 6. 关闭案件，应该干干净净地回到街上 ──────────────────
	trigger._close_case()
	await _settle(0.9)

	_check(get_tree().root.get_node_or_null("CaseLayer") == null,
		"关闭之后 CaseLayer 被拆掉，没有残留")
	_check(not player.automated, "关闭之后玩家解冻")
	_check(trigger._prompt.visible, "还站在触发区里，[E] 提示回来了")

	# 玩家没有被搬走 —— "原地冻结"是策划案的硬要求
	var now: Vector3 = player.global_position
	_check(absf(now.x - before.x) < 0.6 and absf(now.z - before.z) < 0.6,
		"玩家还在触发区附近 (%.2f, %.2f, %.2f)" % [now.x, now.y, now.z])

	_finish()


func _finish() -> void:
	if _fails == 0:
		print("CASE_TRIGGER_OK")
	else:
		print("CASE_TRIGGER_FAILED (%d)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
