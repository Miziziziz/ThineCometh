extends Node2D

var cur_level = 1

var scene_root = null
var player = null
var exit = null
var tilemap = null
onready var astar =  AStar2D.new()
var astar_points_cache = {}
var treasure_ind = 0

var treasures = [
	{
		"scene_object": preload("res://treasures/Cat.tscn"),
		"header": "Treasure found:\nA Friendly Cat",
		"message": "\"Meow\"",
		"image": preload("res://sprites/portraits/cat.png")
	},
	{
		"scene_object": preload("res://treasures/Mantis.tscn"),
		"header": "Treasure found:\nA Recently Widowed Praying Mantis",
		"message": "\"No officer, I haven't seen him in days\"",
		"image": preload("res://sprites/portraits/prayingmantis.png")
	},
	{
		"scene_object": preload("res://treasures/Dog.tscn"),
		"header": "Treasure found:\nA Racist Dog",
		"message": "\"Hitler did nothing wrong\"",
		"image": preload("res://sprites/portraits/dog.png")
	},
	{
		"scene_object": preload("res://treasures/BumbleBae.tscn"),
		"header": "Treasure found:\nA Bumble Bae",
		"message": "\"Hey Honey\"",
		"image": preload("res://sprites/portraits/bumblebae.png")
	},
	{
		"scene_object": preload("res://treasures/Gamedev.tscn"),
		"header": "Treasure found:\nA Self-Promoting Game Developer",
		"message": "\"Buy my game Theyest Thou on Steam, also congrats on beating this game\"",
		"image": preload("res://sprites/portraits/gamedev.png")
	}
]

onready var rooms_texture_data = preload("res://sprites/rooms.png").get_data()

var key = preload("res://objects/Key.tscn")
var door = preload("res://objects/Door.tscn")
var enemy = preload("res://objects/Enemy.tscn")
var potion = preload("res://objects/Potion.tscn")

const START_ROOM_COUNT = 3 # not including starting room and exit room
const ROOM_COUNT_INCREASE_PER_LEVEL = 2
const EXIT_ROOM_TYPE_IND = 0
const START_ROOM_TYPE_IND = 1

const CELL_SIZE = 16
const ROOMS_SIZE = 8
const ROOM_DATA_IMAGE_ROW_LEN = 4
const NUM_OF_ROOM_TYPES = 11

const NUM_OF_WALL_TYPES = 4
const CHANCE_OF_NON_BLANK_WALL = 4

const KEY_COUNT = 3
const DOOR_COUNT = 3
const START_ENEMY_COUNT = 2
const ENEMY_COUNT_INCREASE_PER_LEVEL = 1
const START_POTION_COUNT = 0
const POTION_COUNT_INCREASE_PER_LEVEL = 1

const CHANCE_OF_TREASURE_SPAWNING = 2

func init(scn_root, tilemap_ref, player_ref, exit_ref):
	scene_root = scn_root 
	player = player_ref 
	exit = exit_ref 
	tilemap = tilemap_ref

func generate_world(level, trsure_ind):
	cur_level = level
	treasure_ind = trsure_ind
	astar.clear()
	tilemap.clear()
	get_tree().call_group("enemies", "queue_free")
	get_tree().call_group("keys", "queue_free")
	get_tree().call_group("potions", "queue_free")
	get_tree().call_group("doors", "queue_free")
	get_tree().call_group("treasure", "queue_free")
	var rooms_data = generate_rooms_data()
	var spawn_locations = generate_rooms(rooms_data)
	var world_data = generate_objects_in_world(spawn_locations)
	world_data["astar"] = astar
	world_data["astar_points_cache"] = astar_points_cache
	if world_data.keys.size() < KEY_COUNT:
		# in case level generation fails and makes an unwinnable world
		world_data = generate_world(level, treasure_ind)
	return world_data

func generate_rooms_data() -> Dictionary:
	var room_count = START_ROOM_COUNT + cur_level * ROOM_COUNT_INCREASE_PER_LEVEL
	var rooms_data={
		str([0,0]):{"type": START_ROOM_TYPE_IND, "coords":[0,0]}
	}
	
	# randomly generate rooms
	var possible_room_locations = get_open_adjacent_rooms(rooms_data, [0,0])
	var generated_rooms = []
	for _i in range(room_count):
		var rand_room_type = (randi() % (NUM_OF_ROOM_TYPES - 1)) + 1 # room type 0 is the exit room, don't use here
		var rand_room_loc = select_rand_room_location(possible_room_locations, rooms_data)
		rooms_data[str(rand_room_loc)] = {"type": rand_room_type, "coords":rand_room_loc}
		generated_rooms.append(rand_room_loc)
		possible_room_locations += get_open_adjacent_rooms(rooms_data, rand_room_loc)
	
	# choose exit room
	var rand_room_loc = select_rand_room_location(possible_room_locations, rooms_data)
	rooms_data[str(rand_room_loc)] = {"type": EXIT_ROOM_TYPE_IND, "coords":rand_room_loc}
	if rooms_data.size() < 5:
		print('error')
	
	return rooms_data

