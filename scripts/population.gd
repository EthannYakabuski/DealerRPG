class_name CityPopulation
extends Node3D

signal informant_reported(npc_id: String)

const PERSON_LAYER: int = 4
const VEHICLE_LAYER: int = 8
const NAV_CELL: float = 2.0
const BASE_POLICE_COUNT := 10
const CITIZEN_COUNT := 57
const Trips = preload("res://scripts/city_car_trips.gd")
const Emotes = preload("res://scripts/npc_emote.gd")
const GROUP_SPACING: float = 1.75
const PEDESTRIAN_CLEARANCE: float = 1.5
const POLICE_CLOSE_AWARENESS: float = 6.0
const POLICE_VIEW_COSINE: float = -0.342020143 # cos(110 degrees): a 220-degree forward cone.
const CRUISER_PURSUIT_TIER := 20.0
const POLICE_FIREARMS_TIER := 25.0
const POLICE_MELEE_STUN := 1.0
var world: Node3D
var player: StudentPlayer
var citizens: Array[Dictionary] = []
var vehicles: Array[Dictionary] = []
var police: Array[Dictionary] = []
var meeting_actors: Dictionary = {}
var meeting_walks: Dictionary = {}
var social_actor_providers: Array[Node] = []
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
var _active_conversation := ""
var _citizens_by_id: Dictionary = {}
var _activity_plans: Dictionary = {}
var _last_routine_phase := ""
var _activity_timer := 0.0
var car_trips: RefCounted
var _pressure_timer := 0.0
var _cruiser_roads := AStar3D.new()
var _cruiser_road_edges: Array[Vector2i] = []
var _cruiser_road_keys: Dictionary = {}

func setup(city: Node3D, student: StudentPlayer) -> void:
	world = city
	player = student
	player.city_world = world
	rng.seed = 87261
	_build_navigation()
	_build_cruiser_roads()
	var routes: Array = world.pedestrian_routes
	for index in range(CITIZEN_COUNT):
		if routes.is_empty(): break
		var cohort: int = index / 3
		var solo := index%9>=3
		var group_id: int = 100+index if solo else cohort
		var route: PackedVector3Array = routes[cohort % routes.size()] if index<42 else world.outskirts_routes[(index-42)/3]
		if route.size() < 2: continue
		var names := ["character-female-a","character-male-d","character-female-e","character-male-b","character-female-f","character-male-e"]
		var actor := _person(names[index % names.size()],1.7+rng.randf_range(-0.08,0.14))
		var spawn: Dictionary = _sample_route(route,fmod(0.12+float(cohort / routes.size())/3.0+(float(index%3)*0.23 if solo else 0.0),0.96))
		var offset := Vector3.ZERO if solo else Vector3(float(index%3-1)*GROUP_SPACING,0,float(index%2)*1.1)
		actor.position = _safe_pedestrian_target(spawn.position + offset)
		citizens.append({"node":actor,"route":route,"index":spawn.index,"speed":1.2+float(group_id%3)*0.12,"hp":100.0,"panic":0.0,"stun":0.0,"wait":float(group_id%3),"goal":"Heading to class","group":group_id,"offset":offset,"nav_path":PackedVector3Array(),"nav_index":0,"nav_target":Vector3.INF,"nav_timer":0.0,"dead_seconds":0.0})
		var identity := "citizen_%02d"%index
		var citizen: Dictionary = citizens.back()
		citizen.id = identity
		citizen.solo = solo
		citizen.routine_zone = cohort%5 if index<42 else 5+(index-42)/3
		citizen.activity_arrived = false
		citizen.activity_id = ""
		citizen.name = _civilian_name(index)
		citizen.conversation = false
		citizen.reporting = false
		citizen.reported = false
		citizen.report_retry = 0.0
		_citizens_by_id[identity] = citizen
		if not _activity_plans.has(group_id): _activity_plans[group_id] = {"members":[],"zone":citizen.routine_zone,"serial":0,"last":"","previous":"","remaining":0.0}
		_activity_plans[group_id].members.append(identity)
	for index in range(BASE_POLICE_COUNT):
		var campus := index < 4 or index in [7,9]
		var patrols: Array = world.campus_police_routes if campus else world.city_police_routes
		if patrols.is_empty(): continue
		var route: PackedVector3Array = patrols[index%(3 if campus else 2)] if index<7 else (world.campus_police_routes[3] if index==7 else (world.city_police_routes[2] if index==8 else world.campus_police_routes[4]))
		if index==6: route = world.city_police_routes[4]
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
		vehicles.append({"node":body,"route":PackedVector3Array(),"index":0,"speed":0.0,"parked":true,"stolen":false,"occupied":false,"wait":0.0,"stuck":0.0,"lot":int(spawn.get("lot",-1)),"police":str(spawn.get("model",""))=="police"})
	car_trips = Trips.new()
	car_trips.setup(self)
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
	_citizens_by_id.clear()
	_activity_plans.clear()
	_last_routine_phase = ""
	_activity_timer = 0.0
	_active_conversation = ""
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
	_pressure_timer = 0.0
	car_trips = null
	player.reset_travel()
	setup(world,player)

func _person(asset: String, height: float) -> CharacterBody3D:
	var person := CharacterBody3D.new()
	person.set_meta("asset",asset)
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
			if child is Node3D and not child is CollisionShape3D and child.name!="NPCEmote":
				parts.append({"node":child,"base_y":child.position.y})
		cached = {"parts":parts}
		_grounding_cache[id] = cached
	var support: float = world.walkable_support_height(at,0.24)
	var lift := support-at.y
	for part: Dictionary in cached.parts:
		if is_instance_valid(part.node): part.node.position.y = float(part.base_y)+lift
	var bubble := actor.get_node_or_null("NPCEmote")
	if bubble: bubble.position.y = 3.25+lift
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
	body.set_meta("asset",asset)
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
	_pressure_timer -= delta
	if _pressure_timer<=0.0:
		_sync_pressure_patrols()
		_pressure_timer = 2.0
	if car_trips: car_trips.update(delta)
	_activity_timer += delta
	if _activity_timer>=0.25:
		_update_activity_plans(_activity_timer)
		_activity_timer = 0.0
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
	if bool(citizen.get("party_guest",false)): return
	var actor: CharacterBody3D = citizen.node
	_ground_person(actor)
	if float(citizen.hp) <= 0.0:
		citizen.dead_seconds += delta
		actor.visible = not indoor and float(citizen.dead_seconds) < 25.0
		actor.collision_layer = 0
		return
	if citizen.get("car_trip","")=="driving":
		_set_person_visible(actor,false)
		actor.collision_layer = 0
		return
	_set_person_visible(actor,not indoor and actor.position.distance_squared_to(player.position) < 8100.0)
	actor.collision_layer = PERSON_LAYER if actor.visible else 0
	if bool(citizen.get("reporting",false)):
		_update_informant(citizen,delta)
		return
	if citizen.get("car_trip","")=="walking_to_car":
		car_trips.walk_to_car(citizen,delta)
		return
	if not actor.visible: return
	if citizen.has("name_label"):
		citizen.name_label.visible = bool(citizen.get("conversation",false)) or actor.position.distance_squared_to(player.position)<64.0
	if bool(citizen.get("conversation",false)):
		actor.velocity = Vector3.ZERO
		ActorVisuals.play(actor,"idle")
		return
	if float(citizen.stun) > 0.0:
		citizen.stun = maxf(0.0,float(citizen.stun)-delta)
		return
	if float(citizen.panic) > 0.0:
		citizen.panic = maxf(0.0,float(citizen.panic)-delta)
		var away: Vector3 = actor.position-Vector3(citizen.get("panic_source",crime_position))
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
	if bool(citizen.get("activity_arrived",false)):
		_settle_idle_spacing(citizen,delta)
		ActorVisuals.play(actor,"idle")
		return
	var target: Vector3 = citizen.walk_target
	if _horizontal_distance(actor.position,target)<1.2:
		citizen.activity_arrived = true
		citizen.goal = world.pedestrian_activities[citizen.activity_id].stay
		ActorVisuals.play(actor,"idle")
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
	var phase: String = Game.current_phase()
	if phase==_last_routine_phase: return
	_last_routine_phase = phase
	for group_id: int in _activity_plans: _choose_activity(group_id)

