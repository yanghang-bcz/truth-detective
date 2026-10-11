extends SceneTree
## 真实输入链路冒烟测试：键盘事件 → InputMap → Input.get_vector → 角色位移。
##
## 为什么需要它：test_player.gd 走的是 automated + test_input 的旁路，
## 证明的是"物理和动画没问题"，但**证明不了玩家真按键时角色会动**。
## 这条链路（动作注册 / 物理键位映射 / Input 单例）一旦断掉，
## 所有现有测试依然全绿，而玩家进游戏后只能干站着 —— 正是网页版最容易踩的坑。
##
## 用 Input.parse_input_event() 注入真实 InputEventKey，走完整管线。

var player: CharacterBody3D
var results: Array[String] = []
var failed := false

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	results.append(("PASS " if ok else "FAIL ") + label)
	print(results[-1])
	if not ok: failed = true

func frames(n: int) -> void:
	for i in range(n): await physics_frame

func key_event(code: int, pressed: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	return e

func hold(code: int, n: int) -> void:
	Input.parse_input_event(key_event(code, true))
	await frames(n)
	Input.parse_input_event(key_event(code, false))
	await frames(2)

func run() -> void:
	var scene = load("res://scenes/playable_neighborhood.tscn").instantiate()
	root.add_child(scene)
	player = scene.get_node("Detective")
	await frames(60)

	# 1. 动作确实被注册了
	for action in ["detective_left", "detective_right", "detective_up", "detective_down", "detective_run"]:
		check(InputMap.has_action(action), "InputMap 注册了 " + action)

	# 2. 注册的事件里确实带 W/A/S/D 与方向键的物理键位
	var codes := {}
	for ev in InputMap.action_get_events("detective_right"):
		if ev is InputEventKey: codes[ev.physical_keycode] = true
	check(codes.has(KEY_D) and codes.has(KEY_RIGHT), "detective_right 绑定了 D 和 →")

	# 3. 真的按下去，Input 单例要认
	Input.parse_input_event(key_event(KEY_D, true))
	await frames(2)
	check(Input.is_action_pressed("detective_right"), "真实按键后 is_action_pressed(detective_right) 为真")
	var vec := Input.get_vector("detective_left", "detective_right", "detective_up", "detective_down")
	check(abs(vec.x - 1.0) < 0.01, "真实按键后 get_vector().x ≈ 1，实际 %.3f" % vec.x)
	Input.parse_input_event(key_event(KEY_D, false))
	await frames(2)

	# 4. 端到端：按 D 两秒，角色必须真的挪窝
	player.global_position = Vector3(0, .15, 0)
	player.velocity = Vector3.ZERO
	await frames(30)
	var start := player.position
	await hold(KEY_D, 120)
	var moved := player.position.distance_to(start)
	check(moved > 1.0, "按住 D 两秒位移 > 1m，实际 %.2f m" % moved)
	check(player.is_on_floor(), "移动后仍在地面")

	# 5. Shift 奔跑
	Input.parse_input_event(key_event(KEY_SHIFT, true))
	await frames(2)
	check(Input.is_action_pressed("detective_run"), "Shift 触发 detective_run")
	Input.parse_input_event(key_event(KEY_SHIFT, false))

	print("INPUT_TESTS %d/%d" % [results.size() - (0 if failed else 0), results.size()])
	quit(1 if failed else 0)
