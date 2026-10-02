extends SceneTree
## Repeatable developer-only native CPU profile. Run with --headless for CPU-only
## timing, or a normal renderer for draw counters. Uses an isolated campaign.

const PROFILE_DIR := "res://.godot/runtime-profile"
const FRAMES_PER_SCENE := 180
var scene: Node
var state: Node
var report: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _instrument(base: String, entries: Array, file: String) -> String:
	var code := "extends \"%s\"\nvar profile_samples: Dictionary = {}\n"%base
	code += "func _profile_add(key: String, usec: int) -> void:\n\tvar entry: Dictionary = profile_samples.get(key, {\"calls\":0,\"total_us\":0,\"peak_us\":0})\n\tentry.calls += 1\n\tentry.total_us += usec\n\tentry.peak_us = maxi(entry.peak_us,usec)\n\tprofile_samples[key] = entry\n"
	for entry: Array in entries:
		var returns: bool = entry.size()>3
		var invoke := "super."+str(entry[0])
		if entry[0]=="_move_person":
			# Profile the unchanged movement body in the ignored derived script so
			# native collision cost can be separated from animation request cost.
			var source := FileAccess.get_file_as_string(base)
			var begin := source.find("func _move_person(")
			var finish := source.find("\nfunc ",begin+1)
			var body := source.substr(begin,finish-begin).replace("func _move_person(","func _profile_move_person(")
			body = body.replace("\tactor.move_and_slide()","\tvar slide_start := Time.get_ticks_usec()\n\tactor.move_and_slide()\n\t_profile_add(\"_native_move_and_slide\",Time.get_ticks_usec()-slide_start)")
			body = body.replace("\tActorVisuals.play(actor,\"sprint\" if speed>2.5 else \"walk\")","\tvar animation_start := Time.get_ticks_usec()\n\tActorVisuals.play(actor,\"sprint\" if speed>2.5 else \"walk\")\n\t_profile_add(\"_animation_request\",Time.get_ticks_usec()-animation_start)")
			code += body+"\n"
			invoke = "_profile_move_person"
		code += "func %s(%s) -> %s:\n\tvar started := Time.get_ticks_usec()\n\t%s%s(%s)\n\t_profile_add(\"%s\",Time.get_ticks_usec()-started)\n"%[entry[0],entry[1],entry[3] if returns else "void","var value = " if returns else "",invoke,entry[2],entry[0]]
		if returns: code += "\treturn value\n"
	var path := PROFILE_DIR.path_join(file+".gd")
	FileAccess.open(path,FileAccess.WRITE).store_string(code)
	return path

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(PROFILE_DIR)
	DirAccess.make_dir_recursive_absolute("res://build/logs")
	var population_path := _instrument("res://scripts/population.gd",[
		["_physics_process","delta: float","delta"],
		["_update_citizen","citizen: Dictionary, delta: float, indoor: bool","citizen,delta,indoor"],
		["_update_traffic","delta: float, indoor: bool","delta,indoor"],
		["_update_police","delta: float, indoor: bool","delta,indoor"],
		["_ground_person","actor: Node3D","actor"],
		["_move_person","record: Dictionary, target: Vector3, speed: float, delta: float","record,target,speed,delta"],
		["_line_of_sight","from: Vector3, to: Vector3","from,to","bool"],
		["_refresh_neighbor_lists","",""],
		["_sync_pressure_patrols","",""],
		["_update_animation_lod","",""],
		["_update_meeting_walks","delta: float, indoor: bool","delta,indoor"]
	],"population")
	var world_path := _instrument("res://scripts/world.gd",[
		["update_camera_occlusion","camera_position: Vector3, player_position: Vector3","camera_position,player_position"],
		["walkable_surface_height","at: Vector3","at","float"],
		["walkable_support_height","at: Vector3, radius: float","at,radius","float"]
	],"world")
	var player_path := _instrument("res://scripts/player.gd",[["_physics_process","delta: float","delta"],["_update_grounding","",""]],"player")
	var interface_path := _instrument("res://scripts/interface.gd",[["_process","delta: float","delta"],["_update_hud","",""]],"interface")
	var party_path := _instrument("res://scripts/party_guests.gd",[["_physics_process","delta: float","delta"]],"party")
	var state_path := _instrument("res://scripts/game_state.gd",[["_process","delta: float","delta"],["advance_time","minutes: float","minutes"]],"state")
	var code := FileAccess.get_file_as_string("res://scripts/main.gd")
	code = code.replace("load(\"res://scripts/world.gd\")","load(\"%s\")"%world_path)
	code = code.replace("StudentPlayer.new()","load(\"%s\").new()"%player_path)
	code = code.replace("CityPopulation.new()","load(\"%s\").new()"%population_path)
	code = code.replace("load(\"res://scripts/interface.gd\")","load(\"%s\")"%interface_path)
	code = code.replace("load(\"res://scripts/party_guests.gd\")","load(\"%s\")"%party_path)
	var main_base_path := PROFILE_DIR.path_join("main_base.gd")
	FileAccess.open(main_base_path,FileAccess.WRITE).store_string(code)
	var main_path := _instrument(main_base_path,[["_process","delta: float","delta"],["_update_lighting","",""],["_update_location","",""],["_capture_world_state","",""]],"main")
	state = root.get_node("Game")
	state.set_script(load(state_path))
	state.save_path = PROFILE_DIR.path_join("campaign.json")
	state.set_process(false)
	scene = load(main_path).new()
	root.add_child(scene)
	await process_frame
	scene.start_game(false)
	state.tutorial_step = 3
	state._rng.seed = 2702
	await _measure("campus",Vector3(20,0.3,50))
	await _measure("west_parking",scene.world.get_landmark("car_park"))
	await _measure("apartment_exterior",scene.world.get_landmark("home"))
	state.cash = 200
	state.reputation = 8
	state.minute = 1080
	state.player_location_id = "home"
	for index in 8: state._add_contact("profile_guest_%d"%index,"Guest %d"%index,45)
	state.host_party()
	for index in 8: state.invite_party_contact("profile_guest_%d"%index)
	state.minute += 70
	for guest: Dictionary in state.party_summary().guests: state.mark_party_guest_arrived(guest.contact_id)
	scene.party_guests._sync()
	scene.enter_building("home")
	await _measure("party_eight_guests",scene.player.position)
	scene._teleport(scene.world.exit_interior())
	state.set_process(true)
	await _measure("campus_running_clock",Vector3(20,0.3,50))
	var output := "res://build/logs/runtime-profile.json"
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"note":"Inclusive instrumented CPU timings; nested timings overlap. Headless renderer counters are zero.","scenarios":report},"\t"))
	print("RUNTIME PROFILE: "+JSON.stringify(report))
	scene._release_audio(scene)
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(state.save_path)
	quit()

