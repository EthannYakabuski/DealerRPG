class_name CityCarTrips
extends RefCounted
## A small number of citizens use the existing traffic solver for a complete
## walk/drive/park trip. No additional vehicle meshes or per-frame path searches.
var city: Node3D
var trips: Array[Dictionary] = []
var assignment_timer := 8.0
var completed_trips := 0

func setup(population: Node3D) -> void:
	city = population

func parking_departure(car: Dictionary) -> PackedVector3Array:
	var lot_id := int(car.get("lot",-1))
	if lot_id<0 or lot_id>=city.world.parking_lots.size(): return PackedVector3Array()
	var lot: Dictionary = city.world.parking_lots[lot_id]
	if not lot.has("gate"): return PackedVector3Array()
	var rotate := Basis(Vector3.UP,float(lot.angle))
	var local: Vector3 = rotate.inverse()*(car.node.position-Vector3(lot.center))
	if absf(local.x)>float(lot.size.x)*0.5+1.0 or absf(local.z)>float(lot.size.y)*0.5+1.0: return PackedVector3Array()
	return PackedVector3Array([car.node.position,Vector3(lot.center)+rotate*Vector3(local.x,0.13,0),lot.gate+Vector3.UP*0.13,lot.road_point+Vector3.UP*0.16])

func parking_return(car: Dictionary, preferred: Vector3) -> Dictionary:
	var lot_id := int(car.get("lot",-1))
	if lot_id<0 or lot_id>=city.world.parking_lots.size(): return {}
	var selected: Dictionary = {}
	for slot: Dictionary in city.world.parking_slots:
		if slot.position.distance_squared_to(preferred)>0.1: continue
		var taken := false
		for other: Dictionary in city.vehicles:
			if other.node!=car.node and (other.node.position.distance_squared_to(slot.position)<8.0 or int(other.get("reserved_parking_id",-1))==int(slot.id)): taken = true
		for trip: Dictionary in trips:
			if int(trip.destination.id)==int(slot.id): taken = true
		if not taken: selected = slot
	if selected.is_empty(): selected = _vacant_slot(lot_id,car.node)
	if selected.is_empty(): return {}
	car.reserved_parking_id = int(selected.id)
	var lot: Dictionary = city.world.parking_lots[lot_id]
	var rotate := Basis(Vector3.UP,float(lot.angle))
	var local: Vector3 = rotate.inverse()*(Vector3(selected.position)-Vector3(lot.center))
	var aisle: Vector3 = Vector3(lot.center)+rotate*Vector3(local.x,0.13,0)
	var local_from: Vector3 = rotate.inverse()*(car.node.position-Vector3(lot.center))
	if absf(local_from.x)<=float(lot.size.x)*0.5+1.0 and absf(local_from.z)<=float(lot.size.y)*0.5+1.0:
		return {"slot":selected,"path":PackedVector3Array([car.node.position,Vector3(lot.center)+rotate*Vector3(local_from.x,0.13,0),aisle,selected.position])}
	return {"slot":selected,"path":PackedVector3Array([lot.road_point+Vector3.UP*0.16,lot.gate+Vector3.UP*0.13,aisle,selected.position])}

func update(delta: float) -> void:
	for trip: Dictionary in trips.duplicate():
		var citizen: Dictionary = city._citizens_by_id.get(trip.id,{})
		var car: Dictionary = trip.car
		if citizen.is_empty() or float(citizen.hp)<=0.0 or citizen.reporting or car.occupied or car.stolen or bool(car.get("owned",false)):
			_abort(trip)
			continue
		if trip.stage=="driving":
			citizen.node.position = car.node.position
			var route: PackedVector3Array = car.route
			if int(car.index)>=route.size()-2 and _bay_blocked(trip):
				if not _replan_return(trip):
					car.speed = 0.0
					continue
				route = car.route
			var near_lot: bool = car.node.position.distance_squared_to(trip.join)<100.0 or int(car.index)<4 or int(car.index)>route.size()-5
			car.speed = 3.1 if near_lot else 7.1
			if int(car.index)==route.size()-1 and car.node.position.distance_to(route[-1])<0.5:
				_finish(trip)
	assignment_timer -= delta
	if assignment_timer<=0.0:
		assignment_timer = 12.0
		if trips.size()<3: _assign_trip()

