extends Camera3D

# Flight characteristics
var base_speed = 50.0
var max_speed = 150.0
var throttle = 0.7
var current_speed = 0.0
var lift_coefficient = 2.0
var drag_coefficient = 0.03
var turn_sensitivity = 2.0
var pitch_sensitivity = 1.5
var roll_sensitivity = 2.0

# Physics values
var velocity = Vector3.ZERO
var angular_velocity = Vector3.ZERO
var gravity_strength = 9.81
var mass = 1000.0
var inertia = 0.9
var previous_altitude = 0.0

# Flight state
var is_stalling = false
var ground_contact = false
var angle_of_attack = 0.0
var stall_angle = 25.0
var stall_speed = 30.0
var damage = 0.0
var max_damage = 100.0
var spawn_height = 1000.0
var can_control = true

# HUD
@onready var hud_scene = preload("res://FlightHUD.tscn")
var hud: Control

func _ready():
	if hud_scene:
		hud = hud_scene.instantiate()
		if hud:
			add_child(hud)
	throttle = 0.7
	respawn()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func respawn():
	var spawn_pos = Vector3(
		position.x,
		spawn_height,
		position.z
	)
	
	position = spawn_pos
	rotation = Vector3.ZERO
	velocity = -transform.basis.z * 45.0
	angular_velocity = Vector3.ZERO
	damage = 0.0
	current_speed = 45.0
	throttle = 0.7
	can_control = false
	previous_altitude = spawn_height
	
	await get_tree().create_timer(2.0).timeout
	can_control = true

func _process(delta):
	if can_control:
		handle_input(delta)
	apply_physics(delta)
	handle_collision()
	update_flight_state()

func handle_input(delta):
	# Throttle control
	if Input.is_key_pressed(KEY_SHIFT):
		throttle = min(throttle + delta * 0.5, 1.0)
	elif Input.is_key_pressed(KEY_CTRL):
		throttle = max(throttle - delta * 0.5, 0.0)
	
	# Flight controls
	var pitch_input = Input.get_axis("ui_up", "ui_down")
	var roll_input = Input.get_axis("ui_left", "ui_right")
	var yaw_input = 0.0
	if Input.is_key_pressed(KEY_Q): yaw_input -= 1.0
	if Input.is_key_pressed(KEY_E): yaw_input += 1.0
	
	var speed = velocity.length()
	var control_effectiveness = clamp(speed / 30.0, 0.3, 1.0)
	
	var target_angular_velocity = Vector3(
		pitch_input * pitch_sensitivity * control_effectiveness,
		yaw_input * turn_sensitivity * control_effectiveness,
		roll_input * roll_sensitivity * control_effectiveness
	)
	
	angular_velocity = angular_velocity.lerp(target_angular_velocity, delta * (1.0 - inertia))
	
	rotate_object_local(Vector3.RIGHT, angular_velocity.x * delta)
	rotate_object_local(Vector3.UP, angular_velocity.y * delta)
	rotate_object_local(Vector3.FORWARD, angular_velocity.z * delta)

func apply_physics(delta):
	var up = transform.basis.y
	var forward = -transform.basis.z
	
	# Calculate current speed and angle of attack
	var speed = velocity.length()
	if speed > 0.1:
		var velocity_normal = velocity.normalized()
		angle_of_attack = rad_to_deg(acos(forward.dot(velocity_normal)))
		angle_of_attack = min(angle_of_attack, 90.0)
	else:
		angle_of_attack = 0.0

	# Basic forces
	var gravity = Vector3(0, -gravity_strength, 0) * mass
	
	# Engine thrust
	var max_thrust = 25000.0
	var thrust = forward * max_thrust * throttle
	
	# Air density (simplified)
	var air_density = 1.0
	
	# Calculate lift coefficient
	var effective_lift_coefficient = lift_coefficient
	if angle_of_attack > stall_angle:
		var stall_factor = (angle_of_attack - stall_angle) / (90.0 - stall_angle)
		effective_lift_coefficient *= max(0.4, 1.0 - stall_factor)
	
	# Calculate lift force
	var lift = Vector3.ZERO
	if speed > 0:
		var lift_force = 0.5 * air_density * speed * speed * effective_lift_coefficient
		lift = up * lift_force
	
	# Calculate drag
	var drag = Vector3.ZERO
	if speed > 0:
		var drag_force = 0.5 * air_density * speed * speed * drag_coefficient
		var induced_drag_coefficient = 0.03 * angle_of_attack / 90.0
		var induced_drag = 0.5 * air_density * speed * speed * induced_drag_coefficient
		drag = -velocity.normalized() * (drag_force + induced_drag)
	
	# Sum forces
	var total_force = gravity + thrust + lift + drag
	
	# Apply forces
	var acceleration = total_force / mass
	velocity += acceleration * delta
	
	# Speed limit
	if speed > max_speed:
		velocity = velocity.normalized() * max_speed
	
	# Update position
	position += velocity * delta
	
	# Update stall state
	is_stalling = (angle_of_attack > stall_angle and speed < stall_speed)
	
	# Add stall effects
	if is_stalling:
		if randf() < 0.03:
			angular_velocity += Vector3(
				randf_range(-0.1, 0.1),
				randf_range(-0.1, 0.1),
				randf_range(-0.2, 0.2)
			) * 0.5

func handle_collision():
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.new()
	query.from = position
	query.to = position + Vector3.DOWN * 2.0
	query.collision_mask = 1
	
	var result = space_state.intersect_ray(query)
	if result:
		ground_contact = true
		var impact_speed = -velocity.y
		var landing_angle = abs(rad_to_deg(transform.basis.y.angle_to(Vector3.UP)))
		
		if impact_speed > 5.0 or landing_angle > 45.0:
			var speed_damage = maxf(0, impact_speed - 5.0) * 2.0
			var angle_damage = maxf(0, landing_angle - 45.0)
			damage += speed_damage + angle_damage
			
			if damage >= max_damage:
				crash()
				return
			
			position.y = result["position"].y + 0.5
			velocity.y = abs(velocity.y) * 0.3
			
			if impact_speed > 8.0:
				angular_velocity += Vector3(
					randf_range(-1, 1),
					randf_range(-1, 1),
					randf_range(-1, 1)
				) * (impact_speed * 0.1)
		else:
			position.y = result["position"].y + 0.5
			velocity.y *= 0.8
	else:
		ground_contact = false

func crash():
	print("CRASHED! Damage: ", damage)
	respawn()

func update_flight_state():
	if hud:
		var hud_data = {
			"speed": velocity.length(),
			"altitude": position.y,
			"throttle": throttle,
			"stalling": is_stalling,
			"damage": damage,
			"pitch": rotation.x,
			"roll": rotation.z,
			"heading": rotation.y,
			"angle_of_attack": angle_of_attack
		}
		hud.update_hud(hud_data)

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	if not can_control:
		return
		
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_object_local(Vector3.RIGHT, event.relative.y * 0.001)
		rotate_object_local(Vector3.UP, -event.relative.x * 0.001)

func _notification(what):
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _exit_tree():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
