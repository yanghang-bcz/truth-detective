extends SceneTree
## 可达性回归测试：角色**自己走过去**能不能走进地铁口触发区。
##
## 为什么需要它：test_case_trigger.gd 是**把玩家瞬移进触发区**的
## （player.global_position = center），所以"玩家能不能走到那里"从来没被验证过。
## 一旦出生点、碰撞体或街道布局改动导致走不到，整局游戏就是死的 ——
## 而其它所有测试依然全绿。这条测试补的就是这个盲区。
##
## 策略：每帧朝目标贪心选键；卡住超过 0.5s 就横向绕一下。
## 这不是寻路算法，只是一个"鲁棒性够用的探针"。

var player: CharacterBody3D
var right := Vector3.ZERO
var back := Vector3.ZERO
var failed := false

const KEYS := {
	"w": KEY_W, "a": KEY_A, "s": KEY_S, "d": KEY_D,
}

func _initialize() -> void: call_deferred("run")

func frames(n: int) -> void:
	for i in range(n): await physics_frame

func ev(code: int, pressed: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	return e

func sync(active: Dictionary, want: Array) -> void:
	for k in KEYS.keys():
		var should := want.has(k)
		if bool(active.get(k, false)) != should:
			Input.parse_input_event(ev(KEYS[k], should))
			active[k] = should

## 触发区用哪个 CollisionShape3D 由场景决定，节点名不稳定，遍历找第一个。
func find_box(trigger: Node) -> CollisionShape3D:
	for child in trigger.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			return child
	return null

func run() -> void:
	var scene = load("res://scenes/playable_neighborhood.tscn").instantiate()
	root.add_child(scene)
	player = scene.get_node("Detective")
	await frames(90)

	var trigger = scene.get_node_or_null("MetroEntranceTrigger")
	if trigger == null:
		print("FAIL 场景里找不到 MetroEntranceTrigger")
		quit(1)
		return

	var box_node := find_box(trigger)
	if box_node == null:
		print("FAIL MetroEntranceTrigger 下没有 BoxShape3D")
		quit(1)
		return

	var cam: Camera3D = root.get_camera_3d()
	right = cam.global_basis.x
	right.y = 0
	right = right.normalized()
	back = cam.global_basis.z
	back.y = 0
	back = back.normalized()

	var center: Vector3 = trigger.global_position
	var box: Vector3 = (box_node.shape as BoxShape3D).size
	var half := Vector3(box.x * 0.5, 0, box.z * 0.5)

	var spawn := player.global_position
	print("NOTE 出生点 (%.2f, %.2f) → 触发区 (%.2f, %.2f) 半盒 (%.2f, %.2f)" % [
		spawn.x, spawn.z, center.x, center.z, half.x, half.z])

	var active := {}
	var best := 1e9
	var best_pos := player.global_position
	var stuck_for := 0
	var detour := 0
	var detour_left := 0
	var reached_at := -1.0

	# 25 秒预算：正常走位约 8 秒，留足绕行余量。
	for frame in range(60 * 25):
		var pos := player.global_position
		var d := center - pos
		d.y = 0
		var dist := d.length()
		if dist < best - 0.02:
			best = dist
			best_pos = pos
			stuck_for = 0
		else:
			stuck_for += 1

		var flat := Vector3(pos.x - center.x, 0, pos.z - center.z)
		if absf(flat.x) <= half.x and absf(flat.z) <= half.z:
			reached_at = frame / 60.0
			break

		if stuck_for > 30:
			if detour_left <= 0:
				detour += 1
				detour_left = 45
			stuck_for = 0

		var dir := d.normalized()
		if detour_left > 0:
			detour_left -= 1
			# 绕行：把朝向目标的方向旋转 ±90°，交替尝试
			var sign := 1.0 if detour % 2 == 0 else -1.0
			dir = Vector3(dir.z * sign, 0, -dir.x * sign)

		var want: Array = []
		var ix := dir.dot(right)
		var iy := dir.dot(back)
		if ix > 0.38: want.append("d")
		elif ix < -0.38: want.append("a")
		if iy > 0.38: want.append("s")
		elif iy < -0.38: want.append("w")
		if want.is_empty():
			want.append("s")
		sync(active, want)
		await physics_frame

	sync(active, [])
	await frames(2)

	var ok := reached_at >= 0.0
	if not ok: failed = true
	print("%s 从出生点走到地铁口触发区（%.1fs，最近 %.2f m 在 (%.2f, %.2f)）" % [
		"PASS" if ok else "FAIL",
		reached_at, best, best_pos.x, best_pos.z])

	print("METRO_REACHABILITY 1/1" if not failed else "METRO_REACHABILITY 0/1")
	quit(1 if failed else 0)