func _assign_trip() -> bool:
	var selected: Dictionary = {}
	var driver: Dictionary = {}
	var best := 38.0*38.0
	for car: Dictionary in city.vehicles:
		if not car.parked or car.occupied or car.stolen or car.get("npc_driver",false) or car.get("trip_reserved",false) or car.get("owned",false) or car.get("police",false): continue
		if int(car.get("lot",-1))<0 or str(car.node.get_meta("asset",""))=="police": continue
		for citizen: Dictionary in city.citizens.slice(42):
			if bool(citizen.get("party_guest",false)) or float(citizen.hp)<=0.0 or citizen.reporting or citizen.conversation or float(citizen.panic)>0.0 or citizen.get("car_trip","")!="" or float(citizen.get("trip_cooldown",0.0))>Game.minute: continue
			var distance: float = citizen.node.position.distance_squared_to(car.node.position)
			if distance<best:
				best = distance
				selected = car
				driver = citizen
	if selected.is_empty(): return false
	var lot: Dictionary = city.world.parking_lots[int(selected.lot)]
	if not lot.has("gate"): return false
	var destination := _vacant_slot(int(selected.lot),selected.node)
	if destination.is_empty(): return false
	var path := _trip_route(selected.node.position,lot,destination.position)
	if path.is_empty(): return false
	var door: Vector3 = selected.node.position+selected.node.basis.x*1.6
	if not city._line_of_sight(selected.node.position,door): door = selected.node.position-selected.node.basis.x*1.6
	var trip := {"id":driver.id,"car":selected,"stage":"walking","door":door,"route":path.points,"join":path.join,"destination":destination}
	trips.append(trip)
	selected.trip_reserved = true
	driver.car_trip = "walking_to_car"
	driver.trip_cooldown = Game.minute+300.0
	driver.goal = "Walking to my car"
	return true

func walk_to_car(citizen: Dictionary, delta: float) -> void:
	for trip: Dictionary in trips:
		if trip.id!=citizen.id: continue
		if citizen.conversation: return
		if citizen.node.position.distance_to(trip.door)<1.0:
			var car: Dictionary = trip.car
			if car.occupied or car.stolen or car.get("owned",false):
				_abort(trip)
				return
			trip.stage = "driving"
			car.npc_driver = true
			car.parked = false
			car.route = trip.route
			car.index = 1
			car.speed = 3.1
			car.wait = 0.0
			car.stuck = 0.0
			citizen.car_trip = "driving"
			citizen.goal = "Driving across town"
			city._set_person_visible(citizen.node,false)
			citizen.node.collision_layer = 0
			return
		city._move_person(citizen,trip.door,1.8,delta)
		return
	citizen.car_trip = ""

func _vacant_slot(lot_id: int, own_car: Node3D) -> Dictionary:
	for slot: Dictionary in city.world.parking_slots:
		if int(slot.lot)!=lot_id or slot.position.distance_squared_to(own_car.position)<10.0: continue
		var taken := false
		for trip: Dictionary in trips:
			if int(trip.destination.id)==int(slot.id): taken = true
		for car: Dictionary in city.vehicles:
			if car.node!=own_car and (car.node.position.distance_squared_to(slot.position)<8.0 or int(car.get("reserved_parking_id",-1))==int(slot.id)): taken = true
		if not taken: return slot
	return {}

