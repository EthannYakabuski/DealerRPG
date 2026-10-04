extends SceneTree
## Native presentation fixtures; real decisions are exercised by interface tests.
var scene: Node
var state: Node

func _initialize() -> void:
	call_deferred("_run")

func _capture(file: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var directory:=ProjectSettings.globalize_path("res://build/screenshots/supplier-social")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join(file+".png"))
	print("Captured supplier-social/"+file)

func _focus(key: String) -> void:
	await process_frame
	await process_frame
	for node in scene.ui.body.find_children("*","Control",true,false):
		if node.get_meta("focus_key","")==key: node.grab_focus()

func _run() -> void:
	state=root.get_node("Game")
	state.save_path="res://.godot/supplier-social-capture-save.json"
	state.set_process(false)
	scene=load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.start_game(false)
	state.split_flower()
	state.tutorial_sell()
	state.add_tutorial_contact()
	state.cash=250
	state.minute=1320
	scene.ui.set_controller_active(true)
	scene.ui.show_page("suppliers")
	scene.ui.toast_timer=0
	await create_timer(2.8).timeout
	await _capture("available-order")
	await _focus("supplier_1_details")
	await _capture("discovery-hints")
	state.supplier_progress[1].unlocked=true
	state.supplier_progress[1].successful_meetings=3
	state.supplier_progress[1].next_order_minute=state.minute+2880
	state.supplier_progress[2].referral_received=true
	scene.ui.show_page("suppliers")
	await _focus("supplier_1_details")
	await _capture("supplier-cooldown")
	scene.ui.close_page()
	scene.supplier_encounters._sync()
	var encounter:Dictionary=scene.supplier_encounters.actors["supplier_2"]
	encounter.node.position=encounter.target
	encounter.node.visible=true
	encounter.state="waiting"
	scene._teleport(encounter.node.position+Vector3(0.9,0,0))
	scene.interact()
	await _focus("supplier_chat_sable")
	await _capture("introduction-question")
	scene.supplier_conversation_action("sable")
	await _focus("supplier_chat_three")
	await _capture("introduction-followup")
	scene.supplier_conversation_action("three")
	await _capture("introduction-complete")
	scene.ui.close_page()
	var host:Dictionary=state.contacts[0]
	host.relationship=70
	for index in range(7): state._add_contact("capture_friend_%d"%index,["Ana","Cam","Devi","Eli","Finn","Gia","Hugo"][index],70)
	var invitation:Dictionary=state._create_npc_party_invitation(host)
	invitation.supplier_present=true
	scene.ui.show_page("messages")
	await _capture("party-invitation")
	state.accept_party_invitation(int(invitation.id))
	scene.ui.show_page("agenda")
	await _capture("party-agenda")
	state.minute=float(invitation.start_minute)
	state.advance_time(0.1)
	scene.ui.show_page("contacts")
	await _capture("npc-host-status")
	scene.ui.close_page()
	scene.enter_building("deerfield_social")
	state.paused=true
	scene._update_location()
	scene.ui.show_page("home")
	await _capture("guest-house-options")
	scene.ui.close_page()
	state.minute=float(invitation.start_minute)+35.0
	for guest:Dictionary in state.party_summary().guests: state.mark_party_guest_arrived(str(guest.contact_id))
	scene.party_guests.reset()
	scene.party_guests._sync()
	state.paused=true
	scene.ui.toast_timer=0
	await _capture("neighbor-party-room")
	# Maximum home gathering: eight contacts plus the visiting supplier. Use the
	# actual interior slots and models with arrival timing fixed for this image.
	scene._teleport(scene.world.exit_interior())
	state.active_party.status="ended"
	state.minute+=200.0
	state.reputation=8
	state.supplier_progress[1].unlocked=false
	scene.player.position=scene.world.get_landmark("home")
	scene._update_location()
	state.host_party()
	if state._party_guest("supplier_1").is_empty(): state._add_party_supplier(true)
	for contact:Dictionary in state.contacts: state.invite_party_contact(str(contact.id))
	state.minute+=60
	for guest:Dictionary in state.party_summary().guests: state.mark_party_guest_arrived(str(guest.contact_id))
	scene.enter_building("home")
	scene.party_guests.reset()
	scene.party_guests._sync()
	state.paused=true
	scene.ui.toast_timer=0
	await _capture("home-nine-guest-room")
	state.minute=2*1440.0+780.0
	scene.ui.show_page("agenda")
	await _capture("afternoon-class")
	scene._release_audio(scene)
	await create_timer(0.15).timeout
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(state.save_path)
	quit()
