extends Node3D

var world: Node3D
var player: StudentPlayer
var population: CityPopulation
var party_guests: Node3D
var supplier_encounters: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var environment: Environment
var sky_material: ProceduralSkyMaterial
var ui: CanvasLayer
var destination := ""
var closest_location := ""
var ambient: AudioStreamPlayer
var last_phase := ""
var autosave_timer := 0.0
var location_tick := 0.0
var started := false
var camera_zoom := 37.0
var navigation_marker: MeshInstance3D
var conversation_id := ""
var controller_active := false
var _last_stick_value_step := 0

func _exit_tree() -> void:
	# Release active mixer voices before a scene is restarted or unloaded.
	_release_audio(self)

func _release_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		node.stop()
		node.stream = null
	for child: Node in node.get_children():
		_release_audio(child)

func _ready() -> void:
	_setup_inputs()
	_setup_environment()
	world=load("res://scripts/world.gd").new()
	add_child(world)
	player=StudentPlayer.new()
	add_child(player)
	player.position=Vector3(20,0.3,50)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=camera_zoom
	camera.far=360
	camera.near=0.2
	camera.current=true
	add_child(camera)
	player.camera=camera
	camera.position=player.position+Vector3(24,38,28)
	camera.look_at(player.position)
	population=CityPopulation.new()
	add_child(population)
	population.setup(world,player)
	party_guests=load("res://scripts/party_guests.gd").new()
	add_child(party_guests)
	party_guests.setup(world,player,population)
	supplier_encounters=load("res://scripts/supplier_encounters.gd").new()
	add_child(supplier_encounters)
	supplier_encounters.setup(world,player,population)
	party_guests.supplier_encounters=supplier_encounters
	supplier_encounters.party_guests=party_guests
	population.social_actor_providers.assign([party_guests,supplier_encounters])
	player.attacked.connect(population.attack)
	ui=load("res://scripts/interface.gd").new()
	ui.game_root=self
	add_child(ui)
	Game.ended.connect(_on_ended)
	Game.notification.connect(_on_notification)
	Game.civilian_reaction.connect(_on_civilian_reaction)
	Game.police_tip.connect(population.respond_to_tip)
	Game.party_reaction.connect(_on_party_reaction)
	Game.street_reaction.connect(population.play_citizen_emote)
	Game.meeting_reaction.connect(population.play_contact_emote)
	population.informant_reported.connect(_on_informant_reported)
	Input.joy_connection_changed.connect(_on_controller_connection)
	controller_active = not Input.get_connected_joypads().is_empty()
	ui.set_controller_active(controller_active)
	Game.paused=true
	_setup_audio()
	_update_lighting()
	if OS.get_cmdline_user_args().has("--smoke"):
		start_game(false)

func _setup_inputs() -> void:
	GameControls.setup()

func _on_controller_connection(_device: int, connected: bool) -> void:
	controller_active = connected or not Input.get_connected_joypads().is_empty()
	ui.set_controller_active(controller_active)
	if controller_active: ui.focus_first_action()

func _input(event: InputEvent) -> void:
	if not ui: return
	var using_pad := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value)>0.3)
	var using_keyboard := event is InputEventKey or event is InputEventMouseButton
	if using_pad and not controller_active:
		controller_active = true
		ui.set_controller_active(true)
		if Game.paused: ui.focus_first_action()
	elif using_keyboard and controller_active:
		controller_active = false
		ui.set_controller_active(false)
	if event is InputEventKey and not event.echo and Game.paused and started and Game.status=="playing":
		for action: String in ["phone","backpack","map","agenda"]:
			if event.is_action_pressed(action):
				ui.close_page()
				get_viewport().set_input_as_handled()
				return
	if using_pad and Game.paused:
		var direction := int(event.is_action_pressed("ui_right"))-int(event.is_action_pressed("ui_left"))
		if direction != 0:
			# Analog motion can generate many events while held. Bound value repeats.
			if event is InputEventJoypadMotion and Time.get_ticks_msec()-_last_stick_value_step<180:
				return
			if ui.adjust_focused_value(direction):
				_last_stick_value_step = Time.get_ticks_msec()
				get_viewport().set_input_as_handled()

