extends Node
## 案件界面的帧耗基准。
##
## 为什么单独测：案件界面是一层不透明的全屏 CanvasLayer，但它**不会**让底下的
## 3D 街区停止渲染 —— Godot 照旧把整个街区（298 个绘制调用、MSAA 解析、
## 每像素 40 次迭代的灯束着色器）画一遍，然后被上面那层界面整个盖住。
## 也就是说玩家盯着一个静态界面的时候，GPU 还在满负荷渲染他看不见的街道。
##
## 这个工具把三种状态的帧耗时并排量出来：
##   A 街区单独
##   B 案件界面叠加（街区仍在渲染）—— 也就是现在的实现
##   C 案件界面叠加 + 街区停渲染 —— 也就是修复后
##   D 在 C 的基础上再关掉全屏颗粒/暗角
##
## 用 force_draw + force_sync 取墙上时间，不受垂直同步影响（和 tools/bench.gd 同一套方法）。
##
## 用法： Godot --path <项目> res://tools/bench_case.tscn

const SCENE := "res://scenes/playable_neighborhood.tscn"
const WARMUP := 60
const SAMPLES := 140

var _world: Node
var _results: Array = []

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	_world = load(SCENE).instantiate()
	add_child(_world)

	for i in WARMUP:
		await get_tree().process_frame

	await _sample("A 街区单独")
	await _sample_loop("A 街区单独（整帧）")

	# ── 打开案件界面（走真实路径，和玩家按 E 一样）──────────────
	var trigger := _world.get_node_or_null("MetroEntranceTrigger")
	if trigger == null:
		print("BENCH_ERROR 找不到 MetroEntranceTrigger —— 场景没重建？")
		get_tree().quit(1)
		return
	trigger.call("_open_case")
	for i in 90:
		await get_tree().process_frame

	var case_layer := get_tree().root.get_node_or_null("CaseLayer")
	if case_layer == null:
		print("BENCH_ERROR 案件层没建起来")
		get_tree().quit(1)
		return

	# ── 故意把街区恢复渲染，模拟"没做这项优化"的旧实现 ──────
	# 这一行是这个工具存在的意义：以后谁把优化删了，它立刻会喊出来。
	_world.visible = true
	await _sample("B 案件界面（模拟旧实现：街区仍在渲染）")

	# ── 修复后的真实状态：触发脚本自己已经把街区关掉了 ────────
	_world.visible = false
	await _sample("C 案件界面（真实状态）")

	await _sample_loop("C 案件界面（真实状态，整帧）")

	# ── 物理也值不值得停？测一下再决定 ────────────────────────
	PhysicsServer3D.set_active(false)
	await _sample_loop("F C + 物理也停（整帧）")
	PhysicsServer3D.set_active(true)

	# ── 再关掉全屏质感层，量它自己的成本 ──────────────────────
	var case_root := case_layer.get_child(0)
	var fx := case_root.get_node_or_null("ScreenFX")
	if fx != null:
		fx.visible = false
		await _sample("D C + 关掉颗粒/暗角")
		fx.visible = true

	_world.visible = true
	await _sample("E 恢复街区（对照 A）")

	_report()
	get_tree().quit(0)

## 主循环整帧耗时。force_draw 只量渲染，量不到物理和脚本 ——
## 而"电脑发烫"是整帧的事，不是渲染一家的账。
## 除了中位数，这里还把 p99 / 最大值 / 掉帧数一起打出来：
## 中位数好看但偶尔卡一下，玩起来照样难受，只看中位数会漏掉这种事。
func _sample_loop(label: String) -> void:
	for i in 24:
		await get_tree().process_frame
	var times: Array[float] = []
	var prev := Time.get_ticks_usec()
	for i in 240:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - prev) / 1000.0)
		prev = now
	times.sort()
	var n := times.size()
	var over := 0
	for t in times:
		if t > 8.0:
			over += 1
	print("LOOP  %-28s p50=%5.2f  p90=%6.2f  p99=%7.2f  max=%7.2f  >8ms: %d/%d" % [
		label, times[n / 2], times[int(n * 0.90)], times[int(n * 0.99)],
		times[n - 1], over, n])


func _sample(label: String) -> void:
	for i in 16:
		await get_tree().process_frame
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
	var draws: int = RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	_results.append({"label": label, "median": median, "p95": p95, "draws": draws})
	print("BENCH %-30s median=%6.2fms  p95=%6.2fms  draws=%5d" % [label, median, p95, draws])

func _pick(prefix: String) -> float:
	for r in _results:
		if r["label"].begins_with(prefix):
			return r["median"]
	return 0.0

func _report() -> void:
	print("BENCH_BEGIN")
	var base := 0.0
	for r in _results:
		print("BENCH %-30s median=%6.2fms draws=%5d" % [r["label"], r["median"], r["draws"]])
		if base == 0.0:
			base = r["median"]
	for r in _results:
		if r["median"] < base:
			print("BENCH 相比 A 节省 %.0f%%" % ((1.0 - r["median"] / base) * 100.0))
			break
	for r in _results:
		if r["label"].begins_with("B"):
			print("BENCH 旧实现 %6.2fms / 修复后 %.2fms —— 省 %.0f%%"
				% [r["median"], _pick("C"), (1.0 - _pick("C") / max(r["median"], 0.001)) * 100.0])
			break
	print("BENCH_END")
