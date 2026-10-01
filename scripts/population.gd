class_name CityPopulation
extends Node3D

const PERSON_LAYER: int = 4
const VEHICLE_LAYER: int = 8
const NAV_CELL: float = 2.0
const GROUP_SPACING: float = 1.75
const PEDESTRIAN_CLEARANCE: float = 1.5
var world: Node3D
var player: StudentPlayer
var citizens: Array[Dictionary] = []
var vehicles: Array[Dictionary] = []
var police: Array[Dictionary] = []
var meeting_actors: Dictionary = {}
var meeting_walks: Dictionary = {}
var _pedestrian_neighbors: Array[Dictionary] = []
var _neighbor_refresh := 0.0
var _animation_lod_timer := 0.0
var _grounding_cache: Dictionary = {}
var rng := RandomNumberGenerator.new()
var pursuit := false
var escape_seconds := 0.0
var arrest_seconds := 0.0
var stolen_vehicle := false
var crime_position := Vector3.ZERO
var crime_age := 1000.0
var friend: Node3D
var lod_tick := 0.0
var navigation := AStarGrid2D.new()
var _last_schedule_hour := -1

func setup(city: Node3D, student: StudentPlayer) -> void:
	world = city
	player = student
	player.city_world = world
	rng.seed = 87261
	_build_navigation()
	var routes: Array = world.pedestrian_routes
	for index in range(42):
		if routes.is_empty(): break
		var group_id: int = index / 3
		var route: PackedVector3Array = routes[group_id % routes.size()]
		if route.size() < 2: continue
		var names := ["character-female-a","character-male-d","character-female-e","character-male-b","character-female-f","character-male-e"]
		var actor := _person(names[index % names.size()],1.7+rng.randf_range(-0.08,0.14))
		var spawn: Dictionary = _sample_route(route,0.12+float(group_id / routes.size())/3.0)
		var offset := Vector3(float(index%3-1)*GROUP_SPACING,0,float(index%2)*1.1)
		actor.position = _safe_pedestrian_target(spawn.position + offset)
		citizens.append({"node":actor,"route":route,"index":spawn.index,"speed":1.2+float(group_id%3)*0.12,"hp":100.0,"panic":0.0,"stun":0.0,"wait":float(group_id%3),"goal":"Heading to class","group":group_id,"offset":offset,"nav_path":PackedVector3Array(),"nav_index":0,"nav_target":Vector3.INF,"nav_timer":0.0,"dead_seconds":0.0})
	for index in range(7):
		var campus := index < 4
		var patrols: Array = world.campus_police_routes if campus else world.city_police_routes
		if patrols.is_empty(): continue
		var route: PackedVector3Array = patrols[index % patrols.size()]
		if route.size() < 2: continue
		var actor := _person("character-male-c",1.9)
		var spawn: Dictionary = _sample_route(route,0.16+float(index % 4)*0.20)
		actor.position = spawn.position
		actor.add_child(ActorVisuals.ground_ring(Color("76b7dd") if campus else Color("668cff"),0.55))
		var badge := ActorVisuals.label("CAMPUS SECURITY" if campus else "CITY POLICE",Color("8ac2ef"),15)
		badge.position.y = 2.3
		actor.add_child(badge)
		police.append({"node":actor,"route":route,"index":spawn.index,"campus":campus,"alert":0.0,"hp":150.0,"stun":0.0,"nav_path":PackedVector3Array(),"nav_index":0,"nav_target":Vector3.INF,"nav_timer":0.0,"dead_seconds":0.0})
	var traffic: Array = world.traffic_routes
	for index in range(12):
		if traffic.is_empty(): break
		var route: PackedVector3Array = traffic[index % traffic.size()]
		if route.size() < 2: continue
		var models := ["sedan","hatchback-sports","suv","taxi","van","sedan-sports"]
		var cruiser := index == 4
		var body := _vehicle("police" if cruiser else models[index%models.size()])
		var spawn: Dictionary = _sample_route(route,float(index / traffic.size())/4.0)
		body.position = spawn.position
		body.rotation.y = _heading(route[int(spawn.index)]-body.position)
		vehicles.append({"node":body,"route":route,"index":spawn.index,"speed":rng.randf_range(6.0,9.0),"parked":false,"stolen":false,"occupied":false,"wait":0.0,"stuck":0.0,"police":cruiser,"distance_travelled":0.0})
	for spawn: Dictionary in world.parked_car_spawns:
		var body := _vehicle(str(spawn.get("model","sedan")))
		body.position = spawn.position
		body.rotation.y = float(spawn.rotation)
		vehicles.append({"node":body,"route":PackedVector3Array(),"index":0,"speed":0.0,"parked":true,"stolen":false,"occupied":false,"wait":0.0,"stuck":0.0})
	friend = _person("character-male-d",1.8)
	friend.position = Vector3(23,0.2,49)
	var tag := ActorVisuals.label("MILO",Color("d5f276"),24)
	tag.position.y = 2.55
	friend.add_child(tag)
	friend.add_child(ActorVisuals.ground_ring(Color("d5f276"),0.7))
	if not Game.crime_committed.is_connected(on_crime): Game.crime_committed.connect(on_crime)
	if not Game.changed.is_connected(_sync_meetings): Game.changed.connect(_sync_meetings)
	_update_citizen_schedule()
	_sync_meetings()
	for record: Dictionary in citizens+police: _ground_person(record.node)
	_ground_person(friend)
	_refresh_neighbor_lists()
	_update_animation_lod()