func _trip_route(start: Vector3, lot: Dictionary, finish: Vector3) -> Dictionary:
	var closest := INF
	var selected := PackedVector3Array()
	var join := Vector3.INF
	var next := 0
	for route: PackedVector3Array in city.world.traffic_routes:
		for segment in route.size():
			var point := Geometry3D.get_closest_point_to_segment(lot.road_point,route[segment],route[(segment+1)%route.size()])
			var distance: float = point.distance_squared_to(lot.road_point)
			if distance>=closest or not city.world._vehicle_corridor_clear(lot.gate,point): continue
			closest = distance
			selected = route
			join = point
			next = (segment+1)%route.size()
	if selected.is_empty(): return {}
	var rotate := Basis(Vector3.UP,float(lot.angle))
	var local_start: Vector3 = rotate.inverse()*(start-Vector3(lot.center))
	var local_finish: Vector3 = rotate.inverse()*(finish-Vector3(lot.center))
	var aisle_start: Vector3 = Vector3(lot.center)+rotate*Vector3(local_start.x,0.13,0)
	var aisle_finish: Vector3 = Vector3(lot.center)+rotate*Vector3(local_finish.x,0.13,0)
	var gate: Vector3 = lot.gate+Vector3.UP*0.13
	var points := PackedVector3Array([start,aisle_start,gate,join])
	for index in selected.size(): points.append(selected[(next+index)%selected.size()])
	points.append(join)
	points.append(gate)
	points.append(aisle_finish)
	points.append(finish)
	for index in [0,1,2,points.size()-4,points.size()-3,points.size()-2]:
		if not city.world._vehicle_corridor_clear(points[index],points[index+1]): return {}
	return {"points":points,"join":join}

func _finish(trip: Dictionary) -> void:
	var car: Dictionary = trip.car
	if _bay_blocked(trip):
		_replan_return(trip)
		return
	var citizen: Dictionary = city._citizens_by_id[trip.id]
	var exit: Vector3 = city._safe_vehicle_exit(car.node)
	if not exit.is_finite():
		car.speed = 0.0
		return
	car.parked = true
	car.npc_driver = false
	car.trip_reserved = false
	car.speed = 0.0
	car.route = PackedVector3Array()
	car.node.rotation.y = float(trip.destination.rotation)
	citizen.node.position = exit
	citizen.node.velocity = Vector3.ZERO
	citizen.car_trip = ""
	citizen.wait = 2.0
	citizen.goal = "Walking from the parking lot"
	city._ground_person(citizen.node)
	completed_trips += 1
	trips.erase(trip)

func _abort(trip: Dictionary) -> void:
	var citizen: Dictionary = city._citizens_by_id.get(trip.id,{})
	var car: Dictionary = trip.car
	car.trip_reserved = false
	car.npc_driver = false
	if not car.occupied:
		car.parked = true
		car.speed = 0.0
	if not citizen.is_empty():
		if citizen.get("car_trip","")=="driving":
			var exit: Vector3 = city._safe_vehicle_exit(car.node)
			if exit.is_finite(): citizen.node.position = exit
		citizen.car_trip = ""
	trips.erase(trip)

func _bay_blocked(trip: Dictionary) -> bool:
	for other: Dictionary in city.vehicles:
		if other.node!=trip.car.node and other.node.position.distance_squared_to(trip.destination.position)<8.0: return true
	return false

func _replan_return(trip: Dictionary) -> bool:
	var car: Dictionary = trip.car
	var replacement := _vacant_slot(int(car.lot),car.node)
	if replacement.is_empty(): return false
	var lot: Dictionary = city.world.parking_lots[int(car.lot)]
	var rotate := Basis(Vector3.UP,float(lot.angle))
	var local_from: Vector3 = rotate.inverse()*(car.node.position-Vector3(lot.center))
	var local_to: Vector3 = rotate.inverse()*(Vector3(replacement.position)-Vector3(lot.center))
	car.route = PackedVector3Array([car.node.position,Vector3(lot.center)+rotate*Vector3(local_from.x,0.13,0),Vector3(lot.center)+rotate*Vector3(local_to.x,0.13,0),replacement.position])
	car.index = 1
	trip.destination = replacement
	return true
