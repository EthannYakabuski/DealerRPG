extends SceneTree
## Native visual review of the meeting card and short transaction feedback.

var scene: Node
var state: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	state=root.get_node("Game")
	state.save_path="res://.godot/feedback-capture-save.json"
	state.set_process(false)
	scene=load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.start_game(false)
	state.paused=true
	state.split_flower()
	state.tutorial_sell()
	state.add_tutorial_contact()
	state.advance_time(90)
	state.schedule_meeting(int(state.inbox[0].id),"library",90,22)
	state.minute=float(state.active_meetings()[0].due_minute)-12
	scene.ui.toast_timer=0
	scene.ui._update_hud()
	await create_timer(3).timeout
	await _capture("meeting-card")
	# A presentation fixture; actual transaction values are covered by test_feedback.
	state.feedback_event.emit("sale",44)
	await create_timer(0.35).timeout
	await _capture("transaction-feedback")
	state.minute=float(state.active_meetings()[0].due_minute)+7
	scene.ui._update_hud()
	await create_timer(2.8).timeout
	await _capture("meeting-late")
	state.reputation=2
	state._maybe_referral(state.contacts[0])
	scene.ui.show_page("messages")
	await _capture("referral-questions")
	var introduction:Dictionary=state.pending_introductions()[0]
	state.ask_introduction(int(introduction.id),"referrer")
	state.ask_introduction(int(introduction.id),"connection")
	await process_frame
	await process_frame
	for button in scene.ui.body.find_children("*","Button",true,false):
		if button.text=="SAVE CONTACT": button.grab_focus()
	await _capture("referral-answers")
	scene.ui.show_page("contacts")
	scene.ui.set_controller_active(true)
	await _capture("contacts-controller")
	scene.ui.show_page("suppliers")
	await _capture("night-suppliers")
	scene.ui.show_postpone_meeting(int(state.active_meetings()[0].id))
	await _capture("in-person-choices")
	var citizen:Dictionary=scene.population.citizens[0]
	scene.ui.show_conversation(state.street_conversation(str(citizen.id),str(citizen.name)))
	await _capture("street-conversation")
	# Presentation fixtures for the live gathering. Walking and physical reach
	# use their own integration tests; these views exercise the actual UI/state.
	scene.ui.close_page()
	for meeting:Dictionary in state.active_meetings(): state.cancel_meeting(int(meeting.id))
	state.resolve_introduction(int(introduction.id),"accept")
	state.reputation=8
	state.cash=200
	state.heat=0
	state.minute=1090
	scene.player.position=scene.world.get_landmark("home")
	scene._update_location()
	scene.ui.show_page("home")
	await _capture("party-host")
	state.host_party()
	for contact:Dictionary in state.contacts: state.invite_party_contact(str(contact.id))
	scene.ui.show_page("contacts")
	await _capture("party-invitations")
	state.minute+=30
	for guest:Dictionary in state.party_summary().guests: state.party_guest_arrived(str(guest.contact_id))
	scene.ui.show_page("contacts")
	await _capture("party-guest-list")
	var guest_id:String=str(state.contacts[0].id)
	var context:Dictionary=state.party_guest_view(guest_id)
	context.actor_id="party:"+guest_id
	context.party_guest=true
	context.district="Deerfield party"
	scene.ui.show_conversation(context)
	await _capture("party-conversation")
	scene.ui.close_page()
	scene.enter_building("home")
	state.paused=true
	scene.party_guests.reset()
	scene.party_guests._sync()
	for guest:Dictionary in scene.party_guests.guests.values():
		load("res://scripts/npc_emote.gd").play(guest.node,"music" if int(guest.slot)%2==0 else "happy",4.0)
	await create_timer(1.0).timeout
	scene.ui.toast_timer=0
	await _capture("party-emotes")
	scene._release_audio(scene)
	await create_timer(0.15).timeout
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(state.save_path)
	quit()

func _capture(file:String) -> void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var dir:String=ProjectSettings.globalize_path("res://build/screenshots/feedback")
	DirAccess.make_dir_recursive_absolute(dir)
	var captured:Image=root.get_texture().get_image()
	captured.save_png(dir.path_join(file+".png"))
	print("Captured feedback/"+file)
