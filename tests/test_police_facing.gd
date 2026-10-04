extends SceneTree
## Real physics and campaign transactions: visible heading, proximity and walls.
var game: Node
var scene: Node3D
var world: Node3D
var player: Node3D
var population: Node3D
var checks := 0
var failures := 0
const CAMPUS := Vector3(0,0.2,48)
const CITY := Vector3(-60,0.2,-17)

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("POLICE FACING: "+label)

func _run() -> void:
	game = root.get_node("Game")
	game.save_path = "res://.godot/police-facing-test-save.json"
	game.restart_game()
	game.set_process(false)
	scene = Node3D.new()
	root.add_child(scene)
	world = load("res://scripts/world.gd").new()
	scene.add_child(world)
	player = load("res://scripts/player.gd").new()
	scene.add_child(player)
	player.set_physics_process(false)
	population = load("res://scripts/population.gd").new()
	scene.add_child(population)
	population.setup(world,player)
	population.set_physics_process(false)
	await physics_frame
	await _test_officers()
	await _test_cruiser()
	await _test_transactions_and_pursuit()
	await _test_road_skating()
	await _test_melee_stun()
	await _test_police_fire()
	await _test_cruiser_routes()
	scene.queue_free()
	await process_frame
	await process_frame
	if FileAccess.file_exists(game.save_path): DirAccess.remove_absolute(game.save_path)
	print("POLICE FACING TESTS: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

func _reset(at: Vector3 = CAMPUS) -> void:
	game.restart_game()
	game.set_process(false)
	game.paused = false
	player.reset_travel()
	player.position = at
	population.pursuit = false
	population.escape_seconds = 0.0
	population.arrest_seconds = 0.0
	population.stolen_vehicle = false
	population.crime_position = Vector3(120,0.2,110)
	population.crime_age = 10.0
	for officer: Dictionary in population.police:
		officer.node.position = Vector3(135,0.2,110)
		officer.node.rotation.y = 0.0
		officer.hp = 150.0
		officer.stun = 0.0
		officer.alert = 0.0
		officer.retiring = false
		officer.nav_path = PackedVector3Array()
		officer.nav_index = 0
		officer.nav_target = Vector3.INF
		officer.shot_cooldown = 0.0
		officer.aim_seconds = 0.0
	for car: Dictionary in population.vehicles:
		if bool(car.get("police",false)):
			car.node.position = Vector3(135,0.2,-110)
			car.node.rotation.y = 0.0
			car.stolen = false
			car.occupied = false

func _place(officer: Dictionary, offset: Vector3, facing: Vector3) -> void:
	officer.node.position = player.position+offset
	officer.node.rotation.y = population._heading(facing)

func _ordinary_handoff() -> void:
	population.pursuit = false
	game.report_crime(14.0)

func _test_officers() -> void:
	_reset()
	var officer: Dictionary = population.police[0]
	_place(officer,Vector3(0,0,-8),Vector3.BACK)
	await physics_frame
	_ordinary_handoff()
	_check(population.pursuit,"an unobstructed handoff eight metres ahead is seen")
	officer.node.rotation.y = PI
	_ordinary_handoff()
	_check(not population.pursuit,"an ordinary handoff behind an officer is not seen")
	officer.node.rotation.y = PI/2.0
	_ordinary_handoff()
	_check(population.pursuit,"a handoff directly beside an officer is inside the broad forward view")
	officer.node.rotation.y = deg_to_rad(109.0)
	_ordinary_handoff()
	_check(population.pursuit,"109 degrees from forward is within the 220 degree cone")
	officer.node.rotation.y = deg_to_rad(111.0)
	_ordinary_handoff()
	_check(not population.pursuit,"111 degrees from forward is outside the 220 degree cone")
	officer.node.rotation.y = deg_to_rad(-109.0)
	_ordinary_handoff()
	_check(population.pursuit,"the opposite edge also sees 109 degrees from forward")
	officer.node.rotation.y = deg_to_rad(-111.0)
	_ordinary_handoff()
	_check(not population.pursuit,"the opposite rear blind spot starts beyond 110 degrees")
	_place(officer,Vector3(0,0,-19.1),Vector3.BACK)
	_ordinary_handoff()
	_check(not population.pursuit,"looking toward a distant handoff does not exceed sight range")
	_place(officer,Vector3(0,0,-5.9),Vector3.FORWARD)
	_ordinary_handoff()
	_check(population.pursuit,"a handoff within six metres is noticed even from behind")
	_place(officer,Vector3(0,0,-6.1),Vector3.FORWARD)
	_ordinary_handoff()
	_check(not population.pursuit,"rear awareness does not extend beyond six metres")
	_place(officer,Vector3(-2,0,0),Vector3.LEFT)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4,3.0,8.0)
	shape.shape = box
	wall.add_child(shape)
	wall.position = player.position+Vector3(-1,1,0)
	scene.add_child(wall)
	await physics_frame
	_ordinary_handoff()
	_check(not population.pursuit,"near awareness cannot detect a handoff through a solid wall")
	_place(officer,Vector3(-8,0,0),Vector3.RIGHT)
	await physics_frame
	_ordinary_handoff()
	_check(not population.pursuit,"forward view cannot see a handoff through a solid wall")
	wall.queue_free()
	await physics_frame
	_ordinary_handoff()
	_check(population.pursuit,"the same forward handoff becomes visible when the wall is removed")
	officer.hp = 0.0
	_ordinary_handoff()
	_check(not population.pursuit,"a defeated officer cannot witness a handoff")
	officer.hp = 150.0
	officer.stun = 2.0
	_ordinary_handoff()
	_check(not population.pursuit,"a stunned officer cannot witness a handoff")
	officer.stun = 0.0
	officer.retiring = true
	_ordinary_handoff()
	_check(not population.pursuit,"a departing reinforcement does not start a new handoff pursuit")
	_reset(CITY)
	_place(officer,Vector3(0,0,-2),Vector3.BACK)
	_ordinary_handoff()
	_check(not population.pursuit,"campus police retain jurisdiction even for close handoffs")
	_place(population.police[4],Vector3(0,0,-8),Vector3.BACK)
	await physics_frame
	_ordinary_handoff()
	_check(population.pursuit,"city police witness handoffs in their own district")

