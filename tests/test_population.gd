extends SceneTree
## Actual 3D world integration: physics, actors, witnesses, vehicles, interiors.

var checks := 0
var failures := 0
var scene: Node3D
var world: Node3D
var player: Node3D
var population: Node3D
var game: Node
var crimes := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	game = root.get_node("Game")
	game.save_path = "res://.godot/population-test-save.json"
	game.restart_game()
	game.set_process(false)
	game.crime_committed.connect(func(_severity: float) -> void: crimes += 1)
	_setup_inputs()
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
	player.attacked.connect(population.attack)
	await physics_frame
	await _test_world_population()
	await _test_police()
	await _test_player()
	await _test_surface_traversal()
	await _test_vehicles()
	await _test_meetings()
	await _test_dynamic_simulation()
	await _test_traffic_endurance()
	_test_world_state_save()
	scene.queue_free()
	await process_frame
	await process_frame
	if FileAccess.file_exists(game.save_path): DirAccess.remove_absolute(game.save_path)
	print("POPULATION TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: "+message)

func _setup_inputs() -> void:
	for action: String in ["move_left","move_right","move_up","move_down","sprint"]:
		if not InputMap.has_action(action): InputMap.add_action(action)

func _test_world_population() -> void:
	_check(population.citizens.size()==42,"world has fourteen groups of three pedestrians")
	_check(population.police.size()==7,"campus and city patrols spawn")
	_check(population.vehicles.size()==12+world.parked_car_spawns.size(),"all world parking stall positions are populated")
	var group: Dictionary = population.citizens[0]
	_check(group.group==population.citizens[1].group and group.route==population.citizens[1].route,"friends share routes and purpose")
	_check(group.node.position.distance_to(population.citizens[1].node.position)>1.4,"group members start with natural shoulder spacing")
	var clear_tutorial := true
	for actor: Dictionary in population.citizens+population.police:
		if actor.node.position.distance_to(Vector3(20,0.2,50))<5.0 or actor.node.position.distance_to(population.friend.position)<5.0: clear_tutorial = false
	_check(clear_tutorial,"tutorial spawn and Milo have five metres of clear space")
	for officer: Dictionary in population.police:
		_check(population._is_campus(officer.node.position)==bool(officer.campus),"patrol begins inside its own jurisdiction")
	var anim: AnimationPlayer = ActorVisuals.animator(player.visual)
	_check(anim!=null and anim.get_animation_list().size()>20,"supplied player model has working animation library")
	var original_goal: String = str(group.goal)
	game.minute = 1240.0
	population._update_citizen_schedule()
	_check(str(group.goal)!=original_goal,"pedestrian goals respond to time of day")
	var rect: Rect2 = world.obstacle_rects[0]
	var start: Vector3 = Vector3(rect.position.x-4.0,0.2,rect.get_center().y)
	var target: Vector3 = Vector3(rect.end.x+4.0,0.2,rect.get_center().y)
	var route: PackedVector2Array = population.navigation.get_point_path(population._nearest_open_cell(start),population._nearest_open_cell(target))
	_check(route.size()>2,"navigation finds a detour around actual building footprint")
	var valid := true
	for point: Vector2 in route:
		if rect.grow(0.2).has_point(point): valid = false
	_check(valid,"navigation detour never passes through the building")
	var all_targets_reachable := true
	for pedestrian: Dictionary in population.citizens:
		var pedestrian_route: PackedVector3Array = pedestrian.route
		for index in pedestrian_route.size():
			var goal: Vector3 = population._safe_pedestrian_target(pedestrian_route[index]+Vector3(pedestrian.offset))
			for obstacle: Rect2 in world.obstacle_rects:
				if obstacle.grow(-0.25).has_point(Vector2(goal.x,goal.z)): all_targets_reachable = false
	_check(all_targets_reachable,"every group offset destination stays outside a building footprint")
	await physics_frame

func _reset_crime() -> void:
	game.restart_game()
	game.set_process(false)
	population.pursuit = false
	population.arrest_seconds = 0.0
	population.escape_seconds = 0.0
	population.stolen_vehicle = false
	for officer: Dictionary in population.police:
		officer.hp = 150.0
		officer.alert = 0.0
		officer.stun = 0.0
		officer.node.position = Vector3(135.0,0.2,110.0)
	for citizen: Dictionary in population.citizens: citizen.panic = 0.0

