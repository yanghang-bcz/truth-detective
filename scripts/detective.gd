extends CharacterBody3D
## +Z visual forward. Movement follows the fixed camera's horizontal axes.
@export var walk_speed: float = 2.0
@export var run_speed: float = 3.8
@export var acceleration: float = 14.0
@export var step_height: float = 0.34
@onready var visual: Node3D = $Visual
@onready var animation: AnimationPlayer = find_child("AnimationPlayer", true, false)
var state: String = "Idle"
var spawn_position: Vector3
var test_input: Vector2 = Vector2.ZERO
var test_run: bool = false
var automated: bool = false
var gravity: float = 18.0
var step_hold: float = 0.0

func _ready() -> void:
	spawn_position = global_position
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(48.0)
	for action in ["detective_left", "detective_right", "detective_up", "detective_down", "detective_run"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	var keys = {"detective_left": [KEY_A, KEY_LEFT], "detective_right": [KEY_D, KEY_RIGHT], "detective_up": [KEY_W, KEY_UP], "detective_down": [KEY_S, KEY_DOWN], "detective_run": [KEY_SHIFT]}
	for action in keys:
		for code in keys[action]:
			var event = InputEventKey.new()
			event.physical_keycode = code
			if not InputMap.action_has_event(action, event): InputMap.action_add_event(action, event)
	if animation:
		for clip in animation.get_animation_list():
			animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		animation.play("Idle")

func _physics_process(delta: float) -> void:
	var input := test_input if automated else Input.get_vector("detective_left", "detective_right", "detective_up", "detective_down")
	var running := test_run if automated else Input.is_action_pressed("detective_run")
	var camera := get_viewport().get_camera_3d()
	var right := Vector3.RIGHT
	var back := Vector3.BACK
	if camera:
		right = camera.global_basis.x
		back = camera.global_basis.z
		right.y = 0.0
		back.y = 0.0
		right = right.normalized()
		back = back.normalized()
	var direction := (right * input.x + back * input.y).limit_length(1.0)
	var speed := run_speed if running else walk_speed
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	step_hold = maxf(0.0, step_hold - delta)
	floor_snap_length = 0.0 if step_hold > 0.0 else 0.4
	if step_hold > 0.0: velocity.y = 0.0
	elif is_on_floor(): velocity.y = -0.5
	else: velocity.y -= gravity * delta
	var motion := Vector3(velocity.x, 0, velocity.z) * delta
	if is_on_floor() and motion.length() > 0.001:
		_try_step(motion)
	var before := global_position
	move_and_slide()
	var actual_speed := Vector2(global_position.x-before.x, global_position.z-before.z).length() / delta
	if direction.length_squared() > 0.01:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(direction.x, direction.z), 1.0-exp(-12.0*delta))
	var next := "Idle" if actual_speed < 0.12 else ("Run" if running else "Walk")
	if next != state:
		state = next
		if animation: animation.play(state, 0.16)
	if global_position.y < -4.0:
		global_position = spawn_position
		velocity = Vector3.ZERO

func _try_step(motion: Vector3) -> void:
	if not test_move(global_transform, motion): return
	if test_move(global_transform, Vector3.UP * step_height): return
	var raised := global_transform
	raised.origin.y += step_height
	if test_move(raised, motion): return
	raised.origin += motion
	var ahead := global_position + motion.normalized() * 0.30
	var query := PhysicsRayQueryParameters3D.create(ahead + Vector3.UP * step_height, ahead + Vector3.DOWN * 0.05, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.normal.dot(Vector3.UP) >= cos(floor_max_angle):
		var rise: float = hit.position.y - global_position.y
		if rise > 0.01 and rise <= step_height:
			global_position.y += rise + 0.004
			step_hold = 0.16
			floor_snap_length = 0.0
			velocity.y = 0.0
