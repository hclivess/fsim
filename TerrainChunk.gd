# TerrainChunk.gd
extends Node3D

var mesh_instance: MeshInstance3D

func _ready():
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)

func generate_terrain(chunk_size: int, noise: FastNoiseLite, height_scale: float):
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var verts = PackedVector3Array()
	var uvs = PackedVector2Array()
	var normals = PackedVector3Array()
	var indices = PackedInt32Array()
	
	# Generate grid points
	for z in range(chunk_size + 1):
		for x in range(chunk_size + 1):
			var world_x = position.x + x
			var world_z = position.z + z
			
			var height = noise.get_noise_2d(world_x, world_z)
			height += noise.get_noise_2d(world_x * 2.0, world_z * 2.0) * 0.5
			height += noise.get_noise_2d(world_x * 4.0, world_z * 4.0) * 0.25
			
			verts.push_back(Vector3(x, height * height_scale, z))
			uvs.push_back(Vector2(float(x) / chunk_size, float(z) / chunk_size))
			normals.push_back(Vector3.UP)
	
	# Generate triangles with correct winding order
	for z in range(chunk_size):
		for x in range(chunk_size):
			var current = z * (chunk_size + 1) + x
			var right = current + 1
			var below = (z + 1) * (chunk_size + 1) + x
			var below_right = below + 1
			
			# First triangle
			indices.push_back(current)
			indices.push_back(right)
			indices.push_back(below)
			
			# Second triangle
			indices.push_back(right)
			indices.push_back(below_right)
			indices.push_back(below)
	
	# Calculate proper normals
	for i in range(0, indices.size(), 3):
		var v1 = verts[indices[i]]
		var v2 = verts[indices[i + 1]]
		var v3 = verts[indices[i + 2]]
		
		var normal = (v2 - v1).cross(v3 - v1).normalized()
		
		normals[indices[i]] = normal
		normals[indices[i + 1]] = normal
		normals[indices[i + 2]] = normal
	
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = array_mesh
	
	# Add material with correct settings
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.5, 0.2)
	material.roughness = 0.9
	material.cull_mode = StandardMaterial3D.CULL_BACK  # Enable backface culling
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED  # Ensure no transparency
	mesh_instance.material_override = material
	
	# Add collision
	var static_body = StaticBody3D.new()
	add_child(static_body)
	
	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = array_mesh.create_trimesh_shape()
	static_body.add_child(collision_shape)
