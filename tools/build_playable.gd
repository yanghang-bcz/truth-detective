extends SceneTree
var world: Node3D
func _initialize() -> void:
	call_deferred("build")
func solid(label: String, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = label
	world.add_child(body)
	body.owner = world
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	shape.owner = world
func build() -> void:
	world = load("res://scenes/neighborhood.tscn").instantiate()
	root.add_child(world)
	world.set_script(load("res://scripts/preview_capture.gd"))
	var body := StaticBody3D.new()
	body.name = "NeighborhoodCollision"
	world.add_child(body)
	body.owner = world
	var shape := CollisionShape3D.new()
	# 碰撞几何体由 tools/build_scene.gd 在合并静态网格之前烘焙，已经剔除掉
	# 玩家够不到的装饰构件（招牌字、窗棂、遮阳篷…），比从渲染网格现算小一个数量级。
	var concave: ConcavePolygonShape3D = load("res://scenes/neighborhood_collision.res")
	if concave == null:
		push_error("找不到 scenes/neighborhood_collision.res，请先运行 tools/build_scene.gd")
		concave = ConcavePolygonShape3D.new()
	shape.shape = concave
	body.add_child(shape)
	shape.owner = world
	for side in [-1,1]:
		solid("BoundaryX"+str(side), Vector3(side*15.8,1,0),Vector3(.3,6,26))
		solid("BoundaryZ"+str(side), Vector3(0,1,side*12.5),Vector3(32,6,.3))
	var player := CharacterBody3D.new()
	player.name = "Detective"
	player.set_script(load("res://scripts/detective.gd"))
	var visual := Node3D.new()
	visual.name = "Visual"
	player.add_child(visual)
	visual.owner = player
	var model: Node3D = load("res://assets/characters/detective.glb").instantiate()
	visual.add_child(model)
	model.owner = player
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = .23
	capsule.height = 1.5
	collision.shape = capsule
	collision.position.y = .75
	player.add_child(collision)
	collision.owner = player
	var p := PackedScene.new()
	p.pack(player)
	ResourceSaver.save(p,"res://scenes/detective.tscn")
	player.free()
	player = load("res://scenes/detective.tscn").instantiate()
	player.position = Vector3(0, .15, 2)
	world.add_child(player)
	player.owner = world
	# 地铁口的案件触发区。放在可玩层而不是 build_scene.gd 里，是为了让基础街区
	# （neighborhood.tscn）保持纯几何：玩法对象只在 playable 场景里出现。
	var trigger := Area3D.new()
	trigger.name = "MetroEntranceTrigger"
	trigger.set_script(load("res://scripts/case_trigger.gd"))
	trigger.position = Vector3(-4.8, 0.9, 9.7)
	trigger.collision_layer = 0
	trigger.collision_mask = 1
	trigger.monitorable = false
	var trigger_shape := CollisionShape3D.new()
	var trigger_box := BoxShape3D.new()
	trigger_box.size = Vector3(3.6, 2.6, 2.6)
	trigger_shape.shape = trigger_box
	trigger.add_child(trigger_shape)
	trigger_shape.owner = world
	world.add_child(trigger)
	trigger.owner = world
	var packed := PackedScene.new()
	packed.pack(world)
	ResourceSaver.save(packed,"res://scenes/playable_neighborhood.tscn")
	print("Built playable street; collision triangles: ", concave.get_faces().size()/3)
	quit()