func _test_cruiser() -> void:
	_reset(CITY)
	var cruiser: Dictionary = {}
	for car: Dictionary in population.vehicles:
		if bool(car.get("police",false)): cruiser = car
	cruiser.node.position = player.position+Vector3(0,0,-8)
	cruiser.node.rotation.y = 0.0
	await physics_frame
	_ordinary_handoff()
	_check(population.pursuit,"a road patrol notices handoffs ahead of its actual heading")
	cruiser.node.rotation.y = PI
	_ordinary_handoff()
	_check(not population.pursuit,"a road patrol does not see handoffs behind the vehicle")
	cruiser.node.rotation.y = PI/2.0
	_ordinary_handoff()
	_check(population.pursuit,"a road patrol sees handoffs directly to its side within the broader cone")
	cruiser.node.position = player.position+Vector3(0,0,-5.9)
	_ordinary_handoff()
	_check(population.pursuit,"close awareness also applies to the road patrol")
	cruiser.occupied = true
	_ordinary_handoff()
	_check(not population.pursuit,"player-occupied cruisers cannot witness crimes")
	cruiser.occupied = false
	cruiser.stolen = true
	_ordinary_handoff()
	_check(not population.pursuit,"stolen cruisers cannot witness crimes")
	_reset()
	cruiser.node.position = player.position+Vector3(0,0,-2)
	_ordinary_handoff()
	_check(not population.pursuit,"road patrols do not override campus jurisdiction")

