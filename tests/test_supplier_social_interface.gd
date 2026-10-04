extends SceneTree
## Real controller choices for discoveries, supplier introductions and invitations.

var checks := 0
var failures := 0
var game: Node
var scene: Node

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SUPPLIER SOCIAL UI CHECK: " + label)

func _settle() -> void:
	for tick in range(4): await process_frame

func _tap(code: int) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventJoypadButton.new()
		event.button_index=code
		event.pressed=pressed
		Input.parse_input_event(event)
		await _settle()

func _key(node: Node, key: String) -> Control:
	if node is Control and node.get_meta("focus_key","")==key: return node
	for child in node.get_children(true):
		var found:=_key(child,key)
		if found: return found
	return null

func _text(fragment: String) -> bool:
	for node in scene.ui.body.find_children("*","Label",true,false):
		if fragment in node.text: return true
	return false

func _choose(key: String) -> void:
	var button:=_key(scene.ui.body,key)
	_check(button!=null,"Available controller action: "+key)
	if button:
		button.grab_focus()
		await _tap(JOY_BUTTON_A)

func _meet(tier: int) -> void:
	scene.ui.close_page()
	game.paused=true
	scene.supplier_encounters._sync()
	var id:=""
	for entry: Dictionary in game.supplier_encounters():
		if int(entry.tier)==tier and bool(entry.active): id=str(entry.id)
	_check(id!="" and scene.supplier_encounters.actors.has(id),"Tier%d has its real discoverable encounter"%tier)
	if id=="" or not scene.supplier_encounters.actors.has(id): return
	var actor: Dictionary=scene.supplier_encounters.actors[id]
	actor.node.position=actor.target
	actor.node.visible=true
	actor.state="waiting"
	scene._teleport(actor.node.position+Vector3(0.9,0,0))
	scene._update_location()
	scene.interact()
	await _settle()
	_check(scene.ui.page=="supplier_conversation","Physical introduction opens the supplier dialog")

