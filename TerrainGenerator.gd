# TerrainGenerator.gd
extends Node3D

const CHUNK_SIZE = 96
const VIEW_DISTANCE = 2
const HEIGHT_SCALE = 80.0

var noise = FastNoiseLite.new()
var chunks = {}
var current_chunk = Vector2()
var camera: Camera3D

func _ready():
	# Configure noise for more interesting terrain
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = randi()  # Random seed each time
	noise.frequency = 0.005
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 6
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	
	# Get camera reference
	camera = get_tree().get_root().find_child("Camera3D", true, false)
	if !camera:
		print("Camera3D not found!")
		return
	
	_generate_chunks_around_player()

func _process(_delta):
	if !camera:
		return
		
	var player_pos = camera.global_position
	var new_chunk = Vector2(floor(player_pos.x / CHUNK_SIZE), floor(player_pos.z / CHUNK_SIZE))
	
	if new_chunk != current_chunk:
		current_chunk = new_chunk
		_generate_chunks_around_player()

func _generate_chunks_around_player():
	var needed_chunks = {}
	
	for x in range(current_chunk.x - VIEW_DISTANCE, current_chunk.x + VIEW_DISTANCE + 1):
		for z in range(current_chunk.y - VIEW_DISTANCE, current_chunk.y + VIEW_DISTANCE + 1):
			var chunk_pos = Vector2(x, z)
			needed_chunks[chunk_pos] = true
			
			if not chunks.has(chunk_pos):
				create_chunk(chunk_pos)
	
	for chunk_pos in chunks.keys():
		if not needed_chunks.has(chunk_pos):
			chunks[chunk_pos].queue_free()
			chunks.erase(chunk_pos)

func create_chunk(chunk_pos: Vector2):
	var chunk = Node3D.new()
	chunk.set_script(load("res://TerrainChunk.gd"))
	add_child(chunk)
	
	chunk.position = Vector3(chunk_pos.x * CHUNK_SIZE, 0, chunk_pos.y * CHUNK_SIZE)
	chunk.generate_terrain(CHUNK_SIZE, noise, HEIGHT_SCALE)
	
	chunks[chunk_pos] = chunk
