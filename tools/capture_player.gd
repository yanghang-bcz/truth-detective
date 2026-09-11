extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene = load("res://scenes/playable_neighborhood.tscn").instantiate()
	root.add_child(scene)
	var player = scene.get_node("Detective")
	player.automated = true
	var camera = root.get_camera_3d()
	root.size = Vector2i(1600,1000)
	await create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/playable_neighborhood.png")
	camera.position = player.position + Vector3(3.2,2.2,4.5)
	camera.look_at(player.position+Vector3(0,.78,0))
	camera.size = 3.0
	await create_timer(1).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://previews/detective_closeup.png")
	print("CAPTURED_PLAYER")
	quit()