func _test_police() -> void:
	_reset_crime()
	player.position = Vector3(0.0,0.2,48.0)
	population.police[0].node.position = Vector3(2.0,0.2,48.0)
	await physics_frame
	game.report_crime(14.0)
	_check(population.pursuit,"even a first low-heat sale is pursued when witnessed")
	_check(game.heat>=40.0,"witnessed crime raises an actionable police alert")
	_check(float(population.citizens[0].panic)==0.0,"quiet dealing does not make every nearby civilian flee")
	population.police[0].node.position = player.position+Vector3(1,0,0)
	population.arrest_seconds = 2.29
	await physics_frame
	population._update_police(0.05,false)
	_check(game.status=="lost" and game.ending_reason.contains("police"),"close sustained pursuit creates police-specific hardcore loss")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	_check(str(saved["ending_reason"]).contains("police"),"arrest reason is persisted before ending notification")
	_reset_crime()
	player.position = Vector3(-60,0.2,-17)
	population.police[0].node.position = player.position+Vector3(1,0,0)
	await physics_frame
	game.report_crime(14.0)
	_check(not population.pursuit,"campus officer does not enforce an unrelated city jurisdiction")
	population.police[4].node.position = player.position+Vector3(1,0,0)
	await physics_frame
	game.report_crime(14.0)
	_check(population.pursuit,"city officer pursues a witnessed commercial-district crime")
	_reset_crime()
	player.position = Vector3(-2,0.2,48)
	population.police[0].node.position = Vector3(2,0.2,48)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6,3,8)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0,1.5,48)
	scene.add_child(wall)
	await physics_frame
	game.report_crime(14.0)
	_check(not population.pursuit,"solid walls block crime witnesses")
	wall.queue_free()
	await physics_frame
	population.pursuit = true
	population.escape_seconds = 9.99
	for officer: Dictionary in population.police: officer.node.position = Vector3(135,0.2,110)
	population._update_police(0.05,false)
	_check(not population.pursuit,"ten seconds out of sight escapes a pursuit")
	player.position = Vector3(-60,0.2,-17)
	var cruiser: Dictionary = {}
	for car: Dictionary in population.vehicles:
		if bool(car.get("police",false)): cruiser = car
	var cruiser_start: Vector3 = cruiser.node.position
	cruiser.node.position = player.position+Vector3(8,0,0)
	await physics_frame
	game.report_crime(14.0)
	_check(population.pursuit and float(population.police[4].alert)>0.0,"roaming cruiser witnesses a city crime and calls officers")
	population._update_police(2.5,false)
	_check(game.status=="playing" and population.arrest_seconds==0.0,"cruiser sighting cannot arrest the player without a nearby officer")
	cruiser.node.position = cruiser_start
	population.citizens[0].hp = 0.0
	population.pursuit = true
	population.reset_population()
	_check(not population.pursuit and population.citizens[0].hp==100.0,"restart resets police and defeated citizens")
	population.set_physics_process(false)
	await physics_frame

func _test_player() -> void:
	_reset_crime()
	game.paused = false
	for center: float in [600.0,680.0,760.0,840.0,920.0]:
		player.position = Vector3(center,0.3,4.5)
		player.velocity = Vector3.ZERO
		await physics_frame
		player._physics_process(1.0/60.0)
		_check(absf(player.position.x-center)<0.1,"interior at x%d stays within its actual room"%int(center))
	player.position = Vector3(0,0.2,48)
	player.velocity = Vector3.ZERO
	game.energy = 100.0
	Input.action_press("move_down")
	Input.action_press("sprint")
	await physics_frame
	player._physics_process(0.5)
	_check(game.energy<100.0,"sprinting consumes stamina")
	Input.action_release("move_down")
	Input.action_release("sprint")
	var depleted: float = game.energy
	player._physics_process(0.5)
	_check(game.energy>depleted,"standing still recovers stamina")
	player.position = Vector3(920,0.3,4.5)
	player.toggle_skateboard()
	_check(not player.skateboarding,"skateboard cannot be ridden inside library")
	player.position = Vector3(0,0.2,48)
	player.toggle_skateboard()
	_check(player.skateboarding,"skateboard equips outside")
	game.inventory["skateboard"] = 0
	player._physics_process(1.0/60.0)
	_check(not player.skateboarding,"discarding board also unequips it")
	game.inventory["pistol"] = 1
	game.inventory["ammo"] = 2
	player.attack_cooldown = 0.0
	var previous_crimes := crimes
	player.attack("shoot")
	_check(game.inventory["ammo"]==1 and crimes==previous_crimes+1,"gunfire consumes one round and reports one crime")
	player._physics_process(1.0/60.0)
	_check(player.weapon.visible,"equipped weapon is visible during a shot")
	var cooldown: float = player.attack_cooldown
	game.paused = true
	player._physics_process(2.0)
	_check(player.attack_cooldown==cooldown,"pausing cannot refresh combat cooldown for free")
	game.paused = false
	player.attack_cooldown = 0.0
	game.energy = 0.0
	player.attack("kick")
	_check(player.attack_cooldown==0.0,"exhausted player cannot kick repeatedly")
	game.energy = 100.0
	player.facing = Vector3(0,0,1)
	population.citizens[0].node.position = player.position+Vector3(0,0,1.3)
	population.citizens[0].hp = 100.0
	await physics_frame
	player.attack("kick")
	_check(population.citizens[0].hp==68.0 and population.citizens[0].stun>0.0,"kick damages an NPC and lets hit animation play")
	await create_timer(0.15).timeout

