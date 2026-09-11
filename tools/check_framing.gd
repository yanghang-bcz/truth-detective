extends SceneTree
## 构图检查：把玩家能走到的边界角落投影到屏幕坐标，确认在给定的正交 size 下是否还在画面里。
## 固定正交相机不会跟随玩家，所以「镜头拉近多少」必须用可达范围来定，不能凭感觉。
##
## 用法：  Godot --path <项目> --resolution 1280x800 --script res://tools/check_framing.gd

const MARGIN := 0.06   # 要求角落离画面边缘至少留 6% 的余量

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: Node = load("res://scenes/playable_neighborhood.tscn").instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame

	var cam: Camera3D = null
	var stack := [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Camera3D:
			cam = n
		for c in n.get_children():
			stack.append(c)
	if cam == null:
		print("FRAME 找不到相机")
		quit(1)
		return

	var vp := root.get_visible_rect().size
	print("FRAME 视口=%dx%d 投影=%s" % [vp.x, vp.y, "正交" if cam.projection == Camera3D.PROJECTION_ORTHOGONAL else "透视"])

	# 玩家可达范围由 BoundaryX/BoundaryZ 决定（±15.8 / ±12.5），留一个身位
	var corners := [
		Vector3(-15.6, 0, -12.3), Vector3(15.6, 0, -12.3),
		Vector3(-15.6, 0, 12.3), Vector3(15.6, 0, 12.3),
		Vector3(0, 0, 0),
	]
	var names := ["西北角", "东北角", "西南角", "东南角", "中心"]

	for size in [34.0, 30.0, 28.0, 26.0, 24.0, 22.0]:
		cam.size = size
		for i in 2:
			await process_frame
		var worst := 0.0
		var line := ""
		for k in corners.size():
			var p := cam.unproject_position(corners[k] + Vector3(0, 0.9, 0))
			var nx: float = abs(p.x / vp.x * 2.0 - 1.0)
			var ny: float = abs(p.y / vp.y * 2.0 - 1.0)
			var m: float = max(nx, ny)
			worst = max(worst, m)
			line += "%s=(%.0f,%.0f) " % [names[k], p.x, p.y]
		var fits := worst <= (1.0 - MARGIN)
		print("FRAME size=%4.1f 最坏越界=%.2f  余量=%5.1f%%  %s" % [size, worst, (1.0 - worst) * 100.0, "OK" if fits else "出画!"])
		if size == 26.0:
			print("FRAME   size=26 各点屏幕坐标: ", line)
	quit(0)
