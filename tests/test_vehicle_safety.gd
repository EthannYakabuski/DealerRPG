extends SceneTree
## Real static shapes and player physics: props, rotation, crowding and recovery.
var checks := 0
var failures := 0
var game: Node
var scene: Node3D
var world: Node3D
var player: Node3D
var car: Node3D

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("VEHICLE SAFETY: "+label)

func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame
		player._physics_process(1.0/60.0)

func _drive_at(at: Vector3, heading: float) -> void:
	player.reset_travel()
	player.position = at
	car.position = at
	car.rotation.y = heading
	player.vehicle = car
	player.visual.rotation.y = heading
	game.paused = false

func _target_prop(key: String) -> Dictionary:
	for entry: Dictionary in world.public_props:
		if entry.key!=key or not entry.has("collider"): continue
		var shape: CollisionShape3D = entry.collider.get_child(0)
		var at := Vector3(shape.global_position.x,0.2,shape.global_position.z)
		if absf(at.x)>143.0 or absf(at.z)>120.0: continue
		var from := at-Vector3(6,0,0)
		var to := at+Vector3(6,0,0)
		if not world.vehicle_pose_clear(from,PI/2) or not world.vehicle_pose_clear(to,PI/2): continue
		var query := PhysicsRayQueryParameters3D.create(from+Vector3.UP*0.6,to+Vector3.UP*0.6,1)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider==entry.collider: return {"at":at,"entry":entry}
	return {}

