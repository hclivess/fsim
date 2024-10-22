extends Node3D

const CHUNK_SIZE = 4096
const VERTEX_SPACING = 64
const HEIGHT_SCALE = 2400.0
const MAX_CHUNKS = 36
const UPDATE_FREQUENCY = 0.2

var noise = FastNoiseLite.new()
var chunks = {}
var camera: Camera3D
var update_timer = 0.0
var current_chunk = Vector2.ZERO
var base_material: StandardMaterial3D
var ground_texture: NoiseTexture2D

func _ready():
	camera = get_tree().get_root().find_child("Camera3D", true, false)
	create_terrain_texture()
	setup_noise()
	setup_environment()
	create_base_material()
	_update_chunks()

func create_terrain_texture():
	var texture_noise = FastNoiseLite.new()
	texture_noise.seed = randi()
	texture_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	texture_noise.frequency = 0.05
	texture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	texture_noise.fractal_octaves = 4
	
	ground_texture = NoiseTexture2D.new()
	ground_texture.width = 1024
	ground_texture.height = 1024
	ground_texture.seamless = true
	ground_texture.noise = texture_noise

func setup_noise():
	noise.seed = 12345
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.00015
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 3.0
	noise.fractal_gain = 0.7

func setup_environment():
	var light = DirectionalLight3D.new()
	add_child(light)
	light.light_energy = 2.0
	light.rotation_degrees = Vector3(-45, 45, 0)
	
	var env = Environment.new()
	var sky = Sky.new()
	var sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.4, 0.6, 1.0)
	sky_material.sky_horizon_color = Color(0.8, 0.9, 1.0)
	sky.sky_material = sky_material
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.85, 0.95)
	env.fog_density = 0.0005
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.25
	
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

func create_base_material():
	base_material = StandardMaterial3D.new()
	base_material.uv1_scale = Vector3(50.0, 50.0, 50.0)
	base_material.uv1_triplanar = true
	base_material.albedo_color = Color(0.25, 0.23, 0.20)
	base_material.albedo_texture = ground_texture
	base_material.roughness = 0.95
	base_material.metallic = 0.1
	base_material.vertex_color_use_as_albedo = true
	base_material.vertex_color_is_srgb = true
	base_material.detail_enabled = true
	base_material.detail_mask = ground_texture
	base_material.detail_blend_mode = StandardMaterial3D.BLEND_MODE_MUL
	base_material.detail_uv_layer = 1
	base_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX

func get_height_at(world_x: float, world_z: float) -> float:
	var h = noise.get_noise_2d(world_x, world_z)
	h = (h + 1.0) * 0.5
	h = pow(h, 1.5)
	return h * HEIGHT_SCALE

func _process(delta):
	if !camera:
		return
	
	update_timer += delta
	if update_timer < UPDATE_FREQUENCY:
		return
	
	update_timer = 0.0
	var cam_pos = camera.global_position
	var new_chunk = Vector2(floor(cam_pos.x / CHUNK_SIZE), floor(cam_pos.z / CHUNK_SIZE))
	
	if new_chunk != current_chunk:
		current_chunk = new_chunk
		_update_chunks()

func _update_chunks():
	var keep_chunks = {}
	var forward = -camera.global_transform.basis.z
	var view_direction = Vector2(forward.x, forward.z).normalized()
	
	var base_radius = 4
	var height_factor = clamp(sqrt(camera.position.y) / 50.0, 0, 8)
	var view_radius = ceili(base_radius + height_factor)
	
	var cam_script = camera as Node
	var speed_factor = 0.0
	if cam_script and cam_script.has_method("get"):
		var speed = cam_script.get("velocity").length()
		speed_factor = clamp(speed / 50.0, 0, 3)
	
	var look_ahead = view_direction * (2 + speed_factor)
	var center_chunk = current_chunk + Vector2(look_ahead.x, look_ahead.y).round()
	
	for z in range(-view_radius - 2, view_radius + 3):
		for x in range(-view_radius - 2, view_radius + 3):
			var check_pos = center_chunk + Vector2(x, z)
			var distance = check_pos.distance_to(current_chunk)
			
			if distance <= view_radius + 2.0:
				keep_chunks[check_pos] = true
				if not chunks.has(check_pos):
					call_deferred("_create_chunk", check_pos)
	
	var to_remove = []
	for pos in chunks.keys():
		if not keep_chunks.has(pos):
			to_remove.append(pos)
	
	to_remove.sort_custom(func(a, b):
		var dist_a = a.distance_to(current_chunk)
		var dist_b = b.distance_to(current_chunk)
		return dist_a > dist_b
	)
	
	for pos in to_remove:
		chunks[pos].queue_free()
		chunks.erase(pos)

