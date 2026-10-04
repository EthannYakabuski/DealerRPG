extends SceneTree
## Exercise introductions through real actors, menus, range checks and saves.
var game: Node
var scene: Node3D
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SUPPLIER WORLD: " + message)

func _settle() -> void:
	for tick in 3: await process_frame

func _run() -> void:
	game = root.get_node("Game")
	game.save_path = "res://.godot/supplier-world-test-save.json"
	game.set_process(false)
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await _settle()
	scene.start_game(false)
	scene.set_process(false)
	scene.player.set_physics_process(false)
	scene.population.set_physics_process(false)
	scene.party_guests.set_physics_process(false)
	scene.supplier_encounters.set_physics_process(false)
	game.split_flower()
	game.tutorial_sell()
	game.add_tutorial_contact()
	game.minute = 1330.0
	var opportunities: Array = game.supplier_encounters()
	_check(not opportunities.is_empty(), "Sable has an actual late-night encounter before unlocking")
	if opportunities.is_empty():
		quit(1)
		return
	var entry: Dictionary = opportunities[0]
	var id := str(entry.id)
	var target: Vector3 = scene.world.get_landmark(str(entry.location_id))
	scene.player.position = target + Vector3(1,0.2,1)
	scene.camera.position = scene.player.position + Vector3(24,38,28)
	scene.camera.look_at(scene.player.position)
	scene._update_location()
	scene.supplier_encounters._sync()
	_check(scene.supplier_encounters.actors.has(id), "Introduction creates a physical actor")
	var record: Dictionary = scene.supplier_encounters.actors[id]
	var start: Vector3 = record.node.position
	_check(scene.population._point_offscreen(start), "New supplier appears beyond the camera and walks in")
	_check(not scene.supplier_encounters.in_reach(id), "Distant or approaching supplier cannot be spoken to")
	scene.conversation_id = "supplier:" + id
	scene.supplier_conversation_action("introduce")
	_check(not bool(game.supplier_catalog()[1].unlocked), "World dispatcher rejects an introduction from across the map")
	for tick in 150:
		scene.supplier_encounters._physics_process(1.0/60.0)
		if tick % 10 == 0: await physics_frame
	_check(start.distance_to(record.node.position) > 1.0, "Supplier visibly progresses along a real walking path")
	var saved_at: Vector3 = record.node.position
	scene._capture_world_state()
	game.save_game()
	scene.start_game(true)
	await _settle()
	record = scene.supplier_encounters.actors[id]
	_check(record.node.position.distance_to(saved_at) < 0.01, "Continue preserves the supplier's approach position")
	# Complete the approach under simulation, without advancing hunger or class.
	for tick in 5000:
		scene.supplier_encounters._physics_process(1.0/30.0)
		if record.state == "waiting": break
		if tick % 10 == 0: await physics_frame
	_check(record.state == "waiting", "Supplier reaches the remote rendezvous without getting stuck")
	scene.player.position = record.node.position + Vector3(1.0,0,0)
	scene._update_location()
	scene.interact()
	await _settle()
	_check(scene.ui.page == "supplier_conversation", "Nearby supplier opens the introduction menu")
	var view: Dictionary = game.supplier_encounter_view(id)
	_check(not view.choices.is_empty(), "Introduction has a usable conversation choice")
	if not view.choices.is_empty(): scene.supplier_conversation_action(str(view.choices[0].id))
	_check(bool(game.supplier_catalog()[1].unlocked), "Speaking face to face permanently adds Sable as a supplier")
	scene.ui.close_page()
	_check(scene.conversation_id == "" and scene.supplier_encounters.conversation_id == "", "Closing the conversation releases the physical actor")
	game.save_game()
	game.supplier_progress[1].unlocked = false
	_check(game.load_game(false) and bool(game.supplier_catalog()[1].unlocked), "Supplier access survives save and reload")
	_check(game.supplier_order(1,1), "Newly introduced supplier accepts a future pickup")
	var order: Dictionary = game.active_meetings()[0]
	scene.population._sync_meetings()
	_check(not scene.population.meeting_actors.has(str(int(order.id))), "Booking immediately after an introduction cannot create a second visible supplier")
	game.cancel_meeting(int(order.id))
	# A real neighboring venue, including the same Sable body walking over.
	scene.enter_building("deerfield_social")
	_check(scene.world.current_interior == "", "Neighbor apartment is private outside an accepted party")
	game.contacts[0].relationship = 75.0
	var invite: Dictionary = game._create_npc_party_invitation(game.contacts[0])
	invite.supplier_present = true
	var before_cash: float = game.cash
	_check(game.accept_party_invitation(int(invite.id)), "Strong contact's invitation can be accepted")
	game.minute = float(invite.start_minute) + 35.0
	game._resolve_party_invitations()
	scene.party_guests._sync()
	_check(game.cash == before_cash and game.party_summary().mode == "npc", "Friend hosts the gathering without charging the player supplies")
	_check(scene.party_guests.location_id == "deerfield_social", "Guests head to the neighbor apartment instead of player home")
	_check(scene.party_guests.guests.supplier_1.node == record.node and not scene.supplier_encounters.actors.has(id), "Party reuses Sable's existing body without duplicating her")
	for guest: Dictionary in scene.party_guests.guests.values():
		_check(guest.target.distance_to(scene.world.get_landmark("deerfield_social")) < 0.1, "NPC-party guests target the neighbor's entrance")
	for tick in 6000:
		scene.party_guests._physics_process(1.0/30.0)
		if scene.party_guests.guests.values().all(func(guest: Dictionary): return guest.state == "inside"): break
		if tick % 10 == 0: await physics_frame
	_check(scene.party_guests.guests.values().all(func(guest: Dictionary): return guest.state == "inside"), "Host and supplier walk to the neighboring door and enter")
	scene.enter_building("deerfield_social")
	scene.party_guests._physics_process(0.016)
	_check(scene.world.current_interior == "deerfield_social", "Accepted active invitation opens the furnished neighbor apartment")
	var host: Node3D = scene.party_guests.guests.milo.node
	scene.player.position = host.position + Vector3(0.7,0,0)
	scene.interact()
	_check(scene.conversation_id == "party:milo", "Can talk to the host inside their apartment")
	var relationship: float = game.contacts[0].relationship
	scene.conversation_action("party:milo", "smalltalk")
	_check(game.contacts[0].relationship == relationship + 3.0, "Social visit improves relationship")
	scene.conversation_action("party:milo", "offer")
	_check(game.cash == before_cash + 24.0, "Visiting player can choose an individual sale")
	scene.ui.close_page()
	scene._capture_world_state()
	game.save_game()
	scene.start_game(true)
	await _settle()
	scene.party_guests._physics_process(0.016)
	_check(scene.world.current_interior == "deerfield_social" and scene.party_guests.guests.milo.node.visible, "Continue restores the NPC party in its correct interior")
	_check(bool(game._party_guest("milo").purchased), "Individual sales remain completed after continuing")
	game.minute = float(game.party_summary().end_minute) + 1.0
	game._resolve_party()
	scene.party_guests._sync()
	_check(scene.party_guests.guests.milo.state == "exiting", "Neighbor party closes with guests walking out")
	game.supplier_progress[1].unlocked = false
	game.minute = ceilf(game.minute / 1440.0) * 1440.0 + 1320.0
	scene.supplier_encounters._sync()
	_check(not scene.supplier_encounters.actors.has("supplier_1"), "An unintroduced departing visitor cannot also appear at her hangout")
	for tick in 700:
		scene.party_guests._physics_process(1.0/30.0)
		if tick % 10 == 0: await physics_frame
	_check(scene.party_guests.guests.values().all(func(guest: Dictionary): return guest.state == "leaving"), "Guests can leave the neighbor room without furniture trapping them")
	scene._release_audio(scene)
	await create_timer(0.15).timeout
	scene.queue_free()
	await _settle()
	DirAccess.remove_absolute(game.save_path)
	print("SUPPLIER WORLD TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