func reset_population() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	citizens.clear()
	vehicles.clear()
	police.clear()
	meeting_actors.clear()
	meeting_walks.clear()
	_grounding_cache.clear()
	_neighbor_refresh = 0.0
	_animation_lod_timer = 0.0
	pursuit = false
	escape_seconds = 0.0
	arrest_seconds = 0.0
	stolen_vehicle = false
	crime_age = 1000.0
	_last_schedule_hour = -1
	player.reset_travel()
	setup(world,player)

func _person(asset: String, height: float) -> CharacterBody3D:
	var person := CharacterBody3D.new()
	person.collision_layer = PERSON_LAYER
	person.collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.6
	shape.shape = capsule
	shape.position.y = 0.82
	person.add_child(shape)
	var model := ActorVisuals.model("Characters",asset,height)
	person.add_child(model)
	person.set_meta("model",model)
	add_child(person)
	ActorVisuals.play(person,"idle")
	return person

func _ground_person(actor: Node3D) -> void:
	var id := actor.get_instance_id()
	var at := actor.global_position
	var cached: Dictionary = _grounding_cache.get(id,{})
	if not cached.is_empty():
		var previous: Vector3 = cached.position
		if absf(previous.y-at.y)<0.002 and Vector2(previous.x,previous.z).distance_squared_to(Vector2(at.x,at.z))<0.0081: return
	else:
		var parts: Array[Dictionary] = []
		for child: Node in actor.get_children():
			if child is Node3D and not child is CollisionShape3D:
				parts.append({"node":child,"base_y":child.position.y})
		cached = {"parts":parts}
		_grounding_cache[id] = cached
	var support: float = world.walkable_support_height(at,0.24)
	var lift := support-at.y
	for part: Dictionary in cached.parts: part.node.position.y = float(part.base_y)+lift
	cached.position = at

func _refresh_neighbor_lists() -> void:
	# Ten-Hz broadphase keeps separation local instead of scanning the whole city
	# for every pedestrian on every physics tick. Three-metre cells cover movement
	# between refreshes as well as the full personal-space radius.
	_pedestrian_neighbors = citizens + police
	for record: Dictionary in meeting_walks.values(): _pedestrian_neighbors.append(record)
	var buckets: Dictionary = {}
	for record: Dictionary in _pedestrian_neighbors:
		var at: Vector3 = record.node.position
		var cell := Vector2i(floori(at.x/3.0),floori(at.z/3.0))
		if not buckets.has(cell): buckets[cell] = []
		buckets[cell].append(record)
	for record: Dictionary in _pedestrian_neighbors:
		var at: Vector3 = record.node.position
		var cell := Vector2i(floori(at.x/3.0),floori(at.z/3.0))
		var neighbors: Array[CharacterBody3D] = []
		for x in range(-1,2):
			for z in range(-1,2):
				for neighbor: Dictionary in buckets.get(cell+Vector2i(x,z),[]):
					if neighbor.node!=record.node: neighbors.append(neighbor.node)
		record.neighbors = neighbors

func _vehicle(asset: String) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	body.collision_layer = VEHICLE_LAYER
	body.collision_mask = 0
	body.add_child(ActorVisuals.model("Cars",asset,1.65))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9,1.5,4.0)
	shape.shape = box
	shape.position.y = 0.86
	body.add_child(shape)
	add_child(body)
	return body

func _physics_process(delta: float) -> void:
	if not player or Game.paused or Game.status != "playing": return
	crime_age += delta
	lod_tick += delta
	var indoor: bool = player.position.x > 400.0
	_neighbor_refresh -= delta
	if _neighbor_refresh<=0.0:
		_refresh_neighbor_lists()
		_neighbor_refresh = 0.1
	for citizen: Dictionary in citizens:
		_update_citizen(citizen,delta,indoor)
	_update_traffic(delta,indoor)
	_update_police(delta,indoor)
	if friend:
		friend.visible = Game.tutorial_step < 3 and not indoor
		friend.collision_layer = PERSON_LAYER if friend.visible else 0
		_ground_person(friend)
	_update_meeting_walks(delta,indoor)
	_animation_lod_timer -= delta
	if _animation_lod_timer<=0.0:
		_update_animation_lod()
		_animation_lod_timer = 0.2
	if lod_tick > 1.0:
		lod_tick = 0.0
		_sync_meetings()
		_update_citizen_schedule()

func _update_citizen(citizen: Dictionary, delta: float, indoor: bool) -> void:
	var actor: CharacterBody3D = citizen.node
	_ground_person(actor)
	if float(citizen.hp) <= 0.0:
		citizen.dead_seconds += delta
		actor.visible = not indoor and float(citizen.dead_seconds) < 25.0
		actor.collision_layer = 0
		return
	_set_person_visible(actor,not indoor and actor.position.distance_squared_to(player.position) < 8100.0)
	actor.collision_layer = PERSON_LAYER if actor.visible else 0
	if not actor.visible: return
	if float(citizen.stun) > 0.0:
		citizen.stun = maxf(0.0,float(citizen.stun)-delta)
		return
	if float(citizen.panic) > 0.0:
		citizen.panic = maxf(0.0,float(citizen.panic)-delta)
		var away: Vector3 = actor.position-crime_position
		away.y = 0.0
		if away.length_squared() < 0.01: away = Vector3.RIGHT
		var escape_target: Vector3 = actor.position+away.normalized()*9.0
		escape_target.x = clampf(escape_target.x,-149.0,149.0)
		escape_target.z = clampf(escape_target.z,-122.0,122.0)
		_move_person(citizen,escape_target,3.1,delta)
		return
	if float(citizen.wait) > 0.0:
		citizen.wait = maxf(0.0,float(citizen.wait)-delta)
		_settle_idle_spacing(citizen,delta)
		ActorVisuals.play(actor,"idle")
		return
	var route: PackedVector3Array = citizen.route
	if int(citizen.get("target_index",-1))!=int(citizen.index):
		citizen.walk_target = _safe_pedestrian_target(route[int(citizen.index)]+Vector3(citizen.offset))
		citizen.target_index = int(citizen.index)
	var target: Vector3 = citizen.walk_target
	if _horizontal_distance(actor.position,target) < 1.2:
		citizen.index = (int(citizen.index)+1)%route.size()
		citizen.wait = 1.0+float(int(citizen.group)%4)
		if Game.current_phase() in ["Evening","Dusk","Night"]: citizen.wait = 8.0+float(int(citizen.group)%4)*3.0
	else:
		_move_person(citizen,target,float(citizen.speed),delta)

