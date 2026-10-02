extends SceneTree
var game: Node
var scene: Node
var checks:=0
var failures:=0

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("PARTY WORLD: "+message)

func _settle() -> void:
	for tick in 3: await process_frame

func _walk(ticks: int) -> void:
	for tick in ticks:
		game.advance_time(0.05)
		scene.party_guests._physics_process(1.0/60.0)
		if tick%10==0: await physics_frame

func _run() -> void:
	game=root.get_node("Game")
	game.save_path="res://.godot/party-world-test-save.json"
	game.set_process(false)
	scene=load("res://main.tscn").instantiate()
	root.add_child(scene)
	await _settle()
	scene.start_game(false)
	scene.player.set_physics_process(false)
	scene.population.set_physics_process(false)
	scene.party_guests.set_physics_process(false)
	game.split_flower()
	game.tutorial_sell()
	game.add_tutorial_contact()
	game._add_contact("street_citizen_03","Jules",45.0)
	game.reputation=5
	game.cash=100
	game.minute=1020
	scene.player.position=scene.world.get_landmark("home")+Vector3(0,0.2,3)
	scene.camera.position=scene.player.position+Vector3(24,38,28)
	scene.camera.look_at(scene.player.position)
	scene._update_location()
	var stock: int=game.inventory.dime_bag
	_check(game.host_party(),"Host a live evening party")
	_check(game.cash==75 and game.inventory.dime_bag==stock,"Supplies cost cash but never automatically consume product")
	_check(game.invite_party_contact("milo") and game.invite_party_contact("street_citizen_03"),"Known contacts accept individual invitations")
	scene.party_guests._sync()
	_check(scene.party_guests.guests.size()==2,"Each invite creates one actual walking guest")
	_check(scene.party_guests.guests.street_citizen_03.node==scene.population._citizens_by_id.citizen_03.node,"Street contact keeps their original body rather than creating a duplicate pedestrian")
	for guest: Dictionary in scene.party_guests.guests.values():
		if not guest.has("citizen_id"): _check(scene.population._point_offscreen(guest.node.position),"New guests begin outside the visible camera area")
	var origin: Vector3=scene.party_guests.guests.milo.node.position
	await _walk(120)
	var walked: Vector3=scene.party_guests.guests.milo.node.position
	_check(origin.distance_to(walked)>1,"Guest physically walks towards the apartment")
	scene._capture_world_state()
	game.save_game()
	scene.start_game(true)
	await _settle()
	_check(scene.party_guests.guests.milo.node.position.distance_to(walked)<0.01,"Save/continue preserves the walking guest without teleporting")
	for tick in 2400:
		await _walk(1)
		if scene.party_guests.guests.milo.state=="inside" and scene.party_guests.guests.street_citizen_03.state=="inside": break
	_check(scene.party_guests.guests.milo.state=="inside" and scene.party_guests.guests.street_citizen_03.state=="inside","Both guests walk to the entrance then enter the apartment")
	for guest: Dictionary in scene.party_guests.guests.values():
		if guest.state!="inside": print("PARTY WALK DIAGNOSTIC ",guest.contact_id," ",guest.state," position=",guest.node.position," target=",guest.target," clock=",game.minute," paused=",game.paused," status=",game.status," nav=",guest.nav_path," index=",guest.nav_index)
	_check(game.inventory.dime_bag==stock and game.cash==75,"Arrivals grant no automatic sales")
	scene.enter_building("home")
	scene.party_guests._physics_process(0.016)
	var actor: Node3D=scene.party_guests.guests.milo.node
	_check(actor.visible and actor.position.x>400,"Party guest is visible inside the furnished home")
	scene.player.position=actor.position+Vector3(0.7,0,0)
	scene.interact()
	_check(scene.ui.page=="conversation" and scene.conversation_id=="party:milo","Nearby guest opens the actual conversation UI")
	scene.conversation_action("party:milo","smalltalk")
	_check(bool(game._party_guest("milo").chatted),"Catching up records relationship-building conversation")
	scene.conversation_action("party:milo","offer")
	_check(game.cash==99 and game.inventory.dime_bag==stock-1,"Only explicit guest offer completes a sale")
	scene.conversation_action("party:milo","offer")
	_check(game.cash==99 and game.inventory.dime_bag==stock-1,"Repeated click cannot double-sell the same guest")
	scene.ui.close_page()
	scene._capture_world_state()
	game.save_game()
	scene.start_game(true)
	await _settle()
	scene.party_guests._physics_process(0.016)
	_check(scene.world.current_interior=="home" and scene.party_guests.guests.milo.node.visible and bool(game._party_guest("milo").purchased),"Indoor save restores guests and their individual sale progress")
	game.advance_time(float(game.party_summary().end_minute)-game.minute+1)
	scene.party_guests._sync()
	_check(scene.party_guests.guests.milo.state=="exiting","Party end makes indoor guests head for the exit")
	_check(scene.party_guests.nearest_guest().is_empty(),"Expired party cannot sell to departing guests")
	await _walk(600)
	for guest: Dictionary in scene.party_guests.guests.values():
		if guest.state=="exiting": print("PARTY EXIT DIAGNOSTIC ",guest.contact_id," position=",guest.node.position," clock=",game.minute," paused=",game.paused)
	_check(scene.party_guests.guests.is_empty() or scene.party_guests.guests.milo.state=="leaving","Guests leave through the apartment exit")
	print("PARTY WORLD TESTS: %d checks, %d failures"%[checks,failures])
	scene._release_audio(scene)
	await create_timer(0.15).timeout
	scene.queue_free()
	await _settle()
	DirAccess.remove_absolute(game.save_path)
	quit(1 if failures else 0)
