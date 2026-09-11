extends Node3D
## Opt-in developer capture. Never changes the camera during normal play.
func _ready() -> void:
	if not FileAccess.file_exists("res://.capture_player"): return
	DirAccess.remove_absolute("res://.capture_player")
	await get_tree().process_frame
	var player = get_node("Detective")
	player.automated = true
	var camera = get_viewport().get_camera_3d()
	await get_tree().create_timer(3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://previews/playable_neighborhood.png")
	camera.position = player.position + Vector3(3.2,2.2,4.5)
	camera.look_at(player.position + Vector3(0,.78,0))
	camera.size = 3.0
	await get_tree().create_timer(1).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://previews/detective_closeup.png")
	for clip in ["Walk", "Run"]:
		player.animation.play(clip)
		player.animation.seek(0.2, true)
		player.animation.pause()
		await get_tree().create_timer(0.15).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://previews/detective_" + clip.to_lower() + ".png")
	print("CAPTURED_PLAYER")
	get_tree().quit()
