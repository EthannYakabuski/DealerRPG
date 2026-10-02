extends Node3D
## Party guests remain actual walkers outside and conversational people inside.
const ROOM_SLOTS := [Vector3(-3.2,0.2,-3.0),Vector3(-0.6,0.2,-3.3),Vector3(2.1,0.2,-2.8),Vector3(5.4,0.2,-1.8),Vector3(-3.3,0.2,3.4),Vector3(-0.4,0.2,2.9),Vector3(2.6,0.2,2.7),Vector3(5.6,0.2,3.1)]
var world: Node3D
var player: StudentPlayer
var population: CityPopulation
var guests: Dictionary = {}
var party_id := -1
var conversation_contact := ""
var _dirty := true
var _lod_timer := 0.0

func setup(city: Node3D, student: StudentPlayer, people: CityPopulation) -> void:
	world=city
	player=student
	population=people
	Game.changed.connect(func():_dirty=true)

func reset() -> void:
	for contact_id: String in guests.keys(): _remove(contact_id)
	party_id=-1
	conversation_contact=""
	_dirty=true

func _physics_process(delta: float) -> void:
	if not world or Game.status!="playing": return
	if _dirty:
		_dirty=false
		_sync()
	if Game.paused: return
	var indoors: bool = world.current_interior=="home"
	_lod_timer-=delta
	for contact_id: String in guests.keys():
		var guest: Dictionary=guests[contact_id]
		var actor: CharacterBody3D=guest.node
		if guest.state=="inside":
			population._set_person_visible(actor,indoors)
			actor.collision_layer=4 if indoors else 0
			if conversation_contact!=contact_id:
				actor.rotation.y=lerp_angle(actor.rotation.y,float(guest.slot)*1.4+sin(Game.minute*0.035)*0.35,delta)
			ActorVisuals.play(actor,"idle")
		elif guest.state=="exiting":
			population._set_person_visible(actor,indoors)
			actor.collision_layer=4 if indoors else 0
			var exit_point: Vector3=world.interior_nodes.home.position+Vector3(0,0.2,5.8)
			# Guests north of the coffee table use its clear east aisle first.
			var destination: Vector3=guest.get("exit_waypoint",exit_point)
			if population._horizontal_distance(actor.position,destination)<0.45:
				guest.erase("exit_waypoint")
				destination=exit_point
			var toward: Vector3=destination-actor.position
			toward.y=0
			if population._horizontal_distance(actor.position,exit_point)<0.7:
				actor.position=world.get_landmark("home")+Vector3(0,0.15,0)
				population._grounding_cache.erase(actor.get_instance_id())
				_begin_departure(guest)
			else:
				actor.velocity=toward.normalized()*2.0+Vector3(0,-0.5,0)
				actor.move_and_slide()
				actor.rotation.y=atan2(toward.x,toward.z)
				population._ground_person(actor)
				ActorVisuals.play(actor,"walk")
		elif guest.state=="entering":
			population._set_person_visible(actor,world.current_interior=="")
			actor.collision_layer=0
			guest.door_wait-=delta
			if float(guest.door_wait)<=0.0 and Game.mark_party_guest_arrived(contact_id):
				_put_inside(guest)
		else:
			population._set_person_visible(actor,world.current_interior=="")
			actor.collision_layer=4 if actor.visible else 0
			if Game.minute<float(guest.start_minute): continue
			if guest.state=="leaving" and population._point_offscreen(actor.position):
				_remove(contact_id)
				continue
			if actor.position.distance_to(guest.target)<1.05 and guest.state=="approaching":
				guest.state="entering"
				guest.door_wait=0.7
				actor.velocity=Vector3.ZERO
				ActorVisuals.play(actor,"idle")
			else:
				var speed:=2.4
				if guest.state=="approaching":
					var remaining: float=population._path_distance(actor.position,guest.nav_path,int(guest.nav_index),guest.target) if not guest.nav_path.is_empty() else actor.position.distance_to(guest.target)
					speed=clampf(remaining/maxf(0.5,(float(guest.due)-Game.minute)/Game.TIME_SCALE),1.8,5.0)
				population._move_person(guest,guest.target,speed,delta)
		if _lod_timer<=0.0: population._set_model_animation_active(actor)
	if _lod_timer<=0.0: _lod_timer=0.2

func _sync() -> void:
	var summary: Dictionary=Game.party_summary()
	if not bool(summary.get("active",false)):
		for contact_id: String in guests:
			var guest: Dictionary=guests[contact_id]
			if guest.state in ["leaving","exiting"]: continue
			if guest.state=="inside":
				guest.state="exiting"
				var relative: Vector3=guest.node.position-world.interior_nodes.home.position
				if relative.z<2.3 and relative.x<1.5:
					guest.exit_waypoint=world.interior_nodes.home.position+Vector3(2.4,0.2,relative.z)
			else: _begin_departure(guest)
		conversation_contact=""
		return
	if int(summary.id)!=party_id:
		reset()
		party_id=int(summary.id)
	var index:=0
	for data: Dictionary in summary.guests:
		var contact_id:=str(data.contact_id)
		if not guests.has(contact_id): _create(data,index)
		index+=1