func _test_transactions_and_pursuit() -> void:
	_reset()
	var officer: Dictionary = population.police[0]
	_place(officer,Vector3(0,0,-8),Vector3.FORWARD)
	await physics_frame
	_check(game.split_flower() and game.tutorial_sell() and game.add_tutorial_contact(),"initial guided sale still completes without a police incident")
	game.minute = 800.0
	game.player_location_id = "campus_quad"
	game.meetings.append({"id":991,"type":"client","contact_id":"milo","contact_name":"Milo","location_id":"campus_quad","due_minute":800.0,"quantity":1,"price":22.0,"status":"scheduled"})
	var cash_before: float = game.cash
	var bags_before: int = game.inventory.dime_bag
	_check(game.complete_meeting(991) and game.cash==cash_before+22.0 and game.inventory.dime_bag==bags_before-1,"an actual ordinary client transaction completes behind a patrol")
	_check(not population.pursuit,"the actual client transaction behind a patrol does not initiate pursuit")
	population.pursuit = true
	population.crime_position = CAMPUS+Vector3(20,0,0)
	population.escape_seconds = 2.0
	officer.alert = 5.0
	var last_known: Vector3 = population.crime_position
	game.report_crime(14.0)
	_check(population.crime_position==last_known and population.escape_seconds==2.0,"an unseen handoff cannot disclose a new location or reset an existing escape")
	population._update_police(0.05,false)
	_check(population.escape_seconds>2.0 and population.crime_position==last_known,"pursuit sight also respects facing and retains the last known location")
	_place(officer,Vector3(0,0,-8),Vector3.BACK)
	await physics_frame
	population._update_police(0.05,false)
	_check(population.escape_seconds==0.0 and population.crime_position==player.position,"turning toward the student reacquires sight and resets the escape timer")
	_reset()
	_place(officer,Vector3(0,0,-8),Vector3.FORWARD)
	game.report_crime(65.0)
	_check(population.pursuit and officer.alert>0.0,"loud crime or a reported sting dispatches independently of visual facing")

func _test_road_skating() -> void:
	var road: PackedVector3Array = world.map_roads[1]
	var at: Vector3 = road[0].lerp(road[1],0.45)+Vector3.UP*0.2
	var direction := (road[1]-road[0]).normalized()
	var side := Vector3(-direction.z,0,direction.x)
	_reset(at)
	player.skateboarding = true
	_place(population.police[4],Vector3(0,0,-2),Vector3.BACK)
	population._update_police(0.1,false)
	_check(not population.pursuit,"foot patrols do not independently cite road skating")
	var cruiser: Dictionary = {}
	for car: Dictionary in population.vehicles:
		if bool(car.get("police",false)) and not car.parked: cruiser = car
	cruiser.node.position = at-direction*8.0
	cruiser.node.rotation.y = population._heading(direction)
	await physics_frame
	population._update_police(0.1,false)
	_check(population.pursuit,"a cruiser spots skateboarding on the actual carriageway")
	_reset(at+side*6.4)
	player.skateboarding = true
	cruiser.node.position = player.position-direction*8.0
	cruiser.node.rotation.y = population._heading(direction)
	await physics_frame
	population._update_police(0.1,false)
	_check(not population.pursuit,"riding the parallel sidewalk is not a road-skating offense")
	var crossing: Dictionary = world.crosswalks[2]
	_reset(crossing.center+Vector3.UP*0.2)
	player.skateboarding = true
	cruiser.node.position = player.position-crossing.tangent*8.0
	cruiser.node.rotation.y = population._heading(crossing.tangent)
	await physics_frame
	population._update_police(0.1,false)
	_check(not population.pursuit,"using an authored pedestrian crossing does not trigger a skating pursuit")