func _run() -> void:
	game=root.get_node("Game")
	game.save_path="res://.godot/supplier-social-ui-test-save.json"
	game.set_process(false)
	scene=load("res://main.tscn").instantiate()
	root.add_child(scene)
	await _settle()
	scene.start_game(false)
	scene.population.set_physics_process(false)
	scene.player.set_physics_process(false)
	scene.supplier_encounters.set_physics_process(false)
	game.split_flower()
	game.tutorial_sell()
	game.add_tutorial_contact()
	game.cash=1000.0
	game.reputation=100
	scene.ui.set_controller_active(true)
	scene.ui.show_page("suppliers")
	await _settle()
	_check(_key(scene.ui.body,"supplier_0_quantity")!=null,"Rae is immediately available after the tutorial")
	_check(_key(scene.ui.body,"supplier_1_quantity")==null and _key(scene.ui.body,"supplier_2_quantity")==null,"Reputation alone cannot expose locked order controls")
	_check(_text("Freight lane") and _text("three pickups") and not _text("Requires 8 reputation"),"Locked cards explain the actual discoveries instead of obsolete reputation gates")
	game.minute=1320.0
	await _meet(1)
	await _choose("supplier_chat_introduce")
	_check(bool(game.supplier_catalog()[1].unlocked) and _text("CONNECTION SAVED"),"Controller introduction saves Sable and shows the result")
	await _tap(JOY_BUTTON_B)
	_check(scene.ui.page=="" and scene.conversation_id=="" and scene.supplier_encounters.conversation_id=="","Cancelling the supplier dialog releases the actor")
	# State tests earn this referral with three actual pickups. Here it is a
	# fixture so this test isolates the physical dialog, focus, and answer routing.
	game.supplier_progress[1].successful_meetings=3
	game.supplier_progress[2].referral_received=true
	var pending_before_intro:int=scene.ui._pending_phone_count()
	_check(pending_before_intro>0,"Persistent supplier introduction is counted by the phone indicator")
	scene.ui.show_page("messages")
	await _settle()
	_check(_text("PERSONAL INTRODUCTION") and _text("three completed pickups") and _text("Sable"),"Referral clues remain readable as a phone conversation")
	await _choose("supplier_intro_supplier_2")
	_check(scene.destination=="east_trail" and scene.ui.page=="","The referral routes to its introduction instead of creating a sale")
	await _meet(2)
	var first: Control=root.gui_get_focus_owner()
	_check(first!=null and str(first.get_meta("focus_key","")).begins_with("supplier_chat_"),"The introduction question starts on a usable controller choice")
	await _tap(JOY_BUTTON_DPAD_DOWN)
	_check(root.gui_get_focus_owner()!=first,"D-pad moves between introduction answers")
	await _choose("supplier_chat_sable")
	_check(_key(scene.ui.body,"supplier_chat_three")!=null,"The next question replaces the answered choices")
	await _choose("supplier_chat_three")
	_check(bool(game.supplier_catalog()[2].unlocked) and _text("CONNECTION SAVED"),"Both controller answers unlock the earned connection")
	_check(scene.ui._pending_phone_count()==pending_before_intro-1,"Completing the introduction clears its pending phone indicator")
	scene.ui.show_page("suppliers")
	await _settle()
	_check(scene.conversation_id=="","Navigating away from the introduction also releases the actor")
	game.supplier_progress[1].next_order_minute=game.minute+2880.0
	game.changed.emit()
	await _settle()
	_check(_text("RESTOCKING") and _text("Next order Day 3 / 22:00"),"Cooldown shows an exact two-day request deadline")
	_check(_key(scene.ui.body,"supplier_1_quantity")==null,"Restocking connection cannot submit an early order")
	var host: Dictionary=game.contacts[0]
	host.relationship=70.0
	var invitation: Dictionary=game._create_npc_party_invitation(host)
	var pending_before_party:int=scene.ui._pending_phone_count()
	scene.ui.show_page("messages")
	await _settle()
	_check(_text("PARTY INVITATION") and _text(str(invitation.text)),"NPC invitation displays the actual host message")
	await _choose("party_accept_%d"%int(invitation.id))
	_check(scene.ui.page=="agenda" and _text("You're on the guest list"),"Controller acceptance adds the gathering to Agenda")
	_check(scene.ui._pending_phone_count()==pending_before_party-1,"Accepted invitation clears its pending phone count")
	await _choose("party_agenda_%d"%int(invitation.id))
	_check(scene.destination==str(invitation.location_id) and scene.ui.page=="","Party agenda routes to its actual residential venue")
	game.minute=float(invitation.start_minute)
	game.advance_time(0.1)
	scene.ui.show_page("contacts")
	await _settle()
	_check(_text(str(invitation.host_name).to_upper()+"'S PARTY") and _text("Hosted by "+str(invitation.host_name)),"Active NPC gathering is labelled with its host")
	game.player_location_id="deerfield_social"
	scene.ui.show_page("home")
	await _settle()
	_check(not _text("Sleep until") and _key(scene.ui.body,"party_host")==null,"A guest house does not offer the player's sleeping or hosting actions")
	game.minute=2*1440.0+780.0
	scene.ui.show_page("agenda")
	await _settle()
	_check(_text("Class at 14:00") and _text("Arrive by 15:00") and _text("finishes at 16:00"),"Agenda uses the third day's afternoon class schedule")
	scene.ui.show_page("campus")
	await _settle()
	_check(_text("13:40 until 15:00") and not _text("08:40 until 10:00"),"Campus service explains the matching afternoon arrival window")
	# Sable can be discovered at a party. Ordering from the phone there must not
	# create another Sable at a pickup while her physical party visit is ongoing.
	game._add_contact("ui_party_peer","Ana",70.0)
	game.minute=2*1440.0+1320.0
	game.supplier_progress[1].next_order_minute=0.0
	scene.player.position=scene.world.get_landmark("home")
	scene._update_location()
	_check(game.host_party(),"Late gathering starts for the pickup-overlap regression")
	if game._party_guest("supplier_1").is_empty(): game._add_party_supplier(true)
	var party_end:float=float(game.party_summary().end_minute)
	scene.ui.show_page("suppliers")
	await _settle()
	var party_pickup_preview:float=float(game.supplier_catalog()[1].next_pickup_minute)
	_check(_text("Next pickup: Day %d / %s"%[int(party_pickup_preview/1440.0)+1,game.format_minute(party_pickup_preview)]),"Supplier card previews the party-aware pickup time")
	await _choose("supplier_1_order")
	var arranged:Dictionary={}
	for appointment:Dictionary in game.active_meetings():
		if appointment.type=="supplier" and int(appointment.tier)==1: arranged=appointment
	_check(not arranged.is_empty() and float(arranged.due_minute)>=party_end+30.0 and is_equal_approx(float(arranged.due_minute),party_pickup_preview),"Ordering from the party matches the preview and gives Sable time to leave")
	print("SUPPLIER SOCIAL INTERFACE TESTS: %d checks, %d failures"%[checks,failures])
	scene._release_audio(scene)
	await create_timer(0.15).timeout
	scene.queue_free()
	await _settle()
	DirAccess.remove_absolute(game.save_path)
	quit(1 if failures>0 else 0)