func _test_surface_traversal() -> void:
	game.restart_game()
	game.set_process(false)
	player.reset_travel()
	_check(is_equal_approx(world.walkable_surface_height(Vector3(32,0,61)),0.23),"raised campus island supports feet at its actual rendered top")
	_check(is_equal_approx(world.walkable_surface_height(Vector3(22,0,61)),0.115),"campus paving height matches its visible slab")
	_check(is_zero_approx(world.walkable_surface_height(Vector3(43,0,63))),"bare grass keeps zero support height instead of a global floating offset")
	_check(world.walkable_surface_height(Vector3(71,0,18))>=0.095,"road ribbons provide their rendered asphalt height")
	_check(is_equal_approx(world.walkable_surface_height(Vector3(81,0,66)),0.055),"parking pavement provides its rendered height")
	player.position = Vector3(32,0.0,63)
	player.skateboarding = true
	player.board.rotation.y = 0.0
	player._update_grounding()
	var curb_board: AABB = ActorVisuals.bounds_of(player.board)
	_check(curb_board.position.y>0.24,"front wheels clear an island edge while the deck centre is still over lower paving")
	player.position = Vector3(25,0.3,61)
	player.velocity = Vector3.ZERO
	player.skateboarding = true
	player.facing = Vector3.RIGHT
	Input.action_press("move_right")
	var supported := true
	var deck_support_peak := 0.0
	for tick in range(120):
		player._physics_process(1.0/60.0)
		var board_bounds: AABB = ActorVisuals.bounds_of(player.board)
		var wheels: float = player.position.y+board_bounds.position.y
		var beneath: float = world.walkable_surface_height(player.position)
		deck_support_peak = maxf(deck_support_peak,wheels)
		if wheels<beneath-0.001: supported = false
		if tick%20==0: await physics_frame
	Input.action_release("move_right")
	_check(player.position.x>43.0,"skateboard crosses slab and island edges without getting blocked by new curbs")
	_check(supported and deck_support_peak>0.24,"actual skateboard mesh remains above paving throughout traversal")
	for tick in 45: player._physics_process(1.0/60.0)
	var final_board: AABB = ActorVisuals.bounds_of(player.board)
	_check(absf(player.position.y+final_board.position.y-0.015)<0.005,"wheels settle back onto bare grass after leaving raised paving")
	player.skateboarding = false
	player._physics_process(1.0/60.0)
	_check(absf(player.visual.global_position.y)<0.005,"walking shoes return to grass height after dismount")
	var citizen: CharacterBody3D = population.citizens[0].node
	var old_position: Vector3 = citizen.position
	citizen.position = Vector3(32,0.15,61)
	population._ground_person(citizen)
	var model: Node3D = citizen.get_meta("model")
	_check(absf(model.global_position.y-0.23)<0.005,"pedestrian shoes share the same raised surface support")
	citizen.position = old_position
	population._ground_person(citizen)

