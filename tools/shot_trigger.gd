extends Node
## 截一张"玩家正站在地铁口"的图。
##
## 这是玩家在街上唯一会看到的新东西：左上角那行目标、屏幕下方的 [E] 提示。
## 案件界面本身有 shot_case 逐屏覆盖，但这一屏一直没人看过 ——
## 而它恰恰是玩家的第一印象。不看一眼就交付，等于把它交给运气。
##
## 用场景方式跑（--script 模式不注册 autoload）：
##   godot --path <项目> res://tools/shot_trigger.tscn

const SCENE := "res://scenes/playable_neighborhood.tscn"
const OUT_DIR := "res://previews/case/"
const OUT_NAME := "00_metro_prompt.png"


func _ready() -> void:
	call_deferred("run")


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw


func run() -> void:
	get_window().size = Vector2i(1600, 1000)
	await get_tree().process_frame

	var street: Node = load(SCENE).instantiate()
	add_child(street)
	await _settle(1.0)

	var trigger := street.get_node_or_null("MetroEntranceTrigger")
	var player := street.get_node_or_null("Detective")
	if trigger == null or player == null:
		push_error("shot_trigger: 场景里缺触发区或玩家")
		get_tree().quit(1)
		return

	# 把玩家放到触发区正下方，模拟"刚走到地铁口"。
	var center: Vector3 = trigger.global_position
	player.global_position = Vector3(center.x, player.global_position.y, center.z)
	for _i in range(6):
		await get_tree().physics_frame
	await _settle(1.0)   # 等提示的淡入 + 上浮动画走完

	print("PROMPT_VISIBLE ", trigger._prompt.visible, "  INSIDE ", trigger._inside)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var image := get_viewport().get_texture().get_image()
	print("SAVED ", OUT_DIR + OUT_NAME, " (", image.save_png(OUT_DIR + OUT_NAME), ")")
	print("SHOT_TRIGGER_DONE")
	get_tree().quit()