func _update_activity_plans(delta: float) -> void:
	for group_id: int in _activity_plans:
		var plan: Dictionary = _activity_plans[group_id]
		var present := 0
		var arrived := 0
		for id: String in plan.members:
			var citizen: Dictionary = _citizens_by_id[id]
			if float(citizen.hp)<=0.0 or citizen.reporting or citizen.get("party_guest",false) or citizen.get("car_trip","")!="": continue
			present += 1
			if citizen.activity_arrived: arrived += 1
		if present==0 or arrived<present: continue
		plan.remaining = maxf(0.0,float(plan.remaining)-delta)
		if float(plan.remaining)<=0.0: _choose_activity(group_id)

func _choose_activity(group_id: int) -> void:
	var plan: Dictionary = _activity_plans[group_id]
	var options: Array = world.pedestrian_itineraries[int(plan.zone)]
	var choices: Array[String] = []
	var night := Game.current_phase() in ["Evening","Dusk","Night"]
	for id: String in options:
		if id==str(plan.last) or id==str(plan.previous): continue
		if night and str(world.pedestrian_activities[id].kind)=="study": continue
		choices.append(id)
	if choices.is_empty():
		for id: String in options:
			if id!=str(plan.last) and (not night or str(world.pedestrian_activities[id].kind)!="study"): choices.append(id)
	var chosen: String = choices[posmod(group_id*31+int(plan.serial)*17+(7 if night else 0),choices.size())]
	plan.previous = plan.last
	plan.last = chosen
	plan.serial = int(plan.serial)+1
	plan.remaining = 18.0+float(posmod(group_id*7+int(plan.serial)*11,23))+(14.0 if night else 0.0)
	var activity: Dictionary = world.pedestrian_activities[chosen]
	for id: String in plan.members:
		var citizen: Dictionary = _citizens_by_id[id]
		citizen.activity_id = chosen
		citizen.activity_arrived = false
		citizen.walk_target = _safe_pedestrian_target(Vector3(activity.position)+Vector3(citizen.offset))
		citizen.goal = str(activity.travel)
		citizen.nav_path = PackedVector3Array()
		citizen.nav_index = 0
		citizen.nav_target = Vector3.INF

func _update_traffic(delta: float, indoor: bool) -> void:
	# Only vehicles whose actual lane corridor intersects ours cause a queue.
	# The previous broad cone also stopped for oncoming and parked cars beside roads.
	for car: Dictionary in vehicles:
		var actor: AnimatableBody3D = car.node
		actor.visible = not indoor
		if car.occupied or car.parked: continue
		if bool(car.get("awaiting_parking",false)): continue
		var route: PackedVector3Array = car.route
		if route.size() < 2: continue
		var target: Vector3 = route[int(car.index)]
		var distance := _horizontal_distance(actor.position,target)
		if distance < 0.35:
			if bool(car.get("chasing",false)) and int(car.index)==route.size()-1:
				car.current_speed = 0.0
				continue
			if bool(car.get("rejoining",false)) and int(car.index)==route.size()-1:
				car.route = car.patrol_route
				car.index = int(car.get("patrol_index",0))
				car.rejoining = false
				car.awaiting_parking = false
				if bool(car.get("patrol_parked",false)):
					car.parked = true
					car.speed = 0.0
					car.reserved_parking_id = -1
					actor.rotation.y = float(car.patrol_rotation)
				continue
			car.index = (int(car.index)+1)%route.size()
			target = route[int(car.index)]
			distance = _horizontal_distance(actor.position,target)
		var direction: Vector3 = (target-actor.position).normalized()
		var speed: float = car.speed
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
		var wanted := actor.position+direction*advance
		if advance>0.001:
			advance *= minf(world.vehicle_motion_fraction(actor.position,wanted),_driving_player_motion_fraction(actor.position,wanted))
		var next_heading := lerp_angle(actor.rotation.y,_heading(direction),minf(1.0,delta*6.0))
		if not world.vehicle_pose_clear(actor.position+direction*advance,next_heading,1.05,2.1):
			advance = 0.0
			if not world.vehicle_pose_clear(actor.position,next_heading,1.05,2.1): next_heading = actor.rotation.y
		car.current_speed = advance/maxf(delta,0.001)
		car.distance_travelled = float(car.get("distance_travelled",0.0))+advance
		var previous_position := actor.position
		actor.position += direction*advance
		if not indoor and not player.vehicle and advance>0.001:
			_apply_traffic_impact(actor,previous_position,direction*(advance/maxf(delta,0.001)))
		actor.rotation.y = next_heading

func _driving_player_motion_fraction(from: Vector3, to: Vector3) -> float:
	if not is_instance_valid(player.vehicle): return 1.0
	# An AnimatableBody moved into the driven player's capsule can force physics
	# recovery sideways into a wall. Stop the AI bumper before that overlap.
	var motion := to-from
	if motion.length_squared()<0.000001: return 1.0
	var inverse := player.vehicle.global_basis.orthonormalized().inverse()
	var heading := inverse*motion.normalized()
	var width := 1.05+absf(heading.z)*1.05+absf(heading.x)*2.1
	var length := 2.1+absf(heading.z)*2.1+absf(heading.x)*1.05
	var body := AABB(Vector3(-width,-3.0,-length),Vector3(width*2.0,6.0,length*2.0))
	var start := inverse*(from-player.global_position)
	var finish := inverse*(to-player.global_position)
	if body.has_point(start):
		# Allow a car already overlapping because the student drove into it to
		# separate naturally, but never advance deeper into the occupied vehicle.
		return 1.0 if finish.length_squared()>start.length_squared() else 0.0
	var hit: Variant = body.intersects_segment(start,finish)
	if hit==null: return 1.0
	return clampf(start.distance_to(hit)/motion.length()-0.02,0.0,1.0)

