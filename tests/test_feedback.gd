extends SceneTree
## Verify the live HUD and the same authoritative event path used by web play.

var checks := 0
var failures := 0
var game: Node
var scene: Node
var events: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("FEEDBACK CHECK: "+label)

func _settle() -> void:
	for i in range(3):
		await process_frame

func _has_label(node:Node,text:String) -> bool:
	if node is Label and node.text==text:
		return true
	for child in node.get_children():
		if _has_label(child,text):
			return true
	return false

func _has_event(kind:String,value:float) -> bool:
	for event in events:
		if event.kind==kind and is_equal_approx(event.value,value):
			return true
	return false

func _run() -> void:
	game=root.get_node("Game")
	game.save_path="res://.godot/feedback-test-save.json"
	game.set_process(false)
	game.restart_game()
	scene=load("res://main.tscn").instantiate()
	root.add_child(scene)
	await _settle()
	scene.start_game(false)
	# Evening keeps the new nocturnal supplier appointment earlier than the
	# client fixture, while still exercising the actual first-message delay.
	game.minute=1170.0
	game.paused=true
	scene.population.set_process(false)
	scene.population.set_physics_process(false)
	game.feedback_event.connect(func(kind:String,value:float):events.append({"kind":kind,"value":value}))
	_check(not scene.ui.meeting_card.visible,"No fake countdown before an appointment exists")
	_check(game.split_flower() and _has_event("pack",0),"Packing emits its dedicated sound event")
	var events_before:int=events.size()
	_check(not game.split_flower() and events.size()==events_before,"Failed packing produces no success feedback")
	_check(game.tutorial_sell(),"Tutorial sale succeeds")
	_check(_has_event("sale",20) and _has_label(scene.ui.root,"+$20"),"Actual tutorial transaction displays its exact proceeds")
	events_before=events.size()
	_check(not game.tutorial_sell() and events.size()==events_before,"Repeated handoff cannot duplicate sale feedback")
	_check(game.add_tutorial_contact(),"Tutorial contact saved")
	game.advance_time(90.0)
	_check(_has_event("text",0),"An arriving text emits the notification cue")
	_check(not game.inbox.is_empty(),"Follow-up arrives after its actual wait")
	if game.inbox.is_empty():
		await _cleanup()
		return
	_check(game.schedule_meeting(int(game.inbox[0].id),"library",120,22.25),"Client appointment created")
	game.cash=100
	_check(game.supplier_order(0,1),"Earlier supplier pickup created")
	scene.ui._update_hud()
	var next:Dictionary=game.active_meetings()[0]
	_check(scene.ui.meeting_card.visible and scene.ui.labels.meeting_contact.text==str(next.contact_name),"HUD prioritizes the earliest appointment across both meeting types")
	_check(scene.ui.labels.meeting_heading.text=="NEXT PICKUP" and next.type=="supplier","Supplier pickups appear on the HUD")
	_check("+1 LATER" in scene.ui.labels.meeting_hint.text,"HUD reports the rest of the schedule")
	_check(scene.ui.labels.meeting_place.text==load("res://scripts/game_data.gd").location_name(str(next.location_id)),"Card names the actual rotating pickup location")
	game.paused=false
	var before_route:float=game.minute
	scene.ui.meeting_card.pressed.emit()
	_check(scene.destination==str(next.location_id) and scene.navigation_marker!=null,"Clicking the live card activates existing world directions")
	_check(not game.paused and scene.ui.page=="" and game.minute==before_route,"Directions do not open a dialog or pause the simulation")
	game.paused=true
	var due:float=float(next.due_minute)
	scene.player.position=scene.world.get_landmark(str(next.location_id))
	scene._update_location()
	scene.ui.show_page("agenda")
	var wait_button:Button=null
	for candidate in scene.ui.body.find_children("*","Button",true,false):
		if candidate.text.begins_with("WAIT UNTIL "):
			wait_button=candidate
	_check(wait_button!=null,"Agenda offers an arrival-window wait at the actual meeting location")
	if wait_button:
		wait_button.pressed.emit()
	_check(is_equal_approx(game.minute,due-30.0),"Agenda wait leaves time for the contact to walk in before the agreed deadline")
	_check(not game.paused and scene.ui.page=="","Agenda wait closes the phone so the natural approach can proceed")
	game.paused=true
	game.minute=due-65
	scene.ui._update_hud()
	_check(scene.ui.labels.meeting_countdown.text=="IN 1h 05m","Countdown formats hours and minutes")
	game.minute=due-12.2
	scene.ui._update_hud()
	_check(scene.ui.labels.meeting_countdown.text=="IN 13m","Countdown rounds partial minutes without showing a false due state")
	game.minute=due
	scene.ui._update_hud()
	_check(scene.ui.labels.meeting_countdown.text=="MEET NOW","Due appointment is unmistakable")
	game.minute=due+7
	scene.ui._update_hud()
	_check(scene.ui.labels.meeting_countdown.text=="7m LATE","Late appointment remains actionable and readable")
	var paused_caption:String=scene.ui.labels.meeting_countdown.text
	await create_timer(0.2).timeout
	_check(scene.ui.labels.meeting_countdown.text==paused_caption,"Countdown follows game time, not wall time, while paused")
	_check(game.cancel_meeting(int(next.id)),"Pickup cancellation succeeds")
	scene.ui._update_hud()
	_check(scene.ui.labels.meeting_contact.text=="Milo" and scene.ui.labels.meeting_heading.text=="NEXT MEETING","Finished appointment hands the card to the next client")
	var client:Dictionary=game.active_meetings()[0]
	game.minute=float(client.due_minute)
	game.player_location_id="library"
	var revenue:float=float(client.quantity)*float(client.price)
	_check(game.complete_meeting(int(client.id)),"Scheduled sale succeeds")
	_check(_has_event("sale",revenue) and _has_label(scene.ui.root,"+$%.2f"%revenue),"Scheduled sale displays its real income including fractional dollars")
	scene.ui._update_hud()
	_check(not scene.ui.meeting_card.visible,"Completed agenda clears its HUD card")
	game.player_location_id="market"
	_check(game.buy_item("sandwich"),"Food purchase succeeds")
	_check(_has_event("purchase",-8) and _has_label(scene.ui.root,"-$8"),"Purchase uses separate negative transaction feedback")
	events_before=events.size()
	game.cash=0
	_check(not game.buy_item("sandwich") and events.size()==events_before,"Rejected purchase has no payment or success sound")
	_check(scene.ui.money_feedback.size()<=3,"Rapid transactions keep feedback bounded")
	var event_voice:AudioStreamPlayer=scene.ui.feedback_voices[0]
	event_voice.stream=scene.ui.sounds.sale
	event_voice.play()
	scene.ui._play_sound("click-a")
	_check(event_voice.stream==scene.ui.sounds.sale and event_voice.playing,"UI click cannot replace or stop the sale audio")
	scene.ui.set_sound_enabled(false)
	scene.ui._play_sound("click-a")
	scene.ui._play_feedback_sound("text")
	var any_playing:bool=scene.ui.sfx.playing
	for voice in scene.ui.feedback_voices:
		any_playing=any_playing or voice.playing
	_check(not any_playing and scene.ambient.stream_paused,"Sound switch mutes ambience, clicks and all event voices")
	scene.ui.set_sound_enabled(true)
	scene.ui._play_feedback_sound("pack")
	_check(scene.ui.feedback_voices[0].playing and not scene.ambient.stream_paused,"Sound switch restores all sound categories")
	for sound:String in scene.ui.EVENT_SOUNDS:
		var stream:AudioStreamWAV=scene.ui.sounds[sound]
		_check(stream!=null and stream.get_length()>0.1 and stream.get_length()<1.1,"Compact distinct feedback resource: "+sound)
	await create_timer(2.8).timeout
	_check(scene.ui.money_feedback.is_empty(),"Transaction cards free themselves even with the game paused")
	game.caught_by_police()
	_check(_has_event("caught",0) and scene.ui.page=="ending","Arrest sound survives the transition to the ending screen")
	events_before=events.size()
	game.caught_by_police()
	_check(events.size()==events_before,"Repeated terminal arrest cannot replay the sting")
	await _cleanup()

func _cleanup() -> void:
	print("FEEDBACK TESTS: %d checks, %d failures"%[checks,failures])
	scene._release_audio(scene)
	await create_timer(0.15).timeout
	scene.queue_free()
	await _settle()
	DirAccess.remove_absolute(game.save_path)
	quit(1 if failures>0 else 0)