func _create_chunk(pos: Vector2):
	if chunks.has(pos):
		return
		
	var chunk = Node3D.new()
	chunk.position = Vector3(pos.x * CHUNK_SIZE, 0, pos.y * CHUNK_SIZE)
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for z in range(0, CHUNK_SIZE + VERTEX_SPACING, VERTEX_SPACING):
		for x in range(0, CHUNK_SIZE + VERTEX_SPACING, VERTEX_SPACING):
			if x > CHUNK_SIZE or z > CHUNK_SIZE:
				continue
				
			var world_x = pos.x * CHUNK_SIZE + x
			var world_z = pos.y * CHUNK_SIZE + z
			
			var v1 = Vector3(x, get_height_at(world_x, world_z), z)
			var v2 = Vector3(x + VERTEX_SPACING, get_height_at(world_x + VERTEX_SPACING, world_z), z)
			var v3 = Vector3(x, get_height_at(world_x, world_z + VERTEX_SPACING), z + VERTEX_SPACING)
			var v4 = Vector3(x + VERTEX_SPACING, get_height_at(world_x + VERTEX_SPACING, world_z + VERTEX_SPACING), z + VERTEX_SPACING)
			
			var normal1 = (v2 - v1).cross(v3 - v1).normalized()
			var normal2 = (v4 - v2).cross(v3 - v2).normalized()
			
			var height_factor1 = clamp(v1.y / HEIGHT_SCALE, 0, 1)
			var height_factor2 = clamp(v2.y / HEIGHT_SCALE, 0, 1)
			var height_factor3 = clamp(v3.y / HEIGHT_SCALE, 0, 1)
			var height_factor4 = clamp(v4.y / HEIGHT_SCALE, 0, 1)
			
			var slope1 = abs(normal1.dot(Vector3.UP))
			var slope2 = abs(normal2.dot(Vector3.UP))
			
			var low_color = Color(0.2, 0.3, 0.1)
			var high_color = Color(0.7, 0.7, 0.7)
			var slope_color = Color(0.4, 0.3, 0.2)
			
			var color1 = low_color.lerp(high_color, height_factor1).lerp(slope_color, 1.0 - slope1)
			var color2 = low_color.lerp(high_color, height_factor2).lerp(slope_color, 1.0 - slope1)
			var color3 = low_color.lerp(high_color, height_factor3).lerp(slope_color, 1.0 - slope1)
			var color4 = low_color.lerp(high_color, height_factor4).lerp(slope_color, 1.0 - slope2)
			
			var uv1 = Vector2(x, z) / CHUNK_SIZE
			var uv2 = Vector2(x + VERTEX_SPACING, z) / CHUNK_SIZE
			var uv3 = Vector2(x, z + VERTEX_SPACING) / CHUNK_SIZE
			var uv4 = Vector2(x + VERTEX_SPACING, z + VERTEX_SPACING) / CHUNK_SIZE
			
			# First triangle
			st.set_normal(normal1)
			st.set_color(color1)
			st.set_uv(uv1)
			st.add_vertex(v1)
			
			st.set_color(color2)
			st.set_uv(uv2)
			st.add_vertex(v2)
			
			st.set_color(color3)
			st.set_uv(uv3)
			st.add_vertex(v3)
			
			# Second triangle
			st.set_normal(normal2)
			st.set_color(color2)
			st.set_uv(uv2)
			st.add_vertex(v2)
			
			st.set_color(color4)
			st.set_uv(uv4)
			st.add_vertex(v4)
			
			st.set_color(color3)
			st.set_uv(uv3)
			st.add_vertex(v3)
	
	var array_mesh = st.commit()
	
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = array_mesh
	mesh_instance.material_override = base_material
	chunk.add_child(mesh_instance)
	
	var static_body = StaticBody3D.new()
	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = array_mesh.create_trimesh_shape()
	static_body.add_child(collision_shape)
	chunk.add_child(static_body)
	
	add_child(chunk)
	chunks[pos] = chunk