func _safe_pedestrian_target(at: Vector3) -> Vector3:
	var result := at
	for obstacle: Rect2 in world.obstacle_rects:
		var clear := obstacle.grow(0.65)
		if not clear.has_point(Vector2(result.x,result.z)): continue
		var options: Array[Vector3] = [Vector3(clear.position.x-0.1,result.y,result.z),Vector3(clear.end.x+0.1,result.y,result.z),Vector3(result.x,result.y,clear.position.y-0.1),Vector3(result.x,result.y,clear.end.y+0.1)]
		var nearest := INF
		for option: Vector3 in options:
			var distance := result.distance_squared_to(option)
			if distance<nearest:
				nearest = distance
				at = option
		result = at
	return result

func _settle_idle_spacing(record: Dictionary, delta: float) -> void:
	var actor: CharacterBody3D = record.node
	var away := Vector3.ZERO
	for other: CharacterBody3D in record.get("neighbors",[]):
		if not is_instance_valid(other) or not other.visible or other.collision_layer==0: continue
		var separation: Vector3 = actor.position-other.position
		separation.y = 0.0
		var squared := separation.length_squared()
		if squared>=PEDESTRIAN_CLEARANCE*PEDESTRIAN_CLEARANCE: continue
		var distance := sqrt(squared)
		if distance>0.05:
			away += separation/distance*(PEDESTRIAN_CLEARANCE-distance)
	if away.length_squared()<0.001: return
	var target := actor.position+away.normalized()*minf(away.length(),delta*0.9)
	if _safe_pedestrian_target(target).distance_squared_to(target)>0.01: return
	actor.velocity = (target-actor.position)/maxf(delta,0.001)
	actor.velocity.y = -0.5
	actor.move_and_slide()

func _update_citizen_schedule() -> void:
	var hour := int(Game.minute/60.0)
	if hour == _last_schedule_hour: return
	_last_schedule_hour = hour
	var hour_of_day := hour%24
	for citizen: Dictionary in citizens:
		var group := int(citizen.group)
		var route_index := group % maxi(1,world.pedestrian_routes.size())
		var day_goals := ["Heading to class","Lunch at College Square","Walking home with friends","Study group at the residence","Meeting friends at the quad"]
		var night_goals := ["Evening study group","Late takeout with friends","Heading home","Hanging out outside residence","Hanging out near the parking lot"]
		citizen.goal = (night_goals if hour_of_day >= 18 or hour_of_day < 7 else day_goals)[route_index%5]

func _update_traffic(delta: float, indoor: bool) -> void:
	# Only vehicles whose actual lane corridor intersects ours cause a queue.
	# The previous broad cone also stopped for oncoming and parked cars beside roads.
	for car: Dictionary in vehicles:
		var actor: AnimatableBody3D = car.node
		actor.visible = not indoor
		if car.occupied or car.parked: continue
		var route: PackedVector3Array = car.route
		if route.size() < 2: continue
		var target: Vector3 = route[int(car.index)]
		var distance := _horizontal_distance(actor.position,target)
		if distance < 0.35:
			car.index = (int(car.index)+1)%route.size()
			target = route[int(car.index)]
			distance = _horizontal_distance(actor.position,target)
		var direction: Vector3 = (target-actor.position).normalized()
		var speed: float = car.speed
		var front: Vector3 = player.position-actor.position
		if not player.vehicle and absf(front.y)<2.0 and front.dot(direction)>-1.0 and front.dot(direction)<5.2 and absf(front.cross(direction).y)<1.6: speed = 0.0
		for other: Dictionary in vehicles:
			if other.node == actor: continue
			var relative: Vector3 = other.node.position-actor.position
			relative.y = 0.0
			if relative.length_squared()>360.0: continue
			var other_direction: Vector3 = other.node.basis.z
			if not other.parked and not other.occupied and other.route.size()>1:
				other_direction = (other.route[int(other.index)]-other.node.position).normalized()
			var ahead := relative.dot(direction)
			var lateral := absf(relative.cross(direction).y)
			var alignment := direction.dot(other_direction)
			if bool(other.parked) or bool(other.occupied):
				# Project both actual car bodies onto our lane instead of treating a stall as a five-metre circle.
				var half_width := absf(alignment)*0.95+absf(direction.cross(other_direction).y)*2.0
				var half_length := absf(alignment)*2.0+absf(direction.cross(other_direction).y)*0.95
				if ahead>0.0 and ahead<2.1+half_length+0.5 and lateral<1.0+half_width: speed = 0.0
				continue
			if alignment>0.6 and ahead>0.0 and ahead<5.8 and lateral<2.05:
				# Following cars always yield to the car ahead, regardless of creation order.
				speed = minf(speed,maxf(0.0,(ahead-4.9)*3.0))
				continue
			if alignment>0.6 or (alignment < -0.6 and lateral>2.2): continue
			var crossing := _traffic_crossing(actor.position,direction,other.node.position,other_direction)
			if not crossing.is_finite(): continue
			var ours: float = crossing.x
			var theirs: float = crossing.y
			if ours < -2.5 or theirs < -2.5 or ours > minf(distance+2.0,14.0) or theirs > 14.0: continue
			# A car already entering the junction clears it; ties have one stable winner.
			var their_priority: bool = theirs < 2.4 or (ours>=2.4 and other.node.get_instance_id()<actor.get_instance_id())
			if their_priority and ours>2.4: speed = minf(speed,maxf(0.0,(ours-4.5)*3.0))
		car.stuck = float(car.stuck)+delta if speed<0.1 else 0.0
		var advance := minf(speed*delta,distance)
		car.distance_travelled = float(car.get("distance_travelled",0.0))+advance
		actor.position += direction*advance
		actor.rotation.y = lerp_angle(actor.rotation.y,_heading(direction),minf(1.0,delta*6.0))

