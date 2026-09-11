extends SceneTree

var world: Node3D
var mats = {}
var serial = 0
var rng = RandomNumberGenerator.new()

func mat(key, color, roughness=0.8, metallic=0.0, glow=0.0):
	var m = StandardMaterial3D.new()
	# 材质名同时用作合并分组的标识和碰撞体筛选依据，不能去掉。
	m.resource_name = str(key)
	m.albedo_color = Color(color)
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.metallic = 0.0
	if glow > 0:
		m.emission_enabled = true
		m.emission = Color(color)
		m.emission_energy_multiplier = glow
	mats[key] = m
	return m

func put(n, label, parent=null):
	if n is Light3D: n.light_specular = 0.0
	if parent == null: parent = world
	serial += 1
	n.name = label + "_%04d" % serial
	parent.add_child(n)
	n.owner = world
	return n

func group(label):
	return put(Node3D.new(), label)

func box(p, size, material, parent=null, label="Masonry"):
	var n = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	n.mesh = mesh
	n.material_override = mats[material]
	n.position = p
	return put(n, label, parent)

func slab(p, size, material, parent, title):
	# Subtract the subway stairwell from every ground layer.
	var x0=p.x-size.x/2.0
	var x1=p.x+size.x/2.0
	var z0=p.z-size.z/2.0
	var z1=p.z+size.z/2.0
	var hx0=max(x0,-6.05)
	var hx1=min(x1,-3.55)
	var hz0=max(z0,4.45)
	var hz1=min(z1,8.8)
	if hx0>=hx1 or hz0>=hz1:
		box(p,size,material,parent,title)
		return
	for r in [Vector4(x0,z0,hx0,z1),Vector4(hx1,z0,x1,z1),Vector4(hx0,z0,hx1,hz0),Vector4(hx0,hz1,hx1,z1)]:
		if r.z-r.x>0.001 and r.w-r.y>0.001:
			box(Vector3((r.x+r.z)/2,p.y,(r.y+r.w)/2),Vector3(r.z-r.x,size.y,r.w-r.y),material,parent,title)

func cyl(p, radius, height, material, parent=null, top=-1.0):
	var n = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius if top < 0 else top
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	n.mesh = mesh
	n.material_override = mats[material]
	n.position = p
	return put(n, "TurnedDetail", parent)

func orb(p, size, material, parent=null):
	var n = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	n.mesh = mesh
	n.position = p
	n.scale = size
	n.material_override = mats[material]
	return put(n, "OrganicForm", parent)

func beam(a,b,r, material,parent=null):
	var n = cyl((a+b)*0.5,r,a.distance_to(b),material,parent)
	var direction = (b-a).normalized()
	var axis = Vector3.UP.cross(direction)
	if axis.length() > 0.001: n.quaternion = Quaternion(axis.normalized(), Vector3.UP.angle_to(direction))
	return n

func label3(text,p,size,parent=null):
	var n = Label3D.new()
	n.text = text
	n.font_size = 64
	n.pixel_size = size/64.0
	n.position = p
	n.modulate = Color("d6c9a7")
	n.outline_size = 0
	n.no_depth_test = false
	return put(n,"SignText",parent)

func light(p,energy=1.4,radius=5.0,parent=null):
	var n = OmniLight3D.new()
	n.position = p
	n.light_color = Color("ffcb88")
	n.light_energy = energy
	n.omni_range = radius
	n.omni_attenuation = 1.6
	return put(n,"WarmPool",parent)

func window(p,w,h,parent,lit=false):
	box(p,Vector3(w+0.17,h+0.17,0.15),"trim",parent,"WindowSurround")
	box(p+Vector3(0,0,0.086),Vector3(w,h,0.04),"glow" if lit else "glass",parent,"WindowPane")
	box(p+Vector3(0,0,0.12),Vector3(0.065,h,0.045),"iron",parent)
	box(p+Vector3(0,0,0.12),Vector3(w,0.055,0.045),"iron",parent)
	box(p+Vector3(0,-h/2-0.07,0.08),Vector3(w+0.28,0.11,0.34),"stone",parent,"Sill")