func _setup_environment() -> void:
	var node := WorldEnvironment.new()
	environment=Environment.new()
	environment.background_mode=Environment.BG_SKY
	var sky := Sky.new()
	sky_material=ProceduralSkyMaterial.new()
	sky_material.sky_top_color=Color("7eacc3")
	sky_material.sky_horizon_color=Color("d7dbbd")
	sky_material.ground_bottom_color=Color("58694b")
	sky_material.ground_horizon_color=Color("d7dbbd")
	sky.sky_material=sky_material
	environment.sky=sky
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("c8dfeb")
	environment.ambient_light_energy=0.3
	environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	node.environment=environment
	add_child(node)
	sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-52,-32,0)
	sun.light_color=Color("ffe7b3")
	sun.light_energy=0.7
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=100
	sun.shadow_bias=0.035
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)

func _setup_audio() -> void:
	# A quiet generated city bed keeps the project entirely self-contained.
	ambient=AudioStreamPlayer.new()
	ambient.volume_db=-27
	var stream:=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=22050
	stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
	stream.loop_end=22050*4
	var data:=PackedByteArray()
	data.resize(22050*4*2)
	var noise:=RandomNumberGenerator.new()
	noise.seed=418
	var filtered:=0.0
	for i in range(22050*4):
		filtered=lerpf(filtered,noise.randf_range(-1,1),0.028)
		var value:float=filtered*0.28+sin(float(i)*TAU*65/22050)*0.025
		data.encode_s16(i*2,int(value*32767))
	stream.data=data
	ambient.stream=stream
	add_child(ambient)

func _process(delta: float) -> void:
	if not player:
		return
	var target:Vector3=player.position+Vector3(24,38,28)
	camera.position=camera.position.lerp(target,1-exp(-delta*6))
	camera.look_at(camera.position-Vector3(24,38,28))
	var desired_zoom:float=28.0 if world.current_interior!="" else camera_zoom+(8 if player.vehicle else 0)
	camera.size=lerpf(camera.size,desired_zoom,delta*4)
	location_tick+=delta
	if location_tick>0.2:
		location_tick=0
		_update_location()
		_update_lighting()
		if world.has_method("update_camera_occlusion"):
			world.update_camera_occlusion(camera.position,player.position)
		if started:
			_capture_world_state()
	if navigation_marker:
		navigation_marker.rotation.y+=delta*0.4
	if started and not Game.paused and Game.status=="playing":
		autosave_timer+=delta
		if autosave_timer>35:
			autosave_timer=0
			Game.save_game()