func _traffic_crossing(a: Vector3, direction: Vector3, b: Vector3, other_direction: Vector3) -> Vector2:
	var divisor := direction.x*other_direction.z-direction.z*other_direction.x
	if absf(divisor)<0.06: return Vector2.INF
	var between := b-a
	return Vector2((between.x*other_direction.z-between.z*other_direction.x)/divisor,(between.x*direction.z-between.z*direction.x)/divisor)

func _update_police(delta: float, indoor: bool) -> void:
	var seen := false
	var closest := INF
	var player_on_campus := _is_campus(player.position)
	if not indoor and not player_on_campus and _cruiser_sees_player():
		if stolen_vehicle and player.vehicle and not pursuit:
			_begin_pursuit("STOLEN VEHICLE IDENTIFIED — a road patrol called it in.")
			_alert_city_officers()
		if pursuit: seen = true
	for officer: Dictionary in police:
		var actor: CharacterBody3D = officer.node
		_ground_person(actor)
		actor.visible = not indoor
		actor.collision_layer = PERSON_LAYER if actor.visible and float(officer.hp)>0.0 else 0
		if float(officer.hp) <= 0.0: continue
		if float(officer.stun) > 0.0:
			officer.stun = maxf(0.0,float(officer.stun)-delta)
			continue
		var distance := _horizontal_distance(actor.position,player.position)
		var jurisdiction := bool(officer.campus) == player_on_campus
		var can_see := not indoor and jurisdiction and distance < (28.0 if pursuit else 19.0) and _line_of_sight(actor.position,player.position)
		if stolen_vehicle and player.vehicle and can_see and not pursuit:
			_begin_pursuit("STOLEN VEHICLE IDENTIFIED — break line of sight to escape.")
			officer.alert = 12.0
			crime_position = player.position
		if can_see and pursuit:
			seen = true
			closest = minf(closest,distance)
			officer.alert = 10.0
		if pursuit and float(officer.alert)>0.0 and jurisdiction:
			officer.alert = maxf(0.0,float(officer.alert)-delta)
			var target: Vector3 = player.position if can_see else crime_position
			_move_person(officer,target,6.3,delta)
		else:
			var route: PackedVector3Array = officer.route
			var target: Vector3 = route[int(officer.index)]
			if _horizontal_distance(actor.position,target)<1.3: officer.index = (int(officer.index)+1)%route.size()
			_move_person(officer,target,1.8,delta)
	if not pursuit: return
	if seen:
		escape_seconds = 0.0
		crime_position = player.position
	else:
		escape_seconds += delta
	if closest < 1.7: arrest_seconds += delta
	else: arrest_seconds = maxf(0.0,arrest_seconds-delta*1.5)
	if arrest_seconds >= 2.3:
		Game.caught_by_police()
		return
	if escape_seconds >= 10.0:
		pursuit = false
		arrest_seconds = 0.0
		for officer: Dictionary in police: officer.alert = 0.0
		Game.set_heat(maxf(0.0,Game.heat-30.0))
		Game.notification.emit("You lost the patrol. Keep a low profile.")

func _cruiser_sees_player() -> bool:
	for car: Dictionary in vehicles:
		if not bool(car.get("police",false)) or car.occupied or car.stolen: continue
		if _horizontal_distance(car.node.position,player.position)<22.0 and _line_of_sight(car.node.position,player.position): return true
	return false

func _alert_city_officers() -> void:
	for officer: Dictionary in police:
		if not bool(officer.campus) and float(officer.hp)>0.0: officer.alert = 15.0

func _begin_pursuit(message: String) -> void:
	if not pursuit:
		Game.notification.emit(message)
		if Game.has_signal("feedback_event"): Game.emit_signal("feedback_event","detected",0.0)
	pursuit = true
	escape_seconds = 0.0
	Game.set_heat(maxf(Game.heat,40.0))

func _build_navigation() -> void:
	navigation.region = Rect2i(-76,-62,153,125)
	navigation.cell_size = Vector2(NAV_CELL,NAV_CELL)
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	for obstacle: Rect2 in world.obstacle_rects:
		var blocked := obstacle.grow(0.7)
		var start := Vector2i(floori(blocked.position.x/NAV_CELL),floori(blocked.position.y/NAV_CELL))
		var finish := Vector2i(ceili(blocked.end.x/NAV_CELL),ceili(blocked.end.y/NAV_CELL))
		for x in range(start.x,finish.x+1):
			for z in range(start.y,finish.y+1):
				var cell := Vector2i(x,z)
				if navigation.is_in_boundsv(cell): navigation.set_point_solid(cell)

