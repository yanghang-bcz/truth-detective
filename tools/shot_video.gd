extends Control
## 单独给 VideoStill 出图。
##
## 案件界面里它只有 728×232，缩在那儿的构图问题（人太胖、头太大、站位挤）
## 根本看不清。这里按同样的长宽比放大单独渲染，静止帧与播放帧各一张。
##
## 两个坑：
##   1. 项目把 viewport 设成 1600×1000、窗口 override 成 1280×800，
##      于是截图拿到的是 1280×800 的帧缓冲，而 Canvas 坐标是 1600×1000 的。
##      这里直接把 content_scale 关掉、窗口设成正好一块视频的大小，
##      让 Canvas 坐标 == 像素坐标，省掉换算。
##   2. 截出来是整块帧缓冲，所以 VideoStill 用全屏锚点铺满就行。
##
## 用法： Godot --path <项目> res://tools/shot_video.tscn
## 产物： previews/video/still.png、previews/video/playing.png

const FRAME := Vector2i(1200, 383)   # 约等于真实界面里的 728×232

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	win.size = FRAME
	await get_tree().process_frame
	await get_tree().process_frame

	var v := VideoStill.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(v)
	await _settle(0.6)

	var shot := get_viewport().get_texture().get_image()
	print("SHOT_SIZE %dx%d  VIDEO_RECT %s" % [shot.get_width(), shot.get_height(),
		str(v.get_global_rect())])
	await _save("still")

	# 播放到 55%：手臂已经伸出去、噪点最粗的那一段。
	v.playing = true
	v._t = 0.55
	v._clock = 2.3
	v.queue_redraw()
	await _settle(0.3)
	await _save("playing")

	print("SHOT_VIDEO_DONE")
	get_tree().quit()

func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw

func _save(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var image_path := "res://previews/video/%s.png" % shot_name
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://previews/video/"))
	var err := image.save_png(image_path)
	print("SHOT %s -> %s (%d)" % [shot_name, image_path, err])
