extends SceneTree
## Validate social actions through the real world dispatcher and campaign save.
var game: Node
var scene: Node
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SOCIAL WORLD CHECK: "+label)

func _settle() -> void:
	for frame in range(3): await process_frame

func _run() -> void:
	game = root.get_node("Game")
	game.save_path = "res://.godot/social-world-test-save.json"
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
	for citizen: Dictionary in scene.population.citizens: citizen.node.position = Vector3(125,0.3,-110)
	for officer: Dictionary in scene.population.police: officer.node.position = Vector3(135,0.3,115)
	var citizen: Dictionary = scene.population.citizens[0]
	var npc_id: String = citizen.id
	citizen.node.position = Vector3(25,0.3,49)
	scene.player.position = Vector3(23,0.3,49)
	scene.interact()
	await _settle()
	_check(scene.ui.page=="conversation" and scene.conversation_id==npc_id,"Nearby pedestrian opens face-to-face conversation")
	_check(citizen.conversation and game.paused,"Conversation holds that person and pauses the world")
	scene.conversation_action(npc_id,"smalltalk")
	_check(scene.ui.conversation.get("response","")!="","Small talk responds about the pedestrian's day")
	game.street_npcs[npc_id].response = "sale"
	var before: float = game.cash
	scene.conversation_action(npc_id,"offer")
	_check(game.cash==before+22 and bool(scene.ui.conversation.get("can_add_contact",false)),"World offer makes a sale and exposes exchange numbers")
	scene.conversation_action(npc_id,"add_contact")
	_check(game.contacts.size()==2 and scene.ui.conversation.contact_id!="","Conversation saves a new phone contact")
	scene.ui.close_page()
	_check(scene.conversation_id=="" and not citizen.conversation and not game.paused,"Closing conversation releases held pedestrian")
	citizen = scene.population.citizens[1]
	npc_id = citizen.id
	citizen.node.position = Vector3(26,0.3,49)
	scene.population.citizens[0].node.position = Vector3(125,0.3,-110)
	scene.player.position = Vector3(24,0.3,49)
	scene.interact()
	game.street_npcs[npc_id].response = "report"
	scene.conversation_action(npc_id,"offer")
	_check(scene.ui.page=="" and citizen.reporting and not game.paused,"Refused offer releases the menu and starts a physical report run")
	_check(not scene.population.pursuit and game.status=="playing","Unreported witness cannot instantly dispatch or end the run")
	citizen.node.position += Vector3(3,0,1)
	var saved_position: Vector3 = citizen.node.position
	scene._capture_world_state()
	game.save_game()
	scene.start_game(true)
	await _settle()
	citizen = scene.population.citizens[1]
	_check(citizen.reporting and citizen.node.position.distance_to(saved_position)<0.01,"Continue preserves the witness's position and pending report")
	_check(game.pending_civilian_reports().has(npc_id),"Pending report stays in campaign state through JSON save")
	for officer: Dictionary in scene.population.police: officer.node.position = Vector3(135,0.3,115)
	scene.population.police[0].node.position = citizen.node.position+Vector3(1,0,0)
	scene.population._update_informant(citizen,0.016)
	_check(scene.population.pursuit and not game.pending_civilian_reports().has(npc_id),"Reaching a living officer starts response and completes persisted report once")
	_check(game.status=="playing","Reporting still requires police to physically catch the player")
	_check(not scene.postpone_in_person(999,120),"Remote or nonexistent meeting cannot be postponed through world dispatcher")
	print("SOCIAL WORLD TESTS: %d checks, %d failures" % [checks,failures])
	scene._release_audio(scene)
	await create_timer(0.15).timeout
	scene.queue_free()
	await _settle()
	DirAccess.remove_absolute(game.save_path)
	quit(1 if failures>0 else 0)