func _apply_traffic_impact(car: Node3D, previous_position: Vector3, velocity: Vector3) -> void:
	if player.vehicle or Game.status!="playing" or not player.has_method("receive_vehicle_impact"): return
	var student_at := player.global_position
	var swept_from := previous_position
	var swept_to := car.global_position
	if student_at.x<minf(swept_from.x,swept_to.x)-6.0 or student_at.x>maxf(swept_from.x,swept_to.x)+6.0 or student_at.z<minf(swept_from.z,swept_to.z)-6.0 or student_at.z>maxf(swept_from.z,swept_to.z)+6.0: return
	# Sweep the moving collision box expanded by the student's capsule. This
	# catches a fast front bumper crossing between ticks, including on a board.
	var inverse := car.global_basis.orthonormalized().inverse()
	var relative_from := inverse*(player.global_position-previous_position)
	var relative_to := inverse*(player.global_position-car.global_position)
	var body := AABB(Vector3(-1.30,-0.5,-2.4),Vector3(2.60,3.0,4.8))
	if body.intersects_segment(relative_from,relative_to)!=null:
		player.call("receive_vehicle_impact",velocity,car)

func _traffic_crossing(a: Vector3, direction: Vector3, b: Vector3, other_direction: Vector3) -> Vector2:
	var divisor := direction.x*other_direction.z-direction.z*other_direction.x
	if absf(divisor)<0.06: return Vector2.INF
	var between := b-a
	return Vector2((between.x*other_direction.z-between.z*other_direction.x)/divisor,(between.x*direction.z-between.z*direction.x)/divisor)

func _build_cruiser_roads() -> void:
	# Build once from the same road geometry that is rendered. Junction splits
	# include branch endpoints lying partway along another road segment.
	_cruiser_roads.clear()
	_cruiser_road_edges.clear()
	_cruiser_road_keys.clear()
	var segments: Array[Dictionary] = []
	var bridges: Array[PackedVector3Array] = []
	for road: PackedVector3Array in world.map_roads:
		for index in road.size()-1:
			segments.append({"a":road[index],"b":road[index+1],"cuts":[0.0,1.0]})
	for index in segments.size():
		var a: Dictionary = segments[index]
		for other in range(index+1,segments.size()):
			var b: Dictionary = segments[other]
			var crossing := _traffic_crossing(a.a,a.b-a.a,b.a,b.b-b.a)
			if crossing.is_finite() and crossing.x>=0.0 and crossing.x<=1.0 and crossing.y>=0.0 and crossing.y<=1.0:
				a.cuts.append(crossing.x)
				b.cuts.append(crossing.y)
			for pair: Array in [[a,b],[b,a]]:
				for endpoint: Vector3 in [pair[0].a,pair[0].b]:
					var near := Geometry3D.get_closest_point_to_segment(endpoint,pair[1].a,pair[1].b)
					if endpoint.distance_squared_to(near)>2.25: continue
					pair[1].cuts.append(Vector3(pair[1].a).distance_to(near)/Vector3(pair[1].a).distance_to(pair[1].b))
					bridges.append(PackedVector3Array([endpoint,near]))
	for segment: Dictionary in segments:
		segment.cuts.sort()
		for index in segment.cuts.size()-1:
			_cruiser_road_edge(Vector3(segment.a).lerp(segment.b,float(segment.cuts[index])),Vector3(segment.a).lerp(segment.b,float(segment.cuts[index+1])))
	for bridge: PackedVector3Array in bridges: _cruiser_road_edge(bridge[0],bridge[1])

func _cruiser_road_id(at: Vector3) -> int:
	var key := Vector2i(roundi(at.x*100.0),roundi(at.z*100.0))
	if _cruiser_road_keys.has(key): return int(_cruiser_road_keys[key])
	var id := _cruiser_roads.get_available_point_id()
	_cruiser_roads.add_point(id,Vector3(float(key.x)/100.0,0,float(key.y)/100.0))
	_cruiser_road_keys[key] = id
	return id

func _cruiser_road_edge(a: Vector3, b: Vector3) -> void:
	var first := _cruiser_road_id(a)
	var last := _cruiser_road_id(b)
	if first==last or _cruiser_roads.are_points_connected(first,last): return
	_cruiser_roads.connect_points(first,last)
	_cruiser_road_edges.append(Vector2i(first,last))

func _nearest_cruiser_road(at: Vector3) -> Dictionary:
	var result: Dictionary = {}
	var best := INF
	for edge: Vector2i in _cruiser_road_edges:
		var near := Geometry3D.get_closest_point_to_segment(at,_cruiser_roads.get_point_position(edge.x),_cruiser_roads.get_point_position(edge.y))
		var distance := at.distance_squared_to(near)
		if distance<best:
			best = distance
			result = {"point":near,"edge":edge}
	return result

func _cruiser_route_to(from: Vector3, target: Vector3) -> PackedVector3Array:
	var start := _nearest_cruiser_road(from)
	var finish := _nearest_cruiser_road(target)
	if start.is_empty() or finish.is_empty(): return PackedVector3Array()
	var start_id := _cruiser_roads.get_available_point_id()
	_cruiser_roads.add_point(start_id,start.point)
	var finish_id := _cruiser_roads.get_available_point_id()
	_cruiser_roads.add_point(finish_id,finish.point)
	for id: int in [start.edge.x,start.edge.y]: _cruiser_roads.connect_points(start_id,id)
	for id: int in [finish.edge.x,finish.edge.y]: _cruiser_roads.connect_points(finish_id,id)
	if start.edge==finish.edge: _cruiser_roads.connect_points(start_id,finish_id)
	var points := _cruiser_roads.get_point_path(start_id,finish_id)
	_cruiser_roads.remove_point(start_id)
	_cruiser_roads.remove_point(finish_id)
	var centers := PackedVector3Array()
	for point: Vector3 in points:
		if centers.is_empty() or point.distance_squared_to(centers[-1])>0.04: centers.append(point)
	if centers.size()<2: return PackedVector3Array()
	var route := PackedVector3Array([from])
	for index in centers.size():
		var incoming := (centers[index]-centers[maxi(0,index-1)]).normalized()
		var outgoing := (centers[mini(centers.size()-1,index+1)]-centers[index]).normalized()
		if incoming.length_squared()<0.1: incoming = outgoing
		if outgoing.length_squared()<0.1: outgoing = incoming
		var tangent := (incoming+outgoing).normalized()
		var side := Vector3(-tangent.z,0,tangent.x)
		var offset := 1.35/maxf(0.65,side.dot(Vector3(-outgoing.z,0,outgoing.x)))
		var lane := centers[index]+side*offset+Vector3.UP*0.16
		if route[-1].distance_squared_to(lane)>0.16: route.append(lane)
	return route

