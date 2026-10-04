extends SceneTree
## Every selectable destination must work through an actual walking contact.
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MEETING LOCATIONS: "+label)

func _run() -> void:
	var game: Node = root.get_node("Game")
	game.save_path = "res://.godot/meeting-locations-test-save.json"
	game.set_process(false)
	var scene: Node = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.start_game(false)
	scene.set_process(false)
	scene.player.set_physics_process(false)
	scene.population.set_physics_process(false)
	scene.party_guests.set_physics_process(false)
	scene.supplier_encounters.set_physics_process(false)
	game.tutorial_step = 3
	for officer: Dictionary in scene.population.police: officer.node.position = Vector3(145,0.2,120)
	for car: Dictionary in scene.population.vehicles:
		if bool(car.get("police",false)): car.stolen = true
	for location: Dictionary in game.available_locations():
		game.minute = 720.0
		game.inventory.dime_bag = 8
		var id := "site_"+str(location.id)
		game._add_contact(id,"Visitor",45.0)
		game._create_request(game._find_contact(id))
		var request: Dictionary = game.inbox.back()
		var booked: bool = game.schedule_meeting_at(int(request.id),str(location.id),780.0,22.0)
		_check(booked,"Booking accepted for "+str(location.id))
		if not booked: continue
		var meeting: Dictionary = game.active_meetings()[0]
		game.minute = float(meeting.due_minute)-12.0
		var marker: Vector3 = scene.world.get_landmark(str(location.id))
		scene.player.position = marker+Vector3.UP*0.2
		scene.camera.position = scene.player.position+Vector3(24,38,28)
		scene.camera.look_at(scene.player.position)
		scene.population._sync_meetings()
		var key := str(int(meeting.id))
		_check(scene.population.meeting_walks.has(key),"Physical approach exists at "+str(location.id))
		if not scene.population.meeting_walks.has(key): continue
		var walk: Dictionary = scene.population.meeting_walks[key]
		for tick in 3200:
			scene.population._update_meeting_walks(1.0/30.0,false)
			if walk.state=="waiting": break
			if tick%20==0: await physics_frame
		_check(walk.state=="waiting","Contact reaches the actual rendezvous at "+str(location.id))
		scene.player.position = walk.node.position+Vector3(0.6,0,0)
		scene._update_location()
		_check(scene.complete_in_person(int(meeting.id)),"Face-to-face handoff works at "+str(location.id))
		# Remove this completed fixture's departing body before testing the next.
		scene.population._remove_meeting_actor(key)
		await physics_frame
	scene._release_audio(scene)
	await create_timer(0.15).timeout
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(game.save_path)
	print("MEETING LOCATIONS TESTS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