# sometimes there are duplicate locations, use special function to account for this
func select_rand_room_location(possible_room_locations: Array, rooms_data: Dictionary):
	var rand_ind = randi() % possible_room_locations.size()
	var rand_room_loc = possible_room_locations[rand_ind]
	possible_room_locations.remove(rand_ind)
	if str(rand_room_loc) in rooms_data:
		rand_room_loc = select_rand_room_location(possible_room_locations, rooms_data)
	return rand_room_loc

func get_open_adjacent_rooms(rooms_data: Dictionary, coords):
	var empty_adjacent_rooms = []
	var adj_coords = [
		[coords[0]+0, coords[1]+1], # up
		[coords[0]+1, coords[1]+0], # right
		[coords[0]+0, coords[1]-1], # down
		[coords[0]-1, coords[1]+0], # left
	]
	for coord in adj_coords:
		if not str(coord) in rooms_data:
			empty_adjacent_rooms.append(coord)
	return empty_adjacent_rooms

# returns list of enemy/pickups spawns, exit door, locked doors locations
func generate_rooms(rooms_data_list: Dictionary) -> Dictionary:
	var spawn_locations = {
		"enemy_spawn_locations": [],
		"pickup_spawn_locations": [],
		"door_coords": [],
		"exit_coords": [0, 0],
	}
	var ind = 0
	var walkable_floor_tiles = {}
	for room_data in rooms_data_list.values():
		var only_do_walls = ind == 0 # only want to create walls if it's the first room since that's where the player starts
		ind += 1
		var coords = room_data.coords
		var x_pos = coords[0] * ROOMS_SIZE
		var y_pos = coords[1] * ROOMS_SIZE
		var type = room_data.type
		var x_pos_img = (type % ROOM_DATA_IMAGE_ROW_LEN) * ROOMS_SIZE
		var y_pos_img = (type / ROOM_DATA_IMAGE_ROW_LEN) * ROOMS_SIZE
		for x in range(ROOMS_SIZE):
			for y in range(ROOMS_SIZE):
				rooms_texture_data.lock()
				var cell_data = rooms_texture_data.get_pixel(x_pos_img+x, y_pos_img+y)
				var cell_coords = [x_pos+x, y_pos+y]
				var wall_tile = false
				if cell_data == Color.black:
					var wall_type = get_rand_wall_type()
					tilemap.set_cell(x_pos+x, y_pos+y, wall_type, randi()%2==0,randi()%2==0)
					wall_tile = true
				if !only_do_walls:
					if cell_data == Color.red:
						spawn_locations.enemy_spawn_locations.append(cell_coords)
					elif cell_data == Color.green:
						spawn_locations.pickup_spawn_locations.append(cell_coords)
					elif cell_data == Color.blue:
						spawn_locations.exit_coords = cell_coords
					elif cell_data == Color.magenta:
						spawn_locations.door_coords.append(cell_coords)
				if !wall_tile:
					walkable_floor_tiles[str([x_pos+x, y_pos+y])] = [x_pos+x, y_pos+y]
		
		var scoords = ""
		var room_at_left = str([coords[0]-1, coords[1]]) in rooms_data_list
		var room_at_right = str([coords[0]+1, coords[1]]) in rooms_data_list
		var room_at_top = str([coords[0], coords[1]-1]) in rooms_data_list
		var room_at_bottom = str([coords[0], coords[1]+1]) in rooms_data_list
		if !room_at_left:
			tilemap.set_cell(x_pos, y_pos+3, get_rand_wall_type(), randi()%2==0,randi()%2==0)
			tilemap.set_cell(x_pos, y_pos+4, get_rand_wall_type(), randi()%2==0,randi()%2==0)
			scoords = str([x_pos, y_pos+3])
			if scoords in walkable_floor_tiles:
				walkable_floor_tiles.erase(scoords)
			scoords = str([x_pos, y_pos+4])
			if scoords in walkable_floor_tiles:
				walkable_floor_tiles.erase(scoords)
		if !room_at_right:
			tilemap.set_cell(x_pos+ROOMS_SIZE-1, y_pos+3, get_rand_wall_type(), randi()%2==0,randi()%2==0)
			tilemap.set_cell(x_pos+ROOMS_SIZE-1, y_pos+4, get_rand_wall_type(), randi()%2==0,randi()%2==0)
			scoords = str([x_pos+ROOMS_SIZE-1, y_pos+3])
			if scoords in walkable_floor_tiles:
				walkable_floor_tiles.erase(scoords)
			scoords = str([x_pos+ROOMS_SIZE-1, y_pos+4])
			if scoords in walkable_floor_tiles:
				walkable_floor_tiles.erase(scoords)
		if !room_at_top:
			tilemap.set_cell(x_pos+3, y_pos, get_rand_wall_type(), randi()%2==0,randi()%2==0)
			tilemap.set_cell(x_pos+4, y_pos, get_rand_wall_type(), randi()%2==0,randi()%2==0)
			scoords = str([x_pos+3, y_pos])
			if scoords in walkable_floor_tiles:
				walkable_floor_tiles.erase(scoords)
			scoords = str([x_pos+4, y_pos])
			if scoords in walkable_floor_tiles:
				walkable_floor_tiles.erase(scoords)
		if !room_at_bottom:
			tilemap.set_cell(x_pos+3, y_pos+ROOMS_SIZE-1, get_rand_wall_type(), randi()%2==0,randi()%2==0)
			tilemap.set_cell(x_pos+4, y_pos+ROOMS_SIZE-1, get_rand_wall_type(), randi()%2==0,randi()%2==0)
			scoords = str([x_pos+3, y_pos+ROOMS_SIZE-1])
			if scoords in walkable_floor_tiles:
				walkable_floor_tiles.erase(scoords)
			scoords = str([x_pos+4, y_pos+ROOMS_SIZE-1])
			if scoords in walkable_floor_tiles:
				walkable_floor_tiles.erase(scoords)
	generate_astar_grid(walkable_floor_tiles)
	return spawn_locations

