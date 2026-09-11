extends SceneTree
## 性能基准。FPS 会被显示链路钳制在刷新率上，量不出真实余量，
## 所以这里用 RenderingServer.force_draw() 手动驱动渲染并 force_sync() 等 GPU 干完，
## 直接测「提交 + 执行一帧」的墙上时间。这个数字不受垂直同步影响。
##
## 用法：  Godot --path <项目> --resolution 1280x800 --script res://tools/bench.gd

const WARMUP_FRAMES := 90
const SAMPLES := 200

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var scene: Node = load("res://scenes/playable_neighborhood.tscn").instantiate()
	root.add_child(scene)

	for i in WARMUP_FRAMES:
		await process_frame

	var draws: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var vmem: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)

	var times: Array[float] = []
	for i in SAMPLES:
		var t0 := Time.get_ticks_usec()
		RenderingServer.force_draw(false, 1.0 / 60.0)
		RenderingServer.force_sync()
		var t1 := Time.get_ticks_usec()
		times.append(float(t1 - t0) / 1000.0)

	times.sort()
	var median: float = times[times.size() / 2]
	var p95: float = times[int(times.size() * 0.95)]
	var total := 0.0
	for t in times:
		total += t
	var avg := total / float(times.size())

	print("BENCH_BEGIN")
	print("BENCH frame_ms_median=%.2f frame_ms_avg=%.2f frame_ms_p95=%.2f" % [median, avg, p95])
	print("BENCH implied_fps_median=%.0f" % (1000.0 / max(median, 0.001)))
	print("BENCH headroom_at_60fps=%.2fx" % (16.67 / max(median, 0.001)))
	print("BENCH draw_calls=%d" % draws)
	print("BENCH primitives=%d" % prims)
	print("BENCH video_mem_mb=%.1f" % (float(vmem) / 1048576.0))
	print("BENCH_END")
	quit(0)
