extends SceneTree
## Exercise the real menu buttons and world interaction dispatcher, not a second
## implementation of the campaign. Test state is isolated from the player's save.

var checks := 0
var failures := 0
var game: Node
var scene: Node

func _initialize() -> void:
	call_deferred("_run")

func _check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("UI CHECK: "+label)

func _settle() -> void:
	for i in range(3):
		await process_frame

func _find_button(node:Node,fragment:String) -> Button:
	if node is Button and fragment in node.text and node.is_visible_in_tree():
		return node
	for child in node.get_children():
		var found:Button=_find_button(child,fragment)
		if found:
			return found
	return null

func _press(fragment:String) -> void:
	var button:Button=_find_button(scene.ui,fragment)
	_check(button!=null,"Button exists: "+fragment)
	if button:
		button.pressed.emit()
	await _settle()

func _run() -> void:
	game=root.get_node("Game")
	game.save_path="res://.godot/interface-test-save.json"
	game.restart_game()
	game.set_process(false)
	scene=load("res://main.tscn").instantiate()
	root.add_child(scene)
	await _settle()
	_check(scene.ui.title_screen.visible,"Title appears before starting")
	await _press("START A NEW STORY")
	# Pursuits have their own spatial tests. Keep this test's staged customer
	# handoff clear so subsequent shop/interior UI assertions remain independent.
	for officer in scene.population.police:
		officer.node.position=Vector3(140,0.3,110)
	_check(scene.started and scene.ui.hud.visible,"Start button enables actual play")
	scene.ui.show_page("backpack")
	await _settle()
	await _press("SPLIT INTO SIX")
	_check(game.tutorial_step==1 and game.inventory.dime_bag==6,"Backpack packages stock through button")
	scene.ui.close_page()
	scene.player.position=scene.population.friend.position+Vector3(1,0,0)
	scene.interact()
	_check(game.tutorial_step==2 and game.cash==42,"World E handoff sells to Milo")
	scene.ui.show_page("messages")
	await _settle()
	await _press("SAVE MILO")
	_check(game.contacts.size()==1 and game.inbox.is_empty(),"Saving contact allows time before a repeat request")
	game.advance_time(90.0)
	await _settle()
	_check(game.inbox.size()>0,"Milo texts after the introductory cooldown")
	await _press("ARRANGE A MEETING")
	_check(scene.ui.page=="schedule","Request opens meeting form")
	await _press("CONFIRM MEETING")
	_check(game.active_meetings().size()==1,"Form schedules a real meeting")
	var meeting:Dictionary=game.active_meetings()[0]
	scene.player.position=scene.world.get_landmark(meeting.location_id)
	scene._update_location()
	scene.camera.position=scene.player.position+Vector3(24,38,28)
	scene.camera.look_at(scene.player.position)
	scene.camera.size=37.0
	scene.population.set_physics_process(false)
	scene.player.set_physics_process(false)
	scene.ui.show_page("agenda")
	await _settle()
	await _press("WAIT UNTIL")
	_check(is_equal_approx(game.minute,float(meeting.due_minute)-30.0) and not game.paused,"Agenda wait leaves thirty minutes for the visible approach")
	var actor_key:String=str(int(meeting.id))
	var approach_start:Vector3=scene.population.meeting_actors[actor_key].position
	for tick in range(120):
		game.advance_time(3.0/60.0)
		scene.population._physics_process(1.0/60.0)
		if tick%30==0: await physics_frame
	var saved_actor_position:Vector3=scene.population.meeting_actors[actor_key].position
	_check(saved_actor_position.distance_to(approach_start)>2.0 and scene.population.meeting_walks[actor_key].state=="approaching","Contact visibly approaches while the normal campaign clock runs")
	var saved_cooldown:float=game.contacts[0].next_request_minute
	scene._capture_world_state()
	game.save_game()
	scene.start_game(true)
	meeting=game.active_meetings()[0]
	actor_key=str(int(meeting.id))
	_check(scene.population.meeting_actors.has(actor_key),"JSON reload normalizes meeting IDs for actor lookup")
	_check(scene.population.meeting_actors[actor_key].position.distance_to(saved_actor_position)<0.01,"Continue preserves the approaching contact without a visible teleport")
	_check(is_equal_approx(float(game.contacts[0].next_request_minute),saved_cooldown),"Continue preserves customer cooldown during an appointment")
	await _settle()
	_check(game.world_state.meeting_walks.size()==1,"Load change signals preserve the captured meeting walk")
	# Advance both the clock and actual walkers so a frozen clock cannot hide
	# a client who would arrive after the appointment has already expired.
	for tick in range(1800):
		if scene.population.meeting_actor_in_reach(int(meeting.id),4.0):
			break
		game.advance_time(3.0/60.0)
		scene.population._physics_process(1.0/60.0)
		if meeting.status!="scheduled": break
		if tick%30==0:
			await physics_frame
	_check(scene.population.meeting_actor_in_reach(int(meeting.id),4.0),"Client physically walks into handoff range")
	_check(game.minute<=float(meeting.due_minute)+10.0 and meeting.status=="scheduled","Waiting on site never incurs a late arrival penalty")
	saved_actor_position=scene.population.meeting_actors[actor_key].position
	scene._capture_world_state()
	game.save_game()
	scene.start_game(true)
	meeting=game.active_meetings()[0]
	_check(scene.population.meeting_actor_in_reach(int(meeting.id),4.0) and scene.population.meeting_actors[actor_key].position.distance_to(saved_actor_position)<0.01,"Continue preserves an arrived contact's position and handoff readiness")
	for officer in scene.population.police:
		officer.node.position=Vector3(140,0.3,110)
	var prior_relationship:float=game.contacts[0].relationship
	scene.interact()
	_check(meeting.status=="completed","Scheduled client handoff works in world")
	_check(float(game.contacts[0].relationship)>=prior_relationship+7.0,"Early arrival earns the full fair punctual relationship reward")
	_check(game.total_sales==2,"Tutorial and client sales counted once")
	scene.population.set_physics_process(true)
	scene.player.set_physics_process(true)
	scene.player.position=scene.world.get_landmark("market")
	scene._update_location()
	scene.interact()
	await _settle()
	_check(scene.ui.page=="shop","Market E opens contextual shop")
	var sandwiches:int=game.inventory.sandwich
	await _press("BUY ONE")
	_check(game.inventory.sandwich==sandwiches+1,"Market button purchases food")
	await _press("STEP INSIDE")
	_check(scene.world.current_interior=="market" and scene.player.position.x>400,"Market entry changes to furnished interior")
	scene.interact()
	_check(scene.world.current_interior=="" and scene.player.position.x<400,"Interior exit returns outside")
	for page_id in ["contacts","agenda","suppliers","backpack","map","tuition","pause","help"]:
		scene.ui.show_page(page_id)
		await _settle()
		_check(scene.ui.body.get_child_count()>0,"Page renders: "+page_id)
	scene.ui.close_page()
	game.reputation=22
	game.cash=1000
	scene.player.position=scene.world.get_landmark("auto_dealer")
	scene._update_location()
	scene.interact()
	await _settle()
	await _press("PURCHASE VEHICLE")
	_check(game.vehicle_owned,"Actual dealer UI grants owned vehicle")
	scene.ui.close_page()
	scene.player.position=scene.world.get_landmark("home")
	scene.enter_building("home")
	scene._capture_world_state()
	game.save_game()
	scene.start_game(true)
	_check(scene.world.current_interior=="home" and scene.player.position.x>400,"Continue restores interior and player position")
	scene.player.position=scene.world.exit_interior()+Vector3(0,0.3,0)
	game.paused=true
	game.minute=1440+550
	scene.player.position=scene.world.get_landmark("classroom")
	scene._update_location()
	scene.interact()
	_check(game.classes_attended==2,"Actual lecture hall allows attendance")
	game.cash=4000
	scene.ui.show_page("tuition")
	await _settle()
	_check(_find_button(scene.ui,"MAKE A PAYMENT")!=null,"Tuition victory reachable from phone")
	game.pay_tuition(game.tuition_remaining)
	await _settle()
	_check(scene.ui.page=="ending" and game.status=="won","Winning creates terminal result screen")
	var escape:=InputEventAction.new()
	escape.action="pause_game"
	escape.pressed=true
	scene._unhandled_input(escape)
	_check(scene.ui.page=="ending","Escape cannot dismiss the terminal result and trap the player")
	_check(_find_button(scene.ui,"START A NEW STORY")!=null,"End screen offers restart")
	print("INTERFACE TESTS: %d checks, %d failures"%[checks,failures])
	scene._release_audio(scene)
	await create_timer(0.15).timeout
	scene.queue_free()
	await _settle()
	DirAccess.remove_absolute(game.save_path)
	quit(1 if failures>0 else 0)
