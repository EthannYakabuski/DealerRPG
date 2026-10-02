extends SceneTree
## Exercise social decisions through the real dialogs and authoritative state.

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
		push_error("SOCIAL UI CHECK: "+label)

func _settle() -> void:
	for i in range(4): await process_frame

func _button(fragment:String) -> Button:
	for node in scene.ui.body.find_children("*","Button",true,false):
		if fragment in node.text and not node.disabled: return node
	return null

func _key(key:String) -> Control:
	for node in scene.ui.body.find_children("*","Control",true,false):
		if str(node.get_meta("focus_key",""))==key: return node
	return null

func _text(fragment:String) -> bool:
	for node in scene.ui.body.find_children("*","Label",true,false):
		if fragment in node.text: return true
	return false

func _press(fragment:String) -> void:
	var control:=_button(fragment)
	_check(control!=null,"Action exists: "+fragment)
	if control: control.pressed.emit()
	await _settle()

func _run() -> void:
	game=root.get_node("Game")
	game.save_path="res://.godot/social-interface-test-save.json"
	game.set_process(false)
	scene=load("res://main.tscn").instantiate()
	root.add_child(scene)
	await _settle()
	scene.start_game(false)
	game.paused=true
	scene.population.set_physics_process(false)
	scene.population.set_process(false)
	for officer in scene.population.police: officer.node.position=Vector3(-145,0.2,-115)
	game.split_flower()
	game.tutorial_sell()
	game.add_tutorial_contact()
	game.advance_time(90)
	scene.ui.show_page("messages")
	await _settle()
	var tomorrow:=_button("HIT ME UP TOMORROW")
	_check(tomorrow!=null,"Incoming request can be deferred before any meeting is made")
	if tomorrow:
		tomorrow.grab_focus()
		var token:String=tomorrow.get_meta("focus_key")
		game.changed.emit()
		await _settle()
		_check(str(root.gui_get_focus_owner().get_meta("focus_key",""))==token,"A live state refresh preserves the selected social action")
	await _press("HIT ME UP TOMORROW")
	_check(game.callbacks.size()==1 and game.active_meetings().is_empty(),"Tomorrow reply queues a callback without creating an obligation")
	# Trigger real word-of-mouth introductions with deterministic reputation.
	game.reputation=2
	game._maybe_referral(game.contacts[0])
	scene.ui.show_page("messages")
	await _settle()
	var contact_count:int=game.contacts.size()
	_check(game.pending_introductions().size()==1,"A referral is a pending number, not an automatic trusted contact")
	await _press("WHO REFERRED YOU?")
	_check(_text("gave me your number") and _text("WHAT YOU KNOW ABOUT MILO"),"Question exposes the answer beside the known friend's background")
	await _press("HOW DO YOU KNOW THEM?")
	_check(_text("We know each other from") and _text("architecture"),"Connection answer can be compared with a saved course and hangout")
	_check(not _text("_informant") and not _text("SAFE CONTACT"),"Dialog does not reveal hidden informant flags or promise certainty")
	await _press("SAVE CONTACT")
	_check(game.contacts.size()==contact_count+1,"Accepting a number is the action that adds it")
	game.reputation=4
	game._maybe_referral(game.contacts[0])
	scene.ui.show_page("messages")
	await _settle()
	await _press("BLOCK NUMBER")
	_check(game.contacts.size()==contact_count+1 and game.pending_introductions().is_empty(),"Blocking leaves the accepted network unchanged")
	# The accepted referral supplies a normal request. Stage an offered ceiling.
	var request:Dictionary={}
	for message in game.inbox:
		if message.status=="new": request=message
	_check(not request.is_empty(),"Accepted referral can initiate a request")
	request.max_price=20.0
	request.suggested_price=20.0
	scene.ui.show_page("messages")
	await _settle()
	await _press("ARRANGE A MEETING")
	var time:OptionButton=_key("schedule_time")
	var price_edit:LineEdit=_key("schedule_price")
	_check(time.item_count==10 and "480 minutes" in time.get_item_text(9),"Client scheduling offers the full eight-hour horizon")
	_check(price_edit.get_parent().max_value==20 and price_edit.get_parent().value==20,"Discounted reply initializes and caps the offered price")
	price_edit.grab_focus()
	_check(scene.ui.adjust_focused_value(-1) and price_edit.get_parent().value==19,"Controller adjustment changes a focused price without typing")
	scene.ui.adjust_focused_value(1)
	scene.ui._build_page()
	await _settle()
	_check(str(root.gui_get_focus_owner().get_meta("focus_key",""))=="schedule_price","Numeric-field focus survives rebuilding the form, including SpinBox's internal editor")
	time=_key("schedule_time")
	time.select(9)
	var scheduled_at:float=game.minute
	await _press("CONFIRM MEETING")
	var appointment:Dictionary=game.active_meetings()[0]
	_check(is_equal_approx(float(appointment.due_minute),scheduled_at+480),"Eight-hour choice reaches the actual scheduling API")
	_check(float(appointment.price)==20,"Accepted discount reaches the actual meeting")
	# Hold an ordinary citizen in an open area. Only the random reaction is seeded.
	scene.ui.close_page()
	var citizen:Dictionary=scene.population.citizens[0]
	citizen.node.position=Vector3(100,0.2,103)
	citizen.node.visible=true
	scene.player.position=Vector3(101,0.3,103)
	scene._update_location()
	game.street_conversation(str(citizen.id),str(citizen.name))
	game.street_npcs[str(citizen.id)].response="sale"
	scene.interact()
	await _settle()
	_check(scene.ui.page=="conversation","World interaction opens the ambient citizen dialog")
	var cash_before:float=game.cash
	await _press("OFFER A BAG")
	_check(is_equal_approx(game.cash,cash_before+22),"Street offer button executes a real sale")
	await _press("SAVE THEIR NUMBER")
	var new_contact:Dictionary=game.contacts.back()
	_check(str(new_contact.id).begins_with("street_"),"Street dialog exchanges numbers only after the accepted offer")
	scene.ui.show_page("contacts")
	await _settle()
	_check(scene.conversation_id=="","Leaving a conversation through phone navigation releases the citizen")
	var check_in:Button=_key("contact_%s_text"%str(new_contact.id))
	_check(check_in!=null,"Saved contacts expose proactive check-in")
	if check_in: check_in.pressed.emit()
	await _settle()
	_check(str(new_contact.last_reply)!="" and _text("Last reply:"),"A negative or positive reply remains readable after the toast")
	# Spatial arrival is covered separately; stage a waiting actor to exercise the
	# actual face-to-face permission check and postponement confirmation controls.
	scene.ui.close_page()
	game.minute=float(appointment.due_minute)-12
	scene.population._sync_meetings()
	var walk:Dictionary=scene.population.meeting_walks[str(int(appointment.id))]
	walk.node.position=walk.target
	walk.node.visible=true
	walk.state="waiting"
	scene.player.position=walk.node.position+Vector3(1,0,0)
	scene._update_location()
	scene.interact()
	await _settle()
	_check(scene.ui.page=="postpone" and _button("COMPLETE HANDOFF")!=null,"Physical meetup presents both complete and postpone choices")
	var friend:Dictionary=game._find_contact(str(appointment.contact_id))
	var trust:float=float(friend.relationship)
	await _press("CONFIRM POSTPONEMENT")
	_check(appointment.status=="postponed" and is_equal_approx(float(friend.relationship),trust),"In-person postponement clears the obligation without a trust penalty")
	_check(scene.ui.page=="","Confirmed postponement releases the phone pause")
	game.cash=100
	scene.ui.show_page("suppliers")
	await _settle()
	_check(_text("22:00") and _text("02:00") and _text("Next available pickup: Day"),"Supplier page makes the night window and exact next day/time explicit")
	await _press("ARRANGE PICKUP")
	var pickup:Dictionary={}
	for meeting in game.active_meetings():
		if meeting.type=="supplier": pickup=meeting
	var hour:float=fmod(float(pickup.due_minute),1440)
	_check(hour>=1320 or hour<120,"Supplier UI creates a real appointment inside the advertised night window")
	_check(_text("Day %d /"%(int(float(pickup.due_minute)/1440)+1)),"Agenda retains the pickup's explicit day")
	scene.ui.show_page("map")
	await _settle()
	var map_destination:OptionButton=_key("map_destination")
	for index in map_destination.item_count:
		if str(map_destination.get_item_metadata(index))=="home": map_destination.select(index)
	await _press("SET DIRECTIONS")
	_check(scene.destination=="home" and scene.navigation_marker!=null,"Controller-accessible map selector activates the same world route as clicking a landmark")
	print("SOCIAL INTERFACE TESTS: %d checks, %d failures"%[checks,failures])
	scene._release_audio(scene)
	await create_timer(0.15).timeout
	scene.queue_free()
	await _settle()
	DirAccess.remove_absolute(game.save_path)
	quit(1 if failures>0 else 0)