func _update_cruiser_routes(delta: float, indoor: bool) -> void:
	var chase := pursuit and not indoor and Game.escape_duration_seconds()>=CRUISER_PURSUIT_TIER and not _is_campus(crime_position)
	for car: Dictionary in vehicles:
		if not bool(car.get("police",false)) or car.occupied or car.stolen: continue
		if chase:
			if not bool(car.get("chasing",false)):
				if not car.has("patrol_route"):
					car.patrol_route = car.route.duplicate()
					car.patrol_speed = car.speed
					car.patrol_parked = car.parked
					car.patrol_origin = car.node.position
					car.patrol_rotation = car.node.rotation.y
				car.chasing = true
				car.rejoining = false
				car.awaiting_parking = false
				car.chase_replan = 0.0
				car.chase_departure = car_trips.parking_departure(car) if car.parked or bool(car.get("patrol_parked",false)) else PackedVector3Array()
				car.chase_merge_index = 0
				car.parked = false
				_emote(car.node,"alert")
			car.chase_replan = float(car.get("chase_replan",0.0))-delta
			if int(car.get("chase_merge_index",0))>0:
				if int(car.index)<=int(car.chase_merge_index):
					car.speed = 3.5
					continue
				car.chase_merge_index = 0
			if float(car.chase_replan)<=0.0:
				car.chase_replan = 1.5
				var departure: PackedVector3Array = car.get("chase_departure",PackedVector3Array())
				var route := _cruiser_route_to(car.node.position if departure.is_empty() else departure[-1],crime_position)
				if not departure.is_empty():
					car.chase_merge_index = departure.size()-1
					departure.append_array(route.slice(1))
					route = departure
					car.chase_departure = PackedVector3Array()
				if route.size()>1:
					car.route = route
					car.index = 1
			car.speed = 13.5
		elif bool(car.get("chasing",false)) or bool(car.get("awaiting_parking",false)):
			if bool(car.get("awaiting_parking",false)):
				car.return_retry = float(car.get("return_retry",0.0))-delta
				if float(car.return_retry)>0.0: continue
			car.chasing = false
			car.speed = float(car.get("patrol_speed",7.0))
			if bool(car.get("patrol_parked",false)):
				var parking: Dictionary = car_trips.parking_return(car,car.patrol_origin)
				if parking.is_empty():
					car.speed = 0.0
					car.awaiting_parking = true
					car.return_retry = 2.0
					continue
				car.awaiting_parking = false
				var access: PackedVector3Array = parking.path
				var route := _cruiser_route_to(car.node.position,access[0])
				if route.is_empty(): route = PackedVector3Array([car.node.position])
				route.append_array(access)
				car.route = route
				car.index = 1
				car.rejoining = true
				car.patrol_rotation = float(parking.slot.rotation)
				car.speed = 5.0
				continue
			var patrol: PackedVector3Array = car.patrol_route
			var nearest := INF
			var join := Vector3.ZERO
			for index in patrol.size():
				var point := Geometry3D.get_closest_point_to_segment(car.node.position,patrol[index],patrol[(index+1)%patrol.size()])
				if car.node.position.distance_squared_to(point)<nearest:
					nearest = car.node.position.distance_squared_to(point)
					join = point
					car.patrol_index = (index+1)%patrol.size()
			var route := _cruiser_route_to(car.node.position,join)
			if route.size()>1:
				route.append(join)
				car.route = route
				car.index = 1
				car.rejoining = true
			else:
				car.route = patrol
				car.index = int(car.get("patrol_index",0))

func _update_police(delta: float, indoor: bool) -> void:
	var seen := false
	var closest := INF
	var player_on_campus := _is_campus(player.position)
	var road_skating: bool = not indoor and player.skateboarding and not player.vehicle and world.is_road_skating_violation(player.global_position)
	if not indoor and not player_on_campus and _cruiser_sees_player():
		if road_skating and not pursuit:
			crime_position = player.position
			_begin_pursuit("ROAD SKATING SPOTTED — the road patrol called it in.")
			_alert_city_officers()
		if stolen_vehicle and player.vehicle and not pursuit:
			crime_position = player.position
			_begin_pursuit("STOLEN VEHICLE IDENTIFIED — a road patrol called it in.")
			_alert_city_officers()
		if pursuit:
			seen = true
			for car: Dictionary in vehicles:
				if _active_cruiser(car) and _police_can_see(car.node,player.global_position,28.0):
					closest = minf(closest,maxf(0.0,_horizontal_distance(car.node.position,player.position)-1.2))
	for officer: Dictionary in police:
		var actor: CharacterBody3D = officer.node
		_ground_person(actor)
		actor.visible = not indoor
		actor.collision_layer = PERSON_LAYER if actor.visible and float(officer.hp)>0.0 else 0
		if float(officer.hp) <= 0.0: continue
		if bool(officer.get("retiring",false)):
			if officer.get("retire_target",Vector3.INF).is_finite(): _move_person(officer,officer.retire_target,2.3,delta)
			continue
		if float(officer.stun) > 0.0:
			officer.stun = maxf(0.0,float(officer.stun)-delta)
			officer.aim_seconds = 0.0
			actor.velocity = Vector3.ZERO
			continue
		officer.shot_cooldown = maxf(0.0,float(officer.get("shot_cooldown",0.0))-delta)
		var distance := _horizontal_distance(actor.position,player.position)
		var jurisdiction := bool(officer.campus) == player_on_campus
		var can_see := not indoor and jurisdiction and _police_can_see(actor,player.global_position,28.0 if pursuit else 19.0)
		if stolen_vehicle and player.vehicle and can_see and not pursuit:
			crime_position = player.position
			_begin_pursuit("STOLEN VEHICLE IDENTIFIED — break line of sight to escape.")
			officer.alert = 12.0
			crime_position = player.position
		if can_see and pursuit:
			seen = true
			closest = minf(closest,distance)
			officer.alert = 10.0
		# A reported location remains worth inspecting after the student has
		# crossed a district boundary; actual sight/arrest still respects jurisdiction.
		var investigating_home_district := _is_campus(crime_position)==bool(officer.campus)
		if pursuit and float(officer.alert)>0.0 and (jurisdiction or investigating_home_district):
			officer.alert = maxf(0.0,float(officer.alert)-delta)
			var target: Vector3 = player.position if can_see else crime_position
			_move_person(officer,target,6.3,delta)
		else:
			var route: PackedVector3Array = officer.route
			var target: Vector3 = route[int(officer.index)]
			if _horizontal_distance(actor.position,target)<1.3: officer.index = (int(officer.index)+1)%route.size()
			_move_person(officer,target,1.8,delta)
		_update_police_fire(officer,delta,can_see,distance)
	_update_cruiser_routes(delta,indoor)
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
	if escape_seconds >= Game.escape_duration_seconds():
		pursuit = false
		Game.end_pursuit()
		arrest_seconds = 0.0
		for officer: Dictionary in police: officer.alert = 0.0
		Game.set_heat(maxf(0.0,Game.heat-30.0))
		Game.notification.emit("You lost the patrol. Keep a low profile.")