func _test_vehicles() -> void:
	_reset_crime()
	player.reset_travel()
	var parked: Dictionary = {}
	for car: Dictionary in population.vehicles:
		if car.parked:
			parked = car
			break
	_check(not parked.is_empty(),"parked vehicles can be found in actual stalls")
	if parked.is_empty(): return
	var origin: Vector3 = parked.node.position
	player.position = origin+Vector3(2,0,0)
	await physics_frame
	population.toggle_vehicle()
	_check(player.vehicle==parked.node and population.stolen_vehicle,"unowned parked car can be stolen")
	_check(parked.node.position.distance_to(origin)<0.01,"entering moves player to the car rather than teleporting the car")
	_check(parked.node.collision_layer==0,"occupied car does not collide with its driver")
	population.toggle_vehicle()
	_check(player.vehicle==null and not population.stolen_vehicle and parked.node.collision_layer==8,"safe exit restores parked-car collision and clears driving flag")
	population.spawn_owned_vehicle()
	var count: int = population.vehicles.size()
	population.spawn_owned_vehicle()
	_check(population.vehicles.size()==count,"owned car spawn is idempotent")
	var owned: Dictionary = population.vehicles.back()
	player.position = owned.node.position+Vector3(2,0,0)
	await physics_frame
	population.toggle_vehicle()
	_check(player.vehicle==owned.node and not population.stolen_vehicle,"legitimate purchased car avoids stolen-vehicle flag")
	population.toggle_vehicle()
	await physics_frame

func _test_meetings() -> void:
	game.restart_game()
	game.split_flower()
	game.tutorial_sell()
	game.add_tutorial_contact()
	game.advance_time(90.0)
	player.position = world.landmarks["cafe"].position
	game.schedule_meeting(int(game.inbox[0].id),"cafe",90.0,24.0)
	var meeting: Dictionary = game.active_meetings()[0]
	var id := str(meeting.id)
	_check(population.meeting_actors.size()==1,"near-term contact begins a physical approach")
	var actor: Node3D = population.meeting_actors[id]
	var initial: Vector3 = actor.position
	_check(population._point_offscreen(actor.position),"meeting contact is generated outside the camera view")
	_check(not population.meeting_actor_in_reach(int(meeting.id)),"approaching contact cannot accept an early handoff")
	var max_step := 0.0
	var previous: Vector3 = actor.position
	var arrived := -1.0
	for tick in range(1800):
		game.minute += 0.05
		population._update_meeting_walks(1.0/60.0,false)
		max_step = maxf(max_step,actor.position.distance_to(previous))
		previous = actor.position
		if tick%60==0: population._sync_meetings()
		if tick%120==0: await physics_frame
		if population.meeting_walks[id].state=="waiting":
			arrived = game.minute
			break
	_check(arrived>=float(meeting.due_minute)-12.05 and arrived<=float(meeting.due_minute)-9.0,"client arrives physically about twelve minutes before appointment")
	_check(initial.distance_to(actor.position)>20.0 and max_step<0.2,"client walks across the world with no visible position jump")
	player.position = actor.position+Vector3(8,0,0)
	_check(not population.meeting_actor_in_reach(int(meeting.id)),"physical handoff rejects an NPC eight metres away")
	player.position = actor.position+Vector3(0.8,0,0)
	await physics_frame
	_check(population.meeting_actor_in_reach(int(meeting.id)),"arrived NPC in direct reach can accept a handoff")
	var snapshot: Array = population.capture_meeting_state()
	game.world_state = {"position":[player.position.x,player.position.y,player.position.z],"interior":"","meeting_walks":snapshot}
	game.save_game()
	actor.position = initial
	population.meeting_walks[id].state = "approaching"
	game.load_game(false)
	population.restore_meeting_state(game.world_state.meeting_walks)
	_check(population.meeting_walks[id].state=="waiting" and population.meeting_actor_in_reach(int(meeting.id)),"save/resume preserves the arrived client's actual position")
	game.advance_time(65.0)
	_check(population.meeting_walks[id].state=="departing","missed client departs on foot instead of disappearing in view")
	var departure: Vector3 = actor.position
	for tick in 120: population._update_meeting_walks(1.0/60.0,false)
	_check(actor.position.distance_to(departure)>1.0,"departing contact visibly walks away")
	player.position = Vector3(140,0.2,110)
	population._update_meeting_walks(1.0/60.0,false)
	_check(population.meeting_actors.is_empty(),"departing contact is removed only after leaving the view")
	await process_frame

