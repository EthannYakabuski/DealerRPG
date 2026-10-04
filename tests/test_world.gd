extends SceneTree
## World-only geometry diagnostics. Run headless after importing the project.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world = load("res://scripts/world.gd").new()
	root.add_child(world)
	await process_frame
	var failures: Array[String] = []
	for id in world.landmarks:
		var pos: Vector3 = world.landmarks[id].position
		for rect in world.obstacle_rects:
			if rect.grow(0.6).has_point(Vector2(pos.x,pos.z)):
				failures.append("Landmark %s blocked at %s" % [id,str(pos)])
	# The authored marker must sit on the native model's door side with a clear
	# approach, not merely somewhere outside its rectangular footprint.
	for id: String in world.building_entrances:
		var entry: Dictionary = world.building_entrances[id]
		var approach: Vector3 = entry.marker-entry.door
		approach.y = 0.0
		if approach.length()<2.0 or approach.length()>6.0 or approach.normalized().dot(entry.outward)<0.98:
			failures.append("Entrance %s is not aligned directly outside its model door"%id)
		var threshold: Vector3 = entry.door+entry.outward*1.5
		for step in range(11):
			var at: Vector3 = entry.marker.lerp(threshold,float(step)/10.0)
			for rect: Rect2 in world.obstacle_rects:
				if rect.grow(0.2).has_point(Vector2(at.x,at.z)):
					failures.append("Entrance %s approach crosses another wall"%id)
		if world.walkable_surface_height(entry.marker)<0.04:
			failures.append("Entrance %s lacks a paved approach"%id)
	if world.building_entrances.size()!=9:
		failures.append("Door audit must include the neighbor apartment as well as the original eight entrances")
	if not world.interior_nodes.has("deerfield_social") or world.interior_nodes.deerfield_social.position.x!=1000.0:
		failures.append("Neighbor apartment needs a separate furnished interior")
	for id: String in ["west_overlook","service_lane","east_trail"]:
		if not world.landmarks.has(id) or not world.is_paved_surface(world.get_landmark(id)):
			failures.append("Outskirts rendezvous lacks a reachable paved marker: "+id)
	for route: PackedVector3Array in world.campus_police_routes:
		for index in route.size():
			for step in 20:
				if world.get_district(route[index].lerp(route[(index+1)%route.size()],float(step)/20.0))!="Campus":
					failures.append("Campus patrol route crosses its movement jurisdiction")
	for id: String in world.pedestrian_activities:
		for rect: Rect2 in world.obstacle_rects:
			var destination: Vector3 = world.pedestrian_activities[id].position
			if rect.grow(0.6).has_point(Vector2(destination.x,destination.z)):
				failures.append("Pedestrian activity sits inside a wall: "+id)
	if world.get_district(world.get_landmark("supplier"))!="College Square":
		failures.append("Service yard uses the wrong police jurisdiction")
	var road_conflicts: Dictionary = {}
	for r in world.map_roads.size():
		var points: PackedVector3Array = world.map_roads[r]
		for i in points.size()-1:
			for step in int(points[i].distance_to(points[i+1]))+1:
				var pos: Vector3 = points[i].lerp(points[i+1],float(step)/maxf(points[i].distance_to(points[i+1]),1))
				for b in world.obstacle_rects.size():
					var rect: Rect2 = world.obstacle_rects[b]
					var p2 := Vector2(pos.x,pos.z)
					var closest := p2.clamp(rect.position,rect.end)
					if p2.distance_to(closest) < world.road_widths[r]*0.5+0.2:
						road_conflicts["road %d / building %d" % [r,b]] = str(world.map_buildings[b])
	var pedestrian_conflicts: Dictionary = {}
	var all_walking_routes: Array = world.pedestrian_routes+world.outskirts_routes
	for r in all_walking_routes.size():
		var points: PackedVector3Array = all_walking_routes[r]
		for i in points.size():
			var next: Vector3 = points[(i+1)%points.size()]
			var distance := points[i].distance_to(next)
			for step in int(distance)+1:
				var pos := points[i].lerp(next,float(step)/maxf(distance,1))
				for b in world.obstacle_rects.size():
					if world.obstacle_rects[b].grow(0.35).has_point(Vector2(pos.x,pos.z)):
						pedestrian_conflicts["route %d / segment %d / building %d" % [r,i,b]] = str(pos)
	for crossing: Dictionary in world.crosswalks:
		var centered := false
		var road: PackedVector3Array = world.map_roads[int(crossing.road)]
		for segment in road.size()-1:
			var closest := Geometry3D.get_closest_point_to_segment(crossing.center,road[segment],road[segment+1])
			if closest.distance_to(crossing.center)<0.01 and absf(crossing.tangent.dot((road[segment+1]-road[segment]).normalized()))>0.999: centered = true
		if not centered: failures.append("Crosswalk is not centered/aligned with its actual road")
	for prop: Dictionary in world.public_props:
		if prop.node.visible and not world._corridor_clear(prop.node.position,float(prop.radius)-0.01): failures.append("Prop blocks a sidewalk/path: "+str(prop.key))
	if world.is_paved_surface(Vector3(32,0,58)) or world.is_paved_surface(Vector3(43,0,63)): failures.append("Raised turf/bare grass incorrectly treated as skate paving")
	if not world.is_paved_surface(Vector3(22,0,61)) or not world.is_paved_surface(Vector3(71,0,18)): failures.append("Actual paving/asphalt is missing its skating classification")
	for lot: Dictionary in world.parking_lots:
		if not lot.has("gate") or not world._vehicle_corridor_clear(lot.gate,lot.road_point): failures.append("Parking lot lacks a driveable entrance")
	var traffic_conflicts: Dictionary = {}
	for r in world.traffic_routes.size():
		var points: PackedVector3Array = world.traffic_routes[r]
		for i in points.size():
			var next: Vector3 = points[(i+1)%points.size()]
			var distance := points[i].distance_to(next)
			for step in int(distance)+1:
				var pos := points[i].lerp(next,float(step)/maxf(distance,1))
				var on_road := false
				for road_index in world.map_roads.size():
					var road: PackedVector3Array = world.map_roads[road_index]
					for seg in road.size()-1:
						var closest := Geometry3D.get_closest_point_to_segment(pos,road[seg],road[seg+1])
						if pos.distance_to(closest) <= world.road_widths[road_index]*0.5-0.65:
							on_road = true
				if not on_road:
					traffic_conflicts["route %d / segment %d" % [r,i]] = str(pos)
	print("WORLD_GEOMETRY ",JSON.stringify({"landmark_failures":failures,"road_conflicts":road_conflicts,"pedestrian_conflicts":pedestrian_conflicts,"traffic_conflicts":traffic_conflicts,"landmarks":world.landmarks.size(),"buildings":world.map_buildings.size(),"parking_spawns":world.parked_car_spawns.size()}))
	for id in world.interior_nodes:
		var at: Vector3 = world.enter_interior(id)
		assert(at.x > 500 and world.current_interior == id)
		assert(world.get_interior_exit().distance_to(at)<5)
		var outside: Vector3 = world.exit_interior()
		assert(outside.distance_to(world.get_landmark(id))<3)
	# The Compatibility cutaway must actually reveal an obstructed player and
	# restore opaque geometry when the camera moves elsewhere.
	var cafe_player := Vector3(-63,0.15,-22)
	world.update_camera_occlusion(cafe_player+Vector3(24,38,28),cafe_player)
	var faded_count := 0
	for record in world._occluders:
		if record.faded:
			faded_count += 1
			for part in record.parts:
				assert(part.ghost.visible)
				assert(part.mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	if faded_count == 0:
		failures.append("Camera cutaway did not detect the café parasol")
	world.update_camera_occlusion(Vector3(300,40,300),Vector3(280,0,280))
	for record in world._occluders:
		assert(not record.faded)
	print("WORLD_CUTAWAY ",faded_count," occluders revealed; opaque state restored")
	world.free()
	quit(0 if failures.is_empty() and pedestrian_conflicts.is_empty() and road_conflicts.is_empty() and traffic_conflicts.is_empty() else 1)