func _nearest_open_cell(at: Vector3) -> Vector2i:
	var cell := Vector2i(roundi(at.x/NAV_CELL),roundi(at.z/NAV_CELL))
	cell.x = clampi(cell.x,navigation.region.position.x,navigation.region.end.x-1)
	cell.y = clampi(cell.y,navigation.region.position.y,navigation.region.end.y-1)
	if not navigation.is_point_solid(cell): return cell
	for radius in range(1,8):
		for dx in range(-radius,radius+1):
			for dz in range(-radius,radius+1):
				var next := cell+Vector2i(dx,dz)
				if navigation.is_in_boundsv(next) and not navigation.is_point_solid(next): return next
	return cell

func _move_person(record: Dictionary, target: Vector3, speed: float, delta: float) -> void:
	var actor: CharacterBody3D = record.node
	record.nav_timer = maxf(0.0,float(record.nav_timer)-delta)
	var destination := target
	var wall_contact := false
	for collision_index in actor.get_slide_collision_count():
		if absf(actor.get_slide_collision(collision_index).get_normal().y)<0.5: wall_contact = true
	if wall_contact or not _line_of_sight(actor.position,target):
		var old_target: Vector3 = record.nav_target
		if float(record.nav_timer)<=0.0 or old_target.distance_squared_to(target)>25.0:
			var points: PackedVector2Array = navigation.get_point_path(_nearest_open_cell(actor.position),_nearest_open_cell(target))
			var route := PackedVector3Array()
			for point: Vector2 in points: route.append(Vector3(point.x,0.15,point.y))
			record.nav_path = route
			record.nav_index = 1 if route.size()>1 else 0
			record.nav_target = target
			record.nav_timer = 1.5
		var route: PackedVector3Array = record.nav_path
		var path_index: int = int(record.nav_index)
		while path_index<route.size() and _horizontal_distance(actor.position,route[path_index])<0.65: path_index += 1
		record.nav_index = path_index
		if path_index<route.size(): destination = route[path_index]
	var direction := destination-actor.position
	direction.y = 0.0
	if direction.length()<0.15:
		actor.velocity = Vector3.ZERO
		ActorVisuals.play(actor,"idle")
		return
	direction = direction.normalized()
	if not record.has("campus"):
		var separation := Vector3.ZERO
		for other: CharacterBody3D in record.get("neighbors",[]):
			if not is_instance_valid(other) or not other.visible or other.collision_layer==0: continue
			var away := actor.position-other.position
			away.y = 0.0
			var squared := away.length_squared()
			if squared>=PEDESTRIAN_CLEARANCE*PEDESTRIAN_CLEARANCE: continue
			var gap := sqrt(squared)
			if gap<0.05:
				away = Vector3.RIGHT if actor.get_instance_id()>other.get_instance_id() else Vector3.LEFT
				gap = 0.05
			separation += away/gap*(PEDESTRIAN_CLEARANCE-gap)*2.6
			if direction.dot(-away/gap)>0.6:
				separation += Vector3(direction.z,0,-direction.x)*(PEDESTRIAN_CLEARANCE-gap)*0.9
		direction = (direction+separation).normalized()
	if record.has("campus") and _is_campus(actor.position+direction*speed*delta) != bool(record.campus):
		if _is_campus(actor.position) == bool(record.campus): return
	actor.velocity.x = direction.x*speed
	actor.velocity.z = direction.z*speed
	actor.velocity.y = -0.5 if actor.is_on_floor() else maxf(-12.0,actor.velocity.y-delta*20.0)
	actor.move_and_slide()
	actor.rotation.y = lerp_angle(actor.rotation.y,_heading(direction),minf(1.0,delta*7.0))
	ActorVisuals.play(actor,"sprint" if speed>2.5 else "walk")
	_ground_person(actor)

func _line_of_sight(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from+Vector3.UP,to+Vector3.UP,1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _is_campus(at: Vector3) -> bool:
	return world.get_district(at) == "Campus"

func on_crime(severity: float) -> void:
	if not player or Game.status != "playing": return
	crime_position = player.position
	crime_age = 0.0
	if severity >= 25.0:
		for citizen: Dictionary in citizens:
			if citizen.node.position.distance_to(player.position)<16.0 and _line_of_sight(citizen.node.position,player.position): citizen.panic = 6.0
	var campus := _is_campus(player.position)
	if not campus and _cruiser_sees_player():
		_begin_pursuit("SPOTTED — a road patrol called the deal in.")
		_alert_city_officers()
	var nearest: Dictionary = {}
	var best := INF
	for officer: Dictionary in police:
		if float(officer.hp)<=0.0 or bool(officer.campus)!=campus: continue
		var distance: float = officer.node.position.distance_to(player.position)
		if distance<best:
			nearest = officer
			best = distance
		if distance<19.0 and _line_of_sight(officer.node.position,player.position):
			officer.alert = 12.0
			_begin_pursuit("SPOTTED — break line of sight and stay hidden to escape.")
	if severity>=65.0 and not nearest.is_empty():
		nearest.alert = 15.0
		_begin_pursuit("POLICE RESPONDING — a patrol is checking the area.")

func nearby_vehicle() -> Dictionary:
	var nearest: Dictionary = {}
	var best := 4.2
	for car: Dictionary in vehicles:
		var distance: float = car.node.position.distance_to(player.position)
		if distance<best and not car.occupied and _line_of_sight(player.position,car.node.position):
			nearest = car
			best = distance
	return nearest

func toggle_vehicle() -> void:
	if Game.paused or Game.status != "playing" or player.blocked: return
	if player.position.x>400.0: return
	if player.vehicle:
		var exit_position := _safe_vehicle_exit(player.vehicle)
		if not exit_position.is_finite():
			Game.notification.emit("No room to open the door. Move the car away from the wall.")
			return
		for car: Dictionary in vehicles:
			if car.node == player.vehicle:
				car.occupied = false
				car.parked = true
				car.node.collision_layer = VEHICLE_LAYER
		player.vehicle = null
		player.position = exit_position
		player.velocity = Vector3.ZERO
		stolen_vehicle = false
		player.mode_changed.emit()
		Game.notification.emit("Vehicle parked. You're back on foot.")
		return
	var car := nearby_vehicle()
	if car.is_empty():
		Game.notification.emit("Move closer to a vehicle to enter it.")
		return
	car.occupied = true
	car.parked = true
	car.node.collision_layer = 0
	player.position = car.node.position+Vector3(0,0.12,0)
	player.visual.rotation.y = car.node.rotation.y
	player.velocity = Vector3.ZERO
	player.vehicle = car.node
	player.skateboarding = false
	stolen_vehicle = not bool(car.get("owned",false))
	car.stolen = stolen_vehicle
	player.mode_changed.emit()
	if stolen_vehicle:
		Game.report_crime(22.0)
		Game.notification.emit("STOLEN VEHICLE — patrols can identify it while you're driving.")
	else:
		Game.notification.emit("Your car. Drive carefully.")

func _safe_vehicle_exit(car: Node3D) -> Vector3:
	var options: Array[Vector3] = [car.global_basis.x*2.1,-car.global_basis.x*2.1,-car.global_basis.z*3.0,car.global_basis.z*3.0]
	for offset: Vector3 in options:
		var target := car.global_position+offset+Vector3(0,0.3,0)
		if not _line_of_sight(car.global_position,target): continue
		var query := PhysicsShapeQueryParameters3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 1.7
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY,target+Vector3(0,0.9,0))
		query.collision_mask = 1|VEHICLE_LAYER
		if get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return target
	return Vector3.INF

