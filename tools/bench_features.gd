extends SceneTree
## 逐项 A/B 基准：在同一进程里反复开关单个渲染特性，量出每一项的真实成本。
## 用 force_draw + force_sync 绕开垂直同步，得到的是「提交+GPU执行」一帧的墙上时间。
##
## 用法：  Godot --path <项目> --resolution 1280x800 --script res://tools/bench_features.gd

var scene: Node
var env: Environment
var moon: DirectionalLight3D
var spots: Array = []
var shafts: Array = []
var dusts: Array = []
var fogs: Array = []

func _initialize() -> void:
	call_deferred("run")

func collect(node: Node) -> void:
	var n := str(node.name)
	if node is WorldEnvironment:
		env = node.environment
	elif node is DirectionalLight3D:
		moon = node
	elif node is SpotLight3D:
		spots.append(node)
	elif node is FogVolume:
		fogs.append(node)
	elif node is CPUParticles3D:
		dusts.append(node)
	elif node is MeshInstance3D and n.begins_with("DepthAwareLanternShaft"):
		shafts.append(node)
	for c in node.get_children():
		collect(c)

func sample(frames: int = 140) -> float:
	for i in 16:
		RenderingServer.force_draw(false, 1.0 / 60.0)
		RenderingServer.force_sync()
	var times: Array[float] = []
	for i in frames:
		var t0 := Time.get_ticks_usec()
		RenderingServer.force_draw(false, 1.0 / 60.0)
		RenderingServer.force_sync()
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	times.sort()
	return times[times.size() / 2]

func measure(label: String) -> float:
	var med := sample()
	var draws: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("FEAT %-30s median=%6.2fms  draws=%d" % [label, med, draws])
	return med

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	scene = load("res://scenes/playable_neighborhood.tscn").instantiate()
	root.add_child(scene)
	for i in 90:
		await process_frame
	collect(scene)
	print("FEAT 找到: spots=", spots.size(), " shafts=", shafts.size(), " dusts=", dusts.size(), " fogvolumes=", fogs.size())

	var base := measure("A 当前配置")

	env.ssil_enabled = true
	measure("B + SSIL 打开")
	env.ssil_enabled = false

	env.ssao_enabled = false
	measure("C SSAO 关闭")
	env.ssao_enabled = true

	env.volumetric_fog_enabled = false
	measure("D 体积雾关闭")
	env.volumetric_fog_enabled = true

	env.glow_enabled = false
	measure("E 辉光关闭")
	env.glow_enabled = true

	for s in spots:
		s.shadow_enabled = false
	measure("F 灯笼阴影关闭")
	for s in spots:
		s.shadow_enabled = true

	for s in spots:
		s.light_volumetric_fog_energy = 28.0
	measure("G 灯笼参与体积雾")
	for s in spots:
		s.light_volumetric_fog_energy = 0.0

	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	measure("H 月光改回 4 级级联")
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL

	moon.shadow_enabled = false
	measure("I 月光阴影关闭")
	moon.shadow_enabled = true

	for d in dusts:
		d.emitting = false
	measure("J 尘埃粒子关闭")
	for d in dusts:
		d.emitting = true

	for s in shafts:
		s.visible = false
	measure("K 灯笼光柱着色器关闭")
	for s in shafts:
		s.visible = true

	for f in fogs:
		f.visible = false
	measure("L 局部雾体积关闭")
	for f in fogs:
		f.visible = true

	print("FEAT 基线=%.2fms" % base)
	quit(0)
