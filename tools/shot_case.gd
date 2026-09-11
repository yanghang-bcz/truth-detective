extends Node
## 开发用截图工具：不进 3D 街区，直接进案件界面，逐屏出图。
##
## 存在的理由很实际 —— 界面这种东西不看截图是调不出来的。
## 这个脚本会顺便把状态填成"玩家玩到一半"的样子，因为空界面看不出排版问题。
##
## 注意：必须用场景方式跑（godot res://tools/shot_case.tscn），不能用 --script。
## --script 模式下不会注册 autoload，脚本里引用 CaseState 会直接编译失败。

const OUT_DIR := "res://previews/case/"
const SIZE := Vector2i(1600, 1000)

var _case: Node = null

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_window().size = SIZE
	await get_tree().process_frame

	var packed: PackedScene = load("res://scenes/cases/case_001/case_001.tscn")
	if packed == null:
		push_error("shot_case: 加载不了案件场景")
		get_tree().quit(1)
		return
	_case = packed.instantiate()
	add_child(_case)
	await _settle(1.2)

	# ── 1. 开场（空状态 + 已选状态）────────────────────────
	await _shot("01_intro_empty")
	var jr := _find_judgment(_case)
	var slider := _find_slider(_case)
	if jr != null:
		jr.value = "suspicious"
	if slider != null:
		slider.value = 65
	await _settle(0.6)
	await _shot("02_intro_answered")

	# ── 2. 调查板（填成玩到一半的样子）──────────────────────
	CaseState.start()
	CaseState.record_judgment("B", "suspicious", 65, "Initial")
	for id in ["E01", "E02", "E04"]:
		CaseState.unlock(id)
	CaseState.mark_opened("E01")
	CaseState.classify("E01", "Direct", "Evidence")
	CaseState.mark_opened("E04")
	CaseState.focused_evidence = "E04"
	CaseState.record_judgment("B", "unsupported", 55, "After Evidence E04")
	_case._show("board")
	await _settle(1.1)
	await _shot("03_board")

	# 分析员说过一句话之后的样子
	var panel := _find_analyst(_case)
	if panel != null:
		panel._run("not_prove")
	await _settle(0.9)
	await _shot("04_board_analyst")

	# ── 3. 证据卡详情 ──────────────────────────────────────
	if _case._phase.has_method("_open_detail"):
		_case._phase._open_detail("E04")
	await _settle(1.1)
	await _shot("05_evidence_detail")

	var detail := _find_detail(_case)
	if detail != null:
		_press_chip(detail, "relevance", "Direct")
		_press_chip(detail, "kind", "Evidence")
	await _settle(0.5)
	await _shot("06_evidence_classified")

	# ── 4. 最终判定 ────────────────────────────────────────
	_case._show("final")
	await _settle(1.0)
	var answers := {"A": "supported", "B": "unsupported", "C": "insufficient", "D": "insufficient"}
	var rows: Dictionary = _case._phase._rows
	for id in rows:
		rows[id]["judgment"].value = answers.get(id, "insufficient")
	await _settle(1.0)
	await _shot("07_final")

	# ── 5. 复盘 ────────────────────────────────────────────
	for id in answers:
		CaseState.set_final(id, answers[id], 80)
		CaseState.record_judgment(id, answers[id], 78, "Final")
	_case._show("debrief")
	await _settle(1.4)
	await _shot("08_debrief")

	print("SHOT_CASE_DONE")
	get_tree().quit()

# ─────────────────────────────────────────────────────────────
func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := OUT_DIR + shot_name + ".png"
	var err := image.save_png(path)
	print("SHOT %s -> %s (%d)" % [shot_name, path, err])

func _walk(node: Node, predicate: Callable, found: Array) -> void:
	if predicate.call(node):
		found.append(node)
	for child in node.get_children():
		_walk(child, predicate, found)

## 把纸面上的分类按钮真的按下去。只调 _on_choice 是改不到按钮外观的，
## 那样截出来的图会显示成"还没选"，和玩家实际操作后的画面不一致。
func _press_chip(detail: EvidenceDetail, group: String, chosen: String) -> void:
	if detail == null or not detail._groups.has(group):
		return
	for child in detail._groups[group].get_children():
		if child is Button and (child as Button).text == chosen.to_upper():
			(child as Button).button_pressed = true
			detail._on_choice(group, chosen)
			return

func _find_typed(root_node: Node, script_name: String) -> Node:
	var found: Array = []
	_walk(root_node, func(n: Node) -> bool: return _script_name(n) == script_name, found)
	return found[0] if not found.is_empty() else null

func _script_name(n: Node) -> String:
	var script: Variant = n.get_script()
	if script == null:
		return ""
	var path: String = script.resource_path
	return path.get_file().get_basename()

func _find_judgment(root_node: Node) -> JudgmentRow:
	var found: Array = []
	_walk(root_node, func(n: Node) -> bool: return n is JudgmentRow, found)
	return found[0] if not found.is_empty() else null

func _find_slider(root_node: Node) -> ConfidenceSlider:
	var found: Array = []
	_walk(root_node, func(n: Node) -> bool: return n is ConfidenceSlider, found)
	return found[0] if not found.is_empty() else null

func _find_analyst(root_node: Node) -> AnalystPanel:
	var found: Array = []
	_walk(root_node, func(n: Node) -> bool: return n is AnalystPanel, found)
	return found[0] if not found.is_empty() else null

func _find_detail(root_node: Node) -> EvidenceDetail:
	var found: Array = []
	_walk(root_node, func(n: Node) -> bool: return n is EvidenceDetail, found)
	return found[0] if not found.is_empty() else null
