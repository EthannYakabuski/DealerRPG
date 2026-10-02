extends SceneTree
## Controller supplier flow, live party controls, and bounded NPC reactions.

const Emotes = preload("res://scripts/npc_emote.gd")
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
		push_error("PARTY UI CHECK: " + label)

func _settle() -> void:
	for tick in range(4): await process_frame

func _tap(code: int) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await _settle()

func _key(node: Node, key: String) -> Control:
	if node is Control and node.get_meta("focus_key", "") == key: return node
	for child in node.get_children(true):
		var found := _key(child, key)
		if found: return found
	return null

func _text(fragment: String) -> bool:
	for node in scene.ui.body.find_children("*", "Label", true, false):
		if fragment in node.text: return true
	return false

func _run() -> void:
	game = root.get_node("Game")
	game.save_path = "res://.godot/party-interface-test-save.json"
	game.set_process(false)
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await _settle()
	scene.start_game(false)
	scene.population.set_physics_process(false)
	scene.player.set_physics_process(false)
	game.split_flower()
	game.tutorial_sell()
	game.add_tutorial_contact()
	game.cash = 500
	game.reputation = 40
	scene.ui.set_controller_active(true)
	scene.ui.show_page("suppliers")
	await _settle()
	var choice: Control = _key(scene.ui.body, "supplier_0_quantity")
	_check(choice is Button and root.gui_get_focus_owner() == choice, "Supplier opens on a labelled quantity button")
	_check(scene.ui.body.find_children("*", "SpinBox", true, false).is_empty(), "Supplier flow has no numeric text-entry field")
	var quantity: Node = choice.get_meta("bundle_stepper")
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	_check(quantity.value == 2 and root.gui_get_focus_owner() == choice, "Right changes one bundle and keeps quantity focus")
	_check(_text("12 packed bags"), "Total packed quantity updates immediately")
	game.changed.emit()
	await _settle()
	choice = _key(scene.ui.body, "supplier_0_quantity")
	quantity = choice.get_meta("bundle_stepper")
	_check(quantity.value == 2 and root.gui_get_focus_owner() == choice, "Live rebuild preserves chosen bundles and focus")
	quantity.plus.pressed.emit()
	_check(quantity.value == mini(3, quantity.maximum), "Mouse plus retains the same quantity behaviour")
	for n in range(15): quantity.adjust(1)
	_check(quantity.value == quantity.maximum and quantity.plus.disabled, "Quantity respects the supplier's maximum")
	for n in range(12): quantity.adjust(-1)
	_check(quantity.value == 1 and quantity.minus.disabled, "Quantity cannot underflow or order zero")
	await _tap(JOY_BUTTON_DPAD_DOWN)
	_check(root.gui_get_focus_owner() == _key(scene.ui.body, "supplier_0_order"), "One Down reaches Arrange Pickup directly")
	await _tap(JOY_BUTTON_DPAD_DOWN)
	_check(root.gui_get_focus_owner() == _key(scene.ui.body, "supplier_1_quantity"), "Down continues to the next unlocked supplier and scrolls into view")
	await _tap(JOY_BUTTON_DPAD_UP)
	await _tap(JOY_BUTTON_DPAD_UP)
	_check(root.gui_get_focus_owner() == choice, "Up returns from pickup to bundles")
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	await _tap(JOY_BUTTON_A)
	_check(scene.ui.page == "agenda", "Controller A confirms pickup and opens the agenda")
	_check(game.active_meetings().size() == 1 and int(game.active_meetings()[0].quantity) == 2, "The confirmed pickup has the selected two bundles")
	# Exercise the real authoritative handoff and main's reaction-signal bridge.
	# Only the physical arrival and random bust chance are fixed by this fixture.
	var pickup: Dictionary = game.active_meetings()[0]
	pickup.risk = 0.0
	game.minute = float(pickup.due_minute)
	scene.population._sync_meetings()
	var pickup_walk: Dictionary = scene.population.meeting_walks[str(int(pickup.id))]
	var pickup_actor: Node3D = pickup_walk.node
	pickup_actor.position = pickup_walk.target
	pickup_actor.visible = true
	pickup_walk.state = "waiting"
	scene._teleport(pickup_actor.position+Vector3(1,0,0))
	_check(scene.complete_in_person(int(pickup.id)), "The scheduled supplier handoff completes beside its actual actor")
	var pickup_bubble: Node3D = pickup_actor.get_node_or_null("NPCEmote")
	_check(pickup_bubble!=null and pickup_bubble.get_meta("emote_kind")=="happy", "Main connects the completed meeting reaction to the actual supplier actor")
	var citizen: Dictionary = scene.population.citizens[0]
	game.street_conversation(str(citizen.id),str(citizen.name))
	var reply: String = game.street_smalltalk(str(citizen.id),str(citizen.goal))
	var street_bubble: Node3D = citizen.node.get_node_or_null("NPCEmote")
	_check(not reply.is_empty() and street_bubble!=null and street_bubble.get_meta("emote_kind")=="wave", "Main connects a real small-talk reaction to the actual street citizen")
	# Failed hosting must leave its explanation visible. Successful hosting must
	# release the paused clock so the actual party actors can walk to the house.
	game.reputation = 5
	game._maybe_referral(game.contacts[0])
	game.resolve_introduction(int(game.pending_introductions()[0].id), "accept")
	scene.player.position = scene.world.get_landmark("home")
	scene._update_location()
	game.minute = 1000.0
	scene.ui.show_page("home")
	await _settle()
	_key(scene.ui.body, "party_host").pressed.emit()
	await _settle()
	_check(scene.ui.page == "home" and not game.party_summary().active, "Host failure before17:00 leaves menu open")
	game.minute = 1030.0
	game.inventory.dime_bag = 0
	var cash_before: float = game.cash
	_key(scene.ui.body, "party_host").pressed.emit()
	await _settle()
	_check(scene.ui.page == "" and not game.paused, "Successful hosting returns to the live world")
	_check(game.party_summary().active and is_equal_approx(game.minute,1030.0), "Hosting starts a live party without skipping time")
	_check(is_equal_approx(game.cash,cash_before-25.0), "Party charges only supplies and needs no stock")
	scene.ui.show_page("contacts")
	await _settle()
	_check(_text("HAPPENING NOW") and _text("invitation list is empty"), "Contacts show the live party status before invitations")
	var contact_id: String = str(game.contacts[0].id)
	var invite: Control = _key(scene.ui.body, "party_invite_"+contact_id)
	_check(invite != null, "Known contacts have an explicit invitation control")
	invite.grab_focus()
	await _tap(JOY_BUTTON_A)
	_check(game.party_summary().guests.size() == 1 and _text("On their way"), "Controller invitation updates the live guest list")
	_check(_key(scene.ui.body,"party_invite_"+contact_id)==null, "Already invited guest cannot receive duplicate invitations")
	var guest: Dictionary = game.party_summary().guests[0]
	game.minute = float(guest.arrival_minute)
	game.party_guest_arrived(contact_id)
	await _settle()
	_check(_text("Inside — come say hello"), "Physical arrival is represented in the guest list")
	var context: Dictionary = game.party_guest_view(contact_id)
	context.actor_id = "party:"+contact_id
	context.party_guest = true
	context.district = "Deerfield party"
	scene.ui.show_conversation(context)
	await _settle()
	_check(_key(scene.ui.body,"street_talk").text=="CATCH UP", "Party conversation uses a social action label")
	_check(_key(scene.ui.body,"street_offer").text.contains("$24"), "Party offer shows the exact sale price")
	game.party_chat(contact_id)
	context = game.party_guest_view(contact_id)
	context.actor_id = "party:"+contact_id
	context.party_guest = true
	scene.ui.show_conversation(context)
	await _settle()
	_check(_key(scene.ui.body,"street_talk")==null, "A completed catch-up is not offered repeatedly")
	# Reactions replace each other instead of accumulating nodes or timers.
	var actor := Node3D.new()
	scene.add_child(actor)
	var reaction: Node3D = Emotes.play(actor,"happy",0.6)
	_check(reaction!=null and reaction.get_child(0) is Sprite3D, "Reaction uses a lightweight billboard")
	_check(not reaction.get_child(0).no_depth_test, "Walls can occlude reaction bubbles")
	Emotes.play(actor,"alert",0.6)
	_check(actor.get_child_count()==1 and actor.get_child(0).get_meta("emote_kind")=="alert", "New reaction replaces the old bubble immediately")
	await create_timer(0.9).timeout
	_check(actor.get_child_count()==0, "Reaction expires without a persistent actor attachment")
	actor.queue_free()
	game.pursuit_incidents = 4
	scene.population.pursuit = true
	scene.population.escape_seconds = 8.0
	scene.ui._update_hud()
	_check("8s / 20s" in scene.ui.labels.objective.text, "HUD displays the current escalating escape requirement")
	scene.ui.show_page("help")
	await _settle()
	_check(_text("20 seconds to escape"), "Help describes the same current escape duration")
	scene.population.pursuit = false
	print("PARTY INTERFACE TESTS: %d checks, %d failures" % [checks, failures])
	scene._release_audio(scene)
	await create_timer(0.15).timeout
	scene.queue_free()
	await _settle()
	DirAccess.remove_absolute(game.save_path)
	quit(1 if failures>0 else 0)
