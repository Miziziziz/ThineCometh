extends Node2D


var alerted = false

func alert():
	alerted = true
	$AnimationPlayer.play("alert")
	$AlertSounds.get_child(randi() % $AlertSounds.get_child_count()).play()

var sight_points = []
# line of sight algorithm found here: http://www.roguebasin.com/index.php?title=Bresenham%27s_Line_Algorithm
func has_line_of_sight(start_coord, end_coord, tilemap: TileMap):
	var x1 = start_coord[0]
	var y1 = start_coord[1]
	var x2 = end_coord[0]
	var y2 = end_coord[1]
	var dx = x2 - x1
	var dy = y2 - y1
	# Determine how steep the line is
	var is_steep = abs(dy) > abs(dx)
	var tmp = 0
	# Rotate line
	if is_steep:
		tmp = x1
		x1 = y1
		y1 = tmp
		tmp = x2
		x2 = y2
		y2 = tmp
	# Swap start and end points if necessary and store swap state
	var swapped = false
	if x1 > x2:
		tmp = x1
		x1 = x2
		x2 = tmp
		tmp = y1
		y1 = y2
		y2 = tmp
		swapped = true
	# Recalculate differentials
	dx = x2 - x1
	dy = y2 - y1
	
	# Calculate error
	var error = int(dx / 2.0)
	var ystep = 1 if y1 < y2 else -1

	# Iterate over bounding box generating points between start and end
	var y = y1
	var points = []
	for x in range(x1, x2 + 1):
		var coord = [y, x] if is_steep else [x, y]
		points.append(coord)
		error -= abs(dy)
		if error < 0:
			y += ystep
			error += dx
	
	if swapped:
		points.invert()
	
	sight_points = []
	for p in points:
		sight_points.append(to_local(Vector2.ONE * 8 + tilemap.map_to_world(Vector2(p[0], p[1]))))
	#update()
	for point in points:
		if tilemap.get_cell(point[0], point[1]) >= 0:
			return false
	return true
#
#func _draw():
#	for sp in sight_points:
#		draw_circle(sp, 4, Color.red)

func get_grid_path(start_coord, end_coord, astar: AStar2D, astar_points_cache: Dictionary):
	#sight_points=[]
	#update()
	var path = astar.get_point_path(astar_points_cache[str(start_coord)], astar_points_cache[str(end_coord)])
	return path