func _cruiser_sees_player() -> bool:
	for car: Dictionary in vehicles:
		if not _active_cruiser(car): continue
		if _police_can_see(car.node,player.global_position,28.0 if pursuit else 19.0): return true
	return false

func _active_cruiser(car: Dictionary) -> bool:
	return bool(car.get("police",false)) and not car.occupied and not car.stolen and float(car.get("hp",100.0))>0.0 and float(car.get("stun",0.0))<=0.0

func _update_police_fire(officer: Dictionary, delta: float, can_see: bool, distance: float) -> void:
	var eligible := pursuit and can_see and float(officer.hp)>0.0 and float(officer.stun)<=0.0 and not bool(officer.get("retiring",false)) and distance>4.0 and distance<22.0 and Game.escape_duration_seconds()>=POLICE_FIREARMS_TIER
	if not eligible:
		officer.aim_seconds = 0.0
		if is_instance_valid(officer.get("weapon",null)): officer.weapon.visible = false
		return
	if not is_instance_valid(officer.get("weapon",null)):
		var weapon := ActorVisuals.model("Blasters","blaster-a",0.3)
		weapon.position = Vector3(0.36,1.1,0.4)
		var model: Node3D = officer.node.get_meta("model")
		model.add_child(weapon)
		officer.weapon = weapon
		_emote(officer.node,"alert")
	officer.weapon.visible = true
	officer.aim_seconds = float(officer.get("aim_seconds",0.0))+delta
	if float(officer.aim_seconds)<0.8 or float(officer.get("shot_cooldown",0.0))>0.0: return
	# Each shot is a fresh unobstructed sight test, not damage scheduled after a
	# wall is crossed. No firing during melee stun, retirement or loss of sight.
	if not _line_of_sight(officer.node.global_position,player.global_position): return
	officer.aim_seconds = 0.0
	officer.shot_cooldown = 2.2+float(officer.node.get_instance_id()%5)*0.13
	ActorVisuals.play(officer.node,"holding-right-shoot",false)
	_police_shot_trace(officer.node.global_position+Vector3(0,1.25,0),player.global_position+Vector3.UP)
	Game.feedback_event.emit("police_shot",0.0)
	player.receive_police_shot(9.0,officer.node)

func _police_shot_trace(from: Vector3, target: Vector3) -> void:
	var line := ImmediateMesh.new()
	line.surface_begin(Mesh.PRIMITIVE_LINES,ActorVisuals.material(Color("ffe3a0"),true))
	line.surface_add_vertex(from)
	line.surface_add_vertex(target)
	line.surface_end()
	var trace := MeshInstance3D.new()
	trace.name = "PoliceShot"
	trace.mesh = line
	add_child(trace)
	get_tree().create_timer(0.12).timeout.connect(trace.queue_free)

func _police_can_see(observer: Node3D, target: Vector3, sight_range: float) -> bool:
	var relative := target-observer.global_position
	relative.y = 0.0
	var squared := relative.length_squared()
	if squared >= sight_range*sight_range: return false
	if squared > POLICE_CLOSE_AWARENESS*POLICE_CLOSE_AWARENESS:
		# Both supplied characters and cars face local +Z. Read the displayed
		# heading, not the next route waypoint (which can be around a corner).
		var forward := observer.global_basis.z
		forward.y = 0.0
		if forward.normalized().dot(relative.normalized()) < POLICE_VIEW_COSINE: return false
	# Even the close-awareness exception cannot see through a solid wall.
	return _line_of_sight(observer.global_position,target)

func _alert_city_officers() -> void:
	for officer: Dictionary in police:
		if not bool(officer.campus) and float(officer.hp)>0.0: officer.alert = 15.0

func _begin_pursuit(message: String) -> void:
	if not pursuit:
		Game.register_pursuit(_closest_incident_location(crime_position))
		for officer: Dictionary in police:
			if officer.node.visible and officer.node.position.distance_squared_to(player.position)<900.0: _emote(officer.node,"alert")
		_pressure_timer = 0.0
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
	var walking_obstacles: Array[Rect2] = []
	walking_obstacles.assign(world.obstacle_rects)
	walking_obstacles.append_array(world.navigation_prop_obstacles())
	for obstacle: Rect2 in walking_obstacles:
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
	var route: PackedVector3Array = record.nav_path
	var path_index := int(record.nav_index)
	var following := path_index<route.size()
	var old_target: Vector3 = record.nav_target
	if old_target.is_finite() and old_target.distance_squared_to(target)>25.0:
		following = false
		record.nav_path = PackedVector3Array()
	# Once a detour starts, finish its waypoints. A centre ray clearing a corner
	# is not clearance for the whole capsule; dropping the route there makes a
	# walker repeatedly cut the corner, collide, and replan backwards.
	if not following and (wall_contact or not _line_of_sight(actor.position,target)):
		var points: PackedVector2Array = navigation.get_point_path(_nearest_open_cell(actor.position),_nearest_open_cell(target))
		route = PackedVector3Array()
		for point: Vector2 in points: route.append(Vector3(point.x,0.15,point.y))
		path_index = 1 if route.size()>1 else 0
		record.nav_path = route
		record.nav_index = path_index
		record.nav_target = target
		record.nav_timer = 1.5
		following = path_index<route.size()
	if following:
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
	if record.has("neighbors"):
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
	if record.has("campus") and bool(record.campus) and not _is_campus(actor.position+direction*speed*delta):
		if _is_campus(actor.position): return
	# City officers may transit between detached city districts. Their sight and
	# arrest checks still reject campus incidents, including during this transit.
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
	if severity >= 25.0:
		for citizen: Dictionary in citizens:
			if citizen.node.position.distance_to(player.position)<16.0 and _line_of_sight(citizen.node.position,player.position):
				citizen.panic = 6.0
				citizen.panic_source = player.position
	var campus := _is_campus(player.position)
	if not campus and _cruiser_sees_player():
		crime_position = player.position
		crime_age = 0.0
		_begin_pursuit("SPOTTED — a road patrol called the deal in.")
		_alert_city_officers()
	var nearest: Dictionary = {}
	var best := INF
	for officer: Dictionary in police:
		if float(officer.hp)<=0.0 or float(officer.stun)>0.0 or bool(officer.get("retiring",false)) or bool(officer.campus)!=campus: continue
		var distance: float = officer.node.position.distance_to(player.position)
		if distance<best:
			nearest = officer
			best = distance
		if _police_can_see(officer.node,player.global_position,19.0):
			crime_position = player.position
			crime_age = 0.0
			officer.alert = 12.0
			_begin_pursuit("SPOTTED — break line of sight and stay hidden to escape.")
	if severity>=65.0 and not nearest.is_empty():
		# Gunfire and reported stings dispatch to a known location independently
		# of visual witnessing. Unseen ordinary handoffs never update that point.
		crime_position = player.position
		crime_age = 0.0
		nearest.alert = 15.0
		_begin_pursuit("POLICE RESPONDING — a patrol is checking the area.")