func generate_astar_grid(walkable_floor_tiles):
	astar_points_cache = {}
	for tile_coord in walkable_floor_tiles.values():
		var tile_id = astar.get_available_point_id()
		astar.add_point(tile_id, Vector2(tile_coord[0], tile_coord[1]))
		astar_points_cache[str([tile_coord[0], tile_coord[1]])] = tile_id
	
	for tile_coord in walkable_floor_tiles.values():
		var tile_id = astar_points_cache[str([tile_coord[0], tile_coord[1]])]
		var left_x_key = str([tile_coord[0]-1, tile_coord[1]])
		if left_x_key in astar_points_cache:
			astar.connect_points(astar_points_cache[left_x_key], tile_id)
		var up_y_key = str([tile_coord[0], tile_coord[1]-1])
		if up_y_key in astar_points_cache:
			astar.connect_points(astar_points_cache[up_y_key], tile_id)

func get_rand_wall_type():
	var wall_type = 0
	if randi() % CHANCE_OF_NON_BLANK_WALL == 0:
		wall_type = randi() % NUM_OF_WALL_TYPES
	return wall_type

func generate_objects_in_world(spawn_locations: Dictionary) -> Dictionary:
	player.global_position = map_coord_to_world_pos(Vector2.ONE)
	exit.global_position = map_coord_to_world_pos(spawn_locations.exit_coords)
	var enemy_count = START_ENEMY_COUNT + ENEMY_COUNT_INCREASE_PER_LEVEL * cur_level
	var enemies = spawn_objects_at_locations(enemy, spawn_locations.enemy_spawn_locations, enemy_count, "enemies")
	
	var pickup_spawn_locations = spawn_locations.pickup_spawn_locations
	var keys = spawn_objects_at_locations(key, spawn_locations.pickup_spawn_locations, KEY_COUNT, "keys")
	
	var treasure = {}
	if treasure_ind < treasures.size() and randi() % CHANCE_OF_TREASURE_SPAWNING == 0:
		treasure["object_data"] = spawn_objects_at_locations(treasures[treasure_ind].scene_object, spawn_locations.pickup_spawn_locations, 1, "treasure")
		treasure["header"] = treasures[treasure_ind].header
		treasure["message"] = treasures[treasure_ind].message
		treasure["image"]  = treasures[treasure_ind].image
	
	var potion_count = START_POTION_COUNT + cur_level * POTION_COUNT_INCREASE_PER_LEVEL
	var potions = spawn_objects_at_locations(potion, spawn_locations.pickup_spawn_locations, potion_count, "potions")
	var doors = spawn_objects_at_locations(door, spawn_locations.door_coords, DOOR_COUNT, "doors", false)
	
	var data = {
		"enemies": enemies,
		"keys": keys,
		"potions": potions,
		"doors": doors,
		"player": player,
		"exit": exit,
		"treasure_data": treasure
	}
	return data

func spawn_objects_at_locations(object_to_spawn, location_list: Array, num_to_spawn: int, group_name: String, flip_randomly=true) -> Dictionary:
	# data is in dict with format "coords": obj, e.g. "(0, 3)": <obj_ref>
	var spawned_objs = {}
	for _i in range(num_to_spawn):
		if location_list.size() == 0:
			break
		var inst = object_to_spawn.instance()
		scene_root.add_child(inst)
		var rand_loc_ind = randi() % location_list.size()
		var coord = location_list[rand_loc_ind]
		inst.global_position = map_coord_to_world_pos(coord)
		location_list.remove(rand_loc_ind)
		spawned_objs[str(coord)] = inst
		inst.add_to_group(group_name)
		if flip_randomly and inst.has_node("Sprite") and randi() % 2 == 0:
			inst.get_node("Sprite").flip_h = true
	return spawned_objs

# takes list of 2 and converts it to a global position
func map_coord_to_world_pos(coord):
	return tilemap.map_to_world(Vector2(coord[0], coord[1])) + Vector2(CELL_SIZE / 2, CELL_SIZE / 2)