func building(title,x,z,w,d,h,material,floors):
	var g=group(title)
	box(Vector3(x,h/2+0.25,z),Vector3(w,h,d),material,g,"Facade")
	box(Vector3(x,0.45,z),Vector3(w+0.17,0.45,d+0.17),"stone",g,"Foundation")
	box(Vector3(x,h+0.32,z),Vector3(w+0.5,0.27,d+0.5),"trim",g,"Cornice")
	box(Vector3(x,h+0.49,z),Vector3(w+0.18,0.12,d+0.18),"roof",g,"FlatRoof")
	for side in [-1,1]:
		box(Vector3(x+side*(w/2-0.03),h+0.72,z),Vector3(0.17,0.42,d),"trim",g,"Parapet")
	box(Vector3(x,h+0.72,z-d/2),Vector3(w,0.42,0.18),"trim",g,"Parapet")
	for level in range(floors):
		var wy=1.8+level*2.0
		if wy+0.7>h: continue
		for col in range(int(w/1.65)):
			var wx=x-w/2+0.9+col*1.65
			window(Vector3(wx,wy,z+d/2+0.03),0.86,1.12,g,rng.randf()<0.23)
		box(Vector3(x,wy+0.9,z+d/2+0.04),Vector3(w,0.09,0.08),"trim",g,"BeltCourse")
	# Shallow side reveals make the fixed camera read real building depth.
	for row in range(floors):
		for col in range(2):
			box(Vector3(x+w/2+0.016,1.8+row*2,z-0.9+col*1.6),Vector3(0.045,1.05,0.76),"glass",g,"SideWindow")
	for j in range(2):
		box(Vector3(x-w*0.25+j*w*0.5,h+0.9,z-0.6),Vector3(0.58,0.85,0.62),"stone",g,"Chimney")
		box(Vector3(x-w*0.25+j*w*0.5,h+1.35,z-0.6),Vector3(0.76,0.12,0.8),"roof",g)
	# Subtle individual masonry repairs and rain streaks.
	for k in range(18):
		box(Vector3(x+rng.randf_range(-w/2+0.3,w/2-0.3),rng.randf_range(0.6,h),z+d/2+0.018),Vector3(rng.randf_range(0.12,0.48),0.055,0.028),"brick_detail",g,"Weathering")
	return g

func shop(g,x,z,w,title,awning):
	box(Vector3(x,1.3,z),Vector3(w-0.6,1.9,0.15),"iron",g,"Shopfront")
	for side in [-1,1]:
		box(Vector3(x+side*w*0.25,1.4,z+0.09),Vector3(w*0.35,1.4,0.06),"glow",g,"DisplayWindow")
		for k in range(3):
			box(Vector3(x+side*w*0.25+(k-1)*0.28,0.9,z+0.14),Vector3(0.12,0.22,0.1),"wood",g,"DisplayObjects")
	box(Vector3(x,1.25,z+0.1),Vector3(0.8,2,0.12),"wood",g,"EntranceDoor")
	box(Vector3(x,1.53,z+0.18),Vector3(0.6,1.12,0.05),"glass",g)
	cyl(Vector3(x+0.25,1.1,z+0.27),0.045,0.08,"brass",g)
	box(Vector3(x,2.76,z+0.05),Vector3(w-0.28,0.58,0.22),"sign",g,"ShopSign")
	label3(title,Vector3(x,2.77,z+0.18),0.45,g)
	for j in range(12):
		var n=box(Vector3(x-w/2+0.25+j*(w-0.5)/12,2.3,z+0.49),Vector3((w-0.5)/12,0.12,0.93),awning if j%2==0 else "canvas",g,"AwningStripe")
		n.rotation.x=0.12
		box(Vector3(n.position.x,2.16,z+0.94),Vector3((w-0.5)/12,0.24,0.06),awning if j%2==0 else "canvas",g)
	light(Vector3(x,1.9,z+1.0),1.2,4.5,g)

func refined(title, asset, position):
	var g=group(title)
	var doc=GLTFDocument.new()
	var state=GLTFState.new()
	var err=doc.append_from_file("res://assets/models/"+asset+".glb",state)
	assert(err==OK, "Refined GLB asset must load")
	var n=doc.generate_scene(state)
	n.name="BlenderModel"
	n.position=position
	g.add_child(n)
	var stack=[n]
	while not stack.is_empty():
		var child=stack.pop_back()
		child.owner=world
		for descendant in child.get_children(): stack.append(descendant)
	return g