func _civilian_name(index: int) -> String:
	var names := ["Avery Chen","Jordan Patel","Casey Brooks","Riley Tremblay","Morgan Lee","Sam Wilson","Rowan Ali","Charlie Martin","Quinn Park","Taylor Scott","Cameron Roy","Alex Singh","Jamie Young","Drew Nguyen","Skyler Reed","Emery Clarke","Noah Hassan","Maya Turner","Leo Bennett","Zoe Wright","Luca Moreau","Ella Davis","Owen Clark","Nina Ibrahim","Evan Walsh","Aria Roberts","Miles Kim","Lily Santos","Theo Brown","Sara Ahmed","Jules Murphy","Ivy Green","Max Laurent","Eva Phillips","Finn Walker","Leah Adams","Rory Bell","Mia Grant","Jesse Moore","Ada Lewis","Remy Baker","Sasha Hill","Dakota Price","Elliot Adams","Harper Quinn","Kai Moore","Logan Bell","Parker Liu","Reese Dubois","Sydney Khan","Jaden Ellis","Blair Ross","Cleo James","Nico Taylor","Tessa Grey","Robin Cook","Dylan Fox"]
	return names[posmod(index,names.size())]

func nearest_conversational_npc(radius: float = 3.2) -> Dictionary:
	if player.vehicle or player.position.x>400.0: return {}
	if _citizens_by_id.has(_active_conversation):
		var held: Dictionary = _citizens_by_id[_active_conversation]
		if bool(held.conversation) and held.node.position.distance_squared_to(player.position)<radius*radius:
			return {"id":held.id,"name":held.name,"goal":held.goal,"node":held.node}
	var closest: Dictionary = {}
	var distance := radius*radius
	for citizen: Dictionary in citizens:
		if bool(citizen.get("party_guest",false)) or citizen.get("car_trip","")=="driving" or float(citizen.hp)<=0.0 or bool(citizen.reporting) or bool(citizen.reported) or float(citizen.panic)>0.0 or float(citizen.stun)>0.0: continue
		var separation: float = citizen.node.position.distance_squared_to(player.position)
		if separation<distance and _line_of_sight(citizen.node.position,player.position):
			distance = separation
			closest = {"id":citizen.id,"name":citizen.name,"goal":citizen.goal,"node":citizen.node}
	return closest

func begin_conversation(id: String) -> bool:
	if not _citizens_by_id.has(id): return false
	var citizen: Dictionary = _citizens_by_id[id]
	if bool(citizen.get("party_guest",false)) or citizen.get("car_trip","")=="driving" or float(citizen.hp)<=0.0 or citizen.reporting or citizen.reported or citizen.node.position.distance_to(player.position)>3.5 or not _line_of_sight(citizen.node.position,player.position): return false
	end_conversation()
	_active_conversation = id
	citizen.conversation = true
	citizen.node.velocity = Vector3.ZERO
	var relative: Vector3 = player.position-citizen.node.position
	if relative.length_squared()>0.01: citizen.node.rotation.y = _heading(relative)
	ActorVisuals.play(citizen.node,"idle")
	var label := _civilian_label(citizen)
	label.text = str(citizen.name).to_upper()
	label.modulate = Color("d5f276")
	label.visible = true
	return true

func end_conversation() -> void:
	if _citizens_by_id.has(_active_conversation):
		var citizen: Dictionary = _citizens_by_id[_active_conversation]
		citizen.conversation = false
		citizen.wait = maxf(float(citizen.wait),1.5)
	_active_conversation = ""

func _civilian_label(citizen: Dictionary) -> Label3D:
	if citizen.has("name_label"): return citizen.name_label
	var label := ActorVisuals.label(str(citizen.name).to_upper(),Color("d5f276"),19)
	label.position.y = 2.55
	citizen.node.add_child(label)
	citizen.name_label = label
	var actor_id: int = citizen.node.get_instance_id()
	if _grounding_cache.has(actor_id):
		_grounding_cache[actor_id].parts.append({"node":label,"base_y":2.55})
		label.position.y += world.walkable_support_height(citizen.node.position,0.24)-citizen.node.position.y
	return label

func start_informant_run(id: String) -> bool:
	if not _citizens_by_id.has(id): return false
	var citizen: Dictionary = _citizens_by_id[id]
	if float(citizen.hp)<=0.0 or citizen.reported: return false
	if citizen.reporting: return true
	end_conversation()
	citizen.reporting = true
	citizen.report_position = player.position
	citizen.report_campus = _is_campus(player.position)
	citizen.report_retry = 0.0
	citizen.report_officer = -1
	citizen.panic = 0.0
	citizen.stun = 0.0
	var label := _civilian_label(citizen)
	label.text = "CALLING FOR HELP!"
	label.modulate = Color("ff927d")
	label.visible = true
	_emote(citizen.node,"angry")
	Game.notification.emit("%s is running to report you to a patrol."%citizen.name)
	return true

func _nearest_officer_index(at: Vector3, campus: bool) -> int:
	var result := -1
	var nearest := INF
	for index in police.size():
		var officer: Dictionary = police[index]
		if float(officer.hp)<=0.0 or bool(officer.get("retiring",false)) or bool(officer.campus)!=campus: continue
		var distance: float = officer.node.position.distance_squared_to(at)
		if distance<nearest:
			nearest = distance
			result = index
	return result