func _create(data: Dictionary, slot: int) -> void:
	var contact_id:=str(data.contact_id)
	var models := ["character-male-d","character-female-a","character-female-e","character-male-b","character-female-f","character-male-e"]
	var citizen: Dictionary=population._citizens_by_id.get(contact_id.trim_prefix("street_"),{}) if contact_id.begins_with("street_") else {}
	if not citizen.is_empty() and (citizen.get("car_trip","")!="" or bool(citizen.reporting)):
		_dirty=true
		return
	var borrowed: bool=not citizen.is_empty()
	var actor: CharacterBody3D=citizen.node if borrowed else population._person(models[posmod(contact_id.hash(),models.size())],1.78)
	actor.reparent(self,false)
	if borrowed:
		citizen.party_guest=true
		citizen.conversation=false
		if citizen.has("name_label"): citizen.name_label.visible=true
	else:
		var label:=ActorVisuals.label(str(data.name).to_upper(),Color("efbf77"),19)
		label.position.y=2.4
		actor.add_child(label)
	var target: Vector3=world.get_landmark("home")
	var start: Vector3=population._offscreen_walk_point(target)
	if not start.is_finite(): start=Vector3(112,0.2,-88)
	start=population._safe_pedestrian_target(start+Vector3(float(slot%3-1)*1.8,0,float(slot/3)*1.8))
	if not borrowed: actor.position=start
	var record: Dictionary={"node":actor,"name":data.name,"contact_id":contact_id,"slot":slot,"state":"approaching","target":target,"start_minute":Game.minute,"due":float(data.get("arrival_minute",Game.minute)),"door_wait":0.7,"nav_path":PackedVector3Array(),"nav_index":0,"nav_target":Vector3.INF,"nav_timer":0.0,"neighbors":[]}
	guests[contact_id]=record
	if borrowed: record.citizen_id=str(citizen.id)
	if bool(data.get("arrived",false)): _put_inside(record)
	else: population._ground_person(actor)

func _put_inside(guest: Dictionary) -> void:
	guest.state="inside"
	guest.node.position=world.interior_nodes.home.position+ROOM_SLOTS[int(guest.slot)%ROOM_SLOTS.size()]
	guest.node.velocity=Vector3.ZERO
	# Interior floor is flat; undo the cached exterior support offset.
	var model: Node3D=guest.node.get_meta("model")
	model.position.y=world.walkable_surface_height(guest.node.position)-guest.node.position.y
	for child: Node in guest.node.get_children():
		if child is Label3D: child.position.y=2.4
	population._grounding_cache.erase(guest.node.get_instance_id())
	population._set_person_visible(guest.node,world.current_interior=="home")
	guest.node.collision_layer=4 if guest.node.visible else 0

func _begin_departure(guest: Dictionary) -> void:
	guest.state="leaving"
	guest.target=population._offscreen_walk_point(guest.node.position)
	if not guest.target.is_finite(): guest.target=Vector3(120,0.2,-85)
	guest.nav_timer=0.0
	guest.nav_target=Vector3.INF
	guest.start_minute=Game.minute

func nearest_guest(radius: float=2.6) -> Dictionary:
	if world.current_interior!="home" or not bool(Game.party_summary().get("active",false)): return {}
	var nearest: Dictionary={}
	var distance:=radius*radius
	for contact_id: String in guests:
		var guest: Dictionary=guests[contact_id]
		if guest.state!="inside": continue
		var separation: float=player.position.distance_squared_to(guest.node.position)
		if separation<distance:
			distance=separation
			nearest={"contact_id":contact_id,"name":guest.name,"node":guest.node}
	return nearest

func in_reach(contact_id: String) -> bool:
	return world.current_interior=="home" and guests.has(contact_id) and guests[contact_id].state=="inside" and player.position.distance_to(guests[contact_id].node.position)<=3.1 and bool(Game.party_summary().get("active",false))

func capture() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for contact_id: String in guests:
		var guest: Dictionary=guests[contact_id]
		if guest.state in ["leaving","exiting"]: continue
		var at: Vector3=guest.node.position
		result.append({"contact_id":contact_id,"state":"inside" if guest.state=="inside" else "approaching","position":[at.x,at.y,at.z],"slot":int(guest.slot)})
	return result

func restore(saved: Array) -> void:
	_sync()
	for entry: Dictionary in saved:
		var contact_id:=str(entry.get("contact_id",""))
		if not guests.has(contact_id): continue
		var guest: Dictionary=guests[contact_id]
		if guest.state=="inside": continue
		var coordinates: Array=entry.get("position",[])
		if coordinates.size()!=3: continue
		var at:=Vector3(float(coordinates[0]),float(coordinates[1]),float(coordinates[2]))
		if not at.is_finite() or absf(at.x)>153 or absf(at.z)>125: continue
		guest.node.position=at
		guest.nav_timer=0.0
		guest.nav_target=Vector3.INF
		population._ground_person(guest.node)

func _remove(contact_id: String) -> void:
	var guest: Dictionary=guests[contact_id]
	var actor: Node3D=guest.node
	if is_instance_valid(actor):
		population._grounding_cache.erase(actor.get_instance_id())
		if guest.has("citizen_id") and population._citizens_by_id.has(guest.citizen_id):
			var citizen: Dictionary=population._citizens_by_id[guest.citizen_id]
			actor.reparent(population,false)
			citizen.party_guest=false
			citizen.nav_timer=0.0
			citizen.nav_path=PackedVector3Array()
			citizen.nav_target=Vector3.INF
			if actor.position.x>400: actor.position=world.get_landmark("home")
		else: actor.queue_free()
	guests.erase(contact_id)