func _test_melee_stun() -> void:
	_reset()
	var officer: Dictionary = population.police[0]
	_place(officer,Vector3(0,0,1.4),Vector3.FORWARD)
	player.facing = Vector3.BACK
	population.pursuit = true
	game.active_pursuit_escape_seconds = 25.0
	population.arrest_seconds = 2.2
	await physics_frame
	population.attack("punch")
	_check(is_equal_approx(float(officer.stun),1.0),"a successful punch gives a pursuing officer one full second of stun")
	var before: Vector3 = officer.node.position
	var health: float = game.health
	for tick in 9: population._update_police(0.1,false)
	_check(officer.node.position.distance_to(before)<0.001 and officer.node.velocity==Vector3.ZERO,"a stunned officer cannot move or physically continue the pursuit")
	_check(population.arrest_seconds<2.2 and game.status=="playing" and game.health==health,"stun prevents arrest progress and police fire")
	population.pursuit = false
	game.report_crime(14.0)
	_check(not population.pursuit,"the stunned officer also cannot witness a new handoff")
	population.pursuit = true
	population._update_police(0.11,false)
	population._update_police(0.1,false)
	_check(officer.stun==0.0 and officer.node.position.distance_to(before)>0.01,"the officer can resume moving after the stun expires")
	_place(officer,Vector3(0,0,1.5),Vector3.FORWARD)
	population.attack("kick")
	_check(is_equal_approx(float(officer.stun),1.0),"a successful kick gets the same full-second police stun")

func _test_police_fire() -> void:
	_reset()
	var officer: Dictionary = population.police[0]
	_place(officer,Vector3(0,0,-12),Vector3.BACK)
	population.pursuit = true
	game.active_pursuit_escape_seconds = 20.0
	population._update_police_fire(officer,1.0,true,12.0)
	_check(game.health==100.0,"officers do not shoot below the 25-second escape tier")
	game.active_pursuit_escape_seconds = 25.0
	population._update_police_fire(officer,0.4,true,12.0)
	_check(game.health==100.0 and officer.weapon.visible,"the first police shot has a visible aiming windup")
	population._update_police_fire(officer,0.4,true,12.0)
	_check(game.health==91.0 and population.get_node_or_null("PoliceShot")!=null,"tier25 fire applies a bounded hit with a visible tracer")
	population._update_police_fire(officer,1.0,true,12.0)
	_check(game.health==91.0,"one officer cannot fire repeatedly during its cooldown")
	officer.shot_cooldown = 0.0
	officer.aim_seconds = 0.0
	population._update_police_fire(officer,1.0,false,12.0)
	_check(game.health==91.0 and not officer.weapon.visible,"losing sight cancels aim rather than scheduling a later hit")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8,3,0.5)
	shape.shape = box
	wall.add_child(shape)
	wall.position = player.position+Vector3(0,1,-6)
	scene.add_child(wall)
	await physics_frame
	population._update_police_fire(officer,1.0,true,12.0)
	_check(game.health==91.0,"a wall appearing during aim prevents the shot even with a stale sight flag")
	wall.queue_free()
	await physics_frame
	population.pursuit = false
	population._update_police_fire(officer,1.0,true,12.0)
	_check(game.health==91.0,"peaceful officers do not shoot merely because the campaign tier is high")