func _update_informant(citizen: Dictionary, delta: float) -> void:
	if float(citizen.stun)>0.0:
		citizen.stun = maxf(0.0,float(citizen.stun)-delta)
		return
	citizen.report_retry = maxf(0.0,float(citizen.report_retry)-delta)
	var index := int(citizen.get("report_officer",-1))
	if index<0 or index>=police.size() or float(police[index].hp)<=0.0 or float(citizen.report_retry)<=0.0:
		index = _nearest_officer_index(citizen.node.position,bool(citizen.report_campus))
		citizen.report_officer = index
		citizen.report_retry = 1.0
	if index<0:
		ActorVisuals.play(citizen.node,"idle")
		return
	var officer: Dictionary = police[index]
	var target: Vector3 = officer.node.position
	if _horizontal_distance(citizen.node.position,target)<2.4 and _line_of_sight(citizen.node.position,target):
		citizen.reporting = false
		citizen.reported = true
		citizen.wait = 10.0
		citizen.name_label.text = "REPORTING TO POLICE"
		crime_position = citizen.report_position
		crime_age = 0.0
		officer.alert = 20.0
		_begin_pursuit("A witness reached a patrol. Officers are checking the area.")
		informant_reported.emit(str(citizen.id))
		return
	_move_person(citizen,target,4.8,delta)

func capture_informant_state() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for citizen: Dictionary in citizens:
		if not bool(citizen.reporting) or float(citizen.hp)<=0.0: continue
		var at: Vector3 = citizen.node.position
		var report_at: Vector3 = citizen.report_position
		result.append({"id":citizen.id,"position":[at.x,at.y,at.z],"report_position":[report_at.x,report_at.y,report_at.z],"campus":citizen.report_campus})
	return result

func restore_informant_state(saved: Array) -> void:
	for entry: Variant in saved:
		if not entry is Dictionary or not _citizens_by_id.has(str(entry.get("id",""))): continue
		var position_data: Variant = entry.get("position",[])
		var report_data: Variant = entry.get("report_position",[])
		if not position_data is Array or position_data.size()!=3 or not report_data is Array or report_data.size()!=3: continue
		var at := Vector3(float(position_data[0]),float(position_data[1]),float(position_data[2]))
		var report_at := Vector3(float(report_data[0]),float(report_data[1]),float(report_data[2]))
		if not at.is_finite() or not report_at.is_finite() or absf(at.x)>153.0 or absf(at.z)>125.0 or absf(report_at.x)>153.0 or absf(report_at.z)>125.0 or at.y< -1.0 or at.y>4.0 or report_at.y< -1.0 or report_at.y>4.0: continue
		var citizen: Dictionary = _citizens_by_id[str(entry.id)]
		if float(citizen.hp)<=0.0: continue
		citizen.node.position = at
		citizen.reporting = true
		citizen.reported = false
		citizen.conversation = false
		citizen.report_position = report_at
		citizen.report_campus = bool(entry.get("campus",_is_campus(report_at)))
		citizen.report_retry = 0.0
		citizen.report_officer = -1
		var label := _civilian_label(citizen)
		label.text = "CALLING FOR HELP!"
		label.modulate = Color("ff927d")
		label.visible = true

func police_presence_count(at: Vector3, radius: float = 24.0) -> int:
	var count := 0
	var campus := _is_campus(at)
	for officer: Dictionary in police:
		if float(officer.hp)>0.0 and not bool(officer.get("retiring",false)) and bool(officer.campus)==campus and officer.node.position.distance_squared_to(at)<radius*radius and _line_of_sight(officer.node.position,at): count += 1
	if not campus:
		for car: Dictionary in vehicles:
			if bool(car.get("police",false)) and not car.occupied and not car.stolen and car.node.position.distance_squared_to(at)<radius*radius and _line_of_sight(car.node.position,at): count += 1
	return count

func meeting_actor_present(meeting_id: int) -> bool:
	return meeting_actors.has(str(meeting_id)) and meeting_walks.has(str(meeting_id)) and meeting_walks[str(meeting_id)].state=="waiting"

func respond_to_tip(location_id: String, _severity: float = 35.0) -> void:
	if not world.landmarks.has(location_id) or Game.status!="playing": return
	var at: Vector3 = world.landmarks[location_id].position
	var index := _nearest_officer_index(at,_is_campus(at))
	if index<0: return
	crime_position = at
	crime_age = 0.0
	police[index].alert = 25.0
	_begin_pursuit("POLICE RESPONDING - a patrol was tipped off about this location.")

func nearby_vehicle() -> Dictionary:
	var nearest: Dictionary = {}
	var best := 4.2
	for car: Dictionary in vehicles:
		var distance: float = car.node.position.distance_to(player.position)
		if distance<best and not car.occupied and not bool(car.get("npc_driver",false)) and _line_of_sight(player.position,car.node.position):
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
	if player.vehicle==car: player.recover_vehicle_if_blocked()
	var options: Array[Vector3] = []
	for side: float in [2.1,-2.1,2.8,-2.8]:
		for along: float in [0.0,-1.35,1.35]: options.append(car.global_basis.x*side+car.global_basis.z*along)
	for along: float in [-3.0,3.0,-3.8,3.8]:
		for side: float in [0.0,-1.0,1.0]: options.append(car.global_basis.z*along+car.global_basis.x*side)
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
		if str(entry.get("state",""))=="waiting" and Game.minute>=float(record.due)-float(record.arrival_minutes) and _horizontal_distance(at,record.target)<2.0:
			record.state = "waiting"

func capture_pursuit_state() -> Dictionary:
	var officers: Array[Dictionary] = []
	for officer: Dictionary in police.slice(0,BASE_POLICE_COUNT):
		var at: Vector3 = officer.node.position
		officers.append({"position":[at.x,at.y,at.z],"hp":officer.hp,"alert":officer.alert,"stun":officer.stun,"index":officer.index})
	return {"officers":officers,"arrest_seconds":arrest_seconds,"escape_seconds":escape_seconds,"crime_age":crime_age,"crime_position":[crime_position.x,crime_position.y,crime_position.z]}

