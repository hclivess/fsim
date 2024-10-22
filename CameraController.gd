extends Camera3D

# Flight characteristics
var base_speed = 50.0
var min_speed = 20.0
var max_speed = 150.0
var stall_speed = 25.0
var pitch_speed_influence = 20.0
var energy_conservation = 0.7
var throttle = 0.5
var current_speed = 0.0
var lift_coefficient = 12.0
var drag_coefficient = 0.03
var turn_sensitivity = 2.0
var pitch_sensitivity = 1.5
var roll_sensitivity = 2.0

# Physics values
var velocity = Vector3.ZERO
var angular_velocity = Vector3.ZERO
var gravity = Vector3(0, -9.81, 0)
var mass = 1000.0
var inertia = 0.8
var energy_retention = 0.98
var previous_altitude = 0.0

# Flight state
var is_stalling = false
var ground_contact = false
var angle_of_attack = 0.0
var stall_angle = 15.0
var damage = 0.0
var max_damage = 100.0
var spawn_height = 500.0
var can_control = true

# HUD
@onready var hud_scene = preload("res://FlightHUD.tscn")
var hud: Control

func _ready():
	# Add HUD
	if hud_scene:
		hud = hud_scene.instantiate()
		if hud:
			add_child(hud)
	
	# Initial spawn
	respawn()
	
	# Set mouse mode
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func respawn():
	# Find a safe spawning position
	var spawn_pos = Vector3(
		position.x,
		spawn_height,
		position.z
	)
	
	position = spawn_pos
	rotation = Vector3.ZERO
	velocity = -transform.basis.z * (min_speed + 10.0)  # Initial forward velocity
	angular_velocity = Vector3.ZERO
	damage = 0
	current_speed = min_speed + 10.0
	throttle = 0.5
	can_control = false
	previous_altitude = spawn_height
	
	# Enable controls after a delay
	await get_tree().create_timer(2.0).timeout
	can_control = true

func _process(delta):
	if can_control:
		handle_input(delta)
	apply_physics(delta)
	handle_collision()
	update_flight_state()

func handle_input(delta):
	# Throttle control with smoother changes
	if Input.is_key_pressed(KEY_SHIFT):
		throttle = min(throttle + delta * 0.5, 1.0)  # Slower throttle increase
	elif Input.is_key_pressed(KEY_CTRL):
		throttle = max(throttle - delta * 0.5, 0.0)  # Slower throttle decrease
	
	# Flight controls - Inverted pitch for simulator style
	var pitch_input = Input.get_axis("ui_up", "ui_down")  # Inverted: up is down, down is up
	var roll_input = Input.get_axis("ui_left", "ui_right")
	var yaw_input = 0.0
	if Input.is_key_pressed(KEY_Q): yaw_input -= 1.0
	if Input.is_key_pressed(KEY_E): yaw_input += 1.0
	
	# Apply control forces with inertia
	var target_angular_velocity = Vector3(
		pitch_input * pitch_sensitivity,
		yaw_input * turn_sensitivity,
		-roll_input * roll_sensitivity
	)
	
	angular_velocity = angular_velocity.lerp(target_angular_velocity, 1.0 - inertia)
	
	# Apply rotation with inertia
	rotate_object_local(Vector3.RIGHT, angular_velocity.x * delta)
	rotate_object_local(Vector3.UP, angular_velocity.y * delta)
	rotate_object_local(Vector3.FORWARD, angular_velocity.z * delta)

func apply_physics(delta):
	# Store previous altitude for energy calculation
	var altitude_change = position.y - previous_altitude
	previous_altitude = position.y
	
	# Calculate angle of attack
	if velocity.length_squared() > 0.1:
		angle_of_attack = abs(rad_to_deg(transform.basis.z.angle_to(velocity.normalized())))
	else:
		angle_of_attack = 0.0
	
	# Get current pitch angle in degrees (-90 to 90)
	var pitch_angle = rad_to_deg(rotation.x)
	
	# Calculate speed changes based on pitch and altitude
	var target_speed = base_speed
	
	# FIXED: Diving (negative pitch) increases speed, climbing (positive pitch) decreases it
	if pitch_angle < 0:  # Diving
		target_speed -= pitch_angle * pitch_speed_influence  # Negative pitch becomes positive influence
	else:  # Climbing
		target_speed -= pitch_angle * pitch_speed_influence  # Positive pitch becomes negative influence
	
	# Convert altitude changes to speed (conservation of energy)
	if altitude_change < 0:  # Losing altitude increases speed
		target_speed += abs(altitude_change) * energy_conservation
	else:  # Gaining altitude decreases speed
		target_speed -= altitude_change * energy_conservation
	
	# Apply throttle influence
	target_speed *= (0.5 + throttle)  # Throttle now modifies the target speed
	
	# Clamp speed to realistic limits
	target_speed = clamp(target_speed, min_speed, max_speed)
	
	# Smoothly adjust current_speed towards target_speed
	current_speed = move_toward(current_speed, target_speed, 10.0 * delta)
	
	# Check for stall condition
	is_stalling = angle_of_attack > stall_angle or current_speed < stall_speed
	
	# Calculate lift and drag
	var speed_factor = current_speed / max_speed
	var lift_force = Vector3.ZERO
	var drag_force = Vector3.ZERO
	
	if not is_stalling:
		lift_force = transform.basis.y * lift_coefficient * speed_factor * speed_factor
		drag_force = -velocity.normalized() * drag_coefficient * speed_factor * speed_factor
	else:
		# Reduced lift and increased drag during stall
		lift_force = transform.basis.y * lift_coefficient * 0.2 * speed_factor
		drag_force = -velocity.normalized() * drag_coefficient * 3.0 * speed_factor
		# Add stall turbulence
		if randf() < 0.1:
			angular_velocity += Vector3(
				randf_range(-1, 1),
				randf_range(-1, 1),
				randf_range(-1, 1)
			) * 0.5
	
	# Apply forces
	var thrust = -transform.basis.z * current_speed * throttle
	var total_force = thrust + lift_force + drag_force + gravity
	
	# Update velocity with inertia
	velocity = velocity.lerp(-transform.basis.z * current_speed, 5.0 * delta)
	velocity += total_force * delta
	
	# Move the aircraft
	position += velocity * delta

func handle_collision():
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.new()
	query.from = position
	query.to = position + Vector3.DOWN * 10.0
	
	var result = space_state.intersect_ray(query)
	if result:
		ground_contact = true
		var impact_speed = velocity.length()
		
		if impact_speed > 10.0:
			damage += impact_speed * 0.5
			if damage >= max_damage:
				crash()
				return
		
		# Bounce off ground with energy loss
		position.y = result["position"].y + 10.0
		velocity.y = abs(velocity.y) * 0.3
	else:
		ground_contact = false

func crash():
	print("CRASHED! Respawning...")
	respawn()

func update_flight_state():
	# Keep minimum height for safety
	if position.y < 10:
		position.y = 10
		velocity.y = 0
		ground_contact = true
	
	# Update HUD
	if hud:
		var hud_data = {
			"speed": current_speed,
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
		# Inverted Y axis for flight sim feel
		rotate_object_local(Vector3.RIGHT, event.relative.y * 0.001)
		rotate_object_local(Vector3.UP, -event.relative.x * 0.001)

func _notification(what):
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _exit_tree():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