func lamp(x,z):
	var g=refined("Streetlamp", "streetlamp_refined", Vector3(x,0,z))
	light(Vector3(x+0.65,3.27,z),0.65,4.5,g)
	var spot=SpotLight3D.new()
	spot.position=Vector3(x+0.65,3.04,z)
	spot.basis=Basis.looking_at(Vector3(0.15,-1,0.1),Vector3.FORWARD)
	spot.light_color=Color("ffd09a")
	spot.light_energy=3.2
	spot.light_volumetric_fog_energy=28.0
	spot.spot_range=6.0
	spot.spot_angle=34
	spot.spot_attenuation=1.2
	# 保留灯下投影：几何合并后每一遍阴影渲染只剩几十次绘制，这点开销买得到灯杆
	# 落在地上的影子，值得。
	spot.shadow_enabled=true
	put(spot,"LanternVolumeBeam",g)
	var volume=FogVolume.new()
	volume.position=Vector3(x+0.65,1.65,z)
	volume.size=Vector3(3.0,3.0,3.0)
	volume.shape=RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	var fm=FogMaterial.new()
	fm.density=0.09
	fm.albedo=Color("c2b6a1")
	fm.edge_fade=1.0
	volume.material=fm
	put(volume,"LocalLanternHaze",g)
	var shaft=MeshInstance3D.new()
	var bounds=BoxMesh.new()
	bounds.size=Vector3(3.5,2.8,3.5)
	shaft.mesh=bounds
	shaft.position=Vector3(x+0.65,1.64,z)
	var shaft_mat=ShaderMaterial.new()
	shaft_mat.shader=load("res://shaders/lantern_beam.gdshader")
	shaft.material_override=shaft_mat
	shaft.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	put(shaft,"DepthAwareLanternShaft",g)
	dust_cluster(Vector3(x+0.5,1.9,z),Vector3(0.95,1.45,0.95),90,g)

func dust_cluster(position, extents, amount, parent=null):
	var dust=CPUParticles3D.new()
	dust.position=position
	dust.amount=amount
	dust.lifetime=18
	dust.preprocess=18
	dust.emission_shape=CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents=extents
	dust.direction=Vector3(0.4,0.24,0.16)
	dust.spread=55
	dust.gravity=Vector3(0,0.002,0)
	dust.initial_velocity_min=0.025
	dust.initial_velocity_max=0.075
	dust.scale_amount_min=0.025
	dust.scale_amount_max=0.063
	var quad=QuadMesh.new()
	quad.size=Vector2.ONE
	dust.mesh=quad
	var dm=ShaderMaterial.new()
	dm.shader=load("res://shaders/dust.gdshader")
	dust.material_override=dm
	var gradient=Gradient.new()
	gradient.set_color(0,Color(1,1,1,0))
	gradient.add_point(0.12,Color(1,1,1,0.8))
	gradient.add_point(0.80,Color(1,1,1,0.8))
	gradient.set_color(1,Color(1,1,1,0))
	dust.color_ramp=gradient
	put(dust,"LightCaughtDust",parent)

func bench(x,z,rot=0.0):
	var g=group("ParkBench")
	g.position=Vector3(x,0,z)
	g.rotation.y=rot
	for k in range(4):
		box(Vector3(0,0.68,(k-1.5)*0.16),Vector3(1.65,0.10,0.12),"wood",g,"SeatSlat")
	for k in range(3):
		box(Vector3(0,0.96+k*0.17,-0.24),Vector3(1.65,0.12,0.1),"wood",g,"BackSlat")
	for side in [-1,1]:
		box(Vector3(side*0.61,0.4,0),Vector3(0.07,0.52,0.48),"iron",g)
		box(Vector3(side*0.61,1.0,-0.3),Vector3(0.07,0.7,0.07),"iron",g)

func tree(x,z,height=3.5):
	var g=group("PollardedTree")
	cyl(Vector3(x,0.24,z),0.85,0.22,"stone",g)
	cyl(Vector3(x,0.37,z),0.71,0.08,"soil",g)
	beam(Vector3(x,0.4,z),Vector3(x+0.2,height,z),0.14,"bark",g)
	for j in range(5):
		var ang=j*TAU/5.0
		var end=Vector3(x+cos(ang)*0.8,height+0.4+sin(j)*0.3,z+sin(ang)*0.8)
		beam(Vector3(x+0.14,height*0.6,z),end,0.07,"bark",g)
		orb(end,Vector3(0.85,0.95,0.75),"foliage",g)
	orb(Vector3(x+0.15,height+0.9,z),Vector3(1.0,0.9,0.95),"foliage",g)