func _measure(label: String, location: Vector3) -> void:
	scene.player.position = location
	scene.camera.position = location+Vector3(24,38,28)
	scene.camera.look_at(location)
	state.health = 100
	state.paused = false
	for tick in 30: await physics_frame
	var nodes := {"main":scene,"population":scene.population,"world":scene.world,"player":scene.player,"interface":scene.ui,"party":scene.party_guests,"campaign":state}
	for node: Node in nodes.values(): node.profile_samples.clear()
	var monitor := {"process_ms":0.0,"physics_ms":0.0,"draw_calls":0.0,"primitives":0.0,"objects":0.0,"fps":0.0}
	for tick in FRAMES_PER_SCENE:
		await physics_frame
		monitor.process_ms += Performance.get_monitor(Performance.TIME_PROCESS)*1000
		monitor.physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000
		monitor.draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		monitor.primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		monitor.objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		monitor.fps += Performance.get_monitor(Performance.TIME_FPS)
	for key: String in monitor: monitor[key] /= FRAMES_PER_SCENE
	var sample := {"scenario":label,"monitor":monitor,"citizens":scene.population.citizens.size(),"police":scene.population.police.size(),"vehicles":scene.population.vehicles.size(),"guests":scene.party_guests.guests.size(),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"memory_mb":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0,"subsystems":{}}
	for key: String in nodes:
		var data: Dictionary = nodes[key].profile_samples.duplicate(true)
		for method: String in data:
			data[method].mean_us = float(data[method].total_us)/maxi(1,int(data[method].calls))
			data[method].us_per_physics_tick = float(data[method].total_us)/FRAMES_PER_SCENE
		sample.subsystems[key] = data
	report.append(sample)
	print("PROFILE SCENE: ",label," ",monitor)
