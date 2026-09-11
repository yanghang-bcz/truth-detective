extends Node3D

# Production preview helper only; normal runs never move the fixed camera.
func _ready():
	if "--capture" not in OS.get_cmdline_user_args() and not FileAccess.file_exists("res://previews/.capture_once"):
		return
	var camera=get_viewport().get_camera_3d()
	for frame in range(120): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result=get_viewport().get_texture().get_image().save_png("res://previews/neighborhood.png")
	print("Overview capture: ",result)
	for item in [
		["cafe_detail",Vector3(8.7,1.9,-2.1),Vector3(-1.7,4.5,6),7.8],
		["school_detail",Vector3(-2,2.8,-6.8),Vector3(6,6,13),12.5],
		["lamplight_detail",Vector3(3.6,1.9,2.9),Vector3(-4,2.7,2),5.6]
	]:
		camera.position=item[1]+item[2]
		camera.look_at(item[1])
		camera.size=item[3]
		for frame in range(60): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var err=get_viewport().get_texture().get_image().save_png("res://previews/"+item[0]+".png")
		print(item[0]," capture: ",err)
		if err!=OK:result=err
	if FileAccess.file_exists("res://previews/.capture_once"):
		DirAccess.remove_absolute("res://previews/.capture_once")
	get_tree().quit(result)