func build_collision_shape():
	# 必须在合并之前跑：合并之后就分不出单个物体了。
	# 玩家是 1.5 米高的胶囊，够不到的东西（招牌字、窗棂、遮阳篷、女儿墙）对碰撞毫无意义，
	# 却占了这个网格 80% 以上的三角面 —— 之前那 24MB 的单行数据就是这么来的。
	var instances = []
	gather_meshes(world, instances)
	var faces = PackedVector3Array()
	var used = 0
	for node in instances:
		var mesh = node.mesh
		if mesh == null or mesh.get_surface_count() == 0: continue
		var label = str(node.name)
		var m = node.material_override
		var mat_name = m.resource_name if m != null else ""
		var skip = false
		for word in ["Crosswalk", "LaneDash", "FallenLeaf", "DrainSlot", "BeamCone", "Surround", "Puddle", "Weathering", "DriftingMistLayer", "FallenLeaf"]:
			if word in label: skip = true
		for word in ["leaf", "paint", "void", "puddle", "canvas", "glow", "brick_detail"]:
			if mat_name == word: skip = true
		if m is ShaderMaterial and not ("Street" in label): skip = true
		if m is StandardMaterial3D and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: skip = true
		var box = node.global_transform * mesh.get_aabb()
		if box.position.y > 1.55: skip = true
		if box.size.length() < 0.22: skip = true
		if skip: continue
		var local_faces = mesh.get_faces()
		for v in local_faces:
			faces.append(node.global_transform * v)
		used += 1
	var shape = ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var err = ResourceSaver.save(shape, "res://scenes/neighborhood_collision.res")
	print("Collision: ", used, " objects, ", faces.size() / 3, " triangles (err ", err, ")")

func gather_meshes(node, out):
	for c in node.get_children():
		if c is MeshInstance3D:
			out.append(c)
		gather_meshes(c, out)

func attr_sig(a):
	# 顶点属性组合相同的网格才能安全合并进同一个表面。
	var s = ""
	if a[Mesh.ARRAY_NORMAL] != null: s += "n"
	if a[Mesh.ARRAY_TANGENT] != null: s += "t"
	if a[Mesh.ARRAY_COLOR] != null: s += "c"
	if a[Mesh.ARRAY_TEX_UV] != null: s += "u"
	if a[Mesh.ARRAY_TEX_UV2] != null: s += "U"
	return s

