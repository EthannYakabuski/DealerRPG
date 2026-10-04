extends SceneTree
## Fixed appointments, every location, early pickup, and death through real UI.

const Data = preload("res://scripts/game_data.gd")
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
		push_error("SCHEDULING UI CHECK: " + label)

func _settle() -> void:
	for tick in range(4): await process_frame

func _capture(label: String) -> void:
	if not "--capture-ui" in OS.get_cmdline_user_args(): return
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://build/screenshots/scheduling-%d"%root.size.x)
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join(label+".png"))

func _tap(code: int) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventJoypadButton.new()
		event.button_index = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await _settle()

func _key(node: Node, key: String) -> Control:
	if node is Control and node.get_meta("focus_key", "") == key: return node
	for child in node.get_children(true):
		var found := _key(child,key)
		if found: return found
	return null

func _text(node: Node, fragment: String) -> bool:
	for label in node.find_children("*", "Label", true, false):
		if fragment in label.text: return true
	return false

func _index(choice: OptionButton, metadata: Variant) -> int:
	for index in choice.item_count:
		if choice.get_item_metadata(index) == metadata: return index
	return -1

func _run() -> void:
	game = root.get_node("Game")
	game.save_path = "res://.godot/scheduling-interface-test-save.json"
	game.set_process(false)
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _settle()
	scene.start_game(false)
	scene.population.set_physics_process(false)
	scene.population.set_process(false)
	scene.player.set_physics_process(false)
	game.split_flower()
	game.tutorial_sell()
	game.add_tutorial_contact()
	game.advance_time(90.0)
	# Preserve an off-grid booking from the relative API, then let the clock move.
	game.minute = 780.25
	var first_request: Dictionary = game.inbox[0]
	_check(game.schedule_meeting(int(first_request.id), "campus_quad", 60.0, 22.0), "Existing off-grid appointment is accepted")
	var first: Dictionary = game.active_meetings()[0]
	game.advance_time(1.333)
	game._add_contact("ui_jules", "Jules", 60.0)
	var friend: Dictionary = game._find_contact("ui_jules")
	friend.next_request_minute = game.minute
	_check(game._create_request(friend), "Another contact sends an independent request")
	scene.ui.selected_message = game.inbox.back()
	scene.ui.set_controller_active(true)
	scene.ui.show_page("schedule")
	await _settle()
	await _capture("schedule")
	var location: OptionButton = _key(scene.ui.body, "schedule_location")
	var all_locations := true
	for entry: Dictionary in game.available_locations():
		all_locations = all_locations and _index(location,str(entry.id)) >= 0
	_check(all_locations and location.item_count == Data.LOCATIONS.size(), "Every named location is exposed in client scheduling")
	for id: String in ["west_overlook", "service_lane", "east_trail", "deerfield_social"]:
		_check(_index(location,id) >= 0, "Meeting choice includes " + id)
	# Open the native popup and scroll to the last location entirely by D-pad.
	location.grab_focus()
	await _tap(JOY_BUTTON_A)
	_check(location.get_popup().visible, "Controller opens the complete location list")
	for step in range(location.item_count-1): await _tap(JOY_BUTTON_DPAD_DOWN)
	await _capture("locations")
	await _tap(JOY_BUTTON_A)
	_check(location.selected == location.item_count-1 and not location.get_popup().visible, "Controller reaches and chooses the final location in the scrolling list")
	var destination: String = str(location.get_item_metadata(location.selected))
	var time: OptionButton = _key(scene.ui.body, "schedule_time")
	var adjacent_due: float = float(first.due_minute)+30.0
	var adjacent_index := _index(time,adjacent_due)
	_check(adjacent_index >= 0 and "30 min after Milo" in time.get_item_text(adjacent_index), "Exact adjacent appointment is labelled despite fractional clock drift")
	var no_conflicts := true
	for index in time.item_count:
		no_conflicts = no_conflicts and absf(float(time.get_item_metadata(index))-float(first.due_minute)) >= 30.0-0.00001
	_check(no_conflicts, "Conflicting appointment choices are hidden")
	if adjacent_index >= 0:
		time.grab_focus()
		await _tap(JOY_BUTTON_A)
		await _capture("times")
		var current: int = time.selected
		for step in range(absi(adjacent_index-current)):
			await _tap(JOY_BUTTON_DPAD_DOWN if adjacent_index>current else JOY_BUTTON_DPAD_UP)
		await _tap(JOY_BUTTON_A)
		_check(float(time.get_item_metadata(time.selected)) == adjacent_due, "Native controller chooses the adjacent fixed timestamp")
	var price: LineEdit = _key(scene.ui.body, "schedule_price")
	price.grab_focus()
	scene.ui.adjust_focused_value(-1)
	var chosen_price: float = price.get_parent().value
	scene.ui._build_page()
	await _settle()
	location = _key(scene.ui.body,"schedule_location")
	time = _key(scene.ui.body,"schedule_time")
	price = _key(scene.ui.body,"schedule_price")
	_check(str(location.get_item_metadata(location.selected)) == destination and float(time.get_item_metadata(time.selected)) == adjacent_due and price.get_parent().value == chosen_price, "Form rebuild retains destination, exact time, and price")
	_key(scene.ui.body,"schedule_confirm").grab_focus()
	await _tap(JOY_BUTTON_A)
	_check(scene.ui.page == "agenda" and game.active_meetings().size() == 2, "Controller confirmation creates the second appointment")
	var second: Dictionary = game.active_meetings().back()
	_check(is_equal_approx(float(second.due_minute)-float(first.due_minute),30.0), "Real bookings are exactly 30 minutes apart")
	_check(str(second.location_id) == destination and scene.destination == destination, "New remote destination reaches the appointment and directions")
	# A real supplier actor can hand over at21:45 for a22:00 appointment.
	game.cash = 200.0
	game.minute = 20.0*60.0
	_check(game.supplier_order(0,1), "Night supplier pickup is arranged")
	var pickup: Dictionary = game.active_meetings().back()
	pickup.risk = 0.0
	game.minute = float(pickup.due_minute)-15.0
	scene.ui.close_page()
	scene.population._sync_meetings()
	var key := str(int(pickup.id))
	_check(scene.population.meeting_walks.has(key), "Supplier has a physical approach actor before the early handoff")
	if scene.population.meeting_walks.has(key):
		var walk: Dictionary = scene.population.meeting_walks[key]
		walk.node.position = walk.target
		walk.node.visible = true
		walk.state = "waiting"
		scene._teleport(walk.node.position+Vector3(1,0,0))
		scene.interact()
		await _settle()
		_check(scene.ui.page == "postpone" and _text(scene.ui.body,"complete the pickup now"), "Physical early supplier dialogue explicitly permits collection")
		var handoff: Control = _key(scene.ui.body,"meeting_handoff")
		_check(handoff != null, "Early pickup exposes the controller handoff action")
		if handoff:
			handoff.grab_focus()
			await _tap(JOY_BUTTON_A)
			_check(pickup.status == "completed", "Controller completes supplier pickup15minutes early")
	# Fatal damage must retain the run summary and offer an actual working restart.
	scene.ui.close_page()
	game.total_sales = 12
	game.total_earned = 321.5
	game.classes_attended = 2
	game.health = 4.0
	game.take_damage(5.0)
	await _settle()
	await _capture("death-stats")
	_check(game.health == 0.0 and game.status == "lost" and scene.ui.page == "ending", "Zero health opens the losing screen through the real ended signal")
	_check(_text(scene.ui.modal,"Sales: 12") and _text(scene.ui.modal,"Earned: $321.50") and _text(scene.ui.modal,"Classes attended: 2"), "Death screen keeps accurate sales, earnings, and class stats")
	var restart: Control = root.gui_get_focus_owner()
	_check(restart is Button and restart.text == "START A NEW STORY", "Restart has controller focus after death")
	await _tap(JOY_BUTTON_A)
	await _settle()
	scene = current_scene
	_check(game.status == "playing" and game.health == 100.0 and game.total_sales == 0 and scene != null and scene.ui.page != "ending", "Controller restart reloads a playable fresh story")
	print("SCHEDULING INTERFACE TESTS: %d checks, %d failures" % [checks,failures])
	scene._release_audio(scene)
	await create_timer(0.15).timeout
	scene.queue_free()
	await _settle()
	DirAccess.remove_absolute(game.save_path)
	quit(1 if failures>0 else 0)