func _run() -> void:
	game = root.get_node("Game")
	game.save_path = "res://.godot/vehicle-safety-test-save.json"
	game.restart_game()
	game.set_process(false)
	GameControls.setup()
	scene = Node3D.new()
	root.add_child(scene)
	world = load("res://scripts/world.gd").new()
	scene.add_child(world)
	player = load("res://scripts/player.gd").new()
	scene.add_child(player)
	player.city_world = world
	player.set_physics_process(false)
	car = Node3D.new()
	scene.add_child(car)
	await physics_frame
	await physics_frame
	var visible_props := 0
	var solid_props := 0
	for entry: Dictionary in world.public_props:
		if not entry.node.visible: continue
		visible_props += 1
		if entry.has("collider") and entry.collider.collision_layer==1: solid_props += 1
	_check(solid_props==visible_props and solid_props>100,"Every visible roadside prop has solid collision after placement")
	_check(world.navigation_prop_obstacles().size()==solid_props,"Walking navigation receives the same final prop bounds")
	for key: String in ["tree","Roads/light-curved"]:
		var target := _target_prop(key)
		_check(not target.is_empty(),"Found a real isolated "+key+" for a driving collision test")
		if target.is_empty(): continue
		var at: Vector3 = target.at
		var fraction: float = world.vehicle_motion_fraction(at-Vector3(6,0,0),at+Vector3(6,0,0))
		_check(fraction>0.05 and fraction<0.5,"Swept AI car stops before "+key)
		_drive_at(at-Vector3(6,0,0),PI/2)
		Input.action_press("move_right")
		await _ticks(120)
		Input.action_release("move_right")
		_check(player.position.x>at.x-4.0 and player.position.x<at.x-1.8,"Driven car approaches but cannot pass through "+key)
		_check(world.vehicle_pose_clear(player.position,player.car_shape.rotation.y),"Driven car remains outside the "+key+" collider")
	# A narrow wall beside a car must prevent its nose rotating through the wall.
	var at := Vector3(0,0.2,48)
	var wall: StaticBody3D = world._collision(scene,at+Vector3(1.55,1.5,0),Vector3(0.25,3,10))
	await physics_frame
	_drive_at(at,0.0)
	await _ticks(2)
	player._turn_vehicle_safely(PI/2)
	_check(absf(player.car_shape.rotation.y)>0.1 and absf(player.car_shape.rotation.y)<1.0,"Steering turns partway then stops before the car rotates into a wall")
	_check(world.vehicle_pose_clear(player.position,player.car_shape.rotation.y),"Blocked turn preserves a valid complete vehicle footprint")
	wall.queue_free()
	await physics_frame
	# Reproduce officers overlapping the driven body, without a static wall.
	_drive_at(at,0.0)
	await _ticks(8)
	var settled: Vector3 = player.position
	var crowd: Array[CharacterBody3D] = []
	for offset: Vector3 in [Vector3(-0.9,0,0),Vector3(0.9,0,0),Vector3(0,0,1.8)]:
		var officer := CharacterBody3D.new()
		officer.collision_layer = 4
		officer.collision_mask = 1
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 1.8
		var shape := CollisionShape3D.new()
		shape.shape = capsule
		shape.position.y = 0.9
		officer.add_child(shape)
		scene.add_child(officer)
		officer.position = settled+offset
		crowd.append(officer)
	await _ticks(30)
	_check((player.collision_mask&4)==0,"Driver ignores pedestrian physics bodies")
	_check(Vector2(player.position.x,player.position.z).distance_to(Vector2(settled.x,settled.z))<0.01,"Crowding officers cannot push a parked driven car")
	for officer in crowd: officer.queue_free()
	await physics_frame
	# Restore a known valid pose after an external overlap; repair legacy saves too.
	var safe: Vector3 = player.position
	var building: Rect2 = world.obstacle_rects[0]
	player.position = Vector3(building.get_center().x,0.2,building.get_center().y)
	player.last_safe_vehicle_position = Vector3.INF
	_check(player.recover_vehicle_if_blocked(),"Legacy embedded car is moved to the nearest free exterior pose")
	_check(world.vehicle_pose_clear(player.position,player.car_shape.rotation.y),"Recovered legacy car is outside the building")
	_drive_at(safe,0.0)
	await _ticks(2)
	var recorded: Vector3 = player.last_safe_vehicle_position
	wall = world._collision(scene,recorded+Vector3(4,1.5,0),Vector3(2,3,3))
	await physics_frame
	player.position = recorded+Vector3(4,0,0)
	_check(player.recover_vehicle_if_blocked() and player.position.distance_to(recorded)<0.01,"Unexpected overlap restores the last safe pose instead of pushing through a wall")
	wall.queue_free()
	player.reset_travel()
	_check((player.collision_mask&4)!=0,"Walking collision with people is restored after driving")
	# A sixth interior was added for neighbor parties: actual movement stays there.
	player.position = world.enter_interior("deerfield_social")
	await _ticks(12)
	_check(player.position.x>990.0 and player.position.x<1010.0,"Neighbor interior movement stays in its own room")
	world.exit_interior()
	player.position = Vector3(20,0.2,50)
	game.paused = true
	_check(not player.receive_police_shot(18.0,car),"Paused menus cannot take police damage")
	game.paused = false
	var health: float = game.health
	_check(player.receive_police_shot(18.0,car) and game.health==health-18.0,"Police bullet applies real health damage")
	_check(not player.receive_police_shot(18.0,car),"Brief hit grace prevents simultaneous officers from instantly stacking hits")
	player.police_hit_cooldown = 0.0
	game.health = 10.0
	_check(player.receive_police_shot(18.0,car) and game.status=="lost" and game.health==0.0,"Lethal bullet ends the run")
	_check(not player.receive_police_shot(18.0,car),"Terminal run cannot take further hits")
	var skating_road := Vector3(139,0.2,-75)
	_check(world.is_road_skating_violation(skating_road),"Road carriageway counts as unsafe skating")
	_check(not world.is_road_skating_violation(skating_road+Vector3(5.0,0,0)),"Adjacent sidewalk is not unsafe road skating")
	_check(not world.is_road_skating_violation(world.get_landmark("car_park")),"Parking meetup is not classified as a road")
	var all_crossings_safe := true
	for crossing: Dictionary in world.crosswalks:
		if world.is_road_skating_violation(crossing.center): all_crossings_safe = false
	_check(all_crossings_safe,"Marked crosswalks permit crossing on a board")
	print("VEHICLE SAFETY TESTS: %d checks, %d failures"%[checks,failures])
	scene.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(game.save_path)
	quit(1 if failures else 0)