func merge_static_geometry():
	# 核心优化：把上千个各自独立的 MeshInstance3D 按“材质 + 顶点格式”合并成少量多表面网格。
	# 顶点全部烘焙到世界空间，合并后的节点放在原点、单位变换，因此所有依赖
	# 世界坐标或模型矩阵的着色器（湿沥青等）依然正确。
	var instances = []
	gather_meshes(world, instances)

	var buckets = {}
	var consumed = {}
	var kept = 0
	for node in instances:
		var mesh = node.mesh
		if mesh == null: continue
		# 不投影阴影的东西保持原样：边界雾层、灯笼光锥等依赖自身局部坐标，合并会算出错误结果。
		if node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			kept += 1
			continue
		var skinned = false
		for s in mesh.get_surface_count():
			var a = mesh.surface_get_arrays(s)
			if a[Mesh.ARRAY_BONES] != null or a[Mesh.ARRAY_WEIGHTS] != null: skinned = true
		if skinned:
			kept += 1
			continue
		for s in mesh.get_surface_count():
			var m = node.material_override
			if m == null: m = mesh.surface_get_material(s)
			var a = mesh.surface_get_arrays(s)
			var key = ("M%d" % m.get_instance_id()) if m != null else "Mnull"
			key += "_" + attr_sig(a)
			if not buckets.has(key):
				buckets[key] = {"mat": m, "items": []}
			buckets[key]["items"].append([node, s])

	var merged = 0
	var merged_group = group("StaticGeometry")
	for key in buckets:
		var items = buckets[key]["items"]
		var total_v = 0
		var total_i = 0
		for it in items:
			var a = it[0].mesh.surface_get_arrays(it[1])
			var n = a[Mesh.ARRAY_VERTEX].size()
			total_v += n
			total_i += a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] != null else n
		if total_v == 0: continue

		var sample = items[0][0].mesh.surface_get_arrays(items[0][1])
		var has_n = sample[Mesh.ARRAY_NORMAL] != null
		var has_t = sample[Mesh.ARRAY_TANGENT] != null
		var has_c = sample[Mesh.ARRAY_COLOR] != null
		var has_uv = sample[Mesh.ARRAY_TEX_UV] != null
		var has_uv2 = sample[Mesh.ARRAY_TEX_UV2] != null

		var V = PackedVector3Array(); V.resize(total_v)
		var N = PackedVector3Array()
		var T = PackedFloat32Array()
		var C = PackedColorArray()
		var UV = PackedVector2Array()
		var UV2 = PackedVector2Array()
		var I = PackedInt32Array(); I.resize(total_i)
		if has_n: N.resize(total_v)
		if has_t: T.resize(total_v * 4)
		if has_c: C.resize(total_v)
		if has_uv: UV.resize(total_v)
		if has_uv2: UV2.resize(total_v)

		var voff = 0
		var ioff = 0
		for it in items:
			var node = it[0]
			var a = node.mesh.surface_get_arrays(it[1])
			var xf = node.global_transform
			var nx = xf.basis.inverse().transposed()
			var src_v = a[Mesh.ARRAY_VERTEX]
			var n = src_v.size()
			for k in n:
				V[voff + k] = xf * src_v[k]
			if has_n:
				var src_n = a[Mesh.ARRAY_NORMAL]
				for k in n:
					N[voff + k] = (nx * src_n[k]).normalized()
			if has_t:
				var src_t = a[Mesh.ARRAY_TANGENT]
				var q = 0
				while q < src_t.size():
					var tv = (nx * Vector3(src_t[q], src_t[q+1], src_t[q+2])).normalized()
					T[(voff + (q / 4)) * 4] = tv.x
					T[(voff + (q / 4)) * 4 + 1] = tv.y
					T[(voff + (q / 4)) * 4 + 2] = tv.z
					T[(voff + (q / 4)) * 4 + 3] = src_t[q+3]
					q += 4
			if has_c:
				var src_c = a[Mesh.ARRAY_COLOR]
				for k in n: C[voff + k] = src_c[k]
			if has_uv:
				var src_uv = a[Mesh.ARRAY_TEX_UV]
				for k in n: UV[voff + k] = src_uv[k]
			if has_uv2:
				var src_uv2 = a[Mesh.ARRAY_TEX_UV2]
				for k in n: UV2[voff + k] = src_uv2[k]
			var src_i = a[Mesh.ARRAY_INDEX]
			if src_i != null:
				for k in src_i.size():
					I[ioff + k] = src_i[k] + voff
				ioff += src_i.size()
			else:
				for k in n:
					I[ioff + k] = voff + k
				ioff += n
			voff += n

		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = V
		if has_n: arrays[Mesh.ARRAY_NORMAL] = N
		if has_t: arrays[Mesh.ARRAY_TANGENT] = T
		if has_c: arrays[Mesh.ARRAY_COLOR] = C
		if has_uv: arrays[Mesh.ARRAY_TEX_UV] = UV
		if has_uv2: arrays[Mesh.ARRAY_TEX_UV2] = UV2
		arrays[Mesh.ARRAY_INDEX] = I

		var am = ArrayMesh.new()
		am.resource_name = "Merged"
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

		var mi = MeshInstance3D.new()
		mi.mesh = am
		mi.material_override = buckets[key]["mat"]
		var mat_name = "Unnamed"
		if mi.material_override != null and mi.material_override.resource_name != "":
			mat_name = mi.material_override.resource_name
		put(mi, "Merged_" + mat_name, merged_group)
		merged += 1

	# 只回收真正被合并进去的节点；跳过合并的（雾层、光锥）必须留在原地。
	for key in buckets:
		for it in buckets[key]["items"]:
			consumed[it[0].get_instance_id()] = true
	for node in instances:
		if not is_instance_valid(node): continue
		if not consumed.has(node.get_instance_id()): continue
		node.get_parent().remove_child(node)
		node.free()
	print("Merged static geometry: ", merged, " draw batches from ", consumed.size(), " meshes; kept ", kept)
	return merged_group

func _initialize():
	# 场景树根节点要等真正入树之后再动 global_transform，否则全部退化成单位矩阵。
	call_deferred("build")