func spawn_owned_vehicle() -> void:
	for car: Dictionary in vehicles:
		if bool(car.get("owned",false)): return
	var node := _vehicle("sedan-sports")
	node.position = Vector3(-106,0.15,2)
	vehicles.append({"node":node,"route":PackedVector3Array(),"index":0,"speed":0.0,"parked":true,"stolen":false,"occupied":false,"owned":true,"wait":0.0,"stuck":0.0})

func meeting_actor_in_reach(meeting_id: int, radius: float = 4.0) -> bool:
	var id := str(meeting_id)
	if not meeting_actors.has(id) or meeting_walks[id].state!="waiting": return false
	var actor: Node3D = meeting_actors[id]
	return is_instance_valid(actor) and actor.visible and player.position.distance_to(actor.position)<=radius and _line_of_sight(player.position,actor.position)

func capture_meeting_state() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in meeting_walks:
		var record: Dictionary = meeting_walks[id]
		if record.state=="departing": continue
		var at: Vector3 = record.node.position
		var target: Vector3 = record.target
		result.append({"id":int(id),"position":[at.x,at.y,at.z],"target":[target.x,target.y,target.z],"state":record.state,"start_minute":record.start_minute,"due":record.due})
	return result

func restore_meeting_state(saved: Array) -> void:
	_sync_meetings()
	for entry: Variant in saved:
		if not entry is Dictionary: continue
		var id := str(int(entry.get("id",-1)))
		if not meeting_walks.has(id): continue
		var position_data: Variant = entry.get("position",[])
		if not position_data is Array or position_data.size()!=3: continue
		var at := Vector3(float(position_data[0]),float(position_data[1]),float(position_data[2]))
		if not at.is_finite() or absf(at.x)>150.0 or absf(at.z)>122.0 or at.y < -0.5 or at.y>2.0: continue
		var record: Dictionary = meeting_walks[id]
		record.node.position = at
		record.nav_path = _walking_path(at,record.target)
		record.nav_index = 0
		record.last_minute = Game.minute
		var start: float = float(entry.get("start_minute",record.start_minute))
		if is_finite(start): record.start_minute = start
		if str(entry.get("state",""))=="waiting" and Game.minute>=float(record.due)-Game.MEETING_ARRIVAL_MINUTES and _horizontal_distance(at,record.target)<2.0:
			record.state = "waiting"

func capture_pursuit_state() -> Dictionary:
	var officers: Array[Dictionary] = []
	for officer: Dictionary in police:
		var at: Vector3 = officer.node.position
		officers.append({"position":[at.x,at.y,at.z],"hp":officer.hp,"alert":officer.alert,"stun":officer.stun,"index":officer.index})
	return {"officers":officers,"arrest_seconds":arrest_seconds,"escape_seconds":escape_seconds,"crime_age":crime_age,"crime_position":[crime_position.x,crime_position.y,crime_position.z]}

func restore_pursuit_state(state: Dictionary) -> void:
	var officers: Array = state.get("officers",[])
	if officers.size()!=police.size(): return
	for index in police.size():
		var saved: Dictionary = officers[index]
		var at: Array = saved.position
		police[index].node.position = Vector3(float(at[0]),float(at[1]),float(at[2]))
		police[index].hp = float(saved.hp)
		police[index].alert = float(saved.alert)
		police[index].stun = float(saved.stun)
		police[index].index = int(saved.index)%police[index].route.size()
	arrest_seconds = float(state.get("arrest_seconds",0.0))
	escape_seconds = float(state.get("escape_seconds",0.0))
	crime_age = float(state.get("crime_age",1000.0))
	var at: Array = state.get("crime_position",[0.0,0.0,0.0])
	crime_position = Vector3(float(at[0]),float(at[1]),float(at[2]))