func _test_world_state_save() -> void:
	game.restart_game()
	game.world_state = {"position":[920.0,0.3,4.5],"interior":"library","driving":true,"skateboarding":true}
	game.save_game()
	game.world_state = {}
	_check(game.load_game(false) and game.world_state.interior=="library" and game.world_state.position[0]==920.0,"save/load preserves real interior and position")
	_check(not game.world_state.driving and not game.world_state.skateboarding,"loaded interior cannot restore invalid vehicle or skateboard state")
	game.world_state = {"position":[999999.0,0.3,4.5],"interior":""}
	game.save_game()
	game.load_game(false)
	_check(game.world_state.position[0]==20.0,"invalid saved world coordinates recover safely at campus")
	population.police[0].node.position = Vector3(24,0.2,50)
	population.arrest_seconds = 2.1
	population.escape_seconds = 0.4
	var pursuit_state: Dictionary = population.capture_pursuit_state()
	game.world_state = {"position":[23.0,0.3,50.0],"interior":"","pursuit":true,"pursuit_state":pursuit_state}
	game.save_game()
	population.police[0].node.position = Vector3(140,0.2,110)
	population.arrest_seconds = 0.0
	game.load_game(false)
	population.restore_pursuit_state(game.world_state.pursuit_state)
	_check(population.police[0].node.position.distance_to(Vector3(24,0.2,50))<0.01 and is_equal_approx(population.arrest_seconds,2.1),"reload preserves nearby patrol and arrest progress instead of granting a fresh escape")

func _test_dynamic_simulation() -> void:
	game.restart_game()
	population.reset_population()
	population.set_physics_process(false)
	player.position = Vector3(20,0.2,50)
	var first_positions: Array[Vector3] = []
	for actor: Dictionary in population.citizens: first_positions.append(actor.node.position)
	var car_start: Vector3 = population.vehicles[0].node.position
	for tick in range(1200):
		population._physics_process(1.0/60.0)
		if tick%120==0: await physics_frame
	var moving := 0
	var grounded := true
	var clear := true
	for index in population.citizens.size():
		var actor: Node3D = population.citizens[index].node
		if actor.position.distance_to(first_positions[index])>2.0: moving += 1
		if actor.position.y < -0.5 or actor.position.y>1.0: grounded = false
		for obstacle: Rect2 in world.obstacle_rects:
			if obstacle.grow(-0.8).has_point(Vector2(actor.position.x,actor.position.z)): clear = false
	var group_gap := INF
	for index in population.citizens.size():
		var citizen: Dictionary = population.citizens[index]
		if not citizen.node.visible: continue
		for next in range(index+1,population.citizens.size()):
			var other: Dictionary = population.citizens[next]
			if other.node.visible and citizen.group==other.group:
				group_gap = minf(group_gap,population._horizontal_distance(citizen.node.position,other.node.position))
	_check(group_gap>1.15,"walking friends retain visible body spacing after twenty seconds")
	print("SMALLEST FRIEND SPACING: ",group_gap)
	_check(moving>=12,"visible pedestrians make meaningful progress during twenty-second simulation")
	_check(grounded,"pedestrians stay on the ground during sustained simulation")
	_check(clear,"pedestrians stay outside building interiors during sustained simulation")
	_check(population.vehicles[0].node.position.distance_to(car_start)>5.0,"traffic progresses during sustained simulation")

func _test_traffic_endurance() -> void:
	player.position = Vector3(600,0.2,0)
	var movers: Array[Dictionary] = []
	for car: Dictionary in population.vehicles:
		if not car.parked and not car.occupied: movers.append(car)
	var travelled: Array[float] = []
	for car: Dictionary in movers: travelled.append(float(car.get("distance_travelled",0.0)))
	var spacing_ok := true
	for tick in range(18000):
		population._update_traffic(1.0/60.0,true)
		if tick%120==0:
			for index in movers.size():
				for next in range(index+1,movers.size()):
					var a: Node3D = movers[index].node
					var b: Node3D = movers[next].node
					var relative := b.position-a.position
					if a.basis.z.dot(b.basis.z)>0.9 and absf(relative.cross(a.basis.z).y)<1.8 and relative.length()<4.3: spacing_ok = false
	var cruiser_moves := false
	for index in movers.size():
		var distance: float = float(movers[index].get("distance_travelled",0.0))-travelled[index]
		_check(distance>500.0 and float(movers[index].stuck)<15.0,"traffic car %d progresses through five minutes without gridlock"%index)
		if bool(movers[index].get("police",false)) and distance>500.0: cruiser_moves = true
	_check(spacing_ok,"following traffic keeps separate car bodies in the same lane")
	_check(cruiser_moves,"marked police cruiser participates in moving road traffic")