func build():
	rng.seed=202709
	world=Node3D.new()
	world.name="StillwaterCorner"
	root.add_child(world)
	world.set_script(load("res://scripts/capture.gd"))
	mat("asphalt","303d41",0.27,0.12)
	var asphalt_shader=ShaderMaterial.new()
	asphalt_shader.shader=load("res://shaders/wet_asphalt.gdshader")
	asphalt_shader.resource_name="asphalt"
	mats["asphalt"]=asphalt_shader
	mat("void","263840")
	mat("stone","647073")
	mat("paving","535e60",0.65)
	mat("trim","465257")
	mat("school","677072")
	mat("brick","665854")
	mat("plaster","73736b")
	mat("blue","526267")
	mat("brick_detail","535958")
	mat("roof","303a40",0.68)
	mat("iron","252f33",0.48,0.65)
	mat("glass","223b42",0.16,0.38)
	mat("glow","d5a66a",0.36,0.05,0.7)
	mat("wood","605345")
	mat("brass","aa976a",0.36,0.55)
	mat("sign","2a4145")
	mat("canvas","929081")
	mat("teal","496969")
	mat("rust","78554b")
	mat("paint","afb7ac",0.7)
	mat("soil","333e36")
	mat("grass","46534a")
	mat("bark","514e46")
	mat("foliage","46594f")
	mat("puddle","465c63",0.09,0.55)
	mat("leaf","83745b")
	var ground=group("GroundAndShortCrossroads")
	slab(Vector3(0,-0.32,0),Vector3(200,0.5,200),"void",ground,"Surround")
	slab(Vector3(0,-0.04,0),Vector3(32,0.12,26),"paving",ground,"NeighborhoodGround")
	box(Vector3(0,0.035,0),Vector3(4.6,0.08,30),"asphalt",ground,"NorthSouthStreet")
	box(Vector3(0,0.04,0),Vector3(36,0.08,4.5),"asphalt",ground,"EastWestStreet")
	# Four small raised pavements, all directly facing the central junction.
	for sx in [-1,1]:
		for sz in [-1,1]:
			slab(Vector3(sx*9.2,0.12,sz*7.3),Vector3(13.4,0.24,9.7),"paving",ground,"Pavement")
			for i in range(22):
				box(Vector3(sx*(2.65+i*0.6),0.26,sz*2.51),Vector3(0.57,0.21,0.22),"stone",ground,"Kerbstone")
			for i in range(16):
				box(Vector3(sx*2.55,0.26,sz*(2.7+i*0.6)),Vector3(0.22,0.21,0.57),"stone",ground,"Kerbstone")
	for side in [-1,1]:
		for j in range(7):
			box(Vector3((j-3)*0.55,0.094,side*3.5),Vector3(0.31,0.018,1.25),"paint",ground,"Crosswalk")
		for j in range(6):
			box(Vector3(side*4.05,0.098,(j-2.5)*0.58),Vector3(1.25,0.018,0.31),"paint",ground,"Crosswalk")
		for j in range(3):
			box(Vector3(0,0.09,side*(6.5+j*2.3)),Vector3(0.07,0.016,0.94),"paint",ground,"LaneDash")
	# Roofline kept to the rear; the foreground contains only low structures.
	building("WestApartments",-11,-8.5,5.5,4.5,7.5,"brick",3)
	building("EastApartments",10.2,-9.0,5.4,4.2,7.0,"blue",3)
	var school=refined("School", "school_refined", Vector3(-2,0,-9))
	light(Vector3(-2,2.5,-5.2),1.3,4,school)
	var cafe=refined("CornerCafe", "cafe_refined", Vector3(8.7,0,-3.9))
	light(Vector3(7.4,1.8,-1.9),1.5,4,cafe)
	light(Vector3(10,1.8,-1.9),1.5,4,cafe)
	var restaurant=building("NeighborhoodDiner",-10.8,-3.4,5.4,3.4,3.55,"brick",0)
	shop(restaurant,-10.8,-1.65,5.4,"LATE PLATE","rust")
	var store=building("ConvenienceStore",-11,5.0,4.8,3.2,3.05,"blue",0)
	shop(store,-11,6.64,4.8,"CORNER  24","teal")
	# Metro is a recessed, descending stair mouth with an enclosed dark end.
	var metro=group("MetroEntrance")
	box(Vector3(-4.8,-1.58,6.6),Vector3(2.5,0.16,4.5),"iron",metro,"StairMouth")
	for i in range(9):
		box(Vector3(-4.8,0.20-i*0.19,8.5-i*0.38),Vector3(2.24,0.12,0.39),"stone",metro,"DescendingTread")
	for side in [-1,1]:
		box(Vector3(-4.8+side*1.3,-0.21,6.65),Vector3(0.23,2.6,4.5),"stone",metro,"StairCheek")
		for i in range(7):
			beam(Vector3(-4.8+side*1.28,1.1,4.8+i*0.58),Vector3(-4.8+side*1.28,1.55,4.8+i*0.58),0.032,"iron",metro)
		beam(Vector3(-4.8+side*1.28,1.55,4.6),Vector3(-4.8+side*1.28,1.55,8.8),0.045,"iron",metro)
		beam(Vector3(-4.8+side*1.35,0.3,7.8),Vector3(-4.8+side*1.35,2.8,7.8),0.07,"iron",metro)
	box(Vector3(-4.8,-0.3,4.55),Vector3(2.7,2.5,0.3),"sign",metro,"TunnelEnd")
	box(Vector3(-4.8,-0.45,4.76),Vector3(2.2,2.1,0.1),"iron",metro,"TunnelShadow")
	box(Vector3(-4.8,1.03,4.8),Vector3(3.1,0.22,1.2),"roof",metro,"MetroRoof")
	box(Vector3(-4.8,2.75,7.8),Vector3(3.1,0.54,0.22),"sign",metro,"MetroSign")
	label3("M  •  METRO",Vector3(-4.8,2.77,7.94),0.36,metro)
	light(Vector3(-4.8,-0.1,6.0),1.7,3.6,metro)
	# A single open park corner, with low planting around a clear footpath.
	var park=group("PocketPark")
	box(Vector3(8,0.29,7.0),Vector3(8.2,0.18,7.5),"grass",park,"Lawn")
	box(Vector3(7.1,0.4,6.8),Vector3(1.6,0.08,7.4),"paving",park,"ParkPath")
	box(Vector3(8.2,0.4,5.2),Vector3(8.0,0.08,1.4),"paving",park,"ParkPath")
	for i in range(16):
		beam(Vector3(4.1+i*0.5,0.3,10.8),Vector3(4.1+i*0.5,1.15,10.8),0.035,"iron",park)
	beam(Vector3(4.1,1.0,10.8),Vector3(11.9,1.0,10.8),0.04,"iron",park)
	for i in range(10):
		orb(Vector3(11.5,0.63,6+i*0.44),Vector3(0.52,0.45,0.5),"foliage",park)
	tree(9.8,8.8,3.5)
	tree(4.9,8.9,2.6)
	tree(12.6,3.9,3.1)
	bench(9.2,6.2)
	bench(5.3,6.2,PI/2)
	box(Vector3(4.55,1.1,3.75),Vector3(1.25,0.65,0.12),"sign",park,"ParkSign")
	beam(Vector3(4.55,0.3,3.75),Vector3(4.55,1.35,3.75),0.06,"wood",park)
	label3("POCKET\nPARK",Vector3(4.55,1.12,3.83),0.22,park)
	for p in [Vector2(-3.1,-3.3),Vector2(3.1,2.9),Vector2(-7.1,8.7),Vector2(11.9,-1.9)]: lamp(p.x,p.y)
	# Cafe tables, chairs, chalkboard and planters.
	for x in [7.2,10.0]:
		cyl(Vector3(x,0.88,-0.9),0.5,0.09,"wood",cafe)
		cyl(Vector3(x,0.57,-0.9),0.055,0.55,"iron",cafe)
		cyl(Vector3(x,0.31,-0.9),0.28,0.07,"iron",cafe)
		for side in [-1,1]:
			cyl(Vector3(x+side*0.7,0.57,-0.9),0.23,0.08,"wood",cafe)
			for dz in [-0.12,0.12]: beam(Vector3(x+side*0.7,0.27,-0.9+dz),Vector3(x+side*0.7,0.57,-0.9+dz),0.027,"iron",cafe)
	var board=box(Vector3(5.6,0.86,-1.2),Vector3(0.6,1.1,0.1),"wood",cafe,"Chalkboard")
	board.rotation.x=-0.12
	box(Vector3(5.6,0.88,-1.11),Vector3(0.48,0.88,0.02),"sign",cafe)
	label3("OPEN\nCOFFEE",Vector3(5.6,0.92,-1.07),0.13,cafe)
	for p in [Vector2(6,-2),Vector2(11.4,-2),Vector2(-8.3,6.4)]:
		cyl(Vector3(p.x,0.5,p.y),0.29,0.5,"stone",null,0.38)
		orb(Vector3(p.x,0.94,p.y),Vector3(0.45,0.48,0.42),"foliage")
	var props=group("StreetDetails")
	for p in [Vector2(-2.9,6.5),Vector2(3.1,-1.7),Vector2(-7.3,-2.7),Vector2(13,0)]:
		cyl(Vector3(p.x,0.54,p.y),0.21,0.65,"iron",props)
		cyl(Vector3(p.x,0.91,p.y),0.25,0.09,"trim",props)
	for p in [Vector2(-2,5.4),Vector2(2,-6),Vector2(6,1.95),Vector2(-7,-1.95)]:
		box(Vector3(p.x,0.094,p.y),Vector3(0.65,0.025,0.42),"iron",props,"Drain")
		for j in range(5): box(Vector3(p.x-0.23+j*0.115,0.112,p.y),Vector3(0.042,0.02,0.34),"stone",props,"DrainSlot")
	# Consume the old random draws to preserve all following asset placement.
	for j in range(16):
		var x=rng.randf_range(-14,14)
		var z=rng.randf_range(-11,11)
		if abs(x)>2.1 and abs(z)>2.0: continue
		rng.randf_range(0.3,0.95)
		rng.randf_range(0.18,0.55)
	for j in range(65):
		var x=rng.randf_range(-13,13)
		var z=rng.randf_range(-10,10)
		var leaf=box(Vector3(x,0.28 if abs(x)>2.5 and abs(z)>2.5 else 0.105,z),Vector3(0.07,0.009,0.16),"leaf",props,"FallenLeaf")
		leaf.rotation.y=rng.randf()*TAU
	setup_atmosphere()
	var camera=Camera3D.new()
	camera.name="FixedIsometricCamera"
	camera.position=Vector3(29,34,43)
	put(camera,"FixedIsometricCamera")
	camera.basis=Basis.looking_at(Vector3(0,1.5,0)-camera.position)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	# 正交 size 就是画面高度（单位）。原来 34 时画面四角还空着 27% 的余量，所以显得很远。
	# 28 是实测出来的甜点：比原来近 21%，而玩家能走到的四个边界角落仍有 11.6% 余量
	# （用 tools/check_framing.gd 量的）。再小到 26 就只剩 4.8%，24 直接出画。
	camera.size=28
	camera.current=true
	camera.far=200
	# 必须在打包前合并：这一步决定了最终场景是几十次绘制还是上千次。
	build_collision_shape()
	merge_static_geometry()
	var packed=PackedScene.new()
	var result=packed.pack(world)
	if result == OK: result=ResourceSaver.save(packed,"res://scenes/neighborhood.tscn")
	print("Scene saved: ",result,"; nodes: ",serial)
	quit(result)