func attack(kind: String) -> void:
	if Game.status != "playing" or kind not in ["shoot","punch","kick"]: return
	var reach := 22.0 if kind=="shoot" else (2.4 if kind=="kick" else 1.9)
	var damage := 60.0 if kind=="shoot" else (32.0 if kind=="kick" else 22.0)
	var victim: Dictionary = {}
	var best := reach
	for actor: Dictionary in citizens+police:
		if float(actor.hp)<=0.0: continue
		var relative: Vector3 = actor.node.position-player.position
		var distance := relative.length()
		if distance<best and relative.normalized().dot(player.facing)>0.30 and _line_of_sight(player.position,actor.node.position):
			victim = actor
			best = distance
	# Gunfire was reported by Game.use_ammo(). Only an actual melee hit is a crime.
	if not victim.is_empty():
		if kind!="shoot": Game.report_crime(28.0)
		victim.hp = maxf(0.0,float(victim.hp)-damage)
		victim.stun = 0.65
		if victim.has("panic"): victim.panic = 8.0
		if float(victim.hp)<=0.0: victim.node.collision_layer = 0
		ActorVisuals.play(victim.node,"die" if float(victim.hp)<=0.0 else "emote-no",false)
		var text := ActorVisuals.label("-%d"%int(damage),Color("ff927d"),32)
		text.position = victim.node.position+Vector3(0,2.6,0)
		add_child(text)
		var tween := create_tween()
		tween.tween_property(text,"position:y",text.position.y+1.2,0.8)
		tween.tween_callback(text.queue_free)
	if kind=="shoot":
		var flash := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.16
		mesh.height = 0.32
		flash.mesh = mesh
		flash.material_override = ActorVisuals.material(Color("ffe3a0"),true)
		flash.position = player.position+player.facing+Vector3.UP
		add_child(flash)
		get_tree().create_timer(0.08).timeout.connect(flash.queue_free)
		var trace := MeshInstance3D.new()
		var line := ImmediateMesh.new()
		line.surface_begin(Mesh.PRIMITIVE_LINES,ActorVisuals.material(Color("ffd99a"),true))
		line.surface_add_vertex(player.position+Vector3.UP+player.facing)
		line.surface_add_vertex(player.position+Vector3.UP+player.facing*best)
		line.surface_end()
		trace.mesh = line
		add_child(trace)
		get_tree().create_timer(0.10).timeout.connect(trace.queue_free)

func _sync_meetings() -> void:
	if not world: return
	var live: Array[String] = []
	for meeting: Dictionary in Game.meetings:
		if meeting.status!="scheduled": continue
		var id := str(int(meeting.id))
		live.append(id)
		if meeting_actors.has(id):
			var existing: Dictionary = meeting_walks[id]
			if Game.minute-float(existing.last_minute)>6.0:
				_fast_forward_offscreen(existing,Game.minute-float(existing.last_minute))
			existing.last_minute = Game.minute
			continue
		if Game.minute<float(meeting.due_minute)-90.0 or not world.landmarks.has(meeting.location_id): continue
		var landmark: Vector3 = world.landmarks[meeting.location_id].position
		var cell := _nearest_open_cell(landmark+Vector3(2.2,0,1.8))
		var target := Vector3(cell.x*NAV_CELL,0.2,cell.y*NAV_CELL)
		var start := _offscreen_walk_point(target)
		if not start.is_finite(): continue
		var actor := _person("character-male-e" if meeting.type=="supplier" else "character-female-b",1.8)
		actor.position = start
		var tag := ActorVisuals.label(str(meeting.contact_name).to_upper(),Color("edc37e"),22)
		tag.position.y = 2.5
		actor.add_child(tag)
		actor.add_child(ActorVisuals.ground_ring(Color("edc37e"),0.7))
		actor.visible = player.position.x<400.0
		actor.collision_layer = PERSON_LAYER if actor.visible else 0
		var path := _walking_path(start,target)
		var distance := _path_distance(start,path,0,target)
		meeting_actors[id] = actor
		meeting_walks[id] = {"node":actor,"hp":100.0,"state":"approaching","target":target,"due":float(meeting.due_minute),"start_minute":float(meeting.due_minute)-Game.MEETING_ARRIVAL_MINUTES-distance/1.9*3.0,"last_minute":Game.minute,"nav_path":path,"nav_index":0,"nav_target":target,"nav_timer":2.0}
	for id: String in meeting_walks.keys():
		if live.has(id): continue
		var record: Dictionary = meeting_walks[id]
		if record.state=="departing": continue
		if _point_offscreen(record.node.position):
			_remove_meeting_actor(id)
			continue
		var exit := _offscreen_walk_point(record.node.position)
		if not exit.is_finite(): continue
		record.state = "departing"
		record.target = exit
		record.nav_path = _walking_path(record.node.position,exit)
		record.nav_index = 0
		record.nav_target = exit
		record.nav_timer = 2.0

func _update_meeting_walks(delta: float, indoor: bool) -> void:
	for id: String in meeting_walks.keys():
		var record: Dictionary = meeting_walks[id]
		var actor: CharacterBody3D = record.node
		_ground_person(actor)
		_set_person_visible(actor,not indoor)
		actor.collision_layer = PERSON_LAYER if actor.visible else 0
		if record.state=="departing":
			if _point_offscreen(actor.position):
				_remove_meeting_actor(id)
				continue
			_move_person(record,record.target,2.0,delta)
			continue
		if record.state=="waiting":
			ActorVisuals.play(actor,"idle")
			continue
		if Game.minute<float(record.start_minute): continue
		var remaining := _horizontal_distance(actor.position,record.target) if _line_of_sight(actor.position,record.target) else _path_distance(actor.position,record.nav_path,int(record.nav_index),record.target)
		var seconds_left := maxf(0.1,(float(record.due)-Game.MEETING_ARRIVAL_MINUTES-Game.minute)/3.0)
		var speed := clampf(remaining/seconds_left,1.2,5.8)
		if _horizontal_distance(actor.position,record.target)<0.85:
			if Game.minute>=float(record.due)-Game.MEETING_ARRIVAL_MINUTES:
				record.state = "waiting"
				ActorVisuals.play(actor,"idle")
			continue
		_move_person(record,record.target,speed,delta)

