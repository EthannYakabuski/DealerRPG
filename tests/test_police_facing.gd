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
