extends SceneTree
## Real input events exercise native focus, shortcuts and analog movement.
var checks := 0
var failures := 0
var scene: Node
var game: Node

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CONTROL CHECK: "+label)

func _settle() -> void:
	for tick in range(4): await process_frame

func _button(code: int,pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await _settle()

func _tap(code: int) -> void:
	await _button(code,true)
	await _button(code,false)

func _axis(code: int,value: float,device: int=0) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = code
	event.axis_value = value
	Input.parse_input_event(event)
	await _settle()

func _find_meta(node: Node,key: String) -> Control:
	if node is Control and node.get_meta("focus_key","")==key: return node
	for child: Node in node.get_children(true):
		var match_control := _find_meta(child,key)
		if match_control: return match_control
	return null

func _run() -> void:
	game = root.get_node("Game")
	game.save_path = "res://.godot/controls-test-save.json"
	game.restart_game()
	game.set_process(false)
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await _settle()
	var count := InputMap.action_get_events("interact").size()
	scene._setup_inputs()
	_check(count==InputMap.action_get_events("interact").size(),"Bindings are idempotent across restarts")
	scene.ui.set_controller_active(true)
	scene.ui.focus_first_action()
	await _settle()
	_check(root.gui_get_focus_owner() is Button,"Title offers controller focus")
	await _tap(JOY_BUTTON_A)
	_check(scene.started,"Controller confirm starts the story")
	scene.population.set_physics_process(false)
	scene.player.set_physics_process(false)
	await _tap(JOY_BUTTON_DPAD_UP)
	_check(scene.ui.page=="agenda" and game.paused,"World D-pad Up opens Agenda")
	var focus_before: Control = root.gui_get_focus_owner()
	_check(focus_before!=null,"Agenda initially focused an action")
	game.changed.emit()
	await _settle()
	_check(root.gui_get_focus_owner()!=null,"State refresh retains usable controller focus")
	await _tap(JOY_BUTTON_DPAD_DOWN)
	_check(scene.ui.page=="agenda" and game.inventory.get("ammo",0)==0,"Menu navigation cannot fire a weapon")
	await _tap(JOY_BUTTON_B)
	_check(scene.ui.page=="" and not game.paused,"Controller cancel closes Agenda")
	await _tap(JOY_BUTTON_LEFT_SHOULDER)
	_check(scene.ui.page=="messages","Left shoulder opens phone")
	await _tap(JOY_BUTTON_B)
	await _tap(JOY_BUTTON_RIGHT_SHOULDER)
	_check(scene.ui.page=="backpack","Right shoulder opens backpack")
	await _tap(JOY_BUTTON_B)
	await _tap(JOY_BUTTON_BACK)
	_check(scene.ui.page=="map","Select opens map")
	await _tap(JOY_BUTTON_B)
	await _tap(JOY_BUTTON_START)
	_check(scene.ui.page=="pause","Start opens pause")
	await _tap(JOY_BUTTON_START)
	_check(scene.ui.page=="" and not game.paused,"Start returns to world")
	game.split_flower()
	game.tutorial_sell()
	game.add_tutorial_contact()
	game.advance_time(90.0)
	scene.ui.selected_message = game.inbox.back().duplicate(true)
	scene.ui.show_page("schedule")
	await _settle()
	var time: OptionButton = _find_meta(scene.ui,"schedule_time")
	_check(time!=null,"Schedule offers focused time selector")
	if time:
		time.grab_focus()
		var selected := time.selected
		await _tap(JOY_BUTTON_A)
		_check(time.get_popup().visible,"A opens native time dropdown")
		await _tap(JOY_BUTTON_DPAD_DOWN)
		await _tap(JOY_BUTTON_A)
		_check(time.selected==selected+1 and not time.get_popup().visible,"D-pad and A choose a time")
		await _tap(JOY_BUTTON_A)
		await _tap(JOY_BUTTON_B)
		_check(scene.ui.page=="schedule" and not time.get_popup().visible,"B closes only the active dropdown first")
	var price: Control = _find_meta(scene.ui,"schedule_price")
	_check(price!=null,"Schedule offers focused price control")
	if price:
		price.grab_focus()
		var before_price: float = price.get_parent().value
		await _tap(JOY_BUTTON_DPAD_RIGHT)
		_check(price.get_parent().value==before_price+1,"Controller adjusts the price without typing")
		await _tap(JOY_BUTTON_DPAD_DOWN)
		_check(root.gui_get_focus_owner()!=price,"Controller can leave numeric entry to reach confirmation")
	scene.ui.close_page()
	await _axis(JOY_AXIS_LEFT_X,0.1)
	_check(Input.get_vector("move_left","move_right","move_up","move_down").length()<0.01,"Analog deadzone prevents drift")
	await _axis(JOY_AXIS_LEFT_X,0.6)
	var partial := Input.get_vector("move_left","move_right","move_up","move_down").length()
	_check(partial>0.2 and partial<0.9,"Stick retains proportional movement")
	await _axis(JOY_AXIS_LEFT_X,1.0)
	_check(Input.get_vector("move_left","move_right","move_up","move_down").x>0.99,"Full stick reaches movement speed")
	await _axis(JOY_AXIS_LEFT_X,0.0)
	await _axis(JOY_AXIS_LEFT_X,1.0,3)
	_check(Input.get_vector("move_left","move_right","move_up","move_down").x>0.99,"Movement accepts a controller with a nonzero device ID")
	await _axis(JOY_AXIS_LEFT_X,0.0,3)
	await _tap(JOY_BUTTON_X)
	_check(scene.player.skateboarding,"X equips skateboard in world")
	var car := Node3D.new()
	scene.add_child(car)
	var before: float = game.health
	_check(not scene.player.receive_vehicle_impact(Vector3.ZERO,car),"Stationary vehicles do not damage player")
	_check(scene.player.receive_vehicle_impact(Vector3(9,0,0),car),"Moving traffic hits player")
	_check(game.health<before and not scene.player.skateboarding,"Traffic deals damage and dismounts skateboard")
	_check(scene.player.impact_velocity.x>0,"Impact imparts directional knockback")
	before = game.health
	_check(not scene.player.receive_vehicle_impact(Vector3(9,0,0),car) and game.health==before,"Overlapping frames cannot repeatedly damage player")
	scene.player.impact_cooldown = 0.0
	scene.player.vehicle = car
	_check(not scene.player.receive_vehicle_impact(Vector3(9,0,0),car),"Player's own vehicle cannot hit its driver")
	scene.player.vehicle = null
	game.paused = true
	_check(not scene.player.receive_vehicle_impact(Vector3(9,0,0),car),"Paused menus cannot take traffic damage")
	scene.player.reset_travel()
	_check(scene.player.impact_velocity==Vector3.ZERO and scene.player.impact_cooldown==0,"Restart clears impact state")
	print("CONTROL TESTS: %d checks, %d failures" % [checks,failures])
	scene._release_audio(scene)
	await create_timer(0.15).timeout
	scene.queue_free()
	await _settle()
	DirAccess.remove_absolute(game.save_path)
	quit(1 if failures>0 else 0)
