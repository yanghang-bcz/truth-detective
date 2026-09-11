extends SceneTree
## 测量场景加载耗时（读盘 + 解析 + 实例化 + 物理体构建）。
## 用法：  Godot --path <项目> --headless --script res://tools/bench_load.gd

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# 冷启动：先卸掉缓存
	var t0 := Time.get_ticks_usec()
	var packed: PackedScene = load("res://scenes/playable_neighborhood.tscn")
	var t1 := Time.get_ticks_usec()
	var inst: Node = packed.instantiate()
	var t2 := Time.get_ticks_usec()
	root.add_child(inst)
	# 等物理体真正建好（ConcavePolygonShape3D 的 BVH 是在这里构建的）
	for i in 30:
		await physics_frame
	var t3 := Time.get_ticks_usec()

	var nodes := 0
	var meshes := 0
	var stack := [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		nodes += 1
		if n is MeshInstance3D:
			meshes += 1
		for c in n.get_children():
			stack.append(c)

	print("LOAD_BEGIN")
	print("LOAD parse_ms=%.1f instantiate_ms=%.1f physics_ready_ms=%.1f total_ms=%.1f" % [
		float(t1 - t0) / 1000.0, float(t2 - t1) / 1000.0, float(t3 - t2) / 1000.0, float(t3 - t0) / 1000.0])
	print("LOAD nodes=%d mesh_instances=%d" % [nodes, meshes])
	print("LOAD_END")
	quit(0)