func _test_cruiser_routes() -> void:
	game.restart_game()
	game.set_process(false)
	population.reset_population()
	population.set_physics_process(false)
	player.position = Vector3(-59,0.2,18)
	var cruiser: Dictionary = {}
	for car: Dictionary in population.vehicles:
		if bool(car.get("police",false)) and not car.parked: cruiser = car
	cruiser.node.position = Vector3(-137,0.16,-30)
	cruiser.node.rotation.y = 0.0
	population.pursuit = true
	population.crime_position = player.position
	game.active_pursuit_escape_seconds = 15.0
	var original: PackedVector3Array = cruiser.route
	population._update_cruiser_routes(0.1,false)
	_check(not bool(cruiser.get("chasing",false)) and cruiser.route==original,"cruisers remain on routine patrol below the 20-second tier")
	game.active_pursuit_escape_seconds = 20.0
	population._update_cruiser_routes(0.1,false)
	_check(cruiser.chasing and cruiser.route!=original and cruiser.speed>10.0,"tier20 dispatch creates an active road pursuit")
	var start: Vector3 = cruiser.node.position
	var on_road := true
	var clear := true
	var max_step := 0.0
	for tick in 3600:
		var before: Vector3 = cruiser.node.position
		population._update_cruiser_routes(1.0/60.0,false)
		population._update_traffic(1.0/60.0,false)
		max_step = maxf(max_step,before.distance_to(cruiser.node.position))
		if tick%60==0:
			var nearest: Dictionary = population._nearest_cruiser_road(cruiser.node.position)
			if cruiser.node.position.distance_to(nearest.point)>4.5: on_road = false
			if not world.vehicle_pose_clear(cruiser.node.position,cruiser.node.rotation.y): clear = false
		if tick%300==0: await physics_frame
		if cruiser.node.position.distance_to(player.position)<5.0: break
	_check(cruiser.node.position.distance_to(player.position)<5.0 and start.distance_to(cruiser.node.position)>40.0,"the cruiser actually closes in through connected roads")
	_check(on_road and clear and max_step<0.3,"cruiser chase stays on roads, clears static props and never teleports")
	population.pursuit = false
	game.end_pursuit()
	population._update_cruiser_routes(0.1,false)
	_check(not cruiser.chasing and cruiser.rejoining,"escaped cruiser takes a road route back to normal patrol")
	for tick in 6000:
		population._update_cruiser_routes(1.0/60.0,false)
		population._update_traffic(1.0/60.0,false)
		if tick%300==0: await physics_frame
		if not cruiser.rejoining: break
	_check(not cruiser.rejoining and cruiser.route==original,"the cruiser physically rejoins its original patrol loop")
	var parked: Dictionary = {}
	for car: Dictionary in population.vehicles:
		if bool(car.get("police",false)) and car.parked: parked = car; break
	_check(not parked.is_empty(),"parked marked cruisers are recognized as police officers")
	if parked.is_empty(): return
	var bay: Vector3 = parked.node.position
	population.pursuit = true
	game.active_pursuit_escape_seconds = 20.0
	population._update_cruiser_routes(0.1,false)
	_check(not parked.parked and parked.chasing and parked.route.size()>4,"parked police can leave their actual bay and join a tier20 response")
	for tick in 4200:
		population._update_cruiser_routes(1.0/60.0,false)
		population._update_traffic(1.0/60.0,false)
		if tick%300==0: await physics_frame
		if parked.node.position.distance_to(bay)>35.0: break
	_check(parked.node.position.distance_to(bay)>35.0,"parked cruiser physically traverses the parking aisle and exit")
	_check(int(parked.get("chase_merge_index",-1))==0 and parked.speed>10.0,"after leaving its lot the cruiser uses normal chase speed and can keep replanning")
	population.pursuit = false
	game.end_pursuit()
	population._update_cruiser_routes(0.1,false)
	for tick in 9000:
		population._update_cruiser_routes(1.0/60.0,false)
		population._update_traffic(1.0/60.0,false)
		if tick%300==0: await physics_frame
		if parked.parked: break
	_check(parked.parked and parked.route.is_empty() and parked.node.position.distance_to(bay)<1.0,"originally parked cruiser returns to its vacant bay after the chase")
	population.pursuit = true
	game.active_pursuit_escape_seconds = 20.0
	population._update_cruiser_routes(0.1,false)
	var reservations: Array[Dictionary] = []
	for car: Dictionary in population.vehicles:
		if car.node!=parked.node: reservations.append(car)
	var index := 0
	for slot: Dictionary in world.parking_slots:
		if int(slot.lot)==int(parked.lot):
			reservations[index].reserved_parking_id = int(slot.id)
			index += 1
	population.pursuit = false
	game.end_pursuit()
	population._update_cruiser_routes(0.1,false)
	_check(bool(parked.get("awaiting_parking",false)),"a full home lot leaves a returning cruiser waiting safely for a free bay")
	for car: Dictionary in reservations: car.reserved_parking_id = -1
	population._update_cruiser_routes(2.1,false)
	_check(not parked.awaiting_parking and parked.rejoining,"the cruiser retries and resumes its return when a parking space becomes free")
