extends SceneTree

func _initialize():
	var scene=load("res://scenes/neighborhood.tscn") as PackedScene
	assert(scene != null, "Main scene must load")
	var instance=scene.instantiate()
	var count=0
	var cameras=0
	var meshes=0
	var atmosphere=0
	var volumes=0
	var shafts=0
	var dust_amount=0
	var found={}
	var stack=[instance]
	while not stack.is_empty():
		var n=stack.pop_back()
		count+=1
		for child in n.get_children(): stack.append(child)
		for landmark in ["School", "CornerCafe", "MetroEntrance", "PocketPark", "ConvenienceStore", "NeighborhoodDiner", "WestApartments", "EastApartments"]:
			if str(n.name).begins_with(landmark): found[landmark]=true
		assert(not n is CollisionObject3D, "Environment must not contain gameplay physics")
		if n is Camera3D:
			cameras+=1
			assert(n.projection==Camera3D.PROJECTION_ORTHOGONAL)
			assert(n.current)
			assert(abs(n.basis.determinant()-1.0)<0.001)
		if n is MeshInstance3D:
			meshes+=1
			assert(n.mesh != null)
		if n is WorldEnvironment:
			atmosphere+=1
			assert(n.environment.volumetric_fog_enabled)
		if n is FogVolume: volumes+=1
		if str(n.name).begins_with("DepthAwareLanternShaft"): shafts+=1
		if n is CPUParticles3D: dust_amount+=n.amount
	assert(found.size()==8, "All eight requested landmark groups must be present")
	assert(cameras==1 and atmosphere==1)
	# 静态几何体在 build_scene.gd 末尾按材质合并过：如果又冒出上千个 MeshInstance3D，
	# 说明合并步骤被跳过或失效了，绘制调用会重新爆掉。
	assert(meshes>30 and meshes<200, "静态几何体应为少量合并批次，实际: " + str(meshes))
	assert(volumes==4 and shafts==4 and dust_amount==600)
	print("PASS: 4 local fog volumes, 4 depth-aware light shafts, 600 dust particles.")
	print("PASS: scene loads; ",count," nodes, ",meshes," merged batches (from 1340 meshes), 8 landmark groups, one fixed orthographic camera and unified environment; no collision/gameplay objects.")
	instance.free()
	quit(0)
