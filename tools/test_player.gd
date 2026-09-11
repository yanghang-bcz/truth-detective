extends SceneTree
var player: CharacterBody3D
var results: Array[String] = []
var failed := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	results.append(("PASS " if ok else "FAIL ") + label)
	print(results[-1])
	if not ok: failed = true
func frames(n: int) -> void:
	for i in range(n): await physics_frame
func direction(world_dir: Vector3) -> Vector2:
	var cam := root.get_camera_3d()
	var r := cam.global_basis.x; r.y = 0; r = r.normalized()
	var b := cam.global_basis.z; b.y = 0; b = b.normalized()
	return Vector2(world_dir.dot(r), world_dir.dot(b))
func reset(pos: Vector3) -> void:
	player.test_input = Vector2.ZERO; player.velocity = Vector3.ZERO; player.global_position = pos
	await frames(45)
func run() -> void:
	var scene = load("res://scenes/playable_neighborhood.tscn").instantiate()
	root.add_child(scene)
	player = scene.get_node("Detective")
	player.automated = true
	await frames(60)
	check(player.is_on_floor() and abs(player.position.y-.08)<.06, "Spawn grounded on street: " + str(player.position))
	check(player.animation.has_animation("Idle") and player.animation.has_animation("Walk") and player.animation.has_animation("Run"), "All three animation clips")
	for d in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
		await reset(Vector3(0,.15,0))
		var start := player.position
		player.test_input = d
		await frames(40)
		check(player.position.distance_to(start) > .8 and player.is_on_floor() and player.state=="Walk", "Screen movement " +str(d))
	await reset(Vector3(0,.15,0))
	player.test_input=Vector2.RIGHT
	await frames(30)
	var walk_dist := player.position.length()
	await reset(Vector3(0,.15,0))
	player.test_run=true;player.test_input=Vector2.RIGHT
	await frames(30)
	check(player.position.length()>walk_dist*1.4 and player.state=="Run", "Run faster than walk")
	player.test_run=false
	await reset(Vector3(0,.15,4.5))
	player.test_input=direction(Vector3.RIGHT)
	await frames(140)
	check(player.position.x>3.3 and player.is_on_floor(), "Step onto kerb and pavement " +str(player.position))
	await reset(Vector3(-10.8,.35,-.3))
	player.test_input=direction(Vector3.FORWARD)
	await frames(150)
	check(player.position.z> -1.9 and player.position.z<-.7, "Diner wall blocks passage " +str(player.position))
	await reset(Vector3(14,.2,0))
	player.test_input=direction(Vector3.RIGHT)
	await frames(120)
	check(player.position.x<15.6 and player.position.x>15, "Map boundary collision")
	player.test_input=Vector2.ZERO
	await frames(30)
	check(player.state=="Idle", "Returns to Idle")
	player.position.y=-5
	await frames(2)
	check(player.position.distance_to(player.spawn_position)<.2, "Fall recovery")
	FileAccess.open("res://previews/player-tests.txt",FileAccess.WRITE).store_string("\n".join(results))
	quit(1 if failed else 0)