func _update_lighting() -> void:
	var hour:float=fmod(Game.minute,1440)/60.0
	var daylight:float=clampf(sin((hour-5.5)/15.0*PI),0,1)
	var dusk:float=clampf(1-absf(hour-19)/2.5,0,1)
	sun.light_energy=0.08+daylight*0.67
	sun.light_color=Color("ffbd82").lerp(Color("fff0d1"),daylight)
	sun.rotation_degrees.x=-15-daylight*45
	sun.rotation_degrees.y=-35+(hour-12)*5
	environment.ambient_light_energy=0.30+daylight*0.10
	environment.ambient_light_color=Color("8b9ac3").lerp(Color("c4d8d8"),daylight)
	sky_material.sky_top_color=Color("17233f").lerp(Color("82adc5"),daylight)
	sky_material.sky_horizon_color=Color("39455f").lerp(Color("dddcc3"),daylight).lerp(Color("de987c"),dusk*0.5)
	if world.has_method("set_night"):
		world.set_night(1-daylight)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("ui_cancel") and ui.page!="" and started and Game.status=="playing":
		ui.close_page()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause_game"):
		if started and Game.status=="playing":
			ui.toggle_page("pause")
		return
	if not started or Game.status!="playing":
		return
	# D-pad navigation belongs to the focused menu while a panel is open.
	if Game.paused and (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		if event.is_action_pressed("phone") or event.is_action_pressed("backpack") or event.is_action_pressed("map"):
			ui.close_page()
		return
	if event.is_action_pressed("phone"):
		ui.toggle_page("messages")
	elif event.is_action_pressed("backpack"):
		ui.toggle_page("backpack")
	elif event.is_action_pressed("map"):
		ui.toggle_page("map")
	elif event.is_action_pressed("agenda"):
		ui.toggle_page("agenda")
	elif event.is_action_pressed("contacts"):
		ui.toggle_page("contacts")
	elif not Game.paused:
		if event.is_action_pressed("interact"):
			interact()
		elif event.is_action_pressed("skateboard"):
			player.toggle_skateboard()
		elif event.is_action_pressed("vehicle"):
			population.toggle_vehicle()
		elif event.is_action_pressed("punch"):
			player.attack("punch")
		elif event.is_action_pressed("kick"):
			player.attack("kick")
		elif event.is_action_pressed("shoot"):
			player.attack("shoot")
		elif event is InputEventMouseButton:
			if event.button_index==MOUSE_BUTTON_WHEEL_UP:
				camera_zoom=clampf(camera_zoom-2,24,65)
			elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:
				camera_zoom=clampf(camera_zoom+2,24,65)

func start_game(resume:bool) -> void:
	end_conversation()
	party_guests.reset()
	supplier_encounters.reset()
	if resume:
		if not Game.load_game():
			Game.restart_game()
	else:
		Game.restart_game()
	if population.has_method("reset_population"):
		population.reset_population()
	if world.current_interior!="":
		world.exit_interior()
	started=true
	Game.paused=false
	player.position=Vector3(20,0.3,50)
	if bool(Game.get("vehicle_owned")):
		population.spawn_owned_vehicle()
	if resume:
		_restore_world_state()
	ui.start_play()
	ambient.play()
	if Game.tutorial_step<3:
		Game.notification.emit("Class is out. Your fridge is empty, and tuition is still due. Milo wants a word.")
	_capture_world_state()

func _capture_world_state() -> void:
	var pos:Vector3=player.position
	var data:Dictionary={"position":[pos.x,pos.y,pos.z],"interior":world.current_interior,"driving":player.vehicle!=null,"stolen_vehicle":population.stolen_vehicle,"pursuit":population.pursuit,"skateboarding":player.skateboarding,"car_rotation":player.visual.rotation.y}
	if population.has_method("capture_pursuit_state"):
		data.pursuit_state=population.capture_pursuit_state()
	if population.has_method("capture_meeting_state"):
		data.meeting_walks=population.capture_meeting_state()
	data.informant_runs=population.capture_informant_state()
	data.party_walks=party_guests.capture()
	data.supplier_walks=supplier_encounters.capture()
	for car in population.vehicles:
		if bool(car.get("owned",false)):
			var parked:Vector3=car.node.position
			data.vehicle_owned_pos=[parked.x,parked.y,parked.z]
	Game.world_state=data

func _restore_world_state() -> void:
	var data:Dictionary=Game.world_state
	var inside:String=str(data.get("interior",""))
	if inside!="" and world.interior_nodes.has(inside):
		world.enter_interior(inside)
	var saved:Array=data.get("position",[20.0,0.3,50.0])
	player.position=Vector3(float(saved[0]),float(saved[1]),float(saved[2]))
	player.skateboarding=bool(data.get("skateboarding",false)) and inside==""
	for car in population.vehicles:
		if bool(car.get("owned",false)) and data.has("vehicle_owned_pos"):
			var parked:Array=data.vehicle_owned_pos
			car.node.position=Vector3(float(parked[0]),float(parked[1]),float(parked[2]))
	if bool(data.get("driving",false)) and inside=="":
		var stolen:bool=bool(data.get("stolen_vehicle",false))
		for car in population.vehicles:
			if (stolen and not bool(car.get("owned",false))) or (not stolen and bool(car.get("owned",false))):
				car.node.position=player.position
				car.node.rotation.y=float(data.get("car_rotation",0))
				car.occupied=true
				car.parked=true
				car.stolen=stolen
				car.node.collision_layer=0
				player.vehicle=car.node
				player.visual.rotation.y=car.node.rotation.y
				population.stolen_vehicle=stolen
				break
	population.pursuit=bool(data.get("pursuit",false)) and inside==""
	if population.pursuit:
		population.crime_position=player.position
		population.crime_age=0
		for officer in population.police:
			officer.alert=12.0
	if population.has_method("restore_pursuit_state"):
		population.restore_pursuit_state(data.get("pursuit_state",{}))
	camera.position=player.position+Vector3(24,38,28)
	camera.look_at(player.position)
	if population.has_method("restore_meeting_state"):
		population.restore_meeting_state(data.get("meeting_walks",[]))
	population.restore_informant_state(data.get("informant_runs",[]))
	for npc_id: String in Game.pending_civilian_reports():
		population.start_informant_run(npc_id)
	party_guests.restore(data.get("party_walks",[]))
	supplier_encounters.restore(data.get("supplier_walks",[]))
	_update_location()

func _update_location() -> void:
	closest_location=""
	var best:=7.0
	for id in world.landmarks:
		var d:float=player.position.distance_to(world.landmarks[id].position)
		if d<best:
			best=d
			closest_location=id
	if world.current_interior!="":
		closest_location=world.current_interior
	Game.player_location_id=closest_location

func interaction_text() -> String:
	var hint := _interaction_text()
	if controller_active:
		hint = hint.replace("E  ","A  ").replace("B  ","RB  ").replace("TAB  ","LB  ").replace("V  ","Y  ").replace("SPACE","X")
	return hint

func _interaction_text() -> String:
	if world.current_interior!="":
		var guest: Dictionary=party_guests.nearest_guest()
		if not guest.is_empty() and player.position.distance_to(world.get_interior_exit())>1.5:
			return "E  Catch up with %s"%guest.name
		if player.position.distance_to(world.get_interior_exit())<3.3:
			return "E  Leave building"
		return "E  Apartment options  •  B  Backpack" if world.current_interior in ["home","deerfield_social"] else "E  "+("Campus services" if world.current_interior in ["classroom","library"] else "Shop here")
	if Game.tutorial_step<3 and player.position.distance_to(population.friend.position)<4.8:
		if Game.tutorial_step==0:
			return "MILO  ‘Got a dime bag?’     B  Open backpack"
		if Game.tutorial_step==1:
			return "E  Sell a dime bag to Milo"
		return "TAB  Save Milo in your contacts"
	var connection: Dictionary=supplier_encounters.nearest()
	if not connection.is_empty(): return "E  Talk to %s" % connection.name
	for meeting in Game.active_meetings():
		if meeting.status=="scheduled" and closest_location==meeting.location_id:
			if Game.minute>=float(meeting.due_minute)-Game.meeting_arrival_minutes(meeting) and population.meeting_walks.get(str(int(meeting.id)),{}).get("state","approaching")=="approaching":
				return "%s is on the way  •  %s" % [meeting.contact_name,Game.format_minute(meeting.due_minute)]
			return "E  Meet %s  •  %s" % [meeting.contact_name,Game.format_minute(meeting.due_minute)]
	var citizen := _conversation_target()
	if not citizen.is_empty(): return "E  Talk to %s" % citizen.name
	if closest_location!="":
		var names:Dictionary={"classroom":"Attend class","market":"Shop at the market","cafe":"Order food","home":"Go home","auto_dealer":"Visit the vehicle dealer","library":"Enter the library","supplier":"Browse the underground market","skate_park":"Skate park • SPACE to ride","campus_quad":"Campus noticeboard","car_park":"Parking lot"}
		return "E  "+str(names.get(closest_location,world.landmarks[closest_location].name))
	if player.vehicle:
		return "V  Park and exit  •  Stolen cars attract patrols" if population.stolen_vehicle else "V  Park and exit"
	if not population.nearby_vehicle().is_empty():
		return "V  Enter vehicle  •  Theft attracts police"
	return ""

func interact() -> void:
	_update_location()
	if world.current_interior!="":
		var guest: Dictionary=party_guests.nearest_guest()
		if not guest.is_empty() and player.position.distance_to(world.get_interior_exit())>1.5:
			conversation_id="party:"+str(guest.contact_id)
			party_guests.conversation_contact=str(guest.contact_id)
			_show_conversation()
		elif player.position.distance_to(world.get_interior_exit())<3.3:
			_teleport(world.exit_interior()+Vector3(0,0.3,0))
		elif world.current_interior in ["home","deerfield_social"]:
			ui.show_page("home")
		elif world.current_interior in ["library","classroom"]:
			ui.show_page("campus")
		else:
			ui.show_page("shop")
		return
	if Game.tutorial_step==1 and player.position.distance_to(population.friend.position)<4.8:
		Game.tutorial_sell()
		return
	var connection: Dictionary=supplier_encounters.nearest()
	if not connection.is_empty():
		conversation_id="supplier:"+str(connection.id)
		supplier_encounters.conversation_id=str(connection.id)
		_show_conversation()
		return
	for meeting in Game.active_meetings():
		if meeting.status=="scheduled" and closest_location==meeting.location_id:
			if Game.minute<float(meeting.due_minute)-Game.meeting_arrival_minutes(meeting):
				Game.notification.emit("You're early. Wait here from your agenda.")
				ui.show_page("agenda")
				return
			if population.has_method("meeting_actor_in_reach") and not population.meeting_actor_in_reach(int(meeting.id),4.0):
				if population.meeting_walks.get(str(int(meeting.id)),{}).get("state","approaching")=="approaching":
					Game.notification.emit("%s is on the way. Watch for them walking in."%meeting.contact_name)
				else:
					Game.notification.emit("Move closer to %s for the handoff."%meeting.contact_name)
				return
			ui.show_postpone_meeting(int(meeting.id))
			return
	var citizen := _conversation_target()
	if not citizen.is_empty() and population.begin_conversation(str(citizen.id)):
		conversation_id = str(citizen.id)
		_show_conversation()
		return
	match closest_location:
		"classroom":
			if not Game.attend_class():
				ui.show_page("campus")
		"market","cafe","supplier","auto_dealer":
			ui.show_page("shop")
		"home":
			ui.show_page("home")
		"deerfield_social":
			enter_building("deerfield_social")
		"library":
			enter_building("library")
		"campus_quad":
			ui.show_page("agenda")
		"skate_park":
			player.toggle_skateboard()
		_:
			if Game.tutorial_step==0:
				ui.show_page("backpack")

func _conversation_target() -> Dictionary:
	if Game.tutorial_step<3 or player.vehicle or world.current_interior!="": return {}
	# A doorstep remains easy to use even when someone walks past it.
	if closest_location!="" and player.position.distance_to(world.get_landmark(closest_location))<2.2: return {}
	return population.nearest_conversational_npc(3.2)

func _show_conversation(response: String="") -> void:
	if conversation_id=="": return
	if conversation_id.begins_with("supplier:"):
		var encounter_id:=conversation_id.trim_prefix("supplier:")
		if not supplier_encounters.in_reach(encounter_id):
			ui.close_page()
			end_conversation()
			return
		ui.show_supplier_conversation(Game.supplier_encounter_view(encounter_id))
		return
	if conversation_id.begins_with("party:"):
		var contact_id:=conversation_id.trim_prefix("party:")
		if not party_guests.in_reach(contact_id):
			ui.close_page()
			end_conversation()
			return
		var party_context: Dictionary=Game.party_guest_view(contact_id)
		party_context.actor_id=conversation_id
		party_context.party_guest=true
		party_context.district="Deerfield party"
		if response!="": party_context.response=response
		ui.show_conversation(party_context)
		return
	var citizen := population.nearest_conversational_npc(4.0)
	if str(citizen.get("id",""))!=conversation_id:
		end_conversation()
		ui.close_page()
		return
	var context: Dictionary = Game.street_conversation(conversation_id,str(citizen.name))
	context.actor_id = conversation_id
	context.district = world.get_district(player.position)
	if response!="": context.response = response
	ui.show_conversation(context)

func conversation_action(npc_id: String, action: String) -> void:
	if npc_id!=conversation_id or conversation_id=="": return
	if npc_id.begins_with("party:"):
		var contact_id:=npc_id.trim_prefix("party:")
		if action=="leave" or not party_guests.in_reach(contact_id):
			ui.close_page()
			end_conversation()
			return
		if action=="smalltalk": Game.chat_party_guest(contact_id)
		elif action=="offer": Game.sell_party_guest(contact_id)
		_show_conversation()
		return
	match action:
		"leave":
			ui.close_page()
			end_conversation()
		"offer":
			Game.offer_street_sale(npc_id)
			if conversation_id!="": _show_conversation()
		"add_contact":
			Game.add_street_contact(npc_id)
			_show_conversation()
		"smalltalk":
			var citizen := population.nearest_conversational_npc(4.0)
			_show_conversation(Game.street_smalltalk(npc_id,str(citizen.get("goal",""))))

func supplier_conversation_action(action: String) -> void:
	if not conversation_id.begins_with("supplier:"): return
	var encounter_id:=conversation_id.trim_prefix("supplier:")
	if action=="leave" or not supplier_encounters.in_reach(encounter_id):
		ui.close_page()
		end_conversation()
		return
	_update_location()
	var accepted: bool=Game.supplier_encounter_action(encounter_id,action)
	load("res://scripts/npc_emote.gd").play(supplier_encounters.actors[encounter_id].node,"happy" if accepted else "question")
	_show_conversation()

func end_conversation() -> void:
	conversation_id = ""
	if is_instance_valid(population): population.end_conversation()
	if is_instance_valid(party_guests): party_guests.conversation_contact=""
	if is_instance_valid(supplier_encounters): supplier_encounters.conversation_id=""

func _on_party_reaction(contact_id: String, kind: String) -> void:
	if is_instance_valid(party_guests) and party_guests.guests.has(contact_id):
		load("res://scripts/npc_emote.gd").play(party_guests.guests[contact_id].node,kind)

func _on_civilian_reaction(npc_id: String, reaction: String) -> void:
	if reaction!="report": return
	end_conversation()
	ui.close_page()
	population.start_informant_run(npc_id)
	_capture_world_state()

func _on_informant_reported(npc_id: String) -> void:
	Game.civilian_report_arrived(npc_id)

func _in_person_meeting(meeting_id: int) -> bool:
	_update_location()
	if player.vehicle or world.current_interior!="": return false
	for meeting in Game.active_meetings():
		if int(meeting.id)==meeting_id and closest_location==meeting.location_id:
			return population.meeting_actor_in_reach(meeting_id,4.0)
	return false

func complete_in_person(meeting_id: int) -> bool:
	if not _in_person_meeting(meeting_id):
		Game.notification.emit("Move beside your contact at the meeting point first.")
		return false
	return Game.complete_meeting(meeting_id)

func postpone_in_person(meeting_id: int, delay_minutes: int=120) -> bool:
	if not _in_person_meeting(meeting_id):
		Game.notification.emit("Speak to your contact face to face to postpone.")
		return false
	return Game.postpone_meeting(meeting_id,delay_minutes)

func enter_building(id:String) -> void:
	if id=="deerfield_social":
		var party: Dictionary=Game.party_summary()
		if not bool(party.get("active",false)) or str(party.get("location_id","home"))!="deerfield_social":
			Game.notification.emit("The neighbours' apartment is private. Accept a party invitation and come back when it starts.")
			return
	if player.vehicle:
		Game.notification.emit("Park your vehicle before entering.")
		return
	if population.pursuit:
		Game.notification.emit("Lose the patrol before entering a building.")
		return
	player.skateboarding=false
	_teleport(world.enter_interior(id)+Vector3(0,0.3,0))
	ui.close_page()

func _teleport(at:Vector3) -> void:
	player.position=at
	player.velocity=Vector3.ZERO
	camera.position=at+Vector3(24,38,28)
	camera.look_at(at)
	ui.transition()

func navigate(id:String) -> void:
	if not world.landmarks.has(id):
		return
	destination=id
	if navigation_marker:
		navigation_marker.queue_free()
	navigation_marker=ActorVisuals.ground_ring(Color("d5f276"),2.2)
	add_child(navigation_marker)
	navigation_marker.position=world.landmarks[id].position+Vector3(0,0.16,0)
	Game.notification.emit("Destination: "+str(world.landmarks[id].name))

func _on_notification(_text:String) -> void:
	if ambient and started:
		pass

func _on_ended(won:bool,reason:String) -> void:
	Game.paused=true
	ui.show_ending(won,reason)

func district_name() -> String:
	if world.current_interior!="":
		return str(world.landmarks[world.current_interior].name).to_upper()
	return str(world.get_district(player.position)).to_upper()