func restore_pursuit_state(state: Dictionary) -> void:
	var officers: Array = state.get("officers",[])
	if officers.size() not in [7,BASE_POLICE_COUNT]: return
	for index in officers.size():
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
		victim.stun = POLICE_MELEE_STUN if victim.has("campus") and kind!="shoot" else 0.65
		victim.node.velocity = Vector3.ZERO
		if victim.has("campus"): victim.aim_seconds = 0.0
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
	var party_contacts: Dictionary = {}
	var party: Dictionary = Game.party_summary()
	if bool(party.get("active",false)):
		for guest: Dictionary in party.get("guests",[]):
			party_contacts[str(guest.contact_id)] = true
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
		# Social helpers retain ownership through their final offscreen departure.
		# A future appointment must not create a second copy of the same person.
		var busy := party_contacts.has(str(meeting.contact_id))
		for provider: Node in social_actor_providers:
			if is_instance_valid(provider) and provider.has_contact_actor(str(meeting.contact_id)): busy = true
		if busy: continue
		if Game.minute<float(meeting.due_minute)-90.0 or not world.landmarks.has(meeting.location_id): continue
		var landmark: Vector3 = world.landmarks[meeting.location_id].position
		var cell := _nearest_open_cell(landmark+Vector3(2.2,0,1.8))
		var target := Vector3(cell.x*NAV_CELL,0.2,cell.y*NAV_CELL)
		var start := _offscreen_walk_point(target)
		if not start.is_finite(): continue
		var asset := "character-female-b"
		if meeting.type=="supplier": asset = "character-female-f" if str(meeting.contact_id)=="supplier_1" else "character-male-e"
		var actor := _person(asset,1.8)
		actor.position = start
		var tag := ActorVisuals.label(str(meeting.contact_name).to_upper(),Color("edc37e"),22)
		tag.position.y = 2.5
		actor.add_child(tag)
		actor.add_child(ActorVisuals.ground_ring(Color("edc37e"),0.7))
		actor.visible = player.position.x<400.0
		actor.collision_layer = PERSON_LAYER if actor.visible else 0
		var path := _walking_path(start,target)
		var distance := _path_distance(start,path,0,target)
		var arrival_minutes: float = Game.meeting_arrival_minutes(meeting)
		meeting_actors[id] = actor
		meeting_walks[id] = {"node":actor,"hp":100.0,"state":"approaching","target":target,"due":float(meeting.due_minute),"arrival_minutes":arrival_minutes,"start_minute":float(meeting.due_minute)-arrival_minutes-distance/1.9*3.0,"last_minute":Game.minute,"nav_path":path,"nav_index":0,"nav_target":target,"nav_timer":2.0}
	for id: String in meeting_walks.keys():
		if live.has(id): continue
		var record: Dictionary = meeting_walks[id]
		if record.state=="departing": continue
		if _point_offscreen(record.node.position):
			_remove_meeting_actor(id)
			continue
		for meeting: Dictionary in Game.meetings:
			if str(int(meeting.id))==id and meeting.status=="missed": _emote(record.node,"sad")
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
		var seconds_left := maxf(0.1,(float(record.due)-float(record.arrival_minutes)-Game.minute)/3.0)
		var speed := clampf(remaining/seconds_left,1.2,5.8)
		if _horizontal_distance(actor.position,record.target)<0.85:
			if Game.minute>=float(record.due)-float(record.arrival_minutes):
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
	if _horizontal_distance(record.node.position,record.target)<0.85 and Game.minute>=float(record.due)-float(record.arrival_minutes):
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

func _closest_incident_location(at: Vector3) -> String:
	var closest := "campus_quad"
	var distance := INF
	var campus := _is_campus(at)
	for id: String in world.landmarks:
		var landmark: Vector3 = world.landmarks[id].position
		if _is_campus(landmark)!=campus: continue
		var gap := at.distance_squared_to(landmark)
		if gap<distance:
			distance = gap
			closest = id
	return closest

func _sync_pressure_patrols() -> void:
	var wanted: Dictionary = {}
	var available := 8
	for pressure: Dictionary in Game.police_pressure_locations():
		var id: String = pressure.location_id
		if not world.landmarks.has(id): continue
		var count := mini(available,mini(4,int(pressure.strength)))
		for number in count: wanted[id+":"+str(number)] = pressure
		available -= count
		if available<=0: break
	for index in range(police.size()-1,BASE_POLICE_COUNT-1,-1):
		var officer: Dictionary = police[index]
		if wanted.has(officer.pressure_key): continue
		if not _point_offscreen(officer.node.position):
			if not bool(officer.retiring): officer.retire_target = _offscreen_patrol_point(officer.node.position,bool(officer.campus))
			officer.retiring = true
			continue
		var actor: CharacterBody3D = officer.node
		_grounding_cache.erase(actor.get_instance_id())
		police.remove_at(index)
		for record: Dictionary in _pedestrian_neighbors:
			if record.has("neighbors"): record.neighbors.erase(actor)
		actor.queue_free()
	var spawned := 0
	for key: String in wanted:
		var exists := false
		for officer: Dictionary in police:
			if str(officer.get("pressure_key",""))==key:
				officer.retiring = false
				exists = true
				break
		if exists: continue
		if spawned>=2 or police.size()>=BASE_POLICE_COUNT+8: break
		var pressure: Dictionary = wanted[key]
		var target: Vector3 = world.landmarks[pressure.location_id].position
		var campus := _is_campus(target)
		var start := _offscreen_patrol_point(target,campus)
		if not start.is_finite(): continue
		var actor := _person("character-male-c",1.9)
		actor.position = start
		var number := int(key.get_slice(":",1))
		var shifted := _safe_pedestrian_target(start+Vector3(float(number%2)*2.0,0,float(number/2)*2.0))
		if _point_offscreen(shifted) and _is_campus(shifted)==campus: actor.position = shifted
		actor.add_child(ActorVisuals.ground_ring(Color("76b7dd") if campus else Color("668cff"),0.55))
		var tag := ActorVisuals.label("CAMPUS PATROL" if campus else "CITY PATROL",Color("8ac2ef"),15)
		tag.position.y = 2.3
		actor.add_child(tag)
		var route := PackedVector3Array()
		for offset: Vector3 in [Vector3(-9,0,0),Vector3(0,0,9),Vector3(9,0,0),Vector3(0,0,-9)]:
			var point := _safe_pedestrian_target(target+offset)
			if _is_campus(point)==campus: route.append(point)
		if route.size()<2: route = PackedVector3Array([target,target+Vector3(0,0,1)])
		police.append({"node":actor,"route":route,"index":0,"campus":campus,"alert":0.0,"hp":150.0,"stun":0.0,"nav_path":PackedVector3Array(),"nav_index":0,"nav_target":Vector3.INF,"nav_timer":0.0,"dead_seconds":0.0,"pressure_key":key,"retiring":false})
		spawned += 1
		_ground_person(actor)
	_refresh_neighbor_lists()

func _emote(actor: Node3D, kind: String) -> void:
	var bubble: Node3D = Emotes.play(actor,kind)
	if bubble: bubble.position.y = 3.25+world.walkable_surface_height(actor.position)-actor.position.y

func play_contact_emote(meeting_id: int, kind: String) -> void:
	var key := str(meeting_id)
	if meeting_actors.has(key): _emote(meeting_actors[key],kind)

func play_citizen_emote(npc_id: String, kind: String) -> void:
	if _citizens_by_id.has(npc_id): _emote(_citizens_by_id[npc_id].node,kind)

func _offscreen_patrol_point(target: Vector3, campus: bool) -> Vector3:
	var candidate := _offscreen_walk_point(target)
	if candidate.is_finite() and _is_campus(candidate)==campus: return candidate
	var result := Vector3.INF
	var nearest := INF
	var routes: Array = world.campus_police_routes if campus else world.city_police_routes
	for route: PackedVector3Array in routes:
		for point: Vector3 in route:
			var distance := point.distance_squared_to(target)
			if distance<nearest and _is_campus(point)==campus and _point_offscreen(point):
				result = point
				nearest = distance
	return result