func setup_atmosphere():
	var env=Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("17232b")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("7a9ca9")
	env.ambient_light_energy=0.42
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	env.fog_enabled=true
	env.fog_light_color=Color("718b94")
	env.fog_light_energy=0.36
	env.fog_density=0.0007
	env.volumetric_fog_enabled=true
	env.volumetric_fog_density=0.002
	env.volumetric_fog_albedo=Color("a3b6c1")
	env.volumetric_fog_length=100
	env.volumetric_fog_detail_spread=1.4
	env.volumetric_fog_ambient_inject=0.25
	env.volumetric_fog_anisotropy=0.35
	env.ssao_enabled=true
	env.ssao_radius=1.4
	env.ssao_intensity=1.3
	# SSIL 是 Godot 里最贵的后处理（逐像素光线步进），在这种大色块的风格化画面上
	# 只贡献极淡的间接光，肉眼几乎分辨不出来 —— 关掉。
	env.ssil_enabled=false
	env.ssr_enabled=false
	env.glow_enabled=true
	env.glow_intensity=0.65
	env.glow_hdr_threshold=1.6
	env.fog_sky_affect=0
	var we=WorldEnvironment.new()
	we.environment=env
	put(we,"UnifiedEnvironment")
	var moon=DirectionalLight3D.new()
	moon.rotation_degrees=Vector3(-52,-32,0)
	moon.light_color=Color("b1c7d3")
	moon.light_energy=0.95
	moon.light_volumetric_fog_energy=0.08
	moon.shadow_enabled=true
	moon.directional_shadow_max_distance=80
	# 固定正交相机下所有物体距离大致相同，4 级级联阴影没有精度收益，却要跑 4 遍
	# 阴影贴图渲染。改成单张正交阴影图：pass 数直接除以 4，清晰度反而更均匀。
	moon.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	put(moon,"Moonlight")
	var rim=DirectionalLight3D.new()
	rim.rotation_degrees=Vector3(-27,145,0)
	rim.light_color=Color("7aa6b3")
	rim.light_energy=0.30
	rim.light_volumetric_fog_energy=0.0
	put(rim,"SoftRim")
	var fogmat=ShaderMaterial.new()
	fogmat.shader=load("res://shaders/edge_mist.gdshader")
	var fog=group("BoundaryMist")
	for i in range(5):
		var n=MeshInstance3D.new()
		var plane=PlaneMesh.new()
		plane.size=Vector2(200,200)
		n.mesh=plane
		n.material_override=fogmat
		n.position=Vector3(0,0.45+i*0.44,0)
		n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		put(n,"DriftingMistLayer",fog)
	dust_cluster(Vector3(0,2.7,0),Vector3(13,2.4,10),140)
	dust_cluster(Vector3(9,1.8,-1.0),Vector3(2.2,1.3,0.85),100)