func _point_offscreen(at: Vector3) -> bool:
	if not player.camera or not player.camera.is_inside_tree():
		return _horizontal_distance(player.position,at)>46.0
	var camera := player.camera
	if camera.is_position_behind(at): return true
	# Margin includes the character and overhead name, so neither can pop into view.
	var screen := camera.get_viewport().get_visible_rect().grow(70.0)
	return not screen.has_point(camera.unproject_position(at+Vector3.UP*1.6))

func _offscreen_walk_point(target: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_distance := INF
	for radius: float in [18.0,28.0,40.0,56.0,76.0,100.0]:
		for index in range(16):
			var angle := TAU*float(index)/16.0
			var candidate := target+Vector3(cos(angle),0,sin(angle))*radius
			if absf(candidate.x)>146.0 or absf(candidate.z)>116.0: continue
			var cell := _nearest_open_cell(candidate)
			candidate = Vector3(cell.x*NAV_CELL,0.2,cell.y*NAV_CELL)
			if not _point_offscreen(candidate): continue
			var path := _walking_path(candidate,target)
			if path.is_empty(): continue
			var distance := _path_distance(candidate,path,0,target)
			if distance<best_distance:
				best_distance = distance
				best = candidate
		if best.is_finite(): break
	return best

func _walking_path(start: Vector3, target: Vector3) -> PackedVector3Array:
	var points := navigation.get_point_path(_nearest_open_cell(start),_nearest_open_cell(target))
	var result := PackedVector3Array()
	for point: Vector2 in points: result.append(Vector3(point.x,0.2,point.y))
	return result

func _path_distance(start: Vector3, path: PackedVector3Array, from_index: int, target: Vector3) -> float:
	var distance := 0.0
	var previous := start
	for index in range(from_index,path.size()):
		distance += _horizontal_distance(previous,path[index])
		previous = path[index]
	return distance+_horizontal_distance(previous,target)

func _fast_forward_offscreen(record: Dictionary, minutes: float) -> void:
	# Agenda waiting and loading may jump the clock. Advance only through unseen
	# space, then let the client visibly walk in through the edge of the camera.
	if record.state!="approaching" or not _point_offscreen(record.node.position): return
	var allowance := minutes/3.0*2.1
	var path := _walking_path(record.node.position,record.target)
	for point: Vector3 in path:
		if not _point_offscreen(point): break
		var distance := _horizontal_distance(record.node.position,point)
		if distance>allowance: break
		record.node.position = point
		allowance -= distance
	record.nav_path = _walking_path(record.node.position,record.target)
	record.nav_index = 0
	if _horizontal_distance(record.node.position,record.target)<0.85 and Game.minute>=float(record.due)-Game.MEETING_ARRIVAL_MINUTES:
		record.state = "waiting"

func _remove_meeting_actor(id: String) -> void:
	var actor: Node3D = meeting_actors[id]
	for record: Dictionary in _pedestrian_neighbors:
		if record.has("neighbors"): record.neighbors.erase(actor)
	_grounding_cache.erase(actor.get_instance_id())
	meeting_actors[id].queue_free()
	meeting_actors.erase(id)
	meeting_walks.erase(id)

func _sample_route(route: PackedVector3Array, fraction: float) -> Dictionary:
	var length := 0.0
	for index in route.size(): length += route[index].distance_to(route[(index+1)%route.size()])
	var distance := fposmod(fraction,1.0)*length
	for index in route.size():
		var next := (index+1)%route.size()
		var segment := route[index].distance_to(route[next])
		if distance<=segment: return {"position":route[index].lerp(route[next],distance/maxf(segment,0.001)),"index":next}
		distance -= segment
	return {"position":route[0],"index":1}

func _horizontal_distance(a: Vector3,b: Vector3) -> float:
	return Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))

func _heading(direction: Vector3) -> float:
	return atan2(direction.x,direction.z)

func _model_in_camera_view(actor: Node3D) -> bool:
	if not player.camera or not player.camera.is_inside_tree(): return true
	var camera := player.camera
	var at := actor.global_position+Vector3.UP
	if camera.is_position_behind(at): return false
	# Extra room covers fast camera travel between five-Hz checks. Only skeletal
	# animation sleeps; bodies keep their routes, collision, visibility and labels.
	return camera.get_viewport().get_visible_rect().grow(120.0).has_point(camera.unproject_position(at))

func _update_animation_lod() -> void:
	for record: Dictionary in citizens+police:
		_set_model_animation_active(record.node)
	for actor: Node3D in meeting_actors.values(): _set_model_animation_active(actor)
	if is_instance_valid(friend): _set_model_animation_active(friend)

func _set_model_animation_active(actor: Node3D) -> void:
	var model: Node = actor.get_meta("model",null)
	if not model: return
	var wanted := Node.PROCESS_MODE_INHERIT if actor.visible and _model_in_camera_view(actor) else Node.PROCESS_MODE_DISABLED
	if model.process_mode!=wanted: model.process_mode = wanted

func _set_person_visible(actor: Node3D, show_actor: bool) -> void:
	if actor.visible==show_actor: return
	actor.visible = show_actor
	var model: Node = actor.get_meta("model",null)
	if model:
		model.process_mode = Node.PROCESS_MODE_INHERIT if show_actor and _model_in_camera_view(actor) else Node.PROCESS_MODE_DISABLED
