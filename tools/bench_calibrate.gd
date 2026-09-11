extends SceneTree
## 校准测量方法：空场景能跑到多少帧？据此判断 bench 是否被垂直同步/刷新率卡住。

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("CAL vsync_mode_before=", DisplayServer.window_get_vsync_mode())
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await process_frame
	await process_frame
	print("CAL vsync_mode_after=", DisplayServer.window_get_vsync_mode(), "  engine_max_fps=", Engine.max_fps)
	print("CAL display_size=", DisplayServer.window_get_size(), " dpi=", DisplayServer.screen_get_dpi())

	for i in 120:
		await process_frame
	var samples: Array[float] = []
	for i in 240:
		await process_frame
		samples.append(Engine.get_frames_per_second())
	samples.sort()
	print("CAL empty_scene fps_median=", samples[samples.size() / 2], " fps_max=", samples[-1])
	quit(0)
