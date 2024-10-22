# TerrainChunk.gd
extends Node3D

var mesh_instance: MeshInstance3D

func _ready():
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)

func generate_terrain(chunk_size: int, noise: FastNoiseLite, height_scale: float, lod_level: int):
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	# Calculate vertex spacing based on LOD level
	var vertex_spacing = pow(2, lod_level)  # 1, 2, 4, 8, 16, etc.
	var vertices_per_side = (chunk_size / vertex_spacing) + 1
	
	var verts = PackedVector3Array()
	var uvs = PackedVector2Array()
	var normals = PackedVector3Array()
	var indices = PackedInt32Array()
	
	# Generate grid points with LOD spacing
	for z in range(0, chunk_size + 1, vertex_spacing):
		for x in range(0, chunk_size + 1, vertex_spacing):
			var world_x = position.x + x
			var world_z = position.z + z
			
			# Height calculation
			var height = noise.get_noise_2d(world_x * 0.5, world_z * 0.5) * height_scale
			
			verts.push_back(Vector3(x, height, z))
			uvs.push_back(Vector2(float(x) / chunk_size, float(z) / chunk_size))
			normals.push_back(Vector3.UP)
	
	# Generate triangles
	for z in range(vertices_per_side - 1):
		for x in range(vertices_per_side - 1):
			var current = z * vertices_per_side + x
			var right = current + 1
			var below = (z + 1) * vertices_per_side + x
			var below_right = below + 1
			
			indices.push_back(current)
			indices.push_back(right)
			indices.push_back(below)
			
			indices.push_back(right)
			indices.push_back(below_right)
			indices.push_back(below)
	
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = array_mesh
	
	# Material with better lighting response
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.5, 0.2)
	material.roughness = 0.95
	material.metallic = 0.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = false
	mesh_instance.material_override = material
	
	# Only add collision for nearby chunks
	if lod_level <= 2:
		var static_body = StaticBody3D.new()
		add_child(static_body)
		
		var collision_shape = CollisionShape3D.new()
		collision_shape.shape = array_mesh.create_trimesh_shape()
		static_body.add_child(collision_shape)
