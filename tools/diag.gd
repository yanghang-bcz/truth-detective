extends SceneTree
## 诊断：统计场景里每个网格的三角形数量，定位几何与碰撞体的成本来源。
## 用法：  Godot --path <项目> --headless --script res://tools/diag.gd

func _initialize() -> void:
	call_deferred("run")

func tri_count(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var arrays: Array = m.surface_get_arrays(s)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		var idx = arrays[Mesh.ARRAY_INDEX]
		var vtx = arrays[Mesh.ARRAY_VERTEX]
		if idx != null and idx.size() > 0:
			t += int(idx.size()) / 3
		elif vtx != null:
			t += int(vtx.size()) / 3
	return t

func gather(node: Node, out: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		out.append(node)
	for c in node.get_children():
		gather(c, out)

func run() -> void:
	var scene: Node = load("res://scenes/neighborhood.tscn").instantiate()
	root.add_child(scene)
	var meshes: Array = []
	gather(scene, meshes)

	var total := 0
	var rows: Array = []
	for n in meshes:
		var t := tri_count(n.mesh)
		total += t
		var mat_name := ""
		if n.material_override is BaseMaterial3D:
			mat_name = n.material_override.resource_name
		if mat_name == "":
			mat_name = n.material_override.get_class() if n.material_override else "none"
		rows.append([t, String(n.name), mat_name])

	rows.sort_custom(func(a, b): return a[0] > b[0])

	print("DIAG_BEGIN")
	print("DIAG mesh_instances=%d  total_triangles=%d" % [meshes.size(), total])
	print("DIAG --- 最重的 15 个网格 ---")
	for i in mini(15, rows.size()):
		print("DIAG TOP%-3d tris=%-7d name=%-30s mat=%s" % [i + 1, rows[i][0], rows[i][1], rows[i][2]])

	var by_prefix := {}
	for r in rows:
		var p: String = String(r[1]).split("_")[0]
		by_prefix[p] = int(by_prefix.get(p, 0)) + int(r[0])
	var keys = by_prefix.keys()
	keys.sort_custom(func(a, b): return by_prefix[a] > by_prefix[b])
	print("DIAG --- 按节点名前缀汇总（前 15）---")
	for i in mini(15, keys.size()):
		print("DIAG PRE %-28s tris=%-8d nodes=?" % [keys[i], by_prefix[keys[i]]])
	print("DIAG_END")
	quit(0)
